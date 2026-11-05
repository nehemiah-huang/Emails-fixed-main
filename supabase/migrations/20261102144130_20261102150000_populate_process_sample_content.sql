/*
# Populate In Process section with editorial sample content

1. Purpose
- Replaces generic placeholder rows with realistic editorial sample data so the In Process section
  renders all of its designed areas: hero, featured project, ongoing projects, project updates, and featured video.

2. Changes
- Existing generic sample rows are updated in-place to become proper project and update entries.
- A featured project ("The Osu Courtyard Project") is flagged with is_featured = true.
- Four ongoing project rows are created if they do not already exist.
- Two project update rows are created if they do not already exist.
- The existing video row is updated with richer copy.

3. Data safety
- No rows are deleted.
- Existing rows are updated by known stable titles using WHERE title = '...' to avoid touching
  any content the admin may have added manually.
- New rows use WHERE NOT EXISTS guards so the migration is safe to re-run.
*/

-- Upgrade the two seed rows into proper project entries
UPDATE member_process_items
SET
  title        = 'The Osu Courtyard Project',
  summary      = 'Exploring the social life of space in Accra''s historic neighbourhood.',
  body         = 'An ongoing study of how courtyard spaces in Osu are used, adapted, and negotiated by the people who live around them. We are mapping patterns of occupation, light, and edge conditions across several blocks.',
  category     = 'Spatial Research',
  image_path   = '/images/breeze-block-detail.webp',
  content_type = 'project',
  is_featured  = true,
  updated_label = 'Updated: Apr 2025',
  progress_label = '60% complete',
  link_url     = '#in-process',
  link_label   = 'View project',
  sort_order   = 1
WHERE title = 'Sample: The studio table';

UPDATE member_process_items
SET
  title        = 'Clay in the City',
  summary      = 'Exploring local materials for contemporary use.',
  body         = 'A hands-on investigation into laterite, clay, and compressed earth as building components. We are testing mixes, firing temperatures, and load-bearing capacity in the studio.',
  category     = 'Material Studies',
  image_path   = '/images/breeze-block-terracotta.jpg',
  content_type = 'project',
  is_featured  = false,
  updated_label = 'Mar 2025',
  progress_label = 'In progress',
  link_url     = '#in-process',
  link_label   = 'View project',
  sort_order   = 3
WHERE title = 'Sample: Notes on a wall that has weathered';

-- Additional ongoing project: Spatial Experiments
INSERT INTO member_process_items (
  title, summary, category, image_path, content_type,
  updated_label, progress_label, link_url, link_label,
  is_featured, is_published, sort_order
)
SELECT
  'Spatial Experiments',
  'Testing spatial ideas through low-cost models.',
  'Research',
  '/images/architectural_sketch2.png',
  'project',
  'Apr 2025', 'In progress',
  '#in-process', 'View project',
  false, true, 4
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items WHERE title = 'Spatial Experiments'
);

-- Additional ongoing project: Notes from the City
INSERT INTO member_process_items (
  title, summary, category, image_path, content_type,
  updated_label, progress_label, link_url, link_label,
  is_featured, is_published, sort_order
)
SELECT
  'Notes from the City',
  'Observations and insights gathered from Accra.',
  'Urban Studies',
  '/images/accra-map.png',
  'project',
  'Mar 2025', 'Ongoing',
  '#in-process', 'View project',
  false, true, 5
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items WHERE title = 'Notes from the City'
);

-- Additional ongoing project: Studio Explorations
INSERT INTO member_process_items (
  title, summary, category, image_path, content_type,
  updated_label, progress_label, link_url, link_label,
  is_featured, is_published, sort_order
)
SELECT
  'Studio Explorations',
  'Prototyping new spatial possibilities.',
  'Design Exploration',
  '/images/model-guesthouse.jpg',
  'project',
  'Apr 2025', 'In progress',
  '#in-process', 'View project',
  false, true, 6
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items WHERE title = 'Studio Explorations'
);

-- Project update 1: Studio visit
INSERT INTO member_process_items (
  title, summary, category, image_path, content_type,
  updated_label, is_published, sort_order
)
SELECT
  'Studio visit: Accra Urban Lab',
  'A recent visit to the Accra Urban Lab sparked new ideas for our ongoing work.',
  'Studio update',
  '/images/sharing.webp',
  'update',
  'Apr 10, 2025',
  true, 20
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items WHERE title = 'Studio visit: Accra Urban Lab'
);

-- Project update 2: Material tests
INSERT INTO member_process_items (
  title, summary, category, image_path, content_type,
  updated_label, is_published, sort_order
)
SELECT
  'Material tests underway',
  'We''re testing local materials for the next phase of our research.',
  'Studio update',
  '/images/architectural sketch.png',
  'update',
  'Mar 28, 2025',
  true, 21
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items WHERE title = 'Material tests underway'
);

-- Enrich the existing video row
UPDATE member_process_items
SET
  summary        = 'A look inside our studio and ongoing research at Ɛdan.',
  category       = 'Studio journal',
  image_path     = '/images/garden.jpg',
  poster_path    = '/images/garden.jpg',
  duration_label = '12:34',
  updated_label  = 'Featured',
  is_published   = true,
  sort_order     = 90
WHERE title = 'Research in Practice' AND content_type = 'video';