-- ============================================================
-- Step 2: Create 6 RPCs for admin session management
-- Run in Supabase SQL Editor
-- search_path includes 'extensions' so that pgcrypto digest()
-- can be resolved (Supabase installs pgcrypto in extensions schema)
-- ============================================================


-- ------------------------------------------------------------
-- 1. create_admin_session
--    Verify admin PIN and issue a session token.
--    Replaces verify_admin_pin for admin-app.html login.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_admin_session(
  admin_id_input uuid,
  pin_input      text
)
RETURNS TABLE (
  id            uuid,
  name          text,
  is_active     boolean,
  session_token text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin  public.genka_admins%ROWTYPE;
  v_token  text;
BEGIN
  -- Verify PIN and active status
  SELECT *
  INTO   v_admin
  FROM   public.genka_admins g
  WHERE  g.id        = admin_id_input
    AND  g.pin       = pin_input
    AND  g.is_active = true;

  -- Return empty if credentials do not match
  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Delete existing sessions for this admin and all expired sessions
  DELETE FROM public.admin_sessions s
  WHERE  s.admin_id   = admin_id_input
     OR  s.expires_at < now();

  -- Generate 32-byte random token (64-char hex string)
  v_token := encode(gen_random_bytes(32), 'hex');

  -- Store only the hash; never store the raw token in DB
  INSERT INTO public.admin_sessions (admin_id, token_hash, expires_at)
  VALUES (
    admin_id_input,
    encode(digest(v_token, 'sha256'), 'hex'),
    now() + interval '8 hours'
  );

  -- Return raw token to client (pin is NOT returned)
  RETURN QUERY
  SELECT v_admin.id, v_admin.name, v_admin.is_active, v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_admin_session(uuid, text)
  TO anon, authenticated;


-- ------------------------------------------------------------
-- 2. create_employee_secure
--    Create a new employee after verifying admin session token.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_employee_secure(
  session_token_input text,
  name_input          text,
  pin_input           text,
  role_input          text,
  company_id_input    uuid,
  is_active_input     boolean DEFAULT true
)
RETURNS TABLE (id uuid, name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Verify session token
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Validate inputs
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION 'Name is required';
  END IF;

  IF pin_input IS NULL OR length(pin_input) <> 4 THEN
    RAISE EXCEPTION 'PIN must be 4 digits';
  END IF;

  -- Insert new employee
  RETURN QUERY
  INSERT INTO public.employees (name, pin, role, company_id, is_active)
  VALUES (
    trim(name_input),
    pin_input,
    role_input,
    company_id_input,
    is_active_input
  )
  RETURNING employees.id, employees.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_employee_secure(text, text, text, text, uuid, boolean)
  TO anon, authenticated;


-- ------------------------------------------------------------
-- 3. update_employee_secure
--    Update an existing employee after verifying admin session.
--    If new_pin_input is NULL, the PIN is not changed.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_employee_secure(
  session_token_input text,
  id_input            uuid,
  name_input          text,
  role_input          text,
  is_active_input     boolean,
  company_id_input    uuid,
  new_pin_input       text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Verify session token
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Validate inputs
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION 'Name is required';
  END IF;

  IF new_pin_input IS NOT NULL AND length(new_pin_input) <> 4 THEN
    RAISE EXCEPTION 'PIN must be 4 digits';
  END IF;

  -- Update without changing PIN
  IF new_pin_input IS NULL THEN
    UPDATE public.employees e
    SET    name       = trim(name_input),
           role       = role_input,
           is_active  = is_active_input,
           company_id = company_id_input
    WHERE  e.id = id_input;
  ELSE
  -- Update including PIN change
    UPDATE public.employees e
    SET    name       = trim(name_input),
           role       = role_input,
           is_active  = is_active_input,
           company_id = company_id_input,
           pin        = new_pin_input
    WHERE  e.id = id_input;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_employee_secure(text, uuid, text, text, boolean, uuid, text)
  TO anon, authenticated;


-- ------------------------------------------------------------
-- 4. create_genka_admin_secure
--    Create a new genka admin after verifying admin session.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_genka_admin_secure(
  session_token_input text,
  name_input          text,
  pin_input           text
)
RETURNS TABLE (id uuid, name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Verify session token
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Validate inputs
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION 'Name is required';
  END IF;

  IF pin_input IS NULL OR length(pin_input) <> 4 THEN
    RAISE EXCEPTION 'PIN must be 4 digits';
  END IF;

  RETURN QUERY
  INSERT INTO public.genka_admins (name, pin, is_active)
  VALUES (trim(name_input), pin_input, true)
  RETURNING genka_admins.id, genka_admins.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_genka_admin_secure(text, text, text)
  TO anon, authenticated;


-- ------------------------------------------------------------
-- 5. update_genka_admin_secure
--    Update an existing genka admin after verifying admin session.
--    If new_pin_input is NULL, the PIN is not changed.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_genka_admin_secure(
  session_token_input text,
  id_input            uuid,
  name_input          text,
  is_active_input     boolean,
  new_pin_input       text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Verify session token
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Validate inputs
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION 'Name is required';
  END IF;

  IF new_pin_input IS NOT NULL AND length(new_pin_input) <> 4 THEN
    RAISE EXCEPTION 'PIN must be 4 digits';
  END IF;

  -- Update without changing PIN
  IF new_pin_input IS NULL THEN
    UPDATE public.genka_admins g
    SET    name      = trim(name_input),
           is_active = is_active_input
    WHERE  g.id = id_input;
  ELSE
  -- Update including PIN change
    UPDATE public.genka_admins g
    SET    name      = trim(name_input),
           is_active = is_active_input,
           pin       = new_pin_input
    WHERE  g.id = id_input;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_genka_admin_secure(text, uuid, text, boolean, text)
  TO anon, authenticated;


-- ------------------------------------------------------------
-- 6. revoke_admin_session
--    Delete session from DB on logout.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.revoke_admin_session(
  session_token_input text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  DELETE FROM public.admin_sessions s
  WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex');
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_admin_session(text)
  TO anon, authenticated;
