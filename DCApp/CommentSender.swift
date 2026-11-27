import Foundation
import SwiftUI
import WebKit

// MARK: - 댓글 등록을 페이지 대신 앱이 보내기 (등록 중에 다른 글로 가도 끊기지 않게)
// 디시의 댓글 등록은 ① /ajax/access (확인 키) → ② /ajax/comment-write 순서.
// 페이지 스크립트가 ②의 본문(확인 키 자리는 placeholder)을 넘기면, 앱이 URLSession으로 두 요청을 차례로 보냄.
// 쿠키는 웹뷰 쿠키 저장소의 것을 직접 붙이고, 받은 쿠키는 호출한 쪽이 웹뷰 저장소에 다시 넣음

/// 서버가 앱이 보낸 요청 자체를 받아 주지 않으면, 앱을 다시 켤 때까지 예전처럼 페이지가 직접 보냄
enum BackgroundComment {
    static var rejected = false
    static var enabled: Bool { !rejected }
}

nonisolated struct CommentSendJob: Sendable {
    var pageURL: URL
    var userAgent: String
    var headers: [String: String]      // 페이지(jQuery)가 붙이려던 헤더 (X-CSRF-TOKEN 등)
    var body: String                   // comment-write 본문
    var setsCheckCookie: Bool          // 디시가 확인 키를 cmtw_chk 쿠키로도 심으려던 경우
}

nonisolated struct CommentSendResult: Sendable {
    var status = 0                     // 0 = 연결 실패·시간 초과
    var text = ""
    var contentType = "application/json"
    var blockKey = ""
    var cookies: [HTTPCookie] = []     // 웹뷰 쿠키 저장소에 넣을 쿠키 (응답이 준 것 + cmtw_chk)
    var rejected = false               // 요청 자체를 거절당한 것으로 보임 (403 등, 답이 JSON이 아님)

    private var json: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    /// 디시 페이지와 같은 기준: result가 false·0이면 실패, 그 밖의 JSON 답은 성공
    var succeeded: Bool {
        guard status == 200, let json else { return false }
        switch json["result"] {
        case let n as NSNumber: return n.intValue != 0
        case let s as String: return s != "0" && s != "false"
        default: return true
        }
    }

    /// 디시가 알려 준 실패 이유 (태그는 뺌)
    var failureCause: String {
        let raw = json?["cause"] as? String ?? ""
        return raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cloudflare Turnstile 등 보안 확인이 필요한 실패인지 판별
    var needsTurnstile: Bool {
        if succeeded { return false }
        // 디시의 코드(캡차) 요청은 Turnstile 시트로 풀 수 없음 → 페이지에 넘겨 입력창에 코드 칸이 뜨게
        if failureCause == "captcha" || failureCause.contains("코드") { return false }
        let c = failureCause.lowercased()
        let t = text.lowercased()
        if c.contains("보안") || c.contains("인증") || c.contains("자동입력") || c.contains("스팸")
            || c.contains("turnstile") || c.contains("captcha") {
            return true
        }
        if t.contains("cf-turnstile") || t.contains("challenges.cloudflare.com") || t.contains("just a moment") {
            return true
        }
        return false
    }
}

nonisolated enum CommentSender {
    static let placeholder = "__DCAPP_BLOCK_KEY__"
    static let origin = URL(string: "https://m.dcinside.com")!

    /// 다른 곳으로 넘기는 응답은 따라가지 않음 (POST가 GET으로 바뀌어 성공처럼 보이지 않게)
    private nonisolated final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil          // 쿠키는 웹뷰 저장소의 것만 직접 붙임
        c.httpShouldSetCookies = false
        c.urlCache = nil
        return URLSession(configuration: c, delegate: NoRedirect(), delegateQueue: nil)
    }()

    /// detached WKWebView로 /ajax/access → /ajax/comment-write 실행 (Safari TLS 지문·쿠키 공유, 메인 웹뷰 이동에도 끊기지 않음)
    @MainActor
    static func send(_ job: CommentSendJob, dataStore: WKWebsiteDataStore, onStatus: ((String) -> Void)? = nil) async -> CommentSendResult {
        await BackgroundCommentRunner.shared.send(job, dataStore: dataStore, onStatus: onStatus)
    }

    /// base: 요청을 보낼 서버 (시험할 때만 바꿈). 쿠키를 고르는 기준은 항상 디시 주소
    /// 429(요청 제한)가 오면 다른 글로 이동해도 끊기지 않도록 Swift 백그라운드에서 직접 재시도
    static func send(_ job: CommentSendJob, cookies: [HTTPCookie], base: URL = origin) async -> CommentSendResult {
        var jar = cookies
        let max429Retries = 15
        for attempt in 0...max429Retries {
            let result = await sendOnce(job, jar: &jar, base: base)
            if result.status == 429 && attempt < max429Retries {
                try? await Task.sleep(for: .milliseconds(1200))
                if Task.isCancelled { return result }
                continue
            }
            return result
        }
        return CommentSendResult()
    }

    private static func sendOnce(_ job: CommentSendJob, jar: inout [HTTPCookie], base: URL) async -> CommentSendResult {
        var result = CommentSendResult()

        // ① 확인 키
        let access = await post("/ajax/access", body: "token_verify=com_submit", job: job, jar: jar, base: base, timeout: 20)
        merge(access.cookies, into: &jar)
        result.cookies = access.cookies
        guard access.status == 200 else {
            result.status = access.status
            result.text = access.text
            result.contentType = access.contentType
            result.rejected = isRejection(access.status)
            return result
        }
        let json = (try? JSONSerialization.jsonObject(with: Data(access.text.utf8))) as? [String: Any]
        guard let key = json?["Block_key"] as? String, !key.isEmpty else {
            // 키 없이는 보내지 않음. 페이지가 성공으로 알지 않도록 실패 답을 만들어 돌려줌
            result.status = 200
            result.text = #"{"result":false,"cause":"댓글 등록 준비에 실패했어요. 다시 등록을 눌러 주세요."}"#
            result.rejected = true
            return result
        }
        result.blockKey = key

        if job.setsCheckCookie, let c = checkCookie(key) {
            merge([c], into: &jar)
            result.cookies.append(c)
        }

        // ② 댓글 등록 (본문은 디시 페이지가 만든 그대로, 확인 키만 진짜 값으로)
        let body = job.body.replacingOccurrences(of: placeholder, with: key)
        let write = await post("/ajax/comment-write", body: body, job: job, jar: jar, base: base, timeout: 30)
        merge(write.cookies, into: &result.cookies)
        result.status = write.status
        result.text = write.text
        result.contentType = write.contentType
        result.rejected = isRejection(write.status)
            || (write.status == 200 && (try? JSONSerialization.jsonObject(with: Data(write.text.utf8))) == nil)
        return result
    }

    private static func isRejection(_ status: Int) -> Bool {
        (300..<400).contains(status) || [400, 401, 403, 405, 419].contains(status)
    }

    private static func post(_ path: String, body: String, job: CommentSendJob, jar: [HTTPCookie], base: URL,
                             timeout: TimeInterval) async -> (status: Int, text: String, contentType: String, cookies: [HTTPCookie]) {
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL,
              let real = URL(string: path, relativeTo: origin)?.absoluteURL else { return (0, "", "", []) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data(body.utf8)
        req.timeoutInterval = timeout
        req.httpShouldHandleCookies = false
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        // 페이지가 붙이려던 헤더 중 필요한 것만
        let allowed = ["x-csrf-token", "accept", "content-type"]
        for (name, value) in job.headers where allowed.contains(name.lowercased()) {
            req.setValue(value, forHTTPHeaderField: name)
        }
        var referer = URLComponents(url: job.pageURL, resolvingAgainstBaseURL: false)
        referer?.fragment = nil
        req.setValue(referer?.string ?? job.pageURL.absoluteString, forHTTPHeaderField: "Referer")
        req.setValue("https://m.dcinside.com", forHTTPHeaderField: "Origin")
        if !job.userAgent.isEmpty { req.setValue(job.userAgent, forHTTPHeaderField: "User-Agent") }
        let cookie = cookieHeader(jar, for: real)
        if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }

        guard let (data, resp) = try? await session.data(for: req), let http = resp as? HTTPURLResponse else { return (0, "", "", []) }
        var fields: [String: String] = [:]
        for (k, v) in http.allHeaderFields { if let k = k as? String, let v = v as? String { fields[k] = v } }
        return (http.statusCode, String(decoding: data, as: UTF8.self),
                http.value(forHTTPHeaderField: "Content-Type") ?? "",
                HTTPCookie.cookies(withResponseHeaderFields: fields, for: real))
    }

    /// 브라우저가 이 주소에 붙일 쿠키만 골라 만든 Cookie 헤더
    static func cookieHeader(_ cookies: [HTTPCookie], for url: URL, now: Date = Date()) -> String {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.isEmpty ? "/" : url.path
        return cookies.filter { c in
            let d = c.domain.lowercased()
            let domainOK = d.hasPrefix(".") ? (host == String(d.dropFirst()) || host.hasSuffix(d)) : host == d
            let pathOK = path == c.path || (path.hasPrefix(c.path) && (c.path.hasSuffix("/") || path.dropFirst(c.path.count).hasPrefix("/")))
            let alive = c.expiresDate.map { $0 > now } ?? true
            return domainOK && pathOK && alive && (!c.isSecure || url.scheme == "https")
        }
        .sorted { $0.path.count > $1.path.count }
        .map { "\($0.name)=\($0.value)" }
        .joined(separator: "; ")
    }

    /// 같은 이름·도메인·경로의 쿠키는 새 것으로 바꿈
    private static func merge(_ new: [HTTPCookie], into jar: inout [HTTPCookie]) {
        for c in new {
            jar.removeAll { $0.name == c.name && $0.domain == c.domain && $0.path == c.path }
            jar.append(c)
        }
    }

    /// 디시 페이지의 setCookie_hk_min("cmtw_chk", 키, 3)과 같은 쿠키
    private static func checkCookie(_ key: String) -> HTTPCookie? {
        let keep = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@*_+-./")   // JS escape()가 그대로 두는 글자
        return HTTPCookie(properties: [
            .name: "cmtw_chk", .value: key.addingPercentEncoding(withAllowedCharacters: keep) ?? key,
            .domain: ".dcinside.com", .path: "/", .expires: Date().addingTimeInterval(180),
        ])
    }

    /// comment-write 본문에 cf-turnstile-response 토큰을 교체하거나 추가
    static func replacingTurnstileToken(_ body: String, token: String) -> String {
        let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "&", with: "%26")
            .replacingOccurrences(of: "=", with: "%3D") ?? token
        let pattern = "(^|&)cf-turnstile-response=[^&]*"
        if let rx = try? NSRegularExpression(pattern: pattern),
           rx.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) != nil {
            return rx.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body),
                                               withTemplate: "$1cf-turnstile-response=\(encoded)")
        }
        return body.isEmpty ? "cf-turnstile-response=\(encoded)" : "\(body)&cf-turnstile-response=\(encoded)"
    }
}

// MARK: - 숨겨진 detached WKWebView로 댓글 등록 (403 차단 회피 + 메인 웹뷰 이동 무관 + 429 자동 재시도)

@MainActor
private final class BackgroundCommentRunner: NSObject, WKNavigationDelegate {
    static let shared = BackgroundCommentRunner()

    private var webView: WKWebView?
    private var currentStoreID: ObjectIdentifier?
    private var loadContinuation: CheckedContinuation<Void, Never>?

    func send(_ job: CommentSendJob, dataStore: WKWebsiteDataStore, onStatus: ((String) -> Void)? = nil) async -> CommentSendResult {
        let wv = ensureWebView(dataStore: dataStore, userAgent: job.userAgent)
        await prepareOrigin(wv, pageURL: job.pageURL)

        let allowed = Set(["x-csrf-token", "accept", "content-type"])
        var filteredHeaders: [String: String] = [:]
        for (k, v) in job.headers where allowed.contains(k.lowercased()) {
            filteredHeaders[k] = v
        }

        let js = """
        const baseHeaders = Object.assign({
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Accept': '*/*',
          'X-Requested-With': 'XMLHttpRequest'
        }, hdrs || {});
        let r1, t1;
        try {
          r1 = await fetch('/ajax/access', {
            method: 'POST',
            credentials: 'include',
            headers: baseHeaders,
            body: 'token_verify=com_submit'
          });
          t1 = await r1.text();
        } catch (e) {
          return { status: 0, text: '', contentType: '', key: '', rejected: false };
        }
        if (r1.status === 429) {
          return { status: 429, text: t1, contentType: r1.headers.get('content-type') || '', key: '', rejected: false };
        }
        if (r1.status !== 200) {
          return { status: r1.status, text: t1, contentType: r1.headers.get('content-type') || '', key: '', rejected: true };
        }
        let j1 = null;
        try { j1 = JSON.parse(t1); } catch (e) {}
        const key = j1 && j1.Block_key ? String(j1.Block_key) : '';
        if (!key) {
          return { status: 200, text: '{"result":false,"cause":"댓글 등록 준비에 실패했어요. 다시 등록을 눌러 주세요."}', contentType: 'application/json', key: '', rejected: true };
        }
        if (setsChk) {
          try { document.cookie = 'cmtw_chk=' + escape(key) + '; path=/; domain=.dcinside.com; max-age=180'; } catch (e) {}
        }
        const finalBody = String(bodyStr).split(placeholder).join(key);
        let r2, t2;
        try {
          r2 = await fetch('/ajax/comment-write', {
            method: 'POST',
            credentials: 'include',
            headers: baseHeaders,
            body: finalBody
          });
          t2 = await r2.text();
        } catch (e) {
          return { status: 0, text: '', contentType: '', key: key, rejected: false };
        }
        if (r2.status === 429) {
          return { status: 429, text: t2, contentType: r2.headers.get('content-type') || '', key: key, rejected: false };
        }
        let isJson = false;
        try { JSON.parse(t2); isJson = true; } catch (e) {}
        return {
          status: r2.status,
          text: t2,
          contentType: r2.headers.get('content-type') || '',
          key: key,
          rejected: (r2.status === 403 || r2.status === 401 || r2.status === 419 || (r2.status === 200 && !isJson))
        };
        """

        let args: [String: Any] = [
            "hdrs": filteredHeaders,
            "bodyStr": job.body,
            "placeholder": CommentSender.placeholder,
            "setsChk": job.setsCheckCookie
        ]
        // 429(요청 제한) 시 완만한 백오프로 재시도 (3초 → 5초 → 8초 → 10초 → 12초 → 15초...)
        let backoffs: [Int] = [3, 5, 8, 10, 12, 15, 15, 15, 15, 15]
        for attempt in 0...backoffs.count {
            guard let dict = (try? await wv.callAsyncJavaScript(js, arguments: args, contentWorld: .page)) as? [String: Any] else {
                return CommentSendResult()
            }
            var res = CommentSendResult()
            res.status = (dict["status"] as? NSNumber)?.intValue ?? 0
            res.text = dict["text"] as? String ?? ""
            res.contentType = dict["contentType"] as? String ?? "application/json"
            res.blockKey = dict["key"] as? String ?? ""
            res.rejected = dict["rejected"] as? Bool ?? false
            if res.status == 429 && attempt < backoffs.count {
                onStatus?("잠시 후 다시 시도 중…")
                try? await Task.sleep(for: .seconds(backoffs[attempt]))
                if Task.isCancelled { return res }
                continue
            }
            return res
        }
        return CommentSendResult()
    }

    private func ensureWebView(dataStore: WKWebsiteDataStore, userAgent: String) -> WKWebView {
        let sid = ObjectIdentifier(dataStore)
        if let existing = webView, currentStoreID == sid {
            if !userAgent.isEmpty { existing.customUserAgent = userAgent }
            return existing
        }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
        if !userAgent.isEmpty { wv.customUserAgent = userAgent }
        wv.navigationDelegate = self
        self.webView = wv
        self.currentStoreID = sid
        return wv
    }

    private func prepareOrigin(_ wv: WKWebView, pageURL: URL) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.loadContinuation = cont
            wv.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: pageURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume()
        loadContinuation = nil
    }
}

// MARK: - 백그라운드 댓글 보안 확인(Turnstile) 시트

struct CommentTurnstileChallenge: Identifiable {
    let id = UUID()
    let pageURL: URL
    let userAgent: String
    let dataStore: WKWebsiteDataStore
    let onToken: (String) -> Void
    let onCancel: () -> Void
}

struct CommentTurnstileSheet: View {
    let challenge: CommentTurnstileChallenge
    @Environment(\.dismiss) private var dismiss
    @State private var finished = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(DCTheme.navy)
                    Text("보안 확인을 완료하면 댓글이 자동으로 등록됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground))

                TurnstileChallengeWebView(
                    url: challenge.pageURL,
                    userAgent: challenge.userAgent,
                    dataStore: challenge.dataStore
                ) { token in
                    guard !finished else { return }
                    finished = true
                    challenge.onToken(token)
                    dismiss()
                }
            }
            .navigationTitle("보안 확인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        if !finished {
                            finished = true
                            challenge.onCancel()
                        }
                        dismiss()
                    }
                }
            }
        }
        .sheetUnderBlueBar()
        .onDisappear {
            if !finished {
                finished = true
                challenge.onCancel()
            }
        }
    }
}

private struct TurnstileChallengeWebView: UIViewRepresentable {
    let url: URL
    let userAgent: String
    let dataStore: WKWebsiteDataStore
    let onToken: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore
        cfg.userContentController.add(context.coordinator, name: "dcappTurnstile")
        let script = """
        (function(){
          var sent = false;
          function focusWidget(){
            var el = document.querySelector('.cf-turnstile, #cf-turnstile, iframe[src*="challenges.cloudflare.com"], #comment_write, .comment-write');
            if (el && el.scrollIntoView) { try { el.scrollIntoView({ behavior: 'instant', block: 'center' }); } catch (e) {} }
          }
          setTimeout(focusWidget, 400);
          setTimeout(focusWidget, 1400);
          var timer = setInterval(function(){
            if (sent) { clearInterval(timer); return; }
            var inp = document.querySelector('input[name="cf-turnstile-response"], textarea[name="g-recaptcha-response"]');
            var val = inp && inp.value ? String(inp.value).trim() : '';
            if (val.length > 10) {
              sent = true;
              clearInterval(timer);
              try { window.webkit.messageHandlers.dcappTurnstile.postMessage({ token: val }); } catch (e) {}
            }
          }, 300);
        })();
        """
        cfg.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        let wv = WKWebView(frame: .zero, configuration: cfg)
        if !userAgent.isEmpty { wv.customUserAgent = userAgent }
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "dcappTurnstile")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onToken: (String) -> Void
        init(onToken: @escaping (String) -> Void) { self.onToken = onToken }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let dict = message.body as? [String: Any], let token = dict["token"] as? String, !token.isEmpty {
                DispatchQueue.main.async { self.onToken(token) }
            }
        }
    }
}
