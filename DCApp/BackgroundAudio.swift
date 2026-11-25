import AVFoundation
import Foundation
import UIKit

// MARK: - 배경 음악 유지하며 영상 재생 (세부 설정)
//
// 켜면 오디오 세션을 playback + mixWithOthers로 바꿔, 영상을 틀어도 듣고 있던 음악이 멈추지 않고 함께 난다.
// WebKit은 영상이 재생되기 시작하면 세션을 자기 방식(섞이지 않는 재생)으로 바꾸므로,
// 그 뒤로는 다음 경우에 다시 맞춘다: 영상·소리 시작(웹 화면이 알려 줌), 시스템 중단이 끝남, 미디어 서비스 재설정, 다른 앱 소리 변화, 앱 복귀.
// 부작용: playback 범주는 무음 스위치를 켜 둬도 소리가 난다. 끄면 iOS 기본 범주(soloAmbient)로 되돌린다.

enum BackgroundAudio {
    static let key = "mixAudioWithOthers"
    static var enabled: Bool { Profile.defaults.bool(forKey: key) }

    /// 시스템 알림 구독 (켜져 있을 때만)
    private static var observers: [NSObjectProtocol] = []

    /// 앱 시작 때: 켜져 있을 때만 적용 (꺼져 있으면 iOS 기본 그대로 둠)
    static func applyStored() {
        if enabled { apply(true) }
    }

    /// 설정을 바꿀 때 / 앱 시작 때 호출
    static func apply(_ on: Bool) {
        if on {
            startObserving()
            configure()
        } else {
            stopObserving()
            restoreDefault()
        }
    }

    /// 지금 세션이 우리 설정(재생 범주 + 섞어 쓰기)과 다르면 다시 맞춤 (같으면 아무것도 안 함)
    static func reassert() {
        guard enabled else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category == .playback && session.categoryOptions.contains(.mixWithOthers) { return }
        configure()
    }

    /// 웹 화면에서 영상·소리가 시작됐을 때: WebKit이 세션을 바꾸는 순간 전후로 몇 번 다시 맞춤
    static func reassertAfterMediaStart() {
        guard enabled else { return }
        reassert()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            reassert()
            try? await Task.sleep(for: .milliseconds(1000))
            reassert()
        }
    }

    private static func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[BackgroundAudio] 오디오 세션 설정 실패: \(error)")
        }
    }

    private static func restoreDefault() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.soloAmbient, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("[BackgroundAudio] 기본 세션 복원 실패: \(error)")
        }
    }

    private static func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            AVAudioSession.interruptionNotification,                 // 전화·알람 등 중단이 끝났을 때 세션이 바뀌어 있을 수 있음
            AVAudioSession.silenceSecondaryAudioHintNotification,    // 다른 앱 소리가 시작·끝날 때
            AVAudioSession.mediaServicesWereResetNotification,       // 미디어 서비스가 다시 시작됨
            UIApplication.didBecomeActiveNotification,               // 앱으로 돌아올 때
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in BackgroundAudio.reassert() }
            }
        }
    }

    private static func stopObserving() {
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers = []
    }
}
