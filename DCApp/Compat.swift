import SwiftUI

// iOS 16 지원용 얇은 대체 구현 (iOS 17 이상에서는 시스템 것을 그대로 씀)

extension View {
    /// onChange(of:initial:_:) (iOS 17) 대체: 이전 값과 새 값을 함께 받음
    func onChangeCompat<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View {
        modifier(OnChangeCompat(value: value, initial: initial, action: action))
    }

    /// safeAreaPadding(.bottom, x) (iOS 17) 대체
    @ViewBuilder
    func safeAreaPaddingBottomCompat(_ length: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.safeAreaPadding(.bottom, length)
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: length) }
        }
    }

    /// 작은 화면에서도 팝오버로 (iOS 16.4부터, 그 아래는 시트로 뜸)
    @ViewBuilder
    func popoverAdaptationCompat() -> some View {
        if #available(iOS 16.4, *) { self.presentationCompactAdaptation(.popover) } else { self }
    }

    /// 시트·전체 화면 덮개의 배경 (iOS 16.4부터, 그 아래는 기본 배경)
    @ViewBuilder
    func presentationBackgroundCompat<S: ShapeStyle>(_ style: S) -> some View {
        if #available(iOS 16.4, *) { self.presentationBackground(style) } else { self }
    }

    /// 하드웨어 키보드 Tab 키 (iOS 17 이상에서만 동작)
    @ViewBuilder
    func onTabKeyCompat(_ action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, *) {
            self.onKeyPress(.tab) { action(); return .handled }
        } else {
            self
        }
    }
}

private struct OnChangeCompat<V: Equatable>: ViewModifier {
    let value: V
    let initial: Bool
    let action: (V, V) -> Void
    @State private var previous: V

    init(value: V, initial: Bool, action: @escaping (V, V) -> Void) {
        self.value = value
        self.initial = initial
        self.action = action
        _previous = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onChange(of: value, initial: initial, action)
        } else {
            content
                .onChange(of: value) { new in
                    let old = previous
                    previous = new
                    action(old, new)
                }
                .onAppear { if initial { action(value, value) } }
        }
    }
}

/// ContentUnavailableView (iOS 17) 대체: 비어 있을 때 가운데 안내
struct EmptyStateView<Label: View, Desc: View, Actions: View>: View {
    @ObservedObject var fonts = FontStore.shared
    private let label: Label
    private let desc: Desc
    private let actions: Actions

    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Desc = { EmptyView() }, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.label = label(); self.desc = description(); self.actions = actions()
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView { label } description: { desc } actions: { actions }
        } else {
            VStack(spacing: 10) {
                label.font(fonts.styleFont(.title3, weight: .semibold)).multilineTextAlignment(.center)
                desc.font(fonts.styleFont(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                actions
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension EmptyStateView where Label == SwiftUI.Label<Text, Image>, Desc == Text?, Actions == EmptyView {
    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, systemImage: systemImage) }, description: { description }, actions: { EmptyView() })
    }
}
