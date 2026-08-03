-- ============================================================
-- Phase 7-D TARGET ONLY: Storage photos bucket + policy restore
-- ⚠️  TARGET（local restore-lab）DB のみで使用する。
-- ⚠️  SOURCE（Production）DB では絶対に実行しない。
-- ⚠️  psql 変数による明示的 human gate 付き。
-- ============================================================
--
-- 実行方法（docker exec psql）:
--   docker exec -i $DB_CONTAINER psql -U postgres -d postgres \
--     -v confirmed='yes' \
--     -f /tmp/phase7d-storage-policy-restore.sql
--
-- 変数説明:
--   confirmed : 'yes' のみ処理を継続。未設定または 'yes' 以外なら中止。
--
-- このファイルで行うこと:
--   1. photos bucket を冪等に作成・設定（Production 実測値どおり）
--   2. photos_read / photos_upload policy を Production 実測値どおり再現
--
-- このファイルで行わないこと:
--   - notice_attachments_insert の作成
--   - storage managed grants の GRANT / REVOKE
--   - Production policy の改善（employee session 検証追加・path 制限追加等）
--   - PUBLIC INSERT の変更（既存 Production 仕様を忠実に再現）
--
-- 既知リスク（KC-5）:
--   photos_upload は PUBLIC INSERT policy（employee session 検証なし・path 制限なし）。
--   これは Production と同じ実装であり、restore-lab で忠実に再現する。
--   将来のセキュリティレビュー候補だが、今回 Production 変更は行わない。
-- ============================================================

-- ============================================================
-- GATE 1: confirmed 変数チェック
-- ============================================================
\if :{?confirmed}
\else
  \echo 'ERROR: psql variable :confirmed is not set.'
  \echo 'Pass -v confirmed=yes to proceed.'
  \quit
\endif

\if :confirmed = 'yes'
\else
  \echo 'ERROR: :confirmed is not yes. Aborting.'
  \quit
\endif

-- ============================================================
-- GATE 2: TARGET DB が localhost / unix socket であること
-- ============================================================
DO $$
DECLARE
  v_addr text;
BEGIN
  SELECT inet_server_addr()::text INTO v_addr;
  IF v_addr IS NOT NULL
     AND v_addr NOT IN ('127.0.0.1', '::1') THEN
    RAISE EXCEPTION
      'inet_server_addr() = %. Not a local connection. SAFETY ABORT.',
      v_addr;
  END IF;
END;
$$;

-- ============================================================
-- GATE 3: storage.objects の RLS が有効であること
-- ============================================================
DO $$
DECLARE
  v_rls boolean;
BEGIN
  SELECT c.relrowsecurity INTO v_rls
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'storage' AND c.relname = 'objects' AND c.relkind = 'r';

  IF v_rls IS NULL THEN
    RAISE EXCEPTION 'storage.objects not found. Is local Supabase running? BLOCKED.';
  END IF;
  IF NOT v_rls THEN
    RAISE EXCEPTION
      'storage.objects RLS is disabled. Do NOT auto-enable. BLOCKED. Investigate first.';
  END IF;
END;
$$;

-- ============================================================
-- MAIN: photos bucket + policy restore（1 transaction）
-- ============================================================
BEGIN;

-- Step 1: photos bucket を冪等に作成・設定
-- Production 実測値: public=true / file_size_limit=5242880 / allowed_mime_types={image/jpeg}
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'photos',
  'photos',
  true,
  5242880,
  ARRAY['image/jpeg']
)
ON CONFLICT (id) DO UPDATE
  SET name               = EXCLUDED.name,
      public             = EXCLUDED.public,
      file_size_limit    = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Step 2: photos_read policy を冪等に再現
-- Production 実測値: PERMISSIVE / SELECT / PUBLIC / USING: bucket_id = 'photos'::text
DROP POLICY IF EXISTS photos_read ON storage.objects;
CREATE POLICY photos_read
  ON storage.objects
  AS PERMISSIVE
  FOR SELECT
  TO PUBLIC
  USING (bucket_id = 'photos'::text);

-- Step 3: photos_upload policy を冪等に再現
-- Production 実測値: PERMISSIVE / INSERT / PUBLIC / WITH CHECK: bucket_id = 'photos'::text
-- ⚠️ KC-5: PUBLIC INSERT policy（employee session 検証なし・path 制限なし）
--          これは Production と同じ実装。restore-lab で忠実に再現する。
--          将来のセキュリティレビュー候補。今回 Production 変更は行わない。
DROP POLICY IF EXISTS photos_upload ON storage.objects;
CREATE POLICY photos_upload
  ON storage.objects
  AS PERMISSIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK (bucket_id = 'photos'::text);

COMMIT;

-- ============================================================
-- POST-CHECK: 設定・policy の確認（read-only）
-- ============================================================

-- photos bucket 設定確認
-- 期待: public=true / file_size_limit=5242880 / allowed_mime_types={image/jpeg}
SELECT
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
FROM storage.buckets
WHERE id = 'photos';

-- storage.objects RLS 確認
-- 期待: rls_enabled=true
SELECT
  n.nspname   AS schema_name,
  c.relname   AS table_name,
  c.relrowsecurity AS rls_enabled
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'storage' AND c.relname = 'objects' AND c.relkind = 'r';

-- photos policy 定義確認
-- 期待:
--   photos_read  : SELECT / PUBLIC / USING: bucket_id='photos'::text / WITH CHECK: NULL
--   photos_upload: INSERT / PUBLIC / USING: NULL / WITH CHECK: bucket_id='photos'::text
SELECT
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename  = 'objects'
  AND policyname IN ('photos_read', 'photos_upload')
ORDER BY policyname;
