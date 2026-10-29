import SwiftUI

/// 처음 켰을 때(업데이트로 처음 받은 사람도) 한 번 보여주는 기능 소개
/// 끝까지 보거나 건너뛰면 다시 안 뜸. 설정 → '튜토리얼 다시 보기'로 다시 볼 수 있음
enum Tutorial {
    static let seenKey = "tutorialSeen"
}

private struct TutorialPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let lines: [String]
}

struct TutorialView: View {
    /// 끝나거나 건너뛰면 (본 것으로 저장한 뒤) 부름
    let onFinish: () -> Void

    @AppStorage(Tutorial.seenKey) private var seen = false
    @State private var index = 0

    private let pages: [TutorialPage] = [
        TutorialPage(icon: "hand.wave", title: "디캡에 오신 걸 환영해요",
                     lines: ["디시인사이드 모바일을 더 편하게 보도록 만든 앱이에요.",
                             "주요 기능을 짧게 알려 드릴게요."]),
        TutorialPage(icon: "rectangle.bottomthird.inset.filled", title: "하단 바",
                     lines: ["계정 · 메뉴 · 개념글 · 검색 · 글쓰기를 아래에서 바로 눌러요.",
                             "개념글 버튼으로 개념글 ⇄ 전체글을 오가요.",
                             "막대를 옆으로 밀면 둘째 칸(설정 · 차단 · 메모 등)이 나와요.",
                             "버튼 배치·접기·위치는 설정에서 바꿀 수 있어요."]),
        TutorialPage(icon: "square.stack", title: "메뉴",
                     lines: ["방문한 갤러리, 즐겨찾기, 보관함, 읽은 글을 한곳에서 봐요.",
                             "갤러리 이름이나 ID로 바로 찾아 들어가요.",
                             "글 목록에서 오른쪽으로 쓸어도 메뉴가 열려요."]),
        TutorialPage(icon: "photo.on.rectangle", title: "글 읽기",
                     lines: ["사진을 누르면 크게 보고, 좌우로 넘기고, 원본으로 저장해요.",
                             "화면을 오른쪽으로 쓸면 뒤로 가요.",
                             "글 목록 아래 큰 버튼으로 페이지를 옮겨요."]),
        TutorialPage(icon: "rectangle.bottomhalf.inset.filled", title: "한손 모드",
                     lines: ["화면 위쪽을 비우고 아래쪽에서만 쓸 수 있어요.",
                             "갤러리 이름을 0.5초 길게 누르면 켜고 꺼요.",
                             "위쪽 빈 부분의 핸들을 맨 위로 끌면 해제돼요."]),
        TutorialPage(icon: "square.and.pencil", title: "글쓰기",
                     lines: ["앱 글쓰기 화면에서 글자 꾸미기, 사진, 디시콘을 넣어요.",
                             "쓰던 글은 사진까지 자동으로 임시저장돼요.",
                             "자짤을 등록해 두면 글쓰기에 자동으로 붙어요."]),
        TutorialPage(icon: "hand.raised", title: "차단 · 메모",
                     lines: ["닉네임을 누르면 차단하거나 메모를 남길 수 있어요.",
                             "키워드·디시콘 차단, 화면 요소 숨기기도 있어요.",
                             "차단한 글은 접거나 완전히 숨길 수 있어요."]),
        TutorialPage(icon: "person.2", title: "계정 · 화면",
                     lines: ["여러 계정을 저장해 두고 한 번에 바꿔요.",
                             "Face ID / Touch ID로 앱을 잠글 수 있어요.",
                             "⋮ 메뉴에서 다크모드를 켜고 꺼요."]),
        TutorialPage(icon: "arrow.down.app", title: "업데이트",
                     lines: ["새 버전이 나오면 앱을 열 때 알려 줘요.",
                             "Feather · SideStore · LiveContainer로 바로 설치할 수 있어요.",
                             "설정 → 튜토리얼 다시 보기에서 이 안내를 다시 볼 수 있어요."]),
    ]

    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("건너뛰기") { finish() }
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
            }
            .padding(.horizontal, 20)
            .frame(height: 44)

            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                    pageView(page).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            dots.padding(.bottom, 20)

            Button {
                if isLast { finish() } else { withAnimation { index += 1 } }
            } label: {
                Text(isLast ? "시작하기" : "다음")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(DCTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: 480)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    private func pageView(_ page: TutorialPage) -> some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image(systemName: page.icon)
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(DCTheme.accent)
                .frame(width: 120, height: 120)
                .background(DCTheme.accent.opacity(0.12), in: Circle())
            Text(page.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(page.lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(DCTheme.accent).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        Text(line)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? DCTheme.accent : Color.secondary.opacity(0.3))
                    .frame(width: i == index ? 20 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: index)
    }

    private func finish() {
        seen = true
        onFinish()
    }
}
