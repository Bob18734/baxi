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
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(summary).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                    ForEach(Array(spots.enumerated()), id: \.element.id) { i, spot in
                        SpotCard(index: i + 1, spot: spot, route: route,
                                 briefing: spot.featureKind.flatMap { briefings[$0] })
                    }
                    if spots.isEmpty {
                        ContentUnavailableView("Nothing tricky", systemImage: "checkmark.circle",
                                               description: Text("No roundabouts, ramps or multi-lane turns on this route."))
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if let onStart {
                    ToolbarItem(placement: .confirmationAction) { Button("Start drive") { dismiss(); onStart() } }
                }
            }
        }
    }

    private var summary: String {
        let counts = Dictionary(grouping: spots, by: \.kind).mapValues(\.count)
        var parts: [String] = []
        if let n = counts[.roundabout] { parts.append("\(n) roundabout\(n == 1 ? "" : "s")") }
        if let n = counts[.ramp] { parts.append("\(n) merge\(n == 1 ? "" : "s") or ramp\(n == 1 ? "" : "s")") }
        if let n = counts[.laneTurn] { parts.append("\(n) lane choice\(n == 1 ? "" : "s")") }
        if let n = counts[.schoolZone] { parts.append("\(n) school zone\(n == 1 ? "" : "s")") }
        if let n = counts[.crashCorridor] { parts.append("\(n) crash-heavy stretch\(n == 1 ? "" : "es")") }
        return "\(routeName): " + (parts.isEmpty ? "no hard spots." : parts.joined(separator: ", ") + ".")
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
        VStack(alignment: .leading, spacing: 10) {
            imagery
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            HStack(alignment: .firstTextBaseline) {
                Text("\(index)").font(.headline.monospacedDigit())
                    .frame(width: 26, height: 26).background(.tint, in: Circle()).foregroundStyle(.white)
                Text(spot.title).font(.headline)
                Spacer()
                Text(DriveView.distance(spot.alongMeters)).font(.caption).foregroundStyle(.secondary)
            }
            Label("“\(spot.spoken)”", systemImage: "speaker.wave.2.fill")
                .font(.callout)
            if let b = briefing {
                VStack(alignment: .leading, spacing: 4) {
                    Text(b.title).font(.subheadline.bold())
                    Text(b.howTo).font(.callout)
                    if !b.quote.isEmpty { Text("“\(b.quote)”").font(.callout.italic()).foregroundStyle(.secondary) }
                    if let c = b.citation { Text(c).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal)
        .task(id: spot.id) { await loadScene() }
    }

    @ViewBuilder private var imagery: some View {
        if let scene {
            LookAroundPreview(initialScene: scene, allowsNavigation: true, showsRoadLabels: true)
        } else {
            // No street imagery (or still loading): a small map of the spot instead.
            Map(initialPosition: .camera(MapCamera(centerCoordinate: spot.location.clLocation, distance: 450, heading: approachHeading, pitch: 45)),
                interactionModes: []) {
                MapPolyline(coordinates: route.polyline.points.map(\.clLocation)).stroke(.blue, lineWidth: 6)
                Marker("", coordinate: spot.location.clLocation)
            }
            .overlay(alignment: .bottomLeading) {
                if looked {
                    Text("No Look Around imagery here").font(.caption2).padding(6)
                        .background(.regularMaterial, in: Capsule()).padding(8)
                }
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
        scene = try? await MKLookAroundSceneRequest(coordinate: point.clLocation).scene
        looked = true
    }
}
