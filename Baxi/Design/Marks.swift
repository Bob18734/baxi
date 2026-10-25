import SwiftUI

// Drawn marks shared by the screens: road-sign shapes, the traffic light, lane arrows, the hours ring.

/// The school-zone sign outline (MUTCD S1-1 is a pentagon, point up).
struct Pentagon: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.42))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.42))
            p.closeSubpath()
        }
    }
}

/// A warning-sign diamond.
struct Diamond: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.closeSubpath()
        }
    }
}

/// A small upright traffic light, the mark next to the light count.
struct TrafficLightMark: View {
    var size: CGFloat = 14
    var body: some View {
        VStack(spacing: size * 0.22) { // design-lint:allow drawn to the mark's own size
            Circle().fill(BaxiColor.stop)
            Circle().fill(BaxiColor.warning)
            Circle().fill(Color(red: 0.2, green: 0.8, blue: 0.4)) // design-lint:allow the green lamp, not a UI color
        }
        .frame(width: size, height: size * 3.5)
        .padding(size * 0.28)
        .background(BaxiColor.signInk, in: RoundedRectangle(cornerRadius: size * 0.5, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A US speed limit sign (MUTCD R2-1), lettered in Overpass like the real sign's Highway Gothic.
struct SpeedLimitSign: View {
    let mph: Int
    var scale: CGFloat = 1
    var body: some View {
        VStack(spacing: 0) {
            Text("SPEED\nLIMIT").font(BaxiFont.signFace(10.5 * scale)).multilineTextAlignment(.center).lineSpacing(-2 * scale)
            Text("\(mph)").font(BaxiFont.signFace(30 * scale)).monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(BaxiColor.signInk)
        .frame(width: 60 * scale, height: 74 * scale)
        .background(.white, in: RoundedRectangle(cornerRadius: 7 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5 * scale, style: .continuous).inset(by: 3 * scale).stroke(BaxiColor.signInk, lineWidth: 2 * scale))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .accessibilityElement()
        .accessibilityLabel("Speed limit \(mph)")
    }
}

/// The school-zone chip: a small yellow-green pentagon with a label.
struct SchoolZoneChip: View {
    var body: some View {
        HStack(spacing: BaxiSpace.sm) {
            Pentagon().fill(BaxiColor.signInk).frame(width: 16, height: 18)
                .overlay(Image(systemName: "figure.walk").font(BaxiFont.signFace(10)).foregroundStyle(BaxiColor.school).offset(y: 2))
                .accessibilityHidden(true)
            Text("School zone").font(BaxiFont.headline)
        }
        .foregroundStyle(BaxiColor.signInk)
        .padding(.horizontal, BaxiSpace.md).padding(.vertical, BaxiSpace.sm)
        .background(BaxiColor.school, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

/// The crash-corridor chip: an orange diamond with a label.
struct CrashChip: View {
    var body: some View {
        HStack(spacing: BaxiSpace.sm) {
            Diamond().fill(BaxiColor.signInk).frame(width: 18, height: 18)
                .overlay(Text("!").font(BaxiFont.signFace(12)).foregroundStyle(BaxiColor.caution))
                .accessibilityHidden(true)
            Text("Crash-heavy road").font(BaxiFont.headline)
        }
        .foregroundStyle(BaxiColor.signInk)
        .padding(.horizontal, BaxiSpace.md).padding(.vertical, BaxiSpace.sm)
        .background(BaxiColor.caution, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

/// One lane's arrows, drawn from the label CueListBuilder gives it ("←", "↑", "↑→", "" when unknown).
/// Arrows shrink to fit narrow lanes (five or more).
struct LaneArrows: View {
    let label: String
    var size: CGFloat = 24
    var body: some View {
        HStack(spacing: -size * 0.25) { // design-lint:allow overlaps the arrows of a shared lane
            ForEach(Array(Self.symbols(for: label).enumerated()), id: \.offset) { _, s in
                Image(systemName: s).font(.system(size: size, weight: .heavy)) // design-lint:allow drawn mark, sized by its lane
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }

    static func symbols(for label: String) -> [String] {
        let out = label.compactMap { ch -> String? in
            switch ch {
            case "←", "↰": "arrow.turn.up.left"
            case "→", "↱": "arrow.turn.up.right"
            case "↖": "arrow.up.left"
            case "↗": "arrow.up.right"
            case "↑": "arrow.up"
            case "↶", "↺": "arrow.uturn.down"
            default: nil
            }
        }
        // No lane data: a neutral dash, never an arrow the driver might trust.
        return out.isEmpty ? ["minus"] : out
    }
}

/// Hours toward a goal as a ring, with the number in sign lettering.
struct HoursRing: View {
    let title: String
    let minutes: Int
    let goalMinutes: Int
    var tint: Color = BaxiColor.accent
    var diameter: CGFloat = 104

    private var fraction: Double { min(1, Double(minutes) / Double(max(goalMinutes, 1))) }

    var body: some View {
        VStack(spacing: BaxiSpace.sm) {
            ZStack {
                Circle().stroke(BaxiColor.sunken, lineWidth: 11)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: fraction)
                VStack(spacing: 0) {
                    Text(DriveLog.hm(minutes)).font(BaxiFont.numberSmall).foregroundStyle(BaxiColor.ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    Text("of \(goalMinutes / 60) h").font(BaxiFont.caption).foregroundStyle(BaxiColor.inkFaint)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .frame(width: diameter, height: diameter)
            Text(title).font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(DriveLog.hm(minutes)) of \(goalMinutes / 60) hours")
    }
}

/// A roundabout seen from above, the way the driver meets it: entry at the bottom, the circle, the exits
/// passed (short and faint), and the path to the driver's exit drawn in yellow, counterclockwise as in the US.
struct RoundaboutGlyph: View {
    let shape: RoundaboutShape
    var size: CGFloat = 64

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let ring = sz.width * 0.24, arm = sz.width * 0.48
            func point(_ compass: Double, _ r: CGFloat) -> CGPoint {
                let a = compass * .pi / 180
                return CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a)))
            }
            let faint = GraphicsContext.Shading.color(.white.opacity(0.45))
            let line = StrokeStyle(lineWidth: sz.width * 0.07, lineCap: .round, lineJoin: .round)
            // Circle and the exits passed.
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)), with: faint, style: line)
            for a in shape.passedAngles {
                var p = Path(); p.move(to: point(a, ring)); p.addLine(to: point(a, arm * 0.85))
                ctx.stroke(p, with: faint, style: line)
            }
            // The driver's path: up the entry, around counterclockwise, out the exit.
            let sweep = RoundaboutDiagram.normalized(180 - shape.exitAngle)
            var path = Path()
            path.move(to: point(180, arm))
            path.addLine(to: point(180, ring))
            let steps = max(2, Int((sweep == 0 ? 360 : sweep) / 10))
            for i in 1...steps { path.addLine(to: point(180 - (sweep == 0 ? 360 : sweep) * Double(i) / Double(steps), ring)) }
            let tip = point(shape.exitAngle, arm)
            path.addLine(to: tip)
            ctx.stroke(path, with: .color(BaxiColor.warning), style: StrokeStyle(lineWidth: sz.width * 0.1, lineCap: .round, lineJoin: .round))
            // Arrowhead at the exit.
            let back = point(shape.exitAngle, arm * 0.72), a = shape.exitAngle * .pi / 180
            let side = CGVector(dx: CGFloat(cos(a)) * sz.width * 0.1, dy: CGFloat(sin(a)) * sz.width * 0.1)
            var head = Path()
            head.move(to: CGPoint(x: tip.x + (tip.x - back.x) * 0.25, y: tip.y + (tip.y - back.y) * 0.25))
            head.addLine(to: CGPoint(x: back.x + side.dx, y: back.y + side.dy))
            head.addLine(to: CGPoint(x: back.x - side.dx, y: back.y - side.dy))
            head.closeSubpath()
            ctx.fill(head, with: .color(BaxiColor.warning))
            // The exit number in the middle.
            ctx.draw(Text("\(shape.exitNumber)").font(BaxiFont.signFace(size * 0.26)).foregroundStyle(.white), at: c)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Roundabout, exit \(shape.exitNumber)")
    }
}

/// The railroad-crossing chip: a white crossbuck on a round yellow sign.
struct RailChip: View {
    var body: some View {
        HStack(spacing: BaxiSpace.sm) {
            Text("RR").font(BaxiFont.signFace(10)).foregroundStyle(BaxiColor.signInk)
                .frame(width: 20, height: 20).background(.white, in: Circle())
                .overlay(Circle().stroke(BaxiColor.signInk, lineWidth: 1.5))
                .accessibilityHidden(true)
            Text("Railroad crossing").font(BaxiFont.headline)
        }
        .foregroundStyle(BaxiColor.signInk)
        .padding(.horizontal, BaxiSpace.md).padding(.vertical, BaxiSpace.sm)
        .background(BaxiColor.warning, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

/// The low-sun chip.
struct GlareChip: View {
    var body: some View {
        Label("Low sun ahead", systemImage: "sun.horizon.fill").font(BaxiFont.headline)
            .foregroundStyle(BaxiColor.signInk)
            .padding(.horizontal, BaxiSpace.md).padding(.vertical, BaxiSpace.sm)
            .background(BaxiColor.warning, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

/// The car's speed beside the speed-limit sign, like a speedometer readout. Orange when more than 5 over.
struct SpeedPill: View {
    let mph: Int
    let limit: Int?
    var scale: CGFloat = 1
    private var over: Bool { limit.map { Double(mph) > Double($0) + DriveHabits.overMph } ?? false }
    var body: some View {
        VStack(spacing: 0) {
            Text("\(mph)").font(BaxiFont.signFace(30 * scale)).monospacedDigit()
                .contentTransition(.numericText(value: Double(mph)))
            Text("MPH").font(BaxiFont.signFace(10.5 * scale))
        }
        .foregroundStyle(over ? BaxiColor.signInk : BaxiColor.ink)
        .frame(width: 60 * scale, height: 74 * scale)
        .background(over ? AnyShapeStyle(BaxiColor.caution) : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: BaxiRadius.md * scale, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .animation(.snappy, value: mph)
        .animation(.smooth, value: over)
        .accessibilityElement()
        .accessibilityLabel(limit.map { "Speed \(mph), limit \($0)" } ?? "Speed \(mph)")
    }
}

/// A drive's 0 to 100 habit score in a ring.
struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 84
    @State private var shown = 0.0
    var body: some View {
        ZStack {
            Circle().stroke(BaxiColor.sunken, lineWidth: size * 0.1)
            Circle().trim(from: 0, to: shown).stroke(BaxiColor.accent, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)").font(BaxiFont.number).foregroundStyle(BaxiColor.ink).monospacedDigit()
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.smooth(duration: 0.9).delay(0.2)) { shown = Double(score) / 100 } }
        .accessibilityElement()
        .accessibilityLabel("Score \(score) out of 100")
    }
}

/// A skill's level as four segments, filled up to `level`.
struct LevelBar: View {
    let level: Int
    var tint: Color = BaxiColor.sign
    var body: some View {
        HStack(spacing: BaxiSpace.xs) {
            ForEach(1...4, id: \.self) { i in
                Capsule().fill(i <= level ? tint : BaxiColor.sunken).frame(height: 8)
            }
        }
        .animation(.snappy, value: level)
        .accessibilityHidden(true)
    }
}

/// A small ring for one skill's progress toward its goal.
struct SkillRing: View {
    let fraction: Double
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            Circle().stroke(BaxiColor.sunken, lineWidth: 4)
            Circle().trim(from: 0, to: min(1, fraction)).stroke(BaxiColor.sign, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}
