import SwiftUI
import Combine

/// 업데이트 알림의 프로필 사진: GitHub 사진을 먼저 받고, 안 되면 GitLab 계정 사진으로 넘어감
/// 주소가 돌려준 것이 실제 이미지인지 디코딩으로 확인함 (깃랩 사진 주소는 로그인 화면(HTML)으로 넘어가 이미지가 아님)
@MainActor
final class AvatarLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var started = false

    private static let githubAvatar = URL(string: "https://github.com/pgyczmkmg8-hue.png")
    private static let gitlabUserAPI = URL(string: "https://gitlab.com/api/v4/users?username=Yami_Q_Ray")

    func load() async {
        guard !started else { return }
        started = true
        if let img = await Self.fetchImage(Self.githubAvatar) {
            image = img
            return
        }
        if let url = await Self.gitlabAvatarURL(), let img = await Self.fetchImage(url) {
            image = img
        }
    }

    /// 주소에서 받은 것이 이미지로 풀리면 그 이미지 (HTTP 200이 아니거나 이미지가 아니면 nil)
    private static func fetchImage(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        let req = URLRequest(url: url, timeoutInterval: 15)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }

    /// GitLab 사용자 정보의 avatar_url. 해상도 인자(s·width)가 있으면 256으로 맞춤
    private static func gitlabAvatarURL() async -> URL? {
        guard let api = gitlabUserAPI,
              let (data, resp) = try? await URLSession.shared.data(from: api),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let raw = list.first?["avatar_url"] as? String,
              var comps = URLComponents(string: raw) else { return nil }
        var items = comps.queryItems ?? []
        for key in ["s", "width"] {
            if let i = items.firstIndex(where: { $0.name == key }) { items[i].value = "256" }
        }
        comps.queryItems = items.isEmpty ? nil : items
        return comps.url
    }
}

/// 새 버전 알림창 (그림 128×128: 저장소 주인의 프로필 사진, 그 아래 글과 버튼)
struct UpdateCard: View {
    @ObservedObject var fonts = FontStore.shared
    let release: AppRelease
    let onClose: () -> Void
    @StateObject private var avatar = AvatarLoader()

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
                    if let image = avatar.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.2)
                    }
                }
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
                .task { await avatar.load() }

                VStack(spacing: 10) {
                    Text("새 버전 \(release.version)")
                        .font(fonts.styleFont(.headline))
                    Text(notesText)
                        .font(fonts.styleFont(.footnote))
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
                .font(fonts.styleFont(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
