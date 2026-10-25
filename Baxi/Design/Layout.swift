import SwiftUI

// Measurements particular to one screen or mark, named so no screen writes a raw number (docs/DESIGN.md).

enum PreviewSize {
    static let imagery: CGFloat = 200
    static let number: CGFloat = 30
    static let mapDistance: Double = 450
    static let mapPitch: Double = 45
}

enum LaneSize {
    static let row: CGFloat = 52
    static let corner: CGFloat = 8
    /// A lane line between lanes, and its dashes (dash, gap) where changing lanes is allowed.
    static let divider: CGFloat = 3
    static let dash: [CGFloat] = [9, 7]
    /// A lane arrow's size as a share of the lane's height.
    static let markRatio: CGFloat = 0.55
    /// The lanes in the welcome screen's example.
    static let sample: CGFloat = 40
}

enum ArrivedSize {
    static let ring: CGFloat = 160
    static let ringLine: CGFloat = 12
    static let segments: CGFloat = 76
}

enum SkillRingSize {
    static let ring: CGFloat = 46
    static let mark: CGFloat = 20
    static let line: CGFloat = 5
}

enum DriveSize {
    static let markBig: CGFloat = 64
    static let route: CGFloat = 8
    static let routeEdge: CGFloat = 13
    static let marker: CGFloat = 34
    static let car: CGFloat = 50
    static let carEdge: CGFloat = 3
    static let control: CGFloat = 60
    static let endWidth: CGFloat = 92
    static let laneTall: CGFloat = 58
}

/// How the Drive map follows the car: it looks this far ahead, so the car sits low on the screen and the road ahead
/// fills it (as in Maps), and it resumes following this long after the driver pans or zooms.
enum DriveFollow {
    static let lookAhead: Double = 150
    static let lookAheadClose: Double = 90
    static let resumeSeconds: Double = 10
}

enum MapLine {
    static let route: CGFloat = 5
    static let edge: CGFloat = 9
    /// A practice route that is not the chosen one, and its number sign.
    static let other: CGFloat = 4
    static let numberSign: CGFloat = 32
    /// How close (in points) a tap must land to a drawn route to choose it.
    static let tapReach: CGFloat = 28
    static let dot: CGFloat = 10
    static let dotEdge: CGFloat = 2
    static let pin: CGFloat = 30
}

enum MapSpan {
    static let home: Double = 7_000
    static let search: Double = 25_000
}

/// The Routes panel: a sheet over the map with three resting heights (docs/DESIGN.md).
enum PanelSize {
    /// The middle height, as a share of the space above the bottom bar.
    static let halfFraction: CGFloat = 0.5
    /// The map that stays visible above the panel at its tallest.
    static let topGap: CGFloat = 48
    /// The part of the route's map area that the panel covers at its middle height, when framing a route.
    static let grabberWidth: CGFloat = 36
    static let grabberHeight: CGFloat = 5
    /// Pulling the list down past its top by this much lowers the panel.
    static let pullToLower: CGFloat = 40
    /// A flick faster than this (points per second) moves one height in its direction.
    static let flick: CGFloat = 500
    static let placeholderWide: CGFloat = 220
    static let placeholderNarrow: CGFloat = 140
}

enum SkillPanelSize { static let segments: CGFloat = 76 }

/// The guide sign's shape: an outer corner, the white border set in from the edge, and the warning-sign icons.
enum SignStyle {
    static let corner: CGFloat = 14
    static let innerCorner: CGFloat = 10
    static let borderInset: CGFloat = 4
    static let border: CGFloat = 2
    static let icon: CGFloat = 30
}

enum SignSize {
    static let width: CGFloat = 58
    static let height: CGFloat = 70
    /// The car's speed, under the sign.
    static let readout: CGFloat = 46
    static let corner: CGFloat = 8
    static let innerCorner: CGFloat = 5
    static let inset: CGFloat = 3
    static let border: CGFloat = 2
}

enum BarSize {
    static let marker: CGFloat = 18
    static let markerHeight: CGFloat = 3
}

enum HabitsSize {
    static let chart: CGFloat = 96
    static let barCorner: CGFloat = 4
}

enum PriorWheel {
    static let maxHours = 100
    static let height: CGFloat = 120
}

enum DriveRowSize { static let date: CGFloat = 44 }
