-- ============================================================
-- Admin secure RPCs for machines (Phase 3-2 / 優先順位2 追加対応)
-- Run in Supabase SQL Editor
--
-- Purpose:
--   admin-app.html の machines 新規/更新は company_id と is_active を
--   扱うため、既存の create_machine_secure / update_machine_secure
--   （company_id を扱わず・is_active を固定/不変更）では機能後退する。
--   そこで admin 画面専用に、company_id と is_active を受け取る
--   admin 向け RPC を additive-only で追加する。
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
-- Does NOT modify the existing 5 RPCs in
--   docs/sql/materials-machines-secure-rpc.sql.
-- Does NOT touch existing tables, RLS, policies, or table grants.
-- Does NOT REVOKE anything (direct INSERT/UPDATE revoke is a later
-- phase, after the front-end is migrated and verified in production).
-- search_path includes 'extensions' to match the existing helper.
--
-- Scope:
--   - public.machines : create / update (admin variant, with company_id + is_active)
--   - public.materials は対象外
--   - public.machine_locations は対象外
--
-- Difference vs existing create_machine_secure / update_machine_secure:
--   - company_id_input を受け取り machines.company_id に設定する（NULL許容）
--   - is_active_input を受け取り machines.is_active に設定する（NULL拒否）
--
-- Column notes (from SQL-editor read-only confirmation):
--   machines (id, name, is_active, created_at, ownership,
--             lease_company, lease_start, lease_end, lease_monthly,
--             company_id)
--   - company_id : nullable; companies.id を参照（存在チェックを明示する）
--   - ownership allowed values (per existing front-end): 'owned' / 'lease'.
-- ============================================================


-- ============================================================
-- 1. create_machine_admin_secure
--    Insert a new machine (master) after verifying management session.
--    company_id と is_active をクライアントから受け取る admin 向け。
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_machine_admin_secure(
  session_token_input  text,
  name_input           text,
  company_id_input     uuid,
  is_active_input      boolean,
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

  -- is_active must be provided explicitly
  IF is_active_input IS NULL THEN
    RAISE EXCEPTION 'is_active is required';
  END IF;

  -- company_id is optional; when provided it must exist
  IF company_id_input IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.companies c WHERE c.id = company_id_input) THEN
      RAISE EXCEPTION 'Company not found';
    END IF;
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

  -- Insert machine; company_id and is_active are set from inputs.
  RETURN QUERY
  INSERT INTO public.machines AS m (
    name,
    company_id,
    is_active,
    ownership,
    lease_company,
    lease_start,
    lease_end,
    lease_monthly
  )
  VALUES (
    btrim(name_input),
    company_id_input,
    is_active_input,
    v_ownership,
    v_lease_company,
    v_lease_start,
    v_lease_end,
    v_lease_monthly
  )
  RETURNING m.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_machine_admin_secure(
  text, text, uuid, boolean, text, text, date, date, integer
) TO anon, authenticated;


-- ============================================================
-- 2. update_machine_admin_secure
--    Update an existing machine after verifying management session.
--    company_id と is_active をクライアントから受け取る admin 向け。
--    created_at は触らない。対象 id が無ければ例外。
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_machine_admin_secure(
  session_token_input  text,
  machine_id_input     uuid,
  name_input           text,
  company_id_input     uuid,
  is_active_input      boolean,
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

  -- is_active must be provided explicitly
  IF is_active_input IS NULL THEN
    RAISE EXCEPTION 'is_active is required';
  END IF;

  -- company_id is optional; when provided it must exist
  IF company_id_input IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.companies c WHERE c.id = company_id_input) THEN
      RAISE EXCEPTION 'Company not found';
    END IF;
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

  -- Update machine; company_id and is_active are set from inputs.
  -- created_at is not touched.
  RETURN QUERY
  UPDATE public.machines m
  SET    name          = btrim(name_input),
         company_id    = company_id_input,
         is_active     = is_active_input,
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

GRANT EXECUTE ON FUNCTION public.update_machine_admin_secure(
  text, uuid, text, uuid, boolean, text, text, date, date, integer
) TO anon, authenticated;
