-- ============================================================
-- Secure RPCs for employee_rates and unit_rates (Phase 3 優先順位3)
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
-- Scope (both written today from admin-app.html / genka-app.html via
-- direct upsert; migrated to these RPCs):
--   - public.employee_rates : upsert (employee_id, effective_from)
--   - public.unit_rates      : upsert (category, name)
--
-- Notes:
--   - employee_rates is an effective-dated history table. A same-day
--     upsert updates that day's daily_rate (ON CONFLICT on the existing
--     unique key employee_id, effective_from). hourly_rate / created_at
--     are NOT touched.
--   - unit_rates.updated_at is set server-side via now() (never trusted
--     from client). company_id is NOT touched.
--   - is_active and any other columns are never trusted from client.
-- ============================================================


-- ============================================================
-- 1. upsert_employee_rate_secure
--    Upsert an employee's daily rate for a given effective_from date,
--    after verifying management session.
--    ON CONFLICT (employee_id, effective_from) updates daily_rate only.
--    hourly_rate and created_at are never touched.
--    Returns the upserted employee_rates.id.
-- ============================================================
CREATE OR REPLACE FUNCTION public.upsert_employee_rate_secure(
  session_token_input  text,
  employee_id_input    uuid,
  daily_rate_input     integer,
  effective_from_input date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_id uuid;
BEGIN
  -- Verify session token (admin session OR employee session with admin role)
  PERFORM public._verify_management_session(session_token_input);

  -- Validate inputs
  IF employee_id_input IS NULL THEN
    RAISE EXCEPTION 'Employee id is required';
  END IF;
  IF daily_rate_input IS NULL OR daily_rate_input < 0 THEN
    RAISE EXCEPTION 'Daily rate must be zero or positive';
  END IF;
  IF effective_from_input IS NULL THEN
    RAISE EXCEPTION 'Effective from date is required';
  END IF;

  -- Employee must exist (is_active and other columns are not checked here,
  -- to avoid relying on unconfirmed columns)
  IF NOT EXISTS (SELECT 1 FROM public.employees e WHERE e.id = employee_id_input) THEN
    RAISE EXCEPTION 'Employee not found';
  END IF;

  -- Upsert; only daily_rate is updated on conflict.
  INSERT INTO public.employee_rates AS er (
    employee_id,
    daily_rate,
    effective_from
  )
  VALUES (
    employee_id_input,
    daily_rate_input,
    effective_from_input
  )
  ON CONFLICT (employee_id, effective_from)
  DO UPDATE SET daily_rate = EXCLUDED.daily_rate
  RETURNING er.id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_employee_rate_secure(text, uuid, integer, date)
  TO anon, authenticated;


-- ============================================================
-- 2. upsert_unit_rate_secure
--    Upsert a unit rate for a given (category, name), after verifying
--    management session.
--    ON CONFLICT (category, name) updates unit_price / unit / updated_at.
--    updated_at is set server-side via now(); company_id is not touched.
--    Returns the upserted unit_rates.id.
-- ============================================================
CREATE OR REPLACE FUNCTION public.upsert_unit_rate_secure(
  session_token_input text,
  category_input      text,
  name_input          text,
  unit_price_input    integer,
  unit_input          text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_id uuid;
BEGIN
  -- Verify session token (admin session OR employee session with admin role)
  PERFORM public._verify_management_session(session_token_input);

  -- Validate inputs
  IF category_input IS NULL OR btrim(category_input) = '' THEN
    RAISE EXCEPTION 'Category is required';
  END IF;
  IF name_input IS NULL OR btrim(name_input) = '' THEN
    RAISE EXCEPTION 'Name is required';
  END IF;
  IF unit_price_input IS NULL OR unit_price_input < 0 THEN
    RAISE EXCEPTION 'Unit price must be zero or positive';
  END IF;
  IF unit_input IS NULL OR btrim(unit_input) = '' THEN
    RAISE EXCEPTION 'Unit is required';
  END IF;

  -- Upsert; unit_price / unit / updated_at are updated on conflict.
  -- updated_at is server-side now(), never trusted from client.
  INSERT INTO public.unit_rates AS ur (
    category,
    name,
    unit_price,
    unit,
    updated_at
  )
  VALUES (
    btrim(category_input),
    btrim(name_input),
    unit_price_input,
    btrim(unit_input),
    now()
  )
  ON CONFLICT (category, name)
  DO UPDATE SET unit_price = EXCLUDED.unit_price,
                unit       = EXCLUDED.unit,
                updated_at = now()
  RETURNING ur.id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_unit_rate_secure(text, text, text, integer, text)
  TO anon, authenticated;


-- ============================================================
-- 3. Post-apply verification (read-only SELECT only)
--    Running these does not change DB state.
-- ============================================================

-- 3-1. Both functions exist, with SECURITY DEFINER and the expected
--      search_path (public, extensions).
--      Expected: 2 rows; security_definer = true;
--      config contains search_path=public, extensions.
SELECT p.proname AS routine_name,
       p.prosecdef AS security_definer,
       p.proconfig AS config
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('upsert_employee_rate_secure', 'upsert_unit_rate_secure')
ORDER BY p.proname;

-- 3-2. EXECUTE privilege for anon / authenticated on the 2 new RPCs.
--      Expected: 4 rows (2 functions x 2 roles).
SELECT routine_name, grantee, privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name IN ('upsert_employee_rate_secure', 'upsert_unit_rate_secure')
  AND grantee IN ('anon', 'authenticated')
ORDER BY routine_name, grantee;

-- 3-3. _verify_management_session external EXECUTE check.
--      Expected: 0 rows (no EXECUTE for anon / authenticated / public).
SELECT routine_name, grantee, privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name = '_verify_management_session'
  AND grantee IN ('anon', 'authenticated', 'public')
ORDER BY grantee;
