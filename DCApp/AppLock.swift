import SwiftUI
import Combine
import LocalAuthentication

/// 앱 잠금(Face ID / Touch ID / 기기 암호) + 앱 전환 화면에서 가리기
/// 시트(설정 창 등)까지 덮어야 해서, SwiftUI 화면 위가 아니라 별도의 최상단 창(UIWindow)에 가림막을 띄움
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()
    static let lockKey = "appLockEnabled"     // 생체인식 잠금
    static let blurKey = "privacyBlur"        // 앱 전환 화면에서 가리기

    @Published private(set) var locked: Bool
    private var authenticating = false
    private var window: UIWindow?
    private var phase: ScenePhase = .active

    static var lockEnabled: Bool { UserDefaults.standard.bool(forKey: lockKey) }
    static var blurEnabled: Bool { UserDefaults.standard.bool(forKey: blurKey) }

    private var cancellables = Set<AnyCancellable>()

    private init() {
        locked = Self.lockEnabled          // 앱을 처음 켤 때도 잠긴 상태로 시작
        // SwiftUI의 scenePhase는 돌아온 뒤 한참(1초 가까이) 늦게 바뀌어서 가림막이 오래 남음
        // → iOS가 바로 보내는 '앞으로 옴 / 활성화' 알림에서 먼저 걷어냄 (잠금은 그대로 유지)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.returnedToForeground() }
            }
            .store(in: &cancellables)
    }

    /// 알림으로 먼저 걷어낸 시각 — 그 직후 늦게 오는 scenePhase '.inactive'로 다시 가리지 않게
    private var foregroundAt: Date?

    private func returnedToForeground() {
        guard phase != .active else { return }
        foregroundAt = Date()
        phase = .active
        updateOverlay()
        Task { await unlock() }
    }

    /// 기기에서 쓰는 인증 이름 (설정 화면 표시용)
    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "기기 암호"
        }
    }

    // MARK: - 앱 상태 변화

    /// 앱을 켰을 때
    func startup() async {
        updateOverlay()
        await unlock()
    }

    func scenePhaseChanged(_ p: ScenePhase) {
        if p == .inactive, let t = foregroundAt, Date().timeIntervalSince(t) < 2 { return }   // 돌아오는 중에 늦게 온 값
        if p == .background { foregroundAt = nil }
        phase = p
        if p == .background, Self.lockEnabled { locked = true }
        updateOverlay()
        if p == .active { Task { await unlock() } }
    }

    // MARK: - 잠금 해제

    func unlock() async {
        guard locked, !authenticating else { return }
        guard Self.lockEnabled else { locked = false; updateOverlay(); return }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "암호 입력"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // 기기에 암호가 없으면 잠글 수 없음 → 그냥 열어 줌
            locked = false
            updateOverlay()
            return
        }
        authenticating = true
        defer { authenticating = false }
        let ok = (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "DCAPP 잠금을 풀어요")) ?? false
        if ok {
            locked = false
            updateOverlay()
        }
    }

    /// 설정에서 잠금을 켤 때 한 번 인증해서 확인 (실패하면 켜지 않음)
    static func verifyForEnabling() async -> Bool {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "앱 잠금을 켜요")) ?? false
    }

    // MARK: - 가림막 창

    /// 잠겨 있거나, '가리기'가 켜진 채 앱이 비활성(전환 화면 등)이면 가림막 표시
    func updateOverlay() {
        let show = locked || (Self.blurEnabled && phase != .active)
        if show { presentOverlay() } else { dismissOverlay() }
    }

    private func presentOverlay() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        let host = LightStatusBarHost(rootView: PrivacyOverlay())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
    }

    private func dismissOverlay() {
        guard let w = window else { return }
        w.isHidden = true
        window = nil
        // 가림막 창이 사라진 뒤 상태바(시계·배터리) 색을 앱 화면 기준(남색 상단바 → 흰색)으로 다시 계산하게
        refreshStatusBar(in: w.windowScene)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.refreshStatusBar(in: w.windowScene)
        }
    }

    private func refreshStatusBar(in scene: UIWindowScene?) {
        for win in scene?.windows ?? [] where !win.isHidden {
            var vc = win.rootViewController
            while let p = vc?.presentedViewController { vc = p }
            vc?.setNeedsStatusBarAppearanceUpdate()
            win.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }
}

/// 가림막 창: 남색 바탕이라 상태바는 흰색 (기본값이면 검은 글씨가 되고, 창이 사라진 뒤에도 남는 경우가 있음)
private final class LightStatusBarHost<Content: View>: UIHostingController<Content> {
    override var preferredStatusBarStyle: UIStatusBarStyle { StatusBarStyler.style(for: traitCollection) }
}

/// 가림막: 흐리게 + (잠겨 있으면) 잠금 해제 버튼
struct PrivacyOverlay: View {
    @ObservedObject private var lock = AppLock.shared

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            DCTheme.navy.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: lock.locked ? "lock.fill" : "eye.slash.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
                if lock.locked {
                    Text("DCAPP 잠김")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label("\(AppLock.biometryName)로 잠금 해제", systemImage: "faceid")
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DCTheme.navy)
                }
            }
        }
    }
}


/// 앱 화면 안쪽에 까는 불투명 가림막 — 잠금이 켜진 채 앱을 켜면 첫 화면이 그려질 때부터 내용을 가림
/// (최상단 가림막 창은 화면이 한 번 그려진 뒤에야 띄울 수 있어서, 그 사이 잠깐 내용이 보이던 문제 해결)
struct LockCover: View {
    @ObservedObject private var lock = AppLock.shared

    var body: some View {
        if lock.locked {
            ZStack {
                DCTheme.navy.ignoresSafeArea()
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .transition(.opacity)
        }
    }
}
