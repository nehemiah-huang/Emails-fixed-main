/*
# Synchronize member appointment samples and API visibility

1. Purpose
- Keep the database aligned with the appointment choices used by the Members booking page.
- Add any missing sample appointment types without duplicating existing records.
- Refresh the Supabase Data API schema cache so the appointment tables remain visible to the website.

2. Existing tables used
- `member_appointment_types`: receives the four standard sample appointment choices.
- `member_appointment_slots`: not changed.
- `member_appointments`: not changed.

3. Sample content
- Introductory Conversation.
- Research Consultation.
- Creative Working Session.
- Membership Support.

4. Security
- No permissions or row-level security policies are widened.
- No appointment bookings or availability slots are created.
- Existing annual-member and administrator access rules remain unchanged.

5. Important notes
- The insert is idempotent and matches by appointment title, so it is safe to run again.
- Real booking still requires future availability slots created by an authorized administrator.
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