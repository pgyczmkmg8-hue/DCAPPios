import SwiftUI
import UniformTypeIdentifiers

/// 백업 파일 내용 (JSON). 계정 비밀번호는 보안상 넣지 않아요.
struct BackupFile: Codable {
    var version = 1
    var createdAt: Date
    var favorites: [Gallery]
    var filters: FilterSettings
    var savedPosts: [SavedPost]
    var folders: [PostFolder]
    var archives: [String: Data]?          // 보관한 글 본문 사본 (파일 이름 → 내용)
    var drafts: [Draft]
    var autoImages: AutoImageSettings
    var autoImageFiles: [String: Data]?    // 자짤 사진 (파일 이름 → 내용)
    var prefs: [String: Bool]
    var stringPrefs: [String: String]? = nil     // 테마 등 (예전 백업에는 없음)
    var memos: [UserMemo]? = nil                 // 유저 메모 (예전 백업에는 없음)
    var recentSearches: [String]
    var visited: [VisitedGallery]? = nil
}

@MainActor
enum BackupManager {
    /// 앱 설정 스위치들 (UserDefaults)
    static let prefKeys = ["autoLogin", "dockComment", "fullSwipeBack", "hideSiteHeader", "homeRankOnly", "showFloatingBar", "adFilter", "hideDory", "alarmBanner"]
    /// 문자열 설정들 (UserDefaults)
    static let stringPrefKeys = ["appTheme"]

    static func makeBackup(favorites: FavoritesStore, includeArchives: Bool, includeImages: Bool) throws -> URL {
        let posts = SavedPostStore.shared
        let auto = AutoImageStore.shared

        var archives: [String: Data]?
        if includeArchives {
            var dict: [String: Data] = [:]
            for p in posts.posts {
                if let f = p.archiveFile, let d = try? Data(contentsOf: posts.archiveDir.appendingPathComponent(f)) {
                    dict[f] = d
                }
            }
            archives = dict
        }

        var images: [String: Data]?
        if includeImages {
            var dict: [String: Data] = [:]
            for img in auto.settings.images {
                if let d = try? Data(contentsOf: auto.fileURL(img)) { dict[img.filename] = d }
            }
            images = dict
        }

        var prefs: [String: Bool] = [:]
        for k in prefKeys {
            if let v = UserDefaults.standard.object(forKey: k) as? Bool { prefs[k] = v }
        }

        let backup = BackupFile(
            createdAt: Date(),
            favorites: favorites.items,
            filters: FilterStore.shared.settings,
            savedPosts: posts.posts,
            folders: posts.folders,
            archives: archives,
            drafts: DraftStore.shared.drafts,
            autoImages: auto.settings,
            autoImageFiles: images,
            prefs: prefs,
            stringPrefs: Dictionary(uniqueKeysWithValues: stringPrefKeys.compactMap { k in
                UserDefaults.standard.string(forKey: k).map { (k, $0) }
            }),
            memos: MemoStore.shared.memos,
            recentSearches: UserDefaults.standard.stringArray(forKey: "recentSearches") ?? [],
            visited: VisitedStore.shared.items
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DCApp-백업-\(f.string(from: Date())).json")
        try data.write(to: url)
        return url
    }

    static func read(_ url: URL) throws -> BackupFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }

    /// 백업 내용으로 지금 데이터를 바꿈 (계정 목록은 건드리지 않음)
    static func restore(_ b: BackupFile, favorites: FavoritesStore) {
        favorites.replaceAll(b.favorites)
        FilterStore.shared.settings = b.filters

        let posts = SavedPostStore.shared
        if let archives = b.archives {
            for (name, data) in archives {
                try? data.write(to: posts.archiveDir.appendingPathComponent(name))
            }
        }
        posts.replaceAll(posts: b.savedPosts, folders: b.folders)

        DraftStore.shared.replaceAll(b.drafts)

        let auto = AutoImageStore.shared
        if let files = b.autoImageFiles {
            for (name, data) in files {
                try? data.write(to: auto.folder.appendingPathComponent(name))
            }
        }
        auto.settings = b.autoImages

        for (k, v) in b.prefs { UserDefaults.standard.set(v, forKey: k) }
        for (k, v) in b.stringPrefs ?? [:] { UserDefaults.standard.set(v, forKey: k) }
        UserDefaults.standard.set(b.recentSearches, forKey: "recentSearches")
        if let v = b.visited { VisitedStore.shared.replaceAll(v) }
        if let m = b.memos { MemoStore.shared.replaceAll(m) }

        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
    }
}

// MARK: - 설정 → 백업 화면

struct BackupView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @AppStorage("backupIncludeArchives") private var includeArchives = true
    @AppStorage("backupIncludeImages") private var includeImages = true

    @State private var backupURL: URL?
    @State private var isWorking = false
    @State private var showImporter = false
    @State private var pending: BackupFile?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("보관한 글 본문 사본 포함", isOn: $includeArchives)
                Toggle("자짤 사진 포함", isOn: $includeImages)
                Button {
                    makeBackup()
                } label: {
                    Label(isWorking ? "만드는 중…" : "백업 파일 만들기", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(isWorking)
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("백업 파일 저장 / 공유", systemImage: "square.and.arrow.up")
                    }
                    Text(backupURL.lastPathComponent + " · " + fileSize(backupURL))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("백업")
            } footer: {
                Text("즐겨찾는 갤러리, 보관한 글과 폴더, 임시저장, 차단 목록, 숨긴 요소, 자짤, 앱 설정이 파일 하나에 담겨요. '저장 / 공유'에서 '파일에 저장'을 고르면 iCloud Drive 등에 보관할 수 있어요.\n계정 비밀번호는 보안을 위해 포함하지 않아요.")
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("백업 파일에서 복원", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("복원")
            } footer: {
                Text("복원하면 지금 앱에 있는 위 항목들이 백업 파일 내용으로 바뀌어요. (저장된 계정은 그대로 유지돼요)")
            }

            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("백업 / 복원")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do { pending = try BackupManager.read(url) }
                catch { message = "백업 파일을 읽지 못했어요. DCApp에서 만든 백업 파일인지 확인해주세요." }
            case .failure:
                break
            }
        }
        .confirmationDialog("이 백업으로 복원할까요?",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible,
                            presenting: pending) { b in
            Button("복원하기", role: .destructive) {
                BackupManager.restore(b, favorites: favorites)
                message = "복원했어요. (\(b.createdAt.shortKorean)에 만든 백업)"
            }
            Button("취소", role: .cancel) {}
        } message: { b in
            Text("\(b.createdAt.shortKorean) 백업 · 갤러리 \(b.favorites.count)개, 보관한 글 \(b.savedPosts.count)개, 임시저장 \(b.drafts.count)개\n지금 데이터가 이 내용으로 바뀌어요.")
        }
    }

    private func makeBackup() {
        isWorking = true
        defer { isWorking = false }
        do {
            backupURL = try BackupManager.makeBackup(favorites: favorites,
                                                     includeArchives: includeArchives,
                                                     includeImages: includeImages)
            message = nil
        } catch {
            message = "백업 파일을 만들지 못했어요: \(error.localizedDescription)"
        }
    }

    private func fileSize(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
