import UIKit
import WebKit

/// ⋮ 메뉴의 다크모드: 앱 화면과 디시 야간 모드(쿠키 m_dcinside_darkmode=done + html.darkmode)를 같이 켜고 끔
/// 버튼을 한 번도 안 눌렀으면 아무것도 건드리지 않음 (아이폰 설정 / 디시에서 직접 켠 야간 모드 그대로)
enum DarkMode {
    static let key = "darkMode"
    static let changed = Notification.Name("DCDarkModeChanged")
    private static let cookieNames = ["m_dcinside_darkmode", "m_dcinside_darkmode_info"]

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }
    private static var isSet: Bool { UserDefaults.standard.object(forKey: key) != nil }

    static func toggle() {
        UserDefaults.standard.set(!isOn, forKey: key)
        apply()
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// 앱을 켤 때 / 바꿀 때: 창 모양 + 디시 쿠키 맞추기
    static func apply() {
        guard isSet else { return }
        let style: UIUserInterfaceStyle = isOn ? .dark : .light
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in scene.windows { w.overrideUserInterfaceStyle = style }
        }
        StatusBarStyler.applySoon()
        syncCookie()
    }

    private static func syncCookie() {
        let store = WKWebsiteDataStore.default().httpCookieStore
        if isOn {
            for name in cookieNames {
                if let c = HTTPCookie(properties: [
                    .domain: ".dcinside.com", .path: "/", .name: name, .value: "done",
                    .expires: Date(timeIntervalSinceNow: 365 * 24 * 3600),
                ]) { store.setCookie(c) }
            }
        } else {
            store.getAllCookies { cookies in
                for c in cookies where cookieNames.contains(c.name) { store.delete(c) }
            }
        }
    }

    /// 지금 열려 있는 페이지에 바로 반영
    static var pageScript: String {
        """
        (function(on){
          var r = document.documentElement; if (!r) return;
          if (on) r.classList.add('darkmode'); else r.classList.remove('darkmode');
          ['m_dcinside_darkmode','m_dcinside_darkmode_info'].forEach(function(n){
            document.cookie = n + (on ? '=done; max-age=31536000' : '=; max-age=0') + '; path=/; domain=.dcinside.com';
          });
        })(\(isOn)); true
        """
    }
}
