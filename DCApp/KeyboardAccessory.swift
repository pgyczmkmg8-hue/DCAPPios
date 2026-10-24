import WebKit
import ObjectiveC

/// 웹뷰 입력칸을 눌렀을 때 키보드 위에 붙는 ▲ ▼ ✓ 막대(입력 보조 막대)를 없앱니다.
/// 웹뷰 내부 콘텐츠 뷰의 inputAccessoryView가 nil을 돌려주도록 바꾸는 방식이에요.
extension WKWebView {
    func removeInputAccessoryBar() {
        guard let content = scrollView.subviews.first(where: {
            String(describing: type(of: $0)).hasPrefix("WKContent")
        }) else { return }

        let baseClass: AnyClass = type(of: content)
        let baseName = NSStringFromClass(baseClass)
        if baseName.hasSuffix("_NoAccessory") { return }      // 이미 적용됨

        let newName = baseName + "_NoAccessory"
        var newClass: AnyClass? = NSClassFromString(newName)
        if newClass == nil, let created = objc_allocateClassPair(baseClass, newName, 0) {
            if let method = class_getInstanceMethod(NoAccessoryProvider.self,
                                                    #selector(getter: NoAccessoryProvider.inputAccessoryView)) {
                class_addMethod(created,
                                #selector(getter: UIResponder.inputAccessoryView),
                                method_getImplementation(method),
                                method_getTypeEncoding(method))
            }
            objc_registerClassPair(created)
            newClass = created
        }
        if let newClass { object_setClass(content, newClass) }
    }
}

private final class NoAccessoryProvider: NSObject {
    @objc var inputAccessoryView: AnyObject? { nil }
}
