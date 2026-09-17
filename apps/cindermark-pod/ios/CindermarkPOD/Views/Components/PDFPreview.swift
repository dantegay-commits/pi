import PDFKit
import SwiftUI

/// Read-only preview of an archived proof of delivery.
struct PDFPreview: UIViewRepresentable {
   let url: URL

   func makeUIView(context: Context) -> PDFView {
      let view = PDFView()
      view.autoScales = true
      view.displayMode = .singlePageContinuous
      view.displayDirection = .vertical
      view.backgroundColor = .secondarySystemBackground
      return view
   }

   func updateUIView(_ view: PDFView, context: Context) {
      guard view.document?.documentURL != url else { return }
      view.document = PDFDocument(url: url)
   }
}
