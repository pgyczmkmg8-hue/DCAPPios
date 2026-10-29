import SwiftUI
import Photos
import PhotosUI
import Combine

// MARK: - 앱 글쓰기 사진 고르기 (앱 전용)
// iOS 기본 사진 선택기는 쓸고 지나가면 여러 장이 한꺼번에 선택돼서 불편 → 한 장씩 눌러서만 고르는 격자 화면
// 고른 순서대로 번호가 붙고, 그 순서대로 글에 들어감

/// 앨범 하나 (최근 항목 / 즐겨찾는 항목 / 스크린샷 / 내가 만든 앨범)
struct PhotoAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let collection: PHAssetCollection?
}

@MainActor
final class PhotoGridModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var assets: PHFetchResult<PHAsset> = PHFetchResult()
    @Published var albums: [PhotoAlbum] = []
    @Published var album: PhotoAlbum?
    let cache = PHCachingImageManager()

    var canRead: Bool { status == .authorized || status == .limited }

    func start() async {
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard canRead else { return }
        PHPhotoLibrary.shared().register(self)
        loadAlbums()
        reload()
    }

    func stop() {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        cache.stopCachingImagesForAllAssets()
    }

    private static var imageOptions: PHFetchOptions {
        let o = PHFetchOptions()
        o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return o
    }

    private func loadAlbums() {
        var list = [PhotoAlbum(id: "all", title: "최근 항목", collection: nil)]
        for sub in [PHAssetCollectionSubtype.smartAlbumFavorites, .smartAlbumScreenshots, .smartAlbumSelfPortraits] {
            if let c = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: sub, options: nil).firstObject,
               PHAsset.fetchAssets(in: c, options: Self.imageOptions).count > 0 {
                list.append(PhotoAlbum(id: c.localIdentifier, title: c.localizedTitle ?? "앨범", collection: c))
            }
        }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { c, _, _ in
            if PHAsset.fetchAssets(in: c, options: Self.imageOptions).count > 0 {
                list.append(PhotoAlbum(id: c.localIdentifier, title: c.localizedTitle ?? "앨범", collection: c))
            }
        }
        albums = list
        if album == nil || !list.contains(where: { $0.id == album?.id }) { album = list.first }
    }

    func reload() {
        if let c = album?.collection {
            assets = PHAsset.fetchAssets(in: c, options: Self.imageOptions)
        } else {
            assets = PHAsset.fetchAssets(with: Self.imageOptions)
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            self.loadAlbums()
            self.reload()
        }
    }
}

struct PhotoGridPicker: View {
    let maxCount: Int
    /// 고른 사진 (고른 순서대로)
    let onPick: ([PHAsset]) -> Void
    /// 사진 접근이 막혀 있을 때 iOS 기본 선택기로
    let onUseSystemPicker: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PhotoGridModel()
    @State private var selected: [String] = []        // localIdentifier, 고른 순서
    @State private var picked: [String: PHAsset] = [:]
    @State private var limitNotice = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { dismiss() }
                    }
                    ToolbarItem(placement: .principal) { albumMenu }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(selected.isEmpty ? "추가" : "추가 (\(selected.count))") {
                            let list = selected.compactMap { picked[$0] }
                            dismiss()
                            onPick(list)
                        }
                        .fontWeight(.semibold)
                        .disabled(selected.isEmpty)
                    }
                }
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.album) { _, _ in model.reload() }
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .authorized, .limited:
            VStack(spacing: 0) {
                if model.status == .limited { limitedBar }
                grid
                if limitNotice {
                    Text("사진은 \(maxCount)장까지 고를 수 있어요")
                        .font(.footnote)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        case .notDetermined:
            ProgressView()
        default:
            ContentUnavailableView {
                Label("사진에 접근할 수 없어요", systemImage: "photo.on.rectangle")
            } description: {
                Text("설정에서 사진 접근을 허용하거나, iOS 기본 선택기로 골라 주세요.")
            } actions: {
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("기본 선택기로 고르기") {
                    dismiss()
                    onUseSystemPicker()
                }
            }
        }
    }

    private var albumMenu: some View {
        Menu {
            Picker("앨범", selection: $model.album) {
                ForEach(model.albums) { Text($0.title).tag(Optional($0)) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.album?.title ?? "사진").font(.headline)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
        }
        .disabled(model.albums.count < 2)
    }

    private var limitedBar: some View {
        HStack {
            Text("고른 사진만 보여요")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("사진 더 보이게") {
                if let vc = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first {
                    var top = vc
                    while let p = top.presentedViewController { top = p }
                    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<model.assets.count, id: \.self) { i in
                    let asset = model.assets.object(at: i)
                    PhotoGridCell(asset: asset, manager: model.cache,
                                  order: selected.firstIndex(of: asset.localIdentifier).map { $0 + 1 })
                        .onTapGesture { toggle(asset) }
                }
            }
        }
        .overlay {
            if model.assets.count == 0 {
                ContentUnavailableView("사진이 없어요", systemImage: "photo")
            }
        }
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if let i = selected.firstIndex(of: id) {
            selected.remove(at: i)
            picked[id] = nil
        } else {
            guard selected.count < maxCount else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                withAnimation { limitNotice = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { limitNotice = false }
                }
                return
            }
            selected.append(id)
            picked[id] = asset
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// 고른 사진의 원본 파일 (iCloud에만 있으면 받아 옴)
    nonisolated static func loadData(_ asset: PHAsset) async -> Data? {
        await withCheckedContinuation { c in
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.version = .current
            o.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: o) { data, _, _, _ in
                c.resume(returning: data)
            }
        }
    }
}

private struct PhotoGridCell: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let order: Int?
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Color(uiColor: .secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay {
                if order != nil { Color.black.opacity(0.25) }
            }
            .overlay(alignment: .topTrailing) { badge.padding(5) }
            .overlay(alignment: .bottomLeading) {
                if asset.playbackStyle == .imageAnimated {
                    Text("GIF")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            .onAppear(perform: request)
            .onDisappear {
                if let requestID { manager.cancelImageRequest(requestID) }
                requestID = nil
            }
    }

    @ViewBuilder private var badge: some View {
        if let order {
            Text("\(order)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(DCTheme.accent, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
        } else {
            Circle()
                .stroke(.white, lineWidth: 1.5)
                .background(Circle().fill(.black.opacity(0.15)))
                .frame(width: 24, height: 24)
                .shadow(radius: 1)
        }
    }

    private func request() {
        guard image == nil, requestID == nil else { return }
        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic
        o.isNetworkAccessAllowed = true
        o.resizeMode = .fast
        let side = UIScreen.main.scale * 120
        requestID = manager.requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                         contentMode: .aspectFill, options: o) { img, _ in
            if let img { image = img }
        }
    }
}
