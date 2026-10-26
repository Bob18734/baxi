import SwiftUI

/// The driver's name and license number for the official State Form 54706. Optional, saved on this phone.
struct DriverDetailsView: View {
    @AppStorage(OfficialLogPDF.driverNameKey) private var name = ""
    @AppStorage(OfficialLogPDF.licenseNumberKey) private var licenseNumber = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s12) {
                Text("Printed on the official log when you export it. Optional, and saved on this phone only.")
                    .role(.body).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Space.s8)
                FieldBox {
                    TextField("Last, first, middle initial", text: $name)
                        .role(.body).foregroundStyle(Palette.ink)
                        .textContentType(.name)
                        .accessibilityLabel("Driver's name, last, first, middle initial")
                }
                FieldBox {
                    TextField("Driver's license number", text: $licenseNumber)
                        .role(.body).foregroundStyle(Palette.ink)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Driver's license number")
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.s32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pageBackground()
    }
}

/// Driver details as a sheet, from the Log's export menu.
struct DriverDetailsSheet: View {
    var onDone: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Driver details", action: onDone)
            DriverDetailsView()
        }
        .pageBackground()
        .presentationDetents([.medium, .large])
    }
}
