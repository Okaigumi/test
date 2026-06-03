-- notice-attachments-rpc.sql
--
-- Adds image / PDF attachment support to the notices feature.
--
-- Steps:
--   1. Add 5 attachment columns to public.notices
--   2. Add CHECK constraint on attachment_type
--   3. Recreate 3 existing notice RPCs (DROP + CREATE)
--      Reason: RETURNS TABLE column list changes; CREATE OR REPLACE
--      cannot change a function's return type in PostgreSQL.
--   4. Create 2 new attachment RPCs
--   5. Grant EXECUTE on all 5 RPCs to anon, authenticated
--
-- Storage (done in Supabase dashboard, not SQL):
--   Bucket : notice-attachments  (public)
--   Path   : notices/{noticeId}/{timestamp}_{sanitized_filename}
--   MIME   : image/jpeg, image/png, image/webp, application/pdf
--   Size   : max 10 MB per file (bucket policy)
--   Images : 5 MB soft limit enforced on the frontend (no server-side resize)
--
-- NOTE: Create the notice-attachments Storage bucket first.
--       Then run this SQL before deploying frontend attachment changes.
--       Current admin-app.html / index.html are backward compatible with
--       the added columns and expanded RPC return fields.
-- Run in Supabase SQL Editor (run each section separately).
-- ============================================================


-- ============================================================
-- 1. ALTER TABLE: add attachment columns to notices
-- ============================================================
ALTER TABLE public.notices
  ADD COLUMN IF NOT EXISTS attachment_url  TEXT,
  ADD COLUMN IF NOT EXISTS attachment_path TEXT,
  ADD COLUMN IF NOT EXISTS attachment_type TEXT,
  ADD COLUMN IF NOT EXISTS attachment_name TEXT,
  ADD COLUMN IF NOT EXISTS updated_at      TIMESTAMPTZ;


-- ============================================================
-- 2. CHECK constraint on attachment_type
--    NULL = no attachment; 'image' or 'pdf' = attachment present
--    DROP first to make this script re-runnable.
-- ============================================================
ALTER TABLE public.notices
  DROP CONSTRAINT IF EXISTS notices_attachment_type_check;

ALTER TABLE public.notices
  ADD CONSTRAINT notices_attachment_type_check
  CHECK (attachment_type IS NULL OR attachment_type IN ('image', 'pdf'));


-- ============================================================
-- 3. Permissions: keep SELECT; revoke direct writes
--    Re-stated here for clarity; already applied in
--    notices-admin-rpc.sql.
-- ============================================================
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.notices
  FROM anon, authenticated;

GRANT SELECT
  ON TABLE public.notices
  TO anon, authenticated;


-- ============================================================
-- 4. Recreate 3 existing notice RPCs
--
--    Why DROP + CREATE instead of CREATE OR REPLACE?
--    PostgreSQL does not allow CREATE OR REPLACE to change the
--    return type of an existing function.  Adding attachment
--    columns to RETURNS TABLE is a return-type change, so
--    DROP FUNCTION IF EXISTS is required first.
--    GRANT EXECUTE is re-applied after each CREATE.
-- ============================================================

-- ---- 4-1. list_notices_admin_secure ----

DROP FUNCTION IF EXISTS public.list_notices_admin_secure(text);

CREATE FUNCTION public.list_notices_admin_secure(
  session_token_input text
)
RETURNS TABLE (
  id              uuid,
  content         text,
  is_active       boolean,
  created_at      timestamptz,
  attachment_url  text,
  attachment_path text,
  attachment_type text,
  attachment_name text,
  updated_at      timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  RETURN QUERY
  SELECT n.id, n.content, n.is_active, n.created_at,
         n.attachment_url, n.attachment_path, n.attachment_type, n.attachment_name,
         n.updated_at
  FROM   public.notices n
  ORDER BY n.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_notices_admin_secure(text)
  TO anon, authenticated;


-- ---- 4-2. create_notice_secure ----

DROP FUNCTION IF EXISTS public.create_notice_secure(text, text, boolean);

CREATE FUNCTION public.create_notice_secure(
  session_token_input text,
  content_input       text,
  is_active_input     boolean DEFAULT true
)
RETURNS TABLE (
  id              uuid,
  content         text,
  is_active       boolean,
  created_at      timestamptz,
  attachment_url  text,
  attachment_path text,
  attachment_type text,
  attachment_name text,
  updated_at      timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  IF content_input IS NULL OR trim(content_input) = '' THEN
    RAISE EXCEPTION 'Notice content is required';
  END IF;

  RETURN QUERY
  INSERT INTO public.notices (content, is_active, updated_at)
  VALUES (trim(content_input), is_active_input, now())
  RETURNING notices.id, notices.content, notices.is_active, notices.created_at,
            notices.attachment_url, notices.attachment_path, notices.attachment_type,
            notices.attachment_name, notices.updated_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_notice_secure(text, text, boolean)
  TO anon, authenticated;


-- ---- 4-3. update_notice_secure ----

DROP FUNCTION IF EXISTS public.update_notice_secure(text, uuid, text, boolean);

CREATE FUNCTION public.update_notice_secure(
  session_token_input text,
  id_input            uuid,
  content_input       text,
  is_active_input     boolean
)
RETURNS TABLE (
  id              uuid,
  content         text,
  is_active       boolean,
  created_at      timestamptz,
  attachment_url  text,
  attachment_path text,
  attachment_type text,
  attachment_name text,
  updated_at      timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  IF content_input IS NULL OR trim(content_input) = '' THEN
    RAISE EXCEPTION 'Notice content is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.notices n WHERE n.id = id_input
  ) THEN
    RAISE EXCEPTION 'Notice not found';
  END IF;

  RETURN QUERY
  UPDATE public.notices n
  SET    content    = trim(content_input),
         is_active  = is_active_input,
         updated_at = now()
  WHERE  n.id = id_input
  RETURNING n.id, n.content, n.is_active, n.created_at,
            n.attachment_url, n.attachment_path, n.attachment_type, n.attachment_name,
            n.updated_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_notice_secure(text, uuid, text, boolean)
  TO anon, authenticated;


-- ============================================================
-- 5. New RPCs: attachment management
-- ============================================================

-- ---- 5-1. update_notice_attachment_secure ----
--    Saves or replaces the attachment for a notice.
--    Storage upload is done on the frontend before calling this RPC.
--    Returns the full updated row so the frontend can update its cache.

CREATE OR REPLACE FUNCTION public.update_notice_attachment_secure(
  session_token_input   text,
  id_input              uuid,
  attachment_url_input  text,
  attachment_path_input text,
  attachment_type_input text,
  attachment_name_input text
)
RETURNS TABLE (
  id              uuid,
  content         text,
  is_active       boolean,
  created_at      timestamptz,
  attachment_url  text,
  attachment_path text,
  attachment_type text,
  attachment_name text,
  updated_at      timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  IF attachment_type_input NOT IN ('image', 'pdf') THEN
    RAISE EXCEPTION 'attachment_type must be image or pdf';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.notices n WHERE n.id = id_input
  ) THEN
    RAISE EXCEPTION 'Notice not found';
  END IF;

  RETURN QUERY
  UPDATE public.notices n
  SET    attachment_url  = attachment_url_input,
         attachment_path = attachment_path_input,
         attachment_type = attachment_type_input,
         attachment_name = attachment_name_input,
         updated_at      = now()
  WHERE  n.id = id_input
  RETURNING n.id, n.content, n.is_active, n.created_at,
            n.attachment_url, n.attachment_path, n.attachment_type, n.attachment_name,
            n.updated_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_notice_attachment_secure(text, uuid, text, text, text, text)
  TO anon, authenticated;


-- ---- 5-2. delete_notice_attachment_secure ----
--    NULLs out all attachment columns in DB only.
--    The file in Storage is NOT deleted by this RPC.
--    Employees no longer see the attachment because index.html
--    skips display when attachment_url IS NULL.
--    Orphaned files left in Storage are tolerated for now and
--    will be cleaned up manually or via a maintenance script.

CREATE OR REPLACE FUNCTION public.delete_notice_attachment_secure(
  session_token_input text,
  id_input            uuid
)
RETURNS TABLE (
  id              uuid,
  content         text,
  is_active       boolean,
  created_at      timestamptz,
  attachment_url  text,
  attachment_path text,
  attachment_type text,
  attachment_name text,
  updated_at      timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.notices n WHERE n.id = id_input
  ) THEN
    RAISE EXCEPTION 'Notice not found';
  END IF;

  RETURN QUERY
  UPDATE public.notices n
  SET    attachment_url  = NULL,
         attachment_path = NULL,
         attachment_type = NULL,
         attachment_name = NULL,
         updated_at      = now()
  WHERE  n.id = id_input
  RETURNING n.id, n.content, n.is_active, n.created_at,
            n.attachment_url, n.attachment_path, n.attachment_type, n.attachment_name,
            n.updated_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_notice_attachment_secure(text, uuid)
  TO anon, authenticated;


-- ============================================================
-- 6. Storage RLS policies for notice-attachments bucket
--
--    Why admin_sessions cannot be validated here:
--    Storage USING / WITH CHECK clauses run inside PostgreSQL
--    but cannot read custom request headers sent by the frontend.
--    auth.uid() is always NULL for anon-key requests because
--    this app does not use Supabase Auth.
--
--    MVP policy: INSERT only
--    - INSERT is restricted to paths starting with 'notices/'
--      so uploads cannot land in arbitrary locations.
--    - DELETE policy is intentionally omitted.  Allowing anon
--      DELETE would let any caller remove files if they know the
--      attachment_path from the public URL.
--    - Attachment removal is handled by delete_notice_attachment_secure,
--      which NULLs the attachment_* columns in DB only.
--      The file remains in Storage but is no longer shown to employees.
--    - Orphaned files in Storage are tolerated for now and will be
--      cleaned up manually or via a maintenance script as needed.
--    - Public read is covered by the bucket's public setting;
--      no SELECT policy is required.
--    - Bucket settings (MIME types + 10 MB limit) provide an
--      additional layer of defence for uploads.
--
--    Run AFTER the notice-attachments bucket is created in the
--    Supabase dashboard.  DROP + CREATE makes this re-runnable.
-- ============================================================

DROP POLICY IF EXISTS notice_attachments_insert ON storage.objects;

-- Upload: restricted to notices/ prefix within this bucket
CREATE POLICY notice_attachments_insert
ON storage.objects FOR INSERT TO anon
WITH CHECK (
  bucket_id = 'notice-attachments'
  AND name  LIKE 'notices/%'
);


-- ============================================================
-- Confirmation queries
-- Run each block separately AFTER all SQL above is executed.
-- ============================================================

-- [1] notices table columns
--     Expected: attachment_url, attachment_path, attachment_type,
--               attachment_name, updated_at exist
SELECT column_name, data_type, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'notices'
ORDER BY ordinal_position;

-- [2] attachment_type CHECK constraint
--     Expected: notices_attachment_type_check exists
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM   pg_constraint
WHERE  conrelid = 'public.notices'::regclass
  AND  contype  = 'c';

-- [3] notice RPC existence
--     Expected: 5 rows with routine_type = FUNCTION
SELECT routine_name, routine_type
FROM   information_schema.routines
WHERE  routine_schema = 'public'
  AND  routine_name IN (
    'list_notices_admin_secure',
    'create_notice_secure',
    'update_notice_secure',
    'update_notice_attachment_secure',
    'delete_notice_attachment_secure'
  )
ORDER BY routine_name;

-- [4] RPC EXECUTE permissions
--     Expected: 10 rows (5 RPCs x 2 roles, privilege_type = EXECUTE)
SELECT grantee, routine_name, privilege_type
FROM   information_schema.role_routine_grants
WHERE  routine_schema = 'public'
  AND  routine_name IN (
    'list_notices_admin_secure',
    'create_notice_secure',
    'update_notice_secure',
    'update_notice_attachment_secure',
    'delete_notice_attachment_secure'
  )
  AND  grantee IN ('anon', 'authenticated')
ORDER BY routine_name, grantee;

-- [5] notices permissions for anon / authenticated
--     Expected: SELECT only
SELECT grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name   = 'notices'
  AND  grantee IN ('anon', 'authenticated')
ORDER BY grantee, privilege_type;

-- [6] Storage RLS policies for notice-attachments
--     Expected: 1 row (insert)
SELECT policyname, cmd, roles
FROM   pg_policies
WHERE  schemaname = 'storage'
  AND  tablename  = 'objects'
  AND  policyname LIKE 'notice_attachments%'
ORDER BY policyname;
