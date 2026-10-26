import SwiftUI
import MapKit

/// Where a searched route begins. Three ways: a precise fix of the phone's position (PlanningLocation), Carmel
/// City Center, or a place found by search. A choice lasts for this session; until one is made, a searched route
/// starts wherever the phone is. From the partner's trip-start work (PR #4), on Baxi's own rows.
struct StartingPointView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var location = PlanningLocation()
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    /// Why the search shows no places; nil while results show.
    @State private var searchNote: String?
    @State private var searchID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Starting point", subtitle: "Where a searched route begins. Kept for this session.") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s24) {
                    choices
                    search
                    Text("Place searches go to Apple Maps. Finding a route sends its start and end to the route server. Practice routes always start in Carmel.")
                        .role(.meta).foregroundStyle(Palette.meta).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.s32)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .pageBackground()
        // Places appear while typing, once the typing pauses.
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await runSearch()
        }
        .onChange(of: location.coordinate) { _, found in
            if let found { choose(found, label: "Your location") }
        }
        .onDisappear { location.cancel() }
    }

    /// The phone's position, or Carmel: the one in use has a check.
    private var choices: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Start from")
            Button { Haptic.tap(); location.request() } label: {
                Row(title: location.isLocating ? "Finding your location…" : "Your location",
                    detail: "A precise fix of where the phone is now",
                    leading: { Mark(glyph: .locate, size: MarkSize.row).foregroundStyle(Palette.ink) },
                    trailing: { trailing(chosen: !store.homeChosen || store.homeLabel == "Your location", working: location.isLocating) })
            }
            .buttonStyle(Press())
            .disabled(location.isLocating)
            .accessibilityHint("Finds where the phone is and starts searched routes there")
            if let error = location.error {
                Text(error).role(.meta).foregroundStyle(Palette.stopText)
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, Space.s8)
            }
            Button { Haptic.tap(); choose(AppStore.carmelDemoHome, label: "Carmel City Center") } label: {
                Row(title: "Carmel City Center", detail: "Where the practice routes begin", showsDivider: false,
                    leading: { SignalMark(size: MarkSize.row) },
                    trailing: { trailing(chosen: store.homeChosen && store.home == AppStore.carmelDemoHome, working: false) })
            }
            .buttonStyle(Press())
        }
    }

    @ViewBuilder private func trailing(chosen: Bool, working: Bool) -> some View {
        if working { SignalDots() }
        else if chosen { Mark(glyph: .check, size: MarkSize.row).foregroundStyle(Palette.goText).accessibilityLabel("In use") }
        else { RowArrow() }
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            GroupLabel("Or a place")
            FieldBox {
                Mark(glyph: .search, size: MarkSize.row).foregroundStyle(Palette.meta)
                TextField("Search an address or place", text: $query)
                    .role(.body).foregroundStyle(Palette.ink)
                    .submitLabel(.search)
                    .onSubmit { Task { await runSearch() } }
                    .autocorrectionDisabled()
                    .accessibilityLabel("Starting address or place")
                if !query.isEmpty {
                    MarkButton(glyph: .close, label: "Clear search", tint: Palette.meta) { query = ""; results = []; searchNote = nil }
                        .padding(.trailing, -Space.s12)
                }
            }
            if let searchNote {
                Text(searchNote).role(.body).foregroundStyle(Palette.read).padding(.vertical, Space.s8)
            } else if results.isEmpty, !query.isEmpty {
                SignalDots().padding(.vertical, Space.s12)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.offset) { i, item in
                    Button { Haptic.tap(); choose(Coordinate(item.placemark.coordinate), label: item.name ?? "Chosen place") } label: {
                        Row(title: item.name ?? "Place", detail: item.placemark.title, showsDivider: i < results.count - 1) { RowArrow() }
                    }
                    .buttonStyle(Press())
                }
            }
        }
    }

    private func choose(_ coordinate: Coordinate, label: String) {
        location.cancel()
        store.chooseStart(coordinate, label: label)
        Haptic.success()
        dismiss()
    }

    private func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { results = []; searchNote = nil; return }
        let id = UUID(); searchID = id
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        req.region = MKCoordinateRegion(center: store.start.clLocation, latitudinalMeters: MapSpan.search, longitudinalMeters: MapSpan.search)
        do {
            let found = try await MKLocalSearch(request: req).start().mapItems
            guard searchID == id else { return }   // typing moved on
            results = found
            searchNote = found.isEmpty ? "No places found for \u{201C}\(text)\u{201D}." : nil
        } catch {
            guard searchID == id else { return }
            results = []
            searchNote = (error as? MKError)?.code == .placemarkNotFound
                ? "No places found for \u{201C}\(text)\u{201D}."
                : "No connection. Check the internet and try again."
        }
    }
}
