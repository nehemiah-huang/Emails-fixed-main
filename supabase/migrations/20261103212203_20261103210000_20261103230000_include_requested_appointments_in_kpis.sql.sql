/*
# Count requested-date appointments in admin KPIs

1. Purpose
- Keep the admin dashboard appointment count aligned with both appointment booking modes.
- Count upcoming appointments that use an administrator-created slot and appointments that store a member-requested date and time.

2. Modified functions
- `admin_dashboard_kpis()` now counts active requested and confirmed appointments using either `member_appointment_slots.starts_at` or `member_appointments.requested_start_at`.

3. Tables and columns
- No tables or columns are added, removed, or changed.
- Existing `member_appointments.requested_start_at` values are included when `slot_id` is null.

4. Security
- The function remains `SECURITY DEFINER` and keeps its internal administrator check.
- Anonymous and public execution remain revoked.
- Authenticated execution remains available for the administrator dashboard.

5. Important notes
- Existing slot-backed appointments continue to be counted.
- No appointment rows are rewritten or deleted.
- The migration is safe to apply after the requested-date appointment migration.
*/

CREATE OR REPLACE FUNCTION public.admin_dashboard_kpis()
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT json_build_object(
    'active_members', (
      SELECT count(*) FROM memberships
      WHERE membership_status = 'active'
        AND (expires_at IS NULL OR expires_at > now())
    ),
    'pending_review', (
      SELECT count(*) FROM membership_applications
      WHERE status = 'pending'
    ),
    'expired', (
      SELECT count(*) FROM memberships
      WHERE membership_status = 'expired'
         OR (membership_status = 'active' AND expires_at IS NOT NULL AND expires_at <= now())
    ),
    'total_bookings', (
      SELECT count(*) FROM stay_bookings
      WHERE status IN ('confirmed', 'completed')
    ),
    'appointments', (
      SELECT count(*)
      FROM member_appointments a
      LEFT JOIN member_appointment_slots s ON s.id = a.slot_id
      WHERE a.status IN ('requested', 'confirmed')
        AND COALESCE(s.starts_at, a.requested_start_at) >= now()
    )
  ) INTO result;

  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_dashboard_kpis() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_kpis() TO authenticated;

NOTIFY pgrst, 'reload schema';