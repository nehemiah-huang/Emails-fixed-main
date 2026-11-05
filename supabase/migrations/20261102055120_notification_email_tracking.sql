/*
# Notification email tracking for membership submissions and stay bookings

1. Modified tables
- `membership_applications` gains `submission_emailed_at` (timestamptz, empty until the confirmation and admin alert emails are sent).
- `stay_bookings` gains `confirmation_emailed_at` (timestamptz, empty until the guest confirmation and admin alert emails are sent).

2. Purpose
- The email functions claim these timestamps before sending, so an email is never sent twice for the same application or booking, even if a request is retried.

3. Security
- No policy or grant changes. Only server-side functions (service role) write these columns.

4. Notes
- Statements are idempotent, so re-running this migration is safe. No data is removed.
*/

ALTER TABLE membership_applications ADD COLUMN IF NOT EXISTS submission_emailed_at timestamptz;
ALTER TABLE stay_bookings ADD COLUMN IF NOT EXISTS confirmation_emailed_at timestamptz;
