import Combine
import Foundation

/// The stops loaded on this iPad. Persisted as a single JSON file in
/// Documents/Data so a dispatcher can drop a manifest in over the Files app or
/// AirDrop, and so the run survives a force-quit.
@MainActor
final class ShipmentStore: ObservableObject {
   @Published private(set) var shipments: [Shipment] = []
   @Published var lastImportSummary: String?

   private let fileURL = AppPaths.data.appendingPathComponent("shipments.json")

   init() {
      AppPaths.prepare()
      load()
   }

   var open: [Shipment] {
      shipments.filter { !$0.isCompleted }.sorted { $0.scheduledFor < $1.scheduledFor }
   }

   var completed: [Shipment] {
      shipments.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
   }

   func shipment(id: UUID) -> Shipment? {
      shipments.first { $0.id == id }
   }

   func upsert(_ shipment: Shipment) {
      if let index = shipments.firstIndex(where: { $0.id == shipment.id }) {
         shipments[index] = shipment
      } else {
         shipments.append(shipment)
      }
      save()
   }

   func delete(_ shipment: Shipment) {
      shipments.removeAll { $0.id == shipment.id }
      save()
   }

   func markCompleted(shipmentId: UUID, recordId: UUID, at date: Date) {
      guard let index = shipments.firstIndex(where: { $0.id == shipmentId }) else { return }
      shipments[index].completedRecordId = recordId
      shipments[index].completedAt = date
      save()
   }

   // MARK: - Persistence

   func load() {
      guard let data = try? Data(contentsOf: fileURL) else { return }
      shipments = (try? PodCoding.decoder().decode([Shipment].self, from: data)) ?? []
   }

   func save() {
      guard let data = try? PodCoding.encoder(pretty: true).encode(shipments) else { return }
      try? data.write(to: fileURL, options: .atomic)
   }

   // MARK: - Import

   enum ImportError: LocalizedError {
      case unreadable
      case badFormat

      var errorDescription: String? {
         switch self {
         case .unreadable: return "That file could not be opened."
         case .badFormat: return "That file is not a CINDERMARK manifest. Expected JSON with a list of shipments."
         }
      }
   }

   /// Accepts either a bare array of shipments or `{"shipments": [...]}`, which
   /// is what the WordPress endpoint returns, so the same file works from
   /// either source. Shipments already present (matched on order number) are
   /// replaced unless they have already been signed.
   @discardableResult
   func importManifest(from url: URL) throws -> Int {
      let needsScope = url.startAccessingSecurityScopedResource()
      defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

      guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
      return try importManifest(data: data)
   }

   @discardableResult
   func importManifest(data: Data) throws -> Int {
      let decoder = PodCoding.decoder()
      let incoming: [Shipment]
      if let list = try? decoder.decode([Shipment].self, from: data) {
         incoming = list
      } else if let envelope = try? decoder.decode(ShipmentEnvelope.self, from: data) {
         incoming = envelope.shipments
      } else {
         throw ImportError.badFormat
      }

      var added = 0
      for var shipment in incoming {
         if let existing = shipments.first(where: { $0.orderNumber == shipment.orderNumber && !$0.orderNumber.isEmpty }) {
            guard !existing.isCompleted else { continue }
            shipment.id = existing.id
         }
         upsertWithoutSaving(shipment)
         added += 1
      }
      save()
      lastImportSummary = added == 1 ? "1 stop loaded" : "\(added) stops loaded"
      return added
   }

   private func upsertWithoutSaving(_ shipment: Shipment) {
      if let index = shipments.firstIndex(where: { $0.id == shipment.id }) {
         shipments[index] = shipment
      } else {
         shipments.append(shipment)
      }
   }

   /// A single worked example, loaded on request from Settings. Not seeded
   /// automatically: an empty run list is honest, invented patient data is not.
   func loadSampleStop() {
      var item = LineItem()
      item.sku = "CM-OXY-5L"
      item.itemDescription = "Portable oxygen concentrator, 5 LPM, with carry case"
      item.manufacturer = "Inogen"
      item.quantityShipped = 1
      item.unitOfMeasure = "EA"
      item.serialNumber = "IG-4471902"
      item.hcpcsCode = "E1392"

      var supplies = LineItem()
      supplies.sku = "CM-CAN-25"
      supplies.itemDescription = "Nasal cannula, 25 ft, single patient use"
      supplies.manufacturer = "Salter Labs"
      supplies.quantityShipped = 4
      supplies.unitOfMeasure = "EA"
      supplies.lotNumber = "L-88213"
      supplies.expirationDate = Calendar.current.date(byAdding: .year, value: 2, to: Date())

      var shipment = Shipment()
      shipment.orderNumber = "SO-10482"
      shipment.purchaseOrder = "PO-77315"
      shipment.serviceLevel = "Routine"
      shipment.pieceCount = 2
      shipment.deliveryInstructions = "Ring bell twice. Leave nothing outside."
      shipment.customer = Customer(
         accountNumber: "ACCT-3391",
         companyName: "Northside Family Care",
         contactName: "Dana Whitfield",
         email: "",
         phone: "(555) 010-2288",
         address: PostalAddress(
            line1: "1420 Marigold Avenue",
            line2: "Suite 200",
            city: "Sacramento",
            state: "CA",
            postalCode: "95815"
         )
      )
      shipment.lineItems = [item, supplies]
      upsert(shipment)
   }
}
