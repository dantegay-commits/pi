import Combine
import Foundation

/// The working state of one stop between "arrived" and "signed".
///
/// It starts as a copy of the shipment so the driver can correct a bad email or
/// a wrong quantity at the door without editing the dispatch record, and it is
/// discarded if the stop is abandoned.
@MainActor
final class DeliveryDraft: ObservableObject {
   @Published var shipment: Shipment
   @Published var customer: Customer
   @Published var lines: [ReceivedLineItem]
   @Published var signer = Signer()
   @Published var deliveryNotes = ""

   init(shipment: Shipment) {
      self.shipment = shipment
      self.customer = shipment.customer
      self.lines = shipment.lineItems.map(ReceivedLineItem.init)
   }

   var exceptions: [ReceivedLineItem] { lines.filter { !$0.isClean } }
   var hasExceptions: Bool { !exceptions.isEmpty }

   var unitsReceived: Int { lines.reduce(0) { $0 + $1.quantityReceived } }
   var unitsShipped: Int { lines.reduce(0) { $0 + $1.item.quantityShipped } }

   func setDisposition(_ disposition: ItemDisposition, for id: UUID) {
      guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
      lines[index].disposition = disposition
      // Keep the quantity honest when the whole line is rejected, and restore it
      // when the driver changes their mind back to a clean receipt.
      switch disposition {
      case .refused:
         lines[index].quantityReceived = 0
      case .received:
         lines[index].quantityReceived = lines[index].item.quantityShipped
      case .shortShipped, .damaged:
         break
      }
   }

   func setQuantityReceived(_ quantity: Int, for id: UUID) {
      guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
      let clamped = max(0, min(quantity, lines[index].item.quantityShipped))
      lines[index].quantityReceived = clamped
      // A shortfall entered on a line still marked received is an exception,
      // whether or not the driver remembers to change the status.
      if clamped < lines[index].item.quantityShipped, lines[index].disposition == .received {
         lines[index].disposition = .shortShipped
      } else if clamped == lines[index].item.quantityShipped, lines[index].disposition == .shortShipped {
         lines[index].disposition = .received
      }
   }

   func setNote(_ note: String, for id: UUID) {
      guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
      lines[index].note = note
   }

   /// What has to be settled on the manifest before the iPad is handed over.
   /// Kept separate from `signerIssues` so the driver fixes their own work
   /// first and the customer is not left holding a Pencil in front of a
   /// validation error.
   func manifestIssues(requireCustomerEmail: Bool) -> [String] {
      var issues: [String] = []
      if lines.isEmpty {
         issues.append("This stop has no items on its manifest.")
      }
      for line in lines where line.needsNote {
         let label = line.item.sku.isBlank ? line.item.itemDescription : line.item.sku
         issues.append("Add a note explaining the exception on \(label).")
      }
      if requireCustomerEmail, !customer.hasUsableEmail {
         issues.append("Add the email address the signed copy should go to.")
      }
      return issues
   }

   /// What the signature screen itself still needs.
   func signerIssues() -> [String] {
      var issues: [String] = []
      if signer.printedName.isBlank {
         issues.append("Enter the printed name of the person signing.")
      }
      if signer.relationship == .other, signer.relationshipDetail.isBlank {
         issues.append("Say how the signer is related to the patient.")
      }
      return issues
   }
}
