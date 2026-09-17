import UIKit

/// Renders a `DeliveryRecord` as the CINDERMARK proof-of-delivery document.
///
/// The PDF is a rendering of the record, not a second source of truth: every
/// value on the page comes from the record, and the record's SHA-256 is printed
/// on the last page so a copy can be checked against the archived JSON.
///
/// Rendering runs twice. The first pass exists only to learn the page count so
/// the footer can say "Page 2 of 3"; the footer sits at a fixed position and
/// does not affect where content breaks, so both passes paginate identically.
enum PodPDFRenderer {
   static let pageSize = CGSize(width: 612, height: 792)
   static let margin: CGFloat = 36
   static let footerHeight: CGFloat = 28

   static func render(record: DeliveryRecord, signature: UIImage?) -> Data {
      let counted = draw(record: record, signature: signature, totalPages: 0).pageCount
      return draw(record: record, signature: signature, totalPages: counted).data
   }

   private static func draw(
      record: DeliveryRecord,
      signature: UIImage?,
      totalPages: Int
   ) -> (data: Data, pageCount: Int) {
      let format = UIGraphicsPDFRendererFormat()
      format.documentInfo = documentInfo(for: record)
      let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
      var pageCount = 0
      let data = renderer.pdfData { context in
         let writer = DocumentWriter(
            record: record,
            signature: signature,
            totalPages: totalPages,
            context: context
         )
         writer.write()
         pageCount = writer.pageCount
      }
      return (data, pageCount)
   }

   /// PDF document metadata. The keywords field carries the machine-readable
   /// capture facts, so the coordinates and the signing time travel with the
   /// file even when it is separated from its JSON sidecar.
   private static func documentInfo(for record: DeliveryRecord) -> [String: Any] {
      var keywords: [String] = [
         "record=\(record.id.uuidString)",
         "order=\(record.orderNumber)",
         "signed_at_utc=\(PodCoding.dateFormat.string(from: record.signedAt))",
         "time_zone=\(record.timeZoneIdentifier)",
         "sha256=\(record.payloadHash)",
      ]
      if let coordinates = record.location.coordinateString {
         keywords.append("latitude=\(record.location.latitude.map { String(format: "%.6f", $0) } ?? "")")
         keywords.append("longitude=\(record.location.longitude.map { String(format: "%.6f", $0) } ?? "")")
         keywords.append("coordinates=\(coordinates)")
      } else {
         keywords.append("coordinates=unavailable")
      }
      if let accuracy = record.location.horizontalAccuracyMeters {
         keywords.append("accuracy_m=\(String(format: "%.1f", accuracy))")
      }
      return [
         kCGPDFContextTitle as String: "Proof of Delivery \(record.orderNumber)",
         kCGPDFContextAuthor as String: BrandConfig.companyName,
         kCGPDFContextSubject as String: "Signed delivery receipt for \(record.customer.displayName)",
         kCGPDFContextCreator as String: "CINDERMARK POD \(record.courier.appVersion) (\(record.courier.appBuild))",
         kCGPDFContextKeywords as String: keywords.joined(separator: "; "),
      ]
   }
}

/// One column of the manifest table.
private struct ManifestColumn {
   let title: String
   let width: CGFloat
   let alignment: NSTextAlignment
}

/// Walks the record top to bottom, breaking pages as it goes.
private final class DocumentWriter {
   private let record: DeliveryRecord
   private let signature: UIImage?
   private let totalPages: Int
   private let context: UIGraphicsPDFRendererContext

   private(set) var pageCount = 0
   private var y: CGFloat = 0

   private let margin = PodPDFRenderer.margin
   private let pageSize = PodPDFRenderer.pageSize
   private var contentWidth: CGFloat { pageSize.width - margin * 2 }
   private var contentBottom: CGFloat { pageSize.height - margin - PodPDFRenderer.footerHeight }

   // 66 + 180 + 88 + 48 + 46 + 50 + 62 = 540, the full content width.
   private let columns: [ManifestColumn] = [
      ManifestColumn(title: "SKU", width: 66, alignment: .left),
      ManifestColumn(title: "Item", width: 180, alignment: .left),
      ManifestColumn(title: "Lot / Serial", width: 88, alignment: .left),
      ManifestColumn(title: "Expires", width: 48, alignment: .left),
      ManifestColumn(title: "Shipped", width: 46, alignment: .right),
      ManifestColumn(title: "Received", width: 50, alignment: .right),
      ManifestColumn(title: "Status", width: 62, alignment: .left),
   ]

   init(record: DeliveryRecord, signature: UIImage?, totalPages: Int, context: UIGraphicsPDFRendererContext) {
      self.record = record
      self.signature = signature
      self.totalPages = totalPages
      self.context = context
   }

   func write() {
      startPage()
      drawPartyBlocks()
      drawManifest()
      drawExceptionSummary()
      drawNotes()
      drawSignatureBlock()
      drawAuditBlock()
      closePage()
   }

   // MARK: - Page frame

   private func startPage() {
      context.beginPage()
      pageCount += 1
      PodPDFText.fill(CGRect(origin: .zero, size: pageSize), with: BrandColor.Document.paper)
      y = drawHeader()
   }

   private func closePage() {
      drawFooter()
   }

   private func ensure(_ needed: CGFloat) {
      guard y + needed > contentBottom else { return }
      closePage()
      startPage()
   }

   private func drawHeader() -> CGFloat {
      let top = margin - 6
      let logoBox = CGRect(x: margin, y: top, width: 210, height: 38)
      if let logo = BrandLogo.document {
         logo.draw(in: PodPDFText.fittedRect(for: logo, in: logoBox))
      } else {
         drawWordmark(in: logoBox)
      }

      let rightWidth: CGFloat = 250
      let rightX = pageSize.width - margin - rightWidth
      PodPDFText.draw(
         PodPDFText.attributed(
            "PROOF OF DELIVERY",
            font: PodPDFText.font(15, .bold),
            color: BrandColor.Document.ink,
            alignment: .right,
            tracking: 0.8
         ),
         in: CGRect(x: rightX, y: top, width: rightWidth, height: 20)
      )
      PodPDFText.draw(
         PodPDFText.attributed(
            "Order \(record.orderNumber.isEmpty ? "-" : record.orderNumber)",
            font: PodPDFText.font(9.5, .medium),
            color: BrandColor.Document.slate,
            alignment: .right
         ),
         in: CGRect(x: rightX, y: top + 20, width: rightWidth, height: 14)
      )

      let ruleY = top + 44
      PodPDFText.rule(
         from: CGPoint(x: margin, y: ruleY),
         to: CGPoint(x: pageSize.width - margin, y: ruleY),
         color: BrandColor.Document.ember,
         width: 1.5
      )
      return ruleY + 16
   }

   /// Fallback header when no logo artwork has been added to the asset catalog.
   private func drawWordmark(in box: CGRect) {
      PodPDFText.draw(
         PodPDFText.attributed(
            BrandConfig.companyShortName,
            font: PodPDFText.font(19, .heavy),
            color: BrandColor.Document.ember,
            tracking: 1.2
         ),
         in: CGRect(x: box.minX, y: box.minY, width: box.width, height: 24)
      )
      PodPDFText.draw(
         PodPDFText.attributed(
            BrandConfig.divisionLine,
            font: PodPDFText.font(7.5, .semibold),
            color: BrandColor.Document.slate,
            tracking: 2.4
         ),
         in: CGRect(x: box.minX, y: box.minY + 22, width: box.width, height: 12)
      )
   }

   private func drawFooter() {
      let footerY = pageSize.height - margin - 14
      PodPDFText.rule(
         from: CGPoint(x: margin, y: footerY - 6),
         to: CGPoint(x: pageSize.width - margin, y: footerY - 6),
         color: BrandColor.Document.hairline
      )
      PodPDFText.draw(
         PodPDFText.attributed(
            BrandConfig.footerLine,
            font: PodPDFText.font(7),
            color: BrandColor.Document.slate
         ),
         in: CGRect(x: margin, y: footerY, width: contentWidth - 120, height: 12)
      )
      let page = totalPages > 0 ? "Page \(pageCount) of \(totalPages)" : "Page \(pageCount)"
      PodPDFText.draw(
         PodPDFText.attributed(
            page,
            font: PodPDFText.font(7),
            color: BrandColor.Document.slate,
            alignment: .right
         ),
         in: CGRect(x: pageSize.width - margin - 120, y: footerY, width: 120, height: 12)
      )
      PodPDFText.draw(
         PodPDFText.attributed(
            "Record \(record.id.uuidString.lowercased())",
            font: PodPDFText.font(6),
            color: BrandColor.Document.hairline
         ),
         in: CGRect(x: margin, y: footerY + 9, width: contentWidth, height: 10)
      )
   }

   // MARK: - Blocks

   private func sectionTitle(_ title: String) {
      ensure(22)
      PodPDFText.draw(
         PodPDFText.attributed(
            title.uppercased(),
            font: PodPDFText.font(8, .bold),
            color: BrandColor.Document.ember,
            tracking: 1.4
         ),
         in: CGRect(x: margin, y: y, width: contentWidth, height: 12)
      )
      y += 14
   }

   private func drawPartyBlocks() {
      let columnWidth = (contentWidth - 24) / 2
      let leftX = margin
      let rightX = margin + columnWidth + 24
      let startY = y

      var leftLines: [(String, UIFont)] = [
         (record.customer.displayName, PodPDFText.font(11, .semibold)),
      ]
      if !record.customer.contactName.isBlank, record.customer.contactName != record.customer.displayName {
         leftLines.append((record.customer.contactName, PodPDFText.font(9)))
      }
      for line in record.customer.address.lines {
         leftLines.append((line, PodPDFText.font(9)))
      }
      if !record.customer.phone.isBlank { leftLines.append((record.customer.phone, PodPDFText.font(9))) }
      if !record.customer.email.isBlank { leftLines.append((record.customer.email, PodPDFText.font(9))) }

      var leftY = drawBlockHeading("Delivered to", at: CGPoint(x: leftX, y: startY), width: columnWidth)
      for (text, font) in leftLines {
         let attributed = PodPDFText.attributed(text, font: font, color: BrandColor.Document.ink)
         let height = PodPDFText.height(attributed, width: columnWidth)
         PodPDFText.draw(attributed, in: CGRect(x: leftX, y: leftY, width: columnWidth, height: height))
         leftY += height + 1
      }

      var rightY = drawBlockHeading("Shipment", at: CGPoint(x: rightX, y: startY), width: columnWidth)
      var details: [(String, String)] = [
         ("Order number", record.orderNumber.isEmpty ? "-" : record.orderNumber),
      ]
      if !record.purchaseOrder.isBlank { details.append(("Purchase order", record.purchaseOrder)) }
      if !record.customer.accountNumber.isBlank { details.append(("Account", record.customer.accountNumber)) }
      if !record.serviceLevel.isBlank { details.append(("Service level", record.serviceLevel)) }
      details.append(("Lines / units", "\(record.lineItems.count) / \(record.totalUnitsShipped)"))
      if record.coldChainRequired { details.append(("Handling", "Cold chain")) }
      for (label, value) in details {
         rightY += drawDetailRow(label: label, value: value, x: rightX, y: rightY, width: columnWidth)
      }

      y = max(leftY, rightY) + 12
   }

   private func drawBlockHeading(_ title: String, at origin: CGPoint, width: CGFloat) -> CGFloat {
      PodPDFText.draw(
         PodPDFText.attributed(
            title.uppercased(),
            font: PodPDFText.font(7.5, .bold),
            color: BrandColor.Document.slate,
            tracking: 1.4
         ),
         in: CGRect(x: origin.x, y: origin.y, width: width, height: 11)
      )
      return origin.y + 14
   }

   @discardableResult
   private func drawDetailRow(label: String, value: String, x: CGFloat, y rowY: CGFloat, width: CGFloat) -> CGFloat {
      let labelWidth = min(96, width * 0.44)
      let valueWidth = width - labelWidth - 6
      let labelText = PodPDFText.attributed(label, font: PodPDFText.font(8.5), color: BrandColor.Document.slate)
      let valueText = PodPDFText.attributed(value, font: PodPDFText.font(8.5, .medium), color: BrandColor.Document.ink)
      let height = max(PodPDFText.height(labelText, width: labelWidth), PodPDFText.height(valueText, width: valueWidth))
      PodPDFText.draw(labelText, in: CGRect(x: x, y: rowY, width: labelWidth, height: height))
      PodPDFText.draw(valueText, in: CGRect(x: x + labelWidth + 6, y: rowY, width: valueWidth, height: height))
      return height + 3
   }

   // MARK: - Manifest

   private func drawManifest() {
      sectionTitle("Shipment contents")
      drawTableHeader()
      for (index, line) in record.lineItems.enumerated() {
         let height = manifestRowHeight(line)
         if y + height > contentBottom {
            closePage()
            startPage()
            drawTableHeader()
         }
         drawManifestRow(line, zebra: index.isMultiple(of: 2))
      }
      drawManifestTotals()
   }

   private func drawTableHeader() {
      let height: CGFloat = 16
      PodPDFText.fill(
         CGRect(x: margin, y: y, width: contentWidth, height: height),
         with: BrandColor.Document.tableHeader
      )
      var x = margin
      for column in columns {
         PodPDFText.draw(
            PodPDFText.attributed(
               column.title.uppercased(),
               font: PodPDFText.font(6.8, .bold),
               color: BrandColor.Document.slate,
               alignment: column.alignment,
               tracking: 0.8
            ),
            in: CGRect(x: x + 5, y: y + 4.5, width: column.width - 10, height: 10)
         )
         x += column.width
      }
      y += height
   }

   private func manifestCells(_ line: ReceivedLineItem) -> [String] {
      let expires = line.item.expirationDate.map { Self.shortDate.string(from: $0) } ?? "-"
      var description = line.item.itemDescription.isBlank ? "(no description)" : line.item.itemDescription
      if !line.item.manufacturer.isBlank { description += "\n\(line.item.manufacturer)" }
      if !line.item.hcpcsCode.isBlank { description += "\nHCPCS \(line.item.hcpcsCode)" }
      var flags: [String] = []
      if line.item.coldChain { flags.append("Cold chain") }
      if line.item.controlledSubstance { flags.append("Controlled") }
      if !flags.isEmpty { description += "\n\(flags.joined(separator: " · "))" }
      let trace = line.item.traceabilityLine.isEmpty ? "-" : line.item.traceabilityLine
      return [
         line.item.sku.isBlank ? "-" : line.item.sku,
         description,
         trace,
         expires,
         "\(line.item.quantityShipped) \(line.item.unitOfMeasure)",
         "\(line.quantityReceived) \(line.item.unitOfMeasure)",
         line.disposition.label,
      ]
   }

   private func manifestRowHeight(_ line: ReceivedLineItem) -> CGFloat {
      let cells = manifestCells(line)
      var tallest: CGFloat = 10
      for (index, column) in columns.enumerated() {
         let text = PodPDFText.attributed(cells[index], font: PodPDFText.font(8), color: BrandColor.Document.ink)
         tallest = max(tallest, PodPDFText.height(text, width: column.width - 10))
      }
      var height = tallest + 9
      if let note = noteText(line) {
         height += PodPDFText.height(note, width: contentWidth - 20) + 4
      }
      return height
   }

   private func noteText(_ line: ReceivedLineItem) -> NSAttributedString? {
      guard !line.isClean else { return nil }
      let shortfall = line.item.quantityShipped - line.quantityReceived
      var parts: [String] = []
      if shortfall > 0 { parts.append("\(shortfall) \(line.item.unitOfMeasure) not received") }
      if !line.note.isBlank { parts.append(line.note.trimmed) }
      guard !parts.isEmpty else { return nil }
      return PodPDFText.attributed(
         "Exception - \(parts.joined(separator: ". "))",
         font: PodPDFText.font(7.6, .medium),
         color: BrandColor.Document.ember
      )
   }

   private func drawManifestRow(_ line: ReceivedLineItem, zebra: Bool) {
      let height = manifestRowHeight(line)
      let rowRect = CGRect(x: margin, y: y, width: contentWidth, height: height)
      if !line.isClean {
         PodPDFText.fill(rowRect, with: BrandColor.Document.exceptionTint)
         PodPDFText.fill(CGRect(x: margin, y: y, width: 2, height: height), with: BrandColor.Document.ember)
      } else if zebra {
         PodPDFText.fill(rowRect, with: BrandColor.Document.zebra)
      }

      let cells = manifestCells(line)
      var x = margin
      for (index, column) in columns.enumerated() {
         let isStatus = index == columns.count - 1
         let color = isStatus && !line.isClean ? BrandColor.Document.ember : BrandColor.Document.ink
         let weight: UIFont.Weight = isStatus ? .semibold : .regular
         PodPDFText.draw(
            PodPDFText.attributed(
               cells[index],
               font: PodPDFText.font(8, weight),
               color: color,
               alignment: column.alignment
            ),
            in: CGRect(x: x + 5, y: y + 4.5, width: column.width - 10, height: height - 9)
         )
         x += column.width
      }

      if let note = noteText(line) {
         let noteHeight = PodPDFText.height(note, width: contentWidth - 20)
         PodPDFText.draw(
            note,
            in: CGRect(x: margin + 10, y: y + height - noteHeight - 4, width: contentWidth - 20, height: noteHeight)
         )
      }

      PodPDFText.rule(
         from: CGPoint(x: margin, y: y + height),
         to: CGPoint(x: margin + contentWidth, y: y + height),
         color: BrandColor.Document.hairline,
         width: 0.4
      )
      y += height
   }

   private func drawManifestTotals() {
      ensure(20)
      let text = "\(record.lineItems.count) lines  ·  \(record.totalUnitsShipped) units shipped  ·  "
         + "\(record.totalUnitsReceived) units received"
      PodPDFText.draw(
         PodPDFText.attributed(
            text,
            font: PodPDFText.font(8.5, .semibold),
            color: BrandColor.Document.ink,
            alignment: .right
         ),
         in: CGRect(x: margin, y: y + 5, width: contentWidth, height: 12)
      )
      y += 24
   }

   private func drawExceptionSummary() {
      let exceptions = record.exceptions
      guard !exceptions.isEmpty else { return }
      sectionTitle("Exceptions")
      for line in exceptions {
         let shortfall = line.item.quantityShipped - line.quantityReceived
         var detail = "\(line.disposition.label.lowercased())"
         if shortfall > 0 { detail += ", \(shortfall) of \(line.item.quantityShipped) not received" }
         let summary = "\(line.item.sku.isBlank ? line.item.itemDescription : line.item.sku): \(detail)."
            + (line.note.isBlank ? "" : " \(line.note.trimmed)")
         let text = PodPDFText.attributed(summary, font: PodPDFText.font(8.5), color: BrandColor.Document.ink)
         let height = PodPDFText.height(text, width: contentWidth - 12)
         ensure(height + 6)
         PodPDFText.fill(CGRect(x: margin, y: y, width: 2, height: height), with: BrandColor.Document.ember)
         PodPDFText.draw(text, in: CGRect(x: margin + 12, y: y, width: contentWidth - 12, height: height))
         y += height + 6
      }
      y += 6
   }

   private func drawNotes() {
      guard !record.deliveryNotes.isBlank else { return }
      sectionTitle("Delivery notes")
      let text = PodPDFText.attributed(
         record.deliveryNotes.trimmed,
         font: PodPDFText.font(8.5),
         color: BrandColor.Document.ink
      )
      let height = PodPDFText.height(text, width: contentWidth)
      ensure(height + 10)
      PodPDFText.draw(text, in: CGRect(x: margin, y: y, width: contentWidth, height: height))
      y += height + 12
   }

   // MARK: - Signature

   private func drawSignatureBlock() {
      let attestation = PodPDFText.attributed(
         BrandConfig.attestation,
         font: PodPDFText.font(7.6),
         color: BrandColor.Document.slate,
         lineSpacing: 2
      )
      let attestationHeight = PodPDFText.height(attestation, width: contentWidth)
      let boxHeight: CGFloat = 96
      // Section title, attestation, signature box and the printed lines under it.
      ensure(attestationHeight + boxHeight + 74)

      sectionTitle("Recipient acknowledgement")
      PodPDFText.draw(attestation, in: CGRect(x: margin, y: y, width: contentWidth, height: attestationHeight))
      y += attestationHeight + 10

      let boxWidth = contentWidth * 0.56
      let boxRect = CGRect(x: margin, y: y, width: boxWidth, height: boxHeight)
      PodPDFText.fill(boxRect, with: BrandColor.Document.paper)
      PodPDFText.stroke(boxRect, color: BrandColor.Document.hairline, width: 0.6, cornerRadius: 3)
      if let signature = signature {
         let inset = boxRect.insetBy(dx: 10, dy: 10)
         signature.draw(in: PodPDFText.fittedRect(for: signature, in: inset))
      }

      let detailX = margin + boxWidth + 20
      let detailWidth = contentWidth - boxWidth - 20
      var detailY = y
      detailY += drawDetailRow(
         label: "Signed by",
         value: record.signer.printedName.isBlank ? "-" : record.signer.printedName,
         x: detailX,
         y: detailY,
         width: detailWidth
      )
      detailY += drawDetailRow(
         label: "Relationship",
         value: record.signer.relationshipDisplay,
         x: detailX,
         y: detailY,
         width: detailWidth
      )
      detailY += drawDetailRow(label: "Date and time", value: localTimestamp(), x: detailX, y: detailY, width: detailWidth)
      detailY += drawDetailRow(
         label: "Delivered by",
         value: record.courier.driverName.isBlank ? "-" : record.courier.driverName,
         x: detailX,
         y: detailY,
         width: detailWidth
      )

      y = max(boxRect.maxY, detailY) + 4
      PodPDFText.rule(
         from: CGPoint(x: margin, y: y),
         to: CGPoint(x: margin + boxWidth, y: y),
         color: BrandColor.Document.ink,
         width: 0.8
      )
      PodPDFText.draw(
         PodPDFText.attributed(
            "Recipient signature",
            font: PodPDFText.font(7),
            color: BrandColor.Document.slate,
            tracking: 0.6
         ),
         in: CGRect(x: margin, y: y + 3, width: boxWidth, height: 10)
      )
      y += 22
   }

   // MARK: - Audit

   private func drawAuditBlock() {
      sectionTitle("Capture audit")

      var rows: [(String, String)] = [
         ("Signed (local)", localTimestamp()),
         ("Signed (UTC)", PodCoding.dateFormat.string(from: record.signedAt)),
         ("Time zone", "\(record.timeZoneIdentifier) (UTC\(Self.offsetString(record.utcOffsetSeconds)))"),
         ("Location", record.location.summary),
      ]
      if let address = record.location.resolvedAddress, !address.isBlank {
         rows.append(("Resolved address", address))
      }
      if let fixTime = record.location.fixTimestamp {
         rows.append(("Location fix taken", PodCoding.dateFormat.string(from: fixTime)))
      }
      rows.append(("Signature input", signatureInputSummary()))
      rows.append(("Device", "\(record.courier.deviceModel), \(record.courier.systemVersion)"))
      rows.append(("Device id", record.courier.deviceId))
      rows.append(("App version", "\(record.courier.appVersion) (\(record.courier.appBuild))"))
      rows.append(("Record id", record.id.uuidString.lowercased()))
      rows.append(("Record SHA-256", PodPDFText.chunked(record.payloadHash, every: 16)))

      let labelWidth: CGFloat = 108
      for (label, value) in rows {
         let labelText = PodPDFText.attributed(label, font: PodPDFText.font(7.6), color: BrandColor.Document.slate)
         let valueFont = label.hasSuffix("SHA-256") || label == "Record id" || label == "Device id"
            ? UIFont.monospacedSystemFont(ofSize: 7.4, weight: .regular)
            : PodPDFText.font(7.8, .medium)
         let valueText = PodPDFText.attributed(value, font: valueFont, color: BrandColor.Document.ink)
         let valueWidth = contentWidth - labelWidth - 8
         let height = max(PodPDFText.height(labelText, width: labelWidth), PodPDFText.height(valueText, width: valueWidth))
         ensure(height + 4)
         PodPDFText.draw(labelText, in: CGRect(x: margin, y: y, width: labelWidth, height: height))
         PodPDFText.draw(valueText, in: CGRect(x: margin + labelWidth + 8, y: y, width: valueWidth, height: height))
         y += height + 3
      }

      let note = PodPDFText.attributed(
         "The SHA-256 above covers the delivery record this document was rendered from. "
            + "The archived record and this document are retained by \(BrandConfig.companyName).",
         font: PodPDFText.font(6.8),
         color: BrandColor.Document.slate
      )
      let noteHeight = PodPDFText.height(note, width: contentWidth)
      ensure(noteHeight + 8)
      y += 6
      PodPDFText.draw(note, in: CGRect(x: margin, y: y, width: contentWidth, height: noteHeight))
      y += noteHeight
   }

   private func signatureInputSummary() -> String {
      let audit = record.signature
      var parts: [String] = []
      if audit.inputPolicy == "pencilOnly" {
         parts.append("Apple Pencil only (finger input disabled)")
      } else if audit.pressureObserved {
         parts.append("Stylus pressure detected")
      } else {
         parts.append("Touch or stylus")
      }
      parts.append("\(audit.strokeCount) strokes")
      parts.append(String(format: "%.1f s", audit.captureDurationSeconds))
      return parts.joined(separator: "  ·  ")
   }

   private func localTimestamp() -> String {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US")
      formatter.timeZone = TimeZone(identifier: record.timeZoneIdentifier) ?? .current
      formatter.dateFormat = "MMMM d, yyyy 'at' h:mm:ss a zzz"
      return formatter.string(from: record.signedAt)
   }

   private static let shortDate: DateFormatter = {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "MM/dd/yy"
      return formatter
   }()

   private static func offsetString(_ seconds: Int) -> String {
      let sign = seconds < 0 ? "-" : "+"
      let absolute = abs(seconds)
      return String(format: "%@%02d:%02d", sign, absolute / 3600, (absolute % 3600) / 60)
   }
}
