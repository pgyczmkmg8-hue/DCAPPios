import SwiftUI
import Combine

/// 유저 메모: 아이디·IP·닉네임에 짧은 메모를 달면, 글 목록·댓글·글 보기에서 닉네임 옆에 보여 줌
struct UserMemo: Codable, Hashable, Identifiable {
    var kind: BlockedUser.Kind      // 아이디 / IP / 닉네임 (차단과 같은 구분)
    var value: String
    var text: String
    var gallery: String? = nil      // 이 갤러리에서만 보임 (nil = 모든 갤러리)
    var id: String { "\(kind.rawValue):\(value)@\(gallery ?? "*")" }
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
            memos = saved
        }
    }

    /// 지금 갤러리에서 보이는 메모 (갤러리 전용 메모가 있으면 그것, 없으면 모든 갤러리 메모)
    func memo(kind: BlockedUser.Kind, value: String, gallery: String?) -> UserMemo? {
        memos.first { $0.kind == kind && $0.value == value && gallery != nil && $0.gallery == gallery }
            ?? memos.first { $0.kind == kind && $0.value == value && $0.gallery == nil }
    }

    /// 빈 글이면 삭제. gallery: 그 갤러리에서만 (nil = 모든 갤러리). replacing: 고치는 중인 원래 메모(범위를 바꾸면 지움)
    func set(kind: BlockedUser.Kind, value: String, text: String, gallery: String? = nil, replacing old: UserMemo? = nil) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        var list = memos.filter { !($0.kind == kind && $0.value == v && $0.gallery == gallery) && $0.id != old?.id }
        if !t.isEmpty { list.insert(UserMemo(kind: kind, value: v, text: t, gallery: gallery), at: 0) }
        memos = list
    }

    func remove(_ m: UserMemo) { memos.removeAll { $0.id == m.id } }

    /// 백업 복원용
    func replaceAll(_ list: [UserMemo]) { memos = list }
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
            Button("저장") { if let m = editing { store.set(kind: m.kind, value: m.value, text: editText, gallery: m.gallery, replacing: m) } }
            Button("취소", role: .cancel) {}
        } message: {
            Text(editing.map { "\($0.kind.label) \($0.value)" } ?? "")
        }
    }
}
