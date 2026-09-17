<?php
/**
 * Optional dispatch side: stops the iPad can pull instead of typing in.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class CMPOD_Shipments {

	const POST_TYPE = 'cmpod_shipment';

	public static function register() {
		add_action( 'init', array( __CLASS__, 'register_post_type' ) );
		add_action( 'add_meta_boxes', array( __CLASS__, 'add_meta_box' ) );
		add_action( 'save_post_' . self::POST_TYPE, array( __CLASS__, 'save' ), 10, 2 );
		add_filter( 'manage_' . self::POST_TYPE . '_posts_columns', array( __CLASS__, 'columns' ) );
		add_action( 'manage_' . self::POST_TYPE . '_posts_custom_column', array( __CLASS__, 'render_column' ), 10, 2 );
	}

	public static function register_post_type() {
		register_post_type(
			self::POST_TYPE,
			array(
				'labels'          => array(
					'name'          => __( 'Stops', 'cindermark-pod' ),
					'singular_name' => __( 'Stop', 'cindermark-pod' ),
					'add_new_item'  => __( 'Add stop', 'cindermark-pod' ),
					'edit_item'     => __( 'Edit stop', 'cindermark-pod' ),
					'not_found'     => __( 'No stops queued.', 'cindermark-pod' ),
				),
				'public'          => false,
				'show_ui'         => true,
				'show_in_menu'    => 'edit.php?post_type=' . CMPOD_Records::POST_TYPE,
				'supports'        => array( 'title' ),
				'capability_type' => 'post',
				'map_meta_cap'    => true,
			)
		);
	}

	/**
	 * Open stops, in the wire shape the app expects.
	 *
	 * Every key is present even when empty: the app decodes defensively, but a
	 * complete object is one less thing that can differ between producers.
	 *
	 * @return array[]
	 */
	public static function open_shipments() {
		$posts = get_posts(
			array(
				'post_type'   => self::POST_TYPE,
				'post_status' => 'publish',
				'numberposts' => 100,
				'orderby'     => 'date',
				'order'       => 'ASC',
				'meta_query'  => array(
					array(
						'key'     => '_cmpod_completed',
						'compare' => 'NOT EXISTS',
					),
				),
			)
		);

		$shipments = array();
		foreach ( $posts as $post ) {
			$manifest = json_decode( (string) get_post_meta( $post->ID, '_cmpod_manifest', true ), true );
			if ( ! is_array( $manifest ) ) {
				continue;
			}
			$shipments[] = self::normalize( $manifest, $post );
		}
		return $shipments;
	}

	/**
	 * @param array   $manifest
	 * @param WP_Post $post
	 * @return array
	 */
	private static function normalize( $manifest, $post ) {
		$customer = isset( $manifest['customer'] ) && is_array( $manifest['customer'] ) ? $manifest['customer'] : array();
		$address  = isset( $customer['address'] ) && is_array( $customer['address'] ) ? $customer['address'] : array();

		$lines = array();
		if ( isset( $manifest['line_items'] ) && is_array( $manifest['line_items'] ) ) {
			foreach ( $manifest['line_items'] as $line ) {
				if ( ! is_array( $line ) ) {
					continue;
				}
				$lines[] = array(
					'id'                   => isset( $line['id'] ) ? (string) $line['id'] : wp_generate_uuid4(),
					'sku'                  => isset( $line['sku'] ) ? (string) $line['sku'] : '',
					'item_description'     => isset( $line['item_description'] ) ? (string) $line['item_description'] : '',
					'manufacturer'         => isset( $line['manufacturer'] ) ? (string) $line['manufacturer'] : '',
					'quantity_shipped'     => isset( $line['quantity_shipped'] ) ? (int) $line['quantity_shipped'] : 1,
					'unit_of_measure'      => isset( $line['unit_of_measure'] ) ? (string) $line['unit_of_measure'] : 'EA',
					'lot_number'           => isset( $line['lot_number'] ) ? (string) $line['lot_number'] : '',
					'serial_number'        => isset( $line['serial_number'] ) ? (string) $line['serial_number'] : '',
					'expiration_date'      => isset( $line['expiration_date'] ) ? (string) $line['expiration_date'] : null,
					'hcpcs_code'           => isset( $line['hcpcs_code'] ) ? (string) $line['hcpcs_code'] : '',
					'cold_chain'           => ! empty( $line['cold_chain'] ),
					'controlled_substance' => ! empty( $line['controlled_substance'] ),
				);
			}
		}

		$scheduled = isset( $manifest['scheduled_for'] ) ? (string) $manifest['scheduled_for'] : '';
		if ( '' === $scheduled ) {
			$scheduled = gmdate( 'Y-m-d\TH:i:s\Z', get_post_time( 'U', true, $post ) );
		}

		return array(
			'id'                    => isset( $manifest['id'] ) ? (string) $manifest['id'] : self::stable_uuid( $post->ID ),
			'order_number'          => isset( $manifest['order_number'] ) ? (string) $manifest['order_number'] : $post->post_title,
			'purchase_order'        => isset( $manifest['purchase_order'] ) ? (string) $manifest['purchase_order'] : '',
			'customer'              => array(
				'account_number' => isset( $customer['account_number'] ) ? (string) $customer['account_number'] : '',
				'company_name'   => isset( $customer['company_name'] ) ? (string) $customer['company_name'] : '',
				'contact_name'   => isset( $customer['contact_name'] ) ? (string) $customer['contact_name'] : '',
				'email'          => isset( $customer['email'] ) ? (string) $customer['email'] : '',
				'phone'          => isset( $customer['phone'] ) ? (string) $customer['phone'] : '',
				'address'        => array(
					'line1'       => isset( $address['line1'] ) ? (string) $address['line1'] : '',
					'line2'       => isset( $address['line2'] ) ? (string) $address['line2'] : '',
					'city'        => isset( $address['city'] ) ? (string) $address['city'] : '',
					'state'       => isset( $address['state'] ) ? (string) $address['state'] : '',
					'postal_code' => isset( $address['postal_code'] ) ? (string) $address['postal_code'] : '',
				),
			),
			'scheduled_for'         => $scheduled,
			'service_level'         => isset( $manifest['service_level'] ) ? (string) $manifest['service_level'] : 'Routine',
			'delivery_instructions' => isset( $manifest['delivery_instructions'] ) ? (string) $manifest['delivery_instructions'] : '',
			'line_items'            => $lines,
			'piece_count'           => isset( $manifest['piece_count'] ) ? (int) $manifest['piece_count'] : 1,
			'cold_chain_required'   => ! empty( $manifest['cold_chain_required'] ),
		);
	}

	/**
	 * A UUID that stays the same for a given stop, so pulling the run twice
	 * updates the stop on the iPad instead of duplicating it.
	 *
	 * @param int $post_id
	 * @return string
	 */
	private static function stable_uuid( $post_id ) {
		$hash = md5( 'cmpod-shipment-' . get_current_blog_id() . '-' . $post_id );
		return sprintf(
			'%s-%s-4%s-a%s-%s',
			substr( $hash, 0, 8 ),
			substr( $hash, 8, 4 ),
			substr( $hash, 13, 3 ),
			substr( $hash, 17, 3 ),
			substr( $hash, 20, 12 )
		);
	}

	/**
	 * Marks the matching stop done once its delivery arrives.
	 *
	 * @param string $order_number
	 */
	public static function mark_completed( $order_number ) {
		if ( '' === $order_number ) {
			return;
		}
		$posts = get_posts(
			array(
				'post_type'   => self::POST_TYPE,
				'post_status' => 'publish',
				'numberposts' => 5,
				'meta_key'    => '_cmpod_order',
				'meta_value'  => $order_number,
				'fields'      => 'ids',
			)
		);
		foreach ( $posts as $post_id ) {
			update_post_meta( $post_id, '_cmpod_completed', gmdate( 'Y-m-d H:i:s' ) );
		}
	}

	public static function add_meta_box() {
		add_meta_box(
			'cmpod_manifest',
			__( 'Manifest', 'cindermark-pod' ),
			array( __CLASS__, 'render_meta_box' ),
			self::POST_TYPE,
			'normal',
			'high'
		);
	}

	public static function render_meta_box( $post ) {
		wp_nonce_field( 'cmpod_save_manifest', 'cmpod_manifest_nonce' );
		$manifest = (string) get_post_meta( $post->ID, '_cmpod_manifest', true );
		if ( '' === $manifest ) {
			$manifest = wp_json_encode(
				array(
					'order_number' => '',
					'customer'     => array(
						'company_name' => '',
						'contact_name' => '',
						'email'        => '',
						'address'      => array( 'line1' => '', 'city' => '', 'state' => '', 'postal_code' => '' ),
					),
					'line_items'   => array(
						array( 'sku' => '', 'item_description' => '', 'quantity_shipped' => 1, 'unit_of_measure' => 'EA' ),
					),
				),
				JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES
			);
		}
		echo '<p>' . esc_html__( 'The stop as the app will see it. Keys match the manifest file format documented with the app.', 'cindermark-pod' ) . '</p>';
		printf(
			'<textarea name="cmpod_manifest" rows="20" class="large-text code" spellcheck="false">%s</textarea>',
			esc_textarea( $manifest )
		);
	}

	/**
	 * @param int     $post_id
	 * @param WP_Post $post
	 */
	public static function save( $post_id, $post ) {
		if ( defined( 'DOING_AUTOSAVE' ) && DOING_AUTOSAVE ) {
			return;
		}
		if ( ! isset( $_POST['cmpod_manifest_nonce'] ) || ! wp_verify_nonce( sanitize_key( $_POST['cmpod_manifest_nonce'] ), 'cmpod_save_manifest' ) ) {
			return;
		}
		if ( ! current_user_can( 'edit_post', $post_id ) ) {
			return;
		}
		if ( ! isset( $_POST['cmpod_manifest'] ) ) {
			return;
		}

		// Round-tripping through json_decode/encode both validates the input and
		// stores it normalised, so a stray trailing comma is caught here rather
		// than on the van.
		$raw     = wp_unslash( $_POST['cmpod_manifest'] );
		$decoded = json_decode( $raw, true );
		if ( ! is_array( $decoded ) ) {
			update_post_meta( $post_id, '_cmpod_manifest_error', __( 'The manifest was not valid JSON and was not saved.', 'cindermark-pod' ) );
			return;
		}
		delete_post_meta( $post_id, '_cmpod_manifest_error' );
		update_post_meta( $post_id, '_cmpod_manifest', wp_json_encode( $decoded, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES ) );
		update_post_meta( $post_id, '_cmpod_order', isset( $decoded['order_number'] ) ? sanitize_text_field( (string) $decoded['order_number'] ) : '' );
	}

	public static function columns( $columns ) {
		$columns['cmpod_stop_status'] = __( 'Status', 'cindermark-pod' );
		return $columns;
	}

	public static function render_column( $column, $post_id ) {
		if ( 'cmpod_stop_status' !== $column ) {
			return;
		}
		$error = get_post_meta( $post_id, '_cmpod_manifest_error', true );
		if ( $error ) {
			echo '<span style="color:#b32d2e">' . esc_html( $error ) . '</span>';
			return;
		}
		$completed = get_post_meta( $post_id, '_cmpod_completed', true );
		echo $completed ? esc_html__( 'Delivered', 'cindermark-pod' ) : esc_html__( 'Open', 'cindermark-pod' );
	}
}
