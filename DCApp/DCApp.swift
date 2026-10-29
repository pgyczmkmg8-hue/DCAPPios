import SwiftUI
import Combine

/// 디시인사이드 관련 주소 모음. 사이트 구조가 바뀌면 여기만 고치면 됩니다.
enum DC {
    static let home = URL(string: "https://m.dcinside.com/")!
    static let login = URL(string: "https://msign.dcinside.com/login?r_url=https%3A%2F%2Fm.dcinside.com")!
    static let dccon = URL(string: "https://dccon.dcinside.com/")!
    static let loginHost = "msign.dcinside.com"

    /// 디시 모바일 통합검색 결과 주소 (검색이 안 되면 이 형식만 고치면 됩니다)
    static func search(_ keyword: String) -> URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?")
        let q = keyword.addingPercentEncoding(withAllowedCharacters: allowed) ?? keyword
        return URL(string: "https://m.dcinside.com/search/?keyword=\(q)") ?? home
    }

    /// 로그인/로그아웃 시 모든 탭을 새로고침하기 위한 알림
    static let sessionChanged = Notification.Name("DCSessionChanged")
    /// 차단 목록/숨김 설정이 바뀌었을 때
    static let filtersChanged = Notification.Name("DCFiltersChanged")
    /// 저장된 로그인 정보가 바뀌었을 때
    static let credentialsChanged = Notification.Name("DCCredentialsChanged")
}

/// 앱 화면 위로 띄우는 창 (보관함 / 검색 / 설정)
enum AppSheet: String, Identifiable {
    case library, posts, search, settings
    var id: String { rawValue }
}

/// 화면 하나(메인 브라우저) + 위로 띄우는 창들을 관리합니다.
/// 보관함·검색에서 고른 페이지는 모두 메인 브라우저에서 열려요.
@MainActor
final class AppRouter: ObservableObject {
    @Published var sheet: AppSheet?
    /// 설정을 열 때 바로 보여줄 칸 (예: "block" = 차단)
    var settingsAnchor: String?
    let mainBrowser: WebViewModel

    init() {
        mainBrowser = WebViewModel(url: DC.home)
        // 갤러리 목록에서 스와이프 → 하단 바 "갤러리" 버튼과 같은 효과
        mainBrowser.onGallerySwipe = { [weak self] in self?.sheet = .library }
    }

    func open(_ url: URL) {
        sheet = nil
        mainBrowser.load(url)
    }

    /// 계정 전환: 지금 로그인을 지우고 → 로그인 화면을 열어 고른 계정으로 자동 로그인
    func switchAccount(_ account: LoginCredential) {
        sheet = nil
        mainBrowser.loginHere(account)     // 로그인이 끝나면 보던 페이지로 돌아옴
    }

    /// 임시저장 글을 이어서 쓰기: 글쓰기 화면을 열고, 다 열리면 내용을 채움
    func openDraft(_ draft: Draft) {
        mainBrowser.pendingDraft = draft
        var url = draft.writeURL ?? URL(string: "https://m.dcinside.com/write/\(draft.galleryID)")!
        // 예전에 잘못 저장된 미니 갤러리 글쓰기 주소(/mini/write/) 고치기
        if let fixed = URL(string: url.absoluteString.replacingOccurrences(of: "m.dcinside.com/mini/write/", with: "m.dcinside.com/writemini/")) { url = fixed }
        open(url)
    }
}

@main
struct DCApp: App {
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var router = AppRouter()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(favorites)
                .environmentObject(router)
                .overlay { LockCover() }                    // 잠겨 있으면 첫 화면부터 가림 (가림막 창이 뜨기 전 깜빡임 방지)
                .task { await AppLock.shared.startup() }    // 잠금이 켜져 있으면 켜자마자 인증
        }
        // 백그라운드로 갈 때 알림 확인 예약 → iOS가 깨우면 디시 알림 확인
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { DCNotify.schedule() }
            AppLock.shared.scenePhaseChanged(phase)      // 앱 잠금 / 전환 화면 가리기
        }
        .backgroundTask(.appRefresh(DCNotify.refreshTaskID)) {
            await DCNotify.backgroundRefresh()
        }
    }
}

/// 앱 탭바 없이 브라우저 하나만. 하단 바의 갤러리/검색, ⋮ 메뉴의 설정 등은 창으로 열림
/// 한손 모드: 화면 위쪽을 비워두고(PIP 영상 자리) 아래쪽에서만 앱이 동작
struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var favorites: FavoritesStore
    @AppStorage("compactMode") private var compactMode = false
    /// 테마가 바뀌면 화면을 새로 그려 상단바·강조색에 바로 반영
    @AppStorage(DCTheme.storageKey) private var themeRaw = AppTheme.dc.rawValue
    @Environment(\.colorScheme) private var systemScheme
    /// GitHub에 새 버전이 있으면 알림창
    @State private var availableUpdate: AppRelease?
    /// 앱 사용 중 새 디시 알림 배너
    @ObservedObject private var alarms = AlarmStore.shared
    @State private var bannerTask: Task<Void, Never>?
    /// 듀오 오른쪽 빈 줄 (상단바가 그 줄까지 늘어나지 않게 위쪽을 바탕색으로 덮음)
    @ObservedObject private var sideColumn = SideColumnLayout.shared
    @AppStorage("compactTopRatio") private var topRatio = 0.34
    @State private var keyboardVisible = false
    @State private var dragStartRatio: Double?      // 핸들을 끌기 시작할 때의 높이
    @State private var exitHoldTask: Task<Void, Never>?   // 맨 위에서 버티는 시간 재기
    @State private var exitArmed = false            // 맨 위에 닿아 해제 대기 중 (핸들 색 바뀜)

    private static let minTopRatio = 0.12
    private static let maxTopRatio = 0.6
    private static let exitHoldDelay: Duration = .milliseconds(300)

    /// 앱 창의 실제 높이 (UIScreen.main은 화면이 두 개인 기기(듀오)에서 엉뚱한 화면을 줄 수 있어서 창 크기를 직접 잼)
    @State private var windowHeight: CGFloat = 800

    private func closeBanner() {
        bannerTask?.cancel()
        AlarmStore.shared.incoming = nil
    }

    /// 한손 모드에서 비워둘 위쪽 높이 (상태바 포함)
    private var topGap: CGFloat {
        compactMode ? windowHeight * topRatio : 0
    }

    var body: some View {
        // 화면 구조는 항상 같게 유지하고(웹뷰가 빠지지 않도록), 한손 모드일 때 위쪽 여백만 줌
        ZStack {
            Color.black.ignoresSafeArea()
                .opacity(compactMode ? 1 : 0)   // 한손 모드일 때만 위쪽 빈 공간을 검게
            NavigationStack {
                BrowserView(model: router.mainBrowser, fallbackTitle: "홈", showsMenuButton: true)
            }
            .id(themeRaw)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: compactMode ? 22 : 0,
                                              topTrailingRadius: compactMode ? 22 : 0,
                                              style: .continuous))
            .padding(.top, topGap)
            // 앱 화면이 상태바·홈 바 영역까지 덮도록 (남색 상단바가 위 끝까지, 아래 검은 띠 없음)
            // 키보드 처리는 그대로 두기 위해 .container만 무시
            .ignoresSafeArea(.container, edges: .all)

            // 앱 글쓰기 화면: 디시 글쓰기 페이지 위에 덮음 (등록은 뒤의 디시 양식으로)
            NativeWriteHost(model: router.mainBrowser)
                .padding(.top, topGap)

            // 듀오: 상단바가 오른쪽 빈 줄(안전 영역)까지 늘어난 부분을 바탕색으로 덮어 사파리처럼
            if sideColumn.width > 0 && !compactMode {
                Color(uiColor: .systemBackground)
                    .frame(width: sideColumn.width, height: sideColumn.topBarBottom + 2)   // +2: 상단바 아래 회색 구분선까지 덮기
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // 한손 모드: 앱 화면 바로 위에 있는 핸들을 위아래로 끌어 높이 조절
            if compactMode {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(0, topGap - 30)).allowsHitTesting(false)
                    resizeHandle
                    Spacer(minLength: 0).allowsHitTesting(false)   // 핸들 말고는 터치를 막지 않음
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
            }
        }
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { windowHeight = g.size.height }
                    .onChange(of: g.size.height) { _, h in windowHeight = h }
            }
            .ignoresSafeArea()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .animation(.spring(duration: 0.35), value: compactMode)
        // (높이 조절은 손가락을 바로 따라오도록 애니메이션 없이)
        .onAppear {
            StatusBarStyler.applySoon()   // 상태바(시계·배터리) 글씨: 유색 상단바면 흰색
            DarkMode.apply()              // ⋮ 메뉴에서 정한 다크모드
            compactMode = false     // 앱을 새로 켜면 항상 일반 모드로 시작 (안전장치)
            if let url = DCNotify.pendingURL { DCNotify.pendingURL = nil; router.open(url) }   // 알림을 눌러서 켠 경우
        }
        .overlay(alignment: .top) {
            if let inc = alarms.incoming {
                AlarmBanner(item: inc.item, more: inc.more, onTap: {
                    AlarmStore.shared.markRead(inc.item)
                    AlarmStore.shared.markRead(galleryID: inc.item.galleryID, postNo: inc.item.postNo)
                    router.open(inc.item.url)
                    closeBanner()
                }, onClose: closeBanner)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(inc.item.id)
            }
        }
        .animation(.spring(duration: 0.35), value: alarms.incoming?.item.id)
        .onChange(of: themeRaw) { _, _ in StatusBarStyler.applySoon() }          // 테마를 바꾸면 상태바 글씨 색도
        .onChange(of: systemScheme) { _, _ in StatusBarStyler.applySoon() }      // 다크 모드 전환 (테마 색이 바뀔 수 있음)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            StatusBarStyler.apply()
        }
        .onChange(of: alarms.incoming?.item.id) { _, newID in
            // 4초 뒤 자동으로 닫힘
            bannerTask?.cancel()
            guard newID != nil else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            bannerTask = Task {
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { closeBanner() }
            }
        }
        .task {
            // 앱을 열 때마다 GitHub Releases 확인
            if let r = await UpdateChecker.checkIfDue() { availableUpdate = r }
        }
        .alert(availableUpdate.map { "새 버전 \($0.version)" } ?? "",
               isPresented: Binding(get: { availableUpdate != nil }, set: { if !$0 { availableUpdate = nil } }),
               presenting: availableUpdate) { r in
            // 버전 정보 → 업데이트에서 고른 앱(Feather/SideStore/LiveContainer)으로 바로 설치
            let installer = UpdateView.Installer.current
            if let ipa = r.ipaURL, let url = installer.installURL(for: ipa) {
                Button("\(installer.name)로 바로 설치") { UIApplication.shared.open(url) }
            }
            Button("다운로드") { UIApplication.shared.open(r.ipaURL ?? r.pageURL) }
            Button("릴리스 노트 보기") { UIApplication.shared.open(r.pageURL) }
            Button("이 버전 건너뛰기") { UpdateChecker.skip(r.version) }
            Button("나중에", role: .cancel) {}
        } message: { r in
            let notes = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            Text("지금 버전: \(UpdateChecker.currentVersion)" + (notes.isEmpty ? "" : "\n\n" + String(notes.prefix(300))))
        }
        .onReceive(NotificationCenter.default.publisher(for: DCNotify.openURL)) { note in
            if let url = note.object as? URL { DCNotify.pendingURL = nil; router.open(url) }
        }
        .sheet(item: $router.sheet) { sheet in
            Group {
                switch sheet {
                case .library: FavoritesView()
                case .posts: SavedPostsSheet()
                case .search: SearchView()
                case .settings: SettingsView()
                }
            }
            .environmentObject(router)
            .environmentObject(favorites)
        }
    }

    /// 한손 모드 핸들 (아이폰 홈 바처럼 얇고 긴 막대). 위아래로 끌면 비워둘 높이가 바뀜
    private var resizeHandle: some View {
        Capsule()
            .fill(exitArmed ? DCTheme.accent : Color.white.opacity(0.75))
            .frame(width: exitArmed ? 170 : 120, height: exitArmed ? 7 : 5)
            .animation(.spring(duration: 0.25), value: exitArmed)
            .frame(maxWidth: .infinity)          // 가로 전체를 잡는 영역으로
            .frame(height: 30)                   // 손가락으로 잡기 쉽게 위아래 여유
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        guard compactMode else { return }
                        let screen = max(windowHeight, 1)
                        if dragStartRatio == nil { dragStartRatio = topRatio }
                        let next = (dragStartRatio ?? topRatio) + Double(v.translation.height / screen)
                        topRatio = min(Self.maxTopRatio, max(Self.minTopRatio, next))
                        // 맨 위까지 끌어올린 채로 잠깐 버티면 한손 모드 해제
                        if next <= Self.minTopRatio {
                            if exitHoldTask == nil { armExit() }
                        } else {
                            disarmExit()
                        }
                    }
                    .onEnded { _ in
                        disarmExit()
                        dragStartRatio = nil
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
    }

    /// 핸들이 맨 위에 닿음 → 잠시 뒤 해제 (그 사이 내리거나 손을 떼면 취소)
    private func armExit() {
        exitArmed = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        exitHoldTask = Task { @MainActor in
            try? await Task.sleep(for: Self.exitHoldDelay)
            guard !Task.isCancelled, compactMode else { return }
            // 다음에 켤 때 맨 위 높이로 켜지지 않도록 끌기 전 높이로 되돌림
            if let start = dragStartRatio, start > Self.minTopRatio + 0.02 { topRatio = start }
            dragStartRatio = nil
            exitArmed = false
            exitHoldTask = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            compactMode = false
        }
    }

    private func disarmExit() {
        exitHoldTask?.cancel()
        exitHoldTask = nil
        if exitArmed { exitArmed = false }
    }

}


