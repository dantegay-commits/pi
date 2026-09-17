import SwiftUI
import UIKit

/// Logo lookup with a drawn fallback.
///
/// Drop the real CINDERMARK artwork into the asset catalog and it is used
/// everywhere automatically:
///
///   Assets.xcassets/LogoPrimary.imageset   full lockup, app screens
///   Assets.xcassets/LogoDocument.imageset  PDF header (mono/dark version)
///   Assets.xcassets/LogoMark.imageset      icon-only mark, compact layouts
///
/// Until those slots are filled, `UIImage(named:)` returns nil and the app draws
/// a plain wordmark instead, so nothing ever renders as a blank space or a
/// missing-image box.
enum BrandLogo {
   static var primary: UIImage? { UIImage(named: "LogoPrimary") }
   static var mark: UIImage? { UIImage(named: "LogoMark") }

   /// The PDF prefers a document-specific version, then the main lockup.
   static var document: UIImage? { UIImage(named: "LogoDocument") ?? primary }

   static var hasArtwork: Bool { primary != nil || document != nil }
}

/// App-side logo: real artwork if present, otherwise the wordmark.
struct BrandLogoView: View {
   var height: CGFloat = 34
   var showsDivision = true

   var body: some View {
      if let image = BrandLogo.primary {
         Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel(BrandConfig.companyName)
      } else {
         BrandWordmark(height: height, showsDivision: showsDivision)
      }
   }
}

/// Typographic stand-in for the logo.
struct BrandWordmark: View {
   var height: CGFloat = 34
   var showsDivision = true

   var body: some View {
      HStack(spacing: height * 0.26) {
         EmberMark()
            .fill(BrandColor.ember)
            .frame(width: height * 0.72, height: height * 0.86)
         VStack(alignment: .leading, spacing: height * 0.06) {
            Text(BrandConfig.companyShortName)
               .font(.system(size: height * 0.58, weight: .heavy))
               .kerning(height * 0.05)
               .foregroundStyle(BrandColor.ink)
            if showsDivision {
               Text(BrandConfig.divisionLine)
                  .font(.system(size: height * 0.235, weight: .semibold))
                  .kerning(height * 0.09)
                  .foregroundStyle(BrandColor.slate)
            }
         }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(BrandConfig.companyName)
   }
}

/// A stylised ember: the placeholder mark. Replace by filling LogoMark.
struct EmberMark: Shape {
   func path(in rect: CGRect) -> Path {
      var path = Path()
      let width = rect.width
      let height = rect.height
      path.move(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addCurve(
         to: CGPoint(x: rect.maxX, y: rect.minY + height * 0.62),
         control1: CGPoint(x: rect.midX + width * 0.28, y: rect.minY + height * 0.18),
         control2: CGPoint(x: rect.maxX, y: rect.minY + height * 0.34)
      )
      path.addCurve(
         to: CGPoint(x: rect.midX, y: rect.maxY),
         control1: CGPoint(x: rect.maxX, y: rect.minY + height * 0.86),
         control2: CGPoint(x: rect.midX + width * 0.26, y: rect.maxY)
      )
      path.addCurve(
         to: CGPoint(x: rect.minX, y: rect.minY + height * 0.62),
         control1: CGPoint(x: rect.midX - width * 0.26, y: rect.maxY),
         control2: CGPoint(x: rect.minX, y: rect.minY + height * 0.86)
      )
      path.addCurve(
         to: CGPoint(x: rect.midX, y: rect.minY),
         control1: CGPoint(x: rect.minX, y: rect.minY + height * 0.34),
         control2: CGPoint(x: rect.midX - width * 0.28, y: rect.minY + height * 0.18)
      )
      path.closeSubpath()
      return path
   }
}
