import SwiftUI
import WebKit

/// 프로필 하나 (이름은 사용자가 정함)
struct ProfileInfo: Codable, Identifiable, Equatable {
    var id: String
    var name: String
}

/// 다중 프로필: 프로필마다 설정·기록·보관함·저장된 계정·디시 로그인(쿠키)이 완전히 따로.
/// - 첫 프로필('기본')은 예전부터 쓰던 저장 위치를 그대로 씀 → 업데이트해도 기존 데이터가 그대로 첫 프로필이 됨
/// - 새 프로필은 별도 UserDefaults 묶음 / 별도 폴더 / 별도 키체인 항목 / 별도 웹 저장소를 씀
/// - 프로필을 바꾸면 앱을 다시 시작함 (싱글톤 저장소들이 시작할 때 읽으므로)
/// 프로필 목록·현재 프로필 번호만 공통 저장소(UserDefaults.standard)에 둠
nonisolated enum Profile {
    static let primaryID = "main"
    private static let listKey = "profiles.list.v1"
    private static let activeKey = "profiles.active.v1"
    private static let shared = UserDefaults.standard

    /// 앱을 켠 뒤로는 바뀌지 않는 현재 프로필 번호
    static let activeID: String = {
        let id = shared.string(forKey: activeKey) ?? primaryID
        return id == primaryID || all.contains(where: { $0.id == id }) ? id : primaryID
    }()
    static var isPrimary: Bool { activeID == primaryID }

    /// 프로필 설정·기록 저장소 (@AppStorage·UserDefaults 모두 이걸 씀)
    static let defaults: UserDefaults = {
        guard activeID != primaryID, let d = UserDefaults(suiteName: "DCApp.profile.\(activeID)") else { return .standard }
        return d
    }()

    /// 파일 저장 위치 (첫 프로필은 예전 위치 그대로)
    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard activeID != primaryID else { return base }
        let d = base.appendingPathComponent("Profiles", isDirectory: true).appendingPathComponent(activeID, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// 키체인 항목 이름 뒤에 붙임 (첫 프로필은 그대로)
    static var keychainSuffix: String { activeID == primaryID ? "" : ".\(activeID)" }

    /// 웹(디시 로그인 쿠키 등) 저장소. 첫 프로필은 기본 저장소 그대로 → 로그인 유지
    static let websiteDataStore: WKWebsiteDataStore = {
        guard activeID != primaryID, let u = UUID(uuidString: activeID) else { return .default() }
        return WKWebsiteDataStore(forIdentifier: u)
    }()

    // MARK: 목록

    static var all: [ProfileInfo] {
        var list: [ProfileInfo] = []
        if let data = shared.data(forKey: listKey), let l = try? JSONDecoder().decode([ProfileInfo].self, from: data) { list = l }
        if !list.contains(where: { $0.id == primaryID }) { list.insert(ProfileInfo(id: primaryID, name: "기본 프로필"), at: 0) }
        return list
    }

    static var activeName: String { all.first(where: { $0.id == activeID })?.name ?? "기본 프로필" }

    private static func save(_ list: [ProfileInfo]) {
        if let data = try? JSONEncoder().encode(list) { shared.set(data, forKey: listKey) }
    }

    @discardableResult
    static func add(name: String) -> ProfileInfo {
        var list = all
        let p = ProfileInfo(id: UUID().uuidString, name: name)
        list.append(p)
        save(list)
        return p
    }

    static func rename(_ id: String, to name: String) {
        var list = all
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].name = name; save(list) }
    }

    /// 다음에 켤 때 쓸 프로필 지정 (바로 바뀌지는 않음 — 앱을 다시 시작해야 함)
    static func setActive(_ id: String) { shared.set(id, forKey: activeKey) }

    /// 프로필 지우기 (현재 쓰는 프로필과 첫 프로필은 못 지움). 설정·기록·폴더·키체인·웹 저장소를 모두 지움
    static func delete(_ id: String) async {
        guard id != primaryID, id != activeID else { return }
        save(all.filter { $0.id != id })
        UserDefaults(suiteName: "DCApp.profile.\(id)")?.removePersistentDomain(forName: "DCApp.profile.\(id)")
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: base.appendingPathComponent("Profiles/\(id)", isDirectory: true))
        for service in ["DCApp.dcinside.accounts.\(id)", "DCApp.dcinside.anon.\(id)"] {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        }
        if let u = UUID(uuidString: id) { try? await WKWebsiteDataStore.remove(forIdentifier: u) }
    }
}

// MARK: - 화면

struct ProfileView: View {
    @State private var profiles = Profile.all
    @State private var newName = ""
    @State private var showAdd = false
    @State private var renameTarget: ProfileInfo?
    @State private var renameText = ""
    @State private var switchTarget: ProfileInfo?
    @State private var deleteTarget: ProfileInfo?

    var body: some View {
        List {
            Section {
                ForEach(profiles) { p in
                    Button {
                        if p.id != Profile.activeID { switchTarget = p }
                    } label: {
                        HStack {
                            Text(p.name).foregroundStyle(.primary)
                            Spacer()
                            if p.id == Profile.activeID {
                                Image(systemName: "checkmark").foregroundStyle(DCTheme.accent)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if p.id != Profile.primaryID && p.id != Profile.activeID {
                            Button("삭제", role: .destructive) { deleteTarget = p }
                        }
                        Button("이름") { renameText = p.name; renameTarget = p }.tint(.gray)
                    }
                }
            } header: {
                Text("프로필")
            } footer: {
                Text("프로필마다 설정·테마·컨트롤바, 방문·즐겨찾기 갤러리, 보관함, 작성글·읽은글 기록, 저장된 계정, 디시 로그인이 완전히 따로예요. 프로필을 바꾸면 앱이 종료되고, 다시 열면 그 프로필로 시작해요. 왼쪽으로 밀어 이름을 바꾸거나 지울 수 있어요(지금 쓰는 프로필과 기본 프로필은 지울 수 없어요).")
            }
            Section {
                Button { newName = ""; showAdd = true } label: {
                    Label("새 프로필 만들기", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("프로필")
        .navigationBarTitleDisplayMode(.inline)
        .alert("새 프로필", isPresented: $showAdd) {
            TextField("이름", text: $newName)
            Button("만들기") {
                let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                Profile.add(name: n.isEmpty ? "프로필 \(profiles.count + 1)" : n)
                profiles = Profile.all
            }
            Button("취소", role: .cancel) {}
        }
        .alert("이름 바꾸기", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("이름", text: $renameText)
            Button("바꾸기") {
                let n = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let t = renameTarget, !n.isEmpty { Profile.rename(t.id, to: n); profiles = Profile.all }
            }
            Button("취소", role: .cancel) {}
        }
        .alert("'\(switchTarget?.name ?? "")' 프로필로 바꿀까요?", isPresented: Binding(get: { switchTarget != nil }, set: { if !$0 { switchTarget = nil } })) {
            Button("바꾸고 종료") {
                if let t = switchTarget {
                    Profile.setActive(t.id)
                    UserDefaults.standard.synchronize()
                    exit(0)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("앱이 종료돼요. 다시 열면 그 프로필로 시작해요.")
        }
        .alert("'\(deleteTarget?.name ?? "")' 프로필을 지울까요?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("지우기", role: .destructive) {
                if let t = deleteTarget { Task { await Profile.delete(t.id); profiles = Profile.all } }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 프로필의 설정·기록·보관함·저장된 계정·로그인이 모두 지워져요. 되돌릴 수 없어요.")
        }
    }
}
