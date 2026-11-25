import SwiftUI
import UniformTypeIdentifiers

// MARK: - 설정 → 글꼴 (기본 · 프리셋 받기 · 파일에서 가져오기)

/// 세부 설정의 '글꼴' 줄 (고른 글꼴 이름 표시)
struct FontSettingsRow: View {
    @ObservedObject private var fonts = FontStore.shared

    var body: some View {
        NavigationLink { FontSettingsView() } label: {
            LabeledContent("글꼴", value: fonts.selectedName)
        }
    }
}

struct FontSettingsView: View {
    @ObservedObject private var fonts = FontStore.shared
    @State private var importing = false

    /// 파일 앱에서 고를 수 있는 글꼴 종류
    private static let fontTypes: [UTType] = [.font, UTType(filenameExtension: "ttf"), UTType(filenameExtension: "otf")].compactMap { $0 }

    private var presetIDs: Set<String> { Set(FontPresets.all.map(\.id)) }
    /// 파일 앱에서 가져온 글꼴 (프리셋이 아닌 것)
    private var imported: [InstalledFont] { fonts.installed.filter { !presetIDs.contains($0.id) } }

    var body: some View {
        Form {
            Section {
                Text("가나다라마 ABC 123 · 디시 글 본문 미리보기")
                    .font(fonts.swiftUIFont ?? .body)
                    .lineLimit(2)
            } header: {
                Text("미리보기")
            } footer: {
                Text("고른 글꼴은 앱 전체와 디시 웹페이지의 글자에 적용돼요. 버튼이나 아이콘에 따로 지정된 글꼴은 그대로 둬요.")
            }

            Section {
                ForEach(FontPresets.all) { preset in
                    if preset.isSystem {
                        choiceRow(id: FontStore.systemID, title: preset.name, subtitle: preset.subtitle)
                    } else {
                        presetRow(preset)
                    }
                }
            } header: {
                Text("프리셋")
            } footer: {
                Text(FontPresets.all.count <= 1
                     ? "프리셋은 아직 없어요. 글꼴 파일 주소를 추가하면 여기서 받을 수 있어요."
                     : "받기를 눌러 기기에 저장한 뒤, 글꼴 이름을 눌러 고르세요. 받은 글꼴은 인터넷 없이도 써요.")
            }

            if !imported.isEmpty {
                Section {
                    ForEach(imported) { font in
                        choiceRow(id: font.id, title: font.name, subtitle: "파일에서 가져옴")
                            .swipeActions {
                                Button(role: .destructive) { fonts.delete(font.id) } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("가져온 글꼴")
                }
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("파일에서 .ttf · .otf 가져오기", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("파일 앱에서 글꼴 파일을 고르면 기기에 저장하고 바로 적용해요. 가져온 글꼴은 목록에서 밀어서 지울 수 있어요.")
            }

            if let message = fonts.message {
                Section {
                    Text(message).foregroundStyle(.red).font(.footnote)
                }
            }

            if fonts.selectedID != FontStore.systemID {
                Section {
                    Button("시스템 글꼴로 되돌리기", role: .destructive) { fonts.select(FontStore.systemID) }
                }
            }
        }
        .navigationTitle("글꼴")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.fontTypes, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { fonts.importFile(url) }
            case .failure(let error):
                fonts.message = error.localizedDescription
            }
        }
    }

    /// 고를 수 있는 줄 (받아 둔 글꼴 / 시스템). 누르면 고르고, 선택 표시를 붙임
    private func choiceRow(id: String, title: String, subtitle: String) -> some View {
        Button {
            fonts.select(id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if fonts.selectedID == id {
                    Image(systemName: "checkmark").foregroundStyle(DCTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
    }

    /// 프리셋 줄: 받기 전 / 받는 중 / 받은 뒤(고르기·지우기)
    @ViewBuilder
    private func presetRow(_ preset: FontPreset) -> some View {
        let isInstalled = fonts.installed.contains { $0.id == preset.id }
        if isInstalled {
            choiceRow(id: preset.id, title: preset.name, subtitle: preset.subtitle)
                .swipeActions {
                    Button(role: .destructive) { fonts.delete(preset.id) } label: {
                        Label("지우기", systemImage: "trash")
                    }
                }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                    Text(preset.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if fonts.busyIDs.contains(preset.id) {
                    ProgressView()
                } else {
                    Button("받기") { fonts.download(preset) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}
