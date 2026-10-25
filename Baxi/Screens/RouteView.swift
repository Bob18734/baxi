import SwiftUI
import MapKit

/// Pick a preset Carmel practice route or search a destination, see the route on the map, then start the drive
/// (live, or a replay for the demo). Laid out like Apple Maps: the map fills the screen and one panel along the
/// bottom holds the search field and either the practice routes, the search results, or the chosen route.
struct RouteView: View {
    @Environment(AppStore.self) private var store
    @State private var camera: MapCameraPosition = .automatic
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var results: [MKMapItem] = []
    @State private var routing = false
    /// Why the search shows no places: nothing matched, or no connection. nil while results show.
    @State private var searchNote: String?
    @State private var showPreview = false
    @State private var startAfterPreview = false

    /// The panel shows search results while the field is in use.
    private var searching: Bool { searchFocused || !query.isEmpty }

    var body: some View {
        routeMap
            .safeAreaInset(edge: .bottom, spacing: 0) { panel }
            // Places appear while typing, once the typing pauses.
            .task(id: query) {
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                await search()
            }
            .onAppear {
                store.loadCarmelDemo(); store.refreshPrep()
                Task { await store.refreshOrigin() }
                if let r = store.route { camera = Self.overview(r) } else { camera = .region(homeRegion) }
            }
            // Once the phone's location arrives, show it (until a route is picked).
            .onChange(of: store.originIsHere) { _, here in
                guard here, store.route == nil else { return }
                withAnimation(.smooth) { camera = .region(homeRegion) }
            }
            .onChange(of: store.wantsSearch, initial: true) { _, want in
                if want { searchFocused = true; store.wantsSearch = false }
            }
            .animation(.snappy, value: searching)
            .animation(.snappy, value: store.route?.id)
            .sheet(isPresented: $showPreview, onDismiss: {
                // Start only after the sheet is gone; presenting the drive mid-dismiss can be dropped.
                if startAfterPreview { startAfterPreview = false; store.activeSession = store.makeSession(replay: nil) }
            }) {
                if let r = store.route {
                    PreviewView(routeName: r.name, spots: spots, route: r) { startAfterPreview = true }
                }
            }
    }

    /// Where the map rests with no route: around the phone when its location is known, else Carmel.
    private var homeRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: (store.originIsHere ? store.origin : AppStore.carmelDemoHome).clLocation,
                           latitudinalMeters: 7_000, longitudinalMeters: 7_000)
    }

    // MARK: Map

    private var routeMap: some View {
        Map(position: $camera) {
            UserAnnotation()
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
            } else if !store.originIsHere {
                Annotation("Carmel", coordinate: AppStore.carmelDemoHome.clLocation) {
                    Image(systemName: "mappin.circle.fill").font(BaxiFont.title).foregroundStyle(BaxiColor.accent)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onChange(of: store.route) { _, r in
            guard let r else { withAnimation(.smooth) { camera = .region(homeRegion) }; return }
            // .automatic again is no change to SwiftUI, so step through the route's region first.
            withAnimation(.smooth) { camera = .region(Self.region(r)) }
            Task { await Task.yield(); withAnimation(.smooth) { camera = Self.overview(r) } }
        }
    }

    // MARK: Panel

    /// One sheet along the bottom, reaching the bottom edge of the screen (the tab bar sits on it).
    private var panel: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            Capsule().fill(BaxiColor.hairline).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            if !(store.route != nil && !searching) { searchField }
            if searching {
                searchResults
            } else if routing {
                VStack(alignment: .leading, spacing: BaxiSpace.sm) {
                    RoundedRectangle(cornerRadius: BaxiRadius.md).fill(BaxiColor.sunken).frame(height: 64).shimmer()
                    Text(store.routeStep ?? "Finding a route…")
                        .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                        .contentTransition(.opacity).animation(.snappy, value: store.routeStep)
                }
            } else if let err = store.routeError {
                Label(err, systemImage: "exclamationmark.triangle.fill").font(BaxiFont.footnote).foregroundStyle(BaxiColor.stopText)
                Button("Back to practice routes") { store.clearRoute() }.font(BaxiFont.bodyBold).tint(BaxiColor.accent)
            } else if let r = store.route {
                routeHeader(r)
                selected(r)
            } else {
                practiceRoutes
            }
        }
        .padding(.horizontal, BaxiSpace.page)
        .padding(.top, BaxiSpace.sm)
        .padding(.bottom, BaxiSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: BaxiRadius.xl, topTrailingRadius: BaxiRadius.xl, style: .continuous)
                .fill(BaxiColor.surface)
                .shadow(color: .black.opacity(0.15), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The search field, at the top of the panel as in Apple Maps.
    private var searchField: some View {
        HStack(spacing: BaxiSpace.sm) {
            HStack(spacing: BaxiSpace.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(BaxiColor.inkSoft)
                TextField("Search a destination", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = ""; results = []; searchNote = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(BaxiColor.inkFaint)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .font(BaxiFont.body)
            .padding(.horizontal, BaxiSpace.md)
            .frame(minHeight: 44)
            .background(BaxiColor.sunken, in: RoundedRectangle(cornerRadius: BaxiRadius.md, style: .continuous))
            if searching {
                Button("Cancel") { query = ""; results = []; searchNote = nil; searchFocused = false }
                    .font(BaxiFont.body).tint(BaxiColor.accent)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    /// Places matching the search, in the panel.
    private var searchResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let searchNote {
                    Label(searchNote, systemImage: "magnifyingglass").font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
                        .padding(.vertical, BaxiSpace.md)
                } else if results.isEmpty {
                    Text(query.isEmpty ? "Type a place or an address." : "Searching…")
                        .font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft).padding(.vertical, BaxiSpace.md)
                }
                ForEach(results, id: \.self) { item in
                    Button { go(to: item) } label: {
                        HStack(spacing: BaxiSpace.md) {
                            Image(systemName: "mappin.circle.fill").font(BaxiFont.title).foregroundStyle(BaxiColor.route)
                            VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                                Text(item.name ?? "Place").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                                Text(item.placemark.title ?? "").font(BaxiFont.caption).foregroundStyle(BaxiColor.inkSoft).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, BaxiSpace.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    Divider()
                }
            }
        }
        .frame(maxHeight: 320)
        .scrollDismissesKeyboard(.immediately)
    }

    private func go(to item: MKMapItem) {
        guard !routing else { return }
        searchFocused = false
        let name = item.name ?? "Destination"
        Task {
            routing = true
            query = ""; results = []; searchNote = nil
            await store.routeTo(Coordinate(item.placemark.coordinate), name: name)
            routing = false
        }
    }

    /// The practice routes as tiles, two by two, so all four are in view.
    private var practiceRoutes: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.sm) {
            Eyebrow("Practice routes in Carmel")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: BaxiSpace.sm), GridItem(.flexible(), spacing: BaxiSpace.sm)],
                      spacing: BaxiSpace.sm) {
                ForEach(RouteService.presets) { p in
                    PresetTile(preset: p, miles: store.presetMeters[p.id].map { $0 / 1609.34 }) {
                        store.choosePreset(p.id)
                    }
                }
            }
        }
    }

    /// The chosen route's name, with a button back to the list.
    private func routeHeader(_ r: PlannedRoute) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(r.name).font(BaxiFont.title).foregroundStyle(BaxiColor.ink).lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            Button { store.clearRoute() } label: {
                Image(systemName: "xmark").font(BaxiFont.headline).foregroundStyle(BaxiColor.inkSoft)
                    .frame(width: 32, height: 32).background(BaxiColor.sunken, in: Circle())
            }
            .accessibilityLabel("Close this route")
        }
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
        if store.isPreparing {
            HStack(spacing: BaxiSpace.sm) {
                ProgressView().controlSize(.small)
                Text("Getting the route ready…").font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
            }
            .transition(.opacity)
        }
        Label("Mount the phone first. The driver never touches it.", systemImage: "hand.raised.fill")
            .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
    }

    private func switchTo(_ id: String) {
        Task { routing = true; await store.chooseOption(id); routing = false }
    }

    /// Built in the background with the route's cues; empty for a moment after a route is picked.
    private var spots: [HardSpot] { store.hardSpots() }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; searchNote = nil; return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        req.region = MKCoordinateRegion(center: store.origin.clLocation, latitudinalMeters: 25_000, longitudinalMeters: 25_000)
        do {
            let items = try await MKLocalSearch(request: req).start().mapItems
            guard q == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }   // typing moved on
            results = items
            searchNote = items.isEmpty ? "No places found for \u{201C}\(q)\u{201D}" : nil
        } catch {
            guard q == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = []
            // MapKit reports "nothing matched" as an error too.
            searchNote = (error as? MKError)?.code == .placemarkNotFound
                ? "No places found for \u{201C}\(q)\u{201D}"
                : "No connection. Check the internet and try again."
        }
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

/// A practice route as a small green guide sign: its name, miles and what it practices.
private struct PresetTile: View {
    let preset: RouteService.Preset
    let miles: Double?
    var choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                Text(preset.name).font(BaxiFont.signFace(17)).lineLimit(1).minimumScaleFactor(0.8)
                Text([miles.map { String(format: "%.0f mi", max(1, $0)) }, preset.short].compactMap { $0 }.joined(separator: " · "))
                    .font(BaxiFont.caption).opacity(0.9).lineLimit(2, reservesSpace: true)
            }
            .foregroundStyle(BaxiColor.onSign)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(BaxiSpace.md)
            .signPanel(radius: BaxiRadius.md)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(preset.name). \(preset.summary)")
        .accessibilityHint("Shows the route on the map")
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

