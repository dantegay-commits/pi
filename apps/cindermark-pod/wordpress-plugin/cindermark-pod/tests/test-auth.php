<?php
/**
 * Exercises request signing, replay protection and file sniffing.
 *
 * Run: php tests/test-auth.php
 */

require_once __DIR__ . '/stubs.php';

// CMPOD_Settings reaches into WordPress options, so the tests substitute a
// stub with the same two static methods CMPOD_Auth uses.
class CMPOD_Settings {
	public static $secret  = 'test-secret-value';
	public static $devices = array();

	public static function get( $key, $fallback = '' ) {
		return 'shared_secret' === $key ? self::$secret : $fallback;
	}

	public static function allowed_devices() {
		return self::$devices;
	}
}

require_once __DIR__ . '/../includes/class-cmpod-auth.php';
require_once __DIR__ . '/../includes/class-cmpod-storage-sniff.php';

$failures = 0;
$checks   = 0;

function check( $label, $condition ) {
	global $failures, $checks;
	$checks++;
	if ( $condition ) {
		echo "  ok   $label\n";
		return;
	}
	$failures++;
	echo "  FAIL $label\n";
}

/**
 * Builds a signed request the way the iPad does.
 */
function signed_request( $payload, $overrides = array() ) {
	$device    = isset( $overrides['device'] ) ? $overrides['device'] : 'ipad-test-0001';
	$timestamp = isset( $overrides['timestamp'] ) ? $overrides['timestamp'] : (string) time();
	$nonce     = isset( $overrides['nonce'] ) ? $overrides['nonce'] : 'nonce-' . wp_unique();
	$secret    = isset( $overrides['secret'] ) ? $overrides['secret'] : CMPOD_Settings::$secret;
	$hash      = isset( $overrides['hash'] ) ? $overrides['hash'] : hash( 'sha256', $payload );
	$canonical = $device . "\n" . $timestamp . "\n" . $nonce . "\n" . $hash;
	$signature = isset( $overrides['signature'] ) ? $overrides['signature'] : hash_hmac( 'sha256', $canonical, $secret );

	return new CMPOD_Test_Request(
		array(
			'X-Cindermark-Device'       => $device,
			'X-Cindermark-Timestamp'    => $timestamp,
			'X-Cindermark-Nonce'        => $nonce,
			'X-Cindermark-Signature'    => $signature,
			'X-Cindermark-Payload-Hash' => $hash,
		),
		array( 'payload' => $payload )
	);
}

$counter = 0;
function wp_unique() {
	global $counter;
	$counter++;
	return (string) $counter;
}

echo "Request signing\n";

$payload = '{"a":1,"record_canonical":"{}"}';

$request = signed_request( $payload );
check( 'a correctly signed request is accepted', true === CMPOD_Auth::verify( $request ) );

$request = signed_request( $payload );
CMPOD_Auth::verify( $request );
check( 'the same request replayed is refused', is_wp_error( CMPOD_Auth::verify( $request ) ) );

$request = signed_request( $payload, array( 'signature' => str_repeat( 'a', 64 ) ) );
check( 'a bad signature is refused', is_wp_error( CMPOD_Auth::verify( $request ) ) );

$request = signed_request( $payload, array( 'secret' => 'the-wrong-secret' ) );
check( 'a signature from the wrong secret is refused', is_wp_error( CMPOD_Auth::verify( $request ) ) );

$request = signed_request( $payload, array( 'timestamp' => (string) ( time() - 600 ) ) );
check( 'a ten-minute-old request is refused', is_wp_error( CMPOD_Auth::verify( $request ) ) );

$request = signed_request( $payload, array( 'timestamp' => (string) ( time() + 600 ) ) );
check( 'a request from the future is refused', is_wp_error( CMPOD_Auth::verify( $request ) ) );

$request = signed_request( $payload, array( 'hash' => hash( 'sha256', 'something else' ) ) );
check( 'a payload that does not match its hash is refused', is_wp_error( CMPOD_Auth::verify( $request ) ) );

// A tampered body with a hash and signature recomputed over the *original*
// payload: the signature verifies over the header hash, but the body hash check
// must still catch it.
$request = new CMPOD_Test_Request(
	array(
		'X-Cindermark-Device'       => 'ipad-test-0001',
		'X-Cindermark-Timestamp'    => (string) time(),
		'X-Cindermark-Nonce'        => 'nonce-tamper',
		'X-Cindermark-Signature'    => hash_hmac(
			'sha256',
			"ipad-test-0001\n" . time() . "\nnonce-tamper\n" . hash( 'sha256', $payload ),
			CMPOD_Settings::$secret
		),
		'X-Cindermark-Payload-Hash' => hash( 'sha256', $payload ),
	),
	array( 'payload' => $payload . 'tampered' )
);
check( 'a tampered body is refused', is_wp_error( CMPOD_Auth::verify( $request ) ) );

CMPOD_Settings::$devices = array( 'ipad-known' );
$request                 = signed_request( $payload, array( 'device' => 'ipad-unknown' ) );
check( 'an unlisted device is refused when a list is set', is_wp_error( CMPOD_Auth::verify( $request ) ) );

$request = signed_request( $payload, array( 'device' => 'ipad-known' ) );
check( 'a listed device is accepted', true === CMPOD_Auth::verify( $request ) );
CMPOD_Settings::$devices = array();

$request = new CMPOD_Test_Request( array(), array( 'payload' => $payload ) );
check( 'an unsigned request is refused', is_wp_error( CMPOD_Auth::verify( $request ) ) );

CMPOD_Settings::$secret = '';
$request                = signed_request( $payload, array( 'secret' => '' ) );
$result                 = CMPOD_Auth::verify( $request );
check( 'an unpaired site refuses everything', is_wp_error( $result ) && 'cmpod_not_configured' === $result->get_error_code() );
CMPOD_Settings::$secret = 'test-secret-value';

echo "\nPayload selection\n";

$multipart = new CMPOD_Test_Request( array(), array( 'payload' => 'from-the-form-field' ), 'from-the-raw-body' );
check( 'multipart uploads hash the payload field', 'from-the-form-field' === CMPOD_Auth::payload_for( $multipart ) );

$json = new CMPOD_Test_Request( array(), array(), '{"json":true}' );
check( 'json requests hash the raw body', '{"json":true}' === CMPOD_Auth::payload_for( $json ) );

echo "\nFile sniffing\n";

check( 'a real PDF header is accepted', CMPOD_Storage_Sniff::looks_like( "%PDF-1.7\n...", 'pdf' ) );
check( 'a PHP file posing as a PDF is refused', ! CMPOD_Storage_Sniff::looks_like( "<?php echo 1;", 'pdf' ) );
check( 'a real PNG header is accepted', CMPOD_Storage_Sniff::looks_like( "\x89PNG\r\n\x1a\n\x00\x00", 'png' ) );
check( 'a PDF posing as a PNG is refused', ! CMPOD_Storage_Sniff::looks_like( '%PDF-1.7', 'png' ) );

echo "\n$checks checks, $failures failed\n";
exit( $failures > 0 ? 1 : 0 );
