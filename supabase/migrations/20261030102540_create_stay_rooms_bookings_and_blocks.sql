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
