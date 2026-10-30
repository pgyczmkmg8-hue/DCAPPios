import SwiftUI
import WebKit

// MARK: - 설정 탭

struct SettingsView: View {
    @ObservedObject private var filters = FilterStore.shared
    @AppStorage(DCTheme.storageKey) private var themeRaw = AppTheme.dc.rawValue
    @AppStorage(DarkMode.followKey) private var darkFollowSystem = false
    @AppStorage(AlarmStore.bannerKey) private var alarmBanner = true
    @AppStorage(AppLock.lockKey) private var appLock = false
    @AppStorage(AppLock.blurKey) private var privacyBlur = false
    @State private var lockMessage: String?
    @AppStorage(DCNotify.enabledKey) private var notifyEnabled = false
    @State private var notifyResult: String?
    @State private var notifyChecking = false
    @EnvironmentObject private var router: AppRouter
    @State private var path: [SettingsPage] = []
    @State private var showTutorial = false
    @State private var currentID: String? = CredentialStore.currentAccountID

    private func runNotifyCheck() async {
        notifyChecking = true
        notifyResult = await DCNotify.check()
        notifyChecking = false
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                // 계정 / 테마
                Section {
                    NavigationLink(value: SettingsPage.account) {
                        LabeledContent {
                            Text(currentID ?? "로그인 안 함")
                        } label: {
                            Label("계정", systemImage: "person.crop.circle")
                        }
                    }
                    Picker(selection: $themeRaw) {
                        ForEach(AppTheme.allCases) { t in
                            Label {
                                Text(t.name)
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(Color(uiColor: t.bar))
                            }
                            .tag(t.rawValue)
                        }
                    } label: {
                        Label("테마", systemImage: "paintpalette")
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: themeRaw) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)   // 웹페이지 색도 다시 칠하기
                    }
                    Toggle(isOn: $darkFollowSystem) {
                        Label("다크모드를 시스템에 맞추기", systemImage: "circle.lefthalf.filled")
                    }
                    .onChange(of: darkFollowSystem) { _, _ in DarkMode.followChanged() }
                    NavigationLink { ControlBarOrderView() } label: {
                        Label("컨트롤바 버튼", systemImage: "arrow.up.arrow.down")
                    }
                    NavigationLink { AppIconSettingsView() } label: {
                        Label("앱 아이콘", systemImage: "app.badge")
                    }
                }

                // 도구 / 차단 / 세부 설정
                Section {
                    NavigationLink { ToolsSettingsView() } label: {
                        Label("도구", systemImage: "wrench.and.screwdriver")
                    }
                    NavigationLink(value: SettingsPage.block) {
                        LabeledContent {
                            Text(filters.settings.enabled ? "켜짐" : "꺼짐")
                        } label: {
                            Label("차단", systemImage: "hand.raised")
                        }
                    }
                    NavigationLink { DetailSettingsView() } label: {
                        Label("세부 설정", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("도구: 글쓰기 화면·댓글창·자짤 / 세부 설정: 화면 쓸기·사이트 메뉴·화면 정리")
                }

                // 알림 (백그라운드에서 디시 알림 확인 → iOS 알림) — DCNotify.featureAvailable이 false면 숨김
                if DCNotify.featureAvailable {
                Section {
                    Toggle("디시 알림 받기", isOn: $notifyEnabled)
                        .onChange(of: notifyEnabled) { _, on in
                            guard on else { DCNotify.schedule(); notifyResult = nil; return }
                            Task {
                                if await DCNotify.requestPermission() {
                                    DCNotify.schedule()
                                    await runNotifyCheck()
                                } else {
                                    notifyEnabled = false
                                    notifyResult = "설정 앱 → DCAPP → 알림에서 허용해주세요"
                                }
                            }
                        }
                    if notifyEnabled {
                        Button {
                            Task { await runNotifyCheck() }
                        } label: {
                            HStack {
                                Text("지금 확인해보기")
                                if notifyChecking { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(notifyChecking)
                    }
                    if let notifyResult {
                        Text(notifyResult).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } header: {
                    Text("알림")
                } footer: {
                    Text("앱이 백그라운드에 있을 때 iOS가 정한 간격(보통 15분~몇 시간)으로 디시 알림을 확인해요. 로그인 상태여야 하고, 앱을 위로 쓸어 완전히 종료하면 확인하지 않아요.")
                }
                }

                // 보안: 앱 잠금 / 전환 화면 가리기
                Section {
                    Toggle("\(AppLock.biometryName)로 앱 잠금", isOn: $appLock)
                        .onChange(of: appLock) { _, on in
                            guard on else { lockMessage = nil; return }
                            Task {
                                // 켤 때 한 번 인증해서 되는지 확인
                                if await AppLock.verifyForEnabling() {
                                    lockMessage = nil
                                } else {
                                    appLock = false
                                    lockMessage = "인증하지 못해서 켜지 않았어요. 기기 암호가 설정돼 있어야 해요."
                                }
                            }
                        }
                    Toggle("앱 전환 화면에서 가리기", isOn: $privacyBlur)
                    if let lockMessage {
                        Text(lockMessage).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("보안")
                } footer: {
                    Text("앱 잠금을 켜면 앱을 켜거나 다른 앱에서 돌아올 때 \(AppLock.biometryName)(안 되면 기기 암호)로 잠금을 풀어야 해요. '가리기'를 켜면 앱 전환 화면(멀티태스킹)에서 내용이 흐리게 보여요.")
                }

                // 디시 알림 (앱 안)
                Section {
                    Toggle("앱 사용 중 알림 배너 띄우기", isOn: $alarmBanner)
                } header: {
                    Text("알림")
                } footer: {
                    Text("내 글·댓글에 새 댓글이 달리면 화면 위에 배너로 잠깐 보여 줘요. 누르면 그 글로 가요. 받은 알림은 하단 바 '갤러리' → '알림' 탭에 쌓여요.")
                }

                // 디시콘
                Section("디시콘") {
                    NavigationLink {
                        BrowserView(startURL: DC.dccon, fallbackTitle: "디시콘 샵")
                    } label: {
                        Label("디시콘 샵", systemImage: "face.smiling")
                    }
                }

                // 백업
                Section("백업") {
                    NavigationLink { BackupView() } label: {
                        Label("설정 · 즐겨찾기 · 글 보관함 백업 / 복원", systemImage: "externaldrive")
                    }
                }

                // 튜토리얼 다시 보기 + 버전 정보 (맨 아래)
                Section {
                    Button { showTutorial = true } label: {
                        Label {
                            Text("튜토리얼 다시 보기").foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "questionmark.circle")
                        }
                    }
                    NavigationLink { AboutView() } label: {
                        LabeledContent {
                            Text(AboutView.versionString)
                        } label: {
                            Label("버전 정보/업데이트 확인", systemImage: "info.circle")
                        }
                    }
                }
            }
            .navigationTitle("설정")
            .fullScreenCover(isPresented: $showTutorial) {
                TutorialView { showTutorial = false }
            }
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .account: AccountSettingsView()
                case .block: BlockSettingsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { router.sheet = nil }
                }
            }
            .onAppear {
                // ⋮ → '차단 설정 가기'로 열었으면 차단 화면으로 바로
                if router.settingsAnchor == "block" { path = [.block] }
                router.settingsAnchor = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: DC.credentialsChanged)) { _ in
                currentID = CredentialStore.currentAccountID
            }
        }
    }
}

enum SettingsPage: Hashable { case account, block }

// MARK: - 계정

struct AccountSettingsView: View {
    @EnvironmentObject private var router: AppRouter
    @AppStorage("autoLogin") private var autoLogin = false
    @State private var accounts: [LoginCredential] = CredentialStore.all()
    @State private var currentID: String? = CredentialStore.currentAccountID
    @State private var showAddAccount = false
    @State private var switchTarget: LoginCredential?
    @State private var confirmLogout = false
    @State private var message: String?

    var body: some View {
        Form {
            // 계정 (여러 개 저장 → 눌러서 전환)
            Section {
                ForEach(accounts) { acc in
                    Button {
                        if acc.id != currentID { switchTarget = acc }
                    } label: {
                        HStack {
                            Image(systemName: acc.id == currentID ? "person.crop.circle.fill" : "person.crop.circle")
                                .foregroundStyle(acc.id == currentID ? DCTheme.accent : .secondary)
                                .font(.title3)
                            Text(acc.id).foregroundStyle(.primary)
                            Spacer()
                            if acc.id == currentID {
                                Text("로그인 중").font(.caption).foregroundStyle(DCTheme.accent)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { CredentialStore.remove(id: accounts[i].id) }
                }
                .onMove { CredentialStore.move(from: $0, to: $1) }

                Button { showAddAccount = true } label: {
                    Label("계정 추가", systemImage: "plus.circle")
                }
                if !accounts.isEmpty {
                    Toggle("로그인 화면에서 자동 로그인", isOn: $autoLogin)
                }
                NavigationLink { AnonInfoView() } label: {
                    Label("유동 닉네임·비밀번호", systemImage: "person.fill.questionmark")
                }
                NavigationLink {
                    BrowserView(startURL: DC.login, fallbackTitle: "로그인")
                } label: {
                    Label("로그인 페이지 직접 열기", systemImage: "person.badge.key")
                }
                Button("로그아웃", role: .destructive) { confirmLogout = true }
            } header: {
                Text("계정")
            } footer: {
                Text(accounts.isEmpty
                     ? "계정을 추가하거나, 로그인에 성공하면 저장할지 물어봐요. 비밀번호는 기기 키체인에 암호화돼요."
                     : "계정을 누르면 지금 로그인을 끝내고 그 계정으로 바로 로그인해요. 밀어서 삭제할 수 있어요. 맨 위 계정(가장 최근에 저장한 계정)이 로그인 화면에 자동으로 입력돼요.")
            }

            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("계정")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("로그아웃할까요?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("로그아웃", role: .destructive) { Task { await logout() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: DC.credentialsChanged)) { _ in
            accounts = CredentialStore.all()
            currentID = CredentialStore.currentAccountID
            if accounts.isEmpty { autoLogin = false }
        }
        .confirmationDialog(switchTarget.map { "\($0.id) 계정으로 전환할까요?" } ?? "",
                            isPresented: Binding(get: { switchTarget != nil }, set: { if !$0 { switchTarget = nil } }),
                            titleVisibility: .visible,
                            presenting: switchTarget) { acc in
            Button("전환") { router.switchAccount(acc) }
            Button("취소", role: .cancel) {}
        }
        .sheet(isPresented: $showAddAccount) { AddAccountView() }
    }

    private func logout() async {
        await DCSession.clear(notify: true)
        message = autoLogin
            ? "로그아웃했어요. (자동 로그인이 켜져 있어서 로그인 페이지를 열면 다시 로그인돼요)"
            : "로그아웃했어요."
    }
}

// MARK: - 차단

struct BlockSettingsView: View {
    @ObservedObject private var filters = FilterStore.shared
    @AppStorage(AutoMemo.enabledKey) private var autoMemo = false
    @AppStorage(AutoMemo.allKey) private var autoMemoAll = true

    var body: some View {
        Form {
            // 차단
            Section {
                Toggle("차단 기능 사용", isOn: $filters.settings.enabled)
                Picker("차단된 글·댓글·디시콘", selection: $filters.settings.display) {
                    ForEach(BlockDisplay.allCases) { Text($0.label).tag($0) }
                }
                NavigationLink { BlockedUsersView() } label: {
                    LabeledContent("차단한 유저", value: "\(filters.settings.users.count)")
                }
                NavigationLink { BlockedDcconsView() } label: {
                    LabeledContent("차단한 디시콘", value: "\(filters.settings.dccons.count)")
                }
                NavigationLink { KeywordsView() } label: {
                    LabeledContent("차단 키워드", value: "\(filters.settings.keywords.count)")
                }
                NavigationLink { MemoListView() } label: {
                    LabeledContent("유저 메모", value: "\(MemoStore.shared.memos.count)")
                }
            } header: {
                Text("차단")
            } footer: {
                Text("글 목록이나 댓글을 길게 누르면 작성자·디시콘을 바로 차단할 수 있어요. '차단됨 표시'는 그 자리에 회색 안내 칸을 남기고(탭하면 내용 보기), '완전히 숨김'은 흔적 없이 가려요.")
            }

            // 자동메모
            Section {
                Toggle("자동메모", isOn: $autoMemo)
                if autoMemo {
                    Picker("메모 범위", selection: $autoMemoAll) {
                        Text("모든 갤러리").tag(true)
                        Text("갤러리마다").tag(false)
                    }
                }
            } footer: {
                Text("글 목록을 불러올 때 메모가 없는 로그인 계정(유동 제외)에 닉네임이 아닌 아이디를 자동으로 메모해요. '갤러리마다'는 본 갤러리에서만 보이는 메모로 달아요.")
            }
        }
        .onChange(of: autoMemo) { _, _ in NotificationCenter.default.post(name: DC.filtersChanged, object: nil) }
        .onChange(of: autoMemoAll) { _, _ in NotificationCenter.default.post(name: DC.filtersChanged, object: nil) }
        .navigationTitle("차단")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 세부 설정 (앱 + 화면 정리)

struct DetailSettingsView: View {
    @ObservedObject private var filters = FilterStore.shared
    @AppStorage("fullSwipeBack") private var fullSwipeBack = true
    @AppStorage("swipeSensitivity") private var swipeSensitivity = 3.0
    @AppStorage("gallerySwipeOpensList") private var gallerySwipeOpensList = true
    @AppStorage("hideSiteHeader") private var hideSiteHeader = true
    @AppStorage("homeRankOnly") private var homeRankOnly = true
    @AppStorage("hideDory") private var hideDory = true

    private var sensitivityLabel: String {
        switch Int(swipeSensitivity) {
        case 1: "매우 둔감"
        case 2: "둔감"
        case 3: "보통"
        case 4: "민감"
        default: "매우 민감"
        }
    }

    var body: some View {
        Form {
            // 앱 아이콘 / 제스처
            Section("앱") {
                Toggle("화면을 오른쪽으로 쓸어 뒤로가기", isOn: $fullSwipeBack)
                    .onChange(of: fullSwipeBack) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                    }
                if fullSwipeBack {
                    Toggle("갤러리 목록에서 쓸면 '갤러리' 창 열기", isOn: $gallerySwipeOpensList)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("스와이프 민감도")
                            Spacer()
                            Text(sensitivityLabel).foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        HStack {
                            Text("둔감").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $swipeSensitivity, in: 1...5, step: 1)
                            Text("민감").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle("사이트 상단 메뉴 숨기기", isOn: $hideSiteHeader)
                    .onChange(of: hideSiteHeader) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                    }
                Toggle("홈 화면 대신 실북갤 순위 보기", isOn: $homeRankOnly)
                    .onChange(of: homeRankOnly) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                    }
                Toggle("댓글돌이 댓글 숨기기", isOn: $hideDory)
                    .onChange(of: hideDory) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                    }
            }

            // 글자 크기 (0 = 기본값, 되돌리기 누르면 전부 기본값)
            Section {
                FontSizeRow(title: "제목", key: "textSizeTitle", base: 18)
                FontSizeRow(title: "본문", key: "textSizeBody", base: 16)
                FontSizeRow(title: "댓글", key: "textSizeComment", base: 14)
                FontSizeRow(title: "목록", key: "textSizeList", base: 14)
                Button("기본으로 되돌리기", role: .destructive) {
                    for key in ["textSizeTitle", "textSizeBody", "textSizeComment", "textSizeList"] {
                        UserDefaults.standard.set(0, forKey: key)
                    }
                    NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                }
            } header: {
                Text("글자 크기")
            } footer: {
                Text("글 화면의 제목·본문·댓글과 글 목록 제목의 글자 크기입니다. 기본값은 제목 18, 본문 16, 댓글 14, 목록 14pt입니다.")
            }

            // 화면 정리
            Section {
                Toggle("실시간 베스트 알림 숨기기", isOn: $filters.settings.hideBestNotice)
                NavigationLink { HiddenElementsView() } label: {
                    LabeledContent("직접 숨긴 요소", value: "\(filters.settings.hiddenElements.count)")
                }
            } header: {
                Text("화면 정리")
            } footer: {
                Text("그래도 보이는 알림이나 배너는 컨트롤바 설정(⋮) → '요소 숨기기'를 누르고 직접 탭해서 숨길 수 있어요.")
            }

            PhotoSaveSettingsSection()
        }
        .navigationTitle("세부 설정")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 계정 추가

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var id = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("아이디", text: $id)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    SecureField("비밀번호", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("기기 키체인에 암호화해서 저장해요. 다른 기기나 백업으로는 넘어가지 않아요.")
                }
            }
            .navigationTitle("계정 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        CredentialStore.save(LoginCredential(id: id.trimmingCharacters(in: .whitespaces),
                                                             password: password))
                        dismiss()
                    }
                    .disabled(id.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 차단한 유저

struct BlockedUsersView: View {
    @ObservedObject private var filters = FilterStore.shared
    @State private var kind: BlockedUser.Kind = .id
    @State private var value = ""

    var body: some View {
        List {
            Section {
                Picker("종류", selection: $kind) {
                    ForEach(BlockedUser.Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField(placeholder, text: $value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("추가") {
                        filters.addUser(kind: kind, value: value)
                        value = ""
                    }
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("직접 추가")
            } footer: {
                Text("비로그인(유동) 유저는 IP 앞 두 자리(예: 118.235)로 구분돼요. 닉네임 차단은 같은 닉네임을 쓰는 모든 사람이 가려져요.")
            }

            Section("차단 목록") {
                if filters.settings.users.isEmpty {
                    Text("차단한 유저가 없어요").foregroundStyle(.secondary)
                }
                ForEach(filters.settings.users) { u in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(u.memo.isEmpty ? u.value : u.memo)
                        Text("\(u.kind.label) · \(u.value) · \(u.gallery.map { "\($0) 갤러리만" } ?? "모든 갤러리")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { filters.settings.users.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("차단한 유저")
        .toolbar { EditButton() }
    }

    private var placeholder: String {
        switch kind {
        case .id: "아이디 (갤로그 주소 끝부분)"
        case .ip: "예: 118.235"
        case .nick: "닉네임"
        }
    }
}

// MARK: - 차단한 디시콘

struct BlockedDcconsView: View {
    @ObservedObject private var filters = FilterStore.shared

    var body: some View {
        List {
            if filters.settings.dccons.isEmpty {
                Text("댓글의 디시콘을 길게 눌러서 차단할 수 있어요.")
                    .foregroundStyle(.secondary)
            }
            ForEach(filters.settings.dccons) { d in
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: d.imageURL)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "face.smiling").foregroundStyle(.secondary)
                    }
                    .frame(width: 48, height: 48)
                    Text(String(d.key.prefix(16)) + "…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { filters.settings.dccons.remove(atOffsets: $0) }
        }
        .navigationTitle("차단한 디시콘")
        .toolbar { EditButton() }
    }
}

// MARK: - 차단 키워드

struct KeywordsView: View {
    @ObservedObject private var filters = FilterStore.shared
    @State private var input = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("차단할 단어", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("추가", action: add)
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("제목·본문·댓글·닉네임에 이 단어가 들어가면 가려져요. 대소문자는 구분하지 않아요.")
            }
            Section("키워드 목록") {
                if filters.settings.keywords.isEmpty {
                    Text("차단 키워드가 없어요").foregroundStyle(.secondary)
                }
                ForEach(filters.settings.keywords, id: \.self) { Text($0) }
                    .onDelete { filters.settings.keywords.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("차단 키워드")
        .toolbar { EditButton() }
    }

    private func add() {
        filters.addKeyword(input)
        input = ""
    }
}

// MARK: - 직접 숨긴 요소

struct HiddenElementsView: View {
    @ObservedObject private var filters = FilterStore.shared
    @State private var selector = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("CSS 선택자 (고급)", text: $selector)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button("추가") {
                        filters.addHidden(selector: selector, memo: "직접 입력")
                        selector = ""
                    }
                    .disabled(selector.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("보통은 브라우저 화면의 ⋯ → '요소 숨기기'로 탭해서 추가하는 게 편해요. 잘못 숨겼으면 여기서 지우면 다시 보여요.")
            }
            Section("숨긴 요소") {
                if filters.settings.hiddenElements.isEmpty {
                    Text("직접 숨긴 요소가 없어요").foregroundStyle(.secondary)
                }
                ForEach(filters.settings.hiddenElements) { h in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.memo.isEmpty ? "(내용 없음)" : h.memo).lineLimit(1)
                        Text(h.selector).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .onDelete { filters.settings.hiddenElements.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("직접 숨긴 요소")
        .toolbar { EditButton() }
    }
}


/// 유동(비로그인)으로 쓸 때 자동으로 채울 닉네임·비밀번호
struct AnonInfoView: View {
    @State private var nick = AnonStore.nick
    @State private var password = AnonStore.password

    var body: some View {
        Form {
            Section {
                TextField("닉네임 (비우면 갤러리 기본 닉네임)", text: $nick)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("비밀번호", text: $password)
            } footer: {
                Text("로그아웃 상태에서 댓글·글쓰기 칸에 자동으로 채워요. 댓글칸에 직접 입력해도 여기에 저장돼요. 비밀번호는 이 기기 키체인에 암호화해서 보관해요.")
            }
        }
        .navigationTitle("유동 닉네임·비밀번호")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            AnonStore.nick = nick.trimmingCharacters(in: .whitespaces)
            AnonStore.password = password
            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)   // 페이지 스크립트에 새 값 반영
        }
    }
}


/// 설정 → 컨트롤바 버튼 순서 (끌어서 바꾸기)
struct ControlBarOrderView: View {
    @AppStorage(ControlBarItem.storageKey) private var raw = ""
    @AppStorage(ControlBarItem.menuInTopBarKey) private var menuInTopBar = true
    @AppStorage(ControlBarItem.verticalLandscapeKey) private var verticalInLandscape = true
    @AppStorage(ControlBarItem.autoHideKey) private var autoHideBar = true
    @AppStorage("sideBarOffsetY") private var sideBarOffsetY = 0.0
    @AppStorage(ControlBarItem.mirroredKey) private var mirrored = false
    @AppStorage(ControlBarItem.verticalPortraitKey) private var verticalInPortrait = ControlBarItem.defaultVerticalInPortrait

    private var items: [ControlBarItem] { ControlBarItem.order(from: raw) }

    var body: some View {
        List {
            Section {
                ForEach(items.filter { $0 != .menu }) { item in
                    Label(item.label, systemImage: item.icon)
                }
                .onMove { from, to in
                    var list = items.filter { $0 != .menu }
                    list.move(fromOffsets: from, toOffset: to)
                    raw = ControlBarItem.raw(from: list + [.menu])
                }
                if !menuInTopBar {
                    LabeledContent {
                        Text("맨 끝 고정").font(.caption)
                    } label: {
                        Label(ControlBarItem.menu.label, systemImage: ControlBarItem.menu.icon)
                    }
                    .foregroundStyle(.secondary)
                    .moveDisabled(true)
                }
            } footer: {
                Text("오른쪽 손잡이(≡)를 끌어서 순서를 바꿔요. 위쪽이 가로 배치에서는 왼쪽, 세로 배치에서는 위쪽이에요. 설정 ⋮은 평소에 숨겨 두고, 막대를 밀면(가로: 오른쪽→왼쪽, 세로: 아래→위) 설정 · 차단(탭해서) · 메모하기 · 전체 검색 · 링크 공유 칸이 나와요. 반대로 밀면 원래대로 돌아와요. 글을 볼 때 나오는 댓글 새로고침 버튼은 따로 떠요.")
            }
            // 모든 기기에 적용 (가로로 쓸 때 / 세로로 쓸 때 따로)
            Section {
                Picker("가로로 쓸 때", selection: $verticalInLandscape) {
                    Text("가로").tag(false)
                    Text("세로").tag(true)
                }
                Picker("세로로 쓸 때", selection: $verticalInPortrait) {
                    Text("가로").tag(false)
                    Text("세로").tag(true)
                }
            } header: {
                Text("배치")
            } footer: {
                Text("가로: 화면 아래쪽에 가로로. 세로: 화면 오른쪽 가운데에 세로로.\n휴대폰을 가로로 쓸 때 세로 막대는 아이콘만 보여요.")
            }
            Section {
                Toggle("좌우반전", isOn: $mirrored)
            } footer: {
                Text("켜면 세로 막대·접은 버튼·새로고침 버튼이 왼쪽에 오고, 가로 막대는 왼쪽→오른쪽으로 밀면 둘째 칸, 오른쪽→왼쪽으로 밀면 접혀요.")
            }
            Section {
                Button("세로 막대 위치 가운데로") { sideBarOffsetY = 0 }
                    .disabled(sideBarOffsetY == 0)
            } footer: {
                Text("세로 막대는 1초 꾹 누른 뒤 위아래로 끌어서 옮길 수 있어요. 옮긴 위치는 저장돼요.")
            }
            Section {
                Toggle("스크롤할 때 숨기기", isOn: $autoHideBar)
            } footer: {
                Text("페이지를 스크롤하는 동안 컨트롤바가 화면 아래(세로 막대는 오른쪽)로 들어가고, 멈추면 다시 나와요.")
            }
            Section {
                Toggle("⋮ 메뉴를 상단바 오른쪽에 두기", isOn: $menuInTopBar)
            } footer: {
                Text("켜면 ⋮ 메뉴가 상단바 오른쪽 위에 나오고 컨트롤바에서는 빠져요. (글쓰기 화면에서는 상단바 왼쪽)")
            }
            Section {
                Button("기본 순서로") { raw = "" }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("컨트롤바 버튼")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 도구 (글쓰기 · 댓글 · 자짤)

struct ToolsSettingsView: View {
    @ObservedObject private var autoImages = AutoImageStore.shared
    @AppStorage("dockComment") private var dockComment = true
    @AppStorage(WebViewModel.nativeWriteKey) private var nativeWrite = true
    @AppStorage(WriteImageSize.key) private var imageSize = WriteImageSize.original.rawValue

    var body: some View {
        Form {
            // 글쓰기
            Section {
                Picker("글쓰기 화면", selection: $nativeWrite) {
                    Text("앱 글쓰기").tag(true)
                    Text("디시 원래 화면").tag(false)
                }
                if nativeWrite {
                    Picker("사진 크기", selection: $imageSize) {
                        ForEach(WriteImageSize.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
            } header: {
                Text("글쓰기")
            } footer: {
                Text(nativeWrite
                     ? "앱이 만든 글쓰기 화면으로 써요. 사진·자짤·디시콘·동영상·유튜브·투표와 글자 꾸미기(굵게·기울임·크기·색)를 쓸 수 있고, 등록은 디시 글쓰기 페이지로 그대로 보내져요. 키보드 위 도구줄 맨 오른쪽 나침반 버튼을 누르면 디시 원래 화면으로 바꿔서 쓸 수 있어요.\n사진 크기는 디시 '이미지 크기 일괄 설정'과 같아요. 원본 크기를 고르면 사진을 줄이지 않고 올려요. 가로 크기보다 작은 사진은 그대로 올라가요."
                     : "디시 모바일 웹 글쓰기 화면을 그대로 써요. 사진 크기는 디시 글쓰기 화면의 설정(톱니) 버튼에서 바꿀 수 있어요.")
            }

            // 댓글
            Section {
                Toggle("댓글창을 키보드 위에 붙이기", isOn: $dockComment)
                    .onChange(of: dockComment) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                    }
            } header: {
                Text("댓글")
            } footer: {
                Text("댓글 입력칸을 누르면 닉네임·비밀번호·코드·디시콘 버튼이 있는 댓글창 전체가 키보드 바로 위로 올라와요. 댓글창 바깥을 누르면 원래 자리로 돌아가요.")
            }

            // 자짤
            Section {
                NavigationLink { AutoImageSettingsView() } label: {
                    LabeledContent {
                        Text(autoImages.settings.enabled ? "\(autoImages.settings.images.count)장 · 켜짐" : "꺼짐")
                    } label: {
                        Label("자짤", systemImage: "photo.on.rectangle")
                    }
                }
            } header: {
                Text("자짤")
            } footer: {
                Text("글쓰기 화면에 미리 등록한 사진을 자동으로 첨부해요.")
            }
        }
        .navigationTitle("도구")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 글자 크기 한 줄 (스테퍼). 0이면 기본값(base)을 쓰고, 기본값과 같게 고치면 0으로 저장
private struct FontSizeRow: View {
    let title: String
    let base: Int
    @AppStorage private var stored: Int

    init(title: String, key: String, base: Int) {
        self.title = title
        self.base = base
        _stored = AppStorage(wrappedValue: 0, key)
    }

    var body: some View {
        let current = stored == 0 ? base : stored
        Stepper(value: Binding(get: { current }, set: { stored = $0 == base ? 0 : $0 }), in: 10...28) {
            LabeledContent(title, value: "\(current)pt")
        }
        .onChange(of: stored) { _, _ in
            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
        }
    }
}
