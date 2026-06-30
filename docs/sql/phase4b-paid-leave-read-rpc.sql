-- ============================================================
-- Phase 4-B：paid_leave 読み取りRPC追加
-- ============================================================
-- 【実行ステータス】★実行済み★
--   - 実行日：2026-06-30
--   - Supabase SQL Editor 実行結果：Success. No rows returned
--   - RPC追加成功：
--       public.list_my_paid_leave_secure(text)
--       public.list_paid_leave_admin_secure(text)
--   - 新規2関数：PUBLIC EXECUTE は外し、anon / authenticated / service_role
--     に明示 GRANT 済み（proacl に =X/postgres 無し／3ロール付与を確認）。
--   - 事後確認 D / E / E-2 / F：いずれも期待どおりで完了。
--   - 既存 write RPC 3本は不変（security_definer=true / search_path 維持）。
--
--   【まだ未実施（後フェーズ）】
--   - paid_leave_requests / paid_leave_grants の SELECT REVOKE：未実施
--   - plr_read / plg_read policy 削除：未実施
--   - index.html / admin-app.html のフロント移行：未実施
--   - docs（workflow等）への記録：未実施
-- ============================================================
-- 目的：
--   paid_leave_requests / paid_leave_grants の anon 直接 SELECT を
--   将来 REVOKE するための準備として、本人用／管理者用の
--   読み取り専用 RPC（SECURITY DEFINER）を追加する。
--
-- このファイルの方針（重要）：
--   - まだ REVOKE しない（paid_leave_requests / paid_leave_grants の
--     anon/authenticated SELECT 権限は残したまま）。
--   - まだ policy 削除しない（plr_read / plg_read は触らない）。
--   - 既存 write RPC（create_paid_leave_request_secure /
--     review_paid_leave_request_secure / save_paid_leave_grant_secure）は
--     一切変更しない（EXECUTE 権限の変更も含めて触らない）。
--   - フロント移行前の「新旧併存」用。既存の直接 SELECT と新RPCが
--     同時に成立する状態を作る。
--
--   【EXECUTE 権限の方針（Phase 4-B 新規read RPC）】
--   - 新規2関数は CREATE 時にデフォルト付与される PUBLIC EXECUTE を外す。
--   - anon / authenticated / service_role にのみ EXECUTE を明示 GRANT する。
--   - 既存 write RPC の EXECUTE 権限（PUBLIC 残）は今回は変更しない。
--
-- 追加する RPC：
--   1. public.list_my_paid_leave_secure(text)    … 本人用（employee_sessions）
--   2. public.list_paid_leave_admin_secure(text) … 管理者用（二経路検証）
--
-- 実行方法：
--   Supabase SQL Editor で各セクションを順に実行。
--   「事前確認」→「変更（CREATE/GRANT）」→「事後確認」の順。
--   ※ 本ファイルは SQL 案。実行・本番反映はフロント移行と合わせて別途判断。
--
-- 検証パターンの流用元：
--   - 本人検証：employee-report-secure-rpc.sql の create_report_secure
--   - 二経路検証：paid-leave-admin-session-compatible-rpc.sql の
--     review_paid_leave_request_secure
-- ============================================================


-- ============================================================
-- 事前確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- A. paid_leave 2テーブルの anon/authenticated/PUBLIC 権限
--    期待：SELECT のみ残存（INSERT/UPDATE/DELETE は REVOKE 済）。
--    この時点ではまだ SELECT が残っていてよい（REVOKE は後フェーズ）。
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('paid_leave_requests', 'paid_leave_grants')
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
GROUP BY table_name, grantee
ORDER BY table_name, grantee;

-- B. paid_leave 2テーブルの既存 policy（plr_read / plg_read 等の現状確認）
--    このフェーズでは削除しない。現状把握のみ。
SELECT tablename,
       policyname,
       permissive,
       cmd,
       roles,
       qual,
       with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('paid_leave_requests', 'paid_leave_grants')
ORDER BY tablename, cmd, policyname;

-- C. 既存の paid_leave 系 RPC 一覧（write RPC を壊していないかの基準）
--    期待：create_/review_/save_ の write RPC が存在。
--    本ファイル実行後に list_ 2本が増える。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       p.proconfig      AS config,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname LIKE '%paid_leave%'
ORDER BY p.proname;


-- ============================================================
-- 変更（CREATE OR REPLACE FUNCTION × 2 / REVOKE × 2 / GRANT × 2）
--   実行順：CREATE 2本 → REVOKE PUBLIC 2本 → GRANT 2本
-- ============================================================

-- ------------------------------------------------------------
-- 1. list_my_paid_leave_secure(session_token_input text)
--    本人用。employee_sessions でセッション検証し、
--    本人 employee_id の grants / requests だけを jsonb で返す。
--    返却：
--      {
--        "grants":   [ {"year":..., "granted":...}, ... ],
--        "requests": [ {"leave_date":..., "leave_type":..., "status":..., "reason":...}, ... ]
--      }
--    requests は leave_date desc 順。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_my_paid_leave_secure(
  session_token_input text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
  v_result      jsonb;
BEGIN
  -- セッション検証：トークンから employee_id をサーバー側で確定
  SELECT es.employee_id
  INTO   v_employee_id
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true
  LIMIT 1;

  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- 本人分の grants / requests だけを集約して返す
  SELECT jsonb_build_object(
    'grants', COALESCE((
      SELECT jsonb_agg(
               jsonb_build_object(
                 'year',    g.year,
                 'granted', g.granted
               )
               ORDER BY g.year
             )
      FROM   public.paid_leave_grants g
      WHERE  g.employee_id = v_employee_id
    ), '[]'::jsonb),
    'requests', COALESCE((
      SELECT jsonb_agg(
               jsonb_build_object(
                 'leave_date', r.leave_date,
                 'leave_type', r.leave_type,
                 'status',     r.status,
                 'reason',     r.reason
               )
               ORDER BY r.leave_date DESC
             )
      FROM   public.paid_leave_requests r
      WHERE  r.employee_id = v_employee_id
    ), '[]'::jsonb)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;


-- ------------------------------------------------------------
-- 2. list_paid_leave_admin_secure(session_token_input text)
--    管理者用。二経路検証（review_paid_leave_request_secure と同型）：
--      a. employee_sessions + employees.role = 'admin'
--      b. admin_sessions + genka_admins.is_active = true
--    どちらも不成立なら RAISE EXCEPTION。
--    全員分の grants / approved / pending を jsonb で返す。
--    返却：
--      {
--        "grants":   [ {"employee_id":..., "year":..., "granted":...}, ... ],
--        "approved": [ {"employee_id":..., "leave_type":...}, ... ],
--        "pending":  [ {"id":..., "employee_id":..., "leave_date":..., "leave_type":..., "reason":...}, ... ]
--      }
--    pending は leave_date asc 順。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_paid_leave_admin_secure(
  session_token_input text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_role     text;
  v_is_admin boolean := false;
  v_result   jsonb;
BEGIN
  -- 経路a：employee_sessions の管理者
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

  -- 経路b：admin_sessions + genka_admins
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

  -- 全員分の grants / approved / pending を集約して返す
  SELECT jsonb_build_object(
    'grants', COALESCE((
      SELECT jsonb_agg(
               jsonb_build_object(
                 'employee_id', g.employee_id,
                 'year',        g.year,
                 'granted',     g.granted
               )
             )
      FROM   public.paid_leave_grants g
    ), '[]'::jsonb),
    'approved', COALESCE((
      SELECT jsonb_agg(
               jsonb_build_object(
                 'employee_id', r.employee_id,
                 'leave_type',  r.leave_type
               )
             )
      FROM   public.paid_leave_requests r
      WHERE  r.status = 'approved'
    ), '[]'::jsonb),
    'pending', COALESCE((
      SELECT jsonb_agg(
               jsonb_build_object(
                 'id',          r.id,
                 'employee_id', r.employee_id,
                 'leave_date',  r.leave_date,
                 'leave_type',  r.leave_type,
                 'reason',      r.reason
               )
               ORDER BY r.leave_date ASC
             )
      FROM   public.paid_leave_requests r
      WHERE  r.status = 'pending'
    ), '[]'::jsonb)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;


-- ------------------------------------------------------------
-- 3. REVOKE PUBLIC EXECUTE → GRANT EXECUTE（最小権限）
--    CREATE FUNCTION 時にデフォルト付与される PUBLIC の EXECUTE を外し、
--    anon / authenticated / service_role にのみ明示的に付与する。
--    （SECURITY DEFINER のため、後フェーズで直接 SELECT を REVOKE しても
--      RPC 経由の読み取りは動作継続する）
--    ※ 実行順：CREATE 2本 → REVOKE 2本 → GRANT 2本
-- ------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.list_my_paid_leave_secure(text)    FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_paid_leave_admin_secure(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_my_paid_leave_secure(text)    TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_paid_leave_admin_secure(text) TO anon, authenticated, service_role;


-- ============================================================
-- 事後確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- D. 作成された関数 / SECURITY DEFINER / search_path
--    期待：list_my_paid_leave_secure / list_paid_leave_admin_secure が
--    security_definer=true、config に search_path=public, extensions。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       p.proconfig      AS config,           -- {search_path=public, extensions} を期待
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('list_my_paid_leave_secure', 'list_paid_leave_admin_secure')
ORDER BY p.proname;

-- E. EXECUTE 権限（anon / authenticated / service_role に付与され、PUBLIC が無いか）
--    期待：anon / authenticated / service_role の3行が出る。
--          PUBLIC は出ない（REVOKE 済のため）。
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name IN ('list_my_paid_leave_secure', 'list_paid_leave_admin_secure')
  AND grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER BY routine_name, grantee;

-- E-2. proacl 直接確認（PUBLIC EXECUTE が外れていることの権威的チェック）
--    期待：proacl に =X/postgres（先頭が空＝PUBLIC）が無い。
--          anon=X/postgres / authenticated=X/postgres / service_role=X/postgres が有る。
SELECT p.proname,
       p.proacl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'list_my_paid_leave_secure',
    'list_paid_leave_admin_secure'
  )
ORDER BY p.proname;

-- F. 既存 write RPC が変化していないことの確認
--    期待：create_/review_/save_ の3本が引き続き security_definer=true で存在。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
        'create_paid_leave_request_secure',
        'review_paid_leave_request_secure',
        'save_paid_leave_grant_secure'
      )
ORDER BY p.proname;

-- ============================================================
-- このファイルに「含めていない」もの（後フェーズで別途）：
--   - paid_leave_requests / paid_leave_grants の SELECT REVOKE
--   - plr_read / plg_read policy の削除・整理
--   - index.html / admin-app.html のフロント移行
--   ※ いずれもフロント移行＆本番確認が完了してから実施する。
-- ============================================================
