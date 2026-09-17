import CoreLocation
import SwiftUI
import UIKit

struct SettingsView: View {
   @EnvironmentObject private var settings: AppSettings
   @EnvironmentObject private var shipments: ShipmentStore
   @EnvironmentObject private var archive: ShippedArchive
   @EnvironmentObject private var location: LocationService
   @Environment(\.dismiss) private var dismiss

   @State private var isTesting = false
   @State private var testResult: String?
   @State private var testFailed = false

   var body: some View {
      NavigationStack {
         Form {
            siteSection
            courierSection
            captureSection
            brandingSection
            dataSection
            aboutSection
         }
         .formStyle(.grouped)
         .navigationTitle("Settings")
         .navigationBarTitleDisplayMode(.inline)
         .toolbar {
            ToolbarItem(placement: .confirmationAction) {
               Button("Done") { dismiss() }
                  .fontWeight(.semibold)
            }
         }
      }
   }

   private var siteSection: some View {
      Section {
         LabeledContent("Site address") {
            TextField("cindermarklogistics.com", text: $settings.siteURLString)
               .textContentType(.URL)
               .keyboardType(.URL)
               .textInputAutocapitalization(.never)
               .autocorrectionDisabled()
               .multilineTextAlignment(.trailing)
         }
         LabeledContent("Pairing secret") {
            SecureField("Paste from the plugin settings", text: $settings.sharedSecret)
               .multilineTextAlignment(.trailing)
         }
         LabeledContent("This iPad") {
            Text(settings.deviceId)
               .font(.system(.footnote, design: .monospaced))
               .textSelection(.enabled)
               .foregroundStyle(.secondary)
         }
         Button {
            Task { await testConnection() }
         } label: {
            HStack {
               Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
               if isTesting {
                  Spacer()
                  ProgressView()
               }
            }
         }
         .disabled(!settings.isLinked || isTesting)

         if let testResult {
            Label(testResult, systemImage: testFailed ? "xmark.octagon.fill" : "checkmark.circle.fill")
               .font(.footnote)
               .foregroundStyle(testFailed ? BrandColor.alert : .green)
         }
      } header: {
         SectionHeading(title: "CINDERMARK site")
      } footer: {
         Text("The signed receipt is posted to your WordPress site, which emails the customer from your business address. Add the site address and the pairing secret shown on the plugin's settings page.")
      }
   }

   private var courierSection: some View {
      Section {
         LabeledContent("Driver name") {
            TextField("Printed on every receipt", text: $settings.driverName)
               .multilineTextAlignment(.trailing)
         }
         LabeledContent("Copy receipts to") {
            TextField("dispatch@example.com", text: $settings.operationsEmail)
               .textContentType(.emailAddress)
               .keyboardType(.emailAddress)
               .textInputAutocapitalization(.never)
               .autocorrectionDisabled()
               .multilineTextAlignment(.trailing)
         }
         Toggle("Email the customer a copy", isOn: $settings.sendCustomerEmail)
      } header: {
         SectionHeading(title: "Courier")
      } footer: {
         Text("Turning off the customer email still files the delivery on the site and on this iPad.")
      }
   }

   private var captureSection: some View {
      Section {
         Toggle(isOn: $settings.pencilOnly) {
            Label("Apple Pencil only", systemImage: "applepencil")
         }
         Toggle(isOn: $settings.requireLocation) {
            Label("Require a location fix", systemImage: "location.fill")
         }
         Toggle(isOn: $settings.reverseGeocode) {
            Label("Look up the street address", systemImage: "map")
         }
         LabeledContent("Location permission") {
            Text(authorizationLabel)
               .foregroundStyle(.secondary)
         }
         if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
            Button("Open iPad Settings") {
               guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
               UIApplication.shared.open(url)
            }
         }
      } header: {
         SectionHeading(title: "Signature capture")
      } footer: {
         Text("With Apple Pencil only, a hand resting on the screen cannot add strokes. Requiring a fix stops a delivery being signed with no location on the record.")
      }
   }

   private var brandingSection: some View {
      Section {
         HStack {
            BrandLogoView(height: 30)
            Spacer()
            StatusPill(
               title: BrandLogo.hasArtwork ? "Logo installed" : "Placeholder wordmark",
               systemImage: BrandLogo.hasArtwork ? "checkmark.seal.fill" : "exclamationmark.circle",
               tint: BrandLogo.hasArtwork ? .green : BrandColor.alert
            )
         }
      } header: {
         SectionHeading(title: "Branding")
      } footer: {
         Text("Add the CINDERMARK artwork to LogoPrimary, LogoDocument and LogoMark in the project's asset catalog and rebuild. Until then the app and the receipts use a plain wordmark.")
      }
   }

   private var dataSection: some View {
      Section {
         LabeledContent("Stops loaded", value: "\(shipments.shipments.count)")
         LabeledContent("Deliveries filed", value: "\(archive.deliveries.count)")
         LabeledContent("Waiting to send", value: "\(archive.pendingUploads.count)")
         Button("Load a sample stop") {
            shipments.loadSampleStop()
         }
         Button("Rescan the Shipped folder") {
            archive.reload()
         }
      } header: {
         SectionHeading(title: "On this iPad")
      } footer: {
         Text("Signed deliveries live in Files under On My iPad > CINDERMARK POD > Shipped, filed by year and month.")
      }
   }

   private var aboutSection: some View {
      Section {
         LabeledContent("App version", value: DeviceInfo.versionDisplay)
         LabeledContent("Device", value: DeviceInfo.model)
         LabeledContent("System", value: DeviceInfo.systemVersion)
      } header: {
         SectionHeading(title: "About")
      } footer: {
         Text(BrandConfig.footerLine)
      }
   }

   private var authorizationLabel: String {
      switch location.authorizationStatus {
      case .authorizedAlways, .authorizedWhenInUse:
         return location.authorizationStatus == .authorizedAlways ? "Always" : "While using the app"
      case .denied: return "Denied"
      case .restricted: return "Restricted"
      case .notDetermined: return "Not asked yet"
      @unknown default: return "Unknown"
      }
   }

   private func testConnection() async {
      guard let baseURL = settings.siteURL else { return }
      isTesting = true
      defer { isTesting = false }
      let client = PodAPIClient(config: PodEndpointConfig(
         baseURL: baseURL,
         secret: settings.sharedSecret,
         deviceId: settings.deviceId,
         sendCustomerEmail: settings.sendCustomerEmail,
         operationsEmail: settings.operationsEmail
      ))
      do {
         let result = try await client.ping()
         testFailed = false
         var parts = ["Connected"]
         if let site = result.site { parts.append(site) }
         if let version = result.pluginVersion { parts.append("plugin \(version)") }
         if let from = result.mailFrom { parts.append("mail from \(from)") }
         testResult = parts.joined(separator: " - ")
      } catch {
         testFailed = true
         testResult = error.localizedDescription
      }
   }
}
