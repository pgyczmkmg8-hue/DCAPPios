import SwiftUI
import WebKit

// MARK: - 설정 탭

struct SettingsView: View {
    @ObservedObject private var filters = FilterStore.shared
    @AppStorage(DCTheme.storageKey, store: Profile.defaults) private var themeRaw = AppTheme.dc.rawValue
    @AppStorage(DarkMode.followKey, store: Profile.defaults) private var darkFollowSystem = false
    @AppStorage(AlarmStore.bannerKey, store: Profile.defaults) private var alarmBanner = true
    @AppStorage(AppLock.lockKey, store: Profile.defaults) private var appLock = false
    @AppStorage(AppLock.blurKey, store: Profile.defaults) private var privacyBlur = false
    @AppStorage(AppLock.graceKey, store: Profile.defaults) private var lockGrace = 0
    @State private var lockMessage: String?
    @AppStorage(DCNotify.enabledKey, store: Profile.defaults) private var notifyEnabled = false
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
                    .onChangeCompat(of: themeRaw) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)   // 웹페이지 색도 다시 칠하기
                    }
                    Toggle(isOn: $darkFollowSystem) {
                        Label("다크모드를 시스템에 맞추기", systemImage: "circle.lefthalf.filled")
                    }
                    .onChangeCompat(of: darkFollowSystem) { _, _ in DarkMode.followChanged() }
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
                            Label("차단 / 메모", systemImage: "hand.raised")
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
                        .onChangeCompat(of: notifyEnabled) { _, on in
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
                        .onChangeCompat(of: appLock) { _, on in
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
                    if appLock {
                        Picker("다시 잠그기까지", selection: $lockGrace) {
                            Text("바로").tag(0)
                            Text("1분").tag(1)
                            Text("3분").tag(3)
                            Text("5분").tag(5)
                            Text("10분").tag(10)
                            Text("30분").tag(30)
                        }
                    }
                    Toggle("앱 전환 화면에서 가리기", isOn: $privacyBlur)
                    NavigationLink { CoverSettingsView() } label: {
                        Label("가림막 꾸미기", systemImage: "paintbrush")
                    }
                    if let lockMessage {
                        Text(lockMessage).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("보안")
                } footer: {
                    Text("앱 잠금을 켜면 앱을 켜거나 다른 앱에서 돌아올 때 \(AppLock.biometryName)(안 되면 기기 암호)로 잠금을 풀어야 해요. 생체인식을 취소하면 기기 암호로 풀 수 있어요. '다시 잠그기까지'를 정하면 다른 앱에 갔다가 그 시간 안에 돌아올 땐 다시 묻지 않아요(앱을 완전히 종료하면 항상 물어요). '가리기'를 켜면 앱 전환 화면(멀티태스킹)에서 내용이 흐리게 보여요.")
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
                        StandaloneBrowserView(startURL: DC.dccon, fallbackTitle: "디시콘 샵")
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
    @AppStorage("autoLogin", store: Profile.defaults) private var autoLogin = false
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
                    StandaloneBrowserView(startURL: DC.login, fallbackTitle: "로그인")
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

/// 자동메모 '선택한 갤러리만'에서 고르는 갤러리 목록 (방문한 갤러리 기준)
struct AutoMemoGalleryList: View {
    @ObservedObject private var visited = VisitedStore.shared
    @State private var selected = Set(AutoMemo.selectedIDs)

    private var galleries: [Gallery] {
        var seen = Set<String>()
        return visited.items.map(\.gallery).filter { seen.insert($0.galleryID).inserted }
    }

    var body: some View {
        List {
            Section {
                ForEach(galleries) { g in
                    Toggle(g.name, isOn: Binding(
                        get: { selected.contains(g.galleryID) },
                        set: { on in
                            if on { selected.insert(g.galleryID) } else { selected.remove(g.galleryID) }
                            Profile.defaults.set(Array(selected).sorted(), forKey: AutoMemo.selectedKey)
                            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                        }))
                }
            } footer: {
                Text("방문한 적 있는 갤러리만 나와요. 여기서 고른 갤러리의 글 목록에서만 자동메모를 달아요.")
            }
        }
        .navigationTitle("갤러리 고르기")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BlockSettingsView: View {
    @ObservedObject private var filters = FilterStore.shared
    @AppStorage(AutoMemo.enabledKey, store: Profile.defaults) private var autoMemo = false
    @AppStorage(IdCode.key, store: Profile.defaults) private var showIdCode = false
    @State private var autoMemoMode = AutoMemo.mode
    @ObservedObject private var memoStore = MemoStore.shared
    @State private var confirmDeleteIDMemos = false

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
                NavigationLink { BlockedImagesView() } label: {
                    LabeledContent("차단한 이미지", value: "\(filters.settings.images.count)")
                }
                NavigationLink { KeywordsView() } label: {
                    LabeledContent("차단 키워드", value: "\(filters.settings.keywords.count)")
                }
                NavigationLink { AdvancedBlockView() } label: {
                    LabeledContent("고급 차단 (유저+키워드)", value: "\(filters.settings.advancedRules.count)")
                }
                NavigationLink { MemoListView() } label: {
                    LabeledContent("유저 메모", value: "\(MemoStore.shared.memos.count)")
                }
            } header: {
                Text("차단")
            } footer: {
                Text("글 목록이나 댓글을 길게 누르면 작성자·디시콘을 바로 차단할 수 있어요. '차단됨 표시'는 그 자리에 회색 안내 칸을 남기고(탭하면 내용 보기), '완전히 숨김'은 흔적 없이 가려요.")
            }

            Section {
                Toggle("특수문자 끼워넣기 무시", isOn: $filters.settings.ignoreSymbols)
                Toggle("공백 끼워넣기 무시", isOn: $filters.settings.ignoreSpaces)
            } header: {
                Text("단어·닉네임 비교")
            } footer: {
                Text("특수문자 끼워넣기 무시를 켜면 '야미큐레' 차단이 '야$미@@큐레'처럼 특수문자를 끼운 글도 가려요.\n공백 끼워넣기 무시를 켜면 '야미큐레' 차단이 '야 미 큐 레'도 가려요. 짧은 단어는 띄어 쓴 다른 말에도 걸릴 수 있어요 (예: '시발' → '이 시 발표').")
            }

            // 고닉 식별코드 보기 (자동메모와 같이 쓸 수 없음)
            Section {
                Toggle("고닉 식별코드 보기", isOn: Binding(get: { showIdCode && !autoMemo }, set: { showIdCode = $0 }))
                    .disabled(autoMemo)
            } footer: {
                Text(autoMemo
                     ? "자동메모가 켜져 있어서 쓸 수 없어요. 자동메모를 끄면 쓸 수 있어요."
                     : "메모가 없는 고닉(로그인 계정)의 메모 자리에 식별코드(아이디)를 보여 줘요. 메모로 저장하지는 않고 보여 주기만 해요. 직접 단 메모가 있으면 그 메모가 보여요. 자동메모와는 같이 쓸 수 없어요.")
            }

            // 식별코드 메모 일괄 삭제 (자동메모가 달아 둔 '내용 = 식별코드' 메모)
            Section {
                Button(role: .destructive) { confirmDeleteIDMemos = true } label: {
                    Text("식별코드와 같은 메모 일괄 삭제 (\(memoStore.idSameAsTextMemos.count)개)")
                }
                .disabled(memoStore.idSameAsTextMemos.isEmpty)
            } footer: {
                Text("고닉(아이디) 메모 중 내용이 식별코드와 똑같은 것만 지워요. 자동메모가 달아 둔 메모예요. 직접 다른 내용으로 쓴 메모와 닉네임·IP 메모는 그대로 둬요.")
            }
            .confirmationDialog("식별코드와 같은 메모 \(memoStore.idSameAsTextMemos.count)개를 지울까요?", isPresented: $confirmDeleteIDMemos, titleVisibility: .visible) {
                Button("삭제", role: .destructive) { memoStore.removeIDSameAsText() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("되돌릴 수 없어요. 자동메모가 켜져 있으면 목록을 불러올 때 다시 달릴 수 있어요.")
            }

            // 자동메모
            Section {
                Toggle("자동메모", isOn: $autoMemo)
                if autoMemo {
                    Picker("메모 범위", selection: $autoMemoMode) {
                        ForEach(AutoMemo.Mode.allCases) { m in Text(m.label).tag(m) }
                    }
                    if autoMemoMode == .selected {
                        NavigationLink("갤러리 고르기") { AutoMemoGalleryList() }
                    }
                }
            } footer: {
                Text("글 목록을 불러올 때 메모가 없는 로그인 계정(유동 제외)에 닉네임이 아닌 아이디를 자동으로 메모해요. '갤러리마다'는 본 갤러리에서만 보이는 메모로 달아요. '선택한 갤러리만'은 고른 갤러리에서만 달아요.")
            }
        }
        .onChangeCompat(of: autoMemo) { _, on in
            if on { showIdCode = false }      // 자동메모를 켜면 식별코드 보기는 저절로 꺼짐 (같이 쓸 수 없음)
            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
        }
        .onChangeCompat(of: showIdCode) { _, _ in NotificationCenter.default.post(name: DC.filtersChanged, object: nil) }
        .onChangeCompat(of: autoMemoMode) { _, v in
            Profile.defaults.set(v.rawValue, forKey: AutoMemo.modeKey)
            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
        }
        .navigationTitle("차단 / 메모")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 세부 설정 (앱 + 화면 정리)

struct DetailSettingsView: View {
    @ObservedObject private var filters = FilterStore.shared
    @AppStorage("fullSwipeBack", store: Profile.defaults) private var fullSwipeBack = true
    @AppStorage("swipeSensitivity", store: Profile.defaults) private var swipeSensitivity = 3.0
    @AppStorage("gallerySwipeOpensList", store: Profile.defaults) private var gallerySwipeOpensList = true
    @AppStorage("hideSiteHeader", store: Profile.defaults) private var hideSiteHeader = true
    @AppStorage("homeRankOnly", store: Profile.defaults) private var homeRankOnly = true
    @AppStorage("hideDory", store: Profile.defaults) private var hideDory = true
    @AppStorage(ControlBarItem.autoHideKey, store: Profile.defaults) private var autoHideBar = true
    @AppStorage("barGlassTint", store: Profile.defaults) private var barGlassTint = 0.0

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
                    .onChangeCompat(of: fullSwipeBack) { _, _ in
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
                    .onChangeCompat(of: hideSiteHeader) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                    }
                Toggle("홈 화면 대신 실북갤 순위 보기", isOn: $homeRankOnly)
                    .onChangeCompat(of: homeRankOnly) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                    }
                Toggle("댓글돌이 댓글 숨기기", isOn: $hideDory)
                    .onChangeCompat(of: hideDory) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                    }
            }

            // 컨트롤바 유리 진하기 (0 = 가장 투명)
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("컨트롤바 유리 진하기")
                        Spacer()
                        Text("\(Int(barGlassTint * 100))%").foregroundStyle(.secondary)
                    }
                    Slider(value: $barGlassTint, in: 0...1, step: 0.05)
                }
                Button("기본(가장 투명)으로", role: .destructive) { barGlassTint = 0 }
                    .disabled(barGlassTint == 0)
            } footer: {
                Text("0%가 가장 투명합니다. 올리면 유리 위에 밝은 막이 더해져 버튼이 또렷해져요.")
            }

            // 스크롤할 때 컨트롤바·새로고침 숨기기 (컨트롤바 버튼 화면과 같은 설정)
            Section {
                Toggle("스크롤할 때 컨트롤바·새로고침 숨기기", isOn: $autoHideBar)
                if autoHideBar { BarAutoHideStylePicker() }
            } footer: {
                Text(BarAutoHideStylePicker.footer)
            }

            // 글자 크기 (0 = 기본값, 되돌리기 누르면 전부 기본값)
            Section {
                FontSizeRow(title: "제목", key: "textSizeTitle", base: 16)
                FontSizeRow(title: "본문", key: "textSizeBody", base: 16)
                FontSizeRow(title: "목록", key: "textSizeList", base: 14)
                Button("기본으로 되돌리기", role: .destructive) {
                    for key in ["textSizeTitle", "textSizeBody", "textSizeList"] {
                        Profile.defaults.set(0, forKey: key)
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
                ForEach(filters.settings.users.indices, id: \.self) { i in
                    let u = filters.settings.users[i]
                    NavigationLink {
                        BlockScopeDetail(title: u.memo.isEmpty ? u.value : u.memo,
                                         detail: "\(u.kind.label) · \(u.value)",
                                         gallery: Binding(
                                            get: { i < filters.settings.users.count ? filters.settings.users[i].gallery ?? "" : "" },
                                            set: { if i < filters.settings.users.count { filters.settings.users[i].gallery = $0.isEmpty ? nil : $0 } }),
                                         onRemove: { if i < filters.settings.users.count { filters.settings.users.remove(at: i) } })
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.memo.isEmpty ? u.value : u.memo)
                            Text("\(u.kind.label) · \(u.value) · \(GalleryScopeLabel.text(u.gallery))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
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

/// 글 속 사진 차단 목록: 가리는 방식, 목록(썸네일), 빼기
struct BlockedImagesView: View {
    @ObservedObject private var filters = FilterStore.shared

    var body: some View {
        List {
            Section {
                Picker("차단된 이미지 표시", selection: $filters.settings.imageBlockStyle) {
                    ForEach(ImageBlockStyle.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("글 속에서 차단한 사진만 여기서 고른 방식으로 가려져요. 가려진 사진을 짧게 누르면 잠깐 보이고, 길게 누르면 차단을 풀 수 있어요. 같은 사진을 다른 이름으로 다시 올려도 찾아서 가려요.")
            }

            Section {
                if filters.settings.images.isEmpty {
                    Text("차단한 이미지가 없어요. 글 속 사진을 길게 누르거나 사진 보기에서 차단할 수 있어요.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filters.settings.images) { img in
                    HStack(spacing: 12) {
                        BlockedImageThumb(urlString: img.src)
                        Text(img.hash == nil ? "같은 사진 찾기 준비 중" : "다시 올린 사진도 찾아요")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    let keys = offsets.map { filters.settings.images[$0].key }
                    keys.forEach { filters.removeImage(key: $0) }
                }
            }
        }
        .navigationTitle("차단한 이미지")
        .toolbar { EditButton() }
    }
}

/// 차단한 사진의 작은 미리보기 (디시 사진 서버는 Referer가 필요해서 직접 받음)
private struct BlockedImageThumb: View {
    let urlString: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: urlString) {
            guard image == nil, let data = await ImageBlockHash.download(urlString) else { return }
            image = UIImage(data: data)
        }
    }
}

// MARK: - 차단 키워드

struct KeywordsView: View {
    @ObservedObject private var filters = FilterStore.shared
    @State private var input = ""
    @State private var galleryID = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("차단할 단어 (쉼표로 여러 개)", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("추가", action: add)
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                GalleryScopeRow(galleryID: $galleryID)
            } footer: {
                Text("제목·본문·댓글·닉네임에 이 단어가 들어가면 가려져요. 대소문자는 구분하지 않아요. 쉼표로 여러 단어를 넣으면 모두 들어간 글·댓글만 가려요 (예: 안녕하세요, 야미큐레). 적용 범위에서 갤러리를 고르면 그 갤러리에서만 가려요.\n특수문자·공백 끼워넣기 무시는 차단 설정의 '단어·닉네임 비교'에서 켤 수 있어요.")
            }
            Section("키워드 목록") {
                if filters.settings.keywords.isEmpty {
                    Text("차단 키워드가 없어요").foregroundStyle(.secondary)
                }
                ForEach(filters.settings.keywords.indices, id: \.self) { i in
                    let k = filters.settings.keywords[i]
                    NavigationLink {
                        BlockScopeDetail(title: k.displayText, detail: "차단 키워드",
                                         gallery: Binding(
                                            get: { i < filters.settings.keywords.count ? filters.settings.keywords[i].gallery ?? "" : "" },
                                            set: { if i < filters.settings.keywords.count { filters.settings.keywords[i].gallery = $0.isEmpty ? nil : $0 } }),
                                         onRemove: { if i < filters.settings.keywords.count { filters.settings.keywords.remove(at: i) } })
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k.displayText)
                            Text((BlockMatch.terms(k.word).count >= 2 ? "모두 포함 · " : "") + GalleryScopeLabel.text(k.gallery))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                    .onDelete { filters.settings.keywords.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("차단 키워드")
        .toolbar { EditButton() }
    }

    private func add() {
        filters.addKeyword(input, gallery: galleryID.trimmingCharacters(in: .whitespaces))
        input = ""
    }
}

// MARK: - 차단 항목 상세 (적용 범위 바꾸기)

/// 차단 목록의 항목을 눌렀을 때: 모든 갤러리 / 고른 갤러리로 바꾸기, 차단 해제
struct BlockScopeDetail: View {
    let title: String
    let detail: String
    @Binding var gallery: String
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                GalleryScopeRow(galleryID: $gallery)
            } footer: {
                Text("'모든 갤러리'면 어디서든 차단하고, 갤러리를 고르면 그 갤러리들에서만 차단해요. 여러 개를 고를 수 있어요.")
            }
            Section {
                Button("차단 해제", role: .destructive) { onRemove(); dismiss() }
            }
        }
        .navigationTitle("차단 항목")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 갤러리 범위 고르기 (차단 키워드·고급 차단)

enum GalleryScopeLabel {
    /// "모든 갤러리" / "○○ 갤러리만" / "○○ 외 2개 갤러리만"
    @MainActor static func text(_ scope: String?) -> String {
        let ids = GalleryScope.ids(scope)
        if ids.isEmpty { return "모든 갤러리" }
        let first = GalleryNames.name(ids[0])
        return ids.count == 1 ? "\(first) 갤러리만" : "\(first) 외 \(ids.count - 1)개 갤러리만"
    }
}

/// "적용 범위: 모든 갤러리 / 고른 갤러리(여러 개 가능)" 한 줄 — 누르면 즐겨찾기·방문한 갤러리에서 찾아 고름
struct GalleryScopeRow: View {
    @Binding var galleryID: String
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var visited = VisitedStore.shared
    @State private var showing = false

    private var all: [Gallery] {
        var seen = Set<String>()
        return (favorites.items + visited.items.map(\.gallery)).filter { seen.insert($0.galleryID).inserted }
    }

    var body: some View {
        Button { showing = true } label: {
            HStack {
                Text("적용 범위").foregroundStyle(.primary)
                Spacer()
                Text(GalleryScopeLabel.text(galleryID).replacingOccurrences(of: " 갤러리만", with: "")).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $showing) {
            GalleryScopeSheet(galleryID: $galleryID, galleries: all)
        }
    }
}

private struct GalleryScopeSheet: View {
    @Binding var galleryID: String
    let galleries: [Gallery]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var selected: [String] { GalleryScope.ids(galleryID) }
    private var q: String { query.trimmingCharacters(in: .whitespaces) }
    private var matches: [Gallery] {
        guard !q.isEmpty else { return galleries }
        let k = q.lowercased()
        return galleries.filter { $0.name.lowercased().contains(k) || $0.galleryID.lowercased().contains(k) }
    }
    /// 목록에 없는 (직접 입력한) 선택 갤러리
    private var extras: [String] { selected.filter { id in !galleries.contains { $0.galleryID == id } } }

    private func toggle(_ id: String) {
        var cur = selected
        if let i = cur.firstIndex(of: id) { cur.remove(at: i) } else { cur.append(id) }
        galleryID = GalleryScope.join(cur) ?? ""
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    galleryID = ""
                } label: {
                    HStack {
                        Text("모든 갤러리").foregroundStyle(.primary)
                        Spacer()
                        if selected.isEmpty { Image(systemName: "checkmark") }
                    }
                }
                if !extras.isEmpty {
                    Section("직접 입력한 갤러리") {
                        ForEach(extras, id: \.self) { id in
                            Button { toggle(id) } label: {
                                HStack {
                                    Text(id).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Section {
                    if matches.isEmpty { Text("찾는 갤러리가 없어요").foregroundStyle(.secondary) }
                    ForEach(matches) { g in
                        Button { toggle(g.galleryID) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.name).foregroundStyle(.primary)
                                    Text("\(g.kind.label) · \(g.galleryID)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected.contains(g.galleryID) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } header: {
                    Text("즐겨찾기 · 방문한 갤러리")
                } footer: {
                    Text("여러 갤러리를 고를 수 있어요. 아무것도 고르지 않으면 모든 갤러리예요.")
                }
                if !q.isEmpty, q.range(of: "^[A-Za-z0-9_$]+$", options: .regularExpression) != nil,
                   !galleries.contains(where: { $0.galleryID == q }), !selected.contains(q) {
                    Section("직접 입력") {
                        Button("'\(q)' 갤러리 ID 추가") { toggle(q); query = "" }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "갤러리 이름이나 ID로 찾기")
            .navigationTitle("적용 범위")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }
}

// MARK: - 고급 차단 (특정 유저가 특정 단어를 말할 때만)

struct AdvancedBlockView: View {
    @ObservedObject private var filters = FilterStore.shared
    @State private var kind: BlockedUser.Kind = .ip
    @State private var value = ""
    @State private var words = ""
    @State private var galleryID = ""

    private var wordList: [String] {
        words.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        List {
            Section {
                Picker("대상", selection: $kind) {
                    ForEach(BlockedUser.Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField(kind == .ip ? "IP 앞 두 자리 (예: 117.111)" : kind == .id ? "아이디(식별코드)" : "닉네임", text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("단어 (쉼표로 묶으면 모두 들어간 것만)", text: $words)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                GalleryScopeRow(galleryID: $galleryID)
                Button("추가") {
                    let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !v.isEmpty, !wordList.isEmpty else { return }
                    let g = galleryID.trimmingCharacters(in: .whitespaces)
                    filters.settings.advancedRules.append(AdvancedBlockRule(kind: kind, value: v, keywords: wordList, gallery: g.isEmpty ? nil : g))
                    value = ""; words = ""; galleryID = ""
                }
                .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty || wordList.isEmpty)
            } header: {
                Text("새 규칙")
            } footer: {
                Text("통신사 IP처럼 여러 사람이 같이 쓰는 대상 중 특정인만 가리고 싶을 때 써요. 그 대상이 쓴 글·댓글에 입력한 단어가 모두 들어 있을 때만 가려져요 (쉼표로 나눈 단어 전부). 단어는 대소문자를 구분하지 않아요.\n특수문자·공백 끼워넣기 무시는 차단 설정의 '단어·닉네임 비교'에서 켤 수 있어요.")
            }
            Section("규칙 목록") {
                if filters.settings.advancedRules.isEmpty {
                    Text("고급 차단 규칙이 없어요").foregroundStyle(.secondary)
                }
                ForEach(filters.settings.advancedRules.indices, id: \.self) { i in
                    let r = filters.settings.advancedRules[i]
                    NavigationLink {
                        BlockScopeDetail(title: "\(r.kind.label) \(r.value)",
                                         detail: r.wordsLabel,
                                         gallery: Binding(
                                            get: { i < filters.settings.advancedRules.count ? filters.settings.advancedRules[i].gallery ?? "" : "" },
                                            set: { if i < filters.settings.advancedRules.count { filters.settings.advancedRules[i].gallery = $0.isEmpty ? nil : $0 } }),
                                         onRemove: { if i < filters.settings.advancedRules.count { filters.settings.advancedRules.remove(at: i) } })
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.kind.label) \(r.value)")
                            Text(r.wordsLabel + " · " + GalleryScopeLabel.text(r.gallery))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { filters.settings.advancedRules.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("고급 차단")
        .toolbar { EditButton() }
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


/// 유동(비로그인)으로 쓸 때 자동으로 채울 닉네임·비밀번호 (모든 갤러리 공통 + 갤러리별)
struct AnonInfoView: View {
    @State private var nick = AnonStore.nick
    @State private var password = AnonStore.password
    @State private var galleries = AnonStore.galleryIDs
    @State private var newID = ""
    @ObservedObject private var visited = VisitedStore.shared

    private func name(_ id: String) -> String {
        visited.items.first { $0.gallery.galleryID == id }?.gallery.name ?? id
    }

    var body: some View {
        Form {
            Section {
                TextField("닉네임 (비우면 갤러리 기본 닉네임)", text: $nick)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("비밀번호", text: $password)
            } header: {
                Text("모든 갤러리")
            } footer: {
                Text("갤러리별 설정이 없는 갤러리에서 쓰는 값이에요. 로그아웃 상태에서 댓글·글쓰기 칸에 자동으로 채워요. 비밀번호는 이 기기 키체인에 암호화해서 보관해요.")
            }
            Section {
                ForEach(galleries, id: \.self) { g in
                    NavigationLink {
                        AnonGalleryEditView(galleryID: g, title: name(g))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name(g))
                            Text(AnonStore.galleryNick(g).isEmpty ? "닉네임: 공통 설정 따름" : "닉네임: \(AnonStore.galleryNick(g))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    for i in idx { AnonStore.removeGallery(galleries[i]) }
                    galleries = AnonStore.galleryIDs
                    NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                }
                HStack {
                    TextField("갤러리 ID 추가 (예: stock_new)", text: $newID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("추가") {
                        let id = DCGalleryID.bare(newID.trimmingCharacters(in: .whitespaces))
                        guard !id.isEmpty else { return }
                        if !AnonStore.hasGallery(id) { AnonStore.setGallery(id, nick: "", password: "") }
                        galleries = AnonStore.galleryIDs
                        newID = ""
                    }
                    .disabled(newID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("갤러리별")
            } footer: {
                Text("갤러리별 설정이 있으면 그 갤러리에서는 공통 설정보다 먼저 써요. 글쓰기·댓글 칸에서 닉네임이나 비밀번호를 바꾸면 그 갤러리 설정이 자동으로 만들어지고 갱신돼요.")
            }
        }
        .navigationTitle("유동 닉네임·비밀번호")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { galleries = AnonStore.galleryIDs }
        .onDisappear {
            AnonStore.nick = nick.trimmingCharacters(in: .whitespaces)
            AnonStore.password = password
            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)   // 페이지 스크립트에 새 값 반영
        }
    }
}

/// 갤러리 하나의 유동 닉네임·비밀번호
struct AnonGalleryEditView: View {
    let galleryID: String
    let title: String
    @State private var nick = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                TextField("닉네임 (비우면 공통 설정)", text: $nick)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("비밀번호 (비우면 공통 설정)", text: $password)
            } footer: {
                Text("\(title) (\(galleryID)) 갤러리에서만 쓰는 값이에요. 비워 둔 칸은 모든 갤러리 설정을 따라요.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nick = AnonStore.galleryNick(galleryID)
            password = AnonStore.galleryPassword(galleryID)
        }
        .onDisappear {
            AnonStore.setGallery(galleryID, nick: nick.trimmingCharacters(in: .whitespaces), password: password)
            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
        }
    }
}


/// 설정 → 컨트롤바 버튼 순서 (끌어서 바꾸기)
struct ControlBarOrderView: View {
    @AppStorage(ControlBarItem.storageKey, store: Profile.defaults) private var raw = ""
    @AppStorage(ControlBarItem.menuInTopBarKey, store: Profile.defaults) private var menuInTopBar = true
    @AppStorage("compactTopBar", store: Profile.defaults) private var compactTopBar = true
    @AppStorage(ControlBarItem.verticalLandscapeKey, store: Profile.defaults) private var verticalInLandscape = true
    @AppStorage(ControlBarItem.autoHideKey, store: Profile.defaults) private var autoHideBar = true
    @AppStorage("sideBarOffsetY", store: Profile.defaults) private var sideBarOffsetY = 0.0
    @AppStorage(ControlBarItem.mirroredKey, store: Profile.defaults) private var mirrored = false
    @AppStorage(ControlBarItem.verticalPortraitKey, store: Profile.defaults) private var verticalInPortrait = ControlBarItem.defaultVerticalInPortrait

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
                Toggle("상단바 줄이기 (듀오)", isOn: $compactTopBar)
            } footer: {
                Text("듀오처럼 시계가 옆 세로 줄에 있는 화면에서, 제목·버튼을 위쪽 빈 띠 안에 그려 파란 영역을 줄여요. 스크롤해도 상단바가 위로 밀려 올라가지 않아요.")
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
                if autoHideBar { BarAutoHideStylePicker() }
            } footer: {
                Text(BarAutoHideStylePicker.footer)
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
    @AppStorage("dockComment", store: Profile.defaults) private var dockComment = true
    @AppStorage("nativeComment", store: Profile.defaults) private var nativeComment = true
    @AppStorage("splitView", store: Profile.defaults) private var splitView = true
    @AppStorage(WebViewModel.nativeWriteKey, store: Profile.defaults) private var nativeWrite = true
    @AppStorage(WriteImageSize.key, store: Profile.defaults) private var imageSize = WriteImageSize.original.rawValue

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
                Toggle("앱 댓글 입력창", isOn: $nativeComment)
                    .onChangeCompat(of: nativeComment) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                    }
                Toggle("댓글창을 키보드 위에 붙이기", isOn: $dockComment)
                    .onChangeCompat(of: dockComment) { _, _ in
                        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                    }
            } header: {
                Text("댓글")
            } footer: {
                Text("앱 댓글 입력창을 켜면 댓글 칸이나 대댓글을 눌렀을 때 앱이 만든 입력창이 키보드 위에 떠요(유동 닉네임·비밀번호·코드, 디시콘 포함). 등록은 디시 댓글 양식으로 그대로 보내져요. 끄면 디시 원래 댓글 칸을 써요. 아래 '키보드 위에 붙이기'는 앱 댓글 입력창을 끈 경우에만 쓰여요.\n댓글 입력칸을 누르면 닉네임·비밀번호·코드·디시콘 버튼이 있는 댓글창 전체가 키보드 바로 위로 올라와요. 댓글창 바깥을 누르면 원래 자리로 돌아가요.")
            }

            // 분할 화면
            Section {
                Toggle("가로 분할 화면", isOn: $splitView)
            } header: {
                Text("화면")
            } footer: {
                Text("아이패드·듀오 펼침처럼 가로로 넓을 때 왼쪽에 글 목록, 오른쪽에 글을 나란히 보여요. 목록에서 글을 누르면 오른쪽에서 열려요. 세로로 돌리면 한 화면으로 돌아가요.")
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

            // 꼬릿말
            Section {
                NavigationLink { FooterSettingsView() } label: {
                    LabeledContent {
                        Text(FooterStore.enabled ? "\(FooterStore.shared.rules.count)개 · 켜짐" : "꺼짐")
                    } label: {
                        Label("꼬릿말", systemImage: "text.append")
                    }
                }
            } header: {
                Text("꼬릿말")
            } footer: {
                Text("글 맨 아래에 '-내용' 한 줄을 회색 12px로 붙여요. 계정(유동 포함)·갤러리마다 따로 정할 수 있어요.")
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
        .onChangeCompat(of: stored) { _, _ in
            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
        }
    }
}

/// 컨트롤바 숨기는 방식 선택 (스크롤하는 동안만 / 내리면 숨기고 올리면 표시)
struct BarAutoHideStylePicker: View {
    @AppStorage(ControlBarItem.autoHideStyleKey, store: Profile.defaults) private var style = ControlBarItem.autoHideStyleScrolling
    static let footer = "스크롤하는 동안만: 스크롤하는 동안 화면 밖(가로 막대는 아래, 세로 막대는 오른쪽)으로 들어갔다가 멈추면 다시 나와요. 내리면 숨기고 올리면 표시: 아래로 스크롤하면 숨기고 멈춰도 그대로 두고, 위로 스크롤하면 다시 나와요. 댓글 영역에 닿으면 다시 나와요. 끄면 항상 보여요."
    var body: some View {
        Picker("숨기는 방식", selection: $style) {
            Text("스크롤하는 동안만").tag(ControlBarItem.autoHideStyleScrolling)
            Text("내리면 숨기고 올리면 표시").tag(ControlBarItem.autoHideStyleDirection)
        }
    }
}
