<?php
/**
 * Customer receipt email.
 *
 * Override by filtering `cmpod_receipt_template` with a path to your own copy.
 *
 * @var array $data record, company, order, customer, signer, signed, lines, location
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

$cmpod_date = date_i18n( get_option( 'date_format' ) . ' \a\t ' . get_option( 'time_format' ), $data['signed'] );
?>
<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:#16181d;max-width:640px">
	<p style="font-size:15px;line-height:1.5">
		<?php
		printf(
			/* translators: %s: customer name */
			esc_html__( 'Hello %s,', 'cindermark-pod' ),
			esc_html( $data['customer'] )
		);
		?>
	</p>

	<p style="font-size:15px;line-height:1.5">
		<?php
		printf(
			/* translators: 1: company name, 2: date and time */
			esc_html__( 'Your shipment from %1$s was delivered and signed for on %2$s. Your signed receipt is below, and a copy is attached for your records.', 'cindermark-pod' ),
			esc_html( $data['company'] ),
			esc_html( $cmpod_date )
		);
		?>
	</p>

	<table style="width:100%;border-collapse:collapse;font-size:14px;margin:18px 0">
		<tr>
			<td style="padding:6px 0;color:#5a6068;width:150px"><?php esc_html_e( 'Order', 'cindermark-pod' ); ?></td>
			<td style="padding:6px 0;font-weight:600"><?php echo esc_html( '' !== $data['order'] ? $data['order'] : '-' ); ?></td>
		</tr>
		<tr>
			<td style="padding:6px 0;color:#5a6068"><?php esc_html_e( 'Signed by', 'cindermark-pod' ); ?></td>
			<td style="padding:6px 0;font-weight:600"><?php echo esc_html( $data['signer'] ); ?></td>
		</tr>
		<?php if ( ! empty( $data['location']['resolved_address'] ) ) : ?>
		<tr>
			<td style="padding:6px 0;color:#5a6068"><?php esc_html_e( 'Delivered to', 'cindermark-pod' ); ?></td>
			<td style="padding:6px 0"><?php echo esc_html( $data['location']['resolved_address'] ); ?></td>
		</tr>
		<?php endif; ?>
	</table>

	<h3 style="font-size:12px;letter-spacing:1.2px;text-transform:uppercase;color:#d9531e;margin:24px 0 8px">
		<?php esc_html_e( 'What was delivered', 'cindermark-pod' ); ?>
	</h3>

	<table style="width:100%;border-collapse:collapse;font-size:14px">
		<thead>
			<tr style="background:#eeece8">
				<th align="left" style="padding:8px"><?php esc_html_e( 'Item', 'cindermark-pod' ); ?></th>
				<th align="right" style="padding:8px"><?php esc_html_e( 'Received', 'cindermark-pod' ); ?></th>
				<th align="left" style="padding:8px"><?php esc_html_e( 'Status', 'cindermark-pod' ); ?></th>
			</tr>
		</thead>
		<tbody>
		<?php foreach ( $data['lines'] as $cmpod_line ) : ?>
			<?php
			$cmpod_item        = isset( $cmpod_line['item'] ) && is_array( $cmpod_line['item'] ) ? $cmpod_line['item'] : array();
			$cmpod_description = ! empty( $cmpod_item['item_description'] ) ? $cmpod_item['item_description'] : ( isset( $cmpod_item['sku'] ) ? $cmpod_item['sku'] : '' );
			$cmpod_clean       = isset( $cmpod_line['disposition'] ) && 'received' === $cmpod_line['disposition'];
			?>
			<tr style="border-bottom:1px solid #e3e0da">
				<td style="padding:8px">
					<?php echo esc_html( $cmpod_description ); ?>
					<?php if ( ! empty( $cmpod_item['lot_number'] ) ) : ?>
						<br /><span style="color:#5a6068;font-size:12px"><?php echo esc_html( sprintf( 'Lot %s', $cmpod_item['lot_number'] ) ); ?></span>
					<?php endif; ?>
				</td>
				<td align="right" style="padding:8px">
					<?php echo esc_html( isset( $cmpod_line['quantity_received'] ) ? $cmpod_line['quantity_received'] : '' ); ?>
					<?php echo esc_html( isset( $cmpod_item['unit_of_measure'] ) ? $cmpod_item['unit_of_measure'] : '' ); ?>
				</td>
				<td style="padding:8px;<?php echo $cmpod_clean ? '' : 'color:#d9531e;font-weight:600'; ?>">
					<?php echo esc_html( isset( $cmpod_line['disposition'] ) ? $cmpod_line['disposition'] : '' ); ?>
					<?php if ( ! empty( $cmpod_line['note'] ) ) : ?>
						<br /><span style="font-weight:400;font-size:12px"><?php echo esc_html( $cmpod_line['note'] ); ?></span>
					<?php endif; ?>
				</td>
			</tr>
		<?php endforeach; ?>
		</tbody>
	</table>

	<p style="font-size:12px;color:#5a6068;line-height:1.5;margin-top:24px">
		<?php
		printf(
			/* translators: %s: company name */
			esc_html__( 'This receipt was generated at the time of delivery by %s. If anything here does not match what you received, reply to this email.', 'cindermark-pod' ),
			esc_html( $data['company'] )
		);
		?>
	</p>
</div>
