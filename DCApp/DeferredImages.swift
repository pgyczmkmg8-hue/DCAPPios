import Foundation
import WebKit

// MARK: - 본문 이미지 숨기기 (눌러서 불러오기) — 셀룰러 데이터 절약
//
// 설정(세부 설정 → 본문 이미지 숨기기)이 켜져 있으면, 글 페이지에서 디시 본문 사진 서버(dcimg*) 요청을
// 웹뷰가 아예 보내지 않게 막는다 (WKContentRuleList, 사진 요청만, 글 페이지에서만).
// 페이지(ContentScript)는 막힌 사진 자리에 '이미지 불러오기' 버튼을 두고, 누르면 앱이 대신 받아서
// data 주소로 돌려준다. 받을 수 있는 주소는 dcimg 호스트뿐이다.
// 차단(사용자 차단)과는 다른 기능이다.

@MainActor
enum DeferredImages {
    static let key = "deferPostImages"
    static var enabled: Bool { Profile.defaults.object(forKey: key) as? Bool ?? false }

    private static let identifier = "DCAppDeferImg-v2"
    private static var compiled: WKContentRuleList?

    /// 글 페이지에서만 (m.dcinside.com/board/{갤}/{글번호}, mini·person 포함)
    private static let postPageRegex = #"^https?://m\.dcinside\.com/((mini|person)/)?board/[^/]+/[0-9]+"#
    /// 본문 사진 서버 (dcimg1, dcimg2 … 이 .co.kr / .com 으로 있음). 디시콘 서버는 빼 둠
    private static let photoHostRegex = #"^https?://dcimg[0-9]*\.dcinside\.(co\.kr|com)[:/]"#

    /// 사진(image)과 움짤 동영상(media, <video>의 mp4)을 막는다. 둘 다 같은 사진 서버 주소
    private static var rulesJSON: String {
        let rules: [[String: Any]] = ["image", "media"].map { type in
            [
                "trigger": [
                    "url-filter": photoHostRegex,
                    "resource-type": [type],
                    "if-top-url": [postPageRegex],
                ],
                "action": ["type": "block"],
            ]
        }
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// 웹뷰에 사진 막기 규칙을 붙임 (설정이 꺼져 있으면 아무것도 안 함). AdBlock.apply가 먼저 전부 뗀 뒤 부름
    static func attach(to controller: WKUserContentController) {
        guard enabled else { return }
        if let compiled {
            controller.add(compiled)
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier,
                                                                encodedContentRuleList: rulesJSON) { list, error in
            Task { @MainActor in
                if let list {
                    compiled = list
                    if enabled { controller.add(list) }
                } else if let error {
                    print("[DeferredImages] 규칙 컴파일 실패: \(error)")
                }
            }
        }
    }

    /// 눌러서 불러오기: 디시 사진 서버 주소만 받아 data 주소(이미지)로 돌려줌. 실패하면 nil
    /// 동시에 두 장까지만 받고, 실패하면 잠시 뒤 세 번까지 다시 받는다 (사진 서버가 한꺼번에 많이 오면 막는 일이 있음).
    /// 사진 서버는 Referer가 없으면 403을 주고, 사진을 application/octet-stream 으로 보내는 일이 있어서
    /// Content-Type이 아니라 파일 머리(시그니처)로 이미지인지 확인한다.
    static func fetchDataURL(_ src: String, page: String, userAgent: String) async -> String? {
        guard let url = allowedURL(src) else { return nil }
        await gate.enter()
        var result: String? = nil
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt))) }
            if let data = await fetchOnce(url, page: page, userAgent: userAgent) {
                result = data
                break
            }
        }
        await gate.leave()
        return result
    }

    private static let gate = FetchGate()

    /// 한 번 받기 (성공이면 data 주소, 아니면 nil)
    private static func fetchOnce(_ url: URL, page: String, userAgent: String) async -> String? {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(referer(for: page), forHTTPHeaderField: "Referer")
        req.setValue(agent(userAgent), forHTTPHeaderField: "User-Agent")
        req.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("ko-KR,ko;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let result = try? await URLSession.shared.data(for: req),
              let http = result.1 as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let data = result.0
        guard !data.isEmpty, let mime = sniffImage(data) else { return nil }
        let limit = mime.hasPrefix("video/") ? 30_000_000 : 15_000_000
        guard data.count <= limit else { return nil }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    /// 받을 수 있는 주소: 디시 사진 서버(dcimg*)만. //로 시작하면 https, http는 https로 올려서 받음 (앱은 평문 http를 막음)
    private static func allowedURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("//") { text = "https:" + text }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), host.hasPrefix("dcimg"),
              WebViewModel.isDCURL(url) else { return nil }
        guard scheme == "http", var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        comps.scheme = "https"
        return comps.url
    }

    /// 사진을 연 글 주소를 Referer로 (디시 주소일 때만), 아니면 모바일 디시 주소
    private static func referer(for page: String) -> String {
        if let u = URL(string: page), let h = u.host?.lowercased(), WebViewModel.isDCURL(u), h.hasSuffix("dcinside.com") || h.hasSuffix("dcinside.co.kr") {
            return page
        }
        return "https://m.dcinside.com/"
    }

    /// 페이지의 실제 브라우저 UA (없거나 이상하면 사파리 모바일 UA)
    private static func agent(_ ua: String) -> String {
        let t = ua.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty, t.count < 400 { return t }
        return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    }

    /// 파일 머리로 종류 확인 (JPEG·PNG·GIF·WebP·AVIF·HEIC 사진, MP4 동영상). 아니면 nil (HTML 오류 페이지 등)
    static func sniffImage(_ d: Data) -> String? {
        let b = [UInt8](d.prefix(12))
        guard b.count >= 4 else { return nil }
        if b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "image/jpeg" }
        if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "image/png" }
        if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46, b[3] == 0x38 { return "image/gif" }
        if b.count >= 12, b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46,
           b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return "image/webp" }
        if b.count >= 12, b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 {   // 'ftyp' 상자
            let brand = String(bytes: b[8..<12], encoding: .ascii) ?? ""
            if brand == "avif" || brand == "avis" { return "image/avif" }
            if brand.hasPrefix("heic") || brand.hasPrefix("heix") { return "image/heic" }
            return "video/mp4"   // 움짤 동영상 (mp4·m4v·mov 계열 'ftyp' 상자)
        }
        return nil
    }
}

/// 사진 받기를 동시에 두 장까지만 허용 (먼저 온 순서대로, 빠지면 다음 사람이 들어감)
private actor FetchGate {
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if active < 2 {
            active += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty {
            active -= 1
        } else {
            waiting.removeFirst().resume()   // 자리를 그대로 넘김
        }
    }
}
