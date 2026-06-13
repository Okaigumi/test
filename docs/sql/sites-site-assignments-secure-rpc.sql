-- ============================================================
-- Secure RPCs for sites and site_assignments (Phase 3-1)
-- Run in Supabase SQL Editor
--
-- Authorization (dual-session):
--   1. Valid admin session
--      (admin_sessions + genka_admins.is_active = true)
--   OR
--   2. Valid employee session with admin role
--      (employee_sessions + employees.role = 'admin'
--       + employees.is_active = true)
--
-- Additive-only: creates new functions only.
-- Does NOT touch existing tables, RLS, policies, or grants.
-- search_path includes 'extensions' for pgcrypto digest().
-- ============================================================


-- ============================================================
-- 0. _verify_management_session (internal helper)
--    Validates the session token against admin_sessions OR
--    employee_sessions (role = 'admin'). Raises on failure.
--    NOT exposed to clients; called from the RPCs below only.
-- ============================================================
CREATE OR REPLACE FUNCTION public._verify_management_session(
  session_token_input text
)
RETURNS TABLE (
  actor_type text,
  actor_id   uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- 1. Valid admin session (admin must still be active)
  SELECT 'admin', g.id
  INTO   actor_type, actor_id
  FROM   public.admin_sessions s
  JOIN   public.genka_admins g ON g.id = s.admin_id
  WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  s.expires_at > now()
    AND  g.is_active  = true;

  IF FOUND THEN
    RETURN NEXT;
    RETURN;
  END IF;

  -- 2. Valid employee session with admin role (employee must still be active)
  SELECT 'employee', e.id
  INTO   actor_type, actor_id
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.role        = 'admin'
    AND  e.is_active   = true;

  IF FOUND THEN
    RETURN NEXT;
    RETURN;
  END IF;

  RAISE EXCEPTION 'Invalid or expired session';
END;
$$;

-- Internal use only: revoke from all client-facing roles.
-- (Revokes on this NEW function only; no existing grants are touched.)
REVOKE EXECUTE ON FUNCTION public._verify_management_session(text)
  FROM PUBLIC, anon, authenticated;


-- ============================================================
-- 1. create_site_secure
--    Insert a new site after verifying management session.
--    is_active is always true server-side; never trusted from client.
--    category_id / contract_amount are not handled here.
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_site_secure(
  session_token_input text,
  name_input          text,
  location_input      text DEFAULT NULL,
  start_date_input    date DEFAULT NULL,
  end_date_input      date DEFAULT NULL,
  company_id_input    uuid DEFAULT NULL
)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Verify session token (admin session OR employee session with admin role)
  PERFORM public._verify_management_session(session_token_input);

  -- Validate inputs
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION 'Site name is required';
  END IF;

  IF start_date_input IS NOT NULL
     AND end_date_input IS NOT NULL
     AND start_date_input > end_date_input THEN
    RAISE EXCEPTION 'Start date must be on or before end date';
  END IF;

  -- Validate company reference explicitly (do not rely on FK)
  IF company_id_input IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.companies c
    WHERE  c.id        = company_id_input
      AND  c.is_active = true
  ) THEN
    RAISE EXCEPTION 'Company not found';
  END IF;

  -- Insert site; is_active is fixed to true server-side
  RETURN QUERY
  INSERT INTO public.sites AS s (
    name,
    location,
    start_date,
    end_date,
    company_id,
    is_active
  )
  VALUES (
    trim(name_input),
    location_input,
    start_date_input,
    end_date_input,
    company_id_input,
    true
  )
  RETURNING s.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_site_secure(
  text, text, text, date, date, uuid
) TO anon, authenticated;


-- ============================================================
-- 2. update_site_secure
--    Update an existing site after verifying management session.
--    is_active / category_id / contract_amount are not modified.
--
--    NOTE: The WHERE clause matches by id only (current behavior
--    preserved). A deactivated site (is_active = false) can still
--    be updated when its id is specified directly.
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_site_secure(
  session_token_input text,
  id_input            uuid,
  name_input          text,
  location_input      text DEFAULT NULL,
  start_date_input    date DEFAULT NULL,
  end_date_input      date DEFAULT NULL,
  company_id_input    uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_rows integer;
BEGIN
  -- Verify session token (admin session OR employee session with admin role)
  PERFORM public._verify_management_session(session_token_input);

  -- Validate inputs
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION 'Site name is required';
  END IF;

  IF start_date_input IS NOT NULL
     AND end_date_input IS NOT NULL
     AND start_date_input > end_date_input THEN
    RAISE EXCEPTION 'Start date must be on or before end date';
  END IF;

  -- Validate company reference explicitly (do not rely on FK)
  IF company_id_input IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.companies c
    WHERE  c.id        = company_id_input
      AND  c.is_active = true
  ) THEN
    RAISE EXCEPTION 'Company not found';
  END IF;

  -- Update site; is_active / category_id / contract_amount are not touched.
  -- Matches by id only: an inactive site is still updatable by direct id.
  UPDATE public.sites s
  SET    name       = trim(name_input),
         location   = location_input,
         start_date = start_date_input,
         end_date   = end_date_input,
         company_id = company_id_input
  WHERE  s.id = id_input;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Site not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_site_secure(
  text, uuid, text, text, date, date, uuid
) TO anon, authenticated;


-- ============================================================
-- 3. deactivate_site_secure
--    Set site is_active to false (logical delete) and
--    deactivate all assignments for that site atomically.
-- ============================================================
CREATE OR REPLACE FUNCTION public.deactivate_site_secure(
  session_token_input text,
  id_input            uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_rows integer;
BEGIN
  -- Verify session token (admin session OR employee session with admin role)
  PERFORM public._verify_management_session(session_token_input);

  -- Deactivate site
  UPDATE public.sites s
  SET    is_active = false
  WHERE  s.id = id_input;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Site not found';
  END IF;

  -- Deactivate all assignments for this site (zero rows is fine)
  UPDATE public.site_assignments a
  SET    is_active = false
  WHERE  a.site_id = id_input;
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_site_secure(text, uuid)
  TO anon, authenticated;


-- ============================================================
-- 4. set_site_assignment_secure
--    Toggle a single site assignment on or off.
--    ON  : upsert with is_active = true (idempotent)
--    OFF : update only; zero rows is fine (idempotent),
--          never inserts a row for a non-existing pair
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_site_assignment_secure(
  session_token_input text,
  site_id_input       uuid,
  employee_id_input   uuid,
  is_active_input     boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Verify session token (admin session OR employee session with admin role)
  PERFORM public._verify_management_session(session_token_input);

  IF is_active_input IS NULL THEN
    RAISE EXCEPTION 'Assignment active flag is required';
  END IF;

  IF is_active_input THEN
    -- Validate references before creating an assignment
    IF NOT EXISTS (
      SELECT 1 FROM public.sites s
      WHERE  s.id        = site_id_input
        AND  s.is_active = true
    ) THEN
      RAISE EXCEPTION 'Site not found';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.employees e
      WHERE  e.id        = employee_id_input
        AND  e.is_active = true
    ) THEN
      RAISE EXCEPTION 'Employee not found';
    END IF;

    INSERT INTO public.site_assignments (site_id, employee_id, is_active)
    VALUES (site_id_input, employee_id_input, true)
    ON CONFLICT (site_id, employee_id)
    DO UPDATE SET is_active = true;
  ELSE
    -- Deactivate only; zero rows is fine, never insert here
    UPDATE public.site_assignments a
    SET    is_active = false
    WHERE  a.site_id     = site_id_input
      AND  a.employee_id = employee_id_input;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_site_assignment_secure(
  text, uuid, uuid, boolean
) TO anon, authenticated;


-- ============================================================
-- 5. replace_site_assignments_secure
--    Replace all assignments for a site atomically:
--    deactivate everything, then activate the given employees.
--    NULL or empty employee_ids_input means "remove everyone".
-- ============================================================
CREATE OR REPLACE FUNCTION public.replace_site_assignments_secure(
  session_token_input text,
  site_id_input       uuid,
  employee_ids_input  uuid[] DEFAULT '{}'::uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_ids uuid[];
BEGIN
  -- Verify session token (admin session OR employee session with admin role)
  PERFORM public._verify_management_session(session_token_input);

  -- Validate site
  IF NOT EXISTS (
    SELECT 1 FROM public.sites s
    WHERE  s.id        = site_id_input
      AND  s.is_active = true
  ) THEN
    RAISE EXCEPTION 'Site not found';
  END IF;

  -- Reject NULL elements, then deduplicate
  IF employee_ids_input IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(employee_ids_input) AS t(emp_id)
    WHERE  t.emp_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Employee id list contains null';
  END IF;

  v_employee_ids := COALESCE(
    ARRAY(SELECT DISTINCT emp_id FROM unnest(employee_ids_input) AS t(emp_id)),
    '{}'::uuid[]
  );

  -- Validate all employees exist and are active
  IF array_length(v_employee_ids, 1) IS NOT NULL THEN
    IF (
      SELECT count(*)
      FROM   public.employees e
      WHERE  e.id        = ANY(v_employee_ids)
        AND  e.is_active = true
    ) <> array_length(v_employee_ids, 1) THEN
      RAISE EXCEPTION 'One or more employees not found';
    END IF;
  END IF;

  -- Deactivate all current assignments for this site
  UPDATE public.site_assignments a
  SET    is_active = false
  WHERE  a.site_id = site_id_input;

  -- Activate the requested assignments (no-op for empty list)
  IF array_length(v_employee_ids, 1) IS NOT NULL THEN
    INSERT INTO public.site_assignments (site_id, employee_id, is_active)
    SELECT site_id_input, emp_id, true
    FROM   unnest(v_employee_ids) AS t(emp_id)
    ON CONFLICT (site_id, employee_id)
    DO UPDATE SET is_active = true;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.replace_site_assignments_secure(
  text, uuid, uuid[]
) TO anon, authenticated;
