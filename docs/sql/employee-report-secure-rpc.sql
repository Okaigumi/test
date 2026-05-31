-- ============================================================
-- Employee session management and secure report RPCs
--
-- Creates:
--   1. employee_sessions table
--   2. create_employee_session  - PIN auth + session token issuance
--   3. revoke_employee_session  - logout / session deletion
--   4. create_report_secure     - INSERT reports with server-side employee_id
--   5. update_report_secure     - UPDATE reports (own records only)
--   6. update_report_photo_secure - UPDATE photo fields after upload
--
-- employee_id is NEVER trusted from the client.
-- It is resolved server-side from the session token in every RPC.
--
-- Run in Supabase SQL Editor.
-- ============================================================


-- ============================================================
-- 1. employee_sessions table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.employee_sessions (
  id           uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  employee_id  uuid        NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  token_hash   text        NOT NULL UNIQUE,
  expires_at   timestamptz NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Indexes for fast token lookup and expiry cleanup
CREATE INDEX IF NOT EXISTS employee_sessions_token_hash_idx
  ON public.employee_sessions (token_hash);

CREATE INDEX IF NOT EXISTS employee_sessions_expires_at_idx
  ON public.employee_sessions (expires_at);

CREATE INDEX IF NOT EXISTS employee_sessions_employee_id_idx
  ON public.employee_sessions (employee_id);

-- RLS enabled; no direct-access policies (SECURITY DEFINER RPCs only)
ALTER TABLE public.employee_sessions ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 2. create_employee_session
--    Verify employee PIN and issue a session token.
--    Replaces verify_employee_pin for index.html login.
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_employee_session(
  employee_id_input uuid,
  pin_input         text
)
RETURNS TABLE (
  id            uuid,
  name          text,
  role          text,
  is_active     boolean,
  company_id    uuid,
  can_genka     boolean,
  can_admin     boolean,
  session_token text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_emp   public.employees%ROWTYPE;
  v_token text;
BEGIN
  -- Verify PIN and active status
  SELECT *
  INTO   v_emp
  FROM   public.employees e
  WHERE  e.id        = employee_id_input
    AND  e.pin       = pin_input
    AND  e.is_active = true;

  -- Return empty set if credentials do not match
  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Remove existing sessions for this employee and all expired sessions
  DELETE FROM public.employee_sessions s
  WHERE  s.employee_id = employee_id_input
     OR  s.expires_at  < now();

  -- Generate 32-byte random token (64-char hex string)
  v_token := encode(gen_random_bytes(32), 'hex');

  -- Store only the hash; never persist the raw token
  INSERT INTO public.employee_sessions (employee_id, token_hash, expires_at)
  VALUES (
    employee_id_input,
    encode(digest(v_token, 'sha256'), 'hex'),
    now() + interval '8 hours'
  );

  -- Return employee info + raw token (pin is NOT returned)
  RETURN QUERY
  SELECT
    v_emp.id,
    v_emp.name,
    v_emp.role,
    v_emp.is_active,
    v_emp.company_id,
    v_emp.can_genka,
    v_emp.can_admin,
    v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_employee_session(uuid, text)
  TO anon, authenticated;


-- ============================================================
-- 3. revoke_employee_session
--    Delete session from DB on logout.
-- ============================================================
CREATE OR REPLACE FUNCTION public.revoke_employee_session(
  session_token_input text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  DELETE FROM public.employee_sessions s
  WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex');
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_employee_session(text)
  TO anon, authenticated;


-- ============================================================
-- 4. create_report_secure
--    Insert a new daily report after verifying employee session.
--    employee_id is resolved server-side; never trusted from client.
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_report_secure(
  session_token_input       text,
  report_date_input         date,
  site_ids_input            uuid[],
  material_ids_input        uuid[],
  start_time_input          time,
  end_time_input            time,
  memo_input                text    DEFAULT NULL,
  normal_mins_input         integer DEFAULT 0,
  overtime_mins_input       integer DEFAULT 0,
  material_quantities_input jsonb   DEFAULT '{}'::jsonb,
  work_type_input           text    DEFAULT 'normal',
  machine_transfers_input   jsonb   DEFAULT '[]'::jsonb,
  subcontractor_ids_input   uuid[]  DEFAULT '{}'::uuid[],
  sub_machines_input        jsonb   DEFAULT '{}'::jsonb,
  dump_count_input          integer DEFAULT 0,
  guard_count_input         integer DEFAULT 0,
  dump_company_input        text    DEFAULT NULL
)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
BEGIN
  -- Verify session token and resolve employee_id server-side
  SELECT s.employee_id INTO v_employee_id
  FROM   public.employee_sessions s
  WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  s.expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Validate required fields
  IF site_ids_input IS NULL OR array_length(site_ids_input, 1) IS NULL THEN
    RAISE EXCEPTION 'At least one site is required';
  END IF;

  IF start_time_input IS NULL OR end_time_input IS NULL THEN
    RAISE EXCEPTION 'Start and end time are required';
  END IF;

  IF normal_mins_input < 0 OR overtime_mins_input < 0 THEN
    RAISE EXCEPTION 'Work minutes must be zero or greater';
  END IF;

  -- Insert report; employee_id comes from session, not from client
  RETURN QUERY
  INSERT INTO public.reports (
    employee_id,
    report_date,
    site_ids,
    material_ids,
    material_quantities,
    subcontractor_ids,
    sub_machines,
    start_time,
    end_time,
    normal_mins,
    overtime_mins,
    work_type,
    memo,
    photo_count,
    photo_urls,
    dump_count,
    guard_count,
    dump_company,
    status,
    migrated_to_entries
  )
  VALUES (
    v_employee_id,
    report_date_input,
    site_ids_input,
    material_ids_input,
    material_quantities_input,
    subcontractor_ids_input,
    sub_machines_input,
    start_time_input,
    end_time_input,
    normal_mins_input,
    overtime_mins_input,
    work_type_input,
    memo_input,
    0,
    '{}'::text[],
    dump_count_input,
    guard_count_input,
    dump_company_input,
    'pending',
    false
  )
  RETURNING reports.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_report_secure(
  text, date, uuid[], uuid[], time, time,
  text, integer, integer, jsonb, text, jsonb, uuid[], jsonb,
  integer, integer, text
) TO anon, authenticated;


-- ============================================================
-- 5. update_report_secure
--    Update an existing report after verifying employee session.
--    Only the report owner (employee_id match) can update.
--    photo_urls and photo_count are not modified here.
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_report_secure(
  session_token_input       text,
  id_input                  uuid,
  report_date_input         date,
  site_ids_input            uuid[],
  material_ids_input        uuid[],
  start_time_input          time,
  end_time_input            time,
  memo_input                text    DEFAULT NULL,
  normal_mins_input         integer DEFAULT 0,
  overtime_mins_input       integer DEFAULT 0,
  material_quantities_input jsonb   DEFAULT '{}'::jsonb,
  work_type_input           text    DEFAULT 'normal',
  machine_transfers_input   jsonb   DEFAULT '[]'::jsonb,
  subcontractor_ids_input   uuid[]  DEFAULT '{}'::uuid[],
  sub_machines_input        jsonb   DEFAULT '{}'::jsonb,
  dump_count_input          integer DEFAULT 0,
  guard_count_input         integer DEFAULT 0,
  dump_company_input        text    DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
  v_rows        integer;
BEGIN
  -- Verify session token and resolve employee_id server-side
  SELECT s.employee_id INTO v_employee_id
  FROM   public.employee_sessions s
  WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  s.expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Validate required fields
  IF site_ids_input IS NULL OR array_length(site_ids_input, 1) IS NULL THEN
    RAISE EXCEPTION 'At least one site is required';
  END IF;

  IF start_time_input IS NULL OR end_time_input IS NULL THEN
    RAISE EXCEPTION 'Start and end time are required';
  END IF;

  IF normal_mins_input < 0 OR overtime_mins_input < 0 THEN
    RAISE EXCEPTION 'Work minutes must be zero or greater';
  END IF;

  -- Update report; WHERE clause enforces ownership
  -- employee_id, photo_urls, photo_count, migrated_to_entries are not modified
  UPDATE public.reports r
  SET    report_date         = report_date_input,
         site_ids            = site_ids_input,
         material_ids        = material_ids_input,
         material_quantities = material_quantities_input,
         subcontractor_ids   = subcontractor_ids_input,
         sub_machines        = sub_machines_input,
         start_time          = start_time_input,
         end_time            = end_time_input,
         normal_mins         = normal_mins_input,
         overtime_mins       = overtime_mins_input,
         work_type           = work_type_input,
         memo                = memo_input,
         dump_count          = dump_count_input,
         guard_count         = guard_count_input,
         dump_company        = dump_company_input
  WHERE  r.id          = id_input
    AND  r.employee_id = v_employee_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Report not found or permission denied';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_report_secure(
  text, uuid, date, uuid[], uuid[], time, time,
  text, integer, integer, jsonb, text, jsonb, uuid[], jsonb,
  integer, integer, text
) TO anon, authenticated;


-- ============================================================
-- 6. update_report_photo_secure
--    Update photo_urls and photo_count after upload.
--    Only the report owner (employee_id match) can update.
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_report_photo_secure(
  session_token_input text,
  id_input            uuid,
  photo_urls_input    text[],
  photo_count_input   integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
  v_rows        integer;
BEGIN
  -- Verify session token and resolve employee_id server-side
  SELECT s.employee_id INTO v_employee_id
  FROM   public.employee_sessions s
  WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  s.expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  IF photo_count_input < 0 THEN
    RAISE EXCEPTION 'Photo count must be zero or greater';
  END IF;

  -- Update photo fields; WHERE clause enforces ownership
  UPDATE public.reports r
  SET    photo_urls  = photo_urls_input,
         photo_count = photo_count_input
  WHERE  r.id          = id_input
    AND  r.employee_id = v_employee_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Report not found or permission denied';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_report_photo_secure(text, uuid, text[], integer)
  TO anon, authenticated;
