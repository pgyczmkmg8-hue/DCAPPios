import Foundation

// MARK: - 글 본문의 유튜브 링크 찾기
//
// youtube.com/watch?v=…, m.youtube.com, youtu.be/…, youtube.com/shorts/…, embed/…, live/… 를 인식한다.
// 글자를 링크 기준으로 나눠서 (글자 조각, 영상 ID, 글자 조각 …) 순서대로 돌려준다.
// 영상 칸은 등록할 때 디시 편집기의 유튜브 삽입(insertYt)으로 만든다.

nonisolated enum YouTubeLinks {
    /// 나눈 조각: 글자 또는 유튜브 영상 ID
    enum Piece: Equatable {
        case text(String)
        case video(String)

        var videoID: String? {
            if case .video(let id) = self { return id }
            return nil
        }
    }

    private static let regex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:https?://)?(?:(?:www|m)\.)?(?:youtube\.com/(?:watch\?[^\s<>"']*?\bv=|shorts/|embed/|live/)|youtu\.be/)([A-Za-z0-9_-]{11})(?:[?&#][^\s<>"']*)?"#,
        options: [.caseInsensitive])

    /// 글자를 유튜브 링크 기준으로 나눔. 항상 글자 조각으로 시작하고 끝남 (빈 조각 포함)
    static func split(_ text: String) -> [Piece] {
        guard let regex, text.range(of: "youtu", options: .caseInsensitive) != nil else { return [.text(text)] }
        let ns = text as NSString
        var out: [Piece] = []
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 1 {
            out.append(.text(ns.substring(with: NSRange(location: last, length: m.range.location - last))))
            out.append(.video(ns.substring(with: m.range(at: 1))))
            last = m.range.location + m.range.length
        }
        out.append(.text(ns.substring(from: last)))
        return out
    }
}
