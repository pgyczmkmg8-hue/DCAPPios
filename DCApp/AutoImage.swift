import SwiftUI
import Combine
import PhotosUI

// MARK: - 모델

struct AutoImage: Codable, Identifiable, Hashable {
    var id: UUID
    var filename: String
    var mime: String
    var ext: String
    var galleries: [String]   // 비어 있으면 "모든 갤러리 공통"
}

enum AutoImageMode: String, Codable, CaseIterable, Identifiable {
    case auto, manual
    var id: String { rawValue }
    var label: String { self == .auto ? "글쓰기 열면 자동 첨부" : "버튼 눌러서 첨부" }
}

/// 갤러리별 자짤 사용 방식
enum GalleryAutoMode: String, Codable, CaseIterable, Identifiable {
    case inherit, auto, manual, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .inherit: "기본 설정 따르기"
        case .auto: "자동 첨부"
        case .manual: "버튼 눌러서 첨부"
        case .off: "이 갤러리에서는 끄기"
        }
    }
}

struct GalleryAutoRule: Codable, Equatable {
    var mode: GalleryAutoMode = .inherit
    var useCommon = true        // 이 갤러리 전용 자짤이 없을 때 공통 자짤 쓰기
}

struct AutoImageSettings: Codable {
    var enabled = false
    var mode: AutoImageMode = .auto
    var images: [AutoImage] = []
    var rules: [String: GalleryAutoRule]? = nil   // 갤러리ID → 갤러리별 설정 (예전 버전 호환 위해 옵션)
}

// MARK: - 저장소

/// 자짤 사진과 설정. 사진 파일은 앱 내부 저장공간(Application Support/AutoImages)에 보관해요.
@MainActor
final class AutoImageStore: ObservableObject {
    static let shared = AutoImageStore()

    @Published var settings: AutoImageSettings {
        didSet { save() }
    }

    private let key = "autoImageSettings"
    let folder: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("AutoImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(AutoImageSettings.self, from: data) {
            settings = saved
        } else {
            settings = AutoImageSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func fileURL(_ img: AutoImage) -> URL { folder.appendingPathComponent(img.filename) }

    /// 앨범에서 고른 사진 추가 (GIF는 움짤 유지, 나머지는 긴 변 1600px JPEG로 줄여서 저장)
    @discardableResult
    func add(data: Data) -> Bool {
        guard let prepared = Self.prepare(data) else { return false }
        let id = UUID()
        let filename = "\(id.uuidString).\(prepared.ext)"
        do {
            try prepared.data.write(to: folder.appendingPathComponent(filename))
        } catch {
            return false
        }
        settings.images.append(AutoImage(id: id, filename: filename, mime: prepared.mime,
                                         ext: prepared.ext, galleries: []))
        return true
    }

    func remove(_ img: AutoImage) {
        try? FileManager.default.removeItem(at: fileURL(img))
        settings.images.removeAll { $0.id == img.id }
    }

    func setGalleries(_ galleries: [String], for img: AutoImage) {
        guard let i = settings.images.firstIndex(where: { $0.id == img.id }) else { return }
        settings.images[i].galleries = galleries
    }

    /// 이 갤러리에 쓸 자짤 1장 고르기: 갤러리 전용 자짤이 있으면 그중에서, 없으면 공통 자짤 중에서 랜덤
    func pick(for galleryID: String) -> AutoImage? {
        candidates(for: galleryID).randomElement()
    }

    /// 이 갤러리에서 쓸 수 있는 자짤들: 전용 자짤이 있으면 그것만, 없으면(공통 허용 시) 공통 자짤
    func candidates(for galleryID: String) -> [AutoImage] {
        let specific = settings.images.filter { $0.galleries.contains(galleryID) }
        if !specific.isEmpty { return specific }
        guard rule(for: galleryID).useCommon else { return [] }
        return settings.images.filter { $0.galleries.isEmpty }
    }

    // MARK: 갤러리별 설정

    func rule(for galleryID: String) -> GalleryAutoRule {
        settings.rules?[galleryID] ?? GalleryAutoRule()
    }

    func setRule(_ rule: GalleryAutoRule, for galleryID: String) {
        var rules = settings.rules ?? [:]
        rules[galleryID] = rule
        settings.rules = rules
    }

    func removeRule(for galleryID: String) {
        settings.rules?[galleryID] = nil
        for i in settings.images.indices {
            settings.images[i].galleries.removeAll { $0 == galleryID }
        }
    }

    /// 이 갤러리에서 실제로 적용되는 (사용 여부, 방식)
    func effective(for galleryID: String) -> (enabled: Bool, mode: AutoImageMode) {
        switch rule(for: galleryID).mode {
        case .inherit: (settings.enabled, settings.mode)
        case .auto: (true, .auto)
        case .manual: (true, .manual)
        case .off: (false, settings.mode)
        }
    }

    /// 갤러리별 설정이 있거나 전용 자짤이 있는 갤러리 목록
    var configuredGalleries: [String] {
        var ids = Set(settings.rules?.keys.map { $0 } ?? [])
        for img in settings.images { ids.formUnion(img.galleries) }
        return ids.sorted()
    }

    /// 사진 하나를 이 갤러리 전용으로 넣거나 빼기
    func toggle(_ img: AutoImage, in galleryID: String) {
        guard let i = settings.images.firstIndex(where: { $0.id == img.id }) else { return }
        if let j = settings.images[i].galleries.firstIndex(of: galleryID) {
            settings.images[i].galleries.remove(at: j)
        } else {
            settings.images[i].galleries.append(galleryID)
        }
    }

    /// 글쓰기 화면이면 갤러리 ID를 돌려줌 (ID를 모르면 빈 문자열), 글쓰기 화면이 아니면 nil
    ///  - https://m.dcinside.com/write/{id}
    ///  - https://m.dcinside.com/mini/write/{id}
    ///  - https://gall.dcinside.com/board/write/?id={id}
    nonisolated static func writeGalleryID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), host.hasSuffix("dcinside.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        // 일반·마이너는 /write/갤ID, 미니는 /writemini/갤ID, 인물은 /writepr/갤ID (수정은 뒤에 /modify/글번호)
        guard let i = parts.firstIndex(where: { ["write", "writemini", "writepr"].contains($0) }) else { return nil }
        if i + 1 < parts.count { return parts[i + 1] }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value ?? ""
    }

    nonisolated static func prepare(_ data: Data) -> (data: Data, mime: String, ext: String)? {
        if data.starts(with: [0x47, 0x49, 0x46]) {           // "GIF"
            return (data, "image/gif", "gif")
        }
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        return (jpg, "image/jpeg", "jpg")
    }

    /// 앱 글쓰기에 올릴 사진 준비. maxWidth가 없으면(원본 크기) JPEG·PNG·GIF는 받은 파일 그대로,
    /// 디시가 못 받는 형식(HEIC 등)만 같은 크기의 JPEG로 바꿈. maxWidth가 있으면 가로가 그보다 클 때만 줄임
    nonisolated static func prepareForUpload(_ data: Data, maxWidth: CGFloat?) -> (data: Data, mime: String, ext: String)? {
        if data.starts(with: [0x47, 0x49, 0x46]) { return (data, "image/gif", "gif") }
        let isJPEG = data.starts(with: [0xFF, 0xD8, 0xFF])
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        guard let image = UIImage(data: data) else { return nil }
        guard let maxWidth, image.size.width > maxWidth else {
            if isJPEG { return (data, "image/jpeg", "jpg") }
            if isPNG { return (data, "image/png", "png") }
            guard let jpg = image.jpegData(compressionQuality: 0.95) else { return nil }
            return (jpg, "image/jpeg", "jpg")
        }
        let size = CGSize(width: maxWidth, height: (image.size.height * maxWidth / image.size.width).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpg = resized.jpegData(compressionQuality: 0.92) else { return nil }
        return (jpg, "image/jpeg", "jpg")
    }
}

// MARK: - 자짤 설정 화면

struct AutoImageSettingsView: View {
    @ObservedObject private var store = AutoImageStore.shared
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var showGalleryPicker = false

    private func galleryName(_ gid: String) -> String {
        favorites.items.first { $0.galleryID == gid }?.name
            ?? VisitedStore.shared.items.first { $0.gallery.galleryID == gid }?.gallery.name
            ?? gid
    }

    private func summary(_ gid: String) -> String {
        let r = store.rule(for: gid)
        let own = store.settings.images.filter { $0.galleries.contains(gid) }.count
        return "\(r.mode.label) · 전용 자짤 \(own)장" + (own == 0 && r.useCommon ? " (공통 사용)" : "")
    }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        Form {
            Section {
                Toggle("자짤 사용", isOn: $store.settings.enabled)
                Picker("첨부 방식", selection: $store.settings.mode) {
                    ForEach(AutoImageMode.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("글쓰기 화면에서 아래쪽 '자짤 첨부' 버튼으로 언제든 다시 넣을 수 있어요. 자동 첨부는 같은 글쓰기 화면에서 10분 안에는 다시 넣지 않아요(새로고침 중복 방지).")
            }

            Section {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                    Label(isImporting ? "가져오는 중…" : "앨범에서 사진 추가", systemImage: "photo.badge.plus")
                }
                .disabled(isImporting)

                if store.settings.images.isEmpty {
                    Text("등록된 자짤이 없어요").foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(store.settings.images) { img in
                            NavigationLink {
                                AutoImageDetailView(image: img)
                            } label: {
                                AutoImageThumb(image: img)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("자짤 \(store.settings.images.count)장")
            } footer: {
                Text("여러 장이면 랜덤으로 1장을 골라요. 갤러리 전용으로 지정하지 않은 사진은 '공통 자짤'이에요. 움짤(GIF)은 그대로 저장돼요.")
            }

            // 갤러리별 설정
            Section {
                ForEach(store.configuredGalleries, id: \.self) { gid in
                    NavigationLink {
                        GalleryAutoImageView(galleryID: gid, name: galleryName(gid))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(galleryName(gid))
                            Text(summary(gid)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let list = store.configuredGalleries
                    for i in offsets { store.removeRule(for: list[i]) }
                }
                Button { showGalleryPicker = true } label: {
                    Label("갤러리 추가", systemImage: "plus.circle")
                }
            } header: {
                Text("갤러리별 설정")
            } footer: {
                Text("갤러리마다 자짤을 켜고 끄거나, 첨부 방식과 전용 자짤을 따로 정할 수 있어요. 목록에 없는 갤러리는 위의 기본 설정을 따라요. 글쓰기 화면의 '자짤' 버튼을 길게 눌러도 바로 설정할 수 있어요.")
            }
        }
        .navigationTitle("자짤")
        .sheet(isPresented: $showGalleryPicker) {
            GalleryIDPicker { gid in
                if store.settings.rules?[gid] == nil { store.setRule(GalleryAutoRule(), for: gid) }
            }
            .environmentObject(favorites)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            isImporting = true
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        store.add(data: data)
                    }
                }
                pickerItems = []
                isImporting = false
            }
        }
    }
}

struct AutoImageThumb: View {
    let image: AutoImage
    var body: some View {
        let store = AutoImageStore.shared
        ZStack(alignment: .bottomLeading) {
            if let ui = UIImage(contentsOfFile: store.fileURL(image).path) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.2)
            }
            HStack(spacing: 4) {
                if image.ext == "gif" { tag("GIF") }
                if !image.galleries.isEmpty { tag("전용 \(image.galleries.count)") }
            }
            .padding(4)
        }
        .frame(minWidth: 96, minHeight: 96)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(.caption2.bold()).foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
    }
}

/// 자짤 한 장: 미리보기, 적용할 갤러리 지정, 삭제
struct AutoImageDetailView: View {
    let image: AutoImage
    @ObservedObject private var store = AutoImageStore.shared
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss
    @State private var newID = ""

    private var current: AutoImage {
        store.settings.images.first { $0.id == image.id } ?? image
    }

    var body: some View {
        Form {
            Section {
                if let ui = UIImage(contentsOfFile: store.fileURL(image).path) {
                    Image(uiImage: ui).resizable().scaledToFit()
                        .frame(maxHeight: 260)
                        .frame(maxWidth: .infinity)
                }
            }

            Section {
                Toggle("모든 갤러리 공통", isOn: Binding(
                    get: { current.galleries.isEmpty },
                    set: { if $0 { store.setGalleries([], for: image) } }
                ))
                ForEach(favorites.items) { g in
                    Button {
                        toggle(g.galleryID)
                    } label: {
                        HStack {
                            Text(g.name).foregroundStyle(.primary)
                            Spacer()
                            if current.galleries.contains(g.galleryID) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
                HStack {
                    TextField("갤러리 ID 직접 입력", text: $newID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("추가") {
                        let id = newID.trimmingCharacters(in: .whitespaces)
                        if !id.isEmpty && !current.galleries.contains(id) {
                            store.setGalleries(current.galleries + [id], for: image)
                        }
                        newID = ""
                    }
                }
                let extra = current.galleries.filter { id in !favorites.items.contains { $0.galleryID == id } }
                ForEach(extra, id: \.self) { id in
                    HStack {
                        Text(id)
                        Spacer()
                        Button(role: .destructive) { toggle(id) } label: { Image(systemName: "minus.circle") }
                    }
                }
            } header: {
                Text("적용할 갤러리")
            } footer: {
                Text("갤러리를 고르면 그 갤러리에서만 이 자짤을 써요. 아무것도 안 고르면 전용 자짤이 없는 모든 갤러리에서 써요.")
            }

            Section {
                Button("이 자짤 삭제", role: .destructive) {
                    store.remove(image)
                    dismiss()
                }
            }
        }
        .navigationTitle("자짤 설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ id: String) {
        var list = current.galleries
        if let i = list.firstIndex(of: id) { list.remove(at: i) } else { list.append(id) }
        store.setGalleries(list, for: image)
    }
}


// MARK: - 갤러리 하나의 자짤 설정

struct GalleryAutoImageView: View {
    let galleryID: String
    let name: String
    @ObservedObject private var store = AutoImageStore.shared
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    private var rule: Binding<GalleryAutoRule> {
        Binding(get: { store.rule(for: galleryID) },
                set: { store.setRule($0, for: galleryID) })
    }

    var body: some View {
        Form {
            Section {
                Picker("사용", selection: rule.mode) {
                    ForEach(GalleryAutoMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("전용 자짤이 없으면 공통 자짤 쓰기", isOn: rule.useCommon)
            } header: {
                Text(name)
            } footer: {
                Text("기본 설정: \(store.settings.enabled ? store.settings.mode.label : "꺼짐")")
            }

            Section {
                if store.settings.images.isEmpty {
                    Text("먼저 자짤 화면에서 사진을 추가해주세요").foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(store.settings.images) { img in
                            let on = img.galleries.contains(galleryID)
                            Button { store.toggle(img, in: galleryID) } label: {
                                AutoImageThumb(image: img)
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(on ? Color.accentColor : Color.white)
                                            .shadow(radius: 2)
                                            .padding(4)
                                    }
                                    .opacity(on ? 1 : 0.55)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("이 갤러리 전용 자짤")
            } footer: {
                Text("체크한 사진만 이 갤러리에서 써요(여러 장이면 랜덤). 하나도 체크하지 않으면 위 설정에 따라 공통 자짤을 써요.")
            }
        }
        .navigationTitle("갤러리별 자짤")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 갤러리 고르기 (즐겨찾기 / 방문한 갤러리 / 직접 입력)
struct GalleryIDPicker: View {
    let onPick: (String) -> Void
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var visited = VisitedStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            List {
                Section("직접 입력") {
                    HStack {
                        TextField("갤러리 ID", text: $typed)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("추가") { pick(typed) }
                            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if !favorites.items.isEmpty {
                    Section("즐겨찾는 갤러리") {
                        ForEach(favorites.items) { g in
                            Button(g.name) { pick(g.galleryID) }
                        }
                    }
                }
                if !visited.items.isEmpty {
                    Section("방문한 갤러리") {
                        ForEach(visited.items) { v in
                            Button(v.gallery.name) { pick(v.gallery.galleryID) }
                        }
                    }
                }
            }
            .navigationTitle("갤러리 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
    }

    private func pick(_ id: String) {
        let v = id.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        onPick(v)
        dismiss()
    }
}
