-- ============================================================
-- Secure RPCs for invoices and site_budgets
-- Run in Supabase SQL Editor
-- All 8 functions require a valid admin session token.
-- company_id for invoices is resolved server-side from sites table.
-- search_path includes 'extensions' for pgcrypto digest().
-- ============================================================


-- ------------------------------------------------------------
-- Helper: session validation snippet (used in every RPC below)
--
-- IF NOT EXISTS (
--   SELECT 1 FROM public.admin_sessions s
--   WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
--     AND  s.expires_at > now()
-- ) THEN
--   RAISE EXCEPTION 'Invalid or expired session';
-- END IF;
-- ------------------------------------------------------------


-- ============================================================
-- 1. create_invoice_secure
--    Insert a new invoice after verifying admin session.
--    company_id is resolved from sites table; never trusted from client.
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_invoice_secure(
  session_token_input  text,
  invoice_date_input   date,
  site_id_input        uuid,
  vendor_name_input    text,
  category_input       text,
  amount_input         integer,
  tax_included_input   boolean,
  description_input    text    DEFAULT NULL,
  memo_input           text    DEFAULT NULL
)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_company_id uuid;
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
  IF vendor_name_input IS NULL OR trim(vendor_name_input) = '' THEN
    RAISE EXCEPTION 'Vendor name is required';
  END IF;

  IF amount_input IS NULL OR amount_input <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  -- Resolve company_id server-side
  IF site_id_input IS NOT NULL THEN
    SELECT s.company_id INTO v_company_id
    FROM   public.sites s
    WHERE  s.id = site_id_input;
  ELSE
    v_company_id := NULL;
  END IF;

  -- Insert invoice
  RETURN QUERY
  INSERT INTO public.invoices (
    invoice_date,
    site_id,
    company_id,
    vendor_name,
    category,
    amount,
    tax_included,
    description,
    memo,
    status
  )
  VALUES (
    invoice_date_input,
    site_id_input,
    v_company_id,
    trim(vendor_name_input),
    category_input,
    amount_input,
    tax_included_input,
    description_input,
    memo_input,
    'confirmed'
  )
  RETURNING invoices.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_invoice_secure(
  text, date, uuid, text, text, integer, boolean, text, text
) TO anon, authenticated;


-- ============================================================
-- 2. update_invoice_secure
--    Update an existing invoice after verifying admin session.
--    company_id is resolved from sites table; never trusted from client.
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_invoice_secure(
  session_token_input  text,
  id_input             uuid,
  invoice_date_input   date,
  site_id_input        uuid,
  vendor_name_input    text,
  category_input       text,
  amount_input         integer,
  tax_included_input   boolean,
  description_input    text    DEFAULT NULL,
  memo_input           text    DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_company_id uuid;
  v_rows       integer;
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
  IF vendor_name_input IS NULL OR trim(vendor_name_input) = '' THEN
    RAISE EXCEPTION 'Vendor name is required';
  END IF;

  IF amount_input IS NULL OR amount_input <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  -- Resolve company_id server-side
  IF site_id_input IS NOT NULL THEN
    SELECT s.company_id INTO v_company_id
    FROM   public.sites s
    WHERE  s.id = site_id_input;
  ELSE
    v_company_id := NULL;
  END IF;

  -- Update invoice
  UPDATE public.invoices i
  SET    invoice_date = invoice_date_input,
         site_id      = site_id_input,
         company_id   = v_company_id,
         vendor_name  = trim(vendor_name_input),
         category     = category_input,
         amount       = amount_input,
         tax_included = tax_included_input,
         description  = description_input,
         memo         = memo_input
  WHERE  i.id = id_input;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Invoice not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_invoice_secure(
  text, uuid, date, uuid, text, text, integer, boolean, text, text
) TO anon, authenticated;


-- ============================================================
-- 3. reject_invoice_secure
--    Set invoice status to 'rejected' (logical delete).
-- ============================================================
CREATE OR REPLACE FUNCTION public.reject_invoice_secure(
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
  -- Verify session token
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  UPDATE public.invoices i
  SET    status = 'rejected'
  WHERE  i.id = id_input;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Invoice not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_invoice_secure(text, uuid)
  TO anon, authenticated;


-- ============================================================
-- 4. restore_invoice_secure
--    Set invoice status to 'confirmed' (restore from rejected).
-- ============================================================
CREATE OR REPLACE FUNCTION public.restore_invoice_secure(
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
  -- Verify session token
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  UPDATE public.invoices i
  SET    status = 'confirmed'
  WHERE  i.id = id_input;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Invoice not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.restore_invoice_secure(text, uuid)
  TO anon, authenticated;


-- ============================================================
-- 5. upsert_site_budget_secure
--    Insert or update a site budget (conflict on site_id, year, month).
--    month is always NULL (annual budget only).
-- ============================================================
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

  -- Upsert budget
  RETURN QUERY
  INSERT INTO public.site_budgets (site_id, year, month, budget, memo, updated_at, is_active)
  VALUES (site_id_input, year_input, NULL, amount_input, memo_input, now(), true)
  ON CONFLICT (site_id, year, month)
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


-- ============================================================
-- 6. update_site_budget_secure
--    Update an existing site budget row by id.
--    Used when editing an existing budget entry (admin only).
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_site_budget_secure(
  session_token_input text,
  id_input            uuid,
  site_id_input       uuid,
  year_input          integer,
  amount_input        integer,
  memo_input          text    DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_rows integer;
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

  -- Update budget
  UPDATE public.site_budgets b
  SET    site_id    = site_id_input,
         year       = year_input,
         month      = NULL,
         budget     = amount_input,
         memo       = memo_input,
         updated_at = now(),
         is_active  = true
  WHERE  b.id = id_input;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Budget not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_site_budget_secure(
  text, uuid, uuid, integer, integer, text
) TO anon, authenticated;


-- ============================================================
-- 7. deactivate_site_budget_secure
--    Set site budget is_active to false (logical delete).
-- ============================================================
CREATE OR REPLACE FUNCTION public.deactivate_site_budget_secure(
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
  -- Verify session token
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  UPDATE public.site_budgets b
  SET    is_active = false
  WHERE  b.id = id_input;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Budget not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_site_budget_secure(text, uuid)
  TO anon, authenticated;


-- ============================================================
-- 8. restore_site_budget_secure
--    Restore a deactivated site budget (set is_active to true).
--    Raises an error if another active budget for the same
--    site_id + year + month already exists.
-- ============================================================
CREATE OR REPLACE FUNCTION public.restore_site_budget_secure(
  session_token_input text,
  id_input            uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_site_id uuid;
  v_year    integer;
  v_rows    integer;
BEGIN
  -- Verify session token
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Fetch target budget
  SELECT b.site_id, b.year
  INTO   v_site_id, v_year
  FROM   public.site_budgets b
  WHERE  b.id = id_input;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Budget not found';
  END IF;

  -- Check for duplicate active budget (same site_id + year + month IS NULL)
  IF EXISTS (
    SELECT 1
    FROM   public.site_budgets b
    WHERE  b.site_id   = v_site_id
      AND  b.year      = v_year
      AND  b.month     IS NULL
      AND  b.is_active = true
      AND  b.id       <> id_input
  ) THEN
    RAISE EXCEPTION 'Duplicate active budget exists';
  END IF;

  -- Restore budget
  UPDATE public.site_budgets b
  SET    is_active = true
  WHERE  b.id = id_input;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Budget not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.restore_site_budget_secure(text, uuid)
  TO anon, authenticated;
