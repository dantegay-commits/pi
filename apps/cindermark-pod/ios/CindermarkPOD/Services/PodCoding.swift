#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// JSON encoders shared by the archive, the PDF and the upload, plus the record
/// hash.
///
/// The hash has to be reproducible on the server, so the bytes that are hashed
/// have to be produced the same way twice. `canonicalEncoder` pins the two
/// things that would otherwise vary: key order (`sortedKeys`) and slash escaping.
/// Dates go out as ISO-8601 in UTC, which PHP parses with `DateTimeImmutable`.
enum PodCoding {
   static let dateFormat: ISO8601DateFormatter = {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      return formatter
   }()

   /// For dates written the way a person writes an expiry: 2028-06-30.
   static let dayOnlyFormat: DateFormatter = {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyy-MM-dd"
      return formatter
   }()

   static func encoder(pretty: Bool = false) -> JSONEncoder {
      let encoder = JSONEncoder()
      encoder.keyEncodingStrategy = .convertToSnakeCase
      encoder.dateEncodingStrategy = .custom { date, coder in
         var container = coder.singleValueContainer()
         try container.encode(dateFormat.string(from: date))
      }
      encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : []
      return encoder
   }

   /// Byte-for-byte reproducible encoding. Used only for hashing.
   static func canonicalEncoder() -> JSONEncoder {
      let encoder = encoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      return encoder
   }

   static func decoder() -> JSONDecoder {
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      decoder.dateDecodingStrategy = .custom { decoder in
         let container = try decoder.singleValueContainer()
         let raw = try container.decode(String.self)
         if let date = dateFormat.date(from: raw) { return date }
         // Tolerate fractional seconds from other producers.
         let fractional = ISO8601DateFormatter()
         fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
         if let date = fractional.date(from: raw) { return date }
         // And a bare calendar date, which is how a person writes an expiry.
         if let date = dayOnlyFormat.date(from: raw) { return date }
         throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unparseable date \(raw)")
      }
      return decoder
   }

   /// Canonical JSON for a record with `payload_hash` blanked out, which is what
   /// both sides hash. Verifying a record means: blank the field, re-encode
   /// here, compare.
   static func canonicalPayload(for record: DeliveryRecord) throws -> Data {
      var unhashed = record
      unhashed.payloadHash = ""
      return try canonicalEncoder().encode(unhashed)
   }

   static func hashed(_ record: DeliveryRecord) throws -> DeliveryRecord {
      var stamped = record
      stamped.payloadHash = try sha256Hex(canonicalPayload(for: record))
      return stamped
   }

   static func sha256Hex(_ data: Data) -> String {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
   }
}
