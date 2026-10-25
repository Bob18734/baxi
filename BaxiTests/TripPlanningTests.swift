import Testing
import CoreLocation
@testable import Baxi

struct TripPlanningTests {
    @Test func olderDestinationCannotReplaceNewDestinationOrFinishItsSpinner() {
        var requests = RouteRequestState()
        let first = requests.begin()
        let second = requests.begin()
        #expect(!requests.accepts(first))
        requests.finish(first)
        #expect(requests.isRouting)
        #expect(requests.accepts(second))
        requests.finish(second)
        #expect(!requests.isRouting)
    }

    @Test func changingStartOrChoosingPresetRejectsPendingRoutingAndRoadData() {
        var requests = RouteRequestState()
        let pending = requests.begin()
        requests.cancel()
        #expect(!requests.accepts(pending))
        #expect(!requests.isRouting)
        let next = requests.begin()
        requests.finish(pending)
        #expect(requests.accepts(next))
    }

    @Test func planningRejectsStaleImpreciseAndInvalidLocationFixes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func fix(age: Double, accuracy: Double, latitude: Double = 39.97) -> CLLocation {
            CLLocation(coordinate: .init(latitude: latitude, longitude: -86.12), altitude: 0,
                       horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
        }
        #expect(PlanningLocationPolicy.accepts(fix(age: 0, accuracy: 10), now: now))
        #expect(PlanningLocationPolicy.accepts(fix(age: 30, accuracy: 100), now: now))
        #expect(!PlanningLocationPolicy.accepts(fix(age: 31, accuracy: 10), now: now))
        #expect(!PlanningLocationPolicy.accepts(fix(age: -6, accuracy: 10), now: now))
        #expect(!PlanningLocationPolicy.accepts(fix(age: 0, accuracy: -1), now: now))
        #expect(!PlanningLocationPolicy.accepts(fix(age: 0, accuracy: 101), now: now))
        #expect(!PlanningLocationPolicy.accepts(fix(age: 0, accuracy: 10, latitude: 95), now: now))
    }
}

@MainActor struct TripPlanningStoreTests {
    @Test func selectedStartSurvivesBundledDataLoadingAndDoesNotPersistAcrossLaunches() async throws {
        let suite = "baxi-trip-test-\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = AppStore(preferences: preferences)
        let chosen = Coordinate(lat: 40.0428, lon: -86.1275)
        store.chooseStart(chosen, label: "Selected place")
        await store.ensureLoaded()
        #expect(store.home == chosen)
        #expect(store.homeLabel == "Selected place")
        #expect(AppStore(preferences: preferences).home == AppStore.carmelDemoHome)
        store.chooseStart(Coordinate(lat: 99, lon: 0), label: "Invalid")
        #expect(store.home == chosen)
    }

    @Test func warningLevelRestoresAndUnknownStoredValueFallsBack() throws {
        let suite = "baxi-trip-test-\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = AppStore(preferences: preferences)
        store.level = .new
        #expect(AppStore(preferences: preferences).level == .new)
        preferences.set("invalid", forKey: "experienceLevel")
        #expect(AppStore(preferences: preferences).level == .gettingComfortable)
    }
}
