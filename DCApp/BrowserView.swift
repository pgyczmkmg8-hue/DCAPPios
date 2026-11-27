import SwiftUI
import Combine

/// 앱 테마 (설정 → 앱 → 테마). 상단바 색, 강조색(하단 바 선택 등), 웹페이지 속 디시 파란색 계열을 바꿀 색
enum AppTheme: String, CaseIterable, Identifiable {
    case dc, navy, green, gray, custom
    var id: String { rawValue }

    var name: String {
        switch self {
        case .dc: "디시 (기본)"
        case .navy: "남색"
        case .green: "연두"
        case .gray: "무채색"
        case .custom: "직접 지정"
        }
    }

    /// 상단바 색
    var bar: UIColor {
        switch self {
        case .dc: UIColor(red: 0.231, green: 0.282, blue: 0.565, alpha: 1)    // 디시 고유 색 (#3B4890)
        case .navy: UIColor(red: 0.29, green: 0.33, blue: 0.64, alpha: 1)     // 예전 기본색
        case .green: UIColor(red: 0.01, green: 0.78, blue: 0.35, alpha: 1)    // 네이버 초록 (#03C75A)
        case .gray: UIColor(red: 0.33, green: 0.33, blue: 0.35, alpha: 1)
        case .custom: DCTheme.customColor
        }
    }

    /// 강조색 — 밝은 화면 / 어두운 화면(다크 모드에서는 잘 보이게 밝게)
    var accentLight: UIColor {
        switch self {
        case .dc, .navy, .custom: bar
        case .green: UIColor(red: 0.0, green: 0.62, blue: 0.29, alpha: 1)      // 흰 바탕 글자용으로 조금 진하게
        case .gray: UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1)
        }
    }
    var accentDark: UIColor {
        switch self {
        case .dc, .navy: return UIColor(red: 0.55, green: 0.62, blue: 1.0, alpha: 1)
        case .green: return UIColor(red: 0.18, green: 0.88, blue: 0.48, alpha: 1)
        case .gray: return UIColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1)
        case .custom:
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            bar.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return UIColor(hue: h, saturation: min(s, 0.85), brightness: max(b, 0.78), alpha: 1)
        }
    }

    /// 웹페이지 속 디시 파란색 계열을 바꿀 색 (h: 색상각, s: 채도 배율). nil이면 사이트 색 그대로
    var pageTint: [String: Double]? {
        switch self {
        case .dc, .navy: return nil
        case .green: return ["h": 147, "s": 1.6]
        case .gray: return ["h": 230, "s": 0]
        case .custom:
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            bar.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return ["h": Double(h * 360), "s": s < 0.08 ? 0 : 1.3]
        }
    }
}

/// 앱 색상 — 지금 고른 테마를 따름
enum DCTheme {
    static let storageKey = "appTheme"
    static let customHexKey = "appThemeCustomHex"
    static let defaultCustomHex = "3B4890"

    static var current: AppTheme {
        AppTheme(rawValue: Profile.defaults.string(forKey: storageKey) ?? "") ?? .dc
    }

    static var customHex: String {
        normalizedHex(Profile.defaults.string(forKey: customHexKey) ?? "") ?? defaultCustomHex
    }

    static var customColor: UIColor {
        color(fromHex: customHex) ?? UIColor(red: 0.231, green: 0.282, blue: 0.565, alpha: 1)
    }

    /// 6자리 16진법 코드 정규화 (# 제거, 대문자 6자리만 허용)
    static func normalizedHex(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard s.count == 6, s.allSatisfy(\.isHexDigit) else { return nil }
        return s
    }

    static func color(fromHex hex: String) -> UIColor? {
        guard let norm = normalizedHex(hex), let val = UInt32(norm, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255
        let g = CGFloat((val >> 8) & 0xFF) / 255
        let b = CGFloat(val & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
    /// 상단바 색 (이름은 예전 그대로 navy)
    static var navy: Color { Color(uiColor: current.bar) }
    /// 하단 바 선택 색 등 (다크 모드에서는 밝게)
    static var accent: Color {
        let t = current
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? t.accentDark : t.accentLight
        })
    }
}

/// 갤러리 하단 바의 칸
enum GallerySection {
    case home, notice, recommend, search, write
}

extension Gallery {
    /// 개념글 목록
    var recommendURL: URL { URL(string: url.absoluteString + "?recommend=1")! }
    /// 공지 목록 (주소 형식이 다르면 여기만 고치면 됨)
    var noticeURL: URL { URL(string: url.absoluteString + "?notice=1")! }
    /// 갤러리 내 검색 (제목+내용)
    func searchURL(_ keyword: String, type: GallerySearchType = .subjectMemo, recommendOnly: Bool = false,
                   head: HeadTab? = nil) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = [
            URLQueryItem(name: "s_type", value: type.rawValue),
            URLQueryItem(name: "serval", value: keyword),
        ]
        if recommendOnly { items.insert(URLQueryItem(name: "recommend", value: "1"), at: 0) }
        // 말머리: 말머리 탭 링크에 붙어 있던 값(headid 등)을 그대로 붙임
        if let head, let headItems = URLComponents(url: head.url, resolvingAgainstBaseURL: false)?.queryItems {
            items.insert(contentsOf: headItems.filter { !["page", "s_type", "serval", "recommend"].contains($0.name) }, at: 0)
        }
        comps.queryItems = items
        return comps.url ?? url
    }
    /// 글쓰기
    var writeURL: URL {
        switch kind {
        case .board: URL(string: "https://m.dcinside.com/write/\(galleryID)")!
        case .mini:  URL(string: "https://m.dcinside.com/writemini/\(galleryID)")!   // 미니는 /writemini/ (디시 웹과 같게)
        case .person: URL(string: "https://m.dcinside.com/writepr/\(galleryID)")!    // 인물은 /writepr/
        }
    }
}

/// 갤러리 내 검색 범위 (디시 모바일 검색 주소의 s_type 값 — 다르면 여기만 고치면 됨)
enum GallerySearchType: String, CaseIterable, Identifiable {
    case subjectMemo = "subject_m"
    case subject = "subject"
    case memo = "memo"
    case name = "name"
    case comment = "comment"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .subjectMemo: "제목+내용"
        case .subject: "제목"
        case .memo: "내용"
        case .name: "글쓴이"
        case .comment: "댓글"
        }
    }
}

/// 말머리 (지금 갤러리 페이지의 탭에서 읽어옴)
struct HeadTab: Hashable, Identifiable {
    let name: String
    let url: URL
    var id: String { name }
}

/// 검색 창: 세그먼트(갤러리 내 글 검색 · 통합검색 · 식별코드·IP) + 검색어 입력칸 하나(공통)
/// 입력칸은 탭과 무관하게 같은 자리에 있어서, 탭을 바꿔도 키보드가 내려가지 않고 검색어도 그대로 남음
/// 상단 '나무위키' 버튼은 지금 적은 검색어를 넘겨 나무위키 입력 창을 띄움
struct GallerySearchSheet: View {
    @ObservedObject var fonts = FontStore.shared
    let gallery: Gallery
    var heads: [HeadTab] = []
    let onSearch: (URL) -> Void
    @State private var head: HeadTab?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var visited = VisitedStore.shared
    @ObservedObject private var idSearch = IdPostSearcher.shared
    @AppStorage("gallerySearchType", store: Profile.defaults) private var typeRaw = GallerySearchType.subjectMemo.rawValue
    /// 공통 검색어 (세 탭이 같이 씀)
    @State private var keyword = ""
    @State private var recommendOnly = false
    @State private var recent: [String] = Profile.defaults.stringArray(forKey: "gallerySearchRecent") ?? []
    /// 식별코드 탭에서 찾을 갤러리 (nil = 지금 보고 있는 갤러리)
    @State private var idGallery: Gallery?
    @FocusState private var focused: Bool

    /// 상단 세그먼트
    private enum SearchTab: String { case gallery, all, id }
    @State private var tab: SearchTab = .gallery

    private var type: GallerySearchType { GallerySearchType(rawValue: typeRaw) ?? .subjectMemo }
    private var keywordEmpty: Bool { keyword.trimmingCharacters(in: .whitespaces).isEmpty }
    private var trimmedKeyword: String { keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// 식별코드 탭에서 찾을 갤러리
    private var pickedGallery: Gallery { idGallery ?? gallery }
    /// 찾을 갤러리 목록: 지금 갤러리 → 즐겨찾기 → 방문한 갤러리 (같은 갤러리는 한 번만)
    private var galleryChoices: [Gallery] {
        var seen = Set<String>()
        return ([gallery] + favorites.items + visited.items.map(\.gallery)).filter { seen.insert($0.id).inserted }
    }
    /// 검색창 placeholder: 이름에 이미 '갤러리'가 있으면 한 번만 붙임
    private var galleryPlaceholder: String {
        gallery.name.contains("갤러리") ? "\(gallery.name) 글 검색" : "\(gallery.name) 갤러리 글 검색"
    }
    private var fieldPlaceholder: String {
        switch tab {
        case .gallery: return galleryPlaceholder
        case .all: return "갤러리 & 통합검색"
        case .id: return "식별코드 또는 IP"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("검색 종류", selection: $tab) {
                    Text("갤러리 내 글 검색").tag(SearchTab.gallery)
                    Text("통합검색").tag(SearchTab.all)
                    Text("식별코드·IP").tag(SearchTab.id)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Group {
                    // 탭별 내용만 바뀜
                    switch tab {
                    case .gallery:
                        galleryForm
                    case .all:
                        SearchPanel(query: $keyword) { url in
                            onSearch(url)      // 지금 화면에서 열고 창을 닫음
                            dismiss()
                        }
                    case .id:
                        idForm
                    }
                }
            }
            // 검색어 칸은 검색 탭과 같은 시스템 검색창 (취소·지우기 버튼 포함)
            .searchable(text: $keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(fieldPlaceholder))
            .autoFocusSearch($focused)
            .onSubmit(of: .search) { submit() }
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
            .onChangeCompat(of: tab) { _, new in
                if new == .id { enterIdTab() }
            }
            .onChangeCompat(of: keyword) { _, _ in
                if tab == .id { idSearch.code = trimmedKeyword }   // 식별코드 탭에서는 이 칸이 식별코드 칸
            }
            .onAppear {
                Task { try? await Task.sleep(for: .milliseconds(80)); focused = true }
            }
        }
        .presentationBackgroundCompat(Color(uiColor: .systemGroupedBackground))
        .sheetUnderBlueBar(medium: true)
    }

    /// '갤러리 내 글 검색' 탭 내용 (말머리 · 검색 범위 · 개념글 · 최근 검색어)
    @ViewBuilder
    private var galleryForm: some View {
        Form {
            Section {
                if !heads.isEmpty {
                    Picker("말머리", selection: $head) {
                        Text("전체 말머리").tag(HeadTab?.none)
                        ForEach(heads) { Text($0.name).tag(HeadTab?.some($0)) }
                    }
                }
                Picker("검색 범위", selection: $typeRaw) {
                    ForEach(GallerySearchType.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("개념글에서만 검색", isOn: $recommendOnly)
            } header: {
                // 이름에 이미 '갤러리'가 있으면(예: 퓨처스리그 마이너 갤러리) 한 번만 붙임
                Text(gallery.name.contains("갤러리") ? "\(gallery.name)에서 검색" : "\(gallery.name) 갤러리에서 검색")
            }

            if !recent.isEmpty {
                Section {
                    ForEach(recent, id: \.self) { w in
                        Button { search(w) } label: {
                            Label(w, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                        }
                    }
                    .onDelete { recent.remove(atOffsets: $0); saveRecent() }
                } header: {
                    HStack {
                        Text("최근 검색어")
                        Spacer()
                        Button("전체 삭제") { recent.removeAll(); saveRecent() }.font(fonts.styleFont(.caption))
                    }
                }
            }
        }
    }

    /// '식별코드·IP' 탭: 찾을 갤러리 고르기 + 식별코드 찾기 (결과는 이 안에 나오고, 찾은 글을 누르면 그 화면으로 감)
    @ViewBuilder
    private var idForm: some View {
        List {
            Section {
                Picker("갤러리", selection: idGalleryBinding) {
                    ForEach(galleryChoices) { g in Text(g.name).tag(g.id) }
                }
                .disabled(idSearch.running)
            } header: {
                Text("찾을 갤러리")
            } footer: {
                Text("기본은 지금 보고 있는 갤러리예요. 즐겨찾기나 방문한 갤러리로 바꿀 수 있어요. 찾는 중에는 바꿀 수 없어요.")
            }
            IdPostSearchSections(showsCodeField: false) { url in
                onSearch(url)
                dismiss()
            }
        }
    }

    /// 갤러리 고르기 칸 (갤러리 ID로 주고받음)
    private var idGalleryBinding: Binding<String> {
        Binding(
            get: { pickedGallery.id },
            set: { id in
                guard !idSearch.running, let g = galleryChoices.first(where: { $0.id == id }) else { return }
                idGallery = g
                idSearch.setGallery(g)
            }
        )
    }

    /// 식별코드 탭을 열 때: 찾을 갤러리(기본은 지금 갤러리)와 검색어를 맞춰 둠 (찾는 중이면 그대로)
    private func enterIdTab() {
        guard !idSearch.running else { return }
        idSearch.setGallery(pickedGallery)
        idSearch.code = trimmedKeyword
    }

    /// 엔터: 지금 탭에 맞는 검색
    private func submit() {
        guard !keywordEmpty else { return }
        switch tab {
        case .gallery:
            search(keyword)
        case .all:
            SearchRouting.run(keyword) { url in
                onSearch(url)
                dismiss()
            }
            keyword = ""
        case .id:
            startIdSearch()
        }
    }

    /// 식별코드 탭에서 찾기 (이미 찾는 중이면 그대로 둠)
    private func startIdSearch() {
        guard !idSearch.running else { return }
        idSearch.setGallery(pickedGallery)
        idSearch.code = trimmedKeyword
        focused = false
        idSearch.start()
    }

    private func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        recent.removeAll { $0 == q }
        recent.insert(q, at: 0)
        if recent.count > 20 { recent.removeLast(recent.count - 20) }
        saveRecent()
        onSearch(gallery.searchURL(q, type: type, recommendOnly: recommendOnly, head: head))
        dismiss()
    }

    private func saveRecent() { Profile.defaults.set(recent, forKey: "gallerySearchRecent") }
}

/// 자기 브라우저를 직접 만들어 쓰는 화면(설정의 디시콘 샵·로그인 페이지 직접 열기)
/// 모델을 여기서 @StateObject로 한 번만 만들고, BrowserView에는 넘겨서 보여 줌 (화면이 다시 그려져도 웹뷰가 새로 만들어지지 않음)
struct StandaloneBrowserView: View {
    @StateObject private var model: WebViewModel
    private let fallbackTitle: String

    init(startURL: URL, fallbackTitle: String) {
        _model = StateObject(wrappedValue: WebViewModel(url: startURL))
        self.fallbackTitle = fallbackTitle
    }

    var body: some View {
        BrowserView(model: model, fallbackTitle: fallbackTitle)
    }
}

/// 웹뷰 + 남색 상단바 + 공식 앱 스타일 하단 바. NavigationStack 안에 넣어서 사용하세요.
struct BrowserView: View {
    /// 밖(AppRouter 등)에서 만들어 넘겨받은 브라우저라 @ObservedObject — @StateObject로 받으면 같은 자리에서 넘겨받는 모델이 바뀌어도(primaryBrowser: main ↔ detail) 처음 받은 모델을 계속 붙들고 있음
    /// 스스로 브라우저를 만들어야 하는 화면은 StandaloneBrowserView가 @StateObject로 소유
    @ObservedObject private var model: WebViewModel
    /// 분할 화면의 글 화면 (컨트롤바가 오른쪽에 있을 때 숨김 기준) — 단일 화면이면 model과 같음
    @ObservedObject private var detailPane: WebViewModel
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var autoImages = AutoImageStore.shared
    @ObservedObject private var savedPosts = SavedPostStore.shared
    @ObservedObject private var alarms = AlarmStore.shared
    @ObservedObject private var hwKeyboard = HardwareKeyboard.shared
    @ObservedObject private var fonts = FontStore.shared
    @AppStorage("compactMode", store: Profile.defaults) private var compactMode = false
    /// 오른쪽 세로 버튼 막대 (끄면 ⋮ 메뉴가 상단바로 감)
    /// 오른쪽 세로 버튼 막대는 없앰 (⋮는 상단바, 한손 모드는 제목 길게 누르기, 글 볼 때만 댓글 새로고침 버튼)
    private let showFloatingBar = false
    /// 컨트롤바 버튼 순서 (설정에서 바꿈)
    @AppStorage(ControlBarItem.storageKey, store: Profile.defaults) private var controlOrderRaw = ""
    /// ⋮ 메뉴를 상단바 오른쪽에 둘지 (켜면 컨트롤바에서는 빠짐)
    @AppStorage(ControlBarItem.menuInTopBarKey, store: Profile.defaults) private var menuInTopBar = true
    /// 휴대폰·듀오: 시스템 상단바 대신 위쪽 띠에 낮은 상단바(제목·버튼)를 그림 — 스크롤해도 고정, 높이 최소. 끄면 시스템 상단바
    @AppStorage("compactTopBar", store: Profile.defaults) private var compactTopBarSetting = true

    // 글쓰기 화면 → 이 갤러리 자짤 설정 창
    @State private var autoImageGallery: String?
    /// 차단·메모 버튼: 무엇을 할지 고르는 창
    @State private var showBlockMemoChoice = false
    private var writeGalleryID: String? { model.url.flatMap(AutoImageStore.writeGalleryID) }
    /// 자짤 설정에 쓸 계정 범위 (알 수 없으면 nil = 모든 계정)
    private var autoScopeAccount: String? { footerAccountKey == FooterRule.all ? nil : footerAccountKey }
    /// 자짤 설정 화면 제목: 범위 키(계정+갤러리) → '계정 · 갤러리 이름'
    private func autoScopeName(_ key: String) -> String {
        let (a, g) = AutoImageScope.parse(key)
        let name = favorites.items.first { $0.galleryID == g }?.name ?? gallery?.name ?? g
        return a == nil ? name : "\(AutoImageScope.accountLabel(a)) · \(name)"
    }
    /// 꼬릿말을 정할 갤러리 (갤러리 목록·글 보기·글쓰기 화면)
    private var footerGalleryID: String? { writeGalleryID ?? currentGallery?.id }
    /// 꼬릿말을 정할 계정: 글쓰기 중이면 그 글의 신분(유동/로그인), 아니면 지금 로그인한 계정 (없으면 유동)
    private var footerAccountKey: String {
        if let s = model.nativeWrite { return s.isAnon ? FooterRule.anon : (CredentialStore.currentAccountID ?? FooterRule.all) }
        return CredentialStore.currentAccountID ?? FooterRule.anon
    }

    // 글쓰기 화면의 계정 버튼에 표시할 현재 계정
    @State private var currentAccount: String? = CredentialStore.currentAccountID

    // 글 보관 버튼: 폴더 고르기 / 이미 보관한 글 메뉴
    @State private var showSaveFolderPicker = false
    @AppStorage("showDiagnoseMenu", store: Profile.defaults) private var showDiagnoseMenu = false
    @AppStorage(DarkMode.key, store: Profile.defaults) private var darkMode = false
    @AppStorage(DarkMode.followKey, store: Profile.defaults) private var darkFollowSystem = false
    @State private var newFolderName = ""
    @State private var newFolderFor: SavedPost?        // nil이면 지금 글을 새 폴더에 보관, 있으면 그 글을 새 폴더로 옮기기
    @State private var showNewFolder = false
    @State private var savedPostMenu: SavedPost?
    let fallbackTitle: String
    /// 왼쪽 위 ☰ 버튼 (홈 탭의 메인 브라우저에서만 표시, 다른 곳은 뒤로가기 버튼 자리)
    var showsMenuButton = false
    /// 분할 화면의 왼쪽(목록) 화면이면 목록이 쓰는 폭 — 이 화면은 창 전체 폭으로 그려지고(컨트롤바가 창 오른쪽 끝에 놓이게),
    /// 웹페이지·하단 바 같은 내용만 이 폭 안에 둠
    var splitListWidth: CGFloat? = nil


    // 갤러리 내 검색
    @State private var showGallerySearch = false
    @State private var galleryHeads: [HeadTab] = []
    @State private var gallerySearchText = ""

    // 유저 직접 입력 차단
    @State private var showUserPrompt = false
    @State private var userInput = ""

    // 유저 메모 입력 (길게 누르기 → 메모)
    @State private var memoTarget: (kind: BlockedUser.Kind, value: String, nick: String, existing: UserMemo?)?
    // 메모가 이미 있는 대상 → 메모 목록 (눌러서 고치기 / 새 메모 추가)
    @State private var memoListTarget: (kind: BlockedUser.Kind, value: String, nick: String)?
    // 차단 범위 고르기 (이 갤러리만 / 모든 갤러리)
    @State private var pendingBlock: (kind: BlockedUser.Kind, value: String, nick: String, label: String)?
    @State private var memoInput = ""

    // 키워드 차단 입력
    @State private var showKeywordPrompt = false
    @State private var idSearchTarget: IdSearchTarget?
    @State private var keywordInput = ""

    // 구조 진단
    @State private var diagnosticText: String?

    // 임시저장 불러오기
    @State private var showDraftPicker = false
    @State private var showListFilter = false
    @ObservedObject private var listFilter = ListFilterStore.shared

    // 키보드가 떠 있는 동안에는 앱 툴바를 숨겨서, 디시 댓글창(유동 닉/비번/코드, 디시콘 버튼)이
    // 사파리처럼 키보드 바로 위에 붙도록 함
    @State private var keyboardVisible = false
    /// 키보드가 화면 아래를 가린 높이 (앱 화면 전체는 키보드로 줄어들지 않고 화면 끝까지 쓰므로, 아래에 붙는 글쓰기 버튼만 이만큼 올림)
    @State private var keyboardCover: CGFloat = 0
    /// 웹페이지 위에 떠 있는 하단 바(+안내 배너) 높이 → 그만큼 페이지 아래에 스크롤 여백
    @State private var bottomBarHeight: CGFloat = 0
    /// 화면 오른쪽 안전 영역 폭 (듀오의 시계·카메라 줄 등) — 창(UIWindow)에서 직접 읽음
    @State private var trailingInset: CGFloat = 0
    /// 오른쪽 안전 영역이 버튼이 들어갈 만큼 넓은지 (듀오)
    /// 듀오 오른쪽 빈 줄에 컨트롤바를 넣던 방식은 쓰지 않음 (가끔 바가 사라짐) → 일반 아이폰처럼 하단 바
    private var hasSideColumn: Bool { false }
    /// 듀오처럼 오른쪽 안전 영역이 넓으면 웹페이지가 그 줄까지 씀
    private var fillsTrailing: Bool { trailingInset >= 56 }
    /// 듀오를 돌려서 시계·배터리 세로 줄이 왼쪽에 있는 상태
    private var leftColumn: Bool {
        _ = viewSize   // 화면 크기(회전)가 바뀌면 다시 계산
        // 웹 화면이 실제로 받은 안전 영역 (분할 화면에서 왼쪽에 놓인 앱은 창 값이 아니라 웹 화면 값에만 왼쪽 여백이 잡힘)
        if webInsets.left >= 56 && webInsets.right < 20 { return true }
        let ws = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { $0.windowLevel == .normal && !$0.isHidden }
        return (ws.map(\.safeAreaInsets.left).max() ?? 0) >= 56 && (ws.map(\.safeAreaInsets.right).max() ?? 0) < 20
    }
    /// 웹 화면(WKWebView)의 좌우 안전 영역 — 크기가 바뀔 때 다시 읽음
    @State private var webInsets: (left: CGFloat, right: CGFloat) = (0, 0)
    @State private var lastFlip = false
    /// 컨트롤바와 화면 가장자리 사이 간격: 듀오는 막대를 옆 세로 줄 안(가운데)에 놓음
    private var barEdge: CGFloat { (fillsTrailing && Self.hasSideColumnOnly && !barMirrored) ? max((trailingInset - 64) / 2, 4) : 12 }
    /// 듀오처럼 오른쪽에만 세로 줄(안전 영역)이 있는 상태 — 가로로 눕힌 일반 아이폰은 양쪽에 생김
    /// 듀오를 돌려 창 전체의 왼쪽에 세로 줄이 생긴 상태 (분할 화면에서 왼쪽에 놓인 앱은 창 자체의 줄이 없어 해당 없음)
    static var windowLeftColumn: Bool {
        let ws = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { $0.windowLevel == .normal && !$0.isHidden }
        return (ws.map(\.safeAreaInsets.left).max() ?? 0) >= 56 && (ws.map(\.safeAreaInsets.right).max() ?? 0) < 20
    }
    static var hasSideColumnOnly: Bool {
        let ws = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { $0.windowLevel == .normal && !$0.isHidden }
        let r = ws.map(\.safeAreaInsets.right).max() ?? 0, l = ws.map(\.safeAreaInsets.left).max() ?? 0
        return (r >= 56 && l < 20) || (l >= 56 && r < 20)   // 화면을 돌리면 세로 줄이 왼쪽에 생김
    }
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var showFooterEditor = false
    /// 길게 눌러 '원본 저장'을 골랐을 때 앨범을 물어보는 설정이면 그 요청을 들고 시트를 띄움
    @State private var albumAsk: BlockRequest?
    @Environment(\.verticalSizeClass) private var vSizeClass
    @AppStorage(ControlBarItem.verticalLandscapeKey, store: Profile.defaults) private var verticalInLandscape = true
    @AppStorage(ControlBarItem.autoHideKey, store: Profile.defaults) private var autoHideBar = true
    @AppStorage(ControlBarItem.autoHideStyleKey, store: Profile.defaults) private var autoHideStyle = ControlBarItem.autoHideStyleScrolling
    /// 컨트롤바를 화면 밖으로 넣었는지 — 방식 1: 스크롤하는 동안만 / 방식 2: 내리면 숨기고 올리면 표시
    /// 방식 2에서 댓글 영역에 닿으면 다시 나오는 건 '한 번 꺼내 주는' 동작(WebViewModel cmtview)이지 숨김 잠금이 아님
    /// (예전엔 댓글이 화면에 걸쳐 있는 동안 숨김을 통째로 막아서, 큰 화면·짧은 글에서는 영영 안 숨었음)
    private var barTucked: Bool {
        guard autoHideBar else { return false }
        let src = barScrollModel
        if autoHideStyle == ControlBarItem.autoHideStyleDirection { return src.barHiddenByDirection }
        return src.isScrolling
    }
    /// 숨길 때 화면 밖으로 빼는 거리: 막대가 화면 밖으로 완전히 나가도록 화면 폭(세로 막대)·바 높이(가로 막대)를 넘게
    private var sideTuckDistance: CGFloat { max(220, viewSize.width + 80) }
    private var bottomTuckDistance: CGFloat { max(160, bottomBarHeight + 80) }
    @AppStorage(ControlBarItem.verticalPortraitKey, store: Profile.defaults) private var verticalInPortrait = ControlBarItem.defaultVerticalInPortrait
    /// 화면(이 브라우저 영역) 크기 — 가로로 쓰는지 판단
    @State private var viewSize: CGSize = .zero
    private var isLandscape: Bool { viewSize.width > viewSize.height }
    /// 아이패드·듀오 펼친 화면 (가로·세로 모두 넓음) — 이때만 설정에서 고른 배치를 따름
    private var isLargeScreen: Bool { hSizeClass == .regular && vSizeClass == .regular }
    /// 컨트롤바를 오른쪽 세로 막대로 둘지 — 설정 → 컨트롤바에서 가로로 쓸 때 / 세로로 쓸 때 따로 선택 (모든 기기)
    private var usesSideBar: Bool {
        guard showsMenuButton else { return false }
        return isLandscape ? verticalInLandscape : verticalInPortrait
    }
    /// 휴대폰 가로 + 세로 막대: 높이가 낮아서 글자 없이 아이콘만 (막대를 짧게)
    private var compactSideBar: Bool { usesSideBar && !isLargeScreen && isLandscape }

    /// 오른쪽 빈 줄 폭을 다시 읽고, 메인 화면이면 앱 전체(RootView)에도 알려 줌 → 상단바가 빈 줄을 침범하지 않게 가림
    @State private var lastTopBarBottom: CGFloat = 0
    private func updateSideColumn(top: CGFloat) {
        syncCommentPin()
        // 화면을 돌린 뒤 웹 화면이 새 크기로 다시 그려지지 않고 비어 보이는 일이 있어, 크기가 바뀔 때마다 다시 배치하게 함
        model.nudgeLayout()
        let band = topBandBottom(measured: top)
        if model.isDetailPane, band > 20, abs(router.splitTopHeight - band) > 0.5 { router.splitTopHeight = band }
        lastTopBarBottom = band
        if !model.isDetailPane, band > 20 { ListBarMetrics.bottom = band }
        applySideColumn()
        // 접기·펴기·앱 전환 직후엔 안전 영역 값이 잠깐 0으로 읽힐 때가 있어서 조금 뒤에 한 번 더 읽음
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300)); applySideColumn()
            try? await Task.sleep(for: .milliseconds(700)); applySideColumn()
        }
    }
    /// 세로 컨트롤바가 웹 화면 위에 떠서 가리는 폭 (듀오 옆 세로 줄 안에 있으면 줄 여백이 이미 비워 주므로 0)
    private var barCoverWidth: CGFloat {
        guard usesSideBar, !barCollapsed, !(fillsTrailing && Self.hasSideColumnOnly) else { return 0 }
        return 64 + barEdge + 8
    }
    /// 앱 댓글 입력창(디시콘 목록 등)이 세로 컨트롤바에 겹치지 않게 비울 폭 (듀오 옆 세로 줄 안의 막대는 줄 폭만큼)
    private var composerBarInset: CGFloat {
        guard usesSideBar, !barCollapsed else { return 0 }
        return barCoverWidth     // 옆 세로 줄 안의 막대는 0 (줄 자리는 디시콘·글자콘 목록이 따로 비움)
    }
    /// 글 아래 수정·삭제 버튼 줄이 컨트롤바에 겹치지 않게 웹 화면에 비울 폭을 알림
    private func applyBarInset() {
        if showsMenuButton && !model.isDetailPane {
            if router.barOverlayWidth != barCoverWidth { router.barOverlayWidth = barCoverWidth }
            if router.barOverlayLeft != barMirrored { router.barOverlayLeft = barMirrored }
        }
        let detailW = router.barOverlayWidth > 0 ? router.barOverlayWidth : ((usesSideBar && !barCollapsed) ? barCoverWidth : 0)
        let w: CGFloat = model.isDetailPane ? detailW : ((showsMenuButton && !router.splitActive) ? barCoverWidth : 0)
        let left = model.isDetailPane ? router.barOverlayLeft : barMirrored
        model.setBarInset(left: left ? w : 0, right: left ? 0 : w)
    }
    @State private var lastDuoOff: Bool?
    private func applySideColumn() {
        settleCompact()
        let inset = Self.windowTrailingInset
        if inset != trailingInset { trailingInset = inset }
        let wi = model.webView.safeAreaInsets
        if wi.left != webInsets.left || wi.right != webInsets.right { webInsets = (wi.left, wi.right) }
        // 듀오를 반대 방향으로 돌려 세로 줄이 왼쪽↔오른쪽으로 바뀌면, 열려 있는 페이지의 글자 여백도 바로 뒤집음
        let flip = Self.windowLeftColumn
        if flip != lastFlip {
            lastFlip = flip
            model.setColumnFlip(flip)
        }
        applyBarInset()
        syncCommentPin()   // 컨트롤바 가로 ↔ 세로 전환 시 댓글 입력칸 아래 고정도 바로 따라감
        let duoOff = Self.duoHorizontalBarNow
        if duoOff != lastDuoOff { lastDuoOff = duoOff; model.applyFilters() }
        model.pushDuoFlags()   // 화면 자리(분할·회전)에 맞춰 이 화면의 옆 줄 여백을 다시 맞춤 (회전 뒤 늦게 정해지는 값도 300·700ms 뒤에 다시 읽음)
        guard showsMenuButton else { return }
        SideColumnLayout.shared.update(width: 0, topBarBottom: lastTopBarBottom)
    }

    /// 앱 화면이 그려지는 일반 창에서 읽음 (앱 잠금·가림 화면 같은 덧씌운 창은 제외 — 그쪽이 키 창이면 0이 나올 수 있음)
    static var windowTrailingInset: CGFloat {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel == .normal && !$0.isHidden }
        let r = windows.map(\.safeAreaInsets.right).max() ?? 0
        let l = windows.map(\.safeAreaInsets.left).max() ?? 0
        // 듀오를 돌려 창 전체의 왼쪽에 세로 줄이 생기면 → 오른쪽 줄처럼 다룸 (여백·컨트롤바를 오른쪽으로 뒤집어 씀)
        if l >= 56 && r < 20 { return l }
        return r
    }

    /// 이미 만들어진 브라우저(홈 탭의 메인 브라우저 등)를 화면에 붙일 때
    /// detailPane: 분할 화면의 오른쪽 글 화면 — 컨트롤바가 오른쪽에 있을 때 그 스크롤에 따라 숨김 (목록 화면에서 함께 구독해야 다시 그려짐)
    init(model: WebViewModel, fallbackTitle: String, showsMenuButton: Bool = false, splitListWidth: CGFloat? = nil, detailPane: WebViewModel? = nil) {
        _model = ObservedObject(wrappedValue: model)
        _detailPane = ObservedObject(wrappedValue: detailPane ?? model)
        self.fallbackTitle = fallbackTitle
        self.showsMenuButton = showsMenuButton
        self.splitListWidth = splitListWidth
    }

    /// 컨트롤바 숨김을 따르는 웹 화면: 분할 화면에서 컨트롤바가 오른쪽(글 쪽)에 있으면 글 화면, 왼쪽(목록 쪽, 좌우반전)이면 목록
    private var barScrollModel: WebViewModel { (splitListWidth != nil && !barMirrored) ? detailPane : model }

    private var filters: FilterStore { FilterStore.shared }

    private var currentGallery: (id: String, kind: GalleryKind)? {
        guard let url = model.url else { return nil }
        return Gallery.parse(url)
    }

    private var isFavorite: Bool {
        guard let g = currentGallery else { return false }
        return favorites.contains(galleryID: g.id, kind: g.kind)
    }

    /// 지금 갤러리 (이름 포함)
    private var gallery: Gallery? {
        guard let g = currentGallery, let url = model.url else { return nil }
        let name = favorites.items.first { $0.galleryID == g.id && $0.kind == g.kind }?.name
            ?? Gallery.guessName(title: model.title, url: url, id: g.id)
        return Gallery(galleryID: g.id, name: name, kind: g.kind)
    }

    /// 디시 모바일 첫 화면인지 (아직 아무 페이지도 안 열렸을 때 포함)
    private var isHomeScreen: Bool {
        guard let u = model.url else { return fallbackTitle == "홈" }
        return u.host == "m.dcinside.com" && (u.path.isEmpty || u.path == "/")
    }

    /// 상단바 제목: 갤러리 안이면 갤러리 이름, 아니면 페이지 제목
    private var titleText: String {
        // 분할 화면의 오른쪽(글) 화면: 갤러리 이름이 아니라 글 제목
        if model.isDetailPane {
            let t = Gallery.cleanTitle(model.title)
            return t.isEmpty ? fallbackTitle : t
        }
        if let g = gallery { return g.name }
        return model.title.isEmpty ? fallbackTitle : Gallery.cleanTitle(model.title)
    }

    /// 상단 갤러리 이름: '갤러리' 글자는 빼고, 마이너(Ⓜ)·미니(mi)·인물(사람) 표시를 따로
    private enum GalleryBadge { case minor, mini, person }
    private var titleParts: (name: String, badge: GalleryBadge?) {
        if model.isDetailPane { return (titleText, nil) }
        guard let g = gallery else { return (titleText, nil) }
        let raw = g.name
        let name = raw.replacingOccurrences(of: #"\s*(마이너|미니|인물)?\s*갤러리$"#, with: "", options: .regularExpression)
        let badge: GalleryBadge?
        switch g.kind {
        case .mini: badge = .mini
        case .person: badge = .person
        case .board: badge = (raw.contains("마이너 갤러리") || model.title.contains("마이너 갤러리")) ? .minor : nil
        }
        return (name.isEmpty ? raw : name, badge)
    }

    /// 분할 화면 왼쪽(목록) 상단바: 목록 폭 안에 제목(+글 목록이면 필터 버튼)
    /// 앱 창의 위쪽 안전 영역 높이 (듀오: 옆 세로 줄 때문에 비어 있는 위쪽 띠 높이)
    /// 창의 위쪽 안전 영역(상태바 높이). 웹 화면 상단바와 글쓰기 상단바가 같은 값을 씀
    static var windowTopInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { $0.windowLevel == .normal && !$0.isHidden }
            .map(\.safeAreaInsets.top).max() ?? 0
    }
    /// 위쪽 띠 안에 상단바를 그릴지 — 일반 휴대폰은 항상, 듀오는 옆 세로 줄이 있을 때만(90도 돌려 줄이 없으면 0.9.19(3)처럼 시스템 상단바). 글쓰기 화면은 자기 상단바가 따로 있음
    private var compactRaw: Bool {
        _ = viewSize      // 접기·펴기·회전으로 크기가 바뀌면 다시 계산
        return compactTopBarSetting && (Self.isDuoSizedScreen ? Self.hasSideColumnOnly : Self.isPhone) && !model.isWritePage
    }
    /// 돌리는 도중 안전 영역 값이 잠깐 흔들려도 시스템 상단바가 켜졌다 꺼지지 않게: 값이 0.6초 동안 그대로일 때만 바꿈
    @State private var compactStable: Bool?
    private var compactTopBar: Bool { compactStable ?? compactRaw }
    private func settleCompact() {
        let raw = compactRaw
        guard raw != compactStable else { return }
        if compactStable == nil { compactStable = raw; return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if compactRaw == raw { compactStable = raw }
        }
    }

    /// 상단바 띠 높이 (휴대폰·듀오 공통). 시스템 내비게이션 바(세로 화면 44pt, 가로로 눕힌 휴대폰 32pt)보다 낮거나 같게
    static let compactTopBarHeight: CGFloat = 34
    /// 듀오 띠 높이 (0.9.19와 같은 44pt)
    static let duoTopBarHeight: CGFloat = 44
    /// 창이 가로(너비 > 높이)인지 — 창 크기로 판별 (분할 화면의 왼쪽 목록은 뷰 폭이 좁아 뷰 크기로는 틀릴 수 있음)
    static var windowIsLandscape: Bool {
        let ws = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { $0.windowLevel == .normal && !$0.isHidden }
        guard let b = (ws.first(where: \.isKeyWindow) ?? ws.first)?.bounds else { return false }
        return b.width > b.height
    }
    /// 가로(회전)에서는 띠를 상태바 줄(시계·배터리가 있는 맨 위 줄)에 올림: 띠 높이 = 상태바 높이, 상태바가 32pt보다 낮으면 32pt
    /// 세로: 듀오 68pt, 일반 폰 34pt (변경 없음)
    private var compactBarHeight: CGFloat {
        if Self.isDuoLayout { return Self.duoTopBarHeight }
        if Self.windowIsLandscape { return max(Self.windowTopInset, 32) }
        if vSizeClass == .compact { return 32 }
        return Self.compactTopBarHeight
    }
    /// 띠가 상태바 줄부터 그려지는지 (가로에서 띠를 쓰는 동안)
    private var barInStatusRow: Bool { compactTopBar && Self.windowIsLandscape && !Self.isDuoLayout }
    /// 가로 일반 휴대폰(듀오 같은 큰 화면 제외)에서 시스템 상태바가 안 보이므로 띠 양끝에 시계·배터리를 직접 넣음
    private var bandShowsClock: Bool { barInStatusRow && Self.isPhone && !Self.isDuoSizedScreen }
    /// 띠 양끝 시계·배터리 칸 폭 (양쪽 같게 넣어 제목이 가운데 오게)
    static let bandSideItemWidth: CGFloat = 64
    /// 듀오 레이아웃 (옆 세로 줄 + 큰 화면). 이 경우 상단바는 0.9.19 값(44pt)과 동작을 그대로 씀
    static var isDuoLayout: Bool { hasSideColumnOnly && isDuoSizedScreen }
    /// 듀오 같은 큰 폰 화면인지 (가장 짧은 변 450pt 초과). 가로·세로 모두 판별
    static var isDuoSizedScreen: Bool {
        let b = UIScreen.main.bounds
        return UIDevice.current.userInterfaceIdiom == .phone && min(b.width, b.height) > 450
    }
    /// 위쪽 띠 아래 끝의 화면 y: 상태바 줄에 올린 띠는 띠 높이 그대로, 아니면 띠를 쓰는 동안 상태바 + 띠 높이, 그 밖은 측정값
    /// (시트 높이·글쓰기 상단 높이·듀오 측면 덮개가 이 값을 씀)
    private func topBandBottom(measured top: CGFloat) -> CGFloat {
        if Self.isDuoLayout { return top }
        if barInStatusRow { return compactBarHeight }
        return compactTopBar ? Self.windowTopInset + compactBarHeight : top
    }
    /// 누르는 칸 한 변 (손가락 목표 44pt). 띠보다 커서 위아래로 조금 삐져나가고, 그만큼도 눌림
    static let compactTouchSize: CGFloat = 44
    /// 휴대폰(듀오 포함). 아이패드는 시스템 상단바를 그대로 씀
    static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    /// 듀오에서 컨트롤바를 가로(하단 바)로 쓰는 중인지 — 이때 웹 화면은 좌우 안전 영역을 무시하고 화면 끝까지 씀 (시계·배터리와 겹치는 것은 감수)
    static var duoHorizontalBarNow: Bool {
        guard isDuoSizedScreen else { return false }
        let landscape = windowIsLandscape
        let key = landscape ? ControlBarItem.verticalLandscapeKey : ControlBarItem.verticalPortraitKey
        let vertical = Profile.defaults.object(forKey: key) as? Bool ?? (landscape ? true : ControlBarItem.defaultVerticalInPortrait)
        return !vertical
    }
    /// 창의 좌우 안전 영역 중 큰 값 (휴대폰을 가로로 눕히면 노치 쪽 여백)
    static var windowSideInsetMax: CGFloat {
        let ws = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { $0.windowLevel == .normal && !$0.isHidden }
        return max(ws.map(\.safeAreaInsets.left).max() ?? 0, ws.map(\.safeAreaInsets.right).max() ?? 0)
    }
    /// 오른쪽에 놓이는 버튼 수 (제목을 가운데에 두려고 왼쪽 칸도 같은 폭으로 맞춤)
    private var compactRightCount: Int {
        if showsMenuButton { return (showsListFilterInBar ? 1 : 0) + (menuInTopBarShown ? 1 : 0) }
        return (currentGallery != nil ? 1 : 0) + 1
    }
    private var compactSideWidth: CGFloat {
        let n = max(compactRightCount, 1)
        return CGFloat(n) * Self.compactTouchSize + CGFloat(n - 1) * Self.topSlotSpacing
    }
    /// 띠 좌우 여백: 듀오는 옆 세로 줄 폭(기존 계산 그대로), 그 밖의 휴대폰은 가로로 눕혔을 때 노치 쪽 여백
    private var compactSidePad: (leading: CGFloat, trailing: CGFloat) {
        if Self.isDuoLayout {
            return (splitListWidth == nil && leftColumn ? trailingInset : 0,
                    splitListWidth == nil && !leftColumn && fillsTrailing ? trailingInset : 0)
        }
        let s = Self.windowSideInsetMax
        return (s, s)
    }
    /// 위쪽 띠: [뒤로] 제목 [필터·⋮ / 즐겨찾기·⋮]. 시스템 상단바의 버튼과 같은 기능
    private var compactTopBarView: some View {
        // 듀오는 0.9.19(3)과 같은 칸 크기(28pt)·간격(6pt)·로고(36pt)를 씀. 휴대폰은 낮은 띠라 칸을 44pt로 둠
        let duo = Self.isDuoLayout
        let slot: CGFloat = duo ? Self.topSlotWidth : Self.compactTouchSize
        let logo: CGFloat = compactBarHeight >= 40 ? 36 : 24
        let side = compactSideWidth
        let pad = compactSidePad
        return HStack(spacing: duo ? 6 : 0) {
            if bandShowsClock { BandClockText().frame(width: Self.bandSideItemWidth, alignment: .leading) }
            if showsTopBack {
                backButton { Image(systemName: "arrow.left").frame(width: slot, height: slot).contentShape(Rectangle()) }
                    .frame(width: duo ? Self.topSlotWidth : side, alignment: .leading)
            } else {
                Color.clear.frame(width: duo ? Self.topSlotWidth : side, height: duo ? Self.topSlotWidth : 1)
            }
            titleView(logo: logo).frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: duo ? 6 : Self.topSlotSpacing) {
                if showsMenuButton {
                    if showsListFilterInBar {
                        Button { showListFilter = true } label: {
                            Image(systemName: listFilter.filter.activeIn(model.galleryFilterKey) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .frame(width: slot, height: slot)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("게시물 필터")
                    }
                    if menuInTopBarShown {
                        MorePopoverButton { close in morePopover(dismiss: close) } label: {
                            Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                                .frame(width: slot, height: slot)
                                .contentShape(Rectangle())
                        }
                    }
                } else if !model.isDetailPane {
                    if currentGallery != nil {
                        Button { toggleFavorite() } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .frame(width: slot, height: slot)
                                .contentShape(Rectangle())
                        }
                    }
                    MorePopoverButton { close in morePopover(dismiss: close) } label: {
                        Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                            .frame(width: slot, height: slot)
                            .contentShape(Rectangle())
                    }
                }
            }
            .buttonStyle(.plain)
            .fixedSize()
            .frame(minWidth: duo ? Self.topSlotWidth : side, alignment: .trailing)
            if bandShowsClock { BandBatteryText().frame(width: Self.bandSideItemWidth, alignment: .trailing) }
        }
        .foregroundStyle(.white)
        .padding(.leading, 10 + pad.leading)
        .padding(.trailing, 10 + pad.trailing)
        .frame(width: splitListWidth, height: compactBarHeight)
        .background(DCTheme.navy)
        // 가로: 띠를 맨 위(상태바 줄)로 올림. 레이아웃에서는 상태바 아래 띠 높이 - 상태바 높이만 차지해 웹 화면이 띠 아래 끝에서 시작
        .offset(y: barInStatusRow ? -Self.windowTopInset : 0)
        .frame(height: barInStatusRow ? compactBarHeight - Self.windowTopInset : compactBarHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var splitTopBar: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: Self.topSlotWidth, height: Self.topSlotWidth)
            topTitle.frame(maxWidth: .infinity, alignment: .center)
            if showsListFilterInBar {
                Button { showListFilter = true } label: {
                    Image(systemName: listFilter.filter.activeIn(model.galleryFilterKey) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .frame(width: Self.topSlotWidth, height: Self.topSlotWidth)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("게시물 필터")
            } else {
                Color.clear.frame(width: Self.topSlotWidth, height: Self.topSlotWidth)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(width: splitListWidth ?? 0, height: max(router.splitTopHeight, 44))   // 오른쪽 글 화면 상단바와 같은 높이
        .background(DCTheme.navy)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func badgeView(_ b: GalleryBadge) -> some View {
        switch b {
        case .minor:
            Text("M").font(fonts.uiFont(size: 12, weight: .bold))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
        case .mini:
            Text("mi").font(fonts.uiFont(size: 11, weight: .bold))
                .frame(width: 22, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 1.5))
        case .person:
            Image(systemName: "person.fill").font(.system(size: 15, weight: .semibold))
        }
    }

    /// 디시 첫 화면인지 (하단 바 홈 강조용)
    private var isDCHome: Bool {
        guard let url = model.url, url.host == "m.dcinside.com" else { return false }
        return url.path.isEmpty || url.path == "/"
    }

    /// 하단 바에서 지금 선택된 칸
    private var section: GallerySection {
        guard let url = model.url else { return .home }
        if AutoImageStore.writeGalleryID(from: url) != nil { return .write }
        let q = url.query ?? ""
        if q.contains("recommend=1") { return .recommend }
        if q.contains("notice=") { return .notice }
        if q.contains("serval=") || q.contains("s_keyword=") { return .search }
        return .home
    }

    // body를 여러 조각으로 나눔 (한 덩어리면 컴파일러가 타입 계산을 못 함)
    var body: some View { layer8 }

    /// 가장 위 층: 알림(토스트). 댓글 입력창·가림막보다 위에 그려서 떠 있어도 보이게
    private var layer8: some View {
        AnyView(layer7).overlay { ToastOverlay(model: model) }
    }

    /// 웹뷰 + 상단바 + 하단 바 + 키보드 감지
    private var layer1: some View {
        WebView(model: model)
            .overlay {
                if model.isRateLimited {
                    RateLimitOverlayView(tries: model.rateLimitTries) { model.reload() }
                }
            }
            .modifier(SplitPane(width: splitListWidth))
            // 로딩 게이지(topOverlay)는 상단바 안쪽에 붙여서, 상단바 제일 아래(웹뷰 맨 위)에 나오게 함
            .overlay(alignment: .top) { topOverlay }
            .safeAreaInset(edge: .top, spacing: 0) { if compactTopBar { compactTopBarView } else if splitListWidth != nil { splitTopBar } }   // 듀오: 낮은 상단바 / 분할 화면의 목록: 시스템 내비게이션 바 대신
            .ignoresSafeArea(.keyboard, edges: .bottom)   // 키보드 처리는 웹뷰(WebKit)에 맡김
            // 하단 바 뒤 화면 아래 끝까지 웹페이지가 쓰도록. 좌우 안전 영역(듀오의 시계·카메라 줄)은 사파리처럼 비워 둠
            // 화면을 돌려 세로 줄이 왼쪽에 생기면(듀오) 왼쪽도 같은 방식으로 웹페이지가 줄 아래까지 깔리게 (파란 상단바만 튀어나와 보이지 않게)
            .ignoresSafeArea(.container, edges: UIDevice.current.userInterfaceIdiom == .phone ? [.bottom, .leading, .trailing]   // 폰(가로 포함): 안전 영역 없이 화면 끝까지
                                                : (fillsTrailing ? (leftColumn ? [.bottom, .leading, .trailing] : [.bottom, .trailing]) : (leftColumn ? [.bottom, .leading] : .bottom)))
            // 상단바 뒤~화면 맨 위까지 남색으로 (듀오를 펼치면 상단바 위에 띠가 생기고, 내비게이션 화면의 기본 흰 배경이 보임)
            // 웹페이지 뒤에 깔리므로 다른 곳에는 안 보임
            // 웹페이지 위쪽(상단바 뒤 ~ 화면 맨 위)만 남색으로, 오른쪽 빈 줄(듀오)의 위쪽까지 포함.
            // 웹페이지 위쪽 안전 영역 높이(상단바+그 위 띠)를 재서 그만큼만 위로 그림 → 상단바 아래 빈 줄은 칠하지 않음
            .background {
                GeometryReader { g in
                    let top = g.safeAreaInsets.top
                    DCTheme.navy
                        .frame(width: g.size.width + g.safeAreaInsets.leading + g.safeAreaInsets.trailing, height: top + 1)   // 듀오 옆 세로 줄 위쪽까지
                        .offset(x: -g.safeAreaInsets.leading, y: -top)
                }
            }
            .background {
                // 예비: 웹페이지 폭만큼은 화면 맨 위까지 (위 방법이 안 먹히는 경우 대비)
                // 분할 화면: 오른쪽 컨트롤바 띠는 남색이 아니라 글 화면과 어울리는 바탕색으로 (상단바는 따로 남색)
                if splitListWidth == nil {
                    DCTheme.navy.ignoresSafeArea(.container, edges: [.top, .trailing])
                }
            }
            .overlay {
                // 화면 크기가 바뀔 때마다(접기·펴기·회전) 오른쪽 안전 영역 폭을 다시 읽음
                GeometryReader { g in
                    Color.clear
                        .onAppear { viewSize = g.size; updateSideColumn(top: g.frame(in: .global).minY) }
                        .onChangeCompat(of: g.size) { _, sz in viewSize = sz; updateSideColumn(top: g.frame(in: .global).minY) }
                        .onChangeCompat(of: g.frame(in: .global).minY) { _, y in updateSideColumn(top: y) }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                            updateSideColumn(top: g.frame(in: .global).minY)
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                            updateSideColumn(top: g.frame(in: .global).minY)
                        }
                }
                .allowsHitTesting(false)
            }
            // 글쓰기: 키보드가 올라와 있으면 키보드 바로 위 왼쪽에 < > (제목 ⇄ 내용), 오른쪽에 '등록'
            .overlay(alignment: .bottomLeading) {
                if showsMenuButton && model.isWritePage && keyboardVisible {
                    HStack(spacing: 0) {
                        Button { model.moveWriteFocus(forward: false) } label: {
                            Image(systemName: "chevron.left").frame(width: 58, height: 46).contentShape(Rectangle())
                        }
                        Divider().frame(height: 26)
                        Button { model.moveWriteFocus(forward: true) } label: {
                            Image(systemName: "chevron.right").frame(width: 58, height: 46).contentShape(Rectangle())
                        }
                    }
                    .font(fonts.uiFont(size: 20, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .buttonStyle(.plain)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .padding(.leading, 12)
                    .padding(.bottom, 8 + model.writeToolbarHeight + keyboardCover)     // 키보드 위 글쓰기 도구줄 위로
                    .animation(.easeOut(duration: 0.15), value: model.writeToolbarHeight)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsMenuButton && model.isWritePage && keyboardVisible {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        model.submitWrite()
                    } label: {
                        Text("등록")
                            .font(fonts.styleFont(.subheadline, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(DCTheme.navy, in: Capsule())
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8 + keyboardCover)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if usesSideBar {
                        if !keyboardVisible {
                            if barCollapsed {
                                collapsedSideButton
                                // 접힌 동안에도 펼친 막대의 높이를 재 둠 — 처음부터 접혀 있거나 회전 직후 높이를 모르면 접은 버튼이 아래 구석으로 떨어짐
                                sideBar.opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                            } else { sideBar }
                        }
                    } else if collapsedInColumn && !keyboardVisible {
                        collapsedColumnButton      // 듀오: 가로 막대를 접은 버튼도 세로 막대를 접었을 때처럼 옆 세로 줄 한가운데
                    } else if showsMenuButton && showsRefresh && !keyboardVisible && !barCollapsed && !Self.duoHorizontalBarNow {
                        refreshButtonPlaced        // 글 볼 때: 댓글 새로고침 / 글 목록: 페이지 새로고침 (듀오 가로 바에서는 바 안의 새로고침을 씀)
                    }
                }
                // 스크롤하는 동안 오른쪽(좌우반전이면 왼쪽) 밖으로 들어갔다가 멈추면 다시 나옴 (숨겨진 동안은 터치도 받지 않음)
                .offset(x: barTucked ? (barMirrored ? -sideTuckDistance : sideTuckDistance) : 0)
                .opacity(barTucked ? 0 : 1)      // 화면 밖으로 다 못 나가는 경우(접힌 버튼·유리 그림자 등)에도 확실히 안 보이게
                .animation(.easeOut(duration: 0.2), value: barTucked)
                .allowsHitTesting(!barTucked)
                .ignoresSafeArea(.container, edges: ((UIDevice.current.userInterfaceIdiom == .phone && !Self.hasSideColumnOnly) || Self.duoHorizontalBarNow) ? [.leading, .trailing]   // 일반 폰은 가로여도 컨트롤바를 화면 가장자리 기준으로 (듀오 가로 바도 양끝까지)
                                                : (fillsTrailing && Self.hasSideColumnOnly && !barMirrored ? .trailing : []))   // 듀오: 컨트롤바를 옆 세로 줄 자리로
            }
            // 듀오는 제목을 왼쪽 칸에 직접 그림 → 시스템 제목까지 있으면 펼쳤을 때 이름이 두 번 나옴
            .navigationTitle(splitListWidth != nil || (duoTopBar && !model.isDetailPane && !(showsMenuButton && model.isWritePage)) ? "" : titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                topBar   // 로딩 스피너는 제목 옆(titleView overlay) 한 곳에만 그림 — 오른쪽 리퀴드 글래스 원의 중복 스피너는 제거
            }
            .toolbar(compactTopBar ? .hidden : .automatic, for: .navigationBar)      // 휴대폰·듀오: 시스템 상단바는 숨기고 위쪽 띠에 직접 그림 (스크롤해도 고정)
            .keepsTopStatusBar()   // 듀오: 시계·버튼을 오른쪽 세로 줄로 보내지 않고 위쪽 가로로
            .toolbarBackground(DCTheme.navy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            // 하단 바: 페이지를 잘라내지 않고 그 위에 띄움 (리퀴드 글래스 너머로 페이지가 비침)
            .overlay(alignment: .bottom) {
                if !keyboardVisible {
                    VStack(spacing: 0) {
                        modeBanner
                        if showsMenuButton && !usesSideBar {
                            Group { if barCollapsed { if !collapsedInColumn { collapsedBarButton } } else { galleryBar } }
                                // 스크롤하는 동안 화면 아래로 들어갔다가 멈추면 다시 나옴 (바 높이를 재서 그만큼 내림)
                                .offset(y: barTucked ? bottomTuckDistance : 0)
                                .opacity(barTucked ? 0 : 1)
                                .animation(.easeOut(duration: 0.2), value: barTucked)
                                .allowsHitTesting(!barTucked)
                        }
                    }
                    .background {
                        GeometryReader { g in
                            Color.clear
                                .onAppear { bottomBarHeight = g.size.height }
                                .onChangeCompat(of: g.size.height) { _, h in bottomBarHeight = h }
                        }
                    }
                    // 듀오 가로 바: 안전 영역 안에 갇히지 않게 좌우 끝까지 (아래에서 바 양옆에 12pt 여백)
                    .ignoresSafeArea(.container, edges: Self.duoHorizontalBarNow ? [.leading, .trailing] : [])
                    .modifier(SplitBottom(listWidth: splitListWidth, totalWidth: viewSize.width, mirrored: barMirrored))
                    .transition(.opacity)
                }
            }
            .onChangeCompat(of: bottomBarHeight) { _, _ in updateBottomInset() }
            .onChangeCompat(of: keyboardVisible) { _, _ in updateBottomInset() }
            // 키보드가 정말 화면에 올라와 있는지는 키보드 위치로 판단 (화면을 돌릴 때 오는 알림만 보고 바를 숨기지 않게)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { n in
                keyboardFrameChanged(n)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
                keyboardFrameChanged(n)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                setKeyboardVisible(false)
                withAnimation(.easeOut(duration: 0.2)) { keyboardCover = 0 }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                setKeyboardVisible(false)
                keyboardCover = 0
            }
            // 길게 누르기 → 차단 메뉴
    }

    private func setKeyboardVisible(_ v: Bool) {
        guard keyboardVisible != v else { return }
        withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = v }
    }

    /// 키보드 알림의 끝 위치가 화면 안에 충분히(80pt 이상) 올라와 있을 때만 '키보드 떠 있음'
    private func keyboardFrameChanged(_ n: Notification) {
        guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let screen = (n.object as? UIScreen)?.bounds
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?.screen.bounds
            ?? .zero
        let overlap = end.intersection(screen)
        setKeyboardVisible(!overlap.isNull && overlap.height > 80)
        withAnimation(.easeOut(duration: 0.2)) { keyboardCover = (!overlap.isNull && overlap.height > 80) ? overlap.height : 0 }
    }

    /// 차단 메뉴 / 요소 숨기기 확인
    private var layer2: some View {
        // 뷰 타입이 너무 깊게 중첩되면 실행하자마자 스택이 넘쳐 튕김 → 단계마다 AnyView로 끊음
        AnyView(layer1)
            .confirmationDialog(model.blockRequest.map { blockDialogTitle($0) } ?? "차단/메모/갤로그",
                                isPresented: Binding(get: { model.blockRequest != nil },
                                                     set: { if !$0 { model.blockRequest = nil } }),
                                titleVisibility: .visible,
                                presenting: model.blockRequest) { req in
                blockButtons(req)
            } message: { req in
                if !req.imgKey.isEmpty {
                    Text(filters.isImageBlocked(key: req.imgKey) ? "이 사진을 저장하거나 차단을 풀까요?" : "이 사진을 저장하거나 가릴까요?")
                } else {
                    Text(req.snippet.isEmpty ? (isAlreadyBlocked(req) ? "차단을 풀까요?" : "무엇을 차단할까요?") : req.snippet)
                }
            }
            .sheet(item: $albumAsk) { req in
                NavigationStack {
                    PhotoAlbumPicker(title: "어디에 저장할까요?", selectedID: PhotoSaver.defaultAlbumID) { id in
                        albumAsk = nil
                        savePhotoOriginal(req, albumID: id)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("취소") { albumAsk = nil } }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .background {
                // 요소 숨기기 확인 (다이얼로그끼리 겹치지 않게 별도 레이어에 부착)
                Color.clear
                    .confirmationDialog("이 부분을 숨길까요?",
                                        isPresented: Binding(get: { model.pickRequest != nil },
                                                             set: { if !$0 { model.pickRequest = nil } }),
                                        titleVisibility: .visible,
                                        presenting: model.pickRequest) { req in
                        Button("숨기기", role: .destructive) {
                            filters.addHidden(selector: req.selector, memo: req.snippet)
                            model.clearPick()
                        }
                        Button("더 넓게 선택") { model.pickParent() }
                        Button("취소", role: .cancel) { model.clearPick() }
                    } message: { req in
                        Text("\(req.snippet.isEmpty ? "(내용 없음)" : req.snippet)\n같은 모양의 요소 \(req.count)개가 숨겨져요.")
                    }
                    .sheet(isPresented: $showFooterEditor) {
                        FooterQuickSheet(account: footerAccountKey, gallery: footerGalleryID ?? FooterRule.all)
                            .sheetUnderBlueBar(medium: true)
                    }
                    .confirmationDialog("댓글 링크",
                                        isPresented: Binding(get: { model.commentLink != nil },
                                                             set: { if !$0 { model.commentLink = nil } }),
                                        titleVisibility: .visible,
                                        presenting: model.commentLink) { url in
                        Button("대댓글 달기") { model.replyToPendingComment() }
                        Button("링크로 이동") { model.commentLink = nil; model.load(url) }
                        Button("취소", role: .cancel) { model.commentLink = nil }
                    } message: { url in
                        Text(url.absoluteString)
                    }
            }
    }

    /// 토스트 / 키워드·유저 차단 입력
    private var layer3: some View {
        // 뷰 타입이 너무 깊게 중첩되면 실행하자마자 스택이 넘쳐 튕김 → 단계마다 AnyView로 끊음
        // (알림은 가장 위 층 layer8에서 그림 — 댓글 입력창에 가려지지 않게)
        AnyView(layer2)
            // 진단용: 화면이 컨트롤바를 숨겨야 한다고 본 순간을 모델에 남김 (페이지 구조 진단의 '컨트롤바 숨김' 줄)
            .onChangeCompat(of: barTucked) { _, v in
                model.noteViewTucked(v)
                if barScrollModel !== model { barScrollModel.noteViewTucked(v) }
            }
            .alert("키워드 차단", isPresented: $showKeywordPrompt) {
                TextField("차단할 단어 (쉼표로 여러 개)", text: $keywordInput)
                Button("취소", role: .cancel) {}
                if let g = currentGallery?.id {
                    Button("이 갤러리에서만") {
                        filters.addKeyword(keywordInput, gallery: g)
                        if !keywordInput.trimmingCharacters(in: .whitespaces).isEmpty {
                            model.showToast("'\(keywordInput)' 키워드 차단 (이 갤러리)")
                        }
                    }
                }
                Button("모든 갤러리") {
                    filters.addKeyword(keywordInput)
                    if !keywordInput.trimmingCharacters(in: .whitespaces).isEmpty {
                        model.showToast("'\(keywordInput)' 키워드 차단 (모든 갤러리)")
                    }
                }
            } message: {
                Text("이 단어가 들어간 글과 댓글을 가려요. 쉼표로 여러 단어를 넣으면 모두 들어간 글·댓글만 가려요.")
            }
            .alert("유저 차단", isPresented: $showUserPrompt) {
                TextField("아이디, IP 또는 닉네임", text: $userInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("아이디로 차단") { blockTyped(.id) }
                Button("IP로 차단") { blockTyped(.ip) }
                Button("닉네임으로 차단") { blockTyped(.nick) }
                Button("취소", role: .cancel) {}
            } message: {
                Text("유동은 IP 앞 두 자리(예: 118.235)를 입력하세요.")
            }
    }

    private func saveMemo(gallery: String?) {
        guard let t = memoTarget else { return }
        let empty = memoInput.trimmingCharacters(in: .whitespaces).isEmpty
        if let old = t.existing {
            MemoStore.shared.update(old, text: memoInput, gallery: gallery)
            model.showToast(empty ? "메모를 지웠어요" : (gallery == nil ? "메모를 고쳤어요 (모든 갤러리)" : "메모를 고쳤어요 (이 갤러리)"))
        } else {
            guard !empty else { return }
            MemoStore.shared.add(kind: t.kind, value: t.value, text: memoInput, gallery: gallery)
            model.showToast(gallery == nil ? "메모를 남겼어요 (모든 갤러리)" : "메모를 남겼어요 (이 갤러리)")
        }
    }

    /// 캡처 / 보관 폴더 고르기 / 유저 메모 / 차단 범위
    private var layer4: some View {
        // 뷰 타입이 너무 깊게 중첩되면 실행하자마자 스택이 넘쳐 튕김 → 단계마다 AnyView로 끊음
        AnyView(layer3)
            .confirmationDialog("어디서 가릴까요?",
                                isPresented: Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } }),
                                titleVisibility: .visible) {
                if let b = pendingBlock {
                    Button("이 갤러리(\(gallery?.name ?? currentGallery?.id ?? ""))에서만", role: .destructive) {
                        filters.addUser(kind: b.kind, value: b.value, memo: b.nick, gallery: currentGallery?.id)
                        model.showToast("\(b.label) 차단했어요 (이 갤러리)")
                    }
                    Button("모든 갤러리에서", role: .destructive) {
                        filters.addUser(kind: b.kind, value: b.value, memo: b.nick)
                        model.showToast("\(b.label) 차단했어요 (모든 갤러리)")
                    }
                }
                Button("취소", role: .cancel) {}
            }
            .alert(memoTarget?.existing == nil ? "유저 메모" : "메모 고치기",
                   isPresented: Binding(get: { memoTarget != nil }, set: { if !$0 { memoTarget = nil } })) {
                TextField(memoTarget?.existing == nil ? "메모" : "메모 (비우면 삭제)", text: $memoInput)
                if let gid = currentGallery?.id {
                    Button("이 갤러리에만 저장") { saveMemo(gallery: gid) }
                }
                Button(currentGallery == nil ? "저장" : "모든 갤러리에 저장") { saveMemo(gallery: nil) }
                Button("취소", role: .cancel) {}
            } message: {
                if let t = memoTarget {
                    Text("\(t.nick.isEmpty ? "" : t.nick + " · ")\(t.kind.label) \(t.value)\n닉네임 옆에 보여요.")
                }
            }
            .sheet(item: $model.captured) { CapturePreview(capture: $0) }
            .confirmationDialog("어느 폴더에 보관할까요?", isPresented: $showSaveFolderPicker, titleVisibility: .visible) {
                Button("분류 없음") { Task { await model.savePost(folderID: nil, keepFolder: false) } }
                ForEach(savedPosts.folders) { f in
                    Button("📁 \(f.name)") { Task { await model.savePost(folderID: f.id, keepFolder: false) } }
                }
                Button("＋ 새 폴더 만들기") { newFolderFor = nil; newFolderName = ""; showNewFolder = true }
                Button("취소", role: .cancel) {}
            }
            .alert("새 폴더", isPresented: $showNewFolder) {
                TextField("폴더 이름", text: $newFolderName)
                Button("취소", role: .cancel) {}
                Button("만들기") {
                    guard let id = savedPosts.addFolder(newFolderName) else { return }
                    if let post = newFolderFor {
                        savedPosts.move(post, to: id)
                        model.showToast("\(savedPosts.folderName(id))(으)로 옮겼어요")
                    } else {
                        Task { await model.savePost(folderID: id, keepFolder: false) }
                    }
                }
            } message: { Text("만든 폴더에 바로 넣어요") }
    }

    /// 보관한 글 메뉴
    private var layer5: some View {
        // 뷰 타입이 너무 깊게 중첩되면 실행하자마자 스택이 넘쳐 튕김 → 단계마다 AnyView로 끊음
        AnyView(layer4)
            // 컨트롤바 '메모하기'로 고른 작성자 → 메모 남기기
            .background {
                Color.clear
                    .confirmationDialog("유저 메모",
                                        isPresented: Binding(get: { model.memoRequest != nil },
                                                             set: { if !$0 { model.memoRequest = nil } }),
                                        titleVisibility: .visible,
                                        presenting: model.memoRequest) { req in
                        memoButton(req)
                        Button("취소", role: .cancel) {}
                    } message: { req in
                        Text(req.nick.isEmpty ? "작성자" : req.nick)
                    }
            }
            // 메모가 이미 있는 대상 → 메모 목록 (눌러서 고치기 / 새 메모 추가)
            .background {
                Color.clear
                    .confirmationDialog("유저 메모",
                                        isPresented: Binding(get: { memoListTarget != nil },
                                                             set: { if !$0 { memoListTarget = nil } }),
                                        titleVisibility: .visible,
                                        presenting: memoListTarget) { t in
                        ForEach(MemoStore.shared.memos(kind: t.kind, value: t.value, gallery: currentGallery?.id)) { m in
                            Button((m.gallery == nil ? "" : "[이 갤러리] ") + m.text) {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(450))
                                    openMemoEditor(t.kind, t.value, t.nick, existing: m)
                                }
                            }
                        }
                        Button("＋ 새 메모 추가…") {
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(450))
                                openMemoEditor(t.kind, t.value, t.nick, existing: nil)
                            }
                        }
                        Button("취소", role: .cancel) {}
                    } message: { t in
                        Text("\(t.nick.isEmpty ? "" : t.nick + " · ")\(t.kind.label) \(t.value)\n고칠 메모를 누르세요 (비우고 저장하면 삭제)")
                    }
            }
            .onReceive(NotificationCenter.default.publisher(for: DC.credentialsChanged)) { _ in
                currentAccount = CredentialStore.currentAccountID
            }
            .background {
                Color.clear
                    .confirmationDialog("보관한 글이에요",
                                        isPresented: Binding(get: { savedPostMenu != nil },
                                                             set: { if !$0 { savedPostMenu = nil } }),
                                        titleVisibility: .visible,
                                        presenting: savedPostMenu) { post in
                        Button("최신 내용으로 다시 저장") { Task { await model.savePost() } }
                        if post.folderID != nil {
                            Button("분류 없음으로 옮기기") {
                                savedPosts.move(post, to: nil)
                                model.showToast("분류 없음으로 옮겼어요")
                            }
                        }
                        ForEach(savedPosts.folders.filter { $0.id != post.folderID }) { f in
                            Button("📁 \(f.name)(으)로 옮기기") {
                                savedPosts.move(post, to: f.id)
                                model.showToast("\(f.name)(으)로 옮겼어요")
                            }
                        }
                        Button("＋ 새 폴더로 옮기기") { newFolderFor = post; newFolderName = ""; showNewFolder = true }
                        Button("보관함에서 빼기", role: .destructive) {
                            savedPosts.remove(post)
                            model.showToast("보관함에서 뺐어요")
                        }
                        Button("취소", role: .cancel) {}
                    } message: { post in
                        Text("지금 폴더: \(savedPosts.folderName(post.folderID))")
                    }
            }
    }

    /// 갤러리 검색 / 임시저장 / 진단
    private var layer6: some View {
        // 뷰 타입이 너무 깊게 중첩되면 실행하자마자 스택이 넘쳐 튕김 → 단계마다 AnyView로 끊음
        AnyView(layer5)
            .sheet(isPresented: $showGallerySearch) {
                if let g = gallery {
                    GallerySearchSheet(gallery: g, heads: galleryHeads, onSearch: { url in model.load(url) })
                }
            }
            .sheet(isPresented: $showListFilter) {
                ListFilterSheet(headNames: model.headNames, gallery: model.galleryFilterKey) { model.applyListFilter() }
                    .sheetUnderBlueBar(medium: true)
            }
            // 나무위키 검색어 입력 → 확인하면 입력 시트를 닫고 인앱 사파리로 검색 결과를 연다 (닫으면 디시 화면 그대로)
            .sheet(isPresented: $showNamuSearch, onDismiss: { namuInitial = "" }) {
                NamuSearchInputSheet(initialText: namuInitial) { url in
                    Task { @MainActor in
                        // 입력 시트가 완전히 닫힌 뒤에 나무위키 시트를 띄움 (겹쳐 띄우면 무시될 때가 있음)
                        try? await Task.sleep(for: .milliseconds(450))
                        namuTarget = NamuTarget(url: url)
                    }
                }
            }
            .sheet(item: $namuTarget) { target in
                NamuWebSheet(model: target.model)
            }
            .onChangeCompat(of: model.listFilterTick) { _, _ in showListFilter = true }   // 말머리 줄 깔때기 버튼 (웹)
            .onChangeCompat(of: verticalInLandscape) { _, _ in applySideColumn() }   // 컨트롤바 가로/세로 바꾸면 웹 여백도 바로
            .onChangeCompat(of: verticalInPortrait) { _, _ in applySideColumn() }
            .sheet(isPresented: $showDraftPicker) {
                DraftPickerSheet(galleryID: model.url.flatMap(AutoImageStore.writeGalleryID)) { d in
                    model.restoreDraft(d)
                }
            }
            .sheet(isPresented: Binding(get: { diagnosticText != nil },
                                        set: { if !$0 { diagnosticText = nil } })) {
                DiagnosticView(text: diagnosticText ?? "")
                    .sheetUnderBlueBar()
            }
    }

    /// 이 브라우저가 사진 보기·댓글 내용 창을 직접 띄워야 하는지 (RootView의 메인·글 화면이 아닌 단독 브라우저)
    private var ownsCovers: Bool { model !== router.mainBrowser && model !== router.detailBrowser }

    /// 글쓰기 화면 → 이 갤러리 자짤 설정 / 사진 보기
    private var layer7: some View {
        // 뷰 타입이 너무 깊게 중첩되면 실행하자마자 스택이 넘쳐 튕김 → 단계마다 AnyView로 끊음
        AnyView(layer6)
            .overlay(alignment: .bottom) { CommentComposerHost(model: model, barInset: composerBarInset, barLeft: barMirrored).ignoresSafeArea(.keyboard, edges: .bottom) }   // 앱 댓글 입력창 (키보드가 내려가는 동안 입력창·어두운 막이 키보드 높이만큼 줄어 아래 흰 바탕이 보이지 않게 화면 맨 아래까지 유지)
            // 사진 보기·댓글 내용 보기는 RootView가 맡음 (분할 전환 중에도 창이 끊기지 않게). 단독 브라우저만 여기서 띄움
            .background { if ownsCovers { BrowserCovers(model: model) } }
            .overlay { commentTextPromptButton }
            .sheet(item: $idSearchTarget) { t in
                IdPostSearchSheet(gallery: t.gallery, code: t.code) { url in model.load(url) }
            }
            .overlay(alignment: .top) {
                // 뒤에서 작성글을 찾는 중이거나 끝났을 때 알림 칸 (누르면 결과 창)
                if idSearchTarget == nil, !model.isDetailPane {
                    IdSearchPill {
                        if let g = IdPostSearcher.shared.gallery { idSearchTarget = IdSearchTarget(gallery: g, code: "") }
                    }
                }
            }
            .onChangeCompat(of: model.isScrolling) { _, on in if on { model.commentTextPrompt = nil } }
            .sheet(isPresented: Binding(get: { autoImageGallery != nil },
                                        set: { if !$0 { autoImageGallery = nil } })) {
                if let gid = autoImageGallery {
                    NavigationStack {
                        GalleryAutoImageView(galleryID: gid, name: autoScopeName(gid))
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("완료") { autoImageGallery = nil }
                                }
                            }
                    }
                    .sheetUnderBlueBar()
                }
            }
    }

    /// 댓글을 길게 누르면 그 자리 위에 뜨는 '텍스트 선택' 버튼
    @ViewBuilder
    private var commentTextPromptButton: some View {
        if let item = model.commentTextPrompt {
            GeometryReader { g in
                let frame = g.frame(in: .global)
                let origin = model.webView.convert(CGPoint.zero, to: nil)       // 웹 화면의 왼쪽 위 (창 기준)
                let x = min(max(origin.x + item.point.x - frame.minX, 70), max(g.size.width - 70, 70))
                let y = max(origin.y + item.point.y - frame.minY - 44, 30)
                Button {
                    model.commentTextPrompt = nil
                    model.commentText = item
                } label: {
                    Label("텍스트 선택", systemImage: "text.cursor")
                        .font(fonts.styleFont(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.black.opacity(0.82), in: Capsule())
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .position(x: x, y: y)
                .transition(.opacity)
            }
            .animation(.easeOut(duration: 0.15), value: item.id)
        }
    }

    // MARK: - 상단: 로딩바 / 캡처 중

    @ViewBuilder
    private var topOverlay: some View {
        ZStack(alignment: .top) {
            topOverlayItems
        }
        .onChangeCompat(of: Double(barCoverWidth) + (barMirrored ? 1000 : 0)) { _, _ in applyBarInset() }
        .onChangeCompat(of: router.barOverlayWidth) { _, _ in applyBarInset() }
        .onChangeCompat(of: router.barOverlayLeft) { _, _ in applyBarInset() }
        .onChangeCompat(of: router.splitActive) { _, _ in
            applyBarInset()
            model.applyFilters()
            model.nudgeLayout()
        }
        .onChangeCompat(of: compactRaw) { _, _ in settleCompact() }
    }

    private var topOverlayItems: some View {
        VStack(spacing: 0) {
            if model.isCapturing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("전체 페이지 캡처 중…")
                }
                .font(fonts.styleFont(.subheadline))
                .padding(10)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 8)
            }
            if let status = model.backgroundCommentStatus {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(status)
                }
                .font(fonts.styleFont(.subheadline))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 8)
            }
        }
    }


    // MARK: - 글쓰기 화면 계정 버튼 (로그인 / 계정 전환 / 로그아웃)

    /// 하단 바(또는 세로 막대)의 로그인 칸 — 누르면 계정 메뉴
    private var accountBarItem: some View {
        let compact = compactSideBar
        return Menu { accountMenuItems } label: {
            VStack(spacing: 2) {
                Image(systemName: currentAccount == nil ? "person.crop.circle.badge.plus" : "person.crop.circle.fill")
                    .font(.system(size: 19, weight: .medium))
                    .frame(height: 24)
                if !compact {
                    Text(currentAccount == nil ? "로그인" : "계정").font(fonts.uiFont(size: 11, weight: .semibold, relativeTo: .caption2))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 10 : 7)
            .foregroundStyle(currentAccount == nil ? Color.primary : DCTheme.accent)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .id("\(DCTheme.current.rawValue)-\(DCTheme.customHex)")
    }

    private var accountMenu: some View {
        Menu { accountMenuItems } label: {
            Image(systemName: currentAccount == nil ? "person.crop.circle.badge.plus" : "person.crop.circle.fill")
                .font(.system(size: 19))
        }
    }

    @ViewBuilder
    private var accountMenuItems: some View {
        let others = CredentialStore.all().filter { $0.id != currentAccount }
        Group {
            if let cur = currentAccount {
                Section("현재 계정: \(cur)") {
                    Button(role: .destructive) { model.logoutHere() } label: {
                        Label("로그아웃 (유동으로 쓰기)", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            if !others.isEmpty {
                Section(currentAccount == nil ? "저장된 계정으로 로그인" : "다른 계정으로 전환") {
                    ForEach(others) { acc in
                        Button { model.loginHere(acc) } label: {
                            Label(acc.id, systemImage: "person.crop.circle")
                        }
                    }
                }
            }
            Button { model.loginHere(nil) } label: {
                Label("로그인 페이지 열기", systemImage: "person.badge.key")
            }
        }
    }

    // MARK: - 모드 안내 배너 (하단 툴바 위에 표시 → 페이지 맨 위를 가리지 않음)

    @ViewBuilder
    private var modeBanner: some View {
            // 글쓰기: 로그인 / 임시저장 / 불러오기 / 등록은 상단바로 옮김 → 여기엔 자짤만
            if model.isWritePage, let gid = writeGalleryID,
               autoImages.effective(for: gid, account: autoScopeAccount).enabled || !autoImages.settings.images.isEmpty {
                HStack(spacing: 8) {
                    Spacer()
                    if autoImages.effective(for: gid, account: autoScopeAccount).enabled {
                        // 누르면 자짤 첨부, 길게 누르면 이 갤러리 자짤 설정
                        Menu {
                            Button { model.attachAutoImage(force: true) } label: {
                                Label("자짤 첨부", systemImage: "photo.badge.plus")
                            }
                            Button { autoImageGallery = AutoImageScope.key(account: autoScopeAccount, gallery: gid) } label: {
                                Label("이 계정·갤러리 자짤 설정", systemImage: "slider.horizontal.3")
                            }
                        } label: {
                            Text("자짤")
                        } primaryAction: {
                            model.attachAutoImage(force: true)
                        }
                    } else {
                        Button("자짤 꺼짐") { autoImageGallery = AutoImageScope.key(account: autoScopeAccount, gallery: gid) }
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(fonts.styleFont(.subheadline))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial)
                .overlay(alignment: .top) { Divider() }
            }
            if model.isPickMode {
                HStack {
                    Image(systemName: "hand.tap")
                    Text("숨길 부분을 탭하세요")
                    Spacer()
                    Button("완료") { model.setPickMode(false) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .font(fonts.styleFont(.subheadline))
                .padding(10)
                .background(.thinMaterial)
                .overlay(alignment: .top) { Divider() }
            }
            if model.isBlockPickMode {
                HStack {
                    Image(systemName: "person.crop.circle.badge.xmark")
                    Text("차단할 글이나 댓글을 탭하세요")
                    Spacer()
                    Button("취소") { model.setBlockPickMode(false) }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                }
                .font(fonts.styleFont(.subheadline))
                .padding(10)
                .background(.thinMaterial)
                .overlay(alignment: .top) { Divider() }
            }
    }

    // MARK: - 상단바 (남색): 제목만 (메인 화면). 설정 안에서 연 화면은 오른쪽에 ☆ ⋮

    /// 상단바 제목 (홈은 dcAPP, 갤러리 안이면 이름 + 배지)
    private var topTitle: some View { titleView(logo: 36) }

    /// 제목 한 줄 (logo: 홈 로고 높이 — 낮은 상단바 띠 안에 들어가도록 줄일 수 있게 인자로 받음)
    private func titleView(logo: CGFloat) -> some View {
        return HStack(spacing: 6) {
            if isHomeScreen {
                // 홈: 페이지 제목(connecting… 등) 대신 앱 이름 (글자 옆에 로고 그림)
                // 로고 폭을 정해 둠 (폭이 정해지지 않으면 아이패드에서 처음 열 때 글자가 'dcA…'로 잘림)
                Image("HomeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logo * 34 / 36, height: logo)
                Text("dcAPP").fontWeight(.heavy).italic()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Text(titleParts.name)
                    .lineLimit(1)
                    .minimumScaleFactor(BrowserView.windowIsLandscape ? 0.8 : 1)   // 가로의 낮은 띠에서 이름이 길면 조금 줄여서 한 줄에
                if let b = titleParts.badge { badgeView(b) }
            }
        }
            .font(fonts.styleFont(.headline))
            .foregroundStyle(.white)
            .contentShape(Rectangle())
            // 갤러리 이름을 0.5초 누르면 한손 모드 켜기/끄기
            .onLongPressGesture(minimumDuration: 0.5) {
                guard showsMenuButton else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                compactMode.toggle()
            }
            .overlay(alignment: .trailing) {
                if model.isLoading {
                    ProgressView().controlSize(.small).tint(.white).offset(x: 22)   // 페이지 불러오는 동안 제목 오른쪽 옆에 작게
                }
            }
    }

    @ToolbarContentBuilder
    private var topBar: some ToolbarContent {
        // 듀오: 상단바 오른쪽이 시계·카메라 줄이라 제목이 길면 '…'로 줄지 않고 통째로 사라짐
        // → 오른쪽 버튼과 겹치지 않는 고정 폭을 줌 (가운데 정렬은 그대로)
        if duoTopBar && !model.isDetailPane && !(showsMenuButton && model.isWritePage) {
            ToolbarItem(placement: .principal) {
                topTitle.frame(width: duoTitleWidth)
            }
        } else {
            ToolbarItem(placement: .principal) {
                // 제목이 길면(디시 첫 화면 제목 등) 넓은 화면에서 양옆 버튼 자리를 밀어내 로그인 버튼이 사라짐 → 폭 제한
                topTitle.frame(maxWidth: model.isDetailPane ? 520 : 240)
            }
        }
        if showsMenuButton {
            // 글쓰기 화면: 왼쪽 (⋮) 로그인 / 오른쪽 임시저장 불러오기 등록
            // (한 칸에 묶어서 넣어야 공간이 모자라도 '…'로 접히지 않음, 테두리(글래스)는 뺌)
            if model.isWritePage {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        if showsKeyboardBack { backButton { Image(systemName: "chevron.backward") } }
                        accountMenu                          // 로그인 / 계정 (글쓰기 화면은 컨트롤바 대신 여기)
                        if menuInTopBarShown { topMoreMenu }     // 글쓰기 화면은 오른쪽이 임시저장·등록이라 ⋮는 왼쪽
                    }
                    .foregroundStyle(.white)
                }
                .noGlassBackground()
                // 상단바 버튼은 버튼마다 기본 여백이 붙어서 간격 숫자를 줄여도 그대로 → plain 스타일로 여백을 없애고 한 칸에 모음
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button("임시저장") { Task { await model.saveDraftManually() } }
                        Button("불러오기") { showDraftPicker = true }
                        // 등록만 테두리
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            model.submitWrite()
                        } label: {
                            Text("등록")
                                .fontWeight(.bold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.85), lineWidth: 1.2))
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .buttonStyle(.plain)
                    .font(fonts.styleFont(.subheadline))
                    .foregroundStyle(.white)
                    .fixedSize()
                }
                .noGlassBackground()
            } else {
                // 다른 화면: 왼쪽은 (하드웨어 키보드일 때) 뒤로가기, 오른쪽은 깔때기(글 목록)·⋮
                // 양쪽을 같은 폭(칸 수 × 28 + 간격)으로 맞춰야 가운데 제목이 한쪽으로 밀리지 않음
                // 단 듀오는 상단바 오른쪽 절반이 시계·카메라 줄이라 제목을 왼쪽에 두므로 빈 칸 생략
                if topSlots > 0 {
                    if !duoTopBar || showsTopBack {
                        ToolbarItem(placement: .topBarLeading) {
                            HStack(spacing: Self.topSlotSpacing) {
                                if showsTopBack {
                                    backButton { Image(systemName: "arrow.left") }
                                        .frame(width: Self.topSlotWidth, height: Self.topSlotWidth)
                                }
                                ForEach(0..<(duoTopBar ? 0 : topSlots - (showsTopBack ? 1 : 0)), id: \.self) { _ in
                                    Color.clear.frame(width: Self.topSlotWidth, height: Self.topSlotWidth)
                                        .accessibilityHidden(true)
                                }
                            }
                            .foregroundStyle(.white)
                            .fixedSize()
                        }
                        .noGlassBackground()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: Self.topSlotSpacing) {
                            ForEach(0..<(topSlots - topTrailingCount), id: \.self) { _ in
                                Color.clear.frame(width: Self.topSlotWidth, height: Self.topSlotWidth)
                                    .accessibilityHidden(true)
                            }
                            // 글 목록(말머리 줄이 없을 때): 게시물 필터 깔때기
                            if showsListFilterInBar {
                                Button { showListFilter = true } label: {
                                    Image(systemName: listFilter.filter.activeIn(model.galleryFilterKey) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                        .frame(width: Self.topSlotWidth, height: Self.topSlotWidth)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("게시물 필터")
                            }
                            // ⋮ 메뉴: 설정에서 '상단바에 두기'를 켰을 때만 (아니면 컨트롤바 안)
                            if menuInTopBarShown {
                                MorePopoverButton { close in morePopover(dismiss: close) } label: {
                                    Image(systemName: "ellipsis")
                                        .rotationEffect(.degrees(90))
                                        .frame(width: Self.topSlotWidth, height: Self.topSlotWidth)
                                        .contentShape(Rectangle())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .fixedSize()
                        .offset(x: Self.duoTopButtonShift)
                    }
                    .noGlassBackground()
                }
            }
        } else if !model.isDetailPane {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if currentGallery != nil {
                    Button { toggleFavorite() } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                    }
                }
                Menu {
                    moreMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                }
            }
        }
    }

    /// 세로 막대를 껐을 때 상단바에 놓는 ⋮ 메뉴
    private var topMoreMenu: some View {
        Menu {
            moreMenu
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
        }
    }

    // MARK: - 오른쪽 아래 세로 버튼 (한손 모드 / ⋮ 메뉴 / 댓글 새로고침)

    /// 세로 버튼 위치: 보통은 웹페이지 오른쪽 아래.
    /// 듀오처럼 오른쪽에 넓은 안전 영역(시계·카메라 줄)이 있으면 그 빈 줄의 맨 아래(하단 바 옆)에 넣음
    /// 글 볼 때 오른쪽 아래(하단 바 위)에 떠 있는 댓글 새로고침 버튼
    private var refreshButtonPlaced: some View {
        VStack(spacing: 2) {
            Button { refreshTapped() } label: {
                floatIcon("arrow.clockwise", tint: .primary)
            }
        }
        .padding(4)
        .glassBar()
        .padding(barMirrored ? .leading : .trailing, barEdge)
            .padding(.bottom, 16 + bottomBarHeight)      // 페이지 위에 떠 있는 하단 바 위로
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: barMirrored ? .bottomLeading : .bottomTrailing)
    }

    /// 홈 인디케이터 등 기기 아래쪽 안전 영역 높이
    private static var windowBottomInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.bottom
            ?? scene?.windows.first?.safeAreaInsets.bottom ?? 0
    }

    private var floatingButtons: some View {
        VStack(spacing: 2) { floatingButtonItems }
            .padding(4)
            .glassBar()
    }

    @ViewBuilder
    private var floatingButtonItems: some View {
            // 1. 한손 모드 켜기/끄기
            Button { compactMode.toggle() } label: {
                floatIcon(compactMode ? "rectangle.expand.vertical" : "rectangle.bottomhalf.inset.filled",
                          tint: compactMode ? DCTheme.accent : .primary)
            }
            // 2. ⋮ 메뉴
            Menu {
                moreMenu
            } label: {
                floatIcon("ellipsis", tint: .primary).rotationEffect(.degrees(90))
            }
            // 3. 새로고침 (글 보기: 댓글 / 글 목록: 페이지)
            if showsRefresh {
                Button { refreshTapped() } label: {
                    floatIcon("arrow.clockwise.circle", tint: .primary)
                }
            }
            // 4. 뒤로가기 — 하드웨어 키보드(트랙패드)를 쓸 때만 (쓸어서 뒤로가기를 못 쓰므로). ⌘[ 단축키도
            if showsKeyboardBack {
                backButton { floatIcon("chevron.backward", tint: .primary) }
            }
    }

    /// 뒤로가기 버튼 (⌘[ 단축키 포함) — 화면 쓸기와 같은 동작
    /// (글 보기 → 갤러리 1페이지, 갤러리 1페이지 → 갤러리 창, 개념글 목록 → 전체글, 그 밖에는 뒤로가기)
    private func backButton<L: View>(@ViewBuilder label: () -> L) -> some View {
        let _ = model.canGoBack      // 뒤로 갈 수 있는 상태가 바뀌면 다시 그리기
        let enabled = model.canSwipeBack
        return Button { model.swipeBack() } label: { label() }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
            .keyboardShortcut("[", modifiers: .command)
    }

    /// 링크 공유 대상 — 분할 화면에서 컨트롤바는 왼쪽(목록) 화면에 붙어 있지만 사용자가 보는 글은 오른쪽이므로, 오른쪽에 글이 열려 있으면 그 주소를 공유
    private var shareTarget: URL? {
        if router.splitActive, model === router.mainBrowser,
           let u = router.detailBrowser.url, u.scheme?.hasPrefix("http") == true {
            return u
        }
        return model.url
    }

    private var isPostPage: Bool { model.url.flatMap(SavedPostStore.postInfo) != nil }

    /// 갤러리 글 목록 화면인지 (model.url을 읽어 주소가 바뀌면 다시 그림)
    private var isListPage: Bool {
        let _ = model.url
        return model.isGalleryListPage
    }

    /// 새로고침 버튼을 보일 화면: 글 보기 + 글 목록
    private var showsRefresh: Bool { isPostPage || isListPage }


    /// 상단바 양옆 버튼 칸 (제목 가운데 맞춤용)
    static let topSlotWidth: CGFloat = 28
    static let topSlotSpacing: CGFloat = 14
    /// ⋮를 실제로 상단바에 놓는지 — 설정이 켜져 있어도, 듀오처럼 옆 세로 줄(시계)이 상단바 오른쪽을 가리는 화면에서는 보이지 않으므로 컨트롤바에 둠
    private var menuInTopBarShown: Bool { menuInTopBar && !fillsTrailing }
    /// 게시물 필터 깔때기를 상단바 우측에 둘지: 글 목록이고 말머리 줄이 없을 때 (말머리가 있으면 말머리 줄 맨 왼쪽)
    private var showsListFilterInBar: Bool { isListPage && model.headNames.isEmpty }
    private var topTrailingCount: Int { (showsListFilterInBar ? 1 : 0) + (menuInTopBarShown ? 1 : 0) }
    /// 하드웨어 키보드(트랙패드)용 뒤로가기 버튼 — 아이패드만. 아이폰(듀오 포함)은 키보드를 연결해도 쓸어서 뒤로가기만
    private var showsKeyboardBack: Bool {
        hwKeyboard.connected && UIDevice.current.userInterfaceIdiom != .phone
    }
    /// 양쪽 모두 이 칸 수만큼 차지 (모자란 쪽은 빈 칸)
    /// 상단바 왼쪽 뒤로가기 화살표: 글 볼 때(디시 아래 목록보기 버튼을 대신함) + 하드웨어 키보드(아이패드)
    /// 듀오가 접혀 있을 때(바깥 디스플레이) 글 보기에서는 뒤로가기 버튼을 두지 않음 — 시스템이 상단바 버튼을 세로 줄 쪽으로 옮겨 사진 위에 뜨는 일이 간헐적으로 생겨서 (쓸어서 뒤로가기는 그대로)
    @ObservedObject private var display = DisplayState.shared
    private var showsTopBack: Bool { (isPostPage || showsKeyboardBack) && !display.outerDisplay }
    private var topSlots: Int { max(topTrailingCount, showsTopBack ? 1 : 0) }
    /// 듀오처럼 상단바 오른쪽에 시계·카메라가 겹쳐 그려지는 화면인지
    /// (세로 화면은 오른쪽 안전 영역이 0이라 폭으로 구분 — 일반 아이폰은 가장 넓은 Pro Max도 440pt)
    private var duoTopBar: Bool {
        false
    }
    /// 듀오 상단바 제목 폭: 시계·카메라 자리를 뺀 폭의 가운데에 놓았을 때 오른쪽 버튼과 겹치지 않는 만큼
    private var duoTitleWidth: CGFloat {
        let statusArea: CGFloat = trailingInset > 0 ? trailingInset : 200
        let usable = Self.windowWidth - statusArea
        let buttons = CGFloat(max(topTrailingCount, 1))
        let trailing = buttons * Self.topSlotWidth + (buttons - 1) * Self.topSlotSpacing
        return min(240, max(60, usable - 48 - 2 * trailing))
    }
    /// 듀오(펼친 화면, 세로): 상단바 오른쪽 버튼이 시계·배터리에서 떨어져 좁은 상단바를 더 쓰므로 조금만 오른쪽으로 (시계에 가려지지 않을 만큼만)
    /// 듀오 같은 큰 폰 화면(짧은 변 450pt 초과, 세로)인지 — 시트 위쪽 버튼을 시계 아래로 내릴 때 씀
    static var isDuoLikeScreen: Bool {
        let b = UIScreen.main.bounds
        return UIDevice.current.userInterfaceIdiom == .phone && min(b.width, b.height) > 450 && b.height > b.width
    }
    private static var duoTopButtonShift: CGFloat {
        let b = UIScreen.main.bounds
        guard UIDevice.current.userInterfaceIdiom == .phone, min(b.width, b.height) > 450, b.height > b.width else { return 0 }
        return 0   // 시계가 옆 세로 줄이라 필터 버튼을 옮길 필요 없음
    }
    private static var windowWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel == .normal && !$0.isHidden }
            .map(\.bounds.width).max() ?? 390
    }

    /// 글 보기 → 댓글 새로고침, 글 목록 → 페이지 새로고침
    private func refreshTapped() {
        // 분할 화면: 버튼은 왼쪽(목록) 화면에 붙어 있지만 사용자가 보는 글은 오른쪽 → 오른쪽에 글이 열려 있으면 그 댓글을 새로고침
        if router.splitActive, model === router.mainBrowser,
           let u = router.detailBrowser.url, SavedPostStore.postInfo(u) != nil {
            router.detailBrowser.refreshComments()
            return
        }
        if isPostPage { model.refreshComments() } else { model.reload() }
    }

    private var isPostSaved: Bool {
        guard let url = model.url else { return false }
        return savedPosts.contains(url: url)
    }

    private func bookmarkTapped() {
        guard let url = model.url else { return }
        if let saved = savedPosts.post(for: url) {
            savedPostMenu = saved                       // 이미 보관 → 폴더 이동 / 빼기 메뉴
        } else if savedPosts.folders.isEmpty {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await model.savePost() }             // 폴더가 없으면 바로 보관
        } else {
            showSaveFolderPicker = true                 // 어느 폴더에 넣을지 고르기
        }
    }

    private func floatIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    // MARK: - 하단 바 (리퀴드 글라스): 홈 / 보관함 / 개념글 / 검색 / 글쓰기

    /// 지금 화면 방향(가로로 쓸 때 / 세로로 쓸 때)의 컨트롤바 배치를 바꿈 — 설정 → 컨트롤바 버튼의 '배치'와 같은 값
    private func setBarVertical(_ v: Bool) {
        if isLandscape { verticalInLandscape = v } else { verticalInPortrait = v }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 꾹 눌러 밀기 중 — 이때는 막대 안 버튼이 눌리지 않게 (손을 뗄 때 버튼이 눌리던 문제)
    @State private var barGestureActive = false
    /// 컨트롤바를 동그란 버튼 하나로 접어 둠
    @AppStorage(ControlBarItem.collapsedKey, store: Profile.defaults) private var barCollapsed = false
    /// 가로 막대: 설정 ⋮만 보이는 상태
    @State private var barMenuMode = false
    /// 나무위키 검색: 검색어 입력 시트 / 인앱 사파리로 열 주소
    @State private var showNamuSearch = false
    /// 나무위키 입력 창에 미리 넣을 검색어 (지금은 항상 빈 칸으로 열림)
    @State private var namuInitial = ""
    @State private var namuTarget: NamuTarget?
    /// 글쓰기 버튼 한 번 탭을 기다리는 중인 작업 (기다리는 동안 두 번째 탭이 오면 퀵 글쓰기)
    @State private var writeTapTask: Task<Void, Never>?
    @State private var barMenuChangedAt = Date.distantPast
    @State private var barMenuIdleSince = Date.distantPast
    @State private var galleryBarWidth: CGFloat = 0
    @State private var sideBarHeight: CGFloat = 0
    /// 세로 막대 위치 (가운데 기준 위아래 거리, 저장)
    @AppStorage("sideBarOffsetY", store: Profile.defaults) private var sideBarOffsetY = 0.0
    @State private var sideDragY: CGFloat = 0
    @State private var sideMoving = false
    @State private var sideMovedAt = Date.distantPast
    @State private var collapsedHeight: CGFloat = 0
    /// 좌우반전: 세로 막대·접은 버튼·새로고침 버튼을 왼쪽에, 가로 막대 밀기 방향도 반대로
    @AppStorage(ControlBarItem.mirroredKey, store: Profile.defaults) private var barMirroredSetting = false
    /// 실제로 막대를 왼쪽에 둘지: 설정의 좌우반전, 또는 시스템이 왼쪽에만 여백(안전 영역)을 준 창(분할 화면에서 왼쪽에 놓인 앱 등)이면 그 여백 쪽(왼쪽)으로
    private var barMirrored: Bool { barMirroredSetting || splitLeftMargin }
    /// 분할 화면에서 왼쪽에 놓여 웹 화면에만 왼쪽 여백이 생긴 상태 (창 자체의 안전 영역은 0).
    /// 듀오를 돌려 창 전체에 왼쪽 세로 줄이 생긴 상태는 해당 없음 → 컨트롤바는 예전처럼 오른쪽
    private var splitLeftMargin: Bool {
        _ = viewSize
        guard webInsets.left >= 56 && webInsets.right < 20 else { return false }
        let ws = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { $0.windowLevel == .normal && !$0.isHidden }
        return (ws.map(\.safeAreaInsets.left).max() ?? 0) < 20
    }

    /// 막대가 화면 밖으로 나가지 않게
    private func clampedSideOffset(_ y: CGFloat) -> CGFloat {
        let limit = max(0, (viewSize.height - sideBarHeight) / 2 - 16)
        return min(max(y, -limit), limit)
    }

    /// 둘째 칸이 열린 뒤 막대를 마지막으로 건드린 시각 (30초 지나면 첫째 칸으로)
    private func barMenuIdleTick() {
        guard barMenuMode, Date().timeIntervalSince(barMenuIdleSince) > 30 else { return }
        setBarMenuMode(false)
    }

    private func setBarMenuMode(_ on: Bool) {
        barMenuChangedAt = Date()
        barMenuIdleSince = Date()
        withAnimation(.spring(duration: 0.3)) { barMenuMode = on }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func barGestureChanged(_ active: Bool) {
        if active {
            barGestureActive = true
        } else {
            // 손을 뗀 순간의 버튼 눌림까지 막은 뒤 풀어 줌
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                barGestureActive = false
            }
        }
    }

    /// 접힌 전개버튼에서 밀어 가로/세로 막대로 펼침
    private func expandBar(vertical: Bool) {
        if isLandscape { verticalInLandscape = vertical } else { verticalInPortrait = vertical }
        withAnimation(.spring(duration: 0.3)) { barCollapsed = false }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func collapseBar() {
        withAnimation(.spring(duration: 0.3)) { barCollapsed = true }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 접어 둔 컨트롤바(전개 버튼) — 글 볼 때는 댓글 새로고침과 한 덩어리 (위: 새로고침, 아래: 펼치기)
    private var collapsedBarCore: some View {
        VStack(spacing: 0) {
            if showsRefresh {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    refreshTapped()
                } label: {
                    collapsedIcon("arrow.clockwise")
                }
                Divider().frame(width: 28)
            }
            Button {
                withAnimation(.spring(duration: 0.3)) { barCollapsed = false }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                collapsedIcon("square.grid.2x2")
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, showsRefresh ? 2 : 0)
        .glassBar()      // 한 칸이면 동그라미, 두 칸이면 세로 캡슐
        // 꾹 누를 필요 없이 그냥 밀면 바로 펼침 (탭은 그대로 버튼 동작)
        .simultaneousGesture(
            DragGesture(minimumDistance: 15)
                .onEnded { v in
                    let t = v.translation
                    if t.width * (barMirrored ? -1 : 1) < -30 && abs(t.width) > abs(t.height) {
                        expandBar(vertical: false)        // 안쪽(보통 왼쪽, 좌우반전이면 오른쪽)으로 밀기 → 가로 막대
                    } else if t.height < -30 && abs(t.height) > abs(t.width) {
                        expandBar(vertical: true)         // 위로 밀기 → 세로 막대
                    }
                }
        )
    }

    /// 가로 배치일 때: 오른쪽 아래
    /// 가로 막대를 접은 상태인데 듀오처럼 오른쪽에 세로 줄이 있으면, 전개버튼을 그 줄 안(세로 막대를 접었을 때와 같은 자리)에 놓음
    private var collapsedInColumn: Bool {
        barCollapsed && showsMenuButton && !usesSideBar && fillsTrailing && Self.hasSideColumnOnly && !barMirrored
    }

    private var collapsedColumnButton: some View {
        collapsedBarCore
            .padding(.trailing, barEdge + 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var collapsedBarButton: some View {
        collapsedBarCore
            .padding(barMirrored ? .leading : .trailing, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: barMirrored ? .leading : .trailing)
    }

    /// 세로 배치일 때: 펼친 세로 막대와 아래쪽을 맞춤 → 접힌 네모 버튼이 펼쳤을 때 맨 아래(새로고침) 버튼 자리에
    @ViewBuilder
    private var collapsedSideButton: some View {
        if sideBarHeight > 0 {
            // 펼친 막대 맨 아래 칸(글자 있음)의 가운데가 막대 아래 끝에서 조금 더 위라 그만큼 올림
            let lift: CGFloat = compactSideBar ? 0 : 7
            collapsedBarCore
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsedHeight = $0 }
                .offset(y: clampedSideOffset(CGFloat(sideBarOffsetY)) + (sideBarHeight - collapsedHeight) / 2 - lift)
                .padding(barMirrored ? .leading : .trailing, barEdge + 6)          // 세로 막대(폭 64, 가장자리 12)와 가운데 맞춤
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: barMirrored ? .leading : .trailing)
        } else {
            collapsedBarButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: barMirrored ? .bottomLeading : .bottomTrailing)
        }
    }

    private func collapsedIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(Color.primary)
            .frame(width: 52, height: showsRefresh ? 48 : 52)
            .contentShape(Rectangle())
    }

    private var galleryBar: some View {
        HStack(spacing: 2) { barItems(horizontal: true) }
            .disabled(barGestureActive)
            .padding(6)
            .glassBar()
            .padding(.horizontal, Self.duoHorizontalBarNow ? 12 : 0)   // 듀오 가로 바: 양옆 12pt 여백 (화면 끝까지 뻗되 캡슐이 끝에 붙지 않게)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { galleryBarWidth = $0 }
            // 그냥 밀기: 오른쪽→왼쪽 = 설정 ⋮만 보기 / 그 상태에서 왼쪽→오른쪽 = 원래대로
            //           평소에 왼쪽→오른쪽으로 막대 길이 30% 이상 쓸면 접기
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        // 밀기 시작했으면 막대 안 버튼이 눌리지 않게
                        if !barGestureActive && hypot(v.translation.width, v.translation.height) > 8 { barGestureChanged(true) }
                    }
                    .onEnded { v in
                        barGestureChanged(false)
                        // 좌우반전이면 방향도 뒤집음 (왼→오 = 둘째 칸, 오→왼 = 접기)
                        let w = v.translation.width * (barMirrored ? -1 : 1), h = v.translation.height
                        guard abs(w) > abs(h) * 1.5 else { return }
                        if barMenuMode {
                            if w > 18 { setBarMenuMode(false) }
                        } else if w < -18 {
                            if barHasMenu { setBarMenuMode(true) }
                        } else if galleryBarWidth > 0 && w >= galleryBarWidth * 0.3 {
                            collapseBar()
                        }
                    }
            )
            // 둘째 칸이 열린 채 30초 동안 막대를 건드리지 않으면 첫째 칸으로 돌아감
            .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in barMenuIdleSince = Date() })
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in barMenuIdleTick() }
            .barSwitchGesture(onActive: barGestureChanged) { t in
                // 설정 ⋮만 보이는 상태(또는 방금 원래대로 돌린 직후)에는 접지 않음
                guard !barMenuMode, Date().timeIntervalSince(barMenuChangedAt) > 0.6 else { return }
                if t.width * (barMirrored ? -1 : 1) > 40 && abs(t.width) > abs(t.height) {
                    collapseBar()                 // 꾹 누른 채 오른쪽으로 → 동그란 버튼 하나
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    /// 아이패드: 오른쪽 세로 막대 하나에 하단 바 칸들 + 기존 세로 버튼(한손·⋮·댓글 새로고침·뒤로)을 모음
    @ViewBuilder
    private var sideBar: some View {
        let bar = VStack(spacing: 2) {
            Group { barItems(horizontal: true) }.disabled(barGestureActive)
            if showsRefresh {
                // 글 볼 때: 댓글 새로고침 / 글 목록: 페이지 새로고침
                barItem("arrow.clockwise", "arrow.clockwise", "새로고침", selected: false) { refreshTapped() }
                    .disabled(barGestureActive)
            }
            if showFloatingBar {
                if hasSideColumn {
                    Spacer().frame(height: 6)
                } else {
                    Divider().frame(width: 36).padding(.vertical, 4)
                }
                floatingButtonItems
            }
        }
        .padding(.vertical, 6)
        if hasSideColumn {
            // 듀오: 오른쪽 빈 줄(안전 영역) 안, 맨 아래부터 세로로 (웹페이지는 그 줄을 쓰지 않음)
            // 리퀴드 글래스 없이 빈 줄 바탕에 그대로 (애플 시계·카메라 UI와 겹쳐 보이지 않게, 빈 줄과 한 몸처럼)
            bar
                .frame(width: trailingInset)
                .padding(.bottom, Self.windowBottomInset + 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .ignoresSafeArea(.container, edges: [.trailing, .bottom])
        } else {
            // 아이패드: 오른쪽 가운데 (손에 쥐었을 때 엄지 닿는 곳)
            bar
                .frame(width: 64)
                .glassBar()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sideBarHeight = $0 }
                // 그냥 밀기: 아래→위 = 둘째 칸 / 그 상태에서 위→아래 = 원래대로
                //           평소에 위→아래로 막대 길이 30% 이상 쓸면 접기
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { v in
                            if !barGestureActive && hypot(v.translation.width, v.translation.height) > 8 { barGestureChanged(true) }
                        }
                        .onEnded { v in
                            barGestureChanged(false)
                            if sideMoving || Date().timeIntervalSince(sideMovedAt) < 0.5 { return }   // 위치 옮기기였음
                            let w = v.translation.width, h = v.translation.height
                            guard abs(h) > abs(w) * 1.5 else { return }
                            if barMenuMode {
                                if h > 18 { setBarMenuMode(false) }
                            } else if h < -18 {
                                setBarMenuMode(true)
                            } else if sideBarHeight > 0 && h >= sideBarHeight * 0.3 {
                                collapseBar()
                            }
                        }
                )
                // 둘째 칸이 열린 채 30초 동안 막대를 건드리지 않으면 첫째 칸으로 돌아감
                .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in barMenuIdleSince = Date() })
                .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in barMenuIdleTick() }
                .barSwitchGesture(onActive: barGestureChanged) { t in
                    guard !barMenuMode, Date().timeIntervalSince(barMenuChangedAt) > 0.6 else { return }
                    guard !sideMoving, Date().timeIntervalSince(sideMovedAt) > 0.5 else { return }
                    if t.height > 40 && abs(t.height) > abs(t.width) {
                        collapseBar()             // 꾹 누른 채 아래로 → 동그란 버튼 하나
                    }
                }
                // 1초 꾹 누른 뒤 위아래로 끌면 막대 위치 옮기기 (저장됨)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 1.0)
                        .onEnded { _ in
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            sideMoving = true
                            barGestureChanged(true)
                        }
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))   // 막대가 같이 움직이므로 화면 기준 좌표여야 떨리지 않음
                        .onChanged { value in
                            if case .second(true, let d?) = value { sideDragY = d.translation.height }
                        }
                        .onEnded { _ in
                            if sideMoving {
                                sideBarOffsetY = Double(clampedSideOffset(CGFloat(sideBarOffsetY) + sideDragY))
                            }
                            sideDragY = 0
                            sideMoving = false
                            sideMovedAt = Date()
                            barGestureChanged(false)
                        }
                )
                .scaleEffect(sideMoving ? 1.06 : 1)
                .animation(.spring(duration: 0.2), value: sideMoving)
                .offset(y: clampedSideOffset(CGFloat(sideBarOffsetY) + sideDragY))
                .padding(barMirrored ? .leading : .trailing, barEdge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: barMirrored ? .leading : .trailing)
        }
    }

    /// 웹페이지 아래에 하단 바 높이만큼 스크롤 여백 (바에 가려지지 않게)
    /// 컨트롤바가 세로 막대면 글 아래 댓글 입력칸을 화면 아래에 고정
    private func syncCommentPin() {
        guard showsMenuButton else { return }
        CommentPin.update(usesSideBar)
    }

    private func updateBottomInset() {
        syncCommentPin()
        model.syncTopInset()   // 위쪽 상단바 높이를 페이지에 넘김 (디시콘 정보 창이 바 밑으로 잘리지 않게)
        if splitListWidth != nil {
            // 분할 화면: 하단 바는 오른쪽(글) 화면 아래에 떠 있으므로 여백은 글 화면 쪽에 줌
            model.setBottomBarInset(0)
            router.detailBrowser.setBottomBarInset(keyboardVisible || bottomBarHeight == 0 ? 0 : bottomBarHeight + 24)
            return
        }
        // 바 높이만 비우면 페이지 맨 아래(페이지 번호 등)가 바 테두리에 걸림 → 여유를 더 줌
        model.setBottomBarInset(keyboardVisible || bottomBarHeight == 0 ? 0 : bottomBarHeight + 24)
    }

    /// 컨트롤바 버튼들 — 순서는 설정 → 컨트롤바 버튼 순서에서 바꿀 수 있음
    private var galleryBarItems: some View { barItems(horizontal: false) }

    /// 컨트롤바에 넣을 버튼 (설정 ⋮은 항상 맨 끝)
    /// 가로 막대: 평소엔 설정 ⋮을 빼고, 오른쪽→왼쪽으로 밀면 설정 ⋮만 보임
    private func barItems(horizontal: Bool) -> some View {
        // 글쓰기 화면은 로그인을 상단바 왼쪽에 두므로 컨트롤바에서는 뺌
        let all = ControlBarItem.order(from: controlOrderRaw).filter { !(menuInTopBarShown && $0 == .menu) && !(model.isWritePage && $0 == .account) }
        return Group {
            if horizontal && barMenuMode {
                // 밀어서 나오는 둘째 칸: 설정 / 탭해서 차단 / 메모하기 / 전체 검색 / 링크 공유
                if all.contains(.menu) {
                    controlItem(.menu)
                } else {
                    // ⋮이 상단바에 있으면 그 자리에 홈
                    barItem("house", "house.fill", "홈", selected: false) { model.load(DC.home) }
                }
                extraBarItems
            } else {
                ForEach(horizontal ? all.filter { $0 != .menu } : all) { item in
                    controlItem(item)
                }
                // 듀오 가로 바: 따로 떠 있던 새로고침을 바 안으로 (글 보기: 댓글 / 글 목록: 페이지)
                // 둘째 칸의 빈 자리 새로고침은 글 보기·글 목록이 아닐 때만 나와서 겹치지 않음. 세로 막대(sideBar)는 자체 새로고침이 있어 제외
                if horizontal && Self.duoHorizontalBarNow && !usesSideBar && showsRefresh {
                    barItem("arrow.clockwise", "arrow.clockwise", "새로고침", selected: false) { refreshTapped() }
                }
            }
        }
    }

    /// 컨트롤바 둘째 칸 (설정 ⋮ 다음)
    @ViewBuilder
    private var extraBarItems: some View {
        // 차단·메모: 누르면 무엇을 할지 고르고, 작성자를 탭해서 고름 (차단 모드·메모 모드 중이면 누르면 끔)
        barItem("hand.raised", "hand.raised.fill", "차단·메모",
                selected: model.isBlockPickMode || model.isMemoPickMode) {
            if model.isBlockPickMode || model.isMemoPickMode {
                model.setBlockPickMode(false)
                model.setMemoPickMode(false)
            } else {
                showBlockMemoChoice = true
            }
        }
        .confirmationDialog("무엇을 할까요?", isPresented: $showBlockMemoChoice, titleVisibility: .visible) {
            Button("차단할 유저 고르기") {
                model.setBlockPickMode(true)
                model.showToast("차단할 글이나 댓글의 작성자를 탭하세요")
            }
            Button("메모할 유저 고르기") {
                model.setMemoPickMode(true)
                model.showToast("메모할 글이나 댓글의 작성자를 탭하세요")
            }
            Button("취소", role: .cancel) {}
        }
        // 빈 한 자리: 글 보기면 보관함, 갤러리 목록이면 즐겨찾기, 그 밖에는 새로고침
        if isPostPage {
            barItem("folder.badge.plus", "folder.fill.badge.plus", "보관함", selected: false) {
                Task { await model.savePost() }
            }
        } else if currentGallery != nil {
            barItem("star", "star.fill", "즐겨찾기", selected: isFavorite) {
                toggleFavorite()
            }
        } else {
            barItem("arrow.clockwise", "arrow.clockwise", "새로고침", selected: false) {
                model.reload()
            }
        }
        barItem("text.book.closed", "text.book.closed.fill", "나무위키", selected: false) {
            showNamuSearch = true                    // 검색어 입력 → 인앱 사파리로 나무위키 검색
        }
        barItem("link", "link", "링크 공유", selected: false, enabled: model.url != nil) {
            if let url = shareTarget { model.share(url) }
        }
        // 듀오 가로 바: 첫째 칸(새로고침 포함 6개)과 폭을 맞추려고 둘째 칸에도 새로고침
        // 빈 자리 새로고침(model.reload)은 갤러리 주소가 아닐 때만 나오고, 이 버튼은 글 보기·글 목록에서만 나와서 겹치지 않음
        if Self.duoHorizontalBarNow && !usesSideBar && showsRefresh {
            barItem("arrow.clockwise", "arrow.clockwise", "새로고침", selected: false) { refreshTapped() }
        }
    }

    /// 밀어서 둘째 칸을 열 수 있는지
    private var barHasMenu: Bool { true }

    @ViewBuilder
    private func controlItem(_ item: ControlBarItem) -> some View {
        let g = gallery
        switch item {
        case .account:
            // 로그인 / 계정
            accountBarItem
        case .gallery:
            barItem("square.stack", "square.stack.fill", "메뉴", selected: false) {
                router.sheet = .library
            }
            .overlay(alignment: .top) {
                // 안 읽은 알림이 있으면 빨간 점 (갤러리 창 → 알림 탭)
                if alarms.unreadCount > 0 {
                    Circle().fill(.red).frame(width: 8, height: 8).offset(x: 12, y: 6).allowsHitTesting(false)
                }
            }
        case .recommend:
            // 글 보기 + 가로 바 + 분할 화면 아님 → 개념글 자리에 댓글작성 (앱 댓글 입력창)
            if isPostPage && !usesSideBar && !router.splitActive && splitListWidth == nil {
                barItem("text.bubble", "text.bubble", "댓글작성", selected: false) {
                    model.openCommentComposer()
                }
            // 전체글 보는 중 → "개념글" / 개념글 보는 중 → "전체글"(≡)로 바뀜
            } else if section == .recommend {
                barItem("line.3.horizontal", "line.3.horizontal", "전체글", selected: true, enabled: g != nil) {
                    if let g { model.load(g.url) }
                }
            } else {
                barItem("star", "star.fill", "개념글", selected: false, enabled: g != nil) {
                    if let g { model.load(g.recommendURL) }
                }
            }
        case .search:
            barItem("magnifyingglass", "magnifyingglass", "검색", selected: section == .search) {
                if g != nil {
                    Task {
                        galleryHeads = await model.headTabs()   // 지금 페이지의 말머리 읽기
                        showGallerySearch = true
                    }
                } else {
                    router.sheet = .search
                }
            }
        case .write:
            barItem("square.and.pencil", "square.and.pencil", "글쓰기", selected: section == .write, enabled: g != nil) {
                if let g { writeTapped(g) }      // 한 번: 일반 글쓰기 · 두 번: 퀵 글쓰기
            }
            // 길게 누르면 퀵 글쓰기 (글쓰기 화면 없이 제목·본문을 바로 등록)
            .contextMenu {
                if let g {
                    Button {
                        router.quickWriteTarget = QuickWriteTarget(gallery: g, model: model)
                        router.sheet = .quickWrite
                    } label: {
                        Label("퀵 글쓰기", systemImage: "bolt")
                    }
                }
            }
        case .menu:
            // ⋮ 메뉴 (상단바에서 컨트롤바로 옮김)
            let compact = compactSideBar
            MorePopoverButton { close in morePopover(dismiss: close) } label: {
                VStack(spacing: 2) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 19, weight: .medium))
                        .frame(height: 24)
                    if !compact { Text("설정").font(fonts.uiFont(size: 11, weight: .semibold, relativeTo: .caption2)) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 10 : 7)
                .foregroundStyle(Color.primary)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// 글쓰기 버튼: 한 번 탭하면 0.3초 기다렸다가 일반 글쓰기, 그 안에 한 번 더 탭하면 퀵 글쓰기 (글쓰기 화면 없이 바로 등록)
    private func writeTapped(_ g: Gallery) {
        if let pending = writeTapTask {
            pending.cancel()
            writeTapTask = nil
            router.quickWriteTarget = QuickWriteTarget(gallery: g, model: model)
            router.sheet = .quickWrite
            return
        }
        writeTapTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            writeTapTask = nil
            model.focusTitleOnWrite = true      // 열리면 제목 칸에 바로 키보드
            model.load(g.writeURL)
        }
    }

    private func barItem(_ icon: String, _ selectedIcon: String, _ title: String, selected: Bool, enabled: Bool = true,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: selected ? selectedIcon : icon)
                    .font(.system(size: 19, weight: .medium))
                    .frame(height: 24)
                // 듀오 빈 줄 안에서는 글자를 빼서 막대를 짧게 (위쪽 애플 시계·와이파이 표시와 겹치지 않게)
                if !compactSideBar {
                    Text(title).font(fonts.uiFont(size: 11, weight: .semibold, relativeTo: .caption2))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compactSideBar ? 8 : 7)
            .foregroundStyle(selected ? DCTheme.accent : Color.primary)
            .background {
                if selected {
                    Capsule().fill(Color.primary.opacity(0.08))   // 선택된 칸 둥근 하이라이트
                }
            }
            .opacity(enabled ? 1 : 0.3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - ⋮ 메뉴

    private func morePopoverHeader(_ title: String) -> some View {
        Text(title)
            .font(fonts.styleFont(.caption))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func morePopoverRow(_ title: String, systemImage: String, dismiss: @escaping () -> Void,
                                action: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .frame(width: 22)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(fonts.styleFont(.body))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 커스텀 팝오버 메뉴: 시스템 Menu 대신 SwiftUI 뷰로 띄워 선택한 글꼴이 그대로 적용됨
    private func morePopover(dismiss: @escaping () -> Void) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                morePopoverRow("설정", systemImage: "gearshape", dismiss: dismiss) { router.sheet = .settings }
                if !darkFollowSystem {
                    morePopoverRow(darkMode ? "다크모드 끄기" : "다크모드 켜기",
                                   systemImage: darkMode ? "sun.max" : "moon",
                                   dismiss: dismiss) { DarkMode.toggle() }
                }

                Divider().padding(.vertical, 4)

                if isPostPage {
                    morePopoverRow(isPostSaved ? "보관한 글 (옮기기 / 빼기)" : "이 글 보관하기",
                                   systemImage: isPostSaved ? "bookmark.fill" : "bookmark",
                                   dismiss: dismiss) { bookmarkTapped() }
                } else if currentGallery != nil {
                    morePopoverRow(isFavorite ? "갤러리 즐겨찾기 해제" : "갤러리 즐겨찾기 추가",
                                   systemImage: isFavorite ? "star.fill" : "star",
                                   dismiss: dismiss) { toggleFavorite() }
                }
                if isPostPage {
                    morePopoverRow("신고하기", systemImage: "exclamationmark.bubble", dismiss: dismiss) { model.reportPost() }
                } else if currentGallery != nil {
                    morePopoverRow("갤러리 공지 보기", systemImage: "megaphone", dismiss: dismiss) { model.openNotice() }
                    morePopoverRow("갤러리 정보 보기", systemImage: "info.circle", dismiss: dismiss) { model.openGalleryInfo() }
                }
                if currentGallery != nil {
                    morePopoverRow("갤러리 관리 내역", systemImage: "list.bullet.clipboard", dismiss: dismiss) { model.openManageLog() }
                }
                if footerGalleryID != nil {
                    morePopoverRow("꼬릿말 설정", systemImage: "text.append", dismiss: dismiss) { showFooterEditor = true }
                }
                if let url = model.url {
                    morePopoverRow("링크 공유", systemImage: "link", dismiss: dismiss) { model.share(shareTarget ?? url) }
                }

                Divider().padding(.vertical, 4)
                morePopoverHeader("캡처")
                morePopoverRow("보이는 화면 캡처", systemImage: "camera.viewfinder", dismiss: dismiss) {
                    Task { await model.captureVisible() }
                }
                morePopoverRow("전체 페이지 캡처", systemImage: "doc.viewfinder", dismiss: dismiss) {
                    Task { await model.captureFullPage() }
                }

                Divider().padding(.vertical, 4)
                morePopoverHeader("차단")
                morePopoverRow(model.isBlockPickMode ? "탭해서 차단 끝내기" : "탭해서 유저 차단",
                               systemImage: "hand.tap", dismiss: dismiss) {
                    model.setBlockPickMode(!model.isBlockPickMode)
                }
                morePopoverRow("차단 설정 가기", systemImage: "hand.raised", dismiss: dismiss) {
                    router.settingsAnchor = "block"
                    router.sheet = .settings
                }

                Divider().padding(.vertical, 4)
                morePopoverHeader("화면 정리")
                morePopoverRow(model.isPickMode ? "요소 숨기기 끝내기" : "요소 숨기기",
                               systemImage: "eye.slash", dismiss: dismiss) {
                    model.setPickMode(!model.isPickMode)
                }

                if showDiagnoseMenu {
                    Divider().padding(.vertical, 4)
                    morePopoverRow("페이지 구조 진단", systemImage: "stethoscope", dismiss: dismiss) {
                        Task { diagnosticText = await model.diagnose() }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 260)
        .frame(maxHeight: 520)
    }

    @ViewBuilder
    private var moreMenu: some View {
        // 맨 위: 설정 (따로 한 칸)
        Section {
            Button { router.sheet = .settings } label: {
                Label("설정", systemImage: "gearshape")
            }
            if !darkFollowSystem {   // 시스템 따라가기가 켜져 있으면 직접 못 바꿈
                Button { DarkMode.toggle() } label: {
                    Label(darkMode ? "다크모드 끄기" : "다크모드 켜기", systemImage: darkMode ? "sun.max" : "moon")
                }
            }
        }
        // 화면에 따라 바뀌는 칸: 글 보기 중 → 글 보관 / 갤러리 목록 → 갤러리 즐겨찾기
        Section {
            if isPostPage {
                Button { bookmarkTapped() } label: {
                    Label(isPostSaved ? "보관한 글 (옮기기 / 빼기)" : "이 글 보관하기",
                          systemImage: isPostSaved ? "bookmark.fill" : "bookmark")
                }
            } else if currentGallery != nil {
                Button { toggleFavorite() } label: {
                    Label(isFavorite ? "갤러리 즐겨찾기 해제" : "갤러리 즐겨찾기 추가",
                          systemImage: isFavorite ? "star.fill" : "star")
                }
            }
            // 글 보기에서는 '갤러리 공지' 자리에 신고하기
            if isPostPage {
                Button { model.reportPost() } label: {
                    Label("신고하기", systemImage: "exclamationmark.bubble")
                }
            } else if currentGallery != nil {
                Button { model.openNotice() } label: {
                    Label("갤러리 공지 보기", systemImage: "megaphone")
                }
                Button { model.openGalleryInfo() } label: {
                    Label("갤러리 정보 보기", systemImage: "info.circle")
                }
            }
            if currentGallery != nil {
                Button { model.openManageLog() } label: {
                    Label("갤러리 관리 내역", systemImage: "list.bullet.clipboard")
                }
            }
            if footerGalleryID != nil {
                Button { showFooterEditor = true } label: {
                    Label("꼬릿말 설정", systemImage: "text.append")
                }
            }
            // (글 보관함은 갤러리 창의 '보관함' 탭으로)
        }
        if let url = model.url {
            // ShareLink를 메뉴 안에 두면 아이패드에서 공유 창이 상단바 제목에 붙어 화면이 깨짐 → 직접 띄움
            Button { model.share(shareTarget ?? url) } label: { Label("링크 공유", systemImage: "link") }
        }
        Section("캡처") {
            Button { Task { await model.captureVisible() } } label: {
                Label("보이는 화면 캡처", systemImage: "camera.viewfinder")
            }
            Button { Task { await model.captureFullPage() } } label: {
                Label("전체 페이지 캡처", systemImage: "doc.viewfinder")
            }
        }
        Section("차단") {
            Button { model.setBlockPickMode(!model.isBlockPickMode) } label: {
                Label(model.isBlockPickMode ? "탭해서 차단 끝내기" : "탭해서 유저 차단",
                      systemImage: "hand.tap")
            }
            Button {
                router.settingsAnchor = "block"
                router.sheet = .settings
            } label: {
                Label("차단 설정 가기", systemImage: "hand.raised")
            }
        }
        Section("화면 정리") {
            Button { model.setPickMode(!model.isPickMode) } label: {
                Label(model.isPickMode ? "요소 숨기기 끝내기" : "요소 숨기기",
                      systemImage: "eye.slash")
            }
        }
        // 버전 정보/업데이트 확인 화면에서 켰을 때만
        if showDiagnoseMenu {
            Button {
                Task { diagnosticText = await model.diagnose() }
            } label: {
                Label("페이지 구조 진단", systemImage: "stethoscope")
            }
        }
    }

    // MARK: - 차단 메뉴 버튼

    /// 길게 누른 대상이 이미 차단돼 있는지 (그러면 차단 대신 해제를 물음 — 실수로 차단했을 때 바로 되돌리기)
    private func isAlreadyBlocked(_ req: BlockRequest) -> Bool {
        !filters.blockedUsers(id: req.userID, ip: req.ip, nick: req.nick, gallery: currentGallery?.id).isEmpty
            || filters.isDcconBlocked(req.dcconKey)
            || !filters.blockedKeywords(in: req.snippet, gallery: currentGallery?.id).isEmpty
    }

    /// 길게 눌러 고른 본문 사진의 원본을 사진 앱에 저장 (PC 원본 → 못 받으면 모바일 사진)
    private func savePhotoOriginal(_ req: BlockRequest, albumID: String?) {
        let page = req.pageURL, index = req.imgIndex, count = req.imgCount, filenos = req.imgFilenos
        let mobile = URL(string: req.imgSrc)
        Task {
            var links: [URL]?
            if index >= 0 { links = await PostPhotoOriginals.links(page: page, count: count) }
            guard let data = await PostPhotoOriginals.original(links: links, index: index, filenos: filenos, mobile: mobile) else {
                model.showToast("사진을 가져오지 못했어요")
                return
            }
            do {
                let album = try await PhotoSaver.save(data, albumID: albumID)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                model.showToast(album.map { "'\($0)' 앨범에 저장했어요" } ?? "사진 앱에 저장했어요")
            } catch PhotoSaver.SaveError.denied {
                model.showToast("설정에서 사진 접근을 허용해주세요")
            } catch {
                model.showToast("저장하지 못했어요")
            }
        }
    }

    /// 차단 확인 창 제목: 사진이면 사진 차단, 아니면 기존 제목
    private func blockDialogTitle(_ req: BlockRequest) -> String {
        if !req.imgKey.isEmpty { return "사진" }
        return isAlreadyBlocked(req) ? "차단 해제/메모/갤로그" : "차단/메모/갤로그"
    }

    @ViewBuilder
    private func blockButtons(_ req: BlockRequest) -> some View {
        if !req.imgKey.isEmpty {
            // 본문 사진: 그 사진만 차단·해제 (작성자 차단 등은 같이 뜨지 않게)
            imageBlockButtons(req)
        } else if isAlreadyBlocked(req) {
            unblockButtons(req)
        } else {
            newBlockButtons(req)
        }
    }

    @ViewBuilder
    private func imageBlockButtons(_ req: BlockRequest) -> some View {
        let store = FilterStore.shared
        Button("원본 저장") {
            if PhotoSaver.askEveryTime { albumAsk = req } else { savePhotoOriginal(req, albumID: PhotoSaver.defaultAlbumID) }
        }
        if store.isImageBlocked(key: req.imgKey) {
            Button("이미지 차단 해제") {
                store.removeImage(key: req.imgKey)
                model.showToast("이미지 차단을 풀었어요")
            }
        } else {
            Button("이 이미지 차단", role: .destructive) {
                let key = req.imgKey, src = req.imgSrc
                store.addImage(key: key, src: src, hash: nil)
                model.showToast("이미지를 차단했어요")
                // 같은 사진을 다른 이름으로 다시 올린 것도 찾도록, 사진을 받아 생김새 해시를 채움 (백그라운드)
                Task {
                    if let h = await ImageBlockHash.fetch(src) { store.setImageHash(key: key, hash: h) }
                }
            }
        }
        // 본문 사진 위 디시 기본 '댓글' 버튼 보임/숨김 (설정 → 세부 설정과 같은 값, Profile.defaults)
        let commentHidden = Profile.defaults.bool(forKey: "hideImgCommentButton")
        Button(commentHidden ? "사진 댓글 버튼 보이기" : "사진 댓글 버튼 숨기기") {
            Profile.defaults.set(!commentHidden, forKey: "hideImgCommentButton")
            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
            model.showToast(commentHidden ? "사진 댓글 버튼을 보여요" : "사진 댓글 버튼을 숨겼어요")
        }
        Button("취소", role: .cancel) {}
    }

    @ViewBuilder
    private func unblockButtons(_ req: BlockRequest) -> some View {
        ForEach(filters.blockedUsers(id: req.userID, ip: req.ip, nick: req.nick, gallery: currentGallery?.id)) { u in
            let who = u.memo.isEmpty ? u.value : "\(u.memo) (\(u.value))"
            Button("\(u.kind.label) 차단 해제: \(who)\(u.gallery == nil ? " · 전체" : " · 이 갤러리")") {
                filters.removeUser(u)
                model.showToast("\(u.memo.isEmpty ? u.value : u.memo) 차단을 풀었어요")
            }
        }
        if filters.settings.dccons.contains(where: { $0.key == req.dcconKey }) {
            Button("디시콘 차단 해제") {
                filters.removeDccon(key: req.dcconKey)
                model.showToast("디시콘 차단을 풀었어요")
            }
        }
        if let p = filters.dcconPackage(containing: req.dcconKey) {
            Button("디시콘 패키지 차단 해제: \(p.name.isEmpty ? p.pkg : p.name)") {
                filters.removeDcconPackage(pkg: p.pkg)
                model.showToast("디시콘 패키지 차단을 풀었어요")
            }
        }
        ForEach(filters.blockedKeywords(in: req.snippet, gallery: currentGallery?.id)) { k in
            Button("키워드 차단 해제: \(k.displayText)\(k.gallery == nil ? " · 전체" : " · 이 갤러리")") {
                filters.removeKeyword(k)
                model.showToast("'\(k.word)' 키워드 차단을 풀었어요")
            }
        }
        searchPostsButton(req)
        memoButton(req)
        gallogButton(req)
        Button("취소", role: .cancel) {}
    }

    @ViewBuilder
    private func newBlockButtons(_ req: BlockRequest) -> some View {
        let name = req.nick.isEmpty ? "작성자" : req.nick
        if !req.userID.isEmpty {
            Button("유저 차단: \(name) (\(req.userID))", role: .destructive) {
                askBlockScope(.id, req.userID, req.nick, label: name)
            }
        }
        if !req.ip.isEmpty {
            Button("IP로 차단: \(name) (\(req.ip))", role: .destructive) {
                askBlockScope(.ip, req.ip, req.nick, label: "\(name)(\(req.ip))")
            }
        }
        if req.userID.isEmpty && !req.nick.isEmpty {
            // 유동은 IP / 닉네임 중 골라서 차단 (닉네임은 같은 닉네임 쓰는 유동 모두 가려짐)
            Button("닉네임으로 차단: \(req.nick) (같은 닉 모두)", role: .destructive) {
                askBlockScope(.nick, req.nick, req.nick, label: req.nick)
            }
        }
        if !req.dcconKey.isEmpty {
            Button("이 디시콘 차단", role: .destructive) {
                filters.addDccon(key: req.dcconKey, imageURL: req.dcconSrc)
                model.showToast("디시콘을 차단했어요")
            }
            Button("이 디시콘 패키지 전체 차단", role: .destructive) {
                blockDcconPackage(req)
            }
        }
        Button("키워드로 차단…") {
            keywordInput = ""
            showKeywordPrompt = true
        }
        searchPostsButton(req)
        memoButton(req)
        gallogButton(req)
        Button("취소", role: .cancel) {}
    }

    /// 길게 누른 디시콘이 속한 패키지 전체를 차단 (디시 목록에서 패키지와 디시콘 번호들을 찾아 저장)
    private func blockDcconPackage(_ req: BlockRequest) {
        model.showToast("디시콘 패키지를 찾는 중이에요")
        Task { @MainActor in
            guard let p = await model.dcconPackage(forKey: req.dcconKey) else {
                model.showToast("이 디시콘의 패키지를 찾지 못했어요. 이 디시콘만 차단해 주세요")
                return
            }
            let keys = p.keys.isEmpty ? [req.dcconKey] : p.keys
            filters.addDcconPackage(pkg: p.pkg, name: p.name, keys: keys)
            model.showToast("디시콘 패키지 '\(p.name.isEmpty ? p.pkg : p.name)' 전체를 차단했어요 (\(keys.count)개)")
        }
    }

    /// 디시 메뉴에 있던 '작성글 검색' (이 갤러리에서 글쓴이로 검색)
    @ViewBuilder
    private func searchPostsButton(_ req: BlockRequest) -> some View {
        if let g = gallery, !req.nick.isEmpty {
            Button("작성글 검색: \(req.nick)") { model.load(g.searchURL(req.nick, type: .name)) }
        }
        // 디시는 식별코드 검색이 없어서, 앱이 목록 여러 쪽을 받아 같은 식별코드(유동은 IP 앞자리)의 글만 모아 줌
        if let g = gallery {
            let key = !req.userID.isEmpty ? req.userID : req.ip
            if !key.isEmpty {
                Button((!req.userID.isEmpty ? "식별코드로 작성글 찾기 (" : "IP로 작성글 찾기 (") + key + ")") {
                    idSearchTarget = IdSearchTarget(gallery: g, code: key)
                }
            }
        }
    }

    /// 고닉·반고닉의 갤로그로 이동 (유동은 갤로그가 없음)
    @ViewBuilder
    private func gallogButton(_ req: BlockRequest) -> some View {
        if !req.userID.isEmpty, let url = URL(string: "https://m.dcinside.com/gallog/\(req.userID)") {
            Button("갤로그 가기") { router.open(url) }
        }
    }

    /// 길게 누르기 메뉴의 '메모': 고닉·반고닉은 아이디에, 유동은 IP / 닉네임 중 골라서
    @ViewBuilder
    private func memoButton(_ req: BlockRequest) -> some View {
        if !req.userID.isEmpty {
            memoChoice(.id, req.userID, req.nick, label: "")
        } else {
            if !req.ip.isEmpty { memoChoice(.ip, req.ip, req.nick, label: "IP(\(req.ip))에 ") }
            if !req.nick.isEmpty { memoChoice(.nick, req.nick, req.nick, label: "닉네임(\(req.nick))에 ") }
        }
    }

    private func memoChoice(_ kind: BlockedUser.Kind, _ value: String, _ nick: String, label: String) -> some View {
        let count = MemoStore.shared.memos(kind: kind, value: value, gallery: currentGallery?.id).count
        return Button(label + (count == 0 ? "메모 남기기…" : "메모 \(count)개 보기·추가…")) {
            // 메뉴가 닫힌 뒤에 다음 창을 띄움 (바로 띄우면 무시될 때가 있음)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                if count == 0 { openMemoEditor(kind, value, nick, existing: nil) } else { memoListTarget = (kind, value, nick) }
            }
        }
    }

    /// 메모 입력 창 (existing이 있으면 그 메모 고치기, 없으면 새 메모)
    private func openMemoEditor(_ kind: BlockedUser.Kind, _ value: String, _ nick: String, existing: UserMemo?) {
        memoInput = existing?.text ?? ""
        memoTarget = (kind, value, nick, existing)
    }

    /// 차단 대상을 고르면 → 갤러리 안이면 범위(이 갤러리만 / 모든 갤러리)를 한 번 더 물음
    private func askBlockScope(_ kind: BlockedUser.Kind, _ value: String, _ nick: String, label: String) {
        if currentGallery == nil {
            filters.addUser(kind: kind, value: value, memo: nick)
            model.showToast("\(label) 차단했어요")
        } else {
            // 차단 메뉴(확인 창)가 닫히는 중에 바로 다음 창을 띄우면 iOS가 무시해서 범위 질문이 안 뜸 → 닫힌 뒤에 띄움
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                pendingBlock = (kind, value, nick, label)
            }
        }
    }

    private func toggleFavorite() {
        guard let g = currentGallery else { return }
        guard let url = model.url else { return }
        let name = Gallery.guessName(title: model.title, url: url, id: g.id)
        if isFavorite {
            favorites.remove(galleryID: g.id, kind: g.kind)
            model.showToast("즐겨찾기에서 뺐어요")
        } else {
            favorites.add(Gallery(galleryID: g.id, name: name, kind: g.kind))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            model.showToast("★ \(name) 추가됨")
        }
    }

    private func blockTyped(_ kind: BlockedUser.Kind) {
        let v = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        filters.addUser(kind: kind, value: v)
        model.showToast("\(kind.label) '\(v)' 차단했어요")
    }
}

extension ToolbarContent {
    /// iOS 26: 상단바 버튼 뒤의 리퀴드 글래스(공유 배경)를 빼서 테두리 없이 보이게
    @ToolbarContentBuilder
    func noGlassBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// 페이지 구조 진단 결과 (차단이 잘 안 될 때 이 내용을 복사해서 보내주면 선택자를 맞출 수 있어요)
struct DiagnosticView: View {
    @ObservedObject var fonts = FontStore.shared
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("페이지 구조 진단")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("복사") { UIPasteboard.general.string = text }
                }
            }
        }
    }
}

// MARK: - 리퀴드 글라스 캡슐 (iOS 26 이상은 진짜 유리 효과, 그 아래는 비슷한 반투명 재질)

extension View {
    func glassBar() -> some View {
        modifier(GlassBarModifier())
    }
}

/// 컨트롤바 유리: 기본은 가장 투명한 .clear, 설정의 '유리 진하기'를 올리면 밝은 막이 더해짐
private struct GlassBarModifier: ViewModifier {
    @AppStorage("barGlassTint", store: Profile.defaults) private var tint = 0.0
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let wash = Color(uiColor: .systemBackground).opacity(tint * 0.6)
        if #available(iOS 26.0, *) {
            // 다크모드에서는 투명 유리가 흐려 안 보여서 불투명한 기본 유리(.regular)를 씀
            if colorScheme == .dark {
                content.glassEffect(.regular.interactive(), in: Capsule())
            } else if tint > 0 {
                content.glassEffect(.clear.interactive().tint(wash), in: Capsule())
            } else {
                content.glassEffect(.clear.interactive(), in: Capsule())
            }
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .background(Capsule().fill(wash))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        }
    }
}


/// 듀오의 오른쪽 빈 줄 정보 (폭, 상단바 아래 끝 위치) — 앱 전체에서 그 줄 위쪽을 가리는 데 씀
@MainActor
final class SideColumnLayout: ObservableObject {
    static let shared = SideColumnLayout()
    @Published private(set) var width: CGFloat = 0
    @Published private(set) var topBarBottom: CGFloat = 0

    func update(width w: CGFloat, topBarBottom t: CGFloat) {
        if abs(width - w) > 0.5 { width = w }
        if abs(topBarBottom - t) > 0.5 { topBarBottom = t }
    }
}


/// 컨트롤바(하단 바 / 아이패드·듀오 세로 바)에 들어가는 버튼 — 순서는 설정에서 바꿀 수 있음
enum ControlBarItem: String, CaseIterable, Identifiable {
    case account, gallery, recommend, search, write, menu
    var id: String { rawValue }
    static let storageKey = "controlBarOrder"
    static let menuInTopBarKey = "menuInTopBar"
    /// 아이패드·듀오 펼친 화면: 가로로 쓸 때 / 세로로 쓸 때 컨트롤바를 세로 막대로 (false면 하단 가로)
    static let verticalLandscapeKey = "controlBarVerticalLandscape"
    static let verticalPortraitKey = "controlBarVerticalPortrait"
    /// 스크롤하는 동안 컨트롤바 숨기기
    static let autoHideKey = "controlBarAutoHide"
    /// 숨기는 방식: 스크롤하는 동안만(기본) / 내리면 숨기고 올리면 표시
    static let autoHideStyleKey = "controlBarAutoHideStyle"
    static let autoHideStyleScrolling = "scrolling"
    static let autoHideStyleDirection = "direction"
    /// 컨트롤바를 동그란 버튼 하나로 접어 둠
    static let collapsedKey = "controlBarCollapsed"
    /// 좌우반전 (왼손용)
    static let mirroredKey = "controlBarMirrored"
    /// 기본값: 가로로 쓸 때는 세로 막대, 세로로 쓸 때는 아이패드만 세로 막대 (아이폰·듀오는 하단 가로)
    static var defaultVerticalInPortrait: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    /// 아이패드, 또는 지금 앱 창이 가로·세로 모두 넓은 화면(듀오 펼침)인지
    /// (설정 시트 안에서는 크기 분류가 좁게 바뀌어서 시트 밖 앱 창 기준으로 봄)
    static var isLargeScreenDevice: Bool {
        if UIDevice.current.userInterfaceIdiom == .pad { return true }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel == .normal }
        return windows.contains {
            $0.traitCollection.horizontalSizeClass == .regular && $0.traitCollection.verticalSizeClass == .regular
        }
    }

    var label: String {
        switch self {
        case .account: "로그인 / 계정"
        case .gallery: "메뉴 (갤러리·기록)"
        case .recommend: "개념글 / 전체글"
        case .search: "검색"
        case .write: "글쓰기"
        case .menu: "설정 (⋮)"
        }
    }
    var icon: String {
        switch self {
        case .account: "person.crop.circle"
        case .gallery: "square.stack"
        case .recommend: "star"
        case .search: "magnifyingglass"
        case .write: "square.and.pencil"
        case .menu: "ellipsis"
        }
    }

    /// 저장된 순서 ("account,gallery,…") → 목록. 빠진 버튼은 뒤에 붙이고, 모르는 이름은 버림
    static func order(from raw: String) -> [ControlBarItem] {
        var list: [ControlBarItem] = []
        for part in raw.split(separator: ",") {
            if let item = ControlBarItem(rawValue: String(part)), !list.contains(item) { list.append(item) }
        }
        for item in allCases where !list.contains(item) { list.append(item) }
        // 설정 ⋮은 항상 맨 끝(오른쪽·아래)
        list.removeAll { $0 == .menu }
        list.append(.menu)
        return list
    }

    static func raw(from list: [ControlBarItem]) -> String { list.map(\.rawValue).joined(separator: ",") }
}

// MARK: - 다크모드 바탕색
extension UIColor {
    /// 디시 페이지 다크모드 바탕(#272729)과 같은 앱 쪽 바탕색. 라이트 모드는 기본 배경
    static let dcPage = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x27/255, green: 0x27/255, blue: 0x29/255, alpha: 1) : .systemBackground }
}

// MARK: - 시트를 파란 상단바 아래까지만
/// 듀오 같은 큰 폰에서 시트가 파란 영역(상단바)을 덮지 않고 그 바로 아래까지만 올라오게 높이를 정함. 일반 아이폰은 기존 높이
extension View {
    @ViewBuilder
    func sheetUnderBlueBar(medium: Bool = false) -> some View {
        if BrowserView.isDuoLikeScreen {
            let winH = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow)?.bounds.height ?? UIScreen.main.bounds.height
            let blue = ListBarMetrics.bottom > 20 ? ListBarMetrics.bottom : 86   // 목록을 아직 안 열었으면 파란 상단바 기본 높이
            let h = max(320, winH - blue)
            if medium { self.presentationDetents([.medium, .height(h)]) } else { self.presentationDetents([.height(h)]) }
        } else {
            if medium { self.presentationDetents([.medium, .large]) } else { self.presentationDetents([.large]) }
        }
    }
}

// MARK: - 듀오 세로 줄 끄기
extension View {
    /// iPhone Duo는 iOS 27.1 SDK로 빌드한 앱의 시계·상단바 버튼을 화면 옆 세로 줄에 세움.
    /// 이걸 끄면 서드파티 브라우저처럼 시계는 위쪽(카메라 왼쪽)에, 화면은 옆 여백 없이 꽉 차게.
    @ViewBuilder
    func keepsTopStatusBar() -> some View {
        self   // 0.9.5 (13) 방식: 가로 고정을 걸지 않고 시스템 기본(듀오 옆 세로 줄)에 맡김 (축이 바뀌는 전환·잔상이 없게)
    }
}

// MARK: - 컨트롤바 꾹 눌러 밀기 (가로 ⇄ 세로 배치 바꾸기)
extension View {
    /// 0.3초 꾹 누른 뒤 밀면 onEnd(밀린 거리). 짧게 누르는 버튼 탭은 그대로 동작
    func barSwitchGesture(onActive: @escaping (Bool) -> Void = { _ in }, onEnd: @escaping (CGSize) -> Void) -> some View {
        modifier(BarSwitchGesture(onActive: onActive, onEnd: onEnd))
    }
}

extension View {
    /// 꾹 누르지 않고 막대를 막대 길이의 30% 이상 한 번에 쓸면 action (어디서 시작하든 상관없음)
    /// 가로 막대는 왼쪽→오른쪽, 세로 막대는 위→아래. 손가락이 처음 버튼 밖으로 나가므로 버튼은 눌리지 않음
    func barSweepGesture(vertical: Bool, action: @escaping () -> Void) -> some View {
        modifier(BarSweepGesture(vertical: vertical, action: action))
    }
}

private struct BarSweepGesture: ViewModifier {
    let vertical: Bool
    let action: () -> Void
    @State private var length: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { vertical ? $0.size.height : $0.size.width } action: { length = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { v in
                        guard length > 0 else { return }
                        let along = vertical ? v.translation.height : v.translation.width
                        let across = vertical ? v.translation.width : v.translation.height
                        if along >= length * 0.3 && abs(along) > abs(across) * 2 { action() }
                    }
            )
    }
}

private struct BarSwitchGesture: ViewModifier {
    let onActive: (Bool) -> Void
    let onEnd: (CGSize) -> Void
    @GestureState private var holding = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(holding ? 1.04 : 1)
            .animation(.spring(duration: 0.25), value: holding)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onActive(true)            // 꾹 눌림 확인 → 막대 안 버튼 잠시 끔
                    }
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($holding) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    }
                    .onEnded { value in
                        if case .second(true, let drag?) = value { onEnd(drag.translation) }
                        onActive(false)
                    }
            )
    }
}


/// 분할 화면의 왼쪽(목록) 화면: 내용을 정해 준 폭 안(왼쪽)에 두고, 바깥은 창 전체 폭으로 되돌려 둠
private struct SplitPane: ViewModifier {
    let width: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let w = width {
            content.frame(width: w).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
        }
    }
}

/// 분할 화면: 가로 하단 바는 왼쪽(목록) 아래가 아니라 오른쪽(글) 화면 아래에 띄움
private struct SplitBottom: ViewModifier {
    let listWidth: CGFloat?
    let totalWidth: CGFloat
    /// 컨트롤바가 왼쪽(좌우반전)이면 목록 아래, 아니면 글 화면 아래 (세로 막대와 같은 쪽)
    var mirrored = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if let l = listWidth {
            if mirrored {
                content.frame(width: max(l, 200)).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content.frame(width: max(totalWidth - l, 200)).frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            content
        }
    }
}

/// 가로 띠 왼쪽 끝의 시계 (TimelineView로 1분마다 다시 그림)
private struct BandClockText: View {
    @ObservedObject var fonts = FontStore.shared
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            Text(ctx.date, style: .time)
                .font(fonts.uiFont(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// 가로 띠 오른쪽 끝의 배터리 (배터리 값이 바뀌면 알림으로 갱신)
private struct BandBatteryText: View {
    @ObservedObject var fonts = FontStore.shared
    @State private var level: Float = UIDevice.current.batteryLevel
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "battery.100")
            Text(level < 0 ? "--" : "\(Int((level * 100).rounded()))%")
        }
        .font(fonts.uiFont(size: 12, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            level = UIDevice.current.batteryLevel
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            level = UIDevice.current.batteryLevel
        }
    }
}

/// 글 목록 상단바(내비게이션 바) 아래 끝 위치 — 글쓰기 상단바 높이를 맞추는 데 씀
enum ListBarMetrics {
    nonisolated(unsafe) static var bottom: CGFloat = 0
}

// MARK: - 알림(토스트)

/// 알림 말풍선: 첫 줄은 제목(굵게), 나머지 줄은 설명 ("\n"으로 구분). 여러 줄이어도 둥근 사각형 안에서 가운데 정렬
struct ToastBubble: View {
    @ObservedObject var fonts = FontStore.shared
    let text: String

    var body: some View {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        VStack(spacing: 4) {
            Text(lines.first ?? "")
                .font(fonts.styleFont(.subheadline, weight: .semibold))
                .multilineTextAlignment(.center)
            if lines.count > 1 {
                Text(lines.dropFirst().joined(separator: "\n"))
                    .font(fonts.styleFont(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .padding(.horizontal, 24)
    }
}

/// 브라우저 화면의 알림: 댓글 입력창이 떠 있으면 위쪽에, 아니면 하단 바 위에 띄움
struct ToastOverlay: View {
    @ObservedObject var model: WebViewModel

    var body: some View {
        let composing = model.commentCompose != nil
        ZStack {
            if model.isRetryingComment {
                RetryingBubble()
                    .transition(.move(edge: composing ? .top : .bottom).combined(with: .opacity))
            } else if let text = model.toast {
                ToastBubble(text: text)
                    .transition(.move(edge: composing ? .top : .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, composing ? 96 : 0)          // 댓글 입력창이 아래를 덮으니 위쪽 (상단 바 아래)
        .padding(.bottom, composing ? 0 : 88)       // 평소엔 하단 바 위
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: composing ? .top : .bottom)
        .animation(.spring(duration: 0.3), value: model.toast)
        .animation(.spring(duration: 0.3), value: model.isRetryingComment)
        .allowsHitTesting(false)
    }
}

/// 429로 막힌 댓글을 자동으로 다시 누르는 동안 떠 있는 말풍선: 톱니바퀴 + 문구 (댓글이 달리거나 멈출 때까지 계속)
struct RetryingBubble: View {
    @ObservedObject var fonts = FontStore.shared
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("댓글을 다는 중입니다")
                .font(fonts.styleFont(.subheadline, weight: .semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .padding(.horizontal, 24)
    }
}

/// 사진 보기·댓글 내용 보기 창 (분할 화면 맨 바깥에 붙여 두는 호스트). 닫히면 웹 화면 레이아웃을 다시 맞춤
struct BrowserCovers: View {
    @ObservedObject var model: WebViewModel
    /// 같이 보이는 다른 웹 화면 (분할 화면이면 반대쪽 글 화면). 창을 닫은 뒤 두 화면을 모두 다시 맞춤
    var other: WebViewModel? = nil

    /// 창을 닫으면 두 웹 화면을 즉시, 그리고 0.15초 뒤 한 번 더 다시 맞춤 (닫히는 중에 새 자리가 드러나도 빈 화면이 남지 않게)
    private func relayout() {
        model.nudgeLayout()
        other?.nudgeLayout()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            model.nudgeLayout()
            other?.nudgeLayout()
        }
    }

    var body: some View {
        Color.clear
            .fullScreenCover(item: $model.imageViewer, onDismiss: { relayout() }) { item in
                ImageViewer(item: item)
                    .presentationBackgroundCompat(.clear)   // 끌어내릴 때 뒤의 글이 비쳐 보이도록
            }
            .fullScreenCover(item: $model.commentText, onDismiss: { relayout() }) { item in
                CommentTextViewer(item: item) { url in
                    model.commentText = nil     // 디시 링크는 닫고 앱 안에서 열기
                    model.load(url)
                }
                .presentationBackgroundCompat(Color.black.opacity(0.4))   // 뒤 화면을 어둡게 (실시간 흐림 효과는 웹뷰 위에서 끌 때 버벅여서 뺌)
            }
            // 투표 보기 사진: 디시 전체 화면 대신 적당한 크기의 앱 창
            .sheet(item: $model.votePreview) { item in
                VoteImagePreviewSheet(item: item)
            }
            // 백그라운드 댓글 등록 중 보안 확인(Turnstile)이 필요할 때 사용자가 직접 체크할 수 있는 시트
            .sheet(item: $model.turnstileChallenge) { challenge in
                CommentTurnstileSheet(challenge: challenge)
            }
    }
}

/// 시스템 Menu 대신 커스텀 SwiftUI 팝오버를 띄워 선택한 글꼴이 그대로 적용되도록 하는 버튼
private struct MorePopoverButton<Label: View, MenuContent: View>: View {
    @State private var open = false
    @ViewBuilder let menuContent: (@escaping () -> Void) -> MenuContent
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button { open = true } label: { label() }
            .popover(isPresented: $open) {
                menuContent { open = false }
                    .foregroundStyle(Color.primary)
                    .tint(Color.primary)
                    .popoverAdaptationCompat()
            }
    }
}

/// 429 "너무 많은 요청으로 이용하실 수 없습니다" 전용 안내 오버레이 (다크모드·테마색 지원)
private struct RateLimitOverlayView: View {
    let tries: Int
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(DCTheme.accent.opacity(0.12))
                        .frame(width: 68, height: 68)
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(DCTheme.accent)
                }
                VStack(spacing: 6) {
                    Text("잠시 요청이 몰려 있어요")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("디시인사이드에서 일시적으로 접속을 제한하고 있어요.\n정상화될 때까지 자동으로 다시 불러오는 중이에요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("자동 재시도 중… (\(max(1, tries))회)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
                Button("지금 다시 시도", action: onRetry)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DCTheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DCTheme.accent.opacity(0.12), in: Capsule())
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28)
        }
    }
}
