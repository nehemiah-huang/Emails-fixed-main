/*
# Membership applications and admin review

1. Memberships
- Adds the columns the member pages already read: tier (monthly or annual), membership status, start and end dates.
- One membership row per member, so approvals and renewals update the same row.

2. New Table
- `membership_applications`: one row per membership application, linked to the applicant's account. Starts as pending.

3. Functions
- `approve_membership_application`: admin-only. Marks the application approved and sets the member's tier and dates, in one step.
- `reject_membership_application`: admin-only. Marks the application rejected.

4. Security
- Applicants can read their own applications; admins can read all of them.
- Nobody can change applications or memberships directly; changes go through the two functions.
*/

ALTER TABLE memberships
  ADD COLUMN IF NOT EXISTS membership_tier text CHECK (membership_tier IN ('monthly', 'annual')),
  ADD COLUMN IF NOT EXISTS membership_status text NOT NULL DEFAULT 'pending'
    CHECK (membership_status IN ('pending', 'active', 'expired', 'rejected')),
  ADD COLUMN IF NOT EXISTS started_at timestamptz,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS memberships_user_id_key ON memberships (user_id);

CREATE TABLE IF NOT EXISTS membership_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  applicant_email text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

ALTER TABLE membership_applications ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON membership_applications TO authenticated;

DROP POLICY IF EXISTS "select_own_membership_application" ON membership_applications;
CREATE POLICY "select_own_membership_application" ON membership_applications FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "admins_select_membership_applications" ON membership_applications;
CREATE POLICY "admins_select_membership_applications" ON membership_applications FOR SELECT
  TO authenticated USING (is_edan_admin());

CREATE OR REPLACE FUNCTION approve_membership_application(
  p_application_id uuid,
  p_tier text,
  p_started_at timestamptz,
  p_expires_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  app membership_applications%ROWTYPE;
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501';
  END IF;

  IF p_tier NOT IN ('monthly', 'annual') THEN
    RAISE EXCEPTION 'Choose monthly or annual membership';
  END IF;

  IF p_started_at IS NULL OR p_expires_at IS NULL OR p_expires_at <= p_started_at THEN
    RAISE EXCEPTION 'The end date must be after the start date';
  END IF;

  SELECT * INTO app FROM membership_applications WHERE id = p_application_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  IF app.status <> 'pending' THEN
    RAISE EXCEPTION 'This application has already been reviewed';
  END IF;

  INSERT INTO memberships (user_id, member_email, membership_tier, membership_status, started_at, expires_at)
  VALUES (app.user_id, app.applicant_email, p_tier, 'active', p_started_at, p_expires_at)
  ON CONFLICT (user_id) DO UPDATE SET
    member_email = EXCLUDED.member_email,
    membership_tier = EXCLUDED.membership_tier,
    membership_status = 'active',
    started_at = EXCLUDED.started_at,
    expires_at = EXCLUDED.expires_at;

  UPDATE membership_applications
  SET status = 'approved', reviewed_at = now(), reviewed_by = auth.uid()
  WHERE id = app.id;
END;
$$;

CREATE OR REPLACE FUNCTION reject_membership_application(p_application_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  app membership_applications%ROWTYPE;
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO app FROM membership_applications WHERE id = p_application_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  IF app.status <> 'pending' THEN
    RAISE EXCEPTION 'This application has already been reviewed';
  END IF;

  UPDATE membership_applications
  SET status = 'rejected', reviewed_at = now(), reviewed_by = auth.uid()
  WHERE id = app.id;
END;
$$;

REVOKE EXECUTE ON FUNCTION approve_membership_application(uuid, text, timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION approve_membership_application(uuid, text, timestamptz, timestamptz) TO authenticated;

REVOKE EXECUTE ON FUNCTION reject_membership_application(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reject_membership_application(uuid) TO authenticated;
