-- ============================================================
-- PR-4C-2: 旧PIN照合RPC2本の DROP FUNCTION
--   対象: public.verify_employee_pin(uuid, text)
--         public.verify_admin_pin(uuid, text)
--   目的: PR-4C-1 で外部 EXECUTE を REVOKE 済みの旧RPC2本を、
--         DBから完全に撤去する（平文PIN照合ロジックの残存を無くす）。
-- ============================================================
-- 【背景】
--   - 旧RPC2本は SECURITY DEFINER で pin = pin_input の平文照合を行う関数。
--   - PR-4C-1 で PUBLIC / anon / authenticated の EXECUTE は REVOKE 済み
--     （has_function_privilege 全 false / routine_privileges 対象3ロール 0 rows 確認済み）。
--   - 現行ログイン導線は create_*_session に統一済みで、フロントからの
--     verify_*_pin 呼び出しはゼロ件（index/admin/genka の3ファイルとも）。
--       index.html      : create_employee_session (L909)
--       admin-app.html   : create_admin_session   (L306)
--       genka-app.html   : create_admin_session   (L504)
--   - 関数本体（平文PIN照合）と旧RPC定義自体はまだDBに残存しているため撤去する。
--
-- 【このファイルの方針（重要）】
--   - DROP FUNCTION のみ。CASCADE は絶対に使わない（RESTRICT を明示）。
--   - 依存オブジェクト（ビュー/トリガ/他関数等）が1件でもあれば DROP せず停止し報告する。
--     （A-2 の依存確認が 0 rows のときのみ B を実行する）
--   - GRANT / ALTER / CREATE / REVOKE / RLS / policy / RPC定義変更はしない。
--   - HTML / JS / 認証 / PIN処理は変更しない。
--   - 不可逆操作のため、再作成が必要な場合は docs/db-migrations.md の
--     「2026-05-28 RLS security hardening / RPC login」節の CREATE 定義
--     （verify_employee_pin / verify_admin_pin）を参照して復元する。
--     ※ 復元時に anon/authenticated へ再 GRANT しないこと（平文PIN照合RPCを再び外部公開しないため）。
--
-- 【実行ステータス】☆未実行☆
--   - DB実行はユーザーが Supabase SQL Editor で手動実行する。
--   - Claude からの DB 接続・SQL 実行・Supabase CLI / psql 使用は一切しない。
--   - 実行順序: (A) 実行前確認 → A-2 が 0 rows を確認 → (B) DROP → (C) 実行後確認。
--   - 実行後、本番3導線（/ 従業員・/admin 管理者・/genka 原価）のログインが
--     正常であること（create_*_session 利用のため影響しない想定）を目視確認する。
--   - 実行記録は後続PRで docs/db-migrations.md に追記する（このファイルでは追記しない）。
-- ============================================================


-- ------------------------------------------------------------
-- (A) 実行前確認
--     旧RPC2本の存在・属性・依存・現行EXECUTE権限を確認する。
-- ------------------------------------------------------------

-- A-1) 存在と属性（2行返る想定：employee / admin 各1）
SELECT n.nspname AS schema,
       p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS args,
       p.prosecdef AS security_definer,
       r.rolname  AS owner
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_roles r     ON r.oid = p.proowner
WHERE n.nspname = 'public'
  AND p.proname IN ('verify_employee_pin','verify_admin_pin')
ORDER BY p.proname;
-- 期待値: 2行。security_definer = true。args = 'employee_id_input uuid, pin_input text'
--         / 'admin_id_input uuid, pin_input text'。
--         ※ 0行なら既に存在しない → DROP不要（B はスキップ）。

-- A-2) DB内の依存確認（他オブジェクトから旧RPC2本を参照していないこと）
--      ★ここが 0 rows のときのみ (B) を実行する。1行でも出たら DROP せず停止・報告。
SELECT d.classid::regclass AS dependent_catalog,
       d.objid,
       pg_describe_object(d.classid, d.objid, d.objsubid) AS dependent_object,
       d.deptype
FROM pg_depend d
JOIN pg_proc p      ON p.oid = d.refobjid
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('verify_employee_pin','verify_admin_pin')
  AND d.deptype <> 'i';   -- internal（型・言語等の内部依存）は除外
-- 期待値: 0 rows（＝旧RPC2本を参照する他オブジェクト無し → DROP 安全）。
--         行が出た場合は DROP せず、dependent_object の内容を報告してから再設計する。

-- A-3) 現行 EXECUTE 権限（PR-4C-1 の再確認。3ロールとも false の想定）
SELECT p.oid::regprocedure AS func,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('public',        p.oid, 'EXECUTE') AS public_exec
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('verify_employee_pin','verify_admin_pin')
ORDER BY func;
-- 期待値: anon_exec / auth_exec / public_exec がすべて false（2行とも）。


-- ------------------------------------------------------------
-- (B) DROP 本体
--     ★ A-2 の依存確認が 0 rows であることを確認してから実行する。
--     CASCADE は絶対に使わない。RESTRICT を明示し、
--     万一依存が残っていた場合はエラーで停止させる（巻き込み削除しない）。
-- ------------------------------------------------------------

DROP FUNCTION IF EXISTS public.verify_employee_pin(uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS public.verify_admin_pin(uuid, text)   RESTRICT;


-- ------------------------------------------------------------
-- (C) 実行後確認
--     旧RPC2本が pg_proc から消滅したことを確認する。
-- ------------------------------------------------------------

SELECT n.nspname AS schema,
       p.proname AS function_name
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('verify_employee_pin','verify_admin_pin')
ORDER BY p.proname;
-- 期待値: 0 rows（verify_employee_pin / verify_admin_pin とも消滅）。


-- ------------------------------------------------------------
-- 【DB実行後の動作確認（アプリ側・手動）】
--   DROP 後、以下3導線で通常ログインが成功することを確認する。
--   （いずれも create_*_session 経由のため影響が無い想定）
--     - index.html      … 従業員ログイン        （/）
--     - admin-app.html   … 管理者ログイン        （/admin）
--     - genka-app.html   … 原価管理ログイン      （/genka）
--   問題が無ければ、後続PRで docs/db-migrations.md に PR-4C-2 の実行記録を追記する。
-- ------------------------------------------------------------
