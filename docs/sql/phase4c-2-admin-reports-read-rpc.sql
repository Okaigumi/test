-- ============================================================
-- Phase 4-C-2：index 管理系 report_summary 代替 read RPC 追加
--   （list_admin_reports_secure）
-- ============================================================
-- 【実行ステータス】★実行済み（2026-07-01）★
--   - Supabase SQL Editor で「事前確認A〜G」→「変更（CREATE / REVOKE / GRANT）」
--     →「事後確認H〜K」→「動作確認L」の順に実行済み。
--   - 実行結果：
--       CREATE OR REPLACE FUNCTION public.list_admin_reports_secure(text, date, date)
--                                                              … Success. No rows returned
--       REVOKE EXECUTE ... FROM PUBLIC                        … Success. No rows returned
--       GRANT EXECUTE ... TO anon, authenticated, service_role … Success. No rows returned
--   - 事前確認A〜G：OK
--       A report_summary View定義（reports r JOIN employees e / e.name AS employee_name /
--         WHERE なし・通常View・owner=postgres・bypassrls=true・reloptions=null）：OK
--       B report_summary 列型：OK（RETURNS TABLE と整合）
--       C reports 列型：OK
--       D employees 必要列（id / name / role / is_active）：OK
--       E employee_sessions / admin_sessions / genka_admins 必要列：OK
--       F report_summary と reports JOIN employees の行数一致：OK
--           report_summary_rows=135 / reports_join_employees_rows=135 /
--           reports_rows=135 / reports_without_employee_rows=0
--       G list_admin_reports_secure 未存在（新規）：OK
--   - 事後確認H〜K：OK
--       H 関数存在・SECURITY DEFINER=true・search_path=public, extensions・
--         args=(session_token_input text, from_date_input date, to_date_input date)：OK
--       I EXECUTE：anon / authenticated / service_role = true：OK
--       I-2 PUBLIC EXECUTE：なし（proacl に =X/postgres なし）：OK
--       J report_summary：未変更（view のまま・anon/authenticated SELECT 残存）：OK
--       K reports 権限：未変更（Phase 4-C-1 完了状態から変化なし）：OK
--   - 動作確認L：OK
--       管理者ログイン状態の Console から sb.rpc('list_admin_reports_secure', ...) を実行：
--         success=true / error=null / data=Array(1) / status=200
--       （Console の favicon.ico 404 は本RPCと無関係）
--
--   【このファイルで変更していないもの（実行後も不変）】
--   - report_summary View の権限・定義・封鎖：未実施（→ Phase 4-C-4）
--   - reports の SELECT 等の権限：未変更
--   - policy（reports_all 等）：未変更
--   - 既存 RPC（reports write / paid_leave / csv 等）：未変更
--   - index.html のフロント移行（loadAdminData / loadStats）：未実施（別ステップ）
--   - genka-app.html の report_summary 参照：未対応（→ Phase 4-C-3）
--   - docs（roadmap / db-migrations 等）への記録：未実施（別ステップ）
--
-- 目的：
--   index.html の管理系日報表示（loadAdminData / loadStats）が現在
--   直接参照している report_summary View を、将来 View 封鎖できるよう
--   管理者セッション検証付きの read RPC 経由へ移行する。その前段として
--   本 RPC を1本 additive に追加する（新旧併存）。
--
-- 対象フロント（移行先）：
--   - index.html loadAdminData（当日分・from=to=today）
--   - index.html loadStats（対象月・from=月初 / to=月末）
--     ※ showSiteDetail / exportCSV は loadStats の結果（window._statsReports）
--        を参照するため、供給元が本RPCに変わるだけで表示ロジックの改修は原則不要。
--
-- 【重要方針】report_summary は参照しない：
--   実測（2026-07-01 Supabase）で report_summary は
--     FROM reports r JOIN employees e ON e.id = r.employee_id
--     e.name AS employee_name / WHERE 条件なし
--     ORDER BY r.report_date DESC, e.name
--   の通常 View であり、
--     report_summary 行数 = reports JOIN employees 行数 = reports 行数 = 135
--     employee 欠落 reports = 0
--   と 1:1 対応することを確認済み。
--   よって本 RPC は report_summary を参照せず、reports + employees を
--   直接 JOIN して同等の結果を生成する（4-C-4 で View を封鎖しても
--   本 RPC は影響を受けない）。
--
-- 認可方式（4-B list_paid_leave_admin_secure の二経路検証を踏襲・inline）：
--   - 共通ヘルパーは新設せず、inline で検証する。
--   - token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
--   - 経路A：employee_sessions + employees（role='admin' かつ is_active=true）
--   - 経路B：admin_sessions + genka_admins（is_active=true）
--   - どちらも不成立なら RAISE EXCEPTION 'Invalid or expired session'。
--
-- 【EXECUTE 権限の方針（Phase 4-B / 4-C-1 と同一）】
--   - 新規関数は CREATE 時にデフォルト付与される PUBLIC EXECUTE を外す。
--   - anon / authenticated / service_role にのみ EXECUTE を明示 GRANT する。
--
-- このファイルの方針（重要）：
--   - report_summary View は一切触らない（権限・定義とも変更しない）。
--     → View 封鎖・不要 GRANT 整理は Phase 4-C-4 で実施。
--   - reports の権限（anon/authenticated SELECT 等）を変更しない。
--   - reports の policy（reports_all）を変更しない。
--   - genka-app.html の report_summary 参照は触らない（Phase 4-C-3）。
--   - 既存 RPC（reports write 3本・paid_leave・csv 等）は一切変更しない。
--   - フロント移行前の「新旧併存」用。既存の直接 SELECT と新 RPC が
--     同時に成立する状態を作る。
--
-- 実行方法（実行する場合）：
--   Supabase SQL Editor で各セクションを順に実行。
--   「事前確認」→「変更（CREATE / REVOKE / GRANT）」→「事後確認」の順。
--   ※ 実行順：CREATE 1本 → REVOKE PUBLIC 1本 → GRANT 1本。
--
-- 検証パターンの流用元：
--   - 二経路管理者検証：phase4b-paid-leave-read-rpc.sql の list_paid_leave_admin_secure
--   - reports + employees 直接 JOIN での日報生成：csv-export-secure-rpc.sql の
--     export_attendance_details_secure（e.name AS employee_name / 日付範囲 / from>to チェック）
--   - read RPC の枠組み：phase4c-1-my-reports-read-rpc.sql の list_my_reports_secure
-- ============================================================


-- ============================================================
-- 事前確認A〜G（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- A. report_summary View の定義・owner・owner_bypassrls
--    期待：通常 View（relkind='v'）、owner=postgres、owner_bypassrls=true、
--          定義は reports r JOIN employees e ON e.id=r.employee_id /
--          e.name AS employee_name / WHERE なし。
--    ※ 本 RPC は View を参照しないが、実測前提が崩れていないかの確認。
SELECT c.relname                               AS view_name,
       c.relkind                               AS relkind,          -- 'v' を期待
       pg_get_userbyid(c.relowner)             AS owner,            -- postgres を期待
       r.rolbypassrls                          AS owner_bypassrls,  -- true を期待
       c.reloptions                            AS reloptions        -- null を期待
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles     r ON r.oid = c.relowner
WHERE n.nspname = 'public'
  AND c.relname = 'report_summary';

-- A-2. report_summary View 定義本文（reports+employees JOIN の再確認）
SELECT pg_get_viewdef('public.report_summary'::regclass, true) AS view_definition;

-- B. report_summary の列型（RETURNS TABLE の型合わせ根拠）
--    期待：report_date date / employee_id uuid / employee_name text /
--          start_time,end_time time without time zone /
--          normal_mins,overtime_mins integer / site_ids,material_ids uuid[] /
--          material_quantities jsonb / memo text。
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'report_summary'
  AND column_name IN (
        'report_date', 'employee_id', 'employee_name',
        'start_time', 'end_time', 'normal_mins', 'overtime_mins',
        'site_ids', 'material_ids', 'material_quantities', 'memo'
      )
ORDER BY column_name;

-- C. reports の列型（RPC は reports を直接参照するため、こちらが権威）
--    期待：B と同じ型（employee_name を除く。employee_name は employees.name 由来）。
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'reports'
  AND column_name IN (
        'report_date', 'employee_id',
        'start_time', 'end_time', 'normal_mins', 'overtime_mins',
        'site_ids', 'material_ids', 'material_quantities', 'memo'
      )
ORDER BY column_name;

-- D. employees の必要列（JOIN / employee_name / 管理者判定に使用）
--    期待：id uuid / name text / role text / is_active boolean。
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'employees'
  AND column_name IN ('id', 'name', 'role', 'is_active')
ORDER BY column_name;

-- E. セッション検証テーブルの必要列
--    期待：employee_sessions(employee_id,token_hash,expires_at) /
--          admin_sessions(admin_id,token_hash,expires_at) /
--          genka_admins(id,is_active)。
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
        (table_name = 'employee_sessions' AND column_name IN ('employee_id', 'token_hash', 'expires_at'))
     OR (table_name = 'admin_sessions'    AND column_name IN ('admin_id', 'token_hash', 'expires_at'))
     OR (table_name = 'genka_admins'      AND column_name IN ('id', 'is_active'))
      )
ORDER BY table_name, column_name;

-- F. report_summary と reports JOIN employees の行数一致（1:1 対応の担保）
--    期待：view_rows = join_rows = reports_rows、missing_employee_rows = 0。
--    （実測 2026-07-01：135 / 135 / 135 / 0）
SELECT
  (SELECT count(*) FROM public.report_summary)                                   AS view_rows,
  (SELECT count(*) FROM public.reports r
     JOIN public.employees e ON e.id = r.employee_id)                            AS join_rows,
  (SELECT count(*) FROM public.reports)                                          AS reports_rows,
  (SELECT count(*) FROM public.reports r
     LEFT JOIN public.employees e ON e.id = r.employee_id
    WHERE e.id IS NULL)                                                          AS missing_employee_rows;

-- G. list_admin_reports_secure がまだ存在しない、または置換対象かの確認
--    期待：0行（新規）。既に存在する場合は CREATE OR REPLACE で置換される。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_admin_reports_secure'
ORDER BY p.proname;


-- ============================================================
-- 変更（CREATE OR REPLACE FUNCTION × 1 / REVOKE × 1 / GRANT × 1）
--   実行順：CREATE 1本 → REVOKE PUBLIC 1本 → GRANT 1本
-- ============================================================

-- ------------------------------------------------------------
-- 1. list_admin_reports_secure(session_token_input, from_date_input, to_date_input)
--    管理者用。二経路（employee_sessions role=admin / admin_sessions+genka_admins）で
--    セッション検証し、全従業員分の日報を日付範囲で返す。
--    report_summary は参照せず、reports + employees を直接 JOIN する。
--      - loadAdminData: from_date_input = to_date_input = today
--      - loadStats    : from_date_input = 月初, to_date_input = 月末
--    並び順：report_date DESC, e.name（report_summary の ORDER BY と同一）。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_admin_reports_secure(
  session_token_input text,
  from_date_input     date DEFAULT NULL,
  to_date_input       date DEFAULT NULL
)
RETURNS TABLE (
  report_date         date,
  employee_id         uuid,
  employee_name       text,
  start_time          time without time zone,
  end_time            time without time zone,
  normal_mins         integer,
  overtime_mins       integer,
  site_ids            uuid[],
  material_ids        uuid[],
  material_quantities jsonb,
  memo                text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_role     text;
  v_is_admin boolean := false;
BEGIN
  -- 経路A：employee_sessions の管理者
  --   （token 一致 / 未失効 / employees.is_active=true / role='admin'）
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

  -- 経路B：admin_sessions + genka_admins
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

  -- どちらの経路でも管理者と確認できなければ拒否
  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- 日付範囲の防御的チェック（csv RPC と同様）
  IF from_date_input IS NOT NULL AND to_date_input IS NOT NULL
     AND from_date_input > to_date_input THEN
    RAISE EXCEPTION 'from_date は to_date 以前の日付を指定してください';
  END IF;

  -- 全従業員分の日報を日付範囲で返す（report_summary 相当を reports+employees で生成）
  RETURN QUERY
  SELECT r.report_date,
         r.employee_id,
         e.name AS employee_name,
         r.start_time,
         r.end_time,
         r.normal_mins,
         r.overtime_mins,
         r.site_ids,
         r.material_ids,
         r.material_quantities,
         r.memo
  FROM   public.reports r
  JOIN   public.employees e ON e.id = r.employee_id
  WHERE  (from_date_input IS NULL OR r.report_date >= from_date_input)
    AND  (to_date_input   IS NULL OR r.report_date <= to_date_input)
  ORDER  BY r.report_date DESC, e.name;
END;
$$;


-- ------------------------------------------------------------
-- 2. REVOKE PUBLIC EXECUTE → GRANT EXECUTE（最小権限）
--    CREATE FUNCTION 時にデフォルト付与される PUBLIC の EXECUTE を外し、
--    anon / authenticated / service_role にのみ明示的に付与する。
--    （SECURITY DEFINER のため、後フェーズで report_summary / reports の
--      直接 SELECT を REVOKE しても RPC 経由の読み取りは動作継続する）
--    ※ 実行順：CREATE 1本 → REVOKE 1本 → GRANT 1本
-- ------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.list_admin_reports_secure(text, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_admin_reports_secure(text, date, date) TO anon, authenticated, service_role;


-- ============================================================
-- 事後確認H〜L（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- H. 作成された関数 / SECURITY DEFINER / search_path / args
--    期待：list_admin_reports_secure が security_definer=true、
--          config に search_path=public, extensions、
--          args=session_token_input text, from_date_input date, to_date_input date。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       p.proconfig      AS config,           -- {search_path=public, extensions} を期待
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_admin_reports_secure'
ORDER BY p.proname;

-- I. EXECUTE 権限（anon / authenticated / service_role に付与されているか）
--    期待：anon / authenticated / service_role の3行が出る。
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name = 'list_admin_reports_secure'
  AND grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER BY routine_name, grantee;

-- I-2. proacl 直接確認（PUBLIC EXECUTE が外れていることの権威的チェック）
--    期待：proacl に =X/postgres（先頭が空＝PUBLIC）が無い。
--          anon=X/postgres / authenticated=X/postgres / service_role=X/postgres が有る。
SELECT p.proname,
       p.proacl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_admin_reports_secure'
ORDER BY p.proname;

-- J. report_summary が未変更であることの確認（今回触っていない担保）
--    期待：view のまま、anon / authenticated の SELECT も従来どおり残存
--          （REVOKE / View 封鎖は 4-C-4 で実施）。
SELECT table_name AS view_name,
       grantee,
       privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'report_summary'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND privilege_type = 'SELECT'
ORDER BY grantee;

-- K. reports の権限が未変更であることの確認
--    期待：Phase 4-C-1 完了後の状態（anon/authenticated の直接 SELECT は
--          REVOKE 済＝出ない。INSERT/UPDATE/DELETE も無い）から変化していないこと。
--    ※ 本ファイルは reports 権限を一切変更しない。
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

-- L. 動作確認の観点（実トークンは本ファイルに書かない）
--    Supabase 上での確認は以下の観点で行う（フロント or SQL Editor）：
--      L-1. 有効な管理者セッショントークンで
--             SELECT * FROM public.list_admin_reports_secure(:token, :from, :to);
--           を実行し、report_summary を同一範囲で SELECT した結果と
--           件数・内容（report_date/employee_id/employee_name/各列）が一致すること。
--      L-2. from=to=today（loadAdminData 相当）で当日分のみ返ること。
--      L-3. 非管理者（従業員）トークン / 無効・期限切れトークンで
--             'Invalid or expired session' が返る（行が返らない）こと。
--      L-4. from > to を渡すと 'from_date は to_date 以前…' の例外になること。
--    ※ 実トークンは SQL ファイルに記載しない。


-- ============================================================
-- このSQLで「行わない」こと（危険SQLチェック）：
--   - DROP TABLE / DROP VIEW なし
--   - DELETE / TRUNCATE なし
--   - データ UPDATE / INSERT なし（関数定義以外の DML なし）
--   - report_summary の権限変更・定義変更・封鎖なし（→ Phase 4-C-4）
--   - reports の SELECT 権限変更なし
--   - policy（reports_all 等）の変更・削除なし
--   - 既存 RPC（reports write / paid_leave / csv 等）の変更なし
--   - genka-app.html 側 report_summary 参照は対象外（→ Phase 4-C-3）
--   本ファイルの変更は「関数1本の CREATE OR REPLACE ＋ その EXECUTE 権限の
--   REVOKE PUBLIC / GRANT」のみ（additive）。
-- ============================================================
