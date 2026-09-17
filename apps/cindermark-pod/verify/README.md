# Verifying without a Mac

`./verify/run.sh` compiles and exercises the parts of the iOS app that do not
depend on Apple's UI frameworks, on any machine with a Swift toolchain.

It is not a substitute for building the app - it never touches a view, the PDF
renderer, PencilKit or Core Location. What it covers is the logic that is both
easy to get wrong and invisible to a code review:

- **Key mapping.** `convertToSnakeCase` and `convertFromSnakeCase` do not round
  trip acronym-cased names: `shipmentID` encodes to `shipment_id` and decodes
  back to `shipmentId`, which silently fails to match. Every property is checked.
- **Archive round-trip.** A `Shipment` encoded and decoded through the real
  coders comes back equal.
- **Lenient import.** The shipped sample manifest, including a stop that omits
  half its optional fields, decodes with sensible defaults - and something that
  is not a manifest is still rejected.
- **Record hashing.** The SHA-256 verifies by the documented procedure (blank
  `payload_hash`, re-encode canonically, hash), is deterministic, and changes
  when a quantity changes.
- **Cross-language agreement.** The Swift side writes its exact canonical bytes
  to disk and `crosscheck.php` runs the plugin's own checks over them: the same
  digest, the same HMAC, and every field path `CMPOD_Records::create()`
  dereferences actually present in what Swift emitted.

That last point is the seam most likely to fail silently. A renamed key does not
crash the plugin; it just files a record with an empty customer.

## Running it

```sh
./verify/run.sh
```

Needs a Swift toolchain (<https://www.swift.org/install/>) and `php`. On Linux
the toolchain is a tarball; no Xcode required.

## Adding a file to the check

Append it to `sources` in `run.sh`. If it imports SwiftUI, UIKit, PencilKit,
PDFKit or Combine the build will fail - which is the point. The list is the
record of which code is portable, and it is worth keeping honest: business logic
that has drifted into depending on a UI framework usually wants extracting.
