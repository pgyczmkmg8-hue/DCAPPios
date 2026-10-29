import SwiftUI
import Photos

/// 사진 저장 앨범 (설정 → 세부 설정 → 사진 저장)
enum PhotoSaver {
    /// 기본으로 저장할 앨범 (PHAssetCollection localIdentifier, 빈 값 = 앨범 지정 안 함 → 최근 항목에만)
    static let albumKey = "photoSaveAlbumID"
    /// 저장할 때마다 어느 앨범에 넣을지 물어보기
    static let askKey = "photoSaveAskAlbum"

    static var defaultAlbumID: String? {
        let v = UserDefaults.standard.string(forKey: albumKey) ?? ""
        return v.isEmpty ? nil : v
    }
    static var askEveryTime: Bool { UserDefaults.standard.bool(forKey: askKey) }

    /// 앨범 목록을 보려면 사진 '읽기' 권한까지 필요 (저장만 할 땐 추가 전용 권한으로 충분)
    static func requestFullAccess() async -> Bool {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return s == .authorized || s == .limited
    }

    static func albums() -> [PHAssetCollection] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]
        let r = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: opts)
        var list: [PHAssetCollection] = []
        r.enumerateObjects { c, _, _ in if c.canPerform(.addContent) { list.append(c) } }
        return list
    }

    static func album(id: String?) -> PHAssetCollection? {
        guard let id, !id.isEmpty else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    static func albumName(id: String?) -> String {
        guard let id, !id.isEmpty else { return "앨범 지정 안 함" }
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined { return "지정한 앨범" }
        return album(id: id)?.localizedTitle ?? "찾을 수 없는 앨범"
    }

    /// 새 앨범 만들기 → localIdentifier
    static func createAlbum(_ name: String) async -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, await requestFullAccess() else { return nil }
        let box = IDBox()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                box.id = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: n)
                    .placeholderForCreatedAssetCollection.localIdentifier
            }
        } catch { return nil }
        return box.id
    }

    /// performChanges 안(다른 스레드)에서 만든 앨범 아이디를 받아 오는 상자
    nonisolated final class IDBox: @unchecked Sendable { var id: String? }

    enum SaveError: Error { case denied, failed }

    /// 원본 파일 그대로 저장. albumID가 있으면 그 앨범에도 넣음 → 저장한 앨범 이름 (없으면 nil)
    @discardableResult
    static func save(_ data: Data, albumID: String?) async throws -> String? {
        var target: PHAssetCollection?
        if let albumID, !albumID.isEmpty {
            guard await requestFullAccess() else { throw SaveError.denied }
            target = album(id: albumID)
        } else {
            let s = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard s == .authorized || s == .limited else { throw SaveError.denied }
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
                if let target, let p = req.placeholderForCreatedAsset,
                   let change = PHAssetCollectionChangeRequest(for: target) {
                    change.addAssets([p] as NSArray)
                }
            }
        } catch { throw SaveError.failed }
        return target?.localizedTitle
    }
}

/// 앨범 고르기 (설정에서 기본 앨범 정하기 / 저장할 때 물어보기 둘 다)
struct PhotoAlbumPicker: View {
    let title: String
    /// 지금 골라져 있는 앨범 (체크 표시)
    let selectedID: String?
    let onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [PHAssetCollection] = []
    @State private var denied = false
    @State private var loaded = false
    @State private var showNew = false
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                row(name: "앨범 지정 안 함", detail: "최근 항목에만", id: nil)
            }
            Section("내 앨범") {
                if denied {
                    Text("앨범 목록을 보려면 설정 앱 → DCAPP → 사진에서 '전체 접근'(또는 '제한된 접근')을 허용해주세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if loaded && albums.isEmpty {
                    Text("앨범이 없어요").foregroundStyle(.secondary)
                }
                ForEach(albums, id: \.localIdentifier) { a in
                    row(name: a.localizedTitle ?? "이름 없음", detail: nil, id: a.localIdentifier)
                }
                Button {
                    newName = ""
                    showNew = true
                } label: {
                    Label("새 앨범 만들기", systemImage: "plus")
                }
                .disabled(denied)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if await PhotoSaver.requestFullAccess() {
                albums = PhotoSaver.albums()
            } else {
                denied = true
            }
            loaded = true
        }
        .alert("새 앨범", isPresented: $showNew) {
            TextField("앨범 이름", text: $newName)
            Button("취소", role: .cancel) {}
            Button("만들기") {
                Task {
                    if let id = await PhotoSaver.createAlbum(newName) {
                        albums = PhotoSaver.albums()
                        pick(id)
                    }
                }
            }
        }
    }

    private func row(name: String, detail: String?, id: String?) -> some View {
        Button { pick(id) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if (selectedID ?? "") == (id ?? "") {
                    Image(systemName: "checkmark").foregroundStyle(DCTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func pick(_ id: String?) {
        onPick(id)
        dismiss()
    }
}

/// 설정 → 세부 설정 → 사진 저장
struct PhotoSaveSettingsSection: View {
    @AppStorage(PhotoSaver.albumKey) private var albumID = ""
    @AppStorage(PhotoSaver.askKey) private var ask = false

    var body: some View {
        Section {
            NavigationLink {
                PhotoAlbumPicker(title: "기본 저장 앨범", selectedID: albumID.isEmpty ? nil : albumID) { id in
                    albumID = id ?? ""
                }
            } label: {
                LabeledContent("기본 저장 앨범", value: PhotoSaver.albumName(id: albumID))
            }
            Toggle("저장할 때마다 앨범 물어보기", isOn: $ask)
        } header: {
            Text("사진 저장")
        } footer: {
            Text("사진 보기에서 저장(↓)을 누르면 기본 저장 앨범에 넣어요. '앨범 지정 안 함'이면 최근 항목에만 들어가요. 물어보기를 켜면 저장할 때마다 앨범을 골라요.")
        }
    }
}
