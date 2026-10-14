import SwiftUI
import MapKit

/// Pick a preset Carmel practice route or search a destination, see the route with its hard spots,
/// then start the drive (live, or a replay for the demo and for testing).
struct RouteView: View {
    @Environment(AppStore.self) private var store
    @State private var camera: MapCameraPosition = .automatic
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var replaySpeed: Double = 4
    @State private var showPreview = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                routeMap.frame(maxHeight: .infinity)
                controls
            }
            .navigationTitle(store.route?.name ?? "Route")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search a destination in Carmel")
            .onSubmit(of: .search) { Task { await search() } }
            .searchSuggestions {
                ForEach(results, id: \.self) { item in
                    Button {
                        Task {
                            await store.routeTo(Coordinate(item.placemark.coordinate), name: item.name ?? "Destination")
                            query = ""; results = []
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Place")
                            Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear { store.loadCarmelDemo() }
        .sheet(isPresented: $showPreview) {
            if let r = store.route {
                PreviewView(routeName: r.name, spots: store.hardSpots(), route: r) {
                    store.activeSession = store.makeSession(replay: nil)
                }
            }
        }
    }

    private var routeMap: some View {
        Map(position: $camera) {
            if let r = store.route {
                MapPolyline(coordinates: r.polyline.points.map(\.clLocation))
                    .stroke(.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                ForEach(hardSpots(r)) { m in
                    Annotation("", coordinate: m.location.clLocation) {
                        Image(systemName: DriveView.symbol(for: m)).font(.caption.bold()).foregroundStyle(.white)
                            .padding(5).background(m.kind == .roundabout ? .orange : .purple, in: Circle())
                    }
                }
            }
            if let home = store.home {
                Annotation("Start", coordinate: home.clLocation) {
                    Image(systemName: "house.circle.fill").font(.title).foregroundStyle(.green)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onChange(of: store.route) { _, r in
            if let r { camera = .rect(Self.rect(for: r.polyline.points)) }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(RouteService.presets) { p in
                        Button { store.choosePreset(p.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.subheadline.bold())
                                Text(p.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(width: 190, alignment: .leading)
                            .padding(10)
                            .background(store.route?.id == p.id ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let err = store.routeError { Text(err).font(.footnote).foregroundStyle(.red) }
            if let r = store.route {
                Text(summary(r)).font(.footnote).foregroundStyle(.secondary)
                Button { showPreview = true } label: {
                    Label("Preview the hard spots", systemImage: "binoculars.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                HStack {
                    Button { store.activeSession = store.makeSession(replay: nil) } label: {
                        Label("Start drive", systemImage: "car.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    Menu {
                        ForEach([1.0, 4, 8, 16], id: \.self) { s in
                            Button("Replay at \(Int(s))x") { replaySpeed = s; store.activeSession = store.makeSession(replay: s) }
                        }
                    } label: {
                        Label("Replay", systemImage: "play.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                Text("Mount the phone before you start. The driver never touches it.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Pick a practice route above or search a destination.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.bar)
    }

    private func hardSpots(_ r: PlannedRoute) -> [Maneuver] {
        r.maneuvers.filter { $0.kind == .roundabout || $0.kind == .merge || $0.kind == .onRamp || $0.kind == .offRamp || ($0.laneCount ?? 0) > 1 }
    }

    private func summary(_ r: PlannedRoute) -> String {
        let rb = r.maneuvers.filter { $0.kind == .roundabout }.count
        let merges = r.maneuvers.filter { $0.kind == .merge || $0.kind == .onRamp }.count
        let mins = Int((r.durationSeconds / 60).rounded())
        var parts = ["\(DriveView.distance(r.distanceMeters)), about \(mins) min"]
        if rb > 0 { parts.append("\(rb) roundabouts") }
        if merges > 0 { parts.append("\(merges) merges") }
        parts.append(r.source == "apple" ? "Apple directions (no lane data)" : "OpenStreetMap routing")
        return parts.joined(separator: " · ")
    }

    private func search() async {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.region = MKCoordinateRegion(center: (store.home ?? AppStore.carmelDemoHome).clLocation,
                                        latitudinalMeters: 25_000, longitudinalMeters: 25_000)
        results = (try? await MKLocalSearch(request: req).start().mapItems) ?? []
    }

    static func rect(for pts: [Coordinate]) -> MKMapRect {
        let rects = pts.map { MKMapRect(origin: MKMapPoint($0.clLocation), size: MKMapSize(width: 1, height: 1)) }
        let r = rects.reduce(MKMapRect.null) { $0.union($1) }
        return r.insetBy(dx: -r.width * 0.12, dy: -r.height * 0.15)
    }
}

extension DriveSession: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(self) }
}
