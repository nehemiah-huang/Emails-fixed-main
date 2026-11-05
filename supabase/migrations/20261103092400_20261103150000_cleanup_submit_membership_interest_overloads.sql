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
