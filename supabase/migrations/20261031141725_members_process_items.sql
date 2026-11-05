/*
# Members in-process items

1. New Tables
- `member_process_items`: work-in-progress notes shown in the In Process section of the Members page.
  - `title`, `summary`, `body`, `category`, `image_path`, `is_published`, `sort_order`, `created_at`.

2. Security
- Row level security is enabled.
- Active monthly and annual members can read published items only.
- Admins (via the existing `is_edan_admin()` check) can read and write every item.
- Grants are limited to the `authenticated` role.

3. Seed data
- Two sample items are inserted so the In Process section has content to review. Replace or remove them once real work is ready.

4. Research sample
- One additional sample research item is added so the Research section shows more than one layout pattern.

5. Notes
- Creation and seeding are idempotent, so the migration can be re-run safely.
*/

CREATE TABLE IF NOT EXISTS member_process_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 160),
  summary text NOT NULL DEFAULT '',
  body text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT '',
  image_path text NOT NULL DEFAULT '',
  is_published boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE member_process_items ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON member_process_items TO authenticated;

DROP POLICY IF EXISTS "members_select_published_process" ON member_process_items;
CREATE POLICY "members_select_published_process" ON member_process_items FOR SELECT
  TO authenticated USING (
    (is_published AND is_active_member(ARRAY['monthly', 'annual'])) OR is_edan_admin()
  );

DROP POLICY IF EXISTS "admins_insert_process" ON member_process_items;
CREATE POLICY "admins_insert_process" ON member_process_items FOR INSERT
  TO authenticated WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_update_process" ON member_process_items;
CREATE POLICY "admins_update_process" ON member_process_items FOR UPDATE
  TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_process" ON member_process_items;
CREATE POLICY "admins_delete_process" ON member_process_items FOR DELETE
  TO authenticated USING (is_edan_admin());

INSERT INTO member_process_items (title, summary, body, category, image_path, is_published, sort_order)
SELECT v.title, v.summary, v.body, v.category, v.image_path, true, v.sort_order
FROM (VALUES
  ('Sample: The studio table', 'A sample note on how the team gathers around one table to test ideas before they become drawings.', 'Sample text for review. Replace with a real studio note.

The studio table is where most ideas first meet a second opinion. Sketches, half-written notes and material samples sit side by side, and a conversation usually decides what goes forward.

This sample shows how a longer in-process note reads inside the members space.', 'Studio notes', '/images/sharing.webp', 1),
  ('Sample: Notes on a wall that has weathered', 'A sample observation on plants and paint loss along an old wall, and what they reveal about materials over time.', 'Sample text for review. Replace with a real observation.

Walls keep a record of the weather they have stood through. Where paint has lifted and a plant has found a crack, the surface tells us how water moves and where it settles.

This sample shows how a research-style in-process note is presented.', 'Field notes', '/images/garden-plant.jpg', 2)
) AS v(title, summary, body, category, image_path, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM member_process_items);

INSERT INTO member_research_items (title, summary, body, category, image_path, is_published, sort_order)
SELECT 'Sample: Plants that find the cracks', 'A sample research note on how planting and weathering interact along the edges of a building.', 'Sample text for review. Replace with a real research note.

Cracks in a rendered wall are small thresholds. Seeds and roots find them first, and over several seasons they change how the wall holds moisture.

Recording these changes is one way the studio tests materials against the conditions they actually face.', 'Research note', '/images/garden-plant.jpg', true, 4
WHERE NOT EXISTS (SELECT 1 FROM member_research_items WHERE title = 'Sample: Plants that find the cracks');
