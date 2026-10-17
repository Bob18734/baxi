import SwiftUI
import MapKit

/// Pick a preset Carmel practice route or search a destination, see the route with its hard spots
/// numbered the way the Preview shows them, then start the drive (live, or a replay for the demo).
struct RouteView: View {
    @Environment(AppStore.self) private var store
    @State private var camera: MapCameraPosition = .automatic
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var results: [MKMapItem] = []
    @State private var routing = false
    @State private var showPreview = false
    @State private var startAfterPreview = false

    var body: some View {
        NavigationStack {
            routeMap
                .safeAreaInset(edge: .bottom, spacing: 0) { panel }
                .navigationTitle("Routes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .searchable(text: $query, prompt: "Search a destination")
                .searchFocused($searchFocused)
                .onSubmit(of: .search) { Task { await search() } }
                .searchSuggestions { suggestions }
        }
        .onAppear {
            store.loadCarmelDemo(); store.refreshPrep()
            if let r = store.route { camera = Self.overview(r) }
            else { camera = .region(MKCoordinateRegion(center: AppStore.carmelDemoHome.clLocation, latitudinalMeters: 9_000, longitudinalMeters: 9_000)) }
        }
        .onChange(of: store.wantsSearch, initial: true) { _, want in
            if want { searchFocused = true; store.wantsSearch = false }
        }
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
                // Where to change lanes, as on the Drive screen.
                ForEach(store.laneZones, id: \.zone.id) { z in
                    MapPolyline(coordinates: z.line)
                        .stroke(BaxiColor.signInk, style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: z.line)
                        .stroke(BaxiColor.warning, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
                // Small dots here; the Preview numbers and explains each one.
                ForEach(spots) { spot in
                    Annotation(spot.title, coordinate: spot.location.clLocation) {
                        Circle().fill(SpotPin.color(spot.kind)).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
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
        if let calmerId = store.calmerOptionId, let fastest = store.routeOptions.first,
           let calmer = store.routeOptions.first(where: { $0.id == calmerId }) {
            HStack(spacing: BaxiSpace.sm) {
                RouteChoice(title: "Fastest", option: fastest, selected: r.id == fastest.id) { switchTo(fastest.id) }
                RouteChoice(title: "Calmer", option: calmer, selected: r.id == calmer.id) { switchTo(calmer.id) }
            }
        }
        RouteFacts(route: r, spots: spots)
        if let w = store.weather { WeatherLine(weather: w) }
        if let note = store.roadDataNote {
            Label(note, systemImage: "wifi.exclamationmark").font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
        }
        HStack(spacing: BaxiSpace.sm) {
            Button { showPreview = true } label: {
                Label("Preview", systemImage: "binoculars.fill")
            }
            .buttonStyle(.baxiSecondary)
            .disabled(store.isPreparing)
            Menu {
                Section("Replay the route, not logged") {
                    ForEach([1.0, 4, 8, 16], id: \.self) { x in
                        Button("At \(Int(x))x speed") { store.activeSession = store.makeSession(replay: x) }
                    }
                }
            } label: {
                Label("Replay", systemImage: "play.fill")
            }
            .buttonStyle(.baxiSecondary)
            .disabled(store.isPreparing)
        }
        Button { store.activeSession = store.makeSession(replay: nil) } label: {
            Label("Start drive", systemImage: "car.fill")
        }
        .buttonStyle(.baxiPrimary)
        .disabled(store.isPreparing)
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

    private func switchTo(_ id: String) {
        Task { routing = true; await store.chooseOption(id); routing = false }
    }

    /// Built in the background with the route's cues; empty for a moment after a route is picked.
    private var spots: [HardSpot] { store.hardSpots() }

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
            let parts = [DriveView.distance(route.distanceMeters), "\(mins) min",
                         rb > 0 ? "\(rb) roundabout\(rb == 1 ? "" : "s")" : nil,
                         ramps > 0 ? "\(ramps) ramp\(ramps == 1 ? "" : "s")" : nil].compactMap { $0 }
            Text(parts.joined(separator: ", ")).font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
            Text(route.source == "apple" ? "No lane details on this route." : "Yellow on the map is where to change lanes.")
                .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
        }
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
        case .crashCorridor, .studyIntersection, .fatalCrash: BaxiColor.caution
        case .glare: BaxiColor.warning
        }
    }
}

extension DriveSession: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(self) }
}

/// The weather where the drive starts, in one line; an alert in effect is shown first, in orange.
private struct WeatherLine: View {
    let weather: RoadWeather
    private var symbol: String {
        switch weather.condition {
        case .clear: "cloud.sun.fill"
        case .wind: "wind"
        case .rain: "cloud.rain.fill"
        case .fog: "cloud.fog.fill"
        case .storm: "cloud.bolt.rain.fill"
        case .snowOrIce: "snowflake"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
            if let alert = weather.alerts.first {
                Label(alert, systemImage: "exclamationmark.triangle.fill").font(BaxiFont.footnote.weight(.semibold))
                    .foregroundStyle(BaxiColor.caution)
            }
            Label(weather.summary, systemImage: symbol).font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One of the two route choices: its time and how much of it is on roads posted 45 mph or more.
private struct RouteChoice: View {
    let title: String
    let option: RouteService.Option
    let selected: Bool
    var choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                Text(title).font(BaxiFont.bodyBold)
                Text("\(Int((option.route.durationSeconds / 60).rounded())) min").font(BaxiFont.footnote.weight(.semibold))
                if let fast = option.fastMeters {
                    Text(String(format: "%.1f mi at 45+ mph", fast / 1609.34)).font(BaxiFont.caption)
                }
            }
            .foregroundStyle(selected ? BaxiColor.onSign : BaxiColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BaxiSpace.md)
            .background(selected ? BaxiColor.sign : BaxiColor.sunken, in: RoundedRectangle(cornerRadius: BaxiRadius.md, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

