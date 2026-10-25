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

    private init() {
        locked = Self.lockEnabled          // 앱을 처음 켤 때도 잠긴 상태로 시작
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
        let host = UIHostingController(rootView: PrivacyOverlay())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
    }

    private func dismissOverlay() {
        window?.isHidden = true
        window = nil
    }
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
