import PencilKit
import UIKit

struct SignatureExport {
   let image: UIImage
   let pngData: Data
   let audit: SignatureAudit
}

/// Owns the PencilKit canvas for one signature and derives the audit trail from
/// the strokes themselves.
///
/// Timing comes from PencilKit rather than from wall-clock bookkeeping in the
/// UI: every stroke path carries a creation date and every point a time offset,
/// which gives an accurate capture duration even if the driver switches apps
/// halfway through.
@MainActor
final class SignaturePad: ObservableObject {
   @Published private(set) var strokeCount = 0

   let canvasView = PKCanvasView()

   var isEmpty: Bool { canvasView.drawing.strokes.isEmpty }

   func drawingChanged() {
      strokeCount = canvasView.drawing.strokes.count
   }

   func clear() {
      canvasView.drawing = PKDrawing()
      drawingChanged()
   }

   /// Renders the strokes to a transparent PNG, trimmed to the ink with a small
   /// margin, and returns it alongside the audit record. Returns nil when
   /// nothing has been drawn.
   func export(inputPolicy: String, targetWidth: CGFloat = 1400) -> SignatureExport? {
      let drawing = canvasView.drawing
      guard !drawing.strokes.isEmpty else { return nil }

      let inked = drawing.bounds.insetBy(dx: -14, dy: -14)
      guard inked.width > 1, inked.height > 1 else { return nil }
      let scale = min(4, max(1, targetWidth / inked.width))
      let image = drawing.image(from: inked, scale: scale)
      guard let pngData = image.pngData() else { return nil }

      var audit = self.audit(inputPolicy: inputPolicy)
      audit.imageSha256 = PodCoding.sha256Hex(pngData)
      return SignatureExport(image: image, pngData: pngData, audit: audit)
   }

   private func audit(inputPolicy: String) -> SignatureAudit {
      let strokes = canvasView.drawing.strokes
      var audit = SignatureAudit()
      audit.inputPolicy = inputPolicy
      audit.strokeCount = strokes.count
      audit.canvasWidth = Double(canvasView.bounds.width)
      audit.canvasHeight = Double(canvasView.bounds.height)

      var maximumForce: CGFloat = 0
      var minimumForce = CGFloat.greatestFiniteMagnitude
      var points = 0
      for stroke in strokes {
         let path = stroke.path
         points += path.count
         for index in 0 ..< path.count {
            let force = path[index].force
            maximumForce = max(maximumForce, force)
            minimumForce = min(minimumForce, force)
         }
      }
      audit.pointCount = points
      audit.maximumForce = Double(maximumForce)
      // Finger input reports a flat synthesized force. A spread means a real
      // stylus was on the glass; see SignatureAudit for the caveat.
      audit.pressureObserved = points > 0 && (maximumForce - minimumForce) > 0.05

      if let start = strokes.map({ $0.path.creationDate }).min() {
         let ends = strokes.map { stroke -> Date in
            let tail = stroke.path.count > 0 ? stroke.path[stroke.path.count - 1].timeOffset : 0
            return stroke.path.creationDate.addingTimeInterval(tail)
         }
         let end = ends.max() ?? start
         audit.captureDurationSeconds = max(0, end.timeIntervalSince(start))
      }
      return audit
   }
}
