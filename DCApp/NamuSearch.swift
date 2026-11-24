import SwiftUI

// MARK: - 나무위키 검색 (컨트롤바 둘째 칸 '나무위키')
//
// 검색어를 입력하면 https://namu.wiki/Search?q=<검색어> 를 앱 안의 WKWebView 시트(NamuWebSheet)로 연다.
// 검색어가 비어 있으면 실시간 검색어, 입력 중이면 연관 검색어를 보여 준다 (NamuSuggest.swift가 읽어 옴).
// 완료를 누르면 시트만 닫히고 보던 디시 화면이 그대로 남는다 (디시 웹뷰는 건드리지 않음).

/// 나무위키 주소
enum NamuWiki {
    /// 검색 결과 주소
    static func searchURL(_ query: String) -> URL? {
        // 검색어의 & + = # ? 는 주소 구분자라서 퍼센트 인코딩해서 넘김
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://namu.wiki/Search?q=\(encoded)")
    }

    /// 문서 주소 (제목 그대로, 슬래시는 문서 계층이라 살려 둠)
    static func documentURL(_ title: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://namu.wiki/w/\(encoded)")
    }
}

/// 나무위키 시트를 띄울 때 쓰는 값 (주소마다 새 웹뷰 모델을 만들어 둠)
struct NamuTarget: Identifiable {
    let url: URL
    let model: NamuWebModel

    init(url: URL) {
        self.url = url
        self.model = NamuWebModel(url: url)
    }

    var id: URL { url }
}

/// 나무위키 검색어 입력 시트: 실시간 검색어(빈 칸) / 연관 검색어(입력 중)
struct NamuSearchInputSheet: View {
    /// 열 주소를 넘김 (검색 결과 또는 문서). 시트는 이 뒤에 닫힘
    let onOpen: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var ranking: [String] = []
    @State private var rankingLoaded = false
    @State private var suggestions: [String] = []
    @State private var suggesting = false
    @State private var suggestTask: Task<Void, Never>?
    @State private var reasonTarget: NamuHotNowTarget?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("검색어", text: $text)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { submit() }
                } footer: {
                    Text("나무위키에서 검색한 결과를 앱 안에서 열어요. 닫으면 보던 화면으로 돌아와요.")
                }

                if trimmed.isEmpty {
                    Section {
                        if ranking.isEmpty {
                            Text(rankingLoaded ? "실시간 검색어를 불러오지 못했어요" : "불러오는 중…")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(ranking.enumerated()), id: \.offset) { index, word in
                            Button { open(word) } label: {
                                HStack(spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18, alignment: .leading)
                                    Text(word).foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    showReason(for: word)
                                } label: {
                                    Label("사유", systemImage: "questionmark.circle")
                                }
                                .tint(.accentColor)
                            }
                            .accessibilityAction(named: "실시간 검색어 사유 보기") { showReason(for: word) }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("실시간 검색어")
                            Text("실시간 검색어를 왼쪽으로 밀면 실시간 검색어인 사유를 보여줍니다")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                } else {
                    Section {
                        if suggestions.isEmpty {
                            Text(suggesting ? "찾는 중…" : "연관 검색어가 없어요")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(suggestions, id: \.self) { word in
                            Button { open(word) } label: {
                                Label(word, systemImage: "magnifyingglass")
                                    .foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        Text("연관 검색어")
                    }

                    Section {
                        Button { submit() } label: {
                            Label("'\(trimmed)' 나무위키 검색", systemImage: "text.magnifyingglass")
                        }
                    }
                }
            }
            .navigationTitle("나무위키 검색")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("검색") { submit() }
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear {
                Task { try? await Task.sleep(for: .milliseconds(80)); focused = true }
            }
            .task {
                ranking = await NamuSuggestBridge.shared.ranking()
                rankingLoaded = true
            }
            .onChangeCompat(of: text) { _, _ in scheduleSuggest() }
            .onDisappear { suggestTask?.cancel() }
            .sheet(item: $reasonTarget, onDismiss: {
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    focused = true
                }
            }) { target in
                NamuHotNowSheet(keyword: target.keyword)
            }
        }
        .sheetUnderBlueBar(medium: true)
    }

    /// 입력이 멈춘 뒤 300ms 후에 연관 검색어를 받음 (이전 요청은 취소, 늦게 온 결과는 버림)
    private func scheduleSuggest() {
        suggestTask?.cancel()
        let q = trimmed
        guard !q.isEmpty else {
            suggestions = []
            suggesting = false
            return
        }
        suggesting = true
        suggestTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let result = await NamuSuggestBridge.shared.suggestions(for: q)
            guard !Task.isCancelled, q == trimmed else { return }
            suggestions = result
            suggesting = false
        }
    }

    /// 검색 결과 열기 (검색어 확인)
    private func submit() {
        let q = trimmed
        guard !q.isEmpty, let url = NamuWiki.searchURL(q) else { return }
        open(url)
    }

    /// 목록 항목(문서 또는 검색 결과)을 열고 시트를 닫음
    private func open(_ word: String) {
        guard let url = NamuWiki.documentURL(word) else { return }
        open(url)
    }

    private func open(_ url: URL) {
        onOpen(url)
        dismiss()
    }

    /// 실시간 검색어 꾹 누르기: 아카라이브 실검챈에서 사유 글 조회 시트 표시
    private func showReason(for word: String) {
        focused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        reasonTarget = NamuHotNowTarget(keyword: word)
    }
}
