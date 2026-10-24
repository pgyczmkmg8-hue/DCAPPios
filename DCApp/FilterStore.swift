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
    var id: String { "\(kind.rawValue):\(value)" }
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
    var label: String { self == .collapse ? "접어서 표시" : "완전히 숨김" }
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

    func addUser(kind: BlockedUser.Kind, value: String, memo: String = "") {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, !settings.users.contains(where: { $0.kind == kind && $0.value == v }) else { return }
        settings.users.append(BlockedUser(kind: kind, value: v, memo: memo))
    }

    func addDccon(key: String, imageURL: String) {
        guard !key.isEmpty, !settings.dccons.contains(where: { $0.key == key }) else { return }
        settings.dccons.append(BlockedDccon(key: key, imageURL: imageURL))
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

    // MARK: 웹페이지로 넘길 설정(JSON)

    var scriptConfigJSON: String {
        let s = settings
        let dict: [String: Any] = [
            "enabled": s.enabled,
            "mode": s.display.rawValue,
            "users": s.users.map { ["k": $0.kind.rawValue, "v": $0.value] },
            "dccons": s.dccons.map(\.key),
            "keywords": s.keywords.map { $0.lowercased() },
            "selectors": s.hiddenElements.map(\.selector),
            "hideBest": s.hideBestNotice,
            "dockComment": UserDefaults.standard.object(forKey: "dockComment") as? Bool ?? true,
            "hideHeader": UserDefaults.standard.object(forKey: "hideSiteHeader") as? Bool ?? true,
            "homeRank": UserDefaults.standard.object(forKey: "homeRankOnly") as? Bool ?? true,
            "hideDory": UserDefaults.standard.object(forKey: "hideDory") as? Bool ?? true,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}
