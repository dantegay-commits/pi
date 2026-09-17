#!/usr/bin/env bash
#
# Compile and exercise the parts of the iOS app that do not depend on Apple's
# UI frameworks, on any machine with a Swift toolchain - no Mac, no Xcode.
#
# It cannot build the app. What it can do is prove the things a visual pass over
# the code would never catch: that the models survive the encoder and decoder
# that archive them, that a hand-edited manifest still imports, and that the
# SHA-256 and HMAC the iPad produces are byte-for-byte what the WordPress plugin
# recomputes. That last one is the seam most likely to break silently.
#
#   ./verify/run.sh
#
# Requires: a Swift toolchain (swift.org/install), and php for the server half.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$here/.."
work="${TMPDIR:-/tmp}/cindermark-verify"

if ! command -v swift >/dev/null; then
  echo "swift not found. Install a toolchain from https://www.swift.org/install/" >&2
  exit 127
fi

# Only the sources free of SwiftUI, UIKit, PencilKit, PDFKit and Combine. Adding
# a file here that imports one of those will fail the build, which is the point:
# the list is the record of what is portable.
sources=(
  Models/Shipment.swift
  Models/DeliveryRecord.swift
  Services/StringSupport.swift
  Services/PodCoding.swift
  Services/RequestSigner.swift
  Branding/BrandConfig.swift
)

rm -rf "$work"
mkdir -p "$work/Sources/PodCore" "$work/Sources/PodCheck"
for f in "${sources[@]}"; do
  ln -s "$app/ios/CindermarkPOD/$f" "$work/Sources/PodCore/$(basename "$f")"
done
cp "$here/PodCheck/main.swift" "$work/Sources/PodCheck/main.swift"

cat > "$work/Package.swift" <<'PKG'
// swift-tools-version:6.0
import PackageDescription

// CryptoKit is Apple-only; swift-crypto is Apple's own API-identical port, which
// is why PodCoding and RequestSigner import it behind #if canImport(CryptoKit).
let package = Package(
   name: "PodCheck",
   platforms: [.macOS(.v13)],
   dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")],
   targets: [
      .target(name: "PodCore",
              dependencies: [.product(name: "Crypto", package: "swift-crypto")],
              swiftSettings: [.swiftLanguageMode(.v5)]),
      .executableTarget(name: "PodCheck", dependencies: ["PodCore"],
                        swiftSettings: [.swiftLanguageMode(.v5)]),
   ]
)
PKG

export POD_SAMPLE_MANIFEST="$app/samples/manifest-example.json"
export POD_OUT_DIR="$work"

echo "Building the portable core (Swift 5 language mode, matching the Xcode project)"
( cd "$work" && swift build 2>&1 | grep -Ev '^\[|^Building|^Compiling|^Fetching|^Fetched|^Computing|^Creating' || true )

echo
( cd "$work" && swift run --quiet PodCheck )
swift_status=$?

echo
if command -v php >/dev/null; then
  php "$here/crosscheck.php"
else
  echo "php not found - skipping the server-side cross-check" >&2
fi

exit $swift_status
