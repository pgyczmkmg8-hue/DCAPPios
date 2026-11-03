import SwiftUI
import Combine

/// 앱 댓글 입력창에서 쓰는 내용 (등록은 디시 댓글 양식에 채워서 디시 페이지가 처리)
@MainActor
final class CommentComposeSession: ObservableObject, Identifiable {
    let id = UUID()
    /// 대댓글인지, 누구에게 다는지
    let isReply: Bool
    let replyNick: String
    let anon: Bool
    let nickLocked: Bool
    let hasCode: Bool
    let codeImage: UIImage?

    @Published var text: String
    @Published var nick: String
    @Published var pw: String
    @Published var code = ""
    @Published var sending = false

    init(info: [String: Any]) {
        isReply = info["reply"] as? Bool ?? false
        replyNick = info["replyNick"] as? String ?? ""
        anon = info["anon"] as? Bool ?? false
        nickLocked = info["nickLocked"] as? Bool ?? false
        hasCode = info["code"] as? Bool ?? false
        if let s = info["codeImg"] as? String, let comma = s.firstIndex(of: ","),
           let data = Data(base64Encoded: String(s[s.index(after: comma)...])) {
            codeImage = UIImage(data: data)
        } else {
            codeImage = nil
        }
        text = info["text"] as? String ?? ""
        let pageNick = info["nick"] as? String ?? ""
        let pagePw = info["pw"] as? String ?? ""
        nick = !pageNick.isEmpty ? pageNick : (AnonStore.nick.isEmpty ? "ㅇㅇ" : AnonStore.nick)
        pw = !pagePw.isEmpty ? pagePw : AnonStore.password
    }

    /// 같은 칸을 다시 눌렀는지 (입력창을 새로 만들지 않고 그대로 둠)
    func sameTarget(_ info: [String: Any]) -> Bool {
        (info["reply"] as? Bool ?? false) == isReply && (info["replyNick"] as? String ?? "") == replyNick
    }
}

/// 브라우저 화면 맨 아래에 뜨는 앱 댓글 입력창 (키보드 위)
struct CommentComposerHost: View {
    @ObservedObject var model: WebViewModel

    var body: some View {
        if let s = model.commentCompose {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { model.closeCommentCompose(sync: true) }
                CommentComposer(session: s, model: model)
                    .ignoresSafeArea(.container, edges: .trailing)   // 듀오 옆 세로 줄 자리까지 입력창을 채움 (줄은 맨 위 시계 자리라 아래쪽은 비어 있음)
                    .transition(.move(edge: .bottom))
            }
            .id(s.id)
        }
    }
}

private struct CommentComposer: View {
    @ObservedObject var session: CommentComposeSession
    let model: WebViewModel
    private enum Field: Hashable { case text, nick, pw, code }
    @FocusState private var focus: Field?
    private enum Panel { case dccon, txtcon }
    @State private var panel: Panel?

    private func togglePanel(_ p: Panel) {
        panel = panel == p ? nil : p
        focus = panel == nil ? .text : nil      // 디시콘·글자콘을 보는 동안은 키보드를 내림
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
                    TextField("코드 입력", text: $session.code)
                        .focused($focus, equals: .code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fieldBox()
                }
            }
            TextField(session.isReply ? "대댓글을 입력해주세요" : "댓글을 입력해주세요", text: $session.text, axis: .vertical)
                .lineLimit(2...8)
                .focused($focus, equals: .text)
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
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                focus = .text
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
