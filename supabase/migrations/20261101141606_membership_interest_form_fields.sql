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
