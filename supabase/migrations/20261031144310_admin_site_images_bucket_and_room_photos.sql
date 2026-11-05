/*
# Admin image uploads: site-images bucket and room photos

1. New storage bucket
- `site-images` holds photos uploaded by admins for the members page and room pages.
- Public-read bucket (images are shown on public and member pages).
- Limited to 5 MB per file and to JPEG, PNG, WebP, AVIF and GIF.

2. Modified tables
- `stay_rooms` gains `image_path` (text, default empty string). It stores the public web address of the room photo. Existing rows get an empty value. No data is removed.

3. Security
- Only admins (is_edan_admin()) can upload, replace or delete objects in `site-images`.
- Anonymous and signed-in non-admin accounts cannot write to the bucket.
- The room photo column is written only through the existing admin room update policy.

4. Notes
- Statements are idempotent, so re-running this migration is safe.
*/

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'site-images',
  'site-images',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/avif', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "admins_insert_site_images" ON storage.objects;
CREATE POLICY "admins_insert_site_images" ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'site-images' AND public.is_edan_admin());

DROP POLICY IF EXISTS "admins_update_site_images" ON storage.objects;
CREATE POLICY "admins_update_site_images" ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'site-images' AND public.is_edan_admin())
WITH CHECK (bucket_id = 'site-images' AND public.is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_site_images" ON storage.objects;
CREATE POLICY "admins_delete_site_images" ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'site-images' AND public.is_edan_admin());

ALTER TABLE public.stay_rooms ADD COLUMN IF NOT EXISTS image_path text NOT NULL DEFAULT '';
