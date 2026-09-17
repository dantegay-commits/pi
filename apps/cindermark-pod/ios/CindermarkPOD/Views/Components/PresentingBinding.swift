import SwiftUI

/// Bridges an optional error message to the `Bool` binding `alert` expects, and
/// clears the message when the alert closes. Using `.constant(value != nil)`
/// instead leaves the message set, so the alert immediately reappears.
func presenting(_ message: Binding<String?>) -> Binding<Bool> {
   Binding(
      get: { message.wrappedValue != nil },
      set: { isPresented in
         if !isPresented { message.wrappedValue = nil }
      }
   )
}
