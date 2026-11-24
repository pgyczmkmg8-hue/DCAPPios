import Foundation
import Combine
import WebKit

// MARK: - 원격 광고차단 자료 (디시 갤러리 필터 + NamuLink)
//
// 기본 규칙(AdBlock.swift의 도메인 차단, ContentScript의 AD_SELECTORS)은 그대로 두고, 그 위에 원격 최신본을 얹는다.
// 광고차단이 켜져 있을 때 앱을 열거나 돌아올 때 백그라운드에서 받아 로컬 캐시에 저장하고, 받기에 실패하면 직전 캐시를 쓴다.
// 받은 내용이 기대한 형식이 아니면(예: CDN 오류 페이지) 버리고 캐시를 지키므로, 시작을 막거나 망가뜨리지 않는다.

/// 원격 주소, 갱신 간격, 로컬 캐시 위치
nonisolated enum AdRemote {
    static let filterURL = URL(string: "https://cdn.jsdelivr.net/gh/hooray804/adguard-gallery-filter@main/filter.txt")!
    static let namuLinkURL = URL(string: "https://cdn.jsdelivr.net/npm/@filteringdev/namulink@latest/dist/NamuLink.user.js")!
    /// 자동 갱신 간격 (필터 헤더의 Expires: 6 hours)
    static let refreshInterval: TimeInterval = 6 * 60 * 60
    /// 실패 뒤 다시 시도하기까지 (실패가 이어져도 너무 자주 받지 않게)
    static let retryInterval: TimeInterval = 30 * 60
    /// 이보다 큰 응답은 자료가 아니라고 보고 버림
    static let maxBytes = 2_000_000

    /// 로컬 캐시 폴더 (Application Support/AdFilter)
    static var cacheDir: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("AdFilter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cacheFile(_ name: String) -> URL? {
        cacheDir?.appendingPathComponent(name)
    }

    /// 애드가드 필터 텍스트인지 (주석 머리말로 시작하고 규칙이 있어야 함)
    static func isValidFilter(_ text: String) -> Bool {
        guard text.utf8.count <= maxBytes else { return false }
        guard let first = text.drop(while: { $0.isWhitespace }).first, first == "!" || first == "[" else { return false }
        return text.contains("##") || text.contains("||")
    }

    /// NamuLink 유저스크립트인지 (헤더·라이선스·대상 주소 확인)
    static func isValidNamuLink(_ text: String) -> Bool {
        guard text.utf8.count <= maxBytes, text.hasPrefix("// ==UserScript==") else { return false }
        return text.range(of: #"@name\s+NamuLink\b"#, options: .regularExpression) != nil
            && text.range(of: #"@license\s+MPL-2\.0"#, options: .regularExpression) != nil
            && text.range(of: #"@match\s+\*://namu\.wiki/\*"#, options: .regularExpression) != nil
    }
}

/// 원격 내용을 받는 공통 함수 (실패하면 nil)
nonisolated enum AdRemoteFetch {
    static func get(_ url: URL, timeout: TimeInterval) async -> Data? {
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, data.count <= AdRemote.maxBytes else { return nil }
            return data
        } catch {
            return nil
        }
    }
}

/// 필터 자료를 들고 있는 곳: 숨김 규칙 텍스트(페이지 설정으로 전달)와 네트워크 차단 규칙(WKContentRuleList)
@MainActor
final class AdFilterStore: ObservableObject {
    static let shared = AdFilterStore()

    /// 숨김 규칙 텍스트 (한 줄에 규칙 하나). 페이지 설정 cfg.adFilterCSS로 보냄
    private(set) var cssText = ""
    /// 컴파일된 네트워크 차단 목록 (조각별로 나뉘어 컴파일되고, 성공한 것만 들어감)
    private(set) var ruleLists: [WKContentRuleList] = []
    /// 적용된 자료가 바뀔 때마다 올라감 (웹뷰가 새 규칙을 다시 붙일 때 씀)
    @Published private(set) var version = 0

    private var appliedHash: UInt64 = 0
    private var compiledIDs: [String] = []
    private var compiledByIndex: [Int: WKContentRuleList] = [:]

    private init() {
        // 캐시가 있으면 바로 적용 (파싱은 가벼움. 규칙 컴파일만 비동기)
        if let url = AdRemote.cacheFile("filter.txt"),
           let text = try? String(contentsOf: url, encoding: .utf8),
           AdRemote.isValidFilter(text) {
            apply(filterText: text)
        }
    }

    /// 받은(또는 캐시된) 필터 텍스트를 적용. 같은 내용이면 아무 것도 하지 않음
    func apply(filterText: String) {
        let out = AdFilterParser.parse(filterText)
        let css = AdFilterParser.cssText(out.selectors)
        let json = AdFilterParser.contentRulesJSON(out.networkRules) ?? "[]"
        let hash = Self.hash(css + "\u{1}" + json)
        guard hash != appliedHash else { return }
        appliedHash = hash
        cssText = css
        compileNetworkRules(out.networkRules, hash: hash)
        version += 1
        print("[AdFilter] 적용: 숨김 \(out.selectors.count)개, 차단 \(out.networkRules.count)개 (건너뜀 CSS \(out.stats.cssSkipped), 차단 \(out.stats.netSkipped))")
    }

    /// 네트워크 규칙을 500개씩 나눠 컴파일. 한 조각이 실패해도 나머지는 살림
    private func compileNetworkRules(_ rules: [[String: Any]], hash: UInt64) {
        guard let store = WKContentRuleListStore.default() else { return }
        for id in compiledIDs {
            store.removeContentRuleList(forIdentifier: id) { _ in }
        }
        compiledIDs = []
        compiledByIndex = [:]
        ruleLists = []
        guard !rules.isEmpty else { return }

        let size = 500
        var start = 0
        var index = 0
        while start < rules.count {
            let chunk = Array(rules[start..<min(start + size, rules.count)])
            start += size
            guard let json = AdFilterParser.contentRulesJSON(chunk) else { index += 1; continue }
            let id = "DCAppFilter-\(String(hash, radix: 16))-\(index)"
            let i = index
            index += 1
            store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { list, error in
                Task { @MainActor in
                    AdFilterStore.shared.compiled(index: i, id: id, list: list, error: error)
                }
            }
        }
    }

    /// 컴파일 결과를 받음 (성공한 조각만 목록에 넣고, 순서대로 정렬)
    fileprivate func compiled(index: Int, id: String, list: WKContentRuleList?, error: Error?) {
        if let list {
            compiledByIndex[index] = list
            compiledIDs.append(id)
            ruleLists = compiledByIndex.keys.sorted().compactMap { compiledByIndex[$0] }
            version += 1
        } else if let error {
            print("[AdFilter] 규칙 조각 \(index) 컴파일 실패: \(error)")
        }
    }

    /// 안정적인 해시 (FNV-1a). 같은 내용이면 항상 같은 값이라 컴파일 식별자로 쓸 수 있음
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return h
    }
}

/// 원격 자료를 받아 캐시에 저장하고 적용. 앱 시작·복귀 때 부르며, 기다리지 않음 (백그라운드)
@MainActor
enum AdFilterUpdater {
    private static var inFlight = false
    static let lastSuccessKey = "adFilterLastSuccess"
    static let lastAttemptKey = "adFilterLastAttempt"

    /// 광고차단이 켜져 있고, 마지막 성공이 갱신 간격보다 오래됐을 때만 받음
    static func refreshIfNeeded() {
        guard AdBlock.enabled, !inFlight else { return }
        let defaults = Profile.defaults
        let now = Date()
        if let ok = defaults.object(forKey: lastSuccessKey) as? Date, now.timeIntervalSince(ok) < AdRemote.refreshInterval {
            return
        }
        if let tried = defaults.object(forKey: lastAttemptKey) as? Date, now.timeIntervalSince(tried) < AdRemote.retryInterval {
            return
        }
        inFlight = true
        defaults.set(now, forKey: lastAttemptKey)
        Task {
            async let filterData = AdRemoteFetch.get(AdRemote.filterURL, timeout: 20)
            async let namuData = AdRemoteFetch.get(AdRemote.namuLinkURL, timeout: 15)
            let filter = await filterData
            let namu = await namuData

            var ok = true
            if let filter, let text = String(data: filter, encoding: .utf8), AdRemote.isValidFilter(text) {
                if let url = AdRemote.cacheFile("filter.txt") { try? filter.write(to: url, options: .atomic) }
                AdFilterStore.shared.apply(filterText: text)
            } else {
                ok = false
            }
            if let namu, let text = String(data: namu, encoding: .utf8), AdRemote.isValidNamuLink(text) {
                if let url = AdRemote.cacheFile("NamuLink.user.js") { try? namu.write(to: url, options: .atomic) }
            } else {
                ok = false
            }
            if ok { defaults.set(Date(), forKey: lastSuccessKey) }
            inFlight = false
        }
    }
}
