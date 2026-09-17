<?php
/**
 * Sends the customer their signed copy.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class CMPOD_Mailer {

	/**
	 * Emails one delivery receipt.
	 *
	 * Sending goes through wp_mail(), so whatever the site already uses for
	 * business email - an SMTP plugin pointed at the CINDERMARK mailbox, a
	 * transactional provider, or the host's mailer - is what actually delivers
	 * it, and the message comes from the company address rather than the iPad.
	 *
	 * @param int    $post_id       Delivery post.
	 * @param array  $record        Decoded record.
	 * @param string $pdf_path      Absolute path to the signed PDF.
	 * @param string $to            Recipient address.
	 * @param string $extra_bcc     Optional per-run copy address from the app.
	 * @return array{sent:bool,to:string,error:string}
	 */
	public static function send_receipt( $post_id, $record, $pdf_path, $to, $extra_bcc = '' ) {
		$to = sanitize_email( $to );
		if ( '' === $to || ! is_email( $to ) ) {
			update_post_meta( $post_id, '_cmpod_email_status', 'failed' );
			return array(
				'sent'  => false,
				'to'    => '',
				'error' => __( 'No valid customer email address was supplied.', 'cindermark-pod' ),
			);
		}

		$settings = CMPOD_Settings::all();
		$company  = '' !== trim( (string) $settings['from_name'] ) ? $settings['from_name'] : get_bloginfo( 'name' );
		$order    = isset( $record['order_number'] ) ? (string) $record['order_number'] : '';
		$customer = CMPOD_Records::customer_name( $record );
		$signed   = CMPOD_Records::signed_timestamp( $record );

		$subject = strtr(
			(string) $settings['email_subject'],
			array(
				'{company}'  => $company,
				'{order}'    => $order,
				'{customer}' => $customer,
				'{date}'     => date_i18n( get_option( 'date_format' ), $signed ),
			)
		);

		$headers = array( 'Content-Type: text/html; charset=UTF-8' );
		if ( is_email( $settings['from_email'] ) ) {
			$headers[] = sprintf( 'From: %s <%s>', $company, $settings['from_email'] );
		}
		if ( is_email( $settings['reply_to'] ) ) {
			$headers[] = 'Reply-To: ' . $settings['reply_to'];
		}
		foreach ( array( $settings['bcc_email'], $extra_bcc ) as $bcc ) {
			$bcc = sanitize_email( (string) $bcc );
			if ( '' !== $bcc && is_email( $bcc ) ) {
				$headers[] = 'Bcc: ' . $bcc;
			}
		}

		$attachments = array();
		if ( ! empty( $settings['attach_pdf'] ) && $pdf_path && is_readable( $pdf_path ) ) {
			$attachments[] = $pdf_path;
		}

		$body = self::render_body( $record, $company );

		/**
		 * Filters the receipt before it is sent.
		 *
		 * @param array $message subject, body, headers, attachments.
		 * @param array $record
		 */
		$message = apply_filters(
			'cmpod_receipt_email',
			array(
				'subject'     => $subject,
				'body'        => $body,
				'headers'     => $headers,
				'attachments' => $attachments,
			),
			$record
		);

		$sent = wp_mail( $to, $message['subject'], $message['body'], $message['headers'], $message['attachments'] );

		update_post_meta( $post_id, '_cmpod_email_status', $sent ? 'sent' : 'failed' );
		update_post_meta( $post_id, '_cmpod_email_to', $to );

		return array(
			'sent'  => (bool) $sent,
			'to'    => $to,
			'error' => $sent ? '' : __( 'wp_mail() refused the message. Check the site\'s mail configuration.', 'cindermark-pod' ),
		);
	}

	/**
	 * @param array  $record
	 * @param string $company
	 * @return string
	 */
	private static function render_body( $record, $company ) {
		$template = apply_filters( 'cmpod_receipt_template', CMPOD_PLUGIN_DIR . 'templates/email-customer.php', $record );
		if ( ! is_readable( $template ) ) {
			return esc_html__( 'Your delivery receipt is attached.', 'cindermark-pod' );
		}

		$data = array(
			'record'   => $record,
			'company'  => $company,
			'order'    => isset( $record['order_number'] ) ? (string) $record['order_number'] : '',
			'customer' => CMPOD_Records::customer_name( $record ),
			'signer'   => isset( $record['signer']['printed_name'] ) ? (string) $record['signer']['printed_name'] : '',
			'signed'   => CMPOD_Records::signed_timestamp( $record ),
			'lines'    => isset( $record['line_items'] ) && is_array( $record['line_items'] ) ? $record['line_items'] : array(),
			'location' => isset( $record['location'] ) && is_array( $record['location'] ) ? $record['location'] : array(),
		);

		ob_start();
		// $data is consumed by the template.
		include $template;
		return (string) ob_get_clean();
	}
}
