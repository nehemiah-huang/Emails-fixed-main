/*
# Create editable Members page settings

1. New Tables
- `member_page_settings`
- `id`: single settings-record key.
- `hero_eyebrow`, `hero_title`, `hero_image_path`: Members page welcome area.
- `membership_eyebrow`, `membership_intro`: membership overview copy.
- `benefits`: ordered JSON list of membership benefit labels.
- `community_image_path`, `community_eyebrow`, `community_title`, `community_description`: Community section presentation.
- `process_image_path`, `process_eyebrow`, `process_title`, `process_description`: In Process section presentation.
- `gather_image_path`, `gather_eyebrow`, `gather_title`, `gather_description`: Gather section presentation.
- `research_image_path`, `research_eyebrow`, `research_title`, `research_description`: Research section presentation.
- `bonus_image_path`, `bonus_eyebrow`, `bonus_title`, `bonus_description`: Bonus content section presentation.
- `appointments_image_path`, `appointments_eyebrow`, `appointments_title`, `appointments_description`: Appointments section presentation.
- `created_at`, `updated_at`: record timestamps.

2. Modified Tables
- None.

3. Security
- Row-level security is enabled.
- Active monthly and annual members can read the settings.
- Authenticated Ɛdan admins can read, insert, and update the settings.
- No anonymous access is granted because this page is member-only.

4. Important Notes
- The table intentionally contains one row with the key `default`.
- The benefits field is restricted to a JSON array so the dashboard can preserve order.
- Existing page content remains available as a visual fallback until the frontend begins loading these settings.
*/

CREATE TABLE IF NOT EXISTS public.member_page_settings (
  id text PRIMARY KEY DEFAULT 'default' CHECK (id = 'default'),
  hero_eyebrow text NOT NULL DEFAULT 'Members',
  hero_title text NOT NULL DEFAULT 'Welcome to Ɛdan.',
  hero_image_path text NOT NULL DEFAULT '/images/breeze-block-hero.jpg',
  membership_eyebrow text NOT NULL DEFAULT 'Your place at Ɛdan',
  membership_intro text NOT NULL DEFAULT 'Your membership gives you a place to connect, learn and take part in the life of Ɛdan.',
  benefits jsonb NOT NULL DEFAULT '["Community chat", "Behind-the-scenes content", "Monthly social invitations", "10% off Small Moments and Ɛdan residencies", "Bonus videos", "One-to-one appointments"]'::jsonb CHECK (jsonb_typeof(benefits) = 'array'),
  community_image_path text NOT NULL DEFAULT '/images/comm.avif',
  community_eyebrow text NOT NULL DEFAULT '01 / Community',
  community_title text NOT NULL DEFAULT 'Talk with the members.',
  community_description text NOT NULL DEFAULT 'A warm space for ideas, questions and everyday conversation across the Ɛdan community.',
  process_image_path text NOT NULL DEFAULT '/images/breeze-block-detail.jpg',
  process_eyebrow text NOT NULL DEFAULT '02 / In Process',
  process_title text NOT NULL DEFAULT 'Work in progress.',
  process_description text NOT NULL DEFAULT 'An ongoing collection of ideas, experiments and projects taking shape at Ɛdan.',
  gather_image_path text NOT NULL DEFAULT '/images/garden-eat.jpg',
  gather_eyebrow text NOT NULL DEFAULT '03 / Gather',
  gather_title text NOT NULL DEFAULT 'Come together.',
  gather_description text NOT NULL DEFAULT 'A space for conversations, shared experiences and moments that bring our community together.',
  research_image_path text NOT NULL DEFAULT '/images/our story intro.jpg',
  research_eyebrow text NOT NULL DEFAULT '04 / Research',
  research_title text NOT NULL DEFAULT 'Ideas in the making.',
  research_description text NOT NULL DEFAULT 'Notes, observations and research exploring the relationships between people, space and the city.',
  bonus_image_path text NOT NULL DEFAULT '/images/our story image.webp',
  bonus_eyebrow text NOT NULL DEFAULT '05 / Bonus content',
  bonus_title text NOT NULL DEFAULT 'A little further in.',
  bonus_description text NOT NULL DEFAULT 'Films, conversations and research offering a closer look at the ideas, people and processes shaping Ɛdan.',
  appointments_image_path text NOT NULL DEFAULT '/images/our story people.jpg',
  appointments_eyebrow text NOT NULL DEFAULT '06 / Appointments',
  appointments_title text NOT NULL DEFAULT 'Let''s make time.',
  appointments_description text NOT NULL DEFAULT 'Book a conversation, consultation or working session with the Ɛdan team.',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.member_page_settings ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.member_page_settings TO authenticated;
GRANT INSERT, UPDATE ON public.member_page_settings TO authenticated;

DROP POLICY IF EXISTS "active_members_select_member_page_settings" ON public.member_page_settings;
CREATE POLICY "active_members_select_member_page_settings"
  ON public.member_page_settings FOR SELECT
  TO authenticated
  USING (is_active_member(ARRAY['monthly'::text, 'annual'::text]) OR is_edan_admin());

DROP POLICY IF EXISTS "admins_insert_member_page_settings" ON public.member_page_settings;
CREATE POLICY "admins_insert_member_page_settings"
  ON public.member_page_settings FOR INSERT
  TO authenticated
  WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_update_member_page_settings" ON public.member_page_settings;
CREATE POLICY "admins_update_member_page_settings"
  ON public.member_page_settings FOR UPDATE
  TO authenticated
  USING (is_edan_admin())
  WITH CHECK (is_edan_admin());

INSERT INTO public.member_page_settings (id)
VALUES ('default')
ON CONFLICT (id) DO NOTHING;
