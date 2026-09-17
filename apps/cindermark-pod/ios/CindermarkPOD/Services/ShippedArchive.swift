import Combine
import Foundation

/// The local Shipped folder: every signed delivery, filed by year and month,
/// readable from the Files app.
///
/// Each delivery writes three files sharing one base name - the PDF, the
/// signature PNG, and a JSON sidecar holding the record plus its upload state.
/// The sidecar is the source of truth for what still needs sending, so the
/// queue survives being force-quit.
@MainActor
final class ShippedArchive: ObservableObject {
   @Published private(set) var deliveries: [ArchivedDelivery] = []

   private let fileManager = FileManager.default

   init() {
      AppPaths.prepare()
      reload()
   }

   /// Rebuilds the in-memory index by walking Shipped/. Cheap enough for the
   /// volumes a courier operation produces, and it means the folder itself is
   /// the database - a restored backup just works.
   func reload() {
      var found: [ArchivedDelivery] = []
      let decoder = PodCoding.decoder()
      let enumerator = fileManager.enumerator(at: AppPaths.shipped, includingPropertiesForKeys: nil)
      while let url = enumerator?.nextObject() as? URL {
         guard url.pathExtension.lowercased() == "json" else { continue }
         guard let data = try? Data(contentsOf: url),
               let delivery = try? decoder.decode(ArchivedDelivery.self, from: data)
         else { continue }
         found.append(delivery)
      }
      deliveries = found.sorted { $0.record.signedAt > $1.record.signedAt }
   }

   func delivery(id: UUID) -> ArchivedDelivery? {
      deliveries.first { $0.id == id }
   }

   var pendingUploads: [ArchivedDelivery] {
      deliveries.filter { $0.uploadState != .uploaded }
   }

   /// Writes the three files and returns the index entry. Throws rather than
   /// half-writing: the PDF is written first and removed if the sidecar fails,
   /// so the folder never holds a document with no record beside it.
   @discardableResult
   func store(record: DeliveryRecord, pdf: Data, signaturePNG: Data) throws -> ArchivedDelivery {
      let folder = try AppPaths.shippedFolder(for: record.signedAt)
      let base = try uniqueBaseName(in: folder, record: record)

      let pdfURL = folder.appendingPathComponent("\(base).pdf")
      let signatureURL = folder.appendingPathComponent("\(base)-signature.png")
      let sidecarURL = folder.appendingPathComponent("\(base).json")

      try pdf.write(to: pdfURL, options: .atomic)
      do {
         try signaturePNG.write(to: signatureURL, options: .atomic)
         let delivery = ArchivedDelivery(
            record: record,
            pdfRelativePath: AppPaths.relative(pdfURL),
            signatureRelativePath: AppPaths.relative(signatureURL),
            pdfSha256: PodCoding.sha256Hex(pdf)
         )
         try write(delivery, to: sidecarURL)
         deliveries.insert(delivery, at: 0)
         return delivery
      } catch {
         try? fileManager.removeItem(at: pdfURL)
         try? fileManager.removeItem(at: signatureURL)
         throw error
      }
   }

   /// Rewrites the sidecar after an upload attempt.
   func update(_ delivery: ArchivedDelivery) {
      guard let sidecar = sidecarURL(for: delivery) else { return }
      try? write(delivery, to: sidecar)
      if let index = deliveries.firstIndex(where: { $0.id == delivery.id }) {
         deliveries[index] = delivery
      } else {
         deliveries.insert(delivery, at: 0)
      }
   }

   func pdfURL(for delivery: ArchivedDelivery) -> URL {
      AppPaths.absolute(delivery.pdfRelativePath)
   }

   func signatureURL(for delivery: ArchivedDelivery) -> URL {
      AppPaths.absolute(delivery.signatureRelativePath)
   }

   /// Deliveries grouped into the year/month headings the folder itself uses.
   func groupedByMonth() -> [(title: String, deliveries: [ArchivedDelivery])] {
      let formatter = DateFormatter()
      formatter.dateFormat = "LLLL yyyy"
      var order: [String] = []
      var buckets: [String: [ArchivedDelivery]] = [:]
      for delivery in deliveries {
         let key = formatter.string(from: delivery.record.signedAt)
         if buckets[key] == nil {
            buckets[key] = []
            order.append(key)
         }
         buckets[key]?.append(delivery)
      }
      return order.map { ($0, buckets[$0] ?? []) }
   }

   private func sidecarURL(for delivery: ArchivedDelivery) -> URL? {
      let pdf = AppPaths.absolute(delivery.pdfRelativePath)
      return pdf.deletingPathExtension().appendingPathExtension("json")
   }

   private func write(_ delivery: ArchivedDelivery, to url: URL) throws {
      let data = try PodCoding.encoder(pretty: true).encode(delivery)
      try data.write(to: url, options: .atomic)
   }

   private func uniqueBaseName(in folder: URL, record: DeliveryRecord) throws -> String {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyyMMdd-HHmmss"
      formatter.locale = Locale(identifier: "en_US_POSIX")
      let cleanedOrder = record.orderNumber.fileSafeToken
      let order = cleanedOrder.isEmpty ? "NO-ORDER" : cleanedOrder
      let stamp = formatter.string(from: record.signedAt)
      let base = "POD-\(order)-\(stamp)"
      var candidate = base
      var suffix = 2
      while fileManager.fileExists(atPath: folder.appendingPathComponent("\(candidate).pdf").path) {
         candidate = "\(base)-\(suffix)"
         suffix += 1
      }
      return candidate
   }
}
