import SwiftUI

/// 설정 → 버전 정보/업데이트 확인
/// 사진은 아래 aboutImages 목록에서 확률(가중치)에 따라 하나를 골라 보여 줘요. (화면에 들어올 때마다 새로 뽑음)
struct AboutView: View {
    /// ★ 버전 정보 사진 목록: (Assets의 Image Set 이름, 뽑힐 비율)
    /// 비율은 합이 100이 아니어도 돼요 — 예) 70, 20, 10 이면 70% / 20% / 10%
    /// 사진을 추가하려면: Assets에 Image Set을 만들고 이름을 정한 뒤 여기에 한 줄 추가
    /// (Assets에 없는 이름은 자동으로 빠짐)
    static let aboutImages: [(name: String, weight: Double)] = [
        ("AboutImage0", 30),
        ("AboutImage1", 25),
        ("AboutImage2", 20),
        ("AboutImage3", 15),
        ("AboutImage4", 10),
        ("AboutImage5", 100),
    ]

    /// 확률에 따라 하나 뽑기 (excluding: 방금 보던 사진은 빼고 — 다른 사진이 없으면 그대로)
    static func pickImage(excluding current: String? = nil) -> (name: String, image: UIImage)? {
        var pool = aboutImages.compactMap { item -> ((name: String, image: UIImage), Double)? in
            guard item.weight > 0, let img = UIImage(named: item.name) else { return nil }
            return ((item.name, img), item.weight)
        }
        if pool.count > 1 { pool.removeAll { $0.0.name == current } }
        let total = pool.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var r = Double.random(in: 0..<total)
        for (img, w) in pool {
            if r < w { return img }
            r -= w
        }
        return pool.last?.0
    }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }
    static var versionString: String { "\(version) (\(build))" }

    /// 사진이 없을 때 보여주는 자리
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.quaternary)
            .frame(width: 200, height: 200)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.largeTitle)
                    Text("Assets에 AboutImage를\n추가하면 여기에 보여요")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
    }

    /// 업데이트 화면으로 가는 줄 + 진단 메뉴 스위치
    private var updateBox: some View {
        VStack(spacing: 0) {
            NavigationLink {
                UpdateView()
            } label: {
                HStack {
                    Text("업데이트")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 12)
            Divider()
            Toggle("메뉴에 페이지 구조 진단 보이기", isOn: $showDiagnoseMenu)
                .padding(.vertical, 10)
            Divider()
            Toggle("성능 숫자 보이기 (메모리·CPU)", isOn: $showPerfHUD)
                .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: 420)
    }

    /// 광고 차단 (설정 화면에서 옮겨 옴)
    private var adBlockBox: some View {
        Toggle("광고 차단", isOn: $adBlock)
            .onChange(of: adBlock) { _, _ in
                NotificationCenter.default.post(name: DC.filtersChanged, object: nil)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: 420)
    }

    private func photoTapped() {
        confetti += 1
        guard !adBlockUnlocked else { return }
        photoTaps += 1
        if photoTaps >= 10 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation { adBlockUnlocked = true }
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "DCApp"
    }

    @State private var confetti = 0
    @State private var image: (name: String, image: UIImage)? = AboutView.pickImage()
    @AppStorage("showDiagnoseMenu") private var showDiagnoseMenu = false
    @AppStorage("showPerfHUD") private var showPerfHUD = false
    @AppStorage(AdBlock.key) private var adBlock = true
    /// 광고 차단 스위치는 처음엔 숨김 — 사진을 10번 누르면 나타나고 그 뒤로 계속 보임
    @AppStorage("adBlockUnlocked") private var adBlockUnlocked = false
    @State private var photoTaps = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let image {
                    Image(uiImage: image.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                        .onTapGesture {                      // 사진을 누르면 다시 뽑고 한 번 더 축하
                            self.image = AboutView.pickImage(excluding: image.name)
                            photoTapped()
                        }
                } else {
                    placeholder
                        .onTapGesture { photoTapped() }
                }

                VStack(spacing: 6) {
                    Text(appName)
                        .font(.title2.bold())
                    Text("버전 \(Self.version) (빌드 \(Self.build))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                updateBox
                if adBlockUnlocked { adBlockBox }

            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .padding(.horizontal)
        }
        .overlay {
            ConfettiView(trigger: confetti)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
        .onAppear {
            confetti += 1                                       // 들어오면 축하 꽃가루
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .navigationTitle("버전 정보/업데이트 확인")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 버전 정보 → 업데이트: 자동 확인, 지금 확인, 사이드로드 앱으로 바로 설치
struct UpdateView: View {
    @AppStorage(UpdateChecker.autoCheckKey) private var autoCheck = true
    @AppStorage(UpdateChecker.Frequency.storageKey) private var frequency: UpdateChecker.Frequency = .everyOpen
    @AppStorage(Installer.storageKey) private var installer: Installer = .feather
    @State private var checking = false
    @State private var checkResult: String?
    @State private var installing = false
    @State private var foundRelease: AppRelease?

    var body: some View {
        Form {
            Section {
                Toggle("업데이트 자동 확인", isOn: $autoCheck)
                if autoCheck {
                    Picker("확인 주기", selection: $frequency) {
                        ForEach(UpdateChecker.Frequency.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                }
                Button {
                    Task { await checkNow() }
                } label: {
                    HStack {
                        Text("업데이트 확인")
                        Spacer()
                        if checking { ProgressView() }
                    }
                }
                .disabled(checking)
            } footer: {
                Text("앱을 열 때 새 버전(예: 0.9.0 → 0.9.1)이 있으면 알려 줘요.\n지금 버전: \(AboutView.versionString)")
            }
            Section {
                Picker("바로 설치에 쓸 앱", selection: $installer) {
                    ForEach(Installer.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                Button {
                    Task { await install(with: installer) }
                } label: {
                    HStack {
                        Text("\(installer.name)로 바로 설치")
                        Spacer()
                        if installing { ProgressView() }
                    }
                }
                .disabled(installing)
            } footer: {
                Text("GitHub 최신 릴리즈의 ipa를 고른 앱으로 열어 설치해요.")
            }
            if let checkResult {
                Section {
                    Text(checkResult)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert(foundRelease.map { "새 버전 \($0.version)" } ?? "",
               isPresented: Binding(get: { foundRelease != nil }, set: { if !$0 { foundRelease = nil } }),
               presenting: foundRelease) { r in
            if let ipa = r.ipaURL, let url = installer.installURL(for: ipa) {
                Button("\(installer.name)로 바로 설치") { UIApplication.shared.open(url) }
            }
            Button("다운로드") { UIApplication.shared.open(r.ipaURL ?? r.pageURL) }
            Button("릴리스 노트 보기") { UIApplication.shared.open(r.pageURL) }
            Button("닫기", role: .cancel) {}
        } message: { r in
            let notes = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            Text("지금 버전: \(AboutView.version)" + (notes.isEmpty ? "" : "\n\n" + String(notes.prefix(300))))
        }
        .navigationTitle("업데이트")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 수동 확인: 패치 버전이라도 새것이면 알려 줌
    private func checkNow() async {
        checking = true
        checkResult = nil
        let latest = await UpdateChecker.fetchLatest()
        checking = false
        guard let latest else {
            checkResult = "확인하지 못했어요. 인터넷 연결을 확인해 주세요."
            return
        }
        if UpdateChecker.isNewerThanCurrent(latest.version) {
            foundRelease = latest
            checkResult = "새 버전 \(latest.version)이 있어요."
        } else {
            checkResult = "최신 버전이에요. (GitHub 최신: \(latest.version))"
        }
    }

    /// 최신 릴리즈 ipa를 사이드로드 앱으로 바로 설치
    enum Installer: String, CaseIterable {
        case feather, sideStore, liveContainer
        static let storageKey = "installerApp"
        /// 업데이트 화면에서 고른 앱 (업데이트 알림창의 '바로 설치'도 이걸로)
        static var current: Installer {
            Installer(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .feather
        }
        var name: String {
            switch self { case .feather: "Feather"; case .sideStore: "SideStore"; case .liveContainer: "LiveContainer" }
        }
        var scheme: String {
            switch self { case .feather: "feather"; case .sideStore: "sidestore"; case .liveContainer: "livecontainer" }
        }
        /// Feather는 feather://install/<ipa 주소> (주소를 그대로 뒤에 붙임),
        /// SideStore·LiveContainer는 <scheme>://install?url=<ipa 주소>
        func installURL(for ipa: URL) -> URL? {
            if self == .feather { return URL(string: "feather://install/" + ipa.absoluteString) }
            var c = URLComponents()
            c.scheme = scheme
            c.host = "install"
            c.queryItems = [URLQueryItem(name: "url", value: ipa.absoluteString)]
            return c.url
        }
    }

    private func install(with app: Installer) async {
        installing = true
        defer { installing = false }
        let release: AppRelease?
        if let foundRelease { release = foundRelease } else { release = await UpdateChecker.fetchLatest() }
        guard let ipa = release?.ipaURL else {
            checkResult = release == nil ? "최신 버전을 확인하지 못했어요. 인터넷 연결을 확인해 주세요."
                                         : "최신 릴리즈에 ipa 파일이 없어요."
            return
        }
        guard let url = app.installURL(for: ipa) else { return }
        if !(await UIApplication.shared.open(url)) {
            checkResult = "\(app.name)을(를) 열지 못했어요. 설치돼 있는지 확인해 주세요."
        }
    }
}
