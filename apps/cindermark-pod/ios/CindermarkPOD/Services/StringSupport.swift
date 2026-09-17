import Foundation

extension String {
   /// Strips anything that does not belong in a file name, so an order number
   /// typed as "SO 10482/A" still produces a usable, sortable file.
   var fileSafeToken: String {
      let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
      let mapped = unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
      var cleaned = String(mapped)
      while cleaned.contains("--") { cleaned = cleaned.replacingOccurrences(of: "--", with: "-") }
      return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
   }

   var trimmed: String {
      trimmingCharacters(in: .whitespacesAndNewlines)
   }

   var isBlank: Bool {
      trimmed.isEmpty
   }
}
