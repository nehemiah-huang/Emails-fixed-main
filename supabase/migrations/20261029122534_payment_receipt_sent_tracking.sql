/*
# Track when a payment receipt email was sent

1. Modified Table
- `payment_transactions`: adds `receipt_sent_at`, set once the receipt email for a verified payment has been sent. Empty means no receipt has gone out yet.

2. Security
- The server (service role) may read payment rows and set only `receipt_sent_at`. Nothing else in the row is writable by it through this grant.
- Browsers still have no write access to payments.

3. Notes
- Lets a retried webhook delivery send the receipt if an earlier attempt failed, without ever sending it twice.
*/

ALTER TABLE payment_transactions
  ADD COLUMN IF NOT EXISTS receipt_sent_at timestamptz;

GRANT SELECT ON payment_transactions TO service_role;
GRANT UPDATE (receipt_sent_at) ON payment_transactions TO service_role;
