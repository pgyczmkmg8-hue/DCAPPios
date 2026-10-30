import SwiftUI

/// GitHub Releases에 올라온 최신 버전 정보
nonisolated struct AppRelease: Identifiable, Sendable {
    let version: String      // "0.5.6" (태그는 버전 그대로, v가 붙어 있어도 뗌)
    let name: String
    let notes: String
    let pageURL: URL         // 릴리스 페이지
    let ipaURL: URL?         // 첨부한 ipa 파일 (있으면)
    var id: String { version }
    /// 릴리스 글의 '필수 업데이트' 기준 (있으면 이 빌드 이하는 건너뛰기와 상관없이 무조건 알림)
    var requiredUpTo: String? { UpdateChecker.requiredUpTo(notes) }
}

/// 앱을 열 때(백그라운드에서 돌아올 때 포함) GitHub Releases의 최신 버전을 확인해서,
/// 버전(0.9.0 → 0.9.1)이 올라갔을 때만 알려 줌 — 빌드 번호만 바뀐 건(0.9.0.14 → 0.9.0.15) 조용히
/// (저장소: github.com/pgyczmkmg8-hue/DCAPPios — 태그는 0.5.6처럼 버전 그대로, 릴리스에 ipa 첨부)
/// 버전 정보/업데이트 확인 화면에서 자동 확인 끄기 / 수동 확인 가능
enum UpdateChecker {
    nonisolated static let repo = "pgyczmkmg8-hue/DCAPPios"
    private static let skippedKey = "updateSkippedVersion"
    static let autoCheckKey = "updateAutoCheck"
    private static let lastCheckKey = "updateLastCheck"

    /// 자동 확인 주기: 앱을 열 때마다 / 하루 한 번
    enum Frequency: String, CaseIterable {
        case everyOpen, daily
        static let storageKey = "updateCheckFrequency"
        static var current: Frequency {
            Frequency(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .everyOpen
        }
        var name: String {
            switch self { case .everyOpen: "열 때마다"; case .daily: "하루 한 번" }
        }
    }

    /// 자동 확인 켜짐 여부 (기본 켬)
    static var autoCheckEnabled: Bool {
        UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 버전 + 빌드를 한 줄로: 0.9.0 (7) → "0.9.0.7"
    /// 릴리스 태그를 0.9.0.7처럼 빌드까지 붙여 올려도, 같은 빌드면 '새 버전'으로 보지 않게
    static var currentFullVersion: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(currentVersion).\(build)"
    }

    /// 릴리스 버전이 지금 앱보다 새 것인지 (빌드 번호까지 비교)
    /// 0.9.0.7 vs 0.9.0 (7) → 아님 / 0.9.1 vs 0.9.0 (7) → 새 것 / 0.9.0 vs 0.9.0 (7) → 아님
    static func isNewerThanCurrent(_ release: String) -> Bool {
        isNewer(release, than: currentFullVersion)
    }

    /// 앱을 열 때 확인 ('하루 한 번'이면 오늘 이미 확인했으면 건너뜀).
    /// 버전이 올라간 새 릴리스가 있고 '건너뛰기'한 버전이 아니면 돌려줌
    static func checkIfDue() async -> AppRelease? {
        guard autoCheckEnabled else { return nil }
        let defaults = UserDefaults.standard
        if Frequency.current == .daily, let last = defaults.object(forKey: lastCheckKey) as? Date,
           Calendar.current.isDateInToday(last) { return nil }
        guard let latest = await fetchLatest() else { return nil }   // 실패하면 다음에 열 때 다시
        defaults.set(Date(), forKey: lastCheckKey)
        // 필수 업데이트: 지금 빌드가 기준 빌드 이하면 버전이 같아도, 건너뛰기를 했어도 무조건 알림
        if let need = latest.requiredUpTo, !isNewer(currentFullVersion, than: need) { return latest }
        guard isVersionNewer(latest.version, than: currentVersion),   // 빌드만 바뀐 건(0.9.0.14 → 0.9.0.15) 조용히
              defaults.string(forKey: skippedKey) != latest.version else { return nil }
        return latest
    }

    /// 릴리스 글에서 '필수 업데이트' 기준 버전 찾기 — 예: "bug fix: ~0.9.3.3" → "0.9.3.3"
    /// ('bug fix:' 또는 '필수 업데이트:' 뒤의 버전, 앞의 ~ 와 v는 무시)
    nonisolated static func requiredUpTo(_ notes: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"(?im)^\s*(?:bug\s*fix|필수\s*업데이트)\s*[:：]\s*~?\s*v?(\d+(?:\.\d+)*)"#),
              let m = re.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
              let r = Range(m.range(at: 1), in: notes) else { return nil }
        return String(notes[r])
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

    /// 앞의 세 자리(버전)가 올라갔는지: 0.9.1 vs 0.9.0 → true, 0.9.0.15 vs 0.9.0 → false
    nonisolated static func isVersionNewer(_ a: String, than b: String) -> Bool {
        func head(_ s: String) -> String {
            s.split(whereSeparator: { !$0.isNumber }).prefix(3).joined(separator: ".")
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
