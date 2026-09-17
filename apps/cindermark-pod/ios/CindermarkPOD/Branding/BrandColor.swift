import SwiftUI
import UIKit

/// The CINDERMARK palette.
///
/// SwiftUI reads the asset catalog so the app follows light and dark mode. The
/// PDF uses fixed sRGB values instead: a document printed from an iPad in dark
/// mode must look exactly like one printed from an iPad in light mode.
enum BrandColor {
   static let ember = Color("BrandEmber")
   static let ink = Color("BrandInk")
   static let slate = Color("BrandSlate")
   static let paper = Color("BrandPaper")

   enum Document {
      static let ember = UIColor(red: 0.851, green: 0.325, blue: 0.118, alpha: 1)
      static let ink = UIColor(red: 0.086, green: 0.094, blue: 0.114, alpha: 1)
      static let slate = UIColor(red: 0.353, green: 0.376, blue: 0.408, alpha: 1)
      static let hairline = UIColor(red: 0.804, green: 0.792, blue: 0.776, alpha: 1)
      static let tableHeader = UIColor(red: 0.929, green: 0.918, blue: 0.902, alpha: 1)
      static let zebra = UIColor(red: 0.973, green: 0.969, blue: 0.961, alpha: 1)
      static let exceptionTint = UIColor(red: 0.988, green: 0.937, blue: 0.914, alpha: 1)
      static let paper = UIColor.white
   }
}
