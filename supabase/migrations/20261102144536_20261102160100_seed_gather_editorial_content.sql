/*
# Seed Gather editorial sample content

1. Purpose
- Populates the Gather page with realistic placeholder content for its featured gathering,
  upcoming programme, past archive, and community moments areas.

2. Data
- All rows are marked published so active members can see the complete design immediately.
- Images use existing site assets and can be replaced by an administrator later.
- No real ticket prices, confirmed speakers, or invented event commitments are included.

3. Data safety
- Every insert is guarded by a title check and is safe to re-run.
- No existing rows are deleted or modified.

4. Security
- Rows use the existing member_gatherings RLS policies.
*/

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Conversations Around the City',
  'A dialogue on urban life, creativity and belonging in Accra.',
  NULL,
  'Ɛdan, Osu',
  '/images/garden-eat.jpg',
  '', true, 1, 'Featured gathering', 'upcoming', true, ''
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Conversations Around the City'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Material Encounters',
  'Explore materials, techniques and possibilities through an afternoon of making.',
  NULL,
  'Ɛdan, Osu',
  '/images/breeze-block-terracotta.jpg',
  '', true, 3, 'Workshop', 'upcoming', false, ''
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Material Encounters'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Shared Tables',
  'Food, ideas and community around one long table.',
  NULL,
  'Ɛdan, Osu',
  '/images/sharing.webp',
  '', true, 4, 'Talk', 'upcoming', false, ''
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Shared Tables'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Creative Research Gatherings',
  'A community forum for creative researchers and practitioners.',
  NULL,
  'Ɛdan, Osu',
  '/images/garden.jpg',
  '', true, 5, 'Gathering', 'upcoming', false, ''
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Creative Research Gatherings'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Open Studio Sessions',
  '', NULL, 'Ɛdan, Osu', '/images/our story people.jpg', '',
  true, 20, 'Archive', 'past', false, 'A day of shared practice and conversation.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Open Studio Sessions'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'A Table for Many Voices',
  '', NULL, 'Ɛdan, Osu', '/images/eat-hero.jpg', '',
  true, 21, 'Archive', 'past', false, 'An evening of food, stories and new connections.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'A Table for Many Voices'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Making Together',
  '', NULL, 'Ɛdan, Osu', '/images/dye-pits.jpg', '',
  true, 22, 'Archive', 'past', false, 'Hands, materials, and a few hours in the studio.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Making Together'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Ideas at the Table', '', NULL, '', '/images/architectural sketch.png', '',
  true, 30, 'Community moment', 'moment', false, 'Ideas taking shape.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Ideas at the Table'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'A Shared Afternoon', '', NULL, '', '/images/sharing.webp', '',
  true, 31, 'Community moment', 'moment', false, 'A slower afternoon at Ɛdan.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'A Shared Afternoon'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Outside Together', '', NULL, '', '/images/garden-eat.jpg', '',
  true, 32, 'Community moment', 'moment', false, 'The courtyard in conversation.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Outside Together'
);