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

/// 차단한 본문 사진 한 장. key: 사진 주소에서 뽑은 키(no= 값, 없으면 주소 경로), hash: 생김새 해시(같은 사진을 다시 올린 것도 찾음, 아직 못 받았으면 nil)
struct BlockedImage: Codable, Hashable, Identifiable {
    var key: String
    var hash: String?
    var src: String           // 차단할 때의 사진 주소 (목록 썸네일, 나중에 해시를 받을 때 씀)
    var id: String { key }
}

/// 차단한 사진을 가리는 방식
enum ImageBlockStyle: String, Codable, CaseIterable, Identifiable {
    case blur, gray
    var id: String { rawValue }
    var label: String { self == .blur ? "블러 처리" : "회색 칸" }
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

/// 적용 범위: nil/빈 문자열 = 모든 갤러리, 아니면 갤러리 ID를 쉼표로 이은 문자열 (예: "dcbest,baseball_new")
enum GalleryScope {
    nonisolated static func ids(_ scope: String?) -> [String] {
        (scope ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    nonisolated static func join(_ ids: [String]) -> String? { ids.isEmpty ? nil : ids.joined(separator: ",") }
    /// 이 범위가 gid 갤러리에 적용되는지
    nonisolated static func applies(_ scope: String?, _ gid: String?) -> Bool {
        let list = ids(scope)
        if list.isEmpty { return true }
        guard let gid else { return false }
        return list.contains(gid)
    }
}

/// 차단 키워드 (gallery가 있으면 그 갤러리에서만). 예전 저장값(문자열)도 읽을 수 있음
struct BlockedKeyword: Codable, Hashable, Identifiable {
    var word: String
    var gallery: String? = nil
    var id: String { "\(word.lowercased())@\(gallery ?? "*")" }

    init(word: String, gallery: String? = nil) { self.word = word; self.gallery = gallery }
    init(from decoder: Decoder) throws {
        if let one = try? decoder.singleValueContainer().decode(String.self) { word = one; gallery = nil; return }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word)
        gallery = try c.decodeIfPresent(String.self, forKey: .gallery)
    }
}

/// 고급 차단: 특정 작성자(IP·식별코드·닉네임)가 특정 단어를 말할 때만 가림
struct AdvancedBlockRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: BlockedUser.Kind
    var value: String
    var keywords: [String]
    var gallery: String? = nil   // 이 갤러리에서만 (nil = 모든 갤러리)
}

struct FilterSettings: Codable {
    var enabled = true
    var display: BlockDisplay = .collapse
    var users: [BlockedUser] = []
    var dccons: [BlockedDccon] = []
    var keywords: [BlockedKeyword] = []
    var hiddenElements: [HiddenElement] = []
    var hideBestNotice = true
    var advancedRules: [AdvancedBlockRule] = []
    var images: [BlockedImage] = []
    var imageBlockStyle: ImageBlockStyle = .blur

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        display = try c.decodeIfPresent(BlockDisplay.self, forKey: .display) ?? .collapse
        users = try c.decodeIfPresent([BlockedUser].self, forKey: .users) ?? []
        dccons = try c.decodeIfPresent([BlockedDccon].self, forKey: .dccons) ?? []
        keywords = try c.decodeIfPresent([BlockedKeyword].self, forKey: .keywords) ?? []
        hiddenElements = try c.decodeIfPresent([HiddenElement].self, forKey: .hiddenElements) ?? []
        hideBestNotice = try c.decodeIfPresent(Bool.self, forKey: .hideBestNotice) ?? true
        advancedRules = try c.decodeIfPresent([AdvancedBlockRule].self, forKey: .advancedRules) ?? []
        images = try c.decodeIfPresent([BlockedImage].self, forKey: .images) ?? []
        imageBlockStyle = try c.decodeIfPresent(ImageBlockStyle.self, forKey: .imageBlockStyle) ?? .blur
    }
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

    /// 페이지·사진 보기에서 알아낸 사진 키 → 해시 (저장하지 않음). 차단 목록에 키가 없어도 같은 사진(재업로드)이면 차단으로 봄
    @Published private(set) var keyHashes: [String: String] = [:]

    private let key = "filterSettings"

    private init() {
        if let data = Profile.defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(FilterSettings.self, from: data) {
            settings = saved
        } else {
            settings = FilterSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            Profile.defaults.set(data, forKey: key)
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
            guard GalleryScope.applies(u.gallery, gallery) else { return false }
            switch u.kind {
            case .id: return !id.isEmpty && u.value == id
            case .ip: return !ip.isEmpty && u.value == ip
            case .nick: return !nick.isEmpty && u.value == nick
            }
        }
    }

    /// 이 내용에 걸리는 차단 키워드들
    func blockedKeywords(in text: String, gallery: String?) -> [BlockedKeyword] {
        let t = text.lowercased()
        guard !t.isEmpty else { return [] }
        return settings.keywords.filter { GalleryScope.applies($0.gallery, gallery) && t.contains($0.word.lowercased()) }
    }

    func isDcconBlocked(_ key: String) -> Bool {
        !key.isEmpty && settings.dccons.contains { $0.key == key }
    }

    // MARK: 본문 사진 차단

    /// 키가 차단 목록에 있거나, 키의 사진 해시가 차단한 사진과 같으면 차단된 사진
    func isImageBlocked(key: String) -> Bool {
        guard !key.isEmpty else { return false }
        if settings.images.contains(where: { $0.key == key }) { return true }
        guard let h = keyHashes[key] else { return false }
        return imageHashBlocked(h)
    }

    /// 사진 키의 생김새 해시를 기록 (페이지 확인·사진 보기에서 계산했을 때)
    func recordImageHash(key: String, hash: String) {
        guard !key.isEmpty, !hash.isEmpty else { return }
        keyHashes[key] = hash
    }

    func addImage(key: String, src: String, hash: String?) {
        guard !key.isEmpty, !settings.images.contains(where: { $0.key == key }) else { return }
        settings.images.append(BlockedImage(key: key, hash: hash, src: src))
    }

    /// 차단한 사진의 해시를 나중에 채움 (이미 있으면 그대로 둠)
    func setImageHash(key: String, hash: String) {
        recordImageHash(key: key, hash: hash)
        guard let i = settings.images.firstIndex(where: { $0.key == key }), settings.images[i].hash == nil else { return }
        settings.images[i].hash = hash
    }

    /// 차단 해제: 키가 같은 항목뿐 아니라, 키의 해시가 차단한 사진과 같은 항목(재업로드 사진)도 함께 뺌
    func removeImage(key: String) {
        let h = keyHashes[key]
        settings.images.removeAll { b in
            if b.key == key { return true }
            guard let h, let bh = b.hash else { return false }
            return ImageBlockHash.matches(bh, h)
        }
    }

    /// 이 사진의 해시가 차단한 사진과 같은 사진인지 (다른 이름으로 다시 올린 것도 잡음)
    func imageHashBlocked(_ hash: String) -> Bool {
        settings.images.contains { b in
            guard let h = b.hash else { return false }
            return ImageBlockHash.matches(h, hash)
        }
    }

    func removeUser(_ u: BlockedUser) {
        settings.users.removeAll { $0.id == u.id }
    }

    func removeDccon(key: String) {
        settings.dccons.removeAll { $0.key == key }
    }

    func removeKeyword(_ k: BlockedKeyword) {
        settings.keywords.removeAll { $0.id == k.id }
    }

    /// gallery가 있으면 그 갤러리에서만, nil이면 모든 갤러리에서 차단
    func addKeyword(_ word: String, gallery: String? = nil) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let g = (gallery?.isEmpty ?? true) ? nil : gallery
        let k = BlockedKeyword(word: w, gallery: g)
        guard !w.isEmpty, !settings.keywords.contains(where: { $0.id == k.id }) else { return }
        settings.keywords.append(k)
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
            if !GalleryScope.applies(b.gallery, gallery) { return false }
            switch b.kind {
            case .id: return !id.isEmpty && id == b.value
            case .ip: return !ip.isEmpty && ip == b.value
            case .nick: return !nick.isEmpty && nick == b.value
            }
        }
    }

    // MARK: 웹페이지로 넘길 설정(JSON)

    var scriptConfigJSON: String { scriptConfig(detailPane: false) }

    /// detailPane: 분할 화면의 오른쪽(글) 화면 — 왼쪽에 목록이 이미 있어서 글목록 버튼을 숨김
    func scriptConfig(detailPane: Bool) -> String {
        let s = settings
        let dict: [String: Any] = [
            "splitDetail": detailPane,
            "enabled": s.enabled,
            "mode": s.display.rawValue,
            "users": s.users.map { ["k": $0.kind.rawValue, "v": $0.value, "g": $0.gallery ?? ""] },
            "dccons": s.dccons.map(\.key),
            "keywords": s.keywords.map { ["w": $0.word.lowercased(), "g": $0.gallery ?? ""] },
            "advRules": s.advancedRules.map { ["k": $0.kind.rawValue, "v": $0.value, "w": $0.keywords.map { $0.lowercased() }, "g": $0.gallery ?? ""] as [String: Any] },
            "selectors": s.hiddenElements.map(\.selector),
            "hideBest": s.hideBestNotice,
            "dockComment": Profile.defaults.object(forKey: "dockComment") as? Bool ?? true,
            "fontSizes": ["title": Profile.defaults.integer(forKey: "textSizeTitle"), "body": Profile.defaults.integer(forKey: "textSizeBody"), "list": Profile.defaults.integer(forKey: "textSizeList")],   // 글자 크기 (0 = 기본)
            "hideHeader": Profile.defaults.object(forKey: "hideSiteHeader") as? Bool ?? true,
            "homeRank": Profile.defaults.object(forKey: "homeRankOnly") as? Bool ?? true,
            "hideDory": Profile.defaults.object(forKey: "hideDory") as? Bool ?? true,
            "nativeComment": Profile.defaults.object(forKey: "nativeComment") as? Bool ?? true,   // 앱 댓글 입력창
            "pinComment": CommentPin.enabled,   // 컨트롤바가 세로 막대일 때 댓글 입력칸을 아래에 고정
            "myId": CredentialStore.currentAccountID ?? "",
            "adBlock": AdBlock.enabled,   // 광고 자리 숨기기
            "floatBar": Profile.defaults.object(forKey: "showFloatingBar") as? Bool ?? true,   // 세로 막대가 댓글 등록 버튼을 가리지 않게
            "memos": MemoStore.shared.memos.map { ["k": $0.kind.rawValue, "v": $0.value, "t": $0.text, "g": $0.gallery ?? ""] },   // 유저 메모
            "autoMemo": AutoMemo.scriptValue,   // 자동메모 ("" 꺼짐 / all / gallery / selected)
            "showIdCode": IdCode.enabled,   // 고닉 식별코드 보기 (메모 없는 고닉의 메모 자리에 아이디 표시)
            "autoMemoGalleries": AutoMemo.selectedIDs,   // "선택한 갤러리만"에서 고른 갤러리
            "anon": ["nick": AnonStore.nick, "pw": AnonStore.password],   // 유동 닉/비번 자동 채우기 (모든 갤러리 공통)
            "anonG": AnonStore.galleryScriptValue,   // 갤러리별 유동 닉/비번 (있으면 공통보다 우선)
            "duoFlip": BrowserView.windowLeftColumn,   // 돌려서 왼쪽에 생긴 줄 → 글자 여백을 오른쪽으로 뒤집음
            "duoCol": BrowserView.hasSideColumnOnly,   // 듀오 옆 세로 줄이 있으면 글자는 줄 안쪽으로
            "images": s.images.map(\.key),                  // 차단한 본문 사진 키
            "imgHashes": s.images.compactMap { $0.hash },   // 해시 (있으면 페이지가 사진 생김새를 확인해 같은 사진을 찾음)
            "imgStyle": s.imageBlockStyle.rawValue,         // 가리는 방식: blur / gray
            "tint": (DCTheme.current.pageTint as Any?) ?? NSNull(),   // 웹페이지 속 디시 파란색 → 테마 색   // 내 글·댓글 닉네임 형광펜용
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}


/// 컨트롤바가 세로 막대일 때 글 아래 댓글 입력칸을 화면 아래에 고정할지 (컨트롤바 쪽 화면이 알려 줌)
@MainActor
enum CommentPin {
    private(set) static var enabled = false

    static func update(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)     // 열려 있는 모든 페이지에 새 설정 전달
    }
}
