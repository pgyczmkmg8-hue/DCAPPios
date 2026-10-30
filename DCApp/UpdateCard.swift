import SwiftUI

/// 업데이트 알림창 그림: 지금 앱 아이콘 또는 AboutImage 중 하나를 확률 같게 고름
enum UpdateArt {
    /// 버전 정보 화면의 사진 목록과 같은 이름을 씀
    static var aboutImages: [String] { AboutView.aboutImages.map(\.name) }

    static func random() -> UIImage? {
        if Bool.random(), let icon = currentIconImage() { return icon }
        return aboutImages.randomElement().flatMap { UIImage(named: $0) } ?? currentIconImage()
    }

    /// 지금 선택된 앱 아이콘의 미리보기 그림 (AppIconSettings와 같은 이름 규칙)
    private static func currentIconImage() -> UIImage? {
        let name = UIApplication.shared.alternateIconName
        let key = name ?? primaryIconName ?? "AppIcon"
        let clean = "Preview-" + key.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return UIImage(named: "\(key)-Preview") ?? UIImage(named: clean) ?? UIImage(named: key)
    }

    private static var primaryIconName: String? {
        guard let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] else { return nil }
        return primary["CFBundleIconName"] as? String
    }
}

/// 새 버전 알림창 (그림 128×128, 그 아래 글과 버튼)
struct UpdateCard: View {
    let release: AppRelease
    let image: UIImage?
    let onClose: () -> Void

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
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
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
            cardButton("이 버전 건너뛰기") { UpdateChecker.skip(release.version); onClose() }
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
