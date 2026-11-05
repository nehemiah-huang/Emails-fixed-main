/*
# Set safe limits for member media uploads

1. Modified Storage
- `site-videos`: allow MP4 and WebM uploads up to 30 MB.

2. Security
- Existing admin-only storage policies remain unchanged.

3. Important Notes
- The browser validates the same limits for usability, while the bucket enforces them at the storage boundary.
*/

UPDATE storage.buckets
SET file_size_limit = 31457280,
    allowed_mime_types = ARRAY['video/mp4', 'video/webm']::text[]
WHERE id = 'site-videos';
