# Handling patient data

A proof of delivery for medical supplies is patient data. The manifest names a
person, an address, and the equipment and consumables they use, which together
say a great deal about their health. In the United States, if CINDERMARK handles
this on behalf of a covered entity, it is protected health information and
CINDERMARK is a business associate.

This is not legal advice. It is the list of decisions this software leaves to
you, so none of them gets made by accident.

## Email

The plugin emails the customer their receipt, with the PDF attached by default.
That is what customers expect, and it is also the least controlled hop in the
whole system: ordinary email is not encrypted end to end, and once sent it sits
in a mailbox neither you nor the customer fully controls.

Three things worth settling before go-live:

1. **Does your mail provider have a business associate agreement with you?**
   Google Workspace and Microsoft 365 will sign one on their business tiers.
   Many small-business mail hosts will not. If yours will not, either move the
   mailbox or do not attach the PDF.
2. **Does the attachment need to be there?** Turning off "Attach the signed PDF"
   in the plugin settings sends a plain confirmation and keeps the document on
   the site. The customer emails or calls for a copy. Less convenient, much less
   exposure.
3. **Where does the copy go?** The "Always copy" address receives every receipt.
   Point it at a company mailbox, not a personal one.

## On the iPad

- Turn on a passcode and require Face ID or Touch ID. This app does not add its
  own lock; it relies on the device being locked.
- Turn on Find My and remote wipe.
- The Shipped folder is exposed to the Files app so a dispatcher can get at a
  receipt. That also means anyone who can unlock the iPad can read every
  delivery on it.
- Signed receipts are included in iCloud and encrypted local backups. If that is
  not what you want, the app has a hook for excluding them
  (`AppPaths.setExcludedFromBackup`) but does not do it by default, because for
  most small operators the backup is the only second copy.

## On the server

- Documents are stored behind a deny rule in the uploads folder and served only
  through the WordPress admin. On nginx that deny rule does nothing - see the
  README for the two ways to fix it.
- Anyone with an account that can edit posts can download any delivery document.
  If the site has contributors or authors who should not see patient data,
  tighten the capability check in `CMPOD_Records::handle_download()`.
- Keep the site on a host that will sign a business associate agreement, and keep
  WordPress and its plugins updated. A proof-of-delivery archive is a tempting
  target.

## Retention

Nothing is deleted automatically, by design: a plugin that quietly destroys
business records is worse than one that keeps too many. Decide a retention
period, write it down, and apply it deliberately - a quarterly task that removes
year/month folders older than the period, on both the iPad and the server.

Six to ten years is the usual range for delivery records tied to billing, but the
number depends on your contracts, your state, and what your covered-entity
customers require of you. Ask before you guess.

## Breach

If an iPad is lost, assume every delivery still filed on it is exposed. That is
the argument for clearing the Shipped folder off the device on a schedule once
records are confirmed on the server - not just for tidiness.
