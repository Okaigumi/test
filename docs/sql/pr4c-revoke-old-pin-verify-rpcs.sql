-- ============================================================
-- PR-4C-1: 旧PIN照合RPCの外部実行権限を剥奪（REVOKE EXECUTE）
--   対象: public.verify_employee_pin(uuid, text)
--         public.verify_admin_pin(uuid, text)
--   目的: PUBLIC / anon / authenticated からの EXECUTE を剥奪し、
--         平文PIN照合（pin = pin_input）に使える外部実行経路を遮断する。
-- ============================================================
-- 【背景】
--   - 旧RPC2本は SECURITY DEFINER で、PUBLIC / anon / authenticated に
--     EXECUTE 権限がある（PR-4A introspection で確認）。
--   - 両関数は pin_input を受け取り pin = pin_input の平文照合を行い、
--     成功時にユーザー情報を返す（session_token は返さない）。
--     → anon から PIN 総当たり／在籍・PIN一致判定に悪用可能な状態。
--   - 現行ログイン導線は create_*_session に統一済みで、フロントからの
--     verify_*_pin 呼び出しはゼロ件（index/admin/genka の3ファイルとも）。
--       index.html      : create_employee_session (L909)
--       admin-app.html   : create_admin_session   (L306)
--       genka-app.html   : create_admin_session   (L504)
--
-- 【このファイルの方針（重要）】
--   - REVOKE EXECUTE のみ。可逆（必要なら再GRANTで復旧可能）。
--   - DROP FUNCTION はしない（別PRで、ログイン3導線の動作確認後に検討）。
--   - 関数定義・引数・戻り値・SECURITY DEFINER・RLS / policy は一切変更しない。
--   - GRANT / ALTER / CREATE / DROP はしない。
--   - 関数オーナー（postgres）の EXECUTE は REVOKE 対象外（従来どおり保持）。
--   - service_role は明示 GRANT していないため対象に含めない
--     （フロント／業務コードは service_role で本RPCを呼んでいない）。
--
-- 【実行ステータス】☆未実行（ユーザーが Supabase SQL Editor で手動実行）☆
--   - Claude からの DB 実行・DB接続・Supabase CLI / psql 使用は一切なし。
--   - 実行後の結果は別途 docs/db-migrations.md に記録予定（本PRでは記録しない）。
-- ============================================================


-- ------------------------------------------------------------
-- (A) 実行前確認
--     旧RPC2本の存在・SECURITY DEFINER・オーナー・現行EXECUTE権限を確認する。
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

-- A-2) 現行 EXECUTE 権限（PUBLIC / anon / authenticated が並ぶ想定）
SELECT g.routine_name, g.grantee, g.privilege_type
FROM information_schema.routine_privileges g
WHERE g.routine_schema = 'public'
  AND g.routine_name IN ('verify_employee_pin','verify_admin_pin')
ORDER BY g.routine_name, g.grantee;
-- 期待値: PUBLIC / anon / authenticated に EXECUTE がある状態（REVOKE前）。


-- ------------------------------------------------------------
-- (B) REVOKE 本体
--     PUBLIC / anon / authenticated から EXECUTE を剥奪する。
--     ※ PUBLIC を剥がさないと anon/authenticated を剥がしても実行可能なため必須。
-- ------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.verify_employee_pin(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.verify_employee_pin(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.verify_employee_pin(uuid, text) FROM authenticated;

REVOKE EXECUTE ON FUNCTION public.verify_admin_pin(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.verify_admin_pin(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.verify_admin_pin(uuid, text) FROM authenticated;


-- ------------------------------------------------------------
-- (C) 実行後確認
--     PUBLIC / anon / authenticated の EXECUTE が消えたことを確認する。
-- ------------------------------------------------------------

-- C-1) has_function_privilege による実行可否（全て false になる想定）
SELECT p.oid::regprocedure AS func,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('public',         p.oid, 'EXECUTE') AS public_exec
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('verify_employee_pin','verify_admin_pin')
ORDER BY func;
-- 期待値: anon_exec / auth_exec / public_exec がすべて false（2行とも）。

-- C-2) routine_privileges 残存確認（PUBLIC/anon/authenticated の行が消える想定）
SELECT g.routine_name, g.grantee, g.privilege_type
FROM information_schema.routine_privileges g
WHERE g.routine_schema = 'public'
  AND g.routine_name IN ('verify_employee_pin','verify_admin_pin')
ORDER BY g.routine_name, g.grantee;
-- 期待値: PUBLIC / anon / authenticated の EXECUTE 行が無くなる
--         （オーナー postgres 等の行のみ残る、または0行）。

-- ------------------------------------------------------------
-- 【DB実行後の動作確認（アプリ側・手動）】
--   REVOKE 後、以下3導線で通常ログインが成功することを確認する。
--   （いずれも create_*_session 経由のため影響が無い想定）
--     - index.html      … 従業員ログイン
--     - admin-app.html   … 管理者ログイン
--     - genka-app.html   … 原価管理ログイン
-- ------------------------------------------------------------
