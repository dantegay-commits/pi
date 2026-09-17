import SwiftUI
import UniformTypeIdentifiers

/// The run list. Open stops first, then what has already been signed today.
struct StopListView: View {
   @Binding var selection: UUID?

   @EnvironmentObject private var model: AppModel
   @EnvironmentObject private var shipments: ShipmentStore
   @EnvironmentObject private var settings: AppSettings
   @EnvironmentObject private var outbox: OutboxQueue

   @State private var showingSettings = false
   @State private var showingArchive = false
   @State private var editingShipment: Shipment?
   @State private var isImporting = false
   @State private var importError: String?

   var body: some View {
      List(selection: $selection) {
         if shipments.open.isEmpty, shipments.completed.isEmpty {
            emptyRun
         }
         if !shipments.open.isEmpty {
            Section("Open stops") {
               ForEach(shipments.open) { shipment in
                  StopRow(shipment: shipment)
                     .tag(shipment.id)
                     .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                           shipments.delete(shipment)
                        } label: {
                           Label("Remove", systemImage: "trash")
                        }
                        Button {
                           editingShipment = shipment
                        } label: {
                           Label("Edit", systemImage: "pencil")
                        }
                        .tint(BrandColor.slate)
                     }
               }
            }
         }
         if !shipments.completed.isEmpty {
            Section("Signed") {
               ForEach(shipments.completed) { shipment in
                  StopRow(shipment: shipment)
                     .tag(shipment.id)
               }
            }
         }
      }
      .listStyle(.sidebar)
      .navigationTitle("Today's run")
      .toolbar {
         ToolbarItem(placement: .topBarLeading) {
            BrandLogoView(height: 22, showsDivision: false)
               .padding(.vertical, 2)
         }
         ToolbarItem(placement: .primaryAction) {
            Menu {
               Button {
                  editingShipment = Shipment()
               } label: {
                  Label("New stop", systemImage: "plus")
               }
               Button {
                  isImporting = true
               } label: {
                  Label("Import manifest file", systemImage: "square.and.arrow.down")
               }
               Button {
                  Task { await model.syncShipments() }
               } label: {
                  Label("Pull run from site", systemImage: "arrow.triangle.2.circlepath")
               }
               .disabled(!settings.isLinked)
               Divider()
               Button {
                  showingArchive = true
               } label: {
                  Label("Shipped archive", systemImage: "folder")
               }
               Button {
                  showingSettings = true
               } label: {
                  Label("Settings", systemImage: "gearshape")
               }
            } label: {
               Label("Actions", systemImage: "ellipsis.circle")
            }
         }
      }
      .safeAreaInset(edge: .bottom) { uploadStatusBar }
      .sheet(isPresented: $showingSettings) { SettingsView() }
      .sheet(isPresented: $showingArchive) { ArchiveView() }
      .sheet(item: $editingShipment) { shipment in
         ShipmentEditorView(shipment: shipment)
      }
      .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
         switch result {
         case let .success(urls):
            guard let url = urls.first else { return }
            do {
               try shipments.importManifest(from: url)
            } catch {
               importError = error.localizedDescription
            }
         case let .failure(error):
            importError = error.localizedDescription
         }
      }
      .alert("Import failed", isPresented: presenting($importError)) {
         Button("OK", role: .cancel) {}
      } message: {
         Text(importError ?? "")
      }
      .alert("Could not reach the site", isPresented: presenting($model.syncError)) {
         Button("OK", role: .cancel) {}
      } message: {
         Text(model.syncError ?? "")
      }
      .overlay {
         if model.isSyncing { ProgressView().controlSize(.large) }
      }
   }

   private var emptyRun: some View {
      VStack(alignment: .leading, spacing: 8) {
         Text("No stops loaded")
            .font(.headline)
         Text("Add a stop by hand, import a manifest file, or pull the run from the CINDERMARK site.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
      }
      .padding(.vertical, 8)
   }

   @ViewBuilder private var uploadStatusBar: some View {
      let pending = outbox.pendingCount
      if pending > 0 || !outbox.isOnline {
         HStack(spacing: 8) {
            Image(systemName: outbox.isOnline ? "arrow.up.circle" : "wifi.slash")
               .foregroundStyle(outbox.isOnline ? BrandColor.ember : BrandColor.slate)
            VStack(alignment: .leading, spacing: 1) {
               Text(pending == 1 ? "1 delivery waiting to send" : "\(pending) deliveries waiting to send")
                  .font(.footnote.weight(.semibold))
               Text(outbox.isOnline ? "Retrying automatically" : "Offline - they will send when signal returns")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
            }
            Spacer()
            if outbox.isDraining {
               ProgressView()
            } else if outbox.isOnline {
               Button("Send now") {
                  Task { await outbox.drain() }
               }
               .font(.footnote.weight(.semibold))
            }
         }
         .padding(.horizontal, 14)
         .padding(.vertical, 10)
         .background(.bar)
      }
   }
}

private struct StopRow: View {
   let shipment: Shipment

   var body: some View {
      VStack(alignment: .leading, spacing: 5) {
         HStack(spacing: 8) {
            Text(shipment.orderNumber.isBlank ? "No order number" : shipment.orderNumber)
               .font(.subheadline.weight(.bold))
            Spacer()
            if shipment.isCompleted {
               Image(systemName: "checkmark.seal.fill")
                  .foregroundStyle(BrandColor.ember)
                  .accessibilityLabel("Signed")
            }
         }
         Text(shipment.customer.displayName)
            .font(.body.weight(.medium))
            .lineLimit(1)
         if !shipment.customer.address.singleLine.isEmpty {
            Text(shipment.customer.address.singleLine)
               .font(.caption)
               .foregroundStyle(.secondary)
               .lineLimit(2)
         }
         HStack(spacing: 6) {
            StatusPill(title: "\(shipment.lineItems.count) lines", systemImage: "list.bullet")
            if shipment.requiresColdChain {
               StatusPill(title: "Cold chain", systemImage: "thermometer.snowflake", tint: .blue)
            }
            if shipment.hasControlledSubstance {
               StatusPill(title: "Controlled", systemImage: "lock.fill", tint: BrandColor.ember)
            }
         }
      }
      .padding(.vertical, 4)
   }
}
