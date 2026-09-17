=== CINDERMARK Proof of Delivery ===
Contributors: cindermark
Tags: delivery, signature, proof of delivery, logistics
Requires at least: 6.2
Tested up to: 6.6
Requires PHP: 7.4
Stable tag: 1.0.0
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Receives signed proof-of-delivery records from the CINDERMARK POD iPad app, files them, and emails the customer their copy.

== Description ==

The site end of the CINDERMARK proof-of-delivery system. The iPad app captures
the customer's signature at the door; this plugin receives the signed record,
stores the document, and sends the customer their receipt from the company's own
business address using wp_mail().

* Signed deliveries are listed under **Deliveries**, with the order, the signer,
  the coordinates and whether the email went out.
* Documents are stored behind a deny rule and served only through the admin.
* Requests are authenticated with HMAC-SHA256 over a shared secret, with replay
  protection and a five-minute clock-skew window. No WordPress password or mail
  credential is stored on the iPad.
* The record id is an idempotency key: a retried upload never files a second
  copy or sends a second email.

== Installation ==

1. Upload the `cindermark-pod` folder to `/wp-content/plugins/`.
2. Activate the plugin. A pairing secret is generated automatically.
3. Open **Deliveries > Settings**, set the from name and from address to your
   business mailbox, and copy the site address and pairing secret into the iPad
   app under Settings.

On nginx, the deny rule protecting the document folder is not honoured. Either
add an equivalent `location` block for
`wp-content/uploads/cindermark-pod/`, or define `CMPOD_STORAGE_DIR` in
`wp-config.php` to move the folder outside the web root.

== Frequently Asked Questions ==

= Does this send email itself? =

No. It calls `wp_mail()`, so whatever the site already uses for business email
delivers the message. If mail is unreliable on the site generally, it will be
unreliable here.

= What happens when the iPad has no signal? =

Nothing on this end. The app files the receipt locally and retries the upload on
its own; this plugin sees it whenever it arrives.

= Are deliveries deleted when I uninstall? =

No. Uninstalling removes the plugin's settings only. Signed deliveries and their
documents stay, because a proof of delivery is a business record.

== Changelog ==

= 1.0.0 =
* First release.
