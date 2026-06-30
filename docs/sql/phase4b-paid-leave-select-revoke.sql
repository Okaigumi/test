-- ============================================================
-- Phase 4-B：paid_leave SELECT REVOKE / read policy 整理
-- ============================================================
-- 【実行ステータス】★実行済み★
--   - 実行日：2026-06-30
--   - Supabase SQL Editor 実行結果：Success. No rows returned
--   - direct SELECT 遮断完了（paid_leave_requests / paid_leave_grants の
--     anon/authenticated SELECT を REVOKE）。
--   - plr_read / plg_read policy 削除完了。
--   - write 系 policy（plr_write/plr_update/plg_write/plg_update）は今回残存。
--   - 新 read RPC（list_my_paid_leave_secure / list_paid_leave_admin_secure）
--     経由で本番画面（index 本人/管理・admin-app 管理）動作確認 OK、エラーなし。
--   - 事前確認A〜E／事後確認F〜I いずれも期待どおりで完了。
--
--   【まだ未実施】
--   - docs（db-migrations.md / roadmap.md 等）への記録：未実施
--   - git add / commit / push：未実施
--
--   - 前提（完了済み）：
--       * read RPC 2本追加済み（list_my_paid_leave_secure /
--         list_paid_leave_admin_secure）
--       * index.html（本人/管理）・admin-app.html（管理）のフロント移行済み
--       * PR #21 merge 済み、本番画面確認 OK（エラーなし）
--
-- 対象テーブル：
--   - public.paid_leave_requests
--   - public.paid_leave_grants
--
-- 目的：
--   - anon / authenticated からの直接 SELECT を REVOKE して遮断する。
--   - public true の read policy（plr_read / plg_read）を削除する。
--   - 読み取りは secure RPC（SECURITY DEFINER）経由に統一する。
--   - 既存 write RPC（create_/review_/save_）は壊さない。
--   - 新 read RPC 経由の読み取りは維持する（RPC は definer 実行のため
--     直接 SELECT を閉じても動作継続）。
--
-- 実行方法：
--   Supabase SQL Editor で
--     「事前確認」→「変更（REVOKE/DROP POLICY）」→「事後確認」
--   の順に実行。事前確認・事後確認は必須。
--
-- 注意（重要）：
--   - DROP TABLE / DELETE / TRUNCATE / データ UPDATE は行わない。
--   - paid_leave 以外のテーブルは触らない。
--   - write 系 policy（plr_write/plr_update/plg_write/plg_update 等）は
--     今回は削除しない（現状確認のみ）。理由は末尾コメント参照。
-- ============================================================


-- ============================================================
-- 事前確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- A. paid_leave 2テーブルの anon/authenticated/PUBLIC 権限
--    期待：この時点では SELECT がまだ残っている（REVOKE 前のため）。
--          INSERT/UPDATE/DELETE は既に REVOKE 済みのはず。
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

-- B. paid_leave 2テーブルの既存 policy 一覧
--    期待：plr_read / plg_read（read用）が存在。
--          write/update 系 policy も現状確認する（今回は削除しない）。
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

-- B-2. write 系 policy の残存を明示確認（今回は削除しない＝残すべきもの）
--      期待：plr_write / plr_update / plg_write / plg_update 等が残存。
SELECT tablename,
       policyname,
       cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('paid_leave_requests', 'paid_leave_grants')
  AND policyname IN ('plr_write', 'plr_update', 'plg_write', 'plg_update')
ORDER BY tablename, policyname;

-- C. 新 read RPC 2本の存在確認
--    期待：list_my_paid_leave_secure / list_paid_leave_admin_secure が
--          security_definer=true、search_path=public, extensions。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       p.proconfig      AS config,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('list_my_paid_leave_secure', 'list_paid_leave_admin_secure')
ORDER BY p.proname;

-- D. 新 read RPC 2本の EXECUTE 権限確認
--    期待：anon / authenticated / service_role に EXECUTE。PUBLIC は無し。
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name IN ('list_my_paid_leave_secure', 'list_paid_leave_admin_secure')
  AND grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER BY routine_name, grantee;

-- E. 既存 write RPC 3本の存在確認（壊していない基準）
--    期待：3本とも security_definer=true で存在。
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
-- 変更（REVOKE SELECT × 2 / DROP POLICY × 2）
--   ※ ここで初めて DB 状態を変更する。事前確認 OK 後に実行。
-- ============================================================

-- 1. 直接 SELECT の遮断（anon / authenticated）
REVOKE SELECT ON public.paid_leave_requests FROM anon, authenticated;
REVOKE SELECT ON public.paid_leave_grants   FROM anon, authenticated;

-- 2. public true の read policy 削除（read は secure RPC へ統一）
DROP POLICY IF EXISTS plr_read ON public.paid_leave_requests;
DROP POLICY IF EXISTS plg_read ON public.paid_leave_grants;


-- ============================================================
-- 事後確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- F. anon / authenticated の SELECT が消えたか
--    期待：paid_leave_requests / paid_leave_grants について、
--          anon / authenticated の SELECT 行が出ない。
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

-- G. plr_read / plg_read が消えたか／write 系 policy が残っているか
--    期待：plr_read / plg_read は出ない。
--          write/update 系 policy は残存（今回は削除しない方針）。
SELECT tablename,
       policyname,
       cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('paid_leave_requests', 'paid_leave_grants')
ORDER BY tablename, cmd, policyname;

-- H. 新 read RPC 2本の EXECUTE 権限が維持されているか
--    期待：anon / authenticated / service_role の EXECUTE が残存。
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name IN ('list_my_paid_leave_secure', 'list_paid_leave_admin_secure')
  AND grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER BY routine_name, grantee;

-- I. 既存 write RPC 3本が残っているか
--    期待：3本とも引き続き security_definer=true で存在。
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
-- 補足（今回の方針メモ）
-- ============================================================
--   - write 系 policy（plr_write / plr_update / plg_write / plg_update 等）は
--     今回は削除しない。
--     理由：INSERT/UPDATE 権限は既に anon/authenticated から REVOKE 済みで
--           policy 単体の実効性が低く、今回は「read 遮断」を主目的とするため。
--           誤って write 経路を壊すリスクを避ける。
--   - write 系 policy の整理（削除/集約）は別工程候補として残す。
--     実施時は write RPC（SECURITY DEFINER）経由の書き込みに影響しないことを
--     事前確認した上で行うこと。
--
-- このファイルに「含めていない」もの（意図的）：
--   - DROP TABLE / DELETE / TRUNCATE / データ UPDATE：禁止
--   - paid_leave 以外のテーブルへの変更：対象外
--   - docs/db-migrations.md / docs/roadmap.md の更新：本工程では行わない
-- ============================================================
