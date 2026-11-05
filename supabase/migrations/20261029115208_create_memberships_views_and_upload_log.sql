/*
# Memberships, homepage video views and video upload log

1. New Tables
- `memberships`: one row per member. Rows are added by the membership sign-up/payment process, not by the app's visitors.
- `video_views`: one row per homepage hero video play. Only the count is used.
- `video_uploads`: one row per hero video upload made from the dashboard.

2. Security
- `memberships`: members can read their own row; admins can read all rows. No client writes.
- `video_views`: anyone visiting the site can add a row; only admins can read them.
- `video_uploads`: admins can add rows, recorded under their own account; admins can read them.
*/

CREATE TABLE IF NOT EXISTS memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  member_email text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON memberships TO authenticated;

DROP POLICY IF EXISTS "select_own_membership" ON memberships;
CREATE POLICY "select_own_membership" ON memberships FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "admins_select_memberships" ON memberships;
CREATE POLICY "admins_select_memberships" ON memberships FOR SELECT
  TO authenticated USING (is_edan_admin());

CREATE TABLE IF NOT EXISTS video_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE video_views ENABLE ROW LEVEL SECURITY;

GRANT INSERT ON video_views TO anon, authenticated;
GRANT SELECT ON video_views TO authenticated;

DROP POLICY IF EXISTS "anyone_insert_video_views" ON video_views;
CREATE POLICY "anyone_insert_video_views" ON video_views FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "admins_select_video_views" ON video_views;
CREATE POLICY "admins_select_video_views" ON video_views FOR SELECT
  TO authenticated USING (is_edan_admin());

CREATE TABLE IF NOT EXISTS video_uploads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uploaded_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE SET NULL,
  file_name text NOT NULL,
  size_bytes bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE video_uploads ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON video_uploads TO authenticated;

DROP POLICY IF EXISTS "admins_insert_video_uploads" ON video_uploads;
CREATE POLICY "admins_insert_video_uploads" ON video_uploads FOR INSERT
  TO authenticated WITH CHECK (is_edan_admin() AND uploaded_by = auth.uid());

DROP POLICY IF EXISTS "admins_select_video_uploads" ON video_uploads;
CREATE POLICY "admins_select_video_uploads" ON video_uploads FOR SELECT
  TO authenticated USING (is_edan_admin());
