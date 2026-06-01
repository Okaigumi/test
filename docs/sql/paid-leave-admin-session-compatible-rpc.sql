-- paid-leave-admin-session-compatible-rpc.sql
-- ASCII only.
-- Modify two existing paid leave RPCs to accept both employee_sessions and admin_sessions.
-- Do not restore direct table INSERT or UPDATE permissions.

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
  v_is_admin    boolean := false;
  v_rows        integer;
BEGIN
  SELECT es.employee_id, e.role
  INTO   v_employee_id, v_role
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true
  LIMIT 1;

  IF FOUND AND v_role = 'admin' THEN
    v_is_admin := true;
  END IF;

  IF NOT v_is_admin THEN
    IF EXISTS (
      SELECT 1
      FROM   public.admin_sessions s
      JOIN   public.genka_admins g ON g.id = s.admin_id
      WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
        AND  s.expires_at > now()
        AND  g.is_active  = true
    ) THEN
      v_is_admin    := true;
      v_employee_id := NULL;
    END IF;
  END IF;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  IF status_input NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Invalid review status';
  END IF;

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
  v_role     text;
  v_is_admin boolean := false;
BEGIN
  SELECT e.role
  INTO   v_role
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true
  LIMIT 1;

  IF FOUND AND v_role = 'admin' THEN
    v_is_admin := true;
  END IF;

  IF NOT v_is_admin THEN
    IF EXISTS (
      SELECT 1
      FROM   public.admin_sessions s
      JOIN   public.genka_admins g ON g.id = s.admin_id
      WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
        AND  s.expires_at > now()
        AND  g.is_active  = true
    ) THEN
      v_is_admin := true;
    END IF;
  END IF;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  IF year_input IS NULL OR year_input < 2000 OR year_input > 2100 THEN
    RAISE EXCEPTION 'Invalid year';
  END IF;

  IF days_input IS NULL OR days_input < 0 THEN
    RAISE EXCEPTION 'Invalid granted days';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM   public.employees e
    WHERE  e.id        = employee_id_input
      AND  e.is_active = true
  ) THEN
    RAISE EXCEPTION 'Target employee not found';
  END IF;

  INSERT INTO public.paid_leave_grants (employee_id, year, granted)
  VALUES (employee_id_input, year_input, days_input)
  ON CONFLICT (employee_id, year)
  DO UPDATE SET granted = EXCLUDED.granted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_paid_leave_grant_secure(text, uuid, integer, numeric)
  TO anon, authenticated;
