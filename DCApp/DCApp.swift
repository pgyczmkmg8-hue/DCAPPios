import SwiftUI
import Combine

/// 디시인사이드 관련 주소 모음. 사이트 구조가 바뀌면 여기만 고치면 됩니다.
enum DC {
    static let home = URL(string: "https://m.dcinside.com/")!
    static let login = URL(string: "https://msign.dcinside.com/login?r_url=https%3A%2F%2Fm.dcinside.com")!
    static let dccon = URL(string: "https://dccon.dcinside.com/")!
    static let loginHost = "msign.dcinside.com"

    /// 디시 모바일 통합검색 결과 주소 (검색이 안 되면 이 형식만 고치면 됩니다)
    static func search(_ keyword: String) -> URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?")
        let q = keyword.addingPercentEncoding(withAllowedCharacters: allowed) ?? keyword
        return URL(string: "https://m.dcinside.com/search/?keyword=\(q)") ?? home
    }

    /// 로그인/로그아웃 시 모든 탭을 새로고침하기 위한 알림
    static let sessionChanged = Notification.Name("DCSessionChanged")
    /// 차단 목록/숨김 설정이 바뀌었을 때
    static let filtersChanged = Notification.Name("DCFiltersChanged")
    /// 저장된 로그인 정보가 바뀌었을 때
    static let credentialsChanged = Notification.Name("DCCredentialsChanged")
}

/// 앱 화면 위로 띄우는 창 (보관함 / 검색 / 설정)
enum AppSheet: String, Identifiable {
    case library, posts, search, settings
    var id: String { rawValue }
}

/// 화면 하나(메인 브라우저) + 위로 띄우는 창들을 관리합니다.
/// 보관함·검색에서 고른 페이지는 모두 메인 브라우저에서 열려요.
@MainActor
final class AppRouter: ObservableObject {
    @Published var sheet: AppSheet?
    /// 설정을 열 때 바로 보여줄 칸 (예: "block" = 차단)
    var settingsAnchor: String?
    let mainBrowser: WebViewModel
    private var syncBag = Set<AnyCancellable>()
    private var lastWriteSyncURL: URL?
    /// 분할 화면의 오른쪽(글) 화면 — 분할이 켜졌을 때만 화면에 붙음
    let detailBrowser: WebViewModel
    /// 가로로 넓은 화면에서 글 목록(왼쪽)과 글(오른쪽)을 나란히 보여 주는 중인지
    @Published private(set) var splitActive = false
    /// 한 화면으로 접었을 때 오른쪽(글) 화면이 보던 글을 새로고침 없이 그대로 이어 보려고, 그 화면을 한 화면 자리에 보여 주는 중인지
    @Published private(set) var singleUsesDetail = false
    /// 지금 한 화면(또는 분할의 왼쪽) 자리에 보이는 브라우저 — 주소 열기·계정 전환 등은 이 화면으로
    var primaryBrowser: WebViewModel { singleUsesDetail ? detailBrowser : mainBrowser }
    /// 분할 화면 오른쪽(글) 화면의 상단바 높이 — 왼쪽(목록) 상단바를 같은 높이로 맞추는 데 씀
    @Published var splitTopHeight: CGFloat = 0

    init() {
        mainBrowser = WebViewModel(url: DC.home)
        detailBrowser = WebViewModel(url: URL(string: "about:blank")!)
        detailBrowser.isDetailPane = true
        // 갤러리 목록에서 스와이프 → 하단 바 "갤러리" 버튼과 같은 효과
        mainBrowser.onGallerySwipe = { [weak self] in self?.sheet = .library }
        detailBrowser.onGallerySwipe = { [weak self] in self?.sheet = .library }
        // 분할을 접어 오른쪽 글 화면을 한 화면으로 보는 중에 글에서 뒤로 가면, 그 화면에서 본 이전 글이 아니라 목록(왼쪽 화면)으로
        detailBrowser.backToListHandler = { [weak self] in
            guard let self, self.singleUsesDetail else { return false }
            self.closeSingleDetail()
            return true
        }
        // 분할 화면이면 글 목록에서 누른 글은 오른쪽에서 엶
        mainBrowser.postInterceptor = { [weak self] url in
            guard let self, self.splitActive else { return false }
            self.detailBrowser.load(url)
            return true
        }
        // 분할 화면에서 새 글을 쓰고 목록으로 돌아오면 쓴 글을 오른쪽에서 엶
        mainBrowser.openWrittenPost = { [weak self] url in
            guard let self, self.splitActive else { return false }
            self.detailBrowser.load(url)
            return true
        }
        // 분할 화면에서 오른쪽(글)에서 글쓰기를 열면 왼쪽 목록도 그 갤러리로 바꿈
        detailBrowser.$url
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                guard let self, self.splitActive, let url,
                      let gid = AutoImageStore.writeGalleryID(from: url), !gid.isEmpty,
                      url != self.lastWriteSyncURL else { return }
                self.lastWriteSyncURL = url
                let parts = url.pathComponents.filter { $0 != "/" }
                let kind: GalleryKind = parts.contains("writemini") ? .mini : (parts.contains("writepr") ? .person : .board)
                let bare = DCGalleryID.bare(gid)
                if let cur = self.mainBrowser.url.flatMap(Gallery.parse), cur.id == bare, cur.kind == kind { return }
                self.mainBrowser.load(Gallery(galleryID: bare, name: bare, kind: kind).url)
            }
            .store(in: &syncBag)
        // 어떤 경로로든 왼쪽 화면에 글이 열려 버리면 바로 오른쪽으로 옮김
        mainBrowser.postLanded = { [weak self] url in
            guard let self, self.splitActive else { return }
            self.movePostToDetail(url)
        }
    }

    func open(_ url: URL) {
        sheet = nil
        if splitActive, PostKey.from(url) != nil {
            detailBrowser.load(url)
        } else {
            primaryBrowser.load(url)
        }
    }

    /// 분할 화면인데 왼쪽에 글이 떠 있으면 → 글은 오른쪽으로, 왼쪽은 목록으로 (뒤로 갈 곳이 없으면 그 갤러리 목록)
    func movePostToDetail(_ url: URL) {
        detailBrowser.load(url)
        if mainBrowser.canGoBack {
            mainBrowser.goBack()
        } else if let g = Gallery.parse(url) {
            mainBrowser.load(Gallery(galleryID: g.id, name: g.id, kind: g.kind).url)
        }
    }

    /// 한 화면으로 접힌 상태에서 오른쪽 글 화면을 닫고 목록 화면으로 돌아감 (글은 닫힌 것으로 보고 오른쪽은 빈 화면으로)
    private func closeSingleDetail() {
        singleUsesDetail = false
        detailBrowser.load(URL(string: "about:blank")!)
    }

    /// 분할 화면 켜기/끄기 (화면이 가로로 넓어지거나 좁아질 때)
    func setSplit(_ on: Bool) {
        guard on != splitActive else { return }
        splitActive = on
        if on {
            // 접었을 때 오른쪽 화면을 한 화면 자리에서 쓰고 있었으면 그대로 오른쪽으로 돌려보냄 (왼쪽 목록은 그대로 남아 있음)
            let wasSingleDetail = singleUsesDetail
            singleUsesDetail = false
            detailBrowser.isDetailPane = true
            if wasSingleDetail {
                // 접은 사이에 글이 아닌 곳으로 갔으면 오른쪽은 빈 화면으로
                if let u = detailBrowser.url, PostKey.from(u) == nil, u.scheme != "about" {
                    detailBrowser.load(URL(string: "about:blank")!)
                }
            } else if let u = mainBrowser.url, PostKey.from(u) != nil {
                // 글을 보던 중이었으면 그 글은 오른쪽으로 옮기고 왼쪽은 목록으로 돌아감
                movePostToDetail(u)
            }
        } else if let u = detailBrowser.url, PostKey.from(u) != nil {
            // 접으면 오른쪽 글 화면을 그대로 한 화면 자리에 보여 줌 (새로 불러오지 않아 스크롤·입력 중이던 것이 유지됨)
            singleUsesDetail = true
            detailBrowser.isDetailPane = false
        }
    }

    /// 계정 전환: 지금 로그인을 지우고 → 로그인 화면을 열어 고른 계정으로 자동 로그인
    func switchAccount(_ account: LoginCredential) {
        sheet = nil
        primaryBrowser.loginHere(account)     // 로그인이 끝나면 보던 페이지로 돌아옴
    }

    /// 임시저장 글을 이어서 쓰기: 글쓰기 화면을 열고, 다 열리면 내용을 채움
    func openDraft(_ draft: Draft) {
        primaryBrowser.pendingDraft = draft
        var url = draft.writeURL ?? URL(string: "https://m.dcinside.com/write/\(draft.galleryID)")!
        // 예전에 잘못 저장된 미니 갤러리 글쓰기 주소(/mini/write/) 고치기
        if let fixed = URL(string: url.absoluteString.replacingOccurrences(of: "m.dcinside.com/mini/write/", with: "m.dcinside.com/writemini/")) { url = fixed }
        open(url)
    }
}

@main
struct DCApp: App {
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var router = AppRouter()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(favorites)
                .environmentObject(router)
                .overlay { LockCover() }                    // 잠겨 있으면 첫 화면부터 가림 (가림막 창이 뜨기 전 깜빡임 방지)
                .task { await AppLock.shared.startup() }    // 잠금이 켜져 있으면 켜자마자 인증
        }
        // 백그라운드로 갈 때 알림 확인 예약 → iOS가 깨우면 디시 알림 확인
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { DCNotify.schedule() }
            AppLock.shared.scenePhaseChanged(phase)      // 앱 잠금 / 전환 화면 가리기
        }
        .backgroundTask(.appRefresh(DCNotify.refreshTaskID)) {
            await DCNotify.backgroundRefresh()
        }
    }
}

/// 앱 탭바 없이 브라우저 하나만. 하단 바의 갤러리/검색, ⋮ 메뉴의 설정 등은 창으로 열림
/// 한손 모드: 화면 위쪽을 비워두고(PIP 영상 자리) 아래쪽에서만 앱이 동작
struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var favorites: FavoritesStore
    @AppStorage("compactMode", store: Profile.defaults) private var compactMode = false
    @AppStorage("splitView", store: Profile.defaults) private var splitSetting = true
    @AppStorage("showPerfHUD", store: Profile.defaults) private var showPerfHUD = false
    /// 테마가 바뀌면 화면을 새로 그려 상단바·강조색에 바로 반영
    @AppStorage(DCTheme.storageKey, store: Profile.defaults) private var themeRaw = AppTheme.dc.rawValue
    @Environment(\.colorScheme) private var systemScheme
    /// GitHub에 새 버전이 있으면 알림창
    @State private var availableUpdate: AppRelease?
    /// 처음 켰을 때 기능 소개 (한 번 보면 다시 안 뜸)
    @AppStorage(Tutorial.seenKey, store: Profile.defaults) private var tutorialSeen = false
    @State private var showTutorial = false
    /// 처음 켠 튜토리얼이 끝나면 앱 아이콘 고르기 화면을 한 번 보여 줌
    @State private var iconPickAfterTutorial = false
    @State private var showIconPicker = false
    /// 앱 사용 중 새 디시 알림 배너
    @ObservedObject private var alarms = AlarmStore.shared
    @State private var bannerTask: Task<Void, Never>?
    /// 듀오 오른쪽 빈 줄 (상단바가 그 줄까지 늘어나지 않게 위쪽을 바탕색으로 덮음)
    @ObservedObject private var sideColumn = SideColumnLayout.shared
    @AppStorage("compactTopRatio", store: Profile.defaults) private var topRatio = 0.34
    @State private var keyboardVisible = false
    @State private var dragStartRatio: Double?      // 핸들을 끌기 시작할 때의 높이
    @State private var exitHoldTask: Task<Void, Never>?   // 맨 위에서 버티는 시간 재기
    @State private var exitArmed = false            // 맨 위에 닿아 해제 대기 중 (핸들 색 바뀜)

    private static let minTopRatio = 0.12
    private static let maxTopRatio = 0.6
    private static let exitHoldDelay: Duration = .milliseconds(300)

    /// 앱 창의 실제 높이 (UIScreen.main은 화면이 두 개인 기기(듀오)에서 엉뚱한 화면을 줄 수 있어서 창 크기를 직접 잼)
    @State private var windowHeight: CGFloat = 800
    @State private var windowWidth: CGFloat = 0


    /// 가로로 충분히 넓으면 글 목록 | 글 나란히
    private var isSplit: Bool {
        splitSetting && !compactMode && windowWidth >= 900 && windowWidth > windowHeight
    }

    /// 분할을 켜는 건 바로, 끄는 건 잠깐 기다렸다가 (다른 앱에 갔다 오는 사이 창 크기가 잠깐 바뀌어도 분할이 풀렸다 켜지며 글이 왼쪽에 뜨지 않게)
    @State private var splitTask: Task<Void, Never>?
    private func scheduleSplit() {
        splitTask?.cancel()
        if isSplit {
            router.setSplit(true)
        } else {
            splitTask = Task {
                try? await Task.sleep(for: .milliseconds(900))
                if !Task.isCancelled, !isSplit { router.setSplit(false) }
            }
        }
    }

    /// 앱 창의 아래 안전 영역 높이 (홈 바 자리)
    private static var windowBottomSafe: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel == .normal && !$0.isHidden }
            .map(\.safeAreaInsets.bottom).max() ?? 0
    }

    private func closeBanner() {
        bannerTask?.cancel()
        AlarmStore.shared.incoming = nil
    }

    /// 한손 모드에서 비워둘 위쪽 높이 (상태바 포함)
    private var topGap: CGFloat {
        compactMode ? windowHeight * topRatio : 0
    }

    var body: some View {
        // 화면 구조는 항상 같게 유지하고(웹뷰가 빠지지 않도록), 한손 모드일 때 위쪽 여백만 줌
        ZStack {
            Color.black.ignoresSafeArea()
                .opacity(compactMode ? 1 : 0)   // 한손 모드일 때만 위쪽 빈 공간을 검게
            GeometryReader { geo in
                // 실제로 배정받은 폭·높이 기준으로 배치 (화면 밖으로 삐져나가 컨트롤바가 잘리지 않게)
                let total = geo.size.width
                let list = (total * 0.42).rounded()
                ZStack(alignment: .topLeading) {
                    if isSplit {
                        // 아래층: 오른쪽(글) 화면
                        HStack(spacing: 0) {
                            Color.clear.frame(width: list).allowsHitTesting(false)
                            Divider().ignoresSafeArea()
                            NavigationStack {
                                BrowserView(model: router.detailBrowser, fallbackTitle: "글", showsMenuButton: false)
                                    .overlay { DetailPlaceholder(model: router.detailBrowser) }
                            }
                            .keepsTopStatusBar()
                            .id(themeRaw)
                        }
                        .frame(width: total, height: geo.size.height, alignment: .leading)
                        // 위층: 왼쪽(목록) 화면을 창 전체 폭으로 (내비게이션 바 없이 SwiftUI로만) — 목록 폭 밖은 비어 있어 글 화면이 눌리고,
                        // 컨트롤바는 창 오른쪽 끝에서 글 위에 떠 있음
                        BrowserView(model: router.mainBrowser, fallbackTitle: "홈", showsMenuButton: true, splitListWidth: list)
                            .safeAreaPadding(.bottom, Self.windowBottomSafe)   // 내비게이션 스택이 없어진 만큼 아래 안전 영역(홈 바)을 되돌려 컨트롤바 높이를 한 화면일 때와 같게
                            .id(themeRaw)
                            .frame(width: total, height: geo.size.height, alignment: .topLeading)
                    } else {
                        NavigationStack {
                            BrowserView(model: router.primaryBrowser, fallbackTitle: "홈", showsMenuButton: true)
                        }
                        .keepsTopStatusBar()   // 듀오: 시계가 옆 세로 줄로 가며 뒤로가기가 컨트롤바 위로 겹치지 않게 NavigationStack 바깥에서도 가로 고정
                        .id("\(themeRaw)-\(router.singleUsesDetail)")
                    }
                }
                .frame(width: total, height: geo.size.height, alignment: .topLeading)
                // 키보드가 올라오면 이 영역이 키보드 윗변까지로 줄어드는데, 아래를 잘라 버리면 댓글 입력창의 어두운 막·배경이 키보드 아래까지 못 내려가 흰 바탕이 보임
                // → 위·좌·우만 자르고 아래는 길게 열어 둠
                .mask(Rectangle().padding(.bottom, -1200))
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: compactMode ? 22 : 0,
                                              topTrailingRadius: compactMode ? 22 : 0,
                                              style: .continuous))
            .padding(.top, topGap)
            // 앱 화면이 상태바·홈 바 영역까지 덮도록 (남색 상단바가 위 끝까지, 아래 검은 띠 없음)
            // 키보드 처리는 그대로 두기 위해 .container만 무시
            .ignoresSafeArea(.container, edges: .all)
            // 키보드가 올라오거나 내려갈 때(특히 듀오 동영상 분할) 앱 화면 전체 높이가 줄었다가 늦게 돌아와 아래가 흰 바탕으로 비는 문제
            // → 앱 화면은 키보드로 줄이지 않음 (웹뷰는 WebKit이, 댓글 입력창·글쓰기 버튼은 각자 키보드 높이를 따로 계산)
            .ignoresSafeArea(.keyboard, edges: .bottom)

            // 앱 글쓰기 화면: 디시 글쓰기 페이지 위에 덮음 (등록은 뒤의 디시 양식으로)
            NativeWriteHost(model: router.mainBrowser)
                .padding(.top, topGap)
            NativeWriteHost(model: router.detailBrowser)      // 분할 화면의 글에서 연 글쓰기·수정
                .padding(.top, topGap)

            // 듀오: 상단바가 오른쪽 빈 줄(안전 영역)까지 늘어난 부분을 바탕색으로 덮어 사파리처럼
            if sideColumn.width > 0 && !compactMode {
                Color(uiColor: .dcPage)
                    .frame(width: sideColumn.width, height: sideColumn.topBarBottom + 2)   // +2: 상단바 아래 회색 구분선까지 덮기
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // 한손 모드: 앱 화면 바로 위에 있는 핸들을 위아래로 끌어 높이 조절
            if compactMode {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(0, topGap - 30)).allowsHitTesting(false)
                    resizeHandle
                    Spacer(minLength: 0).allowsHitTesting(false)   // 핸들 말고는 터치를 막지 않음
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
            }
        }
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { windowHeight = g.size.height; windowWidth = g.size.width; scheduleSplit() }
                    .onChange(of: g.size.height) { _, h in windowHeight = h; scheduleSplit() }
                    .onChange(of: g.size.width) { _, w in windowWidth = w; scheduleSplit() }
            }
            .ignoresSafeArea()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .overlay(alignment: .top) {
            if showPerfHUD && PerfHUDSettings.toggleVisible {
                PerfHUDView(webView: router.primaryBrowser.webView).padding(.top, 4)   // 상단바 위 상태바 줄 바로 아래
            }
        }
        .keepsTopStatusBar()
        .animation(.spring(duration: 0.35), value: compactMode)
        .background { HingeProbe().allowsHitTesting(false) }   // 듀오가 접혔는지(바깥 디스플레이) 감지
        .onChange(of: router.sheet) { _, new in
            // 웹 화면의 키보드가 열려 있는 채로 시트가 올라오면 키보드 내려가는 동작과 시트 전환이 겹쳐 느려지므로, 시트를 띄울 때 먼저 키보드를 내림
            if new != nil { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
        .onChange(of: splitSetting) { _, _ in scheduleSplit() }
        // (높이 조절은 손가락을 바로 따라오도록 애니메이션 없이)
        .onAppear {
            StatusBarStyler.applySoon()   // 상태바(시계·배터리) 글씨: 유색 상단바면 흰색
            DarkMode.apply()              // ⋮ 메뉴에서 정한 다크모드
            compactMode = false     // 앱을 새로 켜면 항상 일반 모드로 시작 (안전장치)
            if let url = DCNotify.pendingURL { DCNotify.pendingURL = nil; router.open(url) }   // 알림을 눌러서 켠 경우
        }
        .overlay(alignment: .top) {
            if let inc = alarms.incoming {
                AlarmBanner(item: inc.item, more: inc.more, onTap: {
                    AlarmStore.shared.markRead(inc.item)
                    AlarmStore.shared.markRead(galleryID: inc.item.galleryID, postNo: inc.item.postNo)
                    router.open(inc.item.url)
                    closeBanner()
                }, onClose: closeBanner)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(inc.item.id)
            }
        }
        .animation(.spring(duration: 0.35), value: alarms.incoming?.item.id)
        .onChange(of: themeRaw) { _, _ in StatusBarStyler.applySoon() }          // 테마를 바꾸면 상태바 글씨 색도
        .onChange(of: systemScheme) { _, v in
            DarkMode.systemChanged(dark: v == .dark)
            StatusBarStyler.applySoon()
        }      // 다크 모드 전환 (테마 색이 바뀔 수 있음)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            StatusBarStyler.apply()
        }
        .onChange(of: alarms.incoming?.item.id) { _, newID in
            // 4초 뒤 자동으로 닫힘
            bannerTask?.cancel()
            guard newID != nil else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            bannerTask = Task {
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { closeBanner() }
            }
        }
        .task {
            if !tutorialSeen {
                iconPickAfterTutorial = true
                showTutorial = true
            }
            // 앱을 열 때 GitHub Releases 확인 (주기는 버전 정보 → 업데이트에서) — 튜토리얼을 보는 중이면 끝난 뒤에
            let r = await UpdateChecker.checkIfDue()
            while showTutorial { try? await Task.sleep(for: .milliseconds(400)) }
            if let r { availableUpdate = r }
        }
        .fullScreenCover(isPresented: $showTutorial, onDismiss: {
            if iconPickAfterTutorial {
                iconPickAfterTutorial = false
                // 튜토리얼 화면이 완전히 내려간 뒤에 띄워야 시트가 뜸
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    showIconPicker = true
                }
            }
        }) {
            TutorialView { showTutorial = false }
        }
        .sheet(isPresented: $showIconPicker) {
            NavigationStack { AppIconSettingsView() }
                .sheetUnderBlueBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // 백그라운드에서 다시 열었을 때도 확인
            guard availableUpdate == nil else { return }
            Task { if let r = await UpdateChecker.checkIfDue() { availableUpdate = r } }
        }
        .overlay {
            if let r = availableUpdate {
                UpdateCard(release: r) { availableUpdate = nil }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: DCNotify.openURL)) { note in
            if let url = note.object as? URL { DCNotify.pendingURL = nil; router.open(url) }
        }
        .sheet(item: $router.sheet) { sheet in
            Group {
                switch sheet {
                case .library: FavoritesView()
                case .posts: SavedPostsSheet()
                case .search: SearchView()
                case .settings: SettingsView()
                }
            }
            .environmentObject(router)
            .environmentObject(favorites)
            .sheetUnderBlueBar()   // 파란 영역을 덮지 않고 그 아래까지만
        }
    }

    /// 한손 모드 핸들 (아이폰 홈 바처럼 얇고 긴 막대). 위아래로 끌면 비워둘 높이가 바뀜
    private var resizeHandle: some View {
        Capsule()
            .fill(exitArmed ? DCTheme.accent : Color.white.opacity(0.75))
            .frame(width: exitArmed ? 170 : 120, height: exitArmed ? 7 : 5)
            .animation(.spring(duration: 0.25), value: exitArmed)
            .frame(maxWidth: .infinity)          // 가로 전체를 잡는 영역으로
            .frame(height: 30)                   // 손가락으로 잡기 쉽게 위아래 여유
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        guard compactMode else { return }
                        let screen = max(windowHeight, 1)
                        if dragStartRatio == nil { dragStartRatio = topRatio }
                        let next = (dragStartRatio ?? topRatio) + Double(v.translation.height / screen)
                        topRatio = min(Self.maxTopRatio, max(Self.minTopRatio, next))
                        // 맨 위까지 끌어올린 채로 잠깐 버티면 한손 모드 해제
                        if next <= Self.minTopRatio {
                            if exitHoldTask == nil { armExit() }
                        } else {
                            disarmExit()
                        }
                    }
                    .onEnded { _ in
                        disarmExit()
                        dragStartRatio = nil
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
    }

    /// 핸들이 맨 위에 닿음 → 잠시 뒤 해제 (그 사이 내리거나 손을 떼면 취소)
    private func armExit() {
        exitArmed = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        exitHoldTask = Task { @MainActor in
            try? await Task.sleep(for: Self.exitHoldDelay)
            guard !Task.isCancelled, compactMode else { return }
            // 다음에 켤 때 맨 위 높이로 켜지지 않도록 끌기 전 높이로 되돌림
            if let start = dragStartRatio, start > Self.minTopRatio + 0.02 { topRatio = start }
            dragStartRatio = nil
            exitArmed = false
            exitHoldTask = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            compactMode = false
        }
    }

    private func disarmExit() {
        exitHoldTask?.cancel()
        exitHoldTask = nil
        if exitArmed { exitArmed = false }
    }

}




/// 분할 화면의 오른쪽에 아직 연 글이 없을 때 안내
private struct DetailPlaceholder: View {
    @ObservedObject var model: WebViewModel

    var body: some View {
        if model.url == nil || model.url?.scheme == "about" {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.split.2x1").font(.system(size: 40)).foregroundStyle(.tertiary)
                Text("왼쪽 목록에서 글을 누르면 여기서 열려요")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .dcPage))   // 다크모드에서 페이지(#272729)와 같은 색 (순검정이 튀지 않게)
        }
    }
}
