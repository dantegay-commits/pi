import SwiftUI

/// A labelled text field: beside its label where there is room, stacked beneath
/// it where there is not.
///
/// `LabeledContent` puts the field in the trailing half of the row, which works
/// on an iPad and collapses to a few visible characters on a phone - long
/// enough to type an email address into, not long enough to check it. On
/// compact width the label moves above the field and it gets the full row.
struct LabeledField: View {
   let label: String
   var prompt: String = ""
   @Binding var text: String
   var contentType: UITextContentType?
   var keyboard: UIKeyboardType = .default
   var autocapitalize = true
   var isSecure = false
   var foreground: Color?

   @Environment(\.horizontalSizeClass) private var horizontalSizeClass

   var body: some View {
      if horizontalSizeClass == .regular {
         LabeledContent(label) {
            field.multilineTextAlignment(.trailing)
         }
      } else {
         VStack(alignment: .leading, spacing: 4) {
            Text(label)
               .font(.caption)
               .foregroundStyle(.secondary)
            field
         }
         .padding(.vertical, 2)
      }
   }

   @ViewBuilder private var field: some View {
      if isSecure {
         SecureField(prompt, text: $text)
            .textContentType(contentType)
      } else {
         TextField(prompt, text: $text)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalize ? .sentences : .never)
            .autocorrectionDisabled(!autocapitalize)
            .foregroundStyle(foreground ?? Color.primary)
      }
   }
}
