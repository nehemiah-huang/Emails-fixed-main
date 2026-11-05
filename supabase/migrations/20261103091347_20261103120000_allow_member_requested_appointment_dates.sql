/*
# Allow members to request appointment dates without published availability

1. Purpose
- Let active annual members choose a future date and preferred time directly from the Members page.
- Keep the existing appointment tables and administrator workflow intact.
- Record the requested date and time even when no administrator-created availability slot exists.

2. Modified tables
- `member_appointments`
- `requested_start_at` (timestamptz, nullable): the date and preferred start time requested by the member.
- `slot_id` becomes nullable for date-based requests; existing slot-backed appointments are unchanged.

3. New booking behavior
- Adds an overloaded `create_member_appointment` function that validates the member, appointment type, future requested time, and contact details.
- The requested end time is calculated from the selected appointment type duration.
- Existing slot-based bookings remain supported by the original function.

4. Security
- Existing RLS policies remain in place.
- The new booking function is callable only by authenticated users and checks active annual membership before inserting.
- No public or anonymous access is added.

5. Important notes
- No existing appointment rows are deleted or rewritten.
- Existing administrator-created slots continue to work.
- The new nullable field allows the dashboard and notification email to show the member's requested date and time.
*/

ALTER TABLE public.member_appointments
  ADD COLUMN IF NOT EXISTS requested_start_at timestamptz;

ALTER TABLE public.member_appointments
  ALTER COLUMN slot_id DROP NOT NULL;

CREATE INDEX IF NOT EXISTS member_appointments_requested_start_idx
  ON public.member_appointments (requested_start_at)
  WHERE requested_start_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.create_member_appointment(
  p_appointment_type_id uuid,
  p_requested_start_at timestamptz,
  p_member_name text,
  p_member_email text,
  p_whatsapp_number text,
  p_member_note text
)
RETURNS TABLE (
  id uuid,
  booking_reference text,
  status text,
  starts_at timestamptz,
  ends_at timestamptz,
  appointment_title text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type member_appointment_types%ROWTYPE;
  v_appointment member_appointments%ROWTYPE;
BEGIN
  IF NOT is_active_member(ARRAY['annual'::text]) THEN
    RAISE EXCEPTION 'Appointment access requires an active annual membership';
  END IF;

  IF p_requested_start_at IS NULL
     OR p_requested_start_at <= now()
     OR p_requested_start_at > now() + interval '180 days'
     OR length(btrim(coalesce(p_member_name, ''))) NOT BETWEEN 1 AND 120
     OR length(btrim(coalesce(p_member_email, ''))) NOT BETWEEN 3 AND 254
     OR length(coalesce(p_whatsapp_number, '')) > 40
     OR length(coalesce(p_member_note, '')) > 2000 THEN
    RAISE EXCEPTION 'Please check the appointment details';
  END IF;

  SELECT * INTO v_type
  FROM member_appointment_types
  WHERE id = p_appointment_type_id AND is_active
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'That appointment type is unavailable';
  END IF;

  INSERT INTO member_appointments (
    user_id,
    appointment_type_id,
    slot_id,
    requested_start_at,
    member_name,
    member_email,
    whatsapp_number,
    member_note
  )
  VALUES (
    auth.uid(),
    p_appointment_type_id,
    NULL,
    p_requested_start_at,
    btrim(p_member_name),
    lower(btrim(p_member_email)),
    btrim(coalesce(p_whatsapp_number, '')),
    btrim(coalesce(p_member_note, ''))
  )
  RETURNING * INTO v_appointment;

  RETURN QUERY
  SELECT
    v_appointment.id,
    v_appointment.booking_reference,
    v_appointment.status,
    p_requested_start_at,
    p_requested_start_at + make_interval(mins => v_type.duration_minutes),
    v_type.title;
END;
$$;

REVOKE ALL ON FUNCTION public.create_member_appointment(uuid, timestamptz, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_member_appointment(uuid, timestamptz, text, text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';