import SwiftUI

/// Optional identity fields for the official paper log, never sent to a routing provider.
struct DriverDetailsView: View {
    @AppStorage(OfficialLogPDF.driverNameKey) private var name = ""
    @AppStorage(OfficialLogPDF.licenseNumberKey) private var licenseNumber = ""

    var body: some View {
        Form {
            Section {
                TextField("Last, first, middle initial", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                TextField("Driver’s license number (DLN)", text: $licenseNumber)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            } header: {
                Text("Driver details")
            } footer: {
                Text("Saved on this device and included in shared PDFs. Both fields are optional; leave them blank to complete the printed form by hand.")
            }
            Section {
                Text("The export fills the official State Form 54706. Review all entries, then complete the applicable checkbox, affirmation and signatures on paper.")
                    .font(BaxiFont.callout)
                Link("Open the official blank form", destination: URL(string: "https://forms.in.gov/Download.aspx?id=9758")!)
            }
        }
        .scrollContentBackground(.hidden)
        .baxiPage()
        .navigationTitle("Driver details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
