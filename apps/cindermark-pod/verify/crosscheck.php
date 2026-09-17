<?php
/**
 * Feeds the exact bytes the Swift app produced into the checks the plugin runs,
 * and confirms every field the plugin reads actually exists in that output.
 */
$dir       = getenv('POD_OUT_DIR') ?: '/tmp';
$canonical = file_get_contents("$dir/pod-canonical.json");
$claimed   = trim(file_get_contents("$dir/pod-hash.txt"));
list($nonce, $signature, $canonicalString) = explode("\n", file_get_contents("$dir/pod-signing.txt"), 3);

$checks = 0; $fails = 0;
function check($label, $ok, $detail = '') {
    global $checks, $fails; $checks++;
    if ($ok) { echo "  ok   $label\n"; return; }
    $fails++; echo "  FAIL $label" . ($detail ? "  -> $detail" : '') . "\n";
}

echo "Hash agreement (CMPOD_Rest::handle_pod)\n";
$actual = hash('sha256', $canonical);
check('PHP hashes Swift bytes to the same digest', hash_equals($actual, $claimed), "php=$actual swift=$claimed");

echo "\nSignature agreement (CMPOD_Auth::verify)\n";
$expected = hash_hmac('sha256', $canonicalString, 'test-secret-value');
check('PHP recomputes the Swift HMAC', hash_equals($expected, trim($signature)), "php=$expected swift=" . trim($signature));

echo "\nRecord decodes and carries every field the plugin reads\n";
$record = json_decode($canonical, true);
check('canonical JSON parses in PHP', is_array($record));

// Exactly the paths CMPOD_Records::create() and the mailer/template dereference.
$paths = [
    'id', 'schema_version', 'order_number', 'purchase_order', 'signed_at', 'time_zone_identifier',
    'utc_offset_seconds', 'delivery_notes', 'service_level', 'cold_chain_required', 'payload_hash',
    'customer.company_name', 'customer.contact_name', 'customer.email', 'customer.address.line1',
    'customer.address.postal_code',
    'signer.printed_name', 'signer.relationship',
    'location.source', 'location.latitude', 'location.longitude', 'location.horizontal_accuracy_meters',
    'location.resolved_address',
    'courier.driver_name', 'courier.device_id', 'courier.app_version',
    'signature.stroke_count', 'signature.input_policy', 'signature.image_sha256',
    'line_items.0.quantity_received', 'line_items.0.disposition', 'line_items.0.note',
    'line_items.0.item.sku', 'line_items.0.item.item_description', 'line_items.0.item.lot_number',
    'line_items.0.item.quantity_shipped', 'line_items.0.item.unit_of_measure',
];
$missing = [];
foreach ($paths as $path) {
    $node = $record; $ok = true;
    foreach (explode('.', $path) as $part) {
        if (is_array($node) && array_key_exists($part, $node)) { $node = $node[$part]; }
        else { $ok = false; break; }
    }
    if (!$ok) { $missing[] = $path; }
}
check(count($paths) . ' field paths present', empty($missing), implode(', ', $missing));

echo "\nValues survive the trip intact\n";
check('order number', $record['order_number'] === 'SO-10482', var_export($record['order_number'] ?? null, true));
check('latitude keeps 6dp', abs($record['location']['latitude'] - 38.581572) < 1e-9, var_export($record['location']['latitude'] ?? null, true));
check('signed_at parses as a date', (bool) strtotime($record['signed_at']), $record['signed_at'] ?? '');
check('signed_at is UTC Zulu', substr($record['signed_at'], -1) === 'Z', $record['signed_at'] ?? '');
check('disposition enum is a bare string', $record['line_items'][0]['disposition'] === 'shortShipped', var_export($record['line_items'][0]['disposition'] ?? null, true));
check('exception note preserved', $record['line_items'][0]['note'] === 'One box damaged in transit');
check('booleans are real booleans', $record['cold_chain_required'] === false && $record['location']['is_precise_authorization'] === true);
check('payload_hash is blank in the hashed bytes', $record['payload_hash'] === '');

echo "\n$checks checks, $fails failed\n";
exit($fails > 0 ? 1 : 0);
