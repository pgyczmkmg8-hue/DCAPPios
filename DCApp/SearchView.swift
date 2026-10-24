import SwiftUI

/// 검색 탭: 디시 통합검색 + 즐겨찾기 갤러리 빠른 찾기 + 최근 검색어
/// 결과는 홈 탭 브라우저에서 열려요.
struct SearchView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var router: AppRouter
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []

    /// 입력한 글자가 들어간 즐겨찾기 갤러리
    private var matches: [Gallery] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return favorites.items.filter {
            $0.name.lowercased().contains(q) || $0.galleryID.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !matches.isEmpty {
                    Section("즐겨찾기 갤러리") {
                        ForEach(matches) { g in
                            Button {
                                router.open(g.url)
                            } label: {
                                Label(g.name, systemImage: "star.fill")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        Button {
                            search(query)
                        } label: {
                            Label("'\(query)' 통합검색", systemImage: "magnifyingglass")
                        }
                    }
                }

                Section {
                    if recent.isEmpty {
                        Text("최근 검색어가 없어요").foregroundStyle(.secondary)
                    }
                    ForEach(recent, id: \.self) { word in
                        Button {
                            search(word)
                        } label: {
                            Label(word, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.primary)
                        }
                    }
                    .onDelete { offsets in
                        recent.remove(atOffsets: offsets)
                        saveRecent()
                    }
                } header: {
                    HStack {
                        Text("최근 검색")
                        Spacer()
                        if !recent.isEmpty {
                            Button("전체 삭제") {
                                recent.removeAll()
                                saveRecent()
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "갤러리 & 통합검색")
            .autoFocusSearch($searchFocused)
            .onSubmit(of: .search) { search(query) }
            .navigationTitle("검색")
            .onAppear { focusSearch() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { router.sheet = nil }
                }
            }
        }
    }

    private func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        // 최근 검색어 맨 앞에 추가 (중복 제거, 최대 20개)
        recent.removeAll { $0 == q }
        recent.insert(q, at: 0)
        if recent.count > 20 { recent.removeLast(recent.count - 20) }
        saveRecent()

        // 갤러리 주소를 붙여넣었으면 그 갤러리로 바로 이동, 아니면 통합검색
        if let url = URL(string: q), url.host != nil, let g = Gallery.parse(url) {
            router.open(Gallery(galleryID: g.id, name: g.id, kind: g.kind).url)
        } else {
            router.open(DC.search(q))
        }
        query = ""
    }

    /// 탭 전환 애니메이션이 끝난 뒤 검색창에 포커스 → 키보드 표시
    private func focusSearch() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            searchFocused = true
        }
    }

    private func saveRecent() {
        UserDefaults.standard.set(recent, forKey: "recentSearches")
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
