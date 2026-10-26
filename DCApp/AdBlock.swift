import Foundation
import WebKit

/// 앱 자체 광고 차단
/// 1) 네트워크: 광고 서버 주소로 가는 요청 자체를 막음 (WKContentRuleList)
/// 2) 화면: 광고 자리(빈 칸)를 숨김 — content.js의 adBlockCSS (cfg.adBlock)
/// 차단할 광고 서버를 늘리려면 아래 domains 목록에 추가
@MainActor
enum AdBlock {
    static let key = "adBlock"
    static var enabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// 막을 광고 서버 (도메인과 그 하위 주소 모두)
    static let domains = [
        // 구글 광고
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "googletagservices.com",
        "adservice.google.com", "adservice.google.co.kr",
        // 해외 광고 네트워크
        "amazon-adsystem.com", "adnxs.com", "criteo.com", "criteo.net", "taboola.com", "outbrain.com",
        "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com", "smartadserver.com",
        // 국내 광고 네트워크
        "dable.io", "mobon.net", "realclick.co.kr", "tenping.kr", "adpnut.com", "adop.cc",
        "display.ad.daum.net", "adcr.naver.com", "siape.veta.naver.com", "ad.about.co.kr",
        // 디시 자체 광고 서버
        "addc.dcinside.com", "ads.dcinside.com", "ad.dcinside.com",
    ]
    /// 도메인 단위가 아니라 주소 일부로 막을 것
    static let urlPatterns = [
        "^https?://t1\\.daumcdn\\.net/kas/",     // 카카오 애드핏
    ]

    private static let identifier = "DCAppAdBlock-v1"
    private static var compiled: WKContentRuleList?

    private static var rulesJSON: String {
        var rules: [[String: Any]] = []
        for d in domains {
            let escaped = d.replacingOccurrences(of: ".", with: "\\.")
            rules.append(["trigger": ["url-filter": "^https?://([^/]*\\.)?" + escaped + "[:/]"],
                          "action": ["type": "block"]])
        }
        for p in urlPatterns {
            rules.append(["trigger": ["url-filter": p], "action": ["type": "block"]])
        }
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// 웹뷰에 차단 규칙 적용 (끄면 빼기). 처음 한 번은 규칙을 컴파일함
    static func apply(to controller: WKUserContentController) {
        controller.removeAllContentRuleLists()
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
                    print("[AdBlock] 규칙 컴파일 실패: \(error)")
                }
            }
        }
    }
}
