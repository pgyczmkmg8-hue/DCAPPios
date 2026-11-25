import SwiftUI

// MARK: - 계정 전환 로그인 가림막
// 저장된 계정을 골라 자동 로그인하는 동안 디시 원본 로그인 화면(msign)이 잠깐 보이지 않게 '로그인 중…'으로 가린다.
// 가림막은 WebViewModel.loginCover가 정하고, 로그인 화면을 벗어나거나 안내창이 뜨거나 시간이 지나면 풀린다.

struct LoginCoverHost: View {
    @ObservedObject var model: WebViewModel

    var body: some View {
        if let text = model.loginCover {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .transition(.opacity)
        }
    }
}
