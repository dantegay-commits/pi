<?php
/**
 * Format sniffing, kept free of WordPress dependencies so it can be exercised
 * directly in tests. CMPOD_Storage::looks_like() delegates here.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class CMPOD_Storage_Sniff {

	/**
	 * Confirms bytes really are the format they were declared as, so a signed
	 * request cannot plant an executable file in the uploads folder.
	 *
	 * @param string $bytes
	 * @param string $kind 'pdf' or 'png'.
	 * @return bool
	 */
	public static function looks_like( $bytes, $kind ) {
		if ( 'pdf' === $kind ) {
			return 0 === strpos( $bytes, '%PDF-' );
		}
		if ( 'png' === $kind ) {
			return 0 === strpos( $bytes, "\x89PNG\r\n\x1a\n" );
		}
		return false;
	}
}
