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
