import SwiftUI

/// Create or correct a stop on the iPad, for operations that dispatch by phone
/// or paper rather than from the site.
struct ShipmentEditorView: View {
   @State private var draft: Shipment
   @EnvironmentObject private var shipments: ShipmentStore
   @Environment(\.dismiss) private var dismiss

   private let isNew: Bool

   init(shipment: Shipment) {
      _draft = State(initialValue: shipment)
      isNew = shipment.orderNumber.isEmpty && shipment.lineItems.isEmpty
   }

   var body: some View {
      NavigationStack {
         Form {
            Section {
               LabeledContent("Order number") {
                  TextField("SO-10482", text: $draft.orderNumber)
                     .multilineTextAlignment(.trailing)
               }
               LabeledContent("Purchase order") {
                  TextField("Optional", text: $draft.purchaseOrder)
                     .multilineTextAlignment(.trailing)
               }
               LabeledContent("Service level") {
                  TextField("Routine", text: $draft.serviceLevel)
                     .multilineTextAlignment(.trailing)
               }
               DatePicker("Scheduled", selection: $draft.scheduledFor)
               Stepper("Pieces: \(draft.pieceCount)", value: $draft.pieceCount, in: 1 ... 99)
               Toggle("Cold chain shipment", isOn: $draft.coldChainRequired)
            } header: {
               SectionHeading(title: "Order")
            }

            Section {
               TextField("Facility or company", text: $draft.customer.companyName)
               TextField("Contact name", text: $draft.customer.contactName)
               TextField("Email", text: $draft.customer.email)
                  .textContentType(.emailAddress)
                  .keyboardType(.emailAddress)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
               TextField("Phone", text: $draft.customer.phone)
                  .keyboardType(.phonePad)
               TextField("Account number", text: $draft.customer.accountNumber)
            } header: {
               SectionHeading(title: "Customer")
            }

            Section {
               TextField("Street", text: $draft.customer.address.line1)
               TextField("Suite, unit, floor", text: $draft.customer.address.line2)
               TextField("City", text: $draft.customer.address.city)
               HStack {
                  TextField("State", text: $draft.customer.address.state)
                  TextField("ZIP", text: $draft.customer.address.postalCode)
                     .keyboardType(.numbersAndPunctuation)
               }
            } header: {
               SectionHeading(title: "Delivery address")
            }

            Section {
               ForEach($draft.lineItems) { $item in
                  NavigationLink {
                     LineItemEditorView(item: $item)
                  } label: {
                     VStack(alignment: .leading, spacing: 3) {
                        Text(item.sku.isBlank ? "New item" : item.sku)
                           .font(.subheadline.weight(.semibold))
                        Text(item.itemDescription.isBlank ? "Tap to describe" : item.itemDescription)
                           .font(.caption)
                           .foregroundStyle(.secondary)
                           .lineLimit(2)
                        Text("\(item.quantityShipped) \(item.unitOfMeasure)")
                           .font(.caption.monospacedDigit())
                           .foregroundStyle(.tertiary)
                     }
                  }
               }
               .onDelete { offsets in
                  draft.lineItems.remove(atOffsets: offsets)
               }
               Button {
                  draft.lineItems.append(LineItem())
               } label: {
                  Label("Add item", systemImage: "plus.circle")
               }
            } header: {
               SectionHeading(title: "Shipment contents")
            } footer: {
               Text("Everything listed here is printed on the customer's receipt, with the quantity they actually received.")
            }

            Section {
               TextField("Instructions for the driver", text: $draft.deliveryInstructions, axis: .vertical)
                  .lineLimit(2 ... 5)
            } header: {
               SectionHeading(title: "Dispatch notes")
            }
         }
         .formStyle(.grouped)
         .navigationTitle(isNew ? "New stop" : "Edit stop")
         .navigationBarTitleDisplayMode(.inline)
         .toolbar {
            ToolbarItem(placement: .cancellationAction) {
               Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
               Button("Save") {
                  shipments.upsert(draft)
                  dismiss()
               }
               .fontWeight(.semibold)
               .disabled(draft.orderNumber.isBlank || draft.lineItems.isEmpty)
            }
         }
      }
   }
}

private struct LineItemEditorView: View {
   @Binding var item: LineItem
   @State private var hasExpiration: Bool

   init(item: Binding<LineItem>) {
      _item = item
      _hasExpiration = State(initialValue: item.wrappedValue.expirationDate != nil)
   }

   var body: some View {
      Form {
         Section {
            LabeledContent("SKU") {
               TextField("CM-OXY-5L", text: $item.sku)
                  .multilineTextAlignment(.trailing)
            }
            TextField("Description", text: $item.itemDescription, axis: .vertical)
               .lineLimit(1 ... 4)
            LabeledContent("Manufacturer") {
               TextField("Optional", text: $item.manufacturer)
                  .multilineTextAlignment(.trailing)
            }
            LabeledContent("HCPCS") {
               TextField("Optional", text: $item.hcpcsCode)
                  .multilineTextAlignment(.trailing)
            }
         } header: {
            SectionHeading(title: "Item")
         }

         Section {
            Stepper("Quantity: \(item.quantityShipped)", value: $item.quantityShipped, in: 1 ... 999)
            LabeledContent("Unit") {
               TextField("EA", text: $item.unitOfMeasure)
                  .multilineTextAlignment(.trailing)
            }
         } header: {
            SectionHeading(title: "Quantity")
         }

         Section {
            LabeledContent("Lot") {
               TextField("Optional", text: $item.lotNumber)
                  .multilineTextAlignment(.trailing)
            }
            LabeledContent("Serial") {
               TextField("Optional", text: $item.serialNumber)
                  .multilineTextAlignment(.trailing)
            }
            Toggle("Has an expiration date", isOn: $hasExpiration)
            if hasExpiration {
               DatePicker(
                  "Expires",
                  selection: Binding(
                     get: { item.expirationDate ?? Date() },
                     set: { item.expirationDate = $0 }
                  ),
                  displayedComponents: .date
               )
            }
            Toggle("Cold chain", isOn: $item.coldChain)
            Toggle("Controlled substance", isOn: $item.controlledSubstance)
         } header: {
            SectionHeading(title: "Traceability")
         } footer: {
            Text("Lot, serial and expiration are printed on the receipt, which is what makes it useful for a recall.")
         }
      }
      .formStyle(.grouped)
      .navigationTitle(item.sku.isBlank ? "Item" : item.sku)
      .navigationBarTitleDisplayMode(.inline)
      .onChange(of: hasExpiration) { enabled in
         if !enabled { item.expirationDate = nil }
      }
   }
}
