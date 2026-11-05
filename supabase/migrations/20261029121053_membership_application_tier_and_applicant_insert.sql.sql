ALTER TABLE membership_applications
  ADD COLUMN IF NOT EXISTS membership_tier text CHECK (membership_tier IN ('monthly', 'annual'));

GRANT INSERT ON membership_applications TO authenticated;

DROP POLICY IF EXISTS "insert_own_pending_membership_application" ON membership_applications;
CREATE POLICY "insert_own_pending_membership_application" ON membership_applications FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id AND status = 'pending');
