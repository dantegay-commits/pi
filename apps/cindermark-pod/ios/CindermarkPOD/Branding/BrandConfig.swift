import Foundation

/// The company details printed on every document and shown in the app.
///
/// These are the only place the wording lives. Edit them once here and the
/// header, the PDF footer, the email the WordPress plugin sends and the app's
/// About panel all follow.
enum BrandConfig {
   static let companyShortName = "CINDERMARK"
   static let companyName = "CINDERMARK MEDICAL LOGISTICS"
   static let divisionLine = "MEDICAL LOGISTICS"

   /// Printed under the signature block and in the PDF footer. Replace the
   /// placeholders with the real contact details before the first run.
   static let websiteLine = "cindermarklogistics.com"
   static let phoneLine = "(000) 000-0000"
   static let supportEmail = "dispatch@cindermarklogistics.com"

   static var footerLine: String {
      "\(companyName)  ·  \(websiteLine)  ·  \(phoneLine)"
   }

   /// Shown above the signature box. Reviewed wording matters here: this is the
   /// sentence the customer is agreeing to.
   static let attestation = """
   By signing below I confirm that the items listed on this document were \
   delivered to me at the place and time recorded here, that I have reviewed \
   the quantities shown, and that any shortage, damage or refusal is noted on \
   this document. This signature and its recorded time and location become part \
   of the delivery record.
   """
}
