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

/// 나무위키 화면 광고 숨기기 (네트워크 차단 뒤에 남는 광고 칸·광고 프레임을 가림).
/// NamuLink는 메인 화면만 보므로 광고 프레임(iframe) 안의 파워링크는 못 가림 → 광고 서버 주소의 프레임과 '파워링크' 라벨 칸을 여기서 숨김.
/// 제목(h1~h6) 안의 글자는 건드리지 않음.
nonisolated enum NamuAdCosmetic {
    static let source = #"""
(function () {
  if (!/(^|\.)namu\.wiki$/.test(location.hostname)) return;
  var AD_HOST = /(^|\.)(doubleclick\.net|googlesyndication\.com|googleadservices\.com|googletagservices\.com|criteo\.(com|net)|taboola\.com|outbrain\.com|adnxs\.com|amazon-adsystem\.com|dable\.io|mobon\.net|vntsm\.com|affec\.tv|ccgateway\.net|3lift\.com|adsrvr\.org|fastclick\.net|liadm\.com|id5-sync\.com|adcr\.naver\.com|siape\.veta\.naver\.com|ad\.search\.naver\.com|searchad\.naver\.com)$/;
  var LABEL = /^\s*(파워링크|PowerLink|Power Link)\s*$/i;
  function hide(el) {
    if (!el || el.hasAttribute('data-dcapp-ad')) return;
    el.setAttribute('data-dcapp-ad', '1');
    el.style.cssText += ';display:none!important;height:0!important;min-height:0!important;margin:0!important;padding:0!important';
  }
  // 광고 이름표(id·class의 단어가 ad·banner·gpt 등)인지
  var AD_TOKEN = /(^|[-_\s])(ad|ads|adv|advert|advertisement|banner|gpt|sponsor|adslot)([-_\s\d]|$)/i;
  // 주소가 없거나 빈 화면(about:blank)이고 높이가 100px 이상인 프레임 = 광고가 빠진 자리
  function emptyFrame(f) {
    var src = (f.getAttribute('src') || '').trim();
    return (src === '' || src === 'about:blank') && f.getBoundingClientRect().height >= 100;
  }
  // 숨긴 광고 밖에 보이는 글자·사진·입력칸이 없는 상자인지 (광고만 들어 있던 빈 칸)
  function isEmptyBox(p) {
    if ((p.textContent || '').length > 400) return false;
    var w = document.createTreeWalker(p, NodeFilter.SHOW_TEXT), n;
    while ((n = w.nextNode())) {
      if ((n.nodeValue || '').trim() && !(n.parentElement && n.parentElement.closest('[data-dcapp-ad]'))) return false;
    }
    var media = p.querySelectorAll('img,video,canvas,svg,picture,iframe,embed,object,input,button,select,textarea');
    for (var i = 0; i < media.length; i++) {
      if (!media[i].closest('[data-dcapp-ad]')) return false;
    }
    return true;
  }
  // 광고 칸을 숨기고, 그 광고만 들어 있던 위쪽 빈 상자도 같이 접어 빈 여백이 남지 않게 함 (글자가 있는 상자는 그대로 둠)
  function collapse(el) {
    hide(el);
    var box = el;
    for (var k = 0; k < 7; k++) {
      var p = box.parentElement;
      if (!p || p === document.body || p === document.documentElement || p.hasAttribute('data-dcapp-ad')) break;
      if (p.tagName === 'MAIN' || p.tagName === 'ARTICLE' || p.querySelector('h1,h2,h3,h4,h5,h6')) break;   // 제목·본문이 든 상자는 가리지 않음
      if (!isEmptyBox(p)) break;
      box = p;
    }
    hide(box);
  }
  function hostOf(src) {
    try { return new URL(src, location.href).hostname; } catch (e) { return ''; }
  }
  // 광고가 차단돼 비어 버린 상자: 높이만 남은 div·section·aside (글자·사진·입력칸이 없고 높이 100px 이상)를 접음
  // 광고 주소·이름표로는 못 잡는 빈 자리 (광고 스크립트가 막혀 iframe 없이 min-height만 남는 경우)
  var GEO_MEDIA = 'img,video,canvas,table,input,button,select,textarea,iframe,embed,object,svg,picture';
  var geoLast = 0;
  // 기하 검사로 접은 칸은 되돌릴 수 있게 원래 style을 기억해 둠 (클라이언트가 나중에 채우는 본문이 접힌 칸에 갇히지 않도록)
  function geoHide(el) {
    el.setAttribute('data-dcapp-geo', el.getAttribute('style') || '');
    el.style.cssText += ';display:none!important;height:0!important;min-height:0!important;margin:0!important;padding:0!important';
  }
  function geoRestore(el) {
    var orig = el.getAttribute('data-dcapp-geo') || '';
    el.removeAttribute('data-dcapp-geo');
    if (orig) el.setAttribute('style', orig); else el.removeAttribute('style');
  }
  function sweepEmptyBoxes() {
    // 접은 뒤에 글자·사진이 들어온 칸은 다시 보이게
    document.querySelectorAll('[data-dcapp-geo]').forEach(function (el) {
      if ((el.textContent || '').trim() !== '' || el.querySelector(GEO_MEDIA)) geoRestore(el);
    });
    document.querySelectorAll('div,section,aside').forEach(function (el) {
      if (el.hasAttribute('data-dcapp-ad') || el.hasAttribute('data-dcapp-geo') || el === document.body || el === document.documentElement) return;
      if (el.closest('h1,h2,h3,h4,h5,h6') || el.querySelector('h1,h2,h3,h4,h5,h6')) return;
      if (el.getBoundingClientRect().height < 100) return;
      if ((el.textContent || '').trim() !== '') return;
      if (el.querySelector(GEO_MEDIA)) return;
      geoHide(el);
    });
  }
  function sweep() {
    if (!document.body) return;
    if (Date.now() - geoLast >= 500) { geoLast = Date.now(); try { sweepEmptyBoxes(); } catch (e) {} }
    document.querySelectorAll('iframe').forEach(function (f) {
      if (f.hasAttribute('data-dcapp-ad')) return;
      if (AD_HOST.test(hostOf(f.getAttribute('src') || '')) || emptyFrame(f)) collapse(f);
    });
    document.querySelectorAll('ins.adsbygoogle, [id^="google_ads_"], [id^="aswift_"], [id^="div-gpt-ad"], [data-google-query-id]').forEach(function (el) {
      if (!el.hasAttribute('data-dcapp-ad')) collapse(el);
    });
    // 광고 이름표가 붙은 빈 칸(고정 높이로 남은 광고 자리): 광고가 빠져 글자·사진이 없으면 접음
    document.querySelectorAll('[id*="adslot" i],[id*="banner" i],[class*="banner" i],[class*="advert" i],[class*="-ad" i],[class*="ad-" i],[class*="_ad" i],[id^="ad-" i],[id^="ad_" i],[id*="gpt" i]').forEach(function (el) {
      if (el.hasAttribute('data-dcapp-ad') || el.closest('h1,h2,h3,h4,h5,h6')) return;
      if (!AD_TOKEN.test(el.id || '') && !AD_TOKEN.test(el.getAttribute('class') || '')) return;
      if (isEmptyBox(el)) collapse(el);
    });
    document.querySelectorAll('span,b,strong,em,small,p,div,a,label,dt,th,td').forEach(function (el) {
      if (el.hasAttribute('data-dcapp-ad') || el.children.length) return;
      if (!LABEL.test(el.textContent || '')) return;
      if (el.closest('h1,h2,h3,h4,h5,h6')) return;
      var box = el;
      for (var k = 0; k < 4 && box.parentElement && box.parentElement !== document.body; k++) {
        var p = box.parentElement;
        if ((p.textContent || '').trim().length > 160 || p.querySelector('h1,h2,h3,h4,h5,h6')) break;   // 제목이 든 위쪽 상자(본문 전체)는 가리지 않음
        box = p;
      }
      collapse(box);
    });
  }
  // 늦게 그려지는 광고 칸도 바로 접도록: 페이지에 새 노드가 붙을 때마다 (60ms 묶어서) 다시 훑음
  var queued = false;
  function queueSweep() {
    if (queued) return;
    queued = true;
    setTimeout(function () { queued = false; sweep(); }, 60);
  }
  setInterval(sweep, 1000);
  document.addEventListener('DOMContentLoaded', sweep);
  if (document.documentElement) {
    new MutationObserver(queueSweep).observe(document.documentElement, { childList: true, subtree: true });
  }
  sweep();
})();
"""#
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
        controller.addUserScript(WKUserScript(source: NamuAdCosmetic.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
