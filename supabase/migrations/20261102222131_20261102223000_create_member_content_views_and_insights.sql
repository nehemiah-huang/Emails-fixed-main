/*
# Track Members content activity and admin insights

1. New Tables
- `member_content_views`
- `id`: event identifier.
- `content_type`: gathering, research, process, bonus video, or page setting.
- `content_id`: optional published content identifier.
- `user_id`: signed-in active member who viewed the content.
- `created_at`: activity timestamp.

2. New Functions
- `admin_member_content_insights`: returns aggregated view counts and latest activity for admins.

3. Security
- Row-level security is enabled on `member_content_views`.
- Active monthly and annual members may insert events only for themselves.
- Only authenticated Ɛdan admins may read activity and call the insights function.
- Anonymous users cannot create member activity records.

4. Important Notes
- Activity is intentionally append-only from the member browser.
- The admin report aggregates by content type and content ID without exposing member identities.
- The report is limited to published member content through the function's server-side checks.
*/

CREATE TABLE IF NOT EXISTS public.member_content_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_type text NOT NULL CHECK (content_type IN ('gathering', 'research', 'process', 'bonus_video', 'page')),
  content_id uuid,
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS member_content_views_content_idx
  ON public.member_content_views (content_type, content_id, created_at DESC);

ALTER TABLE public.member_content_views ENABLE ROW LEVEL SECURITY;

GRANT INSERT ON public.member_content_views TO authenticated;

DROP POLICY IF EXISTS "active_members_insert_own_content_views" ON public.member_content_views;
CREATE POLICY "active_members_insert_own_content_views"
  ON public.member_content_views FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND is_active_member(ARRAY['monthly'::text, 'annual'::text])
  );

DROP FUNCTION IF EXISTS public.admin_member_content_insights();
CREATE OR REPLACE FUNCTION public.admin_member_content_insights()
RETURNS TABLE (
  content_type text,
  content_id uuid,
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
  SELECT v.content_type, v.content_id, count(*)::bigint, max(v.created_at)
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
