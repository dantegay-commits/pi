import UIKit

/// Identity of the iPad that captured a record, copied into every POD.
enum DeviceInfo {
   static var model: String {
      UIDevice.current.model
   }

   static var systemVersion: String {
      "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
   }

   static var appVersion: String {
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
   }

   static var appBuild: String {
      Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
   }

   static var versionDisplay: String {
      "\(appVersion) (\(appBuild))"
   }
}
