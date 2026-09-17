import SwiftUI
import UIKit

/// The CINDERMARK artwork, in the four arrangements the app needs.
///
///   LogoPrimary    the stacked lockup: mark over CINDERMARK / MEDICAL LOGISTICS
///   LogoDocument   a horizontal lockup, for the PDF header band and toolbars
///   LogoMark       the C and its road, alone
///   LogoWordmark   the type, alone
///
/// The stacked lockup is close to square, so in a 22pt toolbar it would shrink
/// to about 28pt wide and read as a smudge. That is why headers use the
/// horizontal arrangement and only large, centred moments use the stacked one.
///
/// If an image set is ever emptied, `UIImage(named:)` returns nil and the app
/// falls back to a plain wordmark rather than rendering a blank space.
enum BrandLogo {
   static var primary: UIImage? { UIImage(named: "LogoPrimary") }
   static var mark: UIImage? { UIImage(named: "LogoMark") }
   static var wordmark: UIImage? { UIImage(named: "LogoWordmark") }
   static var document: UIImage? { UIImage(named: "LogoDocument") ?? primary }

   static var hasArtwork: Bool { UIImage(named: "LogoDocument") != nil || primary != nil }
}

/// Horizontal lockup, sized by height. For toolbars, headers and list rows.
struct BrandLogoView: View {
   var height: CGFloat = 26

   var body: some View {
      if let image = BrandLogo.document {
         Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel(BrandConfig.companyName)
      } else {
         BrandWordmark(height: height)
      }
   }
}

/// Stacked lockup, sized by width. For empty states and anywhere the logo is
/// the subject rather than a label.
struct BrandLockupView: View {
   var width: CGFloat = 220

   var body: some View {
      if let image = BrandLogo.primary {
         Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .accessibilityLabel(BrandConfig.companyName)
      } else {
         BrandWordmark(height: width * 0.22)
      }
   }
}

/// Typographic stand-in, used only when the artwork is missing.
struct BrandWordmark: View {
   var height: CGFloat = 26

   var body: some View {
      VStack(alignment: .leading, spacing: height * 0.08) {
         Text(BrandConfig.companyShortName)
            .font(.system(size: height * 0.56, weight: .heavy))
            .kerning(height * 0.04)
            .foregroundStyle(BrandColor.ink)
         Text(BrandConfig.divisionLine)
            .font(.system(size: height * 0.22, weight: .semibold))
            .kerning(height * 0.09)
            .foregroundStyle(BrandColor.slate)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(BrandConfig.companyName)
   }
}
