import SwiftUI
import MapKit
import SwiftData

/// The main screen. The phone is mounted; nobody touches it while the car moves. Everything here is
/// readable at a glance: the next maneuver as a green guide sign with its distance, the lane strip with
/// the lane to be in lit yellow, the light count, the speed limit, and the last thing Baxi said.
/// Only Mute and End are tappable, both meant for the passenger or for when the car is parked.
struct DriveView: View {
    let session: DriveSession
    var onClose: () -> Void
    @Environment(\.modelContext) private var context
    @State private var camera: MapCameraPosition = .automatic
    @State private var saved: DriveRecord?
    @State private var didSave = false
    @State private var isNight = false

    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: BaxiSpace.sm) {
                ManeuverSign(session: session, night: isNight)
                if !session.lastCueText.isEmpty { SaidBanner(session: session) }
                else if session.mode == .live && !session.hasFix { WaitingForGPS() }
                HStack(alignment: .top) {
                    if let mph = session.speedLimitMph { SpeedLimitSign(mph: mph).animation(.snappy, value: mph) }
                    // The car's own speed, next to the limit; orange when more than 5 over.
                    if let speed = session.currentMph {
                        SpeedPill(mph: speed, limit: session.speedLimitMph).transition(.opacity)
                    }
                    Spacer()
                    if let alert = session.activeAlert {
                        Group {
                            switch alert.kind {
                            case .schoolZone: SchoolZoneChip()
                            case .railroad: RailChip()
                            case .glare: GlareChip()
                            default: CrashChip()
                            }
                        }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: session.activeAlert?.id)
                .animation(.snappy, value: session.currentMph == nil)
                Spacer()
                DriveBottomBar(session: session)
            }
            .padding(.horizontal, BaxiSpace.md)
            .padding(.vertical, BaxiSpace.sm)
        }
        .onAppear {
            // The phone is mounted for the whole drive, so the screen must not lock.
            UIApplication.shared.isIdleTimerDisabled = true
            isNight = nightNow()
            session.start(); follow()
        }
        // After sunset the whole screen goes dark so it does not glare in the driver's eyes; checked every
        // minute so a drive across sunset switches over.
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                let night = nightNow()
                if night != isNight { withAnimation(.smooth(duration: 1.5)) { isNight = night } }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if !session.isFinished { session.end() }
        }
        .onChange(of: session.position) { _, _ in follow() }
        .onChange(of: traveledStep) { _, _ in traveled = traveledPoints?.map(\.clLocation) ?? [] }
        .onChange(of: session.isFinished) { _, done in if done { save() } }
        .sheet(isPresented: .constant(session.isFinished)) {
            ArrivedView(session: session, record: saved, onDone: onClose)
        }
        .preferredColorScheme(isNight ? .dark : nil)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private func nightNow() -> Bool {
        let at = session.position ?? session.startCoordinate ?? AppStore.carmelDemoHome
        guard let s = Daylight.sunriseSunset(on: Date(), at: at) else { return false }
        return Date() < s.sunrise || Date() >= s.sunset
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera, interactionModes: []) {
            MapPolyline(coordinates: session.routeCoordinates)
                .stroke(BaxiColor.route, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
            // Where to change lanes, in the lane strip's yellow: from the lane cue to "be in the lane by here".
            ForEach(zonesAhead) { z in
                if let line = session.laneZoneCoordinates[z.id], line.count > 1 {
                    // A dark edge under the yellow, so it stands out on Apple Maps' own yellow freeways.
                    MapPolyline(coordinates: line)
                        .stroke(BaxiColor.signInk, style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: line)
                        .stroke(BaxiColor.warning, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    Annotation("", coordinate: line[line.count - 1]) { InLaneMarker(zone: z) }
                }
            }
            if traveled.count > 1 {
                MapPolyline(coordinates: traveled)
                    .stroke(.gray.opacity(0.75), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
            }
            if let m = session.nextManeuver {
                Annotation("", coordinate: m.location.clLocation) {
                    Image(systemName: Self.symbol(for: m)).font(BaxiFont.headline).foregroundStyle(BaxiColor.onSign)
                        .frame(width: 34, height: 34)
                        .signPanel(radius: BaxiRadius.sm)
                }
            }
            if let p = session.position {
                Annotation("", coordinate: p.clLocation) {
                    Image(systemName: "location.north.fill").font(BaxiFont.title).foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(BaxiColor.route, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 4))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll)) // 3D freeways would cover the route and lane zones
        .ignoresSafeArea()
    }

    @State private var traveled: [CLLocationCoordinate2D] = []
    private var traveledStep: Int { Int((session.progress?.alongMeters ?? 0) / 50) }

    /// The driven part of the route, redrawn every 50 m rather than on every fix: rebuilding a long map
    /// overlay several times a second is what makes the map stutter.
    private var traveledPoints: [Coordinate]? {
        guard let p = session.progress else { return nil }
        let line = session.route.polyline
        let step = (p.alongMeters / 50).rounded(.down) * 50
        guard step > 0, let end = line.coordinate(atMeters: step) else { return nil }
        let upTo = line.cumulative.lastIndex { $0 <= step } ?? 0
        return Array(line.points.prefix(upTo + 1)) + [end]
    }

    /// Lane zones not yet passed and within 3 km, so the map is not cluttered with the whole route's.
    private var zonesAhead: [LaneZone] {
        let along = session.progress?.alongMeters ?? 0
        return session.laneZones.filter { $0.endMeters > along && $0.startMeters < along + 3_000 }
    }

    private func follow() {
        guard let p = session.position else { return }
        // Closer while changing lanes, so the yellow stretch and its end marker are easy to read.
        let distance: Double = session.activeLaneZone == nil ? 700 : 420
        withAnimation(.linear(duration: 0.25)) {
            camera = .camera(MapCamera(centerCoordinate: p.clLocation, distance: distance, heading: session.heading, pitch: 50))
        }
    }

    // MARK: Save

    private func save() {
        guard !didSave else { return }
        didSave = true
        let end = session.endedAt ?? Date()
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
        Haptics.success()
    }

    // MARK: Formatting

    static func distance(_ meters: Double) -> String {
        let miles = meters / 1609.34
        if miles >= 0.1 { return String(format: miles >= 10 ? "%.0f mi" : "%.1f mi", miles) }
        let feet = Int((meters * 3.281 / 50).rounded()) * 50
        return "\(max(feet, 0)) ft"
    }

    static func symbol(for m: Maneuver) -> String {
        switch m.kind {
        case .roundabout: return "arrow.triangle.turn.up.right.circle"
        case .merge, .onRamp: return "arrow.merge"
        case .offRamp, .fork: return (m.direction?.rawValue.lowercased().contains("left") ?? false) ? "arrow.up.left" : "arrow.up.right"
        case .arrive: return "flag.checkered"
        case .turn:
            switch m.direction {
            case .left, .sharpLeft: return "arrow.turn.up.left"
            case .right, .sharpRight: return "arrow.turn.up.right"
            case .slightLeft: return "arrow.up.left"
            case .slightRight: return "arrow.up.right"
            case .uturn: return "arrow.uturn.down"
            default: return "arrow.up"
            }
        default: return "arrow.up"
        }
    }
}

/// The next maneuver as a green guide sign: lanes on top, then the arrow, the distance and the words,
/// and the traffic lights left before the turn.
private struct ManeuverSign: View {
    let session: DriveSession
    let night: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            if let zone = session.activeLaneZone {
                LaneChangePanel(zone: zone, progress: session.laneZoneProgress,
                                metersLeft: zone.endMeters - (session.progress?.alongMeters ?? zone.startMeters))
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let strip = session.laneStrip {
                LaneStripView(strip: strip).transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack(alignment: .center, spacing: BaxiSpace.md) {
                if let m = session.nextManeuver {
                    if let shape = session.roundaboutShapes[m.id] {
                        RoundaboutGlyph(shape: shape, size: 64)
                    } else {
                        Image(systemName: DriveView.symbol(for: m))
                            .font(.system(size: 46, weight: .heavy)) // design-lint:allow the sign's arrow is a drawn mark
                            .frame(width: 60)
                    }
                    VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                        Text(DriveView.distance(session.metersToNextManeuver ?? 0))
                            .font(BaxiFont.signFace(38))
                            .contentTransition(.numericText())
                            .animation(.snappy, value: session.metersToNextManeuver.map { Int($0 / 15) })
                        Text(m.instruction).font(BaxiFont.headline).lineLimit(2).minimumScaleFactor(0.7)
                        // Shrinks to the turn, so "almost there" reads without the number.
                        if let p = session.nextManeuverProgress {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(BaxiColor.onSign.opacity(0.2))
                                    Capsule().fill(BaxiColor.onSign).frame(width: max(4, geo.size.width * (1 - p)))
                                }
                            }
                            .frame(height: 5)
                            .padding(.top, BaxiSpace.xs)
                            .animation(.linear(duration: 0.25), value: p)
                        }
                    }
                    Spacer(minLength: 0)
                    if let n = session.lightsToNextManeuver { LightCount(count: n) }
                } else {
                    Image(systemName: "location.north.line.fill").font(BaxiFont.title).frame(width: 60)
                    Text("Head to the start of the route").font(BaxiFont.section)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(BaxiSpace.lg)
        .padding(.horizontal, BaxiSpace.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .signPanel(radius: BaxiRadius.xl, deep: night)
        .overlay(alignment: .bottomTrailing) {
            // What comes right after, when it is close: no surprise second turn.
            if let then = session.thenManeuver {
                HStack(spacing: BaxiSpace.xs) {
                    Text("Then").font(BaxiFont.footnote.weight(.semibold))
                    Image(systemName: DriveView.symbol(for: then)).font(BaxiFont.headline)
                }
                .foregroundStyle(BaxiColor.signInk)
                .padding(.horizontal, BaxiSpace.md).padding(.vertical, BaxiSpace.xs)
                .background(BaxiColor.onSign, in: Capsule())
                .padding(BaxiSpace.lg)
                .accessibilityLabel("Then \(then.instruction)")
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .animation(.snappy, value: session.laneStrip)
        .animation(.snappy, value: session.activeLaneZone?.id)
        .animation(.snappy, value: session.nextManeuver?.id)
    }
}

/// "2 lights": how many traffic lights are left before the turn, the turn's own light included.
private struct LightCount: View {
    let count: Int
    var body: some View {
        HStack(spacing: BaxiSpace.sm) {
            TrafficLightMark(size: 9)
            VStack(spacing: 0) {
                Text("\(count)").font(BaxiFont.signFace(30)).contentTransition(.numericText())
                Text(count == 1 ? "light" : "lights").font(BaxiFont.signFace(12, weight: "Bold"))
            }
        }
        .padding(.horizontal, BaxiSpace.sm).padding(.vertical, BaxiSpace.xs)
        .background(BaxiColor.onSign.opacity(0.14), in: RoundedRectangle(cornerRadius: BaxiRadius.md, style: .continuous))
        .animation(.snappy, value: count)
        .accessibilityElement()
        .accessibilityLabel("\(count) traffic \(count == 1 ? "light" : "lights") until the turn")
    }
}

/// The last thing Baxi said, so a passenger can read it. Orange while off the route.
private struct SaidBanner: View {
    let session: DriveSession
    var body: some View {
        let locationOff = session.lastCueText == DriveSession.locationOffText
        let off = session.progress?.isOffRoute == true || session.isRerouting || locationOff
            || session.lastCueText == DriveSession.rerouteFailedText
        HStack(spacing: BaxiSpace.md) {
            Image(systemName: off ? "arrow.triangle.branch" : "waveform")
                .font(BaxiFont.headline)
                .symbolEffect(.variableColor.iterative, isActive: session.isRerouting)
                .foregroundStyle(off ? BaxiColor.signInk : BaxiColor.accent)
            Text(session.lastCueText).font(BaxiFont.bodyBold).lineLimit(2)
                .foregroundStyle(off ? BaxiColor.signInk : BaxiColor.ink)
            Spacer(minLength: 0)
            if locationOff {
                // For the passenger: straight to Baxi's page in Settings.
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.signInk)
                .padding(.horizontal, BaxiSpace.md).frame(minHeight: 44)
                .background(.white.opacity(0.6), in: Capsule())
                .accessibilityHint("Opens Settings to turn on location for Baxi")
            }
        }
        .padding(.horizontal, BaxiSpace.lg).padding(.vertical, BaxiSpace.md)
        .background {
            if off { RoundedRectangle(cornerRadius: BaxiRadius.lg, style: .continuous).fill(BaxiColor.caution) }
            else { RoundedRectangle(cornerRadius: BaxiRadius.lg, style: .continuous).fill(.regularMaterial) }
        }
        .animation(.snappy, value: session.lastCueText)
        .accessibilityElement(children: locationOff ? .contain : .ignore)
        .accessibilityLabel("Baxi said: \(session.lastCueText)")
    }
}

/// A live drive before the first location fix: the sign has nothing true to show yet.
private struct WaitingForGPS: View {
    var body: some View {
        HStack(spacing: BaxiSpace.md) {
            ProgressView()
            Text("Waiting for GPS…").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BaxiSpace.lg).padding(.vertical, BaxiSpace.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BaxiRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Mute, distance and arrival time, End. For the passenger; the driver never needs it.
private struct DriveBottomBar: View {
    let session: DriveSession
    @State private var confirmEnd = false

    private var remaining: Double { session.progress?.remainingMeters ?? session.route.distanceMeters }
    private var arrival: Date? {
        guard session.route.distanceMeters > 0, session.mode == .live else { return nil }
        return Date().addingTimeInterval(session.route.durationSeconds * remaining / session.route.distanceMeters)
    }

    var body: some View {
        HStack(spacing: BaxiSpace.md) {
            Button { session.muted.toggle(); Haptics.tap() } label: {
                Image(systemName: session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(BaxiFont.section)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(session.muted ? BaxiColor.signInk : BaxiColor.ink)
                    .frame(width: 60, height: 60)
                    .background(session.muted ? AnyShapeStyle(BaxiColor.warning) : AnyShapeStyle(.regularMaterial), in: Circle())
            }
            .accessibilityLabel(session.muted ? "Unmute Baxi" : "Mute Baxi")

            VStack(spacing: 0) {
                Text(DriveView.distance(remaining)).font(BaxiFont.numberSmall).foregroundStyle(BaxiColor.ink)
                    .contentTransition(.numericText())
                Group {
                    if case .replay(let x) = session.mode { Text("to go · replay \(Int(x))×") }
                    else if let arrival { Text("to go · arrive \(arrival.formatted(date: .omitted, time: .shortened))") }
                    else { Text("to go") }
                }
                .font(BaxiFont.caption).foregroundStyle(BaxiColor.inkSoft)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(.regularMaterial, in: Capsule())

            // A live drive asks first: one stray tap from the passenger must not end it. Replays just end.
            Button { if session.mode == .live { confirmEnd = true } else { session.end() } } label: {
                Text("End").font(BaxiFont.button).foregroundStyle(.white)
                    .frame(width: 84, height: 60)
                    .background(BaxiColor.stop, in: Capsule())
            }
            .accessibilityLabel("End drive")
            .confirmationDialog("End this drive?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End drive", role: .destructive) { session.end() }
                Button("Keep driving", role: .cancel) {}
            }
        }
    }
}

/// While the car is in a lane zone: the lanes as seen from above, the lane to be in lit yellow, chevrons
/// in the other lanes sweeping toward it, and a bar for the room left to make the change. The lane lines
/// are dashed while changing is fine and turn solid at "be in the lane by here", as they do on the road.
private struct LaneChangePanel: View {
    let zone: LaneZone
    let progress: Double
    let metersLeft: Double
    @State private var sweep = false

    private var committed: Bool { metersLeft <= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(committed ? "Stay in this lane" : zone.instruction).font(BaxiFont.signFace(22))
                Spacer(minLength: BaxiSpace.sm)
                if !committed {
                    Text("\(DriveView.distance(metersLeft)) to do it").font(BaxiFont.signFace(14, weight: "Bold"))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: Int(metersLeft / 15))
                }
            }
            road
            // Room left to change lanes: full at the start of the zone, empty at the end.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BaxiColor.onSign.opacity(0.18))
                    Capsule().fill(BaxiColor.warning).frame(width: max(6, geo.size.width * (1 - progress)))
                        .opacity(committed ? 0 : 1)
                }
            }
            .frame(height: 6)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) { sweep = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(committed ? "Stay in this lane" : "\(zone.instruction), \(DriveView.distance(metersLeft)) left to do it. "
                            + LaneStripView.spoken(zone.strip))
    }

    private var road: some View {
        let s = zone.strip
        let lit = Set(s.highlighted)
        return HStack(spacing: 0) {
            ForEach(0..<s.laneCount, id: \.self) { i in
                ZStack {
                    Rectangle().fill(lit.contains(i) ? BaxiColor.warning : BaxiColor.onSign.opacity(0.10))
                    LaneArrows(label: i < s.labels.count ? s.labels[i] : "", size: 22)
                        .foregroundStyle(lit.contains(i) ? BaxiColor.signInk : BaxiColor.onSign.opacity(0.5))
                    if !lit.contains(i) && !committed, let toward = direction(from: i, lit: lit) {
                        Image(systemName: toward > 0 ? "chevron.right.2" : "chevron.left.2")
                            .font(BaxiFont.headline.weight(.heavy))
                            .foregroundStyle(BaxiColor.warning)
                            .offset(x: sweep ? CGFloat(toward) * 18 : CGFloat(-toward) * 10)
                            .opacity(sweep ? 0.15 : 1)
                    }
                }
                .frame(maxWidth: .infinity)
                if i < s.laneCount - 1 {
                    LaneLine(solid: committed).frame(width: 3)
                }
            }
        }
        .frame(height: 58)
        .clipShape(RoundedRectangle(cornerRadius: BaxiRadius.sm, style: .continuous))
    }

    /// +1 when the lane to be in is to the right of lane `i`, -1 when to the left.
    private func direction(from i: Int, lit: Set<Int>) -> Int? {
        guard let lo = lit.min(), let hi = lit.max() else { return nil }
        return i < lo ? 1 : (i > hi ? -1 : nil)
    }
}

/// A lane line: dashed where changing lanes is allowed, solid where it is not.
private struct LaneLine: View {
    let solid: Bool
    var body: some View {
        GeometryReader { geo in
            Path { p in p.move(to: CGPoint(x: geo.size.width / 2, y: 0)); p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height)) }
                .stroke(BaxiColor.onSign, style: StrokeStyle(lineWidth: geo.size.width, dash: solid ? [] : [9, 7]))
        }
    }
}

/// Where the lane change must be done: a yellow tab at the end of the zone on the map.
private struct InLaneMarker: View {
    let zone: LaneZone
    var body: some View {
        HStack(spacing: BaxiSpace.xs) {
            Image(systemName: zone.side == .left ? "arrow.left.to.line" : zone.side == .right ? "arrow.right.to.line" : "arrow.up.to.line")
            Text(zone.laneLabel.map { "In the \($0)" } ?? "In lane")
        }
        .font(BaxiFont.caption.weight(.bold))
        .foregroundStyle(BaxiColor.signInk)
        .padding(.horizontal, BaxiSpace.sm).padding(.vertical, BaxiSpace.xs)
        .background(BaxiColor.warning, in: Capsule())
        .overlay(Capsule().stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

/// One box per lane, the lane to be in lit sign yellow (the same yellow as the app icon).
struct LaneStripView: View {
    let strip: LaneStrip
    var body: some View {
        HStack(spacing: BaxiSpace.sm) {
            ForEach(0..<strip.laneCount, id: \.self) { i in
                let lit = strip.highlighted.contains(i)
                LaneArrows(label: i < strip.labels.count ? strip.labels[i] : "", size: 24)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(lit ? BaxiColor.signInk : BaxiColor.onSign.opacity(0.55))
                    .background(lit ? BaxiColor.warning : BaxiColor.onSign.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: BaxiRadius.sm, style: .continuous))
                    .scaleEffect(lit ? 1 : 0.94)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Self.spoken(strip))
    }

    static func spoken(_ strip: LaneStrip) -> String {
        let lanes = strip.highlighted.sorted().map { String($0 + 1) }
        switch lanes.count {
        case 0: return "\(strip.laneCount) lanes"
        case 1: return "Use lane \(lanes[0]) of \(strip.laneCount), counting from the left"
        default: return "Use lanes \(lanes.dropLast().joined(separator: ", ")) or \(lanes.last!) of \(strip.laneCount), counting from the left"
        }
    }
}
