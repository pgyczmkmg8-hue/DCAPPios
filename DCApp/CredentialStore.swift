import Foundation
import SwiftUI   // Array.move(fromOffsets:toOffset:)는 SwiftUI에 들어 있음
import Security
import WebKit

struct LoginCredential: Codable, Equatable, Identifiable {
    var id: String          // 디시 아이디
    var password: String
}

/// 여러 계정을 iOS 키체인에 저장합니다.
/// (암호화되어 저장되며, 이 기기에서 잠금 해제 상태일 때만 읽을 수 있고, 백업/다른 기기로 넘어가지 않습니다)
/// 목록의 맨 앞 계정 = 가장 최근에 쓴 계정(기본 계정)
enum CredentialStore {
    private static let service = "DCApp.dcinside.accounts" + Profile.keychainSuffix
    private static let account = "list"
    private static let legacyService = "DCApp.dcinside.login"   // 예전 버전(계정 1개) 저장 위치
    private static let currentKey = "currentAccountID"

    private static func query(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read(_ service: String, _ account: String) -> Data? {
        var q = query(service, account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    /// 저장된 모든 계정 (최근 사용 순)
    static func all() -> [LoginCredential] {
        if let data = read(service, account),
           let list = try? JSONDecoder().decode([LoginCredential].self, from: data) {
            return list
        }
        // 예전 버전에서 저장한 계정 1개가 있으면 옮겨오기
        if Profile.isPrimary, let old = read(legacyService, "default"),
           let c = try? JSONDecoder().decode(LoginCredential.self, from: old) {
            saveAll([c], notify: false)
            SecItemDelete(query(legacyService, "default") as CFDictionary)
            return [c]
        }
        return []
    }

    private static func saveAll(_ list: [LoginCredential], notify: Bool = true) {
        SecItemDelete(query(service, account) as CFDictionary)
        if !list.isEmpty, let data = try? JSONEncoder().encode(list) {
            var add = query(service, account)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
        if notify { NotificationCenter.default.post(name: DC.credentialsChanged, object: nil) }
    }

    /// 기본 계정 (로그인 화면 자동 입력에 사용)
    static func load() -> LoginCredential? { all().first }

    static func contains(_ c: LoginCredential) -> Bool { all().contains(c) }

    /// 추가 또는 비밀번호 갱신 → 맨 앞(기본 계정)으로
    static func save(_ c: LoginCredential) {
        var list = all().filter { $0.id != c.id }
        list.insert(c, at: 0)
        saveAll(list)
    }

    static func remove(id: String) {
        saveAll(all().filter { $0.id != id })
        if currentAccountID == id { currentAccountID = nil }
    }

    static func move(from: IndexSet, to: Int) {
        var list = all()
        list.move(fromOffsets: from, toOffset: to)
        saveAll(list)
    }

    /// 이 앱에서 마지막으로 로그인한 계정 (표시용)
    static var currentAccountID: String? {
        get { Profile.defaults.string(forKey: currentKey) }
        set {
            Profile.defaults.set(newValue, forKey: currentKey)
            NotificationCenter.default.post(name: DC.credentialsChanged, object: nil)
        }
    }
}

/// 디시 로그인 상태(쿠키 등) 지우기
enum DCSession {
    @MainActor
    static func clear(notify: Bool) async {
        let store = Profile.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records.filter { $0.displayName.contains("dcinside") })
        CredentialStore.currentAccountID = nil
        if notify { NotificationCenter.default.post(name: DC.sessionChanged, object: nil) }
    }
}

/// 유동(비로그인)으로 글·댓글 쓸 때의 닉네임/비밀번호.
/// 디시는 이걸 사이트 저장소에 두는데, 로그인했다 풀면(사이트 데이터 삭제) 같이 지워져서 앱이 따로 기억함.
/// 닉네임은 UserDefaults, 비밀번호는 키체인.
enum AnonStore {
    private static let nickKey = "anonNick"
    private static let galleryNickKey = "anonNickByGallery"
    private static let service = "DCApp.dcinside.anon" + Profile.keychainSuffix
    private static let account = "password"

    private static func query(_ acc: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: acc]
    }

    private static func readKeychain(_ acc: String) -> String {
        var q = query(acc)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let d = item as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    private static func writeKeychain(_ acc: String, _ value: String) {
        SecItemDelete(query(acc) as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query(acc)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: 모든 갤러리 공통

    static var nick: String {
        get { Profile.defaults.string(forKey: nickKey) ?? "" }
        set { Profile.defaults.set(newValue, forKey: nickKey) }
    }

    static var password: String {
        get { readKeychain(account) }
        set { writeKeychain(account, newValue) }
    }

    // MARK: 갤러리별 (있으면 공통보다 우선)

    private static var galleryNicks: [String: String] {
        get { Profile.defaults.dictionary(forKey: galleryNickKey) as? [String: String] ?? [:] }
        set { Profile.defaults.set(newValue, forKey: galleryNickKey) }
    }

    private static func gid(_ g: String) -> String { DCGalleryID.bare(g) }

    /// 갤러리별 설정이 있는 갤러리 ID들
    static var galleryIDs: [String] { galleryNicks.keys.sorted() }

    static func hasGallery(_ g: String) -> Bool { galleryNicks[gid(g)] != nil }

    static func galleryNick(_ g: String) -> String { galleryNicks[gid(g)] ?? "" }
    static func galleryPassword(_ g: String) -> String { readKeychain("\(account)#\(gid(g))") }

    /// 그 갤러리의 설정을 저장(없으면 새로 만듦)
    static func setGallery(_ g: String, nick n: String, password p: String) {
        var d = galleryNicks
        d[gid(g)] = n
        galleryNicks = d
        writeKeychain("\(account)#\(gid(g))", p)
    }

    static func removeGallery(_ g: String) {
        var d = galleryNicks
        d[gid(g)] = nil
        galleryNicks = d
        writeKeychain("\(account)#\(gid(g))", "")
    }

    /// 갤러리별 설정이 있으면 그것, 없으면 공통 설정
    static func nick(for g: String?) -> String {
        if let g, let n = galleryNicks[gid(g)], !n.isEmpty { return n }
        return nick
    }

    static func password(for g: String?) -> String {
        if let g {
            let p = galleryPassword(g)
            if !p.isEmpty { return p }
        }
        return password
    }

    /// 글쓰기·댓글 도구에서 바꾼 값 → 그 갤러리 설정 갱신 (닉네임이 잠겨 있으면 닉네임은 건드리지 않음)
    static func update(gallery g: String?, nick n: String?, password p: String) {
        guard let g, !g.isEmpty else {
            if let n { nick = n }
            password = p
            return
        }
        setGallery(g, nick: n ?? galleryNick(g), password: p)
    }

    /// 페이지 스크립트에 넘길 갤러리별 값
    static var galleryScriptValue: [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        for g in galleryIDs { out[g] = ["nick": galleryNick(g), "pw": galleryPassword(g)] }
        return out
    }
}
