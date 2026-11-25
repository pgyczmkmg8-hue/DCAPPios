import SwiftUI
import UIKit

/// 댓글을 길게 눌렀을 때 페이지에서 넘어오는 댓글 내용
struct CommentTextItem: Identifiable {
    let id = UUID()
    let nick: String
    let text: String
    /// 누른 위치 (웹 화면 안 좌표) — '텍스트 선택' 버튼을 그 근처에 띄움
    var point: CGPoint = .zero
}

/// 댓글 내용만 따로 띄우는 화면 — 글자를 바로 선택·복사할 수 있음 (뒤 화면은 흐리게, 닫기 버튼으로만 닫힘)
/// 안의 링크: 디시 주소는 앱 안에서 열고(onOpenLink), 그 밖의 주소는 기본 웹브라우저로
struct CommentTextViewer: View {
    @ObservedObject var fonts = FontStore.shared
    let item: CommentTextItem
    let onOpenLink: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var handle = SelectionHandle()

    var body: some View {
        ZStack {
            // 바깥을 두 번 누르면 선택만 풀림 (화면은 닫히지 않음 — 닫기 버튼으로만 닫힘)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { handle.clearSelection() }
            VStack(spacing: 14) {
                if !item.nick.isEmpty {
                    Text(item.nick)
                        .font(fonts.styleFont(.footnote, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                }
                SelectableText(text: item.text, handle: handle, onOpenLink: onOpenLink)
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = item.text
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        copied = true
                    } label: {
                        Label(copied ? "복사했어요" : "전체 복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(fonts.styleFont(.subheadline, weight: .semibold))
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    }
                    Button { dismiss() } label: {
                        Text("닫기")
                            .font(fonts.styleFont(.subheadline, weight: .semibold))
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 560)
        }
    }
}

/// 글자 칸의 선택을 바깥(SwiftUI)에서 풀기 위한 손잡이
final class SelectionHandle {
    weak var textView: UITextView?
    func clearSelection() {
        guard let tv = textView else { return }
        tv.selectedRange = NSRange(location: tv.selectedRange.location, length: 0)
    }
}

/// 읽기 전용 글자 칸 — 열리면 전체가 선택돼 있어서 바로 복사 메뉴를 쓸 수 있고, 손가락으로 선택 범위를 끌어 바꿀 수도 있음
private struct SelectableText: UIViewRepresentable {
    let text: String
    let handle: SelectionHandle
    let onOpenLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onOpenLink) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let onOpenLink: (URL) -> Void
        init(_ f: @escaping (URL) -> Void) { onOpenLink = f }
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            guard interaction == .invokeDefaultAction else { return true }
            if ["http", "https"].contains(URL.scheme?.lowercased() ?? ""), WebViewModel.isDCURL(URL) {
                onOpenLink(URL)        // 디시 주소는 앱 안에서
                return false
            }
            return true                // 그 밖의 주소는 시스템 기본(사파리)
        }
    }

    final class TV: UITextView {
        private var didSelect = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !didSelect else { return }
            didSelect = true
            // 열리는 애니메이션이 끝난 뒤에 전체 선택 (도중에 선택하면 첫 끌기가 버벅임). 그 사이 사용자가 직접 선택했으면 건드리지 않음
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.window != nil else { return }
                self.becomeFirstResponder()
                if self.selectedRange.length == 0 {
                    self.selectedRange = NSRange(location: 0, length: (self.text as NSString).length)
                }
            }
        }
    }

    func makeUIView(context: Context) -> TV {
        let v = TV()
        v.isEditable = false
        v.isSelectable = true
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.font = .systemFont(ofSize: 18)
        v.adjustsFontForContentSizeCategory = true
        v.dataDetectorTypes = .link
        v.delegate = context.coordinator
        v.text = text
        handle.textView = v
        return v
    }

    func updateUIView(_ v: TV, context: Context) {
        if v.text != text { v.text = text }
        // 길면 칸 안에서 스크롤 (레이아웃 계산 중이 아니라 여기서 한 번만 정함)
        let w = v.bounds.width > 1 ? v.bounds.width : UIScreen.main.bounds.width - 70
        let need = v.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height > UIScreen.main.bounds.height * 0.5
        if v.isScrollEnabled != need { v.isScrollEnabled = need }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView v: TV, context: Context) -> CGSize? {
        let w = proposal.width ?? 320
        let h = v.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        let maxH = UIScreen.main.bounds.height * 0.5
        return CGSize(width: w, height: min(h, maxH))
    }
}
