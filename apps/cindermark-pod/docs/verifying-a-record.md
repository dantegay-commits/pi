# Verifying a signed record

Every proof of delivery carries a SHA-256 of the delivery record, printed on the
last page of the PDF and stored beside it. It answers one question: has this
record been altered since it was signed?

## What the hash covers

The record as JSON, encoded with:

- keys sorted alphabetically at every level
- forward slashes left unescaped
- dates as ISO-8601 in UTC, to the second (`2026-09-17T21:12:03Z`)
- the `payload_hash` field itself set to an empty string

That last point is the only subtle one. The hash cannot cover itself, so the
field is blanked before hashing and filled in afterwards.

## Checking a record by hand

The archived JSON sidecar wraps the record:

```json
{
  "record": { "...": "..." },
  "pdf_relative_path": "Shipped/2026/09/POD-SO-10482-20260917-141203.pdf",
  "pdf_sha256": "...",
  "upload_state": "uploaded"
}
```

```python
import json, hashlib

with open("POD-SO-10482-20260917-141203.json") as f:
    record = json.load(f)["record"]

claimed = record["payload_hash"]
record["payload_hash"] = ""

canonical = json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
actual = hashlib.sha256(canonical.encode("utf-8")).hexdigest()

print("matches" if actual == claimed else "ALTERED")
```

The PDF is hashed as a whole file, with no preparation:

```sh
shasum -a 256 POD-SO-10482-20260917-141203.pdf
```

Compare that against `pdf_sha256` in the sidecar, or against the copy the
WordPress site stored.

## Checking the server's copy

In WordPress, open the delivery under **Deliveries**. The detail panel shows the
record id, the record SHA-256 and the document SHA-256. They should match the
iPad's copy exactly. The site verified both hashes before it wrote anything to
disk, so a mismatch means something changed after filing, not in transit.

## What the hash does not tell you

It tells you a record has not been altered. It does not tell you the signature is
genuine, that the person who signed was who they said they were, or that the
coordinates were not spoofed by a jailbroken device. It is a tamper-evidence
measure on an internal record, not a legal signature scheme.

If you need signatures that stand up to a determined challenge, that is a
different system: hardware-backed keys, a timestamping authority, and a chain of
custody that does not run through a courier's iPad.
