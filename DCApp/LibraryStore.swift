import SwiftUI
import Combine

// MARK: - 보관한 글

struct SavedPost: Codable, Identifiable, Hashable {
    var id: UUID
    var url: URL
    var title: String
    var galleryID: String
    var savedAt: Date
    var archiveFile: String?     // 본문 사본(.webarchive) 파일 이름. 원글이 지워져도 볼 수 있음
    var folderID: UUID?          // 보관함 폴더 (nil = 분류 없음)
}

struct PostFolder: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
}

@MainActor
final class SavedPostStore: ObservableObject {
    static let shared = SavedPostStore()

    @Published private(set) var posts: [SavedPost] = []
    @Published private(set) var folders: [PostFolder] = []
    private let key = "savedPosts"
    private let foldersKey = "savedPostFolders"
    let archiveDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        archiveDir = base.appendingPathComponent("SavedPosts", isDirectory: true)
        try? FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([SavedPost].self, from: data) {
            posts = saved
        }
        if let data = UserDefaults.standard.data(forKey: foldersKey),
           let saved = try? JSONDecoder().decode([PostFolder].self, from: data) {
            folders = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(posts) {
            UserDefaults.standard.set(data, forKey: key)
        }
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: foldersKey)
        }
    }

    func contains(url: URL) -> Bool {
        posts.contains { Self.sameDocument($0.url, url) }
    }

    func post(for url: URL) -> SavedPost? {
        posts.first { Self.sameDocument($0.url, url) }
    }

    // MARK: 폴더

    @discardableResult
    func addFolder(_ name: String) -> UUID? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        let id = UUID()
        folders.append(PostFolder(id: id, name: n))
        save()
        return id
    }

    func renameFolder(_ f: PostFolder, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = folders.firstIndex(where: { $0.id == f.id }) else { return }
        folders[i].name = n
        save()
    }

    /// 폴더 삭제 (안에 있던 글은 지우지 않고 "분류 없음"으로)
    func deleteFolder(_ f: PostFolder) {
        folders.removeAll { $0.id == f.id }
        for i in posts.indices where posts[i].folderID == f.id { posts[i].folderID = nil }
        save()
    }

    func move(_ post: SavedPost, to folderID: UUID?) {
        guard let i = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[i].folderID = folderID
        save()
    }

    func folderName(_ id: UUID?) -> String {
        guard let id else { return "분류 없음" }
        return folders.first { $0.id == id }?.name ?? "분류 없음"
    }

    /// 백업 복원용: 통째로 바꾸기
    func replaceAll(posts: [SavedPost], folders: [PostFolder]) {
        self.posts = posts
        self.folders = folders
        save()
    }

    /// 보관 (같은 글이면 사본만 새로 갱신)
    /// folderID: 넣을 폴더. keepFolder가 true면 이미 보관된 글의 폴더는 그대로 둠
    func add(url: URL, title: String, galleryID: String, archive: Data?,
             folderID: UUID? = nil, keepFolder: Bool = true) {
        var fileName: String?
        if let archive {
            let name = "\(UUID().uuidString).webarchive"
            if (try? archive.write(to: archiveDir.appendingPathComponent(name))) != nil { fileName = name }
        }
        if let i = posts.firstIndex(where: { Self.sameDocument($0.url, url) }) {
            if let old = posts[i].archiveFile, fileName != nil {
                try? FileManager.default.removeItem(at: archiveDir.appendingPathComponent(old))
            }
            posts[i].title = title
            posts[i].savedAt = Date()
            if !keepFolder { posts[i].folderID = folderID }
            if fileName != nil { posts[i].archiveFile = fileName }
            let item = posts.remove(at: i)
            posts.insert(item, at: 0)
        } else {
            posts.insert(SavedPost(id: UUID(), url: url, title: title, galleryID: galleryID,
                                   savedAt: Date(), archiveFile: fileName, folderID: folderID), at: 0)
        }
        save()
    }

    func remove(_ post: SavedPost) {
        if let f = post.archiveFile { try? FileManager.default.removeItem(at: archiveDir.appendingPathComponent(f)) }
        posts.removeAll { $0.id == post.id }
        save()
    }

    func remove(at offsets: IndexSet) {
        for i in offsets { if let f = posts[i].archiveFile { try? FileManager.default.removeItem(at: archiveDir.appendingPathComponent(f)) } }
        posts.remove(atOffsets: offsets)
        save()
    }

    func archiveURL(_ post: SavedPost) -> URL? {
        post.archiveFile.map { archiveDir.appendingPathComponent($0) }
    }

    /// 글 보기 화면이면 (갤러리ID, 글번호)
    ///  - https://m.dcinside.com/board/{id}/{no}
    ///  - https://m.dcinside.com/mini/{id}/{no}
    ///  - https://gall.dcinside.com/.../view/?id={id}&no={no}
    nonisolated static func postInfo(_ url: URL) -> (galleryID: String, no: String)? {
        guard let host = url.host?.lowercased(), host.hasSuffix("dcinside.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "m.dcinside.com", parts.count >= 3, ["board", "mini", "person"].contains(parts[0]),
           parts[2].allSatisfy(\.isNumber) {
            return (parts[1], parts[2])
        }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let id = q.first(where: { $0.name == "id" })?.value,
           let no = q.first(where: { $0.name == "no" })?.value, !no.isEmpty {
            return (id, no)
        }
        return nil
    }

    nonisolated static func sameDocument(_ a: URL, _ b: URL) -> Bool {
        if let x = postInfo(a), let y = postInfo(b) { return x.galleryID == y.galleryID && x.no == y.no }
        return a.absoluteString == b.absoluteString
    }
}

// MARK: - 임시저장

struct Draft: Codable, Identifiable, Hashable {
    var id: UUID
    var galleryID: String
    var title: String
    var body: String
    var preview: String
    var isHTML: Bool
    var isAuto: Bool          // 자동 저장(갤러리마다 1개, 계속 덮어씀)
    var updatedAt: Date
    var writeURL: URL?        // 저장할 때의 글쓰기 화면 주소 (불러올 때 이 화면을 다시 엶)
}

@MainActor
final class DraftStore: ObservableObject {
    static let shared = DraftStore()

    @Published private(set) var drafts: [Draft] = []
    private let key = "drafts"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Draft].self, from: data) {
            drafts = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(drafts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 직접 저장 → 새 항목
    func addManual(galleryID: String, title: String, body: String, preview: String, isHTML: Bool, writeURL: URL?) {
        drafts.insert(Draft(id: UUID(), galleryID: galleryID, title: title, body: body, preview: preview,
                            isHTML: isHTML, isAuto: false, updatedAt: Date(), writeURL: writeURL), at: 0)
        save()
    }

    /// 자동 저장 → 갤러리별 자동 저장 칸 하나를 덮어씀
    func autosave(galleryID: String, title: String, body: String, preview: String, isHTML: Bool, writeURL: URL?) {
        drafts.removeAll { $0.isAuto && $0.galleryID == galleryID }
        drafts.insert(Draft(id: UUID(), galleryID: galleryID, title: title, body: body, preview: preview,
                            isHTML: isHTML, isAuto: true, updatedAt: Date(), writeURL: writeURL), at: 0)
        save()
    }

    /// 이 갤러리 자동 저장본 지우기 (글을 등록했을 때)
    func removeAuto(galleryID: String) {
        drafts.removeAll { $0.isAuto && $0.galleryID == galleryID }
        save()
    }

    func remove(_ d: Draft) {
        drafts.removeAll { $0.id == d.id }
        save()
    }

    /// 백업 복원용
    func replaceAll(_ list: [Draft]) {
        drafts = list
        save()
    }

    func remove(at offsets: IndexSet) {
        drafts.remove(atOffsets: offsets)
        save()
    }

    /// 여러 개 한꺼번에 삭제 (불러오기 창의 '선택 → 삭제')
    func remove(ids: Set<UUID>) {
        drafts.removeAll { ids.contains($0.id) }
        save()
    }

    /// 이 갤러리 것 먼저, 그다음 나머지 (각각 최신순)
    func sorted(for galleryID: String?) -> [Draft] {
        guard let galleryID else { return drafts }
        return drafts.filter { $0.galleryID == galleryID } + drafts.filter { $0.galleryID != galleryID }
    }
}

extension Date {
    var shortKorean: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = Calendar.current.isDateInToday(self) ? "a h:mm" : "M월 d일 a h:mm"
        return f.string(from: self)
    }
}
