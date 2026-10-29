import SwiftUI
import UIKit

// MARK: - 앱 글쓰기 글자 꾸미기 (크기·색·굵게·기울임)
// 글자 칸은 UITextView(NSAttributedString)로 쓰고, 등록할 때 디시 편집기용 HTML로 바꿈

/// 지금 커서(또는 고른 글자)의 꾸미기 상태
struct RichFormat: Equatable {
    var bold = false
    var italic = false
    var size: CGFloat = RichText.baseSize
    var colorHex: String? = nil
}

enum RichText {
    static let baseSize: CGFloat = 17
    /// 글자 크기 고르기 (화면 크기 / 디시에 보낼 px)
    static let sizes: [(name: String, size: CGFloat, px: Int?)] = [
        ("작게", 13, 11), ("보통", 17, nil), ("크게", 22, 18), ("아주 크게", 28, 24),
    ]
    /// 글자 색 고르기 (nil = 기본색)
    static let colors: [(name: String, hex: String?)] = [
        ("기본", nil), ("빨강", "#e53935"), ("주황", "#fb8c00"), ("노랑", "#f9a825"), ("초록", "#43a047"),
        ("파랑", "#1e88e5"), ("남색", "#3949ab"), ("보라", "#8e24aa"), ("회색", "#9e9e9e"),
    ]

    // 앱이 따로 기억하는 값 (HTML로 바꿀 때 씀)
    static let sizeKey = NSAttributedString.Key("dcappSize")
    static let colorKey = NSAttributedString.Key("dcappColor")

    static var baseAttributes: [NSAttributedString.Key: Any] { attributes(for: RichFormat()) }

    static func attributes(for f: RichFormat) -> [NSAttributedString.Key: Any] {
        var font = UIFont.systemFont(ofSize: f.size, weight: f.bold ? .bold : .regular)
        if f.italic, let d = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) {
            font = UIFont(descriptor: d, size: f.size)
        }
        var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: f.colorHex.flatMap(color(hex:)) ?? UIColor.label]
        if f.size != baseSize { a[sizeKey] = NSNumber(value: Double(f.size)) }
        if let hex = f.colorHex { a[colorKey] = hex }
        return a
    }

    static func format(from a: [NSAttributedString.Key: Any]) -> RichFormat {
        var f = RichFormat()
        if let font = a[.font] as? UIFont {
            let t = font.fontDescriptor.symbolicTraits
            f.bold = t.contains(.traitBold)
            f.italic = t.contains(.traitItalic)
            f.size = font.pointSize
        }
        if let n = a[sizeKey] as? NSNumber { f.size = CGFloat(n.doubleValue) }
        f.colorHex = a[colorKey] as? String
        return f
    }

    nonisolated static func color(hex: String) -> UIColor? {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    static func plain(_ s: String) -> NSAttributedString { NSAttributedString(string: s, attributes: baseAttributes) }

    /// 글자 칸 → 디시 편집기 HTML (줄마다 <p>, 꾸민 부분은 <b>·<i>·<span style>)
    static func html(_ text: NSAttributedString) -> String {
        let ns = text.string as NSString
        var out = ""
        var start = 0
        while start <= ns.length {
            var end = start
            while end < ns.length, ns.character(at: end) != 10 { end += 1 }      // \n
            let line = NSRange(location: start, length: end - start)
            if line.length == 0 {
                out += "<p><br></p>"
            } else {
                var p = ""
                text.enumerateAttributes(in: line) { a, r, _ in
                    var t = esc(ns.substring(with: r))
                    let f = format(from: a)
                    if f.italic { t = "<i>" + t + "</i>" }
                    if f.bold { t = "<b>" + t + "</b>" }
                    var style: [String] = []
                    if f.size != baseSize {
                        let px: Int = sizes.first(where: { $0.size == f.size }).flatMap { $0.px } ?? Int(f.size * 0.85)
                        style.append("font-size:\(px)px")
                    }
                    if let hex = f.colorHex { style.append("color:\(hex)") }
                    if !style.isEmpty { t = "<span style=\"\(style.joined(separator: ";"))\">" + t + "</span>" }
                    p += t
                }
                out += "<p>" + p + "</p>"
            }
            if end >= ns.length { break }
            start = end + 1
        }
        return out
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "  ", with: " &nbsp;")
    }
}

/// 꾸밀 수 있는 글자 칸 (내용이 늘어나면 칸도 커짐)
struct RichTextView: UIViewRepresentable {
    let blockID: UUID
    @ObservedObject var session: NativeWriteSession
    var minLines: Int = 1

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.font = UIFont.systemFont(ofSize: RichText.baseSize)
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 11, bottom: 12, right: 11)
        tv.textContainer.lineFragmentPadding = 0      // 글자·커서가 제목·'내용' 자리표시와 같은 줄(왼쪽 16)에서 시작
        tv.tintColor = UIColor(DCTheme.accent)        // 커서·선택 색을 테마에 맞춤
        tv.typingAttributes = RichText.baseAttributes
        tv.delegate = context.coordinator
        tv.attributedText = session.rich(of: blockID)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // 사진 칸을 끌어다 놓을 때 글자 칸이 가로채지 않게 (놓기는 바깥 칸이 받음)
        tv.interactions.filter { $0 is UIDropInteraction }.forEach { tv.removeInteraction($0) }
        session.register(tv, for: blockID)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        let want = session.rich(of: blockID)
        if !tv.attributedText.isEqual(to: want) {
            let sel = tv.selectedRange
            tv.attributedText = want
            if sel.location + sel.length <= want.length { tv.selectedRange = sel }
        }
        session.register(tv, for: blockID)
        if session.focusRequest == blockID {
            DispatchQueue.main.async {
                tv.becomeFirstResponder()
                tv.selectedRange = NSRange(location: tv.attributedText.length, length: 0)
                session.focusRequest = nil
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? UIScreen.main.bounds.width
        let h = tv.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        let minH = CGFloat(minLines) * 22 + 24
        return CGSize(width: w, height: max(h, minH))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextView
        init(_ p: RichTextView) { parent = p }

        func textViewDidChange(_ tv: UITextView) {
            parent.session.setRich(tv.attributedText, of: parent.blockID)
        }
        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.session.activeBlockID = parent.blockID
            parent.session.editingRich = true
            parent.session.refreshFormat(from: tv)
        }
        func textViewDidEndEditing(_ tv: UITextView) {
            parent.session.editingRich = false
        }
        func textViewDidChangeSelection(_ tv: UITextView) {
            parent.session.refreshFormat(from: tv)
        }
    }
}
