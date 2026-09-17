import CryptoKit
import Foundation

/// Signs requests to the WordPress endpoint.
///
/// The iPad and the site share one secret. Each request carries the device id,
/// a unix timestamp, a random nonce, and the SHA-256 of its JSON payload; the
/// HMAC covers all four, joined by newlines:
///
///     <device id>\n<timestamp>\n<nonce>\n<payload sha-256>
///
/// The server recomputes it, rejects anything more than five minutes out of
/// step, and refuses a nonce it has already seen. That gives integrity and
/// replay protection on top of TLS without putting a WordPress password on the
/// device.
enum RequestSigner {
   struct Headers {
      let deviceId: String
      let timestamp: String
      let nonce: String
      let signature: String
      let payloadHash: String

      var fields: [String: String] {
         [
            "X-Cindermark-Device": deviceId,
            "X-Cindermark-Timestamp": timestamp,
            "X-Cindermark-Nonce": nonce,
            "X-Cindermark-Signature": signature,
            "X-Cindermark-Payload-Hash": payloadHash,
         ]
      }
   }

   static func headers(deviceId: String, secret: String, payload: Data, now: Date = Date()) -> Headers {
      let timestamp = String(Int(now.timeIntervalSince1970))
      let nonce = UUID().uuidString.lowercased()
      let payloadHash = PodCoding.sha256Hex(payload)
      let canonical = "\(deviceId)\n\(timestamp)\n\(nonce)\n\(payloadHash)"
      let key = SymmetricKey(data: Data(secret.utf8))
      let mac = HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: key)
      let signature = mac.map { String(format: "%02x", $0) }.joined()
      return Headers(
         deviceId: deviceId,
         timestamp: timestamp,
         nonce: nonce,
         signature: signature,
         payloadHash: payloadHash
      )
   }
}
