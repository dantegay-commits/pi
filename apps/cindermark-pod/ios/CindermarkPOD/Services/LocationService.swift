import CoreLocation
import Foundation

/// One-shot location capture, taken at the instant the customer signs.
///
/// The app does not track the vehicle: there is no background mode and no
/// continuous updates. `capture()` asks for a single fix, waits up to
/// `timeout` seconds, and always returns a `CapturedLocation` describing what
/// happened - including the cases where there is no coordinate at all, so a
/// record never implies a fix it does not have.
@MainActor
final class LocationService: NSObject, ObservableObject {
   @Published private(set) var authorizationStatus: CLAuthorizationStatus
   @Published private(set) var isCapturing = false
   @Published private(set) var lastCapture: CapturedLocation?

   private let manager = CLLocationManager()
   private var fixContinuation: CheckedContinuation<CLLocation?, Never>?
   private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
   private let geocoder = CLGeocoder()

   override init() {
      authorizationStatus = manager.authorizationStatus
      super.init()
      manager.delegate = self
      manager.desiredAccuracy = kCLLocationAccuracyBest
   }

   /// Called when the driver first opens the app so the prompt is not the last
   /// thing standing between a waiting customer and a signature.
   func primeAuthorization() {
      guard manager.authorizationStatus == .notDetermined else { return }
      manager.requestWhenInUseAuthorization()
   }

   func capture(reverseGeocode: Bool, timeout: TimeInterval = 10) async -> CapturedLocation {
      isCapturing = true
      defer { isCapturing = false }

      var status = manager.authorizationStatus
      if status == .notDetermined {
         status = await requestAuthorization()
      }

      switch status {
      case .denied:
         return record(CapturedLocation(source: .denied))
      case .restricted:
         return record(CapturedLocation(source: .restricted))
      case .notDetermined:
         return record(CapturedLocation(source: .unavailable))
      default:
         break
      }

      // locationServicesEnabled() can block, so Apple asks that it not be called
      // on the main thread.
      let servicesEnabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
      guard servicesEnabled else {
         return record(CapturedLocation(source: .unavailable))
      }

      guard let fix = await requestFix(timeout: timeout) else {
         return record(CapturedLocation(source: .timedOut))
      }

      var captured = CapturedLocation(
         source: .gps,
         latitude: fix.coordinate.latitude,
         longitude: fix.coordinate.longitude,
         horizontalAccuracyMeters: fix.horizontalAccuracy,
         altitudeMeters: fix.altitude,
         verticalAccuracyMeters: fix.verticalAccuracy,
         fixTimestamp: fix.timestamp,
         isPreciseAuthorization: manager.accuracyAuthorization == .fullAccuracy
      )

      if reverseGeocode {
         captured.resolvedAddress = await address(for: fix)
      }
      return record(captured)
   }

   /// Best-effort street address. A geocode failure is not an error worth
   /// blocking a delivery over; the coordinates are the record of truth.
   private func address(for location: CLLocation) async -> String? {
      guard let placemarks = try? await geocoder.reverseGeocodeLocation(location),
            let mark = placemarks.first
      else { return nil }
      let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
      let cityState = [mark.locality, mark.administrativeArea].compactMap { $0 }.joined(separator: ", ")
      let tail = [cityState, mark.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
      let parts = [street, tail].filter { !$0.isEmpty }
      return parts.isEmpty ? nil : parts.joined(separator: ", ")
   }

   private func record(_ capture: CapturedLocation) -> CapturedLocation {
      lastCapture = capture
      return capture
   }

   private func requestAuthorization() async -> CLAuthorizationStatus {
      if let pending = authContinuation {
         authContinuation = nil
         pending.resume(returning: manager.authorizationStatus)
      }
      return await withCheckedContinuation { continuation in
         authContinuation = continuation
         manager.requestWhenInUseAuthorization()
      }
   }

   private func requestFix(timeout: TimeInterval) async -> CLLocation? {
      // A second capture started before the first finished would otherwise
      // strand the earlier continuation and hang that caller forever.
      finishFix(with: nil)
      let location = await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
         fixContinuation = continuation
         manager.requestLocation()
         Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self?.finishFix(with: nil)
         }
      }
      return location
   }

   /// Single exit point for the fix continuation, so a delegate callback racing
   /// the timeout cannot resume it twice.
   private func finishFix(with location: CLLocation?) {
      guard let continuation = fixContinuation else { return }
      fixContinuation = nil
      continuation.resume(returning: location)
   }
}

extension LocationService: CLLocationManagerDelegate {
   // Core Location delivers these on the queue the manager was created on, but
   // that is not something the compiler can know, so each hops to the main
   // actor explicitly. `finishFix` is the single exit point for the fix
   // continuation, so the hop racing the timeout cannot resume it twice.
   nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
      let status = manager.authorizationStatus
      Task { @MainActor in
         authorizationStatus = status
         guard status != .notDetermined, let continuation = authContinuation else { return }
         authContinuation = nil
         continuation.resume(returning: status)
      }
   }

   nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
      let fix = locations.last
      Task { @MainActor in
         finishFix(with: fix)
      }
   }

   nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
      Task { @MainActor in
         finishFix(with: nil)
      }
   }
}
