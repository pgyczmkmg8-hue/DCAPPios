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

    /// 업데이트: 자동 확인 켜기/끄기 + 지금 확인
    private var updateBox: some View {
        VStack(spacing: 0) {
            Toggle("업데이트 자동 확인", isOn: $autoCheck)
                .padding(.vertical, 10)
            Divider()
            Button {
                Task { await checkNow() }
            } label: {
                HStack {
                    Text("업데이트 확인")
                    Spacer()
                    if checking { ProgressView() }
                }
                .contentShape(Rectangle())
            }
            .disabled(checking)
            .padding(.vertical, 12)
            if let checkResult {
                Text(checkResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: 420)
    }

    /// 수동 확인: 패치 버전이라도 새것이면 알려 줌
    private func checkNow() async {
        checking = true
        checkResult = nil
        let latest = await UpdateChecker.fetchLatest()
        checking = false
        guard let latest else {
            checkResult = "확인하지 못했어요. 인터넷 연결을 확인해 주세요."
            return
        }
        if UpdateChecker.isNewer(latest.version, than: Self.version) {
            foundRelease = latest
            checkResult = "새 버전 \(latest.version)이 있어요."
        } else {
            checkResult = "최신 버전이에요. (GitHub 최신: \(latest.version))"
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "DCApp"
    }

    @State private var confetti = 0
    @AppStorage(UpdateChecker.autoCheckKey) private var autoCheck = true
    @State private var checking = false
    @State private var checkResult: String?
    @State private var foundRelease: AppRelease?

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

                updateBox

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
        .alert(foundRelease.map { "새 버전 \($0.version)" } ?? "",
               isPresented: Binding(get: { foundRelease != nil }, set: { if !$0 { foundRelease = nil } }),
               presenting: foundRelease) { r in
            Button("다운로드") { UIApplication.shared.open(r.ipaURL ?? r.pageURL) }
            Button("릴리스 노트 보기") { UIApplication.shared.open(r.pageURL) }
            Button("닫기", role: .cancel) {}
        } message: { r in
            let notes = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            Text("지금 버전: \(Self.version)" + (notes.isEmpty ? "" : "\n\n" + String(notes.prefix(300))))
        }
        .navigationTitle("버전정보")
        .navigationBarTitleDisplayMode(.inline)
    }
}
