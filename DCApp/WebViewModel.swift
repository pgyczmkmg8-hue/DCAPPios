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
    let snippet: String

    init(_ body: [String: Any]) {
        func s(_ k: String) -> String { (body[k] as? String) ?? "" }
        kind = s("kind"); nick = s("nick"); userID = s("userId"); ip = s("ip")
        dcconKey = s("dcconKey"); dcconSrc = s("dcconSrc"); snippet = s("snippet")
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
    @Published var isLoading = false
    @Published var progress: Double = 0

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
    @Published var isBlockPickMode = false
    @Published var isWritePage = false
    var pendingDraft: Draft?
    /// 하단 바 '글쓰기'로 들어왔으면, 글쓰기 화면이 열린 뒤 제목 칸에 커서+키보드
    var focusTitleOnWrite = false
    /// 키보드가 떠 있는지 (제목 칸 포커스가 먹혔는지 확인용)
    private var keyboardUp = false
    @Published var toast: String?
    private var toastTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()
    private var lastHost: String?
    private var pendingCredential: LoginCredential?
    /// 계정 전환으로 로그인할 계정 (로그인 화면이 열리면 자동 입력 + 로그인)
    var pendingLogin: LoginCredential?
    /// 새로고침 후 댓글 위치로 이동할지
    private var scrollToCommentsAfterLoad = false

    init(url: URL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
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
        // 왼쪽 1/4 스와이프를 쓰면 웹뷰 기본(가장자리) 제스처는 끔 → 한 번 쓸었는데 두 번 뒤로 가는 문제 방지
        webView.allowsBackForwardNavigationGestures = !Self.customSwipeEnabled
        webView.allowsLinkPreview = false   // 길게 누르기를 차단 메뉴에 사용
        webView.removeInputAccessoryBar()   // 키보드 위 ▲▼✓ 막대 없애기 (댓글창이 키보드에 딱 붙도록)
        webView.scrollView.keyboardDismissMode = .interactive   // 아래로 쓸어내려 키보드 닫기

        // 화면 어디서나 좌우로 쓸어서 뒤로/앞으로 (가장자리 스와이프는 웹뷰 기본 제스처가 처리)
        let swipe = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipe.delegate = self
        swipe.cancelsTouchesInView = false
        webView.addGestureRecognizer(swipe)

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

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

        webView.load(URLRequest(url: url))
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

    @objc private func handlePullToRefresh() { webView.reload() }

    private var swipeStartX: CGFloat = 0

    /// 갤러리 목록 화면에서 스와이프했을 때 할 일 (메인 화면에서는 "갤러리" 창 열기)
    var onGallerySwipe: (() -> Void)?

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
        UserDefaults.standard.object(forKey: "fullSwipeBack") as? Bool ?? true
    }

    /// 스와이프 민감도 (설정 → 앱, 1 = 둔감 … 5 = 민감, 기본 3)
    /// distance: 이만큼 밀면 뒤로 / flickSpeed: 절반만 밀어도 이 속도 이상으로 튕기면 뒤로
    /// ratio: 가로로 민 거리가 세로의 몇 배 이상이어야 하는지 (클수록 위아래 스크롤과 덜 헷갈림)
    static var swipeThresholds: (distance: CGFloat, flickSpeed: CGFloat, ratio: CGFloat) {
        let level = min(5, max(1, UserDefaults.standard.object(forKey: "swipeSensitivity") as? Double ?? 3))
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
            // 말머리 탭처럼 가로로 스크롤되는 곳에서 시작한 스와이프는 무시
            let inHScroll = await call("return window.__dcapp ? window.__dcapp.lastTouchInHScroll() : false;") as? Bool ?? false
            guard !inHScroll else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            swipeBack()
        }
    }

    // MARK: - '뒤로' 동작 (화면 쓸기와 키보드 모드의 뒤로가기 버튼·⌘[ 가 똑같이 씀)

    /// 갤러리 목록 1페이지면 → 뒤로가기 대신 "갤러리" 창 열기 (2페이지부터는 뒤로가기)
    private var opensGalleriesOnBack: Bool {
        // 검색 결과 목록은 제외 (검색 전 목록으로 돌아가야 하므로 보통 뒤로가기)
        let q = webView.url?.query ?? ""
        let isSearch = q.contains("serval=") || q.contains("s_keyword=")
        return isGalleryListPage && !isSearch && listPageNumber <= 1 && onGallerySwipe != nil &&
            (UserDefaults.standard.object(forKey: "gallerySwipeOpensList") as? Bool ?? true)
    }

    /// 글 보는 중인지 (그 갤러리) — 돌아갈 페이지가 없을 때 목록 1페이지로 보내기 위함
    private var postGalleryOnBack: Gallery? {
        webView.url.flatMap { url -> Gallery? in
            guard SavedPostStore.postInfo(url) != nil, let g = Gallery.parse(url) else { return nil }
            return Gallery(galleryID: g.id, name: g.id, kind: g.kind)
        }
    }

    /// 지금 '뒤로' 할 수 있는 게 있는지
    var canSwipeBack: Bool {
        opensGalleriesOnBack || postGalleryOnBack != nil || backTarget() != nil
    }

    func swipeBack() {
        if let url = webView.url, url.query?.contains("recommend=1") == true,
           let g = Gallery.parse(url), SavedPostStore.postInfo(url) == nil {
            // 개념글 목록에서 → 같은 갤러리의 전체글로
            load(Gallery(galleryID: g.id, name: g.id, kind: g.kind).url)
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

    private func presenter() -> UIViewController? {
        var top = webView.window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - 페이지 스크립트

    private func installUserScript() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let source = "window.__DCAPP_CONFIG__ = \(FilterStore.shared.scriptConfigJSON);\n" + ContentScript.source
        // 알림 주소 찾기용 네트워크 기록 (페이지 맨 처음에 넣어야 처음부터 기록됨)
        controller.addUserScript(WKUserScript(source: ContentScript.netLog, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        // 웹페이지가 화면 옆 안전 영역(듀오의 시계·카메라 줄)을 비워두지 않고 끝까지 쓰도록
        controller.addUserScript(WKUserScript(source: Self.viewportFitCover, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        // 광고 차단 (애드가드 갤러리 필터의 디시 규칙) — 광고가 잠깐 보이지 않도록 페이지 맨 처음에
        if UserDefaults.standard.object(forKey: "adFilter") as? Bool ?? true {
            controller.addUserScript(WKUserScript(source: ContentScript.adFilter, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
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

    func applyFilters() {
        webView.allowsBackForwardNavigationGestures = !Self.customSwipeEnabled
        installUserScript()   // 다음 페이지부터 적용
        let js = "window.__dcapp && window.__dcapp.setConfig(\(FilterStore.shared.scriptConfigJSON)); true"
        webView.evaluateJavaScript(js, completionHandler: nil)   // 지금 페이지에 즉시 적용
    }

    @discardableResult
    private func call(_ body: String, _ args: [String: Any] = [:]) async -> Any? {
        try? await webView.callAsyncJavaScript(body, arguments: args, contentWorld: .page)
    }

    // MARK: - 요소 숨기기 모드

    func setPickMode(_ on: Bool) {
        if on && isBlockPickMode { setBlockPickMode(false) }
        isPickMode = on
        Task { await call("if (window.__dcapp) window.__dcapp.setPickMode(on); return true;", ["on": on]) }
    }

    // MARK: - 탭해서 유저 차단 모드 / 글 작성자 차단

    func setBlockPickMode(_ on: Bool) {
        if on && isPickMode { setPickMode(false) }
        isBlockPickMode = on
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
        guard let img = store.pick(for: galleryID),
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

    func restoreDraft(_ draft: Draft) {
        Task {
            let r = await call("return window.__dcapp ? window.__dcapp.setDraft(t, b, h) : 'noscript';",
                               ["t": draft.title, "b": draft.body, "h": draft.isHTML]) as? String
            showToast(r == "restored" ? "임시저장 글을 불러왔어요" : "글쓰기 칸을 찾지 못했어요")
        }
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
            if CredentialStore.currentAccountID != nil || account != nil {
                await DCSession.clear(notify: false)      // 다른 계정으로 바꿀 때는 기존 로그인 지우기
            }
            pendingLogin = account
            load(loginURL(returnTo: back))
            if let account { showToast("\(account.id) 계정으로 로그인하는 중…") }
        }
    }

    /// 로그아웃하고 지금 화면을 다시 열기 (유동으로 쓰기)
    func logoutHere() {
        let back = webView.url
        Task {
            await DCSession.clear(notify: false)
            NotificationCenter.default.post(name: DC.sessionChanged, object: self)   // 다른 화면만 새로고침
            if let back { load(back) } else { reload() }
            showToast("로그아웃했어요")
        }
    }

    // MARK: - 댓글 새로고침

    /// 디시의 댓글 ⟳ 버튼을 대신 누르고, 못 찾으면 페이지를 새로고침한 뒤 댓글 위치로 이동
    func refreshComments() {
        Task {
            let r = await call("return window.__dcapp ? window.__dcapp.refreshComments() : 'none';") as? String
            if r == "clicked" {
                showToast("댓글을 새로고침했어요")
            } else {
                scrollToCommentsAfterLoad = true
                reload()
            }
        }
    }

    // MARK: - 글쓰기 등록

    /// 상단바 '등록' → 디시 글쓰기 화면의 등록 버튼을 대신 누름
    func submitWrite() {
        Task {
            let r = await call("return window.__dcapp ? window.__dcapp.submitWrite() : 'none';") as? String
            if r != "clicked" { showToast("등록 버튼을 못 찾았어요 (페이지 구조 진단을 보내주세요)") }
        }
    }

    // MARK: - 갤러리 관리 내역

    func openManageLog() {
        Task {
            let r = await call("return window.__dcapp ? window.__dcapp.openManageLog() : 'none';") as? String
            if r == "none" || r == nil {
                showToast("관리 내역이 없는 갤러리예요 (갤러리 목록 화면에서 눌러 주세요)")
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

    func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            if !Task.isCancelled { toast = nil }
        }
    }

    func pickParent() {
        Task { await call("if (window.__dcapp) window.__dcapp.pickParent(); return true;") }
    }

    func clearPick() {
        Task { await call("if (window.__dcapp) window.__dcapp.clearPick(); return true;") }
    }

    // MARK: - 진단

    func diagnose() async -> String {
        (await call("return window.__dcapp ? window.__dcapp.diagnose() : '스크립트가 로드되지 않았어요: ' + location.href;") as? String)
            ?? "진단 정보를 가져오지 못했어요."
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
        let switching = pendingLogin != nil
        guard let cred = pendingLogin ?? CredentialStore.load() else { return }
        let auto = switching || UserDefaults.standard.bool(forKey: "autoLogin")
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
        case "longpress":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if isBlockPickMode { setBlockPickMode(false) }   // 한 번 고르면 모드 종료
            blockRequest = BlockRequest(body)
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
                imageViewer = ImageViewerItem(urls: urls, index: (body["index"] as? NSNumber)?.intValue ?? 0)
            }
        case "anon":   // 유동 닉네임/비밀번호를 입력하면 기억 (다음에 빈 칸이면 채움)
            let v = body["value"] as? String ?? ""
            if body["kind"] as? String == "pw" { AnonStore.password = v } else { AnonStore.nick = v }
            // 페이지 스크립트에 넣어 둔 설정은 설치할 때 값이라, 다시 설치해야 다음 페이지(로그아웃 후 등)에서 새 값으로 채움
            installUserScript()
        case "alarms":   // 디시 알림 응답(/alarm/notification) → 갤러리 창의 알림 탭에 쌓기
            if let list = body["items"] as? [[String: Any]] { AlarmStore.shared.add(list) }
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
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            return .allow
        }
        if !["http", "https", "about", "data", "blob", "javascript"].contains(scheme) {
            _ = await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        endRefreshing()
        webView.removeInputAccessoryBar()   // 웹 프로세스가 다시 시작된 경우 대비

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
        }
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
        if let gid = writeGID {
            let eff = AutoImageStore.shared.effective(for: gid)   // 갤러리별 설정 반영
            if eff.enabled && eff.mode == .auto { attachAutoImage(force: false) }
        }

        // 글쓰기 화면: 15초마다 자동 임시저장 + 이어쓰기 요청이 있으면 내용 채우기
        if writeGID != nil {
            Task { await call("if (window.__dcapp) window.__dcapp.startAutosave(); return true;") }
            if let d = pendingDraft {
                pendingDraft = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    restoreDraft(d)
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
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        endRefreshing()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - 새 창 / alert / confirm

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
            webView.load(navigationAction.request)
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
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in cont.resume() })
            guard let vc = presenter() else { cont.resume(); return }
            vc.present(alert, animated: true)
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
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in cont.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in cont.resume(returning: true) })
            guard let vc = presenter() else { cont.resume(returning: false); return }
            vc.present(alert, animated: true)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in cont.resume(returning: nil) })
            alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak alert] _ in
                cont.resume(returning: alert?.textFields?.first?.text)
            })
            guard let vc = presenter() else { cont.resume(returning: nil); return }
            vc.present(alert, animated: true)
        }
    }
}

// MARK: - SwiftUI 래퍼

struct WebView: UIViewRepresentable {
    let model: WebViewModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - 스와이프 제스처가 웹 스크롤과 같이 동작하도록

extension WebViewModel: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
