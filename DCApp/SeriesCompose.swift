import SwiftUI
import Combine

// MARK: - 시리즈 만들기 (앱 화면)
//
// 제목과 시리즈에 넣을 게시물을 앱에서 고른다. 주소를 직접 넣거나, 글 보관함·최근 본 글에서 골라 넣는다.
// 순서는 편집에서 끌어서 바꾸거나 정렬 메뉴로 바꾼다. 만든 시리즈는 목록으로 저장해 다시 불러올 수 있다.
// 주소 확인과 등록은 디시 함수로 하며, 만든 시리즈는 앱 글쓰기 끝에 시리즈 칸으로 붙는다.
// 등록하면 디시가 글에 시리즈를 붙인다. 시리즈는 글 하나에 5개, 한 시리즈에 게시물 50개까지.

// MARK: 모델

/// 시리즈에 들어갈 게시물 한 개
struct SeriesEntry: Codable, Identifiable, Hashable {
    var url: URL
    var title: String          // 보관함·최근 본 글에서 왔으면 제목이 있고, 주소로 넣었으면 비어 있음
    var galleryID: String      // 앞머리 붙은 갤러리 ID ("ipad1", 미니 "mi$incord")
    var postNo: Int?           // 글번호 (같은 갤러리 안에서는 작성 순서와 같음)
    var date: Date?            // 보관한 날 / 마지막으로 읽은 날 (표시용)

    /// 같은 글은 한 번만 들어가도록 쓰는 기준 ("ipad1/1090313")
    var id: String { PostKey.from(url) ?? url.absoluteString }
    /// 제목이 없으면 주소를 보여줌 (정렬도 같은 값으로)
    var displayTitle: String { title.isEmpty ? url.absoluteString : title }
    var subtitle: String {
        var parts: [String] = []
        if !galleryID.isEmpty { parts.append(galleryID) }
        if let postNo { parts.append("\(postNo)번") }
        return parts.joined(separator: " · ")
    }

    /// 디시 글 주소면 항목으로 만듦. 아니면 nil
    static func make(url: URL, title: String, date: Date?) -> SeriesEntry? {
        guard let key = PostKey.from(url) else { return nil }
        let parts = key.split(separator: "/")
        return SeriesEntry(url: url, title: title, galleryID: PostKey.gallery(key),
                           postNo: parts.count == 2 ? Int(parts[1]) : nil, date: date)
    }

    /// 붙여 넣은 한 줄 (https:// 없이 써도 됨). 디시 글 주소가 아니면 nil
    static func from(text: String) -> SeriesEntry? {
        let t = text.lowercased().hasPrefix("http") ? text : "https://" + text
        guard let url = URL(string: t) else { return nil }
        return make(url: url, title: "", date: nil)
    }
}

/// 정렬 메뉴 항목 (정렬하면 목록 순서가 바로 바뀌고, 그 뒤에 끌어서 다시 바꿀 수 있음)
enum SeriesSort: CaseIterable, Identifiable {
    case titleAscending, titleDescending, writtenOldest, writtenNewest

    var id: Self { self }

    var title: String {
        switch self {
        case .titleAscending: return "제목 ㄱ→ㅎ · A→Z"
        case .titleDescending: return "제목 ㅎ→ㄱ · Z→A"
        case .writtenOldest: return "작성시간 오래된 순"
        case .writtenNewest: return "작성시간 최신 순"
        }
    }

    var icon: String {
        switch self {
        case .titleAscending, .titleDescending: return "textformat"
        case .writtenOldest, .writtenNewest: return "clock"
        }
    }

    func apply(_ list: [SeriesEntry]) -> [SeriesEntry] {
        switch self {
        case .titleAscending:
            return list.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case .titleDescending:
            return list.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedDescending }
        case .writtenOldest:
            return list.sorted { Self.written($0, $1, newestFirst: false) }
        case .writtenNewest:
            return list.sorted { Self.written($0, $1, newestFirst: true) }
        }
    }

    /// 작성 순서: 같은 갤러리 안에서는 글번호 순, 갤러리가 다르면 갤러리 이름 순. 번호를 모르는 글은 맨 뒤
    private static func written(_ a: SeriesEntry, _ b: SeriesEntry, newestFirst: Bool) -> Bool {
        switch (a.postNo, b.postNo) {
        case let (x?, y?):
            if a.galleryID != b.galleryID { return a.galleryID < b.galleryID }
            return newestFirst ? x > y : x < y
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return false
        }
    }
}

/// 저장해 둔 시리즈 (제목 + 게시물 목록)
struct SavedSeries: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var entries: [SeriesEntry]
    var savedAt: Date
}

@MainActor
final class SeriesStore: ObservableObject {
    static let shared = SeriesStore()

    @Published private(set) var items: [SavedSeries] = []
    private let key = "savedSeriesLists"

    private init() {
        if let data = Profile.defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([SavedSeries].self, from: data) {
            items = saved
        }
    }

    /// 같은 id가 있으면 그 항목을 바꾸고, 없으면 맨 앞에 넣음
    func upsert(_ s: SavedSeries) {
        if let i = items.firstIndex(where: { $0.id == s.id }) {
            items[i] = s
        } else {
            items.insert(s, at: 0)
        }
        save()
    }

    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            Profile.defaults.set(data, forKey: key)
        }
    }
}

// MARK: 시트

struct SeriesComposeSheet: View {
    let model: WebViewModel
    /// 이 글에 이미 들어 있는 시리즈 수 (디시 한도 5개)
    let existing: Int
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var entries: [SeriesEntry] = []
    @State private var typedURL = ""
    @State private var notice: String?
    @State private var showPicker = false
    @State private var showLoad = false
    @State private var loadedID: UUID?          // 불러온(또는 저장한) 시리즈면 다음 저장 때 그 항목을 바꿈
    @State private var showSaved = false
    @State private var savedMessage = ""
    @State private var submitting = false

    private static let maxTitle = 20
    private static let maxEntries = 50
    private static let maxSeries = 5

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool {
        !trimmedTitle.isEmpty && trimmedTitle.count <= Self.maxTitle
            && !entries.isEmpty && entries.count <= Self.maxEntries
            && existing < Self.maxSeries
            && !submitting
    }
    private var canSave: Bool { !trimmedTitle.isEmpty && !entries.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if existing >= Self.maxSeries {
                    Section {
                        Text("이 글에는 시리즈를 \(Self.maxSeries)개까지만 넣을 수 있어요.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("시리즈 제목 (20자 이내)", text: $title)
                } header: {
                    Text("제목")
                }
                Section {
                    HStack(spacing: 8) {
                        TextField("주소 (m.dcinside.com/board/…)", text: $typedURL, axis: .vertical)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("추가") { addTyped() }
                            .disabled(typedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button {
                        showPicker = true
                    } label: {
                        Label("글 보관함·최근 본 글에서 고르기", systemImage: "tray.full")
                    }
                } header: {
                    Text("게시물 추가")
                } footer: {
                    Text(notice ?? "주소는 한 줄에 하나씩, 여러 줄을 붙여 넣어도 돼요. 디시 글 주소만 들어가요.")
                }
                Section {
                    if entries.isEmpty {
                        Text("아직 게시물이 없어요. 위에서 주소를 넣거나 보관함에서 골라 주세요.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.displayTitle).lineLimit(1)
                            if !e.subtitle.isEmpty {
                                Text(e.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { entries.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { entries.remove(atOffsets: $0) }
                } header: {
                    Text("게시물 (\(entries.count)/\(Self.maxEntries))")
                } footer: {
                    Text("아래 편집을 누르면 끌어서 순서를 바꿔요. 정렬 메뉴로 한 번에 바꿀 수도 있어요. 작성시간 정렬은 글번호 기준이에요.")
                }
            }
            .navigationTitle("시리즈 만들기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else {
                        Button("만들기") { submit() }
                            .disabled(!canSubmit)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Menu {
                        ForEach(SeriesSort.allCases) { s in
                            Button {
                                entries = s.apply(entries)
                            } label: {
                                Label(s.title, systemImage: s.icon)
                            }
                        }
                    } label: {
                        Label("정렬", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(entries.count < 2)
                    Button {
                        showLoad = true
                    } label: {
                        Label("불러오기", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        saveSeries()
                    } label: {
                        Label("저장", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!canSave)
                    EditButton()
                }
            }
            .sheet(isPresented: $showPicker) {
                SeriesPostPicker(added: Set(entries.map(\.id))) { picked in
                    notice = addEntries(picked, skippedFormat: 0)
                }
            }
            .sheet(isPresented: $showLoad) {
                SeriesLoadSheet { s in
                    title = s.title
                    entries = s.entries
                    loadedID = s.id
                    notice = nil
                }
            }
            .alert("시리즈", isPresented: $showSaved) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(savedMessage)
            }
            .tint(DCTheme.accent)
        }
        .sheetUnderBlueBar(medium: false)
    }

    /// 주소 칸에 넣은 줄들을 게시물로 더함
    private func addTyped() {
        let lines = typedURL.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var found: [SeriesEntry] = []
        var bad = 0
        for line in lines {
            if let e = SeriesEntry.from(text: line) { found.append(e) } else { bad += 1 }
        }
        typedURL = ""
        notice = addEntries(found, skippedFormat: bad)
    }

    /// 여러 개를 넣음. 이미 있는 글·디시 글 주소가 아닌 것·50개를 넘는 것은 건너뛰고, 그 결과를 안내 문구로 돌려줌
    private func addEntries(_ new: [SeriesEntry], skippedFormat: Int) -> String {
        var added = 0, duplicate = 0, over = 0
        for e in new {
            if entries.contains(where: { $0.id == e.id }) { duplicate += 1; continue }
            guard entries.count < Self.maxEntries else { over += 1; continue }
            entries.append(e)
            added += 1
        }
        var parts = ["\(added)개 추가"]
        if skippedFormat > 0 { parts.append("디시 글 주소가 아닌 \(skippedFormat)개 건너뜀") }
        if duplicate > 0 { parts.append("이미 있는 \(duplicate)개 건너뜀") }
        if over > 0 { parts.append("\(Self.maxEntries)개 한도로 \(over)개 건너뜀") }
        return parts.joined(separator: ", ")
    }

    /// 제목·게시물을 저장 목록에 넣음. 불러온 시리즈면 그 항목을 바꿈
    private func saveSeries() {
        guard canSave else { return }
        let item = SavedSeries(id: loadedID ?? UUID(), title: trimmedTitle, entries: entries, savedAt: Date())
        let updating = SeriesStore.shared.items.contains { $0.id == item.id }
        SeriesStore.shared.upsert(item)
        loadedID = item.id
        savedMessage = updating
            ? "‘\(item.title)’ 시리즈를 바꿔 저장했어요."
            : "‘\(item.title)’ 시리즈를 저장했어요. 불러오기에서 다시 쓸 수 있어요."
        showSaved = true
    }

    private func submit() {
        guard canSubmit else { return }
        submitting = true
        let t = trimmedTitle
        let list = entries.map { $0.url.absoluteString }
        let count = existing
        Task {
            let result = await model.submitSeries(title: t, urls: list, existing: count)
            submitting = false
            if result == "ok" { dismiss() }
        }
    }
}

/// 글 보관함 / 최근 본 글에서 게시물을 골라 시리즈에 더함 (여러 개 선택, 고른 순서대로 들어감)
private struct SeriesPostPicker: View {
    /// 이미 시리즈에 들어 있는 글 (고를 수 없게 표시)
    let added: Set<String>
    let onAdd: ([SeriesEntry]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source = 0            // 0 = 글 보관함, 1 = 최근 본 글
    @State private var candidates: [SeriesEntry] = []
    @State private var picked: [SeriesEntry] = []
    @State private var query = ""

    /// 최근 본 글은 목록이 길어질 수 있어서 최근 것만
    private static let readLimit = 500

    private var shown: [SeriesEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return candidates }
        return candidates.filter { $0.displayTitle.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("출처", selection: $source) {
                        Text("글 보관함").tag(0)
                        Text("최근 본 글").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    if shown.isEmpty {
                        Text(emptyText)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shown) { e in
                        row(e)
                    }
                } footer: {
                    Text("여러 개를 고르면 고른 순서대로 들어가요. 최근 본 글은 최근 \(Self.readLimit)개까지 보여요.")
                }
            }
            .searchable(text: $query, prompt: "제목으로 찾기")
            .navigationTitle("게시물 고르기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가 (\(picked.count))") {
                        onAdd(picked)
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear { reload() }
            .onChangeCompat(of: source) { _, _ in reload() }
        }
        .tint(DCTheme.accent)
        .sheetUnderBlueBar(medium: false)
    }

    private var emptyText: String {
        if !query.isEmpty { return "검색 결과가 없어요." }
        return source == 0 ? "보관한 글이 없어요." : "최근에 읽은 글이 없어요."
    }

    @ViewBuilder
    private func row(_ e: SeriesEntry) -> some View {
        let isAdded = added.contains(e.id)
        let isPicked = picked.contains { $0.id == e.id }
        let info = [e.subtitle, e.date?.formatted(date: .abbreviated, time: .omitted)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        Button {
            if isPicked {
                picked.removeAll { $0.id == e.id }
            } else {
                picked.append(e)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.displayTitle).lineLimit(2)
                    if !info.isEmpty {
                        Text(info).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isAdded {
                    Text("추가됨").font(.caption).foregroundStyle(.secondary)
                } else {
                    Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isPicked ? DCTheme.accent : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
    }

    private func reload() {
        if source == 0 {
            candidates = SavedPostStore.shared.posts.compactMap {
                SeriesEntry.make(url: $0.url, title: $0.title, date: $0.savedAt)
            }
        } else {
            candidates = ReadPostStore.shared.items.prefix(Self.readLimit).compactMap { item in
                PostKey.url(item.key).flatMap { SeriesEntry.make(url: $0, title: item.title, date: item.date) }
            }
        }
    }
}

/// 저장해 둔 시리즈 목록 (누르면 그 시리즈로 채움, 밀어서 지우기)
private struct SeriesLoadSheet: View {
    let onPick: (SavedSeries) -> Void
    @ObservedObject private var store = SeriesStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.items.isEmpty {
                    Text("저장한 시리즈가 없어요. 시리즈를 만든 뒤 ‘저장’을 누르면 여기 남아요.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.items) { s in
                    Button {
                        onPick(s)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).lineLimit(1)
                            Text("게시물 \(s.entries.count)개 · \(s.savedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { store.delete(at: $0) }
            }
            .navigationTitle("저장한 시리즈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .tint(DCTheme.accent)
        }
        .sheetUnderBlueBar(medium: false)
    }
}
