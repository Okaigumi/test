-- ============================================================
-- Secure RPCs for materials and machines (Phase 3-2 / 優先順位2)
-- Run in Supabase SQL Editor
--
-- Authorization (dual-session): delegated to the EXISTING helper
--   public._verify_management_session(text)
--   1. Valid admin session
--      (admin_sessions + genka_admins.is_active = true)
--   OR
--   2. Valid employee session with admin role
--      (employee_sessions + employees.role = 'admin'
--       + employees.is_active = true)
--
-- Additive-only: creates new functions only.
-- Does NOT create a new helper (reuses _verify_management_session).
-- Does NOT touch existing tables, RLS, policies, or grants.
-- Does NOT REVOKE anything (direct INSERT/UPDATE revoke is a later
-- phase, after the front-end is migrated and verified in production).
-- search_path includes 'extensions' to match the existing helper.
--
-- Scope:
--   - public.materials  : create / deactivate
--   - public.machines   : create / update / deactivate
--   - public.machine_locations is OUT OF SCOPE
--     (already covered by create_machine_location_secure).
--
-- Column notes (from SQL-editor read-only confirmation):
--   materials(id, name, is_active, created_at)
--   machines (id, name, is_active, created_at, ownership,
--             lease_company, lease_start, lease_end, lease_monthly,
--             company_id)
--   - is_active : never trusted from client; create fixes it to true.
--   - machines.company_id : nullable; NOT touched by these RPCs
--     (kept for existing-UI compatibility).
--   - ownership allowed values (per existing front-end): 'owned' / 'lease'.
-- ============================================================


-- ============================================================
-- 1. create_material_secure
--    Insert a new material (master) after verifying management session.
--    is_active is always true server-side; never trusted from client.
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_material_secure(
  session_token_input text,
  name_input          text
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
  IF name_input IS NULL OR btrim(name_input) = '' THEN
    RAISE EXCEPTION 'Material name is required';
  END IF;

  -- Insert material; is_active is fixed to true server-side
  RETURN QUERY
  INSERT INTO public.materials AS m (name, is_active)
  VALUES (btrim(name_input), true)
  RETURNING m.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_material_secure(text, text)
  TO anon, authenticated;


-- ============================================================
-- 2. deactivate_material_secure
--    Set material is_active to false (logical delete).
--    Matches by id only; raises if no such material.
-- ============================================================
CREATE OR REPLACE FUNCTION public.deactivate_material_secure(
  session_token_input text,
  material_id_input   uuid
)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_rows integer;
BEGIN
  -- Verify session token (admin session OR employee session with admin role)
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
  UPDATE public.materials m
  SET    is_active = false
  WHERE  m.id = material_id_input
  RETURNING m.id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Material not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_material_secure(text, uuid)
  TO anon, authenticated;


-- ============================================================
-- 3. create_machine_secure
--    Insert a new machine (master) after verifying management session.
--    is_active is always true server-side; never trusted from client.
--    company_id is NOT set here (kept nullable / existing-UI compatible).
--
--    ownership: NULL/'' -> 'owned'; only 'owned' or 'lease' allowed.
--    When ownership = 'owned', lease_* are forced to NULL (mirrors the
--    existing front-end, which sends null lease fields for owned machines).
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_machine_secure(
  session_token_input  text,
  name_input           text,
  ownership_input      text    DEFAULT 'owned',
  lease_company_input  text    DEFAULT NULL,
  lease_start_input    date    DEFAULT NULL,
  lease_end_input      date    DEFAULT NULL,
  lease_monthly_input  integer DEFAULT NULL
)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_ownership     text;
  v_lease_company text;
  v_lease_start   date;
  v_lease_end     date;
  v_lease_monthly integer;
BEGIN
  -- Verify session token (admin session OR employee session with admin role)
  PERFORM public._verify_management_session(session_token_input);

  -- Validate name
  IF name_input IS NULL OR btrim(name_input) = '' THEN
    RAISE EXCEPTION 'Machine name is required';
  END IF;

  -- Normalize / validate ownership
  v_ownership := lower(btrim(coalesce(ownership_input, '')));
  IF v_ownership = '' THEN
    v_ownership := 'owned';
  END IF;
  IF v_ownership NOT IN ('owned', 'lease') THEN
    RAISE EXCEPTION 'Invalid ownership (expected owned or lease)';
  END IF;

  -- Validate lease values
  IF lease_monthly_input IS NOT NULL AND lease_monthly_input < 0 THEN
    RAISE EXCEPTION 'Lease monthly must be zero or positive';
  END IF;
  IF lease_start_input IS NOT NULL
     AND lease_end_input IS NOT NULL
     AND lease_start_input > lease_end_input THEN
    RAISE EXCEPTION 'Lease start must be on or before lease end';
  END IF;

  -- Owned machines carry no lease info
  IF v_ownership = 'owned' THEN
    v_lease_company := NULL;
    v_lease_start   := NULL;
    v_lease_end     := NULL;
    v_lease_monthly := NULL;
  ELSE
    v_lease_company := lease_company_input;
    v_lease_start   := lease_start_input;
    v_lease_end     := lease_end_input;
    v_lease_monthly := lease_monthly_input;
  END IF;

  -- Insert machine; is_active fixed to true; company_id not set (defaults NULL)
  RETURN QUERY
  INSERT INTO public.machines AS m (
    name,
    is_active,
    ownership,
    lease_company,
    lease_start,
    lease_end,
    lease_monthly
  )
  VALUES (
    btrim(name_input),
    true,
    v_ownership,
    v_lease_company,
    v_lease_start,
    v_lease_end,
    v_lease_monthly
  )
  RETURNING m.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_machine_secure(
  text, text, text, text, date, date, integer
) TO anon, authenticated;


-- ============================================================
-- 4. update_machine_secure
--    Update an existing machine after verifying management session.
--    is_active / company_id / created_at are NOT modified.
--    Matches by id only; raises if no such machine.
--
--    ownership / lease_* handled the same way as create_machine_secure.
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_machine_secure(
  session_token_input  text,
  machine_id_input     uuid,
  name_input           text,
  ownership_input      text    DEFAULT 'owned',
  lease_company_input  text    DEFAULT NULL,
  lease_start_input    date    DEFAULT NULL,
  lease_end_input      date    DEFAULT NULL,
  lease_monthly_input  integer DEFAULT NULL
)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_rows          integer;
  v_ownership     text;
  v_lease_company text;
  v_lease_start   date;
  v_lease_end     date;
  v_lease_monthly integer;
BEGIN
  -- Verify session token (admin session OR employee session with admin role)
  PERFORM public._verify_management_session(session_token_input);

  -- Validate name
  IF name_input IS NULL OR btrim(name_input) = '' THEN
    RAISE EXCEPTION 'Machine name is required';
  END IF;

  -- Normalize / validate ownership
  v_ownership := lower(btrim(coalesce(ownership_input, '')));
  IF v_ownership = '' THEN
    v_ownership := 'owned';
  END IF;
  IF v_ownership NOT IN ('owned', 'lease') THEN
    RAISE EXCEPTION 'Invalid ownership (expected owned or lease)';
  END IF;

  -- Validate lease values
  IF lease_monthly_input IS NOT NULL AND lease_monthly_input < 0 THEN
    RAISE EXCEPTION 'Lease monthly must be zero or positive';
  END IF;
  IF lease_start_input IS NOT NULL
     AND lease_end_input IS NOT NULL
     AND lease_start_input > lease_end_input THEN
    RAISE EXCEPTION 'Lease start must be on or before lease end';
  END IF;

  -- Owned machines carry no lease info
  IF v_ownership = 'owned' THEN
    v_lease_company := NULL;
    v_lease_start   := NULL;
    v_lease_end     := NULL;
    v_lease_monthly := NULL;
  ELSE
    v_lease_company := lease_company_input;
    v_lease_start   := lease_start_input;
    v_lease_end     := lease_end_input;
    v_lease_monthly := lease_monthly_input;
  END IF;

  -- Update machine; is_active / company_id / created_at are not touched.
  RETURN QUERY
  UPDATE public.machines m
  SET    name          = btrim(name_input),
         ownership     = v_ownership,
         lease_company = v_lease_company,
         lease_start   = v_lease_start,
         lease_end     = v_lease_end,
         lease_monthly = v_lease_monthly
  WHERE  m.id = machine_id_input
  RETURNING m.id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Machine not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_machine_secure(
  text, uuid, text, text, text, date, date, integer
) TO anon, authenticated;


-- ============================================================
-- 5. deactivate_machine_secure
--    Set machine is_active to false (logical delete).
--    Matches by id only; raises if no such machine.
-- ============================================================
CREATE OR REPLACE FUNCTION public.deactivate_machine_secure(
  session_token_input text,
  machine_id_input    uuid
)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_rows integer;
BEGIN
  -- Verify session token (admin session OR employee session with admin role)
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
  UPDATE public.machines m
  SET    is_active = false
  WHERE  m.id = machine_id_input
  RETURNING m.id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Machine not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_machine_secure(text, uuid)
  TO anon, authenticated;
