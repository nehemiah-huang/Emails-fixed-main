/*
# Stay booking confirmation lookup

1. New functions
- `get_own_stay_confirmation(p_booking_id uuid)`: returns the booking details, room name and payment record for one booking. It only returns a row when the booking belongs to the signed-in guest.

2. Why a function
- Room records are visible to admins only, so a guest cannot read the room name from the booking table directly. The function returns just the fields the confirmation page needs and nothing else (no phone number, no Paystack transaction IDs, no payment notes).

3. Security
- The function checks `auth.uid()` against the booking's owner. Anyone else gets no row.
- Executable by signed-in users only. Anonymous visitors and PUBLIC are revoked.
- No table grants or policies change.

4. Notes
- Returns no row when the booking does not exist or belongs to someone else, so the page cannot tell the two cases apart.
*/

CREATE OR REPLACE FUNCTION get_own_stay_confirmation(p_booking_id uuid)
RETURNS TABLE (
  booking_reference text,
  status text,
  room_name text,
  guest_name text,
  guest_email text,
  check_in date,
  check_out date,
  guests smallint,
  breakfast_included boolean,
  nightly_rate_ghs integer,
  total_ghs integer,
  paid_amount_pesewas integer,
  paid_at timestamptz,
  paystack_reference text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    b.booking_reference,
    b.status,
    r.name,
    b.guest_name,
    b.guest_email,
    b.check_in,
    b.check_out,
    b.guests,
    b.breakfast_included,
    b.nightly_rate_ghs,
    b.total_ghs,
    b.paid_amount_pesewas,
    b.paid_at,
    b.paystack_reference
  FROM stay_bookings b
  JOIN stay_rooms r ON r.id = b.room_id
  WHERE b.id = p_booking_id
    AND b.user_id = auth.uid();
$$;

REVOKE EXECUTE ON FUNCTION get_own_stay_confirmation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_own_stay_confirmation(uuid) TO authenticated;
