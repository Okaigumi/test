-- notices-admin-rpc.sql
--
-- Creates 3 RPCs for notices management via admin-app.html.
-- Session token validation follows the same pattern as
-- create_employee_secure / update_employee_secure in
-- admin-session-step2-rpc.sql.
--
-- Creates:
--   1. list_notices_admin_secure   - Return all notices (admin only)
--   2. create_notice_secure        - Insert a new notice
--   3. update_notice_secure        - Update content / is_active
--
-- Does NOT create a delete RPC.
-- Visibility is managed via is_active=false (soft disable).
--
-- Run in Supabase SQL Editor.
-- ============================================================


-- ============================================================
-- 0. Revoke direct write access from anon / authenticated
--    SELECT is intentionally kept for index.html (loadNotice).
-- ============================================================
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.notices
  FROM anon, authenticated;

GRANT SELECT
  ON TABLE public.notices
  TO anon, authenticated;


-- ============================================================
-- 1. list_notices_admin_secure
--    Return all notices regardless of is_active, newest first.
--    Requires a valid admin session token.
-- ============================================================
CREATE OR REPLACE FUNCTION public.list_notices_admin_secure(
  session_token_input text
)
RETURNS TABLE (
  id         uuid,
  content    text,
  is_active  boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Admin session validation (same pattern as create_employee_secure)
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  RETURN QUERY
  SELECT n.id, n.content, n.is_active, n.created_at
  FROM   public.notices n
  ORDER BY n.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_notices_admin_secure(text)
  TO anon, authenticated;


-- ============================================================
-- 2. create_notice_secure
--    Insert a new notice. content must not be empty.
--    Returns the inserted row.
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_notice_secure(
  session_token_input text,
  content_input       text,
  is_active_input     boolean DEFAULT true
)
RETURNS TABLE (
  id         uuid,
  content    text,
  is_active  boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Admin session validation
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  -- content must not be blank
  IF content_input IS NULL OR trim(content_input) = '' THEN
    RAISE EXCEPTION 'Notice content is required';
  END IF;

  RETURN QUERY
  INSERT INTO public.notices (content, is_active)
  VALUES (trim(content_input), is_active_input)
  RETURNING notices.id, notices.content, notices.is_active, notices.created_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_notice_secure(text, text, boolean)
  TO anon, authenticated;


-- ============================================================
-- 3. update_notice_secure
--    Update content and is_active for an existing notice.
--    content must not be empty. Returns the updated row.
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_notice_secure(
  session_token_input text,
  id_input            uuid,
  content_input       text,
  is_active_input     boolean
)
RETURNS TABLE (
  id         uuid,
  content    text,
  is_active  boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Admin session validation
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  -- content must not be blank
  IF content_input IS NULL OR trim(content_input) = '' THEN
    RAISE EXCEPTION 'Notice content is required';
  END IF;

  -- Confirm the target notice exists before updating
  IF NOT EXISTS (SELECT 1 FROM public.notices WHERE id = id_input) THEN
    RAISE EXCEPTION 'Notice not found';
  END IF;

  RETURN QUERY
  UPDATE public.notices n
  SET    content   = trim(content_input),
         is_active = is_active_input
  WHERE  n.id = id_input
  RETURNING n.id, n.content, n.is_active, n.created_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_notice_secure(text, uuid, text, boolean)
  TO anon, authenticated;


-- ============================================================
-- Confirmation queries
-- Run each block separately after the RPCs above are created.
-- ============================================================

-- [1] notices table permissions for anon / authenticated
--     Expected: SELECT only; no INSERT / UPDATE / DELETE / TRUNCATE
SELECT grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name   = 'notices'
  AND  grantee IN ('anon', 'authenticated')
ORDER BY grantee, privilege_type;

-- [2] Existence of the 3 notice RPCs
--     Expected: 3 rows with routine_type = 'FUNCTION'
SELECT routine_name, routine_type
FROM   information_schema.routines
WHERE  routine_schema = 'public'
  AND  routine_name IN (
         'list_notices_admin_secure',
         'create_notice_secure',
         'update_notice_secure'
       )
ORDER BY routine_name;

-- [3] EXECUTE permissions on notice RPCs for anon / authenticated
--     Expected: 6 rows (3 RPCs x 2 roles, privilege_type = 'EXECUTE')
SELECT grantee, routine_name, privilege_type
FROM   information_schema.role_routine_grants
WHERE  routine_schema = 'public'
  AND  routine_name IN (
         'list_notices_admin_secure',
         'create_notice_secure',
         'update_notice_secure'
       )
  AND  grantee IN ('anon', 'authenticated')
ORDER BY routine_name, grantee;
