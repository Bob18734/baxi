import SwiftUI
import UIKit

// Baxi's design system. Every screen takes its colors, type, spacing and corner radii from here;
// scripts/design-lint.sh fails if a screen writes a raw value instead.
//
// The look comes from US road signs, the thing a new driver is learning to read: guide-sign green
// panels with a white rule inset from the edge, warning yellow, school-zone yellow-green, and
// Overpass, an open-source typeface drawn after the Highway Gothic alphabet on US signs
// (SIL Open Font License, Baxi/Resources/Fonts/OFL.txt). Body text stays in the system font so it
// follows the reader's Dynamic Type size.

// MARK: - Color

enum BaxiColor {
    /// Guide-sign green. Fills sign panels and primary buttons; white text on it.
    static let sign = Color(hex: 0x00674A)
    /// Pressed buttons and the night Drive card.
    static let signDeep = Color(hex: 0x004A35)
    /// Green used for text and icons on the page (lighter in dark mode so it stays readable).
    static let accent = dynamic(light: 0x00674A, dark: 0x4FD09A)
    /// Warning-sign yellow: the lit lane, warnings, the highlight in the icon.
    static let warning = Color(hex: 0xFFCC00)
    /// School-zone signs use fluorescent yellow-green in the MUTCD.
    static let school = Color(hex: 0xC6DC00)
    /// Crash-heavy roads: orange, like work-zone signs.
    static let caution = Color(hex: 0xF27A1A)
    /// Stop-sign red: End drive and destructive actions only.
    static let stop = Color(hex: 0xC8102E)
    /// Error text on the page (stop red is too dark to read on the dark surface).
    static let stopText = dynamic(light: 0xC8102E, dark: 0xFF6B6B)
    /// The route line on maps.
    static let route = Color(hex: 0x1F6FEB)
    /// Ink on yellow and white sign faces.
    static let signInk = Color(hex: 0x111111)

    static let page = dynamic(light: 0xF3F2EE, dark: 0x0D100F)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x181C1A)
    static let sunken = dynamic(light: 0xE8E7E2, dark: 0x242927)
    static let ink = dynamic(light: 0x141715, dark: 0xF1F3F2)
    /// Secondary text you read (sentences, values).
    static let inkSoft = dynamic(light: 0x545B57, dark: 0xA9B0AC)
    /// Labels only: eyebrows, units, captions you glance at.
    static let inkFaint = dynamic(light: 0x6B726E, dark: 0x8E9692)
    static let hairline = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.10)
    /// Text and marks on sign green.
    static let onSign = Color.white

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha) })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// Only for this file. Screens use BaxiColor.
    fileprivate init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

// MARK: - Type

/// Overpass (sign lettering) is for things that are signs: screen titles, sign faces, the big numbers.
/// Everything you read or tap is the system font, so it feels like iOS and follows Dynamic Type.
enum BaxiFont {
    // Display (Overpass)
    static let hero = overpass("Black", 40, .largeTitle)
    static let title = overpass("ExtraBold", 28, .title)
    // Reading and tapping (system)
    static let section = Font.title3.weight(.bold)
    static let headline = Font.headline
    static let button = Font.body.weight(.semibold)
    /// The big numbers: distance to the turn, hours driven.
    static let number = overpass("Black", 36, .largeTitle)
    static let numberSmall = overpass("ExtraBold", 24, .title2)
    // Utility
    static let body = Font.body
    static let bodyBold = Font.body.weight(.semibold)
    static let callout = Font.callout
    static let footnote = Font.footnote
    static let caption = Font.caption.weight(.medium)
    /// A section's name over its content: "Practice routes".
    static let eyebrow = Font.subheadline.weight(.semibold)

    /// Fixed sizes for sign faces, which are drawn objects and do not scale with text size.
    static func signFace(_ size: CGFloat, weight: String = "Black") -> Font { .custom("Overpass-\(weight)", fixedSize: size) }

    private static func overpass(_ weight: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
        .custom("Overpass-\(weight)", size: size, relativeTo: style)
    }
}

// MARK: - Spacing and radius

enum BaxiSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Side margin of every scrolling screen.
    static let page: CGFloat = 20
}

enum BaxiRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 18
    static let xl: CGFloat = 26
}

// MARK: - Surfaces

extension View {
    /// A guide-sign panel: green, rounded, with the white rule inset from the edge.
    func signPanel(radius: CGFloat = BaxiRadius.lg, deep: Bool = false) -> some View {
        self
            .foregroundStyle(BaxiColor.onSign)
            .background(deep ? BaxiColor.signDeep : BaxiColor.sign, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius - 5, style: .continuous)
                    .inset(by: 5)
                    .strokeBorder(BaxiColor.onSign.opacity(0.9), lineWidth: 2)
            )
    }

    /// A white (or dark) card on the page.
    func card(radius: CGFloat = BaxiRadius.lg, padding: CGFloat = BaxiSpace.lg) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BaxiColor.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(BaxiColor.hairline, lineWidth: 1))
    }

    /// The page background behind scrolling screens.
    func baxiPage() -> some View {
        self.background(BaxiColor.page.ignoresSafeArea())
    }
}

/// A section's name over its content, in sentence case like iOS's own grouped lists.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(BaxiFont.eyebrow)
            .foregroundStyle(BaxiColor.inkSoft)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons

struct BaxiButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, stop, onSign }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BaxiFont.button)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, BaxiSpace.lg)
            .foregroundStyle(foreground)
            .background(background(pressed: configuration.isPressed),
                        in: RoundedRectangle(cornerRadius: BaxiRadius.md, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, down in if down { Haptics.tap() } }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .stop: BaxiColor.onSign
        case .secondary: BaxiColor.ink
        case .onSign: BaxiColor.sign
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: pressed ? BaxiColor.signDeep : BaxiColor.sign
        case .secondary: pressed ? BaxiColor.sunken.opacity(0.6) : BaxiColor.sunken
        case .stop: BaxiColor.stop.opacity(pressed ? 0.8 : 1)
        case .onSign: BaxiColor.onSign.opacity(pressed ? 0.85 : 1)
        }
    }
}

extension ButtonStyle where Self == BaxiButtonStyle {
    static var baxiPrimary: BaxiButtonStyle { BaxiButtonStyle(kind: .primary) }
    static var baxiSecondary: BaxiButtonStyle { BaxiButtonStyle(kind: .secondary) }
    static var baxiStop: BaxiButtonStyle { BaxiButtonStyle(kind: .stop) }
    static var baxiOnSign: BaxiButtonStyle { BaxiButtonStyle(kind: .onSign) }
}

/// A card-shaped button that dims slightly while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in if down { Haptics.tap() } }
    }
}

// MARK: - Loading

/// A soft moving sheen over a placeholder, used while something loads. Baxi never shows a spinner
/// where the shape of the content is known.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        if reduceMotion { content } else { moving(content) }
    }

    private func moving(_ content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                }
                .clipped()
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

// MARK: - Haptics

/// Haptics are for the person tapping (the passenger, or the driver while parked). Nothing in a
/// moving drive relies on them.
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let notify = UINotificationFeedbackGenerator()

    static func tap() { light.impactOccurred() }
    static func success() { notify.notificationOccurred(.success) }
    static func warning() { notify.notificationOccurred(.warning) }
}

// MARK: - App chrome

enum BaxiChrome {
    /// Navigation bar titles in Overpass, to match the sign lettering.
    static func apply() {
        let large = UIFont(name: "Overpass-Black", size: 34) ?? .systemFont(ofSize: 34, weight: .heavy)
        let inline = UIFont(name: "Overpass-ExtraBold", size: 18) ?? .systemFont(ofSize: 17, weight: .bold)
        let ink = UIColor(BaxiColor.ink)
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: large, .foregroundColor: ink]
        UINavigationBar.appearance().titleTextAttributes = [.font: inline, .foregroundColor: ink]
    }
}
