# Official supervised-driving log export

Baxi bundles the original Indiana BMV State Form 54706, R5 / 8-24, downloaded October 22, 2026 from
https://forms.in.gov/Download.aspx?id=9758. The source PDF is unmodified at
`Baxi/Resources/Forms/54706.pdf`.

SHA-256: `1253b9464a751adcabe794aed794cd4273f66ceaaa065dbf64d7d2b8e7a8026c`.

The form contains 335 fields on two pages. Its four table columns have 31, 31, 23 and 23 rows.
OfficialLogPDF fills dates and day/night hours:minutes in chronological order, plus the optional driver
name and DLN on both pages. A drive uses one row, dated by its start in the export's local time zone,
matching the existing CSV. More than 108 drives adds another complete two-page PDF, shared together.
Separate files retain the official field tree and prevent cross-log edits from mirroring values.
PDFKit's merged-page output lost the canonical form fields in testing, so it is not used.
PDFKit also requests appearance regeneration despite incomplete default font resources, which made
Poppler display blank values. The exporter turns that flag off with an equal-length, uniquely matched
byte replacement, preserving the cross-reference offsets and existing appearance streams. If PDFKit
changes that serialization, export fails visibly instead of sharing an unchecked form.

The checkbox, affirmation, printed signer name, signature fields and signature dates stay blank.
The app does not certify the log. Users review and sign the paper form. The original form has no totals
field; totals remain in Baxi's Log screen and CSV rather than being added over the official layout.

Driver details are optional, stored in app UserDefaults, and included only in the exported PDF.
Settings and the Log export menu both offer a driver-details editor. Sharing a PDF shares these details.
Export failures clear share links and show a retry message; saved drives are retained.

The old LogPDF summary renderer remains in the source as a legacy implementation, but the Log screen
now calls OfficialLogPDF. No network is needed to create an export.

## Validation

OfficialLogPDFTests round-trip the output through PDFKit and cover each column boundary, the 108/109-row
pagination boundary, blank signatures, optional identity and template failures. They run serially on
the main actor because PDFKit uses platform UI services. On a sandboxed Mac, permit the test runner to
access macOS appearance/font services. Set `BAXI_PDF_SAMPLE` to an absolute PDF path to write the
109-drive review fixture using sample identity data (two files, suffixed .1.pdf and .2.pdf).
Tests independently inspect the canonical AcroForm tree through Core Graphics as well as PDFKit widgets.

Validation on Oct 22: 113 active tests pass, three opt-in live-network tests skip (116 discovered).
Unsigned iPhone and Mac Catalyst builds pass; design lint passes. Four sample PDF pages were rendered
with Poppler and visually inspected; pypdf independently verified 335 canonical fields per file,
appearance streams and all 109 unique drive dates. Driver-details screenshot is readable.
Acrobat editing, phone sharing/printing and on-device accessibility remain unverified.
