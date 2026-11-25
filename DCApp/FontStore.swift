import SwiftUI
import Combine
import UIKit
import UniformTypeIdentifiers
import WebKit
import CoreText

// MARK: - 글꼴 (온디맨드: 프리셋 다운로드 · 파일 앱에서 가져오기)
//
// 기본은 시스템 글꼴이고, 아래 프리셋을 골라 받거나 파일 앱에서 .ttf/.otf를 가져와 쓴다.
// 받은 파일은 Application Support/Fonts/<id>/ 에 저장하고, 목록은 Fonts/installed.json 에 둔다.
//  - 앱 안: CoreText로 등록해 SwiftUI 환경 글꼴(앱 전체)과 UIKit 바 제목에 쓴다.
//  - 웹페이지: dcappfont://<id>/regular|bold 주소를 WebFontSchemeHandler가 파일로 건넨다.
//    페이지 설정에는 주소만 넣고 글꼴 데이터는 넣지 않는다 (글꼴이 커도 페이지마다 무거워지지 않게).

/// 프리셋 한 줄. 새 글꼴은 `FontPresets.all`에 한 줄 추가하면 설정 → 글꼴에 나타남
struct FontPreset: Identifiable, Equatable {
    /// 폴더 이름으로도 쓰므로 영문 소문자·숫자·하이픈만 (system은 시스템 글꼴 전용)
    let id: String
    let name: String
    let subtitle: String
    /// 시스템 글꼴이면 nil. 그 밖에는 .ttf / .otf 직접 주소
    let regularURL: URL?
    /// 굵은 글꼴 파일 주소 (없으면 nil → 웹에서는 굵기를 합성함)
    let boldURL: URL?

    var isSystem: Bool { regularURL == nil }
}

enum FontPresets {
    /// 프리셋 목록. 새 글꼴은 한 줄 추가 (주소는 .ttf / .otf 파일 직접 주소)
    /// 주소 확인 (HTTP 200, 파일 헤더 TTF `00010000` / OTF `OTTO`):
    ///  - 리디바탕: fonts-archive/RIDIBatang (RIDI 배포 파일의 미러, 굵기 하나)
    ///  - Pretendard 1.3.9: npm pretendard (OFL)
    ///  - 나눔고딕: google/fonts ofl/nanumgothic (OFL)
    ///  - 도현체: google/fonts ofl/dohyeon (OFL, 굵기 하나)
    static let all: [FontPreset] = [
        FontPreset(id: "system", name: "기본 (시스템)", subtitle: "iOS 기본 글꼴", regularURL: nil, boldURL: nil),
        FontPreset(id: "ridi-batang", name: "리디바탕", subtitle: "책 읽기에 맞춘 명조",
                   regularURL: URL(string: "https://raw.githubusercontent.com/fonts-archive/RIDIBatang/main/RIDIBatang.otf"), boldURL: nil),
        FontPreset(id: "pretendard", name: "Pretendard", subtitle: "깔끔한 산세리프 고딕",
                   regularURL: URL(string: "https://cdn.jsdelivr.net/npm/pretendard@1.3.9/dist/public/static/Pretendard-Regular.otf"),
                   boldURL: URL(string: "https://cdn.jsdelivr.net/npm/pretendard@1.3.9/dist/public/static/Pretendard-Bold.otf")),
        FontPreset(id: "nanum-gothic", name: "나눔고딕", subtitle: "네이버 나눔 고딕",
                   regularURL: URL(string: "https://github.com/google/fonts/raw/main/ofl/nanumgothic/NanumGothic-Regular.ttf"),
                   boldURL: URL(string: "https://github.com/google/fonts/raw/main/ofl/nanumgothic/NanumGothic-Bold.ttf")),
        FontPreset(id: "do-hyeon", name: "배달의민족 도현체", subtitle: "굵고 둥근 제목용 글꼴",
                   regularURL: URL(string: "https://github.com/google/fonts/raw/main/ofl/dohyeon/DoHyeon-Regular.ttf"), boldURL: nil),
    ]
}

/// 기기에 받아 둔 글꼴 한 개 (installed.json에 저장)
struct InstalledFont: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    /// Fonts/<id>/ 안의 파일 이름 (예: regular.ttf)
    var regularFile: String
    var boldFile: String?
}

/// 글꼴 파일 문제 (설정 화면에 그대로 보여 줌)
enum FontFileError: LocalizedError {
    case badResponse
    case notFont
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .badResponse: return "글꼴을 받지 못했어요. 주소를 확인해 주세요."
        case .notFont: return "글꼴 파일(.ttf / .otf)이 아니에요."
        case .tooLarge: return "글꼴 파일이 너무 커요. 40MB 이하만 쓸 수 있어요."
        }
    }
}

@MainActor
final class FontStore: ObservableObject {
    static let shared = FontStore()

    static let systemID = "system"
    /// 웹페이지에서 쓰는 주소 주머니 (WKURLSchemeHandler로 파일을 건넴)
    static let webScheme = "dcappfont"
    nonisolated static let maxBytes = 40_000_000

    @Published private(set) var installed: [InstalledFont] = []
    @Published private(set) var selectedID: String
    /// 앱 안에서 쓰는 글꼴의 PostScript 이름 (nil이면 시스템 글꼴)
    @Published private(set) var activePostScriptName: String?
    /// 굵은 글꼴 파일의 PostScript 이름 (있으면 bold/semibold에 사용)
    @Published private(set) var activeBoldPostScriptName: String?
    /// 받는 중인 프리셋 id
    @Published private(set) var busyIDs: Set<String> = []
    /// 마지막 오류 메시지 (설정 화면에 표시)
    @Published var message: String?

    private static let selectedKey = "selectedFontID"

    private init() {
        selectedID = Profile.defaults.string(forKey: Self.selectedKey) ?? Self.systemID
        installed = Self.loadManifest()
        if selectedID != Self.systemID, installed.contains(where: { $0.id == selectedID }) {
            activate(selectedID)
        } else {
            selectedID = Self.systemID
        }
    }

    // MARK: 표시용

    /// 선택된 글꼴 이름 (설정 목록의 오른쪽 글자)
    var selectedName: String {
        if selectedID == Self.systemID { return "기본 (시스템)" }
        if let f = installed.first(where: { $0.id == selectedID }) { return f.name }
        return "기본 (시스템)"
    }

    /// 앱 전체에 거는 환경 글꼴 (nil이면 시스템 글꼴). 명시적으로 .font(…)를 준 곳은 아래 헬퍼 사용
    var swiftUIFont: Font? {
        guard let name = activePostScriptName else { return nil }
        return .custom(name, size: 17, relativeTo: .body)
    }

    /// 직접 크기·굵기를 지정하는 UI용 (컨트롤바 라벨 등)
    func uiFont(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let isBold = weight == .bold || weight == .semibold || weight == .heavy || weight == .black
        if let name = (isBold ? (activeBoldPostScriptName ?? activePostScriptName) : activePostScriptName) {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(size: size, weight: weight)
    }

    /// 텍스트 스타일(.caption, .subheadline, .headline 등)을 선택한 글꼴로 반환
    func styleFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let isBold = weight == .bold || weight == .semibold || weight == .heavy || weight == .black || style == .headline
        if let name = (isBold ? (activeBoldPostScriptName ?? activePostScriptName) : activePostScriptName) {
            let size: CGFloat = switch style {
            case .largeTitle: 34
            case .title: 28
            case .title2: 22
            case .title3: 20
            case .headline, .body: 17
            case .callout: 16
            case .subheadline: 15
            case .footnote: 13
            case .caption: 12
            case .caption2: 11
            @unknown default: 17
            }
            return .custom(name, size: size, relativeTo: style)
        }
        if let weight { return .system(style).weight(weight) }
        return .system(style)
    }

    /// 페이지 설정에 넣을 웹 글꼴 정보 (선택한 글꼴이 없으면 nil → 페이지는 기본 글꼴)
    var webFontConfig: [String: Any]? {
        guard activePostScriptName != nil, let rec = installed.first(where: { $0.id == selectedID }) else { return nil }
        return ["id": rec.id, "bold": rec.boldFile != nil]
    }

    /// 웹뷰가 요청한 글꼴 파일을 base64로 읽음 (FontFace ArrayBuffer 전달용)
    static func webFontBase64(id: String, weight: String) -> String? {
        guard isSafeID(id), weight == "regular" || weight == "bold",
              let dir = dir(for: id),
              let file = files(in: dir).first(where: { $0.lastPathComponent.hasPrefix(weight + ".") }),
              let data = try? Data(contentsOf: file) else { return nil }
        return data.base64EncodedString()
    }

    // MARK: 선택 · 삭제

    /// 글꼴을 고른다 (앱 전체와 열린 웹페이지에 바로 반영)
    func select(_ id: String) {
        guard id == Self.systemID || installed.contains(where: { $0.id == id }) else { return }
        selectedID = id
        Profile.defaults.set(id, forKey: Self.selectedKey)
        activate(id)
        NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
    }

    /// 받아 둔 글꼴을 지운다 (고른 글꼴이면 시스템 글꼴로 돌아감)
    func delete(_ id: String) {
        guard let dir = Self.dir(for: id) else { return }
        for url in Self.files(in: dir) {
            _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        }
        try? FileManager.default.removeItem(at: dir)
        installed.removeAll { $0.id == id }
        saveManifest()
        if selectedID == id { select(Self.systemID) }
    }

    // MARK: 받기 · 가져오기

    /// 프리셋 글꼴을 받아 저장 (고르기는 따로)
    func download(_ preset: FontPreset) {
        guard let regular = preset.regularURL, !busyIDs.contains(preset.id) else { return }
        busyIDs.insert(preset.id)
        message = nil
        Task {
            defer { busyIDs.remove(preset.id) }
            do {
                let regularFile = try await Self.fetch(regular, id: preset.id, name: "regular")
                var boldFile: String? = nil
                if let bold = preset.boldURL {
                    boldFile = try await Self.fetch(bold, id: preset.id, name: "bold")
                }
                upsert(InstalledFont(id: preset.id, name: preset.name, regularFile: regularFile, boldFile: boldFile))
                // 이미 고른 글꼴을 다시 받았다면 새 파일로 바로 적용
                if selectedID == preset.id { activate(preset.id); NotificationCenter.default.post(name: DC.filtersChanged, object: nil) }
            } catch {
                message = "\(preset.name): \(error.localizedDescription)"
            }
        }
    }

    /// 파일 앱에서 고른 .ttf / .otf를 복사해 등록하고 바로 고른다
    func importFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        message = nil
        let id = "file-" + UUID().uuidString.lowercased()
        do {
            let file = try Self.importLocal(url, id: id)
            let name = url.deletingPathExtension().lastPathComponent
            upsert(InstalledFont(id: id, name: name, regularFile: file, boldFile: nil))
            select(id)
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: 내부

    private func upsert(_ font: InstalledFont) {
        installed.removeAll { $0.id == font.id }
        installed.append(font)
        saveManifest()
    }

    /// 고른 글꼴을 CoreText에 등록하고 PostScript 이름을 읽어 둠
    private func activate(_ id: String) {
        guard id != Self.systemID,
              let rec = installed.first(where: { $0.id == id }),
              let dir = Self.dir(for: id) else {
            activePostScriptName = nil
            activeBoldPostScriptName = nil
            applyUIKit()
            return
        }
        let url = dir.appendingPathComponent(rec.regularFile)
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        activePostScriptName = Self.postScriptName(of: url)
        if let boldFile = rec.boldFile {
            let boldURL = dir.appendingPathComponent(boldFile)
            _ = CTFontManagerRegisterFontsForURL(boldURL as CFURL, .process, nil)
            activeBoldPostScriptName = Self.postScriptName(of: boldURL)
        } else {
            activeBoldPostScriptName = nil
        }
        applyUIKit()
    }

    /// UIKit 쪽(내비게이션 바 제목)에도 같은 글꼴 적용 — 이미 떠 있는 바는 다시 열어야 바뀜
    private func applyUIKit() {
        let bar = UINavigationBar.appearance()
        if let name = activePostScriptName {
            let title: [NSAttributedString.Key: Any] = [.font: UIFont(name: name, size: 17) ?? UIFont.systemFont(ofSize: 17)]
            let large: [NSAttributedString.Key: Any] = [.font: UIFont(name: name, size: 34) ?? UIFont.systemFont(ofSize: 34)]
            bar.titleTextAttributes = title
            bar.largeTitleTextAttributes = large
        } else {
            bar.titleTextAttributes = nil
            bar.largeTitleTextAttributes = nil
        }
    }

    private func saveManifest() {
        guard let root = Self.rootDir, let data = try? JSONEncoder().encode(installed) else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? data.write(to: root.appendingPathComponent("installed.json"), options: .atomic)
    }

    private static func loadManifest() -> [InstalledFont] {
        guard let url = rootDir?.appendingPathComponent("installed.json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([InstalledFont].self, from: data) else { return [] }
        // 파일이 사라진 항목은 빼고 시작
        return list.filter { f in dir(for: f.id).map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(f.regularFile).path) } ?? false }
    }

    // MARK: 파일 · 경로 (화면 밖 스레드에서도 쓰므로 nonisolated)

    /// Application Support/Fonts
    nonisolated static var rootDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Fonts", isDirectory: true)
    }

    /// Fonts/<id> (폴더가 없으면 만듦)
    nonisolated static func dir(for id: String) -> URL? {
        guard isSafeID(id), let root = rootDir else { return nil }
        let url = root.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 주소·폴더에 쓰는 id는 영문 소문자·숫자·하이픈만 허용 (경로 조작 방지)
    nonisolated static func isSafeID(_ id: String) -> Bool {
        id.range(of: #"^[a-z0-9-]{1,80}$"#, options: .regularExpression) != nil
    }

    nonisolated static func files(in dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    }

    /// 글꼴 파일이 맞으면 PostScript 이름, 아니면 nil
    nonisolated static func postScriptName(of url: URL) -> String? {
        guard let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) else { return nil }
        return font.postScriptName as String?
    }

    nonisolated static func checkedExtension(_ url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        guard ext == "ttf" || ext == "otf" else { throw FontFileError.notFont }
        return ext
    }

    nonisolated static func checkSize(_ url: URL) throws {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
        guard size <= maxBytes else { throw FontFileError.tooLarge }
    }

    /// 주소에서 받아 Fonts/<id>/<name>.<ttf|otf> 로 저장. 파일이 글꼴이 아니면 버림
    nonisolated static func fetch(_ url: URL, id: String, name: String) async throws -> String {
        let ext = try checkedExtension(url)
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw FontFileError.badResponse }
        try checkSize(tmp)
        guard postScriptName(of: tmp) != nil else { throw FontFileError.notFont }
        guard let dir = dir(for: id) else { throw FontFileError.badResponse }
        for old in files(in: dir) where old.lastPathComponent.hasPrefix(name + ".") {
            try? FileManager.default.removeItem(at: old)
        }
        let dest = dir.appendingPathComponent("\(name).\(ext)")
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest.lastPathComponent
    }

    /// 파일 앱에서 가져온 파일을 Fonts/<id>/regular.<ext> 로 복사
    nonisolated static func importLocal(_ src: URL, id: String) throws -> String {
        let ext = try checkedExtension(src)
        try checkSize(src)
        guard postScriptName(of: src) != nil else { throw FontFileError.notFont }
        guard let dir = dir(for: id) else { throw FontFileError.badResponse }
        let dest = dir.appendingPathComponent("regular.\(ext)")
        try FileManager.default.copyItem(at: src, to: dest)
        return dest.lastPathComponent
    }
}

/// 페이지가 dcappfont://<id>/regular|bold 를 요청하면 저장된 글꼴 파일을 건넴 (CORS 허용: 페이지 주소와 다른 주소라서)
@MainActor
final class WebFontSchemeHandler: NSObject, WKURLSchemeHandler {
    static let shared = WebFontSchemeHandler()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let reqURL = urlSchemeTask.request.url,
              let id = reqURL.host,
              FontStore.isSafeID(id) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let which = reqURL.lastPathComponent
        guard which == "regular" || which == "bold",
              let dir = FontStore.dir(for: id),
              let file = FontStore.files(in: dir).first(where: { $0.lastPathComponent.hasPrefix(which + ".") }),
              let data = try? Data(contentsOf: file),
              let resp = HTTPURLResponse(url: reqURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                  "Content-Type": file.pathExtension.lowercased() == "otf" ? "font/otf" : "font/ttf",
                  "Content-Length": "\(data.count)",
                  "Access-Control-Allow-Origin": "*",
                  "Cache-Control": "no-cache",
              ]) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        urlSchemeTask.didReceive(resp)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

/// 페이지 JS가 dcappFont 메시지로 글꼴 데이터를 요청하면 base64로 응답 (커스텀 스킴 CORS/혼합콘텐츠 차단 우회)
@MainActor
final class WebFontMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = WebFontMessageHandler()

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let weight = body["weight"] as? String,
              let b64 = FontStore.webFontBase64(id: id, weight: weight) else {
            replyHandler(nil, "not_found")
            return
        }
        replyHandler(b64, nil)
    }
}
