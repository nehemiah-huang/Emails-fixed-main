/*
# Refresh appointment API visibility and seed sample appointment types

1. Purpose
- Refresh the Supabase Data API schema cache so the existing appointment tables are visible to the Members page.
- Ensure the four appointment types from the design reference are available without creating duplicates.

2. Existing tables used
- `member_appointment_types`
- `member_appointment_slots`
- `member_appointments`

3. Sample content
- Introductory Conversation
- Research Consultation
- Creative Working Session
- Membership Support

4. Security
- No access policies are changed.
- No user, booking, or availability records are created.
- Appointment types remain protected by the existing annual-member and administrator policies.

5. Important note
- This migration makes the appointment choices visible. Real booking still requires future availability slots created by an authorized administrator.
*/

INSERT INTO public.member_appointment_types (title, description, duration_minutes, is_active, sort_order)
SELECT sample.title, sample.description, sample.duration_minutes, true, sample.sort_order
FROM (VALUES
  ('Introductory Conversation', 'A chance to meet the team, learn more about Ɛdan and explore possible ways to get involved.', 60, 1),
  ('Research Consultation', 'A focused conversation around research interests, questions, ideas or ongoing work.', 60, 2),
  ('Creative Working Session', 'Dedicated time to discuss, develop or work through a creative idea or project.', 90, 3),
  ('Membership Support', 'A session for questions about membership, access or using the space.', 30, 4)
) AS sample(title, description, duration_minutes, sort_order)
WHERE NOT EXISTS (
  SELECT 1
  FROM public.member_appointment_types existing
  WHERE existing.title = sample.title
);

NOTIFY pgrst, 'reload schema';