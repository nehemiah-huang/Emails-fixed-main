/*
# Store the Paystack access code on Stay bookings

1. Modified tables
- `stay_bookings`: new column `paystack_access_code` (text, nullable). Paystack returns this code when a payment is started, and the Paystack checkout window needs it to open.

2. Security
- No policy or grant changes. The guest policy already limits reads to the guest's own bookings, and only the server writes this column.

3. Notes
- Existing rows keep a null value. Bookings created before this change have no checkout window to resume.
*/

ALTER TABLE stay_bookings ADD COLUMN IF NOT EXISTS paystack_access_code text;
