/*
# Members access helper runs with the caller's permissions

1. Modified Functions
- `is_active_member(tiers text[])` now runs as the calling user instead of its owner.

2. Security
- The function only reads the caller's own membership row, which the memberships policy already allows, so it does not need elevated rights.
- Running as the caller removes the need to grant a privileged function to signed-in users.
*/

CREATE OR REPLACE FUNCTION is_active_member(tiers text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM memberships m
    WHERE m.user_id = auth.uid()
      AND m.membership_status = 'active'
      AND m.membership_tier = ANY (tiers)
      AND (m.expires_at IS NULL OR m.expires_at > now())
  );
$$;
