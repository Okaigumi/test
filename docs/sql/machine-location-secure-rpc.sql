-- ============================================================
-- Secure RPC for machine location records
--
-- Created function:
--   1. create_machine_location_secure
--      Records a machine move after verifying employee session.
--      moved_by is resolved server-side from the session token;
--      never trusted from the client.
--      All active employees (not admin-only) may record a move.
--
-- Prerequisites:
--   employee_sessions table must exist (see employee-report-secure-rpc.sql).
--
-- No REVOKE statements in this file.
-- Run REVOKE separately after front-end migration is confirmed.
--
-- Run in Supabase SQL Editor.
-- ============================================================


-- ============================================================
-- 1. create_machine_location_secure
--    Insert a machine location record after verifying employee
--    session. moved_by is resolved from the session token.
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_machine_location_secure(
  session_token_input text,
  machine_id_input    uuid,
  site_id_input       uuid    DEFAULT NULL,
  memo_input          text    DEFAULT NULL
)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
BEGIN
  -- Verify session token and resolve employee_id
  SELECT es.employee_id
  INTO   v_employee_id
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Validate machine_id
  IF machine_id_input IS NULL THEN
    RAISE EXCEPTION 'Machine is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.machines m
    WHERE  m.id = machine_id_input
  ) THEN
    RAISE EXCEPTION 'Machine not found';
  END IF;

  -- Validate site_id if provided
  IF site_id_input IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.sites s
    WHERE  s.id = site_id_input
  ) THEN
    RAISE EXCEPTION 'Site not found';
  END IF;

  -- Insert machine location record
  -- moved_by comes from session, not from the client
  -- moved_at uses the DB default (now())
  RETURN QUERY
  INSERT INTO public.machine_locations (
    machine_id,
    site_id,
    moved_by,
    memo
  )
  VALUES (
    machine_id_input,
    site_id_input,
    v_employee_id,
    memo_input
  )
  RETURNING machine_locations.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_machine_location_secure(
  text, uuid, uuid, text
) TO anon, authenticated;
