import SwiftUI
import PDFKit

struct CapturedImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let fileURL: URL
}

enum PageCapture {
    /// 웹뷰가 만든 PDF(전체 페이지)를 세로로 긴 이미지 한 장으로 변환
    static func image(fromPDF data: Data) -> UIImage? {
        guard let doc = PDFDocument(data: data), doc.pageCount > 0 else { return nil }
        let pages = (0..<doc.pageCount).compactMap { doc.page(at: $0) }
        let width = pages.map { $0.bounds(for: .mediaBox).width }.max() ?? 0
        let height = pages.reduce(CGFloat(0)) { $0 + $1.bounds(for: .mediaBox).height }
        guard width > 0, height > 0 else { return nil }

        // 메모리 보호: 최대 약 5천만 픽셀, 세로 최대 60000px
        let maxPixels: CGFloat = 50_000_000
        var scale = min(2.0, (maxPixels / (width * height)).squareRoot())
        scale = min(scale, 60_000 / height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var y: CGFloat = 0
            for page in pages {
                let box = page.bounds(for: .mediaBox)
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: y + box.height)
                cg.scaleBy(x: 1, y: -1)            // PDF 좌표계(아래→위)를 뒤집기
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
                y += box.height
            }
        }
    }

    /// 공유/저장용 JPEG 파일 생성
    static func makeCaptured(_ image: UIImage) -> CapturedImage? {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-\(f.string(from: Date())).jpg")
        guard let data = image.jpegData(compressionQuality: 0.9),
              (try? data.write(to: url)) != nil else { return nil }
        return CapturedImage(image: image, fileURL: url)
    }
}

/// 캡처 미리보기 + 공유/사진 저장
struct CapturePreview: View {
    let capture: CapturedImage
    @Environment(\.dismiss) private var dismiss
    @State private var askAlbum = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: capture.image)
                    .resizable()
                    .scaledToFit()
            }
            .background(Color(.secondarySystemBackground))
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 30)
                }
            }
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
            .navigationTitle("캡처")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                // 사진 저장: 설정 → 세부 설정 → 사진 저장에서 정한 앨범으로
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if PhotoSaver.askEveryTime { askAlbum = true } else { Task { await save(albumID: PhotoSaver.defaultAlbumID) } }
                    } label: {
                        Label("사진 저장", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: capture.fileURL,
                              preview: SharePreview("디시 캡처", image: Image(uiImage: capture.image))) {
                        Label("공유", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func save(albumID: String?) async {
        guard let data = try? Data(contentsOf: capture.fileURL) else { return }
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
        withAnimation { message = text }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if message == text { withAnimation { message = nil } }
        }
    }
}
