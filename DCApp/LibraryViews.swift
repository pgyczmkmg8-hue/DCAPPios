import SwiftUI
import WebKit

// MARK: - 보관한 글 목록 (폴더별)

/// 위쪽 폴더 칩에서 고른 범위
enum PostFolderFilter: Hashable {
    case all, unfiled, folder(UUID)
}

struct SavedPostsList: View {
    @ObservedObject private var store = SavedPostStore.shared
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var router: AppRouter

    @State private var filter: PostFolderFilter = .all
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renamingFolder: PostFolder?
    @State private var renameText = ""
    @State private var deletingFolder: PostFolder?

    private var visiblePosts: [SavedPost] {
        switch filter {
        case .all: store.posts
        case .unfiled: store.posts.filter { $0.folderID == nil }
        case .folder(let id): store.posts.filter { $0.folderID == id }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(visiblePosts) { p in
                    NavigationLink {
                        SavedPostReader(post: p)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.title.isEmpty ? "(제목 없음)" : p.title).lineLimit(2)
                            HStack(spacing: 4) {
                                if p.folderID != nil {
                                    Label(store.folderName(p.folderID), systemImage: "folder")
                                        .labelStyle(.titleAndIcon)
                                    Text("·")
                                }
                                Text(galleryName(p.galleryID))
                                Text("·")
                                Text(p.savedAt.shortKorean)
                                if p.archiveFile != nil {
                                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { router.open(p.url) } label: { Label("원본", systemImage: "safari") }
                            .tint(.blue)
                    }
                    .contextMenu {
                        Menu {
                            Button("분류 없음") { store.move(p, to: nil) }
                            ForEach(store.folders) { f in
                                Button(f.name) { store.move(p, to: f.id) }
                            }
                        } label: {
                            Label("폴더로 옮기기", systemImage: "folder")
                        }
                        Button { router.open(p.url) } label: { Label("원본 열기", systemImage: "safari") }
                        Button(role: .destructive) { store.remove(p) } label: { Label("삭제", systemImage: "trash") }
                    }
                }
                .onDelete { offsets in
                    let list = visiblePosts
                    for i in offsets { store.remove(list[i]) }
                }
            } header: {
                folderChips
                    .textCase(nil)
                    .padding(.horizontal, -20)   // 칩 줄을 화면 끝까지
            }
        }
        .overlay {
            if visiblePosts.isEmpty {
                ContentUnavailableView(
                    store.posts.isEmpty ? "보관한 글이 없어요" : "이 폴더에 글이 없어요",
                    systemImage: "bookmark",
                    description: Text(store.posts.isEmpty
                        ? "글을 보다가 오른쪽 아래 🔖 버튼을 누르세요.\n본문 사본도 같이 저장돼서 원글이 지워져도 볼 수 있어요."
                        : "글을 길게 눌러 '폴더로 옮기기'로 넣을 수 있어요.")
                )
                .padding(.top, 60)
            }
        }
        .alert("새 폴더", isPresented: $showNewFolder) {
            TextField("폴더 이름", text: $newFolderName)
            Button("취소", role: .cancel) {}
            Button("만들기") { store.addFolder(newFolderName) }
        }
        .alert("폴더 이름 변경",
               isPresented: Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
            TextField("폴더 이름", text: $renameText)
            Button("취소", role: .cancel) {}
            Button("저장") { if let f = renamingFolder { store.renameFolder(f, to: renameText) } }
        }
        .confirmationDialog("폴더를 삭제할까요?",
                            isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }),
                            titleVisibility: .visible,
                            presenting: deletingFolder) { f in
            Button("'\(f.name)' 삭제", role: .destructive) {
                store.deleteFolder(f)
                if filter == .folder(f.id) { filter = .all }
            }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("폴더 안의 글은 지워지지 않고 '분류 없음'으로 옮겨져요.")
        }
    }

    // 전체 / 분류 없음 / 폴더들 / + 새 폴더
    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("전체 \(store.posts.count)", selected: filter == .all) { filter = .all }
                chip("분류 없음", selected: filter == .unfiled) { filter = .unfiled }
                ForEach(store.folders) { f in
                    let count = store.posts.filter { $0.folderID == f.id }.count
                    chip("📁 \(f.name) \(count)", selected: filter == .folder(f.id)) { filter = .folder(f.id) }
                        .contextMenu {
                            Button { renameText = f.name; renamingFolder = f } label: {
                                Label("이름 변경", systemImage: "pencil")
                            }
                            Button(role: .destructive) { deletingFolder = f } label: {
                                Label("폴더 삭제", systemImage: "trash")
                            }
                        }
                }
                Button {
                    newFolderName = ""
                    showNewFolder = true
                } label: {
                    Label("새 폴더", systemImage: "folder.badge.plus")
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? DCTheme.navy : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func galleryName(_ id: String) -> String {
        favorites.items.first { $0.galleryID == id }?.name ?? id
    }
}

/// 저장해둔 본문 사본 보기 (인터넷 없이도, 원글이 지워져도 볼 수 있음)
struct SavedPostReader: View {
    let post: SavedPost
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            if let file = SavedPostStore.shared.archiveURL(post),
               FileManager.default.fileExists(atPath: file.path) {
                ArchiveWebView(fileURL: file, baseURL: post.url)
            } else {
                ContentUnavailableView("저장된 사본이 없어요", systemImage: "doc",
                                       description: Text("오른쪽 위 '원본 열기'로 확인하세요."))
            }
        }
        .navigationTitle(post.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("원본 열기") { router.open(post.url) }
            }
        }
    }
}

struct ArchiveWebView: UIViewRepresentable {
    let fileURL: URL
    let baseURL: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false   // 사본은 정적으로만 표시
        let webView = WKWebView(frame: .zero, configuration: config)
        if let data = try? Data(contentsOf: fileURL) {
            webView.load(data, mimeType: "application/x-webarchive",
                         characterEncodingName: "utf-8", baseURL: baseURL)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - 임시저장 목록

struct DraftRow: View {
    let draft: Draft

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(draft.title.isEmpty ? "(제목 없음)" : draft.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if draft.isAuto {
                    Text("자동")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
            if !draft.preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(draft.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("\(draft.galleryID) · \(draft.updatedAt.shortKorean)" + (draft.imageCount > 0 ? " · 사진 \(draft.imageCount)장" : ""))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

/// 글쓰기 화면에서 '불러오기'를 누르면 뜨는 시트
/// 누르면 불러오기 / 왼쪽으로 밀어 삭제 / '선택'으로 여러 개 골라 삭제 (모두 선택 가능)
struct DraftPickerSheet: View {
    let galleryID: String?
    let onPick: (Draft) -> Void
    @ObservedObject private var store = DraftStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var confirmDelete = false

    private var list: [Draft] { here + others }
    /// 이 갤러리 글 (최신순)
    private var here: [Draft] {
        guard let galleryID else { return [] }
        return store.drafts.filter { $0.galleryID == galleryID }.sorted { $0.updatedAt > $1.updatedAt }
    }
    /// 다른 갤러리 글 (최신순)
    private var others: [Draft] {
        store.drafts.filter { galleryID == nil || $0.galleryID != galleryID }.sorted { $0.updatedAt > $1.updatedAt }
    }

    @ViewBuilder
    private func draftRows(_ drafts: [Draft]) -> some View {
        ForEach(drafts) { d in
            Group {
                if editing {
                    DraftRow(draft: d)        // 선택 중에는 눌러도 불러오지 않고 체크만
                } else {
                    Button {
                        onPick(d)
                        dismiss()
                    } label: {
                        DraftRow(draft: d)
                    }
                }
            }
            .tag(d.id)
        }
        .onDelete { offsets in
            for i in offsets { store.remove(drafts[i]) }
        }
    }
    private var editing: Bool { editMode.isEditing }
    private var allSelected: Bool { !list.isEmpty && selection.count == list.count }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                // 이 갤러리 글 / 다른 갤러리 글을 나눠서 (다른 갤러리 글이 아래에 묻혀 안 보이던 문제)
                if !here.isEmpty {
                    Section("이 갤러리") { draftRows(here) }
                }
                Section {
                    draftRows(others)
                } header: {
                    if !others.isEmpty && !here.isEmpty { Text("다른 갤러리") }
                } footer: {
                    if !store.drafts.isEmpty && !editing {
                        Text("불러오면 지금 쓰고 있는 제목과 본문이 덮어써져요.")
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .overlay {
                if store.drafts.isEmpty {
                    ContentUnavailableView("임시저장한 글이 없어요", systemImage: "doc.text")
                }
            }
            .navigationTitle(editing ? (selection.isEmpty ? "삭제할 글 선택" : "\(selection.count)개 선택됨") : "임시저장 불러오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if editing {
                        Button(allSelected ? "선택 해제" : "모두 선택") {
                            selection = allSelected ? [] : Set(list.map(\.id))
                        }
                    } else {
                        Button("닫기") { dismiss() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !store.drafts.isEmpty || editing {
                        Button(editing ? "완료" : "선택") {
                            withAnimation {
                                editMode = editing ? .inactive : .active
                                selection = []
                            }
                        }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if editing {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text(selection.isEmpty ? "삭제" : "삭제 (\(selection.count))")
                        }
                        .tint(.red)
                        .disabled(selection.isEmpty)
                    }
                }
            }
            .confirmationDialog("선택한 임시저장 글 \(selection.count)개를 삭제할까요?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    store.remove(ids: selection)
                    selection = []
                    if store.drafts.isEmpty { editMode = .inactive }
                }
                Button("취소", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }
}

/// ⋮ → 글 보관함
struct SavedPostsSheet: View {
    @EnvironmentObject private var router: AppRouter
    var body: some View {
        NavigationStack {
            SavedPostsList()
                .navigationTitle("글 보관함")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { router.sheet = nil }
                    }
                }
        }
    }
}
