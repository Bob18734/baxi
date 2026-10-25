import SwiftUI
import UIKit

// Baxi's design tokens. Every colour, type role, space, corner, animation and haptic the screens use is
// named here, with the value docs/DESIGN.md gives it. Screens never write a raw number or hex value;
// scripts/design-lint.sh checks.

// MARK: - Colour

/// Each colour has one meaning (docs/DESIGN.md). Contrast is measured against the colour it sits on.
enum Palette {
    /// The ground of every planning screen: a cool, overcast daylight grey.
    static let page = Color(hex: 0xEEF1F3)
    /// Things you type into or pick from.
    static let field = Color(hex: 0xFFFFFF)
    /// A shimmer's lighter band, and a pressed row.
    static let lift = Color(hex: 0xF7F9FA)
    /// Headlines, numbers, main text. 14.6:1 on page.
    static let ink = Color(hex: 0x14202A)
    /// Text you read that is not the headline. 6.8:1 on page.
    static let read = Color(hex: 0x475561)
    /// Times, distances, small facts. 5.0:1 on page.
    static let meta = Color(hex: 0x5B6873)
    /// Words you glance at (tab labels, hints). 3.5:1 on page; steps to `meta` with Increase Contrast or Bold Text.
    static let label = Color(UIColor { t in
        t.accessibilityContrast == .high || t.legibilityWeight == .bold ? UIColor(hex: 0x5B6873) : UIColor(hex: 0x75818B)
    })
    /// The only separator.
    static let hairline = Color(hex: 0xD5DBDF)
    /// An empty track behind a progress bar or ring.
    static let track = Color(hex: 0xDDE2E6)

    /// Go: the main action, you're on track, done. Ink text on it (7.4:1).
    static let go = Color(hex: 0x22C58B)
    /// Green words on the page. 4.7:1.
    static let goText = Color(hex: 0x0B7A55)
    /// Get ready: the lane to move into, a heads-up, over the limit. Ink text on it (9.2:1).
    static let ready = Color(hex: 0xF5B700)
    /// Amber words on the page. 5.2:1.
    static let readyText = Color(hex: 0x8A5A00)
    /// Stop: End drive, delete, errors. White text on it (5.2:1).
    static let stop = Color(hex: 0xD0263E)
    /// Red words on the page. 6.0:1.
    static let stopText = Color(hex: 0xB3172F)
    /// Text on `stop`.
    static let onStop = Color.white

    /// The Drive screen's ground after sunset (the only dark screen).
    static let night = Color(hex: 0x0D171E)
    /// A raised panel on `night`.
    static let nightPanel = Color(hex: 0x16242E)
    /// Text you read on `night`. 8.8:1.
    static let nightRead = Color(hex: 0xA9B6BF)
    /// Separators and empty tracks on `night`.
    static let nightLine = Color(hex: 0x2A3A45)
    /// The main text on `night` (and on `ink` panels).
    static let onDark = Color(hex: 0xF4F7F9)
    /// An empty track on an ink or night panel.
    static let panelTrack = Color(hex: 0xF4F7F9).opacity(0.15)
    /// A lane that is not the one to be in, on an ink or night panel.
    static let panelLane = Color(hex: 0xF4F7F9).opacity(0.08)
    /// The one shadow: under the map's panel.
    static let shadow = Color(hex: 0x14202A).opacity(0.14)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Type

/// Named type roles. Atkinson Hyperlegible Next (the Braille Institute's face for telling look-alike letters
/// apart) for headlines, numbers, buttons and the Drive screen; the system font for reading text, so it follows
/// the reader's text size.
enum TypeRole {
    case hero, screenTitle, driveDistance, driveInstruction, number, numberSmall, rowTitle, button, tab
    case body, bodyStrong, meta, group, metaStrong

    var font: Font {
        switch self {
        case .hero: Typeface.display(44, .extraBold, relativeTo: .largeTitle)
        case .screenTitle: Typeface.display(30, .extraBold, relativeTo: .title)
        case .driveDistance: Typeface.display(76, .extraBold, relativeTo: .largeTitle)
        case .driveInstruction: Typeface.display(28, .bold, relativeTo: .title)
        case .number: Typeface.display(40, .extraBold, relativeTo: .largeTitle)
        case .numberSmall: Typeface.display(24, .bold, relativeTo: .title2)
        case .rowTitle: Typeface.display(18, .bold, relativeTo: .headline)
        case .button: Typeface.display(18, .bold, relativeTo: .headline)
        case .tab: Typeface.fixed(11, .semiBold)
        case .body: .body
        case .bodyStrong: .body.weight(.semibold)
        case .meta: .footnote
        case .metaStrong: .footnote.weight(.semibold)
        case .group: .subheadline.weight(.semibold)
        }
    }

    /// Letter spacing in points: tight for big display type, open for the small tab label.
    var tracking: CGFloat {
        switch self {
        case .hero: -1.0
        case .screenTitle: -0.6
        case .driveDistance: -2.0
        case .driveInstruction: -0.3
        case .number: -1.0
        case .numberSmall: -0.4
        case .rowTitle: -0.2
        case .tab: 0.2
        default: 0
        }
    }
}

enum Typeface {
    enum Weight: String { case regular = "Regular", semiBold = "SemiBold", bold = "Bold", extraBold = "ExtraBold" }

    static func name(_ w: Weight) -> String { "AtkinsonHyperlegibleNext-\(w.rawValue)" }

    /// Display type that grows with the reader's text size (screens cap the largest sizes where a layout is fixed).
    static func display(_ size: CGFloat, _ w: Weight, relativeTo style: Font.TextStyle) -> Font {
        .custom(name(w), size: size, relativeTo: style)
    }

    /// Display type at a fixed size, for marks drawn at a set size (the bottom bar, a speed-limit sign).
    static func fixed(_ size: CGFloat, _ w: Weight) -> Font { .custom(name(w), fixedSize: size) }
}

extension View {
    /// Applies a type role: its face, size and tracking.
    func role(_ r: TypeRole) -> some View { font(r.font).tracking(r.tracking) }
}

extension Text {
    func role(_ r: TypeRole) -> Text { font(r.font).tracking(r.tracking) }
}

// MARK: - Space, corners, sizes

enum Space {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48
    /// Left and right page margin.
    static let margin: CGFloat = 20
}

enum Corner {
    /// Fields, tiles, imagery.
    static let control: CGFloat = 12
    /// The top of sheets and the map panel.
    static let sheet: CGFloat = 22
}

enum Size {
    /// Smallest tap target.
    static let tap: CGFloat = 44
    /// Primary and secondary buttons.
    static let button: CGFloat = 56
    /// A field.
    static let field: CGFloat = 52
    /// A list row's minimum height.
    static let row: CGFloat = 56
    /// The bottom bar, above the home indicator.
    static let bar: CGFloat = 58
    /// Hairline width.
    static let hairline: CGFloat = 1
    /// Stroke of the drawn marks on their 24 pt grid.
    static let stroke: CGFloat = 2.25
    /// A progress bar's thickness.
    static let progress: CGFloat = 6
    /// The rule beside a quoted passage.
    static let quoteRule: CGFloat = 2
    /// A secondary button's outline.
    static let outline: CGFloat = 1.5
}

/// Sizes of the drawn marks.
enum MarkSize {
    static let tiny: CGFloat = 16
    static let small: CGFloat = 18
    static let row: CGFloat = 20
    static let inline: CGFloat = 22
    static let standard: CGFloat = 24
    static let car: CGFloat = 26
    static let lane: CGFloat = 30
    static let feature: CGFloat = 56
}

/// The signal mark's heights: in a corner, on the map, on the welcome screen.
enum SignalSize {
    static let corner: CGFloat = 28
    static let map: CGFloat = 30
    static let welcome: CGFloat = 64
}

/// Stroke weights of the drawn marks, as multiples of the 2.25 pt line.
enum MarkWeight {
    static let regular: CGFloat = 1
    static let emphasis: CGFloat = 1.25
    static let heavy: CGFloat = 1.4
    static let drive: CGFloat = 1.6
}

// MARK: - Motion

enum Motion {
    /// Taps.
    static let quick = Animation.easeOut(duration: 0.18)
    /// Content changes.
    static let standard = Animation.smooth(duration: 0.3)
    /// Big reveals: a score ring filling, the welcome signal.
    static let reveal = Animation.smooth(duration: 0.6)
    /// Anything tactile: presses, a marker sliding to a new tab.
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
    /// The Drive map following the car, and the bar that empties toward a turn: steady, no easing.
    static let follow = Animation.linear(duration: 0.25)
    /// The chevrons sweeping toward the lane to be in.
    static let sweep = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: false)
}

// MARK: - Haptics

/// Named by meaning. Only for the person tapping; nothing in a moving drive depends on one.
enum Haptic {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notify = UINotificationFeedbackGenerator()

    static func tap() { light.impactOccurred() }
    static func success() { notify.notificationOccurred(.success) }
    static func error() { notify.notificationOccurred(.error) }
    static func reveal() { soft.impactOccurred(intensity: 0.8) }
}
