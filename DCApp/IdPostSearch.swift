import SwiftUI
import Combine

/// 식별코드(고닉·반고닉) 또는 IP 앞자리(유동)로 한 갤러리의 작성글을 찾아 줌
/// 디시는 식별코드 검색을 지원하지 않아서, 글 목록을 최근 쪽부터 차례로 받아 오며 글쓴이 정보(식별코드)가 같은 글만 모음
/// 창을 닫아도 뒤에서 계속 돌고(IdPostSearcher.shared), 끝나면 화면 위 알림 칸으로 알려 줌
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
    static let shared = IdPostSearcher()

    // 입력값 (창을 닫았다 열어도 그대로)
    @Published var code = ""
    @Published var pagesText = "100"
    @Published var useDate = false
    @Published var fromDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published var toDate = Date()
    @Published private(set) var gallery: Gallery?

    // 진행·결과
    @Published var hits: [IdPostHit] = []
    @Published var scanned = 0
    @Published var total = 0            // 0이면 쪽 수를 미리 알 수 없음 (날짜로 찾을 때)
    @Published var running = false
    @Published var phase = ""
    @Published var failedPages = 0
    @Published var finishedMessage: String?
    /// 끝났는데 아직 결과를 안 본 상태 (화면 위 알림 칸을 띄움)
    @Published var unseen = false
    private var task: Task<Void, Never>?

    static let maxPages = 5000
    private static let hitCap = 1000

    var pages: Int { min(max(Int(pagesText.trimmingCharacters(in: .whitespaces)) ?? 0, 0), Self.maxPages) }

    /// 식별코드 / IP 입력을 목록에 실린 형식으로 (유동 IP는 앞 두 칸만 목록에 나옴)
    static func normalize(_ input: String) -> String {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = s.split(separator: ".")
        if parts.count >= 2, parts.allSatisfy({ Int($0) != nil }) { return parts[0] + "." + parts[1] }
        return s
    }

    var canStart: Bool {
        let hasCode = !Self.normalize(code).isEmpty
        return useDate ? true : (hasCode && pages > 0)
    }

    private func clearResults() {
        hits = []; scanned = 0; total = 0; failedPages = 0; finishedMessage = nil; phase = ""
    }

    /// 창을 열 때: 돌고 있거나 결과가 있으면 그대로 보여 주고, 아니면 새 입력으로 준비
    func prepare(gallery g: Gallery, code newCode: String) {
        unseen = false
        if running { return }
        if gallery?.id != g.id {
            clearResults()
            gallery = g
        }
        if !newCode.isEmpty, Self.normalize(newCode) != Self.normalize(code) {
            code = newCode
            clearResults()
        }
    }

    func start() {
        guard let g = gallery, canStart else { return }
        stop()
        let key = Self.normalize(code)
        clearResults(); unseen = false
        running = true
        if useDate {
            let from = Self.dayKey(of: min(fromDate, toDate)), to = Self.dayKey(of: max(fromDate, toDate))
            task = Task { [weak self] in await self?.runDates(gallery: g, key: key, from: from, to: to) }
        } else {
            let n = pages
            total = n
            task = Task { [weak self] in await self?.runPages(gallery: g, key: key, pages: n) }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if running { running = false; phase = "" }
    }

    // MARK: 쪽 수로 찾기

    private func runPages(gallery: Gallery, key: String, pages: Int) async {
        var page = 1
        let chunk = 4
        var reachedEnd = false
        while page <= pages, !Task.isCancelled, !reachedEnd {
            let range = page..<min(page + chunk, pages + 1)
            let results = await fetchGroup(gallery: gallery, range: range)
            if Task.isCancelled { break }
            for (_, rows) in results {
                guard let rows else { failedPages += 1; scanned += 1; continue }
                scanned += 1
                if rows.isEmpty { reachedEnd = true; continue }
                collect(rows, gallery: gallery, key: key, from: nil, to: nil)
            }
            hits.sort { $0.no > $1.no }
            page = range.upperBound
            try? await Task.sleep(for: .milliseconds(250))
        }
        finish(reachedEnd: reachedEnd)
    }

    // MARK: 날짜로 찾기 (시작 쪽은 이진 탐색으로 빠르게 찾음)

    private func failLocating(_ msg: String) {
        failedPages += 1
        running = false
        phase = ""
        finishedMessage = msg
        unseen = true
    }

    private func runDates(gallery: Gallery, key: String, from: Int, to: Int) async {
        var cache: [Int: [Row]] = [:]
        func rows(_ p: Int) async -> [Row]? {
            if let c = cache[p] { return c }
            guard let r = await Self.fetch(gallery: gallery, page: p) else { return nil }
            cache[p] = r
            return r
        }
        /// 이 쪽의 가장 오래된 글이 '종료일' 이하이면 true (종료일 이전 글이 이 쪽부터 시작)
        func reachesEnd(_ p: Int) async -> Bool? {
            guard let r = await rows(p) else { return nil }
            if r.isEmpty { return true }
            let keys = r.compactMap { Self.dayKey(row: $0.date) }
            guard let oldest = keys.min() else { return true }
            return oldest <= to
        }
        phase = "날짜 위치 찾는 중…"
        var first = 1
        guard let ok1 = await reachesEnd(1) else { failLocating("목록을 받지 못했어요 (요청 제한일 수 있어요). 잠시 뒤 다시 해 보세요"); return }
        if !ok1 {
            var lo = 1, hi = 2
            while true {
                if Task.isCancelled { finish(reachedEnd: false); return }
                guard let ok = await reachesEnd(hi) else { failLocating("목록을 받지 못했어요 (요청 제한일 수 있어요). 잠시 뒤 다시 해 보세요"); return }
                if ok { break }
                lo = hi
                if hi >= 200_000 { break }
                hi = min(hi * 2, 200_000)
            }
            while hi - lo > 1 {
                if Task.isCancelled { finish(reachedEnd: false); return }
                let mid = (lo + hi) / 2
                guard let ok = await reachesEnd(mid) else { failLocating("목록을 받지 못했어요 (요청 제한일 수 있어요). 잠시 뒤 다시 해 보세요"); return }
                if ok { hi = mid } else { lo = mid }
            }
            first = hi
        }
        phase = "\(first)쪽부터 확인 중…"
        // 첫 쪽부터 시작일보다 오래된 글만 나올 때까지
        var page = first
        var reachedEnd = false
        var stopped = false
        let cap = 3000
        var done = 0
        while !Task.isCancelled, !stopped, done < cap {
            let range = page..<(page + 4)
            // 이미 받아 둔 쪽은 다시 받지 않음
            let need = range.filter { cache[$0] == nil }
            if let lo = need.first, let hi = need.last {
                let results = await fetchGroup(gallery: gallery, range: lo..<(hi + 1))
                for (p, r) in results { if let r { cache[p] = r } }
            }
            if Task.isCancelled { break }
            for p in range {
                done += 1
                scanned += 1
                guard let r = cache[p] else { failedPages += 1; continue }
                if r.isEmpty { reachedEnd = true; stopped = true; break }
                collect(r, gallery: gallery, key: key, from: from, to: to)
                let keys = r.compactMap { Self.dayKey(row: $0.date) }
                if let newest = keys.max(), newest < from { stopped = true; break }   // 시작일보다 오래된 쪽만 남음
                cache[p] = nil
            }
            hits.sort { $0.no > $1.no }
            if hits.count >= Self.hitCap { stopped = true }
            page = range.upperBound
            try? await Task.sleep(for: .milliseconds(250))
        }
        finish(reachedEnd: reachedEnd, cappedPages: !stopped && done >= cap)
    }

    // MARK: 공통

    private func fetchGroup(gallery: Gallery, range: Range<Int>) async -> [(Int, [Row]?)] {
        await withTaskGroup(of: (Int, [Row]?).self) { group -> [(Int, [Row]?)] in
            for p in range { group.addTask { (p, await Self.fetch(gallery: gallery, page: p)) } }
            var out: [(Int, [Row]?)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }
        }
    }

    private func collect(_ rows: [Row], gallery: Gallery, key: String, from: Int?, to: Int?) {
        for r in rows {
            if !key.isEmpty, r.info != key { continue }
            if let from, let to {
                guard let d = Self.dayKey(row: r.date), d >= from, d <= to else { continue }
            }
            if hits.count >= Self.hitCap { return }
            let h = IdPostHit(no: r.no, title: r.title, nick: r.nick, date: r.date, comments: r.comments,
                              url: gallery.postURL(r.no))
            if !hits.contains(where: { $0.no == h.no }) { hits.append(h) }
        }
    }

    private func finish(reachedEnd: Bool, cappedPages: Bool = false) {
        running = false
        phase = ""
        if Task.isCancelled { return }
        var m = hits.isEmpty ? "찾은 글이 없어요 (\(scanned)쪽 확인)" : "\(hits.count)개 찾았어요 (\(scanned)쪽 확인)"
        if reachedEnd { m += " · 마지막 쪽까지 봤어요" }
        if cappedPages { m += " · 쪽이 너무 많아 \(scanned)쪽에서 멈췄어요" }
        if hits.count >= Self.hitCap { m += " · 결과는 \(Self.hitCap)개까지만 보여요" }
        finishedMessage = m
        unseen = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: 날짜 (목록은 오늘 글은 시각, 올해 글은 월.일, 지난해 이전은 연.월.일로 보여 줌)

    nonisolated private static var kst: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return c
    }

    nonisolated static func dayKey(of d: Date) -> Int {
        let c = kst.dateComponents([.year, .month, .day], from: d)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    nonisolated static func dayKey(row s: String, now: Date = Date()) -> Int? {
        let today = dayKey(of: now)
        if s.contains(":") { return today }
        let p = s.split(separator: ".").compactMap { Int($0) }
        if p.count == 3 { return (2000 + p[0]) * 10000 + p[1] * 100 + p[2] }
        if p.count == 2 {
            var k = (today / 10000) * 10000 + p[0] * 100 + p[1]
            if k > today { k -= 10000 }          // 올해 날짜가 미래로 나오면 작년
            return k
        }
        return nil
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

/// 식별코드(IP)로 작성글 찾기 창: 목록을 최근 쪽부터 받아 그 사람 글만 모아 보여 줌 (창을 닫아도 뒤에서 계속)
struct IdPostSearchSheet: View {
    let gallery: Gallery
    let initialCode: String
    let onOpen: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var s = IdPostSearcher.shared
    private let presets = [30, 100, 300, 1000]
    @FocusState private var codeFocused: Bool

    init(gallery: Gallery, code: String, onOpen: @escaping (URL) -> Void) {
        self.gallery = gallery
        self.initialCode = code
        self.onOpen = onOpen
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func begin() {
        hideKeyboard()
        s.start()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(s.useDate ? "식별코드 또는 IP (비우면 그날 글 전체)" : "식별코드 또는 IP", text: $s.code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($codeFocused)
                        .submitLabel(.search)
                        .onSubmit { begin() }
                    Toggle("날짜로 찾기", isOn: $s.useDate)
                    if s.useDate {
                        DatePicker("부터", selection: $s.fromDate, in: ...Date(), displayedComponents: .date)
                        DatePicker("까지", selection: $s.toDate, in: ...Date(), displayedComponents: .date)
                    } else {
                        HStack {
                            Text("검색할 쪽 수")
                            Spacer()
                            TextField("100", text: $s.pagesText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text("쪽").foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.self) { n in
                                Button { s.pagesText = String(n) } label: {
                                    Text("\(n)").font(.footnote)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(s.pages == n ? DCTheme.accent.opacity(0.18) : Color(uiColor: .tertiarySystemFill), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button {
                        if s.running { s.stop() } else { begin() }
                    } label: {
                        Text(s.running ? "중지" : "찾기").frame(maxWidth: .infinity)
                    }
                    .disabled(!s.running && !s.canStart)
                } footer: {
                    Text((s.useDate
                          ? "정한 날짜 사이의 글만 찾아요. 오래전 날짜도 앱이 그 근처 쪽을 바로 찾아가서 빨리 시작해요."
                          : "최근 쪽부터 받아 와요. 쪽당 약 30글이고 최대 \(IdPostSearcher.maxPages)쪽까지예요.")
                         + " 창을 닫아도 뒤에서 계속 찾고, 끝나면 화면 위에 알려 줘요. 유동은 IP 앞 두 칸(예: 118.235)으로 찾아요.")
                }
                if s.running || s.finishedMessage != nil || s.scanned > 0 {
                    Section {
                        if s.running {
                            if s.total > 0 {
                                ProgressView(value: Double(min(s.scanned, s.total)), total: Double(max(s.total, 1)))
                                Text("\(s.scanned)/\(s.total)쪽 확인 · \(s.hits.count)개 찾음")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text(s.phase.isEmpty ? "\(s.scanned)쪽 확인 · \(s.hits.count)개 찾음" : s.phase + (s.scanned > 0 ? " · \(s.scanned)쪽 확인 · \(s.hits.count)개" : ""))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        } else if let m = s.finishedMessage {
                            Text(m).font(.footnote).foregroundStyle(.secondary)
                        }
                        if s.failedPages > 0 {
                            Text("\(s.failedPages)쪽은 받지 못했어요 (요청 제한 등)")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
                if !s.hits.isEmpty {
                    Section("찾은 글") {
                        ForEach(s.hits) { h in
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }   // 닫아도 찾기는 뒤에서 계속
        }
        .sheetUnderBlueBar(medium: true)
        .onAppear {
            s.prepare(gallery: gallery, code: initialCode)
            // 식별코드를 아직 안 적었으면 키보드를 바로 올림 (돌고 있거나 결과가 있는 채로 다시 열면 올리지 않음)
            if s.code.trimmingCharacters(in: .whitespaces).isEmpty, !s.running, s.hits.isEmpty {
                Task { try? await Task.sleep(for: .milliseconds(450)); codeFocused = true }
            }
        }
        .onDisappear { s.unseen = false }
    }
}

/// 화면 위에 뜨는 작은 알림 칸: 뒤에서 찾는 중이거나 끝났을 때 (누르면 결과 창)
struct IdSearchPill: View {
    @ObservedObject private var s = IdPostSearcher.shared
    let open: () -> Void

    var body: some View {
        if s.running || s.unseen {
            HStack(spacing: 10) {
                Button(action: open) {
                    HStack(spacing: 8) {
                        if s.running { ProgressView().controlSize(.small) }
                        else { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        Text(label).font(.footnote.weight(.medium)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                if s.running {
                    Button { s.stop() } label: { Image(systemName: "stop.fill").font(.caption) }
                        .buttonStyle(.plain)
                } else {
                    Button { s.unseen = false } label: { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                        .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var label: String {
        if s.running {
            let p = s.total > 0 ? "\(s.scanned)/\(s.total)쪽" : (s.phase.isEmpty ? "\(s.scanned)쪽" : s.phase)
            return "작성글 찾는 중 · \(p) · \(s.hits.count)개"
        }
        return "작성글 찾기 끝 · \(s.hits.count)개 보기"
    }
}
