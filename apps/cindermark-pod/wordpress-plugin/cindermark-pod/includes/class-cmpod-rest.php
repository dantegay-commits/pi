<?php
/**
 * The endpoints the iPad talks to.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class CMPOD_Rest {

	/** 12 MB is generous for a few pages of vector PDF. */
	const MAX_PDF_BYTES = 12582912;

	/** 6 MB is generous for a trimmed signature PNG. */
	const MAX_PNG_BYTES = 6291456;

	public static function register() {
		add_action( 'rest_api_init', array( __CLASS__, 'register_routes' ) );
	}

	public static function register_routes() {
		$auth = array( 'CMPOD_Auth', 'verify' );

		register_rest_route(
			CMPOD_REST_NAMESPACE,
			'/ping',
			array(
				'methods'             => 'POST',
				'callback'            => array( __CLASS__, 'handle_ping' ),
				'permission_callback' => $auth,
			)
		);

		register_rest_route(
			CMPOD_REST_NAMESPACE,
			'/pod',
			array(
				'methods'             => 'POST',
				'callback'            => array( __CLASS__, 'handle_pod' ),
				'permission_callback' => $auth,
			)
		);

		register_rest_route(
			CMPOD_REST_NAMESPACE,
			'/shipments',
			array(
				'methods'             => 'POST',
				'callback'            => array( __CLASS__, 'handle_shipments' ),
				'permission_callback' => $auth,
			)
		);
	}

	/**
	 * @return WP_REST_Response
	 */
	public static function handle_ping() {
		return new WP_REST_Response(
			array(
				'status'         => 'ok',
				'site'           => get_bloginfo( 'name' ),
				'plugin_version' => CMPOD_VERSION,
				'mail_from'      => (string) CMPOD_Settings::get( 'from_email' ),
			),
			200
		);
	}

	/**
	 * @return WP_REST_Response
	 */
	public static function handle_shipments() {
		return new WP_REST_Response( array( 'shipments' => CMPOD_Shipments::open_shipments() ), 200 );
	}

	/**
	 * Receives one signed delivery.
	 *
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function handle_pod( $request ) {
		$payload = json_decode( CMPOD_Auth::payload_for( $request ), true );
		if ( ! is_array( $payload ) ) {
			return self::bad_request( __( 'The upload payload was not valid JSON.', 'cindermark-pod' ) );
		}

		foreach ( array( 'record_canonical', 'payload_hash', 'pdf_sha256', 'signature_sha256' ) as $required ) {
			if ( empty( $payload[ $required ] ) || ! is_string( $payload[ $required ] ) ) {
				return self::bad_request(
					sprintf(
						/* translators: %s: field name */
						__( 'The upload payload is missing %s.', 'cindermark-pod' ),
						$required
					)
				);
			}
		}

		// The app hashes the record with payload_hash blanked and sends those
		// exact bytes, so verification here is a hash of what arrived rather
		// than an attempt to reproduce Swift's JSON encoding in PHP.
		$canonical = (string) $payload['record_canonical'];
		if ( ! hash_equals( hash( 'sha256', $canonical ), strtolower( (string) $payload['payload_hash'] ) ) ) {
			return self::bad_request( __( 'The delivery record did not match its hash.', 'cindermark-pod' ) );
		}

		$record = json_decode( $canonical, true );
		if ( ! is_array( $record ) || empty( $record['id'] ) ) {
			return self::bad_request( __( 'The delivery record could not be read.', 'cindermark-pod' ) );
		}

		$record_id = (string) $record['id'];
		if ( ! preg_match( '/^[0-9a-fA-F-]{36}$/', $record_id ) ) {
			return self::bad_request( __( 'The delivery record has an unusable id.', 'cindermark-pod' ) );
		}

		// The record id is the idempotency key. A retry after a dropped
		// connection must not file the delivery twice or email the customer
		// again.
		$existing = CMPOD_Records::find_by_record_id( $record_id );
		if ( $existing ) {
			return new WP_REST_Response(
				array(
					'status'    => 'ok',
					'record_id' => $record_id,
					'duplicate' => true,
					'emailed'   => 'sent' === get_post_meta( $existing, '_cmpod_email_status', true ),
					'emailed_to' => (string) get_post_meta( $existing, '_cmpod_email_to', true ),
					'message'   => __( 'This delivery was already on file.', 'cindermark-pod' ),
				),
				200
			);
		}

		$pdf = self::read_upload( $request, 'pod', self::MAX_PDF_BYTES, 'pdf', (string) $payload['pdf_sha256'] );
		if ( is_wp_error( $pdf ) ) {
			return $pdf;
		}
		$signature = self::read_upload( $request, 'signature', self::MAX_PNG_BYTES, 'png', (string) $payload['signature_sha256'] );
		if ( is_wp_error( $signature ) ) {
			return $signature;
		}

		$signed_at = CMPOD_Records::signed_timestamp( $record );
		$dir       = CMPOD_Storage::month_dir( $signed_at );
		if ( is_wp_error( $dir ) ) {
			return $dir;
		}

		$order = isset( $record['order_number'] ) ? (string) $record['order_number'] : '';
		$stem  = sprintf(
			'POD-%s-%s-%s',
			'' !== $order ? preg_replace( '/[^A-Za-z0-9_-]+/', '-', $order ) : 'NO-ORDER',
			gmdate( 'Ymd-His', $signed_at ),
			substr( str_replace( '-', '', $record_id ), 0, 8 )
		);

		$pdf_path = CMPOD_Storage::write( $dir, $stem . '.pdf', $pdf );
		if ( is_wp_error( $pdf_path ) ) {
			return $pdf_path;
		}
		$signature_path = CMPOD_Storage::write( $dir, $stem . '-signature.png', $signature );
		if ( is_wp_error( $signature_path ) ) {
			return $signature_path;
		}

		// The stored copy carries the hash it was verified against, so the
		// archive is self-describing.
		$record['payload_hash'] = strtolower( (string) $payload['payload_hash'] );

		$post_id = CMPOD_Records::create(
			$record,
			array(
				'payload_hash'   => strtolower( (string) $payload['payload_hash'] ),
				'pdf_sha256'     => strtolower( (string) $payload['pdf_sha256'] ),
				'pdf_path'       => CMPOD_Storage::relative_path( $pdf_path ),
				'signature_path' => CMPOD_Storage::relative_path( $signature_path ),
				'record_json'    => wp_json_encode( $record, JSON_UNESCAPED_SLASHES ),
			)
		);

		if ( is_wp_error( $post_id ) ) {
			return $post_id;
		}

		CMPOD_Shipments::mark_completed( $order );

		$emailed    = false;
		$emailed_to = '';
		$message    = '';
		$wants_mail = ! empty( $payload['send_customer_email'] );
		$to         = isset( $record['customer']['email'] ) ? (string) $record['customer']['email'] : '';

		if ( $wants_mail && '' !== $to ) {
			$result     = CMPOD_Mailer::send_receipt(
				$post_id,
				$record,
				$pdf_path,
				$to,
				isset( $payload['operations_email'] ) ? (string) $payload['operations_email'] : ''
			);
			$emailed    = $result['sent'];
			$emailed_to = $result['to'];
			$message    = $result['error'];
		} else {
			update_post_meta( $post_id, '_cmpod_email_status', 'skipped' );
			$message = $wants_mail
				? __( 'No customer email address was on the record.', 'cindermark-pod' )
				: __( 'The app asked for no customer email.', 'cindermark-pod' );
		}

		return new WP_REST_Response(
			array(
				'status'     => 'ok',
				'record_id'  => $record_id,
				'duplicate'  => false,
				'emailed'    => $emailed,
				'emailed_to' => $emailed_to,
				'message'    => $message,
				'admin_url'  => admin_url( 'post.php?post=' . $post_id . '&action=edit' ),
			),
			201
		);
	}

	/**
	 * Reads one uploaded file and checks it is what the payload said it was.
	 *
	 * @param WP_REST_Request $request
	 * @param string          $field         Multipart field name.
	 * @param int             $max_bytes
	 * @param string          $kind          'pdf' or 'png'.
	 * @param string          $expected_hash Lowercase SHA-256 from the payload.
	 * @return string|WP_Error File contents.
	 */
	private static function read_upload( $request, $field, $max_bytes, $kind, $expected_hash ) {
		$files = $request->get_file_params();
		if ( empty( $files[ $field ] ) || ! is_array( $files[ $field ] ) ) {
			return self::bad_request(
				sprintf(
					/* translators: %s: multipart field name */
					__( 'The upload is missing its %s file.', 'cindermark-pod' ),
					$field
				)
			);
		}

		$file = $files[ $field ];
		if ( ! empty( $file['error'] ) ) {
			return self::bad_request( __( 'The file did not upload completely. It may be larger than this server accepts.', 'cindermark-pod' ) );
		}
		if ( empty( $file['tmp_name'] ) || ! is_uploaded_file( $file['tmp_name'] ) ) {
			return self::bad_request( __( 'The upload could not be read.', 'cindermark-pod' ) );
		}
		if ( isset( $file['size'] ) && (int) $file['size'] > $max_bytes ) {
			return self::bad_request( __( 'The uploaded file is larger than this site accepts.', 'cindermark-pod' ) );
		}

		$bytes = file_get_contents( $file['tmp_name'] );
		if ( false === $bytes || '' === $bytes ) {
			return self::bad_request( __( 'The uploaded file was empty.', 'cindermark-pod' ) );
		}
		if ( strlen( $bytes ) > $max_bytes ) {
			return self::bad_request( __( 'The uploaded file is larger than this site accepts.', 'cindermark-pod' ) );
		}
		if ( ! CMPOD_Storage::looks_like( $bytes, $kind ) ) {
			return self::bad_request( __( 'The uploaded file was not the format it claimed to be.', 'cindermark-pod' ) );
		}
		if ( ! hash_equals( hash( 'sha256', $bytes ), strtolower( $expected_hash ) ) ) {
			return self::bad_request( __( 'The uploaded file did not match the hash on the signed record.', 'cindermark-pod' ) );
		}

		return $bytes;
	}

	/**
	 * @param string $message
	 * @return WP_Error
	 */
	private static function bad_request( $message ) {
		return new WP_Error( 'cmpod_bad_request', $message, array( 'status' => 400 ) );
	}
}
