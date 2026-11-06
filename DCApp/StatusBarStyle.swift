import UIKit
import ObjectiveC

/// 화면 맨 위 시계·배터리(상태바) 글씨 색을 앱이 직접 정함
/// SwiftUI에 맡기면 화면이 상태바 영역까지 덮는 구조에서 검은 글씨(기본값)로 나와서,
/// 앱 창의 맨 아래 화면(UIHostingController)이 테마 상단바 색을 보고 흰/검은 글씨를 고르게 함.
/// 상단바가 밝은 색(흰색 테마 등)이면 검은 글씨, 그 밖의 유색이면 흰 글씨.
@MainActor
enum StatusBarStyler {
    /// 지금 테마의 상단바 색 기준 상태바 글씨 색
    static func style(for trait: UITraitCollection) -> UIStatusBarStyle {
        let ws = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { $0.windowLevel == .normal && !$0.isHidden }
        let sideR = ws.map(\.safeAreaInsets.right).max() ?? 0, sideL = ws.map(\.safeAreaInsets.left).max() ?? 0
        if (sideR >= 56 && sideL < 20) || (sideL >= 56 && sideR < 20) {
            return trait.userInterfaceStyle == .dark ? .lightContent : .darkContent
        }
        let c = DCTheme.current.bar.resolvedColor(with: trait)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .lightContent }
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.62 ? .darkContent : .lightContent
    }

    private static let prefix = "DCAppStatusBar11_"

    private static var observing = false

    /// 모든 창의 맨 아래 화면에 적용 (이미 적용됐으면 색만 다시 계산)
    /// iOS가 앱 창 위에 따로 띄우는 창(UITrackingElementWindowController 등)도 상태바 색을 가져가서 같이 바꿈
    static func apply() {
        watchOrientation()
        if !observing {
            observing = true
            // 창이 새로 보일 때마다 (iOS가 늦게 띄우는 창 포함) 다시 적용
            NotificationCenter.default.addObserver(forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { StatusBarStyler.apply() }
            }
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows { patch(w.rootViewController) }
        }
    }

    // MARK: 듀오 방향 보정
    // 듀오는 앱 창(안쪽 큰 화면)과 시스템 기본 화면(바깥 화면) 크기가 달라서, 시스템이 기기 방향(바깥 화면 기준)에 맞춰
    // 앱을 가로로 눕혀 놓음 (Safari·게임은 같은 자세에서 세로로 긴 모양). 진단: 이 자세의 기기 방향 raw=4 →
    // 그때는 세로 방향(거꾸로 세로 포함)만 허용해서 시스템이 알맞은 세로를 고르게 함. 그 밖의 자세는 네 방향 모두 허용.
    // 알려진 문제: 시스템이 먼저 한 번 돌고 허용 방향이 바뀐 뒤 다시 돌아서 회전이 두 번 보임 (미해결).
    /// 지금 허용할 방향 (앱 델리게이트·맨 위 화면 컨트롤러가 읽음)
    /// test5 방식: 듀오이고 기기 방향이 가로(오른쪽, raw=4)일 때만 세로(거꾸로 세로 포함)만 허용. 그 밖은 네 방향.
    /// 알려진 문제: 시스템이 먼저 한 번 돌고 허용 방향이 바뀐 뒤 다시 돌아서 회전이 두 번 보임 (미해결).
    private(set) static var orientationMask: UIInterfaceOrientationMask = .all
    private static var watchingOrientation = false
    private(set) static var orientationFixLog = "(아직 없음)"

    private static func watchOrientation() {
        guard !watchingOrientation else { return }
        watchingOrientation = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                for ms in [0, 600] {
                    try? await Task.sleep(for: .milliseconds(ms))
                    updateOrientationMask()
                }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            updateOrientationMask()
        }
    }

    private static func updateOrientationMask() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        let sb = scene.coordinateSpace.bounds.size, ub = UIScreen.main.bounds.size
        let isDuo = ub.width * ub.height > 0 && (sb.width * sb.height) / (ub.width * ub.height) > 1.3
        let dev = UIDevice.current.orientation
        let want: UIInterfaceOrientationMask = (isDuo && dev == .landscapeRight) ? [.portrait, .portraitUpsideDown] : .all
        guard want != orientationMask else { return }
        orientationMask = want
        orientationFixLog = "듀오=\(isDuo) 기기방향=\(dev.rawValue) → 허용 \(want.rawValue) 요청 (화면 방향 \(scene.interfaceOrientation.rawValue))"
        for w in scene.windows { w.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: want)) { error in
            Task { @MainActor in orientationFixLog += " / 실패: \(error.localizedDescription)" }
        }
    }

    /// 앱이 켜진 직후엔 창이 늦게 생길 수 있어서 몇 번 나눠서
    static func applySoon() {
        apply()
        Task { @MainActor in
            for ms in [100, 400, 1000] {
                try? await Task.sleep(for: .milliseconds(ms))
                apply()
            }
        }
    }

    /// 진단용: 창마다 맨 아래 화면 클래스와 상태바 색 결정 경로
    static func diagnostics() -> String {
        var out = ["--- 방향 ---"]
        let dev = UIDevice.current
        out.append("기기 방향 raw=\(dev.orientation.rawValue) (1세로 2거꾸로세로 3가로(왼) 4가로(오)) idiom=\(dev.userInterfaceIdiom.rawValue) 화면=\(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height))")
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            out.append("scene 인터페이스 방향 raw=\(scene.interfaceOrientation.rawValue) 창=\(Int(scene.coordinateSpace.bounds.width))x\(Int(scene.coordinateSpace.bounds.height))")
            for w in scene.windows {
                guard let vc = w.rootViewController else { continue }
                out.append("  \(type(of: w)) 맨위 화면 허용 방향 mask=\(vc.supportedInterfaceOrientations.rawValue) (30=네 방향, 26=거꾸로 세로 뺌) autorotate=\(vc.shouldAutorotate)")
            }
        }
        out.append("방향 보정 기록: \(orientationFixLog)")
        out.append("--- 상태바 ---")
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            out.append("scene statusBar style=\(scene.statusBarManager?.statusBarStyle.rawValue ?? -1)")
            for w in scene.windows {
                guard let vc = w.rootViewController else { continue }
                var chain = [String]()
                var cur: UIViewController? = vc
                for _ in 0..<5 {
                    guard let c = cur else { break }
                    chain.append("\(String(NSStringFromClass(object_getClass(c) ?? type(of: c)).prefix(60))) pref=\(c.preferredStatusBarStyle.rawValue)")
                    cur = c.childForStatusBarStyle
                }
                out.append("window hidden=\(w.isHidden) key=\(w.isKeyWindow) level=\(w.windowLevel.rawValue) \(type(of: w)): " + chain.joined(separator: " → "))
                if let p = vc.presentedViewController { out.append("  presented: \(type(of: p)) pref=\(p.preferredStatusBarStyle.rawValue) captures=\(p.modalPresentationCapturesStatusBarAppearance)") }
            }
        }
        return out.joined(separator: "\n")
    }

    /// 화면 컨트롤러를 '상태바 색만 바꾼' 하위 클래스로 바꿔 끼움 (KVO와 같은 방식)
    private static func patch(_ vc: UIViewController?) {
        guard let vc else { return }
        let base: AnyClass = object_getClass(vc) ?? type(of: vc)
        let baseName = NSStringFromClass(base)
        if baseName.hasPrefix(prefix) {
            vc.setNeedsStatusBarAppearanceUpdate()
            return
        }
        let name = prefix + baseName
        var sub: AnyClass? = NSClassFromString(name)
        if sub == nil, let c = objc_allocateClassPair(base, name, 0) {
            let sel = #selector(getter: UIViewController.preferredStatusBarStyle)
            let block: @convention(block) (UIViewController) -> Int = { me in
                MainActor.assumeIsolated { StatusBarStyler.style(for: me.traitCollection).rawValue }
            }
            class_addMethod(c, sel, imp_implementationWithBlock(block), "q@:")
            // SwiftUI는 상태바 색을 안쪽 화면(내비게이션 컨트롤러 등)에 넘겨서 정함 → 넘기지 말고 여기서 정하게
            let childSel = #selector(getter: UIViewController.childForStatusBarStyle)
            let noChild: @convention(block) (UIViewController) -> UIViewController? = { _ in nil }
            class_addMethod(c, childSel, imp_implementationWithBlock(noChild), "@@:")
            // 화면 방향: SwiftUI 화면 컨트롤러는 아이폰 계열이면 '거꾸로 세로'를 뺀 방향만 허용 → 네 방향 모두 허용 (앱 델리게이트·Info.plist가 허용해도 맨 위 화면 컨트롤러가 막으면 안 돌아감)
            let orientSel = #selector(getter: UIViewController.supportedInterfaceOrientations)
            let allOrient: @convention(block) (UIViewController) -> UInt = { _ in MainActor.assumeIsolated { StatusBarStyler.orientationMask.rawValue } }
            class_addMethod(c, orientSel, imp_implementationWithBlock(allOrient), "Q@:")
            // 진단에서 맨 위 화면의 자동 회전(shouldAutorotate)이 꺼져 있었음 → 켜 둠
            let rotSel = #selector(getter: UIViewController.shouldAutorotate)
            let autoRot: @convention(block) (UIViewController) -> Bool = { _ in true }
            class_addMethod(c, rotSel, imp_implementationWithBlock(autoRot), "B@:")
            objc_registerClassPair(c)
            sub = c
        }
        if let sub {
            object_setClass(vc, sub)
            vc.setNeedsStatusBarAppearanceUpdate()
        }
    }
}
