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
