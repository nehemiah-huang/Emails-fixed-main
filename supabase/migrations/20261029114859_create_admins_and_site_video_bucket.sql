/*
# Admin list and public site-video bucket

1. New Tables
- `admins`: one row per Edan team member allowed into the dashboard. `user_id` points at the signed-in account.

2. Security
- RLS enabled on `admins`. Signed-in users can read only their own row. Nobody can change the list from the app; rows are added by the team directly in the database.
- `is_edan_admin()` returns true when the current signed-in user has an `admins` row. Callable by signed-in users only.
- New public storage bucket `site-videos` for the homepage hero video. Anyone can read files; only admins can upload, replace or delete them.
*/

CREATE TABLE IF NOT EXISTS admins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE admins ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON admins TO authenticated;

DROP POLICY IF EXISTS "select_own_admin_row" ON admins;
CREATE POLICY "select_own_admin_row" ON admins FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION is_edan_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM admins WHERE user_id = auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION is_edan_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION is_edan_admin() TO authenticated;

INSERT INTO storage.buckets (id, name, public)
VALUES ('site-videos', 'site-videos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "admins_insert_site_videos" ON storage.objects;
CREATE POLICY "admins_insert_site_videos" ON storage.objects FOR INSERT
  TO authenticated WITH CHECK (bucket_id = 'site-videos' AND is_edan_admin());

DROP POLICY IF EXISTS "admins_update_site_videos" ON storage.objects;
CREATE POLICY "admins_update_site_videos" ON storage.objects FOR UPDATE
  TO authenticated USING (bucket_id = 'site-videos' AND is_edan_admin())
  WITH CHECK (bucket_id = 'site-videos' AND is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_site_videos" ON storage.objects;
CREATE POLICY "admins_delete_site_videos" ON storage.objects FOR DELETE
  TO authenticated USING (bucket_id = 'site-videos' AND is_edan_admin());
