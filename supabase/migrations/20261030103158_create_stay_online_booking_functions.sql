/*
# Online Stay booking functions

1. New Functions
- `stay_room_availability(check_in, check_out)`: lists each active room with whether it is free for those dates. Callable by anyone; returns no guest details.
- `create_stay_hold(...)`: a signed-in guest reserves one room for 15 minutes while they pay. Creates a pending booking with a Paystack reference. Overlaps are checked under a per-room lock, so two guests cannot hold the same room at once.
- `prepare_stay_payment(booking_id)`: server-only. Rechecks the dates just before Paystack checkout is created.
- `confirm_stay_payment(...)`: server-only. Confirms a booking only after Paystack verification matches the reference, amount (in pesewas) and currency. Repeat calls change nothing. If the dates were taken after the hold expired, the booking is cancelled and flagged for refund instead of being double-booked.
- `mark_stay_payment_failed(reference)`: server-only. Releases a hold when Paystack reports a failed charge.

2. Rules
- Hold length: 15 minutes (`hold_expires_at`).
- Nightly rates: GH₵650 room only, GH₵700 with breakfast; total is nights multiplied by rate.
- Expired holds are marked payment_failed when a new hold is requested, so their dates are released.
- Abandoned or failed payments never produce a confirmed booking.

3. Security
- Guest-facing functions run as the signed-in user or anonymous visitor; they check identity and never expose other guests' details.
- Server-only functions are granted to the service role alone.
- Nothing existing is changed except the new function definitions.
*/

CREATE OR REPLACE FUNCTION stay_room_availability(p_check_in date, p_check_out date)
RETURNS TABLE (available_room_id uuid, available_room_name text, is_available boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_check_in IS NULL OR p_check_out IS NULL OR p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'Check-out must be at least one night after check-in.';
  END IF;

  IF p_check_in < CURRENT_DATE THEN
    RAISE EXCEPTION 'Check-in cannot be in the past.';
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.name,
    NOT EXISTS (
      SELECT 1 FROM stay_bookings b
      WHERE b.room_id = r.id
        AND (
          b.status IN ('confirmed', 'completed')
          OR (b.status = 'pending_payment' AND b.hold_expires_at > now())
        )
        AND daterange(b.check_in, b.check_out, '[)') && daterange(p_check_in, p_check_out, '[)')
    ) AND NOT EXISTS (
      SELECT 1 FROM stay_room_blocks k
      WHERE k.room_id = r.id
        AND daterange(k.starts_on, k.ends_on, '[)') && daterange(p_check_in, p_check_out, '[)')
    )
  FROM stay_rooms r
  WHERE r.is_active
  ORDER BY r.name;
END;
$$;

CREATE OR REPLACE FUNCTION create_stay_hold(
  p_room_id uuid,
  p_check_in date,
  p_check_out date,
  p_guests integer,
  p_breakfast_included boolean,
  p_guest_name text,
  p_guest_email text,
  p_guest_phone text
)
RETURNS stay_bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate integer;
  v_booking stay_bookings;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Please log in to book a room.' USING ERRCODE = '42501';
  END IF;

  IF p_check_in IS NULL OR p_check_out IS NULL OR p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'Check-out must be at least one night after check-in.';
  END IF;

  IF p_check_in < CURRENT_DATE THEN
    RAISE EXCEPTION 'Check-in cannot be in the past.';
  END IF;

  IF p_guests IS NULL OR p_guests NOT BETWEEN 1 AND 2 THEN
    RAISE EXCEPTION 'Each room holds one or two guests.';
  END IF;

  IF length(btrim(coalesce(p_guest_name, ''))) = 0
     OR length(btrim(coalesce(p_guest_email, ''))) = 0
     OR length(btrim(coalesce(p_guest_phone, ''))) = 0 THEN
    RAISE EXCEPTION 'Please enter your name, email and phone number.';
  END IF;

  PERFORM 1 FROM stay_rooms WHERE id = p_room_id AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'That room is not available for booking.';
  END IF;

  UPDATE stay_bookings
  SET status = 'payment_failed',
      updated_at = now(),
      payment_note = 'The payment window closed before payment was completed.'
  WHERE status = 'pending_payment' AND hold_expires_at <= now();

  v_rate := CASE WHEN coalesce(p_breakfast_included, false) THEN 700 ELSE 650 END;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_room_id::text, 0));

  IF EXISTS (
    SELECT 1 FROM stay_bookings b
    WHERE b.room_id = p_room_id
      AND (
        b.status IN ('confirmed', 'completed')
        OR (b.status = 'pending_payment' AND b.hold_expires_at > now())
      )
      AND daterange(b.check_in, b.check_out, '[)') && daterange(p_check_in, p_check_out, '[)')
  ) OR EXISTS (
    SELECT 1 FROM stay_room_blocks k
    WHERE k.room_id = p_room_id
      AND daterange(k.starts_on, k.ends_on, '[)') && daterange(p_check_in, p_check_out, '[)')
  ) THEN
    RAISE EXCEPTION 'Sorry, that room has just been taken for these dates. Please choose another room or dates.';
  END IF;

  INSERT INTO stay_bookings (
    room_id, user_id, check_in, check_out, guests, breakfast_included,
    nightly_rate_ghs, total_ghs, status, source, hold_expires_at, paystack_reference,
    guest_name, guest_email, guest_phone
  ) VALUES (
    p_room_id, auth.uid(), p_check_in, p_check_out, p_guests, coalesce(p_breakfast_included, false),
    v_rate, (p_check_out - p_check_in) * v_rate, 'pending_payment', 'online',
    now() + interval '15 minutes',
    'EDNSTAY-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)),
    btrim(p_guest_name), btrim(p_guest_email), btrim(p_guest_phone)
  )
  RETURNING * INTO v_booking;

  RETURN v_booking;
END;
$$;

CREATE OR REPLACE FUNCTION prepare_stay_payment(p_booking_id uuid)
RETURNS stay_bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking stay_bookings;
BEGIN
  SELECT * INTO v_booking FROM stay_bookings WHERE id = p_booking_id FOR UPDATE;

  IF NOT FOUND OR v_booking.status <> 'pending_payment' THEN
    RAISE EXCEPTION 'This booking is no longer waiting for payment. Please start again.';
  END IF;

  IF v_booking.hold_expires_at <= now() THEN
    RAISE EXCEPTION 'Your 15-minute hold has expired. Please start the booking again.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_booking.room_id::text, 0));

  IF EXISTS (
    SELECT 1 FROM stay_bookings b
    WHERE b.room_id = v_booking.room_id
      AND b.id <> v_booking.id
      AND (
        b.status IN ('confirmed', 'completed')
        OR (b.status = 'pending_payment' AND b.hold_expires_at > now())
      )
      AND daterange(b.check_in, b.check_out, '[)') && daterange(v_booking.check_in, v_booking.check_out, '[)')
  ) OR EXISTS (
    SELECT 1 FROM stay_room_blocks k
    WHERE k.room_id = v_booking.room_id
      AND daterange(k.starts_on, k.ends_on, '[)') && daterange(v_booking.check_in, v_booking.check_out, '[)')
  ) THEN
    RAISE EXCEPTION 'Sorry, these dates are no longer available for this room. Please start again.';
  END IF;

  RETURN v_booking;
END;
$$;

CREATE OR REPLACE FUNCTION confirm_stay_payment(
  p_reference text,
  p_transaction_id bigint,
  p_amount_pesewas integer,
  p_currency text,
  p_paid_at timestamptz
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking stay_bookings;
  v_conflict boolean;
BEGIN
  SELECT * INTO v_booking FROM stay_bookings WHERE paystack_reference = p_reference FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 'unknown_reference';
  END IF;

  IF v_booking.status = 'confirmed' THEN
    RETURN 'already_confirmed';
  END IF;

  IF v_booking.status NOT IN ('pending_payment', 'payment_failed') THEN
    RETURN 'not_confirmable';
  END IF;

  IF p_currency IS DISTINCT FROM 'GHS' OR p_amount_pesewas IS DISTINCT FROM v_booking.total_ghs * 100 THEN
    UPDATE stay_bookings
    SET status = 'cancelled',
        cancelled_at = now(),
        updated_at = now(),
        paystack_transaction_id = p_transaction_id,
        paid_amount_pesewas = p_amount_pesewas,
        paid_at = p_paid_at,
        payment_note = 'Payment amount or currency did not match this booking. Refund required.'
    WHERE id = v_booking.id;
    RETURN 'amount_mismatch';
  END IF;

  v_conflict := EXISTS (
    SELECT 1 FROM stay_bookings b
    WHERE b.room_id = v_booking.room_id
      AND b.id <> v_booking.id
      AND b.status IN ('confirmed', 'completed')
      AND daterange(b.check_in, b.check_out, '[)') && daterange(v_booking.check_in, v_booking.check_out, '[)')
  ) OR EXISTS (
    SELECT 1 FROM stay_room_blocks k
    WHERE k.room_id = v_booking.room_id
      AND daterange(k.starts_on, k.ends_on, '[)') && daterange(v_booking.check_in, v_booking.check_out, '[)')
  );

  IF v_conflict THEN
    UPDATE stay_bookings
    SET status = 'cancelled',
        cancelled_at = now(),
        updated_at = now(),
        paystack_transaction_id = p_transaction_id,
        paid_amount_pesewas = p_amount_pesewas,
        paid_at = p_paid_at,
        payment_note = 'Payment was received after the hold expired and these dates were taken. Refund required.'
    WHERE id = v_booking.id;
    RETURN 'conflict_refund_required';
  END IF;

  UPDATE stay_bookings
  SET status = 'confirmed',
      hold_expires_at = NULL,
      updated_at = now(),
      paystack_transaction_id = p_transaction_id,
      paid_amount_pesewas = p_amount_pesewas,
      paid_at = p_paid_at,
      payment_note = ''
  WHERE id = v_booking.id;

  RETURN 'confirmed';
END;
$$;

CREATE OR REPLACE FUNCTION mark_stay_payment_failed(p_reference text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE stay_bookings
  SET status = 'payment_failed',
      updated_at = now(),
      payment_note = 'The payment was not completed.'
  WHERE paystack_reference = p_reference AND status = 'pending_payment';
$$;

REVOKE EXECUTE ON FUNCTION stay_room_availability(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION stay_room_availability(date, date) TO anon, authenticated;

REVOKE EXECUTE ON FUNCTION create_stay_hold(uuid, date, date, integer, boolean, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_stay_hold(uuid, date, date, integer, boolean, text, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION prepare_stay_payment(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION prepare_stay_payment(uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION confirm_stay_payment(text, bigint, integer, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION confirm_stay_payment(text, bigint, integer, text, timestamptz) TO service_role;

REVOKE EXECUTE ON FUNCTION mark_stay_payment_failed(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mark_stay_payment_failed(text) TO service_role;
