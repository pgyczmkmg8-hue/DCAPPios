import Foundation
import ObjectiveC

/// 웹페이지가 스크립트로 입력칸에 focus()를 해도 iOS는 사용자가 직접 누른 게 아니면 키보드를 안 띄움.
/// 글쓰기 버튼을 누른 직후 몇 초 동안만 "사용자가 누른 것"으로 쳐서 제목 칸에 키보드가 바로 뜨게 함.
/// (WebKit 내부 함수를 바꿔치기하는 방식이라, iOS가 이름을 바꾸면 조용히 아무 일도 안 일어남 → 키보드만 안 뜸)
enum FocusUnlock {
    /// 이 시각 전까지는 스크립트 focus도 키보드를 띄움
    nonisolated(unsafe) static var allowUntil = Date.distantPast
    nonisolated(unsafe) private static var installed = false

    static func allow(for seconds: TimeInterval) {
        allowUntil = Date(timeIntervalSinceNow: seconds)
    }

    static func install() {
        guard !installed, let cls = NSClassFromString("WKContentView") else { return }
        installed = true
        let candidates = [
            "_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:",
            "_elementDidFocus:userIsInteracting:blurPreviousNode:changingActivityState:userObject:",
        ]
        for name in candidates {
            let sel = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(cls, sel),
                  method_getNumberOfArguments(method) == 7 else { continue }   // self, _cmd + 인자 5개
            typealias Fn = @convention(c) (AnyObject, Selector, UnsafeRawPointer?, Bool, Bool, UInt64, AnyObject?) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            let block: @convention(block) (AnyObject, UnsafeRawPointer?, Bool, Bool, UInt64, AnyObject?) -> Void = {
                me, info, userIsInteracting, blur, changes, obj in
                original(me, sel, info, userIsInteracting || Date() < FocusUnlock.allowUntil, blur, changes, obj)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
            return
        }
    }
}
