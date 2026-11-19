import SwiftUI
import ImageIO
import Photos

/// 글 속 사진 보기 요청 (페이지에서 사진을 탭하면 만들어짐)
struct ImageViewerItem: Identifiable {
    let id = UUID()
    /// 보여 줄 사진 (차단해서 가린 사진은 뺌)
    let urls: [URL]
    let index: Int
    /// 사진이 있는 글 주소 (원본 다운로드 주소를 PC 글에서 찾는 데 씀)
    var pageURL: URL? = nil
    /// 사진마다 차단 키 (페이지가 만든 키 — 사진 차단 버튼이 이 키로 차단 목록에 넣음)
    var keys: [String]? = nil
    /// 보여 줄 사진마다: 글 속 전체 사진에서의 순서 (-1이면 모름 → 원본 매칭 안 함)
    var slots: [Int]? = nil
    /// 글 속 전체 사진 수 (가린 사진 포함) — PC 원본 첨부 목록과 개수를 맞출 때 씀
    var allCount: Int = 0
    /// 글 속 전체 사진의 파일 번호 (가린 사진 포함, 같은 순서) — 원본 첨부 목록 순서를 구할 때 씀
    var allFilenos: [Int]? = nil

    /// 보여 줄 i번째 사진의 글 속 전체 순서 (모르면 nil)
    func globalIndex(_ i: Int) -> Int? {
        guard let slots, i < slots.count, slots[i] >= 0 else { return nil }
        return slots[i]
    }
}

/// 사진 보기에서 앨범 시트를 연 목적 (한 장 저장 / 전체 저장)
private enum AlbumAction { case one, all }

/// 글 속 사진 전체 화면 보기: 핀치·더블탭 확대 / 좌우로 넘기기 / 위아래로 쓸어서 닫기 / 저장
struct ImageViewer: View {
    let item: ImageViewerItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var filters = FilterStore.shared

    @State private var index: Int
    @State private var images: [Int: UIImage] = [:]
    @State private var datas: [Int: Data] = [:]
    @State private var failed: Set<Int> = []
    @State private var originals: Set<Int> = []        // 원본으로 바뀐 사진
    @State private var linksTask: Task<[URL]?, Never>? // PC 글의 원본 첨부파일 주소 (사진 순서) — 한 번만 구함
    @State private var bulkSaving = false              // 전체 저장 중 (중복 실행 막기)
    @State private var albumAction: AlbumAction = .one // 앨범 시트를 연 목적

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var axis: Axis?
    @State private var dismissDrag: CGFloat = 0
    @State private var pageDrag: CGFloat = 0
    @State private var showChrome = true
    @State private var message: String?
    @State private var askAlbum = false

    init(item: ImageViewerItem) {
        self.item = item
        _index = State(initialValue: min(max(0, item.index), max(0, item.urls.count - 1)))
    }

    /// 창의 좌우 안전 영역 (뷰에서 안전 영역을 무시하면 GeometryReader가 0으로 읽으므로 창에서 직접 읽음)
    private static func windowInset(_ side: KeyPath<UIEdgeInsets, CGFloat>) -> CGFloat {
        let ws = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { $0.windowLevel == .normal && !$0.isHidden }
        return ws.map { $0.safeAreaInsets[keyPath: side] }.max() ?? 0
    }
    private var count: Int { item.urls.count }
    /// 지금 보고 있는 사진의 차단 키 (없으면 차단 버튼을 못 씀)
    private var currentKey: String? { key(at: index) }

    private func key(at i: Int) -> String? {
        guard let keys = item.keys, i < keys.count, !keys[i].isEmpty else { return nil }
        return keys[i]
    }
    private var zoomed: Bool { scale > 1.01 }
    /// 아래로 끌수록 배경이 투명해져서 뒤의 글이 보임
    private var backgroundOpacity: Double { 1 - min(Double(abs(dismissDrag)) / 500, 0.8) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(backgroundOpacity).ignoresSafeArea()

                ForEach([index - 1, index, index + 1].filter { $0 >= 0 && $0 < count }, id: \.self) { i in
                    pageView(i)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(i == index ? scale : 1)
                        .offset(x: CGFloat(i - index) * (geo.size.width + 16) + pageDrag + (i == index ? offset.width : 0),
                                y: i == index ? offset.height + dismissDrag : 0)
                }

                // 사진은 위·아래 끝까지 채우고, 버튼만 안전 영역 안에 (듀오는 옆 세로 줄 안에)
                chromeLayer(geo.size)
                    .opacity(showChrome && dismissDrag == 0 ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: showChrome)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(geo.size))
            .simultaneousGesture(magnifyGesture)
            .onTapGesture(count: 2) { toggleZoom() }
            .onTapGesture { showChrome.toggle() }
        }
        // 사진은 안전 영역(듀오 옆 세로 줄) 밖까지 한 장씩 꽉 채움 — 안 그러면 줄 자리에 다음 사진 일부가 보임
        .ignoresSafeArea(.container)
        .statusBarHidden(!showChrome)
        .sheet(isPresented: $askAlbum) {
            NavigationStack {
                PhotoAlbumPicker(title: "어디에 저장할까요?", selectedID: PhotoSaver.defaultAlbumID) { id in
                    switch albumAction {
                    case .one: Task { await save(albumID: id) }
                    case .all: Task { await saveAll(albumID: id) }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { askAlbum = false } }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .task(id: index) {
            for i in [index, index + 1, index - 1] where i >= 0 && i < count { await load(i) }
        }
    }

    // MARK: - 화면 조각

    @ViewBuilder
    private func pageView(_ i: Int) -> some View {
        if let img = images[i] {
            AnimatedImageView(image: img)
        } else if failed.contains(i) {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                Text("사진을 불러오지 못했어요").font(.subheadline)
            }
            .foregroundStyle(.white.opacity(0.7))
        } else {
            ProgressView().tint(.white)
        }
    }

    /// 조작 줄 전체. 일반 화면은 위쪽 가로 줄, 듀오(옆에 세로 안전 영역이 있을 때)는 그 세로 줄 아래쪽에 세로로 모음
    /// 화면을 돌리면 이 함수가 다시 그려지면서 안전 영역을 새로 읽음
    @ViewBuilder
    private func chromeLayer(_ size: CGSize) -> some View {
        let left = Self.windowInset(\.left), right = Self.windowInset(\.right)
        ZStack {
            if BrowserView.hasSideColumnOnly {
                duoChrome(column: max(left, right), onLeft: BrowserView.windowLeftColumn,
                          bottom: Self.windowInset(\.bottom))
            } else {
                topChrome(left: left, right: right, top: Self.windowInset(\.top))
            }
            if let message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 40)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// 일반 화면: 위쪽 한 줄 — 닫기(왼쪽), 페이지 번호(가운데), 차단·저장(오른쪽). 안전 영역 안쪽으로 여유 있게
    private func topChrome(left: CGFloat, right: CGFloat, top: CGFloat) -> some View {
        HStack(spacing: 0) {
            closeButton
            Spacer(minLength: 8)
            if count > 1 { pageCapsule() }      // 두 캡슐 사이 빈 공간의 가운데 (정중앙에 고정하면 오른쪽 캡슐과 겹칠 수 있음)
            Spacer(minLength: 8)
            actionCapsule(vertical: false)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)           // 유리 색을 어두운 쪽으로 (밝은 사진 위에서도 흰 글자가 묻히지 않게)
        .padding(.leading, left + 14)
        .padding(.trailing, right + 14)
        .padding(.top, top + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 듀오: 옆 세로 안전 영역 안에 세로로 모음 — 위쪽은 시계·카메라 자리라 비우고, 아래쪽에 맞춰 줄 가운데에 둠
    private func duoChrome(column: CGFloat, onLeft: Bool, bottom: CGFloat) -> some View {
        VStack(spacing: 10) {
            if count > 1 { pageCapsule(inColumn: column) }
            actionCapsule(vertical: true)
            closeButton
        }
        .frame(width: column)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.bottom, max(bottom, 16) + 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: onLeft ? .bottomLeading : .bottomTrailing)
    }

    /// 닫기 (52pt 원형 유리)
    private var closeButton: some View {
        Button { close(direction: 1, height: 0) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .contentShape(Capsule())
                .modifier(ViewerGlassCapsule())
        }
    }

    /// 페이지 번호 캡슐 (사진이 2장 이상일 때). inColumn: 듀오 세로 줄 폭 — 그 안에서 한 줄로 줄어들게
    private func pageCapsule(inColumn column: CGFloat? = nil) -> some View {
        let label = Text("\(index + 1) / \(count)")
            .font(.callout.monospacedDigit().weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        return Group {
            if let column {
                label
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: max(column - 6, 52))
            } else {
                label
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .modifier(ViewerGlassCapsule())
    }

    /// 차단·이 사진 저장·전체 저장 (52pt 버튼 3개)
    @ViewBuilder
    private var actionItems: some View {
        Button { toggleBlock() } label: {
            Image(systemName: currentBlocked ? "hand.raised.slash.fill" : "hand.raised")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .disabled(currentKey == nil)
        Button { startSaveOne() } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .disabled(datas[index] == nil)
        if count > 1 {
            Button { startSaveAll() } label: {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .disabled(bulkSaving)
        }
    }

    /// 조작 버튼을 하나의 유리 캡슐 안에 (가로 줄 또는 듀오의 세로 줄)
    @ViewBuilder
    private func actionCapsule(vertical: Bool) -> some View {
        if vertical {
            VStack(spacing: 4) { actionItems }
                .padding(.vertical, 4)
                .modifier(ViewerGlassCapsule())
        } else {
            HStack(spacing: 0) { actionItems }
                .modifier(ViewerGlassCapsule())
        }
    }

    /// 지금 사진이 차단 목록에 있는지
    private var currentBlocked: Bool { currentKey.map { filters.isImageBlocked(key: $0) } ?? false }

    /// 지금 사진을 차단하거나 차단을 품 (차단하면 글 속에서 이 사진이 가려짐)
    private func toggleBlock() {
        guard let key = currentKey else { return }
        if filters.isImageBlocked(key: key) {
            filters.removeImage(key: key)
            flash("이미지 차단을 풀었어요")
            return
        }
        let url = item.urls[index]
        let data = datas[index]
        filters.addImage(key: key, src: url.absoluteString, hash: data.flatMap { ImageBlockHash.hash(data: $0) })
        if data == nil {
            // 아직 안 받은 사진이면 받은 뒤 생김새 해시를 채움
            Task {
                if let h = await ImageBlockHash.fetch(url.absoluteString) { filters.setImageHash(key: key, hash: h) }
            }
        }
        flash("이 이미지를 차단했어요")
    }

    // MARK: - 제스처

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                if zoomed {   // 확대 중: 사진 움직이기
                    offset = CGSize(width: baseOffset.width + v.translation.width,
                                    height: baseOffset.height + v.translation.height)
                    return
                }
                if axis == nil {
                    axis = abs(v.translation.height) > abs(v.translation.width) ? .vertical : .horizontal
                }
                if axis == .vertical {
                    dismissDrag = v.translation.height
                } else {
                    let atEdge = (v.translation.width > 0 && index == 0) || (v.translation.width < 0 && index == count - 1)
                    pageDrag = atEdge ? v.translation.width / 3 : v.translation.width
                }
            }
            .onEnded { v in
                defer { axis = nil }
                if zoomed { baseOffset = offset; return }
                if axis == .vertical {
                    let dy = v.translation.height, pdy = v.predictedEndTranslation.height
                    if abs(dy) > 110 || abs(pdy) > 450 {
                        close(direction: (pdy == 0 ? dy : pdy) >= 0 ? 1 : -1, height: size.height)
                    } else {
                        withAnimation(.spring(duration: 0.3)) { dismissDrag = 0 }
                    }
                } else if axis == .horizontal {
                    let dx = v.translation.width, pdx = v.predictedEndTranslation.width
                    withAnimation(.spring(duration: 0.3)) {
                        if (dx < -80 || pdx < -size.width / 2), index < count - 1 { index += 1 }
                        else if (dx > 80 || pdx > size.width / 2), index > 0 { index -= 1 }
                        pageDrag = 0
                    }
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()      // iOS 16에서도 되는 확대 제스처
            .onChanged { v in scale = min(5, max(1, baseScale * v)) }
            .onEnded { _ in
                baseScale = scale
                if !zoomed { resetZoom(animated: true) }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(duration: 0.3)) {
            if zoomed { scale = 1; offset = .zero } else { scale = 2.5 }
        }
        baseScale = scale
        baseOffset = offset
    }

    private func resetZoom(animated: Bool) {
        let apply = { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }
        if animated { withAnimation(.spring(duration: 0.3), apply) } else { apply() }
    }

    /// 끈 방향으로 사진을 날려 보내고 닫기
    private func close(direction: CGFloat, height: CGFloat) {
        guard height > 0 else { dismiss(); return }
        withAnimation(.easeOut(duration: 0.18)) { dismissDrag = direction * height }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { dismiss() }
        }
    }

    // MARK: - 불러오기 / 저장

    private func load(_ i: Int) async {
        guard images[i] == nil, !failed.contains(i) else { return }
        // 줄어든 사진을 먼저 보여주고, 원본이 받아지면 바로 바꿔 끼움
        if let r = await Self.fetch(item.urls[i]) {
            datas[i] = r.data
            images[i] = r.image
            // 이 사진의 생김새를 기록 → 같은 사진이 다른 이름으로 다시 올라온 것도 차단 상태를 알 수 있게
            if let key = key(at: i), let h = ImageBlockHash.hash(data: r.data) { filters.recordImageHash(key: key, hash: h) }
        } else {
            failed.insert(i)
        }
        await upgrade(i)
    }

    private func upgrade(_ i: Int) async {
        guard !originals.contains(i), let g = item.globalIndex(i) else { return }
        guard let links = await ensureLinks() else { return }
        let slot = PostPhotoOriginals.linkSlot(g, filenos: item.allFilenos)
        guard slot < links.count,
              let data = await PostPhotoOriginals.download(links[slot]),
              let img = Self.decode(data) else { return }
        datas[i] = data
        images[i] = img
        failed.remove(i)
        originals.insert(i)
    }

    /// 이 글의 PC 원본 링크 목록 — 한 번만 구하고, 진행 중이면 같은 작업을 기다림
    private func ensureLinks() async -> [URL]? {
        if linksTask == nil {
            let page = item.pageURL, n = item.allCount
            linksTask = Task { await PostPhotoOriginals.links(page: page, count: n) }
        }
        return await linksTask?.value
    }

    /// 저장할 원본 데이터 한 장 (이미 원본으로 받아 둔 사진은 그대로, 아니면 PC 원본 → 모바일 사진)
    private func originalData(_ i: Int, links: [URL]?) async -> Data? {
        if originals.contains(i), let d = datas[i] { return d }
        return await PostPhotoOriginals.original(links: links, index: item.globalIndex(i) ?? -1,
                                                 filenos: item.allFilenos, mobile: item.urls[i])
    }

    /// 디시 사진 서버는 Referer가 없으면 막으므로 붙여서 요청
    nonisolated private static func fetch(_ url: URL) async -> (data: Data, image: UIImage)? {
        var req = URLRequest(url: url)
        req.setValue("https://m.dcinside.com/", forHTTPHeaderField: "Referer")
        guard let res = try? await URLSession.shared.data(for: req),
              let img = decode(res.0) else { return nil }
        return (res.0, img)
    }

    /// 움짤(GIF)은 프레임을 모아 움직이는 이미지로
    nonisolated static func decode(_ data: Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let n = CGImageSourceGetCount(src)
        if n <= 1 { return UIImage(data: data) }
        var frames: [UIImage] = []
        var total = 0.0
        for i in 0..<min(n, 400) {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            total += d < 0.02 ? 0.1 : d
        }
        return frames.isEmpty ? UIImage(data: data) : UIImage.animatedImage(with: frames, duration: total)
    }

    /// 원본 파일 그대로 사진 앱에 저장 (움짤도 움직이는 채로)
    /// albumID가 있으면 그 앨범에도 넣음 (설정 → 세부 설정 → 사진 저장)
    private func save(albumID: String?) async {
        guard let shown = datas[index] else { return }
        // 모바일 웹의 사진은 원본이 아닐 수 있어서, PC 글 아래 '원본파일 다운로드'와 같은 주소로 받아서 저장
        if !originals.contains(index) { await upgrade(index) }
        let data = datas[index] ?? shown
        do {
            let album = try await PhotoSaver.save(data, albumID: albumID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash(album.map { "'\($0)' 앨범에 저장했어요" } ?? "사진 앱에 저장했어요")
        } catch PhotoSaver.SaveError.denied {
            flash("설정에서 사진 접근을 허용해주세요")
        } catch {
            flash("저장하지 못했어요")
        }
    }

    /// 한 장 저장: 앨범을 물어보는 설정이면 시트부터
    private func startSaveOne() {
        if PhotoSaver.askEveryTime {
            albumAction = .one
            askAlbum = true
        } else {
            Task { await save(albumID: PhotoSaver.defaultAlbumID) }
        }
    }

    /// 전체 저장: 앨범을 물어보는 설정이면 시트를 한 번만 띄워 고른 앨범에 모두 넣음
    private func startSaveAll() {
        guard !bulkSaving else { return }
        if PhotoSaver.askEveryTime {
            albumAction = .all
            askAlbum = true
        } else {
            Task { await saveAll(albumID: PhotoSaver.defaultAlbumID) }
        }
    }

    /// 글 속 사진 전부를 원본으로 순서대로 저장 (가려진 사진은 목록에 없어서 빠짐)
    private func saveAll(albumID: String?) async {
        guard !bulkSaving else { return }
        bulkSaving = true
        defer { bulkSaving = false }
        let total = count
        let links = await ensureLinks()
        var saved = 0, missed = 0
        var albumName: String?
        for i in 0..<total {
            message = "전체 저장 중 (\(i + 1)/\(total))…"
            guard let data = await originalData(i, links: links) else { missed += 1; continue }
            do {
                albumName = try await PhotoSaver.save(data, albumID: albumID)
                saved += 1
            } catch PhotoSaver.SaveError.denied {
                flash("설정에서 사진 접근을 허용해주세요")
                return
            } catch {
                missed += 1
            }
        }
        guard saved > 0 else {
            flash("사진을 저장하지 못했어요")
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if missed == 0 {
            flash(albumName.map { "'\($0)' 앨범에 \(saved)장 저장했어요" } ?? "사진 \(saved)장을 모두 저장했어요")
        } else {
            flash((albumName.map { "'\($0)' 앨범에 \(saved)장 저장, " } ?? "사진 \(saved)장 저장, ") + "\(missed)장은 가져오지 못했어요")
        }
    }

    private func flash(_ text: String) {
        message = text
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if message == text { message = nil }
        }
    }
}

/// 사진 보기 상단 조각의 유리 캡슐: iOS 26 이상은 어두운 틴트의 리퀴드 글래스, 그 아래는 어두운 막 + 얇은 재질
/// (밝은 사진이 뒤에 와도 흰 아이콘이 묻히지 않도록 뒤를 어둡게 깔아 둠)
private struct ViewerGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.black.opacity(0.35)).interactive(), in: Capsule())
        } else {
            content
                .background(Capsule().fill(.black.opacity(0.45)))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
        }
    }
}

/// 움짤도 움직이게 보여주는 이미지 뷰 (SwiftUI Image는 GIF를 첫 장만 보여줌)
struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = false
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        if v.image !== image { v.image = image }
    }
}
