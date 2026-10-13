import SwiftUI
import MapKit

/// Day 1 version: shows the features near home on an Apple Map, colored by tier.
/// Route generation lands on Oct 15 per the plan.
struct PlanView: View {
    @Environment(AppStore.self) private var store
    @State private var position: MapCameraPosition = .automatic
    @State private var showAll = false

    private var shown: [RoadFeature] {
        let base = store.nearbyFeatures
        return showAll ? base : base.filter { $0.tier == store.tier }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.home == nil {
                    ContentUnavailableView("No practice area yet", systemImage: "map",
                                           description: Text("Go to Home and tap Try the Carmel demo."))
                } else {
                    Map(position: $position) {
                        if let home = store.home {
                            Annotation("Home", coordinate: home.clLocation) {
                                Image(systemName: "house.circle.fill").font(.title).foregroundStyle(.blue)
                            }
                        }
                        ForEach(shown) { f in
                            Annotation(f.name ?? f.kind.label, coordinate: f.coordinate.clLocation) {
                                Image(systemName: f.kind.symbolName)
                                    .font(.caption).padding(5)
                                    .background(tierColor(f.tier), in: Circle())
                                    .foregroundStyle(.white)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .safeAreaInset(edge: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Show every tier", isOn: $showAll)
                            Text(summary).font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(.thinMaterial)
                    }
                }
            }
            .navigationTitle("Plan")
        }
        .onChange(of: store.home) { _, home in
            if let home {
                position = .region(MKCoordinateRegion(center: home.clLocation,
                                                      latitudinalMeters: store.tier.searchRadiusMeters * 2.2,
                                                      longitudinalMeters: store.tier.searchRadiusMeters * 2.2))
            }
        }
    }

    private var summary: String {
        let kinds = FeatureKind.allCases.filter { showAll || $0.tier == store.tier }
        let parts = kinds.map { "\(store.count(of: $0)) \($0.label.lowercased())" }.filter { !$0.hasPrefix("0 ") }
        return parts.isEmpty ? "Nothing of this tier within \(Int(store.tier.searchRadiusMeters / 1000)) km." : parts.joined(separator: ", ")
    }

    func tierColor(_ t: Tier) -> Color {
        switch t {
        case .neighborhood: .green
        case .signalsAndSingleLane: .teal
        case .multiLaneRoundabouts: .orange
        case .parkways: .purple
        case .highway: .red
        }
    }
}
