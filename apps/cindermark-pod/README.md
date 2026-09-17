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
| `brand/` | The logo source and the script that rebuilds the artwork from it. |
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

- Xcode 16 or newer, and an Apple Developer account to run on real hardware
- iOS or iPadOS 16 or newer
- An Apple Pencil, for the input the signature screen was built for. A finger
  works; turn off "Apple Pencil only" in Settings first.
- WordPress 6.2+ on PHP 7.4+, with working outbound mail

## Which devices it runs on

Every iPhone and iPad that can run iOS 16: **iPhone 8 and later**, **iPad 5th
generation and later**, all iPad Air, iPad mini 5 and later, and every iPad Pro.
That is roughly everything Apple has sold since 2017.

iOS 16 rather than 17 is a deliberate choice. Dropping to 16 costs nothing and
picks up the iPhone 8, iPhone X and the 5th-generation iPad - exactly the
hand-me-down devices a small fleet ends up running. Going further back to iOS 15
would mean giving up `NavigationSplitView`, `ShareLink` and `LabeledContent`,
which is to say the whole iPad two-pane design, to gain devices from 2015 and
2016 that cannot be bought new and mostly have dead batteries. Not worth it.

The layout adapts on **size class, not device**, which matters more than it
sounds:

| Width | What you get |
|---|---|
| Regular (iPad, iPhone Max in landscape) | Two panes: run list beside the stop; manifest beside the signature box |
| Compact (any iPhone, iPad in Slide Over or a narrow Split View) | One pane at a time; the manifest moves behind an "Items & terms" button so the signature box is never squeezed off screen |

Because it keys off size class, an iPad in Slide Over gets the phone layout
automatically, and a Max-sized iPhone turned landscape gets the two-pane one.

Two details the phone layout exists to protect:

- **The signature canvas is never inside a scroll view.** `PKCanvasView` is
  itself a scroll view; nesting the two makes a finger-drawn signature scroll
  the page instead of drawing on it. On a narrow screen the canvas takes
  whatever height is left over rather than being placed in a scrolling column.
- **Text fields get the full row width.** `LabeledContent` puts the field in the
  trailing half, which is fine on an iPad and leaves a phone about enough room
  to type an email address into but not to check it.

## Building the app

```sh
open ios/CindermarkPOD.xcodeproj
```

Then, once:

1. Select the **CindermarkPOD** target > **Signing & Capabilities**, and choose
   your team. Xcode fills in a provisioning profile.
2. Change **Bundle Identifier** from `com.cindermark.pod` to something in a
   domain you own if you plan to distribute through Apple Business Manager.
3. Build and run. The app builds for iPhone and iPad from the one target.

There are no package dependencies. The project uses a file-system synchronised
group, so new Swift files added to `ios/CindermarkPOD/` are picked up without
touching the project file.

### Branding

The CINDERMARK logo is already in the app, the app icon and the PDF header. It
was rebuilt from a photo of the logo on a screen - see `brand/README.md` for how,
and for how to replace it if the original vector artwork turns up. Four
arrangements are in the asset catalog:

| Image set | Used for |
|---|---|
| `LogoDocument` | Horizontal lockup: the PDF header band and toolbars |
| `LogoPrimary` | Stacked lockup: large, centred moments |
| `LogoMark` | The C and its road, alone |
| `LogoWordmark` | The type, alone |

The stacked lockup is nearly square, so in a 22pt toolbar it would shrink to
about 28pt wide and read as a smudge. That is why headers use the horizontal
arrangement, and only the empty state uses the stacked one.

The palette comes from the artwork itself: navy `#364564` for the letterform and
ink, road blue `#3D6FB0` for the accent. Both are in the asset catalog
(`BrandInk`, `BrandRoad`, `BrandSlate`, `BrandPaper`, `BrandAlert`) and mirrored
as fixed sRGB values in `BrandColor.Document` for the PDF, so a document printed
from an iPad in dark mode looks the same as one printed in light mode.

`BrandAlert` is deliberately outside the brand. An exception on a receipt has to
read as an exception, and brand blue would make it look like another heading.

Company name, website, phone and the wording of the signed attestation live in
`ios/CindermarkPOD/Branding/BrandConfig.swift`.

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
- The logo artwork is recovered from a photograph, not from the original vector
  file, so it is very slightly soft at large sizes and the two brand colours are
  measured approximations. `brand/README.md` covers replacing both.
- No offline map tiles, barcode scanning, temperature logging or route
  optimisation.
- No multi-driver accounts. Every device carries one driver name.
- Nothing is deleted on uninstall. A signed proof of delivery is a business
  record; removing the plugin removes its settings and leaves the archive alone.
- Retention and disposal are not automated. Decide a retention period and apply
  it deliberately - see `docs/handling-patient-data.md`.
