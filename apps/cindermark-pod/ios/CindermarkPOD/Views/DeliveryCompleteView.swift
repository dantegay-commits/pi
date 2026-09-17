import SwiftUI

/// The confirmation the driver sees right after a signature, before walking back
/// to the van.
///
/// Shown in place of the signing screen rather than as a sheet over it: a sheet
/// presented from a full-screen cover's dismissal is a race, and the one time it
/// loses is the one time the driver does not find out whether the receipt sent.
struct DeliveryCompleteView: View {
   let outcome: DeliveryOutcome
   let onDone: () -> Void

   @EnvironmentObject private var archive: ShippedArchive

   var body: some View {
      ScrollView {
         VStack(spacing: 22) {
            Image(systemName: "checkmark.seal.fill")
               .font(.system(size: 60))
               .foregroundStyle(BrandColor.ember)
               .padding(.top, 20)

            VStack(spacing: 6) {
               Text("Delivery recorded")
                  .font(.title.weight(.bold))
               Text(outcome.delivery.record.orderNumber)
                  .font(.title3)
                  .foregroundStyle(.secondary)
            }

            statusCard

            VStack(alignment: .leading, spacing: 6) {
               SectionHeading(title: "Filed on this iPad")
               Text(outcome.delivery.pdfRelativePath)
                  .font(.system(.footnote, design: .monospaced))
                  .foregroundStyle(.secondary)
                  .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PDFPreview(url: archive.pdfURL(for: outcome.delivery))
               .frame(minHeight: 420)
               .clipShape(RoundedRectangle(cornerRadius: 12))
         }
         .padding(22)
         .frame(maxWidth: 720)
         .frame(maxWidth: .infinity)
      }
      .background(BrandColor.paper)
      .navigationTitle("Signed")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
         ToolbarItem(placement: .primaryAction) {
            ShareLink(item: archive.pdfURL(for: outcome.delivery)) {
               Label("Share", systemImage: "square.and.arrow.up")
            }
         }
         ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: onDone)
               .fontWeight(.semibold)
         }
      }
   }

   @ViewBuilder private var statusCard: some View {
      VStack(alignment: .leading, spacing: 10) {
         if let result = outcome.uploadResult {
            if result.emailed, let address = result.emailedTo, !address.isBlank {
               Label("Receipt emailed to \(address)", systemImage: "envelope.badge.fill")
                  .foregroundStyle(.green)
            } else if result.duplicate {
               Label("Already on file at the CINDERMARK site", systemImage: "checkmark.circle")
                  .foregroundStyle(.secondary)
            } else {
               Label("Filed on the CINDERMARK site", systemImage: "checkmark.circle.fill")
                  .foregroundStyle(.green)
               Text(result.message?.isBlank == false
                  ? result.message ?? ""
                  : "No email was sent. Check the email settings on the site if the customer expects one.")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
            }
         } else {
            Label("Saved on this iPad, not sent yet", systemImage: "clock.arrow.circlepath")
               .foregroundStyle(BrandColor.ember)
            Text(outcome.uploadError ?? "It will send automatically once there is signal.")
               .font(.footnote)
               .foregroundStyle(.secondary)
         }

         if let coordinates = outcome.delivery.record.location.coordinateString {
            Label(coordinates, systemImage: "location.fill")
               .font(.footnote)
               .foregroundStyle(.secondary)
         } else {
            Label("No location was recorded", systemImage: "location.slash")
               .font(.footnote)
               .foregroundStyle(BrandColor.ember)
         }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
   }
}
