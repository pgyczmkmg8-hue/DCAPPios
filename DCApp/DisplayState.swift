import SwiftUI
import UIKit
import Combine

/// iPhone Duo가 접혀 있는지(= 바깥 디스플레이를 쓰는 중인지) 알려 줌.
/// iOS 27.1의 힌지 상태(`UIHingeInteraction`)를 읽음: 닫힘 = 바깥 디스플레이, 부분·완전히 열림 = 안쪽 디스플레이
@MainActor
final class DisplayState: ObservableObject {
    static let shared = DisplayState()
    /// 힌지가 닫혀 있음 (바깥 디스플레이). 상태를 모르면 false
    @Published var outerDisplay = false
}

/// 화면 뒤에 붙여 두면 힌지 상태가 바뀔 때마다 DisplayState를 갱신하는 보이지 않는 뷰
struct HingeProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { _, update in
                let closed = update.hinge?.status == .closed
                Task { @MainActor in
                    if DisplayState.shared.outerDisplay != closed { DisplayState.shared.outerDisplay = closed }
                }
            }
            v.addInteraction(interaction)
        }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
