import SwiftUI

/// 앱 아이콘 바꾸기
/// Assets에 추가한 대체 아이콘(App Icon 세트)을 자동으로 찾아 목록으로 보여줘요.
/// (Build Settings의 "Include All App Icon Assets"가 Yes여야 앱에 포함됨)
struct AppIconSettingsView: View {
    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var errorMessage: String?

    /// 빌드할 때 Xcode가 Info.plist에 기록한 대체 아이콘 이름들
    private var alternates: [String] {
        guard let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
              let alt = icons["CFBundleAlternateIcons"] as? [String: Any] else { return [] }
        return alt.keys.sorted()
    }

    private var primaryName: String? {
        guard let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] else { return nil }
        return primary["CFBundleIconName"] as? String
    }

    var body: some View {
        List {
            Section {
                row(name: nil, label: "기본")
                ForEach(alternates, id: \.self) { name in
                    row(name: name, label: displayName(name))
                }
            }
            // (아이콘 추가 방법: Assets에 'AppIcon-이름' iOS App Icon + 미리보기용 'AppIcon-이름-Preview' Image Set,
            //  Build Settings → Include All App Icon Assets = Yes)
        }
        .navigationTitle("앱 아이콘")
        .alert("아이콘을 바꾸지 못했어요",
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(name: String?, label: String) -> some View {
        Button {
            change(to: name)
        } label: {
            HStack(spacing: 14) {
                preview(for: name)
                Text(label).foregroundStyle(.primary)
                Spacer()
                if current == name {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                }
            }
        }
    }

    @ViewBuilder
    private func preview(for name: String?) -> some View {
        let key = name ?? primaryName ?? "AppIcon"
        // 미리보기 그림: 이름에 공백·점이 있으면 Assets에서 못 쓰므로 글자·숫자만 남긴 이름(Preview-AppIcon-…)도 찾음
        let clean = "Preview-" + key.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        if let ui = UIImage(named: "\(key)-Preview") ?? UIImage(named: clean) ?? UIImage(named: key) {
            Image(uiImage: ui)
                .resizable()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "app").foregroundStyle(.secondary))
        }
    }

    private func displayName(_ name: String) -> String {
        name.hasPrefix("AppIcon-") ? String(name.dropFirst("AppIcon-".count)) : name
    }

    private func change(to name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "이 기기에서는 아이콘 변경을 지원하지 않아요."
            return
        }
        guard current != name else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                current = name
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
