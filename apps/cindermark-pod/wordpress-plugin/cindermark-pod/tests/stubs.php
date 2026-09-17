<?php
/**
 * Minimal WordPress stand-ins so the pure-logic classes can be exercised
 * without a WordPress install. Only what the classes under test touch.
 */

define( 'ABSPATH', __DIR__ . '/' );

class WP_Error {
	public $code;
	public $message;
	public $data;

	public function __construct( $code = '', $message = '', $data = array() ) {
		$this->code    = $code;
		$this->message = $message;
		$this->data    = $data;
	}

	public function get_error_code() {
		return $this->code;
	}

	public function get_error_message() {
		return $this->message;
	}
}

function is_wp_error( $thing ) {
	return $thing instanceof WP_Error;
}

function __( $text, $domain = null ) {
	return $text;
}

$GLOBALS['cmpod_transients'] = array();

function get_transient( $key ) {
	return isset( $GLOBALS['cmpod_transients'][ $key ] ) ? $GLOBALS['cmpod_transients'][ $key ] : false;
}

function set_transient( $key, $value, $ttl = 0 ) {
	$GLOBALS['cmpod_transients'][ $key ] = $value;
	return true;
}

/** Stands in for WP_REST_Request. */
class CMPOD_Test_Request {
	private $headers;
	private $body_params;
	private $body;

	public function __construct( $headers = array(), $body_params = array(), $body = '' ) {
		$this->headers     = array();
		foreach ( $headers as $name => $value ) {
			$this->headers[ strtolower( str_replace( '_', '-', $name ) ) ] = $value;
		}
		$this->body_params = $body_params;
		$this->body        = $body;
	}

	public function get_header( $name ) {
		$name = strtolower( str_replace( '_', '-', $name ) );
		return isset( $this->headers[ $name ] ) ? $this->headers[ $name ] : null;
	}

	public function get_body_params() {
		return $this->body_params;
	}

	public function get_body() {
		return $this->body;
	}
}
