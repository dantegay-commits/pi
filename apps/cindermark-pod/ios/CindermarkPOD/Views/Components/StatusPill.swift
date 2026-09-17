import SwiftUI

/// Compact status chip used in list rows and toolbars.
struct StatusPill: View {
   let title: String
   var systemImage: String?
   var tint: Color = BrandColor.slate

   var body: some View {
      HStack(spacing: 4) {
         if let systemImage {
            Image(systemName: systemImage)
               .font(.caption2.weight(.semibold))
         }
         Text(title)
            .font(.caption.weight(.semibold))
      }
      .foregroundStyle(tint)
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(tint.opacity(0.12), in: Capsule())
      .accessibilityElement(children: .combine)
      .accessibilityLabel(title)
   }
}

/// Label/value row used throughout the detail panes.
///
/// Side by side on a wide screen. On a phone the fixed label column would leave
/// roughly 200pt for values like a 64-character SHA-256, so there the label
/// moves above the value and the value gets the full width.
struct DetailRow: View {
   let label: String
   let value: String
   var monospaced = false

   @Environment(\.horizontalSizeClass) private var horizontalSizeClass

   private var labelText: some View {
      Text(label)
         .font(.subheadline)
         .foregroundStyle(.secondary)
   }

   private var valueText: some View {
      Text(value)
         .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
         .textSelection(.enabled)
         .fixedSize(horizontal: false, vertical: true)
   }

   var body: some View {
      Group {
         if horizontalSizeClass == .regular {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
               labelText.frame(width: 150, alignment: .leading)
               valueText.frame(maxWidth: .infinity, alignment: .leading)
            }
         } else {
            VStack(alignment: .leading, spacing: 2) {
               labelText
               valueText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
         }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(label): \(value)")
   }
}

/// Section heading in the CINDERMARK style: small, tracked, road blue.
struct SectionHeading: View {
   let title: String

   var body: some View {
      Text(title.uppercased())
         .font(.caption.weight(.bold))
         .kerning(1.2)
         .foregroundStyle(BrandColor.road)
   }
}
