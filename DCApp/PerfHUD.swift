import SwiftUI
import Combine
import Darwin

/// 디버그용 성능 숫자: 앱 메모리(phys_footprint)와 CPU 사용률 (설정 → 버전 정보에서 켬)
/// 웹페이지는 WebKit의 별도 프로세스(WebContent)에서 돌아서 여기 숫자에는 빠짐
enum PerfSampler {
    nonisolated static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// 살아 있는 모든 스레드의 CPU 사용률 합 (%). 코어가 여러 개라 100%를 넘을 수 있음
    nonisolated static func cpuPercent() -> Double {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let list = threads else { return 0 }
        var total = 0.0
        for i in 0..<Int(count) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(list[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if kr == KERN_SUCCESS && info.flags & TH_FLAGS_IDLE == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }
        vm_deallocate(mach_task_self_,
                      vm_address_t(UInt(bitPattern: list)),
                      vm_size_t(count) * vm_size_t(MemoryLayout<thread_t>.size))
        return total
    }
}

@MainActor
final class PerfHUD: ObservableObject {
    @Published var memMB: Double = 0
    @Published var cpu: Double = 0
    private var timer: AnyCancellable?

    func start() {
        sample()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sample() }
    }

    func stop() { timer = nil }

    private func sample() {
        memMB = PerfSampler.footprintMB()
        cpu = PerfSampler.cpuPercent()
    }
}

/// 화면 위에 뜨는 작은 숫자판 (터치는 막지 않음)
struct PerfHUDView: View {
    @StateObject private var hud = PerfHUD()

    var body: some View {
        Text(String(format: "메모리 %.0fMB · CPU %.0f%%", hud.memMB, hud.cpu))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.7), in: Capsule())
            .allowsHitTesting(false)
            .onAppear { hud.start() }
            .onDisappear { hud.stop() }
    }
}
