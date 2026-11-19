import UIKit
import ImageIO
import CryptoKit

/// 본문 사진 차단에 쓰는 사진 생김새 해시 (같은 사진을 다른 이름으로 다시 올린 것도 찾으려고)
/// - 64비트 dHash: 9x8 축소본에서 가로로 이웃한 두 픽셀 중 왼쪽이 더 밝은지 비교 → 16자리 hex
/// - 단색(거의 한 가지 색) 사진은 dHash가 모두 0으로 같게 나와 아무 단색 사진이나 잡으므로,
///   축소본 색 값의 SHA-256 앞 16자리에 "s:"를 붙여 완전히 같은 것만 맞춤
enum ImageBlockHash {
    /// 주소별로 받은 해시 (같은 사진을 다시 받지 않도록)
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSString>()

    /// 사진 데이터의 해시 (첫 장 기준). 읽지 못하면 nil
    nonisolated static func hash(data: Data) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = 9, h = 8
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // 회색 값 (밝기 가중 평균)
        var gray = [Int](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let r = Int(px[i * 4]), g = Int(px[i * 4 + 1]), b = Int(px[i * 4 + 2])
            gray[i] = (r * 299 + g * 587 + b * 114) / 1000
        }
        if let lo = gray.min(), let hi = gray.max(), hi - lo <= 3 {
            // 단색: 색 값 자체의 해시 (dHash는 단색끼리 모두 같아져서 쓸 수 없음)
            let digest = SHA256.hash(data: Data(px))
            return "s:" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        }
        var bits: UInt64 = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                bits <<= 1
                if gray[y * w + x] > gray[y * w + x + 1] { bits |= 1 }
            }
        }
        let s = String(bits, radix: 16)
        return String(repeating: "0", count: 16 - s.count) + s
    }

    /// 두 해시가 같은 사진인지: dHash는 해밍 거리 5 이하, 단색("s:")은 완전히 같을 때만
    nonisolated static func matches(_ a: String, _ b: String) -> Bool {
        if a.hasPrefix("s:") || b.hasPrefix("s:") { return a == b }
        guard let x = UInt64(a, radix: 16), let y = UInt64(b, radix: 16) else { return false }
        return (x ^ y).nonzeroBitCount <= 5
    }

    /// 디시 사진 서버는 Referer가 있어야 내주므로 붙여서 받음. 실패하면 nil
    nonisolated static func download(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.setValue("https://m.dcinside.com/", forHTTPHeaderField: "Referer")
        guard let (data, res) = try? await URLSession.shared.data(for: req),
              (res as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        return data
    }

    /// 주소의 사진을 받아 해시를 구함 (한 번 구한 주소는 캐시에서 바로)
    nonisolated static func fetch(_ urlString: String) async -> String? {
        if let c = cache.object(forKey: urlString as NSString) { return c as String }
        guard let data = await download(urlString), let h = hash(data: data) else { return nil }
        cache.setObject(h as NSString, forKey: urlString as NSString)
        return h
    }
}
