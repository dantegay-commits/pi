import PencilKit
import SwiftUI

/// The Apple Pencil signature surface.
///
/// `drawingPolicy` is the setting that matters on an iPad handed to a customer:
/// with `.pencilOnly`, a palm or a sleeve resting on the glass cannot add
/// strokes, and the Pencil still works normally. The canvas is pinned to a light
/// appearance so black ink stays black; PencilKit otherwise inverts dark ink for
/// display on a dark background, and the exported image would not match what the
/// customer saw.
struct SignatureCanvas: UIViewRepresentable {
   @ObservedObject var pad: SignaturePad
   var pencilOnly: Bool

   func makeUIView(context: Context) -> PKCanvasView {
      let canvas = pad.canvasView
      canvas.delegate = context.coordinator
      canvas.tool = PKInkingTool(.pen, color: .black, width: 4.5)
      canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
      canvas.backgroundColor = .clear
      canvas.isOpaque = false
      canvas.alwaysBounceVertical = false
      canvas.alwaysBounceHorizontal = false
      canvas.minimumZoomScale = 1
      canvas.maximumZoomScale = 1
      canvas.bouncesZoom = false
      canvas.overrideUserInterfaceStyle = .light
      return canvas
   }

   func updateUIView(_ canvas: PKCanvasView, context: Context) {
      let policy: PKCanvasViewDrawingPolicy = pencilOnly ? .pencilOnly : .anyInput
      if canvas.drawingPolicy != policy { canvas.drawingPolicy = policy }
   }

   func makeCoordinator() -> Coordinator {
      Coordinator(pad: pad)
   }

   final class Coordinator: NSObject, PKCanvasViewDelegate {
      private let pad: SignaturePad

      init(pad: SignaturePad) {
         self.pad = pad
      }

      func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
         MainActor.assumeIsolated {
            pad.drawingChanged()
         }
      }
   }
}
