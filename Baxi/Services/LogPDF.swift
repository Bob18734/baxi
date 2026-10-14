#if canImport(UIKit)
import UIKit

/// Renders the drive log as a PDF laid out like Indiana's Log of Supervised Driving Practice
/// (State Form 54706, R5 / 8-24): date, drive time, day and night, with name, permit number and an
/// affirmation to sign. The BMV wants entries on the approved form, so the footer says to copy them over.
enum LogPDF {
    static func render(_ rows: [LogRow], timeZone: TimeZone = .current) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter
        let margin: CGFloat = 48
        let rowHeight: CGFloat = 20
        let sorted = rows.sorted { $0.start < $1.start }
        let perPage = 22   // leaves room for totals and the signature block above the footer
        let pages = max(1, Int((Double(sorted.count) / Double(perPage)).rounded(.up)))
        let date = DateFormatter()
        date.timeZone = timeZone; date.dateFormat = "MM/dd/yyyy"

        func draw(_ s: String, at p: CGPoint, size: CGFloat = 10, bold: Bool = false, color: UIColor = .black) {
            (s as NSString).draw(at: p, withAttributes: [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
                                                         .foregroundColor: color])
        }
        func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat = 0.5) {
            let path = UIBezierPath(); path.move(to: a); path.addLine(to: b); path.lineWidth = width
            UIColor.black.setStroke(); path.stroke()
        }
        let columns: [(String, CGFloat)] = [("Date", margin), ("Drive time (h:mm)", margin + 130),
                                            ("Day", margin + 280), ("Night", margin + 370), ("Route", margin + 450)]

        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            for p in 0..<pages {
                ctx.beginPage()
                var y = margin
                draw("Log of Supervised Driving Practice", at: CGPoint(x: margin, y: y), size: 16, bold: true)
                y += 22
                draw("Prepared by Baxi in the layout of Indiana State Form 54706 (R5 / 8-24). IC 9-24-3-2.5.", at: CGPoint(x: margin, y: y), size: 9, color: .darkGray)
                y += 26
                draw("Name of permit holder", at: CGPoint(x: margin, y: y), size: 9)
                line(CGPoint(x: margin + 110, y: y + 11), CGPoint(x: margin + 300, y: y + 11))
                draw("Permit number", at: CGPoint(x: margin + 315, y: y), size: 9)
                line(CGPoint(x: margin + 385, y: y + 11), CGPoint(x: page.width - margin, y: y + 11))
                y += 30
                for (title, x) in columns { draw(title, at: CGPoint(x: x, y: y), bold: true) }
                y += rowHeight - 4
                line(CGPoint(x: margin, y: y), CGPoint(x: page.width - margin, y: y), width: 1)
                y += 4
                for r in sorted.dropFirst(p * perPage).prefix(perPage) {
                    draw(date.string(from: r.start), at: CGPoint(x: columns[0].1, y: y))
                    draw(DriveLog.hm(r.minutes), at: CGPoint(x: columns[1].1, y: y))
                    draw(DriveLog.hm(r.dayMinutes), at: CGPoint(x: columns[2].1, y: y))
                    draw(DriveLog.hm(r.nightMinutes), at: CGPoint(x: columns[3].1, y: y))
                    draw(String(r.routeTitle.prefix(16)) + (r.manual ? " *" : ""), at: CGPoint(x: columns[4].1, y: y), size: 9, color: .darkGray)
                    y += rowHeight
                    line(CGPoint(x: margin, y: y - 3), CGPoint(x: page.width - margin, y: y - 3), width: 0.25)
                }
                if p == pages - 1 {
                    let t = DriveLog.totals(sorted)
                    y += 6
                    draw("Totals", at: CGPoint(x: columns[0].1, y: y), bold: true)
                    draw(DriveLog.hm(t.minutes), at: CGPoint(x: columns[1].1, y: y), bold: true)
                    draw(DriveLog.hm(t.dayMinutes), at: CGPoint(x: columns[2].1, y: y), bold: true)
                    draw(DriveLog.hm(t.nightMinutes), at: CGPoint(x: columns[3].1, y: y), bold: true)
                    y += 22
                    draw("Required: 50:00 total, at least 10:00 at night. Remaining: \(DriveLog.hm(t.minutesLeft)) total, \(DriveLog.hm(t.nightMinutesLeft)) night.",
                         at: CGPoint(x: margin, y: y), size: 9)
                    y += 30
                    draw("I affirm that the permit holder completed the supervised driving practice recorded above.", at: CGPoint(x: margin, y: y), size: 9)
                    y += 30
                    line(CGPoint(x: margin, y: y), CGPoint(x: margin + 260, y: y))
                    line(CGPoint(x: margin + 300, y: y), CGPoint(x: page.width - margin, y: y))
                    draw("Signature of supervising driver", at: CGPoint(x: margin, y: y + 3), size: 8, color: .darkGray)
                    draw("Date", at: CGPoint(x: margin + 300, y: y + 3), size: 8, color: .darkGray)
                }
                let foot = "Night is counted from sunset to sunrise. * entered by hand. Copy these entries onto the official form from forms.in.gov and sign it there. Page \(p + 1) of \(pages)."
                (foot as NSString).draw(in: CGRect(x: margin, y: page.height - margin - 24, width: page.width - 2 * margin, height: 30),
                                        withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray])
            }
        }
    }
}
#endif
