/*
# Clearer outcome for Paystack events that did not succeed

1. Modified Function
- `record_paystack_event`: when Paystack's verification reports that the charge did not succeed, the event is logged with the outcome `not_successful` instead of being reported as an amount mismatch. Payment status is left unchanged.

2. Security
- Unchanged: the function stays server-only (service role).
*/

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
    ELSIF p_verified_transaction_id IS NULL THEN
      result := 'not_successful';
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
