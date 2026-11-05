/*
# Members community, gatherings and annual bonus videos

1. New Functions
- `is_active_member(tiers text[])`: true when the signed-in user has an active, unexpired membership whose tier is in the list.

2. New Tables
- `member_chat_profiles`: one chat username per member.
- `member_chat_messages`: community chat messages.
- `member_gatherings`: gatherings and invitations shown to members. Managed by admins.
- `member_bonus_videos`: annual-only bonus videos. Managed by admins.

3. Security
- Every table has row level security enabled.
- Chat: active monthly and annual members can read and post; a member can only write their own username and messages.
- Gatherings: active members read published rows; admins read and write everything.
- Bonus videos: only active annual members read published rows; admins read and write everything.
- Admin-only writes use the existing `is_edan_admin()` check.

4. Notes
- Realtime is enabled for chat messages so new messages appear live, and realtime respects these policies.
- Creation is idempotent, so the migration can be re-run safely.
*/

CREATE OR REPLACE FUNCTION is_active_member(tiers text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM memberships m
    WHERE m.user_id = auth.uid()
      AND m.membership_status = 'active'
      AND m.membership_tier = ANY (tiers)
      AND (m.expires_at IS NULL OR m.expires_at > now())
  );
$$;

REVOKE EXECUTE ON FUNCTION is_active_member(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION is_active_member(text[]) TO authenticated;

CREATE TABLE IF NOT EXISTS member_chat_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL UNIQUE CHECK (username ~ '^[A-Za-z0-9_]{3,24}$'),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE member_chat_profiles ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON member_chat_profiles TO authenticated;

DROP POLICY IF EXISTS "active_members_select_chat_profiles" ON member_chat_profiles;
CREATE POLICY "active_members_select_chat_profiles" ON member_chat_profiles FOR SELECT
  TO authenticated USING (is_active_member(ARRAY['monthly', 'annual']));

DROP POLICY IF EXISTS "active_members_insert_chat_profiles" ON member_chat_profiles;
CREATE POLICY "active_members_insert_chat_profiles" ON member_chat_profiles FOR INSERT
  TO authenticated WITH CHECK (
    user_id = auth.uid() AND is_active_member(ARRAY['monthly', 'annual'])
  );

DROP POLICY IF EXISTS "active_members_update_chat_profiles" ON member_chat_profiles;
CREATE POLICY "active_members_update_chat_profiles" ON member_chat_profiles FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid() AND is_active_member(ARRAY['monthly', 'annual']))
  WITH CHECK (user_id = auth.uid() AND is_active_member(ARRAY['monthly', 'annual']));

CREATE TABLE IF NOT EXISTS member_chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  message text NOT NULL CHECK (length(btrim(message)) BETWEEN 1 AND 1000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS member_chat_messages_created_at_idx
  ON member_chat_messages (created_at DESC);

ALTER TABLE member_chat_messages ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON member_chat_messages TO authenticated;

DROP POLICY IF EXISTS "active_members_select_chat_messages" ON member_chat_messages;
CREATE POLICY "active_members_select_chat_messages" ON member_chat_messages FOR SELECT
  TO authenticated USING (is_active_member(ARRAY['monthly', 'annual']));

DROP POLICY IF EXISTS "active_members_insert_chat_messages" ON member_chat_messages;
CREATE POLICY "active_members_insert_chat_messages" ON member_chat_messages FOR INSERT
  TO authenticated WITH CHECK (
    user_id = auth.uid()
    AND is_active_member(ARRAY['monthly', 'annual'])
    AND EXISTS (SELECT 1 FROM member_chat_profiles p WHERE p.user_id = auth.uid())
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'member_chat_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE member_chat_messages;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS member_gatherings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  description text NOT NULL DEFAULT '',
  starts_at timestamptz,
  location text NOT NULL DEFAULT '',
  image_path text NOT NULL DEFAULT '',
  registration_url text NOT NULL DEFAULT '',
  is_published boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE member_gatherings ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON member_gatherings TO authenticated;

DROP POLICY IF EXISTS "members_select_published_gatherings" ON member_gatherings;
CREATE POLICY "members_select_published_gatherings" ON member_gatherings FOR SELECT
  TO authenticated USING (
    (is_published AND is_active_member(ARRAY['monthly', 'annual'])) OR is_edan_admin()
  );

DROP POLICY IF EXISTS "admins_insert_gatherings" ON member_gatherings;
CREATE POLICY "admins_insert_gatherings" ON member_gatherings FOR INSERT
  TO authenticated WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_update_gatherings" ON member_gatherings;
CREATE POLICY "admins_update_gatherings" ON member_gatherings FOR UPDATE
  TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_gatherings" ON member_gatherings;
CREATE POLICY "admins_delete_gatherings" ON member_gatherings FOR DELETE
  TO authenticated USING (is_edan_admin());

CREATE TABLE IF NOT EXISTS member_bonus_videos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  description text NOT NULL DEFAULT '',
  video_path text NOT NULL DEFAULT '',
  poster_path text NOT NULL DEFAULT '',
  is_published boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE member_bonus_videos ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON member_bonus_videos TO authenticated;

DROP POLICY IF EXISTS "annual_members_select_published_bonus_videos" ON member_bonus_videos;
CREATE POLICY "annual_members_select_published_bonus_videos" ON member_bonus_videos FOR SELECT
  TO authenticated USING (
    (is_published AND is_active_member(ARRAY['annual'])) OR is_edan_admin()
  );

DROP POLICY IF EXISTS "admins_insert_bonus_videos" ON member_bonus_videos;
CREATE POLICY "admins_insert_bonus_videos" ON member_bonus_videos FOR INSERT
  TO authenticated WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_update_bonus_videos" ON member_bonus_videos;
CREATE POLICY "admins_update_bonus_videos" ON member_bonus_videos FOR UPDATE
  TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_bonus_videos" ON member_bonus_videos;
CREATE POLICY "admins_delete_bonus_videos" ON member_bonus_videos FOR DELETE
  TO authenticated USING (is_edan_admin());
