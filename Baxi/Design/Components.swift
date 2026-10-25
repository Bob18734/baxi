import SwiftUI

// One of each component (docs/DESIGN.md): one way to press, to say "working", to say "done", one toast,
// one shimmer, one field, one row, one sheet header, one empty state.

// MARK: - Pressing

/// The one press: a dip to 0.95 and 0.7 opacity, springing back.
struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Pressed(configuration: configuration) }

    private struct Pressed: View {
        let configuration: ButtonStyleConfiguration
        /// A button that can't be used now looks it: faded, and it doesn't dip.
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1)
                .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .animation(Motion.quick, value: isEnabled)
                .contentShape(Rectangle())
        }
    }
}

/// The four kinds of button. `primary` is the one main action on a screen.
enum ButtonKind { case primary, secondary, quiet, danger }

/// A full-width button. While `working`, its label becomes the signal dots and it keeps its width.
struct BigButton: View {
    let title: String
    var kind: ButtonKind = .primary
    var glyph: Glyph? = nil
    var working = false
    let action: () -> Void

    var body: some View {
        Button(action: { if !working { Haptic.tap(); action() } }) {
            ZStack {
                HStack(spacing: Space.s8) {
                    if let glyph { Mark(glyph: glyph, size: MarkSize.row, weight: 1.15) }
                    // Two lines at the largest text sizes rather than a cut-off label.
                    Text(title).role(.button).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                }
                .opacity(working ? 0 : 1)
                if working { SignalDots(onFill: kind == .primary || kind == .danger) }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: Size.button)
            .background { background }
            .contentShape(Capsule())
        }
        .buttonStyle(Press())
        .animation(Motion.quick, value: working)
        .accessibilityLabel(working ? "\(title), working" : title)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Palette.ink
        case .secondary, .quiet: Palette.ink
        case .danger: Palette.onStop
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary: Capsule().fill(Palette.go)
        case .secondary: Capsule().strokeBorder(Palette.ink, lineWidth: Size.outline)
        case .quiet: Color.clear
        case .danger: Capsule().fill(Palette.stop)
        }
    }
}

/// A round button that is only a mark (Settings, Close, Add). Always labelled for VoiceOver.
struct MarkButton: View {
    let glyph: Glyph
    let label: String
    var tint: Color = Palette.ink
    let action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            Mark(glyph: glyph, size: MarkSize.inline).foregroundStyle(tint).frame(width: Size.tap, height: Size.tap)
        }
        .buttonStyle(Press())
        .accessibilityLabel(label)
    }
}

/// "Working": three small lamps lighting in turn, red, amber, green, like a signal changing. No spinners.
struct SignalDots: View {
    /// On a coloured button the unlit dots are ink; on the page they are the track grey.
    var onFill = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.32)) { t in
            let step = reduceMotion ? 2 : Int(t.date.timeIntervalSinceReferenceDate / 0.32) % 3
            HStack(spacing: Space.s8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == step ? [Palette.stop, Palette.ready, Palette.go][i] : (onFill ? Palette.ink.opacity(0.25) : Palette.track))
                        .frame(width: 10, height: 10)
                        .scaleEffect(i == step ? 1.15 : 1)
                }
            }
            .animation(Motion.quick, value: step)
        }
        .accessibilityLabel("Working")
    }
}

// MARK: - Toast

/// The one toast: a short ink capsule above the bottom bar, shown from anywhere through `ToastCenter`.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Equatable {
        let id = UUID()
        let message: String
        var actionTitle: String? = nil
        var isError = false
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }
    private(set) var current: Toast?
    @ObservationIgnored private var action: (() -> Void)?

    /// Shows a message for a few seconds. An action (Undo) keeps it up a little longer.
    func show(_ message: String, actionTitle: String? = nil, isError: Bool = false, action: (() -> Void)? = nil) {
        let t = Toast(message: message, actionTitle: actionTitle, isError: isError)
        self.action = action
        withAnimation(Motion.standard) { current = t }
        if isError { Haptic.error() }
        AccessibilityNotification.Announcement(message).post()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(actionTitle == nil ? 3 : 6))
            if current == t { withAnimation(Motion.standard) { current = nil } }
        }
    }

    func runAction() {
        let a = action
        action = nil
        withAnimation(Motion.standard) { current = nil }
        a?()
    }
}

struct ToastView: View {
    let toast: ToastCenter.Toast
    let onAction: () -> Void
    var body: some View {
        HStack(spacing: Space.s12) {
            if toast.isError { Mark(glyph: .crash, size: MarkSize.small).foregroundStyle(Palette.stop) }
            Text(toast.message).role(.bodyStrong).foregroundStyle(Palette.onDark)
                .fixedSize(horizontal: false, vertical: true)
            if let title = toast.actionTitle {
                Spacer(minLength: Space.s8)
                Button(title, action: onAction).role(.bodyStrong).foregroundStyle(Palette.go)
                    .buttonStyle(Press()).frame(minHeight: Size.tap)
            }
        }
        .padding(.horizontal, Space.s16)
        .padding(.vertical, Space.s12)
        .background(Palette.ink, in: Capsule())
        .padding(.horizontal, Space.margin)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Loading

/// The shape of what is coming, with a lighter band passing over it. Nothing claims a fact before it loads.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Palette.lift.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing) // design-lint:allow the shimmer band is the one gradient on chrome
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.4)
                }
                .clipped()
                .allowsHitTesting(false)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
            .accessibilityLabel("Loading")
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// A grey block the size of a line of text or a number, for loading states.
struct Placeholder: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var body: some View {
        RoundedRectangle(cornerRadius: height / 3, style: .continuous).fill(Palette.track)
            .frame(width: width, height: height)
            .shimmering()
    }
}

// MARK: - Page structure

extension View {
    /// The planning screens' ground.
    func pageBackground() -> some View { background(Palette.page.ignoresSafeArea()) }
}

/// A group's name above a list: sentence case, never a capitalised label.
struct GroupLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).role(.group).foregroundStyle(Palette.meta)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The one separator.
struct Hairline: View {
    var color: Color = Palette.hairline
    var body: some View { Rectangle().fill(color).frame(height: Size.hairline) }
}

/// A full-width row: a title, an optional line under it, something on the right, and a hairline under it.
struct Row<Leading: View, Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var showsDivider = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s12) {
                leading
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(title).role(.rowTitle).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail).role(.meta).foregroundStyle(Palette.meta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.s8)
                trailing
            }
            .padding(.vertical, Space.s12)
            .frame(minHeight: Size.row)
            if showsDivider { Hairline() }
        }
        .contentShape(Rectangle())
    }
}

extension Row where Leading == EmptyView {
    init(title: String, detail: String? = nil, showsDivider: Bool = true, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, detail: detail, showsDivider: showsDivider, leading: { EmptyView() }, trailing: trailing)
    }
}

/// The forward mark at the end of a row that opens something.
struct RowArrow: View {
    var body: some View { Mark(glyph: .forward, size: MarkSize.tiny).foregroundStyle(Palette.label) }
}

/// A sheet's top: its title on the left, a quiet Close or Done on the right.
struct SheetHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle = "Done"
    let action: () -> Void
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s12) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(title).role(.screenTitle).foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).role(.meta).foregroundStyle(Palette.meta) }
            }
            Spacer(minLength: Space.s8)
            Button(actionTitle) { Haptic.tap(); action() }
                .role(.bodyStrong).foregroundStyle(Palette.ink)
                .buttonStyle(Press()).frame(minHeight: Size.tap)
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s24)
        .padding(.bottom, Space.s16)
    }
}

/// An empty screen is an invitation to act: the signal, one sentence, one action.
struct EmptyState: View {
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            SignalMark(size: 40, lit: 2)
            Text(message).role(.body).foregroundStyle(Palette.read)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                BigButton(title: actionTitle, kind: .secondary, action: action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s24)
    }
}

// MARK: - Field

/// The one field look: white, radius 12, hairline edge.
struct FieldBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: Space.s12) { content }
            .padding(.horizontal, Space.s16)
            .frame(minHeight: Size.field)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: Corner.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Corner.control, style: .continuous).strokeBorder(Palette.hairline, lineWidth: Size.hairline))
    }
}

// MARK: - Progress

/// A thin bar toward a goal, in `go`.
struct ProgressLine: View {
    let fraction: Double
    var tint: Color = Palette.go
    var track: Color = Palette.track
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint)
                    .frame(width: max(Size.progress, geo.size.width * min(1, max(0, fraction))))
                    .opacity(fraction <= 0 ? 0 : 1)
            }
        }
        .frame(height: Size.progress)
        .animation(Motion.standard, value: fraction)
    }
}

/// A ring toward a goal: a skill, or a drive's score.
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 44
    var line: CGFloat = 5
    var tint: Color = Palette.go
    var animated = false
    @State private var shown = 0.0
    var body: some View {
        ZStack {
            // Inset by half the line, so the ring stays inside its frame.
            Circle().inset(by: line / 2).stroke(Palette.track, lineWidth: line)
            Circle().inset(by: line / 2).trim(from: 0, to: animated ? shown : min(1, fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .onAppear { if animated { withAnimation(Motion.reveal.delay(0.15)) { shown = min(1, fraction) } } }
        .accessibilityHidden(true)
    }
}

/// A skill's four levels as four short segments.
struct LevelSegments: View {
    let level: Int
    var body: some View {
        HStack(spacing: Space.s4) {
            ForEach(1...4, id: \.self) { i in
                Capsule().fill(i <= level ? Palette.go : Palette.track).frame(height: Size.progress)
            }
        }
        .animation(Motion.standard, value: level)
        .accessibilityHidden(true)
    }
}
