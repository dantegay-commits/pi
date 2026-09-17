import SwiftUI

/// An archived proof of delivery: what was recorded, where it went, and the
/// document itself.
struct DeliveryDetailView: View {
   let delivery: ArchivedDelivery

   @EnvironmentObject private var archive: ShippedArchive
   @EnvironmentObject private var outbox: OutboxQueue
   @State private var isRetrying = false

   private var current: ArchivedDelivery {
      archive.delivery(id: delivery.id) ?? delivery
   }

   private var record: DeliveryRecord { current.record }

   var body: some View {
      ScrollView {
         VStack(alignment: .leading, spacing: 22) {
            header
            deliveryStatus
            auditBlock
            documentPreview
         }
         .padding(22)
      }
      .background(BrandColor.paper)
      .toolbar {
         ToolbarItem(placement: .primaryAction) {
            ShareLink(item: archive.pdfURL(for: current)) {
               Label("Share", systemImage: "square.and.arrow.up")
            }
         }
      }
   }

   private var header: some View {
      VStack(alignment: .leading, spacing: 6) {
         SectionHeading(title: "Signed \(record.signedAt.formatted(date: .abbreviated, time: .shortened))")
         Text(record.orderNumber.isBlank ? "No order number" : record.orderNumber)
            .font(.largeTitle.weight(.bold))
         Text(record.customer.displayName)
            .font(.title3)
         Text("Signed by \(record.signer.printedName) - \(record.signer.relationshipDisplay)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
         if record.hasExceptions {
            StatusPill(
               title: "\(record.exceptions.count) exception\(record.exceptions.count == 1 ? "" : "s")",
               systemImage: "exclamationmark.triangle.fill",
               tint: BrandColor.ember
            )
         }
      }
   }

   private var deliveryStatus: some View {
      VStack(alignment: .leading, spacing: 10) {
         SectionHeading(title: "Customer copy")
         switch current.uploadState {
         case .uploaded:
            Label(
               current.emailedTo.map { "Emailed to \($0)" } ?? "Filed on the CINDERMARK site",
               systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
         case .pending:
            Label("Waiting to send - it will go out automatically", systemImage: "clock.arrow.circlepath")
               .foregroundStyle(.secondary)
         case .failed:
            VStack(alignment: .leading, spacing: 8) {
               Label("Not sent yet", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                  .foregroundStyle(BrandColor.ember)
               if let error = current.lastUploadError {
                  Text(error)
                     .font(.footnote)
                     .foregroundStyle(.secondary)
               }
               Text("Attempt \(current.uploadAttempts). The local copy in Shipped is complete either way.")
                  .font(.caption)
                  .foregroundStyle(.tertiary)
            }
         }

         if current.uploadState != .uploaded {
            Button {
               Task {
                  isRetrying = true
                  await outbox.retryNow(current)
                  isRetrying = false
               }
            } label: {
               if isRetrying {
                  ProgressView()
               } else {
                  Label("Send now", systemImage: "paperplane")
               }
            }
            .buttonStyle(.bordered)
            .disabled(isRetrying)
         }
      }
   }

   private var auditBlock: some View {
      VStack(alignment: .leading, spacing: 8) {
         SectionHeading(title: "Capture audit")
         DetailRow(label: "Signed (local)", value: localTimestamp)
         DetailRow(label: "Signed (UTC)", value: PodCoding.dateFormat.string(from: record.signedAt))
         DetailRow(label: "Location", value: record.location.summary)
         if let address = record.location.resolvedAddress {
            DetailRow(label: "Address", value: address)
         }
         DetailRow(label: "Signature input", value: inputSummary)
         DetailRow(label: "Device", value: "\(record.courier.deviceModel), \(record.courier.systemVersion)")
         DetailRow(label: "Record id", value: record.id.uuidString.lowercased(), monospaced: true)
         DetailRow(label: "Record SHA-256", value: record.payloadHash, monospaced: true)
         DetailRow(label: "Document SHA-256", value: current.pdfSha256, monospaced: true)
         DetailRow(label: "Filed at", value: current.pdfRelativePath, monospaced: true)
      }
   }

   private var documentPreview: some View {
      VStack(alignment: .leading, spacing: 8) {
         SectionHeading(title: "Document")
         PDFPreview(url: archive.pdfURL(for: current))
            .frame(minHeight: 560)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
               RoundedRectangle(cornerRadius: 12)
                  .strokeBorder(BrandColor.slate.opacity(0.2))
            }
      }
   }

   private var localTimestamp: String {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US")
      formatter.timeZone = TimeZone(identifier: record.timeZoneIdentifier) ?? .current
      formatter.dateFormat = "MMMM d, yyyy 'at' h:mm:ss a zzz"
      return formatter.string(from: record.signedAt)
   }

   private var inputSummary: String {
      let audit = record.signature
      let source = audit.inputPolicy == "pencilOnly"
         ? "Apple Pencil only"
         : (audit.pressureObserved ? "Stylus pressure detected" : "Touch or stylus")
      return "\(source), \(audit.strokeCount) strokes, \(String(format: "%.1f", audit.captureDurationSeconds)) s"
   }
}
