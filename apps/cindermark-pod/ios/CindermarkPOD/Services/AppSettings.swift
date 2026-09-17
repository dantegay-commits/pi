import Foundation

/// Operator configuration. Everything here except the two secrets lives in
/// UserDefaults; the shared secret and device id live in the keychain.
@MainActor
final class AppSettings: ObservableObject {
   private enum Key {
      static let siteURL = "siteURL"
      static let driverName = "driverName"
      static let operationsEmail = "operationsEmail"
      static let pencilOnly = "pencilOnly"
      static let requireLocation = "requireLocation"
      static let reverseGeocode = "reverseGeocode"
      static let sendCustomerEmail = "sendCustomerEmail"
   }

   private let defaults: UserDefaults

   @Published var siteURLString: String { didSet { defaults.set(siteURLString, forKey: Key.siteURL) } }
   @Published var driverName: String { didSet { defaults.set(driverName, forKey: Key.driverName) } }
   @Published var operationsEmail: String { didSet { defaults.set(operationsEmail, forKey: Key.operationsEmail) } }
   /// When on, the signature canvas ignores finger touches so a hand resting on
   /// the glass cannot add strokes.
   @Published var pencilOnly: Bool { didSet { defaults.set(pencilOnly, forKey: Key.pencilOnly) } }
   /// When on, a stop cannot be signed without a coordinate fix.
   @Published var requireLocation: Bool { didSet { defaults.set(requireLocation, forKey: Key.requireLocation) } }
   @Published var reverseGeocode: Bool { didSet { defaults.set(reverseGeocode, forKey: Key.reverseGeocode) } }
   @Published var sendCustomerEmail: Bool { didSet { defaults.set(sendCustomerEmail, forKey: Key.sendCustomerEmail) } }

   /// Mirrors the keychain so SwiftUI can bind to it.
   @Published var sharedSecret: String { didSet { KeychainStore.set(sharedSecret, for: .sharedSecret) } }

   let deviceId: String

   init(defaults: UserDefaults = .standard) {
      self.defaults = defaults
      defaults.register(defaults: [
         Key.pencilOnly: true,
         Key.requireLocation: true,
         Key.reverseGeocode: true,
         Key.sendCustomerEmail: true,
      ])
      siteURLString = defaults.string(forKey: Key.siteURL) ?? ""
      driverName = defaults.string(forKey: Key.driverName) ?? ""
      operationsEmail = defaults.string(forKey: Key.operationsEmail) ?? ""
      pencilOnly = defaults.bool(forKey: Key.pencilOnly)
      requireLocation = defaults.bool(forKey: Key.requireLocation)
      reverseGeocode = defaults.bool(forKey: Key.reverseGeocode)
      sendCustomerEmail = defaults.bool(forKey: Key.sendCustomerEmail)
      sharedSecret = KeychainStore.string(for: .sharedSecret) ?? ""
      deviceId = KeychainStore.deviceIdentifier()
   }

   /// Base site URL, normalised: scheme forced to https, trailing slash removed.
   var siteURL: URL? {
      var trimmed = siteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      if !trimmed.lowercased().hasPrefix("http") { trimmed = "https://" + trimmed }
      while trimmed.hasSuffix("/") { trimmed.removeLast() }
      guard let url = URL(string: trimmed), let host = url.host, host.contains(".") else { return nil }
      return url
   }

   /// `https://site.example/wp-json/cindermark/v1/<route>`
   func endpoint(_ route: String) -> URL? {
      siteURL?.appendingPathComponent("wp-json/cindermark/v1/\(route)")
   }

   /// Uploads are refused rather than queued forever when the app has never been
   /// paired with a site.
   var isLinked: Bool {
      siteURL != nil && !sharedSecret.trimmingCharacters(in: .whitespaces).isEmpty
   }

   var courier: Courier {
      Courier(
         driverName: driverName,
         deviceId: deviceId,
         deviceModel: DeviceInfo.model,
         systemVersion: DeviceInfo.systemVersion,
         appVersion: DeviceInfo.appVersion,
         appBuild: DeviceInfo.appBuild
      )
   }
}
