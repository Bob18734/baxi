import Foundation
import PDFKit
import CoreGraphics
import Testing
@testable import Baxi

@Suite(.serialized)
@MainActor
struct OfficialLogPDFTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func rows(_ count: Int) -> [LogRow] {
        (0..<count).map { i in
            let start = Date(timeIntervalSince1970: 1_760_011_200 + Double(i) * 86400)
            return LogRow(start: start, end: start.addingTimeInterval(4500), dayMinutes: 60,
                          nightMinutes: 15, routeTitle: "Sample drive", distanceMeters: 1000, manual: false)
        }
    }

    private func fields(_ document: PDFDocument) -> [String: PDFAnnotation] {
        Dictionary(uniqueKeysWithValues: (0..<document.pageCount).flatMap {
            document.page(at: $0)!.annotations.compactMap { a in a.fieldName.map { ($0, a) } }
        })
    }

    /// PDFKit widgets can round-trip even when the canonical AcroForm field tree is lost.
    /// Read that tree independently through Core Graphics before accepting an export.
    private func verifyCanonicalFields(_ data: Data) throws {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let catalog = try #require(document.catalog)
        var form: CGPDFDictionaryRef?
        #expect(CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form))
        var array: CGPDFArrayRef?
        let formDictionary = try #require(form)
        var regenerate = true
        #expect(CGPDFDictionaryGetBoolean(formDictionary, "NeedAppearances", &regenerate))
        #expect(!regenerate)
        #expect(CGPDFDictionaryGetArray(formDictionary, "Fields", &array))
        let canonical = try #require(array)
        #expect(CGPDFArrayGetCount(canonical) == 335)
        let widgets = fields(try #require(PDFDocument(data: data)))
        for index in 0..<CGPDFArrayGetCount(canonical) {
            var field: CGPDFDictionaryRef?
            #expect(CGPDFArrayGetDictionary(canonical, index, &field))
            let dictionary = try #require(field)
            var name: CGPDFStringRef?, value: CGPDFStringRef?
            #expect(CGPDFDictionaryGetString(dictionary, "T", &name))
            let fieldName = try #require(name)
            let key = try #require(CGPDFStringCopyTextString(fieldName)) as String
            if CGPDFDictionaryGetString(dictionary, "V", &value), let value {
                let stored = try #require(CGPDFStringCopyTextString(value)) as String
                #expect(stored == (widgets[key]?.widgetStringValue ?? ""))
            }
        }
    }

    @Test func fillsOfficialFormAndLeavesSignaturesBlank() throws {
        let data = try OfficialLogPDF.render(rows(1), driver: .init(name: "Sample, Alex Q", licenseNumber: "1234567890"), timeZone: utc)
        let doc = try #require(PDFDocument(data: data))
        try verifyCanonicalFields(data)
        #expect(doc.pageCount == 2)
        let f = fields(doc)
        #expect(f["Driver Name last first middle initial"]?.widgetStringValue == "Sample, Alex Q")
        #expect(f["Drivers License Number DLN_2"]?.widgetStringValue == "1234567890")
        #expect(f["DAYRow1"]?.widgetStringValue == "1:00")
        #expect(f["NIGHTRow1"]?.widgetStringValue == "0:15")
        #expect(f["Signature of Applicant"]?.widgetStringValue?.isEmpty != false)
        #expect(f["Printed Name"]?.widgetStringValue?.isEmpty != false)
        #expect(f["DATE mmddyyyyRow2"]?.widgetStringValue?.isEmpty != false)
    }

    @Test(arguments: [0, 31, 32, 62, 63, 85, 86, 108, 109])
    func paginatesEveryColumnWithoutLostOrMirroredRows(_ count: Int) throws {
        let forms = try OfficialLogPDF.renderForms(rows(count).reversed(), timeZone: utc)
        #expect(forms.count == (count > 108 ? 2 : 1))
        var dates: [String] = []
        for data in forms {
            try verifyCanonicalFields(data)
            let doc = try #require(PDFDocument(data: data))
            #expect(doc.pageCount == 2)
            dates += fields(doc).filter { $0.key.contains("DATE mmddyyyyRow") }
                .compactMap { $0.value.widgetStringValue }.filter { !$0.isEmpty }
        }
        #expect(dates.count == count)
        #expect(Set(dates).count == count)
    }

    @Test func reportsMissingTemplate() {
        #expect(throws: OfficialLogPDF.ExportError.self) {
            try OfficialLogPDF.render([], templateURL: nil)
        }
    }

    @Test func rejectsInvalidMinutesAndClippedIdentity() {
        let row = rows(1)[0]
        let invalid = LogRow(start: row.start, end: row.end, dayMinutes: -1, nightMinutes: 1,
                             routeTitle: "Invalid", distanceMeters: 0, manual: true)
        #expect(throws: OfficialLogPDF.ExportError.self) { try OfficialLogPDF.render([invalid]) }
        #expect(throws: OfficialLogPDF.ExportError.self) {
            try OfficialLogPDF.render([], driver: .init(name: String(repeating: "W", count: 500)))
        }
    }

    @Test func datesUseTheRequestedTimeZoneAndTimeUsesHoursMinutes() throws {
        let start = Date(timeIntervalSince1970: 0)
        let row = LogRow(start: start, end: start.addingTimeInterval(3900), dayMinutes: 65, nightMinutes: 0,
                         routeTitle: "Test", distanceMeters: 0, manual: true)
        let data = try OfficialLogPDF.render([row], timeZone: TimeZone(secondsFromGMT: -3600)!)
        let f = fields(try #require(PDFDocument(data: data)))
        #expect(f["DATE mmddyyyyRow1"]?.widgetStringValue == "12/31/1969")
        #expect(f["DAYRow1"]?.widgetStringValue == "1:05")
        #expect(f["NIGHTRow1"]?.widgetStringValue == "0:00")
    }

    @Test func writesReviewFixtureWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["BAXI_PDF_SAMPLE"] else { return }
        let forms = try OfficialLogPDF.renderForms(rows(109), driver: .init(name: "Sample, Alex Q", licenseNumber: "SAMPLE-ONLY"), timeZone: utc)
        for (index, data) in forms.enumerated() {
            let url = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("\(index + 1).pdf")
            try data.write(to: url)
        }
    }
}

struct AppearanceFlagTests {
    @Test func theFlagIsTurnedOffWithoutMovingBytes() {
        let data = Data("<< /AcroForm << /NeedAppearances true >> /Fields [] >>".utf8)
        let out = OfficialLogPDF.preserveAppearances(data)
        #expect(out.count == data.count)
        #expect(String(decoding: out, as: UTF8.self).contains("/NeedAppearances false>>"))
    }

    @Test func anUnknownSerializationIsSharedAsWritten() {
        let data = Data("<< /AcroForm << /NeedAppearances true /DA (x) >> >>".utf8)
        #expect(OfficialLogPDF.preserveAppearances(data) == data)
    }
}
