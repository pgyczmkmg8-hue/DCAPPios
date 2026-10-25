import SwiftUI

/// 앱 테마 (설정 → 앱 → 테마). 상단바 색, 강조색(하단 바 선택 등), 웹페이지 속 디시 파란색 계열을 바꿀 색
enum AppTheme: String, CaseIterable, Identifiable {
    case dc, navy, green, gray
    var id: String { rawValue }

    var name: String {
        switch self {
        case .dc: "디시 (기본)"
        case .navy: "남색"
        case .green: "연두"
        case .gray: "무채색"
        }
    }

    /// 상단바 색
    var bar: UIColor {
        switch self {
        case .dc: UIColor(red: 0.231, green: 0.282, blue: 0.565, alpha: 1)    // 디시 고유 색 (#3B4890)
        case .navy: UIColor(red: 0.29, green: 0.33, blue: 0.64, alpha: 1)     // 예전 기본색
        case .green: UIColor(red: 0.01, green: 0.78, blue: 0.35, alpha: 1)    // 네이버 초록 (#03C75A)
        case .gray: UIColor(red: 0.33, green: 0.33, blue: 0.35, alpha: 1)
        }
    }

    /// 강조색 — 밝은 화면 / 어두운 화면(다크 모드에서는 잘 보이게 밝게)
    var accentLight: UIColor {
        switch self {
        case .dc, .navy: bar
        case .green: UIColor(red: 0.0, green: 0.62, blue: 0.29, alpha: 1)      // 흰 바탕 글자용으로 조금 진하게
        case .gray: UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1)
        }
    }
    var accentDark: UIColor {
        switch self {
        case .dc, .navy: UIColor(red: 0.55, green: 0.62, blue: 1.0, alpha: 1)
        case .green: UIColor(red: 0.18, green: 0.88, blue: 0.48, alpha: 1)
        case .gray: UIColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1)
        }
    }

    /// 웹페이지 속 디시 파란색 계열을 바꿀 색 (h: 색상각, s: 채도 배율). nil이면 사이트 색 그대로
    var pageTint: [String: Double]? {
        switch self {
        case .dc, .navy: nil
        case .green: ["h": 147, "s": 1.6]
        case .gray: ["h": 230, "s": 0]
        }
    }
}

/// 앱 색상 — 지금 고른 테마를 따름
enum DCTheme {
    static let storageKey = "appTheme"
    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .dc
    }
    /// 상단바 색 (이름은 예전 그대로 navy)
    static var navy: Color { Color(uiColor: current.bar) }
    /// 하단 바 선택 색 등 (다크 모드에서는 밝게)
    static var accent: Color {
        let t = current
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? t.accentDark : t.accentLight
        })
    }
}

/// 갤러리 하단 바의 칸
enum GallerySection {
    case home, notice, recommend, search, write
}

extension Gallery {
    /// 개념글 목록
    var recommendURL: URL { URL(string: url.absoluteString + "?recommend=1")! }
    /// 공지 목록 (주소 형식이 다르면 여기만 고치면 됨)
    var noticeURL: URL { URL(string: url.absoluteString + "?notice=1")! }
    /// 갤러리 내 검색 (제목+내용)
    func searchURL(_ keyword: String, type: GallerySearchType = .subjectMemo, recommendOnly: Bool = false,
                   head: HeadTab? = nil) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = [
            URLQueryItem(name: "s_type", value: type.rawValue),
            URLQueryItem(name: "serval", value: keyword),
        ]
        if recommendOnly { items.insert(URLQueryItem(name: "recommend", value: "1"), at: 0) }
        // 말머리: 말머리 탭 링크에 붙어 있던 값(headid 등)을 그대로 붙임
        if let head, let headItems = URLComponents(url: head.url, resolvingAgainstBaseURL: false)?.queryItems {
            items.insert(contentsOf: headItems.filter { !["page", "s_type", "serval", "recommend"].contains($0.name) }, at: 0)
        }
        comps.queryItems = items
        return comps.url ?? url
    }
    /// 글쓰기
    var writeURL: URL {
        switch kind {
        case .board: URL(string: "https://m.dcinside.com/write/\(galleryID)")!
        case .mini:  URL(string: "https://m.dcinside.com/mini/write/\(galleryID)")!
        }
    }
}

/// 갤러리 내 검색 범위 (디시 모바일 검색 주소의 s_type 값 — 다르면 여기만 고치면 됨)
enum GallerySearchType: String, CaseIterable, Identifiable {
    case subjectMemo = "subject_m"
    case subject = "subject"
    case memo = "memo"
    case name = "name"
    case comment = "comment"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .subjectMemo: "제목+내용"
        case .subject: "제목"
        case .memo: "내용"
        case .name: "글쓴이"
        case .comment: "댓글"
        }
    }
}

/// 말머리 (지금 갤러리 페이지의 탭에서 읽어옴)
struct HeadTab: Hashable, Identifiable {
    let name: String
    let url: URL
    var id: String { name }
}

/// 갤러리 내 검색 창 (말머리 / 검색 범위 / 개념글만 / 최근 검색어)
struct GallerySearchSheet: View {
    let gallery: Gallery
    var heads: [HeadTab] = []
    let onSearch: (URL) -> Void
    @State private var head: HeadTab?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gallerySearchType") private var typeRaw = GallerySearchType.subjectMemo.rawValue
    @State private var keyword = ""
    @State private var recommendOnly = false
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: "gallerySearchRecent") ?? []
    @FocusState private var focused: Bool

    private var type: GallerySearchType { GallerySearchType(rawValue: typeRaw) ?? .subjectMemo }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("검색어", text: $keyword)
                            .focused($focused)
                            .submitLabel(.search)
                            .onSubmit { search(keyword) }
                    }
                    if !heads.isEmpty {
                        Picker("말머리", selection: $head) {
                            Text("전체 말머리").tag(HeadTab?.none)
                            ForEach(heads) { Text($0.name).tag(HeadTab?.some($0)) }
                        }
                    }
                    Picker("검색 범위", selection: $typeRaw) {
                        ForEach(GallerySearchType.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Toggle("개념글에서만 검색", isOn: $recommendOnly)
                } header: {
                    Text("\(gallery.name)에서 검색")
                }

                if !recent.isEmpty {
                    Section {
                        ForEach(recent, id: \.self) { w in
                            Button { search(w) } label: {
                                Label(w, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                            }
                        }
                        .onDelete { recent.remove(atOffsets: $0); saveRecent() }
                    } header: {
                        HStack {
                            Text("최근 검색어")
                            Spacer()
                            Button("전체 삭제") { recent.removeAll(); saveRecent() }.font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("갤러리 검색")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("검색") { search(keyword) }
                        .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                Task { try? await Task.sleep(for: .milliseconds(350)); focused = true }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        recent.removeAll { $0 == q }
        recent.insert(q, at: 0)
        if recent.count > 20 { recent.removeLast(recent.count - 20) }
        saveRecent()
        onSearch(gallery.searchURL(q, type: type, recommendOnly: recommendOnly, head: head))
        dismiss()
    }

    private func saveRecent() { UserDefaults.standard.set(recent, forKey: "gallerySearchRecent") }
}

/// 웹뷰 + 남색 상단바 + 공식 앱 스타일 하단 바. NavigationStack 안에 넣어서 사용하세요.
struct BrowserView: View {
    @StateObject private var model: WebViewModel
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var autoImages = AutoImageStore.shared
    @ObservedObject private var savedPosts = SavedPostStore.shared
    @ObservedObject private var alarms = AlarmStore.shared
    @AppStorage("compactMode") private var compactMode = false
    /// 오른쪽 세로 버튼 막대 (끄면 ⋮ 메뉴가 상단바로 감)
    @AppStorage("showFloatingBar") private var showFloatingBar = true

    // 글쓰기 화면 → 이 갤러리 자짤 설정 창
    @State private var autoImageGallery: String?
    private var writeGalleryID: String? { model.url.flatMap(AutoImageStore.writeGalleryID) }

    // 글쓰기 화면의 계정 버튼에 표시할 현재 계정
    @State private var currentAccount: String? = CredentialStore.currentAccountID

    // 글 보관 버튼: 폴더 고르기 / 이미 보관한 글 메뉴
    @State private var showSaveFolderPicker = false
    @State private var savedPostMenu: SavedPost?
    let fallbackTitle: String
    /// 왼쪽 위 ☰ 버튼 (홈 탭의 메인 브라우저에서만 표시, 다른 곳은 뒤로가기 버튼 자리)
    var showsMenuButton = false


    // 갤러리 내 검색
    @State private var showGallerySearch = false
    @State private var galleryHeads: [HeadTab] = []
    @State private var gallerySearchText = ""

    // 유저 직접 입력 차단
    @State private var showUserPrompt = false
    @State private var userInput = ""

    // 유저 메모 입력 (길게 누르기 → 메모)
    @State private var memoTarget: (kind: BlockedUser.Kind, value: String, nick: String, existing: UserMemo?)?
    // 차단 범위 고르기 (이 갤러리만 / 모든 갤러리)
    @State private var pendingBlock: (kind: BlockedUser.Kind, value: String, nick: String, label: String)?
    @State private var memoInput = ""

    // 키워드 차단 입력
    @State private var showKeywordPrompt = false
    @State private var keywordInput = ""

    // 구조 진단
    @State private var diagnosticText: String?

    // 임시저장 불러오기
    @State private var showDraftPicker = false

    // 키보드가 떠 있는 동안에는 앱 툴바를 숨겨서, 디시 댓글창(유동 닉/비번/코드, 디시콘 버튼)이
    // 사파리처럼 키보드 바로 위에 붙도록 함
    @State private var keyboardVisible = false

    init(startURL: URL, fallbackTitle: String) {
        _model = StateObject(wrappedValue: WebViewModel(url: startURL))
        self.fallbackTitle = fallbackTitle
    }

    /// 이미 만들어진 브라우저(홈 탭의 메인 브라우저 등)를 화면에 붙일 때
    init(model: WebViewModel, fallbackTitle: String, showsMenuButton: Bool = false) {
        _model = StateObject(wrappedValue: model)
        self.fallbackTitle = fallbackTitle
        self.showsMenuButton = showsMenuButton
    }

    private var filters: FilterStore { FilterStore.shared }

    private var currentGallery: (id: String, kind: GalleryKind)? {
        guard let url = model.url else { return nil }
        return Gallery.parse(url)
    }

    private var isFavorite: Bool {
        guard let g = currentGallery else { return false }
        return favorites.contains(galleryID: g.id, kind: g.kind)
    }

    /// 지금 갤러리 (이름 포함)
    private var gallery: Gallery? {
        guard let g = currentGallery, let url = model.url else { return nil }
        let name = favorites.items.first { $0.galleryID == g.id && $0.kind == g.kind }?.name
            ?? Gallery.guessName(title: model.title, url: url, id: g.id)
        return Gallery(galleryID: g.id, name: name, kind: g.kind)
    }

    /// 상단바 제목: 갤러리 안이면 갤러리 이름, 아니면 페이지 제목
    private var titleText: String {
        if let g = gallery { return g.name }
        return model.title.isEmpty ? fallbackTitle : Gallery.cleanTitle(model.title)
    }

    /// 디시 첫 화면인지 (하단 바 홈 강조용)
    private var isDCHome: Bool {
        guard let url = model.url, url.host == "m.dcinside.com" else { return false }
        return url.path.isEmpty || url.path == "/"
    }

    /// 하단 바에서 지금 선택된 칸
    private var section: GallerySection {
        guard let url = model.url else { return .home }
        if AutoImageStore.writeGalleryID(from: url) != nil { return .write }
        let q = url.query ?? ""
        if q.contains("recommend=1") { return .recommend }
        if q.contains("notice=") { return .notice }
        if q.contains("serval=") || q.contains("s_keyword=") { return .search }
        return .home
    }

    // body를 여러 조각으로 나눔 (한 덩어리면 컴파일러가 타입 계산을 못 함)
    var body: some View { layer7 }

    /// 웹뷰 + 상단바 + 하단 바 + 키보드 감지
    private var layer1: some View {
        WebView(model: model)
            .ignoresSafeArea(.keyboard, edges: .bottom)   // 키보드 처리는 웹뷰(WebKit)에 맡김
            // 듀오를 펼쳤을 때 오른쪽(시계·카메라 줄) 안전 영역까지 웹페이지가 쓰도록
            .ignoresSafeArea(.container, edges: .horizontal)
            // 상단바 뒤~화면 맨 위까지 남색으로 (듀오를 펼치면 상단바 위에 띠가 생기고, 내비게이션 화면의 기본 흰 배경이 보임)
            // 웹페이지 뒤에 깔리므로 다른 곳에는 안 보임
            .background {
                DCTheme.navy.ignoresSafeArea(.container, edges: [.top, .horizontal])
            }
            .overlay(alignment: .top) { topOverlay }
            .overlay(alignment: .bottomTrailing) {
                if showsMenuButton && showFloatingBar && !keyboardVisible { floatingButtonsPlaced }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { topBar }
            .toolbarBackground(DCTheme.navy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {   // 탭바 바로 위에 붙는 툴바
                if !keyboardVisible {
                    VStack(spacing: 0) {
                        modeBanner
                        if showsMenuButton { galleryBar }
                    }
                    .transition(.opacity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = false }
            }
            // 길게 누르기 → 차단 메뉴
    }

    /// 차단 메뉴 / 요소 숨기기 확인
    private var layer2: some View {
        layer1
            .confirmationDialog(model.blockRequest.map { isAlreadyBlocked($0) } == true ? "차단 해제" : "차단",
                                isPresented: Binding(get: { model.blockRequest != nil },
                                                     set: { if !$0 { model.blockRequest = nil } }),
                                titleVisibility: .visible,
                                presenting: model.blockRequest) { req in
                blockButtons(req)
            } message: { req in
                Text(req.snippet.isEmpty ? (isAlreadyBlocked(req) ? "차단을 풀까요?" : "무엇을 차단할까요?") : req.snippet)
            }
            .background {
                // 요소 숨기기 확인 (다이얼로그끼리 겹치지 않게 별도 레이어에 부착)
                Color.clear
                    .confirmationDialog("이 부분을 숨길까요?",
                                        isPresented: Binding(get: { model.pickRequest != nil },
                                                             set: { if !$0 { model.pickRequest = nil } }),
                                        titleVisibility: .visible,
                                        presenting: model.pickRequest) { req in
                        Button("숨기기", role: .destructive) {
                            filters.addHidden(selector: req.selector, memo: req.snippet)
                            model.clearPick()
                        }
                        Button("더 넓게 선택") { model.pickParent() }
                        Button("취소", role: .cancel) { model.clearPick() }
                    } message: { req in
                        Text("\(req.snippet.isEmpty ? "(내용 없음)" : req.snippet)\n같은 모양의 요소 \(req.count)개가 숨겨져요.")
                    }
            }
    }

    /// 토스트 / 키워드·유저 차단 입력
    private var layer3: some View {
        layer2
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 88)   // 하단 바 위에 표시
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: model.toast)
            .alert("키워드 차단", isPresented: $showKeywordPrompt) {
                TextField("차단할 단어", text: $keywordInput)
                Button("취소", role: .cancel) {}
                Button("추가") {
                    filters.addKeyword(keywordInput)
                    if !keywordInput.trimmingCharacters(in: .whitespaces).isEmpty {
                        model.showToast("'\(keywordInput)' 키워드 차단")
                    }
                }
            } message: {
                Text("이 단어가 들어간 글과 댓글을 가려요.")
            }
            .alert("유저 차단", isPresented: $showUserPrompt) {
                TextField("아이디, IP 또는 닉네임", text: $userInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("아이디로 차단") { blockTyped(.id) }
                Button("IP로 차단") { blockTyped(.ip) }
                Button("닉네임으로 차단") { blockTyped(.nick) }
                Button("취소", role: .cancel) {}
            } message: {
                Text("유동은 IP 앞 두 자리(예: 118.235)를 입력하세요.")
            }
    }

    private func saveMemo(gallery: String?) {
        guard let t = memoTarget else { return }
        MemoStore.shared.set(kind: t.kind, value: t.value, text: memoInput, gallery: gallery, replacing: t.existing)
        let empty = memoInput.trimmingCharacters(in: .whitespaces).isEmpty
        model.showToast(empty ? "메모를 지웠어요" : (gallery == nil ? "메모를 남겼어요 (모든 갤러리)" : "메모를 남겼어요 (이 갤러리)"))
    }

    /// 캡처 / 보관 폴더 고르기 / 유저 메모 / 차단 범위
    private var layer4: some View {
        layer3
            .confirmationDialog("어디서 가릴까요?",
                                isPresented: Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } }),
                                titleVisibility: .visible) {
                if let b = pendingBlock {
                    Button("이 갤러리(\(gallery?.name ?? currentGallery?.id ?? ""))에서만", role: .destructive) {
                        filters.addUser(kind: b.kind, value: b.value, memo: b.nick, gallery: currentGallery?.id)
                        model.showToast("\(b.label) 차단했어요 (이 갤러리)")
                    }
                    Button("모든 갤러리에서", role: .destructive) {
                        filters.addUser(kind: b.kind, value: b.value, memo: b.nick)
                        model.showToast("\(b.label) 차단했어요 (모든 갤러리)")
                    }
                }
                Button("취소", role: .cancel) {}
            }
            .alert("유저 메모", isPresented: Binding(get: { memoTarget != nil }, set: { if !$0 { memoTarget = nil } })) {
                TextField("메모 (비우면 삭제)", text: $memoInput)
                if let gid = currentGallery?.id {
                    Button("이 갤러리에만 저장") { saveMemo(gallery: gid) }
                }
                Button(currentGallery == nil ? "저장" : "모든 갤러리에 저장") { saveMemo(gallery: nil) }
                Button("취소", role: .cancel) {}
            } message: {
                if let t = memoTarget {
                    Text("\(t.nick.isEmpty ? "" : t.nick + " · ")\(t.kind.label) \(t.value)\n닉네임 옆에 보여요.")
                }
            }
            .sheet(item: $model.captured) { CapturePreview(capture: $0) }
            .confirmationDialog("어느 폴더에 보관할까요?", isPresented: $showSaveFolderPicker, titleVisibility: .visible) {
                Button("분류 없음") { Task { await model.savePost(folderID: nil, keepFolder: false) } }
                ForEach(savedPosts.folders) { f in
                    Button("📁 \(f.name)") { Task { await model.savePost(folderID: f.id, keepFolder: false) } }
                }
                Button("취소", role: .cancel) {}
            }
    }

    /// 보관한 글 메뉴
    private var layer5: some View {
        layer4
            .onReceive(NotificationCenter.default.publisher(for: DC.credentialsChanged)) { _ in
                currentAccount = CredentialStore.currentAccountID
            }
            .background {
                Color.clear
                    .confirmationDialog("보관한 글이에요",
                                        isPresented: Binding(get: { savedPostMenu != nil },
                                                             set: { if !$0 { savedPostMenu = nil } }),
                                        titleVisibility: .visible,
                                        presenting: savedPostMenu) { post in
                        Button("최신 내용으로 다시 저장") { Task { await model.savePost() } }
                        if post.folderID != nil {
                            Button("분류 없음으로 옮기기") {
                                savedPosts.move(post, to: nil)
                                model.showToast("분류 없음으로 옮겼어요")
                            }
                        }
                        ForEach(savedPosts.folders.filter { $0.id != post.folderID }) { f in
                            Button("📁 \(f.name)(으)로 옮기기") {
                                savedPosts.move(post, to: f.id)
                                model.showToast("\(f.name)(으)로 옮겼어요")
                            }
                        }
                        Button("보관함에서 빼기", role: .destructive) {
                            savedPosts.remove(post)
                            model.showToast("보관함에서 뺐어요")
                        }
                        Button("취소", role: .cancel) {}
                    } message: { post in
                        Text("지금 폴더: \(savedPosts.folderName(post.folderID))")
                    }
            }
    }

    /// 갤러리 검색 / 임시저장 / 진단
    private var layer6: some View {
        layer5
            .sheet(isPresented: $showGallerySearch) {
                if let g = gallery {
                    GallerySearchSheet(gallery: g, heads: galleryHeads) { url in model.load(url) }
                }
            }
            .sheet(isPresented: $showDraftPicker) {
                DraftPickerSheet(galleryID: model.url.flatMap(AutoImageStore.writeGalleryID)) { d in
                    model.restoreDraft(d)
                }
            }
            .sheet(isPresented: Binding(get: { diagnosticText != nil },
                                        set: { if !$0 { diagnosticText = nil } })) {
                DiagnosticView(text: diagnosticText ?? "")
            }
    }

    /// 글쓰기 화면 → 이 갤러리 자짤 설정 / 사진 보기
    private var layer7: some View {
        layer6
            .fullScreenCover(item: $model.imageViewer) { item in
                ImageViewer(item: item)
                    .presentationBackground(.clear)   // 끌어내릴 때 뒤의 글이 비쳐 보이도록
            }
            .sheet(isPresented: Binding(get: { autoImageGallery != nil },
                                        set: { if !$0 { autoImageGallery = nil } })) {
                if let gid = autoImageGallery {
                    NavigationStack {
                        GalleryAutoImageView(galleryID: gid, name: gallery?.name ?? gid)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("완료") { autoImageGallery = nil }
                                }
                            }
                    }
                }
            }
    }

    // MARK: - 상단: 로딩바 / 캡처 중

    @ViewBuilder
    private var topOverlay: some View {
        VStack(spacing: 0) {
            if model.isLoading {
                ProgressView(value: model.progress).progressViewStyle(.linear)
            }
            if model.isCapturing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("전체 페이지 캡처 중…")
                }
                .font(.subheadline)
                .padding(10)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 8)
            }
        }
    }


    // MARK: - 글쓰기 화면 계정 버튼 (로그인 / 계정 전환 / 로그아웃)

    private var accountMenu: some View {
        let others = CredentialStore.all().filter { $0.id != currentAccount }
        return Menu {
            if let cur = currentAccount {
                Section("현재 계정: \(cur)") {
                    Button(role: .destructive) { model.logoutHere() } label: {
                        Label("로그아웃 (유동으로 쓰기)", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            if !others.isEmpty {
                Section(currentAccount == nil ? "저장된 계정으로 로그인" : "다른 계정으로 전환") {
                    ForEach(others) { acc in
                        Button { model.loginHere(acc) } label: {
                            Label(acc.id, systemImage: "person.crop.circle")
                        }
                    }
                }
            }
            Button { model.loginHere(nil) } label: {
                Label("로그인 페이지 열기", systemImage: "person.badge.key")
            }
        } label: {
            // 상단바 자리를 아끼려고 아이콘만 (계정 이름은 메뉴 안 '현재 계정'에 표시)
            Image(systemName: currentAccount == nil ? "person.crop.circle.badge.plus" : "person.crop.circle.fill")
                .font(.system(size: 19))
        }
    }

    // MARK: - 모드 안내 배너 (하단 툴바 위에 표시 → 페이지 맨 위를 가리지 않음)

    @ViewBuilder
    private var modeBanner: some View {
            // 글쓰기: 로그인 / 임시저장 / 불러오기 / 등록은 상단바로 옮김 → 여기엔 자짤만
            if model.isWritePage, let gid = writeGalleryID,
               autoImages.effective(for: gid).enabled || !autoImages.settings.images.isEmpty {
                HStack(spacing: 8) {
                    Spacer()
                    if autoImages.effective(for: gid).enabled {
                        // 누르면 자짤 첨부, 길게 누르면 이 갤러리 자짤 설정
                        Menu {
                            Button { model.attachAutoImage(force: true) } label: {
                                Label("자짤 첨부", systemImage: "photo.badge.plus")
                            }
                            Button { autoImageGallery = gid } label: {
                                Label("이 갤러리 자짤 설정", systemImage: "slider.horizontal.3")
                            }
                        } label: {
                            Text("자짤")
                        } primaryAction: {
                            model.attachAutoImage(force: true)
                        }
                    } else {
                        Button("자짤 꺼짐") { autoImageGallery = gid }
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial)
                .overlay(alignment: .top) { Divider() }
            }
            if model.isPickMode {
                HStack {
                    Image(systemName: "hand.tap")
                    Text("숨길 부분을 탭하세요")
                    Spacer()
                    Button("완료") { model.setPickMode(false) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .font(.subheadline)
                .padding(10)
                .background(.thinMaterial)
                .overlay(alignment: .top) { Divider() }
            }
            if model.isBlockPickMode {
                HStack {
                    Image(systemName: "person.crop.circle.badge.xmark")
                    Text("차단할 글이나 댓글을 탭하세요")
                    Spacer()
                    Button("취소") { model.setBlockPickMode(false) }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                }
                .font(.subheadline)
                .padding(10)
                .background(.thinMaterial)
                .overlay(alignment: .top) { Divider() }
            }
    }

    // MARK: - 상단바 (남색): 제목만 (메인 화면). 설정 안에서 연 화면은 오른쪽에 ☆ ⋮

    @ToolbarContentBuilder
    private var topBar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(titleText)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .contentShape(Rectangle())
                // 갤러리 이름을 0.5초 누르면 한손 모드 켜기/끄기
                .onLongPressGesture(minimumDuration: 0.5) {
                    guard showsMenuButton else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    compactMode.toggle()
                }
        }
        if showsMenuButton {
            // 글쓰기 화면: 왼쪽 (⋮) 로그인 / 오른쪽 임시저장 불러오기 등록
            // (한 칸에 묶어서 넣어야 공간이 모자라도 '…'로 접히지 않음, 테두리(글래스)는 뺌)
            if model.isWritePage {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        if !showFloatingBar { topMoreMenu }
                        accountMenu
                    }
                    .foregroundStyle(.white)
                }
                .noGlassBackground()
                // 상단바 버튼은 버튼마다 기본 여백이 붙어서 간격 숫자를 줄여도 그대로 → plain 스타일로 여백을 없애고 한 칸에 모음
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button("임시저장") { Task { await model.saveDraftManually() } }
                        Button("불러오기") { showDraftPicker = true }
                        // 등록만 테두리
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            model.submitWrite()
                        } label: {
                            Text("등록")
                                .fontWeight(.bold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1.2))
                                .contentShape(Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize()
                }
                .noGlassBackground()
            } else {
                // 다른 화면: 왼쪽에 로그인/로그아웃(계정) 버튼 — 글쓰기 화면과 같은 메뉴
                ToolbarItem(placement: .topBarLeading) {
                    accountMenu.foregroundStyle(.white)
                }
                .noGlassBackground()
                if !showFloatingBar {
                    ToolbarItem(placement: .topBarTrailing) { topMoreMenu.foregroundStyle(.white) }
                        .noGlassBackground()
                }
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if currentGallery != nil {
                    Button { toggleFavorite() } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                    }
                }
                Menu {
                    moreMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                }
            }
        }
    }

    /// 세로 막대를 껐을 때 상단바에 놓는 ⋮ 메뉴
    private var topMoreMenu: some View {
        Menu {
            moreMenu
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
        }
    }

    // MARK: - 오른쪽 아래 세로 버튼 (한손 모드 / ⋮ 메뉴 / 댓글 새로고침)

    /// 세로 버튼 위치: 보통은 웹페이지 오른쪽 아래.
    /// 듀오처럼 오른쪽에 넓은 안전 영역(시계·카메라 줄)이 있으면 그 빈 줄의 맨 아래(하단 바 옆)에 넣음
    private var floatingButtonsPlaced: some View {
        GeometryReader { g in
            let side = g.safeAreaInsets.trailing
            if side >= 56 {
                ZStack(alignment: .bottom) {
                    Color.clear.allowsHitTesting(false)
                    floatingButtons
                        .padding(.bottom, Self.windowBottomInset + 6)
                }
                .frame(width: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .ignoresSafeArea(.container, edges: [.trailing, .bottom])
            } else {
                floatingButtons
                    .padding(.trailing, 12)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    /// 홈 인디케이터 등 기기 아래쪽 안전 영역 높이
    private static var windowBottomInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.bottom
            ?? scene?.windows.first?.safeAreaInsets.bottom ?? 0
    }

    private var floatingButtons: some View {
        VStack(spacing: 2) {
            // 1. 한손 모드 켜기/끄기
            Button { compactMode.toggle() } label: {
                floatIcon(compactMode ? "rectangle.expand.vertical" : "rectangle.bottomhalf.inset.filled",
                          tint: compactMode ? DCTheme.accent : .primary)
            }
            // 2. ⋮ 메뉴
            Menu {
                moreMenu
            } label: {
                floatIcon("ellipsis", tint: .primary).rotationEffect(.degrees(90))
            }
            // 3. 댓글 새로고침 (글 보기 화면에서만 보임)
            if isPostPage {
                Button { model.refreshComments() } label: {
                    floatIcon("arrow.clockwise.circle", tint: .primary)
                }
            }
        }
        .padding(4)
        .glassBar()
    }

    private var isPostPage: Bool { model.url.flatMap(SavedPostStore.postInfo) != nil }

    private var isPostSaved: Bool {
        guard let url = model.url else { return false }
        return savedPosts.contains(url: url)
    }

    private func bookmarkTapped() {
        guard let url = model.url else { return }
        if let saved = savedPosts.post(for: url) {
            savedPostMenu = saved                       // 이미 보관 → 폴더 이동 / 빼기 메뉴
        } else if savedPosts.folders.isEmpty {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await model.savePost() }             // 폴더가 없으면 바로 보관
        } else {
            showSaveFolderPicker = true                 // 어느 폴더에 넣을지 고르기
        }
    }

    private func floatIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    // MARK: - 하단 바 (리퀴드 글라스): 홈 / 보관함 / 개념글 / 검색 / 글쓰기

    private var galleryBar: some View {
        let g = gallery
        return HStack(spacing: 2) {
            // 홈: 언제나 디시 첫 화면
            barItem("house", "house.fill", "홈", selected: isDCHome) {
                model.load(DC.home)
            }
            barItem("square.stack", "square.stack.fill", "갤러리", selected: false) {
                router.sheet = .library
            }
            .overlay(alignment: .top) {
                // 안 읽은 알림이 있으면 빨간 점 (갤러리 창 → 알림 탭)
                if alarms.unreadCount > 0 {
                    Circle().fill(.red).frame(width: 8, height: 8).offset(x: 12, y: 6).allowsHitTesting(false)
                }
            }
            // 가운데: 전체글 보는 중 → "개념글" / 개념글 보는 중 → "전체글"(≡)로 바뀜
            if section == .recommend {
                barItem("line.3.horizontal", "line.3.horizontal", "전체글", selected: true, enabled: g != nil) {
                    if let g { model.load(g.url) }
                }
            } else {
                barItem("star", "star.fill", "개념글", selected: false, enabled: g != nil) {
                    if let g { model.load(g.recommendURL) }
                }
            }
            barItem("magnifyingglass", "magnifyingglass", "검색", selected: section == .search) {
                if g != nil {
                    Task {
                        galleryHeads = await model.headTabs()   // 지금 페이지의 말머리 읽기
                        showGallerySearch = true
                    }
                } else {
                    router.sheet = .search
                }
            }
            barItem("square.and.pencil", "square.and.pencil", "글쓰기", selected: section == .write, enabled: g != nil) {
                if let g {
                    model.focusTitleOnWrite = true      // 열리면 제목 칸에 바로 키보드
                    model.load(g.writeURL)
                }
            }
        }
        .padding(6)
        .glassBar()
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private func barItem(_ icon: String, _ selectedIcon: String, _ title: String, selected: Bool, enabled: Bool = true,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: selected ? selectedIcon : icon)
                    .font(.system(size: 19, weight: .medium))
                    .frame(height: 24)
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? DCTheme.accent : Color.primary)
            .background {
                if selected {
                    Capsule().fill(Color.primary.opacity(0.08))   // 선택된 칸 둥근 하이라이트
                }
            }
            .opacity(enabled ? 1 : 0.3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - ⋮ 메뉴

    @ViewBuilder
    private var moreMenu: some View {
        // 화면에 따라 바뀌는 첫 칸: 글 보기 중 → 글 보관 / 갤러리 목록 → 갤러리 즐겨찾기
        Section {
            if isPostPage {
                Button { bookmarkTapped() } label: {
                    Label(isPostSaved ? "보관한 글 (옮기기 / 빼기)" : "이 글 보관하기",
                          systemImage: isPostSaved ? "bookmark.fill" : "bookmark")
                }
            } else if currentGallery != nil {
                Button { toggleFavorite() } label: {
                    Label(isFavorite ? "갤러리 즐겨찾기 해제" : "갤러리 즐겨찾기 추가",
                          systemImage: isFavorite ? "star.fill" : "star")
                }
            }
            if currentGallery != nil {
                Button { model.openManageLog() } label: {
                    Label("갤러리 관리 내역", systemImage: "list.bullet.clipboard")
                }
            }
            Button { router.sheet = .posts } label: {
                Label("글 보관함", systemImage: "bookmark.square")
            }
            Button { router.sheet = .settings } label: {
                Label("설정", systemImage: "gearshape")
            }
        }
        Section {
            Button { model.goForward() } label: { Label("앞으로", systemImage: "chevron.forward") }
                .disabled(!model.canGoForward)
            Button { model.reload() } label: { Label("새로고침", systemImage: "arrow.clockwise") }
            if showsMenuButton && !showFloatingBar {
                if isPostPage {
                    Button { model.refreshComments() } label: {
                        Label("댓글 새로고침", systemImage: "arrow.clockwise.circle")
                    }
                }
                Button { compactMode.toggle() } label: {
                    Label(compactMode ? "한손 모드 끄기" : "한손 모드 켜기", systemImage: "rectangle.bottomhalf.inset.filled")
                }
            }
        }
        if let url = model.url {
            ShareLink(item: url) { Label("링크 공유", systemImage: "link") }
        }
        Section("캡처") {
            Button { Task { await model.captureVisible() } } label: {
                Label("보이는 화면 캡처", systemImage: "camera.viewfinder")
            }
            Button { Task { await model.captureFullPage() } } label: {
                Label("전체 페이지 캡처", systemImage: "doc.viewfinder")
            }
        }
        Section("차단") {
            Button {
                Task {
                    if let author = await model.articleAuthor() {
                        model.blockRequest = author
                    } else {
                        model.showToast("글 보기 화면에서 쓸 수 있어요")
                    }
                }
            } label: {
                Label("이 글 작성자 차단", systemImage: "person.fill.xmark")
            }
            Button { model.setBlockPickMode(!model.isBlockPickMode) } label: {
                Label(model.isBlockPickMode ? "탭해서 차단 끝내기" : "탭해서 유저 차단",
                      systemImage: "hand.tap")
            }
            Button {
                userInput = ""
                showUserPrompt = true
            } label: {
                Label("유저 직접 입력해서 차단", systemImage: "person.crop.circle.badge.plus")
            }
            Button {
                keywordInput = ""
                showKeywordPrompt = true
            } label: {
                Label("키워드 차단 추가", systemImage: "text.badge.xmark")
            }
        }
        Section("화면 정리") {
            Button { model.setPickMode(!model.isPickMode) } label: {
                Label(model.isPickMode ? "요소 숨기기 끝내기" : "요소 숨기기 (탭해서 선택)",
                      systemImage: "eye.slash")
            }
        }
        Button {
            Task { diagnosticText = await model.diagnose() }
        } label: {
            Label("페이지 구조 진단", systemImage: "stethoscope")
        }
    }

    // MARK: - 차단 메뉴 버튼

    /// 길게 누른 대상이 이미 차단돼 있는지 (그러면 차단 대신 해제를 물음 — 실수로 차단했을 때 바로 되돌리기)
    private func isAlreadyBlocked(_ req: BlockRequest) -> Bool {
        !filters.blockedUsers(id: req.userID, ip: req.ip, nick: req.nick, gallery: currentGallery?.id).isEmpty
            || filters.isDcconBlocked(req.dcconKey)
            || !filters.blockedKeywords(in: req.snippet).isEmpty
    }

    @ViewBuilder
    private func blockButtons(_ req: BlockRequest) -> some View {
        if isAlreadyBlocked(req) {
            unblockButtons(req)
        } else {
            newBlockButtons(req)
        }
    }

    @ViewBuilder
    private func unblockButtons(_ req: BlockRequest) -> some View {
        ForEach(filters.blockedUsers(id: req.userID, ip: req.ip, nick: req.nick, gallery: currentGallery?.id)) { u in
            let who = u.memo.isEmpty ? u.value : "\(u.memo) (\(u.value))"
            Button("\(u.kind.label) 차단 해제: \(who)\(u.gallery == nil ? " · 전체" : " · 이 갤러리")") {
                filters.removeUser(u)
                model.showToast("\(u.memo.isEmpty ? u.value : u.memo) 차단을 풀었어요")
            }
        }
        if filters.isDcconBlocked(req.dcconKey) {
            Button("디시콘 차단 해제") {
                filters.removeDccon(key: req.dcconKey)
                model.showToast("디시콘 차단을 풀었어요")
            }
        }
        ForEach(filters.blockedKeywords(in: req.snippet), id: \.self) { w in
            Button("키워드 차단 해제: \(w)") {
                filters.removeKeyword(w)
                model.showToast("'\(w)' 키워드 차단을 풀었어요")
            }
        }
        memoButton(req)
        Button("취소", role: .cancel) {}
    }

    @ViewBuilder
    private func newBlockButtons(_ req: BlockRequest) -> some View {
        let name = req.nick.isEmpty ? "작성자" : req.nick
        if !req.userID.isEmpty {
            Button("유저 차단: \(name) (\(req.userID))", role: .destructive) {
                askBlockScope(.id, req.userID, req.nick, label: name)
            }
        }
        if !req.ip.isEmpty {
            Button("IP로 차단: \(name) (\(req.ip))", role: .destructive) {
                askBlockScope(.ip, req.ip, req.nick, label: "\(name)(\(req.ip))")
            }
        }
        if req.userID.isEmpty && !req.nick.isEmpty {
            // 유동은 IP / 닉네임 중 골라서 차단 (닉네임은 같은 닉네임 쓰는 유동 모두 가려짐)
            Button("닉네임으로 차단: \(req.nick) (같은 닉 모두)", role: .destructive) {
                askBlockScope(.nick, req.nick, req.nick, label: req.nick)
            }
        }
        if !req.dcconKey.isEmpty {
            Button("이 디시콘 차단", role: .destructive) {
                filters.addDccon(key: req.dcconKey, imageURL: req.dcconSrc)
                model.showToast("디시콘을 차단했어요")
            }
        }
        Button("키워드로 차단…") {
            keywordInput = ""
            showKeywordPrompt = true
        }
        memoButton(req)
        Button("취소", role: .cancel) {}
    }

    /// 길게 누르기 메뉴의 '메모': 고닉·반고닉은 아이디에, 유동은 IP / 닉네임 중 골라서
    @ViewBuilder
    private func memoButton(_ req: BlockRequest) -> some View {
        if !req.userID.isEmpty {
            memoChoice(.id, req.userID, req.nick, label: "")
        } else {
            if !req.ip.isEmpty { memoChoice(.ip, req.ip, req.nick, label: "IP(\(req.ip))에 ") }
            if !req.nick.isEmpty { memoChoice(.nick, req.nick, req.nick, label: "닉네임(\(req.nick))에 ") }
        }
    }

    private func memoChoice(_ kind: BlockedUser.Kind, _ value: String, _ nick: String, label: String) -> some View {
        let existing = MemoStore.shared.memo(kind: kind, value: value, gallery: currentGallery?.id)
        return Button(label + (existing == nil ? "메모 남기기…" : "메모 고치기…")) {
            memoInput = existing?.text ?? ""
            memoTarget = (kind, value, nick, existing)
        }
    }

    /// 차단 대상을 고르면 → 갤러리 안이면 범위(이 갤러리만 / 모든 갤러리)를 한 번 더 물음
    private func askBlockScope(_ kind: BlockedUser.Kind, _ value: String, _ nick: String, label: String) {
        if currentGallery == nil {
            filters.addUser(kind: kind, value: value, memo: nick)
            model.showToast("\(label) 차단했어요")
        } else {
            pendingBlock = (kind, value, nick, label)
        }
    }

    private func toggleFavorite() {
        guard let g = currentGallery else { return }
        guard let url = model.url else { return }
        let name = Gallery.guessName(title: model.title, url: url, id: g.id)
        if isFavorite {
            favorites.remove(galleryID: g.id, kind: g.kind)
            model.showToast("즐겨찾기에서 뺐어요")
        } else {
            favorites.add(Gallery(galleryID: g.id, name: name, kind: g.kind))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            model.showToast("★ \(name) 추가됨")
        }
    }

    private func blockTyped(_ kind: BlockedUser.Kind) {
        let v = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        filters.addUser(kind: kind, value: v)
        model.showToast("\(kind.label) '\(v)' 차단했어요")
    }
}

extension ToolbarContent {
    /// iOS 26: 상단바 버튼 뒤의 리퀴드 글래스(공유 배경)를 빼서 테두리 없이 보이게
    @ToolbarContentBuilder
    func noGlassBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// 페이지 구조 진단 결과 (차단이 잘 안 될 때 이 내용을 복사해서 보내주면 선택자를 맞출 수 있어요)
struct DiagnosticView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("페이지 구조 진단")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("복사") { UIPasteboard.general.string = text }
                }
            }
        }
    }
}

// MARK: - 리퀴드 글라스 캡슐 (iOS 26 이상은 진짜 유리 효과, 그 아래는 비슷한 반투명 재질)

extension View {
    @ViewBuilder
    func glassBar() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        }
    }
}
