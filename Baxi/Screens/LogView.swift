import SwiftUI
import SwiftData

/// The supervised driving log: totals toward Indiana's 50 hours (10 at night), every drive, drives added
/// by hand, and exports (a PDF in the State Form 54706 layout, and CSV).
struct LogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]
    @State private var adding = false
    @State private var pdfURL: URL?
    @State private var csvURL: URL?

    private var totals: DriveLog.Totals { DriveLog.totals(drives.map(\.row)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 24) {
                        ProgressRing(title: "Total", value: totals.minutes, goal: DriveLog.requiredMinutes)
                        ProgressRing(title: "Night", value: totals.nightMinutes, goal: DriveLog.requiredNightMinutes)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    Text(totals.isComplete ? "Requirement met. Bring the signed log to the BMV."
                         : "\(DriveLog.hm(totals.minutesLeft)) to go, \(DriveLog.hm(totals.nightMinutesLeft)) of it at night.")
                        .font(.footnote).foregroundStyle(.secondary)
                } footer: {
                    Text("Indiana requires 50 supervised hours, at least 10 at night (IC 9-24-3-2.5). Baxi counts night from sunset to sunrise.")
                }

                Section("Drives") {
                    if drives.isEmpty {
                        Text("Finished drives appear here. Replays are never logged.").foregroundStyle(.secondary)
                    }
                    ForEach(drives) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(d.routeTitle).font(.headline)
                                if d.manual { Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text(DriveLog.hm(d.dayMinutes + d.nightMinutes)).font(.headline.monospacedDigit())
                            }
                            Text("\(d.start.formatted(date: .abbreviated, time: .shortened)) · day \(DriveLog.hm(d.dayMinutes)) · night \(DriveLog.hm(d.nightMinutes))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { idx in idx.map { drives[$0] }.forEach(context.delete) }
                }
            }
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { adding = true } label: { Label("Add a drive", systemImage: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let pdfURL { ShareLink("Log as PDF (Form 54706 layout)", item: pdfURL) }
                        if let csvURL { ShareLink("Log as CSV", item: csvURL) }
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .disabled(drives.isEmpty)
                }
            }
            .sheet(isPresented: $adding) { AddDriveView() }
            .task(id: drives.map(\.id)) { writeExports() }
        }
    }

    /// Writes both export files to a temporary folder so the share sheet can hand them off.
    private func writeExports() {
        let rows = drives.map(\.row)
        guard !rows.isEmpty else { pdfURL = nil; csvURL = nil; return }
        let dir = FileManager.default.temporaryDirectory
        let pdf = dir.appendingPathComponent("Baxi driving log.pdf")
        let csv = dir.appendingPathComponent("Baxi driving log.csv")
        do {
            try LogPDF.render(rows).write(to: pdf)
            try DriveLog.csv(rows).write(to: csv, atomically: true, encoding: .utf8)
            pdfURL = pdf; csvURL = csv
        } catch {
            pdfURL = nil; csvURL = nil
        }
    }
}

/// For practice drives done without Baxi running. Night minutes are split from the times entered.
private struct AddDriveView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var end = Date()
    @State private var note = ""

    private var split: (day: Int, night: Int) {
        Daylight.split(start: start, end: end, at: store.home ?? AppStore.carmelDemoHome)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Bounded: the last 60 days, drives up to 6 hours (the split walks every minute).
                DatePicker("Started", selection: $start, in: Date().addingTimeInterval(-60 * 86_400)...Date())
                DatePicker("Ended", selection: $end, in: start...min(Date(), start.addingTimeInterval(6 * 3600)))
                TextField("Where (optional)", text: $note)
                Section {
                    LabeledContent("Day", value: DriveLog.hm(split.day))
                    LabeledContent("Night", value: DriveLog.hm(split.night))
                } footer: { Text("Night is counted from sunset to sunrise in Carmel.") }
            }
            .navigationTitle("Add a drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let s = split
                        context.insert(DriveRecord(start: start, end: end, dayMinutes: s.day, nightMinutes: s.night,
                                                   level: store.level, routeTitle: note.isEmpty ? "Practice drive" : note,
                                                   distanceMeters: 0, cuesSpoken: 0, manual: true))
                        dismiss()
                    }
                    .disabled(split.day + split.night == 0)
                }
            }
        }
    }
}
