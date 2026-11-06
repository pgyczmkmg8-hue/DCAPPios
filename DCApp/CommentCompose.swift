import SwiftUI
import Combine

/// 앱 댓글 입력창에서 쓰는 내용 (등록은 디시 댓글 양식에 채워서 디시 페이지가 처리)
@MainActor
final class CommentComposeSession: ObservableObject, Identifiable {
    let id = UUID()
    /// 대댓글인지, 누구에게 다는지
    let isReply: Bool
    let replyNick: String
    /// 대댓글 대상 댓글 번호 (페이지가 다시 불려온 뒤 답글 칸을 다시 찾을 때 씀)
    let replyCh: String
    let anon: Bool
    let nickLocked: Bool
    @Published var hasCode = false
    @Published var codeImage: UIImage?
    /// 코드 입력칸에 회색으로 보이는 안내 (디시 페이지의 안내 문구, 예: 코드 3자리 입력)
    @Published var codePlaceholder = "코드 입력"

    @Published var text: String
    @Published var nick: String
    @Published var pw: String
    @Published var code = ""
    @Published var sending = false
    /// 쓰던 글을 보관·복구할 때 쓰는 키 (글 주소 + 댓글/대댓글 대상)
    var draftKey = ""
    /// 이 입력창이 붙은 페이지 (글 주소, # 뒤 제외) — 다른 페이지로 가면 닫음
    var pageKey = ""

    init(info: [String: Any], gallery: String? = nil) {
        isReply = info["reply"] as? Bool ?? false
        replyNick = info["replyNick"] as? String ?? ""
        replyCh = info["ch"] as? String ?? ""
        anon = info["anon"] as? Bool ?? false
        nickLocked = info["nickLocked"] as? Bool ?? false
        hasCode = info["code"] as? Bool ?? false
        if let ph = info["codePh"] as? String, !ph.isEmpty { codePlaceholder = ph }
        codeImage = Self.codeImage(from: info["codeImg"] as? String)
        text = info["text"] as? String ?? ""
        let pageNick = info["nick"] as? String ?? ""
        let pagePw = info["pw"] as? String ?? ""
        let saved = AnonStore.nick(for: gallery)
        nick = !pageNick.isEmpty ? pageNick : (saved.isEmpty ? "ㅇㅇ" : saved)
        pw = !pagePw.isEmpty ? pagePw : AnonStore.password(for: gallery)
    }

    static func codeImage(from s: String?) -> UIImage? {
        guard let s, let comma = s.firstIndex(of: ","),
              let data = Data(base64Encoded: String(s[s.index(after: comma)...])) else { return nil }
        return UIImage(data: data)
    }

    /// 같은 칸을 다시 눌렀는지 (입력창을 새로 만들지 않고 그대로 둠)
    func sameTarget(_ info: [String: Any]) -> Bool {
        (info["reply"] as? Bool ?? false) == isReply && (info["replyNick"] as? String ?? "") == replyNick
    }
}

/// 브라우저 화면 맨 아래에 뜨는 앱 댓글 입력창 (키보드 위)
struct CommentComposerHost: View {
    @ObservedObject var model: WebViewModel
    /// 키보드 윗변의 화면 y (키보드가 없으면 nil) / 키보드가 화면 아래를 가린 높이
    /// SwiftUI의 키보드 안전 영역 값은 글자를 칠 때(추천 줄이 바뀔 때) 실제 키보드와 10pt쯤 어긋나
    /// 입력창과 키보드 사이에 틈이 남음 → 입력창의 실제 아래 끝 위치를 재서 키보드 윗변에 맞게 보정
    @State private var keyboardTop: CGFloat?
    @State private var keyboardCover: CGFloat = 0
    @State private var correction: CGFloat = 0

    var body: some View {
        if let s = model.commentCompose {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { model.closeCommentCompose(sync: true) }
                CommentComposer(session: s, model: model)
                    .ignoresSafeArea(.container, edges: .trailing)   // 듀오 옆 세로 줄 자리까지 입력창을 채움 (줄은 맨 위 시계 자리라 아래쪽은 비어 있음)
                    .background {
                        GeometryReader { g in
                            Color.clear
                                .onChange(of: g.frame(in: .global).maxY) { _, y in realign(composerBottom: y) }
                                .onAppear { realign(composerBottom: g.frame(in: .global).maxY) }
                        }
                    }
                    .padding(.bottom, max(0, keyboardCover - Self.windowBottomInset + correction))
                    .transition(.move(edge: .bottom))
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .id(s.id)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
                guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
                let kbTop = end.minY, winH = UIScreen.main.bounds.height
                let d = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
                withAnimation(.easeOut(duration: d)) {
                    keyboardTop = kbTop < winH - 1 ? kbTop : nil
                    keyboardCover = max(0, winH - kbTop)
                    correction = 0
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { n in
                let d = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
                withAnimation(.easeOut(duration: d)) { keyboardTop = nil; keyboardCover = 0; correction = 0 }
            }
        }
    }

    /// 입력창 아래 끝이 키보드 윗변과 어긋나면 그만큼 보정 (듀오 동영상 분할처럼 앱 창이 화면 일부일 때 큰 어긋남도 여기서 맞춤)
    private func realign(composerBottom: CGFloat) {
        guard let top = keyboardTop else { return }
        let gap = top - composerBottom
        guard abs(gap) > 0.5, abs(gap) < 600 else { return }
        correction -= gap
    }

    private static var windowBottomInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { $0.windowLevel == .normal && !$0.isHidden }
            .map(\.safeAreaInsets.bottom).max() ?? 0
    }
}

private struct CommentComposer: View {
    @ObservedObject var session: CommentComposeSession
    let model: WebViewModel
    private enum Field: Hashable { case text, nick, pw, code }
    @FocusState private var focus: Field?
    private enum Panel { case dccon, txtcon }
    @State private var panel: Panel?
    /// 댓글 입력칸(UIKit)에 키보드를 띄울지 — SwiftUI FocusState와 따로 둠 (FocusState가 UIKit 칸의 포커스를 비우는 일을 막음)
    @State private var textFocus = false
    @State private var contentH: CGFloat = 0

    private func togglePanel(_ p: Panel) {
        panel = panel == p ? nil : p
        textFocus = panel == nil      // 디시콘·글자콘을 보는 동안은 키보드를 내림
        focus = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.isReply {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.footnote)
                    Text(session.replyNick.isEmpty ? "대댓글" : "\(session.replyNick)에게 대댓글")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            if session.anon {
                HStack(spacing: 8) {
                    TextField("닉네임", text: $session.nick)
                        .focused($focus, equals: .nick)
                        .disabled(session.nickLocked)
                        .opacity(session.nickLocked ? 0.6 : 1)
                        .fieldBox()
                    SecureField("비밀번호", text: $session.pw)
                        .focused($focus, equals: .pw)
                        .fieldBox()
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
            if session.hasCode {
                HStack(spacing: 8) {
                    if let img = session.codeImage {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(height: 30)
                    } else {
                        Text("코드").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button { model.refreshCommentCode() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    TextField(session.codePlaceholder, text: $session.code)
                        .focused($focus, equals: .code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fieldBox()
                }
            }
            CommentTextView(
                text: $session.text,
                placeholder: session.isReply ? "대댓글을 입력해주세요" : "댓글을 입력해주세요",
                isFocused: $textFocus,
                onCommandReturn: { model.submitComment() })
                .fieldBox(minHeight: 70)
            HStack(spacing: 14) {
                Button { togglePanel(.dccon) } label: {
                    Label("디시콘", systemImage: panel == .dccon ? "keyboard" : "face.smiling").font(.subheadline)
                }
                .disabled(session.sending)
                Button { togglePanel(.txtcon) } label: {
                    Label("글자콘", systemImage: panel == .txtcon ? "keyboard" : "textformat").font(.subheadline)
                }
                .disabled(session.sending)
                Spacer()
                Text("\(session.text.count)자")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                Button { model.closeCommentCompose(sync: true) } label: {
                    Text("닫기").font(.subheadline)
                }
                Button { model.submitComment() } label: {
                    Text(session.sending ? "등록 중…" : "등록")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(DCTheme.navy.opacity(session.sending ? 0.5 : 1), in: Capsule())
                }
                .disabled(session.sending)
            }
            .buttonStyle(.plain)
            if panel == .dccon {
                CommentDcconPanel(model: model)
                    .frame(height: 280)
            } else if panel == .txtcon {
                CommentTxtconPanel(model: model)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in contentH = h }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        // 글자를 칠 때 시스템이 바깥에서 주는 높이가 131↔150pt로 번갈아 바뀌어(아래 끝은 키보드에 붙은 채 위쪽만 움직임)
        // 입력창이 위로 뜨던 것 → 내용 높이를 직접 재서 입력창 높이를 못 박음
        .frame(height: contentH > 0 ? contentH + 22 : nil, alignment: .top)
        // 배경은 아래로 길게 늘려 키보드 뒤·화면 맨 아래까지 깔음 (키보드의 둥근 모서리 뒤나 키보드가 내려갈 때 흰 바탕이 보이지 않게, 화면 모서리에서 잘려 둥글게 보임) — 기기에서 키보드 윗변 값이 실제 보이는 키보드보다 10pt쯤 높게 나와
        // 입력창과 키보드 사이에 틈이 보이는 경우가 있어서, 틈이 생겨도 입력창 배경이 이어지게 함
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .padding(.bottom, -20)
        }
        // 입력창 아래(키보드 뒤)는 키보드와 같은 회색으로 채움 — 키보드의 둥근 모서리 뒤로 흰색이 비치지 않게
        .background(alignment: .bottom) {
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1) })
                .frame(height: 700)
                .offset(y: 700 + 20)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                textFocus = true
            }
        }
    }
}

private extension View {
    func fieldBox(minHeight: CGFloat = 0) -> some View {
        self
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 앱 댓글 입력창 아래에 펼치는 디시콘 목록 (고르면 바로 댓글로 등록)
private struct CommentDcconPanel: View {
    let model: WebViewModel
    @State private var tabs: [DcconTab] = []
    @State private var current = ""
    @State private var items: [DcconItem] = []
    @State private var loading = true
    @State private var failed = false
    @State private var picking: String?

    var body: some View {
        VStack(spacing: 6) {
            ScrollView {
                if loading {
                    ProgressView().padding(40)
                } else if items.isEmpty {
                    Text(failed ? "디시콘 목록을 불러오지 못했어요" : "디시콘이 없어요")
                        .font(.subheadline).foregroundStyle(.secondary).padding(40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                        ForEach(items) { it in
                            Button { pick(it) } label: {
                                DcconThumb(url: it.src)
                                    .frame(width: 64, height: 64)
                                    .overlay { if picking == it.id { ProgressView() } }
                            }
                            .buttonStyle(.plain)
                            .disabled(picking != nil)
                            .accessibilityLabel(it.alt)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if !tabs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tabs) { t in
                            Button { select(t) } label: {
                                Group {
                                    if t.idx == "0" { Image(systemName: "clock").font(.system(size: 18)) }
                                    else { DcconThumb(url: t.thumb) }
                                }
                                .frame(width: 32, height: 32)
                                .padding(4)
                                .background(current == t.idx ? DCTheme.accent.opacity(0.18) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(t.idx == "0" ? "최근 사용" : t.name)
                        }
                    }
                }
            }
        }
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
        picking = it.id
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            _ = await model.sendCommentDccon(it)
            picking = nil
        }
    }
}

// MARK: - 글자콘

struct TxtconColor: Hashable {
    let hex: String
    let on: Bool
}

struct TxtconInfo {
    let bg: [TxtconColor]
    let font: [TxtconColor]
    let recent: [String]
    let max: Int
}

private extension Color {
    init(txtconHex hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

/// 앱 댓글 입력창 아래에 펼치는 글자콘 만들기 (글자·배경색·글자색 → 등록)
private struct CommentTxtconPanel: View {
    let model: WebViewModel
    @State private var info: TxtconInfo?
    @State private var failed = false
    @State private var text = ""
    @State private var bg = "3b4890"
    @State private var font = "ffffff"
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if let info {
                VStack(spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Color(txtconHex: bg))
                            Text(text.isEmpty ? "미리보기" : text)
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(Color(txtconHex: text.isEmpty ? font : font).opacity(text.isEmpty ? 0.5 : 1))
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.4)
                                .padding(6)
                        }
                        .frame(width: 100, height: 100)
                        VStack(alignment: .leading, spacing: 8) {
                            colorRow("배경색", info.bg, selected: bg) { hex in
                                bg = hex; model.txtconSetColor("bg", hex)
                            }
                            colorRow("글자색", info.font, selected: font) { hex in
                                font = hex; model.txtconSetColor("font", hex)
                            }
                            HStack {
                                TextField("글자콘 내용 입력 (최대 \(info.max)자)", text: $text, axis: .vertical)
                                    .lineLimit(1...3)
                                    .focused($focused)
                                    .submitLabel(.done)
                                    .onChange(of: text) { _, v in
                                        Task {
                                            let kept = await model.txtconSetText(v)
                                            if kept != v { text = kept }      // 디시가 못 쓰는 글자·글자수는 되돌림
                                        }
                                    }
                                Text("\(text.count)/\(info.max)")
                                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    if !info.recent.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text("최근").font(.footnote).foregroundStyle(.secondary)
                                ForEach(info.recent, id: \.self) { r in
                                    Button { text = r } label: {
                                        Text(r).font(.footnote).lineLimit(1)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    Button {
                        sending = true
                        Task {
                            _ = await model.sendCommentTxtcon()
                            sending = false
                        }
                    } label: {
                        Text(sending ? "등록 중…" : "글자콘 등록")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(DCTheme.navy.opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending ? 0.4 : 1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                }
            } else if failed {
                Text("글자콘을 불러오지 못했어요").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(30)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(30)
            }
        }
        .task {
            guard info == nil else { return }
            if let r = await model.txtconOpen() {
                info = r
                if let b = r.bg.first(where: \.on) ?? r.bg.first { bg = b.hex }
                if let f = r.font.first(where: \.on) ?? r.font.first { font = f.hex }
            } else {
                failed = true
            }
        }
        .onDisappear { model.txtconClose() }
    }

    private func colorRow(_ title: String, _ colors: [TxtconColor], selected: String, pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.footnote).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            ForEach(colors, id: \.hex) { c in
                Button { pick(c.hex) } label: {
                    Circle().fill(Color(txtconHex: c.hex))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                        .overlay(Circle().stroke(DCTheme.accent, lineWidth: selected == c.hex ? 3 : 0).padding(-3))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}


/// 앱 댓글 입력창에 쓰던 글 보관 (다른 앱에 갔다 와서 페이지가 다시 불려와 입력창이 닫혀도 같은 글의 댓글칸을 다시 누르면 이어 쓰게)
@MainActor
enum CommentDraftStore {
    private static let key = "commentDrafts"
    private struct Item: Codable { var key: String; var text: String; var at: Date }

    private static var items: [Item] {
        get {
            guard let d = Profile.defaults.data(forKey: key), let l = try? JSONDecoder().decode([Item].self, from: d) else { return [] }
            return l
        }
        set { Profile.defaults.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static func pageKey(_ url: URL?) -> String {
        var c = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        c?.fragment = nil
        return c?.string ?? ""
    }

    static func draftKey(url: URL?, isReply: Bool, replyNick: String) -> String {
        var c = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        c?.fragment = nil
        return "\(c?.string ?? "")|\(isReply ? "r" : "c")|\(replyNick)"
    }

    static func save(_ s: CommentComposeSession) {
        let t = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.draftKey.isEmpty, !t.isEmpty else { return }
        var l = items.filter { $0.key != s.draftKey }
        l.insert(Item(key: s.draftKey, text: s.text, at: Date()), at: 0)
        items = Array(l.prefix(20))
    }

    /// 하루 안에 보관한 글만
    static func text(for key: String) -> String? {
        items.first { $0.key == key && Date().timeIntervalSince($0.at) < 86400 }?.text
    }

    static func remove(_ key: String) {
        guard !key.isEmpty else { return }
        items = items.filter { $0.key != key }
    }
}


/// 댓글 입력칸 (UITextView) — SwiftUI 여러 줄 입력칸은 줄이 늘어나면 하드웨어 키보드 입력이 끊기는 일이 있어 UIKit으로 만듦
/// 2~8줄 높이 안에서 줄이 늘고, 넘치면 칸 안에서 스크롤. 엔터 = 줄바꿈, ⌘엔터 = 등록
private struct CommentTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool
    let onCommandReturn: () -> Void

    final class TV: UITextView {
        var onCommandReturn: (() -> Void)?
        override var keyCommands: [UIKeyCommand]? {
            let c = UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(cmdReturn))
            c.wantsPriorityOverSystemBehavior = true
            return [c]
        }
        @objc private func cmdReturn() { onCommandReturn?() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TV {
        let v = TV()
        v.delegate = context.coordinator
        v.backgroundColor = .clear
        v.font = .preferredFont(forTextStyle: .body)
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.autocorrectionType = .default
        v.onCommandReturn = onCommandReturn
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let ph = UILabel()
        ph.text = placeholder
        ph.font = v.font
        ph.textColor = .placeholderText
        ph.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(ph)
        NSLayoutConstraint.activate([ph.topAnchor.constraint(equalTo: v.topAnchor), ph.leadingAnchor.constraint(equalTo: v.leadingAnchor)])
        context.coordinator.placeholderLabel = ph
        return v
    }

    func updateUIView(_ v: TV, context: Context) {
        v.onCommandReturn = onCommandReturn
        if v.text != text && v.markedTextRange == nil { v.text = text }
        context.coordinator.placeholderLabel?.text = placeholder
        context.coordinator.placeholderLabel?.isHidden = !v.text.isEmpty
        if isFocused, !v.isFirstResponder { DispatchQueue.main.async { v.becomeFirstResponder() } }
        if !isFocused, v.isFirstResponder { DispatchQueue.main.async { v.resignFirstResponder() } }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView v: TV, context: Context) -> CGSize? {
        let w = proposal.width ?? 300
        let line = v.font?.lineHeight ?? 20
        let h = v.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        return CGSize(width: w, height: min(max(h, line * 2), line * 8))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CommentTextView
        weak var placeholderLabel: UILabel?
        init(_ p: CommentTextView) { parent = p }
        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            placeholderLabel?.isHidden = !tv.text.isEmpty
            tv.invalidateIntrinsicContentSize()
            // 커서가 보이게 (줄이 8줄을 넘으면 칸 안에서 스크롤)
            if let r = tv.selectedTextRange { tv.scrollRectToVisible(tv.caretRect(for: r.end), animated: false) }
        }
        func textViewDidBeginEditing(_ tv: UITextView) { if !parent.isFocused { parent.isFocused = true } }
        func textViewDidEndEditing(_ tv: UITextView) { if parent.isFocused { parent.isFocused = false } }
    }
}
