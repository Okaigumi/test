-- ============================================================
-- Fix: annual site_budget duplicate prevention
--
-- Problem:
--   ON CONFLICT (site_id, year, month) does not detect duplicates
--   when month IS NULL, because PostgreSQL treats NULL as not equal
--   to NULL in unique constraints.
--
-- Solution:
--   1. Add a partial unique index covering only annual budgets
--      (month IS NULL AND is_active = true).
--   2. Replace upsert_site_budget_secure to use the new conflict
--      target so ON CONFLICT works correctly for NULL month rows.
--
-- Run in Supabase SQL Editor.
-- ============================================================


-- ------------------------------------------------------------
-- Step 1: Partial unique index for annual budgets
--   Covers rows where month IS NULL AND is_active = true.
--   This makes (site_id, year) unique within that subset,
--   enabling ON CONFLICT (site_id, year) WHERE ... to work.
-- ------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS site_budgets_annual_active_unique
  ON public.site_budgets (site_id, year)
  WHERE month IS NULL AND is_active = true;


-- ------------------------------------------------------------
-- Step 2: Replace upsert_site_budget_secure
--   Uses the partial unique index as the conflict target.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_site_budget_secure(
  session_token_input text,
  site_id_input       uuid,
  year_input          integer,
  amount_input        integer,
  memo_input          text    DEFAULT NULL
)
RETURNS TABLE (id uuid)
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
  IF site_id_input IS NULL THEN
    RAISE EXCEPTION 'Site is required';
  END IF;

  IF year_input IS NULL OR year_input < 2000 THEN
    RAISE EXCEPTION 'Year must be 2000 or later';
  END IF;

  IF amount_input IS NULL OR amount_input < 0 THEN
    RAISE EXCEPTION 'Amount must be zero or greater';
  END IF;

  -- Upsert annual budget using partial unique index as conflict target
  RETURN QUERY
  INSERT INTO public.site_budgets (site_id, year, month, budget, memo, updated_at, is_active)
  VALUES (site_id_input, year_input, NULL, amount_input, memo_input, now(), true)
  ON CONFLICT (site_id, year) WHERE month IS NULL AND is_active = true
  DO UPDATE SET
    budget     = EXCLUDED.budget,
    memo       = EXCLUDED.memo,
    updated_at = now(),
    is_active  = true
  RETURNING site_budgets.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_site_budget_secure(
  text, uuid, integer, integer, text
) TO anon, authenticated;
