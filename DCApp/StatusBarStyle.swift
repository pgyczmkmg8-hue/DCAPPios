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
        let c = DCTheme.current.bar.resolvedColor(with: trait)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .lightContent }
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.62 ? .darkContent : .lightContent
    }

    private static let prefix = "DCAppStatusBar2_"

    private static var observing = false

    /// 모든 창의 맨 아래 화면에 적용 (이미 적용됐으면 색만 다시 계산)
    /// iOS가 앱 창 위에 따로 띄우는 창(UITrackingElementWindowController 등)도 상태바 색을 가져가서 같이 바꿈
    static func apply() {
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
        var out = ["--- 상태바 ---"]
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
            objc_registerClassPair(c)
            sub = c
        }
        if let sub {
            object_setClass(vc, sub)
            vc.setNeedsStatusBarAppearanceUpdate()
        }
    }
}
