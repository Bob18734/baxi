import SwiftUI

// Baxi's marks, drawn in one style: a 24 pt grid, a 2.25 pt round-capped stroke, no fills except where a mark
// is a light or a pointer (docs/DESIGN.md). System symbols are used only inside system controls.

/// Every drawn mark. Each is a path on a 24 x 24 grid.
enum Glyph: Hashable {
    // The bottom bar
    case signal, route, log
    // Actions
    case search, close, back, forward, settings, play, plus, share, speaker, speakerOff, check, locate
    // Driving
    case turnLeft, turnRight, slightLeft, slightRight, straight, uturn, merge, exitLeft, exitRight, roundabout, arrive, start
    // Heads-ups
    case school, crash, railroad, sun, moon, offRoute, waiting
    // Skills
    case oneLane, twoLane, highwayMerge, exitRamp, laneTurn, fastRoad
    // Welcome
    case handsOff, lock

    /// The arrow for a maneuver.
    static func maneuver(_ m: Maneuver) -> Glyph {
        switch m.kind {
        case .roundabout: return .roundabout
        case .merge, .onRamp: return .merge
        case .offRamp, .fork:
            return [.left, .slightLeft, .sharpLeft].contains(m.direction) ? .exitLeft : .exitRight
        case .arrive: return .arrive
        case .depart: return .start
        case .turn:
            switch m.direction {
            case .left, .sharpLeft: return .turnLeft
            case .right, .sharpRight: return .turnRight
            case .slightLeft: return .slightLeft
            case .slightRight: return .slightRight
            case .uturn: return .uturn
            default: return .straight
            }
        default: return .straight
        }
    }

    static func skill(_ s: Skill) -> Glyph {
        switch s {
        case .singleLaneRoundabout: .oneLane
        case .multiLaneRoundabout: .twoLane
        case .highwayMerge: .highwayMerge
        case .exitRamp: .exitRamp
        case .laneTurn: .laneTurn
        case .fastRoadMiles: .fastRoad
        }
    }
}

/// A drawn mark at a size, in the current foreground style.
struct Mark: View {
    let glyph: Glyph
    var size: CGFloat = 24
    /// A heavier stroke for the active tab and the Drive screen.
    var weight: CGFloat = 1

    var body: some View {
        Canvas { ctx, canvas in
            let k = canvas.width / 24
            let stroke = StrokeStyle(lineWidth: Size.stroke * weight * k, lineCap: .round, lineJoin: .round)
            let shading = GraphicsContext.Shading.foreground
            for part in MarkPaths.parts(glyph) {
                let path = part.path.applying(CGAffineTransform(scaleX: k, y: k))
                if part.filled { ctx.fill(path, with: shading) } else { ctx.stroke(path, with: shading, style: stroke) }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The paths behind each mark, on the 24 x 24 grid.
enum MarkPaths {
    struct Part { let path: Path; var filled = false }

    static func parts(_ g: Glyph) -> [Part] {
        func p(_ build: (inout Path) -> Void) -> Part { var path = Path(); build(&path); return Part(path: path) }
        func fill(_ build: (inout Path) -> Void) -> Part { var path = Path(); build(&path); return Part(path: path, filled: true) }
        func head(_ path: inout Path, tip: CGPoint, angle: Double, length: CGFloat = 5) {
            // An open arrowhead: two strokes back from the tip.
            for side in [-1.0, 1.0] {
                let a = angle + .pi + side * .pi / 4.2
                path.move(to: tip)
                path.addLine(to: CGPoint(x: tip.x + length * cos(a), y: tip.y + length * sin(a)))
            }
        }
        let up = -Double.pi / 2, left = Double.pi, right = 0.0

        switch g {
        case .signal:
            return [p { $0.addRoundedRect(in: CGRect(x: 7.5, y: 2.5, width: 9, height: 19), cornerSize: CGSize(width: 4.5, height: 4.5)) },
                    fill { $0.addEllipse(in: CGRect(x: 10, y: 5, width: 4, height: 4)) },
                    fill { $0.addEllipse(in: CGRect(x: 10, y: 10, width: 4, height: 4)) },
                    fill { $0.addEllipse(in: CGRect(x: 10, y: 15, width: 4, height: 4)) }]
        case .route:
            return [p {
                $0.move(to: CGPoint(x: 6, y: 19))
                $0.addCurve(to: CGPoint(x: 12, y: 12), control1: CGPoint(x: 6, y: 13), control2: CGPoint(x: 12, y: 17))
                $0.addCurve(to: CGPoint(x: 18, y: 5), control1: CGPoint(x: 12, y: 7), control2: CGPoint(x: 18, y: 11))
            }, fill { $0.addEllipse(in: CGRect(x: 3.5, y: 17.5, width: 5, height: 5)) },
                    p { $0.addEllipse(in: CGRect(x: 15.5, y: 1.5, width: 5, height: 5)) }]
        case .log:
            return [p { $0.addRoundedRect(in: CGRect(x: 4.5, y: 3, width: 15, height: 18), cornerSize: CGSize(width: 2.5, height: 2.5)) },
                    p { $0.move(to: CGPoint(x: 8, y: 8.5)); $0.addLine(to: CGPoint(x: 16, y: 8.5))
                        $0.move(to: CGPoint(x: 8, y: 12.5)); $0.addLine(to: CGPoint(x: 13, y: 12.5)) },
                    p { $0.move(to: CGPoint(x: 9, y: 16.5)); $0.addLine(to: CGPoint(x: 11, y: 18)); $0.addLine(to: CGPoint(x: 15.5, y: 14.5)) }]
        case .search:
            return [p { $0.addEllipse(in: CGRect(x: 4, y: 4, width: 12, height: 12)); $0.move(to: CGPoint(x: 14.5, y: 14.5)); $0.addLine(to: CGPoint(x: 20, y: 20)) }]
        case .close:
            return [p { $0.move(to: CGPoint(x: 6, y: 6)); $0.addLine(to: CGPoint(x: 18, y: 18)); $0.move(to: CGPoint(x: 18, y: 6)); $0.addLine(to: CGPoint(x: 6, y: 18)) }]
        case .back:
            return [p { $0.move(to: CGPoint(x: 15, y: 5)); $0.addLine(to: CGPoint(x: 8, y: 12)); $0.addLine(to: CGPoint(x: 15, y: 19)) }]
        case .forward:
            return [p { $0.move(to: CGPoint(x: 9, y: 5)); $0.addLine(to: CGPoint(x: 16, y: 12)); $0.addLine(to: CGPoint(x: 9, y: 19)) }]
        case .settings:
            return [p { $0.move(to: CGPoint(x: 4, y: 8)); $0.addLine(to: CGPoint(x: 20, y: 8)); $0.move(to: CGPoint(x: 4, y: 16)); $0.addLine(to: CGPoint(x: 20, y: 16)) },
                    fill { $0.addEllipse(in: CGRect(x: 12, y: 5, width: 6, height: 6)) },
                    fill { $0.addEllipse(in: CGRect(x: 6, y: 13, width: 6, height: 6)) }]
        case .play:
            return [fill { $0.move(to: CGPoint(x: 8, y: 5)); $0.addLine(to: CGPoint(x: 19, y: 12)); $0.addLine(to: CGPoint(x: 8, y: 19)); $0.closeSubpath() }]
        case .plus:
            return [p { $0.move(to: CGPoint(x: 12, y: 5)); $0.addLine(to: CGPoint(x: 12, y: 19)); $0.move(to: CGPoint(x: 5, y: 12)); $0.addLine(to: CGPoint(x: 19, y: 12)) }]
        case .share:
            return [p { $0.move(to: CGPoint(x: 8, y: 10)); $0.addLine(to: CGPoint(x: 6, y: 10)); $0.addLine(to: CGPoint(x: 6, y: 20))
                        $0.addLine(to: CGPoint(x: 18, y: 20)); $0.addLine(to: CGPoint(x: 18, y: 10)); $0.addLine(to: CGPoint(x: 16, y: 10)) },
                    p { $0.move(to: CGPoint(x: 12, y: 14)); $0.addLine(to: CGPoint(x: 12, y: 3)); head(&$0, tip: CGPoint(x: 12, y: 3), angle: up, length: 4.5) }]
        case .speaker, .speakerOff:
            var out = [p { $0.move(to: CGPoint(x: 4, y: 9.5)); $0.addLine(to: CGPoint(x: 7.5, y: 9.5)); $0.addLine(to: CGPoint(x: 12, y: 5.5))
                           $0.addLine(to: CGPoint(x: 12, y: 18.5)); $0.addLine(to: CGPoint(x: 7.5, y: 14.5)); $0.addLine(to: CGPoint(x: 4, y: 14.5)); $0.closeSubpath() }]
            if g == .speaker {
                out.append(p { $0.addArc(center: CGPoint(x: 13, y: 12), radius: 4.5, startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false)
                               $0.move(to: CGPoint(x: 13 + 8 * cos(-.pi / 4), y: 12 + 8 * sin(-.pi / 4)))
                               $0.addArc(center: CGPoint(x: 13, y: 12), radius: 8, startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false) })
            } else {
                out.append(p { $0.move(to: CGPoint(x: 15.5, y: 9.5)); $0.addLine(to: CGPoint(x: 20.5, y: 14.5)); $0.move(to: CGPoint(x: 20.5, y: 9.5)); $0.addLine(to: CGPoint(x: 15.5, y: 14.5)) })
            }
            return out
        case .check:
            return [p { $0.move(to: CGPoint(x: 5, y: 12.5)); $0.addLine(to: CGPoint(x: 10, y: 17.5)); $0.addLine(to: CGPoint(x: 19, y: 7)) }]
        case .locate:
            return [fill { $0.move(to: CGPoint(x: 12, y: 3)); $0.addLine(to: CGPoint(x: 19, y: 20)); $0.addLine(to: CGPoint(x: 12, y: 16))
                           $0.addLine(to: CGPoint(x: 5, y: 20)); $0.closeSubpath() }]

        case .straight:
            return [p { $0.move(to: CGPoint(x: 12, y: 21)); $0.addLine(to: CGPoint(x: 12, y: 3.5)); head(&$0, tip: CGPoint(x: 12, y: 3.5), angle: up, length: 6.5) }]
        case .turnLeft, .turnRight:
            let s: CGFloat = g == .turnLeft ? -1 : 1
            return [p { $0.move(to: CGPoint(x: 12 - 3 * s, y: 21)); $0.addLine(to: CGPoint(x: 12 - 3 * s, y: 13))
                        $0.addQuadCurve(to: CGPoint(x: 12 + 2 * s, y: 8), control: CGPoint(x: 12 - 3 * s, y: 8))
                        $0.addLine(to: CGPoint(x: 12 + 8.5 * s, y: 8)); head(&$0, tip: CGPoint(x: 12 + 8.5 * s, y: 8), angle: s < 0 ? left : right, length: 6) }]
        case .slightLeft, .slightRight:
            let s: CGFloat = g == .slightLeft ? -1 : 1
            return [p { $0.move(to: CGPoint(x: 12 - 2 * s, y: 21)); $0.addLine(to: CGPoint(x: 12 - 2 * s, y: 13))
                        $0.addLine(to: CGPoint(x: 12 + 6 * s, y: 5)); head(&$0, tip: CGPoint(x: 12 + 6 * s, y: 5), angle: s < 0 ? -3 * .pi / 4 : -.pi / 4, length: 6.5) }]
        case .uturn:
            return [p { $0.move(to: CGPoint(x: 16, y: 21)); $0.addLine(to: CGPoint(x: 16, y: 10))
                        $0.addArc(center: CGPoint(x: 12, y: 10), radius: 4, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
                        $0.addLine(to: CGPoint(x: 8, y: 17)); head(&$0, tip: CGPoint(x: 8, y: 17), angle: .pi / 2, length: 5.5) }]
        case .merge:
            return [p { $0.move(to: CGPoint(x: 12, y: 13)); $0.addLine(to: CGPoint(x: 12, y: 3.5)); head(&$0, tip: CGPoint(x: 12, y: 3.5), angle: up, length: 6) },
                    p { $0.move(to: CGPoint(x: 5, y: 21)); $0.addQuadCurve(to: CGPoint(x: 12, y: 13), control: CGPoint(x: 5, y: 15)) },
                    p { $0.move(to: CGPoint(x: 19, y: 21)); $0.addQuadCurve(to: CGPoint(x: 12, y: 13), control: CGPoint(x: 19, y: 15)) }]
        case .exitLeft, .exitRight:
            let s: CGFloat = g == .exitLeft ? -1 : 1
            return [p { $0.move(to: CGPoint(x: 12 - 3 * s, y: 21)); $0.addLine(to: CGPoint(x: 12 - 3 * s, y: 3)) },
                    p { $0.move(to: CGPoint(x: 12 - 3 * s, y: 15)); $0.addQuadCurve(to: CGPoint(x: 12 + 6 * s, y: 5), control: CGPoint(x: 12 + 5 * s, y: 13))
                        head(&$0, tip: CGPoint(x: 12 + 6 * s, y: 5), angle: up, length: 5.5) }]
        case .roundabout:
            // The roundabout sign: three arrows chasing each other counterclockwise around a circle.
            var arrows = Path()
            for k in 0..<3 {
                let from = Double(k) * 120 + 20, to = from + 80   // degrees, clockwise from the right, on screen
                arrows.addArc(center: CGPoint(x: 12, y: 12), radius: 7.5, startAngle: .degrees(-from), endAngle: .degrees(-to), clockwise: true)
                let end = -to * .pi / 180
                let tip = CGPoint(x: 12 + 7.5 * cos(end), y: 12 + 7.5 * sin(end))
                head(&arrows, tip: tip, angle: end - .pi / 2, length: 3.6)
            }
            return [Part(path: arrows)]
        case .arrive:
            return [p { $0.move(to: CGPoint(x: 6, y: 21)); $0.addLine(to: CGPoint(x: 6, y: 3)) },
                    fill { $0.move(to: CGPoint(x: 6, y: 4)); $0.addLine(to: CGPoint(x: 19, y: 8)); $0.addLine(to: CGPoint(x: 6, y: 12)); $0.closeSubpath() }]
        case .start:
            return [p { $0.addEllipse(in: CGRect(x: 6, y: 6, width: 12, height: 12)) }, fill { $0.addEllipse(in: CGRect(x: 9.5, y: 9.5, width: 5, height: 5)) }]

        case .school:
            // The school-zone sign's pentagon.
            return [p { $0.move(to: CGPoint(x: 12, y: 3)); $0.addLine(to: CGPoint(x: 20, y: 10)); $0.addLine(to: CGPoint(x: 20, y: 21))
                        $0.addLine(to: CGPoint(x: 4, y: 21)); $0.addLine(to: CGPoint(x: 4, y: 10)); $0.closeSubpath() }]
        case .crash, .offRoute:
            return [p { $0.move(to: CGPoint(x: 12, y: 3.5)); $0.addLine(to: CGPoint(x: 21.5, y: 20)); $0.addLine(to: CGPoint(x: 2.5, y: 20)); $0.closeSubpath()
                        $0.move(to: CGPoint(x: 12, y: 10)); $0.addLine(to: CGPoint(x: 12, y: 14)) },
                    fill { $0.addEllipse(in: CGRect(x: 10.8, y: 16, width: 2.4, height: 2.4)) }]
        case .railroad:
            return [p { $0.move(to: CGPoint(x: 4, y: 6)); $0.addLine(to: CGPoint(x: 20, y: 18)); $0.move(to: CGPoint(x: 20, y: 6)); $0.addLine(to: CGPoint(x: 4, y: 18)) }]
        case .sun:
            var rays = Path()
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                rays.move(to: CGPoint(x: 12 + 7 * cos(a), y: 12 + 7 * sin(a)))
                rays.addLine(to: CGPoint(x: 12 + 9.5 * cos(a), y: 12 + 9.5 * sin(a)))
            }
            return [p { $0.addEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8)) }, Part(path: rays)]
        case .moon:
            // A crescent: the outer edge of one circle, closed by the inner edge of a circle offset up and right.
            return [p {
                $0.move(to: CGPoint(x: 15.6, y: 4.2))
                $0.addArc(center: CGPoint(x: 12, y: 12), radius: 8.5, startAngle: .degrees(-65), endAngle: .degrees(5), clockwise: true)
                $0.addArc(center: CGPoint(x: 15, y: 9), radius: 6, startAngle: .degrees(60), endAngle: .degrees(-100), clockwise: false)
                $0.closeSubpath()
            }]
        case .waiting:
            return [p { $0.addEllipse(in: CGRect(x: 4, y: 4, width: 16, height: 16)); $0.move(to: CGPoint(x: 12, y: 8)); $0.addLine(to: CGPoint(x: 12, y: 12))
                        $0.addLine(to: CGPoint(x: 15, y: 14)) }]

        case .oneLane:
            return [p { $0.addEllipse(in: CGRect(x: 6, y: 6, width: 12, height: 12)) }]
        case .twoLane:
            return [p { $0.addEllipse(in: CGRect(x: 4, y: 4, width: 16, height: 16)) }, p { $0.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6)) }]
        case .highwayMerge:
            return parts(.merge)
        case .exitRamp:
            return parts(.exitRight)
        case .laneTurn:
            // Two lanes, and a turn arrow leaving the left one.
            return [p { $0.move(to: CGPoint(x: 12, y: 21)); $0.addLine(to: CGPoint(x: 12, y: 15)) },
                    p { $0.move(to: CGPoint(x: 7, y: 21)); $0.addLine(to: CGPoint(x: 7, y: 11))
                        $0.addQuadCurve(to: CGPoint(x: 2.5, y: 6.5), control: CGPoint(x: 7, y: 6.5)); head(&$0, tip: CGPoint(x: 2.5, y: 6.5), angle: left, length: 4) },
                    p { $0.move(to: CGPoint(x: 17, y: 21)); $0.addLine(to: CGPoint(x: 17, y: 4)); head(&$0, tip: CGPoint(x: 17, y: 4), angle: up, length: 4) }]
        case .fastRoad:
            return [p { $0.addArc(center: CGPoint(x: 12, y: 15), radius: 9, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false) },
                    p { $0.move(to: CGPoint(x: 12, y: 15)); $0.addLine(to: CGPoint(x: 17.5, y: 9)) }]

        case .handsOff:
            return [p { $0.addRoundedRect(in: CGRect(x: 7, y: 2.5, width: 10, height: 19), cornerSize: CGSize(width: 2.5, height: 2.5)) },
                    p { $0.move(to: CGPoint(x: 3, y: 21)); $0.addLine(to: CGPoint(x: 21, y: 3)) }]
        case .lock:
            return [p { $0.addRoundedRect(in: CGRect(x: 5, y: 10.5, width: 14, height: 10.5), cornerSize: CGSize(width: 2.5, height: 2.5)) },
                    p { $0.move(to: CGPoint(x: 8.5, y: 10.5)); $0.addLine(to: CGPoint(x: 8.5, y: 7.5))
                        $0.addArc(center: CGPoint(x: 12, y: 7.5), radius: 3.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                        $0.addLine(to: CGPoint(x: 15.5, y: 10.5)) }]
        }
    }
}

// MARK: - Lane arrows

/// A lane's arrows as they are painted on the road: one stem that branches toward each way the lane goes
/// ("↑→" is straight or right). An unknown lane is a short dash, never an arrow a driver might trust.
struct LaneMark: View {
    let label: String
    var size: CGFloat = 28
    var weight: CGFloat = 1.3

    var body: some View {
        Canvas { ctx, canvas in
            let k = canvas.width / 24
            let style = StrokeStyle(lineWidth: Size.stroke * weight * k, lineCap: .round, lineJoin: .round)
            ctx.stroke(Self.path(label).applying(CGAffineTransform(scaleX: k, y: k)), with: .foreground, style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func path(_ label: String) -> Path {
        var p = Path()
        let dirs = Set(label.compactMap { ch -> String? in
            switch ch {
            case "←", "↰": "left"
            case "→", "↱": "right"
            case "↖": "slightLeft"
            case "↗": "slightRight"
            case "↑": "straight"
            case "↩", "↶", "↺": "uturn"
            default: nil
            }
        })
        guard !dirs.isEmpty else {
            p.move(to: CGPoint(x: 8, y: 12)); p.addLine(to: CGPoint(x: 16, y: 12))
            return p
        }
        func head(_ tip: CGPoint, _ angle: Double) {
            for side in [-1.0, 1.0] {
                let a = angle + .pi + side * .pi / 4.2
                p.move(to: tip); p.addLine(to: CGPoint(x: tip.x + 5 * cos(a), y: tip.y + 5 * sin(a)))
            }
        }
        // The stem, from the bottom to where the branches leave it.
        p.move(to: CGPoint(x: 12, y: 22)); p.addLine(to: CGPoint(x: 12, y: dirs.contains("straight") ? 3 : 12))
        if dirs.contains("straight") { head(CGPoint(x: 12, y: 3), -.pi / 2) }
        if dirs.contains("left") {
            p.move(to: CGPoint(x: 12, y: 14)); p.addQuadCurve(to: CGPoint(x: 4, y: 8), control: CGPoint(x: 12, y: 8)); head(CGPoint(x: 4, y: 8), .pi)
        }
        if dirs.contains("right") {
            p.move(to: CGPoint(x: 12, y: 14)); p.addQuadCurve(to: CGPoint(x: 20, y: 8), control: CGPoint(x: 12, y: 8)); head(CGPoint(x: 20, y: 8), 0)
        }
        if dirs.contains("slightLeft") { p.move(to: CGPoint(x: 12, y: 13)); p.addLine(to: CGPoint(x: 6, y: 5)); head(CGPoint(x: 6, y: 5), -2.21) }
        if dirs.contains("slightRight") { p.move(to: CGPoint(x: 12, y: 13)); p.addLine(to: CGPoint(x: 18, y: 5)); head(CGPoint(x: 18, y: 5), -0.93) }
        if dirs.contains("uturn") {
            p.move(to: CGPoint(x: 12, y: 13)); p.addArc(center: CGPoint(x: 8.5, y: 10), radius: 3.5, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
            p.addLine(to: CGPoint(x: 5, y: 16)); head(CGPoint(x: 5, y: 16), .pi / 2)
        }
        return p
    }
}

// MARK: - Roundabout diagram

/// One roundabout as the driver meets it, heading up: the circle, the exits passed, and the way to the
/// driver's exit drawn in `go`.
struct RoundaboutMark: View {
    let shape: RoundaboutShape
    var size: CGFloat = 72
    var ink: Color = Palette.onDark

    var body: some View {
        Canvas { ctx, canvas in
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let r = canvas.width * 0.24
            let w = canvas.width * 0.075
            func point(_ angle: Double, _ radius: CGFloat) -> CGPoint {
                let a = (angle - 90) * .pi / 180
                return CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
            }
            let style = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
            // The circle and every leg, in ink.
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(ink.opacity(0.45)), style: style)
            for a in shape.passedAngles + [shape.exitAngle, 180] {
                var leg = Path(); leg.move(to: point(a, r)); leg.addLine(to: point(a, canvas.width * 0.48))
                ctx.stroke(leg, with: .color(ink.opacity(0.45)), style: style)
            }
            // The way through: in from the bottom, counterclockwise around, out at the exit.
            var way = Path()
            way.move(to: point(180, canvas.width * 0.48)); way.addLine(to: point(180, r))
            let sweep = (180 - shape.exitAngle + 360).truncatingRemainder(dividingBy: 360)
            let steps = 24
            for i in 1...steps { way.addLine(to: point(180 - sweep * Double(i) / Double(steps), r)) }
            let tip = point(shape.exitAngle, canvas.width * 0.46)
            way.addLine(to: tip)
            ctx.stroke(way, with: .color(Palette.go), style: StrokeStyle(lineWidth: w * 1.35, lineCap: .round, lineJoin: .round))
            let a = (shape.exitAngle - 90) * .pi / 180
            for side in [-1.0, 1.0] {
                var h = Path(); h.move(to: tip)
                let back = a + .pi + side * .pi / 4.2
                h.addLine(to: CGPoint(x: tip.x + w * 3 * cos(back), y: tip.y + w * 3 * sin(back)))
                ctx.stroke(h, with: .color(Palette.go), style: StrokeStyle(lineWidth: w * 1.35, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Roundabout, exit \(shape.exitNumber)")
    }
}

// MARK: - Signs Baxi shows as they appear on the road

/// The regulatory speed-limit sign: black on white with a black border, as on the road.
struct SpeedLimitSign: View {
    let mph: Int
    var body: some View {
        VStack(spacing: 0) {
            Text("SPEED\nLIMIT").font(Typeface.fixed(10, .bold)).multilineTextAlignment(.center)
            Text("\(mph)").font(Typeface.fixed(28, .extraBold)).monospacedDigit().contentTransition(.numericText(value: Double(mph)))
        }
        .foregroundStyle(Palette.ink)
        .frame(width: SignSize.width, height: SignSize.height)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: SignSize.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SignSize.innerCorner, style: .continuous)
                    .inset(by: SignSize.inset).stroke(Palette.ink, lineWidth: SignSize.border))
        .accessibilityElement()
        .accessibilityLabel("Speed limit \(mph)")
    }
}

/// The car's speed beside the limit. Amber (get ready) when more than 5 over.
struct SpeedReadout: View {
    let mph: Int
    let limit: Int?
    let night: Bool
    private var over: Bool { limit.map { Double(mph) > Double($0) + DriveHabits.overMph } ?? false }
    var body: some View {
        VStack(spacing: 0) {
            Text("\(mph)").font(Typeface.fixed(28, .extraBold)).monospacedDigit().contentTransition(.numericText(value: Double(mph)))
            Text("mph").font(Typeface.fixed(11, .bold))
        }
        .foregroundStyle(over ? Palette.ink : (night ? Palette.onDark : Palette.ink))
        .frame(width: SignSize.width, height: SignSize.height)
        .background(over ? Palette.ready : (night ? Palette.nightPanel : Palette.field),
                    in: RoundedRectangle(cornerRadius: SignSize.corner, style: .continuous))
        .animation(Motion.quick, value: mph)
        .animation(Motion.standard, value: over)
        .accessibilityElement()
        .accessibilityLabel(limit.map { "Speed \(mph), limit \($0)" } ?? "Speed \(mph)")
    }
}

/// The traffic signal: Baxi's mark. `lit` lights one lamp (0 red, 1 amber, 2 green); nil lights all three.
struct SignalMark: View {
    var size: CGFloat = 44
    var lit: Int? = nil
    var body: some View {
        let lamp = size * 0.26
        VStack(spacing: size * 0.06) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill([Palette.stop, Palette.ready, Palette.go][i])
                    .opacity(lit == nil || lit == i ? 1 : 0.18)
                    .frame(width: lamp, height: lamp)
            }
        }
        .padding(.vertical, size * 0.1)
        .frame(width: size * 0.46, height: size)
        .background(Palette.ink, in: Capsule())
        .accessibilityHidden(true)
    }
}
