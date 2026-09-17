import CoreLocation
import SwiftUI

/// The screen the customer sees. Stripped of anything that is not either the
/// thing being agreed to or the place to sign it.
///
/// The two layouts are driven by size class, not by device, so an iPad in Slide
/// Over gets the narrow arrangement and an iPhone in landscape gets whatever
/// fits. On a wide screen the manifest sits beside the signature; on a narrow
/// one it moves behind a button, because the one thing that must never be
/// squeezed off a phone screen is the box the customer signs in.
///
/// The canvas is never placed inside a `ScrollView`. `PKCanvasView` is itself a
/// scroll view, and nesting the two makes a finger-drawn signature scroll the
/// page instead of drawing.
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
   @State private var showingItems = false

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
                  .frame(width: 330)
                  .background(BrandColor.paper)
               Divider()
               signingColumn
            }
         } else {
            VStack(spacing: 0) {
               compactSummaryBar
               Divider()
               signingColumn
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
         if isWide {
            ToolbarItem(placement: .principal) {
               BrandLogoView(height: 20)
            }
         }
         ToolbarItem(placement: .confirmationAction) {
            Button {
               Task { await submit() }
            } label: {
               Text(isWide ? "Complete delivery" : "Complete").fontWeight(.semibold)
            }
            .disabled(!blockers.isEmpty || isSubmitting)
         }
      }
      .overlay { submittingOverlay }
      .sheet(isPresented: $showingItems) {
         NavigationStack {
            detailColumn
               .navigationTitle("What you are signing for")
               .navigationBarTitleDisplayMode(.inline)
               .toolbar {
                  ToolbarItem(placement: .confirmationAction) {
                     Button("Done") { showingItems = false }
                  }
               }
         }
      }
      .alert("Could not complete this delivery", isPresented: presenting($errorMessage)) {
         Button("OK", role: .cancel) {}
      } message: {
         Text(errorMessage ?? "")
      }
   }

   // MARK: - The manifest, beside the canvas or behind a button

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
                        .frame(minWidth: 26, alignment: .trailing)
                     VStack(alignment: .leading, spacing: 2) {
                        Text(line.item.itemDescription.isBlank ? line.item.sku : line.item.itemDescription)
                           .font(.subheadline)
                           .fixedSize(horizontal: false, vertical: true)
                        if !line.isClean {
                           Text("\(line.disposition.label)\(line.note.isBlank ? "" : " - \(line.note.trimmed)")")
                              .font(.caption)
                              .foregroundStyle(BrandColor.alert)
                              .fixedSize(horizontal: false, vertical: true)
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
                  .fixedSize(horizontal: false, vertical: true)
            }

            captureStatus
         }
         .padding(20)
         .frame(maxWidth: .infinity, alignment: .leading)
      }
   }

   /// Narrow screens get the gist inline and the detail a tap away.
   private var compactSummaryBar: some View {
      Button {
         showingItems = true
      } label: {
         HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
               Text(draft.customer.displayName)
                  .font(.subheadline.weight(.semibold))
                  .lineLimit(1)
               HStack(spacing: 6) {
                  Text("\(draft.unitsReceived) of \(draft.unitsShipped) units")
                  if draft.hasExceptions {
                     Text("·")
                     Text("\(draft.exceptions.count) exception\(draft.exceptions.count == 1 ? "" : "s")")
                        .foregroundStyle(BrandColor.alert)
                  }
               }
               .font(.caption)
               .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("Items & terms")
               .font(.caption.weight(.semibold))
            Image(systemName: "chevron.right")
               .font(.caption2.weight(.semibold))
               .foregroundStyle(.tertiary)
         }
         .padding(.horizontal, 16)
         .padding(.vertical, 10)
         .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Shows every item on this delivery and the wording being agreed to")
   }

   private var captureStatus: some View {
      VStack(alignment: .leading, spacing: 8) {
         SectionHeading(title: "Will be recorded")
         Label(Date().formatted(date: .abbreviated, time: .standard), systemImage: "clock")
            .font(.caption)
         Label(locationStatusText, systemImage: locationStatusIcon)
            .font(.caption)
            .foregroundStyle(locationIsReady ? .secondary : BrandColor.alert)
            .fixedSize(horizontal: false, vertical: true)
         if !settings.driverName.isBlank {
            Label(settings.driverName, systemImage: "person.fill.checkmark")
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
         return "Location is restricted on this device"
      default:
         return "Location permission has not been granted yet"
      }
   }

   private var locationStatusIcon: String {
      locationIsReady ? "location.fill" : "location.slash"
   }

   // MARK: - Signing

   private var signingColumn: some View {
      VStack(alignment: .leading, spacing: isWide ? 14 : 10) {
         signerFields

         if draft.signer.relationship == .other || !draft.signer.relationshipDetail.isBlank {
            TextField("How they are authorised to sign", text: $draft.signer.relationshipDetail)
               .textFieldStyle(.roundedBorder)
         }

         // The canvas takes whatever is left, so it is as large as the screen
         // allows and never scrolled out of reach.
         signatureBox
            .frame(maxHeight: .infinity)
            .layoutPriority(1)

         canvasControls

         if let first = blockers.first {
            Label(first, systemImage: "info.circle")
               .font(.footnote)
               .foregroundStyle(.secondary)
               .fixedSize(horizontal: false, vertical: true)
         }
      }
      .padding(isWide ? 20 : 16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
   }

   @ViewBuilder private var signerFields: some View {
      if isWide {
         HStack(alignment: .bottom, spacing: 16) {
            printedNameField
            relationshipField.frame(width: 210)
         }
      } else {
         printedNameField
         relationshipField
      }
   }

   private var printedNameField: some View {
      VStack(alignment: .leading, spacing: 4) {
         Text("Printed name")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
         TextField("Name of the person receiving", text: $draft.signer.printedName)
            .textContentType(.name)
            .textFieldStyle(.roundedBorder)
            .font(isWide ? .title3 : .body)
      }
   }

   private var relationshipField: some View {
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
   }

   /// The pencil switch and Clear. Side by side when there is room, stacked when
   /// there is not - at the largest accessibility text sizes they will not fit
   /// on one line of a phone.
   @ViewBuilder private var canvasControls: some View {
      ViewThatFits(in: .horizontal) {
         HStack {
            pencilToggle
            Spacer(minLength: 12)
            clearButton
         }
         VStack(alignment: .leading, spacing: 8) {
            pencilToggle
            clearButton
         }
      }
   }

   private var pencilToggle: some View {
      Toggle(isOn: $settings.pencilOnly) {
         Label("Apple Pencil only", systemImage: "applepencil")
            .font(.footnote)
      }
      .toggleStyle(.switch)
      .fixedSize()
   }

   private var clearButton: some View {
      Button(role: .destructive) {
         pad.clear()
      } label: {
         Label("Clear", systemImage: "eraser")
      }
      .disabled(pad.strokeCount == 0)
   }

   private var signatureBox: some View {
      ZStack(alignment: .bottomLeading) {
         RoundedRectangle(cornerRadius: 14)
            .fill(Color.white)
            .overlay {
               RoundedRectangle(cornerRadius: 14)
                  .strokeBorder(pad.strokeCount == 0 ? BrandColor.slate.opacity(0.35) : BrandColor.road, lineWidth: 1.5)
            }

         VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Rectangle()
               .fill(BrandColor.slate.opacity(0.35))
               .frame(height: 1)
               .padding(.horizontal, isWide ? 28 : 18)
            Text("Sign above")
               .font(.caption)
               .foregroundStyle(BrandColor.slate)
               .padding(.leading, isWide ? 28 : 18)
               .padding(.top, 6)
               .padding(.bottom, 14)
         }

         SignatureCanvas(pad: pad, pencilOnly: settings.pencilOnly)
            .clipShape(RoundedRectangle(cornerRadius: 14))
      }
      .frame(minHeight: isWide ? 300 : 170)
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
            .frame(maxWidth: 320)
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
