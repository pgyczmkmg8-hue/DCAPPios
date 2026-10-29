import SwiftUI
import ImageIO
import Photos

/// 글 속 사진 보기 요청 (페이지에서 사진을 탭하면 만들어짐)
struct ImageViewerItem: Identifiable {
    let id = UUID()
    let urls: [URL]
    let index: Int
    /// 사진이 있는 글 주소 (원본 다운로드 주소를 PC 글에서 찾는 데 씀)
    var pageURL: URL? = nil
}

/// 글 속 사진 전체 화면 보기: 핀치·더블탭 확대 / 좌우로 넘기기 / 위아래로 쓸어서 닫기 / 저장
struct ImageViewer: View {
    let item: ImageViewerItem
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    @State private var images: [Int: UIImage] = [:]
    @State private var datas: [Int: Data] = [:]
    @State private var failed: Set<Int> = []

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

    private var count: Int { item.urls.count }
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

                chrome
                    .opacity(showChrome && dismissDrag == 0 ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: showChrome)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(geo.size))
            .simultaneousGesture(magnifyGesture)
            .onTapGesture(count: 2) { toggleZoom() }
            .onTapGesture { showChrome.toggle() }
        }
        .statusBarHidden(!showChrome)
        .sheet(isPresented: $askAlbum) {
            NavigationStack {
                PhotoAlbumPicker(title: "어디에 저장할까요?", selectedID: PhotoSaver.defaultAlbumID) { id in
                    Task { await save(albumID: id) }
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

    private var chrome: some View {
        VStack {
            HStack {
                Button { close(direction: 1, height: 0) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                Spacer()
                if count > 1 {
                    Text("\(index + 1) / \(count)")
                        .font(.subheadline.monospacedDigit().weight(.medium))
                }
                Spacer()
                Button {
                    if PhotoSaver.askEveryTime { askAlbum = true } else { Task { await save(albumID: PhotoSaver.defaultAlbumID) } }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .disabled(datas[index] == nil)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            Spacer()
            if let message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 40)
            }
        }
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
        MagnifyGesture()
            .onChanged { v in scale = min(5, max(1, baseScale * v.magnification)) }
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
        if let r = await Self.fetch(item.urls[i]) {
            datas[i] = r.data
            images[i] = r.image
        } else {
            failed.insert(i)
        }
    }

    /// 모바일 웹의 사진은 줄어든 사진이라, PC 글 아래 '원본 첨부파일' 링크(download.php)에서 원본을 받음
    /// 모바일 글 주소 → PC 글 주소로 바꿔서 원본 링크를 사진 순서대로 읽음. 못 찾으면 nil
    nonisolated private static func fetchOriginal(page: URL?, index: Int, count: Int) async -> Data? {
        guard let page, let pc = pcURL(page) else { return nil }
        var req = URLRequest(url: pc)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("https://gall.dcinside.com/", forHTTPHeaderField: "Referer")
        guard let (html, _) = try? await URLSession.shared.data(for: req),
              let text = String(data: html, encoding: .utf8),
              let box = text.range(of: "appending_file") else { return nil }
        let tail = String(text[box.upperBound...])
        let end = tail.range(of: "</ul>")?.lowerBound ?? tail.endIndex
        let section = String(tail[..<end]).replacingOccurrences(of: "&amp;", with: "&")
        guard let re = try? NSRegularExpression(pattern: #"https://image\.dcinside\.com/download\.php\?[^"'\s<>]+"#) else { return nil }
        let links = re.matches(in: section, range: NSRange(section.startIndex..., in: section))
            .compactMap { Range($0.range, in: section).map { String(section[$0]) } }
        // 사진 수와 원본 파일 수가 같을 때만 순서로 짝지음 (다르면 엉뚱한 파일이 저장될 수 있어서)
        guard links.count == count, index < links.count, let u = URL(string: links[index]) else { return nil }
        var dl = URLRequest(url: u)
        dl.setValue("https://gall.dcinside.com/", forHTTPHeaderField: "Referer")
        guard let (data, res) = try? await URLSession.shared.data(for: dl),
              (res as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty,
              CGImageSourceCreateWithData(data as CFData, nil) != nil else { return nil }
        return data
    }

    /// m.dcinside.com/board/{id}/{no} (mini·person도) → gall.dcinside.com/.../board/view/?id=&no=
    nonisolated private static func pcURL(_ url: URL) -> URL? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 3, let kind = ["board", "mini", "person"].first(where: { $0 == parts[0] }),
              parts[2].allSatisfy(\.isNumber) else { return nil }
        let prefix = kind == "board" ? "" : "/\(kind)"
        return URL(string: "https://gall.dcinside.com\(prefix)/board/view/?id=\(parts[1])&no=\(parts[2])")
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
        let data = await Self.fetchOriginal(page: item.pageURL, index: index, count: count) ?? shown
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

    private func flash(_ text: String) {
        message = text
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if message == text { message = nil }
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
