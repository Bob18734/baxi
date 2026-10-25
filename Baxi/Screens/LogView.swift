import SwiftUI
import SwiftData

/// The supervised driving log: totals toward Indiana's 50 hours (10 at night), every drive grouped by
/// month, drives added by hand, and exports (the official State Form 54706, and CSV).
struct LogView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppStore.self) private var store
    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]
    @State private var adding = false
    @State private var pdfURLs: [URL] = []
    @State private var csvURL: URL?
    @State private var exportError: String?
    @State private var editingDriver = false
    @AppStorage(OfficialLogPDF.driverNameKey) private var driverName = ""
    @AppStorage(OfficialLogPDF.licenseNumberKey) private var licenseNumber = ""

    private struct ExportInput: Equatable {
        let rows: [LogRow]
        let driver: OfficialLogPDF.Driver
    }
    private var exportInput: ExportInput {
        ExportInput(rows: drives.map(\.row), driver: .init(name: driverName, licenseNumber: licenseNumber))
    }

    private var totals: DriveLog.Totals { DriveLog.totals(drives.map(\.row)) }

    private var months: [(title: String, drives: [DriveRecord])] {
        let groups = Dictionary(grouping: drives) { Calendar.current.dateInterval(of: .month, for: $0.start)?.start ?? $0.start }
        return groups.keys.sorted(by: >).map { key in
            (key.formatted(.dateTime.month(.wide).year()), groups[key] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { summary }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                Section { SkillsPanel(done: Practice.total(drives.map(\.skills)), routes: store.presetSkills) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if let exportError {
                    Section {
                        Text(exportError).font(BaxiFont.callout).foregroundStyle(BaxiColor.stopText)
                        Button("Retry export") { writeExports() }
                    } header: { Text("Export unavailable") }
                }
                if drives.isEmpty {
                    Section { emptyState }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                ForEach(months, id: \.title) { month in
                    Section {
                        ForEach(month.drives) { DriveRow(drive: $0) }
                            .onDelete { idx in
                                idx.map { month.drives[$0] }.forEach(context.delete)
                                try? context.save()
                            }
                            .listRowBackground(BaxiColor.surface)
                    } header: {
                        Eyebrow(month.title)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .baxiPage()
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { exportMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Label("Add a drive", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $adding) { AddDriveView() }
            .sheet(isPresented: $editingDriver) {
                NavigationStack {
                    DriverDetailsView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { editingDriver = false }
                        } }
                }
            }
            .task(id: exportInput) {
                pdfURLs = []; csvURL = nil
                guard !editingDriver else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                writeExports()
            }
            .onChange(of: editingDriver) { _, editing in
                if !editing { writeExports() }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.lg) {
            HStack(alignment: .firstTextBaseline, spacing: BaxiSpace.sm) {
                Text(DriveLog.hm(totals.minutes)).font(BaxiFont.number).foregroundStyle(BaxiColor.ink)
                    .contentTransition(.numericText())
                Text("of 50 hours").font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
            }
            HoursBar(label: "Total", minutes: totals.minutes, goal: DriveLog.requiredMinutes, tint: BaxiColor.accent)
            HoursBar(label: "At night", minutes: totals.nightMinutes, goal: DriveLog.requiredNightMinutes, tint: BaxiColor.route)
            Text(totals.isComplete ? "Requirement met. Export the official log, review it and sign it on paper."
                 : "\(DriveLog.hm(totals.minutesLeft)) to go, \(DriveLog.hm(totals.nightMinutesLeft)) of it at night.")
                .font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
        }
        .padding(.horizontal, BaxiSpace.xs)
        .padding(.vertical, BaxiSpace.sm)
    }

    /// The official form and CSV, from the toolbar.
    private var exportMenu: some View {
        Menu {
            Button("Driver details") { editingDriver = true }
            if !pdfURLs.isEmpty {
                ShareLink(items: pdfURLs) {
                    Text(pdfURLs.count == 1 ? "Official State Form 54706 (PDF)" : "Official logs (\(pdfURLs.count) PDFs)")
                }
            }
            if let csvURL { ShareLink("Spreadsheet (CSV)", item: csvURL) }
        } label: { Label("Export", systemImage: "square.and.arrow.up") }
        .disabled(drives.isEmpty)
    }

    private var emptyState: some View {
        VStack(spacing: BaxiSpace.md) {
            Image(systemName: "road.lanes").font(BaxiFont.number).foregroundStyle(BaxiColor.inkFaint)
            Text("No drives yet").font(BaxiFont.section).foregroundStyle(BaxiColor.ink)
            Text("Live drives save here when you arrive. Drove without Baxi? Add it with the + button. Replays are never logged.")
                .font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BaxiSpace.xxl)
        .padding(.horizontal, BaxiSpace.xl)
    }

    /// Writes both export files to a temporary folder so the share sheet can hand them off.
    private func writeExports() {
        let input = exportInput
        let rows = input.rows
        pdfURLs = []; csvURL = nil; exportError = nil
        guard !rows.isEmpty else { return }
        // Each snapshot gets its own files so a share sheet never reads a partly rewritten export.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("baxi-export-\(UUID().uuidString)")
        let csv = dir.appendingPathComponent("Baxi driving log.csv")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let forms = try OfficialLogPDF.renderForms(rows, driver: input.driver)
            var urls: [URL] = []
            for (index, data) in forms.enumerated() {
                let pdf = dir.appendingPathComponent("Baxi State Form 54706 - \(index + 1).pdf")
                try data.write(to: pdf, options: .atomic)
                urls.append(pdf)
            }
            try DriveLog.csv(rows).write(to: csv, atomically: true, encoding: .utf8)
            pdfURLs = urls; csvURL = csv
        } catch {
            pdfURLs = []; csvURL = nil
            exportError = error.localizedDescription
            try? FileManager.default.removeItem(at: dir)
        }
    }
}

/// The skills practiced across every drive Baxi recorded, toward Baxi's suggested goals, and the
/// practice route that would fill the biggest gaps.
private struct SkillsPanel: View {
    let done: SkillCounts
    let routes: [(id: String, skills: SkillCounts)]

    var body: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            Text("Skills").font(BaxiFont.section).foregroundStyle(BaxiColor.ink)
            ForEach(Skill.allCases) { s in
                ProgressRow(label: s.title, value: done[s] ?? 0, goal: s.goal, tint: BaxiColor.sign)
            }
            if let next = Practice.suggest(done: done, routes: routes),
               let name = RouteService.presets.first(where: { $0.id == next.presetId })?.name {
                Label {
                    Text("Next, try the \(name): " + next.covers.prefix(3).map { "\($0.count) \($0.skill.title.lowercased())" }
                        .joined(separator: ", ") + ".")
                } icon: { Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").foregroundStyle(BaxiColor.accent) }
                .font(BaxiFont.callout).foregroundStyle(BaxiColor.ink)
            }
            Text("Goals are Baxi's suggestion, not a state rule.")
                .font(BaxiFont.caption).foregroundStyle(BaxiColor.inkFaint)
        }
        .padding(.horizontal, BaxiSpace.xs)
        .padding(.vertical, BaxiSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labeled bar toward a count goal.
private struct ProgressRow: View {
    let label: String
    let value: Int
    let goal: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.xs) {
            HStack {
                Text(label).font(BaxiFont.footnote.weight(.semibold)).foregroundStyle(BaxiColor.ink)
                Spacer()
                Text("\(min(value, goal)) / \(goal)").font(BaxiFont.footnote.monospacedDigit()).foregroundStyle(BaxiColor.inkSoft)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BaxiColor.sunken)
                    Capsule().fill(tint).frame(width: max(8, geo.size.width * min(1, Double(value) / Double(goal))))
                        .opacity(value == 0 ? 0 : 1)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value) of \(goal)")
    }
}

/// A labeled bar toward a goal.
private struct HoursBar: View {
    let label: String
    let minutes: Int
    let goal: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.xs) {
            HStack {
                Text(label).font(BaxiFont.footnote.weight(.semibold)).foregroundStyle(BaxiColor.ink)
                Spacer()
                Text("\(DriveLog.hm(minutes)) / \(goal / 60):00").font(BaxiFont.footnote.monospacedDigit()).foregroundStyle(BaxiColor.inkSoft)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BaxiColor.sunken)
                    Capsule().fill(tint).frame(width: max(8, geo.size.width * min(1, Double(minutes) / Double(goal))))
                        .opacity(minutes == 0 ? 0 : 1)
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(DriveLog.hm(minutes)) of \(goal / 60) hours")
    }
}

private struct DriveRow: View {
    let drive: DriveRecord

    var body: some View {
        HStack(spacing: BaxiSpace.md) {
            VStack(spacing: 0) {
                Text(drive.start.formatted(.dateTime.day())).font(BaxiFont.numberSmall).foregroundStyle(BaxiColor.ink)
                Text(drive.start.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(BaxiFont.eyebrow).foregroundStyle(BaxiColor.inkFaint)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: BaxiSpace.xs) {
                HStack(spacing: BaxiSpace.xs) {
                    Text(drive.routeTitle).font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink).lineLimit(1)

                }
                HStack(spacing: BaxiSpace.sm) {
                    Text(drive.start.formatted(date: .omitted, time: .shortened))
                    if drive.manual { Text("added by hand") }
                    if drive.nightMinutes > 0 { Label(DriveLog.hm(drive.nightMinutes), systemImage: "moon.fill") }
                    if drive.distanceMeters > 0 { Text(DriveView.distance(drive.distanceMeters)) }
                }
                .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
            Text(DriveLog.hm(drive.dayMinutes + drive.nightMinutes)).font(BaxiFont.headline.monospacedDigit()).foregroundStyle(BaxiColor.ink)
        }
        .padding(.vertical, BaxiSpace.xs)
        .accessibilityElement(children: .combine)
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
        Daylight.split(start: start, end: end, at: store.origin)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Bounded: the last 60 days, drives up to 6 hours (the split walks every minute).
                    DatePicker("Started", selection: $start, in: Date().addingTimeInterval(-60 * 86_400)...Date())
                    DatePicker("Ended", selection: $end, in: start...min(Date(), start.addingTimeInterval(6 * 3600)))
                    TextField("Where (optional)", text: $note)
                }
                Section {
                    LabeledContent("Day", value: DriveLog.hm(split.day))
                    LabeledContent { Text(DriveLog.hm(split.night)) } label: { Label("Night", systemImage: "moon.fill") }
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
                        try? context.save()
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(split.day + split.night == 0)
                }
            }
        }
    }
}
