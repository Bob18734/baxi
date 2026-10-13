import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]

    private var dayMinutes: Int { drives.map(\.dayMinutes).reduce(0, +) }
    private var nightMinutes: Int { drives.map(\.nightMinutes).reduce(0, +) }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tier \(store.tier.rawValue): \(store.tier.title)").font(.title3.bold())
                        Text(store.tier.summary).foregroundStyle(.secondary)
                        Picker("Tier", selection: $store.tier) {
                            ForEach(Tier.allCases) { t in Text("\(t.rawValue)").tag(t) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                } header: { Text("Skill level") }

                Section {
                    HStack(spacing: 24) {
                        ProgressRing(title: "Day", value: dayMinutes, goal: 40 * 60)
                        ProgressRing(title: "Night", value: nightMinutes, goal: 10 * 60)
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
                        Label("Try the Carmel demo", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(store.isLoading)
                    Text(store.dataStatus).font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Practice area") }
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
