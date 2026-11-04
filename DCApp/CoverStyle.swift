import SwiftUI
import PhotosUI
import Combine
import ImageIO

// MARK: - 가림막(블라인드) 꾸미기
// 두 곳에서 쓰는 가림막의 모양을 바꿀 수 있게 함
//  - 잠금 화면: 앱 잠금이 켜진 채 앱을 켜거나 돌아왔을 때
//  - 앱 전환 화면: 멀티태스킹 화면에서 내용을 가릴 때 (설정의 '앱 전환 화면에서 가리기')
// 바탕(흐리게·색·사진 + 흐림 정도)과 가운데 표시(자물쇠·앱 로고·문구·없음)를 고르고, 두 화면에 같은 모양을 쓸지 따로 쓸지 정함

enum CoverKind: String, CaseIterable, Identifiable {
    case lock, switcher
    var id: String { rawValue }
    var label: String { self == .lock ? "잠금 화면" : "앱 전환 화면" }
}

enum CoverBackground: String, Codable, CaseIterable, Identifiable {
    case blur, color, photo
    var id: String { rawValue }
    var label: String {
        switch self {
        case .blur: "흐리게"
        case .color: "색"
        case .photo: "사진"
        }
    }
}

enum CoverCenter: String, Codable, CaseIterable, Identifiable {
    case lock, logo, text, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lock: "자물쇠"
        case .logo: "앱 로고"
        case .text: "문구"
        case .none: "없음"
        }
    }
}

struct CoverStyle: Codable, Equatable {
    var background: CoverBackground = .blur
    var colorHex = "3B4890"
    /// 흐림 정도 0(약)…4(강). 흐리게=블러 재질 단계, 사진=사진에 거는 흐림
    var blurLevel = 0
    var center: CoverCenter = .lock
    var text = ""
    var hasPhoto = false
}

@MainActor
final class CoverStore: ObservableObject {
    static let shared = CoverStore()

    private let stylesKey = "coverStyles"
    private let sameKey = "coverSameForBoth"

    @Published private(set) var styles: [String: CoverStyle]
    @Published var sameForBoth: Bool {
        didSet { UserDefaults.standard.set(sameForBoth, forKey: sameKey) }
    }
    private var images: [String: UIImage] = [:]

    private init() {
        if let d = UserDefaults.standard.data(forKey: stylesKey),
           let s = try? JSONDecoder().decode([String: CoverStyle].self, from: d) {
            styles = s
        } else {
            styles = [:]
        }
        sameForBoth = UserDefaults.standard.object(forKey: sameKey) as? Bool ?? true
    }

    /// 같은 모양을 쓰면 잠금 화면 설정이 두 곳에 다 쓰임
    private func key(_ k: CoverKind) -> String { sameForBoth ? CoverKind.lock.rawValue : k.rawValue }

    func style(_ k: CoverKind) -> CoverStyle { styles[key(k)] ?? CoverStyle() }

    func update(_ k: CoverKind, _ change: (inout CoverStyle) -> Void) {
        var s = style(k)
        change(&s)
        styles[key(k)] = s
        if let d = try? JSONEncoder().encode(styles) { UserDefaults.standard.set(d, forKey: stylesKey) }
    }

    // MARK: 사진

    private func fileURL(_ k: CoverKind) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Cover", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cover-\(key(k)).jpg")
    }

    func image(_ k: CoverKind) -> UIImage? {
        guard style(k).hasPhoto else { return nil }
        if let i = images[key(k)] { return i }
        guard let d = try? Data(contentsOf: fileURL(k)), let i = UIImage(data: d) else { return nil }
        images[key(k)] = i
        return i
    }

    /// 앱을 켤 때 미리 읽어 두어 가림막이 늦게 뜨지 않게
    func preload() {
        for k in CoverKind.allCases { _ = image(k) }
    }

    func setPhoto(_ k: CoverKind, data: Data) async {
        let target = fileURL(k)
        let img: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            let ui = UIImage(cgImage: cg)
            if let jpg = ui.jpegData(compressionQuality: 0.85) { try? jpg.write(to: target, options: .atomic) }
            return ui
        }.value
        guard let img else { return }
        images[key(k)] = img
        update(k) { $0.hasPhoto = true; $0.background = .photo }
        objectWillChange.send()
    }

    func removePhoto(_ k: CoverKind) {
        try? FileManager.default.removeItem(at: fileURL(k))
        images[key(k)] = nil
        update(k) { $0.hasPhoto = false; if $0.background == .photo { $0.background = .blur } }
        objectWillChange.send()
    }
}

// MARK: - 그리기

private extension Color {
    init(coverHex hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    var coverHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.62
    }
}

/// 가림막 바탕
struct CoverBackgroundView: View {
    let style: CoverStyle
    let image: UIImage?
    /// '흐리게'일 때 앱 화면을 미리 찍어 흐리게 만든 그림. 시스템 블러(Material)는 멀티태스킹 화면용 캡처에서 검게 찍히는 일이 있어서, 그림으로 직접 깔아 줌
    var blurredSnapshot: UIImage? = nil

    private var material: Material {
        [Material.ultraThinMaterial, .thinMaterial, .regularMaterial, .thickMaterial, .ultraThickMaterial][min(max(style.blurLevel, 0), 4)]
    }

    var body: some View {
        ZStack {
            switch style.background {
            case .blur:
                if let blurredSnapshot {
                    GeometryReader { g in
                        Image(uiImage: blurredSnapshot)
                            .resizable().scaledToFill()
                            .frame(width: g.size.width, height: g.size.height)
                            .clipped()
                    }
                } else {
                    Rectangle().fill(material)
                }
                DCTheme.navy.opacity(0.25)
            case .color:
                Color(coverHex: style.colorHex)
            case .photo:
                if let image {
                    GeometryReader { g in
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(width: g.size.width, height: g.size.height)
                            .clipped()
                            .blur(radius: CGFloat(style.blurLevel) * 8)
                    }
                    Color.black.opacity(0.12)
                } else {
                    DCTheme.navy
                }
            }
        }
        .ignoresSafeArea()
    }

    /// 바탕 위 글자·아이콘 색
    var foreground: Color {
        switch style.background {
        case .color: Color(coverHex: style.colorHex).isLight ? .black : .white
        default: .white
        }
    }
}

/// 가림막 가운데 표시
struct CoverCenterView: View {
    let style: CoverStyle
    let locked: Bool
    let color: Color

    var body: some View {
        switch style.center {
        case .lock:
            Image(systemName: locked ? "lock.fill" : "eye.slash.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(color)
        case .logo:
            Image("HomeLogo")
                .resizable().scaledToFit()
                .frame(width: 96, height: 96)
        case .text:
            Text(style.text.isEmpty ? "DCAPP" : style.text)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(color)
                .padding(.horizontal, 24)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - 설정 화면

struct CoverSettingsView: View {
    @ObservedObject private var store = CoverStore.shared
    @State private var kind: CoverKind = .lock
    @State private var photoItem: PhotosPickerItem?

    private var style: CoverStyle { store.style(kind) }

    private func bind<T>(_ get: @escaping (CoverStyle) -> T, _ set: @escaping (inout CoverStyle, T) -> Void) -> Binding<T> {
        Binding(get: { get(store.style(kind)) }, set: { v in store.update(kind) { set(&$0, v) } })
    }

    var body: some View {
        Form {
            Section {
                Toggle("두 화면에 같은 모양 쓰기", isOn: $store.sameForBoth)
                if !store.sameForBoth {
                    Picker("꾸밀 화면", selection: $kind) {
                        ForEach(CoverKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                Text("잠금 화면은 앱 잠금이 켜진 채 앱을 켜거나 돌아왔을 때, 앱 전환 화면은 멀티태스킹 화면에서 내용을 가릴 때 보여요.")
            }

            Section("미리보기") {
                preview.frame(maxWidth: .infinity).listRowInsets(EdgeInsets())
            }

            Section("바탕") {
                Picker("바탕", selection: bind({ $0.background }, { $0.background = $1 })) {
                    ForEach(CoverBackground.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if style.background == .color {
                    ColorPicker("색", selection: Binding(
                        get: { Color(coverHex: style.colorHex) },
                        set: { c in store.update(kind) { $0.colorHex = c.coverHex } }))
                }
                if style.background == .photo {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(style.hasPhoto ? "다른 사진 고르기" : "사진 고르기", systemImage: "photo")
                    }
                    if style.hasPhoto {
                        Button("사진 지우기", role: .destructive) { store.removePhoto(kind) }
                    }
                }
                if style.background != .color {
                    Picker("흐림 정도", selection: bind({ $0.blurLevel }, { $0.blurLevel = $1 })) {
                        ForEach(0..<5) { Text($0 == 0 ? "약" : ($0 == 4 ? "강" : "\($0 + 1)")).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("가운데 표시") {
                Picker("표시", selection: bind({ $0.center }, { $0.center = $1 })) {
                    ForEach(CoverCenter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if style.center == .text {
                    TextField("가림막에 보일 문구", text: bind({ $0.text }, { $0.text = $1 }))
                }
            }

            Section {
                Button("기본 모양으로", role: .destructive) {
                    store.removePhoto(kind)
                    store.update(kind) { $0 = CoverStyle() }
                }
            }
        }
        .navigationTitle("가림막 꾸미기")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await store.setPhoto(kind, data: data)
                }
                photoItem = nil
            }
        }
    }

    private var preview: some View {
        let bg = CoverBackgroundView(style: style, image: store.image(kind))
        return ZStack {
            Color(uiColor: .secondarySystemBackground)
            bg
            CoverCenterView(style: style, locked: kind == .lock, color: bg.foreground)
        }
        .frame(height: 260)
        .clipped()
    }
}
