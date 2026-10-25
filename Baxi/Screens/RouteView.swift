import SwiftUI
import MapKit

/// Plan a drive: search a destination or pick a practice route, see it on the map, preview it, start it.
/// The map fills the screen; one panel along the bottom holds the search field and either the practice
/// routes, the places found, or the chosen route. The panel ends where the bottom bar begins.
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

    /// The panel shows places while the field is in use.
    private var searching: Bool { searchFocused || !query.isEmpty }

    var body: some View {
        routeMap
            .safeAreaInset(edge: .bottom, spacing: 0) { panel }
            // Places appear while typing, once the typing pauses.
            .task(id: query) {
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                await search()
            }
            // The tab stays alive while hidden, so its work runs each time it is opened, not when the app launches
            // (which would ask for location over the Welcome screen).
            .onChange(of: store.tab, initial: true) { _, tab in
                guard tab == .route else { searchFocused = false; return }
                store.loadCarmelDemo(); store.refreshPrep()
                Task { await store.refreshOrigin() }
                if let r = store.route { camera = Self.overview(r) } else { camera = .region(homeRegion) }
            }
            // Once the phone's location arrives, show it (until a route is picked).
            .onChange(of: store.originIsHere) { _, here in
                guard here, store.route == nil else { return }
                withAnimation(Motion.standard) { camera = .region(homeRegion) }
            }
            .onChange(of: store.wantsSearch, initial: true) { _, want in
                if want { searchFocused = true; store.wantsSearch = false }
            }
            .animation(Motion.standard, value: searching)
            .animation(Motion.standard, value: store.route?.id)
            .animation(Motion.standard, value: routing)
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
                           latitudinalMeters: MapSpan.home, longitudinalMeters: MapSpan.home)
    }

    // MARK: Map

    private var routeMap: some View {
        Map(position: $camera) {
            if MapPrivacy.showsYou { UserAnnotation() }
            if let r = store.route {
                // The planned road: ink with a white edge.
                MapPolyline(coordinates: r.polyline.points.map(\.clLocation))
                    .stroke(Palette.field, style: StrokeStyle(lineWidth: MapLine.edge, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: r.polyline.points.map(\.clLocation))
                    .stroke(Palette.ink, style: StrokeStyle(lineWidth: MapLine.route, lineCap: .round, lineJoin: .round))
                // Where to change lanes: amber, get ready.
                ForEach(store.laneZones, id: \.zone.id) { z in
                    MapPolyline(coordinates: z.line)
                        .stroke(Palette.ready, style: StrokeStyle(lineWidth: MapLine.route, lineCap: .round, lineJoin: .round))
                }
                // Hard spots as small dots; the Preview explains each one.
                ForEach(spots) { spot in
                    Annotation(spot.title, coordinate: spot.location.clLocation) {
                        Circle().fill(SpotColor.of(spot.kind)).frame(width: MapLine.dot, height: MapLine.dot)
                            .overlay(Circle().stroke(Palette.field, lineWidth: MapLine.dotEdge))
                    }
                    .annotationTitles(.hidden)
                }
                if let start = r.polyline.points.first {
                    Annotation("Start", coordinate: start.clLocation) {
                        Mark(glyph: .start, size: MarkSize.small).foregroundStyle(Palette.onDark)
                            .frame(width: MapLine.pin, height: MapLine.pin).background(Palette.ink, in: Circle())
                            .overlay(Circle().stroke(Palette.field, lineWidth: MapLine.dotEdge))
                    }
                }
            } else if !store.originIsHere {
                Annotation("Carmel", coordinate: AppStore.carmelDemoHome.clLocation) {
                    SignalMark(size: SignalSize.map)
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            if MapPrivacy.showsYou { MapUserLocationButton() }
            MapCompass()
        }
        .ignoresSafeArea(edges: .top)
        .onChange(of: store.route) { _, r in
            guard let r else { withAnimation(Motion.standard) { camera = .region(homeRegion) }; return }
            // .automatic again is no change to SwiftUI, so step through the route's region first.
            withAnimation(Motion.standard) { camera = .region(Self.region(r)) }
            Task { await Task.yield(); withAnimation(Motion.standard) { camera = Self.overview(r) } }
        }
    }

    // MARK: Panel

    /// The panel scrolls only when its content is taller than it can be (a long route card at the largest text).
    private var panel: some View {
        ViewThatFits(in: .vertical) {
            panelContent
            ScrollView { panelContent }.scrollBounceBehavior(.basedOnSize).frame(height: PanelSize.maxHeight)
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s16)
        .padding(.bottom, Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Corner.sheet, topTrailingRadius: Corner.sheet, style: .continuous)
                .fill(Palette.page)
                .shadow(color: Palette.shadow, radius: Space.s16, y: -Space.s4)
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            if !(store.route != nil && !searching && !routing) { searchField }
            if searching {
                places
            } else if routing {
                VStack(alignment: .leading, spacing: Space.s12) {
                    Placeholder(width: PanelSize.placeholderWide, height: Space.s24)
                    Placeholder(width: PanelSize.placeholderNarrow)
                    Text(store.routeStep ?? "Finding a route…").role(.meta).foregroundStyle(Palette.meta)
                        .contentTransition(.opacity)
                }
            } else if let err = store.routeError {
                VStack(alignment: .leading, spacing: Space.s12) {
                    Text(err).role(.body).foregroundStyle(Palette.stopText).fixedSize(horizontal: false, vertical: true)
                    BigButton(title: "Back to practice routes", kind: .secondary) { store.clearRoute() }
                }
            } else if let r = store.route {
                RouteCard(route: r, spots: spots, showPreview: { showPreview = true }, switchTo: switchTo)
            } else {
                practiceRoutes
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: Space.s12) {
            FieldBox {
                Mark(glyph: .search, size: MarkSize.row).foregroundStyle(Palette.meta)
                TextField("Search a destination", text: $query)
                    .role(.body)
                    .foregroundStyle(Palette.ink)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    MarkButton(glyph: .close, label: "Clear search", tint: Palette.meta) { query = ""; results = []; searchNote = nil }
                        .padding(.trailing, -Space.s12)
                }
            }
            if searching {
                Button("Cancel") { query = ""; results = []; searchNote = nil; searchFocused = false }
                    .role(.bodyStrong).foregroundStyle(Palette.ink)
                    .buttonStyle(Press()).frame(minHeight: Size.tap)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    /// Places matching the search.
    private var places: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let searchNote {
                    Text(searchNote).role(.body).foregroundStyle(Palette.read).padding(.vertical, Space.s12)
                } else if results.isEmpty {
                    if query.isEmpty {
                        Text("Type a place or an address.").role(.body).foregroundStyle(Palette.meta).padding(.vertical, Space.s12)
                    } else {
                        SignalDots().padding(.vertical, Space.s16)
                    }
                }
                ForEach(Array(results.enumerated()), id: \.offset) { i, item in
                    Button { go(to: item) } label: {
                        Row(title: item.name ?? "Place", detail: item.placemark.title, showsDivider: i < results.count - 1) {
                            RowArrow()
                        }
                    }
                    .buttonStyle(Press())
                }
            }
        }
        .frame(maxHeight: PanelSize.placesHeight)
        .scrollDismissesKeyboard(.immediately)
    }

    private var practiceRoutes: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            GroupLabel("Practice routes in Carmel")
            ForEach(RouteService.presets) { p in
                RouteGuideSign(name: p.name, facts: [p.short, store.presetMeters[p.id].map { "\(Int(max(1, ($0 / 1609.34).rounded()))) mi" }]
                                .compactMap { $0 }.joined(separator: ", ")) { store.choosePreset(p.id) }
                    .accessibilityHint("Shows the route on the map")
            }
        }
    }

    private func go(to item: MKMapItem) {
        guard !routing else { return }
        Haptic.tap()
        searchFocused = false
        let name = item.name ?? "Destination"
        Task {
            routing = true
            query = ""; results = []; searchNote = nil
            await store.routeTo(Coordinate(item.placemark.coordinate), name: name)
            routing = false
        }
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
        req.region = MKCoordinateRegion(center: store.origin.clLocation, latitudinalMeters: MapSpan.search, longitudinalMeters: MapSpan.search)
        do {
            let items = try await MKLocalSearch(request: req).start().mapItems
            guard q == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }   // typing moved on
            results = items
            searchNote = items.isEmpty ? "No places found for \u{201C}\(q)\u{201D}." : nil
        } catch {
            guard q == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = []
            // MapKit reports "nothing matched" as an error too.
            searchNote = (error as? MKError)?.code == .placemarkNotFound
                ? "No places found for \u{201C}\(q)\u{201D}."
                : "No connection. Check the internet and try again."
        }
    }

    /// Fits the route line and its dots in the part of the map the panel leaves visible.
    static func overview(_ r: PlannedRoute) -> MapCameraPosition { .automatic }

    static func region(_ r: PlannedRoute) -> MKCoordinateRegion {
        let rect = r.polyline.points.reduce(MKMapRect.null) {
            $0.union(MKMapRect(origin: MKMapPoint($1.clLocation), size: MKMapSize(width: 1, height: 1)))   // design-lint:allow a one-point map rect to union, not a drawn size
        }
        return MKCoordinateRegion(rect)
    }
}

/// The chosen route: its name, the choice of fastest or calmer, what's on it, Preview, Replay and Start.
private struct RouteCard: View {
    let route: PlannedRoute
    let spots: [HardSpot]
    let showPreview: () -> Void
    let switchTo: (String) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(route.name).role(.screenTitle).foregroundStyle(Palette.ink)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    Text(facts).role(.meta).foregroundStyle(Palette.meta)
                }
                Spacer(minLength: 0)
                MarkButton(glyph: .close, label: "Close this route") { store.clearRoute() }
                    .padding(.trailing, -Space.s12)
            }
            if let calmerId = store.calmerOptionId, let fastest = store.routeOptions.first,
               let calmer = store.routeOptions.first(where: { $0.id == calmerId }) {
                HStack(spacing: Space.s8) {
                    RouteChoice(title: "Fastest", option: fastest, selected: route.id == fastest.id) { switchTo(fastest.id) }
                    RouteChoice(title: "Calmer", option: calmer, selected: route.id == calmer.id) { switchTo(calmer.id) }
                }
            }
            notes
            BigButton(title: "Start drive", working: store.isPreparing) {
                store.activeSession = store.makeSession(replay: nil)
            }
            .accessibilityHint(store.isPreparing ? "Getting the route ready" : "Mount the phone first")
            if store.isPreparing {
                Text("Getting the route ready…").role(.meta).foregroundStyle(Palette.meta)
                    .frame(maxWidth: .infinity).transition(.opacity)
            }
            // Secondary actions as quiet links: Start drive is the one main action.
            HStack(spacing: Space.s32) {
                Button { Haptic.tap(); showPreview() } label: {
                    HStack(spacing: Space.s8) { Mark(glyph: .search, size: MarkSize.small); Text("Preview the hard spots").role(.bodyStrong) }
                        .foregroundStyle(Palette.ink).frame(minHeight: Size.tap)
                }
                .buttonStyle(Press())
                .disabled(store.isPreparing)
                Menu {
                    Section("Replay the route, not logged") {
                        ForEach([1.0, 4, 8, 16], id: \.self) { x in
                            Button("At \(Int(x))x speed") { store.activeSession = store.makeSession(replay: x) }
                        }
                    }
                } label: {
                    HStack(spacing: Space.s8) { Mark(glyph: .play, size: MarkSize.small); Text("Replay").role(.bodyStrong) }
                        .foregroundStyle(Palette.ink).frame(minHeight: Size.tap)
                }
                .buttonStyle(Press())
                .disabled(store.isPreparing)
                Spacer(minLength: 0)
            }
        }
    }

    /// Counted from the route's own maneuvers, the same way Home and the Log count skills, so numbers agree everywhere.
    private var facts: String {
        let c = Practice.count(maneuvers: route.maneuvers, features: store.features, fastMeters: 0)
        let rb = (c[.singleLaneRoundabout] ?? 0) + (c[.multiLaneRoundabout] ?? 0)
        let ramps = (c[.highwayMerge] ?? 0) + (c[.exitRamp] ?? 0)
        let mins = Int((route.durationSeconds / 60).rounded())
        return [DriveView.distance(route.distanceMeters), "\(mins) min",
                rb > 0 ? "\(rb) roundabout\(rb == 1 ? "" : "s")" : nil,
                ramps > 0 ? "\(ramps) ramp\(ramps == 1 ? "" : "s")" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    @ViewBuilder private var notes: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            // Weather only when it changes the drive.
            if let w = store.weather, w.spoken != nil {
                if let alert = w.alerts.first {
                    Text(alert).role(.metaStrong).foregroundStyle(Palette.readyText)
                }
                Text(w.summary).role(.meta).foregroundStyle(Palette.readyText)
            }
            if route.source == "apple" {
                Text("No lane details on this route.").role(.meta).foregroundStyle(Palette.meta)
            } else if !store.laneZones.isEmpty {
                HStack(spacing: Space.s8) {
                    Capsule().fill(Palette.ready).frame(width: Space.s16, height: Size.progress)
                    Text("Change lanes along the amber stretches.").role(.meta).foregroundStyle(Palette.meta)
                }
            }
            if let note = store.roadDataNote {
                Text(note).role(.meta).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.s8) {
                Mark(glyph: .handsOff, size: MarkSize.tiny).foregroundStyle(Palette.meta)
                Text("Mount the phone first. The driver never touches it.").role(.meta).foregroundStyle(Palette.meta)
            }
        }
    }
}

/// One of the two route choices: its time and how much of it is on roads posted 45 mph or more.
private struct RouteChoice: View {
    let title: String
    let option: RouteService.Option
    let selected: Bool
    var choose: () -> Void

    var body: some View {
        Button { Haptic.tap(); choose() } label: {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(title).role(.rowTitle)
                Text("\(Int((option.route.durationSeconds / 60).rounded())) min").role(.meta)
                if let fast = option.fastMeters {
                    Text(String(format: "%.1f mi at 45+ mph", fast / 1609.34)).role(.meta)
                }
            }
            .foregroundStyle(selected ? Palette.onDark : Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s12)
            .background(selected ? Palette.ink : Palette.field, in: RoundedRectangle(cornerRadius: Corner.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Corner.control, style: .continuous)
                        .strokeBorder(selected ? Palette.ink : Palette.hairline, lineWidth: Size.hairline))
        }
        .buttonStyle(Press())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Hard spots on maps: crash records in `stop`; everything else in ink, so amber means only "change lanes here".
enum SpotColor {
    static func isCrash(_ kind: HardSpot.Kind) -> Bool { [.crashCorridor, .studyIntersection, .fatalCrash].contains(kind) }
    static func of(_ kind: HardSpot.Kind) -> Color { isCrash(kind) ? Palette.stop : Palette.ink }
    /// Text on a spot's marker.
    static func onMarker(_ kind: HardSpot.Kind) -> Color { isCrash(kind) ? Palette.onStop : Palette.onDark }
}

extension DriveSession: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(self) }
}
