-- ============================================================
-- Secure RPCs for paid leave requests and leave grants
--
-- Created functions:
--   1. create_paid_leave_request_secure
--      Employee submits a leave request; employee_id resolved
--      server-side from session token, never trusted from client.
--
--   2. review_paid_leave_request_secure
--      Admin approves or rejects a pending leave request.
--      Admin role is verified server-side from session token.
--
--   3. save_paid_leave_grant_secure
--      Admin upserts annual leave grant for an employee.
--      Admin role is verified server-side from session token.
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
-- Helper: session validation with role lookup
--
--   SELECT es.employee_id, e.role
--   INTO   v_employee_id, v_role
--   FROM   public.employee_sessions es
--   JOIN   public.employees e ON e.id = es.employee_id
--   WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
--     AND  es.expires_at > now()
--     AND  e.is_active   = true;
--   IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or expired session'; END IF;
-- ============================================================


-- ============================================================
-- 1. create_paid_leave_request_secure
--    Employee submits a paid leave request.
--    employee_id is resolved from session; never trusted from client.
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_paid_leave_request_secure(
  session_token_input text,
  leave_date_input    date,
  leave_type_input    text,
  reason_input        text DEFAULT NULL
)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
  v_role        text;
BEGIN
  -- Verify session token, resolve employee_id and role
  SELECT es.employee_id, e.role
  INTO   v_employee_id, v_role
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Validate inputs
  IF leave_date_input IS NULL THEN
    RAISE EXCEPTION 'Leave date is required';
  END IF;

  IF leave_type_input NOT IN ('full', 'am', 'pm') THEN
    RAISE EXCEPTION 'Invalid leave type';
  END IF;

  -- Insert leave request; employee_id comes from session, not from client
  RETURN QUERY
  INSERT INTO public.paid_leave_requests (
    employee_id,
    leave_date,
    leave_type,
    reason,
    status
  )
  VALUES (
    v_employee_id,
    leave_date_input,
    leave_type_input,
    reason_input,
    'pending'
  )
  RETURNING paid_leave_requests.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_paid_leave_request_secure(
  text, date, text, text
) TO anon, authenticated;


-- ============================================================
-- 2. review_paid_leave_request_secure
--    Admin approves or rejects a pending leave request.
--    Admin role is verified server-side; reviewed_by is set
--    from the session, never from the client.
-- ============================================================
CREATE OR REPLACE FUNCTION public.review_paid_leave_request_secure(
  session_token_input text,
  id_input            uuid,
  status_input        text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
  v_role        text;
  v_rows        integer;
BEGIN
  -- Verify session token, resolve employee_id and role
  SELECT es.employee_id, e.role
  INTO   v_employee_id, v_role
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Require admin role
  IF v_role <> 'admin' THEN
    RAISE EXCEPTION 'Admin permission required';
  END IF;

  -- Validate status value
  IF status_input NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Invalid review status';
  END IF;

  -- Update the request; only pending requests can be reviewed
  -- reviewed_by is set from session, not from client
  UPDATE public.paid_leave_requests r
  SET    status      = status_input,
         reviewed_by = v_employee_id,
         reviewed_at = now()
  WHERE  r.id     = id_input
    AND  r.status = 'pending';

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Request not found or already reviewed';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.review_paid_leave_request_secure(text, uuid, text)
  TO anon, authenticated;


-- ============================================================
-- 3. save_paid_leave_grant_secure
--    Admin upserts an annual leave grant for a target employee.
--    Admin role is verified server-side from session token.
-- ============================================================
CREATE OR REPLACE FUNCTION public.save_paid_leave_grant_secure(
  session_token_input text,
  employee_id_input   uuid,
  year_input          integer,
  days_input          numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
  v_role        text;
BEGIN
  -- Verify session token, resolve employee_id and role
  SELECT es.employee_id, e.role
  INTO   v_employee_id, v_role
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Require admin role
  IF v_role <> 'admin' THEN
    RAISE EXCEPTION 'Admin permission required';
  END IF;

  -- Validate inputs
  IF year_input IS NULL OR year_input < 2000 OR year_input > 2100 THEN
    RAISE EXCEPTION 'Invalid year';
  END IF;

  IF days_input IS NULL OR days_input < 0 THEN
    RAISE EXCEPTION 'Invalid granted days';
  END IF;

  -- Verify target employee exists and is active
  IF NOT EXISTS (
    SELECT 1 FROM public.employees e
    WHERE  e.id        = employee_id_input
      AND  e.is_active = true
  ) THEN
    RAISE EXCEPTION 'Target employee not found';
  END IF;

  -- Upsert leave grant
  INSERT INTO public.paid_leave_grants (employee_id, year, granted)
  VALUES (employee_id_input, year_input, days_input)
  ON CONFLICT (employee_id, year)
  DO UPDATE SET granted = EXCLUDED.granted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_paid_leave_grant_secure(
  text, uuid, integer, numeric
) TO anon, authenticated;
