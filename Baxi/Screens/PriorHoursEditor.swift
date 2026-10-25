import SwiftUI

/// Hours driven before Baxi: the total, and how much of it was at night. Used at setup and in the Log.
struct PriorHoursEditor: View {
    @Binding var prior: PriorHours
    /// The night hours as last set: scrolling the total below them and back up again restores them.
    @State private var wantedNight: Int?

    private var total: Binding<Int> {
        Binding(get: { prior.totalMinutes },
                set: { t in
                    let t = min(max(0, t), PriorWheel.maxHours * 60)
                    let n = min(wantedNight ?? prior.nightMinutes, t)
                    prior = PriorHours(dayMinutes: t - n, nightMinutes: n)
                })
    }
    private var night: Binding<Int> {
        Binding(get: { prior.nightMinutes },
                set: { n in
                    let n = min(max(0, n), prior.totalMinutes)
                    wantedNight = n
                    prior = PriorHours(dayMinutes: prior.totalMinutes - n, nightMinutes: n)
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            DurationWheel(title: "Hours driven so far", minutes: total, maxMinutes: PriorWheel.maxHours * 60)
            // Never more than the total: the wheel only offers what fits.
            DurationWheel(title: "Of those, at night", minutes: night, maxMinutes: prior.totalMinutes)
                .disabled(prior.totalMinutes == 0)
            Text("They count toward your 50 hours here. They aren't added to the official form's drive list: keep them on your paper log.")
                .role(.meta).foregroundStyle(Palette.meta).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A duration as two wheels, hours and minutes (in 5-minute steps), under a title.
private struct DurationWheel: View {
    let title: String
    @Binding var minutes: Int
    let maxMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                Text(title).role(.bodyStrong).foregroundStyle(Palette.ink)
                Spacer()
                Text(DriveLog.hm(minutes)).role(.numberSmall).foregroundStyle(Palette.ink).contentTransition(.numericText())
            }
            HStack(spacing: 0) {
                Picker("Hours", selection: Binding(get: { minutes / 60 }, set: { minutes = $0 * 60 + minutes % 60 })) {
                    ForEach(0...(maxMinutes / 60), id: \.self) { Text("\($0) h").tag($0) }
                }
                Picker("Minutes", selection: Binding(get: { (minutes % 60) / 5 * 5 }, set: { minutes = min(maxMinutes, minutes / 60 * 60 + $0) })) {
                    // In the last hour only the minutes that fit under the maximum.
                    ForEach(Array(stride(from: 0, through: minutes / 60 == maxMinutes / 60 ? maxMinutes % 60 : 55, by: 5)), id: \.self) {
                        Text("\($0) m").tag($0)
                    }
                }
            }
            .pickerStyle(.wheel)
            .frame(height: PriorWheel.height)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: Corner.control, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Hours before Baxi as a sheet, from the Log.
struct PriorHoursSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Starts from what's saved (set before the first frame, so the wheels never show zeros first).
    @State private var draft: PriorHours?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Hours before Baxi", actionTitle: "Save") {
                if let draft { store.priorHours = draft }
                Haptic.success()
                dismiss()
            }
            ScrollView {
                if draft != nil {
                    PriorHoursEditor(prior: Binding(get: { draft ?? PriorHours() }, set: { draft = $0 }))
                        .padding(.horizontal, Space.margin)
                        .padding(.bottom, Space.s32)
                }
            }
        }
        .pageBackground()
        .onAppear { if draft == nil { draft = store.priorHours } }
    }
}
