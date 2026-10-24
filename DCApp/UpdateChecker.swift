import SwiftUI

/// GitHub Releases에 올라온 최신 버전 정보
nonisolated struct AppRelease: Identifiable, Sendable {
    let version: String      // "0.5.6" (태그는 버전 그대로, v가 붙어 있어도 뗌)
    let name: String
    let notes: String
    let pageURL: URL         // 릴리스 페이지
    let ipaURL: URL?         // 첨부한 ipa 파일 (있으면)
    var id: String { version }
}

/// 앱을 열 때마다 GitHub Releases의 최신 버전을 확인해서, 판올림(0.6.x → 0.7.x)일 때만 알려 줌
/// (저장소: github.com/pgyczmkmg8-hue/DCApp — 태그는 0.5.6처럼 버전 그대로, 릴리스에 ipa 첨부)
/// 버전 정보/업데이트 확인 화면에서 자동 확인 끄기 / 수동 확인 가능
enum UpdateChecker {
    nonisolated static let repo = "pgyczmkmg8-hue/DCApp"
    private static let skippedKey = "updateSkippedVersion"
    static let autoCheckKey = "updateAutoCheck"

    /// 자동 확인 켜짐 여부 (기본 켬)
    static var autoCheckEnabled: Bool {
        UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 앱을 열 때마다 확인. 판올림 새 버전이 있고 '건너뛰기'한 버전이 아니면 돌려줌
    static func checkIfDue() async -> AppRelease? {
        guard autoCheckEnabled else { return nil }
        let defaults = UserDefaults.standard
        guard let latest = await fetchLatest() else { return nil }   // 실패하면 다음에 열 때 다시
        guard isMinorNewer(latest.version, than: currentVersion),     // 패치(0.6.1 → 0.6.2)는 조용히
              defaults.string(forKey: skippedKey) != latest.version else { return nil }
        return latest
    }

    static func skip(_ version: String) {
        UserDefaults.standard.set(version, forKey: skippedKey)
    }

    nonisolated static func fetchLatest() async -> AppRelease? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let res = try? await URLSession.shared.data(for: req),
              (res.1 as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let page = (obj["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        let assets = obj["assets"] as? [[String: Any]] ?? []
        let ipa = assets.compactMap { $0["browser_download_url"] as? String }
            .first { $0.lowercased().hasSuffix(".ipa") }
            .flatMap(URL.init(string:))
        return AppRelease(version: version,
                          name: obj["name"] as? String ?? tag,
                          notes: obj["body"] as? String ?? "",
                          pageURL: page,
                          ipaURL: ipa)
    }

    /// 앞의 두 자리(판)가 올라갔는지: 0.7.0 vs 0.6.9 → true, 0.6.3 vs 0.6.2 → false
    nonisolated static func isMinorNewer(_ a: String, than b: String) -> Bool {
        func head(_ s: String) -> String {
            s.split(whereSeparator: { !$0.isNumber }).prefix(2).joined(separator: ".")
        }
        return isNewer(head(a), than: head(b))
    }

    /// "0.5.10" > "0.5.9" 처럼 숫자 단위로 비교
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
