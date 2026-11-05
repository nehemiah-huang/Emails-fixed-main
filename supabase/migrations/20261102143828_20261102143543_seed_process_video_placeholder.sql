/*
# Seed an In Process video placeholder

1. Purpose
- Adds one published editorial video placeholder so the new In Process page demonstrates its video area immediately.

2. Data
- Creates `Research in Practice` only when no In Process video with that title exists.
- Uses an existing site image as the thumbnail and leaves the video path empty so no fake player controls are shown.

3. Security
- The row uses the existing `member_process_items` table policies.
- Active monthly and annual members can read it when published; admins can manage it through the existing dashboard.

4. Data safety
- The insert is idempotent and does not modify or remove existing rows.
*/

INSERT INTO member_process_items (
  title,
  summary,
  category,
  image_path,
  poster_path,
  content_type,
  duration_label,
  updated_label,
  is_published,
  sort_order
)
SELECT
  'Research in Practice',
  'A look inside our studio and ongoing research at Ɛdan.',
  'Studio journal',
  '/images/garden.jpg',
  '/images/garden.jpg',
  'video',
  '12:34',
  'Featured',
  true,
  90
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items
  WHERE content_type = 'video' AND title = 'Research in Practice'
);