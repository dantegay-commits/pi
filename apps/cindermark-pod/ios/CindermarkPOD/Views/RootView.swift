import SwiftUI

/// iPad-first split layout: the run on the left, the stop being worked on the
/// right. On iPhone the same views stack into a push navigation.
struct RootView: View {
   @EnvironmentObject private var shipments: ShipmentStore
   @State private var selectedStop: UUID?
   @State private var columnVisibility = NavigationSplitViewVisibility.all

   var body: some View {
      NavigationSplitView(columnVisibility: $columnVisibility) {
         StopListView(selection: $selectedStop)
      } detail: {
         // No NavigationStack here: the detail column is already a navigation
         // container, and on a phone - where the split view collapses into one
         // stack - nesting a second one gives the pushed screen two title bars.
         if let id = selectedStop, let shipment = shipments.shipment(id: id) {
            ShipmentDetailView(shipment: shipment)
               .id(shipment.id)
         } else {
            NoStopSelectedView()
         }
      }
      .navigationSplitViewStyle(.balanced)
   }
}

struct NoStopSelectedView: View {
   var body: some View {
      VStack(spacing: 18) {
         BrandLockupView(width: 210)
         Text("Select a stop to begin")
            .font(.title3.weight(.medium))
            .foregroundStyle(.secondary)
         Text("Check the manifest with the customer, then capture their signature.")
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(BrandColor.paper)
   }
}
