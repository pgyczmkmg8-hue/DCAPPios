import SwiftUI
import PhotosUI
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
        WriteImageSize(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .original
    }
}

struct WriteImage: Identifiable {
    let id = UUID()
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

    init(galleryID: String) { self.galleryID = galleryID }

    /// 글자만 이어 붙인 내용 (임시저장·자동 저장용)
    var body: String {
        get { blocks.filter { $0.image == nil && !$0.text.isEmpty }.map(\.text).joined(separator: "\n") }
        set { blocks = blocks.filter { $0.image != nil } + [WriteBlock(text: newValue)]; normalize() }
    }
    var images: [WriteImage] { blocks.compactMap(\.image) }
    /// 새로 올릴 사진이 있는지 (수정할 때 원래 있던 사진은 빼고)
    var hasNewImages: Bool { images.contains { $0.rawHTML == nil } }

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

    /// 임시저장 글 불러오기 (HTML로 저장된 예전 글은 글자만)
    func apply(_ d: Draft) {
        title = d.title
        body = d.isHTML ? Self.plainText(fromHTML: d.body) : d.body
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
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showDraftPicker = false
    @State private var didFocus = false
    @State private var dropTarget: UUID?
    @State private var showDcconPicker = false
    @State private var endDropID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { toolbar }
        .overlay { if session.submitting { submittingCover } }
        // 안내 문구 (브라우저 화면의 안내는 이 화면에 가려서 여기서도 띄움)
        .overlay(alignment: .bottom) { NativeWriteToast(model: model).padding(.bottom, 70) }
        // .current: 사진 앱에 있는 원본 파일 그대로 받음 (HEIC 등은 올리기 전에 JPEG로 바꿈)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 20,
                      matching: .images, preferredItemEncoding: .current, photoLibrary: .shared())
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .sheet(isPresented: $showDcconPicker) {
            DcconPickerSheet(model: model)
        }
        .sheet(isPresented: $showDraftPicker) {
            DraftPickerSheet(galleryID: session.galleryID) { d in session.apply(d) }
        }
        .onAppear {
            guard !didFocus else { return }
            didFocus = true
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                if focus == nil {
                    if session.title.isEmpty { focus = .title } else { session.focusFirstText() }
                }
            }
        }
    }

    // MARK: 상단 (테마색): ← … 임시 등록 / 유동 닉네임·비밀번호

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { model.closeNativeWrite() } label: {
                    Image(systemName: "arrow.left").font(.system(size: 22, weight: .medium))
                        .frame(width: 40, height: 36, alignment: .leading)
                }
                accountMenu
                Spacer(minLength: 4)
                Button { model.saveNativeDraft() } label: {
                    Text("임시저장").font(.callout)
                }
                Button { showDraftPicker = true } label: {
                    Text("불러오기").font(.callout)
                }
                Button { dismissKeyboard(); model.submitNative() } label: {
                    Text("등록").font(.callout.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 1))
                }
                .disabled(session.submitting)
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .padding(.trailing, 2)

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
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(DCTheme.navy.ignoresSafeArea(edges: .top))
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
                .font(.system(size: 21))
                .frame(width: 36, height: 36)
        }
    }

    // MARK: 본문: 말머리 / 제목 / 코드 / 사진 / 내용

    private var content: some View {
        ScrollView {
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
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    Divider()
                }

                TextField("제목", text: $session.title)
                    .font(.system(size: 18))
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focus = nil; session.focusFirstText() }
                    .padding(.horizontal, 16).padding(.vertical, 16)
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
                                .padding(.horizontal, 5)
                                .overlay(alignment: .topLeading) {
                                    if block.text.isEmpty && block.id == session.blocks.first(where: { $0.image == nil })?.id {
                                        Text("내용").font(.system(size: 17)).foregroundStyle(Color(uiColor: .placeholderText))
                                            .padding(.leading, 16).padding(.top, 12)
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
                    .onTapGesture { if let last = session.blocks.last { focus = nil; session.focusRequest = last.id } }
                    .dropDestination(for: WriteBlockDrag.self) { items, _ in
                        drop(items, before: nil)
                    } isTargeted: { on in
                        if on { dropTarget = endDropID } else if dropTarget == endDropID { dropTarget = nil }
                    }
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private func dropLine(active: Bool) -> some View {
        Rectangle().fill(DCTheme.accent)
            .frame(height: active ? 3 : 0)
            .padding(.horizontal, 16)
            .animation(.easeOut(duration: 0.12), value: active)
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
            .padding(.horizontal, 16).padding(.vertical, 8)
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
                    tool("photo", "사진") { showPhotoPicker = true }
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
                    Menu {
                        ForEach(RichText.sizes.indices, id: \.self) { i in
                            let opt = RichText.sizes[i]
                            Button { session.applyFormat { $0.size = opt.size } } label: {
                                if session.format.size == opt.size { Label(opt.name, systemImage: "checkmark") } else { Text(opt.name) }
                            }
                        }
                    } label: {
                        toolIcon("textformat.size", on: session.format.size != RichText.baseSize)
                    }
                    .accessibilityLabel("글자 크기")
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
                }
                .padding(.horizontal, 6)
            }
            if keyboardUp {
                Button { dismissKeyboard() } label: {
                    toolIcon("keyboard.chevron.compact.down", on: false)
                }
                .buttonStyle(.plain)
            }
            // 맨 오른쪽: 디시 원래 글쓰기 화면으로
            Button { dismissKeyboard(); model.switchToWebWrite() } label: {
                toolIcon("safari", on: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("디시 원래 화면으로 쓰기")
            .padding(.trailing, 4)
        }
        .frame(height: 50)
        .background(Color(uiColor: .systemGray5).ignoresSafeArea(edges: .bottom))
    }

    /// 도구줄 아이콘: 모양이 달라도(배지 달린 아이콘 등) 같은 크기·같은 높이로
    private func toolIcon(_ icon: String, on: Bool) -> some View {
        Image(systemName: icon)
            .resizable()
            .scaledToFit()
            .fontWeight(.regular)
            .frame(width: 23, height: 23)
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
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: 사진 고르기

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
    /// 상단 테마색 위의 흰 입력 상자 (공식 앱처럼)
    func headerBox() -> some View {
        self.font(.system(size: 16))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 3))
            .environment(\.colorScheme, .light)
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

private struct DcconThumb: View {
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
        .presentationDetents([.medium, .large])
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
