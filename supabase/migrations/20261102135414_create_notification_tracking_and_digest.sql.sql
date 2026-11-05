/*
# Admin notification tracking and daily digest function

1. New table: notification_log
   - Tracks every admin email sent so nothing is duplicated.
   - Columns: id, notification_type (signup|application|booking|approval|reminder), ref_id, sent_at.
   - Unique on (notification_type, ref_id) so the same event is never emailed twice.

2. New table: reminder_log
   - Tracks daily reminder emails (pending_apps|expired_memberships|blocked_dates) by date.
   - Unique on (reminder_type, reminder_date) so each reminder type fires at most once per day.

3. New function: get_daily_admin_digest()
   - Admin-only. Returns a single JSON object with:
     - pending_applications: rows with full applicant details + tier + submitted_at
     - expired_memberships: rows with member_email, tier, expired status, expiry date
     - upcoming_block_ends: stay_room_blocks ending in the next 7 days with room name + dates + reason
   - Used by the admin-notifications edge function for the daily reminder.

4. Security
   - notification_log and reminder_log are service_role only (written by edge functions).
   - get_daily_admin_digest is admin-only via is_edan_admin(), granted to authenticated.
*/

CREATE TABLE IF NOT EXISTS notification_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_type text NOT NULL,
  ref_id text NOT NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT notification_log_unique UNIQUE (notification_type, ref_id)
);

ALTER TABLE notification_log ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON notification_log TO service_role;

CREATE TABLE IF NOT EXISTS reminder_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reminder_type text NOT NULL,
  reminder_date date NOT NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reminder_log_unique UNIQUE (reminder_type, reminder_date)
);

ALTER TABLE reminder_log ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON reminder_log TO service_role;

CREATE OR REPLACE FUNCTION get_daily_admin_digest()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'Admins only' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'pending_applications', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', ma.id,
        'full_name', ma.full_name,
        'applicant_email', ma.applicant_email,
        'phone', ma.phone,
        'practice_type', ma.practice_type,
        'based_in', ma.based_in,
        'membership_tier', ma.membership_tier,
        'about_work', ma.about_work,
        'submitted_at', ma.submitted_at,
        'created_at', ma.created_at
      ) ORDER BY ma.submitted_at DESC NULLS LAST), '[]'::jsonb)
      FROM membership_applications ma
      WHERE ma.status = 'pending' AND ma.submitted_at IS NOT NULL
    ),
    'expired_memberships', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', m.id,
        'member_email', m.member_email,
        'membership_tier', m.membership_tier,
        'membership_status', CASE
          WHEN m.membership_status = 'expired' THEN 'expired'
          WHEN m.expires_at IS NOT NULL AND m.expires_at <= now() THEN 'expired'
          ELSE m.membership_status
        END,
        'expires_at', m.expires_at
      ) ORDER BY m.expires_at DESC NULLS LAST), '[]'::jsonb)
      FROM memberships m
      WHERE m.membership_status = 'expired'
         OR (m.membership_status = 'active' AND m.expires_at IS NOT NULL AND m.expires_at <= now())
    ),
    'upcoming_block_ends', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', b.id,
        'room_name', r.name,
        'starts_on', b.starts_on,
        'ends_on', b.ends_on,
        'reason', b.reason
      ) ORDER BY b.ends_on ASC), '[]'::jsonb)
      FROM stay_room_blocks b
      JOIN stay_rooms r ON r.id = b.room_id
      WHERE b.ends_on >= CURRENT_DATE
        AND b.ends_on <= CURRENT_DATE + interval '7 days'
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION get_daily_admin_digest() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_daily_admin_digest() TO authenticated;

NOTIFY pgrst, 'reload schema';
