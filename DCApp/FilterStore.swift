import SwiftUI
import Combine

// MARK: - 모델

struct BlockedUser: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case id, ip, nick
        var id: String { rawValue }
        var label: String {
            switch self {
            case .id: "아이디"
            case .ip: "IP"
            case .nick: "닉네임"
            }
        }
    }
    var kind: Kind
    var value: String
    var memo: String          // 차단할 때의 닉네임 (표시용)
    var gallery: String? = nil   // 이 갤러리에서만 차단 (nil = 모든 갤러리)
    var id: String { "\(kind.rawValue):\(value)@\(gallery ?? "*")" }
}

struct BlockedDccon: Codable, Hashable, Identifiable {
    var key: String           // 디시콘 이미지 주소의 no= 값
    var imageURL: String
    var id: String { key }
}

struct HiddenElement: Codable, Hashable, Identifiable {
    var selector: String      // CSS 선택자
    var memo: String
    var id: String { selector }
}

enum BlockDisplay: String, Codable, CaseIterable, Identifiable {
    case collapse, remove
    var id: String { rawValue }
    var label: String { self == .collapse ? "차단됨 표시" : "완전히 숨김" }
}

struct FilterSettings: Codable {
    var enabled = true
    var display: BlockDisplay = .collapse
    var users: [BlockedUser] = []
    var dccons: [BlockedDccon] = []
    var keywords: [String] = []
    var hiddenElements: [HiddenElement] = []
    var hideBestNotice = true
}

// MARK: - 저장소

/// 차단/숨김 설정. 바뀔 때마다 저장하고, 열려 있는 모든 웹뷰에 즉시 반영됩니다.
@MainActor
final class FilterStore: ObservableObject {
    static let shared = FilterStore()

    @Published var settings: FilterSettings {
        didSet {
            save()
            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
        }
    }

    private let key = "filterSettings"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(FilterSettings.self, from: data) {
            settings = saved
        } else {
            settings = FilterSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: 추가

    /// gallery가 있으면 그 갤러리에서만, nil이면 모든 갤러리에서 차단
    func addUser(kind: BlockedUser.Kind, value: String, memo: String = "", gallery: String? = nil) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty,
              !settings.users.contains(where: { $0.kind == kind && $0.value == v && $0.gallery == gallery }) else { return }
        settings.users.append(BlockedUser(kind: kind, value: v, memo: memo, gallery: gallery))
    }

    func addDccon(key: String, imageURL: String) {
        guard !key.isEmpty, !settings.dccons.contains(where: { $0.key == key }) else { return }
        settings.dccons.append(BlockedDccon(key: key, imageURL: imageURL))
    }

    // MARK: 길게 눌렀을 때 이미 차단된 대상인지 / 해제

    /// 이 글·댓글 작성자에게 걸려 있는 유저 차단들
    /// gallery: 지금 보고 있는 갤러리 (그 갤러리 전용 차단 + 모든 갤러리 차단이 해당)
    func blockedUsers(id: String, ip: String, nick: String, gallery: String?) -> [BlockedUser] {
        settings.users.filter { u in
            guard u.gallery == nil || u.gallery == gallery else { return false }
            switch u.kind {
            case .id: return !id.isEmpty && u.value == id
            case .ip: return !ip.isEmpty && u.value == ip
            case .nick: return !nick.isEmpty && u.value == nick
            }
        }
    }

    /// 이 내용에 걸리는 차단 키워드들
    func blockedKeywords(in text: String) -> [String] {
        let t = text.lowercased()
        guard !t.isEmpty else { return [] }
        return settings.keywords.filter { t.contains($0.lowercased()) }
    }

    func isDcconBlocked(_ key: String) -> Bool {
        !key.isEmpty && settings.dccons.contains { $0.key == key }
    }

    func removeUser(_ u: BlockedUser) {
        settings.users.removeAll { $0.id == u.id }
    }

    func removeDccon(key: String) {
        settings.dccons.removeAll { $0.key == key }
    }

    func removeKeyword(_ word: String) {
        settings.keywords.removeAll { $0.lowercased() == word.lowercased() }
    }

    func addKeyword(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !settings.keywords.contains(where: { $0.lowercased() == w.lowercased() }) else { return }
        settings.keywords.append(w)
    }

    func addHidden(selector: String, memo: String) {
        let s = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !settings.hiddenElements.contains(where: { $0.selector == s }) else { return }
        settings.hiddenElements.append(HiddenElement(selector: s, memo: memo))
    }

    /// 앱 차단 목록에 걸리는 작성자인지 (알림 거르기용)
    func isBlocked(nick: String, ip: String, id: String, gallery: String) -> Bool {
        let s = settings
        guard s.enabled else { return false }
        return s.users.contains { b in
            if let g = b.gallery, !g.isEmpty, g != gallery { return false }
            switch b.kind {
            case .id: return !id.isEmpty && id == b.value
            case .ip: return !ip.isEmpty && ip == b.value
            case .nick: return !nick.isEmpty && nick == b.value
            }
        }
    }

    // MARK: 웹페이지로 넘길 설정(JSON)

    var scriptConfigJSON: String {
        let s = settings
        let dict: [String: Any] = [
            "enabled": s.enabled,
            "mode": s.display.rawValue,
            "users": s.users.map { ["k": $0.kind.rawValue, "v": $0.value, "g": $0.gallery ?? ""] },
            "dccons": s.dccons.map(\.key),
            "keywords": s.keywords.map { $0.lowercased() },
            "selectors": s.hiddenElements.map(\.selector),
            "hideBest": s.hideBestNotice,
            "dockComment": UserDefaults.standard.object(forKey: "dockComment") as? Bool ?? true,
            "fontSizes": ["title": UserDefaults.standard.integer(forKey: "textSizeTitle"), "body": UserDefaults.standard.integer(forKey: "textSizeBody"), "list": UserDefaults.standard.integer(forKey: "textSizeList")],   // 글자 크기 (0 = 기본)
            "hideHeader": UserDefaults.standard.object(forKey: "hideSiteHeader") as? Bool ?? true,
            "homeRank": UserDefaults.standard.object(forKey: "homeRankOnly") as? Bool ?? true,
            "hideDory": UserDefaults.standard.object(forKey: "hideDory") as? Bool ?? true,
            "myId": CredentialStore.currentAccountID ?? "",
            "adBlock": AdBlock.enabled,   // 광고 자리 숨기기
            "floatBar": UserDefaults.standard.object(forKey: "showFloatingBar") as? Bool ?? true,   // 세로 막대가 댓글 등록 버튼을 가리지 않게
            "memos": MemoStore.shared.memos.map { ["k": $0.kind.rawValue, "v": $0.value, "t": $0.text, "g": $0.gallery ?? ""] },   // 유저 메모
            "autoMemo": AutoMemo.scriptValue,   // 자동메모 ("" 꺼짐 / all / gallery / selected)
            "autoMemoGalleries": AutoMemo.selectedIDs,   // "선택한 갤러리만"에서 고른 갤러리
            "anon": ["nick": AnonStore.nick, "pw": AnonStore.password],   // 유동 닉/비번 자동 채우기
            "tint": (DCTheme.current.pageTint as Any?) ?? NSNull(),   // 웹페이지 속 디시 파란색 → 테마 색   // 내 글·댓글 닉네임 형광펜용
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}
