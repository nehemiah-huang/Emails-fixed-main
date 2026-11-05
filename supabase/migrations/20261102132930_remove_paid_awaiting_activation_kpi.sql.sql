CREATE OR REPLACE FUNCTION admin_dashboard_kpis()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'Admins only' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'active_members', (
      SELECT count(*)::int FROM memberships
      WHERE membership_status = 'active' AND (expires_at IS NULL OR expires_at > now())
    ),
    'pending_review', (
      SELECT count(*)::int FROM membership_applications
      WHERE status = 'pending' AND submitted_at IS NOT NULL
    ),
    'expired', (
      SELECT count(*)::int FROM memberships
      WHERE membership_status = 'expired'
         OR (membership_status = 'active' AND expires_at IS NOT NULL AND expires_at <= now())
    ),
    'total_bookings', (
      SELECT count(*)::int FROM stay_bookings
      WHERE status IN ('confirmed', 'completed')
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_dashboard_kpis() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_dashboard_kpis() TO authenticated;

NOTIFY pgrst, 'reload schema';
