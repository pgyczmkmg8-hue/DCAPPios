import SwiftUI
import Combine

// MARK: - 읽은 글 / 작성한 글 / 댓글 단 글 기록
// 글은 "갤ID/글번호"로 구분 (미니는 mi$갤ID, 인물은 pr$갤ID — 디시 알림과 같은 표기)

enum PostKey {
    /// 글 주소 → "ipad1/1090313", 미니 "mi$incord/123", 인물 "pr$abc/45"
    nonisolated static func from(_ url: URL) -> String? {
        guard let host = url.host?.lowercased(), host == "m.dcinside.com" else { return nil }
        let p = url.pathComponents.filter { $0 != "/" }
        guard p.count >= 3, p[2].allSatisfy(\.isNumber), !p[2].isEmpty else { return nil }
        switch p[0] {
        case "board": return "\(DCGalleryID.bare(p[1]))/\(p[2])"
        case "mini": return "mi$\(DCGalleryID.bare(p[1]))/\(p[2])"
        case "person": return "pr$\(DCGalleryID.bare(p[1]))/\(p[2])"
        default: return nil
        }
    }

    nonisolated static func url(_ key: String) -> URL? {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let no = Int(parts[1]) else { return nil }
        return DCGalleryID.postURL(parts[0], no: no, comments: false)
    }

    /// 앞머리 붙은 갤러리 ID ("mi$incord")
    nonisolated static func gallery(_ key: String) -> String { String(key.split(separator: "/").first ?? "") }
}

/// 파일 하나에 JSON으로 저장 (UserDefaults보다 큰 목록에 알맞음)
private enum HistoryFile {
    static func url(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("History", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
    static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        guard let d = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let d = try? JSONEncoder().encode(value) else { return }
        try? d.write(to: url(name), options: .atomic)
    }
}

// MARK: 읽은 글

struct ReadPost: Codable, Identifiable, Hashable {
    let key: String          // "ipad1/1090313"
    var title: String
    var date: Date
    var id: String { key }
}

@MainActor
final class ReadPostStore: ObservableObject {
    static let shared = ReadPostStore()
    static let limit = 50_000
    private let file = "read.json"

    /// 최근에 읽은 순서 (맨 앞이 최신)
    @Published private(set) var items: [ReadPost] = []
    private var keys = Set<String>()
    private var saveTask: Task<Void, Never>?

    private init() {
        items = HistoryFile.load(file, as: [ReadPost].self) ?? []
        keys = Set(items.map(\.key))
    }

    func isRead(_ key: String) -> Bool { keys.contains(key) }

    /// 이 갤러리에서 읽은 글 번호들 (목록 보라색 표시용)
    func readKeys(gallery: String) -> [String] {
        let prefix = gallery + "/"
        return items.filter { $0.key.hasPrefix(prefix) }.map(\.key)
    }

    func markRead(_ key: String, title: String) {
        if let i = items.firstIndex(where: { $0.key == key }) {
            var p = items.remove(at: i)
            if !title.isEmpty { p.title = title }
            p.date = Date()
            items.insert(p, at: 0)
        } else {
            items.insert(ReadPost(key: key, title: title, date: Date()), at: 0)
            keys.insert(key)
            if items.count > Self.limit {
                for old in items[Self.limit...] { keys.remove(old.key) }
                items.removeLast(items.count - Self.limit)
            }
        }
        scheduleSave()
    }

    /// 제목을 나중에 알게 됐을 때 (글이 다 열린 뒤)
    func setTitle(_ title: String, for key: String) {
        guard !title.isEmpty, let i = items.firstIndex(where: { $0.key == key }), items[i].title != title else { return }
        items[i].title = title
        scheduleSave()
    }

    func remove(_ keysToRemove: Set<String>) {
        items.removeAll { keysToRemove.contains($0.key) }
        keys.subtract(keysToRemove)
        scheduleSave()
    }

    func clearAll() { items = []; keys = []; scheduleSave() }

    func clear(gallery: String) {
        let prefix = gallery + "/"
        let gone = Set(items.filter { $0.key.hasPrefix(prefix) }.map(\.key))
        remove(gone)
    }

    /// 갤러리별 개수 (지우기 화면용)
    struct GalleryCount: Hashable { let gallery: String; let count: Int }
    var galleryCounts: [GalleryCount] {
        var c: [String: Int] = [:]
        for p in items { c[PostKey.gallery(p.key), default: 0] += 1 }
        return c.map { GalleryCount(gallery: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))     // 글 여러 개를 빠르게 열어도 한 번만 저장
            guard !Task.isCancelled else { return }
            HistoryFile.save(items, file)
        }
    }
}

// MARK: 작성한 글 / 댓글 단 글

/// 쓸 때의 신분: 로그인 계정 또는 유동(닉네임·IP)
struct WriterIdentity: Codable, Hashable {
    var account: String?     // 로그인 아이디
    var nick: String?        // 유동 닉네임
    var ip: String?          // 유동 IP 앞 두 자리 ("118.235")

    var label: String {
        if let a = account, !a.isEmpty { return a }
        let n = (nick?.isEmpty == false ? nick! : "유동")
        if let ip, !ip.isEmpty { return "\(n)(\(ip))" }
        return n
    }
}

struct WrittenItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case post, comment }
    var id = UUID()
    let kind: Kind
    let key: String          // 글 "ipad1/1090313"
    var title: String        // 글 제목
    var snippet: String      // 댓글 앞부분 (글이면 빈 칸)
    var date: Date
    var who: WriterIdentity
}

@MainActor
final class WrittenStore: ObservableObject {
    static let shared = WrittenStore()
    private let file = "written.json"
    @Published private(set) var items: [WrittenItem] = []

    private init() { items = HistoryFile.load(file, as: [WrittenItem].self) ?? [] }

    func posts() -> [WrittenItem] { items.filter { $0.kind == .post } }
    func comments() -> [WrittenItem] { items.filter { $0.kind == .comment } }

    func add(_ item: WrittenItem) {
        // 같은 글을 두 번 기록하지 않음 (글은 글 하나당 한 번)
        if item.kind == .post, items.contains(where: { $0.kind == .post && $0.key == item.key }) { return }
        items.insert(item, at: 0)
        if items.count > 10_000 { items.removeLast(items.count - 10_000) }
        HistoryFile.save(items, file)
    }

    /// 나중에 알게 된 IP·제목 채우기
    func update(_ id: UUID, _ change: (inout WrittenItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        HistoryFile.save(items, file)
    }

    func remove(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        HistoryFile.save(items, file)
    }

    func clear(kind: WrittenItem.Kind) {
        items.removeAll { $0.kind == kind }
        HistoryFile.save(items, file)
    }

    /// 분류용: 지금까지 쓴 신분들
    func identities(kind: WrittenItem.Kind) -> [WriterIdentity] {
        var seen: [WriterIdentity] = []
        for it in items where it.kind == kind && !seen.contains(it.who) { seen.append(it.who) }
        return seen
    }
}

// MARK: - 갤러리 창의 목록 화면들

/// 갤러리 ID로 이름 찾기 (방문 기록·즐겨찾기에서)
@MainActor
enum GalleryNames {
    static func name(_ prefixedID: String) -> String {
        let bare = DCGalleryID.bare(prefixedID)
        if let v = VisitedStore.shared.items.first(where: { $0.gallery.galleryID == bare }) { return v.gallery.name }
        return bare
    }
}

/// 갤러리 창 → 알림 (종 버튼)
struct AlarmsScreen: View {
    @ObservedObject private var store = AlarmStore.shared

    var body: some View {
        AlarmsList()
            .navigationTitle("알림")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !store.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("모두 읽음으로") { store.markAllRead() }
                            Button("전체 삭제", role: .destructive) { store.removeAll() }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
    }
}

/// 갤러리 창 → 읽은 글
struct ReadPostsList: View {
    @ObservedObject private var store = ReadPostStore.shared
    @EnvironmentObject private var router: AppRouter
    @State private var confirmAll = false
    @State private var galleryToClear: String?

    var body: some View {
        List {
            Section {
                ForEach(store.items) { p in
                    Button {
                        if let u = PostKey.url(p.key) { router.open(u) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title.isEmpty ? p.key : p.title).foregroundStyle(.primary).lineLimit(2)
                            Text("\(GalleryNames.name(PostKey.gallery(p.key))) · \(p.date.shortKorean)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.remove([p.key]) } label: { Label("삭제", systemImage: "trash") }
                    }
                }
            } header: {
                HStack {
                    Text("\(store.items.count)개")
                    Spacer()
                    if !store.items.isEmpty {
                        Menu {
                            Button("전체 지우기", role: .destructive) { confirmAll = true }
                            Section("갤러리별 지우기") {
                                ForEach(Array(store.galleryCounts.prefix(30)), id: \.self) { g in
                                    Button("\(GalleryNames.name(g.gallery)) (\(g.count))") { galleryToClear = g.gallery }
                                }
                            }
                        } label: { Label("기록 지우기", systemImage: "trash") }
                        .textCase(nil)
                    }
                }
                .padding(.top, 12).padding(.bottom, 6)
            }
        }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView("읽은 글이 없어요", systemImage: "book",
                                       description: Text("글을 열면 여기에 기록되고, 글 목록에서 보라색으로 표시돼요."))
            }
        }
        .confirmationDialog("읽은 글 기록을 모두 지울까요?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("모두 지우기", role: .destructive) { store.clearAll() }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog(galleryToClear.map { "\(GalleryNames.name($0)) 갤러리의 읽은 글 기록을 지울까요?" } ?? "",
                            isPresented: Binding(get: { galleryToClear != nil }, set: { if !$0 { galleryToClear = nil } }),
                            titleVisibility: .visible) {
            Button("지우기", role: .destructive) { if let g = galleryToClear { store.clear(gallery: g) } }
            Button("취소", role: .cancel) {}
        }
    }
}

/// 갤러리 창 → 작성한 글 / 댓글 작성한 글 (쓸 때의 계정·유동 닉네임·IP로 골라 보기)
struct WrittenList: View {
    let kind: WrittenItem.Kind
    @ObservedObject private var store = WrittenStore.shared
    @EnvironmentObject private var router: AppRouter
    @State private var who: WriterIdentity?
    @State private var confirmAll = false

    private var list: [WrittenItem] {
        store.items.filter { $0.kind == kind && (who == nil || $0.who == who) }
    }

    var body: some View {
        List {
            Section {
                ForEach(list) { it in
                    Button {
                        if let u = PostKey.url(it.key) {
                            router.open(kind == .comment ? URL(string: u.absoluteString + "#comment_box") ?? u : u)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(it.title.isEmpty ? it.key : it.title).foregroundStyle(.primary).lineLimit(2)
                            if kind == .comment, !it.snippet.isEmpty {
                                Text("💬 " + it.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Text("\(GalleryNames.name(PostKey.gallery(it.key))) · \(it.date.shortKorean) · \(it.who.label)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.remove(ids: [it.id]) } label: { Label("삭제", systemImage: "trash") }
                    }
                }
            } header: {
                HStack {
                    Menu {
                        Button { who = nil } label: {
                            if who == nil { Label("전체", systemImage: "checkmark") } else { Text("전체") }
                        }
                        ForEach(store.identities(kind: kind), id: \.self) { w in
                            Button { who = w } label: {
                                if who == w { Label(w.label, systemImage: "checkmark") } else { Text(w.label) }
                            }
                        }
                    } label: {
                        Label(who?.label ?? "전체 (\(list.count))", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .textCase(nil)
                    Spacer()
                    if !store.items.filter({ $0.kind == kind }).isEmpty {
                        Button("전체 삭제", role: .destructive) { confirmAll = true }.textCase(nil)
                    }
                }
                .padding(.top, 12).padding(.bottom, 6)
            }
        }
        .overlay {
            if list.isEmpty {
                ContentUnavailableView(kind == .post ? "작성한 글이 없어요" : "댓글 단 글이 없어요",
                                       systemImage: kind == .post ? "square.and.pencil" : "text.bubble",
                                       description: Text("이 앱에서 쓴 \(kind == .post ? "글" : "댓글")이 여기에 기록돼요."))
            }
        }
        .confirmationDialog(kind == .post ? "작성한 글 기록을 모두 지울까요?" : "댓글 기록을 모두 지울까요?",
                            isPresented: $confirmAll, titleVisibility: .visible) {
            Button("모두 지우기", role: .destructive) { store.clear(kind: kind); who = nil }
            Button("취소", role: .cancel) {}
        }
    }
}

// MARK: - 게시물 필터 (글 목록 상단바 깔때기 버튼)

struct ListFilter: Codable, Equatable {
    enum ReadMode: String, Codable, CaseIterable { case all, read, unread }
    var read: ReadMode = .all
    var recOn = false, rec = 3
    var cmtOn = false, cmt = 3
    var viewOn = false, view = 30

    var isActive: Bool { read != .all || recOn || cmtOn || viewOn }
    /// 페이지로 넘길 값 (켠 조건만)
    var script: [String: Any] {
        ["read": read.rawValue, "rec": recOn ? rec : -1, "cmt": cmtOn ? cmt : -1, "view": viewOn ? view : -1]
    }
}

@MainActor
final class ListFilterStore: ObservableObject {
    static let shared = ListFilterStore()
    private let key = "listFilter"
    @Published var filter: ListFilter {
        didSet { if let d = try? JSONEncoder().encode(filter) { UserDefaults.standard.set(d, forKey: key) } }
    }
    private init() {
        filter = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(ListFilter.self, from: $0) } ?? ListFilter()
    }
}

struct ListFilterSheet: View {
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var f = ListFilterStore.shared.filter

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("보기", selection: $f.read) {
                        Text("전체글").tag(ListFilter.ReadMode.all)
                        Text("읽은글").tag(ListFilter.ReadMode.read)
                        Text("안 읽은글").tag(ListFilter.ReadMode.unread)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    row("추천 수", on: $f.recOn, value: $f.rec)
                    row("댓글 수", on: $f.cmtOn, value: $f.cmt)
                    row("조회 수", on: $f.viewOn, value: $f.view)
                } footer: {
                    Text("체크한 조건을 모두 만족하는 글만 목록에 보여요. 읽은 글은 이 앱에서 연 글 기준이에요.")
                }
                if f.isActive {
                    Section {
                        Button("필터 끄기", role: .destructive) { f = ListFilter() }
                    }
                }
            }
            .navigationTitle("게시물 필터 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        ListFilterStore.shared.filter = f
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, on: Binding<Bool>, value: Binding<Int>) -> some View {
        HStack {
            Toggle(isOn: on) { Text(title) }
                .toggleStyle(CheckToggleStyle())
            Spacer()
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .padding(6)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                .disabled(!on.wrappedValue)
                .opacity(on.wrappedValue ? 1 : 0.5)
            Text("이상").foregroundStyle(.secondary)
        }
    }
}

/// 체크박스 모양 토글 (공식 앱 필터처럼)
private struct CheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? DCTheme.accent : Color.secondary)
                configuration.label.foregroundStyle(Color.primary)
            }
        }
        .buttonStyle(.plain)
    }
}
