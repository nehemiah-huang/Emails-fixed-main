/*
# Harden browser access to public tables and admin functions

1. Purpose
- The live database had accumulated broad table grants for both browser roles.
- Row-level security still blocked most unauthorized rows, but the grants were wider than the application requires and created unnecessary exposure if a policy were ever added accidentally.
- One admin dashboard function was also executable by anonymous callers because a later function replacement restored the default EXECUTE grant.

2. Modified access
- Revoke all table privileges from `anon` and `authenticated` across the public schema.
- Restore only the table operations used by the current website.
- Keep internal payment, webhook, notification, and reminder tables inaccessible to browser roles.
- Keep service-role access unchanged for server-side functions.

3. Restored browser operations
- Anonymous visitors may insert `video_views` and call the public room-availability function.
- Signed-in users may read their own/member-visible data and use the existing admin or member workflows.
- Direct writes remain limited to tables whose existing RLS policies already restrict them to the signed-in user or an administrator.

4. Function security
- Revoke anonymous EXECUTE on `admin_dashboard_kpis()`.
- Grant it only to authenticated callers; its existing function-level admin check remains in place.

5. Important notes
- No rows, columns, tables, policies, or stored values are deleted.
- RLS policies remain the row-level authorization boundary.
- This migration changes privileges only; existing application behavior is preserved through explicit grants below.
*/

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM anon, authenticated;

GRANT SELECT ON public.admins TO authenticated;
GRANT SELECT ON public.memberships TO authenticated;
GRANT INSERT, SELECT ON public.video_views TO anon, authenticated;
GRANT INSERT, SELECT ON public.video_uploads TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.membership_applications TO authenticated;
GRANT SELECT ON public.payment_transactions TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.stay_rooms TO authenticated;
GRANT SELECT, DELETE ON public.stay_bookings TO authenticated;
GRANT SELECT, DELETE ON public.stay_room_blocks TO authenticated;

GRANT SELECT, INSERT, UPDATE ON public.member_chat_profiles TO authenticated;
GRANT SELECT, INSERT ON public.member_chat_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.member_gatherings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.member_bonus_videos TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.member_research_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.member_process_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.member_appointment_types TO authenticated;
GRANT SELECT ON public.member_appointment_slots TO authenticated;
GRANT SELECT ON public.member_appointments TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.member_page_settings TO authenticated;
GRANT INSERT ON public.member_content_views TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_dashboard_kpis() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_kpis() TO authenticated;

NOTIFY pgrst, 'reload schema';