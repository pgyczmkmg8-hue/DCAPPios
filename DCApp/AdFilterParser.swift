import Foundation

// MARK: - 애드가드 형식 필터 파서 (디시 갤러리 필터 filter.txt)
//
// 앱이 안전하게 옮길 수 있는 규칙만 골라낸다.
// - 넣는 것: 일반(##) 숨김 규칙과 dcinside.com 한정 숨김 규칙, ||호스트 형태의 네트워크 차단 규칙
//   (옵션은 자원 종류와 자사/타사 구분만 허용)
// - 버리는 것: 예외(@@, #@#는 같은 선택자를 빼는 데만 씀), 스크립트릿(#%#·#$#·+js), 비표준 확장(:has-text 등),
//   앱·도메인 한정 옵션(app=, domain=, badfilter 등), 필수 도메인(DC·나무위키·CDN·캡차)을 건드리는 규칙,
//   입력칸·댓글·글쓰기 영역 선택자(앱 기능이 쓰는 곳)

nonisolated enum AdFilterParser {
    /// 필수 도메인: 이 도메인(과 하위 주소)을 막는 네트워크 규칙은 넣지 않음
    static let protectedDomains = [
        "dcinside.com", "dcinside.co.kr", "dcinside.kr", "namu.wiki", "jsdelivr.net",
        "cloudflare.com", "hcaptcha.com", "gstatic.com", "googleapis.com", "apple.com", "icloud.com",
    ]
    /// 선택자에 이 문자열이 있으면 버림 (입력·댓글·글쓰기 영역은 앱 기능이 쓰므로 가리지 않음)
    static let denyFragments = ["input", "textarea", "select", "form", "comment", "write", "dcapp", "[type=", "contenteditable"]
    /// 들어 있으면 CSS로 옮길 수 없는 비표준 확장·스크립트 문법
    static let unsupportedFragments = [":has-text", ":-abp-", ":xpath", ":matches-css", ":upward", ":nth-ancestor",
                                       ":min-text-length", ":remove(", ":watch-attr", ":matches-path", ":style(",
                                       "+js(", "{", "}", "\\", "<"]
    /// 선택자가 정확히 이것이면 버림: 앱이 이미 같은 것을 숨기고(AD_SELECTORS), 글 보기에서 아래 버튼 줄(.btm-btns-both)까지 감싸서
    static let denySelectors: Set<String> = [".outside-search-box"]
    /// 네트워크 규칙에서 허용하는 옵션 (그 밖의 옵션이 붙은 규칙은 버림)
    static let allowedOptions: Set<String> = [
        "third-party", "~third-party", "first-party", "~first-party",
        "script", "image", "stylesheet", "xmlhttprequest", "media", "font", "all",
    ]
    /// 자원 종류 옵션 → WebKit 자원 종류
    static let resourceTypes: [String: String] = [
        "script": "script", "image": "image", "stylesheet": "style-sheet",
        "xmlhttprequest": "raw", "media": "media", "font": "font",
    ]
    /// 네트워크 패턴에 쓸 수 있는 문자 (이 밖의 문자가 있으면 정규식으로 옮기기 어려워 버림)
    static let allowedPatternChars = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_/*^?=&%~")

    struct Stats {
        var cssGeneric = 0
        var cssDC = 0
        var cssSkipped = 0
        var cssException = 0
        var netUsed = 0
        var netSkipped = 0
    }

    struct Output {
        /// 숨김 선택자 (선택자마다 따로 규칙으로 넣음 → 하나가 틀려도 나머지는 살아남음)
        var selectors: [String] = []
        /// WKContentRuleList 규칙 (JSON 객체 배열)
        var networkRules: [[String: Any]] = []
        var stats = Stats()
    }

    static func parse(_ text: String) -> Output {
        var out = Output()

        // 한 줄씩 다듬고, 주석(!)과 머리말([...])은 건너뜀
        var lines: [String] = []
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("!") || s.hasPrefix("[") { continue }
            lines.append(s)
        }

        // 1) 예외 선택자: DC에 해당하는 #@#(또는 도메인 없는 #@#)는 같은 선택자를 빼는 데 씀
        var excepted = Set<String>()
        for s in lines {
            guard let r = s.range(of: "#@#") else { continue }
            let domains = domainList(String(s[..<r.lowerBound]))
            if domains.isEmpty || domains.contains(where: { isDC($0) }) {
                excepted.insert(String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
        }

        // 2) 숨김 규칙 · 네트워크 규칙
        var seenSelectors = Set<String>()
        var seenNetwork = Set<String>()
        for s in lines {
            // 스크립트릿·확장 문법(#$# #%# #?# #$?#)과 예외(#@#)는 여기서 다루지 않음
            if s.contains("#$") || s.contains("#%") || s.contains("#?") || s.contains("#@") {
                out.stats.cssSkipped += s.contains("##") ? 1 : 0
                continue
            }
            if let r = s.range(of: "##") {
                let domains = domainList(String(s[..<r.lowerBound]))
                guard appliesToDC(domains) else { continue }        // 다른 사이트 전용 규칙
                let sel = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard isSafeSelector(sel), !denySelectors.contains(sel) else { out.stats.cssSkipped += 1; continue }
                if excepted.contains(sel) { out.stats.cssException += 1; continue }
                if seenSelectors.contains(sel) { continue }
                seenSelectors.insert(sel)
                if domains.contains(where: { !$0.hasPrefix("~") && isDC($0) }) {
                    out.stats.cssDC += 1
                } else {
                    out.stats.cssGeneric += 1
                }
                out.selectors.append(sel)
            } else if s.hasPrefix("||") {
                if let rule = networkRule(s) {
                    let key = (rule["trigger"] as? [String: Any])?["url-filter"] as? String ?? ""
                    if seenNetwork.contains(key) { continue }
                    seenNetwork.insert(key)
                    out.networkRules.append(rule)
                    out.stats.netUsed += 1
                } else {
                    out.stats.netSkipped += 1
                }
            }
        }
        return out
    }

    /// 선택자들을 CSS 텍스트로 (한 줄에 규칙 하나)
    static func cssText(_ selectors: [String]) -> String {
        selectors.map { $0 + "{display:none!important}" }.joined(separator: "\n")
    }

    /// 네트워크 규칙을 WKContentRuleList JSON으로
    static func contentRulesJSON(_ rules: [[String: Any]]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: rules) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: 도메인 판단

    /// "a.com,~b.com" → ["a.com", "~b.com"] (빈 값·"*"는 도메인 없음으로)
    static func domainList(_ prefix: String) -> [String] {
        prefix.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0 != "*" }
    }

    static func isDC(_ d: String) -> Bool {
        d == "dcinside.com" || d.hasSuffix(".dcinside.com")
    }

    /// 이 규칙이 DC 페이지에 적용되는지 (도메인 없음 / DC 포함 / DC만 뺀 규칙)
    static func appliesToDC(_ domains: [String]) -> Bool {
        let negative = domains.filter { $0.hasPrefix("~") }.map { String($0.dropFirst()) }
        if negative.contains(where: isDC) { return false }
        let positive = domains.filter { !$0.hasPrefix("~") }
        if positive.isEmpty { return true }
        return positive.contains(where: isDC)
    }

    // MARK: 선택자 검사

    /// CSS 규칙으로 옮길 수 있는 선택자인지 (비표준 문법·입력 영역 제외, 괄호·따옴표 짝 확인)
    static func isSafeSelector(_ sel: String) -> Bool {
        guard !sel.isEmpty, sel.count < 400 else { return false }
        let l = sel.lowercased()
        if unsupportedFragments.contains(where: { l.contains($0) }) { return false }
        if denyFragments.contains(where: { l.contains($0) }) { return false }
        var depth = 0
        var quote: Character?
        for ch in sel {
            if let q = quote {
                if ch == q { quote = nil }
                continue
            }
            switch ch {
            case "\"", "'": quote = ch
            case "(", "[": depth += 1
            case ")", "]":
                depth -= 1
                if depth < 0 { return false }
            default: break
            }
        }
        return depth == 0 && quote == nil
    }

    // MARK: 네트워크 규칙

    /// "||host^$옵션" 한 줄 → WKContentRuleList 규칙 (옮길 수 없으면 nil)
    static func networkRule(_ line: String) -> [String: Any]? {
        guard line.hasPrefix("||") else { return nil }
        var pattern = String(line.dropFirst(2))
        var options: [String] = []
        if let d = pattern.firstIndex(of: "$") {
            options = pattern[pattern.index(after: d)...].split(separator: ",").map { String($0) }
            pattern = String(pattern[..<d])
        }
        if options.contains("badfilter") { return nil }
        if options.contains(where: { !allowedOptions.contains($0) }) { return nil }

        let lower = pattern.lowercased()
        guard !lower.isEmpty, lower.unicodeScalars.allSatisfy({ allowedPatternChars.contains($0) }) else { return nil }
        // 필수 도메인을 막을 수 있으면 버림
        if protectedDomains.contains(where: { lower.contains($0) }) { return nil }

        // 끝의 ^(구분자)는 "/ : ? 또는 주소 끝"으로 옮김. 가운데 ^는 옮기지 않음
        var body = lower
        var tail = ""
        if body.hasSuffix("^") {
            body.removeLast()
            tail = "([/:?]|$)"
        }
        guard !body.contains("^") else { return nil }

        // 호스트(첫 / 전) 와 경로를 나눠서 * 의 뜻을 다르게 (호스트는 / 를 넘지 않음)
        let hostPart: String
        let pathPart: String
        if let slash = body.firstIndex(of: "/") {
            hostPart = String(body[..<slash])
            pathPart = String(body[slash...])
        } else {
            hostPart = body
            pathPart = ""
        }
        guard !hostPart.isEmpty, !hostPart.hasPrefix("*"), hostPart.contains(".") else { return nil }

        let regex = "^[a-z][a-z0-9+.-]*://([^/]*\\.)?"
            + regexFragment(hostPart, wildcard: "[^/]*")
            + regexFragment(pathPart, wildcard: ".*")
            + tail

        var trigger: [String: Any] = ["url-filter": regex]
        var types: [String] = []
        for o in options {
            if let t = resourceTypes[o], !types.contains(t) { types.append(t) }
        }
        if !types.isEmpty { trigger["resource-type"] = types }
        let third = options.contains("third-party"), notThird = options.contains("~third-party")
        let first = options.contains("first-party"), notFirst = options.contains("~first-party")
        if (third || notFirst) && !(notThird || first) { trigger["load-type"] = ["third-party"] }
        if (first || notThird) && !(third || notFirst) { trigger["load-type"] = ["first-party"] }
        return ["trigger": trigger, "action": ["type": "block"]]
    }

    /// 패턴 조각 → 정규식 조각 (* 는 wildcard로, 나머지 특수문자는 이스케이프)
    static func regexFragment(_ s: String, wildcard: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "*": out += wildcard
            case ".", "?", "+", "(", ")", "[", "]", "{", "}", "|", "\\", "$", "^":
                out += "\\" + String(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }
}
