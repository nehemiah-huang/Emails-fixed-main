/*
# Online Stay booking columns and payment event log

1. Changes to `stay_bookings`
- `user_id`: the signed-in guest who made an online booking. Manual bookings leave it empty.
- `paystack_reference`: unique payment reference sent to Paystack for each online booking.
- `paystack_authorization_url`: the Paystack checkout link, kept so a retried request returns the same checkout instead of creating a duplicate charge.
- `hold_expires_at`: when a temporary hold on the dates ends if payment is not completed.
- `paid_amount_pesewas`, `paystack_transaction_id`, `paid_at`: payment details recorded only after Paystack verification.
- `payment_note`: plain-text note for the team (for example, a payment that needs a refund).

2. New table `stay_payment_events`
- One row per Paystack webhook event, keyed by a hash of the event body. Duplicate deliveries are detected by this key.

3. Security
- Guests can read only their own online bookings (`user_id` must match their account).
- `stay_payment_events` has no public access; only the server (service role) can write to it.
- No existing rows or columns are removed or changed.
*/

ALTER TABLE stay_bookings
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS paystack_reference text UNIQUE,
  ADD COLUMN IF NOT EXISTS paystack_authorization_url text,
  ADD COLUMN IF NOT EXISTS hold_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS paid_amount_pesewas integer,
  ADD COLUMN IF NOT EXISTS paystack_transaction_id bigint,
  ADD COLUMN IF NOT EXISTS paid_at timestamptz,
  ADD COLUMN IF NOT EXISTS payment_note text NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS stay_bookings_user_idx ON stay_bookings (user_id);

DROP POLICY IF EXISTS "guests_select_own_stay_bookings" ON stay_bookings;
CREATE POLICY "guests_select_own_stay_bookings" ON stay_bookings FOR SELECT
  TO authenticated USING (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS stay_payment_events (
  event_key text PRIMARY KEY,
  event_type text NOT NULL,
  reference text,
  received_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE stay_payment_events ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON stay_payment_events TO service_role;
GRANT SELECT, UPDATE ON stay_bookings TO service_role;
