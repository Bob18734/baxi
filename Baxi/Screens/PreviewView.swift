import SwiftUI
import MapKit

/// Before the drive, at home or parked: every hard spot on the route as street-level imagery, what Baxi
/// will say there, and the rule from the Indiana Driver's Manual (written by the students).
struct PreviewView: View {
    let routeName: String
    let spots: [HardSpot]
    let route: PlannedRoute
    var onStart: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    private let briefings = BundledData.briefings()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BaxiSpace.xl) {
                    header
                    ForEach(Array(spots.enumerated()), id: \.element.id) { i, spot in
                        SpotCard(index: i + 1, spot: spot, route: route,
                                 briefing: spot.featureKind.flatMap { briefings[$0] })
                    }
                    if spots.isEmpty {
                        ContentUnavailableView("Nothing tricky", systemImage: "checkmark.circle",
                                               description: Text("No roundabouts, ramps or multi-lane turns on this route."))
                    }
                }
                .padding(.horizontal, BaxiSpace.page)
                .padding(.bottom, BaxiSpace.xl)
            }
            .baxiPage()
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if let onStart {
                    Button { dismiss(); onStart() } label: { Label("Start drive", systemImage: "car.fill") }
                        .buttonStyle(.baxiPrimary)
                        .padding(.horizontal, BaxiSpace.page)
                        .padding(.vertical, BaxiSpace.sm)
                        .background(.bar)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.sm) {
            Text(routeName).font(BaxiFont.title).foregroundStyle(BaxiColor.ink)
            Text(summary).font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
        }
        .padding(.top, BaxiSpace.md)
    }

    private var summary: String {
        let counts = Dictionary(grouping: spots, by: \.kind).mapValues(\.count)
        var parts: [String] = []
        if let n = counts[.roundabout] { parts.append("\(n) roundabout\(n == 1 ? "" : "s")") }
        if let n = counts[.ramp] { parts.append("\(n) merge\(n == 1 ? "" : "s") or ramp\(n == 1 ? "" : "s")") }
        if let n = counts[.laneTurn] { parts.append("\(n) lane choice\(n == 1 ? "" : "s")") }
        if let n = counts[.schoolZone] { parts.append("\(n) school zone\(n == 1 ? "" : "s")") }
        if let n = counts[.crashCorridor] { parts.append("\(n) crash-heavy stretch\(n == 1 ? "" : "es")") }
        if let n = counts[.glare] { parts.append("\(n) low-sun stretch\(n == 1 ? "" : "es") if you leave now") }
        return parts.isEmpty ? "No hard spots." : parts.joined(separator: ", ") + "."
    }
}

private struct SpotCard: View {
    let index: Int
    let spot: HardSpot
    let route: PlannedRoute
    let briefing: Briefing?
    @State private var scene: MKLookAroundScene?
    @State private var looked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imagery
                .frame(height: 210)
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    // Bottom right: Look Around keeps its own badge top left and the Maps logo bottom left.
                    HStack(spacing: BaxiSpace.sm) {
                        Text("at \(DriveView.distance(spot.alongMeters))").font(BaxiFont.caption)
                            .padding(.horizontal, BaxiSpace.sm).padding(.vertical, BaxiSpace.xs)
                            .background(.regularMaterial, in: Capsule())
                        SpotPin(number: index, kind: spot.kind)
                    }
                    .padding(BaxiSpace.md)
                    .allowsHitTesting(false)
                }
            VStack(alignment: .leading, spacing: BaxiSpace.md) {
                Text(spot.title).font(BaxiFont.section).foregroundStyle(BaxiColor.ink)
                said
                if let b = briefing { manual(b) }
            }
            .padding(BaxiSpace.lg)
        }
        .background(BaxiColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BaxiRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BaxiRadius.lg, style: .continuous).strokeBorder(BaxiColor.hairline, lineWidth: 1))
        .task(id: spot.id) { await loadScene() }
    }

    private var said: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.xs) {
            if spot.spoken.isEmpty {
                Label("Baxi stays quiet here", systemImage: "speaker.slash").font(BaxiFont.eyebrow).foregroundStyle(BaxiColor.accent)
                Text("This is only for your preview. Federal crash records (NHTSA FARS) list a fatal crash at this spot.")
                    .font(BaxiFont.body).foregroundStyle(BaxiColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Baxi will say", systemImage: "waveform").font(BaxiFont.eyebrow).foregroundStyle(BaxiColor.accent)
                Text("“\(spot.spoken)”").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BaxiSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BaxiColor.sunken, in: RoundedRectangle(cornerRadius: BaxiRadius.md, style: .continuous))
    }

    private func manual(_ b: Briefing) -> some View {
        VStack(alignment: .leading, spacing: BaxiSpace.sm) {
            Label("From the Indiana Driver's Manual", systemImage: "book.closed.fill")
                .font(BaxiFont.eyebrow).foregroundStyle(BaxiColor.inkFaint)
            Text(b.title).font(BaxiFont.headline).foregroundStyle(BaxiColor.ink)
            Text(b.howTo).font(BaxiFont.callout).foregroundStyle(BaxiColor.ink)
            if !b.quote.isEmpty {
                Text("“\(b.quote)”").font(BaxiFont.callout.italic()).foregroundStyle(BaxiColor.inkSoft)
                    .padding(.leading, BaxiSpace.md)
                    .overlay(alignment: .leading) { Rectangle().fill(BaxiColor.accent).frame(width: 3) }
            }
            if let c = b.citation { Text(c).font(BaxiFont.caption).foregroundStyle(BaxiColor.inkFaint) }
        }
    }

    @ViewBuilder private var imagery: some View {
        if let scene {
            LookAroundPreview(initialScene: scene, allowsNavigation: true, showsRoadLabels: true)
        } else if !looked {
            Rectangle().fill(BaxiColor.sunken).shimmer()
        } else {
            // No street imagery here: a small map of the spot, aimed the way the car arrives.
            Map(initialPosition: .camera(MapCamera(centerCoordinate: spot.location.clLocation, distance: 450, heading: approachHeading, pitch: 45)),
                interactionModes: []) {
                MapPolyline(coordinates: route.polyline.points.map(\.clLocation)).stroke(BaxiColor.route, lineWidth: 6)
                Annotation("", coordinate: spot.location.clLocation) { SpotPin(number: index, kind: spot.kind) }
            }
            .overlay(alignment: .bottomLeading) {
                Text("No street imagery here").font(BaxiFont.caption).padding(.horizontal, BaxiSpace.sm).padding(.vertical, BaxiSpace.xs)
                    .background(.regularMaterial, in: Capsule()).padding(BaxiSpace.md)
            }
        }
    }

    /// The partner's ApproachHeading once it is written; until then the route's own bearing.
    private var approachHeading: Double {
        if ApproachHeading.isImplemented, let b = ApproachHeading.bearing(route: route.polyline.points, spot: spot.location) { return b }
        return route.polyline.bearing(atMeters: max(0, spot.alongMeters - 40)) ?? 0
    }

    /// Look Around from just before the spot, so the image shows the approach.
    private func loadScene() async {
        let point = route.polyline.coordinate(atMeters: max(0, spot.alongMeters - 40)) ?? spot.location
        let found = try? await MKLookAroundSceneRequest(coordinate: point.clLocation).scene
        withAnimation(.easeOut(duration: 0.25)) { scene = found; looked = true }
    }
}
