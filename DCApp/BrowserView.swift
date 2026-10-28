import SwiftUI
import Combine

/// 앱 테마 (설정 → 앱 → 테마). 상단바 색, 강조색(하단 바 선택 등), 웹페이지 속 디시 파란색 계열을 바꿀 색
enum AppTheme: String, CaseIterable, Identifiable {
    case dc, navy, green, gray
    var id: String { rawValue }

    var name: String {
        switch self {
        case .dc: "디시 (기본)"
        case .navy: "남색"
        case .green: "연두"
        case .gray: "무채색"
        }
    }

    /// 상단바 색
    var bar: UIColor {
        switch self {
        case .dc: UIColor(red: 0.231, green: 0.282, blue: 0.565, alpha: 1)    // 디시 고유 색 (#3B4890)
        case .navy: UIColor(red: 0.29, green: 0.33, blue: 0.64, alpha: 1)     // 예전 기본색
        case .green: UIColor(red: 0.01, green: 0.78, blue: 0.35, alpha: 1)    // 네이버 초록 (#03C75A)
        case .gray: UIColor(red: 0.33, green: 0.33, blue: 0.35, alpha: 1)
        }
    }

    /// 강조색 — 밝은 화면 / 어두운 화면(다크 모드에서는 잘 보이게 밝게)
    var accentLight: UIColor {
        switch self {
        case .dc, .navy: bar
        case .green: UIColor(red: 0.0, green: 0.62, blue: 0.29, alpha: 1)      // 흰 바탕 글자용으로 조금 진하게
        case .gray: UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1)
        }
    }
    var accentDark: UIColor {
        switch self {
        case .dc, .navy: UIColor(red: 0.55, green: 0.62, blue: 1.0, alpha: 1)
        case .green: UIColor(red: 0.18, green: 0.88, blue: 0.48, alpha: 1)
        case .gray: UIColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1)
        }
    }

    /// 웹페이지 속 디시 파란색 계열을 바꿀 색 (h: 색상각, s: 채도 배율). nil이면 사이트 색 그대로
    var pageTint: [String: Double]? {
        switch self {
        case .dc, .navy: nil
        case .green: ["h": 147, "s": 1.6]
        case .gray: ["h": 230, "s": 0]
        }
    }
}

/// 앱 색상 — 지금 고른 테마를 따름
enum DCTheme {
    static let storageKey = "appTheme"
    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .dc
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

/// 갤러리 내 검색 창 (말머리 / 검색 범위 / 개념글만 / 최근 검색어)
struct GallerySearchSheet: View {
    let gallery: Gallery
    var heads: [HeadTab] = []
    let onSearch: (URL) -> Void
    @State private var head: HeadTab?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gallerySearchType") private var typeRaw = GallerySearchType.subjectMemo.rawValue
    @State private var keyword = ""
    @State private var recommendOnly = false
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: "gallerySearchRecent") ?? []
    @FocusState private var focused: Bool

    private var type: GallerySearchType { GallerySearchType(rawValue: typeRaw) ?? .subjectMemo }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("검색어", text: $keyword)
                            .focused($focused)
                            .submitLabel(.search)
                            .onSubmit { search(keyword) }
                    }
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
                    Text("\(gallery.name)에서 검색")
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
                            Button("전체 삭제") { recent.removeAll(); saveRecent() }.font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("갤러리 검색")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("검색") { search(keyword) }
                        .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                Task { try? await Task.sleep(for: .milliseconds(350)); focused = true }
            }
        }
        .presentationDetents([.medium, .large])
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

    private func saveRecent() { UserDefaults.standard.set(recent, forKey: "gallerySearchRecent") }
}

/// 웹뷰 + 남색 상단바 + 공식 앱 스타일 하단 바. NavigationStack 안에 넣어서 사용하세요.
struct BrowserView: View {
    @StateObject private var model: WebViewModel
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var autoImages = AutoImageStore.shared
    @ObservedObject private var savedPosts = SavedPostStore.shared
    @ObservedObject private var alarms = AlarmStore.shared
    @ObservedObject private var hwKeyboard = HardwareKeyboard.shared
    @AppStorage("compactMode") private var compactMode = false
    /// 오른쪽 세로 버튼 막대 (끄면 ⋮ 메뉴가 상단바로 감)
    /// 오른쪽 세로 버튼 막대는 없앰 (⋮는 상단바, 한손 모드는 제목 길게 누르기, 글 볼 때만 댓글 새로고침 버튼)
    private let showFloatingBar = false
    /// 컨트롤바 버튼 순서 (설정에서 바꿈)
    @AppStorage(ControlBarItem.storageKey) private var controlOrderRaw = ""
    /// ⋮ 메뉴를 상단바 오른쪽에 둘지 (켜면 컨트롤바에서는 빠짐)
    @AppStorage(ControlBarItem.menuInTopBarKey) private var menuInTopBar = false

    // 글쓰기 화면 → 이 갤러리 자짤 설정 창
    @State private var autoImageGallery: String?
    private var writeGalleryID: String? { model.url.flatMap(AutoImageStore.writeGalleryID) }

    // 글쓰기 화면의 계정 버튼에 표시할 현재 계정
    @State private var currentAccount: String? = CredentialStore.currentAccountID

    // 글 보관 버튼: 폴더 고르기 / 이미 보관한 글 메뉴
    @State private var showSaveFolderPicker = false
    @State private var savedPostMenu: SavedPost?
    let fallbackTitle: String
    /// 왼쪽 위 ☰ 버튼 (홈 탭의 메인 브라우저에서만 표시, 다른 곳은 뒤로가기 버튼 자리)
    var showsMenuButton = false


    // 갤러리 내 검색
    @State private var showGallerySearch = false
    @State private var galleryHeads: [HeadTab] = []
    @State private var gallerySearchText = ""

    // 유저 직접 입력 차단
    @State private var showUserPrompt = false
    @State private var userInput = ""

    // 유저 메모 입력 (길게 누르기 → 메모)
    @State private var memoTarget: (kind: BlockedUser.Kind, value: String, nick: String, existing: UserMemo?)?
    // 차단 범위 고르기 (이 갤러리만 / 모든 갤러리)
    @State private var pendingBlock: (kind: BlockedUser.Kind, value: String, nick: String, label: String)?
    @State private var memoInput = ""

    // 키워드 차단 입력
    @State private var showKeywordPrompt = false
    @State private var keywordInput = ""

    // 구조 진단
    @State private var diagnosticText: String?

    // 임시저장 불러오기
    @State private var showDraftPicker = false

    // 키보드가 떠 있는 동안에는 앱 툴바를 숨겨서, 디시 댓글창(유동 닉/비번/코드, 디시콘 버튼)이
    // 사파리처럼 키보드 바로 위에 붙도록 함
    @State private var keyboardVisible = false
    /// 웹페이지 위에 떠 있는 하단 바(+안내 배너) 높이 → 그만큼 페이지 아래에 스크롤 여백
    @State private var bottomBarHeight: CGFloat = 0
    /// 화면 오른쪽 안전 영역 폭 (듀오의 시계·카메라 줄 등) — 창(UIWindow)에서 직접 읽음
    @State private var trailingInset: CGFloat = 0
    /// 오른쪽 안전 영역이 버튼이 들어갈 만큼 넓은지 (듀오)
    /// 듀오 오른쪽 빈 줄에 컨트롤바를 넣던 방식은 쓰지 않음 (가끔 바가 사라짐) → 일반 아이폰처럼 하단 바
    private var hasSideColumn: Bool { false }
    /// 듀오처럼 오른쪽 안전 영역이 넓으면 웹페이지가 그 줄까지 씀
    private var fillsTrailing: Bool { trailingInset >= 56 }
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @AppStorage(ControlBarItem.verticalLandscapeKey) private var verticalInLandscape = true
    @AppStorage(ControlBarItem.autoHideKey) private var autoHideBar = true
    /// 스크롤 중이라 컨트롤바를 화면 밖으로 넣었는지
    private var barTucked: Bool { autoHideBar && model.isScrolling }
    @AppStorage(ControlBarItem.verticalPortraitKey) private var verticalInPortrait = ControlBarItem.defaultVerticalInPortrait
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
        lastTopBarBottom = top
        applySideColumn()
        // 접기·펴기·앱 전환 직후엔 안전 영역 값이 잠깐 0으로 읽힐 때가 있어서 조금 뒤에 한 번 더 읽음
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300)); applySideColumn()
            try? await Task.sleep(for: .milliseconds(700)); applySideColumn()
        }
    }
    private func applySideColumn() {
        let inset = Self.windowTrailingInset
        if inset != trailingInset { trailingInset = inset }
        guard showsMenuButton else { return }
        SideColumnLayout.shared.update(width: 0, topBarBottom: lastTopBarBottom)
    }

    /// 앱 화면이 그려지는 일반 창에서 읽음 (앱 잠금·가림 화면 같은 덧씌운 창은 제외 — 그쪽이 키 창이면 0이 나올 수 있음)
    private static var windowTrailingInset: CGFloat {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel == .normal && !$0.isHidden }
        return windows.map(\.safeAreaInsets.right).max() ?? 0
    }

    init(startURL: URL, fallbackTitle: String) {
        _model = StateObject(wrappedValue: WebViewModel(url: startURL))
        self.fallbackTitle = fallbackTitle
    }

    /// 이미 만들어진 브라우저(홈 탭의 메인 브라우저 등)를 화면에 붙일 때
    init(model: WebViewModel, fallbackTitle: String, showsMenuButton: Bool = false) {
        _model = StateObject(wrappedValue: model)
        self.fallbackTitle = fallbackTitle
        self.showsMenuButton = showsMenuButton
    }

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

    /// 상단바 제목: 갤러리 안이면 갤러리 이름, 아니면 페이지 제목
    private var titleText: String {
        if let g = gallery { return g.name }
        return model.title.isEmpty ? fallbackTitle : Gallery.cleanTitle(model.title)
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
    var body: some View { layer7 }

    /// 웹뷰 + 상단바 + 하단 바 + 키보드 감지
    private var layer1: some View {
        WebView(model: model)
            .ignoresSafeArea(.keyboard, edges: .bottom)   // 키보드 처리는 웹뷰(WebKit)에 맡김
            // 하단 바 뒤 화면 아래 끝까지 웹페이지가 쓰도록. 좌우 안전 영역(듀오의 시계·카메라 줄)은 사파리처럼 비워 둠
            .ignoresSafeArea(.container, edges: fillsTrailing ? [.bottom, .trailing] : .bottom)
            // 상단바 뒤~화면 맨 위까지 남색으로 (듀오를 펼치면 상단바 위에 띠가 생기고, 내비게이션 화면의 기본 흰 배경이 보임)
            // 웹페이지 뒤에 깔리므로 다른 곳에는 안 보임
            // 웹페이지 위쪽(상단바 뒤 ~ 화면 맨 위)만 남색으로, 오른쪽 빈 줄(듀오)의 위쪽까지 포함.
            // 웹페이지 위쪽 안전 영역 높이(상단바+그 위 띠)를 재서 그만큼만 위로 그림 → 상단바 아래 빈 줄은 칠하지 않음
            .background {
                GeometryReader { g in
                    let top = g.safeAreaInsets.top
                    DCTheme.navy
                        .frame(width: g.size.width + g.safeAreaInsets.leading, height: top + 1)   // 오른쪽 빈 줄은 칠하지 않음
                        .offset(x: -g.safeAreaInsets.leading, y: -top)
                }
            }
            .background {
                // 예비: 웹페이지 폭만큼은 화면 맨 위까지 (위 방법이 안 먹히는 경우 대비)
                DCTheme.navy.ignoresSafeArea(.container, edges: .top)
            }
            .overlay(alignment: .top) { topOverlay }
            .overlay {
                // 화면 크기가 바뀔 때마다(접기·펴기·회전) 오른쪽 안전 영역 폭을 다시 읽음
                GeometryReader { g in
                    Color.clear
                        .onAppear { viewSize = g.size; updateSideColumn(top: g.frame(in: .global).minY) }
                        .onChange(of: g.size) { _, sz in viewSize = sz; updateSideColumn(top: g.frame(in: .global).minY) }
                        .onChange(of: g.frame(in: .global).minY) { _, y in updateSideColumn(top: y) }
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .buttonStyle(.plain)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .padding(.leading, 12)
                    .padding(.bottom, 8 + model.writeToolbarHeight)     // 키보드 위 글쓰기 도구줄 위로
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
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(DCTheme.navy, in: Capsule())
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if usesSideBar {
                        if !keyboardVisible {
                            if barCollapsed {
                                collapsedBarButton
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            } else { sideBar }
                        }
                    } else if showsMenuButton && showsRefresh && !keyboardVisible && !barCollapsed {
                        refreshButtonPlaced        // 글 볼 때: 댓글 새로고침 / 글 목록: 페이지 새로고침
                    }
                }
                // 스크롤하는 동안 오른쪽 밖으로 들어갔다가 멈추면 다시 나옴
                .offset(x: barTucked ? 220 : 0)
                .animation(.easeOut(duration: 0.2), value: barTucked)
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { topBar }
            .keepsTopStatusBar()   // 듀오: 시계·버튼을 오른쪽 세로 줄로 보내지 않고 위쪽 가로로
            .toolbarBackground(DCTheme.navy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            // 하단 바: 페이지를 잘라내지 않고 그 위에 띄움 (리퀴드 글래스 너머로 페이지가 비침)
            .overlay(alignment: .bottom) {
                if !keyboardVisible {
                    VStack(spacing: 0) {
                        modeBanner
                        if showsMenuButton && !usesSideBar {
                            Group { if barCollapsed { collapsedBarButton } else { galleryBar } }
                                // 스크롤하는 동안 화면 아래로 들어갔다가 멈추면 다시 나옴
                                .offset(y: barTucked ? 160 : 0)
                                .animation(.easeOut(duration: 0.2), value: barTucked)
                        }
                    }
                    .background {
                        GeometryReader { g in
                            Color.clear
                                .onAppear { bottomBarHeight = g.size.height }
                                .onChange(of: g.size.height) { _, h in bottomBarHeight = h }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: bottomBarHeight) { _, _ in updateBottomInset() }
            .onChange(of: keyboardVisible) { _, _ in updateBottomInset() }
            // 키보드가 정말 화면에 올라와 있는지는 키보드 위치로 판단 (화면을 돌릴 때 오는 알림만 보고 바를 숨기지 않게)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { n in
                keyboardFrameChanged(n)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
                keyboardFrameChanged(n)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                setKeyboardVisible(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                setKeyboardVisible(false)
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
    }

    /// 차단 메뉴 / 요소 숨기기 확인
    private var layer2: some View {
        layer1
            .confirmationDialog(model.blockRequest.map { isAlreadyBlocked($0) } == true ? "차단 해제" : "차단",
                                isPresented: Binding(get: { model.blockRequest != nil },
                                                     set: { if !$0 { model.blockRequest = nil } }),
                                titleVisibility: .visible,
                                presenting: model.blockRequest) { req in
                blockButtons(req)
            } message: { req in
                Text(req.snippet.isEmpty ? (isAlreadyBlocked(req) ? "차단을 풀까요?" : "무엇을 차단할까요?") : req.snippet)
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
            }
    }

    /// 토스트 / 키워드·유저 차단 입력
    private var layer3: some View {
        layer2
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 88)   // 하단 바 위에 표시
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: model.toast)
            .alert("키워드 차단", isPresented: $showKeywordPrompt) {
                TextField("차단할 단어", text: $keywordInput)
                Button("취소", role: .cancel) {}
                Button("추가") {
                    filters.addKeyword(keywordInput)
                    if !keywordInput.trimmingCharacters(in: .whitespaces).isEmpty {
                        model.showToast("'\(keywordInput)' 키워드 차단")
                    }
                }
            } message: {
                Text("이 단어가 들어간 글과 댓글을 가려요.")
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
        MemoStore.shared.set(kind: t.kind, value: t.value, text: memoInput, gallery: gallery, replacing: t.existing)
        let empty = memoInput.trimmingCharacters(in: .whitespaces).isEmpty
        model.showToast(empty ? "메모를 지웠어요" : (gallery == nil ? "메모를 남겼어요 (모든 갤러리)" : "메모를 남겼어요 (이 갤러리)"))
    }

    /// 캡처 / 보관 폴더 고르기 / 유저 메모 / 차단 범위
    private var layer4: some View {
        layer3
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
            .alert("유저 메모", isPresented: Binding(get: { memoTarget != nil }, set: { if !$0 { memoTarget = nil } })) {
                TextField("메모 (비우면 삭제)", text: $memoInput)
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
                Button("취소", role: .cancel) {}
            }
    }

    /// 보관한 글 메뉴
    private var layer5: some View {
        layer4
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
        layer5
            .sheet(isPresented: $showGallerySearch) {
                if let g = gallery {
                    GallerySearchSheet(gallery: g, heads: galleryHeads) { url in model.load(url) }
                }
            }
            .sheet(isPresented: $showDraftPicker) {
                DraftPickerSheet(galleryID: model.url.flatMap(AutoImageStore.writeGalleryID)) { d in
                    model.restoreDraft(d)
                }
            }
            .sheet(isPresented: Binding(get: { diagnosticText != nil },
                                        set: { if !$0 { diagnosticText = nil } })) {
                DiagnosticView(text: diagnosticText ?? "")
            }
    }

    /// 글쓰기 화면 → 이 갤러리 자짤 설정 / 사진 보기
    private var layer7: some View {
        layer6
            .fullScreenCover(item: $model.imageViewer) { item in
                ImageViewer(item: item)
                    .presentationBackground(.clear)   // 끌어내릴 때 뒤의 글이 비쳐 보이도록
            }
            .sheet(isPresented: Binding(get: { autoImageGallery != nil },
                                        set: { if !$0 { autoImageGallery = nil } })) {
                if let gid = autoImageGallery {
                    NavigationStack {
                        GalleryAutoImageView(galleryID: gid, name: gallery?.name ?? gid)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("완료") { autoImageGallery = nil }
                                }
                            }
                    }
                }
            }
    }

    // MARK: - 상단: 로딩바 / 캡처 중

    @ViewBuilder
    private var topOverlay: some View {
        VStack(spacing: 0) {
            if model.isLoading {
                ProgressView(value: model.progress).progressViewStyle(.linear)
            }
            if model.isCapturing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("전체 페이지 캡처 중…")
                }
                .font(.subheadline)
                .padding(10)
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
                    Text(currentAccount == nil ? "로그인" : "계정").font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 10 : 7)
            .foregroundStyle(currentAccount == nil ? Color.primary : DCTheme.accent)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
               autoImages.effective(for: gid).enabled || !autoImages.settings.images.isEmpty {
                HStack(spacing: 8) {
                    Spacer()
                    if autoImages.effective(for: gid).enabled {
                        // 누르면 자짤 첨부, 길게 누르면 이 갤러리 자짤 설정
                        Menu {
                            Button { model.attachAutoImage(force: true) } label: {
                                Label("자짤 첨부", systemImage: "photo.badge.plus")
                            }
                            Button { autoImageGallery = gid } label: {
                                Label("이 갤러리 자짤 설정", systemImage: "slider.horizontal.3")
                            }
                        } label: {
                            Text("자짤")
                        } primaryAction: {
                            model.attachAutoImage(force: true)
                        }
                    } else {
                        Button("자짤 꺼짐") { autoImageGallery = gid }
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.subheadline)
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
                .font(.subheadline)
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
                .font(.subheadline)
                .padding(10)
                .background(.thinMaterial)
                .overlay(alignment: .top) { Divider() }
            }
    }

    // MARK: - 상단바 (남색): 제목만 (메인 화면). 설정 안에서 연 화면은 오른쪽에 ☆ ⋮

    @ToolbarContentBuilder
    private var topBar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(titleText)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                // 제목이 길면(디시 첫 화면 제목 등) 넓은 화면에서 양옆 버튼 자리를 밀어내 로그인 버튼이 사라짐 → 폭 제한
                .frame(maxWidth: 240)
                .contentShape(Rectangle())
                // 갤러리 이름을 0.5초 누르면 한손 모드 켜기/끄기
                .onLongPressGesture(minimumDuration: 0.5) {
                    guard showsMenuButton else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    compactMode.toggle()
                }
        }
        if showsMenuButton {
            // 글쓰기 화면: 왼쪽 (⋮) 로그인 / 오른쪽 임시저장 불러오기 등록
            // (한 칸에 묶어서 넣어야 공간이 모자라도 '…'로 접히지 않음, 테두리(글래스)는 뺌)
            if model.isWritePage {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        if hwKeyboard.connected { backButton { Image(systemName: "chevron.backward") } }
                        accountMenu                          // 로그인 / 계정 (글쓰기 화면은 컨트롤바 대신 여기)
                        if menuInTopBar { topMoreMenu }     // 글쓰기 화면은 오른쪽이 임시저장·등록이라 ⋮는 왼쪽
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
                                .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1.2))
                                .contentShape(Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize()
                }
                .noGlassBackground()
            } else {
                // 다른 화면: 왼쪽은 (하드웨어 키보드일 때) 뒤로가기, 오른쪽 위에 ⋮ 고정
                if hwKeyboard.connected {
                    ToolbarItem(placement: .topBarLeading) {
                        backButton { Image(systemName: "chevron.backward") }
                            .foregroundStyle(.white)
                    }
                    .noGlassBackground()
                }
                // ⋮ 메뉴: 설정에서 '상단바에 두기'를 켰을 때만 오른쪽 위 (아니면 컨트롤바 안)
                if menuInTopBar {
                    ToolbarItem(placement: .topBarTrailing) { topMoreMenu.foregroundStyle(.white) }
                        .noGlassBackground()
                }
            }
        } else {
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
        Button { refreshTapped() } label: {
            floatIcon("arrow.clockwise", tint: .primary)
        }
        .padding(4)
        .glassBar()
        .padding(.trailing, 12)
            .padding(.bottom, 16 + bottomBarHeight)      // 페이지 위에 떠 있는 하단 바 위로
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
            if hwKeyboard.connected {
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

    private var isPostPage: Bool { model.url.flatMap(SavedPostStore.postInfo) != nil }

    /// 갤러리 글 목록 화면인지 (model.url을 읽어 주소가 바뀌면 다시 그림)
    private var isListPage: Bool {
        let _ = model.url
        return model.isGalleryListPage
    }

    /// 새로고침 버튼을 보일 화면: 글 보기 + 글 목록
    private var showsRefresh: Bool { isPostPage || isListPage }

    /// 글 보기 → 댓글 새로고침, 글 목록 → 페이지 새로고침
    private func refreshTapped() {
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
    @AppStorage(ControlBarItem.collapsedKey) private var barCollapsed = false

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
    private var collapsedBarButton: some View {
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
                    if t.width < -30 && abs(t.width) > abs(t.height) {
                        expandBar(vertical: false)        // 왼쪽으로 밀기 → 가로 막대
                    } else if t.height < -30 && abs(t.height) > abs(t.width) {
                        expandBar(vertical: true)         // 위로 밀기 → 세로 막대
                    }
                }
        )
        .padding(.trailing, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func collapsedIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(Color.primary)
            .frame(width: 52, height: showsRefresh ? 48 : 52)
            .contentShape(Rectangle())
    }

    private var galleryBar: some View {
        HStack(spacing: 2) { galleryBarItems }
            .disabled(barGestureActive)
            .padding(6)
            .glassBar()
            .barSweepGesture(vertical: false) { collapseBar() }   // 그냥 끝에서 끝까지 오른쪽으로 쓸면 접기
            .barSwitchGesture(onActive: barGestureChanged) { t in
                if t.width > 40 && abs(t.width) > abs(t.height) {
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
            Group { galleryBarItems }.disabled(barGestureActive)
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
                .barSweepGesture(vertical: true) { collapseBar() }    // 그냥 위에서 아래까지 쓸면 접기
                .barSwitchGesture(onActive: barGestureChanged) { t in
                    if t.height > 40 && abs(t.height) > abs(t.width) {
                        collapseBar()             // 꾹 누른 채 아래로 → 동그란 버튼 하나
                    }
                }
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }

    /// 웹페이지 아래에 하단 바 높이만큼 스크롤 여백 (바에 가려지지 않게)
    private func updateBottomInset() {
        model.setBottomBarInset(keyboardVisible ? 0 : bottomBarHeight)
    }

    /// 컨트롤바 버튼들 — 순서는 설정 → 컨트롤바 버튼 순서에서 바꿀 수 있음
    private var galleryBarItems: some View {
        // 글쓰기 화면은 로그인을 상단바 왼쪽에 두므로 컨트롤바에서는 뺌
        ForEach(ControlBarItem.order(from: controlOrderRaw).filter { !(menuInTopBar && $0 == .menu) && !(model.isWritePage && $0 == .account) }) { item in
            controlItem(item)
        }
    }

    @ViewBuilder
    private func controlItem(_ item: ControlBarItem) -> some View {
        let g = gallery
        switch item {
        case .account:
            // 로그인 / 계정
            accountBarItem
        case .gallery:
            barItem("square.stack", "square.stack.fill", "갤러리", selected: false) {
                router.sheet = .library
            }
            .overlay(alignment: .top) {
                // 안 읽은 알림이 있으면 빨간 점 (갤러리 창 → 알림 탭)
                if alarms.unreadCount > 0 {
                    Circle().fill(.red).frame(width: 8, height: 8).offset(x: 12, y: 6).allowsHitTesting(false)
                }
            }
        case .recommend:
            // 전체글 보는 중 → "개념글" / 개념글 보는 중 → "전체글"(≡)로 바뀜
            if section == .recommend {
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
                if let g {
                    model.focusTitleOnWrite = true      // 열리면 제목 칸에 바로 키보드
                    model.load(g.writeURL)
                }
            }
        case .menu:
            // ⋮ 메뉴 (상단바에서 컨트롤바로 옮김)
            let compact = compactSideBar
            Menu { moreMenu } label: {
                VStack(spacing: 2) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 19, weight: .medium))
                        .frame(height: 24)
                    if !compact { Text("메뉴").font(.system(size: 11, weight: .semibold)) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 10 : 7)
                .foregroundStyle(Color.primary)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
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
                    Text(title).font(.system(size: 11, weight: .semibold))
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

    @ViewBuilder
    private var moreMenu: some View {
        // 맨 위: 설정 (따로 한 칸)
        Section {
            Button { router.sheet = .settings } label: {
                Label("설정", systemImage: "gearshape")
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
            if currentGallery != nil {
                Button { model.openNotice() } label: {
                    Label("갤러리 공지 보기", systemImage: "megaphone")
                }
                Button { model.openManageLog() } label: {
                    Label("갤러리 관리 내역", systemImage: "list.bullet.clipboard")
                }
            }
            // (글 보관함은 갤러리 창의 '보관함' 탭으로)
        }
        Section {
            Button { model.goForward() } label: { Label("앞으로", systemImage: "chevron.forward") }
                .disabled(!model.canGoForward)
            Button { model.reload() } label: { Label("새로고침", systemImage: "arrow.clockwise") }
            if showsMenuButton && !showFloatingBar {
                if isPostPage {
                    Button { model.refreshComments() } label: {
                        Label("댓글 새로고침", systemImage: "arrow.clockwise.circle")
                    }
                }
                Button { compactMode.toggle() } label: {
                    Label(compactMode ? "한손 모드 끄기" : "한손 모드 켜기", systemImage: "rectangle.bottomhalf.inset.filled")
                }
            }
        }
        if let url = model.url {
            // ShareLink를 메뉴 안에 두면 아이패드에서 공유 창이 상단바 제목에 붙어 화면이 깨짐 → 직접 띄움
            Button { model.share(url) } label: { Label("링크 공유", systemImage: "link") }
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
            Button {
                Task {
                    if let author = await model.articleAuthor() {
                        model.blockRequest = author
                    } else {
                        model.showToast("글 보기 화면에서 쓸 수 있어요")
                    }
                }
            } label: {
                Label("이 글 작성자 차단", systemImage: "person.fill.xmark")
            }
            Button { model.setBlockPickMode(!model.isBlockPickMode) } label: {
                Label(model.isBlockPickMode ? "탭해서 차단 끝내기" : "탭해서 유저 차단",
                      systemImage: "hand.tap")
            }
            Button {
                userInput = ""
                showUserPrompt = true
            } label: {
                Label("유저 직접 입력해서 차단", systemImage: "person.crop.circle.badge.plus")
            }
            Button {
                keywordInput = ""
                showKeywordPrompt = true
            } label: {
                Label("키워드 차단 추가", systemImage: "text.badge.xmark")
            }
        }
        Section("화면 정리") {
            Button { model.setPickMode(!model.isPickMode) } label: {
                Label(model.isPickMode ? "요소 숨기기 끝내기" : "요소 숨기기 (탭해서 선택)",
                      systemImage: "eye.slash")
            }
        }
        Button {
            Task { diagnosticText = await model.diagnose() }
        } label: {
            Label("페이지 구조 진단", systemImage: "stethoscope")
        }
    }

    // MARK: - 차단 메뉴 버튼

    /// 길게 누른 대상이 이미 차단돼 있는지 (그러면 차단 대신 해제를 물음 — 실수로 차단했을 때 바로 되돌리기)
    private func isAlreadyBlocked(_ req: BlockRequest) -> Bool {
        !filters.blockedUsers(id: req.userID, ip: req.ip, nick: req.nick, gallery: currentGallery?.id).isEmpty
            || filters.isDcconBlocked(req.dcconKey)
            || !filters.blockedKeywords(in: req.snippet).isEmpty
    }

    @ViewBuilder
    private func blockButtons(_ req: BlockRequest) -> some View {
        if isAlreadyBlocked(req) {
            unblockButtons(req)
        } else {
            newBlockButtons(req)
        }
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
        if filters.isDcconBlocked(req.dcconKey) {
            Button("디시콘 차단 해제") {
                filters.removeDccon(key: req.dcconKey)
                model.showToast("디시콘 차단을 풀었어요")
            }
        }
        ForEach(filters.blockedKeywords(in: req.snippet), id: \.self) { w in
            Button("키워드 차단 해제: \(w)") {
                filters.removeKeyword(w)
                model.showToast("'\(w)' 키워드 차단을 풀었어요")
            }
        }
        memoButton(req)
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
        }
        Button("키워드로 차단…") {
            keywordInput = ""
            showKeywordPrompt = true
        }
        memoButton(req)
        Button("취소", role: .cancel) {}
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
        let existing = MemoStore.shared.memo(kind: kind, value: value, gallery: currentGallery?.id)
        return Button(label + (existing == nil ? "메모 남기기…" : "메모 고치기…")) {
            memoInput = existing?.text ?? ""
            // 메뉴가 닫힌 뒤에 메모 창을 띄움 (바로 띄우면 무시될 때가 있음)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                memoTarget = (kind, value, nick, existing)
            }
        }
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
    @ViewBuilder
    func glassBar() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self
                .background(.regularMaterial, in: Capsule())
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
    /// 컨트롤바를 동그란 버튼 하나로 접어 둠
    static let collapsedKey = "controlBarCollapsed"
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
        case .gallery: "갤러리"
        case .recommend: "개념글 / 전체글"
        case .search: "검색"
        case .write: "글쓰기"
        case .menu: "메뉴 (⋮)"
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
        return list
    }

    static func raw(from list: [ControlBarItem]) -> String { list.map(\.rawValue).joined(separator: ",") }
}

// MARK: - 듀오 세로 줄 끄기
extension View {
    /// iPhone Duo는 iOS 27.1 SDK로 빌드한 앱의 시계·상단바 버튼을 화면 옆 세로 줄에 세움.
    /// 이걸 끄면 서드파티 브라우저처럼 시계는 위쪽(카메라 왼쪽)에, 화면은 옆 여백 없이 꽉 차게.
    @ViewBuilder
    func keepsTopStatusBar() -> some View {
        if #available(iOS 27.1, *) {
            self.toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
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
