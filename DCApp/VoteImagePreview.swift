import SwiftUI
import UIKit

// MARK: - 투표 보기 사진 미리보기
// 투표 보기 썸네일을 누르면 디시 팝업 주소(viewimagePop.php?id=...&no=...)를 받아
// 팝업 HTML의 원본 사진(popImg)을 직접 내려받아 확대 가능한 원본 크기로 보여 준다. (썸네일 폴백 없음)

/// 투표 보기 사진 한 장
struct VotePreviewItem: Identifiable {
    let id = UUID()
    /// 팝업 주소(viewimagePop.php) 또는 같은 사진의 viewimage.php 주소
    let url: URL
    /// 사진이 있는 글 주소
    let pageURL: URL?
    /// 사진을 보여 준 투표 iframe 주소
    var referer: URL? = nil
}

struct VoteImagePreviewSheet: View {
    let item: VotePreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                if let image {
                    VoteZoomImageView(image: image)
                } else if failed {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("원본 사진을 불러오지 못했습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("다시 시도") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(12)
            .navigationTitle("투표 사진")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .task(id: item.id) { await load() }
        }
        // 사진을 크게 보도록 절반 높이 없이 큰 창으로
        .sheetUnderBlueBar()
    }

    private func load() async {
        failed = false
        image = nil
        let loaded = await VotePhotoLoader.loadFullImage(for: item.url, referer: item.referer ?? item.pageURL)
        if let loaded {
            image = loaded
        } else {
            failed = true
        }
    }
}

/// 원본 이미지를 핀치 줌·더블탭 확대로 볼 수 있는 네이티브 스크롤 뷰
private struct VoteZoomImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.backgroundColor = .clear
        sv.minimumZoomScale = 1.0
        sv.maximumZoomScale = 4.0
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.bouncesZoom = true
        sv.delegate = context.coordinator

        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        sv.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor),
            iv.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor),
            iv.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor),
            iv.widthAnchor.constraint(equalTo: sv.frameLayoutGuide.widthAnchor),
            iv.heightAnchor.constraint(equalTo: sv.frameLayoutGuide.heightAnchor)
        ])
        context.coordinator.imageView = iv

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        sv.addGestureRecognizer(doubleTap)
        return sv
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            uiView.setZoomScale(1.0, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            guard let sv = gr.view as? UIScrollView else { return }
            let target: CGFloat = sv.zoomScale > 1.05 ? 1.0 : 2.5
            sv.setZoomScale(target, animated: true)
        }
    }
}

/// viewimagePop.php에서 원본 이미지(popImg)를 추출해 직접 내려받는 로더
nonisolated enum VotePhotoLoader {
    static let agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// 캐시·쿠키가 전혀 남지 않는 일회성 세션 (이전 썸네일 캐시나 세션 쿠키 간섭 차단)
    private static let ephemeralSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        return URLSession(configuration: cfg)
    }()

    /// 썸네일 주소(dcimg*.dcinside.com/viewimage.php)가 들어와도 image.dcinside.com/viewimagePop.php로 정규화
    /// (이미 viewimagePop.php인 경우 showVoteImg 원본 주소이므로 no= 접미사를 건드리지 않음)
    static func popupURL(_ url: URL) -> URL {
        let isThumb = url.path.contains("viewimage.php")
        let popped = normalizePopupHostAndPath(url)
        return isThumb ? (stripThumbSuffix(from: popped) ?? popped) : popped
    }

    static func loadFullImage(for rawURL: URL, referer: URL?) async -> UIImage? {
        let popURL = popupURL(rawURL)
        return await fetchFromPopup(popURL: popURL, referer: referer)
    }

    private static func fetchFromPopup(popURL: URL, referer: URL?) async -> UIImage? {
        // 1단계: viewimagePop.php HTML에서 id="popImg"의 원본 이미지 주소 추출
        var popReq = URLRequest(url: popURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        popReq.setValue(agent, forHTTPHeaderField: "User-Agent")
        popReq.setValue(referer?.absoluteString ?? "https://m.dcinside.com/poll", forHTTPHeaderField: "Referer")
        popReq.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        popReq.setValue("no-cache", forHTTPHeaderField: "Pragma")

        guard let (htmlData, _) = try? await ephemeralSession.data(for: popReq) else {
            return nil
        }
        // viewimagePop.php는 EUC-KR 한글 바이트가 섞여 .utf8/.ascii 디코딩이 nil이 될 수 있으므로 .isoLatin1 폴백 필수
        let html = String(data: htmlData, encoding: .utf8)
            ?? String(data: htmlData, encoding: .isoLatin1)
            ?? ""
        let imgURL = extractPopImgURL(from: html, base: popURL)
            ?? swapPath(popURL, from: "viewimagePop.php", to: "viewimage.php")

        // 2단계: 추출한 원본 이미지 주소를 Referer=viewimagePop.php 로 내려받기
        var imgReq = URLRequest(url: imgURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        imgReq.setValue(agent, forHTTPHeaderField: "User-Agent")
        imgReq.setValue(popURL.absoluteString, forHTTPHeaderField: "Referer")
        imgReq.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        imgReq.setValue("no-cache", forHTTPHeaderField: "Pragma")

        guard let (imgData, _) = try? await ephemeralSession.data(for: imgReq),
              let uiImage = UIImage(data: imgData) else {
            return nil
        }
        return uiImage
    }

    private static func extractPopImgURL(from html: String, base: URL) -> URL? {
        let patterns = [
            #"<img[^>]*id=["']popImg["'][^>]*src=["']([^"']+)["']"#,
            #"<img[^>]*src=["']([^"']+)["'][^>]*id=["']popImg["']"#,
            #"src=["'](https?://[^"']*viewimage\.php\?[^"']+)["']"#
        ]
        for pattern in patterns {
            if let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = rx.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let r = Range(match.range(at: 1), in: html) {
                let raw = String(html[r]).replacingOccurrences(of: "&amp;", with: "&")
                if let u = URL(string: raw, relativeTo: base)?.absoluteURL { return u }
            }
        }
        return nil
    }

    private static func stripThumbSuffix(from url: URL, minLength: Int = 164) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var items = comps.queryItems,
              let idx = items.firstIndex(where: { $0.name == "no" }),
              let val = items[idx].value, val.count >= minLength else { return nil }
        items[idx].value = String(val.dropLast(6))
        comps.queryItems = items
        return comps.url
    }

    private static func normalizePopupHostAndPath(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        if let host = comps.host?.lowercased(), host.hasSuffix("dcinside.com"), host != "image.dcinside.com" {
            comps.host = "image.dcinside.com"
        }
        if comps.path.contains("viewimage.php") {
            comps.path = comps.path.replacingOccurrences(of: "viewimage.php", with: "viewimagePop.php")
        }
        return comps.url ?? url
    }

    private static func swapPath(_ url: URL, from: String, to: String) -> URL {
        guard url.lastPathComponent == from || url.lastPathComponent == to,
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        comps.path = comps.path.replacingOccurrences(of: from, with: to)
        return comps.url ?? url
    }
}
