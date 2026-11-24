import SwiftUI
import WebKit
import Combine

// MARK: - 나무위키 시트 (WKWebView)
//
// 나무위키 검색 결과를 앱 안의 WKWebView 시트로 연다 (SFSafariViewController는 스크립트를 넣을 수 없어서 쓰지 않음).
// 광고차단이 켜져 있으면 기존 차단 규칙(AdBlock + 원격 필터)을 붙이고, NamuLink 스크립트를 페이지 시작 전에 주입한다.
// 완료를 누르면 시트만 닫히고 보던 디시 화면은 그대로 남는다.

/// NamuLink 유저스크립트 준비: 로컬 캐시를 먼저 쓰고, 캐시가 없을 때만 짧게 받아 본다 (백그라운드 갱신은 AdFilterUpdater가 함)
nonisolated enum NamuLinkScript {
    /// 캐시가 유효하면 주입용 소스
    static func cachedSource() -> String? {
        guard let url = AdRemote.cacheFile("NamuLink.user.js"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              AdRemote.isValidNamuLink(text) else { return nil }
        return wrap(text)
    }

    /// 캐시가 없으면 4초 안에 받아 보고 저장. 실패하면 nil (나무위키는 스크립트 없이 열림)
    static func fetchIfNeeded() async -> String? {
        if let source = cachedSource() { return source }
        guard let data = await AdRemoteFetch.get(AdRemote.namuLinkURL, timeout: 4),
              let text = String(data: data, encoding: .utf8),
              AdRemote.isValidNamuLink(text) else { return nil }
        if let url = AdRemote.cacheFile("NamuLink.user.js") { try? data.write(to: url, options: .atomic) }
        return wrap(text)
    }

    /// 나무위키 페이지(namu.wiki)에서만 실행되게 감싸고, 유저스크립트의 unsafeWindow를 페이지 window로 맞춤
    static func wrap(_ body: String) -> String {
        "(function () {\n"
            + "  if (location.hostname !== 'namu.wiki') return;\n"
            + "  var unsafeWindow = window;\n"
            + body + "\n"
            + "})();\n"
    }
}

/// 나무위키 시트 하나를 담는 모델 (웹뷰·탐색 상태). 시트를 열 때마다 새로 만듦
@MainActor
final class NamuWebModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    let startURL: URL
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var title = "나무위키"
    @Published private(set) var isLoading = true
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    init(url: URL) {
        startURL = url
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.publisher(for: \.canGoBack).receive(on: DispatchQueue.main).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).receive(on: DispatchQueue.main).assign(to: &$canGoForward)
        webView.publisher(for: \.title)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] t in
                guard let t, !t.isEmpty else { return }
                self?.title = t
            }
            .store(in: &cancellables)
    }

    /// 광고차단이 켜져 있으면 차단 규칙과 NamuLink를 붙인 뒤 페이지를 연다 (스크립트는 페이지가 시작되기 전에 붙어 있어야 함)
    func start() {
        guard !started else { return }
        started = true
        guard AdBlock.enabled else {
            webView.load(URLRequest(url: startURL))
            return
        }
        let controller = webView.configuration.userContentController
        AdBlock.apply(to: controller)
        Task { @MainActor in
            if let source = await NamuLinkScript.fetchIfNeeded() {
                controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
            self.webView.load(URLRequest(url: self.startURL))
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    /// 지금 보던 주소를 기본 브라우저(Safari)로
    func openInSafari() {
        UIApplication.shared.open(webView.url ?? startURL)
    }

    static func isNamuHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "namu.wiki" || host.hasSuffix(".namu.wiki")
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // 안쪽 프레임(광고 칸 등)은 그대로 둠
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            if Self.isNamuHost(url) {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)      // 나무위키 밖 주소는 기본 브라우저로
                decisionHandler(.cancel)
            }
        } else if ["about", "blob", "data", "javascript"].contains(scheme) {
            decisionHandler(.allow)
        } else {
            UIApplication.shared.open(url)          // mailto: 등 앱 주소는 기본 앱으로
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // 새 창(target=_blank)은 따로 만들지 않고 같은 화면에서 열거나, 나무위키 밖이면 기본 브라우저로
        if let url = navigationAction.request.url {
            if Self.isNamuHost(url) {
                webView.load(navigationAction.request)
            } else {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }
}

/// 웹뷰를 SwiftUI에 올리는 얇은 래퍼
private struct NamuWebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// 나무위키 시트: 완료(닫기), 뒤로·앞으로, Safari로 열기
struct NamuWebSheet: View {
    @ObservedObject var model: NamuWebModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NamuWebViewRepresentable(webView: model.webView)
                .overlay {
                    if model.isLoading {
                        ProgressView()
                    }
                }
                .navigationTitle(model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { model.goBack() } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .disabled(!model.canGoBack)
                        .accessibilityLabel("뒤로")

                        Button { model.goForward() } label: {
                            Image(systemName: "chevron.forward")
                        }
                        .disabled(!model.canGoForward)
                        .accessibilityLabel("앞으로")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { model.openInSafari() } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel("Safari로 열기")

                        Button("완료") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .sheetUnderBlueBar()
        .task { model.start() }
    }
}
