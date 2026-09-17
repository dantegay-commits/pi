<?php
/**
 * Plugin options and the admin settings screen.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class CMPOD_Settings {

	const OPTION = 'cmpod_settings';

	/**
	 * Defaults, also the shape of the stored option.
	 *
	 * @return array
	 */
	public static function defaults() {
		return array(
			'shared_secret'   => '',
			'allowed_devices' => '',
			'from_name'       => get_bloginfo( 'name' ),
			'from_email'      => get_option( 'admin_email' ),
			'reply_to'        => get_option( 'admin_email' ),
			'bcc_email'       => '',
			'attach_pdf'      => 1,
			'email_subject'   => 'Your delivery receipt from {company} - order {order}',
		);
	}

	/**
	 * @return array
	 */
	public static function all() {
		$stored = get_option( self::OPTION, array() );
		if ( ! is_array( $stored ) ) {
			$stored = array();
		}
		return array_merge( self::defaults(), $stored );
	}

	/**
	 * @param string $key
	 * @param mixed  $fallback
	 * @return mixed
	 */
	public static function get( $key, $fallback = '' ) {
		$all = self::all();
		return isset( $all[ $key ] ) ? $all[ $key ] : $fallback;
	}

	/**
	 * Generates a pairing secret if there is not one already.
	 *
	 * @return string
	 */
	public static function ensure_secret() {
		$settings = self::all();
		if ( '' === trim( (string) $settings['shared_secret'] ) ) {
			$settings['shared_secret'] = wp_generate_password( 48, false, false );
			update_option( self::OPTION, $settings );
		}
		return $settings['shared_secret'];
	}

	/**
	 * Device identifiers allowed to post. An empty list means any device that
	 * holds the shared secret is accepted, which is the sensible default for a
	 * one-van operation; filling it in pins the site to known iPads.
	 *
	 * @return string[]
	 */
	public static function allowed_devices() {
		$raw = (string) self::get( 'allowed_devices' );
		$ids = preg_split( '/[\r\n,]+/', $raw );
		$ids = array_filter( array_map( 'trim', is_array( $ids ) ? $ids : array() ) );
		return array_values( $ids );
	}

	public static function register() {
		add_action( 'admin_menu', array( __CLASS__, 'add_menu' ) );
		add_action( 'admin_init', array( __CLASS__, 'register_settings' ) );
		add_action( 'admin_post_cmpod_regenerate_secret', array( __CLASS__, 'handle_regenerate_secret' ) );
	}

	public static function add_menu() {
		add_submenu_page(
			'edit.php?post_type=' . CMPOD_Records::POST_TYPE,
			__( 'Proof of Delivery Settings', 'cindermark-pod' ),
			__( 'Settings', 'cindermark-pod' ),
			'manage_options',
			'cmpod-settings',
			array( __CLASS__, 'render_page' )
		);
	}

	public static function register_settings() {
		register_setting(
			'cmpod_settings_group',
			self::OPTION,
			array(
				'type'              => 'array',
				'sanitize_callback' => array( __CLASS__, 'sanitize' ),
				'default'           => self::defaults(),
			)
		);
	}

	/**
	 * @param mixed $input
	 * @return array
	 */
	public static function sanitize( $input ) {
		$current = self::all();
		if ( ! is_array( $input ) ) {
			return $current;
		}

		$clean = array();
		// The secret is never edited through this form; it is generated and
		// rotated by its own action, so a stray empty field cannot wipe it.
		$clean['shared_secret']   = $current['shared_secret'];
		$clean['allowed_devices'] = isset( $input['allowed_devices'] ) ? sanitize_textarea_field( $input['allowed_devices'] ) : '';
		$clean['from_name']       = isset( $input['from_name'] ) ? sanitize_text_field( $input['from_name'] ) : '';
		$clean['from_email']      = isset( $input['from_email'] ) ? sanitize_email( $input['from_email'] ) : '';
		$clean['reply_to']        = isset( $input['reply_to'] ) ? sanitize_email( $input['reply_to'] ) : '';
		$clean['bcc_email']       = isset( $input['bcc_email'] ) ? sanitize_email( $input['bcc_email'] ) : '';
		$clean['attach_pdf']      = empty( $input['attach_pdf'] ) ? 0 : 1;
		$clean['email_subject']   = isset( $input['email_subject'] ) ? sanitize_text_field( $input['email_subject'] ) : self::defaults()['email_subject'];

		if ( '' === $clean['email_subject'] ) {
			$clean['email_subject'] = self::defaults()['email_subject'];
		}

		return $clean;
	}

	public static function handle_regenerate_secret() {
		if ( ! current_user_can( 'manage_options' ) ) {
			wp_die( esc_html__( 'You are not allowed to do that.', 'cindermark-pod' ) );
		}
		check_admin_referer( 'cmpod_regenerate_secret' );

		$settings                  = self::all();
		$settings['shared_secret'] = wp_generate_password( 48, false, false );
		update_option( self::OPTION, $settings );

		wp_safe_redirect(
			add_query_arg(
				array(
					'post_type' => CMPOD_Records::POST_TYPE,
					'page'      => 'cmpod-settings',
					'rotated'   => '1',
				),
				admin_url( 'edit.php' )
			)
		);
		exit;
	}

	public static function render_page() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}
		$settings = self::all();
		$secret   = self::ensure_secret();
		?>
		<div class="wrap">
			<h1><?php esc_html_e( 'CINDERMARK Proof of Delivery', 'cindermark-pod' ); ?></h1>

			<?php if ( isset( $_GET['rotated'] ) ) : ?>
				<div class="notice notice-warning"><p>
					<?php esc_html_e( 'A new pairing secret was generated. Enter it on every iPad; devices still holding the old secret will be refused.', 'cindermark-pod' ); ?>
				</p></div>
			<?php endif; ?>

			<h2><?php esc_html_e( 'Pair an iPad', 'cindermark-pod' ); ?></h2>
			<p><?php esc_html_e( 'In the CINDERMARK POD app, open Settings and enter this site address and pairing secret.', 'cindermark-pod' ); ?></p>
			<table class="form-table" role="presentation">
				<tr>
					<th scope="row"><?php esc_html_e( 'Site address', 'cindermark-pod' ); ?></th>
					<td><code><?php echo esc_html( home_url( '/' ) ); ?></code></td>
				</tr>
				<tr>
					<th scope="row"><?php esc_html_e( 'Pairing secret', 'cindermark-pod' ); ?></th>
					<td>
						<code style="user-select:all"><?php echo esc_html( $secret ); ?></code>
						<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>" style="display:inline-block;margin-left:12px">
							<input type="hidden" name="action" value="cmpod_regenerate_secret" />
							<?php wp_nonce_field( 'cmpod_regenerate_secret' ); ?>
							<button type="submit" class="button"><?php esc_html_e( 'Generate a new secret', 'cindermark-pod' ); ?></button>
						</form>
					</td>
				</tr>
			</table>

			<form method="post" action="options.php">
				<?php settings_fields( 'cmpod_settings_group' ); ?>
				<h2><?php esc_html_e( 'Customer email', 'cindermark-pod' ); ?></h2>
				<table class="form-table" role="presentation">
					<tr>
						<th scope="row"><label for="cmpod_from_name"><?php esc_html_e( 'From name', 'cindermark-pod' ); ?></label></th>
						<td><input id="cmpod_from_name" class="regular-text" type="text" name="<?php echo esc_attr( self::OPTION ); ?>[from_name]" value="<?php echo esc_attr( $settings['from_name'] ); ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><label for="cmpod_from_email"><?php esc_html_e( 'From address', 'cindermark-pod' ); ?></label></th>
						<td>
							<input id="cmpod_from_email" class="regular-text" type="email" name="<?php echo esc_attr( self::OPTION ); ?>[from_email]" value="<?php echo esc_attr( $settings['from_email'] ); ?>" />
							<p class="description"><?php esc_html_e( 'Use an address on this domain. Mail is sent with wp_mail(), so whatever SMTP plugin the site uses for business email is what delivers it.', 'cindermark-pod' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="cmpod_reply_to"><?php esc_html_e( 'Reply-to', 'cindermark-pod' ); ?></label></th>
						<td><input id="cmpod_reply_to" class="regular-text" type="email" name="<?php echo esc_attr( self::OPTION ); ?>[reply_to]" value="<?php echo esc_attr( $settings['reply_to'] ); ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><label for="cmpod_bcc"><?php esc_html_e( 'Always copy', 'cindermark-pod' ); ?></label></th>
						<td>
							<input id="cmpod_bcc" class="regular-text" type="email" name="<?php echo esc_attr( self::OPTION ); ?>[bcc_email]" value="<?php echo esc_attr( $settings['bcc_email'] ); ?>" />
							<p class="description"><?php esc_html_e( 'Dispatch address that receives a copy of every receipt. The iPad can also set this per run.', 'cindermark-pod' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="cmpod_subject"><?php esc_html_e( 'Subject line', 'cindermark-pod' ); ?></label></th>
						<td>
							<input id="cmpod_subject" class="large-text" type="text" name="<?php echo esc_attr( self::OPTION ); ?>[email_subject]" value="<?php echo esc_attr( $settings['email_subject'] ); ?>" />
							<p class="description"><?php esc_html_e( 'Placeholders: {company}, {order}, {customer}, {date}', 'cindermark-pod' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e( 'Attachment', 'cindermark-pod' ); ?></th>
						<td>
							<label>
								<input type="checkbox" name="<?php echo esc_attr( self::OPTION ); ?>[attach_pdf]" value="1" <?php checked( 1, (int) $settings['attach_pdf'] ); ?> />
								<?php esc_html_e( 'Attach the signed PDF to the customer email', 'cindermark-pod' ); ?>
							</label>
							<p class="description"><?php esc_html_e( 'The receipt lists medical supplies. Turn this off if you would rather the email only confirm the delivery and keep the document on the site.', 'cindermark-pod' ); ?></p>
						</td>
					</tr>
				</table>

				<h2><?php esc_html_e( 'Devices', 'cindermark-pod' ); ?></h2>
				<table class="form-table" role="presentation">
					<tr>
						<th scope="row"><label for="cmpod_devices"><?php esc_html_e( 'Allowed device ids', 'cindermark-pod' ); ?></label></th>
						<td>
							<textarea id="cmpod_devices" class="large-text code" rows="4" name="<?php echo esc_attr( self::OPTION ); ?>[allowed_devices]"><?php echo esc_textarea( $settings['allowed_devices'] ); ?></textarea>
							<p class="description"><?php esc_html_e( 'One per line, as shown in the app under Settings > This iPad. Leave empty to accept any device that has the pairing secret.', 'cindermark-pod' ); ?></p>
						</td>
					</tr>
				</table>

				<?php submit_button(); ?>
			</form>

			<h2><?php esc_html_e( 'Where documents are stored', 'cindermark-pod' ); ?></h2>
			<p><code><?php echo esc_html( CMPOD_Storage::base_dir() ); ?></code></p>
			<p class="description"><?php echo esc_html( CMPOD_Storage::protection_notice() ); ?></p>
		</div>
		<?php
	}
}
