import SwiftUI
import Combine
import WebKit

// MARK: - 나무위키 실시간 검색어 · 연관 검색어 (숨김 WKWebView)
//
// 나무위키 대문을 화면 밖의 WKWebView로 열어 두고, 사이트 자체 스크립트가 검색창 아래에 그린 드롭다운을 읽는다.
//  - 검색어가 비어 있으면 드롭다운 = 실시간 검색어
//  - 글자를 입력하면 드롭다운 = 연관 검색어 (검색어로 시작하는 항목만 사용)
// 사이트의 자동완성 응답은 암호화된 형식이라 직접 해석하지 않는다. 화면이 그린 결과만 읽는다.
// 드롭다운 항목 선택자(a.QTz+xWZO)는 사이트 빌드마다 바뀔 수 있다. 없으면 href="#" 링크로 한 번 더 찾는다.
// 요청은 한 번에 하나씩 순서대로 처리해서, 빠른 입력이 서로 섞이지 않게 한다.

@MainActor
final class NamuSuggestBridge: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = NamuSuggestBridge()

    /// 나무위키 대문을 여는 숨김 웹뷰 (광고 차단 규칙 적용)
    let webView: WKWebView
    private var started = false
    private var loaded = false
    /// 앞선 요청이 끝난 뒤에 다음 요청을 실행하기 위한 줄
    private var queue: Task<Void, Never>?

    /// 페이지 본문 (인자 q: 검색어, 빈 문자열이면 실시간 검색어).
    /// 입력은 글자마다 keydown → value → input → keyup 을 보내서 사이트가 키보드 입력과 같게 반응하게 한다.
    private static let script = #"""
    const input = document.querySelector('input[type="search"]');
    if (!input) return [];
    const pick = sel => [...document.querySelectorAll(sel)]
      .map(a => (a.textContent || '').trim())
      .filter(t => t && t.length < 60 && t.indexOf('\n') < 0);
    const read = () => {
      let items = pick('a.QTz\\+xWZO');
      if (!items.length) items = pick('a[href="#"]');
      return [...new Set(items)].slice(0, 10);
    };
    input.focus();
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    setter.call(input, '');
    input.dispatchEvent(new Event('input', { bubbles: true }));
    for (const ch of q) {
      input.dispatchEvent(new KeyboardEvent('keydown', { key: ch, bubbles: true }));
      setter.call(input, input.value + ch);
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new KeyboardEvent('keyup', { key: ch, bubbles: true }));
    }
    const deadline = Date.now() + 3500;
    let items = [];
    while (Date.now() < deadline) {
      await new Promise(r => setTimeout(r, 200));
      items = read();
      if (q ? items.some(t => t.startsWith(q)) : items.length >= 5) break;
    }
    return q ? items.filter(t => t.startsWith(q)) : items;
    """#

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        AdBlock.apply(to: config.userContentController)
    }

    /// 대문을 한 번만 연다. 사이트 스크립트가 도는 동안만 화면에 붙임 (끝나면 떼어냄 — 남겨 두면 좌상단에 흐린 잔상이 보임)
    func prepare() {
        guard !started else { return }
        started = true
        attachHidden()
        webView.load(URLRequest(url: URL(string: "https://namu.wiki/")!))
    }

    /// 창에 붙이되 완전히 투명하게 (알파 0, 터치 안 받음). 이미 붙어 있으면 그대로
    private func attachHidden() {
        guard webView.superview == nil, let window = Self.keyWindow() else { return }
        webView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        webView.alpha = 0
        webView.isUserInteractionEnabled = false
        window.addSubview(webView)
    }

    /// 창에서 떼어냄 (잔상 방지). 페이지 상태는 웹뷰가 그대로 가지고 있어서 다음 요청 때 다시 붙이면 됨
    private func detachHidden() {
        webView.removeFromSuperview()
    }

    /// 빈 검색창의 목록 = 실시간 검색어 (최대 10개)
    func ranking() async -> [String] {
        await serialized { [weak self] in
            guard let self, await self.waitUntilLoaded() else { return [] }
            return await self.run(query: "")
        }
    }

    /// 입력한 검색어의 연관 검색어 (검색어로 시작하는 것만, 최대 10개)
    func suggestions(for query: String) async -> [String] {
        await serialized { [weak self] in
            guard let self, await self.waitUntilLoaded() else { return [] }
            return await self.run(query: query)
        }
    }

    // MARK: 내부

    private func run(query: String) async -> [String] {
        attachHidden()                 // 사이트 검색창 스크립트는 화면에 붙어 있을 때만 확실히 돈다 (보이지는 않음)
        defer { detachHidden() }       // 끝나면 바로 떼어서 흐린 잔상이 남지 않게
        do {
            let result = try await webView.callAsyncJavaScript(Self.script, arguments: ["q": query], in: nil, contentWorld: .page)
            return result as? [String] ?? []
        } catch {
            return []
        }
    }

    /// 대문이 다 열릴 때까지 최대 15초 기다림
    private func waitUntilLoaded() async -> Bool {
        prepare()
        var waited = 0
        while !loaded && waited < 60 {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        return loaded
    }

    /// 요청을 앞의 것이 끝난 뒤에 실행 (한 번에 하나만 페이지 검색창을 건드리게)
    private func serialized<T: Sendable>(_ op: @escaping @MainActor () async -> T) async -> T {
        let previous = queue
        let task = Task { @MainActor () -> T in
            await previous?.value
            return await op()
        }
        queue = Task { _ = await task.value }
        return await task.value
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        detachHidden()                 // 대문이 다 열렸으면 떼어 둠 (질의 때 다시 붙임)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        started = false          // 다음 요청 때 다시 연다
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        started = false
    }
}
