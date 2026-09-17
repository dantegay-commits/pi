import SwiftUI

/// A row of small labels that wraps onto further lines instead of overflowing.
///
/// An `HStack` of pills is fine on an iPad and runs off the edge of a phone as
/// soon as a line carries a lot number, a serial number and an expiry date at
/// once. This lays them out left to right and starts a new line when the next
/// one will not fit.
struct FlowingPills<Content: View>: View {
   var spacing: CGFloat = 6
   var lineSpacing: CGFloat = 6
   @ViewBuilder var content: Content

   var body: some View {
      FlowLayout(spacing: spacing, lineSpacing: lineSpacing) {
         content
      }
   }
}

/// Wrapping layout, built on the `Layout` protocol.
struct FlowLayout: Layout {
   var spacing: CGFloat = 6
   var lineSpacing: CGFloat = 6

   func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
      arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity).size
   }

   func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
      let placements = arrange(subviews: subviews, maxWidth: bounds.width).positions
      for (subview, origin) in zip(subviews, placements) {
         subview.place(
            at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
            anchor: .topLeading,
            proposal: .unspecified
         )
      }
   }

   private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
      var positions: [CGPoint] = []
      var x: CGFloat = 0
      var y: CGFloat = 0
      var lineHeight: CGFloat = 0
      var widest: CGFloat = 0

      for subview in subviews {
         let size = subview.sizeThatFits(.unspecified)
         // Callers build these rows out of `if` statements, so a branch that is
         // false can arrive as a zero-sized subview. Placing it is harmless;
         // letting it consume spacing would open a gap where nothing is.
         guard size.width > 0, size.height > 0 else {
            positions.append(CGPoint(x: x, y: y))
            continue
         }
         // Break before placing, never after, so a single item wider than the
         // container still gets its own line rather than an empty one above it.
         if x > 0, x + size.width > maxWidth {
            x = 0
            y += lineHeight + lineSpacing
            lineHeight = 0
         }
         positions.append(CGPoint(x: x, y: y))
         x += size.width + spacing
         widest = max(widest, x - spacing)
         lineHeight = max(lineHeight, size.height)
      }

      return (CGSize(width: min(widest, maxWidth), height: y + lineHeight), positions)
   }
}
