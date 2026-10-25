import SwiftUI
import MapKit
import SwiftData

/// The Drive screen. The phone is mounted and read in under a second, so the next instruction is the biggest
/// thing on it, the lane to be in is the brightest, and nothing else competes. After sunset it is the app's one
/// dark screen, for glare. Only Mute and End can be tapped, for the passenger.
struct DriveView: View {
    let session: DriveSession
    var onClose: () -> Void
    @Environment(\.modelContext) private var context
    @State private var camera: MapCameraPosition = .automatic
    @State private var saved: DriveRecord?
    @State private var didSave = false
    @State private var isNight = false

    private var look: DriveLook { DriveLook(night: isNight) }

    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: Space.s8) {
                InstructionPanel(session: session, look: look)
                StatusLine(session: session, look: look)
                HStack(alignment: .top, spacing: Space.s8) {
                    SpeedUnit(limit: session.speedLimitMph, speed: session.currentMph,
                              judgedLimit: session.isOnRoute ? session.speedLimitMph : nil, night: isNight)
                    Spacer()
                    if let alert = session.activeAlert {
                        AlertChip(kind: alert.kind).transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(Motion.standard, value: session.activeAlert?.id)
                .animation(Motion.standard, value: session.currentMph == nil)
                .animation(Motion.standard, value: session.speedLimitMph)
                Spacer()
                ControlBar(session: session, look: look)
            }
            .padding(.horizontal, Space.s12)
            .padding(.vertical, Space.s8)
        }
        .background(look.ground.ignoresSafeArea())
        .onAppear {
            // The phone is mounted for the whole drive, so the screen must not lock.
            UIApplication.shared.isIdleTimerDisabled = true
            isNight = nightNow()
            session.start(); follow()
        }
        // After sunset the screen goes dark so it does not glare in the driver's eyes; checked every minute so a
        // drive across sunset switches over.
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                let night = nightNow()
                if night != isNight { withAnimation(Motion.reveal) { isNight = night } }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // Torn down mid-drive (the cover dismissed some other way): end it and keep the record, since the
            // onChange below can no longer fire.
            if !session.isFinished { session.end(); save() }
        }
        .onChange(of: session.position) { _, _ in follow() }
        .onChange(of: traveledStep) { _, _ in traveled = traveledPoints?.map(\.clLocation) ?? [] }
        .onChange(of: session.isFinished) { _, done in if done { save() } }
        .sheet(isPresented: .constant(session.isFinished)) {
            ArrivedView(session: session, record: saved, onDone: onClose)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private func nightNow() -> Bool {
        #if DEBUG
        // Screenshots: --drive-time day|night shows either look whatever the clock says.
        if let forced = ScreenCheck.value("--drive-time") { return forced == "night" }
        #endif
        let at = session.position ?? session.startCoordinate ?? AppStore.carmelDemoHome
        guard let s = Daylight.sunriseSunset(on: Date(), at: at) else { return false }
        return Date() < s.sunrise || Date() >= s.sunset
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera, interactionModes: []) {
            MapPolyline(coordinates: session.routeCoordinates)
                .stroke(look.routeEdge, style: StrokeStyle(lineWidth: DriveSize.routeEdge, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: session.routeCoordinates)
                .stroke(look.route, style: StrokeStyle(lineWidth: DriveSize.route, lineCap: .round, lineJoin: .round))
            // Where to change lanes: amber, from the lane cue to "be in the lane by here".
            ForEach(zonesAhead) { z in
                if let line = session.laneZoneCoordinates[z.id], line.count > 1 {
                    MapPolyline(coordinates: line)
                        .stroke(Palette.ready, style: StrokeStyle(lineWidth: DriveSize.route, lineCap: .round, lineJoin: .round))
                    Annotation("", coordinate: line[line.count - 1]) { InLaneTab(zone: z) }
                }
            }
            if traveled.count > 1 {
                MapPolyline(coordinates: traveled)
                    .stroke(look.traveled, style: StrokeStyle(lineWidth: DriveSize.route, lineCap: .round, lineJoin: .round))
            }
            if let m = session.nextManeuver {
                Annotation("", coordinate: m.location.clLocation) {
                    Mark(glyph: .maneuver(m), size: MarkSize.row, weight: MarkWeight.emphasis).foregroundStyle(Palette.ink)
                        .frame(width: DriveSize.marker, height: DriveSize.marker)
                        .background(Palette.go, in: Circle())
                }
            }
            if let p = session.position {
                Annotation("", coordinate: p.clLocation) {
                    Mark(glyph: .locate, size: MarkSize.car).foregroundStyle(Palette.onDark)
                        .frame(width: DriveSize.car, height: DriveSize.car)
                        .background(Palette.ink, in: Circle())
                        .overlay(Circle().stroke(Palette.field, lineWidth: DriveSize.carEdge))
                }
            }
        }
        // Flat: 3D freeways would cover the route and the lane stretches.
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, isNight ? .dark : .light)
        .ignoresSafeArea()
    }

    @State private var traveled: [CLLocationCoordinate2D] = []
    private var traveledStep: Int { Int((session.progress?.alongMeters ?? 0) / 50) }

    /// The driven part of the route, redrawn every 50 m rather than on every fix: rebuilding a long map overlay
    /// several times a second is what makes the map stutter.
    private var traveledPoints: [Coordinate]? {
        guard let p = session.progress else { return nil }
        let line = session.route.polyline
        let step = (p.alongMeters / 50).rounded(.down) * 50
        guard step > 0, let end = line.coordinate(atMeters: step) else { return nil }
        let upTo = line.cumulative.lastIndex { $0 <= step } ?? 0
        return Array(line.points.prefix(upTo + 1)) + [end]
    }

    /// Lane stretches not yet passed and within 3 km, so the map is not cluttered with the whole route's.
    private var zonesAhead: [LaneZone] {
        let along = session.progress?.alongMeters ?? 0
        return session.laneZones.filter { $0.endMeters > along && $0.startMeters < along + 3_000 }
    }

    private func follow() {
        guard let p = session.position else { return }
        // Closer while changing lanes, so the amber stretch and its end are easy to read.
        let distance: Double = session.activeLaneZone == nil ? 700 : 420
        withAnimation(Motion.follow) {
            camera = .camera(MapCamera(centerCoordinate: p.clLocation, distance: distance, heading: session.heading, pitch: 50))
        }
    }

    // MARK: Save

    private func save() {
        guard !didSave else { return }
        didSave = true
        let end = session.endedAt ?? Date()   // design-lint:allow end() always sets endedAt before isFinished; never nil here
        // A replay is a demo, not a supervised drive, and a drive where the car never moved is not practice.
        guard DriveSession.shouldLog(mode: session.mode, seconds: end.timeIntervalSince(session.startedAt),
                                     meters: session.drivenMeters) else { return }
        let split = Daylight.split(start: session.startedAt, end: end, at: session.startCoordinate ?? AppStore.carmelDemoHome)
        let record = DriveRecord(start: session.startedAt, end: end, dayMinutes: split.day, nightMinutes: split.night,
                                 level: session.level, routeTitle: session.route.name,
                                 distanceMeters: session.drivenMeters, cuesSpoken: session.spokenLog.count,
                                 skills: session.practiced, habits: session.habits)
        context.insert(record)
        // Save now rather than waiting for autosave: the app may be closed right after arriving.
        try? context.save()
        saved = record
        Haptic.success()
    }

    // MARK: Formatting

    static func distance(_ meters: Double) -> String {
        let miles = meters / 1609.34
        if miles >= 0.1 { return String(format: miles >= 10 ? "%.0f mi" : "%.1f mi", miles) }
        let feet = Int((meters * 3.281 / 50).rounded()) * 50
        return "\(max(feet, 0)) ft"
    }
}

/// The Drive screen's colours by day and by night: the only screen with a night.
struct DriveLook {
    let night: Bool
    var ground: Color { night ? Palette.night : Palette.page }
    /// The instruction is an overhead guide sign: highway green with a white border, white sign lettering (the
    /// format drivers are trained to read at a glance); a dimmer green at night.
    var panel: Color { night ? Palette.signNight : Palette.sign }
    var panelText: Color { Palette.onSign }
    var panelSoft: Color { Palette.onSignSoft }
    var surface: Color { night ? Palette.nightPanel : Palette.field }
    var text: Color { night ? Palette.onDark : Palette.ink }
    var soft: Color { night ? Palette.nightRead : Palette.meta }
    var line: Color { night ? Palette.nightLine : Palette.hairline }
    var route: Color { night ? Palette.onDark : Palette.ink }
    var routeEdge: Color { night ? Palette.night : Palette.field }
    var traveled: Color { night ? Palette.nightLine : Palette.label }
}

// MARK: - The instruction

/// The next move: the lane change while in a lane stretch, or the lanes to use, then the mark, the distance
/// (the biggest thing on the screen), the instruction and a bar that empties toward the turn; the lights left
/// before it; and what comes right after, when it is close.
private struct InstructionPanel: View {
    let session: DriveSession
    let look: DriveLook

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            if let zone = session.activeLaneZone {
                LaneChange(zone: zone, progress: session.laneZoneProgress,
                           metersLeft: zone.endMeters - (session.progress?.alongMeters ?? zone.startMeters), look: look)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let strip = session.laneStrip {
                LaneRow(strip: strip, onSign: true, height: DriveSize.laneTall).transition(.move(edge: .top).combined(with: .opacity))
            }
            if let m = session.nextManeuver {
                HStack(alignment: .center, spacing: Space.s16) {
                    if let shape = session.roundaboutShapes[m.id] {
                        RoundaboutMark(shape: shape, size: DriveSize.markBig + Space.s8, ink: look.panelText, way: Palette.onSign)
                    } else {
                        Mark(glyph: .maneuver(m), size: DriveSize.markBig, weight: MarkWeight.drive).foregroundStyle(look.panelText)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(DriveView.distance(session.metersToNextManeuver ?? 0))
                            .role(.driveDistance).foregroundStyle(look.panelText)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                            .animation(Motion.quick, value: session.metersToNextManeuver.map { Int($0 / 15) })
                        Text(m.instruction).role(.driveInstruction).foregroundStyle(look.panelText)
                            .lineLimit(3).minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                    if let n = session.lightsToNextManeuver { LightsLeft(count: n, look: look) }
                }
                if let p = session.nextManeuverProgress {
                    // Empties toward the turn, so "almost there" reads without the number.
                    ProgressLine(fraction: 1 - p, tint: Palette.onSign, track: Palette.signTrack)
                        .animation(Motion.follow, value: p)
                }
                // What Baxi just said, quietly, so a passenger can read it (unless a state above is showing).
                if !session.lastCueText.isEmpty && !StatusLine.isState(session) {
                    Text(session.lastCueText).role(.metaStrong).foregroundStyle(look.panelSoft).lineLimit(2)
                        .contentTransition(.opacity)
                        .accessibilityLabel("Baxi said: \(session.lastCueText)")
                }
                if let then = session.thenManeuver {
                    HStack(spacing: Space.s8) {
                        Text("Then").role(.metaStrong).foregroundStyle(look.panelSoft)
                        Mark(glyph: .maneuver(then), size: MarkSize.inline, weight: MarkWeight.emphasis).foregroundStyle(look.panelText)
                        Text(then.instruction).role(.metaStrong).foregroundStyle(look.panelText).lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Then \(then.instruction)")
                }
            } else {
                HStack(spacing: Space.s16) {
                    Mark(glyph: .start, size: DriveSize.markBig, weight: MarkWeight.heavy).foregroundStyle(look.panelText)
                    Text("Head to the start of the route").role(.driveInstruction).foregroundStyle(look.panelText)
                }
            }
        }
        .padding(Space.s16 + SignStyle.borderInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(look.panel, in: RoundedRectangle(cornerRadius: SignStyle.corner + Space.s4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SignStyle.corner, style: .continuous)
                    .inset(by: SignStyle.borderInset + 1).stroke(Palette.onSign, lineWidth: SignStyle.border))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .animation(Motion.standard, value: session.laneStrip)
        .animation(Motion.standard, value: session.activeLaneZone?.id)
        .animation(Motion.standard, value: session.nextManeuver?.id)
    }
}

/// How many traffic lights are left before the turn, the turn's own light included.
private struct LightsLeft: View {
    let count: Int
    let look: DriveLook
    var body: some View {
        VStack(spacing: Space.s4) {
            Text("\(count)").role(.number).foregroundStyle(look.panelText).contentTransition(.numericText())
            Text(count == 1 ? "light" : "lights").role(.metaStrong).foregroundStyle(look.panelSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) traffic \(count == 1 ? "light" : "lights") until the turn")
    }
}

/// While the car is in a lane stretch: what to do, the room left, and the lanes from above with the one to be in
/// lit amber and chevrons sweeping toward it. The lane lines are dashed while changing is fine and turn solid at
/// "be in the lane by here", as on the road.
private struct LaneChange: View {
    let zone: LaneZone
    let progress: Double
    let metersLeft: Double
    let look: DriveLook
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var committed: Bool { metersLeft <= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            HStack(alignment: .firstTextBaseline) {
                Text(committed ? "Stay in this lane" : zone.instruction).role(.signTitle).foregroundStyle(look.panelText)
                Spacer(minLength: Space.s8)
                if !committed {
                    Text("\(DriveView.distance(metersLeft)) to do it").role(.metaStrong).foregroundStyle(look.panelSoft)
                        .contentTransition(.numericText())
                        .animation(Motion.quick, value: Int(metersLeft / 15))
                }
            }
            road
            ProgressLine(fraction: committed ? 0 : 1 - progress, tint: Palette.ready, track: Palette.signTrack)
        }
        .onAppear { if !reduceMotion { withAnimation(Motion.sweep) { sweep = true } } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(committed ? "Stay in this lane" : "\(zone.instruction), \(DriveView.distance(metersLeft)) left to do it. "
                            + LaneRow.spoken(zone.strip))
    }

    private var road: some View {
        let s = zone.strip
        let lit = Set(s.highlighted)
        return HStack(spacing: 0) {
            ForEach(0..<s.laneCount, id: \.self) { i in
                ZStack {
                    Rectangle().fill(lit.contains(i) ? Palette.ready : Palette.signLane)
                    LaneMark(label: i < s.labels.count ? s.labels[i] : "", size: MarkSize.lane)
                        .foregroundStyle(lit.contains(i) ? Palette.ink : look.panelSoft)
                    if !lit.contains(i) && !committed, let toward = direction(from: i, lit: lit) {
                        Mark(glyph: toward > 0 ? .forward : .back, size: MarkSize.inline, weight: MarkWeight.heavy).foregroundStyle(Palette.ready)
                            .offset(x: sweep ? CGFloat(toward) * Space.s16 : CGFloat(-toward) * Space.s8)
                            .opacity(sweep ? 0.15 : 1)
                    }
                }
                .frame(maxWidth: .infinity)
                if i < s.laneCount - 1 { LaneDivider(solid: committed) }
            }
        }
        .frame(height: DriveSize.laneTall)
        .clipShape(RoundedRectangle(cornerRadius: LaneSize.corner, style: .continuous))
    }

    /// +1 when the lane to be in is to the right of lane `i`, -1 when to the left.
    private func direction(from i: Int, lit: Set<Int>) -> Int? {
        guard let lo = lit.min(), let hi = lit.max() else { return nil }
        return i < lo ? 1 : (i > hi ? -1 : nil)
    }
}

/// A lane line: dashed where changing lanes is allowed, solid where it is not.
private struct LaneDivider: View {
    let solid: Bool
    var body: some View {
        GeometryReader { geo in
            Path { p in p.move(to: CGPoint(x: geo.size.width / 2, y: 0)); p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height)) }
                .stroke(Palette.onDark, style: StrokeStyle(lineWidth: geo.size.width, dash: solid ? [] : LaneSize.dash))
        }
        .frame(width: LaneSize.divider)
    }
}

/// Where a lane change must be done by: an amber tab at the end of the stretch on the map.
private struct InLaneTab: View {
    let zone: LaneZone
    var body: some View {
        Text(zone.laneLabel.map { "In the \($0)" } ?? "In lane")
            .role(.metaStrong).foregroundStyle(Palette.ink)
            .padding(.horizontal, Space.s8).padding(.vertical, Space.s4)
            .background(Palette.ready, in: Capsule())
            .overlay(Capsule().stroke(Palette.field, lineWidth: MapLine.dotEdge))
    }
}

// MARK: - Status, alerts, controls

/// The last thing Baxi said, small, so a passenger can read it; or a state that matters more: off the route
/// (amber), location off (red, with Settings), waiting for GPS.
private struct StatusLine: View {
    let session: DriveSession
    let look: DriveLook

    var body: some View {
        Group {
            if session.mode == .live && !session.hasFix && session.lastCueText.isEmpty {
                line(text: session.coarseFixes ? "Weak GPS. Check Precise Location in Settings" : "Waiting for GPS",
                     fill: look.surface, ink: look.text) { SignalDots(onFill: false) }
            } else if session.lastCueText == DriveSession.locationOffText {
                line(text: session.lastCueText, fill: Palette.stop, ink: Palette.onStop) {
                    Button("Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .role(.bodyStrong).foregroundStyle(Palette.onStop).underline()
                    .buttonStyle(Press()).frame(minHeight: Size.tap)
                    .accessibilityHint("Opens Settings to turn on location for Baxi")
                }
            } else if offRoute {
                line(text: session.lastCueText, fill: Palette.ready, ink: Palette.ink) {
                    Mark(glyph: .offRoute, size: MarkSize.row).foregroundStyle(Palette.ink)
                }
            }
        }
        .animation(Motion.standard, value: session.lastCueText)
    }

    private var offRoute: Bool { Self.offRoute(session) }

    static func offRoute(_ session: DriveSession) -> Bool {
        session.progress?.isOffRoute == true || session.isRerouting || session.lastCueText == DriveSession.rerouteFailedText
    }

    /// A state that matters more than the last thing said: waiting for GPS, location off, off the route.
    static func isState(_ session: DriveSession) -> Bool {
        (session.mode == .live && !session.hasFix && session.lastCueText.isEmpty)
            || session.lastCueText == DriveSession.locationOffText || offRoute(session)
    }

    private func line<Accessory: View>(text: String, fill: Color, ink: Color, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: Space.s12) {
            Text(text).role(.bodyStrong).foregroundStyle(ink).lineLimit(2)
            Spacer(minLength: Space.s8)
            accessory()
        }
        .padding(.horizontal, Space.s16).padding(.vertical, Space.s8)
        .frame(maxWidth: .infinity, minHeight: Size.tap, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: Corner.control, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
    }
}

/// A heads-up the car is in or about to reach: amber (get ready), with its mark and one word.
private struct AlertChip: View {
    let kind: CueKind
    var body: some View {
        let (sign, text): (WarningSign.Kind, String) = switch kind {
        case .schoolZone: (.school, "School zone")
        case .railroad: (.railroad, "Railroad")
        case .glare: (.sun, "Low sun")
        default: (.warning, "Crash-heavy")
        }
        // The heads-up as its road sign, with one word beside it.
        return HStack(spacing: Space.s8) {
            WarningSign(kind: sign)
            Text(text).role(.metaStrong).foregroundStyle(Palette.ink)
        }
        .padding(.leading, Space.s4).padding(.trailing, Space.s12).padding(.vertical, Space.s4)
        .background(Palette.field, in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
    }
}

/// Mute, how far to go and when you'll arrive, End. For the passenger; the driver never needs it.
private struct ControlBar: View {
    let session: DriveSession
    let look: DriveLook
    @State private var confirmEnd = false

    private var remaining: Double { session.progress?.remainingMeters ?? session.route.distanceMeters }
    private var arrival: Date? {
        guard session.route.distanceMeters > 0, session.mode == .live else { return nil }
        return Date().addingTimeInterval(session.route.durationSeconds * remaining / session.route.distanceMeters)
    }

    var body: some View {
        HStack(spacing: Space.s12) {
            Button { session.muted.toggle(); Haptic.tap() } label: {
                Mark(glyph: session.muted ? .speakerOff : .speaker, size: MarkSize.car)
                    .foregroundStyle(session.muted ? Palette.ink : look.text)
                    .frame(width: DriveSize.control, height: DriveSize.control)
                    .background(session.muted ? Palette.ready : look.surface, in: Circle())
            }
            .buttonStyle(Press())
            .accessibilityLabel(session.muted ? "Unmute Baxi" : "Mute Baxi")

            VStack(spacing: 0) {
                Text(DriveView.distance(remaining)).role(.numberSmall).foregroundStyle(look.text)
                    .contentTransition(.numericText())
                Group {
                    if case .replay = session.mode { Text("Demo, not logged") }
                    else if let arrival { Text("arrive \(arrival.formatted(date: .omitted, time: .shortened))") }
                    else { Text("to go") }
                }
                .role(.meta).foregroundStyle(look.soft)
            }
            .frame(maxWidth: .infinity, minHeight: DriveSize.control)
            .background(look.surface, in: Capsule())
            .accessibilityElement(children: .combine)

            // A live drive asks first: one stray tap from the passenger must not end it. Replays just end.
            Button { Haptic.tap(); if session.mode == .live { confirmEnd = true } else { session.end() } } label: {
                Text("End").role(.button).foregroundStyle(Palette.onStop)
                    .frame(width: DriveSize.endWidth, height: DriveSize.control)
                    .background(Palette.stop, in: Capsule())
            }
            .buttonStyle(Press())
            .accessibilityLabel("End drive")
            .confirmationDialog("End this drive?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End drive", role: .destructive) { session.end() }
                Button("Keep driving", role: .cancel) {}
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// The posted limit and the car's speed as one unit: the sign, and the speed under it, amber (get ready) when
/// more than 5 over. Either half hides when unknown.
private struct SpeedUnit: View {
    let limit: Int?
    let speed: Int?
    let judgedLimit: Int?
    let night: Bool
    var body: some View {
        VStack(spacing: Space.s4) {
            if let limit { SpeedLimitSign(mph: limit).transition(.opacity) }
            if let speed { SpeedReadout(mph: speed, limit: judgedLimit, night: night).transition(.opacity) }
        }
        .animation(Motion.standard, value: limit)
        .animation(Motion.standard, value: speed == nil)
    }
}
