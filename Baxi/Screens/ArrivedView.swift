import SwiftUI

/// Shown when a drive ends: what was driven, what went into the log, and everything Baxi said.
struct ArrivedView: View {
    let session: DriveSession
    let record: DriveRecord?
    var onDone: () -> Void

    private var handled: [(String, Int)] {
        let passed = session.route.maneuvers.filter { $0.alongMeters <= (session.progress?.alongMeters ?? 0) }
        return [("Roundabouts", passed.filter { $0.kind == .roundabout }.count),
                ("Merges and ramps", passed.filter { [.merge, .onRamp, .offRamp].contains($0.kind) }.count),
                ("Lane choices", passed.filter { $0.kind == .turn && $0.needsLaneChoice }.count)]
            .filter { $0.1 > 0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Route", value: session.route.name)
                    LabeledContent("Time", value: "\(Int(session.minutes.rounded())) min")
                    LabeledContent("Distance", value: DriveView.distance(session.drivenMeters))
                    LabeledContent("Cues spoken", value: "\(session.spokenLog.count)")
                    if session.rerouteCount > 0 { LabeledContent("Reroutes", value: "\(session.rerouteCount)") }
                }
                if !handled.isEmpty {
                    Section("You handled") {
                        ForEach(handled, id: \.0) { LabeledContent($0.0, value: "\($0.1)") }
                    }
                }
                Section {
                    if let record {
                        LabeledContent("Day", value: DriveLog.hm(record.dayMinutes))
                        LabeledContent("Night", value: DriveLog.hm(record.nightMinutes))
                    } else {
                        Text(session.mode == .live ? "Drives under a minute are not logged."
                                                   : "Replays are demos, so they never count toward the 50 hours.")
                            .foregroundStyle(.secondary)
                    }
                } header: { Text("Saved to your log") } footer: {
                    if record != nil { Text("Night is counted from sunset to sunrise.") }
                }
                Section("What Baxi said") {
                    ForEach(Array(session.spokenLog.enumerated()), id: \.offset) { _, e in
                        Text(e.text).font(.callout)
                    }
                }
            }
            .navigationTitle("Arrived")
            .toolbar { Button("Done", action: onDone) }
        }
        .interactiveDismissDisabled()
    }
}
