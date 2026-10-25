import SwiftUI
import Combine
import GameController

/// 아이패드 등에 하드웨어 키보드(매직 키보드 등)가 연결돼 있는지.
/// 트랙패드로는 화면 쓸기 뒤로가기가 안 되므로, 키보드가 있으면 뒤로가기 버튼을 보여 줌
@MainActor
final class HardwareKeyboard: ObservableObject {
    static let shared = HardwareKeyboard()
    @Published private(set) var connected = GCKeyboard.coalesced != nil

    private init() {
        // 키보드 연결/해제 알림 → 메인 스레드에서 상태 갱신 (Combine으로 받아서 self 캡처 문제 없음)
        NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)
            .merge(with: NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect))
            .receive(on: DispatchQueue.main)
            .map { _ in GCKeyboard.coalesced != nil }
            .assign(to: &$connected)
    }
}
