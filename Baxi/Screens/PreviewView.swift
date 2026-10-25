import SwiftUI
import MapKit

/// Before the drive, at home or parked: every hard spot on the route as street-level imagery from just before
/// it, what Baxi will say there, the lanes, where the data comes from, and the rule from the Indiana Driver's
/// Manual where the students have written it.
struct PreviewView: View {
    let routeName: String
    let spots: [HardSpot]
    let route: PlannedRoute
    var onStart: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    private let briefings = BundledData.briefings()

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Preview", subtitle: routeName, actionTitle: "Close") { dismiss() }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s32) {
                    Text(summary).role(.body).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
                    if spots.isEmpty {
                        EmptyState(message: "Nothing tricky on this route: no roundabouts, ramps or turns from busy roads.")
                    }
                    ForEach(Array(spots.enumerated()), id: \.element.id) { i, spot in
                        SpotSection(index: i + 1, spot: spot, route: route, briefing: spot.featureKind.flatMap { briefings[$0] },
                                    isLast: i == spots.count - 1)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.s32)
            }
        }
        .pageBackground()
        .safeAreaInset(edge: .bottom) {
            if let onStart {
                BigButton(title: "Start drive") { dismiss(); onStart() }
                    .padding(.horizontal, Space.margin)
                    .padding(.vertical, Space.s12)
                    .background(Palette.page)
            }
        }
    }

    private var summary: String {
        let counts = Dictionary(grouping: spots, by: \.kind).mapValues(\.count)
        func n(_ k: HardSpot.Kind, _ one: String, _ many: String) -> String? { counts[k].map { "\($0) \($0 == 1 ? one : many)" } }
        let parts = [n(.roundabout, "roundabout", "roundabouts"), n(.ramp, "merge or ramp", "merges or ramps"),
                     n(.laneTurn, "lane choice", "lane choices"), n(.schoolZone, "school zone", "school zones"),
                     n(.crashCorridor, "crash-heavy stretch", "crash-heavy stretches"),
                     n(.studyIntersection, "studied intersection", "studied intersections"),
                     n(.fatalCrash, "past fatal crash", "past fatal crashes"),
                     n(.glare, "low-sun stretch if you leave now", "low-sun stretches if you leave now")].compactMap { $0 }
        return parts.isEmpty ? "No hard spots on this route." : "On this route: " + parts.joined(separator: ", ") + "."
    }
}

/// One hard spot: the approach in Look Around (or a small map), then what to know about it.
private struct SpotSection: View {
    let index: Int
    let spot: HardSpot
    let route: PlannedRoute
    let briefing: Briefing?
    let isLast: Bool
    @State private var scene: MKLookAroundScene?
    @State private var looked = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            imagery
                .frame(height: PreviewSize.imagery)
                .clipShape(RoundedRectangle(cornerRadius: Corner.control, style: .continuous))
            HStack(alignment: .firstTextBaseline, spacing: Space.s12) {
                Text("\(index)").role(.rowTitle).monospacedDigit()
                    .foregroundStyle(SpotColor.onMarker(spot.kind))
                    .frame(width: PreviewSize.number, height: PreviewSize.number)
                    .background(SpotColor.of(spot.kind), in: Circle())
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(spot.title).role(.rowTitle).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    Text("At \(DriveView.distance(spot.alongMeters))").role(.meta).foregroundStyle(Palette.meta)
                }
            }
            said
            if let strip = spot.laneStrip {
                // The same dark lane panel as the Drive screen, so the driver recognises it on the road.
                LaneRow(strip: strip, night: true)
                    .padding(Space.s12)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: Corner.control, style: .continuous))
            }
            if let note = spot.mapDataNote {
                Text(note).role(.meta).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
            }
            if let context = spot.context { source(context) }
            if let b = briefing { manual(b) }
            if !isLast { Hairline().padding(.top, Space.s8) }
        }
        .task(id: spot.id) { await loadScene() }
    }

    private var said: some View {
        HStack(alignment: .top, spacing: Space.s12) {
            Mark(glyph: spot.spoken.isEmpty ? .speakerOff : .speaker, size: MarkSize.row).foregroundStyle(Palette.meta)
            if spot.spoken.isEmpty {
                Text("Baxi stays quiet here. This record is shown only in Preview.")
                    .role(.body).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\u{201C}\(spot.spoken)\u{201D}").role(.bodyStrong).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spot.spoken.isEmpty ? "Baxi stays quiet here" : "Baxi will say: \(spot.spoken)")
    }

    private func source(_ context: PreviewContext) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Space.s8) {
                Text(context.detail).role(.body).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
                if let url = context.url {
                    Link(context.source, destination: url).role(.metaStrong).foregroundStyle(Palette.ink).underline()
                } else {
                    Text("\(context.source). No source link in this record.").role(.meta).foregroundStyle(Palette.meta)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.s8)
        } label: {
            Text("Where this comes from").role(.metaStrong).foregroundStyle(Palette.ink)
        }
        .tint(Palette.ink)
    }

    private func manual(_ b: Briefing) -> some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text("From the Indiana Driver's Manual").role(.group).foregroundStyle(Palette.meta)
            Text(b.title).role(.rowTitle).foregroundStyle(Palette.ink)
            Text(b.howTo).role(.body).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
            if !b.quote.isEmpty {
                Text("\u{201C}\(b.quote)\u{201D}").role(.body).italic().foregroundStyle(Palette.read)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Space.s12)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.ink).frame(width: Size.quoteRule) }
            }
            if let c = b.citation { Text(c).role(.meta).foregroundStyle(Palette.meta) }
        }
    }

    @ViewBuilder private var imagery: some View {
        if let scene {
            LookAroundPreview(initialScene: scene, allowsNavigation: true, showsRoadLabels: true)
        } else if !looked {
            Rectangle().fill(Palette.track).shimmering()
        } else {
            // No street imagery here: a small map of the spot, aimed the way the car arrives.
            Map(initialPosition: .camera(MapCamera(centerCoordinate: spot.location.clLocation, distance: PreviewSize.mapDistance,
                                                   heading: approachHeading, pitch: PreviewSize.mapPitch)),
                interactionModes: []) {
                MapPolyline(coordinates: route.polyline.points.map(\.clLocation))
                    .stroke(Palette.ink, style: StrokeStyle(lineWidth: MapLine.route, lineCap: .round, lineJoin: .round))
                Annotation("", coordinate: spot.location.clLocation) {
                    Circle().fill(SpotColor.of(spot.kind)).frame(width: MapLine.dot + Space.s4, height: MapLine.dot + Space.s4)
                        .overlay(Circle().stroke(Palette.field, lineWidth: MapLine.dotEdge))
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .overlay(alignment: .bottomLeading) {
                Text("No street imagery here").role(.meta).foregroundStyle(Palette.onDark)
                    .padding(.horizontal, Space.s12).padding(.vertical, Space.s4)
                    .background(Palette.ink, in: Capsule()).padding(Space.s12)
            }
        }
    }

    /// The partner's ApproachHeading where it applies; otherwise the route's own bearing.
    private var approachHeading: Double {
        if ApproachHeading.isImplemented, let b = ApproachHeading.bearing(route: route.polyline.points, spot: spot.location) { return b }
        return route.polyline.bearing(atMeters: max(0, spot.alongMeters - 40)) ?? 0
    }

    /// Look Around from just before the spot, so the image shows the approach.
    private func loadScene() async {
        let point = route.polyline.coordinate(atMeters: max(0, spot.alongMeters - 40)) ?? spot.location
        let found = try? await MKLookAroundSceneRequest(coordinate: point.clLocation).scene
        withAnimation(Motion.standard) { scene = found; looked = true }
    }
}

/// The lanes at a spot or a turn, as painted on the road: the lanes to use lit amber (get ready).
struct LaneRow: View {
    let strip: LaneStrip
    let night: Bool
    var height: CGFloat = LaneSize.row

    var body: some View {
        HStack(spacing: Space.s8) {
            ForEach(0..<strip.laneCount, id: \.self) { i in
                let lit = strip.highlighted.contains(i)
                LaneMark(label: i < strip.labels.count ? strip.labels[i] : "", size: height * LaneSize.markRatio)
                    .foregroundStyle(lit ? Palette.ink : (night ? Palette.nightRead : Palette.meta))
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(lit ? Palette.ready : (night ? Palette.nightPanel : Palette.field),
                                in: RoundedRectangle(cornerRadius: LaneSize.corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: LaneSize.corner, style: .continuous)
                                .strokeBorder(lit || night ? Color.clear : Palette.hairline, lineWidth: Size.hairline))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Self.spoken(strip))
    }

    static func spoken(_ strip: LaneStrip) -> String {
        let lanes = strip.highlighted.sorted().map { String($0 + 1) }
        switch lanes.count {
        case 0: return "\(strip.laneCount) lanes"
        case 1: return "Use lane \(lanes[0]) of \(strip.laneCount), counting from the left"
        default: return "Use lanes \(lanes.dropLast().joined(separator: ", ")) or \(lanes.last!) of \(strip.laneCount), counting from the left"
        }
    }
}
