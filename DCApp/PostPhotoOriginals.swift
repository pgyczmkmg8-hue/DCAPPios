import Foundation
import ImageIO

/// 글 속 사진의 원본 받기 (사진 보기, 길게 눌러 원본 저장, 전체 저장이 같이 씀)
/// 모바일 웹의 사진은 줄어든 것이라, PC 글 아래 '원본 첨부파일' 링크(download.php)에서 원본을 받음.
/// 원본 링크는 PC 글 첨부 목록 순서(파일 번호 순)라서, 본문 사진의 파일 번호 순위로 짝을 맞춤
enum PostPhotoOriginals {
    /// 모바일 글 주소 → PC 글의 원본 첨부 링크들 (사진 순서). 사진 수(count)와 첨부 수가 같을 때만 돌려줌 (다르면 엉뚱한 파일일 수 있어서). 못 찾으면 nil
    nonisolated static func links(page: URL?, count: Int) async -> [URL]? {
        guard count > 0, let page, let pc = pcURL(page) else { return nil }
        var req = URLRequest(url: pc)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("https://gall.dcinside.com/", forHTTPHeaderField: "Referer")
        guard let (html, _) = try? await URLSession.shared.data(for: req),
              let text = String(data: html, encoding: .utf8),
              let box = text.range(of: "appending_file") else { return nil }
        let tail = String(text[box.upperBound...])
        let end = tail.range(of: "</ul>")?.lowerBound ?? tail.endIndex
        let section = String(tail[..<end]).replacingOccurrences(of: "&amp;", with: "&")
        guard let re = try? NSRegularExpression(pattern: #"https://image\.dcinside\.com/download\.php\?[^"'\s<>]+"#) else { return nil }
        let links = re.matches(in: section, range: NSRange(section.startIndex..., in: section))
            .compactMap { Range($0.range, in: section).map { String(section[$0]) } }
            .compactMap { URL(string: $0) }
        return links.count == count ? links : nil
    }

    /// 글 속 전체 사진 중 index번째가 원본 첨부 목록의 몇 번째인지 — 첨부 목록은 파일 번호가 작은 순이므로 파일 번호 순위로 구함
    /// (파일 번호가 없거나 겹치면 본문 순서 그대로)
    nonisolated static func linkSlot(_ index: Int, filenos: [Int]?) -> Int {
        guard let f = filenos, index < f.count, !f.contains(0), Set(f).count == f.count else { return index }
        return f.filter { $0 < f[index] }.count
    }

    /// 원본 한 장 (디시 원본 주소는 gall 도메인 Referer가 필요). 사진으로 읽히지 않으면 nil
    nonisolated static func download(_ u: URL) async -> Data? {
        var dl = URLRequest(url: u)
        dl.setValue("https://gall.dcinside.com/", forHTTPHeaderField: "Referer")
        guard let (data, res) = try? await URLSession.shared.data(for: dl),
              (res as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty,
              CGImageSourceCreateWithData(data as CFData, nil) != nil else { return nil }
        return data
    }

    /// 모바일 사진 (디시 사진 서버는 Referer가 없으면 막음). 사진으로 읽히지 않으면 nil
    nonisolated static func mobileData(_ u: URL) async -> Data? {
        var req = URLRequest(url: u)
        req.setValue("https://m.dcinside.com/", forHTTPHeaderField: "Referer")
        guard let (data, res) = try? await URLSession.shared.data(for: req),
              (res as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty,
              CGImageSourceCreateWithData(data as CFData, nil) != nil else { return nil }
        return data
    }

    /// 글 속 전체 순서 index번째 사진의 원본 데이터: PC 원본 첨부 → 못 받으면 모바일 사진. index가 없으면(-1) 모바일 사진만
    nonisolated static func original(links: [URL]?, index: Int, filenos: [Int]?, mobile: URL?) async -> Data? {
        if index >= 0, let links {
            let slot = linkSlot(index, filenos: filenos)
            if slot < links.count, let data = await download(links[slot]) { return data }
        }
        guard let mobile else { return nil }
        return await mobileData(mobile)
    }

    /// m.dcinside.com/board/{id}/{no} (mini·person도) → gall.dcinside.com/.../board/view/?id=&no=
    nonisolated static func pcURL(_ url: URL) -> URL? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 3, let kind = ["board", "mini", "person"].first(where: { $0 == parts[0] }),
              parts[2].allSatisfy(\.isNumber) else { return nil }
        let prefix = kind == "board" ? "" : "/\(kind)"
        return URL(string: "https://gall.dcinside.com\(prefix)/board/view/?id=\(parts[1])&no=\(parts[2])")
    }
}
