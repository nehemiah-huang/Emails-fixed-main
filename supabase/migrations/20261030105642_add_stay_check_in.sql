/*
# Add guest check-in for Stay bookings

1. Modified tables
- `stay_bookings`: new column `checked_in_at` (timestamptz, nullable). It is set when staff check the guest in. Empty means the guest has not arrived yet.

2. New functions
- `admin_check_in_booking(p_booking_id)`: sets `checked_in_at` to the current time. Rules:
  - The caller must be an admin (checked inside the function).
  - Only confirmed bookings can be checked in.
  - A guest can be checked in once.
  - Check-in is allowed from the arrival date onward, so staff cannot check someone in early.
  - The booking row is locked while the check is made, so two staff members cannot race.

3. Security
- The function is executable by signed-in users only (not anonymous visitors), and it still refuses non-admins.
- No table grants or policies change. Guests and admins read the column through the existing policies.

4. Notes
- Checking out is still done with the existing "Mark as completed" action, which moves the booking to completed.
*/

ALTER TABLE stay_bookings ADD COLUMN IF NOT EXISTS checked_in_at timestamptz;

CREATE OR REPLACE FUNCTION admin_check_in_booking(p_booking_id uuid)
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

  SELECT * INTO v_booking
  FROM stay_bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'That booking does not exist.';
  END IF;

  IF v_booking.status <> 'confirmed' THEN
    RAISE EXCEPTION 'Only confirmed bookings can be checked in.';
  END IF;

  IF v_booking.checked_in_at IS NOT NULL THEN
    RAISE EXCEPTION 'This guest is already checked in.';
  END IF;

  IF v_booking.check_in > CURRENT_DATE THEN
    RAISE EXCEPTION 'Guests can be checked in from their arrival date.';
  END IF;

  UPDATE stay_bookings
  SET checked_in_at = now()
  WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  RETURN v_booking;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_check_in_booking(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_check_in_booking(uuid) TO authenticated;
