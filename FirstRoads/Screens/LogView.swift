import SwiftUI
import SwiftData

/// Day 1 placeholder: lists drives. Form 54706 export lands on Oct 18 per the plan.
struct LogView: View {
    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]

    var body: some View {
        NavigationStack {
            Group {
                if drives.isEmpty {
                    ContentUnavailableView("No drives yet", systemImage: "car",
                                           description: Text("Finished drives appear here with day and night minutes."))
                } else {
                    List(drives) { d in
                        VStack(alignment: .leading) {
                            Text(d.routeTitle).font(.headline)
                            Text("\(d.start.formatted(date: .abbreviated, time: .shortened)) · \(d.dayMinutes) day min · \(d.nightMinutes) night min")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Log")
        }
    }
}
