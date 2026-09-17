import SwiftUI

@main
struct CindermarkPODApp: App {
   @StateObject private var model = AppModel()
   @Environment(\.scenePhase) private var scenePhase

   var body: some Scene {
      WindowGroup {
         RootView()
            .environmentObject(model)
            .environmentObject(model.settings)
            .environmentObject(model.shipments)
            .environmentObject(model.archive)
            .environmentObject(model.outbox)
            .environmentObject(model.location)
            .tint(BrandColor.road)
            .task { await model.start() }
      }
      .onChange(of: scenePhase) { _, phase in
         // Coming back to the foreground is the most likely moment for the iPad
         // to have signal again after a basement or a stairwell.
         guard phase == .active else { return }
         Task { await model.outbox.drain() }
      }
   }
}
