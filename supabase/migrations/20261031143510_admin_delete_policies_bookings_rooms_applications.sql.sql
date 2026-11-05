/*
# Admin delete policies for bookings, rooms and membership applications

1. Changes
- Adds admin-only DELETE policies so the dashboard can remove records.
- stay_bookings: admins may delete only bookings that were never paid or were cancelled, pending_payment, payment_failed or cancelled. Confirmed and completed bookings must be cancelled first, which keeps payment history.
- stay_rooms: admins may delete a room. The existing foreign key from bookings to rooms is RESTRICT, so rooms with any booking cannot be removed. Blocked dates for the room are removed with it (cascade).
- membership_applications: admins may delete applications that are pending or rejected. Approved applications are kept because they link to membership and payment history.

2. Security
- Every policy requires is_edan_admin(), so non-admin accounts cannot delete anything.
- Policies are idempotent (DROP POLICY IF EXISTS before CREATE).
- No table or column changes; no data is removed by this migration itself.

3. Notes
- Grants already give the authenticated role DELETE on these tables; RLS limits which rows it can remove.
*/

DROP POLICY IF EXISTS "admins_delete_stay_bookings" ON public.stay_bookings;
CREATE POLICY "admins_delete_stay_bookings" ON public.stay_bookings FOR DELETE
TO authenticated
USING (
  public.is_edan_admin()
  AND status IN ('pending_payment', 'payment_failed', 'cancelled')
);

DROP POLICY IF EXISTS "admins_delete_stay_rooms" ON public.stay_rooms;
CREATE POLICY "admins_delete_stay_rooms" ON public.stay_rooms FOR DELETE
TO authenticated
USING (public.is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_membership_applications" ON public.membership_applications;
CREATE POLICY "admins_delete_membership_applications" ON public.membership_applications FOR DELETE
TO authenticated
USING (
  public.is_edan_admin()
  AND status IN ('pending', 'rejected')
);
