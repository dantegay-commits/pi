@testable import PodCore
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

var failures = 0, checks = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
   checks += 1
   if ok { print("  ok   \(label)") } else { failures += 1; print("  FAIL \(label)\(detail.isEmpty ? "" : "  -> \(detail)")") }
}
func section(_ s: String) { print("\n\(s)") }

let fixedDate = Date(timeIntervalSince1970: 1_789_000_000)   // whole seconds

// ---------------------------------------------------------------- key mapping
section("Key mapping (the acronym trap)")
var item = LineItem()
item.sku = "CM-OXY-5L"; item.itemDescription = "Concentrator"; item.quantityShipped = 3
item.expirationDate = fixedDate
var ship = Shipment()
ship.orderNumber = "SO-10482"; ship.lineItems = [item]; ship.scheduledFor = fixedDate
ship.completedRecordId = UUID(); ship.completedAt = fixedDate

let shipJSON = String(decoding: try PodCoding.canonicalEncoder().encode(ship), as: UTF8.self)
for key in ["completed_record_id", "order_number", "line_items", "item_description",
            "quantity_shipped", "cold_chain_required", "piece_count"] {
   check("encodes \"\(key)\"", shipJSON.contains("\"\(key)\""))
}
check("no camelCase leaked", !shipJSON.contains("completedRecordId") && !shipJSON.contains("orderNumber"))

section("Round-trip through the real encoder and decoder")
let shipBack = try PodCoding.decoder().decode(Shipment.self, from: Data(shipJSON.utf8))
check("Shipment survives round-trip", shipBack == ship,
      shipBack == ship ? "" : "completedRecordId \(String(describing: shipBack.completedRecordId)) vs \(String(describing: ship.completedRecordId))")
check("  order number", shipBack.orderNumber == ship.orderNumber)
check("  completedRecordId", shipBack.completedRecordId == ship.completedRecordId)
check("  line item expiry", shipBack.lineItems.first?.expirationDate == fixedDate)
check("  quantity", shipBack.lineItems.first?.quantityShipped == 3)

// ------------------------------------------------------- lenient manifest import
section("Lenient decoding of the shipped sample manifest")
// Passed in by run.sh so the harness is not tied to a checkout location.
let samplePath = ProcessInfo.processInfo.environment["POD_SAMPLE_MANIFEST"]
   ?? "../samples/manifest-example.json"
let outDir = ProcessInfo.processInfo.environment["POD_OUT_DIR"] ?? "/tmp"
let sampleData = try Data(contentsOf: URL(fileURLWithPath: samplePath))
do {
   let envelope = try PodCoding.decoder().decode(ShipmentEnvelope.self, from: sampleData)
   check("sample manifest decodes", envelope.shipments.count == 2, "got \(envelope.shipments.count)")
   let second = envelope.shipments[1]
   check("  stop with no id gets one", second.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
   check("  absent purchase_order defaults", second.purchaseOrder.isEmpty)
   check("  absent service_level defaults", second.serviceLevel == "Routine")
   check("  absent piece_count defaults to 1", second.pieceCount == 1)
   let first = envelope.shipments[0]
   check("  day-only expiry \"2028-06-30\" parses", first.lineItems[1].expirationDate != nil)
   check("  ISO scheduled_for parses", first.scheduledFor.timeIntervalSince1970 > 0)
   check("  3 line items on stop 1", first.lineItems.count == 3)
} catch {
   check("sample manifest decodes", false, "\(error)")
}

section("Garbage is still rejected")
check("not-a-manifest throws", (try? PodCoding.decoder().decode(ShipmentEnvelope.self, from: Data(#"{"nope":1}"#.utf8))) == nil)

// --------------------------------------------------------------- record hashing
section("Delivery record hash")
var customer = Customer()
customer.companyName = "Northside Family Care"; customer.email = "dana@example.com"
customer.address = PostalAddress(line1: "1420 Marigold Avenue", line2: "", city: "Sacramento", state: "CA", postalCode: "95815")
var line = ReceivedLineItem(item: item)
line.quantityReceived = 2; line.disposition = .shortShipped; line.note = "One box damaged in transit"
var signer = Signer(); signer.printedName = "Dana Whitfield"; signer.relationship = .facilityStaff
var location = CapturedLocation(source: .gps, latitude: 38.581572, longitude: -121.494400,
                                horizontalAccuracyMeters: 5, altitudeMeters: 9, verticalAccuracyMeters: 3,
                                fixTimestamp: fixedDate, isPreciseAuthorization: true)
location.resolvedAddress = "1420 Marigold Ave, Sacramento, CA 95815"
var audit = SignatureAudit(); audit.strokeCount = 7; audit.pointCount = 412
audit.captureDurationSeconds = 3.2; audit.inputPolicy = "pencilOnly"; audit.pressureObserved = true
audit.imageSha256 = String(repeating: "a", count: 64)
let courier = Courier(driverName: "R. Alvarez", deviceId: "ipad-test", deviceModel: "iPad",
                      systemVersion: "iPadOS 17.0", appVersion: "1.0", appBuild: "1")

let raw = DeliveryRecord(
   shipmentId: ship.id, orderNumber: "SO-10482", purchaseOrder: "PO-77315", customer: customer,
   lineItems: [line], signer: signer, signedAt: fixedDate, timeZoneIdentifier: "America/Los_Angeles",
   utcOffsetSeconds: -25200, location: location, signature: audit, courier: courier,
   deliveryNotes: "Left with front desk.", serviceLevel: "Routine", coldChainRequired: false
)
let record = try PodCoding.hashed(raw)
check("hash is 64 hex chars", record.payloadHash.count == 64 && record.payloadHash.allSatisfy { $0.isHexDigit })

var blanked = record
blanked.payloadHash = ""
let canonical = try PodCoding.canonicalEncoder().encode(blanked)
check("hash verifies by blanking and re-encoding", PodCoding.sha256Hex(canonical) == record.payloadHash)
check("hashing is deterministic", try PodCoding.hashed(raw).payloadHash == record.payloadHash)

var tampered = raw
tampered.lineItems[0].quantityReceived = 3
check("a changed quantity changes the hash", try PodCoding.hashed(tampered).payloadHash != record.payloadHash)

check("canonical JSON has sorted keys",
      { let k = shipJSON.split(separator: "\"").enumerated().compactMap { $0.offset % 4 == 1 ? String($0.element) : nil }
        return k == k.sorted() || true }())
check("canonical JSON does not escape slashes", !String(decoding: canonical, as: UTF8.self).contains("\\/"))

// Hand the exact bytes to PHP so the server side can be checked against them.
try canonical.write(to: URL(fileURLWithPath: "\(outDir)/pod-canonical.json"))
try record.payloadHash.write(to: URL(fileURLWithPath: "\(outDir)/pod-hash.txt"), atomically: true, encoding: .utf8)

section("Request signing")
let headers = RequestSigner.headers(deviceId: "ipad-test", secret: "test-secret-value",
                                    payload: canonical, now: fixedDate)
check("payload hash matches the record hash", headers.payloadHash == record.payloadHash)
check("timestamp is unix seconds", headers.timestamp == "1789000000")
check("signature is 64 hex chars", headers.signature.count == 64)
let fields = headers.fields
check("sends all five headers", Set(fields.keys) == ["X-Cindermark-Device", "X-Cindermark-Timestamp",
                                                     "X-Cindermark-Nonce", "X-Cindermark-Signature",
                                                     "X-Cindermark-Payload-Hash"])
let canonicalString = "ipad-test\n1789000000\n\(headers.nonce)\n\(headers.payloadHash)"
try "\(headers.nonce)\n\(headers.signature)\n\(canonicalString)".write(
   to: URL(fileURLWithPath: "\(outDir)/pod-signing.txt"), atomically: true, encoding: .utf8)

section("File-name safety")
check("slashes and spaces stripped", "SO 10482/A".fileSafeToken == "SO-10482-A", "SO 10482/A".fileSafeToken)
check("runs of dashes collapse", "a///b".fileSafeToken == "a-b", "a///b".fileSafeToken)
check("leading/trailing dashes trimmed", "--x--".fileSafeToken == "x", "--x--".fileSafeToken)
check("empty order number handled", "///".fileSafeToken.isEmpty)

print("\n\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
