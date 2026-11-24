import SwiftUI
import Combine

// MARK: - 디시 갤러리 실시간 검색
//
// 디시 모바일 갤러리 검색 탭(/search/gall_name)이 쓰는 엔드포인트를 그대로 씀.
//   POST https://m.dcinside.com/search_gall
//   form: keyword=<검색어>&type=A(전체)&sort_type=rank
//   헤더: X-Requested-With: XMLHttpRequest, Referer: 검색 페이지 주소 (없으면 "잘못된 접근" 응답)
//   응답: [{"title","type","id","rank","total_post","new_post","member_count","url"}, ...]
//     type: G 정식 · M 마이너 · N 미니 · P 인물
//     id: 미니는 "mi$갤ID", 인물은 "pr$갤ID" (DCGalleryID.bare로 뗌)

/// 갤러리 검색 결과 한 줄
struct GalleryHit: Identifiable, Hashable {
    let title: String
    /// 디시 응답의 type (G·M·N·P)
    let type: String
    /// 디시 응답의 id (앞머리 mi$·pr$ 포함)
    let rawID: String
    let rank: Int?
    let totalPost: Int?

    var id: String { type + ":" + rawID }
    /// 앞머리를 뗀 갤러리 ID
    var galleryID: String { DCGalleryID.bare(rawID) }

    var kind: GalleryKind {
        switch type {
        case "N": .mini
        case "P": .person
        default: .board      // 정식 G · 마이너 M 은 모바일에서 둘 다 /board/{id}
        }
    }

    /// 목록에 붙이는 종류 이름 (정식/마이너/미니/인물)
    var typeLabel: String {
        switch type {
        case "M": "마이너"
        case "N": "미니"
        case "P": "인물"
        default: "정식"
        }
    }

    var gallery: Gallery { Gallery(galleryID: galleryID, name: title, kind: kind) }
}

/// 한 줄이 잘못돼도 나머지 결과는 살리려고, 줄마다 따로 해석
private struct GalleryHitWire: Decodable {
    let title: String?
    let type: String?
    let id: String?
    let rank: Int?
    let total_post: Int?
}

private struct LossyHitWire: Decodable {
    let value: GalleryHitWire?
    init(from decoder: Decoder) throws {
        value = try? GalleryHitWire(from: decoder)
    }
}

/// 검색어가 바뀔 때마다 디바운스(300ms) 후 디시에 물어보고, 이전 요청은 취소
@MainActor
final class GalleryLiveSearch: ObservableObject {
    @Published private(set) var results: [GalleryHit] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false

    private var task: Task<Void, Never>?
    private var lastKeyword: String?

    /// 검색어 칸이 바뀔 때마다 부름. 빈 글자나 자모만 있는 중간 상태는 디시에 묻지 않음
    func update(_ raw: String) {
        guard let keyword = Self.keyword(from: raw) else {
            cancel()
            results = []
            lastKeyword = nil
            return
        }
        // 같은 검색어가 다시 와도(칸 포커스 등) 결과가 있으면 그대로 둠
        if keyword == lastKeyword, !failed, !results.isEmpty {
            return
        }
        task?.cancel()
        lastKeyword = keyword
        loading = true
        failed = false
        task = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let hits = await Self.fetch(keyword)
            guard !Task.isCancelled else { return }
            loading = false
            if let hits {
                results = hits
                failed = false
            } else {
                results = []
                failed = true
            }
        }
    }

    /// 화면을 떠날 때 진행 중인 요청을 끊음
    func cancel() {
        task?.cancel()
        task = nil
        loading = false
    }

    // MARK: 요청·해석

    /// 검색어 정리: 앞뒤 공백을 떼고, 끝에 붙은 자모(조합 중인 글자)는 뺌. 남는 게 없으면 nil
    static func keyword(from raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = s.unicodeScalars.last, isJamo(last) || last == " " {
            s.unicodeScalars.removeLast()
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 한글 자모 (ㄱ~ㆎ 호환 자모, 초성·중성·종성 자모)
    static func isJamo(_ u: Unicode.Scalar) -> Bool {
        (0x3131...0x318E).contains(u.value) || (0x1100...0x11FF).contains(u.value)
    }

    /// 실제 요청. 실패하면 nil
    static func fetch(_ keyword: String) async -> [GalleryHit]? {
        guard let url = URL(string: "https://m.dcinside.com/search_gall") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("https://m.dcinside.com", forHTTPHeaderField: "Origin")
        req.setValue(refererURL(for: keyword), forHTTPHeaderField: "Referer")
        req.httpBody = formBody(["keyword": keyword, "type": "A", "sort_type": "rank"])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return parse(data)
        } catch {
            return nil
        }
    }

    /// 디시 검색 탭 주소 (서버가 Referer로 접근을 확인함)
    static func refererURL(for keyword: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?")
        let q = keyword.addingPercentEncoding(withAllowedCharacters: allowed) ?? keyword
        return "https://m.dcinside.com/search/gall_name?keyword=\(q)"
    }

    /// application/x-www-form-urlencoded 본문 (값은 영숫자와 -._~ 만 두고 전부 퍼센트 인코딩)
    static func formBody(_ fields: [String: String]) -> Data {
        var safe = CharacterSet.alphanumerics
        safe.insert(charactersIn: "-._~")
        let body = fields.sorted { $0.key < $1.key }.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: safe) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: safe) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    /// 응답 해석. 객체({"result":false,...})면 실패(nil), 배열이면 제목이 있는 줄만 (최대 40개)
    static func parse(_ data: Data) -> [GalleryHit]? {
        guard let wires = try? JSONDecoder().decode([LossyHitWire].self, from: data) else { return nil }
        let hits: [GalleryHit] = wires.compactMap { lossy -> GalleryHit? in
            guard let w = lossy.value,
                  let title = w.title, !title.isEmpty,
                  let type = w.type, !type.isEmpty,
                  let raw = w.id, !raw.isEmpty else { return nil }
            return GalleryHit(title: title, type: type, rawID: raw, rank: w.rank, totalPost: w.total_post)
        }
        return Array(hits.prefix(40))
    }
}

// MARK: - 공통 표시

/// 실시간 갤러리 검색 결과 섹션 (List 안에서 씀). 즐겨찾기·방문 갤러리와 겹치는 것은 빼서 중복을 막음
struct GalleryLiveResults: View {
    @ObservedObject var live: GalleryLiveSearch
    /// 이미 위에 보여 준 로컬 갤러리 ID (앞머리 뗀 것)
    let excluded: Set<String>
    /// 갤러리 주소를 여는 방법 (검색 탭은 홈 브라우저, 갤러리 안 창은 지금 화면)
    let open: (URL) -> Void

    private var remote: [GalleryHit] {
        live.results.filter { !excluded.contains($0.galleryID) }
    }

    var body: some View {
        if !remote.isEmpty || live.loading || live.failed {
            Section("디시 갤러리") {
                ForEach(remote) { hit in
                    Button { open(hit.gallery.url) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.title).foregroundStyle(.primary)
                                Text("\(hit.typeLabel) · \(hit.galleryID)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                if remote.isEmpty && live.loading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("갤러리를 찾는 중").foregroundStyle(.secondary)
                    }
                }
                if live.failed {
                    Text("디시 갤러리 목록을 못 받았어요. 아래 버튼으로 디시 검색을 열 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
