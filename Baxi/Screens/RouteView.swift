import SwiftUI
import MapKit

/// Pick a preset Carmel practice route or search a destination, see the route with its hard spots
/// numbered the way the Preview shows them, then start the drive (live, or a replay for the demo).
struct RouteView: View {
    @Environment(AppStore.self) private var store
    @State private var camera: MapCameraPosition = .automatic
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var routing = false
    @State private var spots: [HardSpot] = []
    @State private var showPreview = false
    @State private var startAfterPreview = false

    var body: some View {
        NavigationStack {
            routeMap
                .safeAreaInset(edge: .bottom, spacing: 0) { panel }
                .navigationTitle("Routes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .searchable(text: $query, prompt: "Search a destination near Carmel")
                .onSubmit(of: .search) { Task { await search() } }
                .searchSuggestions { suggestions }
        }
        .onAppear {
            store.loadCarmelDemo(); refreshSpots()
            if let r = store.route { camera = Self.overview(r) }
            else { camera = .region(MKCoordinateRegion(center: AppStore.carmelDemoHome.clLocation, latitudinalMeters: 9_000, longitudinalMeters: 9_000)) }
        }
        .onChange(of: store.route) { _, _ in refreshSpots() }
        .sheet(isPresented: $showPreview, onDismiss: {
            // Start only after the sheet is gone; presenting the drive mid-dismiss can be dropped.
            if startAfterPreview { startAfterPreview = false; store.activeSession = store.makeSession(replay: nil) }
        }) {
            if let r = store.route {
                PreviewView(routeName: r.name, spots: spots, route: r) { startAfterPreview = true }
            }
        }
    }

    // MARK: Map

    private var routeMap: some View {
        Map(position: $camera) {
            if let r = store.route {
                MapPolyline(coordinates: r.polyline.points.map(\.clLocation))
                    .stroke(BaxiColor.route, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                ForEach(Array(spots.enumerated()), id: \.element.id) { i, spot in
                    Annotation(spot.title, coordinate: spot.location.clLocation) {
                        SpotPin(number: i + 1, kind: spot.kind)
                    }
                    .annotationTitles(.hidden)
                }
                if let start = r.polyline.points.first {
                    Annotation("Start", coordinate: start.clLocation) {
                        Image(systemName: "flag.fill").font(BaxiFont.footnote.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(BaxiColor.signInk, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            } else if let home = store.home {
                Annotation("Carmel", coordinate: home.clLocation) {
                    Image(systemName: "mappin.circle.fill").font(BaxiFont.title).foregroundStyle(BaxiColor.accent)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .onChange(of: store.route) { _, r in
            // .automatic again is no change to SwiftUI, so step through the route's region first.
            guard let r else { return }
            withAnimation(.smooth) { camera = .region(Self.region(r)) }
            Task { await Task.yield(); withAnimation(.smooth) { camera = Self.overview(r) } }
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            if store.route == nil { Eyebrow("Practice routes in Carmel") }
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BaxiSpace.md) {
                        ForEach(RouteService.presets) { p in
                            PresetCard(preset: p, selected: store.route?.id == p.id) {
                                withAnimation(.snappy) { store.choosePreset(p.id) }
                            }
                            .id(p.id)
                        }
                    }
                    .padding(.horizontal, BaxiSpace.page)
                }
                .padding(.horizontal, -BaxiSpace.page)
                .fixedSize(horizontal: false, vertical: true) // otherwise the row grows to fill the screen
                .onAppear { if let id = store.route?.id { reader.scrollTo(id, anchor: .center) } }
                .onChange(of: store.route?.id) { _, id in if let id { withAnimation { reader.scrollTo(id, anchor: .center) } } }
            }
            if routing {
                RoundedRectangle(cornerRadius: BaxiRadius.md).fill(BaxiColor.sunken).frame(height: 64).shimmer()
            } else if let err = store.routeError {
                Label(err, systemImage: "exclamationmark.triangle.fill").font(BaxiFont.footnote).foregroundStyle(BaxiColor.stopText)
            } else if let r = store.route {
                selected(r)
            } else {
                Text("Pick a practice route, or search a destination above.")
                    .font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
            }
        }
        .padding(.horizontal, BaxiSpace.page)
        .padding(.top, BaxiSpace.lg)
        .padding(.bottom, BaxiSpace.md)
        .background(BaxiColor.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: BaxiRadius.xl, topTrailingRadius: BaxiRadius.xl, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
    }

    @ViewBuilder private func selected(_ r: PlannedRoute) -> some View {
        RouteFacts(route: r, spots: spots)
        HStack(spacing: BaxiSpace.sm) {
            Button { showPreview = true } label: {
                Label(spots.isEmpty ? "Preview" : "Preview \(spots.count) spots", systemImage: "binoculars.fill")
            }
            .buttonStyle(.baxiSecondary)
            Menu {
                Section("Replay the route (not logged)") {
                    ForEach([1.0, 4, 8, 16], id: \.self) { s in
                        Button("At \(Int(s))× speed") { store.activeSession = store.makeSession(replay: s) }
                    }
                }
            } label: {
                Image(systemName: "play.circle.fill").font(BaxiFont.section)
                    .frame(width: 54, height: 54)
                    .foregroundStyle(BaxiColor.ink)
                    .background(BaxiColor.sunken, in: RoundedRectangle(cornerRadius: BaxiRadius.md, style: .continuous))
            }
            .accessibilityLabel("Replay")
        }
        Button { store.activeSession = store.makeSession(replay: nil) } label: {
            Label("Start drive", systemImage: "car.fill")
        }
        .buttonStyle(.baxiPrimary)
        Label("Mount the phone first. The driver never touches it.", systemImage: "hand.raised.fill")
            .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
    }

    @ViewBuilder private var suggestions: some View {
        ForEach(results, id: \.self) { item in
            Button {
                Task {
                    routing = true
                    await store.routeTo(Coordinate(item.placemark.coordinate), name: item.name ?? "Destination")
                    routing = false
                    query = ""; results = []
                }
            } label: {
                VStack(alignment: .leading) {
                    Text(item.name ?? "Place").foregroundStyle(BaxiColor.ink)
                    Text(item.placemark.title ?? "").font(BaxiFont.caption).foregroundStyle(BaxiColor.inkSoft)
                }
            }
        }
    }

    private func refreshSpots() { spots = store.hardSpots() }

    private func search() async {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.region = MKCoordinateRegion(center: (store.home ?? AppStore.carmelDemoHome).clLocation,
                                        latitudinalMeters: 25_000, longitudinalMeters: 25_000)
        results = (try? await MKLocalSearch(request: req).start().mapItems) ?? []
    }

    /// Fits the route line and its pins in the part of the map the panel leaves visible.
    static func overview(_ r: PlannedRoute) -> MapCameraPosition { .automatic }

    static func region(_ r: PlannedRoute) -> MKCoordinateRegion {
        let rect = r.polyline.points.reduce(MKMapRect.null) {
            $0.union(MKMapRect(origin: MKMapPoint($1.clLocation), size: MKMapSize(width: 1, height: 1)))
        }
        return MKCoordinateRegion(rect)
    }
}

/// A preset route as a small guide sign when chosen, a plain card otherwise.
private struct PresetCard: View {
    let preset: RouteService.Preset
    let selected: Bool
    var choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: BaxiSpace.xs) {
                Text(preset.name).font(BaxiFont.headline)
                // Two lines reserved so every card is the same height.
                Text(preset.summary).font(BaxiFont.caption).lineLimit(2, reservesSpace: true).opacity(selected ? 0.9 : 1)
                    .foregroundStyle(selected ? BaxiColor.onSign : BaxiColor.inkSoft)
            }
            .frame(width: 220, alignment: .topLeading)
            .padding(.vertical, BaxiSpace.md)
            .padding(.horizontal, BaxiSpace.lg)
            .modifier(PresetBackground(selected: selected))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PresetBackground: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        if selected { content.signPanel(radius: BaxiRadius.md) }
        else {
            content.foregroundStyle(BaxiColor.ink)
                .background(BaxiColor.sunken, in: RoundedRectangle(cornerRadius: BaxiRadius.md, style: .continuous))
        }
    }
}

/// Distance, time and what is on the route, as small facts.
private struct RouteFacts: View {
    let route: PlannedRoute
    let spots: [HardSpot]

    var body: some View {
        let rb = spots.filter { $0.kind == .roundabout }.count
        let ramps = spots.filter { $0.kind == .ramp }.count
        let mins = Int((route.durationSeconds / 60).rounded())
        VStack(alignment: .leading, spacing: BaxiSpace.xs) {
            let facts = Group {
                fact("ruler", DriveView.distance(route.distanceMeters))
                fact("clock", "\(mins) min")
                if rb > 0 { fact("arrow.triangle.turn.up.right.circle", "\(rb) roundabout\(rb == 1 ? "" : "s")") }
                if ramps > 0 { fact("arrow.merge", "\(ramps) ramp\(ramps == 1 ? "" : "s")") }
            }
            // One row when it fits, otherwise stacked (large text sizes).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BaxiSpace.md) { facts }
                VStack(alignment: .leading, spacing: BaxiSpace.xs) { facts }
            }
            Text(route.source == "apple" ? "Apple directions: no lane data on this route." : "Lanes and roundabout exits from OpenStreetMap.")
                .font(BaxiFont.caption).foregroundStyle(BaxiColor.inkFaint)
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: BaxiSpace.xs) {
            Image(systemName: symbol).foregroundStyle(BaxiColor.accent)
            Text(text).foregroundStyle(BaxiColor.ink)
        }
        .font(BaxiFont.footnote.weight(.semibold))
        .lineLimit(1)
    }
}

/// A numbered hard spot on the map, colored like the sign it stands for.
struct SpotPin: View {
    let number: Int
    let kind: HardSpot.Kind
    var body: some View {
        Text("\(number)").font(BaxiFont.signFace(13))
            .foregroundStyle(kind == .roundabout || kind == .ramp || kind == .laneTurn ? BaxiColor.onSign : BaxiColor.signInk)
            .frame(width: 26, height: 26)
            .background(SpotPin.color(kind), in: RoundedRectangle(cornerRadius: BaxiRadius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BaxiRadius.sm, style: .continuous).stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }

    static func color(_ kind: HardSpot.Kind) -> Color {
        switch kind {
        case .roundabout, .ramp, .laneTurn: BaxiColor.sign
        case .schoolZone: BaxiColor.school
        case .crashCorridor: BaxiColor.caution
        }
    }
}

extension DriveSession: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(self) }
}
