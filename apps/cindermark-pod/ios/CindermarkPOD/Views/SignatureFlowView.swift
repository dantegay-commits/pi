import CoreLocation
import SwiftUI

/// The screen the customer sees. Full-screen, landscape-friendly, and stripped
/// of anything that is not either the thing being agreed to or the place to
/// sign it.
struct SignatureFlowView: View {
   @ObservedObject var draft: DeliveryDraft

   @EnvironmentObject private var model: AppModel
   @EnvironmentObject private var settings: AppSettings
   @EnvironmentObject private var location: LocationService
   @Environment(\.dismiss) private var dismiss
   @Environment(\.horizontalSizeClass) private var horizontalSizeClass

   @StateObject private var pad = SignaturePad()
   @State private var isSubmitting = false
   @State private var errorMessage: String?
   @State private var outcome: DeliveryOutcome?

   private var isWide: Bool { horizontalSizeClass == .regular }

   private var blockers: [String] {
      var issues = draft.signerIssues()
      if pad.strokeCount == 0 { issues.append("Ask the recipient to sign in the box.") }
      return issues
   }

   var body: some View {
      NavigationStack {
         if let outcome {
            DeliveryCompleteView(outcome: outcome) { dismiss() }
         } else {
            signingScreen
         }
      }
      .interactiveDismissDisabled(isSubmitting)
   }

   private var signingScreen: some View {
      Group {
         if isWide {
            HStack(alignment: .top, spacing: 0) {
               detailColumn
                  .frame(width: 340)
                  .background(BrandColor.paper)
               Divider()
               signingColumn
            }
         } else {
            ScrollView {
               VStack(spacing: 0) {
                  detailColumn
                  signingColumn
                     .frame(minHeight: 420)
               }
            }
         }
      }
      .navigationTitle("Proof of delivery")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
         ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
               .disabled(isSubmitting)
         }
         ToolbarItem(placement: .principal) {
            BrandLogoView(height: 20, showsDivision: false)
         }
         ToolbarItem(placement: .confirmationAction) {
            Button {
               Task { await submit() }
            } label: {
               Text("Complete delivery").fontWeight(.semibold)
            }
            .disabled(!blockers.isEmpty || isSubmitting)
         }
      }
      .overlay { submittingOverlay }
      .alert("Could not complete this delivery", isPresented: presenting($errorMessage)) {
         Button("OK", role: .cancel) {}
      } message: {
         Text(errorMessage ?? "")
      }
   }

   // MARK: - Left column

   private var detailColumn: some View {
      ScrollView {
         VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
               SectionHeading(title: "Order \(draft.shipment.orderNumber)")
               Text(draft.customer.displayName)
                  .font(.title3.weight(.semibold))
               if !draft.customer.address.singleLine.isEmpty {
                  Text(draft.customer.address.singleLine)
                     .font(.footnote)
                     .foregroundStyle(.secondary)
               }
            }

            VStack(alignment: .leading, spacing: 8) {
               SectionHeading(title: "You are signing for")
               ForEach(draft.lines) { line in
                  HStack(alignment: .firstTextBaseline, spacing: 8) {
                     Text("\(line.quantityReceived)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(width: 26, alignment: .trailing)
                     VStack(alignment: .leading, spacing: 2) {
                        Text(line.item.itemDescription.isBlank ? line.item.sku : line.item.itemDescription)
                           .font(.subheadline)
                        if !line.isClean {
                           Text("\(line.disposition.label)\(line.note.isBlank ? "" : " - \(line.note.trimmed)")")
                              .font(.caption)
                              .foregroundStyle(BrandColor.ember)
                        }
                     }
                  }
               }
               Divider()
               Text("\(draft.unitsReceived) of \(draft.unitsShipped) units")
                  .font(.footnote.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
               SectionHeading(title: "Agreement")
               Text(BrandConfig.attestation)
                  .font(.caption)
                  .foregroundStyle(.secondary)
            }

            captureStatus
         }
         .padding(20)
      }
   }

   private var captureStatus: some View {
      VStack(alignment: .leading, spacing: 8) {
         SectionHeading(title: "Will be recorded")
         Label(Date().formatted(date: .abbreviated, time: .standard), systemImage: "clock")
            .font(.caption)
         Label(locationStatusText, systemImage: locationStatusIcon)
            .font(.caption)
            .foregroundStyle(locationIsReady ? .secondary : BrandColor.ember)
         if !settings.driverName.isBlank {
            Label(settings.driverName, systemImage: "person.badge.shield.checkmark")
               .font(.caption)
         }
      }
      .foregroundStyle(.secondary)
   }

   private var locationIsReady: Bool {
      switch location.authorizationStatus {
      case .authorizedAlways, .authorizedWhenInUse: return true
      default: return false
      }
   }

   private var locationStatusText: String {
      switch location.authorizationStatus {
      case .authorizedAlways, .authorizedWhenInUse:
         return "Location at the moment of signing"
      case .denied:
         return "Location is off - the receipt will say so"
      case .restricted:
         return "Location is restricted on this iPad"
      default:
         return "Location permission has not been granted yet"
      }
   }

   private var locationStatusIcon: String {
      locationIsReady ? "location.fill" : "location.slash"
   }

   // MARK: - Right column

   private var signingColumn: some View {
      VStack(alignment: .leading, spacing: 14) {
         HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
               Text("Printed name")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
               TextField("Name of the person receiving", text: $draft.signer.printedName)
                  .textContentType(.name)
                  .textFieldStyle(.roundedBorder)
                  .font(.title3)
            }
            VStack(alignment: .leading, spacing: 4) {
               Text("Relationship")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
               Picker("Relationship", selection: $draft.signer.relationship) {
                  ForEach(SignerRelationship.allCases) { relationship in
                     Text(relationship.label).tag(relationship)
                  }
               }
               .pickerStyle(.menu)
               .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 210)
         }

         if draft.signer.relationship == .other || !draft.signer.relationshipDetail.isBlank {
            TextField("How they are authorised to sign", text: $draft.signer.relationshipDetail)
               .textFieldStyle(.roundedBorder)
         }

         signatureBox

         HStack {
            Toggle(isOn: $settings.pencilOnly) {
               Label("Apple Pencil only", systemImage: "applepencil")
                  .font(.footnote)
            }
            .toggleStyle(.switch)
            .frame(maxWidth: 260)

            Spacer()

            Button(role: .destructive) {
               pad.clear()
            } label: {
               Label("Clear", systemImage: "eraser")
            }
            .disabled(pad.strokeCount == 0)
         }

         if let first = blockers.first {
            Label(first, systemImage: "info.circle")
               .font(.footnote)
               .foregroundStyle(.secondary)
         }
      }
      .padding(20)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
   }

   private var signatureBox: some View {
      ZStack(alignment: .bottomLeading) {
         RoundedRectangle(cornerRadius: 14)
            .fill(Color.white)
            .overlay {
               RoundedRectangle(cornerRadius: 14)
                  .strokeBorder(pad.strokeCount == 0 ? BrandColor.slate.opacity(0.35) : BrandColor.ember, lineWidth: 1.5)
            }

         VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Rectangle()
               .fill(BrandColor.slate.opacity(0.35))
               .frame(height: 1)
               .padding(.horizontal, 28)
            Text("Sign above")
               .font(.caption)
               .foregroundStyle(BrandColor.slate)
               .padding(.leading, 28)
               .padding(.top, 6)
               .padding(.bottom, 14)
         }

         SignatureCanvas(pad: pad, pencilOnly: settings.pencilOnly)
            .clipShape(RoundedRectangle(cornerRadius: 14))
      }
      .frame(minHeight: 300)
      .accessibilityLabel("Signature area")
   }

   @ViewBuilder private var submittingOverlay: some View {
      if isSubmitting {
         ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
               ProgressView()
                  .controlSize(.large)
               Text("Recording delivery")
                  .font(.headline)
               Text("Capturing location, filing the receipt and sending it on.")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
                  .multilineTextAlignment(.center)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
         }
      }
   }

   // MARK: - Submit

   private func submit() async {
      guard blockers.isEmpty else { return }
      guard let signature = pad.export(inputPolicy: settings.pencilOnly ? "pencilOnly" : "anyInput") else {
         errorMessage = DeliveryServiceError.noSignature.localizedDescription
         return
      }
      isSubmitting = true
      defer { isSubmitting = false }
      do {
         outcome = try await model.deliveryService.complete(draft: draft, signature: signature)
      } catch {
         errorMessage = error.localizedDescription
      }
   }
}
