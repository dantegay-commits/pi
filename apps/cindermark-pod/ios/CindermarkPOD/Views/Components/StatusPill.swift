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
struct DetailRow: View {
   let label: String
   let value: String
   var monospaced = false

   var body: some View {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
         Text(label)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(width: 150, alignment: .leading)
         Text(value)
            .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
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
