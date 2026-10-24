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
    private static let service = "DCApp.dcinside.accounts"
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
        if let old = read(legacyService, "default"),
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
        get { UserDefaults.standard.string(forKey: currentKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: currentKey)
            NotificationCenter.default.post(name: DC.credentialsChanged, object: nil)
        }
    }
}

/// 디시 로그인 상태(쿠키 등) 지우기
enum DCSession {
    @MainActor
    static func clear(notify: Bool) async {
        let store = WKWebsiteDataStore.default()
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
    private static let service = "DCApp.dcinside.anon"
    private static let account = "password"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var nick: String {
        get { UserDefaults.standard.string(forKey: nickKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: nickKey) }
    }

    static var password: String {
        get {
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
                  let d = item as? Data else { return "" }
            return String(decoding: d, as: UTF8.self)
        }
        set {
            SecItemDelete(query as CFDictionary)
            guard !newValue.isEmpty else { return }
            var add = query
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
