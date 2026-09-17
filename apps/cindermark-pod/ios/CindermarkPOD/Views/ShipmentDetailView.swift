import SwiftUI

/// The stop being worked: check the manifest with the customer, then hand over
/// the iPad.
struct ShipmentDetailView: View {
   let shipment: Shipment

   @EnvironmentObject private var settings: AppSettings
   @Environment(\.horizontalSizeClass) private var horizontalSizeClass
   @StateObject private var draft: DeliveryDraft
   @State private var showingSignature = false

   private var isWide: Bool { horizontalSizeClass == .regular }

   init(shipment: Shipment) {
      self.shipment = shipment
      _draft = StateObject(wrappedValue: DeliveryDraft(shipment: shipment))
   }

   private var issues: [String] {
      draft.manifestIssues(requireCustomerEmail: settings.sendCustomerEmail)
   }

   var body: some View {
      Group {
         if shipment.isCompleted {
            CompletedStopView(shipment: shipment)
         } else {
            captureForm
         }
      }
      .navigationTitle(shipment.orderNumber.isBlank ? "Stop" : shipment.orderNumber)
      .navigationBarTitleDisplayMode(.inline)
      .fullScreenCover(isPresented: $showingSignature) {
         // The cover shows its own confirmation and then closes; by the time it
         // is gone the stop is completed, so this view switches to the archived
         // record on its own.
         SignatureFlowView(draft: draft)
      }
   }

   private var captureForm: some View {
      Form {
         Section {
            recipientCard
         } header: {
            SectionHeading(title: "Delivering to")
         }

         Section {
            ForEach(draft.lines) { line in
               ManifestLineEditor(line: line, draft: draft)
            }
         } header: {
            HStack {
               SectionHeading(title: "Shipment contents")
               Spacer()
               Button("Mark all received") {
                  for line in draft.lines {
                     draft.setDisposition(.received, for: line.id)
                  }
               }
               .font(.caption.weight(.semibold))
               .textCase(nil)
            }
         } footer: {
            Text("Check each line with the customer. Anything short, damaged or refused needs a note; the note is printed on their receipt.")
         }

         Section {
            TextField("Anything worth recording about this delivery", text: $draft.deliveryNotes, axis: .vertical)
               .lineLimit(2 ... 6)
         } header: {
            SectionHeading(title: "Delivery notes")
         }

         if !shipment.deliveryInstructions.isBlank {
            Section {
               Text(shipment.deliveryInstructions)
                  .font(.subheadline)
            } header: {
               SectionHeading(title: "Dispatch instructions")
            }
         }
      }
      .formStyle(.grouped)
      .safeAreaInset(edge: .bottom) { actionBar }
   }

   private var recipientCard: some View {
      VStack(alignment: .leading, spacing: 12) {
         Text(draft.customer.displayName)
            .font(.title3.weight(.semibold))
         if !draft.customer.address.singleLine.isEmpty {
            Text(draft.customer.address.singleLine)
               .font(.subheadline)
               .foregroundStyle(.secondary)
         }
         LabeledField(label: "Contact", prompt: "Name", text: $draft.customer.contactName)
         LabeledField(
            label: "Email receipt to",
            prompt: "name@example.com",
            text: $draft.customer.email,
            contentType: .emailAddress,
            keyboard: .emailAddress,
            autocapitalize: false,
            foreground: emailIsUsable ? nil : BrandColor.alert
         )
         if !draft.customer.phone.isBlank {
            LabeledContent("Phone", value: draft.customer.phone)
         }
      }
      .padding(.vertical, 4)
   }

   private var emailIsUsable: Bool {
      draft.customer.email.isBlank || draft.customer.hasUsableEmail
   }

   private var actionBar: some View {
      VStack(spacing: 10) {
         if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
               ForEach(issues, id: \.self) { issue in
                  Label(issue, systemImage: "exclamationmark.triangle.fill")
                     .font(.footnote)
                     .foregroundStyle(BrandColor.alert)
               }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
         }

         if isWide {
            HStack(spacing: 16) {
               receiptSummary
               Spacer()
               signatureButton
            }
         } else {
            VStack(spacing: 10) {
               receiptSummary
                  .frame(maxWidth: .infinity, alignment: .leading)
               signatureButton
                  .frame(maxWidth: .infinity)
            }
         }
      }
      .padding(.horizontal, isWide ? 20 : 16)
      .padding(.vertical, 14)
      .background(.bar)
   }

   private var receiptSummary: some View {
      VStack(alignment: .leading, spacing: 2) {
         Text("\(draft.unitsReceived) of \(draft.unitsShipped) units received")
            .font(.subheadline.weight(.semibold))
         if draft.hasExceptions {
            Text("\(draft.exceptions.count) exception\(draft.exceptions.count == 1 ? "" : "s") recorded")
               .font(.caption)
               .foregroundStyle(BrandColor.alert)
         } else {
            Text("No exceptions")
               .font(.caption)
               .foregroundStyle(.secondary)
         }
      }
   }

   private var signatureButton: some View {
      Button {
         showingSignature = true
      } label: {
         Label("Capture signature", systemImage: "signature")
            .font(.headline)
            .frame(maxWidth: isWide ? nil : .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!issues.isEmpty)
   }
}

/// One manifest line with the controls a driver needs at the door.
private struct ManifestLineEditor: View {
   let line: ReceivedLineItem
   @ObservedObject var draft: DeliveryDraft

   @Environment(\.horizontalSizeClass) private var horizontalSizeClass

   private var isWide: Bool { horizontalSizeClass == .regular }

   var body: some View {
      VStack(alignment: .leading, spacing: 10) {
         HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.item.sku.isBlank ? "-" : line.item.sku)
               .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            Text(line.item.itemDescription.isBlank ? "(no description)" : line.item.itemDescription)
               .font(.subheadline)
               .frame(maxWidth: .infinity, alignment: .leading)
         }

         FlowingPills(spacing: 6) {
            if !line.item.lotNumber.isBlank {
               StatusPill(title: "Lot \(line.item.lotNumber)")
            }
            if !line.item.serialNumber.isBlank {
               StatusPill(title: "S/N \(line.item.serialNumber)")
            }
            if let expires = line.item.expirationDate {
               StatusPill(title: "Exp \(expires.formatted(.dateTime.month().year()))")
            }
            if line.item.coldChain {
               StatusPill(title: "Cold chain", systemImage: "thermometer.snowflake", tint: .blue)
            }
            if line.item.controlledSubstance {
               StatusPill(title: "Controlled", systemImage: "lock.fill", tint: BrandColor.alert)
            }
         }

         if isWide {
            HStack(spacing: 16) {
               quantityStepper.frame(maxWidth: 260)
               dispositionPicker
            }
         } else {
            quantityStepper
            dispositionPicker
         }

         if !line.isClean {
            TextField(
               "Why: damaged box, wrong count, customer refused...",
               text: Binding(
                  get: { line.note },
                  set: { draft.setNote($0, for: line.id) }
               ),
               axis: .vertical
            )
            .lineLimit(1 ... 3)
            .textFieldStyle(.roundedBorder)
            .overlay(alignment: .leading) {
               if line.needsNote {
                  Rectangle()
                     .fill(BrandColor.alert)
                     .frame(width: 3)
                     .padding(.vertical, 2)
                     .offset(x: -8)
               }
            }
         }
      }
      .padding(.vertical, 6)
   }

   private var quantityStepper: some View {
      Stepper(
         value: Binding(
            get: { line.quantityReceived },
            set: { draft.setQuantityReceived($0, for: line.id) }
         ),
         in: 0 ... max(line.item.quantityShipped, 0)
      ) {
         Text("\(line.quantityReceived) of \(line.item.quantityShipped) \(line.item.unitOfMeasure)")
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
      }
   }

   private var dispositionPicker: some View {
      Picker(
         "Status",
         selection: Binding(
            get: { line.disposition },
            set: { draft.setDisposition($0, for: line.id) }
         )
      ) {
         ForEach(ItemDisposition.allCases) { disposition in
            Text(disposition.label).tag(disposition)
         }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
   }
}

/// Shown once a stop has been signed.
private struct CompletedStopView: View {
   let shipment: Shipment
   @EnvironmentObject private var archive: ShippedArchive

   private var delivery: ArchivedDelivery? {
      guard let recordId = shipment.completedRecordId else { return nil }
      return archive.delivery(id: recordId)
   }

   var body: some View {
      Group {
         if let delivery {
            DeliveryDetailView(delivery: delivery)
         } else {
            EmptyStateView(
               title: "Signed",
               systemImage: "checkmark.seal",
               message: "This stop was signed on another device, or its archived copy is missing from this one."
            )
         }
      }
   }
}
