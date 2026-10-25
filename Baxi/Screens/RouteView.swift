import SwiftUI
import MapKit

/// Plan a drive: search a destination or pick a practice route, see it on the map, preview it, start it.
/// The map fills the screen. With no route chosen it shows every practice route, each with its number; the
/// numbers match the list. One panel rests along the bottom at one of three heights (just the search field,
/// half the screen, nearly all of it) and is dragged between them, so the map can be the whole screen.
/// The panel ends where the bottom bar begins.
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
    /// Every practice route's line, read once from the bundle, for the map.
    @State private var presetLines: [String: Polyline] = [:]
    /// Routes has been opened at least once. The map lives from launch (the tab stays alive), and its location dot
    /// would ask for permission over Home; it waits until the tab is seen.
    @State private var opened = false

    // The panel.
    @State private var detent: PanelDetent = .half
    /// How far the panel has been dragged from its resting height; zero when at rest.
    @State private var drag: CGFloat = 0
    /// Measured: the part of the panel that always shows (grabber and the search field or the route's title).
    @State private var headerHeight: CGFloat = 0
    /// Measured: everything under the header.
    @State private var contentHeight: CGFloat = 0

    /// The panel shows places while the field is in use.
    private var searching: Bool { searchFocused || !query.isEmpty }
    /// Home's search field was tapped and Routes is now the tab on screen.
    private var wantsSearchNow: Bool { store.tab == .route && store.wantsSearch }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                routeMap(height: geo.size.height)
                panel(available: geo.size.height)
            }
        }
        // Places appear while typing, once the typing pauses.
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await search()
        }
        .task {
            // Reading five bundled routes takes a moment; do it off the main thread, once.
            guard presetLines.isEmpty else { return }
            presetLines = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: RouteService.presets.compactMap { p in
                    (try? RouteService.preset(p.id)).map { (p.id, $0.polyline) }
                })
            }.value
        }
        // The tab stays alive while hidden, so its work runs each time it is opened, not when the app launches
        // (which would ask for location over the Welcome screen).
        .onChange(of: store.tab, initial: true) { _, tab in
            guard tab == .route else { searchFocused = false; return }
            opened = true
            store.loadCarmelDemo(); store.refreshPrep()
            Task { await store.refreshOrigin() }
        }
        // Once the phone's location arrives, show it (until a route is picked).
        .onChange(of: store.originIsHere) { _, here in
            guard here, store.route == nil, presetLines.isEmpty else { return }
            withAnimation(Motion.standard) { camera = .region(homeRegion) }
        }
        .onChange(of: wantsSearchNow) { _, want in
            guard want else { return }
            store.wantsSearch = false
            searchFocused = true
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { settle(.full) }
        }
        .onChange(of: store.route?.id) { _, id in
            // A route arrives or leaves: the panel rests where its content fits, and the map frames the route.
            settle(id == nil ? .half : .half)
        }
        .sheet(isPresented: $showPreview, onDismiss: {
            // Start only after the sheet is gone; presenting the drive mid-dismiss can be dropped.
            if startAfterPreview { startAfterPreview = false; startDrive(replay: nil) }
        }) {
            if let r = store.route {
                PreviewView(routeName: r.name, spots: spots, route: r) { startAfterPreview = true }
            }
        }
    }

    // MARK: Map

    private func routeMap(height: CGFloat) -> some View {
        MapReader { proxy in
            Map(position: $camera) {
                if MapPrivacy.showsYou && opened { UserAnnotation() }
                if let r = store.route {
                    chosenRoute(r)
                } else {
                    allRoutes
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls {
                if MapPrivacy.showsYou && opened { MapUserLocationButton() }
                MapCompass()
            }
            // Map chrome (the compass, the Apple logo) keeps clear of the panel's lowest height.
            .safeAreaPadding(.bottom, headerHeight)
            .onTapGesture { point in
                guard store.route == nil, !searching, let tapped = proxy.convert(point, from: .local),
                      let reach = proxy.convert(CGPoint(x: point.x, y: point.y + MapLine.tapReach), from: .local) else { return }
                if let id = nearestPreset(to: Coordinate(tapped), within: Geo.distanceMeters(Coordinate(tapped), Coordinate(reach))) {
                    Haptic.tap(); store.choosePreset(id)
                }
            }
            .ignoresSafeArea(edges: .top)
            .onChange(of: store.route?.id, initial: true) { _, _ in frame(mapHeight: height) }
            .onChange(of: presetLines.isEmpty) { _, _ in frame(mapHeight: height) }
            .onChange(of: store.tab) { _, tab in if tab == .route { frame(mapHeight: height) } }
        }
    }

    /// The chosen route: the planned road in ink with a white edge, lane changes in amber, hard spots as dots.
    @MapContentBuilder private func chosenRoute(_ r: PlannedRoute) -> some MapContent {
        MapPolyline(coordinates: r.polyline.points.map(\.clLocation))
            .stroke(Palette.field, style: StrokeStyle(lineWidth: MapLine.edge, lineCap: .round, lineJoin: .round))
        MapPolyline(coordinates: r.polyline.points.map(\.clLocation))
            .stroke(Palette.ink, style: StrokeStyle(lineWidth: MapLine.route, lineCap: .round, lineJoin: .round))
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
    }

    /// Every practice route, numbered as in the list. Tapping a number (or the line) chooses that route.
    @MapContentBuilder private var allRoutes: some MapContent {
        ForEach(Array(RouteService.presets.enumerated()), id: \.element.id) { i, p in
            if let line = presetLines[p.id] {
                MapPolyline(coordinates: line.points.map(\.clLocation))
                    .stroke(Palette.field, style: StrokeStyle(lineWidth: MapLine.edge, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: line.points.map(\.clLocation))
                    .stroke(Palette.mapRouteOther, style: StrokeStyle(lineWidth: MapLine.other, lineCap: .round, lineJoin: .round))
                // The loops all start downtown, so each number sits at its route's far end.
                if let at = line.coordinate(atMeters: line.lengthMeters / 2) {
                    Annotation(p.name, coordinate: at.clLocation) {
                        Button { Haptic.tap(); store.choosePreset(p.id) } label: { NumberTab(number: i + 1) }
                            .buttonStyle(Press())
                            .accessibilityLabel("Route \(i + 1), \(p.name)")
                            .accessibilityHint("Shows the route")
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        if presetLines.isEmpty && !store.originIsHere {
            Annotation("Carmel", coordinate: AppStore.carmelDemoHome.clLocation) { SignalMark(size: SignalSize.map) }
        }
    }

    /// The practice route whose line passes within `meters` of a tapped point.
    private func nearestPreset(to point: Coordinate, within meters: Double) -> String? {
        RouteService.presets.compactMap { p -> (String, Double)? in
            guard let line = presetLines[p.id] else { return nil }
            return (p.id, Geo.distanceMeters(from: point, toPolyline: line.points))
        }
        .filter { $0.1 <= meters }
        .min { $0.1 < $1.1 }?.0
    }

    /// Where the map rests with no route and no practice routes yet: around the phone when its location is
    /// known, else Carmel.
    private var homeRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: (store.originIsHere ? store.origin : AppStore.carmelDemoHome).clLocation,
                           latitudinalMeters: MapSpan.home, longitudinalMeters: MapSpan.home)
    }

    /// Frames the chosen route, or all the practice routes, in the map above the panel at its middle height.
    private func frame(mapHeight: CGFloat) {
        let covered = max(0, mapHeight * PanelSize.halfFraction - headerHeight)
        let visible = max(1, mapHeight - headerHeight)
        let region: MKCoordinateRegion
        if let r = store.route {
            region = Self.fit(Self.rect(r.polyline), coveredBelow: covered / visible)
        } else if !presetLines.isEmpty {
            let all = presetLines.values.map(Self.rect).reduce(MKMapRect.null) { $0.union($1) }
            region = Self.fit(all, coveredBelow: covered / visible)
        } else {
            region = homeRegion
        }
        withAnimation(Motion.standard) { camera = .region(region) }
    }

    static func rect(_ line: Polyline) -> MKMapRect {
        line.points.reduce(MKMapRect.null) {
            $0.union(MKMapRect(origin: MKMapPoint($1.clLocation), size: MKMapSize(width: 1, height: 1)))   // design-lint:allow a one-point map rect to union, not a drawn size
        }
    }

    /// A region that shows `rect` with a margin, in the top part of the map: the bottom `coveredBelow` share
    /// of the map (0 to 1) sits under the panel. Map y grows southward, so the extra height goes under the panel.
    static func fit(_ rect: MKMapRect, coveredBelow: Double) -> MKCoordinateRegion {
        guard !rect.isNull else { return MKCoordinateRegion(center: AppStore.carmelDemoHome.clLocation, latitudinalMeters: MapSpan.home, longitudinalMeters: MapSpan.home) }
        let share = min(0.85, max(0, coveredBelow))
        var r = rect.insetBy(dx: -rect.width * MapFrame.margin, dy: -rect.height * MapFrame.margin)
        r.size.height += r.size.height * share / (1 - share)
        return MKCoordinateRegion(r)
    }

    // MARK: Panel

    /// The sheet: a grabber, the header that always shows, and the content under it. Dragged between heights.
    private func panel(available: CGFloat) -> some View {
        let height = panelHeight(available: available)
        return VStack(spacing: 0) {
            header
                .background(HeightReader(onChange: { headerHeight = $0 }))
            ScrollView {
                content
                    .padding(.horizontal, Space.margin)
                    .padding(.bottom, Space.s24)
                    .background(HeightReader(onChange: { contentHeight = $0 }))
            }
            .scrollDisabled(detent != .full)
            .scrollDismissesKeyboard(.immediately)
            .scrollBounceBehavior(.basedOnSize)
            // Pulling the list down past its top lowers the panel, as it does in Maps.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                if y < -PanelSize.pullToLower, detent == .full, drag == 0 { lower() }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .clipped()
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Corner.sheet, topTrailingRadius: Corner.sheet, style: .continuous)
                .fill(Palette.page)
                .shadow(color: Palette.shadow, radius: Space.s16, y: -Space.s4)
        }
        .gesture(dragGesture(available: available))
        .animation(Motion.standard, value: searching)
        .animation(Motion.standard, value: store.route?.id)
        .animation(Motion.standard, value: routing)
    }

    private func panelHeight(available: CGFloat) -> CGFloat {
        let rest = restingHeight(detent, available: available)
        let low = restingHeight(.collapsed, available: available), high = restingHeight(.full, available: available)
        let raw = rest - drag
        // Past the ends the panel gives a little, then stops.
        if raw < low { return low - (low - raw) * MapFrame.giveBeyond }
        if raw > high { return high + (raw - high) * MapFrame.giveBeyond }
        return raw
    }

    /// Where the panel rests at each height. The middle and the top never exceed what the content needs.
    private func restingHeight(_ d: PanelDetent, available: CGFloat) -> CGFloat {
        let natural = headerHeight + contentHeight
        switch d {
        case .collapsed: return headerHeight
        case .half: return min(max(headerHeight, available * PanelSize.halfFraction), max(natural, headerHeight))
        case .full: return min(available - PanelSize.topGap, max(natural, headerHeight))
        }
    }

    private func dragGesture(available: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: Space.s8, coordinateSpace: .global)
            .onChanged { v in drag = v.translation.height }
            .onEnded { v in
                let current = restingHeight(detent, available: available) - v.translation.height
                let flick = v.predictedEndTranslation.height - v.translation.height
                var target: PanelDetent
                if abs(flick) > PanelSize.flick {
                    target = flick < 0 ? detent.higher : detent.lower
                } else {
                    target = PanelDetent.allCases.min { abs(restingHeight($0, available: available) - current) < abs(restingHeight($1, available: available) - current) } ?? detent
                }
                // Pulled down while typing: the keyboard goes, the places stay.
                if target != .full, searchFocused { searchFocused = false }
                drag = 0
                settle(target)
            }
    }

    private func settle(_ d: PanelDetent) {
        withAnimation(Motion.sheet) { detent = d; drag = 0 }
    }

    private func lower() { settle(detent.lower) }

    /// The grabber, then the search field (or the chosen route's title and its one main action).
    private var header: some View {
        VStack(spacing: Space.s12) {
            Button {
                Haptic.tap(); settle(detent == .collapsed ? .half : .collapsed)
            } label: {
                Capsule().fill(Palette.hairline).frame(width: PanelSize.grabberWidth, height: PanelSize.grabberHeight)
                    .frame(maxWidth: .infinity, minHeight: Space.s24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(detent == .collapsed ? "Show the routes" : "Show the map")
            if let r = store.route, !searching, !routing {
                RouteHeader(route: r, spots: spots, start: { startDrive(replay: nil) })
                    .padding(.horizontal, Space.margin)
            } else {
                searchField.padding(.horizontal, Space.margin)
            }
        }
        .padding(.bottom, Space.s12)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        if searching {
            places
        } else if routing {
            VStack(alignment: .leading, spacing: Space.s12) {
                Placeholder(width: PanelSize.placeholderWide, height: Space.s24)
                Placeholder(width: PanelSize.placeholderNarrow)
                Text(store.routeStep ?? "Finding a route…").role(.meta).foregroundStyle(Palette.meta)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let err = store.routeError {
            VStack(alignment: .leading, spacing: Space.s12) {
                Text(err).role(.body).foregroundStyle(Palette.stopText).fixedSize(horizontal: false, vertical: true)
                BigButton(title: "Back to practice routes", kind: .secondary) { store.clearRoute() }
            }
        } else if let r = store.route {
            RouteCard(route: r, showPreview: { showPreview = true }, switchTo: switchTo, replay: { startDrive(replay: $0) })
        } else {
            practiceRoutes
        }
    }

    /// The one search field. It lives in the header so it is never rebuilt while being typed in.
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
                Button("Cancel") { query = ""; results = []; searchNote = nil; searchFocused = false; settle(.half) }
                    .role(.bodyStrong).foregroundStyle(Palette.ink)
                    .buttonStyle(Press()).frame(minHeight: Size.tap)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    /// Places matching the search.
    private var places: some View {
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

    private var practiceRoutes: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            GroupLabel("Practice routes in Carmel")
            ForEach(Array(RouteService.presets.enumerated()), id: \.element.id) { i, p in
                RouteGuideSign(number: i + 1, name: p.name,
                               facts: [p.short, store.presetMeters[p.id].map { "\(Int(max(1, ($0 / 1609.34).rounded()))) mi" }]
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
        guard !routing else { return }
        Task { routing = true; await store.chooseOption(id); routing = false }
    }

    /// Starts the drive (or a replay). Nothing to start is said, never swallowed.
    private func startDrive(replay: Double?) {
        guard store.activeSession == nil else { return }
        if let s = store.makeSession(replay: replay) { store.activeSession = s }
        else { store.routeError = "The road data isn't ready yet. Try again in a moment." }
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
}

/// The panel's three resting heights.
enum PanelDetent: CaseIterable {
    case collapsed, half, full
    var higher: PanelDetent { self == .collapsed ? .half : .full }
    var lower: PanelDetent { self == .full ? .half : .collapsed }
}

/// How the map frames a route: the margin around it, and how much the panel gives when dragged past its ends.
enum MapFrame {
    static let margin = 0.16
    static let giveBeyond: CGFloat = 0.18
}

/// Reports a view's height to its parent, for the panel's measured heights.
private struct HeightReader: View {
    let onChange: (CGFloat) -> Void
    var body: some View {
        GeometryReader { g in
            Color.clear.onChange(of: g.size.height, initial: true) { _, h in onChange(h) }
        }
    }
}

/// The chosen route's title row and the screen's one main action: always visible, even with the panel lowered.
private struct RouteHeader: View {
    let route: PlannedRoute
    let spots: [HardSpot]
    let start: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
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
            BigButton(title: "Start drive", working: store.isPreparing, action: start)
                .accessibilityHint(store.isPreparing ? "Getting the route ready" : "Mount the phone first")
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
}

/// The rest of the chosen route, under its header: the choice of fastest or calmer, what's on it, Preview, Replay.
private struct RouteCard: View {
    let route: PlannedRoute
    let showPreview: () -> Void
    let switchTo: (String) -> Void
    let replay: (Double) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            if let calmerId = store.calmerOptionId, let fastest = store.routeOptions.first,
               let calmer = store.routeOptions.first(where: { $0.id == calmerId }) {
                HStack(spacing: Space.s8) {
                    RouteChoice(title: "Fastest", option: fastest, selected: route.id == fastest.id) { switchTo(fastest.id) }
                    RouteChoice(title: "Calmer", option: calmer, selected: route.id == calmer.id) { switchTo(calmer.id) }
                }
            }
            if store.isPreparing {
                Text("Getting the route ready…").role(.meta).foregroundStyle(Palette.meta).transition(.opacity)
            }
            notes
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
                            Button("At \(Int(x))x speed") { replay(x) }
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
            } else if store.isFetchingRoads {
                HStack(spacing: Space.s8) {
                    SignalDots(onFill: false)
                    Text("Loading lanes and roundabouts from OpenStreetMap…").role(.meta).foregroundStyle(Palette.meta)
                }
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
