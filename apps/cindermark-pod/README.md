# CINDERMARK Proof of Delivery

An iPadOS app for capturing a customer's signature when a medical supply
shipment is dropped off, and a WordPress plugin that files the signed receipt and
emails the customer a copy from the company's business address.

Two halves, both in this directory:

| | |
|---|---|
| `ios/` | The iPad app. SwiftUI, PencilKit, iOS 17+. |
| `wordpress-plugin/cindermark-pod/` | The site end. Receives the signed record, files it, sends the email. |
| `samples/manifest-example.json` | A manifest in the format the app imports. |
| `docs/` | Verifying a record, and notes on patient data. |

## What happens at the door

1. The driver opens the stop and checks each line with the customer. Short,
   damaged or refused lines are marked and need a note.
2. The customer signs with an Apple Pencil. With "Apple Pencil only" on, a hand
   resting on the glass cannot add strokes.
3. On completion the app reads the location once, stamps the time, renders the
   PDF, and writes it to the Shipped folder on the iPad.
4. The record is posted to the WordPress site, which files it and emails the
   customer their copy with the PDF attached.

Step 3 finishes before step 4 starts. A delivery is never lost to a dead signal:
if the upload fails, the receipt is already on the iPad and the app keeps
retrying on its own.

## What is on the receipt

Everything that was on the manifest, line by line: SKU, description,
manufacturer, lot and serial numbers, expiration date, HCPCS code, cold-chain and
controlled-substance flags, quantity shipped and quantity actually received, and
the status of each line. Exceptions are called out separately and in the email.

Under that, the signature, the printed name of the signer and how they were
authorised to sign, and a capture audit block:

- the signing time in local time with its zone, and again in UTC
- the coordinates to six decimal places, the accuracy in metres, and the
  street address they resolve to
- whether an Apple Pencil was used, how many strokes, and how long the signature
  took
- the driver, the iPad, the app version
- the record id and the SHA-256 of the record

The coordinates, the signing time and the hash are also written into the PDF's
own document metadata, so they travel with the file even if it is separated from
everything else.

If there is no location fix, the receipt says so in words. It never leaves the
reader to assume.

## Requirements

- Xcode 16 or newer, and an Apple Developer account to run on a real iPad
- iPadOS 17 or newer (the app also runs on iPhone; the layout is designed for
  iPad)
- An Apple Pencil, for the input it was built for
- WordPress 6.2+ on PHP 7.4+, with working outbound mail

## Building the app

```sh
open ios/CindermarkPOD.xcodeproj
```

Then, once:

1. Select the **CindermarkPOD** target > **Signing & Capabilities**, and choose
   your team. Xcode fills in a provisioning profile.
2. Change **Bundle Identifier** from `com.cindermark.pod` to something in a
   domain you own if you plan to distribute through Apple Business Manager.
3. Build and run on the iPad.

There are no package dependencies. The project uses a file-system synchronised
group, so new Swift files added to `ios/CindermarkPOD/` are picked up without
touching the project file.

### Adding the real logos

The app ships with a typographic stand-in so nothing renders as a blank box.
Drop the CINDERMARK artwork into these image sets in
`ios/CindermarkPOD/Assets.xcassets` and rebuild; the app and the PDF pick it up
automatically:

| Image set | Used for | Suggested |
|---|---|---|
| `LogoPrimary` | App screens | Full colour lockup, PDF vector or @1x/@2x/@3x PNG |
| `LogoDocument` | The PDF header | Dark or single-colour version, reads on white |
| `LogoMark` | Compact spots | The mark alone, no wordmark |

Those image sets are empty until you fill them, which Xcode reports as a build
warning. The build succeeds; the warning goes away with the artwork.

Company name, website, phone and the wording of the signed attestation live in
`ios/CindermarkPOD/Branding/BrandConfig.swift`. The palette is in the asset
catalog (`BrandEmber`, `BrandInk`, `BrandSlate`, `BrandPaper`) and mirrored as
fixed sRGB values in `BrandColor.Document` for the PDF, so a document printed
from an iPad in dark mode looks the same as one printed in light mode.

The app icon slot is empty. Add a 1024x1024 image to `AppIcon` before
distributing.

## Installing the WordPress plugin

1. Copy `wordpress-plugin/cindermark-pod/` into `wp-content/plugins/` on the
   site, or zip that folder and upload it under **Plugins > Add New > Upload**.
2. Activate it. A pairing secret is generated on activation.
3. Go to **Deliveries > Settings**.

Set the from name and from address to the company's business mailbox. Mail is
sent with `wp_mail()`, so whatever the site already uses for business email - an
SMTP plugin pointed at the CINDERMARK mailbox, a transactional provider, or the
host's mailer - is what delivers it. Nothing about mail credentials ever touches
the iPad.

Fill in "Always copy" with the dispatch address that should receive every
receipt.

## Pairing an iPad

In the app: **Settings**.

- **Site address**: the site's address, as shown on the plugin settings page
- **Pairing secret**: copy it from the same page
- **Driver name**: printed on every receipt
- Tap **Test connection**. It should come back with the site name and the
  address mail will be sent from.

To pin the site to known iPads, copy the device id shown under "This iPad" into
**Allowed device ids** on the settings page. Leaving that list empty accepts any
device holding the secret, which is the sensible default for a small operation.

Rotating the secret refuses every iPad still holding the old one, so re-pair them
in the same sitting.

## Loading the run

Three ways, in increasing order of automation:

- **New stop** in the app, typed in at the counter.
- **Import manifest file**: a JSON file, AirDropped or opened from Files. See
  `samples/manifest-example.json`. Missing optional fields are filled in with
  defaults, so a hand-edited file will not be rejected over an absent purchase
  order.
- **Pull run from site**: stops entered under **Deliveries > Stops** in
  WordPress. A stop is marked delivered automatically when its order number comes
  back on a signed record.

## Where the files are

On the iPad, under **Files > On My iPad > CINDERMARK POD**:

```
Shipped/2026/09/POD-SO-10482-20260917-141203.pdf            the signed document
Shipped/2026/09/POD-SO-10482-20260917-141203.json           the record and its hash
Shipped/2026/09/POD-SO-10482-20260917-141203-signature.png  the signature alone
```

There is no separate outbox. A delivery that has not reached the site yet is a
record in that same folder whose `upload_state` is not `uploaded`, so the queue
and the archive cannot disagree about what has been sent.

On the server, under `wp-content/uploads/cindermark-pod/YYYY/MM/`, behind a deny
rule and reachable only through the download buttons in the WordPress admin. The
deny rule is an `.htaccess` file, which Apache and LiteSpeed honour and nginx
ignores. On nginx, either add an equivalent `location` block or move the folder
out of the web root entirely:

```php
// wp-config.php
define( 'CMPOD_STORAGE_DIR', '/var/cindermark/pod-archive' );
```

## How the iPad proves it is the iPad

The app and the site share one secret. Every request carries the device id, a
timestamp, a random nonce and the SHA-256 of its payload, and an HMAC-SHA256 over
all four. The site recomputes the HMAC, refuses anything more than five minutes
out of step with its own clock, and refuses a nonce it has already seen.

That means no WordPress password, no application password and no mail credential
ever lives on the iPad. The secret is stored in the keychain, pinned to the
device, so restoring a backup onto a second iPad does not carry it across.

The record id is the idempotency key. Retrying a delivery after a dropped
connection returns the record already on file; it does not file a second copy and
does not email the customer twice.

The signed payload carries the SHA-256 of both the PDF and the signature image,
and the site checks the uploaded bytes against them and sniffs their format
before writing anything to disk.

## Verifying a record later

See `docs/verifying-a-record.md`. In short: take the archived JSON, blank
`payload_hash`, re-encode it with sorted keys, and hash it. It will match the
hash printed on the PDF unless the record has been edited.

## Running the plugin's tests

```sh
cd wordpress-plugin/cindermark-pod && php tests/test-auth.php
```

Covers request signing, replay rejection, clock skew, body tampering, the device
allow-list and file format sniffing. No WordPress install needed.

## What this does not do

- **It is not verified against a real build.** The Swift was written without a
  Mac to compile it on; expect to fix small things the first time you open it in
  Xcode. The PHP is syntax-checked and its auth path is tested.
- No offline map tiles, barcode scanning, temperature logging or route
  optimisation.
- No multi-driver accounts. Every iPad is one device with one driver name.
- Nothing is deleted on uninstall. A signed proof of delivery is a business
  record; removing the plugin removes its settings and leaves the archive alone.
- Retention and disposal are not automated. Decide a retention period and apply
  it deliberately - see `docs/handling-patient-data.md`.
