import SwiftUI

/// Everything in the Shipped folder, newest first.
struct ArchiveView: View {
   @EnvironmentObject private var archive: ShippedArchive
   @Environment(\.dismiss) private var dismiss
   @State private var selected: ArchivedDelivery?
   @State private var query = ""

   private var groups: [(title: String, deliveries: [ArchivedDelivery])] {
      let trimmed = query.trimmed.lowercased()
      let groups = archive.groupedByMonth()
      guard !trimmed.isEmpty else { return groups }
      return groups.compactMap { group in
         let matches = group.deliveries.filter { delivery in
            delivery.record.orderNumber.lowercased().contains(trimmed)
               || delivery.record.customer.displayName.lowercased().contains(trimmed)
               || delivery.record.signer.printedName.lowercased().contains(trimmed)
         }
         return matches.isEmpty ? nil : (group.title, matches)
      }
   }

   var body: some View {
      NavigationSplitView {
         List(selection: $selected) {
            ForEach(groups, id: \.title) { group in
               Section(group.title) {
                  ForEach(group.deliveries) { delivery in
                     ArchiveRow(delivery: delivery)
                        .tag(delivery)
                  }
               }
            }
         }
         .searchable(text: $query, prompt: "Order, customer or signer")
         .navigationTitle("Shipped")
         .toolbar {
            ToolbarItem(placement: .cancellationAction) {
               Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
               Button {
                  archive.reload()
               } label: {
                  Label("Refresh", systemImage: "arrow.clockwise")
               }
            }
         }
         .overlay {
            if archive.deliveries.isEmpty {
               ContentUnavailableView(
                  "Nothing shipped yet",
                  systemImage: "folder",
                  description: Text("Signed deliveries are filed here by month, and in the Files app under CINDERMARK POD.")
               )
            }
         }
      } detail: {
         NavigationStack {
            if let selected {
               DeliveryDetailView(delivery: selected)
                  .id(selected.id)
            } else {
               ContentUnavailableView("Select a delivery", systemImage: "doc.text")
            }
         }
      }
   }
}

private struct ArchiveRow: View {
   let delivery: ArchivedDelivery

   var body: some View {
      VStack(alignment: .leading, spacing: 4) {
         HStack {
            Text(delivery.record.orderNumber.isBlank ? "No order number" : delivery.record.orderNumber)
               .font(.subheadline.weight(.bold))
            Spacer()
            switch delivery.uploadState {
            case .uploaded:
               Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .pending:
               Image(systemName: "clock").foregroundStyle(.secondary)
            case .failed:
               Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(BrandColor.ember)
            }
         }
         Text(delivery.record.customer.displayName)
            .font(.body)
            .lineLimit(1)
         Text(delivery.record.signedAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
      }
      .padding(.vertical, 3)
   }
}
