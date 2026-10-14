import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]

    private var totals: DriveLog.Totals { DriveLog.totals(drives.map(\.row)) }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    Button { store.startDemoDrive() } label: {
                        Label("Watch a demo drive", systemImage: "play.circle.fill").font(.headline)
                    }
                    Text("Replays the US 31 loop in Carmel from just before the merge: a highway merge, two exit ramps and multi-lane roundabouts, about three minutes. Replays are never logged.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Try it") }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Experience", selection: $store.level) {
                            ForEach(ExperienceLevel.allCases) { l in Text(l.title).tag(l) }
                        }
                        .pickerStyle(.segmented)
                        Text(store.level.summary).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: { Text("How much warning") } footer: {
                    Text("Cue timing is Baxi's own design. The driving rules in each cue come from the Indiana Driver's Manual.")
                }

                Section {
                    HStack(spacing: 24) {
                        ProgressRing(title: "Total", value: totals.minutes, goal: DriveLog.requiredMinutes)
                        ProgressRing(title: "Night", value: totals.nightMinutes, goal: DriveLog.requiredNightMinutes)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    Text("Indiana requires 50 supervised hours, at least 10 at night (IC 9-24-3-2.5).")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Supervised hours") }

                Section {
                    Button {
                        store.loadCarmelDemo()
                    } label: {
                        Label("Load Carmel", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(store.isLoading || store.cache != nil)
                    Text(store.dataStatus).font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Practice area") }

                VoiceSettingsSection()
            }
            .navigationTitle("Baxi")
        }
    }
}

struct ProgressRing: View {
    let title: String
    let value: Int
    let goal: Int

    var body: some View {
        VStack {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(1, Double(value) / Double(goal)))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack {
                    Text("\(value / 60)h").font(.title2.bold())
                    Text("of \(goal / 60)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)
            Text(title).font(.subheadline)
        }
    }
}
