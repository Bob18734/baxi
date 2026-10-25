import SwiftUI

/// Baxi's own bottom bar: Home, Routes in the middle (the reason you open the app), Log. It sits on the page
/// with one hairline above it and a fixed height; the active tab is ink with a heavier mark, a bolder label
/// and a short `go` bar under it, whose space is always reserved so labels never shift.
struct BottomBar: View {
    @Binding var selection: AppTab

    private let tabs: [(tab: AppTab, title: String, glyph: Glyph)] = [
        (.home, "Home", .signal), (.route, "Routes", .route), (.log, "Log", .log),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                ForEach(tabs, id: \.tab) { item in
                    let active = selection == item.tab
                    Button {
                        guard !active else { return }
                        Haptic.tap()
                        withAnimation(Motion.standard) { selection = item.tab }
                    } label: {
                        VStack(spacing: Space.s4) {
                            Mark(glyph: item.glyph, size: MarkSize.standard, weight: active ? MarkWeight.emphasis : MarkWeight.regular)
                            Text(item.title).role(.tab)
                                .fontWeight(active ? .bold : .semibold)
                                .lineLimit(1)
                            Capsule().fill(Palette.go).frame(width: BarSize.marker, height: BarSize.markerHeight)
                                .opacity(active ? 1 : 0)
                        }
                        .foregroundStyle(active ? Palette.ink : Palette.label)
                        .frame(maxWidth: .infinity, minHeight: Size.bar)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(Press())
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                }
            }
            .frame(height: Size.bar)
        }
        .background(Palette.page.ignoresSafeArea(edges: .bottom))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
