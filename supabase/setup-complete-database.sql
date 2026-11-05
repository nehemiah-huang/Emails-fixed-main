-- Ɛdan consolidated Supabase setup
-- Generated from supabase/migrations in filename order.
-- Apply this file only to a fresh project. Existing projects should use individual migrations.

-- SOURCE MIGRATION: 20261029114859_create_admins_and_site_video_bucket.sql
/*
# Admin list and public site-video bucket

1. New Tables
- `admins`: one row per Edan team member allowed into the dashboard. `user_id` points at the signed-in account.

2. Security
- RLS enabled on `admins`. Signed-in users can read only their own row. Nobody can change the list from the app; rows are added by the team directly in the database.
- `is_edan_admin()` returns true when the current signed-in user has an `admins` row. Callable by signed-in users only.
- New public storage bucket `site-videos` for the homepage hero video. Anyone can read files; only admins can upload, replace or delete them.
*/

CREATE TABLE IF NOT EXISTS admins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE admins ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON admins TO authenticated;

DROP POLICY IF EXISTS "select_own_admin_row" ON admins;
CREATE POLICY "select_own_admin_row" ON admins FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION is_edan_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM admins WHERE user_id = auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION is_edan_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION is_edan_admin() TO authenticated;

INSERT INTO storage.buckets (id, name, public)
VALUES ('site-videos', 'site-videos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "admins_insert_site_videos" ON storage.objects;
CREATE POLICY "admins_insert_site_videos" ON storage.objects FOR INSERT
  TO authenticated WITH CHECK (bucket_id = 'site-videos' AND is_edan_admin());

DROP POLICY IF EXISTS "admins_update_site_videos" ON storage.objects;
CREATE POLICY "admins_update_site_videos" ON storage.objects FOR UPDATE
  TO authenticated USING (bucket_id = 'site-videos' AND is_edan_admin())
  WITH CHECK (bucket_id = 'site-videos' AND is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_site_videos" ON storage.objects;
CREATE POLICY "admins_delete_site_videos" ON storage.objects FOR DELETE
  TO authenticated USING (bucket_id = 'site-videos' AND is_edan_admin());


-- SOURCE MIGRATION: 20261029115208_create_memberships_views_and_upload_log.sql
/*
# Memberships, homepage video views and video upload log

1. New Tables
- `memberships`: one row per member. Rows are added by the membership sign-up/payment process, not by the app's visitors.
- `video_views`: one row per homepage hero video play. Only the count is used.
- `video_uploads`: one row per hero video upload made from the dashboard.

2. Security
- `memberships`: members can read their own row; admins can read all rows. No client writes.
- `video_views`: anyone visiting the site can add a row; only admins can read them.
- `video_uploads`: admins can add rows, recorded under their own account; admins can read them.
*/

CREATE TABLE IF NOT EXISTS memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  member_email text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON memberships TO authenticated;

DROP POLICY IF EXISTS "select_own_membership" ON memberships;
CREATE POLICY "select_own_membership" ON memberships FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "admins_select_memberships" ON memberships;
CREATE POLICY "admins_select_memberships" ON memberships FOR SELECT
  TO authenticated USING (is_edan_admin());

CREATE TABLE IF NOT EXISTS video_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE video_views ENABLE ROW LEVEL SECURITY;

GRANT INSERT ON video_views TO anon, authenticated;
GRANT SELECT ON video_views TO authenticated;

DROP POLICY IF EXISTS "anyone_insert_video_views" ON video_views;
CREATE POLICY "anyone_insert_video_views" ON video_views FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "admins_select_video_views" ON video_views;
CREATE POLICY "admins_select_video_views" ON video_views FOR SELECT
  TO authenticated USING (is_edan_admin());

CREATE TABLE IF NOT EXISTS video_uploads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uploaded_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE SET NULL,
  file_name text NOT NULL,
  size_bytes bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE video_uploads ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON video_uploads TO authenticated;

DROP POLICY IF EXISTS "admins_insert_video_uploads" ON video_uploads;
CREATE POLICY "admins_insert_video_uploads" ON video_uploads FOR INSERT
  TO authenticated WITH CHECK (is_edan_admin() AND uploaded_by = auth.uid());

DROP POLICY IF EXISTS "admins_select_video_uploads" ON video_uploads;
CREATE POLICY "admins_select_video_uploads" ON video_uploads FOR SELECT
  TO authenticated USING (is_edan_admin());


-- SOURCE MIGRATION: 20261029120202_membership_applications_and_review_functions.sql
/*
# Membership applications and admin review

1. Memberships
- Adds the columns the member pages already read: tier (monthly or annual), membership status, start and end dates.
- One membership row per member, so approvals and renewals update the same row.

2. New Table
- `membership_applications`: one row per membership application, linked to the applicant's account. Starts as pending.

3. Functions
- `approve_membership_application`: admin-only. Marks the application approved and sets the member's tier and dates, in one step.
- `reject_membership_application`: admin-only. Marks the application rejected.

4. Security
- Applicants can read their own applications; admins can read all of them.
- Nobody can change applications or memberships directly; changes go through the two functions.
*/

ALTER TABLE memberships
  ADD COLUMN IF NOT EXISTS membership_tier text CHECK (membership_tier IN ('monthly', 'annual')),
  ADD COLUMN IF NOT EXISTS membership_status text NOT NULL DEFAULT 'pending'
    CHECK (membership_status IN ('pending', 'active', 'expired', 'rejected')),
  ADD COLUMN IF NOT EXISTS started_at timestamptz,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS memberships_user_id_key ON memberships (user_id);

CREATE TABLE IF NOT EXISTS membership_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  applicant_email text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

ALTER TABLE membership_applications ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON membership_applications TO authenticated;

DROP POLICY IF EXISTS "select_own_membership_application" ON membership_applications;
CREATE POLICY "select_own_membership_application" ON membership_applications FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "admins_select_membership_applications" ON membership_applications;
CREATE POLICY "admins_select_membership_applications" ON membership_applications FOR SELECT
  TO authenticated USING (is_edan_admin());

CREATE OR REPLACE FUNCTION approve_membership_application(
  p_application_id uuid,
  p_tier text,
  p_started_at timestamptz,
  p_expires_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  app membership_applications%ROWTYPE;
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501';
  END IF;

  IF p_tier NOT IN ('monthly', 'annual') THEN
    RAISE EXCEPTION 'Choose monthly or annual membership';
  END IF;

  IF p_started_at IS NULL OR p_expires_at IS NULL OR p_expires_at <= p_started_at THEN
    RAISE EXCEPTION 'The end date must be after the start date';
  END IF;

  SELECT * INTO app FROM membership_applications WHERE id = p_application_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  IF app.status <> 'pending' THEN
    RAISE EXCEPTION 'This application has already been reviewed';
  END IF;

  INSERT INTO memberships (user_id, member_email, membership_tier, membership_status, started_at, expires_at)
  VALUES (app.user_id, app.applicant_email, p_tier, 'active', p_started_at, p_expires_at)
  ON CONFLICT (user_id) DO UPDATE SET
    member_email = EXCLUDED.member_email,
    membership_tier = EXCLUDED.membership_tier,
    membership_status = 'active',
    started_at = EXCLUDED.started_at,
    expires_at = EXCLUDED.expires_at;

  UPDATE membership_applications
  SET status = 'approved', reviewed_at = now(), reviewed_by = auth.uid()
  WHERE id = app.id;
END;
$$;

CREATE OR REPLACE FUNCTION reject_membership_application(p_application_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  app membership_applications%ROWTYPE;
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO app FROM membership_applications WHERE id = p_application_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  IF app.status <> 'pending' THEN
    RAISE EXCEPTION 'This application has already been reviewed';
  END IF;

  UPDATE membership_applications
  SET status = 'rejected', reviewed_at = now(), reviewed_by = auth.uid()
  WHERE id = app.id;
END;
$$;

REVOKE EXECUTE ON FUNCTION approve_membership_application(uuid, text, timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION approve_membership_application(uuid, text, timestamptz, timestamptz) TO authenticated;

REVOKE EXECUTE ON FUNCTION reject_membership_application(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reject_membership_application(uuid) TO authenticated;


-- SOURCE MIGRATION: 20261029121053_membership_application_tier_and_applicant_insert.sql.sql
ALTER TABLE membership_applications
  ADD COLUMN IF NOT EXISTS membership_tier text CHECK (membership_tier IN ('monthly', 'annual'));

GRANT INSERT ON membership_applications TO authenticated;

DROP POLICY IF EXISTS "insert_own_pending_membership_application" ON membership_applications;
CREATE POLICY "insert_own_pending_membership_application" ON membership_applications FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id AND status = 'pending');


-- SOURCE MIGRATION: 20261029121822_paystack_payment_transactions_and_webhook_events.sql
/*
# Paystack payment records and webhook event log for Gather memberships

1. New Tables
- `payment_transactions`: one row per membership payment attempt. Stores the unique payment reference, the linked membership application, the plan, the expected amount in pesewas and the currency, and the payment status.
- `paystack_events`: one row per distinct webhook delivery (keyed by a hash of the raw request body). Used for duplicate detection and audit.

2. New Function
- `record_paystack_event`: the only way a payment becomes successful. Runs in one transaction: locks the matching payment row, checks it has not already been recorded, checks the verified amount and currency, updates the payment, and logs the event.

3. Security
- `payment_transactions`: members can read their own payments; admins can read all. No client writes.
- `paystack_events`: row level security on with no client grants. Only the function above touches it.
- `record_paystack_event`: callable only by the server (service role). Not callable by browsers.

4. Notes
- Payment success never approves a membership. Approval stays with the admin review functions.
- Repeated or simultaneous deliveries for the same reference are safe: the row lock and status check allow only one success.
*/

CREATE TABLE IF NOT EXISTS payment_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text NOT NULL UNIQUE,
  membership_application_id uuid NOT NULL REFERENCES membership_applications(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan text NOT NULL CHECK (plan IN ('monthly', 'annual')),
  amount_pesewas integer NOT NULL CHECK (amount_pesewas > 0),
  currency text NOT NULL DEFAULT 'GHS' CHECK (currency = 'GHS'),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'success', 'failed', 'abandoned')),
  paystack_transaction_id bigint UNIQUE,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payment_transactions_application_id_idx ON payment_transactions (membership_application_id);
CREATE INDEX IF NOT EXISTS payment_transactions_user_id_idx ON payment_transactions (user_id);

ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON payment_transactions TO authenticated;

DROP POLICY IF EXISTS "select_own_payment_transactions" ON payment_transactions;
CREATE POLICY "select_own_payment_transactions" ON payment_transactions FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "admins_select_payment_transactions" ON payment_transactions;
CREATE POLICY "admins_select_payment_transactions" ON payment_transactions FOR SELECT
  TO authenticated USING (is_edan_admin());

CREATE TABLE IF NOT EXISTS paystack_events (
  event_key text PRIMARY KEY,
  event_type text NOT NULL,
  reference text,
  outcome text NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE paystack_events ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION record_paystack_event(
  p_event_key text,
  p_event_type text,
  p_reference text,
  p_verified_transaction_id bigint,
  p_verified_amount_pesewas integer,
  p_verified_currency text,
  p_verified_paid_at timestamptz
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pay payment_transactions%ROWTYPE;
  result text;
BEGIN
  IF p_event_type <> 'charge.success' OR p_reference IS NULL THEN
    result := 'ignored';
  ELSE
    SELECT * INTO pay FROM payment_transactions WHERE reference = p_reference FOR UPDATE;

    IF NOT FOUND THEN
      result := 'unmatched';
    ELSIF pay.status = 'success' THEN
      result := 'already_recorded';
    ELSIF p_verified_amount_pesewas IS DISTINCT FROM pay.amount_pesewas
      OR p_verified_currency IS DISTINCT FROM pay.currency THEN
      result := 'amount_mismatch';
    ELSE
      UPDATE payment_transactions
      SET status = 'success',
          paystack_transaction_id = p_verified_transaction_id,
          paid_at = p_verified_paid_at,
          updated_at = now()
      WHERE id = pay.id;
      result := 'recorded';
    END IF;
  END IF;

  INSERT INTO paystack_events (event_key, event_type, reference, outcome)
  VALUES (p_event_key, p_event_type, p_reference, result)
  ON CONFLICT (event_key) DO NOTHING;

  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION record_paystack_event(text, text, text, bigint, integer, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION record_paystack_event(text, text, text, bigint, integer, text, timestamptz) TO service_role;


-- SOURCE MIGRATION: 20261029121849_paystack_event_not_successful_outcome.sql
/*
# Clearer outcome for Paystack events that did not succeed

1. Modified Function
- `record_paystack_event`: when Paystack's verification reports that the charge did not succeed, the event is logged with the outcome `not_successful` instead of being reported as an amount mismatch. Payment status is left unchanged.

2. Security
- Unchanged: the function stays server-only (service role).
*/

CREATE OR REPLACE FUNCTION record_paystack_event(
  p_event_key text,
  p_event_type text,
  p_reference text,
  p_verified_transaction_id bigint,
  p_verified_amount_pesewas integer,
  p_verified_currency text,
  p_verified_paid_at timestamptz
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pay payment_transactions%ROWTYPE;
  result text;
BEGIN
  IF p_event_type <> 'charge.success' OR p_reference IS NULL THEN
    result := 'ignored';
  ELSE
    SELECT * INTO pay FROM payment_transactions WHERE reference = p_reference FOR UPDATE;

    IF NOT FOUND THEN
      result := 'unmatched';
    ELSIF p_verified_transaction_id IS NULL THEN
      result := 'not_successful';
    ELSIF pay.status = 'success' THEN
      result := 'already_recorded';
    ELSIF p_verified_amount_pesewas IS DISTINCT FROM pay.amount_pesewas
      OR p_verified_currency IS DISTINCT FROM pay.currency THEN
      result := 'amount_mismatch';
    ELSE
      UPDATE payment_transactions
      SET status = 'success',
          paystack_transaction_id = p_verified_transaction_id,
          paid_at = p_verified_paid_at,
          updated_at = now()
      WHERE id = pay.id;
      result := 'recorded';
    END IF;
  END IF;

  INSERT INTO paystack_events (event_key, event_type, reference, outcome)
  VALUES (p_event_key, p_event_type, p_reference, result)
  ON CONFLICT (event_key) DO NOTHING;

  RETURN result;
END;
$$;


-- SOURCE MIGRATION: 20261029122534_payment_receipt_sent_tracking.sql
/*
# Track when a payment receipt email was sent

1. Modified Table
- `payment_transactions`: adds `receipt_sent_at`, set once the receipt email for a verified payment has been sent. Empty means no receipt has gone out yet.

2. Security
- The server (service role) may read payment rows and set only `receipt_sent_at`. Nothing else in the row is writable by it through this grant.
- Browsers still have no write access to payments.

3. Notes
- Lets a retried webhook delivery send the receipt if an earlier attempt failed, without ever sending it twice.
*/

ALTER TABLE payment_transactions
  ADD COLUMN IF NOT EXISTS receipt_sent_at timestamptz;

GRANT SELECT ON payment_transactions TO service_role;
GRANT UPDATE (receipt_sent_at) ON payment_transactions TO service_role;


-- SOURCE MIGRATION: 20261030102540_create_stay_rooms_bookings_and_blocks.sql
/*
# Stay rooms, bookings and room blocks

1. New Tables
- `stay_rooms`: one row per individual room. Names are entered by the team in the dashboard; no names are assumed.
- `stay_bookings`: one row per stay. Holds dates, guests, breakfast choice, nightly rate, total, status, source (online or manual) and guest contact details.
- `stay_room_blocks`: date ranges the team closes off for a room (maintenance, owner use, etc.).

2. Constraints
- A room can have at most one confirmed or completed booking covering any night (enforced by the database, including simultaneous inserts).
- Blocks cannot overlap each other for the same room.
- Total must equal nights multiplied by the nightly rate. Guests must be 1 or 2. Check-out must be after check-in.

3. Security
- RLS enabled on all three tables.
- Only team admins (via `is_edan_admin()`) can read bookings, rooms and blocks, or change rooms.
- Bookings and blocks are created only through the admin functions added in the next migration, so overlap checks always run on the server.
- No public access yet; the public Stay availability check will be added with the guest booking flow.

4. Notes
- Nothing existing is modified. These tables are new.
- Gather membership and payment tables are not touched.
*/

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE IF NOT EXISTS stay_rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 80),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT stay_rooms_name_unique UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS stay_bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_reference text NOT NULL UNIQUE
    DEFAULT ('EDN-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  room_id uuid NOT NULL REFERENCES stay_rooms(id) ON DELETE RESTRICT,
  check_in date NOT NULL,
  check_out date NOT NULL,
  guests smallint NOT NULL CHECK (guests BETWEEN 1 AND 2),
  breakfast_included boolean NOT NULL DEFAULT false,
  nightly_rate_ghs integer NOT NULL CHECK (nightly_rate_ghs > 0),
  total_ghs integer NOT NULL CHECK (total_ghs > 0),
  status text NOT NULL DEFAULT 'confirmed'
    CHECK (status IN ('pending_payment', 'confirmed', 'cancelled', 'completed', 'payment_failed')),
  source text NOT NULL CHECK (source IN ('online', 'manual')),
  guest_name text NOT NULL CHECK (length(btrim(guest_name)) > 0),
  guest_email text NOT NULL CHECK (length(btrim(guest_email)) > 0),
  guest_phone text NOT NULL CHECK (length(btrim(guest_phone)) > 0),
  notes text NOT NULL DEFAULT '',
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  cancelled_at timestamptz,
  CONSTRAINT stay_bookings_dates_valid CHECK (check_out > check_in),
  CONSTRAINT stay_bookings_total_matches_nights
    CHECK (total_ghs = (check_out - check_in) * nightly_rate_ghs),
  CONSTRAINT stay_bookings_no_overlap EXCLUDE USING gist (
    room_id WITH =,
    daterange(check_in, check_out, '[)') WITH &&
  ) WHERE (status IN ('confirmed', 'completed'))
);

CREATE INDEX IF NOT EXISTS stay_bookings_check_in_idx ON stay_bookings (check_in);
CREATE INDEX IF NOT EXISTS stay_bookings_room_idx ON stay_bookings (room_id);

CREATE TABLE IF NOT EXISTS stay_room_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES stay_rooms(id) ON DELETE CASCADE,
  starts_on date NOT NULL,
  ends_on date NOT NULL,
  reason text NOT NULL DEFAULT '',
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT stay_room_blocks_dates_valid CHECK (ends_on > starts_on),
  CONSTRAINT stay_room_blocks_no_overlap EXCLUDE USING gist (
    room_id WITH =,
    daterange(starts_on, ends_on, '[)') WITH &&
  )
);

CREATE INDEX IF NOT EXISTS stay_room_blocks_room_idx ON stay_room_blocks (room_id);

ALTER TABLE stay_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE stay_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE stay_room_blocks ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON stay_rooms TO authenticated;
GRANT UPDATE (name, is_active) ON stay_rooms TO authenticated;
GRANT SELECT ON stay_bookings TO authenticated;
GRANT SELECT, DELETE ON stay_room_blocks TO authenticated;

DROP POLICY IF EXISTS "admins_select_stay_rooms" ON stay_rooms;
CREATE POLICY "admins_select_stay_rooms" ON stay_rooms FOR SELECT
  TO authenticated USING (is_edan_admin());

DROP POLICY IF EXISTS "admins_insert_stay_rooms" ON stay_rooms;
CREATE POLICY "admins_insert_stay_rooms" ON stay_rooms FOR INSERT
  TO authenticated WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_update_stay_rooms" ON stay_rooms;
CREATE POLICY "admins_update_stay_rooms" ON stay_rooms FOR UPDATE
  TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_select_stay_bookings" ON stay_bookings;
CREATE POLICY "admins_select_stay_bookings" ON stay_bookings FOR SELECT
  TO authenticated USING (is_edan_admin());

DROP POLICY IF EXISTS "admins_select_stay_room_blocks" ON stay_room_blocks;
CREATE POLICY "admins_select_stay_room_blocks" ON stay_room_blocks FOR SELECT
  TO authenticated USING (is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_stay_room_blocks" ON stay_room_blocks;
CREATE POLICY "admins_delete_stay_room_blocks" ON stay_room_blocks FOR DELETE
  TO authenticated USING (is_edan_admin());


-- SOURCE MIGRATION: 20261030102557_create_admin_stay_booking_functions.sql
/*
# Admin functions for Stay bookings and room blocks

1. New Functions (team admins only)
- `admin_create_manual_booking`: records a booking received by phone or WhatsApp. Stored as source "manual" and confirmed. It is never linked to a Paystack payment.
- `admin_block_room`: closes a date range for one room.
- `admin_set_booking_status`: marks a confirmed booking as completed or cancelled.

2. Rules enforced on the server
- Only team admins can call these functions.
- Dates must be valid, check-out after check-in, and check-in not in the past.
- Guests must be 1 or 2.
- Nightly rate is set by the function: GH₵650 room only, GH₵700 with breakfast. Total is nights multiplied by the rate.
- Overlaps are checked against confirmed/completed bookings and existing blocks while holding a lock for that room, so two simultaneous requests cannot both succeed.
- Status changes only allow confirmed to completed or cancelled.

3. Security
- Each function is callable by signed-in users only (not anonymous visitors) and checks admin status itself.
- No existing tables or data are changed.
*/

CREATE OR REPLACE FUNCTION admin_create_manual_booking(
  p_room_id uuid,
  p_check_in date,
  p_check_out date,
  p_guests integer,
  p_breakfast_included boolean,
  p_guest_name text,
  p_guest_email text,
  p_guest_phone text,
  p_notes text
)
RETURNS stay_bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate integer;
  v_booking stay_bookings;
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'You are not authorised to manage bookings.' USING ERRCODE = '42501';
  END IF;

  IF p_check_in IS NULL OR p_check_out IS NULL OR p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'Check-out must be at least one night after check-in.';
  END IF;

  IF p_check_in < CURRENT_DATE THEN
    RAISE EXCEPTION 'Check-in cannot be in the past.';
  END IF;

  IF p_guests IS NULL OR p_guests NOT BETWEEN 1 AND 2 THEN
    RAISE EXCEPTION 'Each room holds one or two guests.';
  END IF;

  IF length(btrim(coalesce(p_guest_name, ''))) = 0
     OR length(btrim(coalesce(p_guest_phone, ''))) = 0
     OR length(btrim(coalesce(p_guest_email, ''))) = 0 THEN
    RAISE EXCEPTION 'Guest name, email and phone are required.';
  END IF;

  PERFORM 1 FROM stay_rooms WHERE id = p_room_id AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'That room is not available for bookings.';
  END IF;

  v_rate := CASE WHEN coalesce(p_breakfast_included, false) THEN 700 ELSE 650 END;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_room_id::text, 0));

  IF EXISTS (
    SELECT 1 FROM stay_bookings b
    WHERE b.room_id = p_room_id
      AND b.status IN ('confirmed', 'completed')
      AND daterange(b.check_in, b.check_out, '[)') && daterange(p_check_in, p_check_out, '[)')
  ) OR EXISTS (
    SELECT 1 FROM stay_room_blocks k
    WHERE k.room_id = p_room_id
      AND daterange(k.starts_on, k.ends_on, '[)') && daterange(p_check_in, p_check_out, '[)')
  ) THEN
    RAISE EXCEPTION 'That room is already booked or blocked for these dates.';
  END IF;

  INSERT INTO stay_bookings (
    room_id, check_in, check_out, guests, breakfast_included,
    nightly_rate_ghs, total_ghs, status, source,
    guest_name, guest_email, guest_phone, notes, created_by
  ) VALUES (
    p_room_id, p_check_in, p_check_out, p_guests, coalesce(p_breakfast_included, false),
    v_rate, (p_check_out - p_check_in) * v_rate, 'confirmed', 'manual',
    btrim(p_guest_name), btrim(p_guest_email), btrim(p_guest_phone), coalesce(p_notes, ''), auth.uid()
  )
  RETURNING * INTO v_booking;

  RETURN v_booking;
END;
$$;

CREATE OR REPLACE FUNCTION admin_block_room(
  p_room_id uuid,
  p_starts_on date,
  p_ends_on date,
  p_reason text
)
RETURNS stay_room_blocks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_block stay_room_blocks;
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'You are not authorised to manage bookings.' USING ERRCODE = '42501';
  END IF;

  IF p_starts_on IS NULL OR p_ends_on IS NULL OR p_ends_on <= p_starts_on THEN
    RAISE EXCEPTION 'The blocked end date must be after the start date.';
  END IF;

  PERFORM 1 FROM stay_rooms WHERE id = p_room_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'That room does not exist.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_room_id::text, 0));

  IF EXISTS (
    SELECT 1 FROM stay_bookings b
    WHERE b.room_id = p_room_id
      AND b.status IN ('confirmed', 'completed')
      AND daterange(b.check_in, b.check_out, '[)') && daterange(p_starts_on, p_ends_on, '[)')
  ) THEN
    RAISE EXCEPTION 'A booking already covers part of these dates. Cancel it before blocking the room.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM stay_room_blocks k
    WHERE k.room_id = p_room_id
      AND daterange(k.starts_on, k.ends_on, '[)') && daterange(p_starts_on, p_ends_on, '[)')
  ) THEN
    RAISE EXCEPTION 'This room is already blocked for part of these dates.';
  END IF;

  INSERT INTO stay_room_blocks (room_id, starts_on, ends_on, reason, created_by)
  VALUES (p_room_id, p_starts_on, p_ends_on, coalesce(btrim(p_reason), ''), auth.uid())
  RETURNING * INTO v_block;

  RETURN v_block;
END;
$$;

CREATE OR REPLACE FUNCTION admin_set_booking_status(
  p_booking_id uuid,
  p_status text
)
RETURNS stay_bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking stay_bookings;
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'You are not authorised to manage bookings.' USING ERRCODE = '42501';
  END IF;

  IF p_status NOT IN ('completed', 'cancelled') THEN
    RAISE EXCEPTION 'Bookings can only be marked completed or cancelled here.';
  END IF;

  SELECT * INTO v_booking FROM stay_bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'That booking does not exist.';
  END IF;

  IF v_booking.status <> 'confirmed' THEN
    RAISE EXCEPTION 'Only confirmed bookings can be changed.';
  END IF;

  UPDATE stay_bookings
  SET status = p_status,
      updated_at = now(),
      cancelled_at = CASE WHEN p_status = 'cancelled' THEN now() ELSE cancelled_at END
  WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  RETURN v_booking;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_create_manual_booking(uuid, date, date, integer, boolean, text, text, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION admin_block_room(uuid, date, date, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION admin_set_booking_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_create_manual_booking(uuid, date, date, integer, boolean, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_block_room(uuid, date, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_set_booking_status(uuid, text) TO authenticated;


-- SOURCE MIGRATION: 20261030103135_add_stay_online_booking_columns_and_events.sql
/*
# Online Stay booking columns and payment event log

1. Changes to `stay_bookings`
- `user_id`: the signed-in guest who made an online booking. Manual bookings leave it empty.
- `paystack_reference`: unique payment reference sent to Paystack for each online booking.
- `paystack_authorization_url`: the Paystack checkout link, kept so a retried request returns the same checkout instead of creating a duplicate charge.
- `hold_expires_at`: when a temporary hold on the dates ends if payment is not completed.
- `paid_amount_pesewas`, `paystack_transaction_id`, `paid_at`: payment details recorded only after Paystack verification.
- `payment_note`: plain-text note for the team (for example, a payment that needs a refund).

2. New table `stay_payment_events`
- One row per Paystack webhook event, keyed by a hash of the event body. Duplicate deliveries are detected by this key.

3. Security
- Guests can read only their own online bookings (`user_id` must match their account).
- `stay_payment_events` has no public access; only the server (service role) can write to it.
- No existing rows or columns are removed or changed.
*/

ALTER TABLE stay_bookings
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS paystack_reference text UNIQUE,
  ADD COLUMN IF NOT EXISTS paystack_authorization_url text,
  ADD COLUMN IF NOT EXISTS hold_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS paid_amount_pesewas integer,
  ADD COLUMN IF NOT EXISTS paystack_transaction_id bigint,
  ADD COLUMN IF NOT EXISTS paid_at timestamptz,
  ADD COLUMN IF NOT EXISTS payment_note text NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS stay_bookings_user_idx ON stay_bookings (user_id);

DROP POLICY IF EXISTS "guests_select_own_stay_bookings" ON stay_bookings;
CREATE POLICY "guests_select_own_stay_bookings" ON stay_bookings FOR SELECT
  TO authenticated USING (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS stay_payment_events (
  event_key text PRIMARY KEY,
  event_type text NOT NULL,
  reference text,
  received_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE stay_payment_events ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON stay_payment_events TO service_role;
GRANT SELECT, UPDATE ON stay_bookings TO service_role;


-- SOURCE MIGRATION: 20261030103158_create_stay_online_booking_functions.sql
/*
# Online Stay booking functions

1. New Functions
- `stay_room_availability(check_in, check_out)`: lists each active room with whether it is free for those dates. Callable by anyone; returns no guest details.
- `create_stay_hold(...)`: a signed-in guest reserves one room for 15 minutes while they pay. Creates a pending booking with a Paystack reference. Overlaps are checked under a per-room lock, so two guests cannot hold the same room at once.
- `prepare_stay_payment(booking_id)`: server-only. Rechecks the dates just before Paystack checkout is created.
- `confirm_stay_payment(...)`: server-only. Confirms a booking only after Paystack verification matches the reference, amount (in pesewas) and currency. Repeat calls change nothing. If the dates were taken after the hold expired, the booking is cancelled and flagged for refund instead of being double-booked.
- `mark_stay_payment_failed(reference)`: server-only. Releases a hold when Paystack reports a failed charge.

2. Rules
- Hold length: 15 minutes (`hold_expires_at`).
- Nightly rates: GH₵650 room only, GH₵700 with breakfast; total is nights multiplied by rate.
- Expired holds are marked payment_failed when a new hold is requested, so their dates are released.
- Abandoned or failed payments never produce a confirmed booking.

3. Security
- Guest-facing functions run as the signed-in user or anonymous visitor; they check identity and never expose other guests' details.
- Server-only functions are granted to the service role alone.
- Nothing existing is changed except the new function definitions.
*/

CREATE OR REPLACE FUNCTION stay_room_availability(p_check_in date, p_check_out date)
RETURNS TABLE (available_room_id uuid, available_room_name text, is_available boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_check_in IS NULL OR p_check_out IS NULL OR p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'Check-out must be at least one night after check-in.';
  END IF;

  IF p_check_in < CURRENT_DATE THEN
    RAISE EXCEPTION 'Check-in cannot be in the past.';
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.name,
    NOT EXISTS (
      SELECT 1 FROM stay_bookings b
      WHERE b.room_id = r.id
        AND (
          b.status IN ('confirmed', 'completed')
          OR (b.status = 'pending_payment' AND b.hold_expires_at > now())
        )
        AND daterange(b.check_in, b.check_out, '[)') && daterange(p_check_in, p_check_out, '[)')
    ) AND NOT EXISTS (
      SELECT 1 FROM stay_room_blocks k
      WHERE k.room_id = r.id
        AND daterange(k.starts_on, k.ends_on, '[)') && daterange(p_check_in, p_check_out, '[)')
    )
  FROM stay_rooms r
  WHERE r.is_active
  ORDER BY r.name;
END;
$$;

CREATE OR REPLACE FUNCTION create_stay_hold(
  p_room_id uuid,
  p_check_in date,
  p_check_out date,
  p_guests integer,
  p_breakfast_included boolean,
  p_guest_name text,
  p_guest_email text,
  p_guest_phone text
)
RETURNS stay_bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate integer;
  v_booking stay_bookings;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Please log in to book a room.' USING ERRCODE = '42501';
  END IF;

  IF p_check_in IS NULL OR p_check_out IS NULL OR p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'Check-out must be at least one night after check-in.';
  END IF;

  IF p_check_in < CURRENT_DATE THEN
    RAISE EXCEPTION 'Check-in cannot be in the past.';
  END IF;

  IF p_guests IS NULL OR p_guests NOT BETWEEN 1 AND 2 THEN
    RAISE EXCEPTION 'Each room holds one or two guests.';
  END IF;

  IF length(btrim(coalesce(p_guest_name, ''))) = 0
     OR length(btrim(coalesce(p_guest_email, ''))) = 0
     OR length(btrim(coalesce(p_guest_phone, ''))) = 0 THEN
    RAISE EXCEPTION 'Please enter your name, email and phone number.';
  END IF;

  PERFORM 1 FROM stay_rooms WHERE id = p_room_id AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'That room is not available for booking.';
  END IF;

  UPDATE stay_bookings
  SET status = 'payment_failed',
      updated_at = now(),
      payment_note = 'The payment window closed before payment was completed.'
  WHERE status = 'pending_payment' AND hold_expires_at <= now();

  v_rate := CASE WHEN coalesce(p_breakfast_included, false) THEN 700 ELSE 650 END;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_room_id::text, 0));

  IF EXISTS (
    SELECT 1 FROM stay_bookings b
    WHERE b.room_id = p_room_id
      AND (
        b.status IN ('confirmed', 'completed')
        OR (b.status = 'pending_payment' AND b.hold_expires_at > now())
      )
      AND daterange(b.check_in, b.check_out, '[)') && daterange(p_check_in, p_check_out, '[)')
  ) OR EXISTS (
    SELECT 1 FROM stay_room_blocks k
    WHERE k.room_id = p_room_id
      AND daterange(k.starts_on, k.ends_on, '[)') && daterange(p_check_in, p_check_out, '[)')
  ) THEN
    RAISE EXCEPTION 'Sorry, that room has just been taken for these dates. Please choose another room or dates.';
  END IF;

  INSERT INTO stay_bookings (
    room_id, user_id, check_in, check_out, guests, breakfast_included,
    nightly_rate_ghs, total_ghs, status, source, hold_expires_at, paystack_reference,
    guest_name, guest_email, guest_phone
  ) VALUES (
    p_room_id, auth.uid(), p_check_in, p_check_out, p_guests, coalesce(p_breakfast_included, false),
    v_rate, (p_check_out - p_check_in) * v_rate, 'pending_payment', 'online',
    now() + interval '15 minutes',
    'EDNSTAY-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)),
    btrim(p_guest_name), btrim(p_guest_email), btrim(p_guest_phone)
  )
  RETURNING * INTO v_booking;

  RETURN v_booking;
END;
$$;

CREATE OR REPLACE FUNCTION prepare_stay_payment(p_booking_id uuid)
RETURNS stay_bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking stay_bookings;
BEGIN
  SELECT * INTO v_booking FROM stay_bookings WHERE id = p_booking_id FOR UPDATE;

  IF NOT FOUND OR v_booking.status <> 'pending_payment' THEN
    RAISE EXCEPTION 'This booking is no longer waiting for payment. Please start again.';
  END IF;

  IF v_booking.hold_expires_at <= now() THEN
    RAISE EXCEPTION 'Your 15-minute hold has expired. Please start the booking again.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_booking.room_id::text, 0));

  IF EXISTS (
    SELECT 1 FROM stay_bookings b
    WHERE b.room_id = v_booking.room_id
      AND b.id <> v_booking.id
      AND (
        b.status IN ('confirmed', 'completed')
        OR (b.status = 'pending_payment' AND b.hold_expires_at > now())
      )
      AND daterange(b.check_in, b.check_out, '[)') && daterange(v_booking.check_in, v_booking.check_out, '[)')
  ) OR EXISTS (
    SELECT 1 FROM stay_room_blocks k
    WHERE k.room_id = v_booking.room_id
      AND daterange(k.starts_on, k.ends_on, '[)') && daterange(v_booking.check_in, v_booking.check_out, '[)')
  ) THEN
    RAISE EXCEPTION 'Sorry, these dates are no longer available for this room. Please start again.';
  END IF;

  RETURN v_booking;
END;
$$;

CREATE OR REPLACE FUNCTION confirm_stay_payment(
  p_reference text,
  p_transaction_id bigint,
  p_amount_pesewas integer,
  p_currency text,
  p_paid_at timestamptz
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking stay_bookings;
  v_conflict boolean;
BEGIN
  SELECT * INTO v_booking FROM stay_bookings WHERE paystack_reference = p_reference FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 'unknown_reference';
  END IF;

  IF v_booking.status = 'confirmed' THEN
    RETURN 'already_confirmed';
  END IF;

  IF v_booking.status NOT IN ('pending_payment', 'payment_failed') THEN
    RETURN 'not_confirmable';
  END IF;

  IF p_currency IS DISTINCT FROM 'GHS' OR p_amount_pesewas IS DISTINCT FROM v_booking.total_ghs * 100 THEN
    UPDATE stay_bookings
    SET status = 'cancelled',
        cancelled_at = now(),
        updated_at = now(),
        paystack_transaction_id = p_transaction_id,
        paid_amount_pesewas = p_amount_pesewas,
        paid_at = p_paid_at,
        payment_note = 'Payment amount or currency did not match this booking. Refund required.'
    WHERE id = v_booking.id;
    RETURN 'amount_mismatch';
  END IF;

  v_conflict := EXISTS (
    SELECT 1 FROM stay_bookings b
    WHERE b.room_id = v_booking.room_id
      AND b.id <> v_booking.id
      AND b.status IN ('confirmed', 'completed')
      AND daterange(b.check_in, b.check_out, '[)') && daterange(v_booking.check_in, v_booking.check_out, '[)')
  ) OR EXISTS (
    SELECT 1 FROM stay_room_blocks k
    WHERE k.room_id = v_booking.room_id
      AND daterange(k.starts_on, k.ends_on, '[)') && daterange(v_booking.check_in, v_booking.check_out, '[)')
  );

  IF v_conflict THEN
    UPDATE stay_bookings
    SET status = 'cancelled',
        cancelled_at = now(),
        updated_at = now(),
        paystack_transaction_id = p_transaction_id,
        paid_amount_pesewas = p_amount_pesewas,
        paid_at = p_paid_at,
        payment_note = 'Payment was received after the hold expired and these dates were taken. Refund required.'
    WHERE id = v_booking.id;
    RETURN 'conflict_refund_required';
  END IF;

  UPDATE stay_bookings
  SET status = 'confirmed',
      hold_expires_at = NULL,
      updated_at = now(),
      paystack_transaction_id = p_transaction_id,
      paid_amount_pesewas = p_amount_pesewas,
      paid_at = p_paid_at,
      payment_note = ''
  WHERE id = v_booking.id;

  RETURN 'confirmed';
END;
$$;

CREATE OR REPLACE FUNCTION mark_stay_payment_failed(p_reference text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE stay_bookings
  SET status = 'payment_failed',
      updated_at = now(),
      payment_note = 'The payment was not completed.'
  WHERE paystack_reference = p_reference AND status = 'pending_payment';
$$;

REVOKE EXECUTE ON FUNCTION stay_room_availability(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION stay_room_availability(date, date) TO anon, authenticated;

REVOKE EXECUTE ON FUNCTION create_stay_hold(uuid, date, date, integer, boolean, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_stay_hold(uuid, date, date, integer, boolean, text, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION prepare_stay_payment(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION prepare_stay_payment(uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION confirm_stay_payment(text, bigint, integer, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION confirm_stay_payment(text, bigint, integer, text, timestamptz) TO service_role;

REVOKE EXECUTE ON FUNCTION mark_stay_payment_failed(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mark_stay_payment_failed(text) TO service_role;


-- SOURCE MIGRATION: 20261030105118_add_stay_paystack_access_code.sql
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


-- SOURCE MIGRATION: 20261030105642_add_stay_check_in.sql
/*
# Add guest check-in for Stay bookings

1. Modified tables
- `stay_bookings`: new column `checked_in_at` (timestamptz, nullable). It is set when staff check the guest in. Empty means the guest has not arrived yet.

2. New functions
- `admin_check_in_booking(p_booking_id)`: sets `checked_in_at` to the current time. Rules:
  - The caller must be an admin (checked inside the function).
  - Only confirmed bookings can be checked in.
  - A guest can be checked in once.
  - Check-in is allowed from the arrival date onward, so staff cannot check someone in early.
  - The booking row is locked while the check is made, so two staff members cannot race.

3. Security
- The function is executable by signed-in users only (not anonymous visitors), and it still refuses non-admins.
- No table grants or policies change. Guests and admins read the column through the existing policies.

4. Notes
- Checking out is still done with the existing "Mark as completed" action, which moves the booking to completed.
*/

ALTER TABLE stay_bookings ADD COLUMN IF NOT EXISTS checked_in_at timestamptz;

CREATE OR REPLACE FUNCTION admin_check_in_booking(p_booking_id uuid)
RETURNS stay_bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking stay_bookings;
BEGIN
  IF NOT is_edan_admin() THEN
    RAISE EXCEPTION 'You are not authorised to manage bookings.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_booking
  FROM stay_bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'That booking does not exist.';
  END IF;

  IF v_booking.status <> 'confirmed' THEN
    RAISE EXCEPTION 'Only confirmed bookings can be checked in.';
  END IF;

  IF v_booking.checked_in_at IS NOT NULL THEN
    RAISE EXCEPTION 'This guest is already checked in.';
  END IF;

  IF v_booking.check_in > CURRENT_DATE THEN
    RAISE EXCEPTION 'Guests can be checked in from their arrival date.';
  END IF;

  UPDATE stay_bookings
  SET checked_in_at = now()
  WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  RETURN v_booking;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_check_in_booking(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_check_in_booking(uuid) TO authenticated;


-- SOURCE MIGRATION: 20261030110115_add_stay_confirmation_lookup.sql
/*
# Stay booking confirmation lookup

1. New functions
- `get_own_stay_confirmation(p_booking_id uuid)`: returns the booking details, room name and payment record for one booking. It only returns a row when the booking belongs to the signed-in guest.

2. Why a function
- Room records are visible to admins only, so a guest cannot read the room name from the booking table directly. The function returns just the fields the confirmation page needs and nothing else (no phone number, no Paystack transaction IDs, no payment notes).

3. Security
- The function checks `auth.uid()` against the booking's owner. Anyone else gets no row.
- Executable by signed-in users only. Anonymous visitors and PUBLIC are revoked.
- No table grants or policies change.

4. Notes
- Returns no row when the booking does not exist or belongs to someone else, so the page cannot tell the two cases apart.
*/

CREATE OR REPLACE FUNCTION get_own_stay_confirmation(p_booking_id uuid)
RETURNS TABLE (
  booking_reference text,
  status text,
  room_name text,
  guest_name text,
  guest_email text,
  check_in date,
  check_out date,
  guests smallint,
  breakfast_included boolean,
  nightly_rate_ghs integer,
  total_ghs integer,
  paid_amount_pesewas integer,
  paid_at timestamptz,
  paystack_reference text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    b.booking_reference,
    b.status,
    r.name,
    b.guest_name,
    b.guest_email,
    b.check_in,
    b.check_out,
    b.guests,
    b.breakfast_included,
    b.nightly_rate_ghs,
    b.total_ghs,
    b.paid_amount_pesewas,
    b.paid_at,
    b.paystack_reference
  FROM stay_bookings b
  JOIN stay_rooms r ON r.id = b.room_id
  WHERE b.id = p_booking_id
    AND b.user_id = auth.uid();
$$;

REVOKE EXECUTE ON FUNCTION get_own_stay_confirmation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_own_stay_confirmation(uuid) TO authenticated;


-- SOURCE MIGRATION: 20261030115018_members_community_gatherings_and_bonus_videos.sql
/*
# Members community, gatherings and annual bonus videos

1. New Functions
- `is_active_member(tiers text[])`: true when the signed-in user has an active, unexpired membership whose tier is in the list.

2. New Tables
- `member_chat_profiles`: one chat username per member.
- `member_chat_messages`: community chat messages.
- `member_gatherings`: gatherings and invitations shown to members. Managed by admins.
- `member_bonus_videos`: annual-only bonus videos. Managed by admins.

3. Security
- Every table has row level security enabled.
- Chat: active monthly and annual members can read and post; a member can only write their own username and messages.
- Gatherings: active members read published rows; admins read and write everything.
- Bonus videos: only active annual members read published rows; admins read and write everything.
- Admin-only writes use the existing `is_edan_admin()` check.

4. Notes
- Realtime is enabled for chat messages so new messages appear live, and realtime respects these policies.
- Creation is idempotent, so the migration can be re-run safely.
*/

CREATE OR REPLACE FUNCTION is_active_member(tiers text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
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

REVOKE EXECUTE ON FUNCTION is_active_member(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION is_active_member(text[]) TO authenticated;

CREATE TABLE IF NOT EXISTS member_chat_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL UNIQUE CHECK (username ~ '^[A-Za-z0-9_]{3,24}$'),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE member_chat_profiles ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON member_chat_profiles TO authenticated;

DROP POLICY IF EXISTS "active_members_select_chat_profiles" ON member_chat_profiles;
CREATE POLICY "active_members_select_chat_profiles" ON member_chat_profiles FOR SELECT
  TO authenticated USING (is_active_member(ARRAY['monthly', 'annual']));

DROP POLICY IF EXISTS "active_members_insert_chat_profiles" ON member_chat_profiles;
CREATE POLICY "active_members_insert_chat_profiles" ON member_chat_profiles FOR INSERT
  TO authenticated WITH CHECK (
    user_id = auth.uid() AND is_active_member(ARRAY['monthly', 'annual'])
  );

DROP POLICY IF EXISTS "active_members_update_chat_profiles" ON member_chat_profiles;
CREATE POLICY "active_members_update_chat_profiles" ON member_chat_profiles FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid() AND is_active_member(ARRAY['monthly', 'annual']))
  WITH CHECK (user_id = auth.uid() AND is_active_member(ARRAY['monthly', 'annual']));

CREATE TABLE IF NOT EXISTS member_chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  message text NOT NULL CHECK (length(btrim(message)) BETWEEN 1 AND 1000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS member_chat_messages_created_at_idx
  ON member_chat_messages (created_at DESC);

ALTER TABLE member_chat_messages ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON member_chat_messages TO authenticated;

DROP POLICY IF EXISTS "active_members_select_chat_messages" ON member_chat_messages;
CREATE POLICY "active_members_select_chat_messages" ON member_chat_messages FOR SELECT
  TO authenticated USING (is_active_member(ARRAY['monthly', 'annual']));

DROP POLICY IF EXISTS "active_members_insert_chat_messages" ON member_chat_messages;
CREATE POLICY "active_members_insert_chat_messages" ON member_chat_messages FOR INSERT
  TO authenticated WITH CHECK (
    user_id = auth.uid()
    AND is_active_member(ARRAY['monthly', 'annual'])
    AND EXISTS (SELECT 1 FROM member_chat_profiles p WHERE p.user_id = auth.uid())
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'member_chat_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE member_chat_messages;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS member_gatherings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  description text NOT NULL DEFAULT '',
  starts_at timestamptz,
  location text NOT NULL DEFAULT '',
  image_path text NOT NULL DEFAULT '',
  registration_url text NOT NULL DEFAULT '',
  is_published boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE member_gatherings ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON member_gatherings TO authenticated;

DROP POLICY IF EXISTS "members_select_published_gatherings" ON member_gatherings;
CREATE POLICY "members_select_published_gatherings" ON member_gatherings FOR SELECT
  TO authenticated USING (
    (is_published AND is_active_member(ARRAY['monthly', 'annual'])) OR is_edan_admin()
  );

DROP POLICY IF EXISTS "admins_insert_gatherings" ON member_gatherings;
CREATE POLICY "admins_insert_gatherings" ON member_gatherings FOR INSERT
  TO authenticated WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_update_gatherings" ON member_gatherings;
CREATE POLICY "admins_update_gatherings" ON member_gatherings FOR UPDATE
  TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_gatherings" ON member_gatherings;
CREATE POLICY "admins_delete_gatherings" ON member_gatherings FOR DELETE
  TO authenticated USING (is_edan_admin());

CREATE TABLE IF NOT EXISTS member_bonus_videos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  description text NOT NULL DEFAULT '',
  video_path text NOT NULL DEFAULT '',
  poster_path text NOT NULL DEFAULT '',
  is_published boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE member_bonus_videos ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON member_bonus_videos TO authenticated;

DROP POLICY IF EXISTS "annual_members_select_published_bonus_videos" ON member_bonus_videos;
CREATE POLICY "annual_members_select_published_bonus_videos" ON member_bonus_videos FOR SELECT
  TO authenticated USING (
    (is_published AND is_active_member(ARRAY['annual'])) OR is_edan_admin()
  );

DROP POLICY IF EXISTS "admins_insert_bonus_videos" ON member_bonus_videos;
CREATE POLICY "admins_insert_bonus_videos" ON member_bonus_videos FOR INSERT
  TO authenticated WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_update_bonus_videos" ON member_bonus_videos;
CREATE POLICY "admins_update_bonus_videos" ON member_bonus_videos FOR UPDATE
  TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_bonus_videos" ON member_bonus_videos;
CREATE POLICY "admins_delete_bonus_videos" ON member_bonus_videos FOR DELETE
  TO authenticated USING (is_edan_admin());


-- SOURCE MIGRATION: 20261030115259_members_active_member_helper_invoker.sql
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


-- SOURCE MIGRATION: 20261031125159_members_research_items.sql.sql
/*
# Members research items

1. New Tables
- `member_research_items`: research notes, creative insights and publications shown in the Members page Research section.
  - `title`, `summary`, `category`, `image_path`, `read_more_url`, `is_published`, `sort_order`, `created_at`.

2. Security
- Row level security is enabled.
- Active monthly and annual members can read published items only.
- Admins (via the existing `is_edan_admin()` check) can read and write every item.
- Grants are limited to the `authenticated` role.

3. Seed data
- Three sample items are inserted so the Research section has content to display. Replace or remove them once real research is ready.

4. Notes
- Creation is idempotent, so the migration can be re-run safely.
*/

CREATE TABLE IF NOT EXISTS member_research_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 160),
  summary text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT '',
  image_path text NOT NULL DEFAULT '',
  read_more_url text NOT NULL DEFAULT '',
  is_published boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE member_research_items ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON member_research_items TO authenticated;

DROP POLICY IF EXISTS "members_select_published_research" ON member_research_items;
CREATE POLICY "members_select_published_research" ON member_research_items FOR SELECT
  TO authenticated USING (
    (is_published AND is_active_member(ARRAY['monthly', 'annual'])) OR is_edan_admin()
  );

DROP POLICY IF EXISTS "admins_insert_research" ON member_research_items;
CREATE POLICY "admins_insert_research" ON member_research_items FOR INSERT
  TO authenticated WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_update_research" ON member_research_items;
CREATE POLICY "admins_update_research" ON member_research_items FOR UPDATE
  TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_research" ON member_research_items;
CREATE POLICY "admins_delete_research" ON member_research_items FOR DELETE
  TO authenticated USING (is_edan_admin());

INSERT INTO member_research_items (title, summary, category, image_path, is_published, sort_order)
SELECT v.title, v.summary, v.category, v.image_path, true, v.sort_order
FROM (VALUES
  ('Sample: Notes on breeze-block light', 'A sample research note on how perforated walls shape light and airflow across a day.', 'Research note', '/images/breeze-block-detail.webp', 1),
  ('Sample: Dye pits and the colour of process', 'A sample creative insight on working with natural dyes, from preparation to the finished cloth.', 'Creative insight', '/images/dye-pits.jpg', 2),
  ('Sample: Mapping Accra in lines', 'A sample project note on drawing the city as a set of routes, edges and shared spaces.', 'Project publication', '/images/accra-map-lines.png', 3)
) AS v(title, summary, category, image_path, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM member_research_items);


-- SOURCE MIGRATION: 20261031125354_members_research_body.sql.sql
/*
# Full text for members research items

1. Modified Tables
- `member_research_items`: new `body` column holding the full text of a research note, insight or publication. Plain text; paragraphs are separated by blank lines.

2. Security
- No policy or grant changes. The existing member and admin read rules already cover the new column.

3. Seed data
- Full text is added to the three sample items. Only rows that still have an empty body are updated, so edits made later are not overwritten.

4. Notes
- Creation is idempotent, so the migration can be re-run safely.
*/

ALTER TABLE member_research_items
  ADD COLUMN IF NOT EXISTS body text NOT NULL DEFAULT '';

UPDATE member_research_items
SET body = $body$Breeze blocks are perforated walls, a familiar feature of hot-climate buildings. They let air move through a space while filtering strong sun, so a room can stay open without becoming glaring.

Over a day, the pattern a breeze block casts shifts across the floor and walls. Watching these shadows is a simple way to understand how light and ventilation work together, and it is a useful starting point for thinking about how a building should respond to its site.

This note is a sample. It shows the kind of short research text that will appear in this section.$body$
WHERE title = 'Sample: Notes on breeze-block light' AND body = '';

UPDATE member_research_items
SET body = $body$Natural dyes ask for patience. The pits are prepared, the material is soaked and lifted, and the colour changes as it meets the air. What looks like one shade in the vat can settle into something quite different once it dries.

Working this way means accepting that the process sets the outcome. Each batch teaches something about timing, water and the plants or minerals involved, and those lessons carry into the next piece of work.

This note is a sample. Real insights from the studio will replace it.$body$
WHERE title = 'Sample: Dye pits and the colour of process' AND body = '';

UPDATE member_research_items
SET body = $body$Drawing a city as lines shifts attention away from buildings and towards movement. Routes, edges and shared spaces become the main characters of the map, and the places where people gather start to stand out.

This kind of mapping is a way of asking who a city is for. The lines we draw can show where access is easy, where it is broken, and where a neighbourhood already holds its own sense of community.

This note is a sample. A full project publication will replace it once the work is ready to share.$body$
WHERE title = 'Sample: Mapping Accra in lines' AND body = '';


-- SOURCE MIGRATION: 20261031141725_members_process_items.sql
/*
# Members in-process items

1. New Tables
- `member_process_items`: work-in-progress notes shown in the In Process section of the Members page.
  - `title`, `summary`, `body`, `category`, `image_path`, `is_published`, `sort_order`, `created_at`.

2. Security
- Row level security is enabled.
- Active monthly and annual members can read published items only.
- Admins (via the existing `is_edan_admin()` check) can read and write every item.
- Grants are limited to the `authenticated` role.

3. Seed data
- Two sample items are inserted so the In Process section has content to review. Replace or remove them once real work is ready.

4. Research sample
- One additional sample research item is added so the Research section shows more than one layout pattern.

5. Notes
- Creation and seeding are idempotent, so the migration can be re-run safely.
*/

CREATE TABLE IF NOT EXISTS member_process_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 160),
  summary text NOT NULL DEFAULT '',
  body text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT '',
  image_path text NOT NULL DEFAULT '',
  is_published boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE member_process_items ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON member_process_items TO authenticated;

DROP POLICY IF EXISTS "members_select_published_process" ON member_process_items;
CREATE POLICY "members_select_published_process" ON member_process_items FOR SELECT
  TO authenticated USING (
    (is_published AND is_active_member(ARRAY['monthly', 'annual'])) OR is_edan_admin()
  );

DROP POLICY IF EXISTS "admins_insert_process" ON member_process_items;
CREATE POLICY "admins_insert_process" ON member_process_items FOR INSERT
  TO authenticated WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_update_process" ON member_process_items;
CREATE POLICY "admins_update_process" ON member_process_items FOR UPDATE
  TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_process" ON member_process_items;
CREATE POLICY "admins_delete_process" ON member_process_items FOR DELETE
  TO authenticated USING (is_edan_admin());

INSERT INTO member_process_items (title, summary, body, category, image_path, is_published, sort_order)
SELECT v.title, v.summary, v.body, v.category, v.image_path, true, v.sort_order
FROM (VALUES
  ('Sample: The studio table', 'A sample note on how the team gathers around one table to test ideas before they become drawings.', 'Sample text for review. Replace with a real studio note.

The studio table is where most ideas first meet a second opinion. Sketches, half-written notes and material samples sit side by side, and a conversation usually decides what goes forward.

This sample shows how a longer in-process note reads inside the members space.', 'Studio notes', '/images/sharing.webp', 1),
  ('Sample: Notes on a wall that has weathered', 'A sample observation on plants and paint loss along an old wall, and what they reveal about materials over time.', 'Sample text for review. Replace with a real observation.

Walls keep a record of the weather they have stood through. Where paint has lifted and a plant has found a crack, the surface tells us how water moves and where it settles.

This sample shows how a research-style in-process note is presented.', 'Field notes', '/images/garden-plant.jpg', 2)
) AS v(title, summary, body, category, image_path, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM member_process_items);

INSERT INTO member_research_items (title, summary, body, category, image_path, is_published, sort_order)
SELECT 'Sample: Plants that find the cracks', 'A sample research note on how planting and weathering interact along the edges of a building.', 'Sample text for review. Replace with a real research note.

Cracks in a rendered wall are small thresholds. Seeds and roots find them first, and over several seasons they change how the wall holds moisture.

Recording these changes is one way the studio tests materials against the conditions they actually face.', 'Research note', '/images/garden-plant.jpg', true, 4
WHERE NOT EXISTS (SELECT 1 FROM member_research_items WHERE title = 'Sample: Plants that find the cracks');


-- SOURCE MIGRATION: 20261031143510_admin_delete_policies_bookings_rooms_applications.sql.sql
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


-- SOURCE MIGRATION: 20261031144310_admin_site_images_bucket_and_room_photos.sql
/*
# Admin image uploads: site-images bucket and room photos

1. New storage bucket
- `site-images` holds photos uploaded by admins for the members page and room pages.
- Public-read bucket (images are shown on public and member pages).
- Limited to 5 MB per file and to JPEG, PNG, WebP, AVIF and GIF.

2. Modified tables
- `stay_rooms` gains `image_path` (text, default empty string). It stores the public web address of the room photo. Existing rows get an empty value. No data is removed.

3. Security
- Only admins (is_edan_admin()) can upload, replace or delete objects in `site-images`.
- Anonymous and signed-in non-admin accounts cannot write to the bucket.
- The room photo column is written only through the existing admin room update policy.

4. Notes
- Statements are idempotent, so re-running this migration is safe.
*/

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'site-images',
  'site-images',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/avif', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "admins_insert_site_images" ON storage.objects;
CREATE POLICY "admins_insert_site_images" ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'site-images' AND public.is_edan_admin());

DROP POLICY IF EXISTS "admins_update_site_images" ON storage.objects;
CREATE POLICY "admins_update_site_images" ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'site-images' AND public.is_edan_admin())
WITH CHECK (bucket_id = 'site-images' AND public.is_edan_admin());

DROP POLICY IF EXISTS "admins_delete_site_images" ON storage.objects;
CREATE POLICY "admins_delete_site_images" ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'site-images' AND public.is_edan_admin());

ALTER TABLE public.stay_rooms ADD COLUMN IF NOT EXISTS image_path text NOT NULL DEFAULT '';


-- SOURCE MIGRATION: 20261101141606_membership_interest_form_fields.sql
/*
# Membership interest form fields and submit function

1. Summary
- The membership application now collects the details from the Ɛdan Membership Interest Form before any payment step.

2. Modified table: membership_applications (new columns)
- `full_name` (text): applicant's full name.
- `phone` (text): phone number for mobile money and contact.
- `practice_type` (text): what best describes the applicant (researcher, creative, spatial practitioner, collective, student, partner institution, other).
- `based_in` (text): whether the applicant is based in Accra or passing through.
- `about_work` (text, up to 1000 characters): short description of the applicant's work.
- `commitment_agreed` (boolean): the applicant agreed to the shared commitment to a fairer city.
- `submitted_at` (timestamptz): when the form was completed. Payment only proceeds once this is set.

3. New function: submit_membership_interest
- Signed-in applicants save their form. It updates their latest pending application, or creates one if none exists.
- Validates every field before saving.
- Only the signed-in applicant can call it. Approval and payment status are never changed by it.

4. Security
- No new policies. The existing rules still let applicants read only their own applications and admins read all of them.
- Applicants cannot edit applications directly; changes go through the submit function.
- The function is not callable by anonymous visitors.
*/

ALTER TABLE membership_applications
  ADD COLUMN IF NOT EXISTS full_name text,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS practice_type text CHECK (practice_type IN ('researcher', 'creative', 'spatial_practitioner', 'collective', 'student', 'partner_institution', 'other')),
  ADD COLUMN IF NOT EXISTS based_in text CHECK (based_in IN ('accra', 'passing_through')),
  ADD COLUMN IF NOT EXISTS about_work text CHECK (char_length(about_work) <= 1000),
  ADD COLUMN IF NOT EXISTS commitment_agreed boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS submitted_at timestamptz;

CREATE OR REPLACE FUNCTION submit_membership_interest(
  p_full_name text,
  p_phone text,
  p_practice_type text,
  p_based_in text,
  p_about_work text,
  p_commitment_agreed boolean
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_email text := auth.jwt() ->> 'email';
  v_id uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Please sign in first' USING ERRCODE = '42501';
  END IF;

  IF char_length(btrim(coalesce(p_full_name, ''))) = 0 OR char_length(p_full_name) > 100 THEN
    RAISE EXCEPTION 'Please enter your full name';
  END IF;

  IF char_length(btrim(coalesce(p_phone, ''))) = 0 OR char_length(p_phone) > 20 THEN
    RAISE EXCEPTION 'Please enter a valid phone number';
  END IF;

  IF p_practice_type IS NULL OR p_practice_type NOT IN ('researcher', 'creative', 'spatial_practitioner', 'collective', 'student', 'partner_institution', 'other') THEN
    RAISE EXCEPTION 'Choose what best describes you';
  END IF;

  IF p_based_in IS NULL OR p_based_in NOT IN ('accra', 'passing_through') THEN
    RAISE EXCEPTION 'Tell us where you are based';
  END IF;

  IF char_length(btrim(coalesce(p_about_work, ''))) = 0 OR char_length(p_about_work) > 1000 THEN
    RAISE EXCEPTION 'Tell us about your work (up to 1000 characters)';
  END IF;

  IF p_commitment_agreed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Please agree to the shared commitment to a fairer city';
  END IF;

  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Your account has no email address';
  END IF;

  SELECT id INTO v_id
  FROM membership_applications
  WHERE user_id = v_user AND status = 'pending'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_id IS NULL THEN
    INSERT INTO membership_applications (
      user_id, applicant_email, status, full_name, phone, practice_type,
      based_in, about_work, commitment_agreed, submitted_at
    )
    VALUES (
      v_user, v_email, 'pending', btrim(p_full_name), btrim(p_phone), p_practice_type,
      p_based_in, btrim(p_about_work), true, now()
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE membership_applications
    SET full_name = btrim(p_full_name),
        phone = btrim(p_phone),
        practice_type = p_practice_type,
        based_in = p_based_in,
        about_work = btrim(p_about_work),
        commitment_agreed = true,
        submitted_at = now()
    WHERE id = v_id;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION submit_membership_interest(text, text, text, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION submit_membership_interest(text, text, text, text, text, boolean) TO authenticated;


-- SOURCE MIGRATION: 20261102054157_admin_dashboard_kpis.sql
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
    'paid_awaiting_activation', (
      SELECT count(*)::int FROM payment_transactions pt
      JOIN membership_applications ma ON ma.id = pt.membership_application_id
      WHERE pt.status = 'success' AND ma.status = 'pending'
    ),
    'expired', (
      SELECT count(*)::int FROM memberships
      WHERE membership_status = 'expired'
         OR (membership_status = 'active' AND expires_at IS NOT NULL AND expires_at <= now())
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_dashboard_kpis() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_dashboard_kpis() TO authenticated;

NOTIFY pgrst, 'reload schema';

-- SOURCE MIGRATION: 20261102055120_notification_email_tracking.sql
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


-- SOURCE MIGRATION: 20261102105316_membership_interest_save_tier.sql
/*
# Save membership tier with the interest form

1. Summary
- The Ɛdan membership interest form now also captures the applicant's chosen
  membership tier (monthly or annual) and saves it on the application row.
- Payment no longer happens at submission. The admin reviews the application
  first; once approved, the member pays from the members page.

2. Modified function: submit_membership_interest
- New parameter `p_membership_tier` (text, required): 'monthly' or 'annual'.
- The tier is validated and stored on membership_applications.membership_tier
  (the column already exists from a previous migration).
- The function still creates or updates the latest pending application, now
  including the tier.

3. Security
- No new tables or policies. The function is SECURITY DEFINER and only callable
  by authenticated users (existing grants).
- Tier changes do not affect approval status; admin still reviews through the
  approve/reject functions.
*/

CREATE OR REPLACE FUNCTION submit_membership_interest(
  p_full_name text,
  p_phone text,
  p_practice_type text,
  p_based_in text,
  p_about_work text,
  p_commitment_agreed boolean,
  p_membership_tier text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_email text := auth.jwt() ->> 'email';
  v_id uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Please sign in first' USING ERRCODE = '42501';
  END IF;

  IF char_length(btrim(coalesce(p_full_name, ''))) = 0 OR char_length(p_full_name) > 100 THEN
    RAISE EXCEPTION 'Please enter your full name';
  END IF;

  IF char_length(btrim(coalesce(p_phone, ''))) = 0 OR char_length(p_phone) > 20 THEN
    RAISE EXCEPTION 'Please enter a valid phone number';
  END IF;

  IF p_practice_type IS NULL OR p_practice_type NOT IN ('researcher', 'creative', 'spatial_practitioner', 'collective', 'student', 'partner_institution', 'other') THEN
    RAISE EXCEPTION 'Choose what best describes you';
  END IF;

  IF p_based_in IS NULL OR p_based_in NOT IN ('accra', 'passing_through') THEN
    RAISE EXCEPTION 'Tell us where you are based';
  END IF;

  IF char_length(btrim(coalesce(p_about_work, ''))) = 0 OR char_length(p_about_work) > 1000 THEN
    RAISE EXCEPTION 'Tell us about your work (up to 1000 characters)';
  END IF;

  IF p_commitment_agreed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Please agree to the shared commitment to a fairer city';
  END IF;

  IF p_membership_tier IS NULL OR p_membership_tier NOT IN ('monthly', 'annual') THEN
    RAISE EXCEPTION 'Choose a membership option';
  END IF;

  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Your account has no email address';
  END IF;

  SELECT id INTO v_id
  FROM membership_applications
  WHERE user_id = v_user AND status = 'pending'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_id IS NULL THEN
    INSERT INTO membership_applications (
      user_id, applicant_email, status, full_name, phone, practice_type,
      based_in, about_work, commitment_agreed, submitted_at, membership_tier
    )
    VALUES (
      v_user, v_email, 'pending', btrim(p_full_name), btrim(p_phone), p_practice_type,
      p_based_in, btrim(p_about_work), true, now(), p_membership_tier
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE membership_applications
    SET full_name = btrim(p_full_name),
        phone = btrim(p_phone),
        practice_type = p_practice_type,
        based_in = p_based_in,
        about_work = btrim(p_about_work),
        commitment_agreed = true,
        submitted_at = now(),
        membership_tier = p_membership_tier
    WHERE id = v_id;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION submit_membership_interest(text, text, text, text, text, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION submit_membership_interest(text, text, text, text, text, boolean, text) TO authenticated;


-- SOURCE MIGRATION: 20261102131302_add_bookings_count_to_admin_kpis.sql.sql
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
    'paid_awaiting_activation', (
      SELECT count(*)::int FROM payment_transactions pt
      JOIN membership_applications ma ON ma.id = pt.membership_application_id
      WHERE pt.status = 'success' AND ma.status = 'pending'
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


-- SOURCE MIGRATION: 20261102132930_remove_paid_awaiting_activation_kpi.sql.sql
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


-- SOURCE MIGRATION: 20261102133024_add_email_param_to_membership_interest.sql.sql
CREATE OR REPLACE FUNCTION submit_membership_interest(
  p_full_name text,
  p_email text,
  p_phone text,
  p_practice_type text,
  p_based_in text,
  p_about_work text,
  p_commitment_agreed boolean,
  p_membership_tier text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Please sign in first' USING ERRCODE = '42501';
  END IF;

  IF char_length(btrim(coalesce(p_full_name, ''))) = 0 OR char_length(p_full_name) > 100 THEN
    RAISE EXCEPTION 'Please enter your full name';
  END IF;

  IF char_length(btrim(coalesce(p_email, ''))) = 0 OR p_email !~* '^[^@]+@[^@]+\.[^@]+$' THEN
    RAISE EXCEPTION 'Please enter a valid email address';
  END IF;

  IF char_length(btrim(coalesce(p_phone, ''))) = 0 OR char_length(p_phone) > 20 THEN
    RAISE EXCEPTION 'Please enter a valid phone number';
  END IF;

  IF p_practice_type IS NULL OR p_practice_type NOT IN ('researcher', 'creative', 'spatial_practitioner', 'collective', 'student', 'partner_institution', 'other') THEN
    RAISE EXCEPTION 'Choose what best describes you';
  END IF;

  IF p_based_in IS NULL OR p_based_in NOT IN ('accra', 'passing_through') THEN
    RAISE EXCEPTION 'Tell us where you are based';
  END IF;

  IF char_length(btrim(coalesce(p_about_work, ''))) = 0 OR char_length(p_about_work) > 1000 THEN
    RAISE EXCEPTION 'Tell us about your work (up to 1000 characters)';
  END IF;

  IF p_commitment_agreed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Please agree to the shared commitment to a fairer city';
  END IF;

  IF p_membership_tier IS NULL OR p_membership_tier NOT IN ('monthly', 'annual') THEN
    RAISE EXCEPTION 'Choose a membership option';
  END IF;

  SELECT id INTO v_id
  FROM membership_applications
  WHERE user_id = v_user AND status = 'pending'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_id IS NULL THEN
    INSERT INTO membership_applications (
      user_id, applicant_email, status, full_name, phone, practice_type,
      based_in, about_work, commitment_agreed, submitted_at, membership_tier
    )
    VALUES (
      v_user, btrim(p_email), 'pending', btrim(p_full_name), btrim(p_phone), p_practice_type,
      p_based_in, btrim(p_about_work), true, now(), p_membership_tier
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE membership_applications
    SET full_name = btrim(p_full_name),
        applicant_email = btrim(p_email),
        phone = btrim(p_phone),
        practice_type = p_practice_type,
        based_in = p_based_in,
        about_work = btrim(p_about_work),
        commitment_agreed = true,
        submitted_at = now(),
        membership_tier = p_membership_tier
    WHERE id = v_id;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION submit_membership_interest(text, text, text, text, text, text, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION submit_membership_interest(text, text, text, text, text, text, boolean, text) TO authenticated;

NOTIFY pgrst, 'reload schema';


-- SOURCE MIGRATION: 20261102135414_create_notification_tracking_and_digest.sql.sql
/*
# Admin notification tracking and daily digest function

1. New table: notification_log
   - Tracks every admin email sent so nothing is duplicated.
   - Columns: id, notification_type (signup|application|booking|approval|reminder), ref_id, sent_at.
   - Unique on (notification_type, ref_id) so the same event is never emailed twice.

2. New table: reminder_log
   - Tracks daily reminder emails (pending_apps|expired_memberships|blocked_dates) by date.
   - Unique on (reminder_type, reminder_date) so each reminder type fires at most once per day.

3. New function: get_daily_admin_digest()
   - Admin-only. Returns a single JSON object with:
     - pending_applications: rows with full applicant details + tier + submitted_at
     - expired_memberships: rows with member_email, tier, expired status, expiry date
     - upcoming_block_ends: stay_room_blocks ending in the next 7 days with room name + dates + reason
   - Used by the admin-notifications edge function for the daily reminder.

4. Security
   - notification_log and reminder_log are service_role only (written by edge functions).
   - get_daily_admin_digest is admin-only via is_edan_admin(), granted to authenticated.
*/

CREATE TABLE IF NOT EXISTS notification_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_type text NOT NULL,
  ref_id text NOT NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT notification_log_unique UNIQUE (notification_type, ref_id)
);

ALTER TABLE notification_log ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON notification_log TO service_role;

CREATE TABLE IF NOT EXISTS reminder_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reminder_type text NOT NULL,
  reminder_date date NOT NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reminder_log_unique UNIQUE (reminder_type, reminder_date)
);

ALTER TABLE reminder_log ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON reminder_log TO service_role;

CREATE OR REPLACE FUNCTION get_daily_admin_digest()
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
    'pending_applications', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', ma.id,
        'full_name', ma.full_name,
        'applicant_email', ma.applicant_email,
        'phone', ma.phone,
        'practice_type', ma.practice_type,
        'based_in', ma.based_in,
        'membership_tier', ma.membership_tier,
        'about_work', ma.about_work,
        'submitted_at', ma.submitted_at,
        'created_at', ma.created_at
      ) ORDER BY ma.submitted_at DESC NULLS LAST), '[]'::jsonb)
      FROM membership_applications ma
      WHERE ma.status = 'pending' AND ma.submitted_at IS NOT NULL
    ),
    'expired_memberships', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', m.id,
        'member_email', m.member_email,
        'membership_tier', m.membership_tier,
        'membership_status', CASE
          WHEN m.membership_status = 'expired' THEN 'expired'
          WHEN m.expires_at IS NOT NULL AND m.expires_at <= now() THEN 'expired'
          ELSE m.membership_status
        END,
        'expires_at', m.expires_at
      ) ORDER BY m.expires_at DESC NULLS LAST), '[]'::jsonb)
      FROM memberships m
      WHERE m.membership_status = 'expired'
         OR (m.membership_status = 'active' AND m.expires_at IS NOT NULL AND m.expires_at <= now())
    ),
    'upcoming_block_ends', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', b.id,
        'room_name', r.name,
        'starts_on', b.starts_on,
        'ends_on', b.ends_on,
        'reason', b.reason
      ) ORDER BY b.ends_on ASC), '[]'::jsonb)
      FROM stay_room_blocks b
      JOIN stay_rooms r ON r.id = b.room_id
      WHERE b.ends_on >= CURRENT_DATE
        AND b.ends_on <= CURRENT_DATE + interval '7 days'
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION get_daily_admin_digest() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_daily_admin_digest() TO authenticated;

NOTIFY pgrst, 'reload schema';


-- SOURCE MIGRATION: 20261102143542_20261102170000_expand_process_editorial_content.sql
/*
# Expand In Process editorial content

1. Purpose
- Adds the metadata needed to present the Members In Process area as an editorial project archive while preserving all existing rows and content.

2. Modified table: `member_process_items`
- `content_type`: identifies whether an entry is a project, journal update, or featured video.
- `is_featured`: marks a project for the featured project area.
- `progress_label`: stores progress text such as `60% complete` or `In progress`.
- `updated_label`: stores the visible update date or period.
- `video_path`: stores an optional video path for featured video entries.
- `poster_path`: stores an optional video thumbnail path.
- `duration_label`: stores optional visible video duration text.
- `link_url`: stores an optional internal or external project link.
- `link_label`: stores the optional visible link label.

3. Data safety
- All new columns are nullable-safe through defaults and existing records remain intact.
- No rows, columns, tables, or existing policies are removed.

4. Security
- Existing row-level security, grants, and admin/member policies on `member_process_items` remain in force.
- Members continue to read only published content, while existing admin policies control writes.
*/

ALTER TABLE member_process_items
  ADD COLUMN IF NOT EXISTS content_type text NOT NULL DEFAULT 'project',
  ADD COLUMN IF NOT EXISTS is_featured boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS progress_label text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS updated_label text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS video_path text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS poster_path text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS duration_label text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS link_url text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS link_label text NOT NULL DEFAULT 'View project';

ALTER TABLE member_process_items
  DROP CONSTRAINT IF EXISTS member_process_items_content_type_check;

ALTER TABLE member_process_items
  ADD CONSTRAINT member_process_items_content_type_check
  CHECK (content_type IN ('project', 'update', 'video'));

-- SOURCE MIGRATION: 20261102143828_20261102143543_seed_process_video_placeholder.sql
/*
# Seed an In Process video placeholder

1. Purpose
- Adds one published editorial video placeholder so the new In Process page demonstrates its video area immediately.

2. Data
- Creates `Research in Practice` only when no In Process video with that title exists.
- Uses an existing site image as the thumbnail and leaves the video path empty so no fake player controls are shown.

3. Security
- The row uses the existing `member_process_items` table policies.
- Active monthly and annual members can read it when published; admins can manage it through the existing dashboard.

4. Data safety
- The insert is idempotent and does not modify or remove existing rows.
*/

INSERT INTO member_process_items (
  title,
  summary,
  category,
  image_path,
  poster_path,
  content_type,
  duration_label,
  updated_label,
  is_published,
  sort_order
)
SELECT
  'Research in Practice',
  'A look inside our studio and ongoing research at Ɛdan.',
  'Studio journal',
  '/images/garden.jpg',
  '/images/garden.jpg',
  'video',
  '12:34',
  'Featured',
  true,
  90
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items
  WHERE content_type = 'video' AND title = 'Research in Practice'
);

-- SOURCE MIGRATION: 20261102144130_20261102150000_populate_process_sample_content.sql
/*
# Populate In Process section with editorial sample content

1. Purpose
- Replaces generic placeholder rows with realistic editorial sample data so the In Process section
  renders all of its designed areas: hero, featured project, ongoing projects, project updates, and featured video.

2. Changes
- Existing generic sample rows are updated in-place to become proper project and update entries.
- A featured project ("The Osu Courtyard Project") is flagged with is_featured = true.
- Four ongoing project rows are created if they do not already exist.
- Two project update rows are created if they do not already exist.
- The existing video row is updated with richer copy.

3. Data safety
- No rows are deleted.
- Existing rows are updated by known stable titles using WHERE title = '...' to avoid touching
  any content the admin may have added manually.
- New rows use WHERE NOT EXISTS guards so the migration is safe to re-run.
*/

-- Upgrade the two seed rows into proper project entries
UPDATE member_process_items
SET
  title        = 'The Osu Courtyard Project',
  summary      = 'Exploring the social life of space in Accra''s historic neighbourhood.',
  body         = 'An ongoing study of how courtyard spaces in Osu are used, adapted, and negotiated by the people who live around them. We are mapping patterns of occupation, light, and edge conditions across several blocks.',
  category     = 'Spatial Research',
  image_path   = '/images/breeze-block-detail.webp',
  content_type = 'project',
  is_featured  = true,
  updated_label = 'Updated: Apr 2025',
  progress_label = '60% complete',
  link_url     = '#in-process',
  link_label   = 'View project',
  sort_order   = 1
WHERE title = 'Sample: The studio table';

UPDATE member_process_items
SET
  title        = 'Clay in the City',
  summary      = 'Exploring local materials for contemporary use.',
  body         = 'A hands-on investigation into laterite, clay, and compressed earth as building components. We are testing mixes, firing temperatures, and load-bearing capacity in the studio.',
  category     = 'Material Studies',
  image_path   = '/images/breeze-block-terracotta.jpg',
  content_type = 'project',
  is_featured  = false,
  updated_label = 'Mar 2025',
  progress_label = 'In progress',
  link_url     = '#in-process',
  link_label   = 'View project',
  sort_order   = 3
WHERE title = 'Sample: Notes on a wall that has weathered';

-- Additional ongoing project: Spatial Experiments
INSERT INTO member_process_items (
  title, summary, category, image_path, content_type,
  updated_label, progress_label, link_url, link_label,
  is_featured, is_published, sort_order
)
SELECT
  'Spatial Experiments',
  'Testing spatial ideas through low-cost models.',
  'Research',
  '/images/architectural_sketch2.png',
  'project',
  'Apr 2025', 'In progress',
  '#in-process', 'View project',
  false, true, 4
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items WHERE title = 'Spatial Experiments'
);

-- Additional ongoing project: Notes from the City
INSERT INTO member_process_items (
  title, summary, category, image_path, content_type,
  updated_label, progress_label, link_url, link_label,
  is_featured, is_published, sort_order
)
SELECT
  'Notes from the City',
  'Observations and insights gathered from Accra.',
  'Urban Studies',
  '/images/accra-map.png',
  'project',
  'Mar 2025', 'Ongoing',
  '#in-process', 'View project',
  false, true, 5
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items WHERE title = 'Notes from the City'
);

-- Additional ongoing project: Studio Explorations
INSERT INTO member_process_items (
  title, summary, category, image_path, content_type,
  updated_label, progress_label, link_url, link_label,
  is_featured, is_published, sort_order
)
SELECT
  'Studio Explorations',
  'Prototyping new spatial possibilities.',
  'Design Exploration',
  '/images/model-guesthouse.jpg',
  'project',
  'Apr 2025', 'In progress',
  '#in-process', 'View project',
  false, true, 6
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items WHERE title = 'Studio Explorations'
);

-- Project update 1: Studio visit
INSERT INTO member_process_items (
  title, summary, category, image_path, content_type,
  updated_label, is_published, sort_order
)
SELECT
  'Studio visit: Accra Urban Lab',
  'A recent visit to the Accra Urban Lab sparked new ideas for our ongoing work.',
  'Studio update',
  '/images/sharing.webp',
  'update',
  'Apr 10, 2025',
  true, 20
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items WHERE title = 'Studio visit: Accra Urban Lab'
);

-- Project update 2: Material tests
INSERT INTO member_process_items (
  title, summary, category, image_path, content_type,
  updated_label, is_published, sort_order
)
SELECT
  'Material tests underway',
  'We''re testing local materials for the next phase of our research.',
  'Studio update',
  '/images/architectural sketch.png',
  'update',
  'Mar 28, 2025',
  true, 21
WHERE NOT EXISTS (
  SELECT 1 FROM member_process_items WHERE title = 'Material tests underway'
);

-- Enrich the existing video row
UPDATE member_process_items
SET
  summary        = 'A look inside our studio and ongoing research at Ɛdan.',
  category       = 'Studio journal',
  image_path     = '/images/garden.jpg',
  poster_path    = '/images/garden.jpg',
  duration_label = '12:34',
  updated_label  = 'Featured',
  is_published   = true,
  sort_order     = 90
WHERE title = 'Research in Practice' AND content_type = 'video';

-- SOURCE MIGRATION: 20261102144454_20261102160000_expand_gather_editorial_content.sql
/*
# Expand Gather editorial content

1. Purpose
- Adds the metadata needed for the Members Gather page to separate featured gatherings,
  upcoming events, past archive entries, and informal community moments.

2. Modified table: `member_gatherings`
- `category`: small editorial label such as Workshop or Talk.
- `gathering_type`: controls whether content appears as upcoming, past, or a community moment.
- `is_featured`: marks the gathering for the large featured area.
- `caption`: short archive or moment caption.

3. Data safety
- Existing rows remain intact and default to upcoming gatherings.
- No rows, columns, tables, or existing policies are removed.

4. Security
- Existing row-level security, grants, and member/admin policies remain in force.
*/

ALTER TABLE member_gatherings
  ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS gathering_type text NOT NULL DEFAULT 'upcoming',
  ADD COLUMN IF NOT EXISTS is_featured boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS caption text NOT NULL DEFAULT '';

ALTER TABLE member_gatherings
  DROP CONSTRAINT IF EXISTS member_gatherings_gathering_type_check;

ALTER TABLE member_gatherings
  ADD CONSTRAINT member_gatherings_gathering_type_check
  CHECK (gathering_type IN ('upcoming', 'past', 'moment'));

-- SOURCE MIGRATION: 20261102144536_20261102160100_seed_gather_editorial_content.sql
/*
# Seed Gather editorial sample content

1. Purpose
- Populates the Gather page with realistic placeholder content for its featured gathering,
  upcoming programme, past archive, and community moments areas.

2. Data
- All rows are marked published so active members can see the complete design immediately.
- Images use existing site assets and can be replaced by an administrator later.
- No real ticket prices, confirmed speakers, or invented event commitments are included.

3. Data safety
- Every insert is guarded by a title check and is safe to re-run.
- No existing rows are deleted or modified.

4. Security
- Rows use the existing member_gatherings RLS policies.
*/

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Conversations Around the City',
  'A dialogue on urban life, creativity and belonging in Accra.',
  NULL,
  'Ɛdan, Osu',
  '/images/garden-eat.jpg',
  '', true, 1, 'Featured gathering', 'upcoming', true, ''
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Conversations Around the City'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Material Encounters',
  'Explore materials, techniques and possibilities through an afternoon of making.',
  NULL,
  'Ɛdan, Osu',
  '/images/breeze-block-terracotta.jpg',
  '', true, 3, 'Workshop', 'upcoming', false, ''
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Material Encounters'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Shared Tables',
  'Food, ideas and community around one long table.',
  NULL,
  'Ɛdan, Osu',
  '/images/sharing.webp',
  '', true, 4, 'Talk', 'upcoming', false, ''
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Shared Tables'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Creative Research Gatherings',
  'A community forum for creative researchers and practitioners.',
  NULL,
  'Ɛdan, Osu',
  '/images/garden.jpg',
  '', true, 5, 'Gathering', 'upcoming', false, ''
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Creative Research Gatherings'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Open Studio Sessions',
  '', NULL, 'Ɛdan, Osu', '/images/our story people.jpg', '',
  true, 20, 'Archive', 'past', false, 'A day of shared practice and conversation.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Open Studio Sessions'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'A Table for Many Voices',
  '', NULL, 'Ɛdan, Osu', '/images/eat-hero.jpg', '',
  true, 21, 'Archive', 'past', false, 'An evening of food, stories and new connections.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'A Table for Many Voices'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Making Together',
  '', NULL, 'Ɛdan, Osu', '/images/dye-pits.jpg', '',
  true, 22, 'Archive', 'past', false, 'Hands, materials, and a few hours in the studio.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Making Together'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Ideas at the Table', '', NULL, '', '/images/architectural sketch.png', '',
  true, 30, 'Community moment', 'moment', false, 'Ideas taking shape.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Ideas at the Table'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'A Shared Afternoon', '', NULL, '', '/images/sharing.webp', '',
  true, 31, 'Community moment', 'moment', false, 'A slower afternoon at Ɛdan.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'A Shared Afternoon'
);

INSERT INTO member_gatherings (
  title, description, starts_at, location, image_path, registration_url,
  is_published, sort_order, category, gathering_type, is_featured, caption
)
SELECT
  'Outside Together', '', NULL, '', '/images/garden-eat.jpg', '',
  true, 32, 'Community moment', 'moment', false, 'The courtyard in conversation.'
WHERE NOT EXISTS (
  SELECT 1 FROM member_gatherings WHERE title = 'Outside Together'
);

-- SOURCE MIGRATION: 20261102150625_20261102160000_create_member_appointments.sql.sql
/*
# Create member appointment booking system

1. New tables
- `member_appointment_types`: active appointment options, descriptions, and durations.
- `member_appointment_slots`: administrator-created future times that can be available or blocked.
- `member_appointments`: annual-member booking requests linked to a selected type and slot.

2. Booking behavior
- Only active annual members can read available choices or submit requests.
- Slot reservation is performed atomically by a server function and protected by a unique active-slot index.
- Requests use `requested`, `confirmed`, `declined`, `cancelled`, and `completed` statuses.

3. Security
- RLS is enabled on every new table.
- Members can read only their own appointment records; administrators can manage the system.
- Members cannot directly insert, update, or delete appointment records.
- Privileged functions validate the authenticated caller, membership tier, availability, and booking state.

4. Dashboard
- `admin_dashboard_kpis()` gains an `appointments` count for upcoming requested and confirmed appointments.
*/

CREATE TABLE IF NOT EXISTS member_appointment_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 1000),
  duration_minutes integer NOT NULL DEFAULT 60 CHECK (duration_minutes BETWEEN 15 AND 240),
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS member_appointment_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'blocked')),
  notes text NOT NULL DEFAULT '' CHECK (length(notes) <= 500),
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  CHECK (ends_at - starts_at <= interval '4 hours')
);

CREATE TABLE IF NOT EXISTS member_appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_reference text NOT NULL UNIQUE DEFAULT ('EDN-APT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  appointment_type_id uuid NOT NULL REFERENCES member_appointment_types(id),
  slot_id uuid NOT NULL REFERENCES member_appointment_slots(id),
  member_name text NOT NULL CHECK (length(btrim(member_name)) BETWEEN 1 AND 120),
  member_email text NOT NULL CHECK (length(btrim(member_email)) BETWEEN 3 AND 254),
  whatsapp_number text NOT NULL DEFAULT '' CHECK (length(whatsapp_number) <= 40),
  member_note text NOT NULL DEFAULT '' CHECK (length(member_note) <= 2000),
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'confirmed', 'declined', 'cancelled', 'completed')),
  admin_note text NOT NULL DEFAULT '' CHECK (length(admin_note) <= 2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS member_appointment_slots_starts_at_idx ON member_appointment_slots (starts_at);
CREATE INDEX IF NOT EXISTS member_appointments_user_created_at_idx ON member_appointments (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS member_appointments_status_idx ON member_appointments (status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS member_appointments_active_slot_idx ON member_appointments (slot_id) WHERE status IN ('requested', 'confirmed');

INSERT INTO member_appointment_types (title, description, duration_minutes, sort_order)
SELECT * FROM (VALUES
  ('Introductory Conversation', 'A chance to meet the team, learn more about Ɛdan and explore possible ways to get involved.', 60, 1),
  ('Research Consultation', 'A focused conversation around research interests, questions, ideas or ongoing work.', 60, 2),
  ('Creative Working Session', 'Dedicated time to discuss, develop or work through a creative idea or project.', 90, 3),
  ('Membership Support', 'A session for questions about membership, access or using the space.', 30, 4)
) AS defaults(title, description, duration_minutes, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM member_appointment_types);

ALTER TABLE member_appointment_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_appointment_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_appointments ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON member_appointment_types, member_appointment_slots, member_appointments TO authenticated;

DROP POLICY IF EXISTS "annual_members_select_appointment_types" ON member_appointment_types;
CREATE POLICY "annual_members_select_appointment_types" ON member_appointment_types FOR SELECT TO authenticated USING (is_active_member(ARRAY['annual'::text]) OR is_edan_admin());
DROP POLICY IF EXISTS "admins_insert_appointment_types" ON member_appointment_types;
CREATE POLICY "admins_insert_appointment_types" ON member_appointment_types FOR INSERT TO authenticated WITH CHECK (is_edan_admin());
DROP POLICY IF EXISTS "admins_update_appointment_types" ON member_appointment_types;
CREATE POLICY "admins_update_appointment_types" ON member_appointment_types FOR UPDATE TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());
DROP POLICY IF EXISTS "admins_delete_appointment_types" ON member_appointment_types;
CREATE POLICY "admins_delete_appointment_types" ON member_appointment_types FOR DELETE TO authenticated USING (is_edan_admin());

DROP POLICY IF EXISTS "annual_members_select_appointment_slots" ON member_appointment_slots;
CREATE POLICY "annual_members_select_appointment_slots" ON member_appointment_slots FOR SELECT TO authenticated USING ((status = 'available' AND starts_at > now() AND is_active_member(ARRAY['annual'::text])) OR is_edan_admin());
DROP POLICY IF EXISTS "admins_insert_appointment_slots" ON member_appointment_slots;
CREATE POLICY "admins_insert_appointment_slots" ON member_appointment_slots FOR INSERT TO authenticated WITH CHECK (is_edan_admin() AND created_by = auth.uid());
DROP POLICY IF EXISTS "admins_update_appointment_slots" ON member_appointment_slots;
CREATE POLICY "admins_update_appointment_slots" ON member_appointment_slots FOR UPDATE TO authenticated USING (is_edan_admin()) WITH CHECK (is_edan_admin());
DROP POLICY IF EXISTS "admins_delete_appointment_slots" ON member_appointment_slots;
CREATE POLICY "admins_delete_appointment_slots" ON member_appointment_slots FOR DELETE TO authenticated USING (is_edan_admin());

DROP POLICY IF EXISTS "members_select_own_appointments" ON member_appointments;
CREATE POLICY "members_select_own_appointments" ON member_appointments FOR SELECT TO authenticated USING (user_id = auth.uid() OR is_edan_admin());

CREATE OR REPLACE FUNCTION get_member_appointment_slots(p_from timestamptz, p_to timestamptz)
RETURNS TABLE (id uuid, starts_at timestamptz, ends_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_active_member(ARRAY['annual'::text]) THEN RAISE EXCEPTION 'Appointment access requires an active annual membership'; END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_to <= p_from OR p_to - p_from > interval '90 days' THEN RAISE EXCEPTION 'Invalid appointment date range'; END IF;
  RETURN QUERY SELECT s.id, s.starts_at, s.ends_at
  FROM member_appointment_slots s
  WHERE s.status = 'available' AND s.starts_at >= p_from AND s.starts_at < p_to AND s.starts_at > now()
    AND NOT EXISTS (SELECT 1 FROM member_appointments a WHERE a.slot_id = s.id AND a.status IN ('requested', 'confirmed'))
  ORDER BY s.starts_at;
END;
$$;

CREATE OR REPLACE FUNCTION create_member_appointment(p_appointment_type_id uuid, p_slot_id uuid, p_member_name text, p_member_email text, p_whatsapp_number text, p_member_note text)
RETURNS TABLE (id uuid, booking_reference text, status text, starts_at timestamptz, ends_at timestamptz, appointment_title text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_slot member_appointment_slots%ROWTYPE; v_type member_appointment_types%ROWTYPE; v_appointment member_appointments%ROWTYPE;
BEGIN
  IF NOT is_active_member(ARRAY['annual'::text]) THEN RAISE EXCEPTION 'Appointment access requires an active annual membership'; END IF;
  IF length(btrim(coalesce(p_member_name, ''))) NOT BETWEEN 1 AND 120 OR length(btrim(coalesce(p_member_email, ''))) NOT BETWEEN 3 AND 254 OR length(coalesce(p_whatsapp_number, '')) > 40 OR length(coalesce(p_member_note, '')) > 2000 THEN RAISE EXCEPTION 'Please check the appointment details'; END IF;
  SELECT * INTO v_type FROM member_appointment_types WHERE id = p_appointment_type_id AND is_active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'That appointment type is unavailable'; END IF;
  SELECT * INTO v_slot FROM member_appointment_slots WHERE id = p_slot_id FOR UPDATE;
  IF NOT FOUND OR v_slot.status <> 'available' OR v_slot.starts_at <= now() THEN RAISE EXCEPTION 'That time is no longer available'; END IF;
  IF EXISTS (SELECT 1 FROM member_appointments WHERE slot_id = p_slot_id AND status IN ('requested', 'confirmed')) THEN RAISE EXCEPTION 'That time is no longer available'; END IF;
  INSERT INTO member_appointments (user_id, appointment_type_id, slot_id, member_name, member_email, whatsapp_number, member_note)
  VALUES (auth.uid(), p_appointment_type_id, p_slot_id, btrim(p_member_name), lower(btrim(p_member_email)), btrim(coalesce(p_whatsapp_number, '')), btrim(coalesce(p_member_note, '')))
  RETURNING * INTO v_appointment;
  RETURN QUERY SELECT v_appointment.id, v_appointment.booking_reference, v_appointment.status, v_slot.starts_at, v_slot.ends_at, v_type.title;
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'That time is no longer available';
END;
$$;

CREATE OR REPLACE FUNCTION admin_create_appointment_slot(p_starts_at timestamptz, p_ends_at timestamptz, p_notes text DEFAULT '')
RETURNS member_appointment_slots LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_slot member_appointment_slots;
BEGIN
  IF NOT is_edan_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_starts_at <= now() OR p_ends_at <= p_starts_at OR p_ends_at - p_starts_at > interval '4 hours' THEN RAISE EXCEPTION 'Please enter a valid future appointment time'; END IF;
  INSERT INTO member_appointment_slots (starts_at, ends_at, notes, created_by) VALUES (p_starts_at, p_ends_at, btrim(coalesce(p_notes, '')), auth.uid()) RETURNING * INTO v_slot;
  RETURN v_slot;
END;
$$;

CREATE OR REPLACE FUNCTION admin_set_appointment_slot_status(p_slot_id uuid, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_edan_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_status NOT IN ('available', 'blocked') THEN RAISE EXCEPTION 'Invalid slot status'; END IF;
  UPDATE member_appointment_slots SET status = p_status WHERE id = p_slot_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Slot not found'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION admin_set_appointment_status(p_appointment_id uuid, p_status text, p_admin_note text DEFAULT '')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_edan_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_status NOT IN ('confirmed', 'declined', 'cancelled', 'completed') THEN RAISE EXCEPTION 'Invalid appointment status'; END IF;
  UPDATE member_appointments SET status = p_status, admin_note = btrim(coalesce(p_admin_note, '')), updated_at = now(), confirmed_at = CASE WHEN p_status = 'confirmed' THEN coalesce(confirmed_at, now()) ELSE confirmed_at END, completed_at = CASE WHEN p_status = 'completed' THEN coalesce(completed_at, now()) ELSE completed_at END WHERE id = p_appointment_id AND status NOT IN ('declined', 'cancelled', 'completed');
  IF NOT FOUND THEN RAISE EXCEPTION 'Appointment is unavailable for that change'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION get_member_appointment_slots(timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_member_appointment_slots(timestamptz, timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION create_member_appointment(uuid, uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_member_appointment(uuid, uuid, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION admin_create_appointment_slot(timestamptz, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_create_appointment_slot(timestamptz, timestamptz, text) TO authenticated;
REVOKE ALL ON FUNCTION admin_set_appointment_slot_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_set_appointment_slot_status(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION admin_set_appointment_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_set_appointment_status(uuid, text, text) TO authenticated;

DROP FUNCTION IF EXISTS admin_dashboard_kpis();
CREATE FUNCTION admin_dashboard_kpis()
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result json;
BEGIN
  IF NOT is_edan_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT json_build_object(
    'active_members', (SELECT count(*) FROM memberships WHERE membership_status = 'active' AND (expires_at IS NULL OR expires_at > now())),
    'pending_review', (SELECT count(*) FROM membership_applications WHERE status = 'pending'),
    'expired', (SELECT count(*) FROM memberships WHERE membership_status = 'expired' OR (membership_status = 'active' AND expires_at IS NOT NULL AND expires_at <= now())),
    'total_bookings', (SELECT count(*) FROM stay_bookings WHERE status IN ('confirmed', 'completed')),
    'appointments', (SELECT count(*) FROM member_appointments a JOIN member_appointment_slots s ON s.id = a.slot_id WHERE a.status IN ('requested', 'confirmed') AND s.starts_at >= now())
  ) INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_dashboard_kpis() TO authenticated;

-- SOURCE MIGRATION: 20261102215241_20261102170000_refresh_member_appointments_api_and_seed_samples.sql.sql
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

-- SOURCE MIGRATION: 20261102215855_sync_member_appointment_samples_and_api.sql
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

-- SOURCE MIGRATION: 20261102221630_20261102160000_create_member_page_settings.sql
/*
# Create editable Members page settings

1. New Tables
- `member_page_settings`
- `id`: single settings-record key.
- `hero_eyebrow`, `hero_title`, `hero_image_path`: Members page welcome area.
- `membership_eyebrow`, `membership_intro`: membership overview copy.
- `benefits`: ordered JSON list of membership benefit labels.
- `community_image_path`, `community_eyebrow`, `community_title`, `community_description`: Community section presentation.
- `process_image_path`, `process_eyebrow`, `process_title`, `process_description`: In Process section presentation.
- `gather_image_path`, `gather_eyebrow`, `gather_title`, `gather_description`: Gather section presentation.
- `research_image_path`, `research_eyebrow`, `research_title`, `research_description`: Research section presentation.
- `bonus_image_path`, `bonus_eyebrow`, `bonus_title`, `bonus_description`: Bonus content section presentation.
- `appointments_image_path`, `appointments_eyebrow`, `appointments_title`, `appointments_description`: Appointments section presentation.
- `created_at`, `updated_at`: record timestamps.

2. Modified Tables
- None.

3. Security
- Row-level security is enabled.
- Active monthly and annual members can read the settings.
- Authenticated Ɛdan admins can read, insert, and update the settings.
- No anonymous access is granted because this page is member-only.

4. Important Notes
- The table intentionally contains one row with the key `default`.
- The benefits field is restricted to a JSON array so the dashboard can preserve order.
- Existing page content remains available as a visual fallback until the frontend begins loading these settings.
*/

CREATE TABLE IF NOT EXISTS public.member_page_settings (
  id text PRIMARY KEY DEFAULT 'default' CHECK (id = 'default'),
  hero_eyebrow text NOT NULL DEFAULT 'Members',
  hero_title text NOT NULL DEFAULT 'Welcome to Ɛdan.',
  hero_image_path text NOT NULL DEFAULT '/images/breeze-block-hero.jpg',
  membership_eyebrow text NOT NULL DEFAULT 'Your place at Ɛdan',
  membership_intro text NOT NULL DEFAULT 'Your membership gives you a place to connect, learn and take part in the life of Ɛdan.',
  benefits jsonb NOT NULL DEFAULT '["Community chat", "Behind-the-scenes content", "Monthly social invitations", "10% off Small Moments and Ɛdan residencies", "Bonus videos", "One-to-one appointments"]'::jsonb CHECK (jsonb_typeof(benefits) = 'array'),
  community_image_path text NOT NULL DEFAULT '/images/comm.avif',
  community_eyebrow text NOT NULL DEFAULT '01 / Community',
  community_title text NOT NULL DEFAULT 'Talk with the members.',
  community_description text NOT NULL DEFAULT 'A warm space for ideas, questions and everyday conversation across the Ɛdan community.',
  process_image_path text NOT NULL DEFAULT '/images/breeze-block-detail.jpg',
  process_eyebrow text NOT NULL DEFAULT '02 / In Process',
  process_title text NOT NULL DEFAULT 'Work in progress.',
  process_description text NOT NULL DEFAULT 'An ongoing collection of ideas, experiments and projects taking shape at Ɛdan.',
  gather_image_path text NOT NULL DEFAULT '/images/garden-eat.jpg',
  gather_eyebrow text NOT NULL DEFAULT '03 / Gather',
  gather_title text NOT NULL DEFAULT 'Come together.',
  gather_description text NOT NULL DEFAULT 'A space for conversations, shared experiences and moments that bring our community together.',
  research_image_path text NOT NULL DEFAULT '/images/our story intro.jpg',
  research_eyebrow text NOT NULL DEFAULT '04 / Research',
  research_title text NOT NULL DEFAULT 'Ideas in the making.',
  research_description text NOT NULL DEFAULT 'Notes, observations and research exploring the relationships between people, space and the city.',
  bonus_image_path text NOT NULL DEFAULT '/images/our story image.webp',
  bonus_eyebrow text NOT NULL DEFAULT '05 / Bonus content',
  bonus_title text NOT NULL DEFAULT 'A little further in.',
  bonus_description text NOT NULL DEFAULT 'Films, conversations and research offering a closer look at the ideas, people and processes shaping Ɛdan.',
  appointments_image_path text NOT NULL DEFAULT '/images/our story people.jpg',
  appointments_eyebrow text NOT NULL DEFAULT '06 / Appointments',
  appointments_title text NOT NULL DEFAULT 'Let''s make time.',
  appointments_description text NOT NULL DEFAULT 'Book a conversation, consultation or working session with the Ɛdan team.',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.member_page_settings ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.member_page_settings TO authenticated;
GRANT INSERT, UPDATE ON public.member_page_settings TO authenticated;

DROP POLICY IF EXISTS "active_members_select_member_page_settings" ON public.member_page_settings;
CREATE POLICY "active_members_select_member_page_settings"
  ON public.member_page_settings FOR SELECT
  TO authenticated
  USING (is_active_member(ARRAY['monthly'::text, 'annual'::text]) OR is_edan_admin());

DROP POLICY IF EXISTS "admins_insert_member_page_settings" ON public.member_page_settings;
CREATE POLICY "admins_insert_member_page_settings"
  ON public.member_page_settings FOR INSERT
  TO authenticated
  WITH CHECK (is_edan_admin());

DROP POLICY IF EXISTS "admins_update_member_page_settings" ON public.member_page_settings;
CREATE POLICY "admins_update_member_page_settings"
  ON public.member_page_settings FOR UPDATE
  TO authenticated
  USING (is_edan_admin())
  WITH CHECK (is_edan_admin());

INSERT INTO public.member_page_settings (id)
VALUES ('default')
ON CONFLICT (id) DO NOTHING;


-- SOURCE MIGRATION: 20261102222131_20261102223000_create_member_content_views_and_insights.sql
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


-- SOURCE MIGRATION: 20261102222141_20261102223100_add_titles_to_member_content_insights.sql
/*
# Add readable titles to Members activity insights

1. Modified Functions
- `admin_member_content_insights` now returns `content_title` alongside the content type, identifier, count, and latest view time.

2. Security
- The function remains SECURITY DEFINER and callable only by authenticated Ɛdan admins.

3. Important Notes
- Titles are resolved only from published member content.
- Page-level activity is labelled `Members page`.
*/

DROP FUNCTION IF EXISTS public.admin_member_content_insights();
CREATE OR REPLACE FUNCTION public.admin_member_content_insights()
RETURNS TABLE (
  content_type text,
  content_id uuid,
  content_title text,
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
  SELECT
    v.content_type,
    v.content_id,
    CASE v.content_type
      WHEN 'gathering' THEN (SELECT g.title FROM public.member_gatherings g WHERE g.id = v.content_id AND g.is_published)
      WHEN 'research' THEN (SELECT r.title FROM public.member_research_items r WHERE r.id = v.content_id AND r.is_published)
      WHEN 'process' THEN (SELECT p.title FROM public.member_process_items p WHERE p.id = v.content_id AND p.is_published)
      WHEN 'bonus_video' THEN (SELECT b.title FROM public.member_bonus_videos b WHERE b.id = v.content_id AND b.is_published)
      ELSE 'Members page'
    END,
    count(*)::bigint,
    max(v.created_at)
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


-- SOURCE MIGRATION: 20261102222212_20261102223200_limit_member_media_uploads.sql
/*
# Set safe limits for member media uploads

1. Modified Storage
- `site-videos`: allow MP4 and WebM uploads up to 30 MB.

2. Security
- Existing admin-only storage policies remain unchanged.

3. Important Notes
- The browser validates the same limits for usability, while the bucket enforces them at the storage boundary.
*/

UPDATE storage.buckets
SET file_size_limit = 31457280,
    allowed_mime_types = ARRAY['video/mp4', 'video/webm']::text[]
WHERE id = 'site-videos';


-- SOURCE MIGRATION: 20261103091347_20261103120000_allow_member_requested_appointment_dates.sql
/*
# Allow members to request appointment dates without published availability

1. Purpose
- Let active annual members choose a future date and preferred time directly from the Members page.
- Keep the existing appointment tables and administrator workflow intact.
- Record the requested date and time even when no administrator-created availability slot exists.

2. Modified tables
- `member_appointments`
- `requested_start_at` (timestamptz, nullable): the date and preferred start time requested by the member.
- `slot_id` becomes nullable for date-based requests; existing slot-backed appointments are unchanged.

3. New booking behavior
- Adds an overloaded `create_member_appointment` function that validates the member, appointment type, future requested time, and contact details.
- The requested end time is calculated from the selected appointment type duration.
- Existing slot-based bookings remain supported by the original function.

4. Security
- Existing RLS policies remain in place.
- The new booking function is callable only by authenticated users and checks active annual membership before inserting.
- No public or anonymous access is added.

5. Important notes
- No existing appointment rows are deleted or rewritten.
- Existing administrator-created slots continue to work.
- The new nullable field allows the dashboard and notification email to show the member's requested date and time.
*/

ALTER TABLE public.member_appointments
  ADD COLUMN IF NOT EXISTS requested_start_at timestamptz;

ALTER TABLE public.member_appointments
  ALTER COLUMN slot_id DROP NOT NULL;

CREATE INDEX IF NOT EXISTS member_appointments_requested_start_idx
  ON public.member_appointments (requested_start_at)
  WHERE requested_start_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.create_member_appointment(
  p_appointment_type_id uuid,
  p_requested_start_at timestamptz,
  p_member_name text,
  p_member_email text,
  p_whatsapp_number text,
  p_member_note text
)
RETURNS TABLE (
  id uuid,
  booking_reference text,
  status text,
  starts_at timestamptz,
  ends_at timestamptz,
  appointment_title text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type member_appointment_types%ROWTYPE;
  v_appointment member_appointments%ROWTYPE;
BEGIN
  IF NOT is_active_member(ARRAY['annual'::text]) THEN
    RAISE EXCEPTION 'Appointment access requires an active annual membership';
  END IF;

  IF p_requested_start_at IS NULL
     OR p_requested_start_at <= now()
     OR p_requested_start_at > now() + interval '180 days'
     OR length(btrim(coalesce(p_member_name, ''))) NOT BETWEEN 1 AND 120
     OR length(btrim(coalesce(p_member_email, ''))) NOT BETWEEN 3 AND 254
     OR length(coalesce(p_whatsapp_number, '')) > 40
     OR length(coalesce(p_member_note, '')) > 2000 THEN
    RAISE EXCEPTION 'Please check the appointment details';
  END IF;

  SELECT * INTO v_type
  FROM member_appointment_types
  WHERE id = p_appointment_type_id AND is_active
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'That appointment type is unavailable';
  END IF;

  INSERT INTO member_appointments (
    user_id,
    appointment_type_id,
    slot_id,
    requested_start_at,
    member_name,
    member_email,
    whatsapp_number,
    member_note
  )
  VALUES (
    auth.uid(),
    p_appointment_type_id,
    NULL,
    p_requested_start_at,
    btrim(p_member_name),
    lower(btrim(p_member_email)),
    btrim(coalesce(p_whatsapp_number, '')),
    btrim(coalesce(p_member_note, ''))
  )
  RETURNING * INTO v_appointment;

  RETURN QUERY
  SELECT
    v_appointment.id,
    v_appointment.booking_reference,
    v_appointment.status,
    p_requested_start_at,
    p_requested_start_at + make_interval(mins => v_type.duration_minutes),
    v_type.title;
END;
$$;

REVOKE ALL ON FUNCTION public.create_member_appointment(uuid, timestamptz, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_member_appointment(uuid, timestamptz, text, text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- SOURCE MIGRATION: 20261103092400_20261103150000_cleanup_submit_membership_interest_overloads.sql
/*
# Clean up submit_membership_interest overloads

1. Summary
- The gather page membership interest form was failing because PostgREST's
  schema cache could not resolve `submit_membership_interest` — three overloads
  existed in the database (6, 7, and 8 parameters) and the stale ones prevented
  reliable resolution.
- This migration drops the two old overloads, keeps only the 8-parameter version
  (with p_email), and reloads the PostgREST schema cache.

2. Modified functions
- DROPPED: submit_membership_interest(text, text, text, text, text, boolean)
  — the original 6-param version (no tier, no email param).
- DROPPED: submit_membership_interest(text, text, text, text, text, boolean, text)
  — the 7-param version (tier added, email derived from JWT).
- KEPT: submit_membership_interest(text, text, text, text, text, text, boolean, text)
  — the 8-param version (p_full_name, p_email, p_phone, p_practice_type,
  p_based_in, p_about_work, p_commitment_agreed, p_membership_tier) which the
  frontend calls.

3. Security
- No new tables, columns, or policies. The surviving function is SECURITY
  DEFINER, executable only by authenticated users (existing grants).
*/

DROP FUNCTION IF EXISTS public.submit_membership_interest(text, text, text, text, text, boolean);
DROP FUNCTION IF EXISTS public.submit_membership_interest(text, text, text, text, text, boolean, text);

-- The 8-param version is recreated here to ensure it survives cleanly.
CREATE OR REPLACE FUNCTION submit_membership_interest(
  p_full_name text,
  p_email text,
  p_phone text,
  p_practice_type text,
  p_based_in text,
  p_about_work text,
  p_commitment_agreed boolean,
  p_membership_tier text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Please sign in first' USING ERRCODE = '42501';
  END IF;

  IF char_length(btrim(coalesce(p_full_name, ''))) = 0 OR char_length(p_full_name) > 100 THEN
    RAISE EXCEPTION 'Please enter your full name';
  END IF;

  IF char_length(btrim(coalesce(p_email, ''))) = 0 OR p_email !~* '^[^@]+@[^@]+\.[^@]+$' THEN
    RAISE EXCEPTION 'Please enter a valid email address';
  END IF;

  IF char_length(btrim(coalesce(p_phone, ''))) = 0 OR char_length(p_phone) > 20 THEN
    RAISE EXCEPTION 'Please enter a valid phone number';
  END IF;

  IF p_practice_type IS NULL OR p_practice_type NOT IN ('researcher', 'creative', 'spatial_practitioner', 'collective', 'student', 'partner_institution', 'other') THEN
    RAISE EXCEPTION 'Choose what best describes you';
  END IF;

  IF p_based_in IS NULL OR p_based_in NOT IN ('accra', 'passing_through') THEN
    RAISE EXCEPTION 'Tell us where you are based';
  END IF;

  IF char_length(btrim(coalesce(p_about_work, ''))) = 0 OR char_length(p_about_work) > 1000 THEN
    RAISE EXCEPTION 'Tell us about your work (up to 1000 characters)';
  END IF;

  IF p_commitment_agreed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Please agree to the shared commitment to a fairer city';
  END IF;

  IF p_membership_tier IS NULL OR p_membership_tier NOT IN ('monthly', 'annual') THEN
    RAISE EXCEPTION 'Choose a membership option';
  END IF;

  SELECT id INTO v_id
  FROM membership_applications
  WHERE user_id = v_user AND status = 'pending'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_id IS NULL THEN
    INSERT INTO membership_applications (
      user_id, applicant_email, status, full_name, phone, practice_type,
      based_in, about_work, commitment_agreed, submitted_at, membership_tier
    )
    VALUES (
      v_user, btrim(p_email), 'pending', btrim(p_full_name), btrim(p_phone), p_practice_type,
      p_based_in, btrim(p_about_work), true, now(), p_membership_tier
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE membership_applications
    SET full_name = btrim(p_full_name),
        applicant_email = btrim(p_email),
        phone = btrim(p_phone),
        practice_type = p_practice_type,
        based_in = p_based_in,
        about_work = btrim(p_about_work),
        commitment_agreed = true,
        submitted_at = now(),
        membership_tier = p_membership_tier
    WHERE id = v_id;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION submit_membership_interest(text, text, text, text, text, text, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION submit_membership_interest(text, text, text, text, text, text, boolean, text) TO authenticated;

NOTIFY pgrst, 'reload schema';


-- SOURCE MIGRATION: 20261103202110_20261103110000_harden_public_data_api_grants.sql.sql
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

-- SOURCE MIGRATION: 20261103204303_20261103223000_add_content_titles_to_member_insights.sql.sql
/*
# Include content titles in member insights

1. Modified Functions
- `admin_member_content_insights()` now returns `content_title` alongside the content type, content id, view count, and latest view time.
- Titles are resolved only from the corresponding content table, and the Members page is labelled directly.

2. Tables and Columns
- No tables or columns are added or changed.

3. Security
- The function remains `SECURITY DEFINER` and admin-only.
- Public and anonymous execution remains revoked.
- Authenticated execution remains available for the existing admin dashboard.

4. Important Notes
- This aligns the RPC response with the dashboard's existing content-insights display.
- Existing view-count aggregation and published-content filtering are unchanged.
*/

DROP FUNCTION IF EXISTS public.admin_member_content_insights();

CREATE OR REPLACE FUNCTION public.admin_member_content_insights()
RETURNS TABLE (
  content_type text,
  content_id uuid,
  content_title text,
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
  SELECT
    v.content_type,
    v.content_id,
    CASE v.content_type
      WHEN 'gathering' THEN (SELECT g.title FROM public.member_gatherings g WHERE g.id = v.content_id AND g.is_published)
      WHEN 'research' THEN (SELECT r.title FROM public.member_research_items r WHERE r.id = v.content_id AND r.is_published)
      WHEN 'process' THEN (SELECT p.title FROM public.member_process_items p WHERE p.id = v.content_id AND p.is_published)
      WHEN 'bonus_video' THEN (SELECT b.title FROM public.member_bonus_videos b WHERE b.id = v.content_id AND b.is_published)
      WHEN 'page' THEN 'Members page'
      ELSE NULL
    END,
    count(*)::bigint,
    max(v.created_at)
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

NOTIFY pgrst, 'reload schema';

-- SOURCE MIGRATION: 20261103212203_20261103210000_20261103230000_include_requested_appointments_in_kpis.sql.sql
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
AS $
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
$;

REVOKE EXECUTE ON FUNCTION public.admin_dashboard_kpis() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_kpis() TO authenticated;

NOTIFY pgrst, 'reload schema';
