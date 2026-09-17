<?php
/**
 * The delivery archive: one post per signed proof of delivery.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class CMPOD_Records {

	const POST_TYPE = 'cmpod_delivery';

	public static function register() {
		add_action( 'init', array( __CLASS__, 'register_post_type' ) );
		add_filter( 'manage_' . self::POST_TYPE . '_posts_columns', array( __CLASS__, 'columns' ) );
		add_action( 'manage_' . self::POST_TYPE . '_posts_custom_column', array( __CLASS__, 'render_column' ), 10, 2 );
		add_action( 'add_meta_boxes', array( __CLASS__, 'add_meta_box' ) );
		add_action( 'admin_post_cmpod_download', array( __CLASS__, 'handle_download' ) );
	}

	public static function register_post_type() {
		register_post_type(
			self::POST_TYPE,
			array(
				'labels'          => array(
					'name'          => __( 'Deliveries', 'cindermark-pod' ),
					'singular_name' => __( 'Delivery', 'cindermark-pod' ),
					'menu_name'     => __( 'Deliveries', 'cindermark-pod' ),
					'search_items'  => __( 'Search deliveries', 'cindermark-pod' ),
					'not_found'     => __( 'No deliveries recorded yet.', 'cindermark-pod' ),
				),
				'public'          => false,
				'show_ui'         => true,
				'show_in_menu'    => true,
				'show_in_rest'    => false,
				'menu_icon'       => 'dashicons-clipboard',
				'menu_position'   => 26,
				'supports'        => array( 'title' ),
				'capability_type' => 'post',
				'map_meta_cap'    => true,
				'capabilities'    => array(
					// Records arrive from the app and are evidence; nobody
					// creates or rewrites one by hand in wp-admin.
					'create_posts' => 'do_not_allow',
				),
			)
		);
	}

	/**
	 * @param string $record_id
	 * @return int|null Post ID.
	 */
	public static function find_by_record_id( $record_id ) {
		$found = get_posts(
			array(
				'post_type'        => self::POST_TYPE,
				'post_status'      => 'any',
				'numberposts'      => 1,
				'fields'           => 'ids',
				'meta_key'         => '_cmpod_record_id',
				'meta_value'       => $record_id,
				'suppress_filters' => false,
			)
		);
		return empty( $found ) ? null : (int) $found[0];
	}

	/**
	 * Stores one delivery.
	 *
	 * @param array  $record         Decoded delivery record.
	 * @param array  $meta           Extra values: pdf_path, signature_path, pdf_sha256, payload_hash, record_json.
	 * @return int|WP_Error Post ID.
	 */
	public static function create( $record, $meta ) {
		$order    = isset( $record['order_number'] ) ? (string) $record['order_number'] : '';
		$customer = self::customer_name( $record );
		$signed   = self::signed_timestamp( $record );

		$title = trim( sprintf( '%s - %s', $order !== '' ? $order : __( 'No order number', 'cindermark-pod' ), $customer ) );

		$post_id = wp_insert_post(
			array(
				'post_type'     => self::POST_TYPE,
				'post_status'   => 'publish',
				'post_title'    => $title,
				'post_date_gmt' => gmdate( 'Y-m-d H:i:s', $signed ),
				'post_date'     => get_date_from_gmt( gmdate( 'Y-m-d H:i:s', $signed ) ),
			),
			true
		);

		if ( is_wp_error( $post_id ) ) {
			return $post_id;
		}

		$location = isset( $record['location'] ) && is_array( $record['location'] ) ? $record['location'] : array();
		$courier  = isset( $record['courier'] ) && is_array( $record['courier'] ) ? $record['courier'] : array();
		$signer   = isset( $record['signer'] ) && is_array( $record['signer'] ) ? $record['signer'] : array();

		$values = array(
			'_cmpod_record_id'      => isset( $record['id'] ) ? (string) $record['id'] : '',
			'_cmpod_order'          => $order,
			'_cmpod_customer'       => $customer,
			'_cmpod_customer_email' => isset( $record['customer']['email'] ) ? (string) $record['customer']['email'] : '',
			'_cmpod_signer'         => isset( $signer['printed_name'] ) ? (string) $signer['printed_name'] : '',
			'_cmpod_signed_at'      => gmdate( 'Y-m-d H:i:s', $signed ),
			'_cmpod_time_zone'      => isset( $record['time_zone_identifier'] ) ? (string) $record['time_zone_identifier'] : '',
			'_cmpod_latitude'       => isset( $location['latitude'] ) ? (string) $location['latitude'] : '',
			'_cmpod_longitude'      => isset( $location['longitude'] ) ? (string) $location['longitude'] : '',
			'_cmpod_accuracy'       => isset( $location['horizontal_accuracy_meters'] ) ? (string) $location['horizontal_accuracy_meters'] : '',
			'_cmpod_address'        => isset( $location['resolved_address'] ) ? (string) $location['resolved_address'] : '',
			'_cmpod_location_source' => isset( $location['source'] ) ? (string) $location['source'] : '',
			'_cmpod_driver'         => isset( $courier['driver_name'] ) ? (string) $courier['driver_name'] : '',
			'_cmpod_device'         => isset( $courier['device_id'] ) ? (string) $courier['device_id'] : '',
			'_cmpod_payload_hash'   => (string) $meta['payload_hash'],
			'_cmpod_pdf_sha256'     => (string) $meta['pdf_sha256'],
			'_cmpod_pdf_path'       => (string) $meta['pdf_path'],
			'_cmpod_signature_path' => (string) $meta['signature_path'],
			'_cmpod_record_json'    => (string) $meta['record_json'],
			'_cmpod_email_status'   => 'pending',
		);

		foreach ( $values as $key => $value ) {
			update_post_meta( $post_id, $key, $value );
		}

		/**
		 * Fires once a signed delivery has been filed.
		 *
		 * @param int   $post_id
		 * @param array $record
		 */
		do_action( 'cmpod_delivery_recorded', $post_id, $record );

		return $post_id;
	}

	/**
	 * @param array $record
	 * @return string
	 */
	public static function customer_name( $record ) {
		if ( ! isset( $record['customer'] ) || ! is_array( $record['customer'] ) ) {
			return __( 'Unnamed recipient', 'cindermark-pod' );
		}
		$customer = $record['customer'];
		foreach ( array( 'company_name', 'contact_name' ) as $key ) {
			if ( ! empty( $customer[ $key ] ) ) {
				return (string) $customer[ $key ];
			}
		}
		return __( 'Unnamed recipient', 'cindermark-pod' );
	}

	/**
	 * @param array $record
	 * @return int Unix timestamp.
	 */
	public static function signed_timestamp( $record ) {
		if ( empty( $record['signed_at'] ) ) {
			return time();
		}
		$parsed = strtotime( (string) $record['signed_at'] );
		return $parsed ? $parsed : time();
	}

	// MARK: Admin list

	public static function columns( $columns ) {
		return array(
			'cb'             => isset( $columns['cb'] ) ? $columns['cb'] : '',
			'title'          => __( 'Delivery', 'cindermark-pod' ),
			'cmpod_signed'   => __( 'Signed', 'cindermark-pod' ),
			'cmpod_signer'   => __( 'Signed by', 'cindermark-pod' ),
			'cmpod_location' => __( 'Location', 'cindermark-pod' ),
			'cmpod_email'    => __( 'Customer email', 'cindermark-pod' ),
		);
	}

	public static function render_column( $column, $post_id ) {
		switch ( $column ) {
			case 'cmpod_signed':
				$signed = get_post_meta( $post_id, '_cmpod_signed_at', true );
				echo $signed ? esc_html( get_date_from_gmt( $signed, 'M j, Y g:i a' ) ) : '&mdash;';
				break;
			case 'cmpod_signer':
				echo esc_html( get_post_meta( $post_id, '_cmpod_signer', true ) );
				break;
			case 'cmpod_location':
				$latitude  = get_post_meta( $post_id, '_cmpod_latitude', true );
				$longitude = get_post_meta( $post_id, '_cmpod_longitude', true );
				if ( '' === $latitude || '' === $longitude ) {
					echo '<span style="color:#b32d2e">' . esc_html__( 'Not recorded', 'cindermark-pod' ) . '</span>';
					break;
				}
				printf(
					'<a href="%s" target="_blank" rel="noopener noreferrer">%s</a>',
					esc_url( 'https://maps.apple.com/?ll=' . rawurlencode( $latitude . ',' . $longitude ) ),
					esc_html( $latitude . ', ' . $longitude )
				);
				break;
			case 'cmpod_email':
				$status = get_post_meta( $post_id, '_cmpod_email_status', true );
				$to     = get_post_meta( $post_id, '_cmpod_email_to', true );
				if ( 'sent' === $status ) {
					echo esc_html( sprintf( __( 'Sent to %s', 'cindermark-pod' ), $to ) );
				} elseif ( 'failed' === $status ) {
					echo '<span style="color:#b32d2e">' . esc_html__( 'Failed', 'cindermark-pod' ) . '</span>';
				} elseif ( 'skipped' === $status ) {
					echo esc_html__( 'Not requested', 'cindermark-pod' );
				} else {
					echo '&mdash;';
				}
				break;
		}
	}

	// MARK: Detail

	public static function add_meta_box() {
		add_meta_box(
			'cmpod_record',
			__( 'Delivery record', 'cindermark-pod' ),
			array( __CLASS__, 'render_meta_box' ),
			self::POST_TYPE,
			'normal',
			'high'
		);
	}

	public static function render_meta_box( $post ) {
		$record = json_decode( (string) get_post_meta( $post->ID, '_cmpod_record_json', true ), true );
		if ( ! is_array( $record ) ) {
			echo '<p>' . esc_html__( 'The stored record could not be read.', 'cindermark-pod' ) . '</p>';
			return;
		}

		$rows = array(
			__( 'Order', 'cindermark-pod' )        => get_post_meta( $post->ID, '_cmpod_order', true ),
			__( 'Customer', 'cindermark-pod' )     => get_post_meta( $post->ID, '_cmpod_customer', true ),
			__( 'Signed by', 'cindermark-pod' )    => get_post_meta( $post->ID, '_cmpod_signer', true ),
			__( 'Signed (UTC)', 'cindermark-pod' ) => get_post_meta( $post->ID, '_cmpod_signed_at', true ),
			__( 'Time zone', 'cindermark-pod' )    => get_post_meta( $post->ID, '_cmpod_time_zone', true ),
			__( 'Coordinates', 'cindermark-pod' )  => trim( get_post_meta( $post->ID, '_cmpod_latitude', true ) . ', ' . get_post_meta( $post->ID, '_cmpod_longitude', true ), ', ' ),
			__( 'Accuracy (m)', 'cindermark-pod' ) => get_post_meta( $post->ID, '_cmpod_accuracy', true ),
			__( 'Address', 'cindermark-pod' )      => get_post_meta( $post->ID, '_cmpod_address', true ),
			__( 'Driver', 'cindermark-pod' )       => get_post_meta( $post->ID, '_cmpod_driver', true ),
			__( 'Device', 'cindermark-pod' )       => get_post_meta( $post->ID, '_cmpod_device', true ),
			__( 'Record id', 'cindermark-pod' )    => get_post_meta( $post->ID, '_cmpod_record_id', true ),
			__( 'Record SHA-256', 'cindermark-pod' ) => get_post_meta( $post->ID, '_cmpod_payload_hash', true ),
			__( 'Document SHA-256', 'cindermark-pod' ) => get_post_meta( $post->ID, '_cmpod_pdf_sha256', true ),
		);

		echo '<table class="widefat striped"><tbody>';
		foreach ( $rows as $label => $value ) {
			printf(
				'<tr><th style="width:190px">%s</th><td><code style="user-select:all">%s</code></td></tr>',
				esc_html( $label ),
				esc_html( '' === $value ? '-' : $value )
			);
		}
		echo '</tbody></table>';

		echo '<p style="margin-top:14px">';
		printf(
			'<a class="button button-primary" href="%s">%s</a> ',
			esc_url( self::download_url( $post->ID, 'pdf' ) ),
			esc_html__( 'Download signed PDF', 'cindermark-pod' )
		);
		printf(
			'<a class="button" href="%s">%s</a>',
			esc_url( self::download_url( $post->ID, 'signature' ) ),
			esc_html__( 'Download signature image', 'cindermark-pod' )
		);
		echo '</p>';

		if ( ! empty( $record['line_items'] ) && is_array( $record['line_items'] ) ) {
			echo '<h3>' . esc_html__( 'Shipment contents', 'cindermark-pod' ) . '</h3>';
			echo '<table class="widefat striped"><thead><tr>';
			echo '<th>' . esc_html__( 'SKU', 'cindermark-pod' ) . '</th>';
			echo '<th>' . esc_html__( 'Item', 'cindermark-pod' ) . '</th>';
			echo '<th>' . esc_html__( 'Lot / Serial', 'cindermark-pod' ) . '</th>';
			echo '<th>' . esc_html__( 'Shipped', 'cindermark-pod' ) . '</th>';
			echo '<th>' . esc_html__( 'Received', 'cindermark-pod' ) . '</th>';
			echo '<th>' . esc_html__( 'Status', 'cindermark-pod' ) . '</th>';
			echo '</tr></thead><tbody>';
			foreach ( $record['line_items'] as $line ) {
				$item  = isset( $line['item'] ) && is_array( $line['item'] ) ? $line['item'] : array();
				$trace = trim( ( isset( $item['lot_number'] ) ? $item['lot_number'] : '' ) . ' ' . ( isset( $item['serial_number'] ) ? $item['serial_number'] : '' ) );
				printf(
					'<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
					esc_html( isset( $item['sku'] ) ? $item['sku'] : '' ),
					esc_html( isset( $item['item_description'] ) ? $item['item_description'] : '' ),
					esc_html( '' === $trace ? '-' : $trace ),
					esc_html( isset( $item['quantity_shipped'] ) ? $item['quantity_shipped'] : '' ),
					esc_html( isset( $line['quantity_received'] ) ? $line['quantity_received'] : '' ),
					esc_html( isset( $line['disposition'] ) ? $line['disposition'] : '' )
				);
			}
			echo '</tbody></table>';
		}
	}

	/**
	 * @param int    $post_id
	 * @param string $which 'pdf' or 'signature'.
	 * @return string
	 */
	public static function download_url( $post_id, $which ) {
		return wp_nonce_url(
			add_query_arg(
				array(
					'action' => 'cmpod_download',
					'post'   => $post_id,
					'file'   => $which,
				),
				admin_url( 'admin-post.php' )
			),
			'cmpod_download_' . $post_id
		);
	}

	/**
	 * Streams a stored document to an authorised admin user.
	 */
	public static function handle_download() {
		$post_id = isset( $_GET['post'] ) ? absint( $_GET['post'] ) : 0;
		$which   = isset( $_GET['file'] ) && 'signature' === $_GET['file'] ? 'signature' : 'pdf';

		if ( ! $post_id || ! current_user_can( 'edit_post', $post_id ) ) {
			wp_die( esc_html__( 'You are not allowed to download this document.', 'cindermark-pod' ), '', array( 'response' => 403 ) );
		}
		check_admin_referer( 'cmpod_download_' . $post_id );

		$post = get_post( $post_id );
		if ( ! $post || self::POST_TYPE !== $post->post_type ) {
			wp_die( esc_html__( 'Delivery not found.', 'cindermark-pod' ), '', array( 'response' => 404 ) );
		}

		$relative = (string) get_post_meta( $post_id, 'pdf' === $which ? '_cmpod_pdf_path' : '_cmpod_signature_path', true );
		$path     = CMPOD_Storage::absolute_path( $relative );
		$base     = realpath( CMPOD_Storage::base_dir() );
		$real     = realpath( $path );

		// The stored path came from this plugin, but a symlink or a hand-edited
		// meta value must not be able to read a file outside the archive.
		if ( ! $real || ! $base || 0 !== strpos( $real, $base ) || ! is_readable( $real ) ) {
			wp_die( esc_html__( 'That document is missing from the archive.', 'cindermark-pod' ), '', array( 'response' => 404 ) );
		}

		nocache_headers();
		header( 'Content-Type: ' . ( 'pdf' === $which ? 'application/pdf' : 'image/png' ) );
		header( 'Content-Length: ' . filesize( $real ) );
		header( 'Content-Disposition: attachment; filename="' . basename( $real ) . '"' );
		header( 'X-Content-Type-Options: nosniff' );
		readfile( $real );
		exit;
	}
}
