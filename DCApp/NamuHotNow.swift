import SwiftUI
import Foundation

// MARK: - 아카라이브 실검챈(namuhotnow) 사유 조회
//
// 나무위키 실시간 검색어를 꾹 눌렀을 때 아카라이브 실검챈(https://arca.live/b/namuhotnow)의
// 1~2페이지에서 해당 검색어가 제목에 포함된 가장 최근 글(공지 제외)을 찾아 제목과 본문 텍스트만 보여 준다.
// 아카라이브 웹 페이지는 Cloudflare 확인이 뜰 수 있어 앱 목록/본문 API 경로를 사용한다.

/// 실검챈에서 찾은 글 (제목 + 본문 순수 텍스트)
nonisolated struct NamuHotNowPost: Sendable, Equatable {
    let id: Int
    let title: String
    let bodyText: String
    let category: String?
    let createdAt: Date?
    let isSpoilerAlert: Bool

    var webURL: URL? {
        URL(string: "https://arca.live/b/namuhotnow/\(id)")
    }
}

/// 실검챈 조회 결과
nonisolated enum NamuHotNowResult: Sendable, Equatable {
    case found(NamuHotNowPost)
    case notFound
    case failed(String)
}

/// HTML을 읽기 좋은 순수 텍스트로 정리 (태그 제거, 줄바꿈 유지, 엔티티 복원)
nonisolated enum NamuHotNowHTML {
    private static let namedEntities: [String: String] = [
        "nbsp": " ",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "amp": "&"
    ]

    /// 제목 등에서 인라인 강조 태그와 엔티티만 가볍게 제거
    static func cleanInline(_ raw: String) -> String {
        let noTags = replacing(raw, pattern: #"<[^>]+>"#, with: "")
        return decodeEntities(noTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 본문 HTML에서 단락/줄바꿈을 살린 순수 텍스트 추출
    static func plainText(from html: String) -> String {
        var text = html
        // 주석 및 비텍스트 미디어/스크립트 블록 제거
        text = replacing(text, pattern: #"<!--[\s\S]*?-->"#, with: "")
        text = replacing(
            text,
            pattern: #"<(script|style|iframe|video|audio|object)\b[^>]*>[\s\S]*?</\1\s*>"#,
            with: "\n",
            caseInsensitive: true
        )
        // 줄바꿈·단락 경계 태그를 개행으로 치환
        text = replacing(text, pattern: #"<br\s*/?>"#, with: "\n", caseInsensitive: true)
        text = replacing(
            text,
            pattern: #"</(p|div|li|tr|h[1-6]|blockquote|pre|figure|figcaption)\s*>"#,
            with: "\n",
            caseInsensitive: true
        )
        text = replacing(text, pattern: #"<hr\s*/?>"#, with: "\n", caseInsensitive: true)
        // 나머지 HTML 태그 제거 (속성 안의 '>' 포함)
        text = replacing(
            text,
            pattern: #"</?[a-zA-Z][a-zA-Z0-9]*\b(?:[^>"']|"[^"]*"|'[^']*')*>"#,
            with: ""
        )
        text = decodeEntities(text)

        // 줄별 앞뒤 공백 정리 및 과도한 빈 줄 압축 (최대 1줄 띄움)
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        var blankRun = 0
        for rawLine in normalized.components(separatedBy: "\n") {
            let trimmed = rawLine
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !lines.isEmpty && blankRun < 1 {
                    lines.append("")
                }
                blankRun += 1
            } else {
                lines.append(trimmed)
                blankRun = 0
            }
        }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private static func replacing(
        _ input: String,
        pattern: String,
        with template: String,
        caseInsensitive: Bool = false
    ) -> String {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }

    private static func decodeEntities(_ input: String) -> String {
        guard input.contains("&"),
              let regex = try? NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);"#) else {
            return input
        }
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return input }

        var result = ""
        var cursor = 0
        for match in matches {
            let fullRange = match.range
            if fullRange.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: fullRange.location - cursor))
            }
            let ref = ns.substring(with: match.range(at: 1))
            if ref.hasPrefix("#") {
                let isHex = ref.hasPrefix("#x") || ref.hasPrefix("#X")
                let digits = String(ref.dropFirst(isHex ? 2 : 1))
                if let code = UInt32(digits, radix: isHex ? 16 : 10),
                   let scalar = UnicodeScalar(code) {
                    result += String(scalar)
                } else {
                    result += ns.substring(with: fullRange)
                }
            } else if let mapped = namedEntities[ref.lowercased()] {
                result += mapped
            } else {
                result += ns.substring(with: fullRange)
            }
            cursor = fullRange.location + fullRange.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }
}

/// 아카라이브 실검챈 API 클라이언트 (1~2페이지 목록 + 글 본문 조회, 짧은 메모리 캐시)
actor NamuHotNowClient {
    static let shared = NamuHotNowClient()

    private static let listBaseURL = "https://arca.live/api/app/list/channel/namuhotnow"
    private static let viewBaseURL = "https://arca.live/api/app/view/article/namuhotnow"
    private static let userAgent = "net.umanle.arca.android.playstore/0.9.83"
    private static let deviceTokenDefaultsKey = "DCApp.NamuHotNow.DeviceToken"
    private static let cacheTTL: TimeInterval = 90

    private let session: URLSession
    private var deviceToken: String

    // 짧은 목록 캐시 (연속 롱프레스 시 불필요한 재요청 방지)
    private var cachedPage1: [ListArticle] = []
    private var cachedPage2: [ListArticle] = []
    private var cachedPage1Cursor: String?
    private var page2Loaded = false
    private var cacheDate: Date?
    private var postCache: [Int: NamuHotNowPost] = [:]

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
        self.deviceToken = Self.loadOrCreateDeviceToken()
    }

    /// 실검챈 1~2페이지에서 공지 제외 후 제목에 검색어가 포함된 가장 최근 글 1개의 제목·본문 반환
    func findReason(for keyword: String, forceRefresh: Bool = false) async -> NamuHotNowResult {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .notFound }

        if forceRefresh || !isCacheValid() {
            cachedPage1 = []
            cachedPage2 = []
            cachedPage1Cursor = nil
            page2Loaded = false
            cacheDate = nil
        }

        do {
            // 1페이지 조회
            if cachedPage1.isEmpty {
                let page1 = try await fetchListPage(before: nil)
                cachedPage1 = page1.articles
                cachedPage1Cursor = page1.nextCursor
                cacheDate = Date()
            }

            if let match = firstMatch(for: query, in: cachedPage1) {
                return try await loadPost(for: match)
            }

            // 1페이지에 없으면 2페이지 조회 (&before=<createdAt>&offset=1)
            if !page2Loaded, let cursor = cachedPage1Cursor, !cursor.isEmpty {
                let page2 = try await fetchListPage(before: cursor)
                let seenIDs = Set(cachedPage1.map(\.id))
                cachedPage2 = page2.articles.filter { !seenIDs.contains($0.id) }
                page2Loaded = true
            }

            if let match = firstMatch(for: query, in: cachedPage2) {
                return try await loadPost(for: match)
            }

            return .notFound
        } catch {
            return .failed("실시간 검색어 채널을 불러오지 못했어요.")
        }
    }

    // MARK: - 내부 조회

    private func isCacheValid() -> Bool {
        guard let cacheDate else { return false }
        return Date().timeIntervalSince(cacheDate) < Self.cacheTTL
    }

    private func firstMatch(for keyword: String, in articles: [ListArticle]) -> ListArticle? {
        for article in articles {
            guard !article.isNoticeArticle else { continue }
            let cleanTitle = NamuHotNowHTML.cleanInline(article.title)
            if cleanTitle.localizedCaseInsensitiveContains(keyword) {
                return article
            }
        }
        return nil
    }

    private func loadPost(for article: ListArticle) async throws -> NamuHotNowResult {
        if let cached = postCache[article.id] {
            return .found(cached)
        }
        let detail = try await fetchArticleDetail(id: article.id)
        let title = NamuHotNowHTML.cleanInline(detail.title ?? article.title)
        let body = NamuHotNowHTML.plainText(from: detail.content ?? "")
        let post = NamuHotNowPost(
            id: article.id,
            title: title,
            bodyText: body,
            category: detail.categoryDisplayName ?? article.categoryDisplayName,
            createdAt: Self.parseISO8601(detail.createdAt ?? article.createdAt),
            isSpoilerAlert: detail.isSpoilerAlert ?? article.isSpoilerAlert ?? false
        )
        postCache[article.id] = post
        return .found(post)
    }

    private func fetchListPage(before: String?) async throws -> (articles: [ListArticle], nextCursor: String?) {
        var components = URLComponents(string: Self.listBaseURL)
        var items = [URLQueryItem(name: "limit", value: "50")]
        if let before, !before.isEmpty {
            items.append(URLQueryItem(name: "before", value: before))
            items.append(URLQueryItem(name: "offset", value: "1"))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw URLError(.badURL) }

        let data = try await get(url)
        let response = try JSONDecoder().decode(ListResponse.self, from: data)
        if response.result == false {
            throw URLError(.userAuthenticationRequired)
        }
        let articles = response.articles ?? []
        let cursor = response.next?.before ?? articles.last?.createdAt
        return (articles, cursor)
    }

    private func fetchArticleDetail(id: Int) async throws -> ArticleDetailResponse {
        guard let url = URL(string: "\(Self.viewBaseURL)/\(id)") else { throw URLError(.badURL) }
        let data = try await get(url)
        let response = try JSONDecoder().decode(ArticleDetailResponse.self, from: data)
        if response.result == false {
            throw URLError(.userAuthenticationRequired)
        }
        return response
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(deviceToken, forHTTPHeaderField: "x-device-token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func loadOrCreateDeviceToken() -> String {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: deviceTokenDefaultsKey), saved.count == 64 {
            return saved
        }
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let token = String((0..<64).map { _ in chars[Int.random(in: 0..<chars.count)] })
        defaults.set(token, forKey: deviceTokenDefaultsKey)
        return token
    }

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    // MARK: - API 응답 모델

    private nonisolated struct ListResponse: Decodable {
        let result: Bool?
        let articles: [ListArticle]?
        let next: NextCursor?
    }

    private nonisolated struct NextCursor: Decodable {
        let before: String?
    }

    private nonisolated struct ListArticle: Decodable {
        let id: Int
        let title: String
        let category: String?
        let categoryDisplayName: String?
        let createdAt: String?
        let isNotice: Bool?
        let isSpoilerAlert: Bool?

        var isNoticeArticle: Bool {
            if isNotice == true { return true }
            if let category, category.contains("공지") { return true }
            if let display = categoryDisplayName, display.contains("공지") { return true }
            return false
        }
    }

    private nonisolated struct ArticleDetailResponse: Decodable {
        let result: Bool?
        let title: String?
        let content: String?
        let categoryDisplayName: String?
        let createdAt: String?
        let isSpoilerAlert: Bool?
    }
}

// MARK: - 실검 사유 시트 UI

/// 실검 사유 시트 띄울 때 쓰는 값
struct NamuHotNowTarget: Identifiable {
    let keyword: String
    var id: String { keyword }
}

/// 실검챈 글 제목 + 본문 텍스트를 깔끔하게 보여 주는 시트
struct NamuHotNowSheet: View {
    let keyword: String
    @Environment(\.dismiss) private var dismiss
    @State private var result: NamuHotNowResult?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("실시간 검색어 사유를 찾는 중…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let result {
                    switch result {
                    case .found(let post):
                        postView(post)
                    case .notFound:
                        EmptyStateView(
                            "실시간 검색어 채널에 글이 없습니다",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    case .failed(let message):
                        EmptyStateView {
                            Label(message, systemImage: "exclamationmark.triangle")
                        } description: {
                            Text("잠시 후 다시 시도해 주세요.")
                        } actions: {
                            Button("다시 시도") {
                                Task { await load(forceRefresh: true) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .navigationTitle(keyword)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .sheetUnderBlueBar(medium: true)
        .task { await load(forceRefresh: false) }
    }

    private func postView(_ post: NamuHotNowPost) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    if let category = post.category, !category.isEmpty {
                        Text(category)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.14), in: Capsule())
                    }
                    if post.isSpoilerAlert {
                        Text("스포일러 주의")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.14), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    if let date = post.createdAt {
                        Text(Self.dateFormatter.string(from: date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(post.title)
                    .font(.title3.weight(.bold))
                    .textSelection(.enabled)

                Divider()

                if post.bodyText.isEmpty {
                    Text("본문 텍스트가 없습니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text(post.bodyText)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let url = post.webURL {
                    Divider()
                        .padding(.top, 4)
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Label("아카라이브 원문 보기", systemImage: "arrow.up.right.square")
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private func load(forceRefresh: Bool) async {
        isLoading = true
        result = await NamuHotNowClient.shared.findReason(for: keyword, forceRefresh: forceRefresh)
        isLoading = false
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d HH:mm"
        return f
    }()
}
