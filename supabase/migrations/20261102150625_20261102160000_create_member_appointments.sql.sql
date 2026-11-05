/*
# Create member appointment booking system

1. New tables
- `member_appointment_types`: active appointment options, descriptions, and durations.
- `member_appointment_slots`: administrator-created future times that can be available or blocked.
- `member_appointments`: annual-member booking requests linked to a selected type and slot.

2. Booking behavior
- Only active annual members can read available choices or submit requests.
- Slot reservation is performed atomically by a server function and protected by a unique active-slot index.
- Requests use `requested`, `confirmed`, `declined`, `cancelled`, and `completed` statuses.

3. Security
- RLS is enabled on every new table.
- Members can read only their own appointment records; administrators can manage the system.
- Members cannot directly insert, update, or delete appointment records.
- Privileged functions validate the authenticated caller, membership tier, availability, and booking state.

4. Dashboard
- `admin_dashboard_kpis()` gains an `appointments` count for upcoming requested and confirmed appointments.
*/

CREATE TABLE IF NOT EXISTS member_appointment_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 1000),
  duration_minutes integer NOT NULL DEFAULT 60 CHECK (duration_minutes BETWEEN 15 AND 240),
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS member_appointment_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'blocked')),
  notes text NOT NULL DEFAULT '' CHECK (length(notes) <= 500),
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  CHECK (ends_at - starts_at <= interval '4 hours')
);

CREATE TABLE IF NOT EXISTS member_appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_reference text NOT NULL UNIQUE DEFAULT ('EDN-APT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  appointment_type_id uuid NOT NULL REFERENCES member_appointment_types(id),
  slot_id uuid NOT NULL REFERENCES member_appointment_slots(id),
  member_name text NOT NULL CHECK (length(btrim(member_name)) BETWEEN 1 AND 120),
  member_email text NOT NULL CHECK (length(btrim(member_email)) BETWEEN 3 AND 254),
  whatsapp_number text NOT NULL DEFAULT '' CHECK (length(whatsapp_number) <= 40),
  member_note text NOT NULL DEFAULT '' CHECK (length(member_note) <= 2000),
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'confirmed', 'declined', 'cancelled', 'completed')),
  admin_note text NOT NULL DEFAULT '' CHECK (length(admin_note) <= 2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS member_appointment_slots_starts_at_idx ON member_appointment_slots (starts_at);
CREATE INDEX IF NOT EXISTS member_appointments_user_created_at_idx ON member_appointments (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS member_appointments_status_idx ON member_appointments (status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS member_appointments_active_slot_idx ON member_appointments (slot_id) WHERE status IN ('requested', 'confirmed');

INSERT INTO member_appointment_types (title, description, duration_minutes, sort_order)
SELECT * FROM (VALUES
  ('Introductory Conversation', 'A chance to meet the team, learn more about Ɛdan and explore possible ways to get involved.', 60, 1),
  ('Research Consultation', 'A focused conversation around research interests, questions, ideas or ongoing work.', 60, 2),
  ('Creative Working Session', 'Dedicated time to discuss, develop or work through a creative idea or project.', 90, 3),
  ('Membership Support', 'A session for questions about membership, access or using the space.', 30, 4)
) AS defaults(title, description, duration_minutes, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM member_appointment_types);

ALTER TABLE member_appointment_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_appointment_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_appointments ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON member_appointment_types, member_appointment_slots, member_appointments TO authenticated;

DROP POLICY IF EXISTS "annual_members_select_appointment_types" ON member_appointment_types;
CREATE POLICY "annual_members_select_appointment_types" ON member_appointment_types FOR SELECT TO authenticated USING (is_active_member(ARRAY['annual'::text]) OR is_edan_admin());
DROP POLICY IF EXISTS "admins_insert_appointment_types" ON member_appointment_types;
CREATE POLICY "admins_insert_appointment_types" ON member_appointment_types FOR INSERT TO authenticated WITH CHECK (is_edan_admin());
DROP POLICY IF EXISTS "admins_update_appointment_types" ON member_appointment_types;
CREATE POLICY "admins_update_appointment_types" ON member_appointment_types FOR UPDATE TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());
DROP POLICY IF EXISTS "admins_delete_appointment_types" ON member_appointment_types;
CREATE POLICY "admins_delete_appointment_types" ON member_appointment_types FOR DELETE TO authenticated USING (is_edan_admin());

DROP POLICY IF EXISTS "annual_members_select_appointment_slots" ON member_appointment_slots;
CREATE POLICY "annual_members_select_appointment_slots" ON member_appointment_slots FOR SELECT TO authenticated USING ((status = 'available' AND starts_at > now() AND is_active_member(ARRAY['annual'::text])) OR is_edan_admin());
DROP POLICY IF EXISTS "admins_insert_appointment_slots" ON member_appointment_slots;
CREATE POLICY "admins_insert_appointment_slots" ON member_appointment_slots FOR INSERT TO authenticated WITH CHECK (is_edan_admin() AND created_by = auth.uid());
DROP POLICY IF EXISTS "admins_update_appointment_slots" ON member_appointment_slots;
CREATE POLICY "admins_update_appointment_slots" ON member_appointment_slots FOR UPDATE TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());
DROP POLICY IF EXISTS "admins_delete_appointment_slots" ON member_appointment_slots;
CREATE POLICY "admins_delete_appointment_slots" ON member_appointment_slots FOR DELETE TO authenticated USING (is_edan_admin());

DROP POLICY IF EXISTS "members_select_own_appointments" ON member_appointments;
CREATE POLICY "members_select_own_appointments" ON member_appointments FOR SELECT TO authenticated USING (user_id = auth.uid() OR is_edan_admin());

CREATE OR REPLACE FUNCTION get_member_appointment_slots(p_from timestamptz, p_to timestamptz)
RETURNS TABLE (id uuid, starts_at timestamptz, ends_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_active_member(ARRAY['annual'::text]) THEN RAISE EXCEPTION 'Appointment access requires an active annual membership'; END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_to <= p_from OR p_to - p_from > interval '90 days' THEN RAISE EXCEPTION 'Invalid appointment date range'; END IF;
  RETURN QUERY SELECT s.id, s.starts_at, s.ends_at
  FROM member_appointment_slots s
  WHERE s.status = 'available' AND s.starts_at >= p_from AND s.starts_at < p_to AND s.starts_at > now()
    AND NOT EXISTS (SELECT 1 FROM member_appointments a WHERE a.slot_id = s.id AND a.status IN ('requested', 'confirmed'))
  ORDER BY s.starts_at;
END;
$$;

CREATE OR REPLACE FUNCTION create_member_appointment(p_appointment_type_id uuid, p_slot_id uuid, p_member_name text, p_member_email text, p_whatsapp_number text, p_member_note text)
RETURNS TABLE (id uuid, booking_reference text, status text, starts_at timestamptz, ends_at timestamptz, appointment_title text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_slot member_appointment_slots%ROWTYPE; v_type member_appointment_types%ROWTYPE; v_appointment member_appointments%ROWTYPE;
BEGIN
  IF NOT is_active_member(ARRAY['annual'::text]) THEN RAISE EXCEPTION 'Appointment access requires an active annual membership'; END IF;
  IF length(btrim(coalesce(p_member_name, ''))) NOT BETWEEN 1 AND 120 OR length(btrim(coalesce(p_member_email, ''))) NOT BETWEEN 3 AND 254 OR length(coalesce(p_whatsapp_number, '')) > 40 OR length(coalesce(p_member_note, '')) > 2000 THEN RAISE EXCEPTION 'Please check the appointment details'; END IF;
  SELECT * INTO v_type FROM member_appointment_types WHERE id = p_appointment_type_id AND is_active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'That appointment type is unavailable'; END IF;
  SELECT * INTO v_slot FROM member_appointment_slots WHERE id = p_slot_id FOR UPDATE;
  IF NOT FOUND OR v_slot.status <> 'available' OR v_slot.starts_at <= now() THEN RAISE EXCEPTION 'That time is no longer available'; END IF;
  IF EXISTS (SELECT 1 FROM member_appointments WHERE slot_id = p_slot_id AND status IN ('requested', 'confirmed')) THEN RAISE EXCEPTION 'That time is no longer available'; END IF;
  INSERT INTO member_appointments (user_id, appointment_type_id, slot_id, member_name, member_email, whatsapp_number, member_note)
  VALUES (auth.uid(), p_appointment_type_id, p_slot_id, btrim(p_member_name), lower(btrim(p_member_email)), btrim(coalesce(p_whatsapp_number, '')), btrim(coalesce(p_member_note, '')))
  RETURNING * INTO v_appointment;
  RETURN QUERY SELECT v_appointment.id, v_appointment.booking_reference, v_appointment.status, v_slot.starts_at, v_slot.ends_at, v_type.title;
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'That time is no longer available';
END;
$$;

CREATE OR REPLACE FUNCTION admin_create_appointment_slot(p_starts_at timestamptz, p_ends_at timestamptz, p_notes text DEFAULT '')
RETURNS member_appointment_slots LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_slot member_appointment_slots;
BEGIN
  IF NOT is_edan_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_starts_at <= now() OR p_ends_at <= p_starts_at OR p_ends_at - p_starts_at > interval '4 hours' THEN RAISE EXCEPTION 'Please enter a valid future appointment time'; END IF;
  INSERT INTO member_appointment_slots (starts_at, ends_at, notes, created_by) VALUES (p_starts_at, p_ends_at, btrim(coalesce(p_notes, '')), auth.uid()) RETURNING * INTO v_slot;
  RETURN v_slot;
END;
$$;

CREATE OR REPLACE FUNCTION admin_set_appointment_slot_status(p_slot_id uuid, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_edan_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_status NOT IN ('available', 'blocked') THEN RAISE EXCEPTION 'Invalid slot status'; END IF;
  UPDATE member_appointment_slots SET status = p_status WHERE id = p_slot_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Slot not found'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION admin_set_appointment_status(p_appointment_id uuid, p_status text, p_admin_note text DEFAULT '')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_edan_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_status NOT IN ('confirmed', 'declined', 'cancelled', 'completed') THEN RAISE EXCEPTION 'Invalid appointment status'; END IF;
  UPDATE member_appointments SET status = p_status, admin_note = btrim(coalesce(p_admin_note, '')), updated_at = now(), confirmed_at = CASE WHEN p_status = 'confirmed' THEN coalesce(confirmed_at, now()) ELSE confirmed_at END, completed_at = CASE WHEN p_status = 'completed' THEN coalesce(completed_at, now()) ELSE completed_at END WHERE id = p_appointment_id AND status NOT IN ('declined', 'cancelled', 'completed');
  IF NOT FOUND THEN RAISE EXCEPTION 'Appointment is unavailable for that change'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION get_member_appointment_slots(timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_member_appointment_slots(timestamptz, timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION create_member_appointment(uuid, uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_member_appointment(uuid, uuid, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION admin_create_appointment_slot(timestamptz, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_create_appointment_slot(timestamptz, timestamptz, text) TO authenticated;
REVOKE ALL ON FUNCTION admin_set_appointment_slot_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_set_appointment_slot_status(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION admin_set_appointment_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_set_appointment_status(uuid, text, text) TO authenticated;

DROP FUNCTION IF EXISTS admin_dashboard_kpis();
CREATE FUNCTION admin_dashboard_kpis()
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result json;
BEGIN
  IF NOT is_edan_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT json_build_object(
    'active_members', (SELECT count(*) FROM memberships WHERE membership_status = 'active' AND (expires_at IS NULL OR expires_at > now())),
    'pending_review', (SELECT count(*) FROM membership_applications WHERE status = 'pending'),
    'expired', (SELECT count(*) FROM memberships WHERE membership_status = 'expired' OR (membership_status = 'active' AND expires_at IS NOT NULL AND expires_at <= now())),
    'total_bookings', (SELECT count(*) FROM stay_bookings WHERE status IN ('confirmed', 'completed')),
    'appointments', (SELECT count(*) FROM member_appointments a JOIN member_appointment_slots s ON s.id = a.slot_id WHERE a.status IN ('requested', 'confirmed') AND s.starts_at >= now())
  ) INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_dashboard_kpis() TO authenticated;