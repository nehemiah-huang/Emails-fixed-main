/*
# Admin functions for Stay bookings and room blocks

1. New Functions (team admins only)
- `admin_create_manual_booking`: records a booking received by phone or WhatsApp. Stored as source "manual" and confirmed. It is never linked to a Paystack payment.
- `admin_block_room`: closes a date range for one room.
- `admin_set_booking_status`: marks a confirmed booking as completed or cancelled.

2. Rules enforced on the server
- Only team admins can call these functions.
- Dates must be valid, check-out after check-in, and check-in not in the past.
- Guests must be 1 or 2.
- Nightly rate is set by the function: GH₵650 room only, GH₵700 with breakfast. Total is nights multiplied by the rate.
- Overlaps are checked against confirmed/completed bookings and existing blocks while holding a lock for that room, so two simultaneous requests cannot both succeed.
- Status changes only allow confirmed to completed or cancelled.

3. Security
- Each function is callable by signed-in users only (not anonymous visitors) and checks admin status itself.
- No existing tables or data are changed.
*/

CREATE OR REPLACE FUNCTION admin_create_manual_booking(
  p_room_id uuid,
  p_check_in date,
  p_check_out date,
  p_guests integer,
  p_breakfast_included boolean,
  p_guest_name text,
  p_guest_email text,
  p_guest_phone text,
  p_notes text
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
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'You are not authorised to manage bookings.' USING ERRCODE = '42501';
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
     OR length(btrim(coalesce(p_guest_phone, ''))) = 0
     OR length(btrim(coalesce(p_guest_email, ''))) = 0 THEN
    RAISE EXCEPTION 'Guest name, email and phone are required.';
  END IF;

  PERFORM 1 FROM stay_rooms WHERE id = p_room_id AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'That room is not available for bookings.';
  END IF;

  v_rate := CASE WHEN coalesce(p_breakfast_included, false) THEN 700 ELSE 650 END;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_room_id::text, 0));

  IF EXISTS (
    SELECT 1 FROM stay_bookings b
    WHERE b.room_id = p_room_id
      AND b.status IN ('confirmed', 'completed')
      AND daterange(b.check_in, b.check_out, '[)') && daterange(p_check_in, p_check_out, '[)')
  ) OR EXISTS (
    SELECT 1 FROM stay_room_blocks k
    WHERE k.room_id = p_room_id
      AND daterange(k.starts_on, k.ends_on, '[)') && daterange(p_check_in, p_check_out, '[)')
  ) THEN
    RAISE EXCEPTION 'That room is already booked or blocked for these dates.';
  END IF;

  INSERT INTO stay_bookings (
    room_id, check_in, check_out, guests, breakfast_included,
    nightly_rate_ghs, total_ghs, status, source,
    guest_name, guest_email, guest_phone, notes, created_by
  ) VALUES (
    p_room_id, p_check_in, p_check_out, p_guests, coalesce(p_breakfast_included, false),
    v_rate, (p_check_out - p_check_in) * v_rate, 'confirmed', 'manual',
    btrim(p_guest_name), btrim(p_guest_email), btrim(p_guest_phone), coalesce(p_notes, ''), auth.uid()
  )
  RETURNING * INTO v_booking;

  RETURN v_booking;
END;
$$;

CREATE OR REPLACE FUNCTION admin_block_room(
  p_room_id uuid,
  p_starts_on date,
  p_ends_on date,
  p_reason text
)
RETURNS stay_room_blocks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_block stay_room_blocks;
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'You are not authorised to manage bookings.' USING ERRCODE = '42501';
  END IF;

  IF p_starts_on IS NULL OR p_ends_on IS NULL OR p_ends_on <= p_starts_on THEN
    RAISE EXCEPTION 'The blocked end date must be after the start date.';
  END IF;

  PERFORM 1 FROM stay_rooms WHERE id = p_room_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'That room does not exist.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_room_id::text, 0));

  IF EXISTS (
    SELECT 1 FROM stay_bookings b
    WHERE b.room_id = p_room_id
      AND b.status IN ('confirmed', 'completed')
      AND daterange(b.check_in, b.check_out, '[)') && daterange(p_starts_on, p_ends_on, '[)')
  ) THEN
    RAISE EXCEPTION 'A booking already covers part of these dates. Cancel it before blocking the room.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM stay_room_blocks k
    WHERE k.room_id = p_room_id
      AND daterange(k.starts_on, k.ends_on, '[)') && daterange(p_starts_on, p_ends_on, '[)')
  ) THEN
    RAISE EXCEPTION 'This room is already blocked for part of these dates.';
  END IF;

  INSERT INTO stay_room_blocks (room_id, starts_on, ends_on, reason, created_by)
  VALUES (p_room_id, p_starts_on, p_ends_on, coalesce(btrim(p_reason), ''), auth.uid())
  RETURNING * INTO v_block;

  RETURN v_block;
END;
$$;

CREATE OR REPLACE FUNCTION admin_set_booking_status(
  p_booking_id uuid,
  p_status text
)
RETURNS stay_bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking stay_bookings;
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'You are not authorised to manage bookings.' USING ERRCODE = '42501';
  END IF;

  IF p_status NOT IN ('completed', 'cancelled') THEN
    RAISE EXCEPTION 'Bookings can only be marked completed or cancelled here.';
  END IF;

  SELECT * INTO v_booking FROM stay_bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'That booking does not exist.';
  END IF;

  IF v_booking.status <> 'confirmed' THEN
    RAISE EXCEPTION 'Only confirmed bookings can be changed.';
  END IF;

  UPDATE stay_bookings
  SET status = p_status,
      updated_at = now(),
      cancelled_at = CASE WHEN p_status = 'cancelled' THEN now() ELSE cancelled_at END
  WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  RETURN v_booking;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_create_manual_booking(uuid, date, date, integer, boolean, text, text, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION admin_block_room(uuid, date, date, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION admin_set_booking_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_create_manual_booking(uuid, date, date, integer, boolean, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_block_room(uuid, date, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_set_booking_status(uuid, text) TO authenticated;
