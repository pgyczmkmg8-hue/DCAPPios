import SwiftUI

/// 처음 켰을 때(업데이트로 처음 받은 사람도) 한 번 보여주는 기능 소개
/// 끝까지 보거나 건너뛰면 다시 안 뜸. 설정 → '튜토리얼 다시 보기'로 다시 볼 수 있음
enum Tutorial {
    static let seenKey = "tutorialSeenV3"
}

private struct TutorialPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let lines: [String]
}

struct TutorialView: View {
    /// 끝나거나 건너뛰면 (본 것으로 저장한 뒤) 부름. 인자 openAbout: '시작하기'로 끝냈으면 true (버전 정보/업데이트 화면을 열어 줌), 건너뛰기면 false
    let onFinish: (_ openAbout: Bool) -> Void

    @AppStorage(Tutorial.seenKey, store: Profile.defaults) private var seen = false
    @State private var index = 0

    private let pages: [TutorialPage] = [
        TutorialPage(icon: "hand.wave", title: "디캡에 오신 걸 환영해요",
                     lines: ["디시인사이드 모바일을 더 편하게 보도록 만든 앱이에요.",
                             "주요 기능을 차례로 짧게 소개할게요.",
                             "건너뛰기를 누르면 언제든 끝낼 수 있어요."]),
        TutorialPage(icon: "rectangle.bottomthird.inset.filled", title: "컨트롤바",
                     lines: ["계정 · 메뉴 · 개념글 · 검색 · 글쓰기 버튼이 있어요.",
                             "설정 → 컨트롤바에서 가로로 쓸 때와 세로로 쓸 때의 배치(하단 바 · 오른쪽 막대)를 따로 골라요.",
                             "막대를 옆으로 밀면 둘째 칸(설정 · 차단 · 메모 등)이 나와요.",
                             "버튼 순서, 접기, 스크롤할 때 자동 숨기기도 설정에서 바꿔요."]),
        TutorialPage(icon: "magnifyingglass", title: "나무위키 검색",
                     lines: ["막대를 옆으로 밀어 둘째 칸을 열고 '나무위키'를 누르면 검색 창이 열려요.",
                             "검색어를 비워 두면 나무위키 실시간 검색어가 순위대로 나와요.",
                             "실시간 검색어를 왼쪽으로 밀면 왜 실검인지 사유를 바로 볼 수 있어요.",
                             "글자를 입력하면 연관 검색어가 나와요. 골라서 바로 열거나 검색 버튼을 누르세요.",
                             "나무위키는 앱 안의 창에서 열려요. 닫으면 보던 디시 화면이 그대로 남아요."]),
        TutorialPage(icon: "line.3.horizontal.decrease.circle", title: "말머리 · 필터",
                     lines: ["글 목록 위에 말머리 탭이 고정돼요. 옆으로 밀어서 골라요.",
                             "말머리 줄 왼쪽의 깔때기 버튼으로 필터를 열어요.",
                             "특정 말머리만 골라 보기, 읽은 글 · 안 읽은 글, 추천 · 댓글 · 조회 수 조건을 쓸 수 있어요.",
                             "말머리가 없는 갤러리는 상단바의 깔때기를 써요. 필터는 갤러리마다 따로 저장돼요."]),
        TutorialPage(icon: "arrow.down.to.line", title: "다음 페이지 자동으로",
                     lines: ["목록 맨 아래에 가까워지면 다음 페이지를 알아서 이어 붙여요.",
                             "페이지가 바뀌는 곳에 'N페이지' 구분선이 나와요.",
                             "내려가는 동안 위에는 지금 보는 페이지 번호가 고정돼요.",
                             "불러오기가 멈추면 '더보기' 버튼을 눌러 주세요."]),
        TutorialPage(icon: "person.text.rectangle", title: "식별코드 · IP로 작성글 찾기",
                     lines: ["닉네임을 누르거나 글·댓글을 길게 누르면 메뉴가 열려요. 여기서 식별코드(고닉)나 IP(유동)로 작성글을 찾아요.",
                             "검색 버튼의 검색 창에서도 식별코드나 IP를 적고 찾을 수 있어요.",
                             "디시에는 이 검색이 없어서, 앱이 최근 글 목록을 여러 쪽 받아 같은 사람의 글만 모아 보여 줘요.",
                             "유동은 IP 앞 두 칸으로 찾아요. 시간이 조금 걸리고, 창을 닫아도 뒤에서 계속 모아요."]),
        TutorialPage(icon: "hand.raised", title: "차단 · 메모",
                     lines: ["닉네임이나 IP를 누르면 차단하거나 메모를 남길 수 있어요.",
                             "글·댓글을 길게 누르면 작성자 차단, 디시콘 차단, 메모, 갤로그 가기를 골라요.",
                             "차단한 글은 '차단됨 표시'로 자리를 남기거나 '완전히 숨김'으로 흔적 없이 가릴 수 있어요.",
                             "키워드 차단도 있어요. 쉼표로 여러 단어를 넣으면 모두 들어 있는 글만 가려요."]),
        TutorialPage(icon: "text.magnifyingglass", title: "고급 차단 · 우회 막기",
                     lines: ["고급 차단: 특정 사람(IP · 식별코드 · 닉네임)이 쓴 글에 입력한 단어가 모두 들어 있을 때만 가려요.",
                             "특수문자 끼워넣기 무시: '야$미@@큐레'처럼 특수문자를 끼운 글도 가려요.",
                             "공백 끼워넣기 무시: '야 미 큐 레'처럼 띄어 쓴 글도 가려요.",
                             "본문 사진은 길게 눌러 가리고, ⋯ → 요소 숨기기로 화면의 특정 부분을 탭해서 숨길 수 있어요."]),
        TutorialPage(icon: "photo.on.rectangle", title: "글 읽기 · 사진 · 댓글",
                     lines: ["사진을 누르면 크게 보고 좌우로 넘겨요. 길게 누르면 원본을 저장하고, 글 속 사진 전체를 한꺼번에 저장할 수도 있어요.",
                             "세로 컨트롤바를 쓰면 댓글 입력칸이 화면 아래에 고정돼요.",
                             "추천·비추천이 '다음에 다시 시도'로 실패하면 앱이 알아서 다시 눌러요 (최대 20번).",
                             "댓글 보안 확인(Cloudflare 체크)이 나오면 앱이 기다렸다가 이어서 처리해요."]),
        TutorialPage(icon: "rectangle.split.2x1", title: "메뉴 · 한손 모드 · 듀오",
                     lines: ["컨트롤바의 메뉴 칸에서 방문한 갤러리, 즐겨찾기, 보관함, 읽은 글을 봐요.",
                             "글 목록에서 오른쪽으로 쓸어도 갤러리 창이 열려요 (설정에서 끌 수 있어요).",
                             "갤러리 이름을 0.5초 길게 누르면 한손 모드예요. 위쪽 핸들을 맨 위로 끌어 잠깐 버티면 해제돼요.",
                             "듀오를 펼치면 목록과 글을 나란히 봐요. 접으면 보던 글을 그대로 이어 봐요."]),
        TutorialPage(icon: "square.and.pencil", title: "글쓰기 · 계정 · 잠금",
                     lines: ["글쓰기 화면에서 글자 꾸미기, 사진, 디시콘을 넣어요. 쓰던 글은 사진까지 자동으로 임시저장돼요.",
                             "자짤을 등록해 두면 글쓰기에 자동으로 붙어요.",
                             "여러 계정을 저장해 두고 한 번에 바꿔요.",
                             "Face ID · Touch ID로 앱을 잠그고, 안 되면 기기 암호로 풀어요. ⋮ 메뉴에서 다크모드를 켜고 꺼요."]),
        TutorialPage(icon: "arrow.down.app", title: "업데이트 · 다시 보기",
                     lines: ["새 버전이 나오면 앱을 열 때 알려 줘요. GitLab과 GitHub 릴리즈를 함께 확인해요.",
                             "Feather · SideStore · LiveContainer로 바로 설치할 수 있어요.",
                             "설정 맨 아래의 '튜토리얼 다시 보기'로 이 안내를 언제든 다시 볼 수 있어요."]),
        TutorialPage(icon: "hand.tap", title: "이미지를 계속 터치해 보세요",
                     lines: ["설정 맨 아래의 '버전 정보/업데이트 확인' 화면에 사진이 있어요.",
                             "사진을 누르면 다른 사진으로 바뀌고 작은 축하 효과가 나와요.",
                             "여러 번 계속 눌러 보세요.",
                             "계속 터치하다 보면 무언가 일어날지도?"]),
    ]

    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("건너뛰기") { finish(openAbout: false) }
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

            dots.padding(.bottom, 16)

            Button {
                if isLast { finish(openAbout: true) } else { withAnimation { index += 1 } }
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

    /// 한 장의 내용. 줄이 많아도 잘리지 않도록 스크롤됨 (작은 화면에서도 끝까지 읽을 수 있게)
    private func pageView(_ page: TutorialPage) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: page.icon)
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(DCTheme.accent)
                    .frame(width: 104, height: 104)
                    .background(DCTheme.accent.opacity(0.12), in: Circle())
                Text(page.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 11) {
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
            }
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
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

    private func finish(openAbout: Bool) {
        seen = true
        onFinish(openAbout)
    }
}

/// 튜토리얼 '시작하기' 뒤에 여는 버전 정보/업데이트 화면 (닫기 버튼 포함)
struct TutorialAboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AboutView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { dismiss() }
                    }
                }
        }
    }
}
