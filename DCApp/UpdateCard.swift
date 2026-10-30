import SwiftUI

/// 새 버전 알림창 (그림 128×128: 깃헙 계정 프로필 사진, 그 아래 글과 버튼)
struct UpdateCard: View {
    let release: AppRelease
    let onClose: () -> Void

    /// 프로필 사진 주소 (저장소 주인의 깃헙 계정)
    private static let avatarURL = URL(string: "https://github.com/pgyczmkmg8-hue.png")

    private var notesText: String {
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return "지금 버전: \(UpdateChecker.currentVersion)" + (notes.isEmpty ? "" : "\n\n" + String(notes.prefix(300)))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(spacing: 0) {
                AsyncImage(url: Self.avatarURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.2)
                    }
                }
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 16)
                .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    Text("새 버전 \(release.version)")
                        .font(.headline)
                    Text(notesText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(8)
                    buttons
                }
                .padding(16)
                .frame(width: 256)
            }
            .frame(width: 256)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(radius: 12)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        // 버전 정보 → 업데이트에서 고른 앱(Feather/SideStore/LiveContainer)으로 바로 설치
        let installer = UpdateView.Installer.current
        VStack(spacing: 8) {
            if let ipa = release.ipaURL, let url = installer.installURL(for: ipa) {
                cardButton("\(installer.name)로 바로 설치") { UIApplication.shared.open(url); onClose() }
            }
            cardButton("다운로드") { UIApplication.shared.open(release.ipaURL ?? release.pageURL); onClose() }
            cardButton("릴리스 노트 보기") { UIApplication.shared.open(release.pageURL); onClose() }
            if release.requiredUpTo == nil {   // 필수 업데이트는 건너뛸 수 없음
                cardButton("이 버전 건너뛰기") { UpdateChecker.skip(release.version); onClose() }
            }
            cardButton("나중에") { onClose() }
        }
    }

    private func cardButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
