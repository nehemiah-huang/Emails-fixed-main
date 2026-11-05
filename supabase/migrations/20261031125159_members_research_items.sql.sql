/*
# Members research items

1. New Tables
- `member_research_items`: research notes, creative insights and publications shown in the Members page Research section.
  - `title`, `summary`, `category`, `image_path`, `read_more_url`, `is_published`, `sort_order`, `created_at`.

2. Security
- Row level security is enabled.
- Active monthly and annual members can read published items only.
- Admins (via the existing `is_edan_admin()` check) can read and write every item.
- Grants are limited to the `authenticated` role.

3. Seed data
- Three sample items are inserted so the Research section has content to display. Replace or remove them once real research is ready.

4. Notes
- Creation is idempotent, so the migration can be re-run safely.
*/

CREATE TABLE IF NOT EXISTS member_research_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 160),
  summary text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT '',
  image_path text NOT NULL DEFAULT '',
  read_more_url text NOT NULL DEFAULT '',
  is_published boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE member_research_items ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON member_research_items TO authenticated;

DROP POLICY IF EXISTS "members_select_published_research" ON member_research_items;
CREATE POLICY "members_select_published_research" ON member_research_items FOR SELECT
  TO authenticated USING (
    (is_published AND is_active_member(ARRAY['monthly', 'annual'])) OR is_edan_admin()
  );

DROP POLICY IF EXISTS "admins_insert_research" ON member_research_items;
CREATE POLICY "admins_insert_research" ON member_research_items FOR INSERT
  TO authenticated WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_update_research" ON member_research_items;
CREATE POLICY "admins_update_research" ON member_research_items FOR UPDATE
  TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_research" ON member_research_items;
CREATE POLICY "admins_delete_research" ON member_research_items FOR DELETE
  TO authenticated USING (is_edan_admin());

INSERT INTO member_research_items (title, summary, category, image_path, is_published, sort_order)
SELECT v.title, v.summary, v.category, v.image_path, true, v.sort_order
FROM (VALUES
  ('Sample: Notes on breeze-block light', 'A sample research note on how perforated walls shape light and airflow across a day.', 'Research note', '/images/breeze-block-detail.webp', 1),
  ('Sample: Dye pits and the colour of process', 'A sample creative insight on working with natural dyes, from preparation to the finished cloth.', 'Creative insight', '/images/dye-pits.jpg', 2),
  ('Sample: Mapping Accra in lines', 'A sample project note on drawing the city as a set of routes, edges and shared spaces.', 'Project publication', '/images/accra-map-lines.png', 3)
) AS v(title, summary, category, image_path, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM member_research_items);
