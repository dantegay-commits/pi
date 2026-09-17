import UIKit

/// Small text helpers shared by the PDF renderer. Everything measures first and
/// draws second so the renderer can decide whether a block fits on the page it
/// is on.
enum PodPDFText {
   static func font(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
      UIFont.systemFont(ofSize: size, weight: weight)
   }

   static func attributed(
      _ string: String,
      font: UIFont,
      color: UIColor,
      alignment: NSTextAlignment = .left,
      lineSpacing: CGFloat = 1.5,
      tracking: CGFloat = 0
   ) -> NSAttributedString {
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = alignment
      paragraph.lineSpacing = lineSpacing
      paragraph.lineBreakMode = .byWordWrapping
      var attributes: [NSAttributedString.Key: Any] = [
         .font: font,
         .foregroundColor: color,
         .paragraphStyle: paragraph,
      ]
      if tracking != 0 { attributes[.kern] = tracking }
      return NSAttributedString(string: string, attributes: attributes)
   }

   static func height(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
      guard !text.string.isEmpty else { return 0 }
      let bounds = text.boundingRect(
         with: CGSize(width: width, height: .greatestFiniteMagnitude),
         options: [.usesLineFragmentOrigin, .usesFontLeading],
         context: nil
      )
      return ceil(bounds.height)
   }

   /// Draws into `rect` and returns the height actually consumed.
   @discardableResult
   static func draw(_ text: NSAttributedString, in rect: CGRect) -> CGFloat {
      guard !text.string.isEmpty else { return 0 }
      text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
      return height(text, width: rect.width)
   }

   static func fill(_ rect: CGRect, with color: UIColor) {
      color.setFill()
      UIBezierPath(rect: rect).fill()
   }

   static func rule(from start: CGPoint, to end: CGPoint, color: UIColor, width: CGFloat = 0.5) {
      let path = UIBezierPath()
      path.move(to: start)
      path.addLine(to: end)
      path.lineWidth = width
      color.setStroke()
      path.stroke()
   }

   static func stroke(_ rect: CGRect, color: UIColor, width: CGFloat = 0.5, cornerRadius: CGFloat = 0) {
      let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
      path.lineWidth = width
      color.setStroke()
      path.stroke()
   }

   /// Aspect-fit rect for an image inside `box`, anchored left and vertically centred.
   static func fittedRect(for image: UIImage, in box: CGRect) -> CGRect {
      guard image.size.width > 0, image.size.height > 0 else { return box }
      let scale = min(box.width / image.size.width, box.height / image.size.height)
      let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      return CGRect(
         x: box.minX,
         y: box.minY + (box.height - size.height) / 2,
         width: size.width,
         height: size.height
      )
   }

   /// Breaks a long unbroken token (a hex hash) so it wraps inside a column.
   static func chunked(_ string: String, every count: Int) -> String {
      guard count > 0, string.count > count else { return string }
      var out = ""
      for (index, character) in string.enumerated() {
         if index > 0, index % count == 0 { out.append(" ") }
         out.append(character)
      }
      return out
   }
}
