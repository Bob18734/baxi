import SwiftUI
import MapKit

/// Higgsfield UI concept adapted to Baxi's native controls and design tokens.
struct StartingPointView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var location = PlanningLocation()
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searchError: String?
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var searchID = UUID()

    var body: some View {
        NavigationStack {
            List {
                Section("Selected start") {
                    Label(store.homeLabel, systemImage: "mappin.circle")
                        .font(BaxiFont.body).foregroundStyle(BaxiColor.ink)
                }

                Section {
                    Button {
                        stopSearch()
                        location.request()
                    } label: {
                        HStack {
                            Label(location.isLocating ? "Finding your location…" : "Use current location", systemImage: "location.fill")
                            Spacer()
                            if location.isLocating { ProgressView() }
                        }
                        .font(BaxiFont.bodyBold)
                        .padding(.vertical, BaxiSpace.sm)
                    }
                    .disabled(location.isLocating)
                    if let error = location.error {
                        Text(error).font(BaxiFont.callout).foregroundStyle(BaxiColor.stopText)
                    }
                } footer: {
                    Text("Refresh your starting point if you move.")
                }

                Section {
                    searchLayout {
                        Image(systemName: "magnifyingglass").foregroundStyle(BaxiColor.inkSoft)
                        TextField("Address or place", text: $query)
                            .submitLabel(.search)
                            .onSubmit { search() }
                            .accessibilityLabel("Starting address or place")
                        Button("Search") { search() }
                            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .frame(minHeight: 44)
                    }
                    if searching { ProgressView("Searching…") }
                    if let searchError { Text(searchError).foregroundStyle(BaxiColor.stopText) }
                    ForEach(results, id: \.self) { item in
                        Button {
                            choose(Coordinate(item.placemark.coordinate), label: item.name ?? "Selected starting place")
                        } label: {
                            VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                                Text(item.name ?? "Place").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                                Text(item.placemark.title ?? "").font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                            }
                        }
                    }
                }

                Section {
                    Button { choose(AppStore.carmelDemoHome, label: "Carmel City Center (demo)") } label: {
                        HStack(spacing: BaxiSpace.md) {
                            Image(systemName: "mappin.circle.fill")
                            VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                                Text("Carmel City Center").font(BaxiFont.bodyBold)
                                Text("Demo location").font(BaxiFont.footnote)
                            }
                            Spacer()
                            if store.home == AppStore.carmelDemoHome { Image(systemName: "checkmark") }
                        }
                        .foregroundStyle(BaxiColor.accent)
                        .padding(.vertical, BaxiSpace.sm)
                    }
                } header: {
                    Text("Practice starting point")
                } footer: {
                    Text("Saved for this session. Practice loops always start in Carmel.")
                }
                Section {
                    DisclosureGroup("How your location is used") {
                        Text("Place searches go to Apple Maps. Planning a route sends its start and destination to the route provider.")
                            .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                    }
                    .font(BaxiFont.callout)
                }
            }
            .scrollContentBackground(.hidden)
            .baxiPage()
            .navigationTitle("Starting point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: query) { _, _ in stopSearch(); results = [] }
            .onChange(of: location.coordinate) { _, coordinate in
                if let coordinate { choose(coordinate, label: "Current location (snapshot)") }
            }
            .onDisappear { location.cancel(); stopSearch() }
        }
    }

    private var searchLayout: AnyLayout {
        textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: BaxiSpace.sm))
            : AnyLayout(HStackLayout(spacing: BaxiSpace.sm))
    }

    private func choose(_ coordinate: Coordinate, label: String) {
        location.cancel()
        stopSearch()
        store.chooseStart(coordinate, label: label)
        dismiss()
    }

    private func stopSearch() {
        searchTask?.cancel()
        searchID = UUID()
        searching = false
        searchError = nil
    }

    private func search() {
        stopSearch()
        location.cancel()
        results = []
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let id = searchID
        searching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = MKCoordinateRegion(center: (store.home ?? AppStore.carmelDemoHome).clLocation,
                                            latitudinalMeters: 25_000, longitudinalMeters: 25_000)
        searchTask = Task {
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled, id == searchID else { return }
                results = response.mapItems
                searchError = results.isEmpty ? "No places found. Try a street address or nearby landmark." : nil
            } catch {
                guard !Task.isCancelled, id == searchID else { return }
                searchError = "Search is unavailable. Check your connection and try again."
            }
            searching = false
        }
    }
}
