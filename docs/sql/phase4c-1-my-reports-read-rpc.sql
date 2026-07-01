-- ============================================================
-- Phase 4-C-1：本人日報 read RPC 追加（list_my_reports_secure）
-- ============================================================
-- 【実行ステータス】★実行済み★
--   - 実行日：2026-07-01
--   - Supabase SQL Editor 実行結果：
--       CREATE FUNCTION public.list_my_reports_secure(text, date, integer) … Success. No rows returned
--       REVOKE EXECUTE ... FROM PUBLIC                                       … Success. No rows returned
--       GRANT EXECUTE ... TO anon, authenticated, service_role              … Success. No rows returned
--   - 事前確認A〜E：OK
--       A reports 権限：anon/authenticated SELECT のみ（INSERT/UPDATE/DELETE なし）
--       B reports policy：reports_all / ALL / {public} / qual=true / with_check=true
--       C reports write RPC 3本：存在・SECURITY DEFINER=true・search_path=public, extensions
--       D employee_sessions / employees 検証列：存在
--       E list_my_reports_secure：事前は 0 件（新規）
--   - 事後確認F〜J：OK
--       F list_my_reports_secure：存在・SECURITY DEFINER=true・search_path=public, extensions
--         （args=session_token_input text, before_date_input date, limit_input integer）
--       G EXECUTE：anon / authenticated / service_role = true
--       G-2 PUBLIC EXECUTE：false
--         （proacl={postgres=X/postgres, anon=X/postgres, authenticated=X/postgres, service_role=X/postgres}）
--       H reports write RPC 3本：不変・SECURITY DEFINER=true・search_path=public, extensions
--       I reports 権限：anon/authenticated SELECT はまだ残存（INSERT/UPDATE/DELETE なし）
--       J report_summary：view・owner=postgres・reloptions=null・anon/authenticated SELECT はまだ残存
--
--   【まだ未実施（後フェーズ）】
--   - reports の anon/authenticated 直接 SELECT の REVOKE：未実施
--   - reports_all policy の変更・削除・SELECT 分離：未実施（未変更）
--   - report_summary View の権限・定義変更：未実施（未変更）
--   - index.html のフロント移行（copyFromYesterday / loadHistory）：未実施
--   - docs（roadmap / db-migrations 等）への記録：未実施
--
--   【次工程】
--   - index.html の loadHistory / copyFromYesterday を
--     list_my_reports_secure へ移行する
--     （loadHistory: before_date=NULL / limit=30、copyFromYesterday: before_date=today / limit=1）
--
-- 目的：
--   reports の本人読み取り（index.html の本人日報表示・編集・詳細・前日コピー）を
--   将来 secure RPC 経由へ移行するための前段として、
--   本人用の読み取り専用 RPC（SECURITY DEFINER）を1本追加する。
--
-- 対象フロント（移行先）：
--   - index.html copyFromYesterday（自分の直近1件・report_date < today）
--   - index.html loadHistory（自分の履歴・report_date desc・limit 30）
--     ※ startEdit / showDetail / renderHistory は loadHistory のデータ（window._historyData）
--        を参照するため、供給元が本RPCに変わるだけで表示ロジックの改修は原則不要。
--
-- このファイルの方針（重要）：
--   - まだ REVOKE しない（reports の anon/authenticated 直接 SELECT は残したまま）。
--   - まだ policy を変更しない（reports_all は触らない）。
--   - report_summary View は一切触らない（権限・定義とも変更しない）。
--   - 既存 write RPC（create_report_secure / update_report_secure /
--     update_report_photo_secure）は一切変更しない（EXECUTE 権限含め触らない）。
--   - フロント移行前の「新旧併存」用。既存の直接 SELECT と新 RPC が
--     同時に成立する状態を作る。
--
--   【EXECUTE 権限の方針（Phase 4-B read RPC と同一）】
--   - 新規関数は CREATE 時にデフォルト付与される PUBLIC EXECUTE を外す。
--   - anon / authenticated / service_role にのみ EXECUTE を明示 GRANT する。
--
-- 認可方式（既存 reports write RPC ＋ Phase 4-B read RPC の踏襲）：
--   - _verify_employee_session のような共通ヘルパーは新設しない。
--   - employee_sessions を inline で直接参照する。
--   - token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
--   - expires_at > now()
--   - employees を JOIN して is_active = true も確認する（4-B read と同型）。
--   - employee_id はクライアントから受け取らず、session_token から
--     サーバ側で確定する（v_employee_id）。
--   - 不正 / 期限切れセッションは RAISE EXCEPTION。
--
-- 実行方法（実行する場合）：
--   Supabase SQL Editor で各セクションを順に実行。
--   「事前確認」→「変更（CREATE / REVOKE / GRANT）」→「事後確認」の順。
--   ※ 実行順：CREATE 1本 → REVOKE PUBLIC 1本 → GRANT 1本。
--
-- 検証パターンの流用元：
--   - 本人検証（inline）：employee-report-secure-rpc.sql の create_report_secure
--   - is_active 確認付き read：phase4b-paid-leave-read-rpc.sql の list_my_paid_leave_secure
-- ============================================================


-- ============================================================
-- 事前確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- A. reports の anon / authenticated / PUBLIC 権限
--    期待：SELECT のみ残存（INSERT/UPDATE/DELETE は Phase 3 で REVOKE 済）。
--    この時点ではまだ SELECT が残っていてよい（REVOKE は後フェーズ）。
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'reports'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
GROUP BY table_name, grantee
ORDER BY table_name, grantee;

-- B. reports の既存 policy（reports_all の現状確認）
--    このフェーズでは削除・変更しない。現状把握のみ。
--    期待：reports_all（cmd=ALL / roles={public} / qual=true / with_check=true）。
SELECT tablename,
       policyname,
       permissive,
       cmd,
       roles,
       qual,
       with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'reports'
ORDER BY cmd, policyname;

-- C. 既存 reports write RPC 3本の存在確認（壊していないかの基準）
--    期待：create_report_secure / update_report_secure /
--          update_report_photo_secure が存在。
--    本ファイル実行後に list_my_reports_secure が1本増える。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       p.proconfig      AS config,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
        'create_report_secure',
        'update_report_secure',
        'update_report_photo_secure'
      )
ORDER BY p.proname;

-- D. 検証前提の確認（employee_sessions / employees の存在と主要列）
--    期待：employee_sessions に token_hash / expires_at / employee_id、
--          employees に id / is_active が存在。
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
        (table_name = 'employee_sessions' AND column_name IN ('employee_id', 'token_hash', 'expires_at'))
     OR (table_name = 'employees'         AND column_name IN ('id', 'is_active'))
      )
ORDER BY table_name, column_name;

-- E. list_my_reports_secure がまだ存在しない、または置換対象かの確認
--    期待：0行（新規）。既に存在する場合は CREATE OR REPLACE で置換される。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_my_reports_secure'
ORDER BY p.proname;


-- ============================================================
-- 変更（CREATE OR REPLACE FUNCTION × 1 / REVOKE × 1 / GRANT × 1）
--   実行順：CREATE 1本 → REVOKE PUBLIC 1本 → GRANT 1本
-- ============================================================

-- ------------------------------------------------------------
-- 1. list_my_reports_secure(session_token_input, before_date_input, limit_input)
--    本人用。employee_sessions でセッション検証し、
--    本人 employee_id の reports 行だけを返す。
--    loadHistory と copyFromYesterday を1本で兼用する。
--      - loadHistory      : before_date_input = NULL, limit_input = 30
--      - copyFromYesterday: before_date_input = today, limit_input = 1
--    並び順：report_date DESC。
--    limit_input は濫用防止のため 1〜100 に丸める。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_my_reports_secure(
  session_token_input text,
  before_date_input   date    DEFAULT NULL,
  limit_input         integer DEFAULT 30
)
RETURNS TABLE (
  id                  uuid,
  report_date         date,
  employee_id         uuid,
  start_time          time,
  end_time            time,
  normal_mins         integer,
  overtime_mins       integer,
  site_ids            uuid[],
  material_ids        uuid[],
  material_quantities jsonb,
  subcontractor_ids   uuid[],
  sub_machines        jsonb,
  work_type           text,
  memo                text,
  photo_count         integer,
  photo_urls          text[],
  dump_count          integer,
  dump_company        text,
  guard_count         integer,
  status              text,
  created_at          timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
  v_limit       integer;
BEGIN
  -- セッション検証：トークンから employee_id をサーバ側で確定
  -- （employees を JOIN し is_active = true も確認：Phase 4-B read と同型）
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

  -- limit を 1〜100 に丸める（NULL は既定 30 扱い）
  v_limit := GREATEST(1, LEAST(COALESCE(limit_input, 30), 100));

  -- 本人分の reports 行のみ返す
  -- （employee_id は v_employee_id 固定。before_date_input があれば
  --   report_date < before_date_input を付与＝前日コピー用）
  RETURN QUERY
  SELECT r.id,
         r.report_date,
         r.employee_id,
         r.start_time,
         r.end_time,
         r.normal_mins,
         r.overtime_mins,
         r.site_ids,
         r.material_ids,
         r.material_quantities,
         r.subcontractor_ids,
         r.sub_machines,
         r.work_type,
         r.memo,
         r.photo_count,
         r.photo_urls,
         r.dump_count,
         r.dump_company,
         r.guard_count,
         r.status,
         r.created_at
  FROM   public.reports r
  WHERE  r.employee_id = v_employee_id
    AND  (before_date_input IS NULL OR r.report_date < before_date_input)
  ORDER  BY r.report_date DESC
  LIMIT  v_limit;
END;
$$;


-- ------------------------------------------------------------
-- 2. REVOKE PUBLIC EXECUTE → GRANT EXECUTE（最小権限）
--    CREATE FUNCTION 時にデフォルト付与される PUBLIC の EXECUTE を外し、
--    anon / authenticated / service_role にのみ明示的に付与する。
--    （SECURITY DEFINER のため、後フェーズで reports の直接 SELECT を
--      REVOKE しても RPC 経由の読み取りは動作継続する）
--    ※ 実行順：CREATE 1本 → REVOKE 1本 → GRANT 1本
-- ------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.list_my_reports_secure(text, date, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_my_reports_secure(text, date, integer) TO anon, authenticated, service_role;


-- ============================================================
-- 事後確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- F. 作成された関数 / SECURITY DEFINER / search_path
--    期待：list_my_reports_secure が security_definer=true、
--          config に search_path=public, extensions。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       p.proconfig      AS config,           -- {search_path=public, extensions} を期待
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_my_reports_secure'
ORDER BY p.proname;

-- G. EXECUTE 権限（anon / authenticated / service_role に付与され、PUBLIC が無いか）
--    期待：anon / authenticated / service_role の3行が出る。
--          PUBLIC は出ない（REVOKE 済のため）。
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name = 'list_my_reports_secure'
  AND grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER BY routine_name, grantee;

-- G-2. proacl 直接確認（PUBLIC EXECUTE が外れていることの権威的チェック）
--    期待：proacl に =X/postgres（先頭が空＝PUBLIC）が無い。
--          anon=X/postgres / authenticated=X/postgres / service_role=X/postgres が有る。
SELECT p.proname,
       p.proacl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_my_reports_secure'
ORDER BY p.proname;

-- H. 既存 reports write RPC 3本が不変であることの確認
--    期待：3本が引き続き security_definer=true で存在。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
        'create_report_secure',
        'update_report_secure',
        'update_report_photo_secure'
      )
ORDER BY p.proname;

-- I. reports の SELECT がまだ REVOKE されていないことの確認（新旧併存の担保）
--    期待：anon / authenticated に SELECT が残っている（このフェーズでは剥がさない）。
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'reports'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND privilege_type = 'SELECT'
GROUP BY table_name, grantee
ORDER BY table_name, grantee;

-- J. report_summary が未変更であることの確認（今回触っていない担保）
--    期待：view のまま、anon / authenticated の SELECT も従来どおり残存。
SELECT table_name AS view_name,
       grantee,
       privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'report_summary'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND privilege_type = 'SELECT'
ORDER BY grantee;


-- ============================================================
-- このファイルで「行わない」こと（後フェーズで別途）：
--   - reports の anon/authenticated 直接 SELECT の REVOKE
--   - reports_all policy の変更・削除・SELECT 分離
--   - report_summary View の権限変更・定義変更・廃止
--   - index.html のフロント移行（copyFromYesterday / loadHistory）
--   - docs（roadmap / db-migrations 等）への記録
--   ※ reports direct SELECT 遮断は、フロント移行＆本番確認が
--      完了してから 4-C-1 の最終ステップとして実施する。
-- ============================================================
