import SwiftUI
import Combine

/// 통합검색 최근 검색어 (검색 탭과 갤러리 안 창의 '통합검색' 탭이 같이 씀)
final class SearchRecents: ObservableObject {
    static let shared = SearchRecents()
    private static let key = "recentSearches"

    @Published private(set) var items: [String] = Profile.defaults.stringArray(forKey: SearchRecents.key) ?? []

    func add(_ q: String) {
        items.removeAll { $0 == q }
        items.insert(q, at: 0)
        if items.count > 20 { items.removeLast(items.count - 20) }   // 최대 20개
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        Profile.defaults.set(items, forKey: SearchRecents.key)
    }
}

/// 통합검색 실행: 최근 검색어에 넣고, 갤러리 주소를 붙여넣었으면 그 갤러리로, 아니면 디시 통합검색으로 보냄
enum SearchRouting {
    @MainActor
    static func run(_ text: String, open: (URL) -> Void) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        SearchRecents.shared.add(q)
        if let url = URL(string: q), url.host != nil, let g = Gallery.parse(url) {
            open(Gallery(galleryID: g.id, name: g.id, kind: g.kind).url)
        } else {
            open(DC.search(q))
        }
    }
}

/// 검색 탭: 디시 통합검색 + 즐겨찾기 갤러리 빠른 찾기 + 디시 갤러리 실시간 검색 + 최근 검색어
/// 결과는 홈 탭 브라우저에서 열려요.
struct SearchView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            SearchPanel(query: $query) { url in router.open(url) }
                .searchable(text: $query,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "갤러리 & 통합검색")
                .autoFocusSearch($searchFocused)
                .onSubmit(of: .search) {
                    SearchRouting.run(query) { router.open($0) }
                    query = ""
                }
                .onAppear { focusSearch() }
                .navigationTitle("검색")
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { router.sheet = nil }
                    }
                }
        }
        .presentationBackgroundCompat(Color(uiColor: .systemGroupedBackground))
    }

    /// 탭 전환 애니메이션이 끝난 뒤 검색창에 포커스 → 키보드 표시
    private func focusSearch() {
        Task {
            try? await Task.sleep(for: .milliseconds(80))   // 시트 애니메이션을 기다리지 않고 바로 키보드를 올림
            searchFocused = true
        }
    }
}

/// 검색 내용 (즐겨찾기 갤러리 · 디시 갤러리 실시간 결과 · 통합검색 · 최근 검색어).
/// 검색어 입력칸은 이 안에 없음 — 바깥(검색 탭의 검색창, 갤러리 안 창의 공통 입력창)이 `query`로 넘겨 줌.
/// open: 주소를 여는 방법 (검색 탭은 홈 브라우저, 갤러리 안 창은 지금 화면)
struct SearchPanel: View {
    @ObservedObject var fonts = FontStore.shared
    @Binding var query: String
    let open: (URL) -> Void
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var recents = SearchRecents.shared
    @StateObject private var live = GalleryLiveSearch()

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// 입력한 글자가 들어간 즐겨찾기 갤러리
    private var matches: [Gallery] {
        let q = trimmedQuery.lowercased()
        guard !q.isEmpty else { return [] }
        return favorites.items.filter {
            $0.name.lowercased().contains(q) || $0.galleryID.lowercased().contains(q)
        }
    }

    /// 위에 즐겨찾기로 보여 준 갤러리 ID (실시간 결과에서 중복으로 안 나오게)
    private var localIDs: Set<String> {
        Set(matches.map { DCGalleryID.bare($0.galleryID) })
    }

    var body: some View {
        List {
            if !matches.isEmpty {
                Section("즐겨찾기 갤러리") {
                    ForEach(matches) { g in
                        Button {
                            open(g.url)
                        } label: {
                            Label(g.name, systemImage: "star.fill")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            if !trimmedQuery.isEmpty {
                // 타이핑 중에도 디시 갤러리 검색 결과 (디바운스·이전 요청 취소는 GalleryLiveSearch가 함)
                GalleryLiveResults(live: live, excluded: localIDs, open: open)

                Section {
                    Button {
                        SearchRouting.run(query, open: open)
                        query = ""
                    } label: {
                        Label("'\(query)' 통합검색", systemImage: "magnifyingglass")
                    }
                }
            }

            Section {
                if recents.items.isEmpty {
                    Text("최근 검색어가 없어요").foregroundStyle(.secondary)
                }
                ForEach(recents.items, id: \.self) { word in
                    Button {
                        SearchRouting.run(word, open: open)
                    } label: {
                        Label(word, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                    }
                }
                .onDelete { recents.remove(atOffsets: $0) }
            } header: {
                HStack {
                    Text("최근 검색")
                    Spacer()
                    if !recents.items.isEmpty {
                        Button("전체 삭제") { recents.clear() }
                            .font(fonts.styleFont(.caption))
                    }
                }
            }
        }
        .onChangeCompat(of: query) { _, q in live.update(q) }
        .onAppear { live.update(query) }     // 탭을 다시 열었을 때 입력돼 있던 검색어로 결과를 다시 받음
        .onDisappear { live.cancel() }
    }
}

extension View {
    /// 검색창 자동 포커스 (iOS 18 이상에서 동작, iOS 17에서는 무시)
    @ViewBuilder
    func autoFocusSearch(_ focused: FocusState<Bool>.Binding) -> some View {
        if #available(iOS 18.0, *) {
            self.searchFocused(focused)
        } else {
            self
        }
    }
}
