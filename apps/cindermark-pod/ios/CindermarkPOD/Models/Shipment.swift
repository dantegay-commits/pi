import Foundation

/// A postal address as printed on the proof-of-delivery document.
struct PostalAddress: Codable, Hashable {
   var line1: String = ""
   var line2: String = ""
   var city: String = ""
   var state: String = ""
   var postalCode: String = ""

   /// Address collapsed onto one line, used in list rows and email subjects.
   var singleLine: String {
      lines.joined(separator: ", ")
   }

   /// Address split for block rendering on the PDF, with empty parts dropped.
   var lines: [String] {
      var out: [String] = []
      if !line1.isEmpty { out.append(line1) }
      if !line2.isEmpty { out.append(line2) }
      let cityState = [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
      let tail = [cityState, postalCode].filter { !$0.isEmpty }.joined(separator: " ")
      if !tail.isEmpty { out.append(tail) }
      return out
   }

   var isEmpty: Bool { lines.isEmpty }
}

/// The party receiving the shipment. `email` is where the signed copy is sent.
struct Customer: Codable, Hashable {
   var accountNumber: String = ""
   var companyName: String = ""
   var contactName: String = ""
   var email: String = ""
   var phone: String = ""
   var address = PostalAddress()

   /// Facility name when there is one, otherwise the individual's name.
   var displayName: String {
      if !companyName.isEmpty { return companyName }
      return contactName.isEmpty ? "Unnamed recipient" : contactName
   }

   /// Loose check only: it is a gate for the send button, not validation of deliverability.
   var hasUsableEmail: Bool {
      let trimmed = email.trimmingCharacters(in: .whitespaces)
      guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
      let domain = trimmed[trimmed.index(after: at)...]
      return domain.contains(".") && !domain.hasSuffix(".")
   }
}

/// One product line on the manifest, as it left the warehouse.
struct LineItem: Codable, Hashable, Identifiable {
   var id = UUID()
   var sku: String = ""
   var itemDescription: String = ""
   var manufacturer: String = ""
   var quantityShipped: Int = 1
   var unitOfMeasure: String = "EA"
   var lotNumber: String = ""
   var serialNumber: String = ""
   var expirationDate: Date?
   var hcpcsCode: String = ""
   var coldChain: Bool = false
   var controlledSubstance: Bool = false

   /// Lot and serial share one narrow PDF column; this is what goes in it.
   var traceabilityLine: String {
      var parts: [String] = []
      if !lotNumber.isEmpty { parts.append("Lot \(lotNumber)") }
      if !serialNumber.isEmpty { parts.append("S/N \(serialNumber)") }
      return parts.joined(separator: "\n")
   }
}

/// What actually happened to a line at the door.
enum ItemDisposition: String, Codable, CaseIterable, Identifiable {
   case received
   case shortShipped
   case damaged
   case refused

   var id: String { rawValue }

   var label: String {
      switch self {
      case .received: return "Received"
      case .shortShipped: return "Short"
      case .damaged: return "Damaged"
      case .refused: return "Refused"
      }
   }

   /// Exceptions force a note and are called out on the PDF and in the email.
   var isException: Bool { self != .received }
}

/// A delivery stop: one order, one recipient, one manifest.
struct Shipment: Codable, Hashable, Identifiable {
   var id = UUID()
   var orderNumber: String = ""
   var purchaseOrder: String = ""
   var customer = Customer()
   var scheduledFor = Date()
   var serviceLevel: String = "Routine"
   var deliveryInstructions: String = ""
   var lineItems: [LineItem] = []
   var pieceCount: Int = 1
   var coldChainRequired: Bool = false

   /// Set when a signature has been captured; a completed stop is read-only.
   var completedRecordId: UUID?
   var completedAt: Date?

   var isCompleted: Bool { completedAt != nil }

   var totalUnits: Int {
      lineItems.reduce(0) { $0 + $1.quantityShipped }
   }

   var requiresColdChain: Bool {
      coldChainRequired || lineItems.contains { $0.coldChain }
   }

   var hasControlledSubstance: Bool {
      lineItems.contains { $0.controlledSubstance }
   }

   /// Order number with anything unsafe for a file name replaced.
   var fileSafeOrderNumber: String {
      let cleaned = orderNumber.fileSafeToken
      return cleaned.isEmpty ? "NO-ORDER" : cleaned
   }
}

/// Wire format for a batch of stops: what the WordPress endpoint returns and
/// what an imported manifest file may look like.
struct ShipmentEnvelope: Codable {
   var shipments: [Shipment]
}

/// Forgiving decoding for the types that arrive from outside the app.
///
/// Swift's synthesized `init(from:)` throws on any absent key, even for a
/// property that has a default value. A manifest hand-edited by a dispatcher,
/// or produced by a system that has no purchase order to report, would be
/// rejected whole for one missing field. These decoders fill in the default
/// instead, so an import fails only when it is genuinely not a manifest.
///
/// Records the app produces itself keep the synthesized decoder: there, a
/// missing key means a corrupt archive and should be loud.
private extension KeyedDecodingContainer {
   /// The value at `key`, or `fallback` when it is absent, null, or the wrong
   /// type. `try?` flattens rather than nesting the optional, so one `??`
   /// covers all three cases.
   func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
      (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
   }

   func optionalValue<T: Decodable>(_ key: Key) -> T? {
      try? decodeIfPresent(T.self, forKey: key)
   }
}

extension PostalAddress {
   enum CodingKeys: String, CodingKey {
      case line1, line2, city, state, postalCode
   }

   init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.init(
         line1: container.value(.line1, or: ""),
         line2: container.value(.line2, or: ""),
         city: container.value(.city, or: ""),
         state: container.value(.state, or: ""),
         postalCode: container.value(.postalCode, or: "")
      )
   }
}

extension Customer {
   enum CodingKeys: String, CodingKey {
      case accountNumber, companyName, contactName, email, phone, address
   }

   init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.init(
         accountNumber: container.value(.accountNumber, or: ""),
         companyName: container.value(.companyName, or: ""),
         contactName: container.value(.contactName, or: ""),
         email: container.value(.email, or: ""),
         phone: container.value(.phone, or: ""),
         address: container.value(.address, or: PostalAddress())
      )
   }
}

extension LineItem {
   enum CodingKeys: String, CodingKey {
      case id, sku, itemDescription, manufacturer, quantityShipped, unitOfMeasure
      case lotNumber, serialNumber, expirationDate, hcpcsCode, coldChain, controlledSubstance
   }

   init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.init(
         id: container.value(.id, or: UUID()),
         sku: container.value(.sku, or: ""),
         itemDescription: container.value(.itemDescription, or: ""),
         manufacturer: container.value(.manufacturer, or: ""),
         quantityShipped: max(0, container.value(.quantityShipped, or: 1)),
         unitOfMeasure: container.value(.unitOfMeasure, or: "EA"),
         lotNumber: container.value(.lotNumber, or: ""),
         serialNumber: container.value(.serialNumber, or: ""),
         expirationDate: container.optionalValue(.expirationDate),
         hcpcsCode: container.value(.hcpcsCode, or: ""),
         coldChain: container.value(.coldChain, or: false),
         controlledSubstance: container.value(.controlledSubstance, or: false)
      )
   }
}

extension Shipment {
   enum CodingKeys: String, CodingKey {
      case id, orderNumber, purchaseOrder, customer, scheduledFor, serviceLevel
      case deliveryInstructions, lineItems, pieceCount, coldChainRequired
      case completedRecordId, completedAt
   }

   init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.init(
         id: container.value(.id, or: UUID()),
         orderNumber: container.value(.orderNumber, or: ""),
         purchaseOrder: container.value(.purchaseOrder, or: ""),
         customer: container.value(.customer, or: Customer()),
         scheduledFor: container.value(.scheduledFor, or: Date()),
         serviceLevel: container.value(.serviceLevel, or: "Routine"),
         deliveryInstructions: container.value(.deliveryInstructions, or: ""),
         lineItems: container.value(.lineItems, or: []),
         pieceCount: container.value(.pieceCount, or: 1),
         coldChainRequired: container.value(.coldChainRequired, or: false),
         completedRecordId: container.optionalValue(.completedRecordId),
         completedAt: container.optionalValue(.completedAt)
      )
   }
}
