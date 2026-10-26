import SwiftUI

/// Where a searched route starts, and the way to change it: a quiet line under the search field (Home) and at the
/// top of the Routes lists. At accessibility text sizes the two parts stack so neither is cut short.
struct StartFromRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let action: () -> Void

    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Space.s8))
        Button { Haptic.tap(); action() } label: {
            layout {
                HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                    Mark(glyph: .locate, size: MarkSize.tiny).foregroundStyle(Palette.meta)
                    Text("From \(store.startLabel)").role(.meta).foregroundStyle(Palette.read)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !textSize.isAccessibilitySize { Spacer(minLength: Space.s8) }
                Text("Change").role(.metaStrong).foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity, minHeight: Size.tap, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .accessibilityLabel("Searched routes start from \(store.startLabel)")
        .accessibilityHint("Choose a starting point")
    }
}
