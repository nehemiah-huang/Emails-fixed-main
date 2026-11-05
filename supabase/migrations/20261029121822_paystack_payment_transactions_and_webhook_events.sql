/*
# Paystack payment records and webhook event log for Gather memberships

1. New Tables
- `payment_transactions`: one row per membership payment attempt. Stores the unique payment reference, the linked membership application, the plan, the expected amount in pesewas and the currency, and the payment status.
- `paystack_events`: one row per distinct webhook delivery (keyed by a hash of the raw request body). Used for duplicate detection and audit.

2. New Function
- `record_paystack_event`: the only way a payment becomes successful. Runs in one transaction: locks the matching payment row, checks it has not already been recorded, checks the verified amount and currency, updates the payment, and logs the event.

3. Security
- `payment_transactions`: members can read their own payments; admins can read all. No client writes.
- `paystack_events`: row level security on with no client grants. Only the function above touches it.
- `record_paystack_event`: callable only by the server (service role). Not callable by browsers.

4. Notes
- Payment success never approves a membership. Approval stays with the admin review functions.
- Repeated or simultaneous deliveries for the same reference are safe: the row lock and status check allow only one success.
*/

CREATE TABLE IF NOT EXISTS payment_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text NOT NULL UNIQUE,
  membership_application_id uuid NOT NULL REFERENCES membership_applications(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan text NOT NULL CHECK (plan IN ('monthly', 'annual')),
  amount_pesewas integer NOT NULL CHECK (amount_pesewas > 0),
  currency text NOT NULL DEFAULT 'GHS' CHECK (currency = 'GHS'),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'success', 'failed', 'abandoned')),
  paystack_transaction_id bigint UNIQUE,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payment_transactions_application_id_idx ON payment_transactions (membership_application_id);
CREATE INDEX IF NOT EXISTS payment_transactions_user_id_idx ON payment_transactions (user_id);

ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON payment_transactions TO authenticated;

DROP POLICY IF EXISTS "select_own_payment_transactions" ON payment_transactions;
CREATE POLICY "select_own_payment_transactions" ON payment_transactions FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "admins_select_payment_transactions" ON payment_transactions;
CREATE POLICY "admins_select_payment_transactions" ON payment_transactions FOR SELECT
  TO authenticated USING (is_edan_admin());

CREATE TABLE IF NOT EXISTS paystack_events (
  event_key text PRIMARY KEY,
  event_type text NOT NULL,
  reference text,
  outcome text NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE paystack_events ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION record_paystack_event(
  p_event_key text,
  p_event_type text,
  p_reference text,
  p_verified_transaction_id bigint,
  p_verified_amount_pesewas integer,
  p_verified_currency text,
  p_verified_paid_at timestamptz
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pay payment_transactions%ROWTYPE;
  result text;
BEGIN
  IF p_event_type <> 'charge.success' OR p_reference IS NULL THEN
    result := 'ignored';
  ELSE
    SELECT * INTO pay FROM payment_transactions WHERE reference = p_reference FOR UPDATE;

    IF NOT FOUND THEN
      result := 'unmatched';
    ELSIF pay.status = 'success' THEN
      result := 'already_recorded';
    ELSIF p_verified_amount_pesewas IS DISTINCT FROM pay.amount_pesewas
      OR p_verified_currency IS DISTINCT FROM pay.currency THEN
      result := 'amount_mismatch';
    ELSE
      UPDATE payment_transactions
      SET status = 'success',
          paystack_transaction_id = p_verified_transaction_id,
          paid_at = p_verified_paid_at,
          updated_at = now()
      WHERE id = pay.id;
      result := 'recorded';
    END IF;
  END IF;

  INSERT INTO paystack_events (event_key, event_type, reference, outcome)
  VALUES (p_event_key, p_event_type, p_reference, result)
  ON CONFLICT (event_key) DO NOTHING;

  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION record_paystack_event(text, text, text, bigint, integer, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION record_paystack_event(text, text, text, bigint, integer, text, timestamptz) TO service_role;
