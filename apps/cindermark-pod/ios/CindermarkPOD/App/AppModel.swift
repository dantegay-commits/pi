import SwiftUI

/// Wires the services together and owns their lifetime.
@MainActor
final class AppModel: ObservableObject {
   let settings: AppSettings
   let shipments: ShipmentStore
   let archive: ShippedArchive
   let outbox: OutboxQueue
   let location: LocationService

   @Published var syncError: String?
   @Published var isSyncing = false

   init() {
      let settings = AppSettings()
      let archive = ShippedArchive()
      self.settings = settings
      self.archive = archive
      shipments = ShipmentStore()
      outbox = OutboxQueue(archive: archive, settings: settings)
      location = LocationService()
   }

   var deliveryService: DeliveryService {
      DeliveryService(
         settings: settings,
         location: location,
         archive: archive,
         shipments: shipments,
         outbox: outbox
      )
   }

   func start() async {
      outbox.startMonitoring()
      location.primeAuthorization()
      await outbox.drain()
   }

   /// Pulls the run list from the site, when the site is the dispatch source.
   func syncShipments() async {
      guard settings.isLinked, let baseURL = settings.siteURL else {
         syncError = PodAPIError.notLinked.localizedDescription
         return
      }
      isSyncing = true
      defer { isSyncing = false }
      let client = PodAPIClient(config: PodEndpointConfig(
         baseURL: baseURL,
         secret: settings.sharedSecret,
         deviceId: settings.deviceId,
         sendCustomerEmail: settings.sendCustomerEmail,
         operationsEmail: settings.operationsEmail
      ))
      do {
         let incoming = try await client.fetchShipments()
         let data = try PodCoding.encoder().encode(ShipmentEnvelope(shipments: incoming))
         try shipments.importManifest(data: data)
         syncError = nil
      } catch {
         syncError = error.localizedDescription
      }
   }
}
