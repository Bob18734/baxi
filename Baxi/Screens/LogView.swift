import SwiftUI
import SwiftData
import Charts

/// The supervised driving log: hours toward Indiana's 50 (10 at night), the skills, how recent drives went,
/// every drive by month (tap to edit, swipe to delete with Undo), drives added by hand, and the exports
/// (the official State Form 54706, and a CSV).
struct LogView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]
    @State private var adding = false
    @State private var editing: DriveRecord?
    @State private var pdfURLs: [URL] = []
    @State private var csvURL: URL?
    @State private var exportError: String?
    @State private var editingDriver = false
    @State private var editingPrior = false
    /// Drives deleted since the last Undo offer, so Undo brings all of them back.
    @State private var pendingUndo: [DeletedDrive] = []
    /// The exports are made once the Log has been opened (the tab stays alive from launch).
    @State private var opened = false
    @AppStorage(OfficialLogPDF.driverNameKey) private var driverName = ""
    @AppStorage(OfficialLogPDF.licenseNumberKey) private var licenseNumber = ""

    private struct ExportTrigger: Equatable { let input: ExportInput; let opened: Bool }
    private struct ExportInput: Equatable {
        let rows: [LogRow]
        let driver: OfficialLogPDF.Driver
        let prior: PriorHours
    }
    private var exportInput: ExportInput {
        ExportInput(rows: drives.map(\.row), driver: .init(name: driverName, licenseNumber: licenseNumber), prior: store.priorHours)
    }

    private var totals: DriveLog.Totals { DriveLog.totals(drives.map(\.row), prior: store.priorHours) }
    /// Habit reports of recorded drives, oldest first (the chart reads left to right).
    private var habitReports: [HabitReport] { drives.reversed().compactMap(\.habits).filter { !$0.isDemo } }

    private var months: [(title: String, drives: [DriveRecord])] {
        let groups = Dictionary(grouping: drives) { Calendar.current.dateInterval(of: .month, for: $0.start)?.start ?? $0.start }
        return groups.keys.sorted(by: >).map { key in (key.formatted(.dateTime.month(.wide).year()), groups[key] ?? []) }
    }

    var body: some View {
        List {
            Group {
                header
                HoursPanel(totals: totals, hasDrives: !drives.isEmpty)
                priorRow
                if let exportError {
                    VStack(alignment: .leading, spacing: Space.s8) {
                        Text("The official log couldn't be made: \(exportError)").role(.body).foregroundStyle(Palette.stopText)
                            .fixedSize(horizontal: false, vertical: true)
                        BigButton(title: "Try again", kind: .secondary) { writeExports() }
                    }
                }
                SkillsPanel(done: Practice.total(drives.map(\.skills)), routes: store.presetSkills)
                if !habitReports.isEmpty { HabitsPanel(reports: habitReports) }
                if drives.isEmpty {
                    EmptyState(message: "No drives yet. Live drives save here when you arrive. Drove without Baxi? Add it here. Replays are never logged.",
                               actionTitle: "Add a drive") { adding = true }
                }
            }
            .logRow()
            ForEach(months, id: \.title) { month in
                Section {
                    ForEach(Array(month.drives.enumerated()), id: \.element.id) { i, d in
                        Button { Haptic.tap(); editing = d } label: {
                            DriveRow(drive: d, showsDivider: i < month.drives.count - 1)
                        }
                        .buttonStyle(Press())
                        .accessibilityHint("Edit this drive")
                        .logRow(top: 0, bottom: 0)
                    }
                    .onDelete { idx in delete(idx.map { month.drives[$0] }) }
                } header: {
                    GroupLabel(month.title)
                        .padding(.top, Space.s16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 0, leading: Space.margin, bottom: Space.s4, trailing: Space.margin))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .pageBackground()
        .environment(\.defaultMinListRowHeight, 0)
        .sheet(isPresented: $adding) { DriveFormView(record: nil) }
        .sheet(item: $editing) { DriveFormView(record: $0) }
        .sheet(isPresented: $editingDriver) { DriverDetailsSheet { editingDriver = false } }
        .sheet(isPresented: $editingPrior) { PriorHoursSheet() }
        .onChange(of: store.tab, initial: true) { _, tab in if tab == .log { opened = true } }
        .task(id: ExportTrigger(input: exportInput, opened: opened)) {
            guard opened else { return }
            pdfURLs = []; csvURL = nil
            guard !editingDriver else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            writeExports()
        }
        .onChange(of: editingDriver) { _, editing in if !editing && opened { writeExports() } }
    }

    /// Hours driven before Baxi: a quiet way to add them, or what was entered, to change.
    @ViewBuilder private var priorRow: some View {
        if store.priorHours.isEmpty {
            Button { Haptic.tap(); editingPrior = true } label: {
                HStack(spacing: Space.s12) {
                    Mark(glyph: .plus, size: MarkSize.small)
                    Text("Add hours you drove before Baxi").role(.bodyStrong)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.ink).frame(minHeight: Size.tap)
            }
            .buttonStyle(Press())
        } else {
            Button { Haptic.tap(); editingPrior = true } label: {
                Row(title: "Before Baxi", detail: "\(DriveLog.hm(store.priorHours.totalMinutes)), \(DriveLog.hm(store.priorHours.nightMinutes)) at night. Counted here; kept on your paper log.",
                    showsDivider: false) { Text("Edit").role(.bodyStrong).foregroundStyle(Palette.ink) }
            }
            .buttonStyle(Press())
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Log").role(.screenTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            exportMenu
            MarkButton(glyph: .plus, label: "Add a drive") { adding = true }
                .padding(.trailing, -Space.s12)
        }
        .padding(.top, Space.s16)
    }

    /// The official form and CSV. A system menu: sharing is the system's own sheet.
    private var exportMenu: some View {
        Menu {
            Button("Driver details") { editingDriver = true }
            if pdfURLs.isEmpty && exportError == nil {
                // The files are rewritten a moment after any change to the log.
                Text("Preparing the official log…")
            }
            if !pdfURLs.isEmpty {
                ShareLink(items: pdfURLs) {
                    Text(pdfURLs.count == 1 ? "Official State Form 54706 (PDF)" : "Official logs (\(pdfURLs.count) PDFs)")
                }
            }
            if let csvURL { ShareLink("Spreadsheet (CSV)", item: csvURL) }
        } label: {
            Mark(glyph: .share, size: MarkSize.inline).foregroundStyle(drives.isEmpty ? Palette.label : Palette.ink)
                .frame(width: Size.tap, height: Size.tap)
        }
        .disabled(drives.isEmpty)
        .accessibilityLabel("Export the log")
    }

    private func delete(_ records: [DriveRecord]) {
        pendingUndo += records.map(DeletedDrive.init)
        records.forEach(context.delete)
        try? context.save()
        Haptic.tap()
        let n = pendingUndo.count
        toasts.show(n == 1 ? "Drive deleted. It came off your hours." : "\(n) drives deleted. They came off your hours.", actionTitle: "Undo") {
            pendingUndo.forEach { context.insert($0.restore()) }
            pendingUndo = []
            try? context.save()
            Haptic.success()
        }
        // The offer lasts as long as the toast; after that, deleted is deleted.
        let token = n
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(7))
            if pendingUndo.count == token { pendingUndo = [] }
        }
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
            try DriveLog.csv(rows, prior: input.prior).write(to: csv, atomically: true, encoding: .utf8)
            pdfURLs = urls; csvURL = csv
        } catch {
            pdfURLs = []; csvURL = nil
            exportError = error.localizedDescription
            try? FileManager.default.removeItem(at: dir)
        }
    }
}

private extension View {
    /// A list row laid out like the rest of the app: on the page, the page margin, no system separator.
    func logRow(top: CGFloat = Space.s16, bottom: CGFloat = Space.s16) -> some View {
        listRowBackground(Palette.page)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: Space.margin, bottom: bottom, trailing: Space.margin))
    }
}

/// Hours toward 50, and toward 10 at night, and what's left.
private struct HoursPanel: View {
    let totals: DriveLog.Totals
    /// Whether Baxi has drives to export (the hours may all be from before Baxi).
    let hasDrives: Bool
    /// What's left, as one true sentence: when the night hours still needed are more than the total left, those
    /// night hours are what's left.
    private var toGo: String {
        if totals.isComplete {
            return hasDrives ? "Requirement met. Export the official log, check it, and sign it on paper."
                             : "Requirement met. Check your paper log and sign it."
        }
        let total = totals.minutesLeft, night = totals.nightMinutesLeft
        if night >= total { return "\(Self.words(night)) to go, all of it at night." }
        if night == 0 { return "\(Self.words(total)) to go. The 10 night hours are done." }
        return "\(Self.words(total)) to go, \(Self.words(night)) of it at night."
    }

    /// "46 h 25 m": a duration in words, where a clock reading ("46:25") would look like a time of day.
    static func words(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m) m" : m == 0 ? "\(h) h" : "\(h) h \(m) m"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                Text(DriveLog.hm(totals.minutes)).role(.number).foregroundStyle(Palette.ink).contentTransition(.numericText())
                Text("of 50 hours").role(.body).foregroundStyle(Palette.meta)
            }
            ProgressLine(fraction: Double(totals.minutes) / Double(DriveLog.requiredMinutes))
            HStack(spacing: Space.s8) {
                Mark(glyph: .moon, size: MarkSize.tiny).foregroundStyle(Palette.meta)
                Text("\(DriveLog.hm(totals.nightMinutes)) of 10 at night").role(.meta).foregroundStyle(Palette.meta)
            }
            ProgressLine(fraction: Double(totals.nightMinutes) / Double(DriveLog.requiredNightMinutes), tint: Palette.meta)
            Text(toGo).role(.body).foregroundStyle(totals.isComplete ? Palette.goText : Palette.read)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Each skill's level toward Baxi's suggested goals, and the practice route that fills the biggest gaps.
private struct SkillsPanel: View {
    let done: SkillCounts
    let routes: [(id: String, skills: SkillCounts)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Skills").padding(.bottom, Space.s4)
            ForEach(Array(Skill.allCases.enumerated()), id: \.element) { i, s in
                let count = done[s] ?? 0
                let lv = Practice.level(s, count: count)
                Row(title: s.title, detail: "\(lv.title), \(min(count, s.goal)) of \(s.goal)", showsDivider: i < Skill.allCases.count - 1) {
                    // The same ring as Home's, so a skill looks the same everywhere.
                    ZStack {
                        ProgressRing(fraction: Double(count) / Double(s.goal), size: SkillRingSize.ring, line: SkillRingSize.line)
                        Mark(glyph: .skill(s), size: SkillRingSize.mark).foregroundStyle(Palette.ink)
                    }
                } trailing: {
                    EmptyView()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(s.title): \(lv.title), \(count) of \(s.goal)" + (lv.toNext.map { ". \($0) more to the next level" } ?? ""))
            }
            if let next = Practice.suggest(done: done, routes: routes),
               let name = RouteService.presets.first(where: { $0.id == next.presetId })?.name {
                HStack(alignment: .top, spacing: Space.s12) {
                    Mark(glyph: .route, size: MarkSize.inline).foregroundStyle(Palette.goText)
                    Text("Next, try the \(name): " + next.covers.prefix(3).map { $0.skill.count($0.count) }
                            .joined(separator: ", ") + ".")
                        .role(.body).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s16)
            }
        }
    }
}

/// How recent drives went: the last scores as bars (green from 80, amber below), full stops and speed lately.
private struct HabitsPanel: View {
    let reports: [HabitReport]

    var body: some View {
        let t = DriveHabits.trend(reports)
        VStack(alignment: .leading, spacing: Space.s12) {
            GroupLabel("Habits")
            Chart(Array(t.lastScores.enumerated()), id: \.offset) { i, score in
                // Each drive is a category, so the bar width can be a share of its band.
                BarMark(x: .value("Drive", "\(i + 1)"), y: .value("Score", score), width: .ratio(0.55))
                    .foregroundStyle(score >= 80 ? Palette.go : Palette.ready)
                    .cornerRadius(HabitsSize.barCorner)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { _ in
                    AxisGridLine().foregroundStyle(Palette.hairline)
                    AxisValueLabel().foregroundStyle(Palette.meta)
                }
            }
            .frame(height: HabitsSize.chart)
            .accessibilityLabel("Scores of the last \(t.lastScores.count) drives: " + t.lastScores.map(String.init).joined(separator: ", "))
            if let rate = t.fullStopRate {
                Text("Full stops at all-way stops: \(Int((rate * 100).rounded()))% lately").role(.body).foregroundStyle(Palette.ink)
            }
            if let share = t.overLimitShare {
                Text(share < 0.01 ? "Stayed within 5 mph of the limit lately" : "Over the limit \(Int((share * 100).rounded()))% of the time lately")
                    .role(.body).foregroundStyle(Palette.ink)
            }
            Text("From the last \(t.lastScores.count) recorded \(t.lastScores.count == 1 ? "drive" : "drives"). Baxi's coaching, not a state rule.")
                .role(.meta).foregroundStyle(Palette.meta)
        }
    }
}


/// One drive: the day, its name, when, how it was added, night time and miles, and how long.
private struct DriveRow: View {
    let drive: DriveRecord
    let showsDivider: Bool

    private var detail: String {
        var parts = [drive.start.formatted(date: .omitted, time: .shortened)]
        if drive.manual { parts.append("added by hand") }
        if drive.nightMinutes > 0 { parts.append("\(DriveLog.hm(drive.nightMinutes)) at night") }
        if drive.distanceMeters > 0 { parts.append(DriveView.distance(drive.distanceMeters)) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Row(title: drive.routeTitle, detail: detail, showsDivider: showsDivider) {
            VStack(spacing: 0) {
                Text(drive.start.formatted(.dateTime.day())).role(.numberSmall).foregroundStyle(Palette.ink)
                Text(drive.start.formatted(.dateTime.weekday(.abbreviated))).role(.meta).foregroundStyle(Palette.meta)
            }
            .frame(width: DriveRowSize.date)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        } trailing: {
            Text(DriveLog.hm(drive.dayMinutes + drive.nightMinutes)).role(.bodyStrong).monospacedDigit().foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}


// MARK: - Add or edit a drive

/// Adds a practice drive done without Baxi running, or edits one already in the log. Drives typed in by hand can
/// change their times; drives Baxi recorded keep their times (they came from the GPS) and only their name can
/// change. Night minutes are split from the times at sunset and sunrise.
private struct DriveFormView: View {
    /// nil to add a new drive.
    let record: DriveRecord?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Query private var drives: [DriveRecord]
    @State private var start: Date
    @State private var end: Date
    @State private var note: String

    /// The fields start from the record, set here rather than on appear: a later change to `start` would
    /// shift `end` as if the user had moved it.
    init(record: DriveRecord?) {
        self.record = record
        _start = State(initialValue: record?.start ?? Date().addingTimeInterval(-3600))   // design-lint:allow a new drive's default: the last hour
        _end = State(initialValue: record?.end ?? Date())   // design-lint:allow a new drive's default: ending now
        _note = State(initialValue: record.map { $0.routeTitle == "Practice drive" ? "" : $0.routeTitle } ?? "")
    }

    private var timesEditable: Bool { record?.manual ?? true }
    private var split: (day: Int, night: Int) {
        // A recorded drive keeps the split it was saved with (made where the drive began).
        if let record, !timesEditable { return (record.dayMinutes, record.nightMinutes) }
        return Daylight.split(start: start, end: end, at: store.origin)
    }
    private var overlaps: Bool {
        timesEditable && DriveLog.overlaps(start, end, with: drives.map(\.row), excluding: record?.id)
    }
    private var canSave: Bool { split.day + split.night > 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }.role(.body).foregroundStyle(Palette.ink).buttonStyle(Press()).frame(minHeight: Size.tap)
                Spacer()
                Button("Save", action: save).role(.bodyStrong).foregroundStyle(canSave ? Palette.ink : Palette.label)
                    .buttonStyle(Press()).frame(minHeight: Size.tap).disabled(!canSave)
            }
            .padding(.horizontal, Space.margin).padding(.top, Space.s12)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s24) {
                    Text(record == nil ? "Add a drive" : "Edit drive").role(.screenTitle).foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: Space.s12) {
                        if timesEditable {
                            FieldBox {
                                // Bounded: the last 60 days, drives up to 6 hours (the split walks every minute).
                                DatePicker("Started", selection: $start, in: Date().addingTimeInterval(-60 * 86_400)...Date())
                                    .role(.body).foregroundStyle(Palette.ink)
                            }
                            FieldBox {
                                DatePicker("Ended", selection: $end, in: start...min(Date(), start.addingTimeInterval(6 * 3600)))
                                    .role(.body).foregroundStyle(Palette.ink)
                            }
                        } else {
                            Row(title: "Started", detail: start.formatted(date: .abbreviated, time: .shortened)) { EmptyView() }
                            Row(title: "Ended", detail: end.formatted(date: .omitted, time: .shortened), showsDivider: false) { EmptyView() }
                            Text("Times come from the drive Baxi recorded, so they can't be changed.").role(.meta).foregroundStyle(Palette.meta)
                        }
                        FieldBox {
                            TextField("Where (optional)", text: $note).role(.body).foregroundStyle(Palette.ink)
                        }
                        if overlaps {
                            Text("This overlaps a drive already in your log.").role(.metaStrong).foregroundStyle(Palette.stopText)
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.s8) {
                        HStack(spacing: Space.s32) {
                            minutes(split.day, "day")
                            minutes(split.night, "at night")
                        }
                        Text(canSave ? "Night is counted from sunset to sunrise." : "Set an end time after the start.")
                            .role(.meta).foregroundStyle(canSave ? Palette.meta : Palette.stopText)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.s16)
            }
        }
        .pageBackground()
        .onChange(of: start) { old, new in
            // Moving the start keeps the drive's length, so the end never sits before the start.
            guard timesEditable else { return }
            end = min(Date(), max(new, end.addingTimeInterval(new.timeIntervalSince(old))))
        }
        .presentationDetents([.large])
    }

    private func minutes(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DriveLog.hm(value)).role(.numberSmall).foregroundStyle(Palette.ink).contentTransition(.numericText())
            Text(label).role(.meta).foregroundStyle(Palette.meta)
        }
        .accessibilityElement(children: .combine)
    }

    private func save() {
        let title = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = split
        if let record {
            record.routeTitle = title.isEmpty ? (record.manual ? "Practice drive" : record.routeTitle) : title
            if timesEditable {
                record.start = start; record.end = end
                record.dayMinutes = s.day; record.nightMinutes = s.night
            }
        } else {
            context.insert(DriveRecord(start: start, end: end, dayMinutes: s.day, nightMinutes: s.night,
                                       level: store.level, routeTitle: title.isEmpty ? "Practice drive" : title,
                                       distanceMeters: 0, cuesSpoken: 0, manual: true))
        }
        try? context.save()
        Haptic.success()
        dismiss()
    }
}

/// A deleted drive's values, kept so Undo can put it back.
private struct DeletedDrive {
    let start: Date, end: Date, dayMinutes: Int, nightMinutes: Int, level: String, routeTitle: String
    let distanceMeters: Double, cuesSpoken: Int, manual: Bool, skillsJSON: String, habitsJSON: String

    init(_ r: DriveRecord) {
        (start, end, dayMinutes, nightMinutes, level) = (r.start, r.end, r.dayMinutes, r.nightMinutes, r.level)
        (routeTitle, distanceMeters, cuesSpoken, manual, skillsJSON) = (r.routeTitle, r.distanceMeters, r.cuesSpoken, r.manual, r.skillsJSON)
        habitsJSON = r.habitsJSON
    }

    func restore() -> DriveRecord {
        let r = DriveRecord(start: start, end: end, dayMinutes: dayMinutes, nightMinutes: nightMinutes,
                            level: ExperienceLevel(rawValue: level) ?? .gettingComfortable, routeTitle: routeTitle,
                            distanceMeters: distanceMeters, cuesSpoken: cuesSpoken, manual: manual)
        r.skillsJSON = skillsJSON
        r.habitsJSON = habitsJSON
        return r
    }
}
