import SwiftUI
import UIKit

/// The CINDERMARK palette, measured off the logo artwork itself.
///
/// `ink` is the navy of the letterform and `road` the blue of the road through
/// it. `alert` is deliberately outside the brand: an exception on a delivery
/// receipt has to read as an exception, and brand blue would make it look like
/// another heading.
///
/// SwiftUI reads the asset catalog so the app follows light and dark mode. The
/// PDF uses fixed sRGB values instead: a document printed from an iPad in dark
/// mode must look exactly like one printed from an iPad in light mode.
enum BrandColor {
   static let road = Color("BrandRoad")
   static let ink = Color("BrandInk")
   static let slate = Color("BrandSlate")
   static let paper = Color("BrandPaper")
   static let alert = Color("BrandAlert")

   enum Document {
      /// #3D6FB0 - the road blue.
      static let road = UIColor(red: 0.239, green: 0.435, blue: 0.690, alpha: 1)
      /// #364564 - the navy letterform.
      static let ink = UIColor(red: 0.212, green: 0.271, blue: 0.392, alpha: 1)
      /// #5C677D - secondary labels, tinted toward the navy.
      static let slate = UIColor(red: 0.361, green: 0.404, blue: 0.490, alpha: 1)
      /// #B3261E - exceptions only.
      static let alert = UIColor(red: 0.702, green: 0.149, blue: 0.118, alpha: 1)
      static let hairline = UIColor(red: 0.784, green: 0.808, blue: 0.855, alpha: 1)
      static let tableHeader = UIColor(red: 0.910, green: 0.925, blue: 0.953, alpha: 1)
      static let zebra = UIColor(red: 0.961, green: 0.969, blue: 0.980, alpha: 1)
      static let alertTint = UIColor(red: 0.984, green: 0.929, blue: 0.925, alpha: 1)
      static let paper = UIColor.white
   }
}
