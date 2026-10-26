import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
private typealias FormFont = UIFont
#else
import AppKit
private typealias FormFont = NSFont
#endif

/// Fills the bundled, unmodified Indiana State Form 54706 (R5 / 8-24).
/// Each additional log is a separate two-page PDF, preserving its complete form field tree.
enum OfficialLogPDF {
    static let rowsPerForm = 108
    static let driverNameKey = "logDriverName"
    static let licenseNumberKey = "logLicenseNumber"

    struct Driver: Equatable {
        var name = ""
        var licenseNumber = ""
    }

    enum ExportError: LocalizedError {
        case missingTemplate, invalidTemplate, invalidRow, cannotWrite, tooManyRows, textTooLong
        var errorDescription: String? {
            switch self {
            case .missingTemplate: "The official form is missing. Reinstall Baxi and try again."
            case .invalidTemplate: "The official form could not be read. Your drives are still saved."
            case .invalidRow: "A drive has invalid times or minutes. Check the log before exporting."
            case .cannotWrite: "The filled form could not be saved as a PDF. Your drives are still saved."
            case .tooManyRows: "This form holds 108 drives. Export the complete log as multiple forms."
            case .textTooLong: "Driver details are too long to fit the form. Shorten them or leave them blank to fill by hand."
            }
        }
    }

    static func renderForms(_ rows: [LogRow], driver: Driver = Driver(), timeZone: TimeZone = .current) throws -> [Data] {
        let sorted = rows.sorted { $0.start < $1.start }
        return try (0..<max(1, (sorted.count + rowsPerForm - 1) / rowsPerForm)).map { batch in
            try render(Array(sorted.dropFirst(batch * rowsPerForm).prefix(rowsPerForm)), driver: driver, timeZone: timeZone)
        }
    }

    static func rowFields(_ index: Int) -> (date: String, day: String, night: String) {
        precondition((0..<rowsPerForm).contains(index))
        let row: Int, suffix: String
        switch index {
        case 0..<31: row = index + 1; suffix = ""
        case 31..<62: row = index - 30; suffix = "_2"
        case 62..<85: row = index - 61; suffix = "_3"
        default: row = index - 84; suffix = "_4"
        }
        return ("DATE mmddyyyyRow\(row)\(suffix)", "DAYRow\(row)\(suffix)", "NIGHTRow\(row)\(suffix)")
    }

    static func render(_ rows: [LogRow], driver: Driver = Driver(), timeZone: TimeZone = .current,
                       templateURL: URL? = Bundle.baxi.url(forResource: "54706", withExtension: "pdf")) throws -> Data {
        guard let templateURL else { throw ExportError.missingTemplate }
        guard rows.count <= rowsPerForm else { throw ExportError.tooManyRows }
        guard rows.allSatisfy({ $0.dayMinutes >= 0 && $0.nightMinutes >= 0 && $0.end >= $0.start
            && $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite }) else {
            throw ExportError.invalidRow
        }
        let sorted = rows.sorted { $0.start < $1.start }
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.calendar = Calendar(identifier: .gregorian)
        date.timeZone = timeZone
        date.dateFormat = "MM/dd/yyyy"
        do {
            guard let form = PDFDocument(url: templateURL), form.pageCount == 2,
                  !form.isLocked || form.unlock(withPassword: "") else { throw ExportError.invalidTemplate }
            var fields: [String: PDFAnnotation] = [:]
            for pageIndex in 0..<form.pageCount {
                guard let page = form.page(at: pageIndex) else { throw ExportError.invalidTemplate }
                for annotation in page.annotations {
                    guard let name = annotation.fieldName else { continue }
                    guard fields[name] == nil else { throw ExportError.invalidTemplate }
                    fields[name] = annotation
                }
            }
            func fill(_ name: String, _ value: String) throws {
                guard let field = fields[name], field.widgetFieldType == .text else { throw ExportError.invalidTemplate }
                // Fit long names without clipping; leave the PDF editable for review.
                var size: CGFloat = 10
                while size > 5 && (value as NSString).size(withAttributes: [.font: FormFont(name: "Helvetica", size: size)!]).width > field.bounds.width - 4 {
                    size -= 0.5
                }
                guard !value.contains(where: { $0.isNewline }),
                      (value as NSString).size(withAttributes: [.font: FormFont(name: "Helvetica", size: size)!]).width <= field.bounds.width - 4 else {
                    throw ExportError.textTooLong
                }
                field.font = FormFont(name: "Helvetica", size: size)!
                field.fontColor = .black
                field.widgetStringValue = value
            }
            for suffix in ["", "_2"] {
                try fill("Driver Name last first middle initial" + suffix, driver.name)
                try fill("Drivers License Number DLN" + suffix, driver.licenseNumber)
            }
            // Validate all row fields, including unused ones, so a changed template fails visibly.
            for index in 0..<rowsPerForm {
                let names = rowFields(index)
                for name in [names.date, names.day, names.night] {
                    guard fields[name]?.widgetFieldType == .text else { throw ExportError.invalidTemplate }
                }
            }
            for (index, row) in sorted.enumerated() {
                let names = rowFields(index)
                try fill(names.date, date.string(from: row.start))
                try fill(names.day, DriveLog.hm(row.dayMinutes))
                try fill(names.night, DriveLog.hm(row.nightMinutes))
            }
            guard let data = form.dataRepresentation() else { throw ExportError.cannotWrite }
            return preserveAppearances(data)
        }
    }

    /// PDFKit writes complete appearance streams, but requests that viewers regenerate them using an incomplete
    /// default-font dictionary; Poppler-based viewers then show blank entries. Turn that request off without
    /// shifting any byte offset in PDFKit's cross-reference table (the replacement is the same length).
    /// If this PDFKit wrote the flag some other way, the form is shared as written: it is complete and fills
    /// correctly in Apple's and Adobe's viewers, and a form that can't be exported at all is worse than one a rare
    /// viewer shows blank. (Changed Oct 25 after the phone's PDFKit refused the export this way.)
    static func preserveAppearances(_ data: Data) -> Data {
        for (marker, replacement) in [("/NeedAppearances true >>", "/NeedAppearances false>>"),
                                      ("/NeedAppearances true  >>", "/NeedAppearances false >>"),
                                      ("/NeedAppearances true\n>>", "/NeedAppearances false>>")] {
            let m = Data(marker.utf8), r = Data(replacement.utf8)
            guard m.count == r.count, let range = data.range(of: m),
                  data.range(of: m, in: range.upperBound..<data.endIndex) == nil else { continue }
            var result = data
            result.replaceSubrange(range, with: r)
            return result
        }
        return data
    }
}
