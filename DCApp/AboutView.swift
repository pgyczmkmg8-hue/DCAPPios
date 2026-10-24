import SwiftUI

/// 설정 → 버전정보
/// 사진은 Assets에 "AboutImage"라는 이름의 Image Set으로 넣으면 표시돼요.
struct AboutView: View {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }
    static var versionString: String { "\(version) (\(build))" }

    /// 사진이 없을 때 보여주는 자리
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.quaternary)
            .frame(width: 200, height: 200)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.largeTitle)
                    Text("Assets에 AboutImage를\n추가하면 여기에 보여요")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "DCApp"
    }

    @State private var confetti = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let image = UIImage(named: "AboutImage") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                        .onTapGesture { confetti += 1 }      // 사진을 누르면 한 번 더 축하
                } else {
                    placeholder
                        .onTapGesture { confetti += 1 }
                }

                VStack(spacing: 6) {
                    Text(appName)
                        .font(.title2.bold())
                    Text("버전 \(Self.version) (빌드 \(Self.build))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .padding(.horizontal)
        }
        .overlay {
            ConfettiView(trigger: confetti)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
        .onAppear {
            confetti += 1                                       // 들어오면 축하 꽃가루
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .navigationTitle("버전정보")
        .navigationBarTitleDisplayMode(.inline)
    }
}
