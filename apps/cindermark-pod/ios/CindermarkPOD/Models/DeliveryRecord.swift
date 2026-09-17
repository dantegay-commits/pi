import Foundation

/// One manifest line after the recipient has checked it at the door.
struct ReceivedLineItem: Codable, Hashable, Identifiable {
   var item: LineItem
   var quantityReceived: Int
   var disposition: ItemDisposition = .received
   var note: String = ""

   var id: UUID { item.id }

   init(item: LineItem) {
      self.item = item
      self.quantityReceived = item.quantityShipped
   }

   /// A line is clean when everything shipped was received undamaged.
   var isClean: Bool {
      disposition == .received && quantityReceived == item.quantityShipped
   }

   /// Exceptions must carry an explanation before the stop can be signed.
   var needsNote: Bool {
      !isClean && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
   }
}

/// Who signed, and on what authority.
enum SignerRelationship: String, Codable, CaseIterable, Identifiable {
   case patient
   case caregiver
   case facilityStaff
   case authorizedAgent
   case other

   var id: String { rawValue }

   var label: String {
      switch self {
      case .patient: return "Patient"
      case .caregiver: return "Caregiver / family"
      case .facilityStaff: return "Facility staff"
      case .authorizedAgent: return "Authorized agent"
      case .other: return "Other"
      }
   }
}

struct Signer: Codable, Hashable {
   var printedName: String = ""
   var relationship: SignerRelationship = .patient
   var relationshipDetail: String = ""

   /// What gets printed under the signature line.
   var relationshipDisplay: String {
      let detail = relationshipDetail.trimmingCharacters(in: .whitespacesAndNewlines)
      if relationship == .other {
         return detail.isEmpty ? "Other" : detail
      }
      return detail.isEmpty ? relationship.label : "\(relationship.label) - \(detail)"
   }
}

/// Where the signature was taken. Absent coordinates are recorded explicitly
/// rather than silently omitted, so a record can never be mistaken for a
/// located one it is not.
struct CapturedLocation: Codable, Hashable {
   enum Source: String, Codable {
      case gps
      case denied
      case restricted
      case unavailable
      case timedOut
   }

   var source: Source = .unavailable
   var latitude: Double?
   var longitude: Double?
   var horizontalAccuracyMeters: Double?
   var altitudeMeters: Double?
   var verticalAccuracyMeters: Double?
   var fixTimestamp: Date?
   var resolvedAddress: String?
   /// False when the user granted only approximate location (iOS "Precise: Off").
   var isPreciseAuthorization: Bool = false

   static let unavailable = CapturedLocation()

   var hasFix: Bool { latitude != nil && longitude != nil }

   /// Six decimal places is roughly 0.1 m of resolution: enough to place a doorway.
   var coordinateString: String? {
      guard let lat = latitude, let lon = longitude else { return nil }
      return String(format: "%.6f, %.6f", lat, lon)
   }

   var accuracyString: String? {
      guard let accuracy = horizontalAccuracyMeters, accuracy >= 0 else { return nil }
      return String(format: "+/- %.0f m", accuracy)
   }

   /// One-line summary for the PDF and the audit panel.
   var summary: String {
      guard let coords = coordinateString else {
         switch source {
         case .denied: return "Not recorded - location permission denied"
         case .restricted: return "Not recorded - location restricted on this device"
         case .timedOut: return "Not recorded - no fix before timeout"
         default: return "Not recorded - location unavailable"
         }
      }
      var parts = [coords]
      if let accuracy = accuracyString { parts.append(accuracy) }
      if !isPreciseAuthorization { parts.append("approximate authorization") }
      return parts.joined(separator: "  ")
   }
}

/// Provenance of the signature strokes themselves.
struct SignatureAudit: Codable, Hashable {
   var strokeCount: Int = 0
   var pointCount: Int = 0
   var captureDurationSeconds: Double = 0
   /// "pencilOnly" when finger input was rejected, otherwise "anyInput".
   var inputPolicy: String = "anyInput"
   /// True when stroke force varied across the drawing. Finger input on iPadOS
   /// reports a flat synthesized force, so varying force means a real stylus was
   /// used. This is a strong hint, not a guarantee, and is labelled as such
   /// everywhere it is shown.
   var pressureObserved: Bool = false
   var maximumForce: Double = 0
   var canvasWidth: Double = 0
   var canvasHeight: Double = 0
   /// SHA-256 of the exported signature PNG.
   var imageSha256: String = ""

   var likelyApplePencil: Bool {
      inputPolicy == "pencilOnly" || pressureObserved
   }
}

/// The device and driver that captured the record.
struct Courier: Codable, Hashable {
   var driverName: String = ""
   var deviceId: String = ""
   var deviceModel: String = ""
   var systemVersion: String = ""
   var appVersion: String = ""
   var appBuild: String = ""
}

/// Where a record stands with the WordPress endpoint.
enum DeliveryUploadState: String, Codable {
   case pending
   case uploaded
   case failed

   var label: String {
      switch self {
      case .pending: return "Queued"
      case .uploaded: return "Sent"
      case .failed: return "Needs retry"
      }
   }
}

/// The signed proof of delivery. This is the object that is hashed, archived to
/// the Shipped folder, and posted to WordPress; the PDF is a rendering of it.
struct DeliveryRecord: Codable, Hashable, Identifiable {
   /// Also the idempotency key for the upload: the server stores one record per id.
   var id = UUID()
   var schemaVersion: Int = 1
   var shipmentId: UUID
   var orderNumber: String
   var purchaseOrder: String
   var customer: Customer
   var lineItems: [ReceivedLineItem]
   var signer: Signer
   var signedAt: Date
   var timeZoneIdentifier: String
   var utcOffsetSeconds: Int
   var location: CapturedLocation
   var signature: SignatureAudit
   var courier: Courier
   var deliveryNotes: String = ""
   var serviceLevel: String = ""
   var coldChainRequired: Bool = false
   /// SHA-256 over this record with `payloadHash` blanked. See `PodCoding`.
   var payloadHash: String = ""

   var exceptions: [ReceivedLineItem] {
      lineItems.filter { !$0.isClean }
   }

   var hasExceptions: Bool { !exceptions.isEmpty }

   var totalUnitsShipped: Int {
      lineItems.reduce(0) { $0 + $1.item.quantityShipped }
   }

   var totalUnitsReceived: Int {
      lineItems.reduce(0) { $0 + $1.quantityReceived }
   }
}

/// The on-disk companion to an archived PDF: the record plus the file locations
/// and upload state. Paths are stored relative to the Documents directory
/// because the app container path changes between installs and OS upgrades.
struct ArchivedDelivery: Codable, Hashable, Identifiable {
   var record: DeliveryRecord
   var pdfRelativePath: String
   var signatureRelativePath: String
   var pdfSha256: String
   var uploadState: DeliveryUploadState = .pending
   var uploadAttempts: Int = 0
   var lastAttemptAt: Date?
   var lastUploadError: String?
   var uploadedAt: Date?
   var emailedTo: String?

   var id: UUID { record.id }
}
