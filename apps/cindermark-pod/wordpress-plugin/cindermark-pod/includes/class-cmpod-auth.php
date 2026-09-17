<?php
/**
 * Request authentication for the app endpoints.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class CMPOD_Auth {

	/** Requests older or newer than this are refused. */
	const MAX_SKEW_SECONDS = 300;

	/** How long a nonce is remembered, comfortably longer than the skew window. */
	const NONCE_TTL = 900;

	/**
	 * Verifies the HMAC on a request from the iPad.
	 *
	 * The app signs `device\ntimestamp\nnonce\nsha256(payload)` with the shared
	 * secret. Checking all four together means a captured request cannot be
	 * replayed, retargeted at another device id, or have its body swapped.
	 *
	 * @param WP_REST_Request $request
	 * @return true|WP_Error
	 */
	public static function verify( $request ) {
		$secret = (string) CMPOD_Settings::get( 'shared_secret' );
		if ( '' === trim( $secret ) ) {
			return new WP_Error(
				'cmpod_not_configured',
				__( 'This site has no pairing secret yet. Open Deliveries > Settings in WordPress.', 'cindermark-pod' ),
				array( 'status' => 503 )
			);
		}

		$device    = (string) $request->get_header( 'x-cindermark-device' );
		$timestamp = (string) $request->get_header( 'x-cindermark-timestamp' );
		$nonce     = (string) $request->get_header( 'x-cindermark-nonce' );
		$signature = (string) $request->get_header( 'x-cindermark-signature' );
		$sent_hash = (string) $request->get_header( 'x-cindermark-payload-hash' );

		if ( '' === $device || '' === $timestamp || '' === $nonce || '' === $signature || '' === $sent_hash ) {
			return self::refuse( __( 'The request was not signed.', 'cindermark-pod' ) );
		}

		$allowed = CMPOD_Settings::allowed_devices();
		if ( ! empty( $allowed ) && ! in_array( $device, $allowed, true ) ) {
			return self::refuse( __( 'This device is not on the allowed device list for this site.', 'cindermark-pod' ) );
		}

		if ( ! ctype_digit( $timestamp ) ) {
			return self::refuse( __( 'The request timestamp is malformed.', 'cindermark-pod' ) );
		}
		$skew = abs( time() - (int) $timestamp );
		if ( $skew > self::MAX_SKEW_SECONDS ) {
			return self::refuse(
				__( "The device clock is more than five minutes away from the site's. Check its date and time settings.", 'cindermark-pod' )
			);
		}

		$payload = self::payload_for( $request );
		$hash    = hash( 'sha256', $payload );
		if ( ! hash_equals( $hash, strtolower( $sent_hash ) ) ) {
			return self::refuse( __( 'The request body did not match its hash.', 'cindermark-pod' ) );
		}

		$canonical = $device . "\n" . $timestamp . "\n" . $nonce . "\n" . $hash;
		$expected  = hash_hmac( 'sha256', $canonical, $secret );
		if ( ! hash_equals( $expected, strtolower( $signature ) ) ) {
			return self::refuse( __( 'The request signature did not verify. Check that the device has the current pairing secret.', 'cindermark-pod' ) );
		}

		// Claim the nonce last: a request that failed verification should not be
		// able to burn a nonce, and a verified one must not be replayable.
		$nonce_key = 'cmpod_nonce_' . md5( $device . '|' . $nonce );
		if ( false !== get_transient( $nonce_key ) ) {
			return self::refuse( __( 'This request has already been received.', 'cindermark-pod' ) );
		}
		set_transient( $nonce_key, 1, self::NONCE_TTL );

		return true;
	}

	/**
	 * The exact bytes the signature covers.
	 *
	 * For a JSON request that is the raw body. For the multipart upload it is
	 * the `payload` form field; WordPress hands REST handlers the unslashed
	 * value, so these are the bytes the app sent.
	 *
	 * @param WP_REST_Request $request
	 * @return string
	 */
	public static function payload_for( $request ) {
		$body_params = $request->get_body_params();
		if ( isset( $body_params['payload'] ) && is_string( $body_params['payload'] ) ) {
			return $body_params['payload'];
		}
		return (string) $request->get_body();
	}

	/**
	 * @param string $message
	 * @return WP_Error
	 */
	private static function refuse( $message ) {
		return new WP_Error( 'cmpod_unauthorized', $message, array( 'status' => 401 ) );
	}
}
