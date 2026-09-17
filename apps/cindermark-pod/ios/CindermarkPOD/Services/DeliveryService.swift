import UIKit

/// What happened when a stop was completed: always an archived delivery, plus
/// whatever the upload managed to do.
struct DeliveryOutcome: Identifiable {
   let delivery: ArchivedDelivery
   let uploadResult: PodUploadResult?
   let uploadError: String?

   var id: UUID { delivery.id }
   var wasEmailed: Bool { uploadResult?.emailed == true }
}

enum DeliveryServiceError: LocalizedError {
   case noSignature
   case renderFailed
   case locationRequired(String)

   var errorDescription: String? {
      switch self {
      case .noSignature:
         return "No signature has been captured yet."
      case .renderFailed:
         return "The delivery document could not be created."
      case let .locationRequired(detail):
         return "This delivery is set to require a location fix, and none was available (\(detail)). "
            + "Step outside or turn off \"Require location\" in Settings, then complete the delivery again. "
            + "The signature on screen is still there."
      }
   }
}

/// Turns a completed draft plus a signature into an archived, hashed, uploaded
/// proof of delivery.
///
/// Order matters. Location and time are captured first, because they must
/// describe the moment of signing rather than the moment the paperwork
/// finished. The record is then hashed, rendered, and written to the Shipped
/// folder *before* any network call, so a delivery is never lost to a failed
/// upload.
@MainActor
struct DeliveryService {
   let settings: AppSettings
   let location: LocationService
   let archive: ShippedArchive
   let shipments: ShipmentStore
   let outbox: OutboxQueue

   func complete(draft: DeliveryDraft, signature: SignatureExport) async throws -> DeliveryOutcome {
      let signedAt = Date()
      let fix = await location.capture(reverseGeocode: settings.reverseGeocode)
      if settings.requireLocation, !fix.hasFix {
         throw DeliveryServiceError.locationRequired(fix.summary)
      }

      let timeZone = TimeZone.current
      var record = DeliveryRecord(
         shipmentId: draft.shipment.id,
         orderNumber: draft.shipment.orderNumber,
         purchaseOrder: draft.shipment.purchaseOrder,
         customer: draft.customer,
         lineItems: draft.lines,
         signer: draft.signer,
         signedAt: signedAt,
         timeZoneIdentifier: timeZone.identifier,
         utcOffsetSeconds: timeZone.secondsFromGMT(for: signedAt),
         location: fix,
         signature: signature.audit,
         courier: settings.courier,
         deliveryNotes: draft.deliveryNotes,
         serviceLevel: draft.shipment.serviceLevel,
         coldChainRequired: draft.shipment.requiresColdChain
      )
      record = try PodCoding.hashed(record)

      let pdf = PodPDFRenderer.render(record: record, signature: signature.image)
      guard !pdf.isEmpty else { throw DeliveryServiceError.renderFailed }

      let delivery = try archive.store(record: record, pdf: pdf, signaturePNG: signature.pngData)
      shipments.markCompleted(shipmentId: draft.shipment.id, recordId: record.id, at: signedAt)

      switch await outbox.send(delivery) {
      case let .success(result):
         let stored = archive.delivery(id: delivery.id) ?? delivery
         return DeliveryOutcome(delivery: stored, uploadResult: result, uploadError: nil)
      case let .failure(error):
         let stored = archive.delivery(id: delivery.id) ?? delivery
         return DeliveryOutcome(delivery: stored, uploadResult: nil, uploadError: error.localizedDescription)
      }
   }
}
