import SwiftUI
import WebKit
import Combine

/// 글/댓글을 길게 눌렀을 때 페이지에서 넘어오는 정보
struct BlockRequest: Identifiable {
    let id = UUID()
    let kind: String
    let nick: String
    let userID: String
    let ip: String
    let dcconKey: String
    let dcconSrc: String
    /// 본문 사진을 길게 누른 경우: 사진 차단 키와 사진 주소 (비어 있으면 사진이 아님)
    let imgKey: String
    let imgSrc: String
    /// 본문 사진의 원본 매칭용: 글 속 전체 사진에서의 순서(-1이면 모름), 전체 사진 수, 전체 파일 번호 (가린 사진 포함)
    let imgIndex: Int
    let imgCount: Int
    let imgFilenos: [Int]
    let snippet: String
    /// 사진이 있는 글 주소 (원본 링크를 PC 글에서 찾을 때 씀) — 길게 누른 시점의 글
    var pageURL: URL? = nil

    init(_ body: [String: Any]) {
        func s(_ k: String) -> String { (body[k] as? String) ?? "" }
        kind = s("kind"); nick = s("nick"); userID = s("userId"); ip = s("ip")
        dcconKey = s("dcconKey"); dcconSrc = s("dcconSrc"); snippet = s("snippet")
        imgKey = s("imgKey"); imgSrc = s("imgSrc")
        imgIndex = (body["imgIndex"] as? NSNumber)?.intValue ?? -1
        imgCount = (body["imgCount"] as? NSNumber)?.intValue ?? 0
        imgFilenos = (body["imgFilenos"] as? [NSNumber])?.map(\.intValue) ?? []
    }
}

/// 요소 숨기기 모드에서 탭한 요소 정보
struct PickRequest: Identifiable {
    let id = UUID()
    let selector: String
    let count: Int
    let snippet: String
}

/// WKUserContentController가 핸들러를 강하게 잡아서 생기는 메모리 누수 방지용
@MainActor
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

/// WKWebView 하나와 그 상태를 관리합니다.
/// 모든 탭이 같은 쿠키 저장소(.default())를 쓰므로 한 번 로그인하면 전부 로그인 상태가 됩니다.
@MainActor
final class WebViewModel: NSObject, ObservableObject {
    let webView: WKWebView

    @Published var title: String = ""
    @Published var url: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    /// 지금 보는 글에 디시의 수정·삭제 버튼이 있음 (로그인 계정 본인 글 / 유동 글) → 앱 버튼으로 대신 누름
    @Published var isLoading = false
    @Published var progress: Double = 0

    /// 댓글 링크를 눌렀을 때 물어볼 주소 (대댓글 달기 / 링크로 이동)
    @Published var commentLink: URL?
    /// 앱 댓글 입력창 (댓글·대댓글 칸을 누르면 뜸)
    @Published var commentCompose: CommentComposeSession?
    /// 쓰다 닫은 댓글 내용 (다른 댓글을 눌러 새 입력창이 열리면 옮겨 줌)
    private var commentCarry: (text: String, code: String, page: String, at: Date)?
    @Published var blockRequest: BlockRequest? {
        didSet {   // 차단 메뉴가 닫히면 길게 누르며 생긴 글자 선택도 풀기
            if blockRequest == nil, oldValue != nil {
                webView.evaluateJavaScript("window.__dcapp && window.__dcapp.clearSelection(); true", completionHandler: nil)
            }
        }
    }
    @Published var pickRequest: PickRequest?
    @Published var isPickMode = false
    @Published var isCapturing = false
    @Published var captured: CapturedImage?
    /// 글 속 사진 보기 (사진 탭 → 전체 화면)
    @Published var imageViewer: ImageViewerItem?
    /// 댓글을 길게 눌러 띄우는 '댓글 내용만 보기' (선택·복사용)
    @Published var commentText: CommentTextItem?
    /// 댓글을 길게 눌렀을 때 뜨는 '텍스트 선택' 버튼 (누르면 commentText로 넘어가 내용 화면이 열림)
    @Published var commentTextPrompt: CommentTextItem?
    @Published var isBlockPickMode = false
    /// 탭해서 유저 메모 (탭하는 방식은 차단 모드와 같고, 고르면 메모 창)
    @Published var isMemoPickMode = false
    @Published var memoRequest: BlockRequest?
    @Published var isWritePage = false
    /// 앱 글쓰기 화면 (디시 글쓰기 페이지 위에 덮어서 보여줌, nil이면 디시 원래 화면)
    @Published var nativeWrite: NativeWriteSession?
    /// '디시 원래 화면으로 쓰기'를 고른 글쓰기 페이지 (이 페이지는 앱 화면을 덮지 않음)
    private var nativeSkipURL: URL?
    /// 방금 글쓰기 등록을 누름 → 곧 열리는 글 화면을 '작성한 글'로 기록
    private var pendingWritten: (gallery: String, title: String, nick: String, at: Date)?
    /// 키보드 위에 붙인 글쓰기 도구줄 높이 (그 위로 < > 버튼을 올림)
    @Published var writeToolbarHeight: CGFloat = 0
    /// 페이지를 스크롤하는 동안 true → 컨트롤바를 화면 밖으로 넣음, 멈추면 다시 false
    @Published var isScrolling = false
    /// 글 읽으며 아래로 스크롤하는 중이면 true (상단바 숨김용). 위로 올리거나 맨 위 근처면 false
    @Published var navHiddenByScroll = false
    /// 컨트롤바 '내리면 숨기기' 방식: 아래로 스크롤하면 true(멈춰도 유지), 위로 올리거나 맨 위 근처면 false
    @Published var barHiddenByDirection = false
    /// 댓글 영역이 화면에 걸쳐 있는지 (페이지 스크립트가 알려줌). 걸쳐 있는 동안 컨트롤바를 다시 보여 줌 (지나쳐 내려가면 다시 숨김)
    @Published var commentsInView = false
    /// 컨트롤바 방향 숨김의 기준 위치: 보이는 동안은 '가장 위로 올라간 곳', 숨은 동안은 '가장 아래로 내려간 곳'.
    /// 여기서 24pt 이상 반대로 움직여야 바뀜 → 손가락 떨림이나 한두 샘플의 어긋남이 있어도 누적 거리가 0으로 돌아가지 않음
    private var barRefY: CGFloat = 0
    /// 댓글 영역에 닿아 컨트롤바를 꺼낸 직후 이 시각까지는 다시 숨기지 않음 (관성으로 곧바로 숨어 깜빡이는 것 방지)
    private var barHoldUntil = Date.distantPast
    private var lastScrollY: CGFloat = 0
    private var scrollAnchorY: CGFloat = 0
    private var scrollDirDown = true
    /// 앱이 상단바를 켜고 끈 시각 — 그 직후 0.5초는 상단바 변화로 생기는 흔들림이라 방향을 세지 않음
    private var navToggleAt = Date.distantPast
    /// 직전 화면 폭 (회전으로 폭이 바뀌었는지 보려고)
    private var lastViewWidth: CGFloat = -1
    /// 마지막으로 손가락·관성 스크롤 샘플이 온 시각 (그 직후 0.3초 안의 '손가락 아님' 샘플은 깃발이 잠깐 꺼진 것으로 보고 이어서 셈)
    private var lastUserSampleAt = Date.distantPast
    /// 진단용: 컨트롤바 숨김 판정이 샘플을 어떻게 처리했는지 셈
    private struct BarStats {
        var user = 0, flap = 0, idle = 0, windowSkip = 0, widthChanges = 0, navResets = 0
        var hide = 0, show = 0, cmtShow = 0
        var lastToggle = "-"
        var lastToggleAt = Date.distantPast
    }
    private var barStats = BarStats()
    /// 진단용: 화면(BrowserView)이 컨트롤바를 숨겨야 한다고 본 상태·횟수 — 판정은 바뀌는데 화면이 안 따라가는지 가르는 데 씀
    private var viewTucked = false
    private var viewTuckCount = 0
    private var viewTuckChangedAt = Date.distantPast
    func noteViewTucked(_ v: Bool) {
        viewTucked = v
        if v { viewTuckCount += 1 }
        viewTuckChangedAt = Date()
    }
    private var scrollStopTask: Task<Void, Never>?
    var pendingDraft: Draft?
    /// 하단 바 '글쓰기'로 들어왔으면, 글쓰기 화면이 열린 뒤 제목 칸에 커서+키보드
    var focusTitleOnWrite = false
    /// 키보드가 떠 있는지 (제목 칸 포커스가 먹혔는지 확인용)
    private var keyboardUp = false
    @Published var toast: String?
    /// 429로 막힌 댓글을 자동으로 다시 누르는 중 ('댓글을 다는 중입니다' 말풍선)
    @Published var isRetryingComment = false
    private var toastTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()
    /// 아래로 끌어서 새로고침: 이 거리(pt)만큼 끌면 바로 새로고침 (기본 동작은 훨씬 길게 끌어야 함)
    private static let pullTrigger: CGFloat = 95
    private var pullObserver: NSKeyValueObservation?
    /// 문서가 좌우로 밀리지 않게 contentOffset.x를 0으로 되돌리는 관찰
    private var horizontalObserver: NSKeyValueObservation?
    private var pullFired = false
    private var lastHost: String?
    private var pendingCredential: LoginCredential?
    /// 계정 전환으로 로그인할 계정 (로그인 화면이 열리면 자동 입력 + 로그인)
    var pendingLogin: LoginCredential?
    /// '로그인 페이지 열기'로 연 로그인 화면 → 저장된 계정을 자동으로 채우거나 로그인하지 않음 (다른 아이디로 로그인하려고)
    private var manualLogin = false
    /// 새로고침 후 댓글 위치로 이동할지
    private var scrollToCommentsAfterLoad = false
    /// 댓글 429로 마지막에 처리한 시각 (디시가 곧바로 한 번 더 보내 연달아 오는 429는 한 번만)

    init(url: URL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Profile.websiteDataStore
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // 실제 사파리와 같은 형식의 UA (iOS 버전과 Version 값이 어긋나면 봇 검사에 더 자주 걸릴 수 있음)
        let v = UIDevice.current.systemVersion.split(separator: ".").prefix(2).joined(separator: ".")
        config.applicationNameForUserAgent = "Version/\(v) Mobile/15E148 Safari/604.1"
        config.userContentController = WKUserContentController()
        // 아이패드에서도 PC판이 아닌 모바일 디시를 받도록 (차단·자짤 등 기능이 모바일 페이지 기준)
        config.defaultWebpagePreferences.preferredContentMode = .mobile

        FocusUnlock.install()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        config.userContentController.add(WeakScriptMessageHandler(self), name: "dcapp")
        installUserScript()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        // 페이지가 그려지기 전·끝까지 스크롤했을 때 비치는 바탕을 다크모드 페이지색에 맞춤 (순검정 방지)
        webView.underPageBackgroundColor = .dcPage
        // 왼쪽 1/4 스와이프를 쓰면 웹뷰 기본(가장자리) 제스처는 끔 → 한 번 쓸었는데 두 번 뒤로 가는 문제 방지
        webView.allowsBackForwardNavigationGestures = !Self.customSwipeEnabled
        webView.allowsLinkPreview = false   // 길게 누르기를 차단 메뉴에 사용
        webView.removeInputAccessoryBar()   // 키보드 위 ▲▼✓ 막대 없애기 (댓글창이 키보드에 딱 붙도록)
        webView.scrollView.keyboardDismissMode = .interactive   // 아래로 쓸어내려 키보드 닫기
        // 세로로만 움직이게: 가로 스크롤 막기 (페이지가 좌우로 밀려 흔들리는 것 방지)
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.isDirectionalLockEnabled = true
        // WebKit이 스크롤뷰 델리게이트를 쓰고 있어서 델리게이트 대신 contentOffset을 관찰해 x를 0으로 되돌림
        // (확대 중에는 건드리지 않음)
        horizontalObserver = webView.scrollView.observe(\.contentOffset, options: [.new]) { sv, _ in
            MainActor.assumeIsolated {
                guard sv.contentOffset.x != 0, sv.zoomScale <= sv.minimumZoomScale + 0.001 else { return }
                sv.contentOffset.x = 0
            }
        }

        // 화면 어디서나 좌우로 쓸어서 뒤로/앞으로 (가장자리 스와이프는 웹뷰 기본 제스처가 처리)
        let swipe = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipe.delegate = self
        swipe.cancelsTouchesInView = false
        webView.addGestureRecognizer(swipe)

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        // 기본 새로고침은 한참 끌어야 걸림 → 손가락을 대고 일정 거리(pullTrigger)만 끌어도 바로 새로고침
        pullObserver = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let over = -(sv.contentOffset.y + sv.adjustedContentInset.top)     // 맨 위에서 끌어내린 거리
                if over < 4 { if !(sv.refreshControl?.isRefreshing ?? false) { self.pullFired = false }; return }
                guard sv.isDragging, over >= Self.pullTrigger, !self.pullFired,
                      let rc = sv.refreshControl, !rc.isRefreshing else { return }
                self.pullFired = true
                rc.beginRefreshing()
                self.handlePullToRefresh()
            }
        }

        webView.publisher(for: \.title).map { $0 ?? "" }
            .receive(on: DispatchQueue.main).assign(to: &$title)
        webView.publisher(for: \.url)
            .receive(on: DispatchQueue.main).assign(to: &$url)
        // 글쓰기 화면 여부는 주소가 바뀔 때마다 바로 갱신 (뒤로가기로 캐시된 페이지가 열려도 정확하게)
        webView.publisher(for: \.url)
            .map { $0.flatMap(AutoImageStore.writeGalleryID) != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main).assign(to: &$isWritePage)
        webView.publisher(for: \.canGoBack)
            .receive(on: DispatchQueue.main).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward)
            .receive(on: DispatchQueue.main).assign(to: &$canGoForward)
        webView.publisher(for: \.isLoading)
            .receive(on: DispatchQueue.main).assign(to: &$isLoading)
        webView.publisher(for: \.estimatedProgress)
            .receive(on: DispatchQueue.main).assign(to: &$progress)

        // 다른 화면(분할 화면의 오른쪽)에서 글을 읽으면 이 목록의 읽은 글 표시 갱신
        NotificationCenter.default.publisher(for: Self.postReadNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, (note.object as AnyObject?) !== self else { return }
                self.refreshReadMarks()
            }
            .store(in: &cancellables)

        // 다른 탭에서 로그인/로그아웃하면 새로고침
        NotificationCenter.default.publisher(for: DC.sessionChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let senderID = (note.object as AnyObject?).map(ObjectIdentifier.init)
                Task { @MainActor in
                    guard let self, senderID != ObjectIdentifier(self) else { return }
                    self.webView.reload()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.keyboardUp = true } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.keyboardUp = false } }
            .store(in: &cancellables)

        // 로그인 계정이 바뀌면 (내 글·댓글 형광펜 대상이 바뀜) 페이지 설정 다시 반영
        NotificationCenter.default.publisher(for: DC.credentialsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.applyFilters() } }
            .store(in: &cancellables)

        // 차단 목록이 바뀌면 바로 반영
        NotificationCenter.default.publisher(for: DC.filtersChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyFilters() }
            }
            .store(in: &cancellables)

        // ⋮ 메뉴에서 다크모드를 바꾸면 지금 페이지도 바로
        NotificationCenter.default.publisher(for: DarkMode.changed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in _ = try? await self?.webView.evaluateJavaScript(DarkMode.pageScript) }
            }
            .store(in: &cancellables)

        // 손가락으로 끌거나 관성으로 움직이는 동안만 '스크롤 중' (페이지 로드·키보드 때문에 움직이는 건 제외)
        webView.scrollView.publisher(for: \.contentOffset)
            .sink { [weak self] _ in self?.scrollMoved() }
            .store(in: &cancellables)

        webView.load(URLRequest(url: url))
    }

    private func updateNavHidden(_ sv: UIScrollView) {
        let off = sv.contentOffset.y
        let y = off + sv.adjustedContentInset.top
        defer { lastScrollY = off }
        guard Date().timeIntervalSince(navToggleAt) > 0.5 else { scrollAnchorY = off; return }   // 상단바가 바뀌며 생기는 흔들림은 무시
        let dy = off - lastScrollY
        if dy == 0 { return }
        if (dy > 0) != (scrollDirDown) { scrollDirDown = dy > 0; scrollAnchorY = lastScrollY }   // 방향이 바뀌면 기준점 새로
        let moved = off - scrollAnchorY      // 같은 방향으로 움직인 누적 거리
        if y < 40 { if navHiddenByScroll { setNavHidden(false) }; return }
        if moved > 30, y > 100, !navHiddenByScroll { setNavHidden(true) }
        else if moved < -30, navHiddenByScroll { setNavHidden(false) }
    }

    /// 상단바(와 그 위 남색 띠)를 접고 펴기: 애니메이션 트랜잭션 안에서 바꿔야 시스템 상단바·웹뷰 안전 영역·남색 띠가 휙 바뀌지 않고 같은 곡선으로 움직임
    /// (전환 중 생기는 오프셋 흔들림은 navToggleAt의 0.5초 무시 구간이 덮음)
    private func setNavHidden(_ hidden: Bool) {
        navToggleAt = Date()
        withAnimation(.easeInOut(duration: 0.25)) { navHiddenByScroll = hidden }
    }

    /// 아래로 24pt 스크롤하면 컨트롤바를 숨기고, 위로 24pt 올리면 다시 보임 (멈춰도 그대로)
    /// 방향이 바뀔 때마다 기준점을 새로 잡던 방식은 손가락 떨림(−1pt 한 번)에도 누적이 0으로 돌아가 숨김이 안 먹혔음
    /// → 보이는 동안은 가장 위로 올라간 곳(barRefY)을, 숨은 동안은 가장 아래로 내려간 곳을 기준으로 삼아 거기서 24pt 되돌아와야 바뀜
    private func updateBarHiddenByDirection(_ sv: UIScrollView) {
        let off = sv.contentOffset.y
        guard Date().timeIntervalSince(navToggleAt) > 0.5 else { barRefY = off; barStats.windowSkip += 1; return }   // 상단바가 바뀌며 생기는 흔들림은 무시
        let y = off + sv.adjustedContentInset.top
        if y < 40 {      // 맨 위 근처는 늘 보임
            if barHiddenByDirection { setBarHidden(false, at: off) }
            barRefY = off
            return
        }
        if barHiddenByDirection {
            barRefY = max(barRefY, off)
            if barRefY - off > 24 { setBarHidden(false, at: off) }
        } else {
            if Date() < barHoldUntil { barRefY = off; return }     // 댓글에 닿아 꺼낸 직후
            barRefY = min(barRefY, off)
            if off - barRefY > 24, y > 100 { setBarHidden(true, at: off) }
        }
    }

    private func setBarHidden(_ hidden: Bool, at off: CGFloat) {
        barHiddenByDirection = hidden
        barRefY = off
        if hidden { barStats.hide += 1 } else { barStats.show += 1 }
        barStats.lastToggle = "\(hidden ? "hide" : "show")@\(Int(off))"
        barStats.lastToggleAt = Date()
    }

    private func scrollMoved() {
        let sv = webView.scrollView
        let off = sv.contentOffset.y
        let now = Date()
        // 화면 폭이 바뀐 순간(회전 등)은 움직임으로 세지 않고, 기준점을 지금 위치로 다시 잡고, 컨트롤바는 다시 보임
        let widthChanged = abs(sv.bounds.width - lastViewWidth) > 0.5
        lastViewWidth = sv.bounds.width
        if widthChanged {
            barStats.widthChanges += 1
            lastScrollY = off; scrollAnchorY = off; barRefY = off
            if barHiddenByDirection { setBarHidden(false, at: off) }
            return
        }
        let userDriven = sv.isTracking || sv.isDragging || sv.isDecelerating
        // 손가락 깃발이 꺼진 샘플이라도 직전 0.3초 안에 손가락 샘플이 있었으면 스크롤이 이어지는 중으로 보고 셈 (샘플마다 깃발이 깜빡여도 누적이 끊기지 않게)
        let recentUser = now.timeIntervalSince(lastUserSampleAt) < 0.3
        guard userDriven || recentUser else {
            // 손가락과 상관없는 움직임(회전 뒤 자리 맞춤·로딩·키보드·페이지가 스스로 옮김): 세지 않고 기준점만 지금 위치로
            barStats.idle += 1
            lastScrollY = off; barRefY = off
            return
        }
        if userDriven { lastUserSampleAt = now; barStats.user += 1 } else { barStats.flap += 1 }
        updateBarHiddenByDirection(sv)
        updateNavHidden(sv)
        if !isScrolling { isScrolling = true }
        scrollStopTask?.cancel()
        scrollStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let self else { return }
            // 아직 손가락을 대고 있으면 계속 숨김 (손을 떼고 멈추면 다음 움직임 없이도 다시 확인)
            if self.webView.scrollView.isTracking { self.scrollMoved(); return }
            self.isScrolling = false
        }
    }

    // MARK: - 공유

    /// 공유 창 띄우기. 아이패드에서는 화면 오른쪽 위(⋮ 버튼 근처)를 가리키는 말풍선으로
    func share(_ url: URL) {
        Task {
            try? await Task.sleep(for: .milliseconds(300))   // ⋮ 메뉴가 다 닫힌 뒤에 띄움
            presentShare(url)
        }
    }

    private func presentShare(_ url: URL) {
        guard let vc = presenter() else { return }
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = ac.popoverPresentationController {
            let host = vc.view!
            pop.sourceView = host
            pop.sourceRect = CGRect(x: host.bounds.maxX - 40, y: host.safeAreaInsets.top, width: 1, height: 1)
            pop.permittedArrowDirections = .up
        }
        vc.present(ac, animated: true)
    }

    // MARK: - 기본 조작

    /// 페이지 위에 떠 있는 하단 바 높이만큼 아래 스크롤 여백 (화면 아래 안전 영역은 웹뷰가 따로 더함)
    func setBottomBarInset(_ h: CGFloat) {
        let sv = webView.scrollView
        guard abs(sv.contentInset.bottom - h) > 0.5 else { return }
        sv.contentInset.bottom = h
        sv.verticalScrollIndicatorInsets.bottom = h
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    /// 댓글 링크 선택 창에서 '대댓글 달기'
    // MARK: - 앱 댓글 입력창

    private func composeArgs(_ s: CommentComposeSession) -> [String: Any] {
        ["p": ["text": s.text, "nick": s.nick, "pw": s.pw, "code": s.code, "reply": s.isReply, "ch": s.replyCh, "replyNick": s.replyNick]]
    }

    /// 지금 보는 페이지의 갤러리 ID (글쓰기·글·목록 모두)
    var currentGalleryID: String? {
        guard let url = webView.url else { return nil }
        return AutoImageStore.writeGalleryID(from: url) ?? Gallery.parse(url)?.id
    }

    /// 페이지가 다시 불려와 댓글칸이 새로 생겼으면(대댓글은 답글 칸을 다시 열어) 입력창을 새 칸에 연결
    func reattachCompose(_ s: CommentComposeSession) async {
        _ = await call("return window.__dcapp ? await window.__dcapp.ensureReplyTarget(p) : false;", composeArgs(s))
    }

    /// 입력창의 내용을 디시 댓글 양식에 채우고 등록 버튼을 누름
    /// 댓글을 보낸 뒤 응답이 끝내 안 오면 입력창을 다시 쓸 수 있게 풀어 주는 시간
    /// (보안 확인 대기 최대 50초 + 등록 요청 최대 20초 + 여유 5초. 정상 응답·오류는 그보다 먼저 'cmtdone'으로 풀림)
    static let commentSendFallback: Duration = .seconds(75)

    func submitComment() {
        guard let s = commentCompose, !s.sending else { return }
        let text = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { showToast("내용을 입력해 주세요"); return }
        if s.anon {
            if s.nick.trimmingCharacters(in: .whitespaces).isEmpty { showToast("닉네임을 입력해 주세요"); return }
            if s.pw.isEmpty { showToast("비밀번호를 입력해 주세요"); return }
            AnonStore.update(gallery: currentGalleryID, nick: s.nickLocked ? nil : s.nick, password: s.pw)
        }
        if s.hasCode && s.code.trimmingCharacters(in: .whitespaces).isEmpty { showToast("코드를 입력해 주세요"); return }
        s.sending = true
        Task {
            await reattachCompose(s)
            let r = await call("return window.__dcapp ? window.__dcapp.cmtSubmit(p) : 'none';", composeArgs(s)) as? String
            switch r {
            case "sent":
                // 성공하면 'cmtok'으로 닫힘. 응답이 없으면(디시가 입력 오류 안내만 띄운 경우 등) 입력창을 다시 쓸 수 있게
                try? await Task.sleep(for: Self.commentSendFallback)
                if commentCompose === s { s.sending = false }
            case "tswait", "tserror":
                s.sending = false
                showToast(Self.tsWaitToast(r))
            case "notready":
                s.sending = false
                showToast("댓글 기능을 아직 준비 중이에요. 잠시 뒤 다시 눌러 주세요")
            case "check":
                showToast("Cloudflare 체크박스를 누른 뒤 아래 '등록'을 눌러 주세요")
                commentCompose = nil
            default:
                s.sending = false
                showToast("댓글 칸을 못 찾았어요. 댓글을 다시 눌러 주세요")
            }
        }
    }

    /// 입력창 닫기 (내용은 디시 댓글 칸에 채워 둠)
    func closeCommentCompose(sync: Bool) {
        guard let s = commentCompose else { return }
        CommentDraftStore.remove(s.draftKey)   // 직접 닫은 글은 웹 댓글칸에 옮겨 두므로 따로 보관한 것은 지움
        // 쓰다 바깥을 눌러 닫은 글: 같은 글 안에서 곧바로 다른 댓글을 눌러 새 입력창이 열리면 그 글을 옮겨 줌 (10분 안)
        if !s.sending, !s.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commentCarry = (s.text, s.code, s.pageKey, Date())
        }
        if sync && !s.sending {
            Task {
                await reattachCompose(s)
                _ = await call("return window.__dcapp ? window.__dcapp.composeSync(p) : false;", composeArgs(s))
            }
        }
        withAnimation(.easeOut(duration: 0.2)) { commentCompose = nil }
    }

    /// 유동이면 닉네임·비밀번호, 코드칸이 있으면 코드를 확인하고 기억 (안 맞으면 안내하고 false)
    private func commentIdentityOK(_ s: CommentComposeSession) -> Bool {
        if s.anon {
            if s.nick.trimmingCharacters(in: .whitespaces).isEmpty { showToast("닉네임을 입력해 주세요"); return false }
            if s.pw.isEmpty { showToast("비밀번호를 입력해 주세요"); return false }
            AnonStore.update(gallery: currentGalleryID, nick: s.nickLocked ? nil : s.nick, password: s.pw)
        }
        if s.hasCode && s.code.trimmingCharacters(in: .whitespaces).isEmpty { showToast("코드를 입력해 주세요"); return false }
        return true
    }

    // MARK: 글자콘 댓글 (디시의 글자콘 창을 화면 밖에서 열어 두고 앱이 조작)

    func txtconOpen() async -> TxtconInfo? {
        if let s = commentCompose { await reattachCompose(s) }
        guard let r = await call("return window.__dcapp ? await window.__dcapp.txtconOpen() : null;") as? [String: Any] else { return nil }
        func colors(_ key: String) -> [TxtconColor] {
            (r[key] as? [[String: Any]] ?? []).map { TxtconColor(hex: $0["hex"] as? String ?? "ffffff", on: $0["on"] as? Bool ?? false) }
        }
        return TxtconInfo(bg: colors("bg"), font: colors("font"), recent: r["recent"] as? [String] ?? [],
                          max: (r["max"] as? NSNumber)?.intValue ?? 20)
    }

    /// 입력한 글자를 글자콘 창에 넣고, 디시가 걸러 낸 결과(글자수·글자 제한)를 돌려받음
    func txtconSetText(_ t: String) async -> String {
        await call("return window.__dcapp ? window.__dcapp.txtconSetText(t) : t;", ["t": t]) as? String ?? t
    }

    func txtconSetColor(_ kind: String, _ hex: String) {
        Task { _ = await call("return window.__dcapp ? window.__dcapp.txtconSetColor(k, h) : false;", ["k": kind, "h": hex]) }
    }

    func txtconClose() {
        Task { _ = await call("return window.__dcapp ? window.__dcapp.txtconClose() : false;") }
    }

    func sendCommentTxtcon() async -> Bool {
        guard let s = commentCompose, !s.sending, commentIdentityOK(s) else { return false }
        s.sending = true
        await reattachCompose(s)
        let r = await call("return window.__dcapp ? window.__dcapp.txtconSend(p) : 'none';",
                           ["p": ["nick": s.nick, "pw": s.pw, "code": s.code]]) as? String ?? "none"
        switch r {
        case "sent":
            Task {
                try? await Task.sleep(for: Self.commentSendFallback)
                if commentCompose === s { s.sending = false }
            }
            return true
        case "tswait", "tserror":
            s.sending = false
            showToast(Self.tsWaitToast(r))
        case "notready":
            s.sending = false
            showToast("댓글 기능을 아직 준비 중이에요. 잠시 뒤 다시 눌러 주세요")
        case "check":
            showToast("Cloudflare 체크박스를 누른 뒤 글자콘을 다시 등록해 주세요")
            commentCompose = nil
        default:
            s.sending = false
            showToast("글자콘을 올리지 못했어요")
        }
        return false
    }

    /// 앱 입력창에서 고른 디시콘을 바로 댓글로 등록 (디시콘 댓글은 글자 없이 디시콘만 올라감)
    func sendCommentDccon(_ item: DcconItem) async -> Bool {
        guard let s = commentCompose, !s.sending, commentIdentityOK(s) else { return false }
        s.sending = true
        await reattachCompose(s)
        let args: [String: Any] = ["p": ["nick": s.nick, "pw": s.pw, "code": s.code], "k": item.pkg, "d": item.detail]
        let r = await call("return window.__dcapp ? window.__dcapp.composeDcconSend(p, k, d) : 'none';", args) as? String ?? "none"
        switch r {
        case "sent":
            Task {
                // 성공하면 'cmtok'으로 닫힘. 응답이 없으면 입력창을 다시 쓸 수 있게
                try? await Task.sleep(for: Self.commentSendFallback)
                if commentCompose === s { s.sending = false }
            }
            return true
        case "tswait", "tserror":
            s.sending = false
            showToast(Self.tsWaitToast(r))
        case "notready":
            s.sending = false
            showToast("댓글 기능을 아직 준비 중이에요. 잠시 뒤 다시 눌러 주세요")
        case "check":
            showToast("Cloudflare 체크박스를 누른 뒤 디시콘을 다시 골라 주세요")
            commentCompose = nil
        default:
            s.sending = false
            showToast("디시콘을 올리지 못했어요")
        }
        return false
    }

    func replyToPendingComment() {
        commentLink = nil
        Task { _ = await call("return window.__dcapp ? window.__dcapp.replyPending() : false;") }
    }
    /// 뒤로가기: 지나온 페이지를 거꾸로 짚어서 '돌아갈 만한' 가장 최근 페이지로 바로 감
    func goBack() {
        if let target = backTarget() { _ = webView.go(to: target) } else { _ = webView.goBack() }
    }

    /// 돌아갈 페이지 — 건너뛰는 것: 로그인 창(msign), 지금과 같은 주소(로그인 뒤 되돌아온 같은 글 등),
    /// 글쓰기 화면(글을 올린 뒤에 뒤로 가면 다시 글쓰기가 뜨지 않게, 지금이 글쓰기 화면이 아닐 때만)
    private func backTarget() -> WKBackForwardListItem? {
        func isWrite(_ url: URL) -> Bool { AutoImageStore.writeGalleryID(from: url) != nil }
        func plain(_ url: URL) -> String {
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
            c?.fragment = nil
            return c?.string ?? url.absoluteString
        }
        let current = webView.url
        let skipWrite = current.map { !isWrite($0) } ?? true
        return webView.backForwardList.backList.reversed().first { item in       // 최근 것부터
            if item.url.host == DC.loginHost { return false }
            if let current, plain(item.url) == plain(current) { return false }
            if skipWrite && isWrite(item.url) { return false }
            return true
        }
    }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    /// 당겨서 새로고침: 글 목록이 2페이지 이상이면 새로고침 대신 1페이지로 (말머리·개념글 등 다른 조건은 유지)
    @objc private func handlePullToRefresh() {
        if isGalleryListPage, listPageNumber > 1, let url = webView.url,
           var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let rest = (c.queryItems ?? []).filter { $0.name != "page" }
            c.queryItems = rest.isEmpty ? nil : rest
            c.fragment = nil
            if let first = c.url {
                webView.load(URLRequest(url: first))
                return
            }
        }
        webView.reload()
    }

    private var swipeStartX: CGFloat = 0

    /// 갤러리 목록 화면에서 스와이프했을 때 할 일 (메인 화면에서는 "갤러리" 창 열기)
    var onGallerySwipe: (() -> Void)?
    /// 분할 화면: 글 주소로 가는 이동을 오른쪽(글) 화면이 대신 열 때 (true면 이 화면은 이동하지 않음)
    var postInterceptor: ((URL) -> Bool)?
    /// 분할 화면의 왼쪽에 글이 열렸을 때 (오른쪽으로 옮기기 위해)
    var postLanded: ((URL) -> Void)?
    /// 분할 화면의 글 수정을 등록한 뒤, 디시가 글 목록으로 보내면 수정한 글로 다시 가기 위한 기억
    private var pendingModifyReturn: (url: URL, at: Date)?
    /// 분할 화면: 새 글을 등록하고 목록으로 돌아오면 그 글을 오른쪽에서 열기 위한 연결 (true면 처리함)
    var openWrittenPost: ((URL) -> Bool)?
    /// 분할 화면에서 접어 오른쪽 글 화면을 한 화면으로 쓰는 중, 글에서 뒤로 가면 (글끼리 거슬러 가지 않고) 목록 화면으로 — true면 처리함
    var backToListHandler: (() -> Bool)?
    /// 분할 화면 오른쪽(글) 화면의 '글목록' 버튼: 왼쪽 목록 화면을 이 글의 갤러리 목록으로 (url = 그 갤러리 목록 주소)
    var showListInMain: ((URL) -> Void)?
    static let postReadNotification = Notification.Name("DCPostRead")
    /// 분할 화면의 오른쪽(글) 화면인지 — 뒤로 갈 곳이 없어도 글 목록으로 가지 않음
    var isDetailPane = false {
        didSet {
            guard oldValue != isDetailPane else { return }
            installUserScript()   // 다음 페이지부터
            webView.evaluateJavaScript("window.__dcapp && window.__dcapp.setConfig(\(scriptConfigJSON)); true", completionHandler: nil)
        }
    }
    private var scriptConfigJSON: String { FilterStore.shared.scriptConfig(detailPane: isDetailPane) }

    /// 지금 화면이 갤러리 글 목록인지 (글 보기·글쓰기 화면은 아님)
    var isGalleryListPage: Bool {
        guard let url = webView.url, Gallery.parse(url) != nil else { return false }
        return SavedPostStore.postInfo(url) == nil && AutoImageStore.writeGalleryID(from: url) == nil
    }

    /// 지금 목록의 페이지 번호 (주소의 page=, 없으면 1)
    private var listPageNumber: Int {
        guard let url = webView.url,
              let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value,
              let n = Int(v) else { return 1 }
        return n
    }

    static var customSwipeEnabled: Bool {
        Profile.defaults.object(forKey: "fullSwipeBack") as? Bool ?? true
    }

    /// 스와이프 민감도 (설정 → 앱, 1 = 둔감 … 5 = 민감, 기본 3)
    /// distance: 이만큼 밀면 뒤로 / flickSpeed: 절반만 밀어도 이 속도 이상으로 튕기면 뒤로
    /// ratio: 가로로 민 거리가 세로의 몇 배 이상이어야 하는지 (클수록 위아래 스크롤과 덜 헷갈림)
    static var swipeThresholds: (distance: CGFloat, flickSpeed: CGFloat, ratio: CGFloat) {
        let level = min(5, max(1, Profile.defaults.object(forKey: "swipeSensitivity") as? Double ?? 3))
        let d = CGFloat(3 - level)                 // 둔감할수록 + , 민감할수록 -
        // 보통(3) = 지금까지 쓰던 값 (50pt / 초속 500 / 1.5배)
        return (distance: 50 * pow(2, d * 0.6),        // 매우 둔감 ≈115pt … 매우 민감 ≈22pt
                flickSpeed: 500 * pow(2, d * 0.4),     // ≈870 … ≈290
                ratio: max(1.1, 1.5 + d * 0.4))        // 2.3배 … 1.1배
    }

    @objc private func handleSwipe(_ g: UIPanGestureRecognizer) {
        if g.state == .began { swipeStartX = g.location(in: webView).x }
        guard g.state == .ended, Self.customSwipeEnabled else { return }
        // 화면 어디서 시작하든 오른쪽으로 쓸면 뒤로가기
        let t = g.translation(in: webView)
        let v = g.velocity(in: webView)
        let th = Self.swipeThresholds
        guard t.x > abs(t.y) * th.ratio,
              t.x > th.distance || (t.x > th.distance / 2 && v.x > th.flickSpeed) else { return }
        guard canSwipeBack else { return }
        Task {
            // 말머리 탭처럼 가로로 스크롤되는 곳에서 시작한 스와이프, 글자를 선택(드래그)하는 중의 스와이프는 무시
            let skip = await call("return window.__dcapp ? (window.__dcapp.lastTouchInHScroll() || window.__dcapp.textSelecting()) : false;") as? Bool ?? false
            guard !skip else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            swipeBack()
        }
    }

    // MARK: - '뒤로' 동작 (화면 쓸기와 키보드 모드의 뒤로가기 버튼·⌘[ 가 똑같이 씀)

    /// 말머리를 골라 본 글 목록이면 → 뒤로가기는 '전체' 말머리(1페이지)로
    private var allHeadURLOnBack: URL? {
        guard let url = webView.url, isGalleryListPage,
              var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = c.queryItems ?? []
        if items.contains(where: { $0.name == "serval" || $0.name == "s_keyword" }) { return nil }   // 검색 결과는 제외
        guard let head = items.first(where: { $0.name == "headid" })?.value, !head.isEmpty else { return nil }
        let rest = items.filter { $0.name != "headid" && $0.name != "page" }
        c.queryItems = rest.isEmpty ? nil : rest
        c.fragment = nil
        return c.url
    }

    /// 갤러리 목록 1페이지('전체' 말머리)면 → 뒤로가기 대신 "갤러리" 창 열기 (2페이지부터는 뒤로가기)
    private var opensGalleriesOnBack: Bool {
        // 검색 결과 목록은 제외 (검색 전 목록으로 돌아가야 하므로 보통 뒤로가기)
        let q = webView.url?.query ?? ""
        let isSearch = q.contains("serval=") || q.contains("s_keyword=")
        return isGalleryListPage && !isSearch && listPageNumber <= 1 && onGallerySwipe != nil &&
            (Profile.defaults.object(forKey: "gallerySwipeOpensList") as? Bool ?? true)
    }

    /// 글 보는 중인지 (그 갤러리) — 돌아갈 페이지가 없을 때 목록 1페이지로 보내기 위함
    private var postGalleryOnBack: Gallery? {
        webView.url.flatMap { url -> Gallery? in
            guard SavedPostStore.postInfo(url) != nil, let g = Gallery.parse(url) else { return nil }
            return Gallery(galleryID: g.id, name: g.id, kind: g.kind)
        }
    }

    /// 개념글 목록 2페이지 이상이면 바로 앞 페이지 주소
    private var recommendPrevPageURL: URL? {
        guard let url = webView.url, url.query?.contains("recommend=1") == true,
              SavedPostStore.postInfo(url) == nil,
              var c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let page = c.queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init), page > 1 else { return nil }
        c.queryItems = c.queryItems?.map { $0.name == "page" ? URLQueryItem(name: "page", value: String(page - 1)) : $0 }
        return c.url
    }

    /// 지금 '뒤로' 할 수 있는 게 있는지
    var canSwipeBack: Bool {
        recommendPrevPageURL != nil || allHeadURLOnBack != nil || opensGalleriesOnBack || postGalleryOnBack != nil || backTarget() != nil
    }

    func swipeBack() {
        if let handler = backToListHandler, webView.url.flatMap({ PostKey.from($0) }) != nil, handler() { return }
        if isDetailPane {
            if webView.canGoBack { webView.goBack() }
            return
        }
        if let prev = recommendPrevPageURL {
            load(prev)        // 개념글 2페이지 이상 → 그 전 페이지 (전체글로 가지 않음)
        } else if let url = webView.url, url.query?.contains("recommend=1") == true,
           let g = Gallery.parse(url), SavedPostStore.postInfo(url) == nil {
            // 개념글 목록에서 → 같은 갤러리의 전체글로
            load(Gallery(galleryID: g.id, name: g.id, kind: g.kind).url)
        } else if let all = allHeadURLOnBack {
            load(all)         // 다른 말머리 → '전체' 말머리로
        } else if opensGalleriesOnBack {
            onGallerySwipe?()
        } else if let g = postGalleryOnBack {
            if backTarget() != nil {
                goBack()      // 글 보기 → 지나온 페이지 중 로그인 창 등을 건너뛴 곳으로 (보던 목록 페이지 등)
            } else {
                // 돌아갈 곳이 없으면 (알림·링크로 바로 열었을 때 등) 갤러리 목록 1페이지로, 개념글에서 온 글이면 개념글로
                let fromRecommend = webView.url?.query?.contains("recommend=1") == true
                load(fromRecommend ? g.recommendURL : g.url)
            }
        } else {
            goBack()
        }
    }

    private func endRefreshing() {
        webView.scrollView.refreshControl?.endRefreshing()
    }

    /// 디시가 요청한 alert/confirm/prompt 창을 띄움. 닫히는 중인 팝업 위라서 안 뜨거나, 뜬 뒤 액션 없이 사라져도
    /// 반드시 한 번은 응답(giveUp)하게 함 — 응답이 없으면 웹 화면이 영영 멈춤(페이지 이동·새로고침 불가)
    private func presentPanel(_ alert: UIAlertController, giveUp: @escaping () -> Void) {
        Task { @MainActor in
            var shown = false
            for _ in 0..<8 {
                if let vc = presenter(), !vc.isBeingDismissed, !vc.isBeingPresented {
                    vc.present(alert, animated: true)
                    try? await Task.sleep(for: .milliseconds(350))
                    if alert.presentingViewController != nil || alert.isBeingPresented { shown = true; break }
                } else {
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            guard shown else { giveUp(); return }
            // 뜬 뒤 사용자가 누르지 않았는데 사라졌으면(부모 팝업이 닫히며 같이 사라짐 등) 응답 처리
            while true {
                try? await Task.sleep(for: .milliseconds(400))
                if alert.presentingViewController == nil && !alert.isBeingPresented && !alert.isBeingDismissed { giveUp(); return }
            }
        }
    }

    private func presenter() -> UIViewController? {
        var top = webView.window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - 페이지 스크립트

    private func installUserScript() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let source = "window.__DCAPP_CONFIG__ = \(scriptConfigJSON);\n" + ContentScript.source
        // 알림 주소 찾기용 네트워크 기록 (페이지 맨 처음에 넣어야 처음부터 기록됨)
        controller.addUserScript(WKUserScript(source: ContentScript.netLog, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        // 웹페이지가 화면 옆 안전 영역(듀오의 시계·카메라 줄)을 비워두지 않고 끝까지 쓰도록
        controller.addUserScript(WKUserScript(source: Self.viewportFitCover, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        // 앱 자체 광고 차단 (광고 서버 요청 막기)
        AdBlock.apply(to: controller)
    }

    private static let viewportFitCover = #"""
(function () {
  var m = document.querySelector('meta[name="viewport"]');
  if (!m) {
    m = document.createElement('meta');
    m.name = 'viewport';
    m.content = 'width=device-width, initial-scale=1';
    (document.head || document.documentElement).appendChild(m);
  }
  if (!/viewport-fit/.test(m.content)) m.content += ', viewport-fit=cover';
})();
"""#

    /// 듀오 세로 줄이 왼쪽↔오른쪽으로 바뀌었을 때 지금 페이지의 글자 여백 방향을 바로 바꿈
    func setColumnFlip(_ on: Bool) {
        applyFilters()   // 다음 페이지부터 쓸 설정도 갱신
        let js = "(function(on){var r=document.documentElement;if(!r)return;if(on)r.classList.add('dcapp-duocol');r.classList.toggle('dcapp-duoflip',on);})(\(on)); true"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// 크기가 바뀐 뒤 웹 화면을 새 크기로 다시 배치 (돌린 뒤 비어 보이는 일 대비)
    func nudgeLayout() {
        // 웹뷰가 들어 있는 상자의 현재 크기에 맞추고, 웹 화면(스크롤 영역 포함)을 다시 배치
        if let sv = webView.superview { webView.frame = sv.bounds }
        webView.setNeedsLayout()
        webView.scrollView.setNeedsLayout()
        webView.evaluateJavaScript("window.dispatchEvent(new Event('resize')); true", completionHandler: nil)
    }

    /// 세로 컨트롤바가 웹 화면 위에 떠서 가리는 폭 (왼쪽/오른쪽) — 글 아래 수정·삭제 버튼 줄을 그만큼 비워 겹치지 않게
    private var barInsetL: CGFloat = 0
    private var barInsetR: CGFloat = 0
    func setBarInset(left: CGFloat, right: CGFloat) {
        guard left != barInsetL || right != barInsetR else { return }
        barInsetL = left; barInsetR = right
        applyBarInset()
    }
    func applyBarInset() {
        let js = "(function(l,r){var s=document.documentElement&&document.documentElement.style;if(!s)return;s.setProperty('--dcapp-bar-l',l+'px');s.setProperty('--dcapp-bar-r',r+'px');})(\(Int(barInsetL)),\(Int(barInsetR))); true"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func applyFilters() {
        webView.allowsBackForwardNavigationGestures = !Self.customSwipeEnabled
        installUserScript()   // 다음 페이지부터 적용
        let js = "window.__dcapp && window.__dcapp.setConfig(\(scriptConfigJSON)); true"
        webView.evaluateJavaScript(js, completionHandler: nil)   // 지금 페이지에 즉시 적용
    }

    @discardableResult
    private func call(_ body: String, _ args: [String: Any] = [:]) async -> Any? {
        try? await webView.callAsyncJavaScript(body, arguments: args, contentWorld: .page)
    }

    // MARK: - 요소 숨기기 모드

    func setPickMode(_ on: Bool) {
        if on && isBlockPickMode { setBlockPickMode(false) }
        if on && isMemoPickMode { setMemoPickMode(false) }
        isPickMode = on
        Task { await call("if (window.__dcapp) window.__dcapp.setPickMode(on); return true;", ["on": on]) }
    }

    // MARK: - 탭해서 유저 차단 모드 / 글 작성자 차단

    func setBlockPickMode(_ on: Bool) {
        if on && isPickMode { setPickMode(false) }
        if on { isMemoPickMode = false }
        isBlockPickMode = on
        Task { await call("if (window.__dcapp) window.__dcapp.setBlockPickMode(on); return true;", ["on": on]) }
    }

    /// 탭해서 메모: 페이지 쪽은 '탭해서 차단'과 같은 고르기 모드를 씀
    func setMemoPickMode(_ on: Bool) {
        if on && isPickMode { setPickMode(false) }
        if on { isBlockPickMode = false }
        isMemoPickMode = on
        showToast(on ? "메모할 글이나 댓글의 작성자를 탭하세요" : "메모 모드를 끝냈어요")
        Task { await call("if (window.__dcapp) window.__dcapp.setBlockPickMode(on); return true;", ["on": on]) }
    }

    /// 지금 보고 있는 글의 작성자 정보 (글 보기 화면이 아니면 nil)
    func articleAuthor() async -> BlockRequest? {
        guard let dict = await call("return window.__dcapp ? window.__dcapp.articleAuthor() : null;") as? [String: Any]
        else { return nil }
        let r = BlockRequest(dict)
        return (r.userID.isEmpty && r.ip.isEmpty && r.nick.isEmpty) ? nil : r
    }

    // MARK: - 자짤

    /// 글쓰기 화면의 사진 첨부 칸에 자짤 1장 넣기. force=false(자동)이면 중복 방지 규칙을 따름
    func attachAutoImage(force: Bool) {
        let store = AutoImageStore.shared
        guard let url = webView.url, let galleryID = AutoImageStore.writeGalleryID(from: url) else { return }
        guard let img = store.pick(for: galleryID, account: AutoImageScope.currentAccount()),
              let data = try? Data(contentsOf: store.fileURL(img)) else {
            if force { showToast("등록된 자짤이 없어요 (설정 → 자짤)") }
            return
        }
        let args: [String: Any] = [
            "b64": data.base64EncodedString(),
            "name": "image_\(Int(Date().timeIntervalSince1970)).\(img.ext)",
            "mime": img.mime,
            "force": force,
        ]
        Task {
            let result = await call("return window.__dcapp ? await window.__dcapp.attachImage(b64, name, mime, force) : 'noscript';", args) as? String
            switch result {
            case "attached": showToast("자짤을 첨부했어요")
            case "already": break
            case "noinput": showToast("사진 첨부 칸을 찾지 못했어요")
            default: if force { showToast("자짤 첨부에 실패했어요") }
            }
        }
    }

    // MARK: - 글 보관

    /// 지금 보고 있는 글을 보관함에 저장 (본문 사본 포함)
    func savePost(folderID: UUID? = nil, keepFolder: Bool = true) async {
        guard let url = webView.url, let info = SavedPostStore.postInfo(url) else {
            showToast("글 보기 화면에서 쓸 수 있어요")
            return
        }
        showToast("보관하는 중…")
        await call("return window.__dcapp ? window.__dcapp.prepareCapture() : 0;")   // 지연 로딩 이미지까지 불러오기
        try? await Task.sleep(for: .milliseconds(800))
        let archive = await webArchive()
        let postTitle = Gallery.cleanTitle(self.title)
        let wasSaved = SavedPostStore.shared.contains(url: url)
        SavedPostStore.shared.add(url: url, title: postTitle, galleryID: info.galleryID, archive: archive,
                                  folderID: folderID, keepFolder: keepFolder)
        let place = SavedPostStore.shared.post(for: url).map { SavedPostStore.shared.folderName($0.folderID) } ?? ""
        showToast(wasSaved ? "보관한 글을 최신 내용으로 갱신했어요" : "보관함(\(place))에 저장했어요")
    }

    private func webArchive() async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            webView.createWebArchiveData { result in
                cont.resume(returning: try? result.get())
            }
        }
    }

    // MARK: - 임시저장

    private var currentWriteGalleryID: String? {
        webView.url.flatMap(AutoImageStore.writeGalleryID)
    }

    func saveDraftManually() async {
        guard let gid = currentWriteGalleryID,
              let d = await call("return window.__dcapp ? window.__dcapp.getDraft() : null;") as? [String: Any],
              (d["ok"] as? Bool) == true else {
            showToast("글쓰기 칸을 찾지 못했어요")
            return
        }
        let title = d["title"] as? String ?? ""
        let body = d["body"] as? String ?? ""
        let preview = d["text"] as? String ?? ""
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("저장할 내용이 없어요")
            return
        }
        DraftStore.shared.addManual(galleryID: gid, title: title, body: body, preview: preview,
                                    isHTML: d["html"] as? Bool ?? false, writeURL: webView.url)
        showToast("임시저장했어요")
    }

    func restoreDraft(_ draft: Draft, message: String = "임시저장 글을 불러왔어요") {
        Task {
            let r = await call("return window.__dcapp ? window.__dcapp.setDraft(t, b, h) : 'noscript';",
                               ["t": draft.title, "b": draft.body, "h": draft.isHTML]) as? String
            showToast(r == "restored" ? message : "글쓰기 칸을 찾지 못했어요")
        }
    }

    /// 로그인·로그아웃으로 글쓰기 화면이 다시 열려도 쓰던 내용이 남도록: 지금 내용을 잡아 두었다가 다시 열리면 채움
    private var keptWrite: (draft: Draft, at: Date)?
    /// 로그인·로그아웃으로 글쓰기 화면을 떠났다가 돌아오면 이 시각까지 그 갤러리의 자동 저장본을 다시 채움 (keptWrite가 어디선가 지워져도 복구되게 하는 안전망)
    private var loginRestoreDeadline: Date?
    /// 로그아웃으로 글쓰기 페이지를 다시 열었을 때, 앱 글쓰기 화면은 두고 양식 정보만 다시 읽기
    private var nativeWriteNeedsReread = false
    /// 마지막으로 본 글쓰기 페이지 주소 (웹 프로세스가 종료돼 url이 비었을 때 복구용)
    private var lastWriteURL: URL?
    /// 웹 프로세스가 종료돼 글쓰기 페이지를 다시 여는 중 (이 화면·주소). 페이지가 다시 열리면 양식만 다시 읽고,
    /// 로그인 만료 등으로 글쓰기 페이지가 아닌 곳이 열리면 쓰던 글을 남겨 둠
    private var nativeRecovery: (session: NativeWriteSession, url: URL)?
    /// 앱 글쓰기 양식이 끝내 안 열릴 때 화면을 닫는 타이머 (다시 불러올 때 취소하고 새로 맞춤)
    private var nativeLoadTimeout: Task<Void, Never>?

    /// 앱 글쓰기 화면의 쓰던 내용을 자동 임시저장 (쓴 게 없으면 아무것도 안 함). 저장한 칸 목록을 돌려줌
    @discardableResult
    private func autosaveNativeWrite(_ s: NativeWriteSession, writeURL: URL?) -> [DraftPart]? {
        guard s.hasText || s.hasUserImages else { return nil }
        let parts = s.draftParts()
        DraftStore.shared.autosave(galleryID: s.galleryID, title: s.title, body: s.body,
                                   preview: String(s.body.prefix(200)), isHTML: false, writeURL: writeURL, parts: parts)
        return parts
    }

    /// 자동 임시저장 + 다시 열린 글쓰기 화면에 채울 수 있게 잡아 둠 (로그인·로그아웃 등으로 글쓰기 화면을 떠날 때)
    private func keepNativeWrite(_ s: NativeWriteSession, writeURL: URL?) {
        guard let parts = autosaveNativeWrite(s, writeURL: writeURL) else { return }
        keptWrite = (Draft(id: UUID(), galleryID: s.galleryID, title: s.title, body: s.body,
                           preview: String(s.body.prefix(200)), isHTML: false, isAuto: true,
                           updatedAt: Date(), writeURL: writeURL, parts: parts), Date())
    }

    /// 앱 글쓰기 양식이 끝내 안 열리면 닫고 안내하는 타이머. 새로 열 때·웹 프로세스 종료로 다시 불러올 때마다
    /// 이전 타이머를 취소하고 새로 맞춤 (옛 타이머가 남아 있다가 다시 불러오는 중에 화면을 닫지 않게)
    /// keepWritten: 쓰던 글이 있으면 닫지 않고 안내만 (다시 불러오는 경우 — 내용은 임시저장돼 있고 페이지가 늦게라도 열리면 이어서 됨)
    private func armNativeLoadTimeout(for s: NativeWriteSession, seconds: Int = 20, keepWritten: Bool = false) {
        nativeLoadTimeout?.cancel()
        nativeLoadTimeout = Task { @MainActor [weak self] in
            // 앱이 화면에 떠 있던 시간만 1초씩 셈 — 백그라운드에 있다 돌아오는 순간 밀린 타이머가 한꺼번에 끝나, 페이지가 열리기도 전에 화면이 닫히지 않게
            var waited = 0
            while waited < seconds {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if UIApplication.shared.applicationState == .active { waited += 1 }
            }
            guard let self, self.nativeWrite === s, !s.loaded, !s.submitting, self.retrySession == nil else { return }
            if keepWritten, s.hasText || s.hasUserImages {
                self.showToast("글쓰기 페이지를 아직 못 불러왔어요. 쓰던 글은 임시저장에 있어요")
                return
            }
            self.forceCloseNativeWrite(quiet: true)
            self.showToast("글쓰기 화면을 불러오지 못했어요. 차단된 IP이거나 연결 문제일 수 있어요")
        }
    }

    /// 웹 프로세스 종료 뒤 글쓰기 페이지가 다시 열림: 앱 글쓰기 화면·내용은 그대로 두고 디시 양식(유동 닉·말머리·코드칸)만 다시 읽음
    /// 페이지 스크립트·양식이 준비되기 전에 읽으면 실패로 보고 화면이 닫히므로 준비될 때까지 기다림 (끝내 안 되면 화면은 두고 타이머가 안내)
    private func rereadNativeWrite(_ s: NativeWriteSession) {
        Task {
            var ready = false
            for _ in 0..<40 {
                guard nativeWrite === s else { return }
                ready = (await call("return !!(window.__dcapp && document.getElementById('subject'));") as? Bool) == true
                if ready { break }
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard nativeWrite === s, ready else { return }
            // 새 양식은 닉네임·비밀번호를 저장된 값으로 채우므로, 쓰던 화면에서 고쳐 둔 값은 다시 넣음
            let wasAnon = s.isAnon, nick = s.nick, pw = s.pw
            guard await readWriteInfo(s) != nil, nativeWrite === s else { return }
            if wasAnon, s.isAnon {
                if !s.nickLocked, !nick.isEmpty { s.nick = nick }
                if !pw.isEmpty { s.pw = pw }
            }
            s.loaded = true
            nativeLoadTimeout?.cancel()
        }
    }

    private func keepWriteBeforeReload() async {
        if let s = nativeWrite {
            keepNativeWrite(s, writeURL: webView.url)
            return
        }
        guard let gid = currentWriteGalleryID,
              let d = await call("return window.__dcapp ? window.__dcapp.getDraft() : null;") as? [String: Any],
              (d["ok"] as? Bool) == true else { return }
        let title = d["title"] as? String ?? "", body = d["body"] as? String ?? "", preview = d["text"] as? String ?? ""
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let isHTML = d["html"] as? Bool ?? false
        // 혹시 몰라 자동 임시저장에도 남김 (불러오기에서 다시 꺼낼 수 있게)
        DraftStore.shared.autosave(galleryID: gid, title: title, body: body, preview: preview, isHTML: isHTML, writeURL: webView.url)
        keptWrite = (Draft(id: UUID(), galleryID: gid, title: title, body: body, preview: preview,
                           isHTML: isHTML, isAuto: true, updatedAt: Date(), writeURL: webView.url), Date())
    }

    // MARK: - 지금 화면에서 로그인 / 로그아웃 (글쓰기 화면 계정 버튼)

    /// 로그인 후 지금 보던 화면(글쓰기 등)으로 돌아오는 로그인 주소
    private func loginURL(returnTo url: URL?) -> URL {
        guard let url else { return DC.login }
        var comps = URLComponents(string: "https://msign.dcinside.com/login")!
        comps.queryItems = [URLQueryItem(name: "r_url", value: url.absoluteString)]
        return comps.url ?? DC.login
    }

    /// account가 있으면 그 계정으로 자동 로그인, nil이면 로그인 화면만 열기. 끝나면 지금 화면으로 돌아옴
    func loginHere(_ account: LoginCredential?) {
        let back = webView.url
        Task {
            await keepWriteBeforeReload()
            if AutoImageStore.writeGalleryID(from: back ?? DC.login) != nil { loginRestoreDeadline = Date().addingTimeInterval(1800) }
            if CredentialStore.currentAccountID != nil || account != nil {
                await DCSession.clear(notify: false)      // 다른 계정으로 바꿀 때는 기존 로그인 지우기
            }
            pendingLogin = account
            manualLogin = (account == nil)
            load(loginURL(returnTo: back))
            if let account { showToast("\(account.id) 계정으로 로그인하는 중…") }
        }
    }

    /// 로그아웃하고 지금 화면을 다시 열기 (유동으로 쓰기)
    func logoutHere() {
        let back = webView.url
        Task {
            if nativeWrite != nil {
                // 앱 글쓰기는 화면(사진 포함)을 그대로 두고, 페이지가 다시 열리면 양식(유동 닉·비번·코드)만 다시 읽음
                nativeWriteNeedsReread = true
            } else {
                await keepWriteBeforeReload()
            }
            if AutoImageStore.writeGalleryID(from: back ?? DC.login) != nil { loginRestoreDeadline = Date().addingTimeInterval(1800) }
            await DCSession.clear(notify: false)
            NotificationCenter.default.post(name: DC.sessionChanged, object: self)   // 다른 화면만 새로고침
            if let back { load(back) } else { reload() }
            showToast("로그아웃했어요")
        }
    }

    // MARK: - 댓글 새로고침

    /// 디시의 댓글 ⟳ 버튼을 대신 누르고, 못 찾으면 페이지를 새로고침한 뒤 댓글 위치로 이동
    func refreshComments() {
        // 댓글만 다시 받으면 다른 기기에서 쓴 새 댓글이 안 보여서, 글을 다시 불러온 뒤 댓글 쪽으로 이동
        scrollToCommentsAfterLoad = true
        reload()
    }

    /// 글 신고: 디시의 신고 창을 그대로 띄움
    func reportPost() {
        Task {
            let r = await call("return window.__dcapp ? window.__dcapp.reportPost() : 'none';") as? String
            if r == "none" || r == nil { showToast("신고 화면을 열 수 없어요") }
        }
    }

    // MARK: - 댓글 등록 중 광고 차단 잠시 끄기

    private var adResumeTask: Task<Void, Never>?

    private func pauseAdBlock() {
        guard AdBlock.enabled else { return }
        adResumeTask?.cancel()          // 다시 켜기로 한 게 있으면 취소
        AdBlock.setPaused(true, controller: webView.configuration.userContentController)
    }

    private func resumeAdBlock(after seconds: Double) {
        guard AdBlock.paused else { return }
        adResumeTask?.cancel()
        adResumeTask = Task {
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard !Task.isCancelled else { return }
            AdBlock.setPaused(false, controller: webView.configuration.userContentController)
        }
    }

    // MARK: - 댓글 429 자동 재등록

    // MARK: - 앱 글쓰기 화면

    static let nativeWriteKey = "nativeWrite"
    static var nativeWriteEnabled: Bool { Profile.defaults.object(forKey: nativeWriteKey) as? Bool ?? true }

    /// 글쓰기 페이지가 열리면 앱 글쓰기 화면을 만들고, 디시 양식에서 유동 여부·말머리 등을 읽어 옴
    /// 앱 글쓰기 화면을 먼저 띄움 (디시 글쓰기 주소로 이동을 시작하는 순간) — 페이지 로딩 중에도 브라우저 상단바 대신 앱 상단바가 보이게
    /// 이어쓰기 / 로그인 후 돌아옴 복원도 여기서
    @discardableResult
    private func beginNativeWrite(_ gid: String) -> (session: NativeWriteSession, restored: Bool) {
        let s = NativeWriteSession(galleryID: gid)
        nativeWrite = s
        var restored = false
        if let d = pendingDraft {
            pendingDraft = nil; keptWrite = nil
            s.apply(d); restored = true
            if d.galleryID != gid { convertRemotePhotos(s) }
        } else if let k = keptWrite {
            keptWrite = nil
            if k.draft.galleryID == gid, Date().timeIntervalSince(k.at) < 1800 { s.apply(k.draft); restored = true }
        }
        if !restored, let dl = loginRestoreDeadline {
            loginRestoreDeadline = nil
            if Date() < dl, let d = DraftStore.shared.drafts.first(where: { $0.isAuto && $0.galleryID == gid && Date().timeIntervalSince($0.updatedAt) < 1800 }) {
                s.apply(d); restored = true
            }
        }
        s.restoredFromDraft = restored
        return (s, restored)
    }

    private var retrySession: NativeWriteSession?

    /// 디시의 '너무 많은 요청으로 이용하실 수 없습니다' 안내 페이지가 뜨면 → 풀릴 때까지 빠르게 자동 새로고침
    private var tooManyTries = 0
    private func retryIfTooManyRequests() {
        let url = webView.url
        Task { @MainActor in
            let js = "(function(){var b=document.body;if(!b)return false;var t=b.innerText||'';return t.length<600 && t.indexOf('너무 많은 요청으로')>=0 && t.indexOf('이용하실 수 없습니다')>=0;})()"
            let hit = (try? await webView.evaluateJavaScript(js)) as? Bool ?? false
            guard hit else { tooManyTries = 0; return }
            tooManyTries += 1
            guard tooManyTries <= 300 else {
                showToast("요청 제한이 계속돼서 자동 새로고침을 멈췄어요")
                tooManyTries = 0
                return
            }
            if tooManyTries == 1 { showToast("요청이 많아 안 열려요. 열릴 때까지 자동으로 다시 불러와요") }
            try? await Task.sleep(for: .milliseconds(600))
            // 그 사이에 다른 페이지로 옮겼으면 멈춤
            guard webView.url == url, !webView.isLoading else { return }
            if let u = url { webView.load(URLRequest(url: u)) } else { webView.reload() }
        }
    }

    private func startNativeWrite(_ gid: String) {
        let (s, restored) = beginNativeWrite(gid)
        finishNativeWriteStart(s, gid, restored: restored)
        // 글쓰기 양식이 끝내 안 열리면(차단된 IP로 글쓰기 페이지가 막힌 경우 등) 무한 로딩 대신 닫고 안내
        armNativeLoadTimeout(for: s)
    }

    /// 페이지 로딩이 끝난 뒤: 디시 양식 읽기 → 자짤·글 수정 불러오기
    private func finishNativeWriteStart(_ s: NativeWriteSession, _ gid: String, restored: Bool) {
        s.infoRequested = true
        Task {
            guard let info = await readWriteInfo(s) else { return }
            // 자짤 (자동 첨부로 설정된 계정·갤러리): 유동/로그인은 글쓰기 양식을 읽은 뒤에야 알 수 있음
            if info["mode"] as? String != "modify" && !restored {
                let eff = AutoImageStore.shared.effective(for: gid, account: AutoImageScope.currentAccount(isAnon: s.isAnon))
                if eff.enabled && eff.mode == .auto { addAutoImage(to: s, silent: true) }
            }
            // 글 수정: 원래 제목·내용(글자·사진 순서 그대로) 불러오기
            if info["mode"] as? String == "modify" {
                s.modifyPostURL = webView.url.flatMap(Self.postURL(fromModifyURL:))
                s.title = info["title"] as? String ?? ""
                let parts = info["blocks"] as? [[String: Any]] ?? []
                if !parts.isEmpty {
                    s.blocks = parts.map { p in
                        if p["t"] as? String == "raw" {
                            return WriteBlock(image: WriteImage(data: Data(), mime: "", ext: "", preview: nil,
                                                                rawHTML: p["html"] as? String ?? "",
                                                                remoteURL: (p["src"] as? String).flatMap(URL.init(string:)),
                                                                label: p["label"] as? String))
                        }
                        return WriteBlock(text: p["text"] as? String ?? "")
                    }
                    s.normalize()
                    s.stripKnownFooter()      // 옛 꼬릿말은 떼고, 등록할 때 규칙에 맞는 꼬릿말만 다시 붙임
                    loadRemotePreviews(s)
                }
            }
            s.loaded = true
            s.startDone = true
            runNativeAutosave(s)
        }
    }

    /// 디시 글쓰기 양식에서 유동 여부·닉네임·말머리·코드 입력칸을 읽어 앱 글쓰기에 반영 (못 읽으면 디시 화면으로)
    private func readWriteInfo(_ s: NativeWriteSession) async -> [String: Any]? {
        let info = await call("return window.__dcapp ? await window.__dcapp.writeInfo() : null;") as? [String: Any]
        guard nativeWrite === s else { return nil }
        guard let info, (info["ok"] as? Bool) == true else {
            if let info, info["banned"] as? Bool == true {
                // 갤러리에서 차단됨: 글쓰기 화면을 닫고 안내
                nativeWrite = nil
                swipeBack()
                showBanAlert(message: info["msg"] as? String ?? "")
                return nil
            }
            // 웹 프로세스가 종료돼 읽기가 끊긴 경우는 화면을 닫지 않음 (복구로 글쓰기 페이지가 다시 열리면 그때 다시 읽음)
            if let rec = nativeRecovery, rec.session === s { return nil }
            nativeWrite = nil
            showToast("글쓰기 양식을 못 읽어서 디시 화면으로 쓸게요")
            return nil
        }
        s.galleryName = info["gallery"] as? String ?? ""
        s.isAnon = info["anon"] as? Bool ?? false
        s.nickLocked = info["nickLocked"] as? Bool ?? false
        if s.isAnon {
            // 앱에 저장된 값(설정에서 바꾼 것·마지막에 쓴 것)이 우선. 디시가 기억해 둔 옛 값이나 잠긴 기본 닉네임은 저장된 값이 없을 때만 씀
            let pageNick = info["nick"] as? String ?? ""
            let saved = AnonStore.nick(for: s.galleryID)
            if s.nickLocked { s.nick = !pageNick.isEmpty ? pageNick : (saved.isEmpty ? "ㅇㅇ" : saved) }
            else { s.nick = !saved.isEmpty ? saved : (!pageNick.isEmpty ? pageNick : "ㅇㅇ") }
            let pagePw = info["pw"] as? String ?? ""
            let savedPw = AnonStore.password(for: s.galleryID)
            s.pw = !savedPw.isEmpty ? savedPw : pagePw
        } else {
            s.nick = ""; s.pw = ""
        }
        s.heads = (info["heads"] as? [[String: Any]] ?? []).compactMap { h in
            guard let no = h["no"] as? String, let name = h["name"] as? String else { return nil }
            // 말머리별 안내 문구는 디시 HTML 그대로(<br> 등) 오므로 글자만 남김
            return WriteHead(no: no, name: name, guide: NativeWriteSession.plainText(fromHTML: h["ph"] as? String ?? ""))
        }
        s.defaultGuide = NativeWriteSession.plainText(fromHTML: info["phDefault"] as? String ?? "")
        if s.head.isEmpty || !s.heads.contains(where: { $0.no == s.head }) { s.head = info["head"] as? String ?? "" }
        s.hasCaptcha = info["captcha"] as? Bool ?? false
        s.captchaImage = Self.imageFromDataURL(info["captchaImg"] as? String)
        s.captcha = ""
        return info
    }

    /// 글 수정: 원래 올라가 있던 사진 미리보기 (디시 이미지 서버는 Referer가 있어야 보여줌)
    func loadRemotePreviews(_ s: NativeWriteSession) {
        let targets = s.images.filter { $0.preview == nil }.compactMap { img in img.remoteURL.map { (img.id, $0) } }
        for (id, url) in targets {
            Task {
                var req = URLRequest(url: url)
                req.setValue("https://m.dcinside.com/", forHTTPHeaderField: "Referer")
                guard let (data, _) = try? await URLSession.shared.data(for: req) else { return }
                // 움직이는 디시콘·움짤은 프레임을 모아 움직이게
                guard let img = await Task.detached(operation: { ImageViewer.decode(data) }).value else { return }
                s.setPreview(img, for: id)
            }
        }
    }

    /// 다른 갤러리에서 쓴 글(글 수정으로 불러온 글 포함)을 불러왔을 때, 이미 디시에 올라가 있던 사진은 그 갤러리 기준 주소라
    /// 이 갤러리에 올리면 글에서 안 보임 → 사진을 내려받아 앱이 가진 사진으로 바꿔 등록할 때 이 갤러리에 새로 올림
    func convertRemotePhotos(_ s: NativeWriteSession) {
        let targets = s.blocks.compactMap { b -> (UUID, URL)? in
            guard let img = b.image, img.rawHTML != nil, img.label == "사진", let u = img.remoteURL else { return nil }
            return (img.id, u)
        }
        guard !targets.isEmpty else { return }
        s.convertingPhotos += targets.count
        let size = WriteImageSize.current
        let maxWidth = size.maxWidth
        Task {
            var failed = 0
            for (id, url) in targets {
                var req = URLRequest(url: url)
                req.setValue("https://m.dcinside.com/", forHTTPHeaderField: "Referer")
                if let (data, _) = try? await URLSession.shared.data(for: req),
                   let p = await Task.detached(operation: { AutoImageStore.prepareForUpload(data, maxWidth: maxWidth) }).value {
                    s.replaceImage(id: id, with: WriteImage(data: p.data, mime: p.mime, ext: p.ext,
                                                            preview: UIImage(data: p.data) ?? UIImage(),
                                                            originalData: data, size: size))
                } else {
                    failed += 1
                }
                s.convertingPhotos -= 1
            }
            if failed > 0 { showToast("사진 \(failed)장을 가져오지 못했어요. 다시 불러와 주세요") }
        }
    }

    private static func imageFromDataURL(_ s: String?) -> UIImage? {
        guard let s, let comma = s.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(s[s.index(after: comma)...])).flatMap(UIImage.init(data:))
    }

    /// 15초마다 바뀐 내용을 자동 임시저장 (사진은 빼고 제목·내용만)
    private func runNativeAutosave(_ s: NativeWriteSession) {
        Task {
            // 사진은 id와 용량으로 (크기만 바꿔도 id는 그대로라서, 용량까지 봐야 바뀐 걸 알아 다시 저장함)
            let signature = { @MainActor in s.title + "\u{0}" + s.body + "\u{0}" + s.images.map { "\($0.id.uuidString):\($0.data.count)" }.joined() }
            var last = signature()
            while nativeWrite === s {
                try? await Task.sleep(for: .seconds(15))
                guard nativeWrite === s, !s.submitting else { continue }
                let sig = signature()
                guard sig != last, s.hasText || s.hasUserImages else { continue }
                last = sig
                DraftStore.shared.autosave(galleryID: s.galleryID, title: s.title, body: s.body,
                                           preview: String(s.body.prefix(200)), isHTML: false, writeURL: webView.url,
                                           parts: s.draftParts())
            }
        }
    }

    /// 댓글 입력창의 코드 그림 새로고침
    func refreshCommentCode() {
        guard let s = commentCompose else { return }
        Task {
            await reattachCompose(s)
            let img = await call("return window.__dcapp ? await window.__dcapp.cmtRefreshCode(p) : null;", composeArgs(s)) as? String
            if commentCompose === s {
                if let i = CommentComposeSession.codeImage(from: img) { s.codeImage = i } else { showToast("코드를 새로 받지 못했어요") }
                s.code = ""
            }
        }
    }

    func refreshNativeCaptcha() {
        guard let s = nativeWrite else { return }
        Task {
            let img = await call("return window.__dcapp ? await window.__dcapp.refreshCaptcha() : null;") as? String
            s.captchaImage = Self.imageFromDataURL(img)
            s.captcha = ""
        }
    }

    /// 자짤 하나를 앱 글쓰기 사진 목록에 넣기
    func addAutoImage(to s: NativeWriteSession? = nil, silent: Bool = false) {
        guard let s = s ?? nativeWrite else { return }
        let store = AutoImageStore.shared
        guard let img = store.pick(for: s.galleryID, account: AutoImageScope.currentAccount(isAnon: s.isAnon)),
              let data = try? Data(contentsOf: store.fileURL(img)) else {
            if !silent { showToast("등록된 자짤이 없어요 (설정 → 자짤)") }
            return
        }
        if silent, s.images.contains(where: \.isAuto) { return }
        s.addImages([WriteImage(data: data, mime: img.mime, ext: img.ext,
                                preview: UIImage(data: data) ?? UIImage(), isAuto: true, originalData: data)], atTop: true)
    }

    // MARK: 사진 크기 (앱 글쓰기)

    /// 사진 하나의 업로드 크기를 바꿈 (원본에서 다시 만들어서, 줄였다가 다시 키워도 화질이 안 떨어짐)
    func setImageSize(_ size: WriteImageSize, for imageID: UUID) {
        guard let s = nativeWrite else { return }
        resizeImages(in: s, ids: [imageID], to: size)
    }

    /// 키보드 위 도구열의 일괄 변경: 기본 크기(이후 넣는 사진·등록)를 바꾸고, 이미 넣은 사진도 모두 이 크기로 (따로 정해 둔 사진도 통일)
    func setAllImageSizes(_ size: WriteImageSize) {
        Profile.defaults.set(size.rawValue, forKey: WriteImageSize.key)
        guard let s = nativeWrite else { return }
        let ids = s.blocks.compactMap(\.image).filter(\.isResizable).map(\.id)
        resizeImages(in: s, ids: ids, to: size)
    }

    private func resizeImages(in s: NativeWriteSession, ids: [UUID], to size: WriteImageSize) {
        // 이미 그 크기인 사진은 건너뜀. 지금 사진이 줄인 것이어도 원본이 있으면 원본에서 다시 만듦
        let targets: [(id: UUID, source: Data)] = ids.compactMap { id in
            guard let img = s.image(id), img.isResizable, img.size != size else { return nil }
            return (id, img.originalData ?? img.data)
        }
        guard !targets.isEmpty else { return }
        let ticket = UUID()
        for t in targets { s.resizeTickets[t.id] = ticket }
        s.convertingPhotos += targets.count         // 다 준비되기 전에는 등록하지 않음
        let maxWidth = size.maxWidth
        Task {
            var failed = 0
            for t in targets {
                let source = t.source
                let p = await Task.detached(priority: .userInitiated) { AutoImageStore.prepareForUpload(source, maxWidth: maxWidth) }.value
                s.convertingPhotos -= 1
                // 그 사이 같은 사진을 또 바꿨으면 마지막 요청 결과만 반영
                guard s.resizeTickets[t.id] == ticket else { continue }
                s.resizeTickets[t.id] = nil
                if let p { s.applyPrepared(p, size: size, to: t.id) } else { failed += 1 }
            }
            if failed > 0 { showToast("사진 \(failed)장은 크기를 바꾸지 못했어요") }
        }
    }

    /// 앱 글쓰기 '임시' → 임시저장 목록에 새로 저장
    func saveNativeDraft() {
        guard let s = nativeWrite else { return }
        guard s.hasText || s.hasUserImages else { showToast("저장할 내용이 없어요"); return }
        DraftStore.shared.addManual(galleryID: s.galleryID, title: s.title, body: s.body,
                                    preview: String(s.body.prefix(200)), isHTML: false, writeURL: webView.url,
                                    parts: s.draftParts())
        showToast(s.images.isEmpty ? "임시저장했어요" : "임시저장했어요 (사진 \(s.images.count)장 포함)")
    }

    /// 앱 글쓰기 '등록' → 디시 양식에 채우고 등록
    func submitNative() {
        guard let s = nativeWrite, !s.submitting else { return }
        if !s.loaded { showToast("디시 글쓰기 양식을 불러오는 중이에요. 잠시 뒤에 눌러 주세요"); return }
        if s.convertingPhotos > 0 { showToast("사진을 준비하는 중이에요. 잠시 뒤에 눌러 주세요"); return }
        let title = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count < 2 { showToast("제목을 2자 이상 입력해 주세요"); return }
        if title.count > 40 { showToast("제목은 40자까지 쓸 수 있어요"); return }
        if s.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && s.images.isEmpty {
            showToast("내용을 입력해 주세요"); return
        }
        if s.isAnon {
            if s.nick.trimmingCharacters(in: .whitespaces).isEmpty { showToast("닉네임을 입력해 주세요"); return }
            if s.pw.count < 4 { showToast("비밀번호를 4자리 이상 입력해 주세요"); return }
            AnonStore.update(gallery: s.galleryID, nick: s.nickLocked ? nil : s.nick, password: s.pw)
        }
        if s.hasCaptcha && s.captcha.isEmpty { showToast("코드를 입력해 주세요"); return }
        if !s.heads.isEmpty && s.head.isEmpty { showToast("말머리를 골라 주세요"); return }
        // 쓰던 내용은 혹시 몰라 자동 저장에도
        DraftStore.shared.autosave(galleryID: s.galleryID, title: s.title, body: s.body,
                                   preview: String(s.body.prefix(200)), isHTML: false, writeURL: webView.url,
                                   parts: s.draftParts())
        s.submitting = true
        let token = UUID()
        s.submitToken = token
        // 분할 화면의 글 수정: 등록 뒤 디시가 글 목록을 열면 수정한 글을 오른쪽에 다시 띄움
        if isDetailPane, let u = s.modifyPostURL { pendingModifyReturn = (u, Date()) }
        var bodyBlocks: [[String: Any]] = s.blocks.compactMap { b -> [String: Any]? in
            if let img = b.image {
                if let raw = img.rawHTML { return ["t": "raw", "html": raw] }      // 수정: 원래 있던 칸 그대로
                return ["t": "image", "b64": img.data.base64EncodedString(), "mime": img.mime, "ext": img.ext]
            }
            return b.text.isEmpty ? nil : ["t": "text", "text": b.text, "html": RichText.html(b.rich)]   // 꾸미기 포함
        }
        // 꼬릿말: 계정(유동 포함)·갤러리에 맞는 한 줄을 본문 맨 아래에 (글 수정으로 이미 들어 있으면 또 붙이지 않음)
        let footerAccount: String? = s.isAnon ? FooterRule.anon : CredentialStore.currentAccountID
        if let f = FooterStore.shared.text(account: footerAccount, gallery: s.galleryID) {
            let line = FooterFormat.plain(f)
            let already = s.blocks.contains { ($0.image?.rawHTML?.contains(line) ?? false) || $0.text.contains(line) }
            if !already { bodyBlocks.append(["t": "text", "text": "\n" + line, "html": FooterFormat.html(f)]) }
        }
        let payload: [String: Any] = [
            "title": title,
            "nick": s.isAnon && !s.nickLocked ? s.nick : NSNull(),
            "pw": s.isAnon ? s.pw : NSNull(),
            "captcha": s.hasCaptcha ? s.captcha : NSNull(),
            "head": s.head,
            "imgSize": Self.submitImageSize(for: s).rawValue,
            // 본문 순서 그대로: 글자 칸 / 사진 칸 (+ 꼬릿말)
            "blocks": bodyBlocks,
        ]
        Task {
            let r = await call("return window.__dcapp ? await window.__dcapp.nativeSubmit(p) : 'noscript';", ["p": payload]) as? String ?? "error"
            // 재시도로 이미 새 등록으로 넘어갔으면(또는 페이지가 바뀌며 이 호출이 오류로 끝났으면) 이 결과는 버림
            guard nativeWrite === s, s.submitToken == token else { return }
            switch r {
            case "submitted":
                // 디시가 등록하고 글 화면으로 넘어가면 닫힘. 안 넘어가면(오류) 잠시 뒤 다시 쓸 수 있게
                try? await Task.sleep(for: .seconds(15))
                if nativeWrite === s, s.submitting, s.submitToken == token { s.submitting = false }
            case "needcheck":
                s.submitting = false
                s.webFeature = nil
                s.showingWeb = true
                showToast("Cloudflare 체크박스를 눌러 주세요 (체크하면 이어서 등록돼요)")
            case "imgtimeout":
                s.submitting = false
                showToast("사진을 올리는 데 실패했어요. 다시 등록해 주세요")
            case _ where r.hasPrefix("imgmissing"):
                // 사진이 본문에 다 들어가지 않은 채로는 등록하지 않음 (사진이 빠진 글이 올라가는 것 방지)
                s.submitting = false
                let n = r.dropFirst("imgmissing:".count)
                showToast("사진이 다 올라가지 않아 등록하지 않았어요 (\(n)). 다시 등록해 주세요")
            default:
                s.submitting = false
                showToast("등록하지 못했어요 (\(r))")
            }
        }
    }

    /// 등록할 때 디시 imgSize 칸에 넣을 크기: 사진마다 크기가 다를 수 있으니 그중 가장 큰 것
    /// (작게 줄인 사진은 앱이 이미 줄였으니 더 줄어들 일이 없고, 큰 사진이 디시 쪽 설정에 다시 줄어드는 일도 없음)
    private static func submitImageSize(for s: NativeWriteSession) -> WriteImageSize {
        let sizes = s.blocks.compactMap(\.image).filter { $0.rawHTML == nil }.map { $0.size ?? WriteImageSize.current }
        return sizes.max(by: { $0.rank < $1.rank }) ?? WriteImageSize.current
    }

    /// 동영상·디시콘·유튜브·투표: 디시 화면에서 그 기능을 열어 넣게 하고, 다 넣으면 앱 화면으로 가져옴
    func openWebFeature(_ kind: String, name: String) {
        guard let s = nativeWrite else { return }
        Task {
            let r = await call("return window.__dcapp ? window.__dcapp.openWebFeature(k) : 'none';", ["k": kind]) as? String
            guard nativeWrite === s else { return }
            if r == "opened" {
                s.webFeature = name
                s.showingWeb = true
            } else {
                showToast("이 갤러리에서는 \(name)을(를) 쓸 수 없어요")
            }
        }
    }

    /// 디시 화면에서 넣은 것(디시콘·동영상 등)을 앱 글쓰기 끝에 붙이고 앱 화면으로
    func finishWebFeature() {
        guard let s = nativeWrite else { return }
        Task {
            let added = Self.writeBlocks(from: await call("return window.__dcapp ? window.__dcapp.collectWebInserts() : [];"))
            let name = s.webFeature ?? "첨부"
            s.webFeature = nil
            s.showingWeb = false
            guard !added.isEmpty else { return }
            appendBlocks(added, to: s)
            showToast("\(name)을(를) 넣었어요")
        }
    }

    // MARK: 디시콘 바로 넣기

    /// 디시콘 목록 첫 화면: 탭(보유·최근 디시콘 묶음)과 지금 탭의 디시콘
    func dcconTabs() async -> (tabs: [DcconTab], current: String, items: [DcconItem])? {
        guard let r = await call("return window.__dcapp ? await window.__dcapp.dcconTabs() : null;") as? [String: Any] else { return nil }
        let tabs = (r["tabs"] as? [[String: Any]] ?? []).map { t in
            DcconTab(idx: t["idx"] as? String ?? "", folder: t["folder"] as? String ?? "",
                     name: t["name"] as? String ?? "", thumb: (t["thumb"] as? String).flatMap(URL.init(string:)))
        }
        return (tabs, r["current"] as? String ?? "", Self.dcconItems(r["items"]))
    }

    func dcconItems(_ tab: DcconTab) async -> [DcconItem] {
        Self.dcconItems(await call("return window.__dcapp ? await window.__dcapp.dcconItems(i, f) : [];",
                                   ["i": tab.idx, "f": tab.folder]))
    }

    private static func dcconItems(_ any: Any?) -> [DcconItem] {
        (any as? [[String: Any]] ?? []).map { d in
            DcconItem(pkg: d["pkg"] as? String ?? "", detail: d["detail"] as? String ?? "",
                      alt: d["alt"] as? String ?? "", src: (d["src"] as? String).flatMap(URL.init(string:)))
        }
    }

    /// 고른 디시콘을 디시 방식 그대로 칸으로 만들어 글 끝에 붙임
    func insertDccon(_ item: DcconItem, preview: UIImage?) async -> Bool {
        guard let s = nativeWrite else { return false }
        let r = await call("return window.__dcapp ? window.__dcapp.dcconMake(p, d) : {error:'noscript'};",
                           ["p": item.pkg, "d": item.detail]) as? [String: Any] ?? [:]
        if let err = r["error"] as? String {
            showToast(err == "denied" ? "이 디시콘은 쓸 수 없어요" : "디시콘을 넣지 못했어요")
            return false
        }
        var blocks = Self.writeBlocks(from: r["blocks"])
        guard !blocks.isEmpty else { showToast("디시콘을 넣지 못했어요"); return false }
        if let preview, blocks.count == 1 { blocks[0].image?.preview = preview }
        appendBlocks(blocks, to: s)
        return true
    }

    /// 페이지에서 받은 칸 목록 → 앱 글쓰기 칸
    private static func writeBlocks(from any: Any?) -> [WriteBlock] {
        (any as? [[String: Any]] ?? []).compactMap { p in
            if p["t"] as? String == "raw" {
                return WriteBlock(image: WriteImage(data: Data(), mime: "", ext: "", preview: nil,
                                                    rawHTML: p["html"] as? String ?? "",
                                                    remoteURL: (p["src"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
                                                    label: p["label"] as? String))
            }
            if let t = p["text"] as? String { return WriteBlock(text: t) }
            return nil
        }
    }

    /// 글 끝(마지막 빈 글자 칸 앞)에 칸 붙이기 → 길게 눌러 끌어서 옮길 수 있음
    private func appendBlocks(_ added: [WriteBlock], to s: NativeWriteSession) {
        guard !added.isEmpty else { return }
        if let last = s.blocks.last, last.image == nil, last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s.blocks.insert(contentsOf: added, at: s.blocks.count - 1)
        } else {
            s.blocks.append(contentsOf: added)
        }
        s.normalize()
        loadRemotePreviews(s)
    }

    /// 디시 원래 글쓰기 화면으로 (지금까지 쓴 제목·내용은 옮김)
    func switchToWebWrite() {
        guard let s = nativeWrite else { return }
        nativeSkipURL = webView.url
        let draft = Draft(id: UUID(), galleryID: s.galleryID, title: s.title, body: s.body, preview: "",
                          isHTML: false, isAuto: true, updatedAt: Date(), writeURL: webView.url)
        let hadImages = !s.images.isEmpty
        nativeWrite = nil
        if s.hasText { restoreDraft(draft, message: hadImages ? "제목·내용을 옮겼어요 (사진은 다시 첨부해 주세요)" : "디시 화면으로 옮겼어요") }
    }

    /// 앱 글쓰기 ← : 쓰던 게 있으면 자동 저장하고 뒤로
    // MARK: - 갤러리 차단 (매니저에게 차단당한 경우): 디시가 준 문구를 보여 주고 이전 화면으로

    /// 디시가 글·댓글을 막으며 띄우는 안내 문구인지 (사용자가 직접 한 차단·해제 안내는 제외)
    nonisolated static func looksLikeBan(_ message: String) -> Bool {
        guard message.contains("차단") || message.contains("이용 제한") || message.contains("이용제한") else { return false }
        let own = ["차단 등록", "차단 해제", "차단이 해제", "숨김 적용", "차단 및 삭제", "일일 차단", "차단 기간", "차단 사유", "차단할", "고정닉", "이미지 차단", "차단하시"]
        return !own.contains { message.contains($0) }
    }

    /// 차단 안내: 디시가 준 문구만 그대로 보여 줌 (문구를 못 받았으면 짧게 알림)
    private func showBanAlert(message: String) {
        guard let vc = presenter(), !(vc is UIAlertController) else { return }
        let text = message.isEmpty ? "차단된 갤러리예요" : message
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        vc.present(alert, animated: true)
    }

    /// 새 글을 등록하고 글 목록으로 돌아왔을 때, 목록에서 방금 쓴 글(제목이 같은 글)을 찾아 오른쪽 화면에서 엶 (목록에 늦게 뜨면 몇 번 다시 찾음)
    private func openWrittenPostFromList(title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Task {
            for attempt in 0..<4 {
                try? await Task.sleep(for: .milliseconds(attempt == 0 ? 700 : 1300))
                // 그 사이 다른 곳으로 옮겼거나 글이 이미 열렸으면 그만둠
                guard let u = webView.url, Gallery.parse(u) != nil, PostKey.from(u) == nil else { return }
                if let href = await call("return window.__dcapp ? window.__dcapp.findPostByTitle(t) : null;", ["t": t]) as? String,
                   let url = URL(string: href), openWrittenPost?(url) == true { return }
                if attempt == 2 { reload() }      // 목록에 아직 없으면 새로고침해서 다시 찾음
            }
        }
    }

    /// 글 수정 주소(/write/갤ID/modify/글번호) → 그 글 주소
    nonisolated static func postURL(fromModifyURL url: URL) -> URL? {
        let p = url.pathComponents.filter { $0 != "/" }
        guard p.count >= 4, p[2] == "modify", let no = Int(p[3]) else { return nil }
        let prefix = p[0] == "writemini" ? "mi$" : (p[0] == "writepr" ? "pr$" : "")
        return DCGalleryID.postURL(prefix + p[1], no: no, comments: false)
    }

    /// 등록이 오래 걸릴 때 강제로 나가기: 진행 중인 로딩을 멈추고 글쓰기 화면을 닫고 이전 화면으로 (내용은 등록 직전에 자동 저장돼 있음)
    /// 등록이 오래 걸릴 때 '재시도': 글쓰기 페이지를 새로 불러온 뒤 같은 내용으로 다시 등록
    /// (새로고침이 아니라 주소를 다시 여는 것이라 등록 요청이 한 번 더 전송되지는 않음. 코드 입력이 있으면 새 코드를 받아 두고 직접 입력하게 함)
    func retrySubmitNative() {
        guard let s = nativeWrite, s.submitting else { return }
        guard let u = webView.url, AutoImageStore.writeGalleryID(from: u) != nil else {
            showToast("글쓰기 페이지를 다시 불러올 수 없어요. 글쓰기 취소 후 임시저장에서 이어 쓰세요")
            return
        }
        DraftStore.shared.autosave(galleryID: s.galleryID, title: s.title, body: s.body,
                                   preview: String(s.body.prefix(200)), isHTML: false, writeURL: u,
                                   parts: s.draftParts())
        retrySession = s
        s.loaded = false
        s.submitToken = UUID()      // 진행 중이던 등록 호출이 페이지가 바뀌며 '오류'로 끝나도 결과를 무시하게
        showToast("글쓰기 페이지를 다시 불러와요…")
        webView.stopLoading()
        webView.load(URLRequest(url: u))
        // 40초 안에 다시 열리지 않으면 '등록 중'을 풀어 직접 다시 등록할 수 있게
        Task {
            try? await Task.sleep(for: .seconds(40))
            if retrySession === s {
                retrySession = nil
                if nativeWrite === s, s.submitting {
                    s.submitting = false
                    s.loaded = true
                    showToast("페이지를 다시 불러오지 못했어요. 등록을 다시 눌러 주세요")
                }
            }
        }
    }

    /// 재시도로 글쓰기 페이지가 다시 열렸을 때: 양식을 읽고 → (코드 입력이 없으면) 바로 다시 등록
    private func continueRetry(_ s: NativeWriteSession) {
        Task {
            // 페이지 스크립트·글쓰기 양식이 준비될 때까지 기다림 (준비 전에 읽으면 앱 글쓰기 화면이 닫힐 수 있음)
            var ready = false
            for _ in 0..<40 {
                ready = (await call("return !!(window.__dcapp && document.getElementById('subject'));") as? Bool) == true
                if ready { break }
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard nativeWrite === s else { return }
            let info: [String: Any]? = ready ? await readWriteInfo(s) : nil
            guard nativeWrite === s else { return }
            s.loaded = true
            s.submitting = false
            if s.hasCaptcha {
                s.captcha = ""
                showToast("새 코드를 입력하고 등록을 눌러 주세요")
            } else if info != nil {
                submitNative()
            } else {
                showToast("글쓰기 페이지를 읽지 못했어요. 다시 등록을 눌러 주세요")
            }
        }
    }

    func forceCloseNativeWrite(quiet: Bool = false) {
        guard let s = nativeWrite else { return }
        webView.stopLoading()
        DraftStore.shared.autosave(galleryID: s.galleryID, title: s.title, body: s.body,
                                   preview: String(s.body.prefix(200)), isHTML: false, writeURL: webView.url,
                                   parts: s.draftParts())
        s.submitting = false
        nativeWrite = nil
        if !quiet { showToast("글쓰기를 취소했어요. 쓰던 내용은 임시저장에 있어요") }
        swipeBack()
    }

    func closeNativeWrite() {
        guard let s = nativeWrite else { return }
        if s.hasText || s.hasUserImages {
            DraftStore.shared.autosave(galleryID: s.galleryID, title: s.title, body: s.body,
                                       preview: String(s.body.prefix(200)), isHTML: false, writeURL: webView.url,
                                       parts: s.draftParts())
            showToast("쓰던 글을 자동 임시저장했어요")
        }
        nativeWrite = nil
        swipeBack()
    }

    // MARK: - 읽은 글 / 작성한 글 기록

    private func recordHistory() {
        guard let url = webView.url else { return }
        if let key = PostKey.from(url) {
            ReadPostStore.shared.markRead(key, title: Gallery.cleanTitle(title))
            NotificationCenter.default.post(name: Self.postReadNotification, object: self)
            let pending = pendingWritten
            Task {
                let info = await call("return window.__dcapp ? window.__dcapp.articleIdentity() : null;") as? [String: Any]
                let realTitle = info?["title"] as? String ?? ""
                if !realTitle.isEmpty { ReadPostStore.shared.setTitle(realTitle, for: key) }
                // 글쓰기 등록 직후 2분 안에 같은 갤러리 글이 열리면 = 방금 쓴 글
                guard let p = pending, Date().timeIntervalSince(p.at) < 120,
                      DCGalleryID.bare(PostKey.gallery(key)) == DCGalleryID.bare(p.gallery) else { return }
                pendingWritten = nil
                let account = CredentialStore.currentAccountID
                let who = WriterIdentity(account: account,
                                         nick: account == nil ? ((info?["nick"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? p.nick) : nil,
                                         ip: account == nil ? (info?["ip"] as? String) : nil)
                WrittenStore.shared.add(WrittenItem(kind: .post, key: key, title: realTitle.isEmpty ? p.title : realTitle,
                                                    snippet: "", date: Date(), who: who))
            }
        } else if Gallery.parse(url) != nil, isGalleryListPage {
            refreshReadMarks()
        }
    }

    /// 글 목록에서 읽은 글을 보라색으로 (분할 화면에서 오른쪽 글을 읽으면 왼쪽 목록도 바로 갱신)
    func refreshReadMarks() {
        guard let url = webView.url, let g = Gallery.parse(url), isGalleryListPage else { return }
        let prefix = g.kind == .mini ? "mi$" : (g.kind == .person ? "pr$" : "")
        let keys = ReadPostStore.shared.readKeys(gallery: prefix + g.id)
        Task {
            await call("if (window.__dcapp) window.__dcapp.setReadPosts(k); return true;", ["k": Array(keys)])
            applyListFilter()
        }
    }

    /// 게시물 필터를 지금 글 목록에 적용 (상단바 깔때기)
    func applyListFilter() {
        let f = ListFilterStore.shared.filter
        let arg: Any = f.isActive ? f.script : NSNull()
        Task { await call("if (window.__dcapp) window.__dcapp.setListFilter(f); return true;", ["f": arg]) }
    }

    // MARK: - 글쓰기 등록

    /// 상단바 '등록' → 디시 글쓰기 화면의 등록 버튼을 대신 누름
    func submitWrite() {
        Task {
            let r = await call("return window.__dcapp ? window.__dcapp.submitWrite() : 'none';") as? String
            if r != "clicked" { showToast("등록 버튼을 못 찾았어요 (페이지 구조 진단을 보내주세요)") }
        }
    }

    // MARK: - 글쓰기 제목 ⇄ 내용 이동

    /// 키보드 위 < > : 제목 칸 ⇄ 내용 칸으로 커서 옮기기
    func moveWriteFocus(forward: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        FocusUnlock.allow(for: 1.0)          // 앱 버튼으로 옮기는 거라 스크립트 focus로도 키보드 유지
        Task { await call("return window.__dcapp ? window.__dcapp.moveWriteFocus(f) : 'none';", ["f": forward]) }
    }

    // MARK: - 키보드 내리기

    /// 웹페이지 입력칸의 포커스를 풀어 키보드를 내림
    func dismissKeyboard() {
        webView.evaluateJavaScript("document.activeElement && document.activeElement.blur && document.activeElement.blur(); true", completionHandler: nil)
        webView.endEditing(true)
    }

    // MARK: - 갤러리 관리 내역

    func openManageLog() {
        Task {
            let r = await call("return window.__dcapp ? window.__dcapp.openManageLog() : 'none';") as? String
            if r == "none" || r == nil {
                // 글 보기 등 '갤러리 정보' 창이 없는 화면: 관리 내역 주소로 바로 이동 (디시가 모든 갤러리에 같은 주소를 씀)
                if let url = webView.url, let g = Gallery.parse(url), g.kind == .board,
                   let target = URL(string: "https://m.dcinside.com/managehistory/minor/\(g.id)") {
                    load(target)
                } else {
                    showToast("관리 내역을 열 수 없는 화면이에요 (갤러리 목록 화면에서 눌러 주세요)")
                }
            }
        }
    }

    // MARK: - 갤러리 공지

    func openNotice() {
        Task {
            let r = await call("return window.__dcapp ? window.__dcapp.openNotice() : 'none';") as? String
            if r == "none" || r == nil {
                showToast("공지를 열 수 없는 화면이에요 (갤러리 목록 화면에서 눌러 주세요)")
            }
        }
    }

    // MARK: - 말머리

    /// 지금 갤러리 페이지의 말머리 탭 (이름, 주소)
    func headTabs() async -> [HeadTab] {
        guard let list = await call("return window.__dcapp ? window.__dcapp.headTabs() : [];") as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let name = d["name"] as? String, let s = d["url"] as? String, let u = URL(string: s) else { return nil }
            return HeadTab(name: name, url: u)
        }
    }

    // MARK: - 토스트 알림

    func showToast(_ text: String, seconds given: Double? = nil) {
        toastTask?.cancel()
        toast = text
        // 제목과 이유·재시도 권유가 함께 나오는 여러 줄 알림은 읽을 시간을 더 줌 (필요하면 호출하는 쪽에서 지정)
        let seconds: Double = given ?? (text.contains("\n") ? 4.5 : 1.8)
        toastTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { toast = nil }
        }
    }

    /// 보안 확인(Cloudflare)이 늦거나 실패했을 때 댓글 입력창에 띄우는 알림: 첫 줄은 상태, 다음 줄은 이유와 재시도 권유
    static func tsWaitToast(_ result: String?) -> String {
        let title = result == "tserror" ? "보안 확인에 실패했어요" : "보안 확인이 아직 진행 중이에요"
        return title + "\n데이터 속도가 느려 보안 확인(Cloudflare) 처리가 지연되고 있어요. 잠시 기다린 뒤 다시 등록을 눌러 주세요."
    }

    /// 데이터가 느려 보안 확인이 늦어질 때 디시가 띄우는 안내에 이유와 재시도 권유를 덧붙임 (해당하지 않으면 nil)
    nonisolated static func slowNetworkNote(for message: String) -> String? {
        let tsWait = message.contains("보안 확인") && (message.contains("진행") || message.contains("확인 중"))
        guard tsWait || message.contains("등록되지 않았") else { return nil }
        return "데이터 속도가 느려 보안 확인 처리가 지연되고 있을 수 있어요. 잠시 기다린 뒤 다시 등록을 눌러 주세요."
    }

    func pickParent() {
        Task { await call("if (window.__dcapp) window.__dcapp.pickParent(); return true;") }
    }

    func clearPick() {
        Task { await call("if (window.__dcapp) window.__dcapp.clearPick(); return true;") }
    }

    // MARK: - 알림: 차단한 사람이 보낸 것 거르기

    /// 디시 알림에는 작성자가 없어서, 새 알림마다 그 글을 한 번 불러와 해당 댓글 작성자를 확인
    private func addAlarmsSkippingBlocked(_ raw: [[String: Any]]) {
        let cands = AlarmStore.shared.candidates(raw)
        guard !cands.isEmpty else { return }
        Task {
            var keep: [AlarmItem] = [], skip: [AlarmItem] = []
            for item in cands {
                guard let cno = item.commentNo, !FilterStore.shared.settings.users.isEmpty else { keep.append(item); continue }
                let a = await call("return window.__dcapp ? await window.__dcapp.alarmAuthor(g, n, c) : null;",
                                   ["g": item.galleryID, "n": item.postNo, "c": cno]) as? [String: Any]
                let nick = a?["nick"] as? String ?? "", ip = a?["ip"] as? String ?? "", id = a?["id"] as? String ?? ""
                if a != nil, FilterStore.shared.isBlocked(nick: nick, ip: ip, id: id, gallery: DCGalleryID.bare(item.galleryID)) {
                    skip.append(item)
                } else {
                    keep.append(item)      // 못 찾으면(댓글이 다른 페이지 등) 그냥 보여줌
                }
            }
            AlarmStore.shared.finishCheck(keep: keep, skip: skip)
        }
    }

    // MARK: - 진단

    func diagnose() async -> String {
        let page = (await call("return window.__dcapp ? window.__dcapp.diagnose() : '스크립트가 로드되지 않았어요: ' + location.href;") as? String)
            ?? "진단 정보를 가져오지 못했어요."
        return StatusBarStyler.diagnostics() + "\n" + barHideDiagnostics() + "\n" + page
    }

    /// 컨트롤바 숨김 판정에 쓰는 값 (실기기에서 숨김이 안 먹힐 때 이 줄들로 원인을 좁힘)
    /// samples: user=손가락·관성 / flap=깃발만 꺼진(직전 0.3초 안에 손가락 있었음) / idle=손가락과 무관 / windowSkip=상단바 변화 직후 0.5초 건너뜀 / widthChg=화면 폭 변화
    /// toggles: hide·show 횟수와 마지막 전환 (hide가 0이면 판정이 안 걸린 것, 0이 아닌데 안 숨으면 화면 쪽 문제)
    private func barHideDiagnostics() -> String {
        let sv = webView.scrollView
        let style = Profile.defaults.string(forKey: ControlBarItem.autoHideStyleKey) ?? ControlBarItem.autoHideStyleScrolling
        let autoHide = Profile.defaults.object(forKey: ControlBarItem.autoHideKey) as? Bool ?? true
        let st = barStats
        let ago = st.lastToggleAt == .distantPast ? "-" : String(format: "%.0fs", Date().timeIntervalSince(st.lastToggleAt))
        return [
            "--- 컨트롤바 숨김 ---",
            "autoHideBar=\(autoHide) autoHideStyle=\(style)",
            "barHiddenByDirection=\(barHiddenByDirection) commentsInView=\(commentsInView) isScrolling=\(isScrolling) navHiddenByScroll=\(navHiddenByScroll)",
            "off=\(Int(sv.contentOffset.y)) insetTop=\(Int(sv.adjustedContentInset.top)) bounds=\(Int(sv.bounds.width))x\(Int(sv.bounds.height)) barRefY=\(Int(barRefY))",
            "samples: user=\(st.user) flap=\(st.flap) idle=\(st.idle) windowSkip=\(st.windowSkip) widthChg=\(st.widthChanges)",
            "toggles: hide=\(st.hide) show=\(st.show) cmtShow=\(st.cmtShow) last=\(st.lastToggle) \(ago) ago | navReset=\(st.navResets) | navToggleAgo=\(String(format: "%.0f", Date().timeIntervalSince(navToggleAt)))s",
            "view: tucked=\(viewTucked) tuckCount=\(viewTuckCount) changedAgo=\(viewTuckChangedAt == .distantPast ? "-" : String(format: "%.0fs", Date().timeIntervalSince(viewTuckChangedAt)))",
            "tracking=\(sv.isTracking) dragging=\(sv.isDragging) decelerating=\(sv.isDecelerating)",
        ].joined(separator: "\n")
    }

    // MARK: - 캡처

    func captureVisible() async {
        await call("if (window.__dcapp) window.__dcapp.clearPick(); return true;")
        guard let image = try? await webView.takeSnapshot(configuration: nil) else { return }
        captured = PageCapture.makeCaptured(image)
    }

    func captureFullPage() async {
        isCapturing = true
        defer { isCapturing = false }
        await call("return window.__dcapp ? window.__dcapp.prepareCapture() : 0;")
        try? await Task.sleep(for: .milliseconds(1000))   // 지연 로딩 이미지 기다리기
        guard let data = try? await webView.pdf(configuration: WKPDFConfiguration()),
              let image = PageCapture.image(fromPDF: data) else { return }
        captured = PageCapture.makeCaptured(image)
    }

    // MARK: - 로그인 자동 입력 / 저장

    private func autofillLogin() {
        if manualLogin { return }
        let switching = pendingLogin != nil
        guard let cred = pendingLogin ?? CredentialStore.load() else { return }
        let auto = switching || Profile.defaults.bool(forKey: "autoLogin")
        Task {
            await call("return window.__dcapp ? window.__dcapp.fillLogin(id, pw, auto, 0, force) : 'none';",
                       ["id": cred.id, "pw": cred.password, "auto": auto, "force": switching])
        }
    }

    private func offerToSaveCredential() {
        // 로그인에 성공한 계정을 "현재 계정"으로 표시
        let loggedIn = pendingCredential ?? pendingLogin
        pendingLogin = nil
        if let loggedIn { CredentialStore.currentAccountID = loggedIn.id }

        guard let cred = pendingCredential else { return }
        pendingCredential = nil
        if CredentialStore.contains(cred) { return }     // 이미 저장된 계정
        let isUpdate = CredentialStore.all().contains { $0.id == cred.id }

        let alert = UIAlertController(
            title: isUpdate ? "비밀번호 갱신" : "계정 저장",
            message: isUpdate
                ? "'\(cred.id)' 계정의 저장된 비밀번호를 새 비밀번호로 바꿀까요?"
                : "'\(cred.id)' 계정을 이 기기 키체인에 암호화해서 저장할까요?\n설정 → 계정에서 눌러서 바로 전환할 수 있어요.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "나중에", style: .cancel))
        alert.addAction(UIAlertAction(title: "저장", style: .default) { _ in
            CredentialStore.save(cred)
        })
        presenter()?.present(alert, animated: true)
    }
}

// MARK: - 페이지에서 오는 메시지

extension WebViewModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
        case "cmttext":   // 댓글 글자를 길게 누름 → 댓글 내용만 따로 띄움
            let t = (body["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            var item = CommentTextItem(nick: body["nick"] as? String ?? "", text: t)
            item.point = CGPoint(x: (body["x"] as? NSNumber)?.doubleValue ?? 0, y: (body["y"] as? NSNumber)?.doubleValue ?? 0)
            commentTextPrompt = item
            // 잠깐 뒤 저절로 사라짐 (그 사이 다른 댓글을 누르면 새 것으로 바뀜)
            let id = item.id
            Task {
                try? await Task.sleep(for: .seconds(4))
                if commentTextPrompt?.id == id { commentTextPrompt = nil }
            }
        case "longpress":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if isMemoPickMode {
                setMemoPickMode(false)                       // 한 번 고르면 모드 종료
                memoRequest = BlockRequest(body)
                return
            }
            if isBlockPickMode { setBlockPickMode(false) }   // 한 번 고르면 모드 종료
            var req = BlockRequest(body)
            req.pageURL = webView.url
            blockRequest = req
        case "draft":
            if let gid = currentWriteGalleryID {
                DraftStore.shared.autosave(galleryID: gid,
                                           title: body["title"] as? String ?? "",
                                           body: body["body"] as? String ?? "",
                                           preview: body["text"] as? String ?? "",
                                           isHTML: body["html"] as? Bool ?? false,
                                           writeURL: webView.url)
            }
        case "images":
            let urls = (body["urls"] as? [String] ?? []).compactMap(URL.init(string:))
            if !urls.isEmpty {
                imageViewer = ImageViewerItem(urls: urls, index: (body["index"] as? NSNumber)?.intValue ?? 0, pageURL: webView.url,
                                              keys: body["keys"] as? [String],
                                              slots: (body["slots"] as? [NSNumber])?.map(\.intValue),
                                              allCount: (body["allCount"] as? NSNumber)?.intValue ?? 0,
                                              allFilenos: (body["allFilenos"] as? [NSNumber])?.map(\.intValue))
            }
        case "checkimg":   // 차단한 사진과 키는 안 맞지만 사진이 있음 → 사진 생김새를 받아 같은 사진이면 페이지에서 가림
            let key = body["key"] as? String ?? "", urlString = body["url"] as? String ?? ""
            guard !key.isEmpty, !urlString.isEmpty else { break }
            Task {
                guard let h = await ImageBlockHash.fetch(urlString) else { return }
                FilterStore.shared.recordImageHash(key: key, hash: h)      // 차단 상태 판별·해제에 쓰려고 키↔해시를 기억
                guard FilterStore.shared.imageHashBlocked(h) else { return }
                await call("if (window.__dcapp) window.__dcapp.markBlockedImageKey(k); return true;", ["k": key])
            }
        case "gotolist":   // 분할 화면 오른쪽 글 화면의 '글목록' 버튼
            if let u = webView.url, let g = Gallery.parse(u) {
                showListInMain?(Gallery(galleryID: g.id, name: g.id, kind: g.kind).url)
            }
        case "automemo":   // 자동메모: 글 목록에서 메모 없는 로그인 계정을 아이디로 메모
            MemoStore.shared.addAuto(body["items"] as? [[String: Any]] ?? [])
        case "anon":   // 유동 닉네임/비밀번호를 입력하면 기억 (다음에 빈 칸이면 채움)
            let v = body["value"] as? String ?? ""
            // 직접 입력한 값은 지금 갤러리의 설정에 저장 (공통 설정은 설정 화면에서만 바뀜)
            if let g = currentGalleryID {
                if body["kind"] as? String == "pw" {
                    AnonStore.setGallery(g, nick: AnonStore.galleryNick(g), password: v)
                } else {
                    AnonStore.setGallery(g, nick: v, password: AnonStore.galleryPassword(g))
                }
            } else if body["kind"] as? String == "pw" { AnonStore.password = v } else { AnonStore.nick = v }
            // 페이지 스크립트에 넣어 둔 설정은 설치할 때 값이라, 다시 설치해야 다음 페이지(로그아웃 후 등)에서 새 값으로 채움
            installUserScript()
        case "adpause":   // 댓글 칸을 누름 → 등록할 때까지 광고 차단 끄기
            pauseAdBlock()
        case "nativewrite":   // Cloudflare 체크가 끝나 디시 화면에서 이어서 등록함 → 앱 화면으로 돌아옴
            if body["state"] as? String == "resumed" {
                nativeWrite?.showingWeb = false
                nativeWrite?.submitting = true
            }
        case "websubmit":   // 글쓰기 등록을 누름 (앱 글쓰기·디시 원래 화면 모두)
            if let gid = currentWriteGalleryID {
                pendingWritten = (gid, body["title"] as? String ?? "", body["nick"] as? String ?? "", Date())
            }
        case "cmtwritten":   // 댓글 등록 성공 → 작성한 댓글 기록
            if let url = webView.url, let key = PostKey.from(url) {
                let account = CredentialStore.currentAccountID
                let who = WriterIdentity(account: account,
                                         nick: account == nil ? (body["nick"] as? String) : nil,
                                         ip: account == nil ? (body["ip"] as? String) : nil)
                let title = (body["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Gallery.cleanTitle(self.title)
                WrittenStore.shared.add(WrittenItem(kind: .comment, key: key, title: title,
                                                    snippet: body["memo"] as? String ?? "", date: Date(), who: who))
            }
        case "cmtmissing":   // 댓글은 등록됐는데 목록에 안 보임 → 글을 다시 불러와 댓글 위치로 (나갔다 들어온 것과 같게)
            scrollToCommentsAfterLoad = true
            reload()
        case "cmtview":   // 댓글 영역이 화면에 닿음/벗어남 → 컨트롤바 '내리면 숨기기'에서 댓글에 새로 닿으면 한 번 다시 꺼내 줌
            let on = (body["on"] as? Bool) ?? false
            if commentsInView != on {
                commentsInView = on
                if on, barHiddenByDirection {
                    // 닿은 순간 한 번만 꺼냄 (그 뒤 아래로 더 내리면 다시 숨음). 같은 스크롤의 관성으로 바로 다시 숨어 깜빡이지 않게 잠깐 유지
                    setBarHidden(false, at: webView.scrollView.contentOffset.y)
                    barHoldUntil = Date().addingTimeInterval(1.0)
                    barStats.cmtShow += 1
                }
            }
        case "tdock":
            let h = CGFloat((body["h"] as? NSNumber)?.doubleValue ?? 0)
            if writeToolbarHeight != h { writeToolbarHeight = h }
        case "cmtdone":   // 댓글 등록 요청 끝 → 광고 차단 다시 켜기 (429면 자동으로 다시 누르는 중이라 그대로)
            let st = (body["status"] as? NSNumber)?.intValue ?? -1
            if st != 429 {
                resumeAdBlock(after: 1)
                // 0 = 연결이 끊기거나 제한 시간(20초)을 넘김 → 알리고, 입력창은 다시 쓸 수 있게 풀어 둠
                if st == 0, commentCompose?.sending == true {
                    showToast("연결이 느려 댓글을 등록하지 못했어요\n데이터 속도가 느리거나 연결이 불안정해요. 잠시 뒤 다시 등록을 눌러 주세요.")
                }
                commentCompose?.sending = false      // 성공이면 이미 닫혔고, 실패면 입력창을 다시 쓸 수 있게
            }
        case "cmtretry":   // 429 뒤 자동 재등록 상태 — 댓글이 달리거나 멈출 때까지 '댓글을 다는 중' 말풍선을 띄움
            switch body["state"] as? String {
            case "start": isRetryingComment = true
            case "check":      // Cloudflare 체크가 필요: 말풍선은 내리고 안내 (체크가 끝나면 페이지가 start를 다시 보냄)
                isRetryingComment = false
                showToast("Cloudflare 체크박스를 눌러주세요 (누르면 이어서 등록해요)", seconds: 8)
                if let k = commentCompose?.draftKey { CommentDraftStore.remove(k) }
                commentCarry = nil
                if commentCompose != nil { withAnimation(.easeOut(duration: 0.2)) { commentCompose = nil } }
            case "done":
                isRetryingComment = false
                showToast("댓글이 등록됐어요 (\((body["tries"] as? NSNumber)?.intValue ?? 0)번 다시 눌렀어요)")
            case "stop": isRetryingComment = false
            default: break
            }
        case "cmtcompose":   // 댓글·대댓글 칸을 누름 → 앱 댓글 입력창
            if let s = commentCompose, s.sameTarget(body) { break }
            let ns = CommentComposeSession(info: body, gallery: currentGalleryID)
            ns.draftKey = CommentDraftStore.draftKey(url: webView.url, isReply: ns.isReply, replyNick: ns.replyNick)
            ns.pageKey = CommentDraftStore.pageKey(webView.url)
            if let old = commentCompose, !old.sending {
                // 쓰던 댓글(대댓글)에서 다른 댓글을 눌러 입력창이 바뀌면 쓰던 내용을 새 입력창으로 옮김
                if ns.text.isEmpty { ns.text = old.text }
                if ns.code.isEmpty { ns.code = old.code }
                CommentDraftStore.remove(old.draftKey)
            } else if ns.text.isEmpty, let c = commentCarry, c.page == ns.pageKey, Date().timeIntervalSince(c.at) < 600 {
                // 쓰다 닫고 다른 댓글을 눌러 연 새 입력창 → 쓰던 내용을 옮김
                ns.text = c.text
                if ns.code.isEmpty { ns.code = c.code }
                commentCarry = nil
            } else if ns.text.isEmpty, let d = CommentDraftStore.text(for: ns.draftKey) {
                // 입력창이 닫히기 전에 쓰던 글이 있으면 이어서
                ns.text = d
            }
            commentCarry = nil
            withAnimation(.easeOut(duration: 0.2)) { commentCompose = ns }
        case "banned":   // 디시가 등록을 막는 안내 창(차단된 IP·매니저 차단)을 띄움 → 웹 안내는 숨기고, 같은 문구를 앱이 띄우고 이전 화면으로
            let msg = body["msg"] as? String ?? ""
            commentCompose = nil
            if nativeWrite != nil {
                forceCloseNativeWrite(quiet: true)
            } else if webView.url.flatMap(AutoImageStore.writeGalleryID) != nil {
                swipeBack()
            }
            showBanAlert(message: msg)
        case "cmtcaptcha":   // 디시가 코드를 요구함 → 앱 입력창에 코드 칸을 띄우고 다시 등록하게
            if let s = commentCompose {
                s.hasCode = true
                s.codeImage = CommentComposeSession.codeImage(from: body["img"] as? String)
                if let ph = body["ph"] as? String, !ph.isEmpty { s.codePlaceholder = ph }
                s.code = ""
                s.sending = false
                showToast((body["wrong"] as? Bool ?? false) ? "코드가 달라요. 다시 입력해 주세요" : "코드를 입력한 뒤 다시 등록해 주세요")
            }
        case "cmtok":   // 댓글 등록 성공 → 입력창 닫기
            if let k = commentCompose?.draftKey { CommentDraftStore.remove(k) }
            commentCarry = nil
            if commentCompose != nil { withAnimation(.easeOut(duration: 0.2)) { commentCompose = nil } }
        case "cmtlink":   // 댓글 안의 링크를 누름 → 대댓글 달기 / 링크로 이동 선택
            if var s = body["href"] as? String {
                // 디시가 <br>·다음 링크까지 한 주소로 묶어 둔 경우 첫 주소만 (스크립트가 옛 버전이어도 안전하게)
                if let r = s.range(of: "(%3C|<)br|%0[AD]|\\s|(?<=.)https?://", options: [.regularExpression, .caseInsensitive],
                                   range: s.index(s.startIndex, offsetBy: min(8, s.count))..<s.endIndex) {
                    s = String(s[..<r.lowerBound])
                }
                if let u = URL(string: s) { commentLink = u }
            }
        case "wantfocus":   // 댓글을 눌러 답글 칸이 열림 → 키보드 띄우기 (스크립트 focus 허용)
            FocusUnlock.allow(for: 1.5)
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                await call("return window.__dcapp ? window.__dcapp.focusReply() : false;")
            }
        case "pw429":   // 글 수정·삭제 비밀번호 확인이 디시 요청 제한(429)에 걸림 → 페이지가 자동으로 다시 시도
            let n = (body["n"] as? NSNumber)?.intValue ?? 0
            showToast(n == 0 ? "디시가 요청을 잠시 막았어요. 자동으로 다시 시도해요" : "다시 시도하는 중… (\(n)회)")
        case "pw429end":
            showToast("계속 막혀서 멈췄어요. 잠시 뒤 다시 시도해 주세요")
        case "cmt429":   // 댓글 등록이 429로 막힘 → 자동 재등록이 처리함 (기기 클립보드는 건드리지 않음)
            break
        case "alarms":   // 디시 알림 응답(/alarm/notification) → 갤러리 창의 알림 탭에 쌓기
            if let list = body["items"] as? [[String: Any]] { addAlarmsSkippingBlocked(list) }
        case "pwskip":
            showToast("비밀번호 변경 안내를 건너뛰었어요")
        case "blockmiss":
            showToast("글 목록이나 댓글을 탭해주세요")
        case "picked":
            pickRequest = PickRequest(selector: body["selector"] as? String ?? "",
                                      count: (body["count"] as? NSNumber)?.intValue ?? 0,
                                      snippet: body["snippet"] as? String ?? "")
        case "credentials":
            if let id = body["id"] as? String, let pw = body["pw"] as? String, !id.isEmpty, !pw.isEmpty {
                pendingCredential = LoginCredential(id: id, password: pw)
            }
        default:
            break
        }
    }
}

// MARK: - 페이지 이동 처리

extension WebViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // 뒤로·앞으로 간 페이지는 예전에 연 화면이라 메모 설정이 옛날 것일 수 있음 → 열린 뒤 설정을 다시 넣음
        if navigationAction.navigationType == .backForward {
            // 캐시에서 되살아난 페이지는 didFinish가 안 올 수 있어서, 잠깐 뒤에 설정을 넣음
            let js = "window.__dcapp && window.__dcapp.setConfig(\(scriptConfigJSON)); true"
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                _ = try? await webView.evaluateJavaScript(js)
            }
        }
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            return .allow
        }
        // 다른 글·목록으로 가면 앱 댓글 입력창은 닫음 (같은 페이지를 다시 불러오는 건 그대로 둠 — 쓰던 글이 남아 있고 새 댓글칸에 이어서 등록)
        // (대댓글 입력창도 등록할 때 그 댓글의 답글 칸을 다시 열어 연결함)
        if let c = commentCompose, !c.sending, navigationAction.targetFrame?.isMainFrame ?? true {
            let moved = CommentDraftStore.pageKey(url) != c.pageKey
            if moved {
                CommentDraftStore.save(c)
                commentCompose = nil
            }
        }
        if !["http", "https", "about", "data", "blob", "javascript"].contains(scheme) {
            _ = await UIApplication.shared.open(url)
            return .cancel
        }
        // 디시 밖 링크(본 화면 이동만 — 광고·유튜브 같은 칸 안 이동은 그대로) → 물어보고 기본 브라우저로
        if ["http", "https"].contains(scheme), navigationAction.targetFrame?.isMainFrame ?? true, !Self.isDCURL(url) {
            askOpenExternal(url)
            return .cancel
        }
        // 분할 화면: 글 목록에서 글을 누르면 이 화면은 그대로 두고 오른쪽 화면에서 열기
        if navigationAction.targetFrame?.isMainFrame ?? true, let interceptor = postInterceptor,
           navigationAction.navigationType != .reload, navigationAction.navigationType != .backForward,
           PostKey.from(url) != nil, webView.url.flatMap({ PostKey.from($0) }) == nil, interceptor(url) {
            return .cancel
        }
        // 글쓰기 주소로 이동을 시작하면 앱 글쓰기 화면부터 띄움 (양식은 로딩이 끝난 뒤 읽음)
        if navigationAction.targetFrame?.isMainFrame ?? true, Self.nativeWriteEnabled, nativeSkipURL != url,
           let gid = AutoImageStore.writeGalleryID(from: url),
           nativeWrite?.galleryID != gid, nativeWrite?.submitting != true {
            beginNativeWrite(gid)
        }
        return .allow
    }

    /// 디시 주소인지 (m.dcinside.com, msign.dcinside.com, dcimg*.dcinside.co.kr 등)
    nonisolated static func isDCURL(_ url: URL) -> Bool {
        guard let h = url.host?.lowercased() else { return true }
        return ["dcinside.com", "dcinside.co.kr", "dcinside.kr"].contains { h == $0 || h.hasSuffix("." + $0) }
    }

    /// "외부 링크를 열까요?" → 열기면 기본 웹브라우저(사파리 등)로
    private func askOpenExternal(_ url: URL) {
        guard let vc = presenter() else { return }
        if vc is UIAlertController { return }      // 이미 묻는 중 (연달아 오는 이동)
        var shown = url.absoluteString
        if shown.count > 120 { shown = String(shown.prefix(120)) + "…" }
        let alert = UIAlertController(title: "외부 링크 열기", message: "\(url.host ?? "")\n\n\(shown)\n\n기본 웹브라우저에서 열까요?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "링크 복사", style: .default) { _ in UIPasteboard.general.url = url })
        alert.addAction(UIAlertAction(title: "열기", style: .default) { _ in UIApplication.shared.open(url) })
        alert.preferredAction = alert.actions.last
        vc.present(alert, animated: true)
    }

    /// 다른 페이지로 가거나 새로고침 시작 → 꺼 둔 광고 차단 다시 켜기 (새 페이지는 차단된 채로 불러옴)
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        commentTextPrompt = nil      // 다른 페이지로 가면 '텍스트 선택' 버튼은 사라짐
        isRetryingComment = false    // 새 페이지로 가면 댓글 재시도 말풍선도 내림 (남아 있으면 영구히 떠 있게 됨)
        barHiddenByDirection = false     // 새 페이지에서는 컨트롤바를 다시 보임
        barRefY = webView.scrollView.contentOffset.y
        barStats.navResets += 1
        commentsInView = false
        if AdBlock.paused {
            adResumeTask?.cancel()
            AdBlock.setPaused(false, controller: webView.configuration.userContentController)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        endRefreshing()
        if barInsetL > 0 || barInsetR > 0 { applyBarInset() }     // 새 페이지에도 컨트롤바 비움 폭 다시 넣음
        retryIfTooManyRequests()
        webView.removeInputAccessoryBar()   // 웹 프로세스가 다시 시작된 경우 대비
        // 로그인 과정에서 다크모드가 풀렸으면(디시가 쿠키를 덮어씀) 다시 맞춤
        if DarkMode.needsRepair { Task { _ = try? await webView.evaluateJavaScript(DarkMode.pageScript); DarkMode.restoreCookie() } }
        if let u = webView.url, PostKey.from(u) != nil { postLanded?(u) }
        // 분할 화면에서 글을 수정하고 등록하면 디시가 목록으로 보내기도 함 → 수정한 글로
        if let ret = pendingModifyReturn, let u = webView.url, AutoImageStore.writeGalleryID(from: u) == nil {
            pendingModifyReturn = nil
            if Date().timeIntervalSince(ret.at) < 120, PostKey.from(u) == nil { load(ret.url) }
        }

        // 읽은 글 기록 + 방금 쓴 글이면 작성한 글 기록 + 목록이면 읽은 글 보라색
        recordHistory()

        // 알림이 온 글을 열면 → 알림 탭에서도 그 글 알림은 읽음으로
        if let url = webView.url, let info = SavedPostStore.postInfo(url), let no = Int(info.no) {
            AlarmStore.shared.markRead(galleryID: info.galleryID, postNo: no)
        }

        // 방문한 갤러리 기록 (하단 바 "갤러리" → 방문한 갤러리)
        if let url = webView.url, let g = Gallery.parse(url) {
            VisitedStore.shared.record(galleryID: g.id, kind: g.kind,
                                       name: Gallery.guessName(title: webView.title ?? "", url: url, id: g.id))
        }
        let host = webView.url?.host

        if lastHost == DC.loginHost, host != DC.loginHost {
            // 로그인 완료
            NotificationCenter.default.post(name: DC.sessionChanged, object: self)
            offerToSaveCredential()
            // 쓰던 글이 있는데 디시가 원래 글쓰기 화면으로 돌려보내지 않았으면(메인 등으로 감) 글쓰기 화면을 다시 열어 쓰던 내용을 채움
            if let k = keptWrite, Date().timeIntervalSince(k.at) < 1800, let w = k.draft.writeURL,
               webView.url.flatMap(AutoImageStore.writeGalleryID) == nil {
                load(w)
            }
        }
        if host != DC.loginHost { manualLogin = false }      // 로그인 화면을 벗어나면 원래대로
        if host == DC.loginHost {
            autofillLogin()
        }
        // 웹페이지의 로그아웃 링크로 로그아웃한 경우 → 앱이 기억하는 '지금 계정'도 비움
        if host == "m.dcinside.com", CredentialStore.currentAccountID != nil {
            Task {
                let state = await call("return window.__dcapp ? window.__dcapp.loginState() : 'unknown';") as? String
                if state == "out", CredentialStore.currentAccountID != nil {
                    CredentialStore.currentAccountID = nil
                }
            }
        }
        if isPickMode { setPickMode(true) }   // 새 페이지에도 선택 모드 유지
        if isBlockPickMode { setBlockPickMode(true) }
        if isMemoPickMode { Task { await call("if (window.__dcapp) window.__dcapp.setBlockPickMode(true); return true;") } }


        if scrollToCommentsAfterLoad {
            scrollToCommentsAfterLoad = false
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                await call("return window.__dcapp ? window.__dcapp.scrollToComments() : false;")
                showToast("댓글을 새로고침했어요")
            }
        }

        // 글쓰기 화면이면 자짤 자동 첨부
        let writeGID = webView.url.flatMap(AutoImageStore.writeGalleryID)
        if writeGID != nil { lastWriteURL = webView.url }
        // 앱 글쓰기 화면: 글쓰기 페이지면 덮고, 다른 페이지로 가면(등록 완료 등) 닫음
        var nativeHandled = false
        if let gid = writeGID, Self.nativeWriteEnabled, nativeSkipURL != webView.url {
            if let s = retrySession, nativeWrite === s {
                retrySession = nil
                continueRetry(s)           // 재시도: 같은 화면·내용을 유지한 채 다시 등록
            } else if let rec = nativeRecovery, nativeWrite === rec.session, rec.session.galleryID == gid, rec.session.infoRequested {
                // 웹 프로세스가 종료돼 다시 연 글쓰기 페이지 → 앱 글쓰기 화면·내용은 그대로 두고 양식만 다시 읽음
                // 처음 양식을 읽는 도중에 끊겼던 화면(startDone 아님)만 처음 시작 과정(자짤·글 수정 불러오기 포함)을 마저 함
                // (화면이 먼저 뜨고 페이지가 아직 안 열린 채 끊긴 경우는 아래 기존 시작 경로가 맡음)
                if rec.session.startDone { rereadNativeWrite(rec.session) }
                else { finishNativeWriteStart(rec.session, gid, restored: rec.session.restoredFromDraft) }
            } else if let s = nativeWrite, s.galleryID == gid, s.submitting, s.hasText || s.hasUserImages {
                // 등록 중이던 화면(쓴 내용 있음)이 있는데 같은 글쓰기 페이지가 새로 열림 → 빈 화면으로 덮어쓰지 않고 같은 화면·내용에서 양식만 다시 읽음
                // 등록이 됐는지 알 수 없으니 자동으로 다시 등록하지는 않음 (끊긴 등록 호출의 결과는 버림)
                s.submitToken = UUID()
                s.submitting = false
                s.loaded = false
                showToast("등록 중에 페이지가 다시 열렸어요. 글이 올라갔는지 확인한 뒤 필요하면 다시 등록해 주세요")
                armNativeLoadTimeout(for: s, keepWritten: true)
                rereadNativeWrite(s)
            } else if nativeWrite?.galleryID != gid || nativeWrite?.submitting == true {
                startNativeWrite(gid)
            } else if let s = nativeWrite, !s.infoRequested {
                finishNativeWriteStart(s, gid, restored: s.restoredFromDraft)   // 이동을 시작할 때 먼저 띄운 화면 → 로딩이 끝났으니 양식 읽기
            } else if nativeWriteNeedsReread, let s = nativeWrite {
                Task { _ = await readWriteInfo(s) }
            }
            nativeWriteNeedsReread = false
            nativeRecovery = nil
            focusTitleOnWrite = false
            nativeHandled = true      // 자짤·이어쓰기·자동 저장은 앱 화면에서 처리
        }
        if writeGID == nil { nativeSkipURL = nil }
        if writeGID == nil, let s = nativeWrite {
            if let rec = nativeRecovery, rec.session === s {
                // 웹 프로세스 종료 뒤 글쓰기 페이지를 다시 열었는데 다른 곳(로그인 만료 등)으로 보내짐 → 조용히 닫지 않고, 쓰던 글을 임시저장해 두고
                // 로그인 뒤 글쓰기 페이지로 돌아오면(또는 로그인 완료 뒤 이 글쓰기 주소를 다시 열면) 다시 채워지게 함
                nativeRecovery = nil
                if s.hasText || s.hasUserImages {
                    keepNativeWrite(s, writeURL: rec.url)
                    loginRestoreDeadline = Date().addingTimeInterval(1800)
                    showToast("글쓰기 페이지로 돌아가지 못했어요. 쓰던 글은 로그인 뒤 다시 채워지고, 임시저장에도 있어요")
                } else {
                    showToast("글쓰기 페이지로 돌아가지 못했어요")
                }
            } else if s.submitting {
                DraftStore.shared.removeAuto(galleryID: s.galleryID)   // 등록됨 → 자동 저장본 지움
                if s.modifyPostURL == nil, openWrittenPost != nil { openWrittenPostFromList(title: s.title) }   // 분할 화면: 방금 쓴 글을 오른쪽에
            }
            nativeWrite = nil
        }
        if let gid = writeGID, !nativeHandled {
            let eff = AutoImageStore.shared.effective(for: gid, account: AutoImageScope.currentAccount())   // 계정·갤러리별 설정 반영
            if eff.enabled && eff.mode == .auto { attachAutoImage(force: false) }
        }

        // 글쓰기 화면: 15초마다 자동 임시저장 + 이어쓰기 요청이 있으면 내용 채우기
        if writeGID != nil, !nativeHandled {
            Task { await call("if (window.__dcapp) window.__dcapp.startAutosave(); return true;") }
            if let d = pendingDraft {
                pendingDraft = nil
                keptWrite = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    restoreDraft(d)
                }
            } else if let k = keptWrite {
                keptWrite = nil
                // 로그인·로그아웃 뒤 같은 갤러리 글쓰기로 돌아왔으면 (10분 안) 쓰던 내용 다시 채우기
                if k.draft.galleryID == writeGID, Date().timeIntervalSince(k.at) < 1800 {
                    Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        restoreDraft(k.draft, message: "쓰던 내용을 다시 채웠어요")
                    }
                }
            }
            if focusTitleOnWrite {
                focusTitleOnWrite = false
                let page = webView.url
                Task {
                    try? await Task.sleep(for: .milliseconds(400))   // 자짤 첨부 등이 먼저 끝나도록
                    // 키보드가 실제로 올라올 때까지 몇 번 다시 시도 (페이지 스크립트가 포커스를 뺏거나, 칸이 늦게 생기는 경우)
                    for attempt in 0..<8 {
                        guard webView.url == page, !keyboardUp else { break }
                        // 갤러리 창·하단 바처럼 앱 버튼으로만 이동해 와서 웹뷰를 한 번도 안 눌렀으면
                        // 웹뷰가 입력 대상(first responder)이 아니라서 키보드가 안 뜸 → 먼저 웹뷰를 입력 대상으로
                        if attempt == 0 { webView.becomeFirstResponder() }
                        FocusUnlock.allow(for: 1.5)
                        await call("return window.__dcapp ? window.__dcapp.focusTitle() : 'none';")
                        try? await Task.sleep(for: .milliseconds(600))
                    }
                }
            }
        } else {
            focusTitleOnWrite = false
        }
        lastHost = host
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        endRefreshing()
        dropUnreadNativeWrite(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        endRefreshing()
        dropUnreadNativeWrite(error)
    }

    /// 먼저 띄운 앱 글쓰기 화면인데 페이지가 안 열렸으면(연결 실패 등) 닫아서 디시 화면의 오류를 보이게 (다른 이동으로 바뀐 '취소'는 무시)
    private func dropUnreadNativeWrite(_ error: Error) {
        guard let s = nativeWrite, !s.infoRequested, (error as NSError).code != NSURLErrorCancelled else { return }
        nativeWrite = nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // 앱 글쓰기 중 웹 프로세스가 (백그라운드에서) 종료됐으면: 화면·내용은 그대로 두고 쓰던 글을 임시저장, 글쓰기 페이지만 다시 열어 양식을 다시 읽음
        if let s = nativeWrite,
           let u = [webView.url, lastWriteURL].compactMap({ $0 }).first(where: { AutoImageStore.writeGalleryID(from: $0) == s.galleryID }) {
            if s.submitting {
                // 등록 도중에 끊겼다면 글이 올라갔는지 알 수 없음 → 자동으로 다시 등록하지 않고(글이 두 번 올라갈 수 있음) '등록 중'만 풀어 직접 확인하게 함
                // 토큰을 바꿔 끊긴 등록 호출이 오류로 돌아와도 결과를 버림. (페이지만 reload하면 didFinish가 이 화면을 빈 화면으로 덮어쓰던 경로이기도 했음)
                s.submitToken = UUID()
                s.submitting = false
                showToast("등록 중에 화면이 다시 시작됐어요. 글이 올라갔는지 확인한 뒤 필요하면 다시 등록해 주세요")
            }
            autosaveNativeWrite(s, writeURL: u)
            s.loaded = false              // 양식을 다시 읽기 전에는 등록하지 못하게
            nativeRecovery = (s, u)
            nativeWriteNeedsReread = false      // 다시 읽기는 nativeRecovery가 맡음 (didFinish에서 양식이 준비되길 기다린 뒤 읽음)
            nativeSkipURL = nil
            retrySession = nil                  // 끊긴 재시도는 이어가지 않음 (화면·내용은 위에서 그대로 유지)
            armNativeLoadTimeout(for: s, keepWritten: true)     // 이전 타이머는 취소하고 지금부터 새로 맞춤
            webView.load(URLRequest(url: u))
            return
        }
        webView.reload()
    }
}

// MARK: - 새 창 / alert / confirm

/// 디시 alert 응답을 한 번만 하게 하는 상자 (액션과 안전장치가 겹쳐도 두 번 응답하지 않음)
final class PanelOnce {
    private var done = false
    func run(_ f: () -> Void) { if !done { done = true; f() } }
}

extension WebViewModel: WKUIDelegate {
    /// 디시 로그인 후 뜨는 '비밀번호 변경 권장' 창인지 ("다음에 변경할까요?"처럼 확인=건너뛰기인 문구는 제외)
    nonisolated static func isPasswordChangeNag(_ message: String) -> Bool {
        guard message.contains("비밀번호"), message.contains("변경") else { return false }
        if message.contains("다음에") || message.contains("나중에") { return false }
        return message.contains("권장") || message.contains("지났") || message.contains("변경하시겠") ||
            message.contains("변경해 주세요") || message.contains("변경해주세요") || message.contains("오래")
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            // 새 창으로 여는 디시 밖 링크도 물어보고 기본 브라우저로
            if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !Self.isDCURL(url) {
                askOpenExternal(url)
            } else {
                webView.load(navigationAction.request)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        if Self.isPasswordChangeNag(message) {           // 안내만 하는 알림창은 그냥 닫기
            showToast("비밀번호 변경 안내를 건너뛰었어요")
            return
        }
        nativeWrite?.submitting = false      // 디시가 안내창을 띄우면(입력 누락 등) 앱 글쓰기 '등록 중' 풀기
        commentCompose?.sending = false
        // 글·댓글을 쓰는 중에 차단 안내가 오면 → 디시 문구를 그대로 보여 주고, 쓰던 화면은 닫고 이전 화면으로 (막지는 않음)
        // 앱 글쓰기가 양식을 불러오는 중(아직 입력 전)에 디시가 안내창을 띄우면 문구에 상관없이 글쓰기를 막는 안내(차단 등)로 봄
        let opening = nativeWrite.map { !$0.loaded && !$0.submitting } ?? false
        let closeAfter = (nativeWrite != nil || commentCompose != nil) && (Self.looksLikeBan(message) || opening)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let once = PanelOnce()
            let shown = Self.slowNetworkNote(for: message).map { message + "\n\n" + $0 } ?? message
            let alert = UIAlertController(title: nil, message: shown, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in once.run { cont.resume() } })
            presentPanel(alert) { once.run { cont.resume() } }
        }
        // 안내를 확인한 뒤에 글쓰기 화면을 닫음 (먼저 닫으면 안내창이 같이 사라져 문구가 안 보임)
        if closeAfter {
            commentCompose = nil
            if nativeWrite != nil { forceCloseNativeWrite(quiet: true) }
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        // 로그인 후 "비밀번호를 변경하시겠습니까?" 확인창 → 자동으로 '취소'(다음에)
        if Self.isPasswordChangeNag(message) {
            showToast("비밀번호 변경 안내를 건너뛰었어요")
            return false
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let once = PanelOnce()
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in once.run { cont.resume(returning: false) } })
            alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in once.run { cont.resume(returning: true) } })
            presentPanel(alert) { once.run { cont.resume(returning: false) } }
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let once = PanelOnce()
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in once.run { cont.resume(returning: nil) } })
            alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak alert] _ in
                let t = alert?.textFields?.first?.text
                once.run { cont.resume(returning: t) }
            })
            presentPanel(alert) { once.run { cont.resume(returning: nil) } }
        }
    }
}

// MARK: - SwiftUI 래퍼

struct WebView: UIViewRepresentable {
    let model: WebViewModel
    func makeUIView(context: Context) -> WebViewContainer { WebViewContainer(model: model) }
    func updateUIView(_ uiView: WebViewContainer, context: Context) {
        uiView.model = model
        uiView.attachWebView()
    }
}

/// 웹 화면을 담는 빈 상자. 웹뷰(model.webView)는 항상 한 상자 안에만 있도록 옮겨 붙임
/// 분할·접기 전환 때 옛 화면이 뒤늦게 사라져도, 이미 새 상자로 옮겨 간 웹뷰는 옛 상자와 함께 지워지지 않음
final class WebViewContainer: UIView {
    var model: WebViewModel

    init(model: WebViewModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .clear
        attachWebView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 웹뷰를 이 상자의 자식으로 (다른 상자에 있으면 옮겨 옴), 상자 크기에 맞춤
    func attachWebView() {
        let web = model.webView
        if web.superview !== self {
            // 이미 창(window)에 붙어 있는 다른 상자가 들고 있는데 이 상자는 아직 창에 안 붙었으면(분기 전환 중 해제될 옛 상자) 빼앗지 않음
            if let sv = web.superview, sv.window != nil, self.window == nil { return }
            web.removeFromSuperview()
            addSubview(web)
        }
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { attachWebView() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if model.webView.superview === self { model.webView.frame = bounds }
    }
}

// MARK: - 스와이프 제스처가 웹 스크롤과 같이 동작하도록

extension WebViewModel: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
