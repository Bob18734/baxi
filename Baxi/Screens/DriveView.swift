import SwiftUI
import MapKit
import SwiftData

/// The main screen. The phone is mounted; nobody touches it while the car moves. Everything here is
/// readable at a glance: the next maneuver and its distance, the light count, the lane strip, and the
/// last thing Baxi said. Only End drive and mute are tappable, both meant for the passenger or a stop.
struct DriveView: View {
    let session: DriveSession
    var onClose: () -> Void
    @Environment(\.modelContext) private var context
    @State private var camera: MapCameraPosition = .automatic
    @State private var saved = false

    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: 10) {
                instructionCard
                if !session.lastCueText.isEmpty { saidBanner }
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { session.start(); follow() }
        .onChange(of: session.position) { _, _ in follow() }
        .onChange(of: session.isFinished) { _, done in if done { save() } }
        .sheet(isPresented: .constant(session.isFinished)) { arrived }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera, interactionModes: []) {
            MapPolyline(coordinates: session.route.polyline.points.map(\.clLocation))
                .stroke(.blue.opacity(0.85), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            if let traveled = traveledPoints, traveled.count > 1 {
                MapPolyline(coordinates: traveled.map(\.clLocation))
                    .stroke(.gray.opacity(0.7), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            }
            if let m = session.nextManeuver {
                Annotation("", coordinate: m.location.clLocation) {
                    Image(systemName: Self.symbol(for: m)).font(.title3.bold()).foregroundStyle(.white)
                        .padding(6).background(.orange, in: Circle())
                }
            }
            if let p = session.position {
                Annotation("", coordinate: p.clLocation) {
                    Image(systemName: "location.north.fill").font(.title).foregroundStyle(.white)
                        .padding(8).background(.blue, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 3))
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

    // MARK: Card

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let strip = session.laneStrip { LaneStripView(strip: strip) }
            HStack(alignment: .center, spacing: 14) {
                if let m = session.nextManeuver {
                    Image(systemName: Self.symbol(for: m)).font(.system(size: 44, weight: .bold))
                        .frame(width: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.distance(session.metersToNextManeuver ?? 0)).font(.system(size: 34, weight: .heavy))
                        Text(m.instruction).font(.title3.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    if let n = session.lightsToNextManeuver {
                        VStack(spacing: 0) {
                            Text("\(n)").font(.system(size: 30, weight: .heavy))
                            Text(n == 1 ? "light" : "lights").font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("\(n) traffic lights until the turn")
                    }
                } else {
                    Text("Head to the route").font(.title2.bold())
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.07, green: 0.33, blue: 0.22), in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 8)
    }

    private var saidBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: session.progress?.isOffRoute == true ? "exclamationmark.triangle.fill" : "speaker.wave.2.fill")
            Text(session.lastCueText).font(.headline).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var bottomBar: some View {
        HStack {
            Button { session.muted.toggle() } label: {
                Image(systemName: session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.title2)
                    .frame(width: 56, height: 56).background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(session.muted ? "Unmute" : "Mute")
            Spacer()
            VStack(spacing: 2) {
                Text(Self.distance(session.progress?.remainingMeters ?? session.route.distanceMeters)).font(.headline)
                Text(session.mode == .live ? "to go" : "to go · replay").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            Spacer()
            Button(role: .destructive) { session.end() } label: {
                Text("End").font(.headline).frame(width: 72, height: 56).background(.red, in: Capsule()).foregroundStyle(.white)
            }
        }
    }

    // MARK: Arrived

    private var arrived: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Route", value: session.route.name)
                    LabeledContent("Time", value: "\(Int(session.minutes.rounded())) min")
                    LabeledContent("Distance", value: Self.distance(session.progress?.alongMeters ?? 0))
                    LabeledContent("Cues spoken", value: "\(session.spokenLog.count)")
                }
                Section("What Baxi said") {
                    ForEach(Array(session.spokenLog.enumerated()), id: \.offset) { _, e in
                        Text(e.text).font(.callout)
                    }
                }
            }
            .navigationTitle("Arrived")
            .toolbar { Button("Done") { onClose() } }
        }
        .interactiveDismissDisabled()
    }

    private func save() {
        guard !saved else { return }
        saved = true
        let mins = Int(session.minutes.rounded())
        // A replay is a demo, not a supervised drive, so it never counts toward the 50 hours.
        guard session.mode == .live, mins > 0 else { return }
        context.insert(DriveRecord(start: session.startedAt, end: Date(), dayMinutes: mins, nightMinutes: 0,
                                   level: session.level, routeTitle: session.route.name,
                                   distanceMeters: session.progress?.alongMeters ?? 0, cuesSpoken: session.spokenLog.count))
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

/// The lane strip across the top: one box per lane, the lane to be in lit.
struct LaneStripView: View {
    let strip: LaneStrip
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<strip.laneCount, id: \.self) { i in
                let lit = strip.highlighted.contains(i)
                Text(i < strip.labels.count && !strip.labels[i].isEmpty ? strip.labels[i] : "↑")
                    .font(.system(size: 26, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(lit ? Color.white : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(lit ? Color(red: 0.07, green: 0.33, blue: 0.22) : .white.opacity(0.6))
            }
        }
        .accessibilityLabel("Lane \(strip.highlighted.first.map { $0 + 1 } ?? 0) of \(strip.laneCount)")
    }
}
