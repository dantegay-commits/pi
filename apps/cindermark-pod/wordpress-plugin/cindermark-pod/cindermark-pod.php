<?php
/**
 * Plugin Name:       CINDERMARK Proof of Delivery
 * Plugin URI:        https://cindermarklogistics.com/
 * Description:       Receives signed proof-of-delivery records from the CINDERMARK POD iPad app, files them, and emails the customer their copy from the site's business address.
 * Version:           1.0.0
 * Requires at least: 6.2
 * Requires PHP:      7.4
 * Author:            CINDERMARK Medical Logistics
 * License:           GPL-2.0-or-later
 * Text Domain:       cindermark-pod
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'CMPOD_VERSION', '1.0.0' );
define( 'CMPOD_PLUGIN_FILE', __FILE__ );
define( 'CMPOD_PLUGIN_DIR', plugin_dir_path( __FILE__ ) );
define( 'CMPOD_REST_NAMESPACE', 'cindermark/v1' );

require_once CMPOD_PLUGIN_DIR . 'includes/class-cmpod-settings.php';
require_once CMPOD_PLUGIN_DIR . 'includes/class-cmpod-storage-sniff.php';
require_once CMPOD_PLUGIN_DIR . 'includes/class-cmpod-storage.php';
require_once CMPOD_PLUGIN_DIR . 'includes/class-cmpod-auth.php';
require_once CMPOD_PLUGIN_DIR . 'includes/class-cmpod-records.php';
require_once CMPOD_PLUGIN_DIR . 'includes/class-cmpod-shipments.php';
require_once CMPOD_PLUGIN_DIR . 'includes/class-cmpod-mailer.php';
require_once CMPOD_PLUGIN_DIR . 'includes/class-cmpod-rest.php';

/**
 * Wires the plugin up once WordPress has loaded.
 */
function cmpod_boot() {
	CMPOD_Records::register();
	CMPOD_Shipments::register();
	CMPOD_Settings::register();
	CMPOD_Rest::register();
}
add_action( 'plugins_loaded', 'cmpod_boot' );

/**
 * Creates the protected upload folder and a pairing secret on activation.
 *
 * The secret is generated here rather than asked for, so an operator never has
 * to invent one and never ends up with a guessable value.
 */
function cmpod_activate() {
	CMPOD_Records::register();
	CMPOD_Shipments::register();
	flush_rewrite_rules();
	CMPOD_Storage::ensure_base_dir();
	CMPOD_Settings::ensure_secret();
}
register_activation_hook( __FILE__, 'cmpod_activate' );

function cmpod_deactivate() {
	flush_rewrite_rules();
}
register_deactivation_hook( __FILE__, 'cmpod_deactivate' );
