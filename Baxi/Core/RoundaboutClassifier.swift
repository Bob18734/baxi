import Foundation

// OWNER: Vardaan. This file is one of the two modules Vardaan writes himself.
// Claude wrote the types, the doc comments, the stub, and the tests in
// BaxiTests/RoundaboutClassifierTests.swift. Replace the body of `classify` with your own logic
// and make every test pass. Keep the signature.

/// One roundabout as it appears in OpenStreetMap: one or more ways tagged junction=roundabout that
/// share nodes, plus every other highway way that touches any of those nodes.
struct RoundaboutInput {
    /// The ways tagged junction=roundabout that form the circle (often more than one).
    let circleWays: [OSMWay]
    /// Ways that touch the circle but are not part of it: the legs (approaches and exits).
    let touchingWays: [OSMWay]
}

enum RoundaboutClass: String, Codable {
    /// One circulating lane. Tier 2.
    case singleLane
    /// Two or more circulating lanes. Tier 3.
    case multiLane
    /// A roundabout that feeds a freeway or parkway ramp (Keystone Parkway style). Tier 4.
    case interchange
}

struct RoundaboutClassification: Equatable {
    /// Circulating lanes, 1 or more.
    let lanes: Int
    /// Distinct legs. A two-way road counts once; a divided road's in and out carriageways count once each.
    let legs: Int
    let classification: RoundaboutClass
    /// True when the lane count came from a `lanes` tag, false when it was guessed.
    let lanesTagged: Bool
}

enum RoundaboutClassifier {
    /// Rules the implementation must follow (the tests check these):
    /// 1. `lanes` is the maximum `lanes` tag across the circle ways. No tag anywhere: guess 1 and set lanesTagged=false.
    /// 2. `legs` counts touching ways by distinct name (or by id when unnamed). A way whose highway tag
    ///    is `service`, `footway`, `cycleway` or `path` is not a leg.
    /// 3. `interchange` when any touching way has highway `motorway_link` or `trunk_link`.
    ///    Otherwise `multiLane` when lanes >= 2, else `singleLane`.
    static func classify(_ input: RoundaboutInput) -> RoundaboutClassification {
        // STUB so the app runs before Vardaan's version lands. Replace everything below.
        let tagged = input.circleWays.compactMap(\.lanes).max()
        let lanes = tagged ?? 1
        let cls: RoundaboutClass = lanes >= 2 ? .multiLane : .singleLane
        return RoundaboutClassification(lanes: lanes, legs: input.touchingWays.count,
                                        classification: cls, lanesTagged: tagged != nil)
    }
}
