/*
# Expand In Process editorial content

1. Purpose
- Adds the metadata needed to present the Members In Process area as an editorial project archive while preserving all existing rows and content.

2. Modified table: `member_process_items`
- `content_type`: identifies whether an entry is a project, journal update, or featured video.
- `is_featured`: marks a project for the featured project area.
- `progress_label`: stores progress text such as `60% complete` or `In progress`.
- `updated_label`: stores the visible update date or period.
- `video_path`: stores an optional video path for featured video entries.
- `poster_path`: stores an optional video thumbnail path.
- `duration_label`: stores optional visible video duration text.
- `link_url`: stores an optional internal or external project link.
- `link_label`: stores the optional visible link label.

3. Data safety
- All new columns are nullable-safe through defaults and existing records remain intact.
- No rows, columns, tables, or existing policies are removed.

4. Security
- Existing row-level security, grants, and admin/member policies on `member_process_items` remain in force.
- Members continue to read only published content, while existing admin policies control writes.
*/

ALTER TABLE member_process_items
  ADD COLUMN IF NOT EXISTS content_type text NOT NULL DEFAULT 'project',
  ADD COLUMN IF NOT EXISTS is_featured boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS progress_label text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS updated_label text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS video_path text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS poster_path text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS duration_label text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS link_url text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS link_label text NOT NULL DEFAULT 'View project';

ALTER TABLE member_process_items
  DROP CONSTRAINT IF EXISTS member_process_items_content_type_check;

ALTER TABLE member_process_items
  ADD CONSTRAINT member_process_items_content_type_check
  CHECK (content_type IN ('project', 'update', 'video'));