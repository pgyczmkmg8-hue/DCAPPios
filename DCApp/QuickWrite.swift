import SwiftUI

// MARK: - 퀵 글쓰기 (글쓰기 화면을 거치지 않고 바로 등록)
//
// 스포츠 중계처럼 빨리 쓸 때 쓴다. 첫 줄은 제목, 엔터로 줄을 나누면 둘째 줄부터 본문이 된다.
// 등록은 앱 글쓰기와 같은 방식(디시 글쓰기 양식에 채워 디시가 등록)으로 하고, 글쓰기 화면은 띄우지 않는다.
// 말머리·코드·유동 비밀번호처럼 더 필요한 게 있거나 등록이 막히면 그때 글쓰기 화면을 띄워 채워 둔다.

/// 퀵 글쓰기 요청: 글쓰기 주소로 가는 동안 기다렸다가, 글쓰기 화면 대신 이 내용으로 채워 바로 등록
struct QuickWriteRequest {
    let galleryID: String      // 글쓰기 주소에 들어가는 갤러리 ID
    let title: String
    let body: String
    let listURL: URL           // 등록 뒤 돌아갈 목록 주소
    let at: Date               // 요청 시각 (오래 지나면 무시)
}

/// 퀵 글쓰기 창이 쓸 대상 (갤러리 + 그 갤러리를 보고 있는 웹 화면)
struct QuickWriteTarget {
    let gallery: Gallery
    let model: WebViewModel
}

/// 입력 나누기: 첫 줄 = 제목, 나머지 = 본문
enum QuickWriteText {
    /// 디시 제목 글자 수 (앱 글쓰기와 같은 기준)
    static let titleRange = 2...40

    static func split(_ text: String) -> (title: String, body: String) {
        var lines = text.components(separatedBy: .newlines)
        let title = lines.removeFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, body)
    }
}

struct QuickWriteSheet: View {
    let target: QuickWriteTarget
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parts: (title: String, body: String) { QuickWriteText.split(text) }
    private var titleCount: Int { parts.title.count }
    private var canSubmit: Bool { QuickWriteText.titleRange.contains(titleCount) }

    private var footer: String {
        if titleCount == 0 { return "첫 줄에 제목을 써 주세요. 엔터로 줄을 나누면 둘째 줄부터 본문이 돼요." }
        if titleCount < QuickWriteText.titleRange.lowerBound { return "제목은 2자 이상 써 주세요 (지금 \(titleCount)자)" }
        if titleCount > QuickWriteText.titleRange.upperBound { return "제목은 40자까지 쓸 수 있어요 (지금 \(titleCount)자)" }
        return "제목 \(titleCount)자 · 둘째 줄부터는 본문이에요. 제목만 써도 등록돼요."
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("첫 줄: 제목\n둘째 줄부터: 본문")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .focused($focused)
                }
                .frame(maxHeight: .infinity)
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("\(target.gallery.name) 퀵 글쓰기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("등록") { submit() }
                        .disabled(!canSubmit)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { focused = true }
        }
        .tint(DCTheme.accent)
    }

    private func submit() {
        guard canSubmit else { return }
        target.model.quickWrite(gallery: target.gallery, title: parts.title, body: parts.body)
        dismiss()
    }
}

/// 퀵 글쓰기 등록 중: 글쓰기 화면은 띄우지 않고 가림막 + 진행 표시만 (뒤의 디시 글쓰기 페이지가 비치지 않게 불투명하게)
struct QuickWriteBusyView: View {
    var message = "퀵 글쓰기 등록 중…"
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
