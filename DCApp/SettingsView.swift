import SwiftUI
import WebKit

// MARK: - 설정 탭

struct SettingsView: View {
    @ObservedObject private var filters = FilterStore.shared
    @ObservedObject private var autoImages = AutoImageStore.shared
    @AppStorage("autoLogin") private var autoLogin = false
    @AppStorage("dockComment") private var dockComment = true
    @AppStorage("fullSwipeBack") private var fullSwipeBack = true
    @AppStorage("swipeSensitivity") private var swipeSensitivity = 3.0
    @AppStorage("gallerySwipeOpensList") private var gallerySwipeOpensList = true

    private var sensitivityLabel: String {
        switch Int(swipeSensitivity) {
        case 1: "매우 둔감"
        case 2: "둔감"
        case 3: "보통"
        case 4: "민감"
        default: "매우 민감"
        }
    }
    @AppStorage("hideSiteHeader") private var hideSiteHeader = true
    @AppStorage("homeRankOnly") private var homeRankOnly = true
    @AppStorage("showFloatingBar") private var showFloatingBar = true
    @AppStorage("adFilter") private var adFilter = true
    @AppStorage(DCTheme.storageKey) private var themeRaw = AppTheme.dc.rawValue
    @AppStorage("hideDory") private var hideDory = true
    @AppStorage(DCNotify.enabledKey) private var notifyEnabled = false
    @State private var notifyResult: String?
    @State private var notifyChecking = false
    @EnvironmentObject private var router: AppRouter
    @State private var accounts: [LoginCredential] = CredentialStore.all()
    @State private var currentID: String? = CredentialStore.currentAccountID
    @State private var showAddAccount = false
    @State private var switchTarget: LoginCredential?
    @State private var confirmLogout = false
    @State private var message: String?

    private func runNotifyCheck() async {
        notifyChecking = true
        notifyResult = await DCNotify.check()
        notifyChecking = false
    }

    var body: some View {
        NavigationStack {
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
                    Text("글쓰기")
                } footer: {
                    Text("글쓰기 화면에 미리 등록한 사진을 자동으로 첨부해요.")
                }

                // 앱 아이콘 / 제스처
                Section("앱") {
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
                    Toggle("광고 차단 (애드가드 갤러리 필터)", isOn: $adFilter)
                        .onChange(of: adFilter) { _, _ in
                            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                        }
                    Toggle("댓글돌이 댓글 숨기기", isOn: $hideDory)
                        .onChange(of: hideDory) { _, _ in
                            NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
                        }
                    Toggle("오른쪽 세로 버튼 막대 보기", isOn: $showFloatingBar)
                    if !showFloatingBar {
                        Text("⋮ 메뉴는 상단바 오른쪽(글쓰기 화면은 왼쪽)으로 옮겨져요. 한손 모드는 상단 갤러리 이름을 0.5초 누르면 켜져요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink { AppIconSettingsView() } label: {
                        Label("앱 아이콘", systemImage: "app.badge")
                    }
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

                // 디시콘
                Section("디시콘") {
                    NavigationLink {
                        BrowserView(startURL: DC.dccon, fallbackTitle: "디시콘 샵")
                    } label: {
                        Label("디시콘 샵 / 내 디시콘", systemImage: "face.smiling")
                    }
                }

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
                } header: {
                    Text("차단")
                } footer: {
                    Text("글 목록이나 댓글을 길게 누르면 작성자·디시콘을 바로 차단할 수 있어요. '차단됨 표시'는 그 자리에 회색 안내 칸을 남기고(탭하면 내용 보기), '완전히 숨김'은 흔적 없이 가려요.")
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
                    Text("그래도 보이는 알림이나 배너는 화면 아래 ⋯ → '요소 숨기기'를 누르고 직접 탭해서 숨길 수 있어요.")
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }

                // 백업
                Section("백업") {
                    NavigationLink { BackupView() } label: {
                        Label("설정 · 즐겨찾기 · 글 보관함 백업 / 복원", systemImage: "externaldrive")
                    }
                }

                // 버전 정보 (맨 아래)
                Section {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { router.sheet = nil }
                }
            }
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
    }

    private func logout() async {
        await DCSession.clear(notify: true)
        message = autoLogin
            ? "로그아웃했어요. (자동 로그인이 켜져 있어서 로그인 페이지를 열면 다시 로그인돼요)"
            : "로그아웃했어요."
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
                        Text("\(u.kind.label) · \(u.value)")
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
