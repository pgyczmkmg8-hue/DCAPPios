import SwiftUI
import Combine

// MARK: - 모델

/// 디시 알림 등은 미니 갤러리를 "mi$갤ID", 인물 갤러리를 "pr$갤ID"로 줌 → 모바일 주소로 바꾸기
enum DCGalleryID {
    /// 앞머리(mi$·pr$)를 뗀 진짜 갤러리 ID
    nonisolated static func bare(_ id: String) -> String {
        for p in ["mi$", "pr$"] where id.hasPrefix(p) { return String(id.dropFirst(p.count)) }
        return id
    }
    /// 글 주소 (일반·마이너 /board, 미니 /mini, 인물 /person)
    nonisolated static func postURL(_ id: String, no: Int, comments: Bool) -> URL {
        let section = id.hasPrefix("mi$") ? "mini" : (id.hasPrefix("pr$") ? "person" : "board")
        return URL(string: "https://m.dcinside.com/\(section)/\(bare(id))/\(no)" + (comments ? "#comment_box" : ""))!
    }
}

enum GalleryKind: String, Codable, CaseIterable, Identifiable {
    case board   // 일반 + 마이너 갤러리 (모바일에서는 둘 다 /board/{id})
    case mini    // 미니 갤러리

    var id: String { rawValue }
    var label: String { self == .board ? "일반/마이너" : "미니" }
}

struct Gallery: Codable, Identifiable, Hashable {
    var galleryID: String
    var name: String
    var kind: GalleryKind

    var id: String { "\(kind.rawValue):\(galleryID)" }

    var url: URL {
        switch kind {
        case .board: URL(string: "https://m.dcinside.com/board/\(galleryID)")!
        case .mini:  URL(string: "https://m.dcinside.com/mini/\(galleryID)")!
        }
    }

    /// 디시 주소에서 갤러리 ID를 뽑아냅니다. (모바일/PC 주소 모두 지원)
    ///  - https://m.dcinside.com/board/{id}[/글번호]
    ///  - https://m.dcinside.com/mini/{id}
    ///  - https://gall.dcinside.com/board/lists?id={id}
    ///  - https://gall.dcinside.com/mgallery/board/lists?id={id}
    ///  - https://gall.dcinside.com/mini/board/lists?id={id}
    nonisolated static func parse(_ url: URL) -> (id: String, kind: GalleryKind)? {
        guard let host = url.host?.lowercased(), host.hasSuffix("dcinside.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }

        if host == "m.dcinside.com" {
            guard parts.count >= 2 else { return nil }
            // 미니 갤러리 글쓰기·수정 주소(/mini/write/갤ID 등)에서 'write'를 갤러리로 잘못 읽지 않게
            var id = DCGalleryID.bare(parts[1])
            if ["write", "modify", "delete"].contains(id) {
                guard parts.count >= 3 else { return nil }
                id = DCGalleryID.bare(parts[2])
            }
            switch parts[0] {
            case "board": return (id, .board)
            case "mini":  return (id, .mini)
            default:      return nil
            }
        }
        if host == "gall.dcinside.com",
           let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value,
           !id.isEmpty {
            return (id, parts.first == "mini" ? .mini : .board)
        }
        return nil
    }

    /// "OO 갤러리 - 커뮤니티 포털 디시인사이드" → "OO 갤러리"
    nonisolated static func cleanTitle(_ title: String) -> String {
        title.components(separatedBy: " - ").first?
            .trimmingCharacters(in: .whitespaces) ?? title
    }

    /// 페이지 제목에서 갤러리 이름 추측. 글 보기 화면이면 글 제목이 아닌 갤러리 이름을 고르고, 모르면 ID 사용.
    nonisolated static func guessName(title: String, url: URL, id: String) -> String {
        let parts = title.components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("디시인사이드") }
        if let g = parts.last(where: { $0.hasSuffix("갤러리") || $0.hasSuffix("갤") }) { return g }
        let isPostPage = url.pathComponents.filter { $0 != "/" }.count >= 3
            || url.query?.contains("no=") == true
        if !isPostPage, let first = parts.first { return first }
        return id
    }
}

// MARK: - 저장소 (UserDefaults에 JSON으로 저장)

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var items: [Gallery] = []
    private let key = "favoriteGalleries"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Gallery].self, from: data) {
            items = saved
        }
    }

    func contains(galleryID: String, kind: GalleryKind) -> Bool {
        items.contains { $0.galleryID == galleryID && $0.kind == kind }
    }

    func add(_ g: Gallery) {
        guard !contains(galleryID: g.galleryID, kind: g.kind) else { return }
        items.append(g); save()
    }

    func remove(galleryID: String, kind: GalleryKind) {
        items.removeAll { $0.galleryID == galleryID && $0.kind == kind }; save()
    }

    func rename(_ g: Gallery, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = items.firstIndex(where: { $0.id == g.id }) else { return }
        items[i].name = n; save()
    }

    func remove(at offsets: IndexSet) { items.remove(atOffsets: offsets); save() }

    /// 백업 복원용
    func replaceAll(_ list: [Gallery]) { items = list; save() }
    func move(from: IndexSet, to: Int) { items.move(fromOffsets: from, toOffset: to); save() }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - 즐겨찾기 탭

enum LibrarySection: String, CaseIterable, Identifiable {
    case visited = "방문한 갤러리"
    case galleries = "즐겨찾기"
    case alarms = "알림"
    case posts = "보관함"
    var id: Self { self }
}

// MARK: - 방문한 갤러리 기록

struct VisitedGallery: Codable, Identifiable, Hashable {
    var gallery: Gallery
    var lastVisited: Date
    var id: String { gallery.id }
}

@MainActor
final class VisitedStore: ObservableObject {
    static let shared = VisitedStore()
    @Published private(set) var items: [VisitedGallery] = []
    private let key = "visitedGalleries"
    private let limit = 100

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([VisitedGallery].self, from: data) {
            // 예전에 미니 갤러리 글쓰기 주소를 잘못 읽어 생긴 'write' 같은 가짜 갤러리 지우기
            items = saved.filter { !["write", "modify", "delete"].contains($0.gallery.galleryID) && !$0.gallery.galleryID.contains("$") }
            if items.count != saved.count { save() }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 갤러리에 들어갈 때마다 기록 (맨 위로 올림). 이름을 모르면 예전에 알던 이름 유지
    func record(galleryID: String, kind: GalleryKind, name: String) {
        let old = items.first { $0.gallery.galleryID == galleryID && $0.gallery.kind == kind }
        let betterName = (name == galleryID ? old?.gallery.name : nil) ?? name
        items.removeAll { $0.gallery.galleryID == galleryID && $0.gallery.kind == kind }
        items.insert(VisitedGallery(gallery: Gallery(galleryID: galleryID, name: betterName, kind: kind),
                                    lastVisited: Date()), at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        save()
    }

    func remove(_ v: VisitedGallery) { items.removeAll { $0.id == v.id }; save() }
    func remove(at offsets: IndexSet) { items.remove(atOffsets: offsets); save() }
    func removeAll() { items.removeAll(); save() }
    func replaceAll(_ list: [VisitedGallery]) { items = list; save() }
}

/// 방문한 갤러리 목록 (개별 삭제 가능)
struct VisitedGalleriesList: View {
    @ObservedObject private var store = VisitedStore.shared
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
            ForEach(store.items) { v in
                let g = v.gallery
                let fav = favorites.items.first { $0.galleryID == g.galleryID && $0.kind == g.kind }
                Button {
                    router.open(g.url)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fav?.name ?? g.name).foregroundStyle(.primary)
                            Text("\(g.kind.label) · \(g.galleryID) · \(v.lastVisited.shortKorean)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if fav != nil {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.remove(v) } label: { Label("삭제", systemImage: "trash") }
                }
                .swipeActions(edge: .leading) {
                    if fav == nil {
                        Button { favorites.add(g) } label: { Label("즐겨찾기", systemImage: "star") }
                            .tint(.yellow)
                    }
                }
            }
            .onDelete { store.remove(at: $0) }
        }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView("방문한 갤러리가 없어요", systemImage: "clock",
                                       description: Text("갤러리에 들어가면 여기에 자동으로 기록돼요."))
            }
        }
    }
}

/// 하단 바 "갤러리": 방문한 갤러리 / 즐겨찾는 갤러리 (임시저장은 글쓰기 화면의 '불러오기'에서)
struct FavoritesView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var router: AppRouter
    @State private var section: LibrarySection = .visited
    @State private var confirmClearVisited = false
    @State private var galleryQuery = ""
    @State private var showingAdd = false
    @State private var renaming: Gallery?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if !galleryQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    GalleryFindResults(query: galleryQuery)    // 갤러리 검색 중
                } else {
                    switch section {
                    case .visited: VisitedGalleriesList()
                    case .galleries: galleriesList
                    case .alarms: AlarmsList()
                    case .posts: SavedPostsList()     // 글 보관함 (⋮ 메뉴에서 옮김)
                    }
                }
            }
            .searchable(text: $galleryQuery, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "갤러리 이름이나 ID로 찾기")
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("갤러리", selection: $section) {
                    ForEach(LibrarySection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("갤러리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 디시 첫 화면으로 (하단 바의 홈 버튼을 이쪽으로 옮김)
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.open(DC.home) } label: {
                        Label("홈", systemImage: "house")
                    }
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                if section == .galleries {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingAdd = true } label: { Image(systemName: "plus") }
                    }
                }
                if section == .alarms && !AlarmStore.shared.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("모두 읽음으로") { AlarmStore.shared.markAllRead() }
                            Button("전체 삭제", role: .destructive) { AlarmStore.shared.removeAll() }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                if section == .visited && !VisitedStore.shared.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("전체 삭제") { confirmClearVisited = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { router.sheet = nil }
                }
            }
            .sheet(isPresented: $showingAdd) { AddGalleryView() }
            .confirmationDialog("방문 기록을 모두 지울까요?", isPresented: $confirmClearVisited, titleVisibility: .visible) {
                Button("모두 지우기", role: .destructive) { VisitedStore.shared.removeAll() }
                Button("취소", role: .cancel) {}
            }
            .alert("이름 변경",
                   isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("갤러리 이름", text: $renameText)
                Button("취소", role: .cancel) {}
                Button("저장") { if let g = renaming { favorites.rename(g, to: renameText) } }
            }
        }
    }

    private var galleriesList: some View {
        List {
            ForEach(favorites.items) { g in
                Button {
                    router.open(g.url)   // 홈 탭 브라우저에서 열기
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).foregroundStyle(.primary)
                            Text("\(g.kind.label) · \(g.galleryID)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .contextMenu {
                    Button { startRename(g) } label: { Label("이름 변경", systemImage: "pencil") }
                    Button(role: .destructive) {
                        favorites.remove(galleryID: g.galleryID, kind: g.kind)
                    } label: { Label("삭제", systemImage: "trash") }
                }
                .swipeActions(edge: .leading) {
                    Button { startRename(g) } label: { Label("이름 변경", systemImage: "pencil") }
                        .tint(.orange)
                }
            }
            .onDelete { favorites.remove(at: $0) }
            .onMove { favorites.move(from: $0, to: $1) }
        }
        .overlay {
            if favorites.items.isEmpty {
                ContentUnavailableView(
                    "즐겨찾는 갤러리가 없어요",
                    systemImage: "star",
                    description: Text("갤러리를 보다가 아래 ☆ 버튼을 누르면 바로 추가돼요.\n길게 누르면 이름을 바꿀 수 있어요.")
                )
            }
        }
    }

    private func startRename(_ g: Gallery) {
        renameText = g.name
        renaming = g
    }
}

// MARK: - 직접 추가 화면

struct AddGalleryView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var name = ""
    @State private var kind: GalleryKind = .board

    /// 주소를 붙여넣었으면 거기서 ID/종류를 뽑고, 아니면 입력값을 ID로 사용
    private var parsed: (id: String, kind: GalleryKind)? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), url.host != nil { return Gallery.parse(url) }
        return (text, kind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("갤러리 ID 또는 주소", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("표시 이름 (선택)", text: $name)
                    Picker("종류", selection: $kind) {
                        ForEach(GalleryKind.allCases) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text("예: dcbest 또는 https://m.dcinside.com/board/dcbest\n주소를 붙여넣으면 종류는 자동으로 판단해요.")
                }
                if !input.isEmpty && parsed == nil {
                    Text("디시 갤러리 주소를 인식하지 못했어요.").foregroundStyle(.red)
                }
            }
            .navigationTitle("갤러리 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가") {
                        if let p = parsed {
                            favorites.add(Gallery(galleryID: p.id,
                                                  name: name.isEmpty ? p.id : name,
                                                  kind: p.kind))
                        }
                        dismiss()
                    }
                    .disabled(parsed == nil)
                }
            }
        }
    }
}


// MARK: - 갤러리 찾기 (하단 바 "갤러리" 창의 검색)

struct GalleryFindResults: View {
    let query: String
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var visited = VisitedStore.shared

    private var q: String { query.trimmingCharacters(in: .whitespaces) }

    /// 즐겨찾기 + 방문한 갤러리 중 이름/ID가 맞는 것 (중복 제거)
    private var localMatches: [Gallery] {
        let key = q.lowercased()
        var seen = Set<String>()
        var out: [Gallery] = []
        for g in favorites.items + visited.items.map(\.gallery) where !seen.contains(g.id) {
            if g.name.lowercased().contains(key) || g.galleryID.lowercased().contains(key) {
                seen.insert(g.id); out.append(g)
            }
        }
        return out
    }

    /// 영문/숫자/밑줄만 있으면 갤러리 ID로 보고 바로 가기 제안
    private var looksLikeID: Bool {
        q.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil
    }

    var body: some View {
        List {
            if !localMatches.isEmpty {
                Section("즐겨찾기 · 방문한 갤러리") {
                    ForEach(localMatches) { g in
                        Button { router.open(g.url) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.name).foregroundStyle(.primary)
                                    Text("\(g.kind.label) · \(g.galleryID)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if favorites.contains(galleryID: g.galleryID, kind: g.kind) {
                                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Button { router.open(DC.search(q)) } label: {
                    Label("'\(q)' 디시에서 갤러리 찾기", systemImage: "magnifyingglass")
                }
                if looksLikeID {
                    Button {
                        router.open(Gallery(galleryID: q, name: q, kind: .board).url)
                    } label: {
                        Label("ID '\(q)' 갤러리로 바로 가기", systemImage: "arrow.right.circle")
                    }
                }
            } footer: {
                Text("디시 통합검색 결과에서 갤러리를 고르면 그 갤러리로 가요.")
            }
        }
    }
}
