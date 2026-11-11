import SwiftUI
import Combine

/// 식별코드(고닉·반고닉) 또는 IP 앞자리(유동)로 한 갤러리의 작성글을 찾아 줌
/// 디시는 식별코드 검색을 지원하지 않아서, 글 목록을 최근 쪽부터 차례로 받아 오며 글쓴이 정보(식별코드)가 같은 글만 모음
/// (갤스코프 유저스크립트와 같은 방식: 목록 여러 쪽을 받아 식별코드로 걸러냄)
struct IdSearchTarget: Identifiable {
    let id = UUID()
    let gallery: Gallery
    let code: String
}

struct IdPostHit: Identifiable, Hashable {
    let no: Int
    let title: String
    let nick: String
    let date: String
    let comments: Int
    let url: URL
    var id: Int { no }
}

@MainActor
final class IdPostSearcher: ObservableObject {
    @Published var hits: [IdPostHit] = []
    @Published var scanned = 0
    @Published var total = 0
    @Published var running = false
    @Published var failedPages = 0
    @Published var finishedMessage: String?
    private var task: Task<Void, Never>?

    /// 식별코드 / IP 입력을 목록에 실린 형식으로 (유동 IP는 앞 두 칸만 목록에 나옴)
    static func normalize(_ input: String) -> String {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = s.split(separator: ".")
        if parts.count >= 2, parts.allSatisfy({ Int($0) != nil }) { return parts[0] + "." + parts[1] }
        return s
    }

    func start(gallery: Gallery, code: String, pages: Int) {
        stop()
        let key = Self.normalize(code)
        guard !key.isEmpty else { return }
        hits = []; scanned = 0; failedPages = 0; total = pages; finishedMessage = nil
        running = true
        task = Task { [weak self] in
            await self?.run(gallery: gallery, key: key, pages: pages)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if running { running = false }
    }

    private func run(gallery: Gallery, key: String, pages: Int) async {
        var page = 1
        let chunk = 4
        var reachedEnd = false
        while page <= pages, !Task.isCancelled, !reachedEnd {
            let range = page..<min(page + chunk, pages + 1)
            let results = await withTaskGroup(of: (Int, [Row]?).self) { group -> [(Int, [Row]?)] in
                for p in range { group.addTask { (p, await Self.fetch(gallery: gallery, page: p)) } }
                var out: [(Int, [Row]?)] = []
                for await r in group { out.append(r) }
                return out.sorted { $0.0 < $1.0 }
            }
            if Task.isCancelled { break }
            for (_, rows) in results {
                guard let rows else { failedPages += 1; scanned += 1; continue }
                scanned += 1
                if rows.isEmpty { reachedEnd = true; continue }
                for r in rows where r.info == key {
                    let h = IdPostHit(no: r.no, title: r.title, nick: r.nick, date: r.date, comments: r.comments,
                                      url: gallery.postURL(r.no))
                    if !hits.contains(where: { $0.no == h.no }) { hits.append(h) }
                }
            }
            hits.sort { $0.no > $1.no }
            page = range.upperBound
            try? await Task.sleep(for: .milliseconds(250))
        }
        running = false
        if Task.isCancelled { return }
        finishedMessage = hits.isEmpty ? "찾은 글이 없어요 (\(scanned)쪽 확인)" : "\(hits.count)개 찾았어요 (\(scanned)쪽 확인)"
        if reachedEnd { finishedMessage = (finishedMessage ?? "") + " · 마지막 쪽까지 봤어요" }
    }

    struct Row { let no: Int; let title: String; let nick: String; let info: String; let date: String; let comments: Int }

    /// 목록 한 쪽 받기 (429면 잠깐 쉬었다 다시, 3번까지). 실패하면 nil
    nonisolated private static func fetch(gallery: Gallery, page: Int) async -> [Row]? {
        var comps = URLComponents(url: gallery.url, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "page", value: String(page))]
        guard let url = comps?.url else { return nil }
        for attempt in 0..<3 {
            if Task.isCancelled { return nil }
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            req.setValue("https://m.dcinside.com/", forHTTPHeaderField: "Referer")
            req.timeoutInterval = 15
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse {
                let html = String(decoding: data, as: UTF8.self)
                if http.statusCode == 200, !html.contains("너무 많은 요청으로") { return parse(html, gallery: gallery) }
                if http.statusCode != 429, !html.contains("너무 많은 요청으로") { return nil }
            }
            try? await Task.sleep(for: .milliseconds(900 * (attempt + 1)))
        }
        return nil
    }

    nonisolated static func parse(_ html: String, gallery: Gallery) -> [Row] {
        func first(_ pattern: String, in s: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            return (1..<m.numberOfRanges).map { i in
                Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
            }
        }
        var out: [Row] = []
        // 글 한 줄은 <div class="gall-detail-lnktb">로 시작 → 그 표시로 잘라 한 줄씩 읽음 (식별코드가 든 숨은 칸이 줄 끝에 있음)
        for row in html.components(separatedBy: #"<div class="gall-detail-lnktb">"#).dropFirst() {
            guard let no = first(#"href="[^"]*/(\d+)(?:\?[^"]*)?(?:#[^"]*)?"\s+class="lt""#, in: row)?.first.flatMap({ Int($0) }) else { continue }
            let title = first(#"<span class="subjectin">(.*?)</span>"#, in: row)?.first ?? ""
            let nick = first(#"data-name="(.*?)"\s+data-info="(.*?)""#, in: row)?[0] ?? ""
            let info = first(#"data-name="(.*?)"\s+data-info="(.*?)""#, in: row)?[1] ?? ""
            let date = first(#"</li>\s*<li>([^<]*)</li>\s*<li>\s*조회"#, in: row)?.first ?? ""
            let cm = first(#"<span class="ct\s*">(\d+)"#, in: row)?.first.flatMap { Int($0) } ?? 0
            out.append(Row(no: no, title: unescape(title).trimmingCharacters(in: .whitespacesAndNewlines),
                           nick: unescape(nick), info: unescape(info), date: date, comments: cm))
        }
        return out
    }

    nonisolated private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }
}

extension Gallery {
    /// 글 주소 (모바일)
    func postURL(_ no: Int) -> URL {
        URL(string: url.absoluteString + "/\(no)") ?? url
    }
}

/// 식별코드(IP)로 작성글 찾기 창: 목록을 최근 쪽부터 N쪽 받아 그 사람 글만 모아 보여 줌
struct IdPostSearchSheet: View {
    let gallery: Gallery
    let onOpen: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searcher = IdPostSearcher()
    @State private var code: String
    @State private var pages = 100
    private let choices = [30, 100, 300, 1000]

    init(gallery: Gallery, code: String, onOpen: @escaping (URL) -> Void) {
        self.gallery = gallery
        self.onOpen = onOpen
        _code = State(initialValue: code)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func begin() {
        hideKeyboard()
        searcher.start(gallery: gallery, code: code, pages: pages)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("식별코드 또는 IP", text: $code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { begin() }
                    Picker("검색 범위", selection: $pages) {
                        ForEach(choices, id: \.self) { Text("최근 \($0)쪽").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button {
                        if searcher.running { searcher.stop() } else { begin() }
                    } label: {
                        Text(searcher.running ? "중지" : "찾기").frame(maxWidth: .infinity)
                    }
                    .disabled(!searcher.running && IdPostSearcher.normalize(code).isEmpty)
                } footer: {
                    Text("디시는 식별코드 검색이 없어서, 글 목록을 최근 쪽부터 받아 오며 같은 식별코드의 글만 모아요. 쪽이 많을수록 오래 걸려요. 유동은 IP 앞 두 칸(예: 118.235)으로 찾아요.")
                }
                if searcher.total > 0 {
                    Section {
                        if searcher.running {
                            ProgressView(value: Double(min(searcher.scanned, searcher.total)), total: Double(max(searcher.total, 1)))
                            Text("\(searcher.scanned)/\(searcher.total)쪽 확인 · \(searcher.hits.count)개 찾음")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if let m = searcher.finishedMessage {
                            Text(m).font(.footnote).foregroundStyle(.secondary)
                        }
                        if searcher.failedPages > 0 {
                            Text("\(searcher.failedPages)쪽은 받지 못했어요 (요청 제한 등)")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
                if !searcher.hits.isEmpty {
                    Section("찾은 글") {
                        ForEach(searcher.hits) { h in
                            Button {
                                dismiss()
                                onOpen(h.url)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(h.title.isEmpty ? "(제목 없음)" : h.title).lineLimit(2)
                                    Text("\(h.nick) · \(h.date)" + (h.comments > 0 ? " · 댓글 \(h.comments)" : ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("작성글 찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { searcher.stop(); dismiss() } }
            }
        }
        .sheetUnderBlueBar(medium: true)
        .onDisappear { searcher.stop() }
    }
}
