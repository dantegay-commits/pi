<?php
/**
 * Uninstall.
 *
 * Deliberately conservative: the settings go, the delivery records and the
 * signed documents stay. A signed proof of delivery is a business record, and
 * deactivating a plugin is not a decision to destroy it. Remove
 * wp-content/uploads/cindermark-pod by hand when you really mean it.
 */

if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}

delete_option( 'cmpod_settings' );
