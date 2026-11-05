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