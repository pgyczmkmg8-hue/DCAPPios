import SwiftUI
import Combine

/// 꼬릿말: 글 맨 아래에 붙는 한 줄 (-내용 양식, 회색 12px 고정)
/// 계정(유동 포함)·갤러리마다 따로 정할 수 있음. 더 구체적으로 맞는 규칙이 먼저 쓰임
struct FooterRule: Codable, Identifiable, Hashable {
    static let all = "*"          // account: 모든 계정 / gallery: 모든 갤러리
    static let anon = ""          // account: 유동 (로그인하지 않은 글)

    var id = UUID()
    var account: String           // all / anon / 디시 아이디
    var gallery: String           // all / 갤러리 아이디
    var text: String              // 꼬릿말 내용 ('-'는 앱이 붙임)

    var accountLabel: String {
        account == Self.all ? "모든 계정" : (account == Self.anon ? "유동" : account)
    }
    var galleryLabel: String { gallery == Self.all ? "모든 갤러리" : gallery }
}

@MainActor
final class FooterStore: ObservableObject {
    static let shared = FooterStore()
    private let rulesKey = "footerRules"
    static let enabledKey = "footerEnabled"

    @Published var rules: [FooterRule] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: rulesKey),
           let saved = try? JSONDecoder().decode([FooterRule].self, from: data) {
            rules = saved
        } else {
            rules = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
    }

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// 이 글(계정·갤러리)에 붙일 꼬릿말 내용. 계정+갤러리 > 계정 > 갤러리 > 전체 순으로 구체적인 규칙이 이김
    /// account: 유동이면 FooterRule.anon, 로그인이면 디시 아이디 (모르면 nil → 전체 규칙만)
    func text(account: String?, gallery: String) -> String? {
        guard Self.enabled else { return nil }
        var best: (score: Int, text: String)?
        for r in rules {
            let t = Self.clean(r.text)
            guard !t.isEmpty else { continue }
            let accountMatch = r.account == FooterRule.all || (account != nil && r.account == account)
            let galleryMatch = r.gallery == FooterRule.all || r.gallery == gallery
            guard accountMatch, galleryMatch else { continue }
            let score = (r.account == FooterRule.all ? 0 : 2) + (r.gallery == FooterRule.all ? 0 : 1)
            if best == nil || score > best!.score { best = (score, t) }
        }
        return best?.text
    }

    /// 줄바꿈 없이 한 줄, 앞의 '-'는 앱이 붙이므로 떼어 냄
    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix("-") { t.removeFirst(); t = t.trimmingCharacters(in: .whitespaces) }
        return t
    }
}

/// 꼬릿말 양식 (내용 앞에 '-', 회색, 12px 고정)
enum FooterFormat {
    static let size = 12
    static let colorHex = "#8a8a8a"

    static func plain(_ text: String) -> String { "-" + text }

    /// 이모지·기호 그림 문자를 뺀 글자 (디시가 이모지를 지우고 저장했을 때 꼬릿말을 알아보기 위함)
    static func withoutEmoji(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { u in
            let v = u.value
            if v >= 0x1F000 || (0x2600...0x27BF).contains(v) || (0xFE00...0xFE0F).contains(v) || v == 0x200D || v == 0x20E3 { return false }
            if (0x2190...0x21FF).contains(v) || (0x2B00...0x2BFF).contains(v) || (0x2300...0x23FF).contains(v) { return false }
            return true
        })).trimmingCharacters(in: .whitespaces)
    }

    /// 디시 편집기 HTML: 빈 줄 하나 + 꼬릿말 줄
    static func html(_ text: String) -> String {
        let e = plain(text).replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return "<p><br></p><p><span style=\"color:\(colorHex);font-size:\(size)px\">\(e)</span></p>"
    }
}

// MARK: - 설정 화면

struct FooterSettingsView: View {
    @ObservedObject private var store = FooterStore.shared
    @AppStorage(FooterStore.enabledKey) private var enabled = false
    @State private var editing: FooterRule?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                Toggle("꼬릿말 사용", isOn: $enabled)
            } footer: {
                Text("글을 등록할 때 맨 아래에 '-내용' 한 줄을 회색 12px로 붙여요. 앱 글쓰기 화면에서 쓴 글에 적용돼요.")
            }

            if enabled {
                Section {
                    ForEach(store.rules) { r in
                        Button { editing = r } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(r.accountLabel) · \(r.galleryLabel)").font(.subheadline).foregroundStyle(.secondary)
                                Text(FooterFormat.plain(FooterStore.clean(r.text)))
                                    .font(.system(size: 12)).foregroundStyle(Color(white: 0.55))
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { store.rules.remove(atOffsets: $0) }
                    Button { adding = true } label: { Label("꼬릿말 추가", systemImage: "plus") }
                } header: {
                    Text("꼬릿말 목록")
                } footer: {
                    Text("계정과 갤러리가 둘 다 맞는 글에만 붙어요. '모든 계정'·'모든 갤러리'는 그 칸은 가리지 않는다는 뜻이에요. 맞는 규칙이 여러 개면 계정·갤러리를 구체적으로 정한 규칙 하나만 붙어요. 밀어서 지울 수 있어요.")
                }
            }
        }
        .navigationTitle("꼬릿말")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            FooterRuleEditor(rule: FooterRule(account: FooterRule.all, gallery: FooterRule.all, text: ""), isNew: true)
                .sheetUnderBlueBar()
        }
        .sheet(item: $editing) { r in
            FooterRuleEditor(rule: r, isNew: false)
                .sheetUnderBlueBar()
        }
    }
}

struct FooterRuleEditor: View {
    @State var rule: FooterRule
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var visited = VisitedStore.shared
    @State private var galleryInput = ""

    /// 고를 수 있는 갤러리: 즐겨찾기 + 방문한 갤러리 (이 규칙의 갤러리도 항상 포함)
    private var galleryChoices: [(id: String, name: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        func add(_ id: String, _ name: String) { if !id.isEmpty, seen.insert(id).inserted { out.append((id, name)) } }
        favorites.items.forEach { add($0.galleryID, $0.name) }
        visited.items.forEach { add($0.gallery.galleryID, $0.gallery.name) }
        if rule.gallery != FooterRule.all { add(rule.gallery, rule.gallery) }
        return out
    }

    private var accountChoices: [String] {
        var ids = CredentialStore.all().map(\.id)
        if rule.account != FooterRule.all, rule.account != FooterRule.anon, !ids.contains(rule.account) { ids.append(rule.account) }
        return ids
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("계정") {
                    Picker("계정", selection: $rule.account) {
                        Text("모든 계정").tag(FooterRule.all)
                        Text("유동").tag(FooterRule.anon)
                        ForEach(accountChoices, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    Picker("갤러리", selection: $rule.gallery) {
                        Text("모든 갤러리").tag(FooterRule.all)
                        ForEach(galleryChoices, id: \.id) { Text($0.name == $0.id ? $0.id : "\($0.name) (\($0.id))").tag($0.id) }
                    }
                    HStack {
                        TextField("갤러리 아이디 직접 입력", text: $galleryInput)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("적용") {
                            let g = galleryInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !g.isEmpty { rule.gallery = g; galleryInput = "" }
                        }
                        .disabled(galleryInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("갤러리")
                } footer: {
                    Text("목록에 없는 갤러리는 주소의 갤러리 아이디(예: m.dcinside.com/board/ipad1 의 ipad1)를 직접 입력해요.")
                }
                Section {
                    TextField("꼬릿말 내용", text: $rule.text)
                    Text(FooterFormat.plain(FooterStore.clean(rule.text)))
                        .font(.system(size: 12)).foregroundStyle(Color(white: 0.55))
                } header: {
                    Text("꼬릿말")
                } footer: {
                    Text("앞의 '-'는 자동으로 붙어요. 회색 12px로 고정이에요.")
                }
            }
            .navigationTitle(isNew ? "꼬릿말 추가" : "꼬릿말 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        rule.text = FooterStore.clean(rule.text)
                        let store = FooterStore.shared
                        if let i = store.rules.firstIndex(where: { $0.id == rule.id }) { store.rules[i] = rule }
                        else { store.rules.append(rule) }
                        UserDefaults.standard.set(true, forKey: FooterStore.enabledKey)   // 꼬릿말을 정했으면 사용 켜기
                        dismiss()
                    }
                    .disabled(FooterStore.clean(rule.text).isEmpty)
                }
            }
        }
    }
}

/// ⋮ 메뉴에서: 지금 계정·갤러리 조합의 꼬릿말을 바로 정함 (이미 있으면 고치기)
struct FooterQuickSheet: View {
    let account: String
    let gallery: String

    var body: some View {
        let existing = FooterStore.shared.rules.first { $0.account == account && $0.gallery == gallery }
        FooterRuleEditor(rule: existing ?? FooterRule(account: account, gallery: gallery, text: ""), isNew: existing == nil)
    }
}
