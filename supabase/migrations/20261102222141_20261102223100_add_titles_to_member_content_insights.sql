/*
# Add readable titles to Members activity insights

1. Modified Functions
- `admin_member_content_insights` now returns `content_title` alongside the content type, identifier, count, and latest view time.

2. Security
- The function remains SECURITY DEFINER and callable only by authenticated Ɛdan admins.

3. Important Notes
- Titles are resolved only from published member content.
- Page-level activity is labelled `Members page`.
*/

DROP FUNCTION IF EXISTS public.admin_member_content_insights();
CREATE OR REPLACE FUNCTION public.admin_member_content_insights()
RETURNS TABLE (
  content_type text,
  content_id uuid,
  content_title text,
  view_count bigint,
  last_viewed_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  RETURN QUERY
  SELECT
    v.content_type,
    v.content_id,
    CASE v.content_type
      WHEN 'gathering' THEN (SELECT g.title FROM public.member_gatherings g WHERE g.id = v.content_id AND g.is_published)
      WHEN 'research' THEN (SELECT r.title FROM public.member_research_items r WHERE r.id = v.content_id AND r.is_published)
      WHEN 'process' THEN (SELECT p.title FROM public.member_process_items p WHERE p.id = v.content_id AND p.is_published)
      WHEN 'bonus_video' THEN (SELECT b.title FROM public.member_bonus_videos b WHERE b.id = v.content_id AND b.is_published)
      ELSE 'Members page'
    END,
    count(*)::bigint,
    max(v.created_at)
  FROM public.member_content_views v
  WHERE (
    (v.content_type = 'gathering' AND EXISTS (SELECT 1 FROM public.member_gatherings g WHERE g.id = v.content_id AND g.is_published))
    OR (v.content_type = 'research' AND EXISTS (SELECT 1 FROM public.member_research_items r WHERE r.id = v.content_id AND r.is_published))
    OR (v.content_type = 'process' AND EXISTS (SELECT 1 FROM public.member_process_items p WHERE p.id = v.content_id AND p.is_published))
    OR (v.content_type = 'bonus_video' AND EXISTS (SELECT 1 FROM public.member_bonus_videos b WHERE b.id = v.content_id AND b.is_published))
    OR v.content_type = 'page'
  )
  GROUP BY v.content_type, v.content_id
  ORDER BY count(*) DESC, max(v.created_at) DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_member_content_insights() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_member_content_insights() TO authenticated;
