import SwiftUI
#if os(iOS)
import UIKit

/// iOS 16 has no `ShareLink`; the system share sheet does the same job.
enum SharePresenter {
    static func present(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
    }
}
#endif

/// The iOS app deploys to iOS 16, which lacks APIs the other platforms already have. Call sites use
/// these stand-ins; where the running system has the real API it is used, and iOS 16 degrades.

extension View {
    /// iOS 16's `onChange` closure takes the new value alone; iOS 17 and the other platforms already
    /// have the two-value form, so this stand-in exists only where the system one does not.
    @available(iOS, introduced: 16, obsoleted: 17)
    @available(macOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    func onChange<Value: Equatable>(of value: Value, initial: Bool = false, _ action: @escaping (Value, Value) -> Void) -> some View {
        modifier(OnChange16(value: value, initial: initial, action: action))
    }

    /// `controlSize` is macOS-only until iOS 18.
    @ViewBuilder func controlSizing(_ size: ControlSize) -> some View {
        #if os(macOS)
        controlSize(size)
        #else
        if #available(iOS 18, tvOS 18, *) { controlSize(size) } else { self }
        #endif
    }

    /// Symbol transitions and effects arrive with iOS 17; iOS 16 keeps the plain symbol.
    @ViewBuilder func contentTransition(_ transition: ContentTransition16) -> some View {
        if #available(iOS 17, macOS 14, tvOS 17, *) { self.contentTransition(transition.native) } else { self }
    }

    @ViewBuilder func symbolEffect(_ effect: SymbolEffect16) -> some View {
        if #available(iOS 17, macOS 14, tvOS 17, *) { self.modifier(SymbolEffect16Modifier(effect: effect)) } else { self }
    }

    /// `Shape` content shapes arrive in iOS 17; a rectangle covers the row either way.
    @ViewBuilder func contentShape(_ shape: RectShape16) -> some View {
        if #available(iOS 17, macOS 14, tvOS 17, *) { self.contentShape(shape.native) } else { self.contentShape(Rectangle()) }
    }

    func capsuleButtonBorder() -> some View { modifier(CapsuleBorder()) }

    func scrollIndicators(_ visibility: ScrollIndicatorVisibility16) -> some View { modifier(ScrollIndicators16(visibility: visibility)) }
    func scrollContentBackground(_ visibility: ScrollBackgroundVisibility16) -> some View { modifier(ScrollBackground16(visibility: visibility)) }
    func keyboardDismiss(_ mode: KeyboardDismiss16) -> some View { modifier(ScrollDismiss16(mode: mode)) }

    /// iOS 17. Content clipped at the scroll view's edge is the iOS 16 behaviour anyway.
    func scrollClipDisabled() -> some View { modifier(ScrollClip16()) }
}

enum ScrollIndicatorVisibility16 { case hidden, never, automatic
    @available(iOS 16, macOS 13, tvOS 16, *) var native: ScrollIndicatorVisibility {
        switch self { case .hidden: .hidden; case .never: .never; case .automatic: .automatic }
    }
}
enum ScrollBackgroundVisibility16 { case hidden
    #if !os(tvOS)
    @available(iOS 16, macOS 13, *) var native: Visibility { .hidden }
    #endif
}
enum KeyboardDismiss16 { case interactive
    @available(iOS 16, macOS 13, tvOS 16, *) var native: ScrollDismissesKeyboardMode { .interactively }
}

/// Records the previous value so callers can keep writing `{ old, new in }`.
private struct OnChange16<Value: Equatable>: ViewModifier {
    let value: Value
    let initial: Bool
    let action: (Value, Value) -> Void
    @State private var previous: Value?
    func body(content: Content) -> some View {
        content
            .onAppear { if initial, previous == nil { action(value, value) }; previous = value }
            .onChange(of: value) { newValue in
                action(previous ?? newValue, newValue)
                previous = newValue
            }
    }
}

/// Stand-in for `Color.mix`, which is iOS 18.
extension Color {
    func mix(with other: Color, by fraction: Double) -> Color {
        let amount = max(0, min(1, fraction))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        #if os(macOS)
        NSColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        NSColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #else
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #endif
        return Color(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount, opacity: a1 + (a2 - a1) * amount)
    }
}

/// Stand-in for `Duration.seconds(n).formatted(.time(pattern:))`.
enum Clock16 {
    static func minuteSecond(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
    static func hourMinuteSecond(_ seconds: Int) -> String { String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
}

enum ContentTransition16 { case symbolReplace, numericText
    @available(iOS 17, macOS 14, tvOS 17, *) var native: ContentTransition {
        switch self { case .symbolReplace: .symbolEffect(.replace); case .numericText: .numericText() }
    }
}
enum SymbolEffect16 { case variableColorIterative, variableColorIterativeActive(Bool), breathe }
enum RectShape16 { case rect, rounded(CGFloat)
    @available(iOS 17, macOS 14, tvOS 17, *) var native: some Shape {
        switch self { case .rect: AnyShape(Rectangle()); case .rounded(let radius): AnyShape(RoundedRectangle(cornerRadius: radius)) }
    }
}

@available(iOS 17, macOS 14, tvOS 17, *)
private struct SymbolEffect16Modifier: ViewModifier {
    let effect: SymbolEffect16
    func body(content: Content) -> some View {
        switch effect {
        case .variableColorIterative: content.symbolEffect(.variableColor.iterative)
        case .variableColorIterativeActive(let active): content.symbolEffect(.variableColor.iterative, isActive: active)
        case .breathe:
            if #available(iOS 18, macOS 15, tvOS 18, *) { content.symbolEffect(.breathe, options: .repeat(.periodic(delay: 2.5))) } else { content }
        }
    }
}

private struct ScrollIndicators16: ViewModifier {
    let visibility: ScrollIndicatorVisibility16
    func body(content: Content) -> some View { content.scrollIndicators(visibility.native) }
}
private struct ScrollBackground16: ViewModifier {
    let visibility: ScrollBackgroundVisibility16
    func body(content: Content) -> some View {
        // tvOS has no scroll background to hide, and the type itself is unavailable there.
        #if os(tvOS)
        content
        #else
        content.scrollContentBackground(visibility.native)
        #endif
    }
}
private struct ScrollDismiss16: ViewModifier {
    let mode: KeyboardDismiss16
    func body(content: Content) -> some View { content.scrollDismissesKeyboard(mode.native) }
}
private struct ScrollClip16: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, macOS 14, tvOS 17, *) { content.scrollClipDisabled() } else { content }
    }
}

private struct CapsuleBorder: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) { content.buttonBorderShape(.capsule) } else { content }
    }
}

/// `presentationBackground` and `presentationCornerRadius` are iOS 16.4.
struct DanmakuSheetChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, macOS 13.3, tvOS 16.4, *) {
            content.presentationBackground(.ultraThinMaterial).presentationCornerRadius(28)
        } else { content }
    }
}

/// `presentationBackground` is iOS 16.4; earlier systems keep the system sheet background.
struct SheetBackground<Backdrop: View>: ViewModifier {
    let backdrop: Backdrop
    func body(content: Content) -> some View {
        if #available(iOS 16.4, macOS 13.3, tvOS 16.4, *) { content.presentationBackground { backdrop } } else { content }
    }
}

/// `NavigationStack` is iOS 16; `NavigationView` does the same for a stack that only pushes.
struct AppNavigation<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { NavigationView { content() }.navigationViewStyle(.stack) }
}

/// Lays out the first alternative when it fits the width, otherwise the second.
struct FitsWidth<First: View, Second: View>: View {
    @ViewBuilder var first: () -> First
    @ViewBuilder var second: () -> Second
    var body: some View { ViewThatFits(in: .horizontal) { first(); second() } }
}

/// An icon, a title, an explanation and optional actions, centred.
struct EmptyState<Actions: View>: View {
    let title: String
    let symbol: String
    var detail: String?
    @ViewBuilder var actions: () -> Actions
    init(_ title: String, systemImage: String, description: String? = nil, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.title = title; self.symbol = systemImage; self.detail = description; self.actions = actions
    }
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            if let detail { Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            actions().padding(.top, 4)
        }
        .padding(32).frame(maxWidth: 460)
    }
}

/// Reports the distance scrolled and how far the content extends past the viewport, for horizontal
/// strips that fade their edges. iOS 18's `onScrollGeometryChange` does this directly.
struct ScrollMetrics: Equatable { var offset: CGFloat = 0, overflow: CGFloat = 0 }
struct ScrollMetricsKey: PreferenceKey {
    static var defaultValue: ScrollMetrics { ScrollMetrics() }
    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) { value = nextValue() }
}

extension View {
    func scrollMetrics(_ report: @escaping (_ offset: CGFloat, _ overflow: CGFloat) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ScrollMetricsKey.self, value: ScrollMetrics(offset: proxy.frame(in: .named("strip")).minX, overflow: proxy.size.width))
            }
        }
        .onPreferenceChange(ScrollMetricsKey.self) { metrics in report(-metrics.offset, max(0, metrics.overflow + metrics.offset)) }
    }
}
