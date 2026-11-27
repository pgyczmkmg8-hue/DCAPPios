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

/// 차단한 디시콘 패키지(묶음): 길게 눌러 '패키지 차단'할 때 그 패키지의 디시콘 번호를 모두 담아 글·댓글 전체에서 가림
struct BlockedDcconPackage: Codable, Hashable, Identifiable {
    var pkg: String           // 디시 패키지 번호 (package_idx)
    var name: String          // 패키지 이름 (표시용)
    var keys: [String]        // 패키지 안 디시콘들의 no= 값
    var id: String { pkg }
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
    /// 목록에 보이는 문구: 쉼표로 나눈 단어들을 " + "로 (단어가 하나면 그대로)
    var displayText: String { BlockMatch.terms(word).joined(separator: " + ") }
    init(from decoder: Decoder) throws {
        if let one = try? decoder.singleValueContainer().decode(String.self) { word = one; gallery = nil; return }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word)
        gallery = try c.decodeIfPresent(String.self, forKey: .gallery)
    }
}

/// 고급 차단: 특정 작성자(IP·식별코드·닉네임)가 쓴 글·댓글에 단어(keywords)가 모두 들어 있을 때만 가림
struct AdvancedBlockRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: BlockedUser.Kind
    var value: String
    var keywords: [String]
    var gallery: String? = nil   // 이 갤러리에서만 (nil = 모든 갤러리)
    /// 단어를 모두 포함해야 하는지. 예전 저장값(이 필드 없음)은 단어 중 하나면 가려지는 OR였으므로,
    /// 불러올 때 FilterSettings.migrateAdvanced가 단어마다 규칙으로 나눠 같은 동작이 되게 함
    var allWords: Bool = true

    init(kind: BlockedUser.Kind, value: String, keywords: [String], gallery: String? = nil, allWords: Bool = true) {
        self.kind = kind; self.value = value; self.keywords = keywords; self.gallery = gallery; self.allWords = allWords
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(BlockedUser.Kind.self, forKey: .kind)
        value = try c.decode(String.self, forKey: .value)
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        gallery = try c.decodeIfPresent(String.self, forKey: .gallery)
        allWords = try c.decodeIfPresent(Bool.self, forKey: .allWords) ?? false
    }

    /// 목록·상세에 보이는 단어 문구: 단어가 2개 이상이면 "단어 모두 포함: A + B", 하나면 "단어: A"
    var wordsLabel: String {
        keywords.count >= 2 ? "단어 모두 포함: " + keywords.joined(separator: " + ") : "단어: " + keywords.joined(separator: "")
    }
}

/// 차단 단어·닉네임 판정 (차단 키워드·고급 차단·유저 차단이 같이 씀). 웹페이지 쪽 JS(blockedReason)와 같은 규칙
/// - 쉼표(`,`와 전각 `，`)로 나눈 단어 조각은 모두 들어 있어야 참 (AND)
/// - 비교 전 정규화 (소문자화는 항상 함):
///   · 특수문자 무시(symbols): 글자(L)·결합 문자(M)·숫자(N)·공백이 아닌 문자를 뺌
///   · 공백 무시(spaces): 공백(줄바꿈 포함, JS \s와 같은 범위)을 뺌
///   · 둘 다 켜면 둘 다 뺌, 둘 다 꺼지면 원문 포함 비교만
enum BlockMatch {
    /// 단어 한 줄 → 조각들 (쉼표로 나눠 앞뒤 공백을 떼고 빈 조각은 버림)
    nonisolated static func terms(_ word: String) -> [String] {
        word.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 공백 판정 (JS \s와 같게: 유니코드 공백 + BOM, 단 U+0085는 제외)
    nonisolated private static func isSpace(_ u: Unicode.Scalar) -> Bool {
        (u.properties.isWhitespace && u.value != 0x85) || u.value == 0xFEFF
    }

    /// 글자(L)·결합 문자(M)·숫자(N) 판정 (JS \p{L}\p{M}\p{N}과 같은 범주)
    nonisolated private static func isWordScalar(_ u: Unicode.Scalar) -> Bool {
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    /// 비교용 정규화: 소문자화 후 (spaces면 공백 제거) (symbols면 글자·결합 문자·숫자·공백만 남김)
    nonisolated static func normalize(_ s: String, symbols: Bool, spaces: Bool) -> String {
        var out = String.UnicodeScalarView()
        for u in s.lowercased().unicodeScalars {
            let space = isSpace(u)
            if spaces && space { continue }
            if symbols && !space && !isWordScalar(u) { continue }
            out.append(u)
        }
        return String(out)
    }

    /// 조각(또는 차단 닉네임)에 특수문자(글자·결합 문자·숫자·공백이 아닌 문자)가 하나라도 있는지
    nonisolated static func hasSymbol(_ s: String) -> Bool {
        s.unicodeScalars.contains { !isSpace($0) && !isWordScalar($0) }
    }

    /// 본문에 조각들이 모두 들어 있는지. 조각마다 따로 판단:
    /// - 원문에 있으면 통과
    /// - 조각에 특수문자가 있으면 그 조각만은 특수문자를 빼지 않고(공백 무시만 적용) 비교 → `c++`가 `c`로 넓게 걸리지 않게
    /// - 그 밖의 조각은 켜진 옵션대로 정규화해서 비교
    /// - 정규화하면 빈 문자열이 되는 조각은 원문 비교만
    nonisolated static func textMatches(terms: [String], text: String, symbols: Bool, spaces: Bool) -> Bool {
        guard !terms.isEmpty, !text.isEmpty else { return false }
        let lower = text.lowercased()
        var normFull: String?     // 특수문자·공백 정규화 본문 (특수문자 무시 기준)
        var normSpace: String?    // 공백만 정규화한 본문 (특수문자가 든 조각 기준)
        for t in terms {
            let tl = t.lowercased()
            if lower.contains(tl) { continue }
            let sym = symbols && !hasSymbol(tl)
            guard sym || spaces else { return false }
            let nt = normalize(tl, symbols: sym, spaces: spaces)
            guard !nt.isEmpty else { return false }
            if sym {
                if normFull == nil { normFull = normalize(text, symbols: true, spaces: spaces) }
                guard normFull?.contains(nt) == true else { return false }
            } else {
                if normSpace == nil { normSpace = normalize(text, symbols: false, spaces: spaces) }
                guard normSpace?.contains(nt) == true else { return false }
            }
        }
        return true
    }

    /// 닉네임이 같은지. 기준은 차단 값(blocked)이 정함: 차단 값에 특수문자가 있으면 특수문자는 빼지 않고(공백 무시만),
    /// 없으면 켜진 옵션대로. 작성자 닉네임(actual)도 같은 기준으로 정규화해서 비교. 정규화 결과가 비면 원문 비교
    nonisolated static func nickMatches(blocked: String, actual: String, symbols: Bool, spaces: Bool) -> Bool {
        guard !blocked.isEmpty, !actual.isEmpty else { return false }
        if blocked == actual { return true }
        let sym = symbols && !hasSymbol(blocked)
        guard sym || spaces else { return false }
        let nb = normalize(blocked, symbols: sym, spaces: spaces)
        return !nb.isEmpty && nb == normalize(actual, symbols: sym, spaces: spaces)
    }
}

struct FilterSettings: Codable {
    var enabled = true
    var display: BlockDisplay = .collapse
    var users: [BlockedUser] = []
    var dccons: [BlockedDccon] = []
    var dcconPackages: [BlockedDcconPackage] = []
    var keywords: [BlockedKeyword] = []
    var hiddenElements: [HiddenElement] = []
    var hideBestNotice = true
    var advancedRules: [AdvancedBlockRule] = []
    var images: [BlockedImage] = []
    var imageBlockStyle: ImageBlockStyle = .blur
    /// 특수문자 끼워넣기 무시: 차단 단어·닉네임 비교 때 특수문자를 빼고 비교 (기본 꺼짐)
    var ignoreSymbols = false
    /// 공백 끼워넣기 무시: 차단 단어·닉네임 비교 때 공백을 빼고 비교 (기본 꺼짐, ignoreSymbols와 독립)
    var ignoreSpaces = false

    init() {}

    /// 예전 고급 차단(단어 OR)을 새 규칙(단어 AND)으로: 단어가 2개 이상인 예전 규칙은 단어마다 규칙 하나로 나눠 같은 동작을 유지
    static func migrateAdvanced(_ rules: [AdvancedBlockRule]) -> [AdvancedBlockRule] {
        rules.flatMap { r -> [AdvancedBlockRule] in
            if r.allWords || r.keywords.count <= 1 {
                var one = r
                one.allWords = true
                return [one]
            }
            return r.keywords.map { AdvancedBlockRule(kind: r.kind, value: r.value, keywords: [$0], gallery: r.gallery) }
        }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        display = try c.decodeIfPresent(BlockDisplay.self, forKey: .display) ?? .collapse
        users = try c.decodeIfPresent([BlockedUser].self, forKey: .users) ?? []
        dccons = try c.decodeIfPresent([BlockedDccon].self, forKey: .dccons) ?? []
        dcconPackages = try c.decodeIfPresent([BlockedDcconPackage].self, forKey: .dcconPackages) ?? []
        keywords = try c.decodeIfPresent([BlockedKeyword].self, forKey: .keywords) ?? []
        hiddenElements = try c.decodeIfPresent([HiddenElement].self, forKey: .hiddenElements) ?? []
        hideBestNotice = try c.decodeIfPresent(Bool.self, forKey: .hideBestNotice) ?? true
        advancedRules = FilterSettings.migrateAdvanced(try c.decodeIfPresent([AdvancedBlockRule].self, forKey: .advancedRules) ?? [])
        images = try c.decodeIfPresent([BlockedImage].self, forKey: .images) ?? []
        imageBlockStyle = try c.decodeIfPresent(ImageBlockStyle.self, forKey: .imageBlockStyle) ?? .blur
        ignoreSymbols = try c.decodeIfPresent(Bool.self, forKey: .ignoreSymbols) ?? false
        ignoreSpaces = try c.decodeIfPresent(Bool.self, forKey: .ignoreSpaces) ?? false
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

    /// 디시콘 패키지 차단 (같은 패키지가 이미 있으면 디시콘 목록만 합침)
    func addDcconPackage(pkg: String, name: String, keys: [String]) {
        guard !pkg.isEmpty, !keys.isEmpty else { return }
        if let i = settings.dcconPackages.firstIndex(where: { $0.pkg == pkg }) {
            var p = settings.dcconPackages[i]
            p.keys = Array(Set(p.keys + keys)).sorted()
            if p.name.isEmpty { p.name = name }
            settings.dcconPackages[i] = p
        } else {
            settings.dcconPackages.append(BlockedDcconPackage(pkg: pkg, name: name, keys: Array(Set(keys)).sorted()))
        }
    }

    /// 이 디시콘이 속한 차단된 패키지 (없으면 nil)
    /// 움직이는 디시콘(video)의 번호는 목록의 그림 번호 뒤에 8자가 붙은 값이라, 그 경우도 같은 디시콘으로 봄
    func dcconPackage(containing key: String) -> BlockedDcconPackage? {
        guard !key.isEmpty else { return nil }
        let image = String(key.dropLast(8))
        return settings.dcconPackages.first { $0.keys.contains(key) || $0.keys.contains(image) }
    }

    func removeDcconPackage(pkg: String) {
        settings.dcconPackages.removeAll { $0.pkg == pkg }
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
            case .nick: return BlockMatch.nickMatches(blocked: u.value, actual: nick, symbols: settings.ignoreSymbols, spaces: settings.ignoreSpaces)
            }
        }
    }

    /// 이 내용에 걸리는 차단 키워드들 (쉼표로 나눈 단어가 모두 들어 있어야 걸림)
    func blockedKeywords(in text: String, gallery: String?) -> [BlockedKeyword] {
        let symbols = settings.ignoreSymbols, spaces = settings.ignoreSpaces
        return settings.keywords.filter { k in
            GalleryScope.applies(k.gallery, gallery)
                && BlockMatch.textMatches(terms: BlockMatch.terms(k.word), text: text, symbols: symbols, spaces: spaces)
        }
    }

    /// 디시콘이 차단됐는지 (개별 차단 또는 속한 패키지 차단)
    func isDcconBlocked(_ key: String) -> Bool {
        !key.isEmpty && (settings.dccons.contains { $0.key == key } || dcconPackage(containing: key) != nil)
    }

    /// 페이지에 넘기는 차단 디시콘 번호 전체 (개별 + 패키지 안의 것)
    var dcconKeysForPage: [String] {
        Array(Set(settings.dccons.map(\.key) + settings.dcconPackages.flatMap(\.keys))).sorted()
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
    /// 쉼표(`,`·`，`)로 나눈 단어는 모두 들어 있어야 가림 (조각을 정리해서 ", "로 이어 저장)
    func addKeyword(_ word: String, gallery: String? = nil) {
        let terms = BlockMatch.terms(word)
        guard !terms.isEmpty else { return }
        let g = (gallery?.isEmpty ?? true) ? nil : gallery
        let k = BlockedKeyword(word: terms.joined(separator: ", "), gallery: g)
        guard !settings.keywords.contains(where: { $0.id == k.id }) else { return }
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
            case .nick: return BlockMatch.nickMatches(blocked: b.value, actual: nick, symbols: settings.ignoreSymbols, spaces: settings.ignoreSpaces)
            }
        }
    }

    // MARK: 웹페이지로 넘길 설정(JSON)

    var scriptConfigJSON: String { scriptConfig(detailPane: false) }

    /// detailPane: 분할 화면의 오른쪽(글) 화면 — 왼쪽에 목록이 이미 있어서 글목록 버튼을 숨김
    /// duo: 이 화면의 여백 설정 (분할이면 화면 끝에 닿은 쪽만). 없으면 창 전체 기준 값
    func scriptConfig(detailPane: Bool, duo: WebViewModel.DuoFlags? = nil) -> String {
        let s = settings
        let dict: [String: Any] = [
            "splitDetail": detailPane,
            "enabled": s.enabled,
            "mode": s.display.rawValue,
            "users": s.users.map { ["k": $0.kind.rawValue, "v": $0.value, "g": $0.gallery ?? ""] },
            "dccons": dcconKeysForPage,
            "dcconPkgs": settings.dcconPackages.map(\.pkg),
            "keywords": s.keywords.map { ["t": BlockMatch.terms($0.word).map { $0.lowercased() }, "g": $0.gallery ?? ""] as [String: Any] },
            "ignoreSymbols": s.ignoreSymbols,
            "ignoreSpaces": s.ignoreSpaces,
            "advRules": s.advancedRules.map { ["k": $0.kind.rawValue, "v": $0.value, "w": $0.keywords.flatMap { BlockMatch.terms($0) }.map { $0.lowercased() }, "g": $0.gallery ?? ""] as [String: Any] },
            "selectors": s.hiddenElements.map(\.selector),
            "hideBest": s.hideBestNotice,
            "dockComment": Profile.defaults.object(forKey: "dockComment") as? Bool ?? true,
            "fontSizes": ["title": Profile.defaults.integer(forKey: "textSizeTitle"), "body": Profile.defaults.integer(forKey: "textSizeBody"), "list": Profile.defaults.integer(forKey: "textSizeList")],   // 글자 크기 (0 = 기본)
            "hideHeader": Profile.defaults.object(forKey: "hideSiteHeader") as? Bool ?? true,
            "homeRank": Profile.defaults.object(forKey: "homeRankOnly") as? Bool ?? true,
            "hideDory": Profile.defaults.object(forKey: "hideDory") as? Bool ?? true,
            "deferImages": DeferredImages.enabled,   // 본문 이미지 숨기기 (눌러서 불러오기)
            "hideImgComment": Profile.defaults.object(forKey: "hideImgCommentButton") as? Bool ?? false,   // 본문 사진 위 디시 기본 '댓글' 버튼 숨김
            "imgNum": Profile.defaults.object(forKey: "showImgNumber") as? Bool ?? true,   // 본문 사진 위 디시 기본 '이미지 순서' 번호 보기
            "imgNumOnAt": Profile.defaults.double(forKey: "showImgNumberOnAt"),   // 앱에서 다시 켠 시각 (디시 쪽 설정이 꺼져 있으면 한 번 켜 줌)
            "nativeComment": Profile.defaults.object(forKey: "nativeComment") as? Bool ?? true,   // 앱 댓글 입력창
            "bgComment": BackgroundComment.enabled,   // 댓글 등록 요청은 앱이 보냄 (글을 옮겨도 끊기지 않게)
            "pinComment": CommentPin.enabled,   // 컨트롤바가 세로 막대일 때 댓글 입력칸을 아래에 고정
            "myId": CredentialStore.currentAccountID ?? "",
            "adBlock": AdBlock.enabled,   // 광고 자리 숨기기
            "webFont": (FontStore.shared.webFontConfig as Any?) ?? NSNull(),   // 고른 글꼴의 페이지 주소 (없으면 null = 기본 글꼴)
            "adFilterCSS": AdBlock.enabled ? AdFilterStore.shared.cssText : "",   // 원격 필터(애드가드 디시 필터)의 숨김 규칙 — 광고차단이 켜졌을 때만
            "floatBar": Profile.defaults.object(forKey: "showFloatingBar") as? Bool ?? true,   // 세로 막대가 댓글 등록 버튼을 가리지 않게
            "memos": MemoStore.shared.memos.map { ["k": $0.kind.rawValue, "v": $0.value, "t": $0.text, "g": $0.gallery ?? ""] },   // 유저 메모
            "autoMemo": AutoMemo.scriptValue,   // 자동메모 ("" 꺼짐 / all / gallery / selected)
            "showIdCode": IdCode.enabled,   // 고닉 식별코드 보기 (메모 없는 고닉의 메모 자리에 아이디 표시)
            "autoMemoGalleries": AutoMemo.selectedIDs,   // "선택한 갤러리만"에서 고른 갤러리
            "anon": ["nick": AnonStore.nick, "pw": AnonStore.password],   // 유동 닉/비번 자동 채우기 (모든 갤러리 공통)
            "anonG": AnonStore.galleryScriptValue,   // 갤러리별 유동 닉/비번 (있으면 공통보다 우선)
            "duoFlip": duo?.flip ?? BrowserView.windowLeftColumn,   // 돌려서 왼쪽에 생긴 줄 → 글자 여백을 오른쪽으로 뒤집음
            "duoFlipR": duo?.flipR ?? BrowserView.windowLeftColumn,   // 뒤집힌 줄의 오른쪽 여백은 화면 오른쪽 끝에 닿을 때만
            "duoCol": duo?.col ?? BrowserView.hasSideColumnOnly,   // 듀오 옆 세로 줄이 있으면 글자는 줄 안쪽으로 (이 화면이 그 줄 쪽 끝에 닿을 때)
            "duoOff": BrowserView.duoHorizontalBarNow,   // 듀오에서 컨트롤바를 가로로 쓰는 중 → 옆 줄 여백을 붙이지 않음 (화면 끝까지)
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
