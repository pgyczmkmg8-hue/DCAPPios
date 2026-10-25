import SwiftUI
import Combine

/// 디시 알림 (내 글·댓글에 달린 댓글 등) — 디시 모바일이 화면 아래에 띄우는 알림 배너와 같은 데이터
/// 페이지가 몰래 불러오는 /alarm/notification 응답을 가로채서 쌓아 둠 → 하단 바 '갤러리' 창의 '알림' 탭
struct AlarmItem: Codable, Identifiable, Hashable {
    let galleryID: String
    let postNo: Int
    let commentNo: Int?
    let type: String
    let subject: String
    var receivedAt: Date
    var read: Bool = false

    var id: String { "\(galleryID)-\(postNo)-\(commentNo ?? 0)-\(type)" }

    var url: URL {
        URL(string: "https://m.dcinside.com/board/\(galleryID)/\(postNo)" + (commentNo != nil ? "#comment_box" : ""))!
    }

    var title: String { commentNo != nil ? "새 댓글" : "알림" }
}

@MainActor
final class AlarmStore: ObservableObject {
    static let shared = AlarmStore()
    private let key = "alarmItems"

    @Published private(set) var items: [AlarmItem] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
        }
    }

    var unreadCount: Int { items.filter { !$0.read }.count }

    /// 방금 새로 들어온 알림 (앱 사용 중 화면 위 배너용). more: 같이 들어온 나머지 개수
    @Published var incoming: (item: AlarmItem, more: Int)?
    static let bannerKey = "alarmBanner"
    static var bannerEnabled: Bool { UserDefaults.standard.object(forKey: bannerKey) as? Bool ?? true }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([AlarmItem].self, from: data) {
            items = saved
        }
    }

    /// 페이지에서 받은 알림 목록 (이미 있는 건 건너뜀, 새것은 맨 위에)
    func add(_ raw: [[String: Any]]) {
        func int(_ v: Any?) -> Int? {
            if let n = v as? NSNumber { return n.intValue }
            if let s = v as? String { return Int(s) }
            return nil
        }
        let known = Set(items.map(\.id))
        var new: [AlarmItem] = []
        for d in raw {
            guard let gid = d["gallery_id"] as? String, let no = int(d["gallery_no"]) else { continue }
            let subject = (d["subject"] as? String ?? "")
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#039;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&")
            let item = AlarmItem(galleryID: gid, postNo: no, commentNo: int(d["comment_no"]),
                                 type: d["type"] as? String ?? "", subject: subject, receivedAt: Date())
            if !known.contains(item.id), !new.contains(where: { $0.id == item.id }) { new.append(item) }
        }
        guard !new.isEmpty else { return }
        var list = new + items
        if list.count > 300 { list.removeLast(list.count - 300) }
        items = list
        if Self.bannerEnabled, let first = new.first { incoming = (first, new.count - 1) }
    }

    func markRead(_ item: AlarmItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }), !items[i].read else { return }
        items[i].read = true
    }

    func markAllRead() { items = items.map { var x = $0; x.read = true; return x } }
    func remove(at offsets: IndexSet) { items.remove(atOffsets: offsets) }
    func removeAll() { items = [] }
}

/// 갤러리 창 → 알림 탭
struct AlarmsList: View {
    @ObservedObject private var store = AlarmStore.shared
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
            ForEach(store.items) { a in
                Button {
                    store.markRead(a)
                    router.open(a.url)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(a.read ? Color.clear : DCTheme.accent)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a.subject.isEmpty ? "(제목 없음)" : a.subject)
                                .foregroundStyle(a.read ? .secondary : .primary)
                                .lineLimit(2)
                            Text("\(a.title) · \(a.galleryID) · \(a.receivedAt.shortKorean)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { store.remove(at: $0) }
        }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView("받은 알림이 없어요", systemImage: "bell",
                                       description: Text("로그인한 상태로 디시를 보는 동안 내 글·댓글에 달린 새 댓글 알림이 여기에 쌓여요."))
            }
        }
    }
}


/// 앱 사용 중 새 알림이 오면 화면 위에 잠깐 뜨는 배너 (누르면 그 글로, 위로 밀면 닫힘)
struct AlarmBanner: View {
    let item: AlarmItem
    let more: Int
    let onTap: () -> Void
    let onClose: () -> Void
    @State private var dragY: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.title3)
                .foregroundStyle(DCTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title + (more > 0 ? " 외 \(more)개" : ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.subject.isEmpty ? item.galleryID : item.subject)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .offset(y: min(0, dragY))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .gesture(
            DragGesture()
                .onChanged { dragY = $0.translation.height }
                .onEnded { v in
                    if v.translation.height < -30 { onClose() } else { withAnimation(.spring) { dragY = 0 } }
                }
        )
    }
}
