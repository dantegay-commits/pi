import Foundation

/// On-disk layout inside the app's Documents directory. Documents is exposed to
/// the Files app (UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace), so
/// this layout is what a dispatcher sees when they open
/// the Files app, under "CINDERMARK POD".
///
///     Documents/
///       Shipped/2026/09/POD-SO-10482-20260917-141203.pdf
///       Shipped/2026/09/POD-SO-10482-20260917-141203.json
///       Shipped/2026/09/POD-SO-10482-20260917-141203-signature.png
///       Data/shipments.json            the day's stops
///
/// There is no separate outbox directory. A delivery that has not reached the
/// site yet is simply a sidecar whose `upload_state` is not `uploaded`, so the
/// queue and the archive can never disagree about what has been sent.
///
/// Everything stored in a record refers to files by their path *relative* to
/// Documents. The absolute container path contains a UUID that iOS changes on
/// app updates and restores, so absolute paths go stale.
enum AppPaths {
   static var documents: URL {
      // Documents always exists for an iOS app; a failure here is unrecoverable
      // and means the container is broken.
      guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
         fatalError("Documents directory unavailable")
      }
      return url
   }

   static var shipped: URL { documents.appendingPathComponent("Shipped", isDirectory: true) }
   static var data: URL { documents.appendingPathComponent("Data", isDirectory: true) }

   static func prepare() {
      for url in [shipped, data] {
         try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      }
      writeReadme()
   }

   /// Shipped/<year>/<month>, created on demand.
   static func shippedFolder(for date: Date) throws -> URL {
      let calendar = Calendar(identifier: .gregorian)
      let parts = calendar.dateComponents([.year, .month], from: date)
      let year = String(format: "%04d", parts.year ?? 0)
      let month = String(format: "%02d", parts.month ?? 0)
      let url = shipped.appendingPathComponent(year, isDirectory: true).appendingPathComponent(month, isDirectory: true)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      return url
   }

   static func absolute(_ relativePath: String) -> URL {
      documents.appendingPathComponent(relativePath)
   }

   /// Path of `url` relative to Documents, or the last path component if `url`
   /// somehow sits outside the container.
   static func relative(_ url: URL) -> String {
      let base = documents.standardizedFileURL.path
      let path = url.standardizedFileURL.path
      guard path.hasPrefix(base + "/") else { return url.lastPathComponent }
      return String(path.dropFirst(base.count + 1))
   }

   /// Keeps signed PDFs out of iCloud/iTunes backups only if the operator asks
   /// for it; by default records are backed up, which is usually what a small
   /// operator wants.
   static func setExcludedFromBackup(_ excluded: Bool, at url: URL) {
      var url = url
      var values = URLResourceValues()
      values.isExcludedFromBackup = excluded
      try? url.setResourceValues(values)
   }

   private static func writeReadme() {
      let url = shipped.appendingPathComponent("READ ME.txt")
      guard !FileManager.default.fileExists(atPath: url.path) else { return }
      let text = """
      CINDERMARK Medical Logistics - Shipped

      Every signed delivery is filed here by year and month. Each delivery has
      three files that share one name:

        POD-<order>-<date>.pdf            the signed document
        POD-<order>-<date>.json           the record, including the audit hash
        POD-<order>-<date>-signature.png  the signature image on its own

      These files are the local copy. The same record is also posted to the
      CINDERMARK WordPress site, which emails the customer their copy.

      Do not edit these files. The JSON carries a SHA-256 hash of the record; an
      edited file will no longer match it.
      """
      try? text.data(using: .utf8)?.write(to: url, options: .atomic)
   }
}
