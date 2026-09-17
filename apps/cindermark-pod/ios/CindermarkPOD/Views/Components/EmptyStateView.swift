import SwiftUI

/// Centred placeholder for an empty list or an unselected detail pane.
///
/// Stands in for `ContentUnavailableView`, which is iOS 17 only. The app runs
/// back to iOS 16 so that iPhone 8, iPhone X and the 5th-generation iPad are
/// still usable, and those are exactly the hand-me-down devices a small fleet
/// ends up running.
struct EmptyStateView: View {
   let title: String
   var systemImage: String?
   var message: String?

   var body: some View {
      VStack(spacing: 12) {
         if let systemImage {
            Image(systemName: systemImage)
               .font(.system(size: 42))
               .foregroundStyle(.tertiary)
         }
         Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
         if let message {
            Text(message)
               .font(.subheadline)
               .foregroundStyle(.tertiary)
               .multilineTextAlignment(.center)
               .frame(maxWidth: 380)
         }
      }
      .padding(32)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityElement(children: .combine)
   }
}
