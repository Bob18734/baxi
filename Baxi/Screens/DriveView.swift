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
                HStack(alignment: .top) {
                    if let mph = session.speedLimitMph { SpeedLimitSign(mph: mph).animation(.snappy, value: mph) }
                    Spacer()
                    if let alert = session.activeAlert {
                        Group { if alert.kind == .schoolZone { SchoolZoneChip() } else { CrashChip() } }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: session.activeAlert?.id)
                Spacer()
                DriveBottomBar(session: session)
            }
            .padding(.horizontal, BaxiSpace.md)
            .padding(.vertical, BaxiSpace.sm)
        }
        .onAppear {
            // The phone is mounted for the whole drive, so the screen must not lock.
            UIApplication.shared.isIdleTimerDisabled = true
            // After sunset the whole screen goes dark so it does not glare in the driver's eyes.
            if let s = Daylight.sunriseSunset(on: Date(), at: session.startCoordinate ?? AppStore.carmelDemoHome) {
                isNight = Date() < s.sunrise || Date() >= s.sunset
            }
            session.start(); follow()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if !session.isFinished { session.end() }
        }
        .onChange(of: session.position) { _, _ in follow() }
        .onChange(of: session.isFinished) { _, done in if done { save() } }
        .sheet(isPresented: .constant(session.isFinished)) {
            ArrivedView(session: session, record: saved, onDone: onClose)
        }
        .preferredColorScheme(isNight ? .dark : nil)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera, interactionModes: []) {
            MapPolyline(coordinates: session.routeCoordinates)
                .stroke(BaxiColor.route, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
            if let traveled = traveledPoints, traveled.count > 1 {
                MapPolyline(coordinates: traveled.map(\.clLocation))
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
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
    }

    private var traveledPoints: [Coordinate]? {
        guard let p = session.progress else { return nil }
        let line = session.route.polyline
        return Array(line.points.prefix(p.segmentIndex + 1)) + [p.snapped]
    }

    private func follow() {
        guard let p = session.position else { return }
        withAnimation(.linear(duration: 0.25)) {
            camera = .camera(MapCamera(centerCoordinate: p.clLocation, distance: 700, heading: session.heading, pitch: 50))
        }
    }

    // MARK: Save

    private func save() {
        guard !didSave else { return }
        didSave = true
        let end = session.endedAt ?? Date()
        // A replay is a demo, not a supervised drive, so it never counts toward the 50 hours.
        guard session.mode == .live, end.timeIntervalSince(session.startedAt) >= 60 else { return }
        let split = Daylight.split(start: session.startedAt, end: end, at: session.startCoordinate ?? AppStore.carmelDemoHome)
        let record = DriveRecord(start: session.startedAt, end: end, dayMinutes: split.day, nightMinutes: split.night,
                                 level: session.level, routeTitle: session.route.name,
                                 distanceMeters: session.drivenMeters, cuesSpoken: session.spokenLog.count)
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
            if let strip = session.laneStrip {
                LaneStripView(strip: strip).transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack(alignment: .center, spacing: BaxiSpace.md) {
                if let m = session.nextManeuver {
                    Image(systemName: DriveView.symbol(for: m))
                        .font(.system(size: 46, weight: .heavy)) // design-lint:allow the sign's arrow is a drawn mark
                        .frame(width: 60)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(DriveView.distance(session.metersToNextManeuver ?? 0))
                            .font(BaxiFont.signFace(38))
                            .contentTransition(.numericText())
                            .animation(.snappy, value: session.metersToNextManeuver.map { Int($0 / 15) })
                        Text(m.instruction).font(BaxiFont.headline).lineLimit(2).minimumScaleFactor(0.7)
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
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .animation(.snappy, value: session.laneStrip)
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
        let off = session.progress?.isOffRoute == true || session.isRerouting
        HStack(spacing: BaxiSpace.md) {
            Image(systemName: off ? "arrow.triangle.branch" : "waveform")
                .font(BaxiFont.headline)
                .symbolEffect(.variableColor.iterative, isActive: session.isRerouting)
                .foregroundStyle(off ? BaxiColor.signInk : BaxiColor.accent)
            Text(session.lastCueText).font(BaxiFont.bodyBold).lineLimit(2)
                .foregroundStyle(off ? BaxiColor.signInk : BaxiColor.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BaxiSpace.lg).padding(.vertical, BaxiSpace.md)
        .background {
            if off { RoundedRectangle(cornerRadius: BaxiRadius.lg, style: .continuous).fill(BaxiColor.caution) }
            else { RoundedRectangle(cornerRadius: BaxiRadius.lg, style: .continuous).fill(.regularMaterial) }
        }
        .animation(.snappy, value: session.lastCueText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Baxi said: \(session.lastCueText)")
    }
}

/// Mute, distance and arrival time, End. For the passenger; the driver never needs it.
private struct DriveBottomBar: View {
    let session: DriveSession

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

            Button { session.end() } label: {
                Text("End").font(BaxiFont.button).foregroundStyle(.white)
                    .frame(width: 84, height: 60)
                    .background(BaxiColor.stop, in: Capsule())
            }
            .accessibilityLabel("End drive")
        }
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
