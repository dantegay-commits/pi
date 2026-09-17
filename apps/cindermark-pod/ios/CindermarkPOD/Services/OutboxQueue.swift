import Foundation
import Network

/// Sends signed deliveries to the WordPress site, and keeps trying.
///
/// A driver loses signal in stairwells, basements and loading docks, so a
/// delivery is never blocked on the network: the signature is archived locally
/// first and the upload is a background concern. Pending work is read straight
/// off the Shipped folder, so a force-quit, a battery death or an app update
/// cannot lose a queued delivery.
@MainActor
final class OutboxQueue: ObservableObject {
   @Published private(set) var isDraining = false
   @Published private(set) var isOnline = true
   @Published private(set) var lastError: String?

   private let archive: ShippedArchive
   private let settings: AppSettings
   private let monitor = NWPathMonitor()
   private var monitorStarted = false

   /// 30 s, 1 m, 2 m, 4 m ... capped at 15 minutes.
   private let baseRetryDelay: TimeInterval = 30
   private let maximumRetryDelay: TimeInterval = 900

   init(archive: ShippedArchive, settings: AppSettings) {
      self.archive = archive
      self.settings = settings
   }

   var pendingCount: Int { archive.pendingUploads.count }

   func startMonitoring() {
      guard !monitorStarted else { return }
      monitorStarted = true
      monitor.pathUpdateHandler = { [weak self] path in
         let online = path.status == .satisfied
         Task { @MainActor in
            await self?.connectivityChanged(to: online)
         }
      }
      monitor.start(queue: DispatchQueue(label: "com.cindermark.pod.network"))
   }

   /// Signal coming back is the moment worth retrying on; losing it is not.
   private func connectivityChanged(to online: Bool) async {
      let cameBack = online && !isOnline
      isOnline = online
      if cameBack { await drain() }
   }

   /// Sends one delivery now, ignoring backoff. Used right after a signature so
   /// the driver sees the outcome while still at the door.
   @discardableResult
   func send(_ delivery: ArchivedDelivery) async -> Result<PodUploadResult, Error> {
      guard let config = endpointConfig() else {
         let error = PodAPIError.notLinked
         record(delivery, failedWith: error)
         return .failure(error)
      }
      return await perform(delivery, config: config)
   }

   /// Attempts every delivery whose backoff has elapsed.
   func drain() async {
      guard !isDraining else { return }
      guard let config = endpointConfig() else { return }
      isDraining = true
      defer { isDraining = false }

      for delivery in archive.pendingUploads where isDue(delivery) {
         _ = await perform(delivery, config: config)
      }
   }

   /// Clears the backoff and tries immediately, for the retry button.
   func retryNow(_ delivery: ArchivedDelivery) async {
      var reset = delivery
      reset.uploadAttempts = 0
      reset.lastAttemptAt = nil
      archive.update(reset)
      _ = await send(reset)
   }

   private func perform(_ delivery: ArchivedDelivery, config: PodEndpointConfig) async -> Result<PodUploadResult, Error> {
      let pdfURL = archive.pdfURL(for: delivery)
      let signatureURL = archive.signatureURL(for: delivery)
      guard let pdf = try? Data(contentsOf: pdfURL), let signature = try? Data(contentsOf: signatureURL) else {
         let error = PodAPIError.transport("The archived files for this delivery are missing.")
         record(delivery, failedWith: error)
         return .failure(error)
      }

      let client = PodAPIClient(config: config)
      do {
         let result = try await client.upload(
            record: delivery.record,
            pdf: pdf,
            signaturePNG: signature,
            pdfSha256: delivery.pdfSha256
         )
         var sent = delivery
         sent.uploadState = .uploaded
         sent.uploadedAt = Date()
         sent.lastAttemptAt = Date()
         sent.lastUploadError = nil
         sent.emailedTo = result.emailedTo
         archive.update(sent)
         lastError = nil
         return .success(result)
      } catch {
         record(delivery, failedWith: error)
         return .failure(error)
      }
   }

   private func record(_ delivery: ArchivedDelivery, failedWith error: Error) {
      var failed = delivery
      failed.uploadState = .failed
      failed.uploadAttempts += 1
      failed.lastAttemptAt = Date()
      failed.lastUploadError = error.localizedDescription
      archive.update(failed)
      lastError = error.localizedDescription
   }

   private func isDue(_ delivery: ArchivedDelivery) -> Bool {
      guard let last = delivery.lastAttemptAt, delivery.uploadAttempts > 0 else { return true }
      let exponent = min(delivery.uploadAttempts - 1, 12)
      let delay = min(maximumRetryDelay, baseRetryDelay * pow(2, Double(exponent)))
      return Date().timeIntervalSince(last) >= delay
   }

   private func endpointConfig() -> PodEndpointConfig? {
      guard settings.isLinked, let baseURL = settings.siteURL else { return nil }
      return PodEndpointConfig(
         baseURL: baseURL,
         secret: settings.sharedSecret,
         deviceId: settings.deviceId,
         sendCustomerEmail: settings.sendCustomerEmail,
         operationsEmail: settings.operationsEmail
      )
   }
}
