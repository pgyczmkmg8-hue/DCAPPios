import SwiftUI
import UserNotifications
import BackgroundTasks
import WebKit

/// 디시 알림 → iOS 알림
/// 앱이 백그라운드에 있을 때 iOS가 정한 간격으로 깨워주면(BGAppRefreshTask)
/// 웹뷰의 로그인 쿠키로 디시 알림 목록(/alarm/notification)을 받아서 새것만 로컬 알림으로 띄움
enum DCNotify {
    static let refreshTaskID = "MACHU.DCApp.refresh"          // Info.plist BGTaskSchedulerPermittedIdentifiers 와 같아야 함
    static let enabledKey = "notifyEnabled"
    static let openURL = Notification.Name("DCOpenNotificationURL")
    private static let seenKey = "notifySeenKeys"
    private static let endpoint = URL(string: "https://m.dcinside.com/alarm/notification")!

    /// 알림 기능 전체 스위치 — 아직 제대로 동작하지 않아서 꺼 둠 (true로 바꾸면 설정에 다시 나타남)
    static let featureAvailable = false

    static var enabled: Bool { featureAvailable && UserDefaults.standard.bool(forKey: enabledKey) }
    /// 앱이 꺼져 있을 때 알림을 눌러 켠 경우, 화면이 뜬 뒤 열 주소
    static var pendingURL: URL?

    struct Item {
        let galleryID: String
        let postNo: Int
        let commentNo: Int?
        let type: String
        let subject: String
        var key: String { "\(galleryID)-\(postNo)-\(commentNo ?? 0)-\(type)" }
        var url: URL {
            DCGalleryID.postURL(galleryID, no: postNo, comments: commentNo != nil)
        }
    }

    enum NotifyError: LocalizedError {
        case badResponse(String)
        var errorDescription: String? {
            switch self { case .badResponse(let s): "응답을 읽지 못했어요: \(s)" }
        }
    }

    // MARK: - 권한 / 예약

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// 다음 백그라운드 확인 예약 (끄면 예약 취소)
    static func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
        guard enabled else { return }
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)   // 15분 뒤부터 (실제 시각은 iOS가 정함)
        try? BGTaskScheduler.shared.submit(req)
    }

    /// iOS가 백그라운드에서 깨웠을 때
    static func backgroundRefresh() async {
        schedule()                 // 다음 것도 미리 예약
        guard enabled else { return }
        _ = await check()
    }

    // MARK: - 확인

    /// 알림 목록을 받아 새것만 띄움. 결과를 글로 돌려줌 (설정의 '지금 확인'에 표시)
    static func check() async -> String {
        do {
            let items = try await fetchItems()
            let defaults = UserDefaults.standard
            let firstRun = defaults.object(forKey: seenKey) == nil
            var seen = defaults.stringArray(forKey: seenKey) ?? []
            let seenSet = Set(seen)
            let new = items.filter { !seenSet.contains($0.key) }
            if !firstRun {
                for it in new.prefix(5) { await show(it) }
            }
            seen.append(contentsOf: new.map(\.key))
            if seen.count > 500 { seen.removeFirst(seen.count - 500) }
            defaults.set(seen, forKey: seenKey)

            var lines = ["받은 알림 \(items.count)개, 새 알림 \(new.count)개" + (firstRun ? " (처음이라 띄우지 않고 기록만 함)" : "")]
            lines += items.prefix(3).map { "· [\($0.type)] \($0.subject)" }
            return lines.joined(separator: "\n")
        } catch {
            return "확인 실패: \(error.localizedDescription)"
        }
    }

    private static func fetchItems() async throws -> [Item] {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            .filter { $0.domain.hasSuffix("dcinside.com") }
        // 1) 그냥 요청 → 2) 안 되면 첫 화면에서 csrf 토큰을 읽어 다시 요청
        if let items = try? await request(cookies: cookies, csrf: nil) { return items }
        let token = await csrfToken(cookies: cookies)
        return try await request(cookies: cookies, csrf: token)
    }

    private static func baseRequest(_ url: URL, cookies: [HTTPCookie]) -> URLRequest {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpShouldHandleCookies = false
        for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("https://m.dcinside.com/", forHTTPHeaderField: "Referer")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return req
    }

    private static var userAgent: String {
        let v = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(v) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    }

    private static func request(cookies: [HTTPCookie], csrf: String?) async throws -> [Item] {
        var req = baseRequest(endpoint, cookies: cookies)
        req.httpMethod = "POST"
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("https://m.dcinside.com", forHTTPHeaderField: "Origin")
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        if let csrf { req.setValue(csrf, forHTTPHeaderField: "X-CSRF-TOKEN") }
        req.httpBody = Data()
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["result"] as? Bool) == true else {
            throw NotifyError.badResponse(String(decoding: data.prefix(120), as: UTF8.self))
        }
        let list = obj["data"] as? [[String: Any]] ?? []
        return list.compactMap { d in
            guard let gid = d["gallery_id"] as? String, let no = intValue(d["gallery_no"]) else { return nil }
            return Item(galleryID: gid, postNo: no, commentNo: intValue(d["comment_no"]),
                        type: d["type"] as? String ?? "", subject: decodeEntities(d["subject"] as? String ?? ""))
        }
    }

    private static func csrfToken(cookies: [HTTPCookie]) async -> String? {
        let req = baseRequest(URL(string: "https://m.dcinside.com/")!, cookies: cookies)
        guard let res = try? await URLSession.shared.data(for: req) else { return nil }
        let html = String(decoding: res.0, as: UTF8.self)
        guard let r = html.range(of: #"name="csrf-token"\s+content="([^"]+)""#, options: .regularExpression) else { return nil }
        let m = String(html[r])
        guard let q = m.range(of: #"content=""#) else { return nil }
        return String(m[q.upperBound...].dropLast())
    }

    private static func intValue(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func show(_ it: Item) async {
        let c = UNMutableNotificationContent()
        c.title = ["R", "C"].contains(it.type) ? "새 댓글" : "디시 알림"
        c.body = it.subject
        c.sound = .default
        c.threadIdentifier = it.galleryID
        c.userInfo = ["url": it.url.absoluteString]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: it.key, content: c, trigger: nil))
    }

    /// 알림을 눌렀을 때
    static func open(_ string: String?) {
        guard let string, let url = URL(string: string) else { return }
        pendingURL = url
        NotificationCenter.default.post(name: openURL, object: url)
    }
}

/// 알림 표시·탭 처리
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // 앱을 보고 있을 때도 배너로 표시
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let url = response.notification.request.content.userInfo["url"] as? String
        await MainActor.run { DCNotify.open(url) }
    }
}
