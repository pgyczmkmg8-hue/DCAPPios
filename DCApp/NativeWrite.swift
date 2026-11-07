import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers
import Combine

// MARK: - 앱 글쓰기 화면 (공식 앱 스타일)
// 화면은 앱이 그리고, 등록은 뒤에 열린 디시 글쓰기 양식에 채워서 디시가 처리하게 함
// (로그인·보안 토큰·Cloudflare 체크는 디시 웹이 원래대로)

/// 앱 글쓰기 사진 크기 — 디시 글쓰기 '이미지 크기 일괄 설정'과 같은 값 (등록할 때 디시 imgSize 칸에도 넣음)
enum WriteImageSize: String, CaseIterable, Identifiable {
    case original = "ori", w1024 = "1024", w850 = "850", w640 = "640", w480 = "480"
    static let key = "writeImageSize"
    var id: String { rawValue }
    var label: String { self == .original ? "원본 크기" : "가로 \(rawValue)px" }
    /// 앱에서 줄일 가로 크기 (원본이면 nil)
    var maxWidth: CGFloat? { Double(rawValue).map { CGFloat($0) } }
    static var current: WriteImageSize {
        WriteImageSize(rawValue: Profile.defaults.string(forKey: key) ?? "") ?? .original
    }
}

struct WriteImage: Identifiable {
    var id = UUID()
    let data: Data
    let mime: String
    let ext: String
    var preview: UIImage?
    var isAuto = false
    /// 글 수정: 이미 올라가 있는 사진·디시콘·동영상 등 → 디시 편집기의 칸(HTML)을 그대로 다시 넣음
    var rawHTML: String? = nil
    var remoteURL: URL? = nil
    var label: String? = nil
}

/// 본문 한 칸: 글자 또는 사진 (순서대로 등록됨)
struct WriteBlock: Identifiable {
    let id = UUID()
    /// 글자 칸 내용 (꾸미기 포함)
    var rich: NSAttributedString
    var image: WriteImage?

    init(text: String = "", image: WriteImage? = nil) {
        rich = RichText.plain(text)
        self.image = image
    }

    /// 꾸미기 뺀 글자만
    var text: String {
        get { rich.string }
        set { rich = RichText.plain(newValue) }
    }
}

/// 사진 칸을 끌 때 실어 보내는 값 — 글자(String)로 보내면 내용 칸(TextField)이 받아서 글자로 넣어 버림
/// → 앱 전용 형식으로 보내서 글자 칸은 못 받고, 우리 놓기 자리만 받게 함
nonisolated struct WriteBlockDrag: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .dcappWriteBlock)
    }
}

extension UTType {
    nonisolated static let dcappWriteBlock = UTType(exportedAs: "MACHU.DCApp.writeblock")
}

struct WriteHead: Identifiable, Hashable {
    let no: String
    let name: String
    var id: String { no }
}

@MainActor
final class NativeWriteSession: ObservableObject {
    let galleryID: String
    @Published var galleryName = ""
    @Published var title = ""
    /// 본문: 글자 칸과 사진 칸을 순서대로 (사진은 길게 눌러 끌어서 옮김)
    @Published var blocks: [WriteBlock] = [WriteBlock()]
    @Published var heads: [WriteHead] = []
    @Published var head = ""
    @Published var isAnon = false
    @Published var nickLocked = false
    @Published var nick = ""
    @Published var pw = ""
    @Published var hasCaptcha = false
    @Published var captchaImage: UIImage?
    @Published var captcha = ""
    @Published var loaded = false
    /// 디시 글쓰기 양식(유동 여부·닉네임·말머리·코드칸)을 읽기 시작했는지 — 화면은 페이지 로딩 전에 먼저 뜨고, 양식은 로딩이 끝난 뒤 읽음
    var infoRequested = false
    /// 임시저장·이어쓰기로 채워서 시작했는지 (자짤 자동 첨부를 건너뜀)
    var restoredFromDraft = false
    /// 글 수정 화면이면 수정하는 글의 주소 (분할 화면에서 수정이 끝나면 그 글을 다시 보여 주기 위해)
    var modifyPostURL: URL?
    @Published var submitting = false
    /// 디시 화면을 보여주는 중 (Cloudflare 체크, 또는 동영상·디시콘 등 디시 기능 쓰는 중)
    @Published var showingWeb = false
    /// 디시 화면에서 쓰는 중인 기능 이름 (nil이면 Cloudflare 체크)
    @Published var webFeature: String?

    // 글자 꾸미기
    /// 지금 커서 자리의 꾸미기 상태 (도구줄 버튼 표시용)
    @Published var format = RichFormat()
    /// 글자 칸을 편집 중인지 (키보드 내리기 버튼 표시용)
    @Published var editingRich = false
    /// 이 칸에 커서를 넣어 달라는 요청
    @Published var focusRequest: UUID?
    var activeBlockID: UUID?
    private var textViews: [UUID: WeakTextView] = [:]
    private struct WeakTextView { weak var view: UITextView? }

    func register(_ tv: UITextView, for id: UUID) { textViews[id] = WeakTextView(view: tv) }
    private var activeTextView: UITextView? {
        guard let id = activeBlockID, let tv = textViews[id]?.view, tv.window != nil else { return nil }
        return tv
    }

    func rich(of id: UUID) -> NSAttributedString { blocks.first { $0.id == id }?.rich ?? NSAttributedString() }
    func setRich(_ r: NSAttributedString, of id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[i].rich = r
    }

    func refreshFormat(from tv: UITextView) {
        let r = tv.selectedRange
        let a: [NSAttributedString.Key: Any]
        if r.length > 0, r.location < tv.attributedText.length {
            a = tv.attributedText.attributes(at: r.location, effectiveRange: nil)
        } else {
            a = tv.typingAttributes
        }
        let f = RichText.format(from: a)
        if f != format { format = f }
    }

    /// 꾸미기 바꾸기: 고른 글자가 있으면 그 글자에, 없으면 앞으로 칠 글자에
    func applyFormat(_ change: (inout RichFormat) -> Void) {
        var target = format
        change(&target)
        guard let tv = activeTextView else { format = target; return }
        let r = tv.selectedRange
        if r.length > 0 {
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            m.enumerateAttributes(in: r) { a, run, _ in
                var f = RichText.format(from: a)
                change(&f)
                m.setAttributes(RichText.attributes(for: f), range: run)
            }
            tv.attributedText = m
            tv.selectedRange = r
            if let id = activeBlockID { setRich(m, of: id) }
        }
        tv.typingAttributes = RichText.attributes(for: target)
        format = target
    }

    /// 첫 글자 칸에 커서
    func focusFirstText() {
        if let b = blocks.first(where: { $0.image == nil }) { focusRequest = b.id }
    }
    /// 글자 칸의 키보드를 내림 (제목으로 옮길 때)
    func resignActiveText() { activeTextView?.resignFirstResponder() }
    /// 지금 편집 중인 글자 칸에 커서를 다시 확실히 넣음 (제목 포커스를 풀다가 키보드가 같이 내려간 경우 대비)
    func refocusActiveText() { activeTextView?.becomeFirstResponder() }

    init(galleryID: String) { self.galleryID = galleryID }

    /// 글자만 이어 붙인 내용 (임시저장·자동 저장용)
    var body: String {
        get { blocks.filter { $0.image == nil && !$0.text.isEmpty }.map(\.text).joined(separator: "\n") }
        set { blocks = blocks.filter { $0.image != nil } + [WriteBlock(text: newValue)]; normalize() }
    }
    var images: [WriteImage] { blocks.compactMap(\.image) }
    /// 새로 올릴 사진이 있는지 (수정할 때 원래 있던 사진은 빼고)
    var hasNewImages: Bool { images.contains { $0.rawHTML == nil } }
    /// 직접 넣은 사진이 있는지 (자짤 빼고) — 이것만 있어도 임시저장할 거리로 봄
    var hasUserImages: Bool { images.contains { $0.rawHTML == nil && !$0.isAuto } }

    /// 본문 끝에 남아 있는 꼬릿말 줄('-내용', 설정에 있는 꼬릿말 중 하나)을 지움.
    /// 꼬릿말은 등록할 때 이 계정·갤러리 규칙에 맞는 것만 새로 붙으므로, 다른 갤러리에서 쓴 글(수정·임시저장)의 옛 꼬릿말이 '-내용'으로 남지 않게.
    /// 디시가 이모지를 지우고 저장하는 경우('-🍎' → '-')도 같은 꼬릿말로 봄
    func stripKnownFooter() {
        let footers = FooterStore.shared.rules
            .map { FooterFormat.plain(FooterStore.clean($0.text)) }
            .filter { $0.count > 1 }
        guard !footers.isEmpty, let i = blocks.lastIndex(where: { $0.image == nil }) else { return }
        let m = NSMutableAttributedString(attributedString: blocks[i].rich)
        let ns = m.string as NSString
        // 끝에서부터 공백을 건너뛰고, 마지막 줄의 범위를 찾음
        var end = ns.length
        while end > 0, let u = UnicodeScalar(ns.character(at: end - 1)), CharacterSet.whitespacesAndNewlines.contains(u) { end -= 1 }
        guard end > 0 else { return }
        var start = end
        while start > 0, ns.character(at: start - 1) != 10 { start -= 1 }
        let line = ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespaces)
        let lineBare = FooterFormat.withoutEmoji(line)
        let isFooter = footers.contains { f in
            line == f || (FooterFormat.withoutEmoji(f) != f && lineBare == FooterFormat.withoutEmoji(f))
        }
        guard isFooter else { return }
        m.deleteCharacters(in: NSRange(location: start, length: ns.length - start))
        // 꼬릿말 앞에 띄워 둔 빈 줄·공백도 정리
        while let last = m.string.last, last.isWhitespace || last.isNewline {
            m.deleteCharacters(in: NSRange(location: m.length - 1, length: 1))
        }
        blocks[i].rich = m
    }

    /// 다른 갤러리 글을 불러올 때 사진을 새로 받아 오는 중인 개수 (다 받기 전에는 등록하지 않음)
    var convertingPhotos = 0

    /// 이미 올라가 있던 사진 칸을 앱이 가진 사진(등록할 때 이 갤러리에 새로 올림)으로 바꿈
    func replaceImage(id: UUID, with new: WriteImage) {
        guard let i = blocks.firstIndex(where: { $0.image?.id == id }) else { return }
        blocks[i].image = new
    }

    func setPreview(_ img: UIImage, for imageID: UUID) {
        guard let i = blocks.firstIndex(where: { $0.image?.id == imageID }) else { return }
        blocks[i].image?.preview = img
    }


    /// 사진 넣기: 맨 위(자짤) 또는 글 끝 (사진 뒤에 이어 쓸 글자 칸을 하나 둠)
    func addImages(_ imgs: [WriteImage], atTop: Bool = false) {
        let new = imgs.map { WriteBlock(image: $0) }
        if atTop {
            blocks.insert(contentsOf: new, at: 0)
        } else if let last = blocks.last, last.image == nil, last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.insert(contentsOf: new, at: blocks.count - 1)
        } else {
            blocks.append(contentsOf: new)
        }
        normalize()
    }

    func removeBlock(_ id: UUID) {
        blocks.removeAll { $0.id == id }
        normalize()
    }

    /// 사진 칸을 다른 칸 앞으로 (target이 nil이면 맨 끝으로)
    func move(_ id: UUID, before target: UUID?) {
        guard id != target, let from = blocks.firstIndex(where: { $0.id == id }) else { return }
        let b = blocks.remove(at: from)
        if let target, let to = blocks.firstIndex(where: { $0.id == target }) {
            blocks.insert(b, at: to)
        } else {
            blocks.append(b)
        }
        normalize()
    }

    /// 빈 글자 칸 정리 + 붙어 있는 글자 칸 합치기 + 맨 끝엔 항상 글자 칸
    func normalize() {
        var out: [WriteBlock] = []
        for b in blocks {
            if b.image == nil, let last = out.last, last.image == nil {
                if !b.text.isEmpty {
                    if last.text.isEmpty {
                        out[out.count - 1].rich = b.rich
                    } else {
                        let m = NSMutableAttributedString(attributedString: last.rich)
                        m.append(RichText.plain("\n"))
                        m.append(b.rich)
                        out[out.count - 1].rich = m
                    }
                }
                continue
            }
            out.append(b)
        }
        // 사진 사이에 낀 빈 글자 칸은 빼기 (맨 끝 칸은 남김)
        out = out.enumerated().filter { i, b in
            !(b.image == nil && b.text.isEmpty && i != out.count - 1)
        }.map(\.element)
        if out.last?.image != nil || out.isEmpty { out.append(WriteBlock()) }
        if out.map(\.id) != blocks.map(\.id) || zip(out, blocks).contains(where: { !$0.rich.isEqual(to: $1.rich) }) { blocks = out }
    }

    var hasText: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 임시저장용: 본문을 칸 순서대로 (사진은 파일로 저장해 두고 이름만)
    func draftParts() -> [DraftPart] {
        blocks.compactMap { b -> DraftPart? in
            guard let img = b.image else { return b.text.isEmpty ? nil : DraftPart(text: b.text) }
            if let raw = img.rawHTML {
                return DraftPart(rawHTML: raw, remoteURL: img.remoteURL, label: img.label)
            }
            guard let name = DraftImageStore.store(id: img.id, data: img.data, ext: img.ext) else { return nil }
            return DraftPart(file: name, mime: img.mime, ext: img.ext, isAuto: img.isAuto ? true : nil)
        }
    }

    /// 임시저장 글 불러오기 (사진이 든 글은 사진·순서까지, HTML로 저장된 예전 글은 글자만)
    func apply(_ d: Draft) {
        title = d.title
        if let parts = d.parts, parts.contains(where: { $0.text == nil }) {
            blocks = parts.compactMap { p -> WriteBlock? in
                if let t = p.text { return WriteBlock(text: t) }
                if let raw = p.rawHTML {
                    return WriteBlock(image: WriteImage(data: Data(), mime: "", ext: "", preview: nil, rawHTML: raw,
                                                        remoteURL: p.remoteURL, label: p.label))
                }
                guard let file = p.file, let data = DraftImageStore.load(file) else { return nil }
                // 파일 이름 = 사진 id → 다시 저장할 때 같은 파일을 그대로 씀
                let id = UUID(uuidString: String(file.split(separator: ".").first ?? "")) ?? UUID()
                return WriteBlock(image: WriteImage(id: id, data: data, mime: p.mime ?? "image/jpeg", ext: p.ext ?? "jpg",
                                                    preview: UIImage(data: data) ?? UIImage(), isAuto: p.isAuto ?? false))
            }
            normalize()
        } else {
            body = d.isHTML ? Self.plainText(fromHTML: d.body) : d.body
        }
        stripKnownFooter()
    }

    static func plainText(fromHTML html: String) -> String {
        var t = html
        for (pattern, rep) in [("(?i)<br\\s*/?>", "\n"), ("(?i)</p>", "\n"), ("(?i)</div>", "\n"), ("<[^>]+>", "")] {
            t = t.replacingOccurrences(of: pattern, with: rep, options: .regularExpression)
        }
        for (a, b) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#039;", "'"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// RootView에서 메인 브라우저 위에 덮는 자리
struct NativeWriteHost: View {
    @ObservedObject var model: WebViewModel

    var body: some View {
        if let s = model.nativeWrite {
            NativeWriteContainer(session: s, model: model)
                .id(ObjectIdentifier(s))
                .transition(.opacity)
        }
    }
}

private struct NativeWriteContainer: View {
    @ObservedObject var session: NativeWriteSession
    let model: WebViewModel

    var body: some View {
        if session.showingWeb {
            // 디시 화면 위에 안내만 (Cloudflare 체크 / 디시 기능 쓰는 중)
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: session.webFeature == nil ? "checkmark.shield" : "square.and.arrow.down")
                    Text(session.webFeature.map { "\($0)을(를) 넣은 뒤 눌러 주세요" } ?? "체크박스를 누르면 이어서 등록돼요")
                        .font(.subheadline)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button(session.webFeature == nil ? "앱 화면으로" : "다 넣었어요") {
                        if session.webFeature != nil { model.finishWebFeature() } else { session.showingWeb = false }
                    }
                    .font(.subheadline.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(DCTheme.navy)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        } else {
            NativeWriteView(session: session, model: model)
        }
    }
}

struct NativeWriteView: View {
    @ObservedObject var session: NativeWriteSession
    let model: WebViewModel

    private enum Field: Hashable { case nick, pw, title, captcha }
    @FocusState private var focus: Field?
    /// 글자 크기 슬라이더 (도구 줄의 글자 크기 버튼)
    @State private var showSizeSlider = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    /// 앱 전용 사진 고르기 (한 장씩 눌러서만 선택)
    @State private var showGridPicker = false
    @State private var showDraftPicker = false
    @State private var didFocus = false
    @State private var dropTarget: UUID?
    @State private var showDcconPicker = false
    @State private var endDropID = UUID()
    /// 등록이 10초 넘게 걸리면 나오는 '글쓰기 취소' 버튼
    @State private var showSubmitCancel = false
    @State private var confirmSubmitCancel = false
    /// 화면 크기(접기·펴기) 바뀔 때 올려서 상단바 배치를 다시 읽게 함
    @State private var sizeTick = 0
    @Environment(\.verticalSizeClass) private var vSizeClass

    var body: some View {
        Group {
            if vSizeClass == .compact {
                // 가로로 눕힌 폰: 키보드가 화면 대부분을 가려서 위쪽(닉네임·말머리)이 잘리므로 상단바 아래 전체를 한 번에 스크롤
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        contentBody
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                VStack(spacing: 0) {
                    header
                    content
                }
            }
        }
        // 일반 아이폰은 가로여도 안전 영역 없이 화면 끝까지 (듀오 옆 세로 줄은 피함)
        .ignoresSafeArea(.container, edges: (UIDevice.current.userInterfaceIdiom == .phone && !BrowserView.hasSideColumnOnly) ? [.leading, .trailing] : [])
        .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
            sizeTick &+= 1
            // 안전 영역 값은 조금 늦게 바뀌므로 한 번 더
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); sizeTick &+= 1 }
        }
        .background(Color(uiColor: Self.pageBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { toolbar }
        .overlay { if session.submitting { submittingCover } }
        .confirmationDialog("글쓰기를 취소하고 나갈까요?", isPresented: $confirmSubmitCancel, titleVisibility: .visible) {
            Button("취소하고 나가기", role: .destructive) { model.forceCloseNativeWrite() }
            Button("계속 기다리기", role: .cancel) {}
        } message: {
            Text("이미 등록됐을 수도 있어요. 나가도 쓰던 내용은 임시저장에 남아 있어요.")
        }
        // 안내 문구 (브라우저 화면의 안내는 이 화면에 가려서 여기서도 띄움)
        .overlay(alignment: .bottom) { NativeWriteToast(model: model).padding(.bottom, 70) }
        // .current: 사진 앱에 있는 원본 파일 그대로 받음 (HEIC 등은 올리기 전에 JPEG로 바꿈)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 20,
                      matching: .images, preferredItemEncoding: .current, photoLibrary: .shared())
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .sheet(isPresented: $showGridPicker) {
            PhotoGridPicker(maxCount: 20, onPick: loadAssets, onCapture: loadCaptured) {
                // 사진 접근이 막혀 있으면 iOS 기본 선택기로 (시트가 다 닫힌 뒤에)
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    showPhotoPicker = true
                }
            }
        }
        .sheet(isPresented: $showDcconPicker) {
            DcconPickerSheet(model: model)
        }
        .sheet(isPresented: $showDraftPicker) {
            DraftPickerSheet(galleryID: session.galleryID) { d in
                session.apply(d)
                model.loadRemotePreviews(session)   // 디시 서버 사진은 미리보기를 따로 받아야 보임 (불러온 임시저장)
                if d.galleryID != session.galleryID { model.convertRemotePhotos(session) }   // 다른 갤러리 글의 사진은 이 갤러리에 새로 올리도록
            }
        }
        .onAppear {
            guard !didFocus else { return }
            didFocus = true
            Task {
                try? await Task.sleep(for: .milliseconds(80))
                if focus == nil {
                    if session.title.isEmpty { focus = .title } else { session.focusFirstText() }
                }
            }
        }
        // 제목 칸에 커서가 있을 때 본문 칸을 눌러 편집이 시작되면 제목 포커스를 풀어 커서를 본문으로 옮김
        .onChange(of: session.editingRich) { _, on in
            if on, focus == .title {
                focus = nil
                // 제목 포커스를 풀 때 SwiftUI가 방금 커서가 들어간 본문까지 내려 버릴 수 있어서, 잠깐 뒤 본문에 커서를 다시 확실히 넣음
                Task {
                    try? await Task.sleep(for: .milliseconds(80))
                    session.refocusActiveText()
                }
            }
        }
    }

    // MARK: 상단 (테마색): ← … 임시 등록 / 유동 닉네임·비밀번호

    /// 듀오처럼 시계·카메라가 상단바에 겹쳐 그려지는 화면이면 (상태 줄 높이, 그 왼쪽에서 쓸 수 있는 폭)
    private static var duoStatusBand: (height: CGFloat, width: CGFloat)? {
        return nil
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel == .normal && !$0.isHidden }
        let width = windows.map(\.bounds.width).max() ?? 0
        let trailing = windows.map(\.safeAreaInsets.right).max() ?? 0
        let top = windows.map(\.safeAreaInsets.top).max() ?? 0
        guard trailing >= 56 || width > 440, top > 20 else { return nil }
        // 시계·카메라가 차지하는 폭: 접은 화면은 오른쪽 끝에서 약 173pt, 펼친 화면은 약 119pt (사진으로 잼)
        return (top, width - (trailing > 0 ? trailing : (width > 600 ? 125 : 180)))
    }

    private func headerButtons(compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 12) {
            Button { model.closeNativeWrite() } label: {
                Image(systemName: "chevron.backward").font(.system(size: compact ? 20 : 25, weight: .medium))
                    .frame(width: compact ? 24 : 40, height: 36, alignment: .leading)
            }
            accountMenu
            Spacer(minLength: compact ? 0 : 4)   // 버튼은 오른쪽(시계·카메라 바로 왼쪽)에 붙임
            if compact {
                // 듀오 상태 줄: 다이나믹 아일랜드가 켜져 시계가 밀려도 등록이 가려지지 않게 임시저장·불러오기는 ⋯ 하나로
                Menu {
                    Button { model.saveNativeDraft() } label: { Label("임시저장", systemImage: "square.and.arrow.down") }
                    Button { showDraftPicker = true } label: { Label("불러오기", systemImage: "tray.full") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 34, height: 36)
                        .contentShape(Rectangle())
                }
            } else {
                Button { model.saveNativeDraft() } label: {
                    Text("임시저장").font(.callout).lineLimit(1).fixedSize()
                }
                Button { showDraftPicker = true } label: {
                    Text("불러오기").font(.callout).lineLimit(1).fixedSize()
                }
            }
            // 로딩 중 상단바(BrowserView)의 등록 버튼과 같은 모양: 둥근 네모 테두리만
            Button { dismissKeyboard(); model.submitNative() } label: {
                Text("등록").font(.callout.weight(.bold)).lineLimit(1).fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.85), lineWidth: 1.2))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(session.submitting)
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.trailing, compact ? 2 : -3)
        .overlay {
            // 상단바 가운데 제목 (아이패드만 — 폰은 버튼이 가운데까지 와서 겹침)
            if !compact, UIDevice.current.userInterfaceIdiom == .pad { Text("글쓰기").font(.headline).foregroundStyle(.white).allowsHitTesting(false) }
        }
    }

    private static var listBarContentHeight: CGFloat {
        let bottom = ListBarMetrics.bottom
        let safeTop = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 0
        return (bottom > 20 && BrowserView.hasSideColumnOnly) ? max(bottom - safeTop, 0) : 0
    }

    private var header: some View {
        _ = sizeTick   // 접기·펴기로 화면 크기가 바뀌면 다시 계산
        let duo = Self.duoStatusBand
        return VStack(spacing: 10) {
            if let d = duo {
                // 시스템 시계·카메라 왼쪽 빈 자리(상태 줄)에 버튼을 올려 파란 영역을 줄임
                headerButtons(compact: true)
                    // 접은 화면: 다이나믹 아일랜드가 둘 켜지면 시계가 앞쪽(약 210pt)까지 밀리므로 버튼 줄은 그 안(약 196pt)에 둠
                    .frame(width: max(min(d.width - 24, d.width > 600 ? .infinity : 196), 0), height: d.height, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 0)
                    .offset(y: -(d.height / 2) + 6)   // 시계·카메라 글자 높이에 맞춤
                    .zIndex(1)
            } else {
                headerButtons(compact: false)
            }

            if session.isAnon {
                HStack(spacing: 10) {
                    TextField("닉네임", text: $session.nick)
                        .focused($focus, equals: .nick)
                        .disabled(session.nickLocked)
                        .opacity(session.nickLocked ? 0.6 : 1)
                        .headerBox()
                    SecureField("비밀번호", text: $session.pw)
                        .focused($focus, equals: .pw)
                        .headerBox()
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .tint(DCTheme.navy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, duo == nil ? (BrowserView.hasSideColumnOnly ? 9 : 6) : 0)
        .padding(.bottom, duo == nil ? (BrowserView.hasSideColumnOnly ? 9 : 12) : (session.isAnon ? 10 : 2))   // 듀오 세로 줄: 위아래 같게 해서 버튼이 바 가운데에
        // 글 목록 상단바(시스템 내비게이션 바)와 같은 높이로 (듀오 세로 줄 상태에서만)
        .frame(minHeight: Self.listBarContentHeight, alignment: .center)
        .background(DCTheme.navy.ignoresSafeArea(edges: [.top, .trailing]))
    }

    /// 로그인 / 계정 (상단바 왼쪽 — 원래 글쓰기 화면과 같은 메뉴)
    private var accountMenu: some View {
        let current = CredentialStore.currentAccountID
        let others = CredentialStore.all().filter { $0.id != current }
        return Menu {
            if let cur = current {
                Section("현재 계정: \(cur)") {
                    Button(role: .destructive) { model.logoutHere() } label: {
                        Label("로그아웃 (유동으로 쓰기)", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            if !others.isEmpty {
                Section(current == nil ? "저장된 계정으로 로그인" : "다른 계정으로 전환") {
                    ForEach(others) { acc in
                        Button { model.loginHere(acc) } label: { Label(acc.id, systemImage: "person.crop.circle") }
                    }
                }
            }
            Button { model.loginHere(nil) } label: { Label("로그인 페이지 열기", systemImage: "person.badge.key") }
        } label: {
            Image(systemName: current == nil ? "person.crop.circle.badge.plus" : "person.crop.circle.fill")
                .font(.system(size: Self.duoStatusBand == nil ? 24 : 21))
                .frame(width: 36, height: 36)
        }
    }

    // MARK: 본문: 말머리 / 제목 / 코드 / 사진 / 내용

    private var content: some View {
        ScrollView { contentBody }
            .scrollDismissesKeyboard(.interactively)
    }

    private var contentBody: some View {
            VStack(alignment: .leading, spacing: 0) {
                if !session.heads.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(session.heads) { h in
                                let on = session.head == h.no
                                Button { session.head = h.no } label: {
                                    Text(h.name).font(.subheadline.weight(on ? .semibold : .regular))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .foregroundStyle(on ? .white : .primary)
                                        .background(on ? DCTheme.navy : Color(uiColor: .secondarySystemBackground), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    Divider()
                }

                TextField("제목", text: $session.title)
                    .font(.system(size: 18))
                    .tint(DCTheme.accent)
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focus = nil; session.focusFirstText() }
                    // 하드웨어 키보드 Tab: 제목 → 본문
                    .onKeyPress(.tab) { focus = nil; session.focusFirstText(); return .handled }
                    .padding(.horizontal, 14).padding(.vertical, 16)      // 글자 왼쪽을 위쪽 닉네임 칸(14pt)과 맞춤
                Rectangle().fill(DCTheme.navy.opacity(0.7)).frame(height: 1)

                if session.hasCaptcha { captchaRow }

                ForEach(session.blocks) { block in
                    VStack(alignment: .leading, spacing: 0) {
                        dropLine(active: dropTarget == block.id)
                        if let img = block.image {
                            imageBlock(img, blockID: block.id)
                        } else {
                            RichTextView(blockID: block.id, session: session,
                                         minLines: block.id == session.blocks.last?.id ? 8 : 1)   // 맨 끝 칸은 넉넉하게
                                .padding(.horizontal, 9)      // 본문 글자 왼쪽도 닉네임 칸·제목과 맞춤
                                .overlay(alignment: .topLeading) {
                                    if block.text.isEmpty && block.id == session.blocks.first(where: { $0.image == nil })?.id {
                                        Text("내용").font(.system(size: 16)).foregroundStyle(Color(uiColor: .placeholderText))
                                            .padding(.leading, 12).padding(.top, 12)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }
                    }
                    // 사진을 끌어다 이 칸 위에 놓으면 이 칸 앞으로
                    .dropDestination(for: WriteBlockDrag.self) { items, _ in
                        drop(items, before: block.id)
                    } isTargeted: { on in
                        if on { dropTarget = block.id } else if dropTarget == block.id { dropTarget = nil }
                    }
                }

                // 맨 끝에 놓기
                Color.clear.frame(height: 80)
                    .overlay(alignment: .top) { dropLine(active: dropTarget == endDropID) }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 제목 등에 커서가 있었으면 본문 맨 끝으로 커서를 옮김 (키보드는 내려가지 않고 이어짐)
                        guard let last = session.blocks.last else { return }
                        let fromField = focus != nil
                        focus = nil
                        session.focusRequest = last.id
                        if fromField {
                            Task {
                                try? await Task.sleep(for: .milliseconds(80))
                                session.refocusActiveText()
                            }
                        }
                    }
                    .dropDestination(for: WriteBlockDrag.self) { items, _ in
                        drop(items, before: nil)
                    } isTargeted: { on in
                        if on { dropTarget = endDropID } else if dropTarget == endDropID { dropTarget = nil }
                    }
            }
    }

    private var captchaRow: some View {
        HStack(spacing: 10) {
            if let img = session.captchaImage {
                Image(uiImage: img).resizable().interpolation(.none).scaledToFit().frame(height: 32)
            }
            Button { model.refreshNativeCaptcha() } label: { Image(systemName: "arrow.clockwise") }
            TextField("코드 입력", text: $session.captcha)
                .focused($focus, equals: .captcha)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 14).padding(.top, 12)
    }

    /// 사진을 끌 때 놓을 자리: 색칠된 큰 칸 (놓으면 여기 들어감)
    private func dropLine(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(DCTheme.accent.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DCTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            )
            .frame(height: active ? 64 : 0)
            .opacity(active ? 1 : 0)
            .padding(.horizontal, 16)
            .padding(.vertical, active ? 6 : 0)
            .animation(.easeOut(duration: 0.15), value: active)
    }

    private func drop(_ items: [WriteBlockDrag], before target: UUID?) -> Bool {
        dropTarget = nil
        guard let id = items.first?.id,
              session.blocks.contains(where: { $0.id == id && $0.image != nil }) else { return false }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.2)) { session.move(id, before: target) }
        return true
    }

    /// 키보드 내리기 (제목·닉네임 칸과 글자 칸 모두)
    /// 제목 → 내용: 제목에서 '>' / 내용 → 제목: 내용에서 '<' (글자 칸은 글 끝에 커서)
    private func moveWriteFocus(forward: Bool) {
        if forward {
            guard focus == .title else { return }
            focus = nil
            session.focusFirstText()
        } else {
            guard focus == nil, session.editingRich else { return }
            session.resignActiveText()
            focus = .title
        }
    }

    private func dismissKeyboard() {
        focus = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var keyboardUp: Bool { focus != nil || session.editingRich }

    @ViewBuilder
    private func imagePicture(_ img: WriteImage) -> some View {
        if let p = img.preview {
            if p.images != nil {
                // 움직이는 디시콘·움짤
                AnimatedImageView(image: p)
                    .aspectRatio(p.size.width / max(p.size.height, 1), contentMode: .fit)
            } else {
                Image(uiImage: p).resizable().scaledToFit()
            }
        } else {
            // 글 수정: 원래 있던 디시콘·동영상 등, 또는 사진을 불러오는 중
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemBackground))
                if img.remoteURL != nil { ProgressView() }
                else {
                    Label(img.label ?? "첨부", systemImage: "paperclip").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(width: img.label == "디시콘" ? 110 : 220, height: img.remoteURL == nil ? 70 : (img.label == "디시콘" ? 110 : 160))
        }
    }

    private func imageBlock(_ img: WriteImage, blockID: UUID) -> some View {
        let isDccon = img.label == "디시콘"
        return imagePicture(img)
            // 디시콘은 실제 크기(작게), 사진은 넓게
            .frame(maxWidth: isDccon ? 110 : 300, maxHeight: isDccon ? 110 : 420, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation { session.removeBlock(blockID) }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .padding(8)
            }
            .overlay {
                // 유튜브·동영상 미리보기엔 재생 표시
                if img.preview != nil, img.label == "유튜브" || img.label == "동영상" {
                    Image(systemName: "play.fill").font(.system(size: 26)).foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(.black.opacity(0.5), in: Circle())
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if img.isAuto {
                    Text("자짤").font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(8)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
            // 길게 눌러 끌면 위치 이동
            .draggable(WriteBlockDrag(id: blockID)) {
                imagePicture(img)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .contextMenu {
                Button { withAnimation { session.move(blockID, before: session.blocks.first?.id) } } label: {
                    Label("맨 위로", systemImage: "arrow.up.to.line")
                }
                Button { withAnimation { session.move(blockID, before: nil) } } label: {
                    Label("맨 아래로", systemImage: "arrow.down.to.line")
                }
                Button(role: .destructive) { withAnimation { session.removeBlock(blockID) } } label: {
                    Label("빼기", systemImage: "trash")
                }
            }
    }

    // MARK: 도구줄 (키보드가 있으면 키보드 위, 없으면 맨 아래)

    private var toolbar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    tool("photo", "사진") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)   // 키보드를 먼저 내려 시트 전환과 겹치지 않게
                        showGridPicker = true
                    }
                    tool("photo.badge.plus", "자짤") {
                        let before = session.images.count
                        model.addAutoImage()
                        if session.images.count > before { model.showToast("자짤을 넣었어요 (길게 눌러 옮길 수 있어요)") }
                    }
                    tool("face.smiling", "디시콘") { dismissKeyboard(); showDcconPicker = true }
                    tool("video", "동영상") { dismissKeyboard(); model.openWebFeature("video", name: "동영상") }
                    tool("play.rectangle", "유튜브") { dismissKeyboard(); model.openWebFeature("youtube", name: "유튜브") }
                    tool("chart.bar", "투표") { dismissKeyboard(); model.openWebFeature("vote", name: "투표") }

                    Divider().frame(height: 24).padding(.horizontal, 4)

                    // 글자 꾸미기: 굵게 / 기울임 / 크기 / 색 (고른 글자, 없으면 앞으로 칠 글자)
                    tool("bold", "굵게", on: session.format.bold) { session.applyFormat { $0.bold.toggle() } }
                    tool("italic", "기울임", on: session.format.italic) { session.applyFormat { $0.italic.toggle() } }
                    Button { showSizeSlider = true } label: {
                        toolIcon("textformat.size", on: session.format.size != RichText.baseSize)
                    }
                    .accessibilityLabel("글자 크기")
                    .popover(isPresented: $showSizeSlider) {
                        VStack(spacing: 12) {
                            Text("글자 크기 \(Int(session.format.size))pt")
                                .font(.headline)
                            Slider(value: Binding(
                                get: { Double(session.format.size) },
                                set: { v in session.applyFormat { $0.size = CGFloat(v.rounded()) } }
                            ), in: 10...32, step: 1)
                            Button("기본 크기로") { session.applyFormat { $0.size = RichText.baseSize } }
                                .font(.subheadline)
                        }
                        .padding(20)
                        .frame(width: 300)
                        .presentationCompactAdaptation(.popover)
                    }
                    Menu {
                        ForEach(RichText.colors.indices, id: \.self) { i in
                            let opt = RichText.colors[i]
                            Button { session.applyFormat { $0.colorHex = opt.hex } } label: {
                                Label {
                                    Text(opt.name)
                                } icon: {
                                    Image(systemName: session.format.colorHex == opt.hex ? "checkmark.circle.fill" : "circle.fill")
                                        .foregroundStyle(opt.hex.flatMap(RichText.color(hex:)).map(Color.init(uiColor:)) ?? .primary)
                                }
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(session.format.colorHex.flatMap(RichText.color(hex:)).map(Color.init(uiColor:)) ?? Color.primary)
                                .frame(width: 20, height: 20)
                            Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1).frame(width: 24, height: 24)
                        }
                        .frame(width: 44, height: 46)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("글자 색")
                    // 글자 색 옆: 잘못 눌리지 않게 앞에 빈 공간을 두고 디시 원래 화면 버튼
                    Button { dismissKeyboard(); model.switchToWebWrite() } label: {
                        toolIcon("safari", on: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("디시 원래 화면으로 쓰기")
                    .padding(.leading, 44)
                }
                .padding(.horizontal, 6)
                .padding(.trailing, 34)
            }
            // 오른쪽 끝에서 잘린 아이콘 조각이 커서처럼 보이지 않게 흐리게 사라지게
            .mask {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 40)
                }
            }
            Divider().frame(height: 24)
            if keyboardUp {
                // 제목 ⇄ 내용 이동 (웹 글쓰기의 < > 와 같음)
                Button { moveWriteFocus(forward: false) } label: {
                    toolIcon("chevron.left", on: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("제목으로")
                Button { moveWriteFocus(forward: true) } label: {
                    toolIcon("chevron.right", on: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("내용으로")
                Button { dismissKeyboard() } label: {
                    toolIcon("keyboard.chevron.compact.down", on: false)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 50)
        .background(Color(uiColor: Self.toolbarBackground).ignoresSafeArea(edges: (UIDevice.current.userInterfaceIdiom == .phone && !BrowserView.hasSideColumnOnly) ? [.bottom, .leading, .trailing] : .bottom))
    }

    /// 다크모드 배경: 디시 화면(다크모드)과 같은 회색 (기본 검정이 너무 어두워서)
    private static let pageBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x27/255, green: 0x27/255, blue: 0x29/255, alpha: 1) : .systemBackground }
    private static let toolbarBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x33/255, green: 0x33/255, blue: 0x36/255, alpha: 1) : .systemGray5 }

    /// 도구줄 아이콘: 모양이 달라도(배지 달린 아이콘 등) 같은 크기·같은 높이로
    /// 그림 크기에 맞춰 늘리지 않고 같은 글자 크기로 그려서, 아이콘마다 선 굵기·크기가 같게
    /// 자짤(photo.badge.plus)은 사진 아이콘을 그대로 두고 '+' 배지만 얹어서 사진 버튼과 줄이 딱 맞게
    private func toolIcon(_ icon: String, on: Bool) -> some View {
        Group {
            if icon == "photo.badge.plus" {
                Image(systemName: "photo")
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .background(Circle().fill(Color(uiColor: .systemGray5)).padding(-1.5))
                            .offset(x: 5, y: 4)
                    }
            } else {
                Image(systemName: icon)
            }
        }
            .font(.system(size: 20, weight: .regular))
            .frame(width: 44, height: 46)
            .foregroundStyle(on ? AnyShapeStyle(DCTheme.accent) : AnyShapeStyle(.secondary))
            .background(on ? DCTheme.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }

    private func tool(_ icon: String, _ label: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolIcon(icon, on: on) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private var submittingCover: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(session.hasNewImages ? "사진을 올리고 등록하는 중…" : "등록하는 중…").font(.subheadline)
                if showSubmitCancel {
                    // 등록이 오래 걸릴 때 강제로 나가기
                    Text("오래 걸리고 있어요").font(.footnote).foregroundStyle(.secondary)
                    Button { confirmSubmitCancel = true } label: {
                        Text("글쓰기 취소")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Color.red, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .animation(.easeOut(duration: 0.2), value: showSubmitCancel)
            .task {
                showSubmitCancel = false
                try? await Task.sleep(for: .seconds(10))
                if !Task.isCancelled { showSubmitCancel = true }
            }
            .onDisappear { showSubmitCancel = false }
        }
    }

    // MARK: 사진 고르기

    /// 앱 전용 사진 고르기에서 고른 사진 (고른 순서대로 글 끝에)
    private func loadAssets(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        let maxWidth = WriteImageSize.current.maxWidth
        Task {
            var added: [WriteImage] = []
            for asset in assets {
                guard let raw = await PhotoGridPicker.loadData(asset) else { continue }
                let prepared = await Task.detached { AutoImageStore.prepareForUpload(raw, maxWidth: maxWidth) }.value
                guard let p = prepared else { continue }
                added.append(WriteImage(data: p.data, mime: p.mime, ext: p.ext, preview: UIImage(data: p.data) ?? UIImage()))
            }
            if added.count < assets.count { model.showToast("사진 \(assets.count - added.count)장을 불러오지 못했어요") }
            withAnimation { session.addImages(added) }
        }
    }

    /// 카메라로 찍은 사진 (글 끝에 붙임)
    private func loadCaptured(_ image: UIImage) {
        let maxWidth = WriteImageSize.current.maxWidth
        Task {
            guard let raw = image.jpegData(compressionQuality: 0.95),
                  let p = await Task.detached(operation: { AutoImageStore.prepareForUpload(raw, maxWidth: maxWidth) }).value else {
                model.showToast("찍은 사진을 불러오지 못했어요")
                return
            }
            let w = WriteImage(data: p.data, mime: p.mime, ext: p.ext, preview: UIImage(data: p.data) ?? UIImage())
            withAnimation { session.addImages([w]) }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        let maxWidth = WriteImageSize.current.maxWidth
        Task {
            var added: [WriteImage] = []
            for item in items {
                guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }
                let prepared = await Task.detached { AutoImageStore.prepareForUpload(raw, maxWidth: maxWidth) }.value
                guard let p = prepared else { continue }
                added.append(WriteImage(data: p.data, mime: p.mime, ext: p.ext, preview: UIImage(data: p.data) ?? UIImage()))
            }
            // 글 끝에 붙임 → 길게 눌러 끌어서 글 위로 옮길 수 있음
            withAnimation { session.addImages(added) }
        }
    }
}

private extension View {
    /// 상단 테마색 위의 입력 상자 (공식 앱처럼 흰색, 다크모드에서는 어두운 회색)
    func headerBox() -> some View { modifier(HeaderBoxStyle()) }
}

private struct HeaderBoxStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content
            .font(.system(size: 16))
            .foregroundStyle(dark ? Color.white : Color.black)
            .tint(dark ? Color.white : DCTheme.navy)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(dark ? Color(white: 0.17) : Color.white, in: RoundedRectangle(cornerRadius: 3))
    }
}


// MARK: - 디시콘 고르기 (앱 화면)

struct DcconTab: Identifiable, Hashable {
    let idx: String
    let folder: String
    let name: String
    let thumb: URL?
    var id: String { idx + "|" + folder }
}

struct DcconItem: Identifiable, Hashable {
    let pkg: String
    let detail: String
    let alt: String
    let src: URL?
    var id: String { pkg + "-" + detail }
}

/// 디시콘 그림 불러오기 (디시 이미지 서버는 Referer가 있어야 보여줌) — 한 번 받은 건 기억
@MainActor
final class DcconImageCache {
    static let shared = DcconImageCache()
    private let datas = NSCache<NSURL, NSData>()
    private let stills = NSCache<NSURL, UIImage>()

    func still(_ url: URL) -> UIImage? { stills.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let img = stills.object(forKey: url as NSURL) { return img }
        guard let data = await data(url), let img = UIImage(data: data) else { return nil }   // 목록은 첫 장만 (가볍게)
        stills.setObject(img, forKey: url as NSURL)
        return img
    }

    /// 글에 넣을 때 미리보기: 움직이는 디시콘은 움직이게
    func animated(_ url: URL) async -> UIImage? {
        guard let data = await data(url) else { return nil }
        return await Task.detached { ImageViewer.decode(data) }.value
    }

    private func data(_ url: URL) async -> Data? {
        if let d = datas.object(forKey: url as NSURL) { return d as Data }
        var req = URLRequest(url: url)
        req.setValue("https://m.dcinside.com/", forHTTPHeaderField: "Referer")
        guard let (d, _) = try? await URLSession.shared.data(for: req) else { return nil }
        datas.setObject(d as NSData, forKey: url as NSURL)
        return d
    }
}

struct DcconThumb: View {
    let url: URL?
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let img { Image(uiImage: img).resizable().scaledToFit() }
            else { Color(uiColor: .secondarySystemBackground).overlay { ProgressView().controlSize(.small) } }
        }
        .task(id: url) {
            guard let url else { return }
            img = DcconImageCache.shared.still(url)
            if img == nil { img = await DcconImageCache.shared.load(url) }
        }
    }
}

struct DcconPickerSheet: View {
    let model: WebViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var tabs: [DcconTab] = []
    @State private var current = ""
    @State private var items: [DcconItem] = []
    @State private var loading = true
    @State private var failed = false
    @State private var inserting: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !tabs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tabs) { t in
                                Button { select(t) } label: {
                                    Group {
                                        if t.idx == "0" { Image(systemName: "clock").font(.system(size: 18)) }
                                        else { DcconThumb(url: t.thumb) }
                                    }
                                    .frame(width: 36, height: 36)
                                    .padding(5)
                                    .background(current == t.idx ? DCTheme.accent.opacity(0.18) : .clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(t.idx == "0" ? "최근 사용" : t.name)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    Divider()
                }
                ScrollView {
                    if loading {
                        ProgressView().padding(40)
                    } else if items.isEmpty {
                        Text(failed ? "디시콘 목록을 불러오지 못했어요" : "디시콘이 없어요")
                            .foregroundStyle(.secondary).padding(40)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                            ForEach(items) { it in
                                Button { pick(it) } label: {
                                    DcconThumb(url: it.src)
                                        .frame(width: 72, height: 72)
                                        .overlay { if inserting == it.id { ProgressView() } }
                                }
                                .buttonStyle(.plain)
                                .disabled(inserting != nil)
                                .accessibilityLabel(it.alt)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle(tabs.first(where: { $0.idx == current }).map { $0.idx == "0" ? "최근 사용" : $0.name } ?? "디시콘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
        .sheetUnderBlueBar(medium: true)
        .task {
            guard tabs.isEmpty else { return }
            if let r = await model.dcconTabs() {
                tabs = r.tabs
                current = r.current.isEmpty ? (r.tabs.first?.idx ?? "") : r.current
                items = r.items
            } else {
                failed = true
            }
            loading = false
        }
    }

    private func select(_ t: DcconTab) {
        guard t.idx != current else { return }
        current = t.idx
        loading = true
        Task {
            let list = await model.dcconItems(t)
            guard current == t.idx else { return }
            items = list
            loading = false
        }
    }

    private func pick(_ it: DcconItem) {
        inserting = it.id
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            var preview: UIImage?
            if let u = it.src { preview = await DcconImageCache.shared.animated(u) }
            let ok = await model.insertDccon(it, preview: preview)
            inserting = nil
            if ok { dismiss() }
        }
    }
}

/// 앱 글쓰기 화면 위 안내 문구 — 안내만 지켜보게 따로 떼어 둠 (글 쓰는 화면이 쓸데없이 다시 그려지지 않게)
private struct NativeWriteToast: View {
    @ObservedObject var model: WebViewModel

    var body: some View {
        Group {
            if let toast = model.toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast)
        .allowsHitTesting(false)
    }
}
