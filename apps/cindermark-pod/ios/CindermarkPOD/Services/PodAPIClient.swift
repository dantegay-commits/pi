import Foundation

/// Immutable snapshot of the settings an upload needs, so network work does not
/// have to reach back to the main actor.
struct PodEndpointConfig {
   let baseURL: URL
   let secret: String
   let deviceId: String
   let sendCustomerEmail: Bool
   let operationsEmail: String

   func route(_ name: String) -> URL {
      baseURL.appendingPathComponent("wp-json/cindermark/v1/\(name)")
   }
}

struct PodUploadResult: Decodable {
   let status: String
   let recordId: String
   /// True when the server already had this record; no second email is sent.
   let duplicate: Bool
   let emailed: Bool
   let emailedTo: String?
   let message: String?
}

struct PodPingResult: Decodable {
   let status: String
   let site: String?
   let pluginVersion: String?
   let mailFrom: String?
}

enum PodAPIError: LocalizedError {
   case notLinked
   case badResponse
   case server(status: Int, message: String)
   case transport(String)

   var errorDescription: String? {
      switch self {
      case .notLinked:
         return "This device is not linked to the CINDERMARK site yet. Add the site address and pairing secret in Settings."
      case .badResponse:
         return "The site replied with something this app could not read. Check that the CINDERMARK POD plugin is active."
      case let .server(status, message):
         return message.isEmpty ? "The site refused the upload (HTTP \(status))." : message
      case let .transport(message):
         return message
      }
   }
}

/// Talks to the CINDERMARK POD WordPress plugin.
struct PodAPIClient {
   let config: PodEndpointConfig
   var session: URLSession = .shared

   /// Settings screen "Test connection".
   func ping() async throws -> PodPingResult {
      let payload = Data("{}".utf8)
      var request = URLRequest(url: config.route("ping"))
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = payload
      sign(&request, payload: payload)
      return try await send(request)
   }

   /// Pulls the stops assigned to this device, when the site is the dispatch
   /// source. Optional: manifests can also be imported from a file.
   func fetchShipments() async throws -> [Shipment] {
      let payload = Data("{}".utf8)
      var request = URLRequest(url: config.route("shipments"))
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = payload
      sign(&request, payload: payload)
      let envelope: ShipmentEnvelope = try await send(request)
      return envelope.shipments
   }

   /// Posts one signed delivery. The record id is the idempotency key: sending
   /// the same record twice returns `duplicate` and does not email the customer
   /// a second time.
   func upload(record: DeliveryRecord, pdf: Data, signaturePNG: Data, pdfSha256: String) async throws -> PodUploadResult {
      // The record travels as the exact bytes that were hashed, not as a nested
      // object. Re-encoding JSON in PHP to check a hash would depend on key
      // order and float formatting matching Swift's exactly, which is not
      // something to bet a signed record on; hashing the bytes as received is
      // unambiguous.
      let canonical = try PodCoding.canonicalPayload(for: record)
      let envelope = UploadEnvelope(
         recordCanonical: String(decoding: canonical, as: UTF8.self),
         payloadHash: record.payloadHash,
         pdfSha256: pdfSha256,
         signatureSha256: record.signature.imageSha256,
         sendCustomerEmail: config.sendCustomerEmail,
         operationsEmail: config.operationsEmail.trimmed,
         appVersion: DeviceInfo.versionDisplay
      )
      let payload = try PodCoding.canonicalEncoder().encode(envelope)

      let boundary = "cindermark.\(UUID().uuidString)"
      var body = Data()
      body.appendMultipartField(name: "payload", value: payload, contentType: "application/json", boundary: boundary)
      body.appendMultipartFile(
         name: "pod",
         filename: "POD-\(record.orderNumber.fileSafeToken).pdf",
         data: pdf,
         contentType: "application/pdf",
         boundary: boundary
      )
      body.appendMultipartFile(
         name: "signature",
         filename: "signature.png",
         data: signaturePNG,
         contentType: "image/png",
         boundary: boundary
      )
      body.append(Data("--\(boundary)--\r\n".utf8))

      var request = URLRequest(url: config.route("pod"))
      request.httpMethod = "POST"
      request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
      request.httpBody = body
      request.timeoutInterval = 60
      // The signature covers the JSON payload, which carries the hashes of both
      // attached files, so tampering with either one breaks verification.
      sign(&request, payload: payload)
      return try await send(request)
   }

   private func sign(_ request: inout URLRequest, payload: Data) {
      let headers = RequestSigner.headers(deviceId: config.deviceId, secret: config.secret, payload: payload)
      for (field, value) in headers.fields {
         request.setValue(value, forHTTPHeaderField: field)
      }
      request.setValue("CindermarkPOD/\(DeviceInfo.appVersion)", forHTTPHeaderField: "User-Agent")
   }

   private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
      let data: Data
      let response: URLResponse
      do {
         (data, response) = try await session.data(for: request)
      } catch {
         throw PodAPIError.transport(error.localizedDescription)
      }
      guard let http = response as? HTTPURLResponse else { throw PodAPIError.badResponse }
      guard (200 ..< 300).contains(http.statusCode) else {
         throw PodAPIError.server(status: http.statusCode, message: Self.errorMessage(from: data))
      }
      do {
         return try PodCoding.decoder().decode(T.self, from: data)
      } catch {
         throw PodAPIError.badResponse
      }
   }

   /// WordPress REST errors come back as {"code":...,"message":...}. Anything
   /// else (an HTML error page from a proxy, say) is not worth showing raw.
   private static func errorMessage(from data: Data) -> String {
      guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
      return object["message"] as? String ?? ""
   }

   /// What the plugin receives.
   ///
   /// `recordCanonical` is the delivery record serialised with `payload_hash`
   /// blanked - the precise bytes `payloadHash` covers. The server verifies
   /// `sha256(record_canonical) == payload_hash`, then decodes the string for
   /// storage. The file hashes ride along inside the same payload, and the
   /// request HMAC covers the payload, so altering either attachment in transit
   /// breaks verification.
   private struct UploadEnvelope: Encodable {
      let recordCanonical: String
      let payloadHash: String
      let pdfSha256: String
      let signatureSha256: String
      let sendCustomerEmail: Bool
      let operationsEmail: String
      let appVersion: String
   }
}

private extension Data {
   mutating func appendMultipartField(name: String, value: Data, contentType: String, boundary: String) {
      append(Data("--\(boundary)\r\n".utf8))
      append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n".utf8))
      append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
      append(value)
      append(Data("\r\n".utf8))
   }

   mutating func appendMultipartFile(name: String, filename: String, data: Data, contentType: String, boundary: String) {
      append(Data("--\(boundary)\r\n".utf8))
      append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
      append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
      append(data)
      append(Data("\r\n".utf8))
   }
}
