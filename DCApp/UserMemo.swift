import SwiftUI
import Combine

/// 유저 메모: 아이디·IP·닉네임에 짧은 메모를 달면, 글 목록·댓글·글 보기에서 닉네임 옆에 보여 줌
/// 같은 대상에 메모를 여러 개 달 수 있음
struct UserMemo: Codable, Hashable, Identifiable {
    var kind: BlockedUser.Kind      // 아이디 / IP / 닉네임 (차단과 같은 구분)
    var value: String
    var text: String
    var gallery: String? = nil      // 이 갤러리에서만 보임 (nil = 모든 갤러리)
    var uid: String? = UUID().uuidString   // 메모마다 따로 (예전 메모는 없음 → 불러올 때 붙임)
    var id: String { uid ?? "\(kind.rawValue):\(value)@\(gallery ?? "*")" }
}

/// 자동메모 설정 (설정 → 차단 → 자동메모). 기본은 꺼짐
enum AutoMemo {
    static let enabledKey = "autoMemo"
    static let allKey = "autoMemoAllGalleries"      // true = 모든 갤러리에 메모, false = 본 갤러리에만
    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var allGalleries: Bool { UserDefaults.standard.object(forKey: allKey) as? Bool ?? true }
    /// 페이지 스크립트에 넘길 값: "" = 꺼짐 / "all" / "gallery"
    static var scriptValue: String { !enabled ? "" : (allGalleries ? "all" : "gallery") }
}

@MainActor
final class MemoStore: ObservableObject {
    static let shared = MemoStore()
    private let key = "userMemos"

    @Published private(set) var memos: [UserMemo] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(memos) { UserDefaults.standard.set(data, forKey: key) }
            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)   // 열린 페이지에 바로 반영
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([UserMemo].self, from: data) {
            memos = Self.withUIDs(saved)
        }
    }

    /// 예전(대상마다 하나) 메모에 고유 번호 붙이기
    private static func withUIDs(_ list: [UserMemo]) -> [UserMemo] {
        list.map { m in
            var m = m
            if m.uid == nil { m.uid = UUID().uuidString }
            return m
        }
    }

    /// 지금 갤러리에서 보이는 메모 전부 (이 갤러리 전용 먼저, 그다음 모든 갤러리 메모, 각각 먼저 단 순서)
    func memos(kind: BlockedUser.Kind, value: String, gallery: String?) -> [UserMemo] {
        let mine = memos.filter { $0.kind == kind && $0.value == value }
        return mine.filter { gallery != nil && $0.gallery == gallery } + mine.filter { $0.gallery == nil }
    }

    /// 새 메모 추가 (같은 대상에 이미 있어도 따로 하나 더)
    func add(kind: BlockedUser.Kind, value: String, text: String, gallery: String? = nil) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, !t.isEmpty else { return }
        memos.append(UserMemo(kind: kind, value: v, text: t, gallery: gallery))
    }

    /// 메모 고치기 (빈 글이면 삭제). gallery로 범위도 바꿈
    func update(_ old: UserMemo, text: String, gallery: String?) {
        guard let i = memos.firstIndex(where: { $0.id == old.id }) else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { memos.remove(at: i); return }
        memos[i].text = t
        memos[i].gallery = gallery
    }

    func remove(_ m: UserMemo) { memos.removeAll { $0.id == m.id } }

    /// 자동메모: 글 목록에서 메모가 없는 로그인 계정을 아이디로 메모 (유동은 건드리지 않음).
    /// items = [{ id, g }] — g는 글 목록의 갤러리 아이디. '갤러리마다' 설정이면 그 갤러리 전용, 아니면 모든 갤러리
    func addAuto(_ items: [[String: Any]]) {
        guard AutoMemo.enabled else { return }
        var added: [UserMemo] = []
        for item in items {
            guard let id = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { continue }
            let g = (item["g"] as? String) ?? ""
            let scope: String? = AutoMemo.allGalleries ? nil : (g.isEmpty ? nil : g)
            if !AutoMemo.allGalleries && g.isEmpty { continue }
            let exists = (memos + added).contains { $0.kind == .id && $0.value == id && ($0.gallery == nil || $0.gallery == scope) }
            if exists { continue }
            added.append(UserMemo(kind: .id, value: id, text: id, gallery: scope))
        }
        if !added.isEmpty { memos.append(contentsOf: added) }
    }

    /// 백업 복원용
    func replaceAll(_ list: [UserMemo]) { memos = Self.withUIDs(list) }
}

/// 설정 → 유저 메모 목록 (눌러서 고치기, 밀어서 지우기)
struct MemoListView: View {
    @ObservedObject private var store = MemoStore.shared
    @State private var editing: UserMemo?
    @State private var editText = ""

    var body: some View {
        List {
            ForEach(store.memos) { m in
                Button {
                    editText = m.text
                    editing = m
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.text).foregroundStyle(.primary)
                        Text("\(m.kind.label) · \(m.value) · \(m.gallery.map { "\($0) 갤러리만" } ?? "모든 갤러리")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let list = store.memos
                for i in offsets { store.remove(list[i]) }
            }
        }
        .overlay {
            if store.memos.isEmpty {
                ContentUnavailableView("메모한 유저가 없어요", systemImage: "note.text",
                                       description: Text("글 목록이나 댓글을 길게 누르고 '메모'를 고르세요."))
            }
        }
        .navigationTitle("유저 메모")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .alert("메모 고치기", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("메모", text: $editText)
            Button("저장") { if let m = editing { store.update(m, text: editText, gallery: m.gallery) } }
            Button("취소", role: .cancel) {}
        } message: {
            Text(editing.map { "\($0.kind.label) \($0.value)" } ?? "")
        }
    }
}
