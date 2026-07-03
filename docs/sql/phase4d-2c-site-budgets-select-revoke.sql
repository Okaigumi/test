-- ============================================================
-- Phase 4-D-2c：site_budgets（現場予算）SELECT REVOKE
-- ============================================================
-- 【実行ステータス】★実行済み★
--   - 実行日：2026-07-04（Supabase SQL Editor 手動実行）。Claude Code CLI からの
--     DB 接続・Supabase CLI 使用はしていない。
--   - 実行SQL：
--       REVOKE SELECT ON TABLE public.site_budgets FROM anon, authenticated; … Success. No rows returned
--   - 事前確認A〜E：すべて合格
--       A site_budgets：anon/authenticated に SELECT 残存（REVOKE前）・INSERT/UPDATE/DELETE なし。
--         ★PUBLIC に SELECT なし → PUBLIC 向け REVOKE は未実行★
--       B read RPC 2本（list_site_budgets_secure / get_site_budget_secure）：
--         prosecdef=true・proconfig=[search_path=public, extensions]
--       C read RPC 2本 EXECUTE：anon/authenticated/service_role（6行）・PUBLIC なし
--       D write RPC 4本（upsert/update/deactivate/restore_site_budget_secure）：
--         prosecdef=true・proconfig=[search_path=public, extensions]
--       E RLS 有効（relrowsecurity=true / relforcerowsecurity=false）。
--         policy＝anon_can_update_site_budgets / sb_read / sb_update / sb_write（把握のみ・変更なし）
--   - 事後確認F〜J：すべて合格
--       F site_budgets の anon/authenticated SELECT：消滅（PUBLIC も無し・想定外DMLなし）
--       G read RPC 2本 EXECUTE：anon/authenticated/service_role 維持（6行）・PUBLIC なし
--       H read RPC 2本：prosecdef=true・search_path=public, extensions 維持
--       I write RPC 4本：不変で存在（prosecdef=true）
--       J RLS 有効のまま・policy 4本 不変
--   - PUBLIC REVOKE 未実行（事前A で PUBLIC SELECT 検出なし）。ロールバック GRANT 未実行。
--   - 本番 Network 確認（REVOKE 後）OK：
--       admin：予算 active/inactive 一覧・編集モーダルで list_site_budgets_secure /
--              get_site_budget_secure が出る。site_budgets?select= なし・赤エラーなし・401/403 なし。
--       genka：原価サマリ・予算モーダルで list_site_budgets_secure が出る。同上。
--       ※ genka 予算モーダルの表示位置が低い件は RPC/REVOKE とは別の UI 改善候補として切り離し。
--
--   【この段の状態】
--   - site_budgets の anon/authenticated direct SELECT は遮断完了。読み取りは read RPC 経由に一本化。
--   - RLS / policy は未変更（policy 整理は別工程候補）。
--   - 記録先：docs/db-migrations.md「2026-07-04 Phase 4-D-2c site_budgets SELECT REVOKE（実行済み）」/
--     docs/roadmap.md Phase 4-D-2 セクション参照。これにより Phase 4-D-2（site_budgets 読み取り保護）完了。
--
-- 【前提（すべて完了済み）】
--   - 4-D-2a：read RPC 2本追加済み（list_site_budgets_secure /
--     get_site_budget_secure・SECURITY DEFINER・search_path=public, extensions・
--     EXECUTE=anon,authenticated,service_role・PUBLIC なし）。PR #44 merge・DB実行済み。
--   - 4-D-2b：フロント移行済み（admin-app.html / genka-app.html の
--     site_budgets direct SELECT 5箇所を read RPC へ置換）。PR #46 merge（merge commit 600ade3）。
--   - ★4-D-2b 本番 Network 確認 OK★：
--       admin：予算 active/inactive 一覧・編集モーダルで
--              list_site_budgets_secure / get_site_budget_secure が呼ばれる（200）。
--       genka：原価サマリ・予算モーダルで list_site_budgets_secure が呼ばれる（200）。
--       共通：site_budgets?select=... は出ない。Console 赤エラーなし・401/403 なし。
--   → Phase 4-C-1 の教訓（フロント本番反映前に REVOKE しない）を満たしており、
--     REVOKE 実施の前提が整っている。
--
-- 【このファイルの方針（重要）】
--   - anon / authenticated の direct SELECT を REVOKE して読み取りを
--     secure read RPC 経由に一本化する（新旧併存の解消）。
--   - ★PUBLIC への SELECT REVOKE は原則行わない（コメントアウトのまま）。★
--       事前確認A で PUBLIC に SELECT が検出された場合は、
--       ここで自動的に PUBLIC REVOKE へ進めてはならない。
--       → いったん停止し、PUBLIC SELECT が存在する事実を報告・確認する。
--       → 明示承認が得られた場合に限り、末尾の PUBLIC REVOKE 行を有効化して実行する。
--   - service_role / postgres(owner) は触らない。
--   - read RPC / write RPC の EXECUTE は維持する（変更しない）。
--   - 既存 RLS 有効状態・既存 policy は今回変更しない（把握のみ）。
--     ※ SELECT privilege を REVOKE すると privilege は RLS より手前の関門のため、
--       read 系 policy が残っても direct SELECT は失敗する（policy は inert 化）。
--       policy の整理は別工程候補として残す。
--
-- 【このファイルに含めない（意図的・禁止）】
--   - DROP POLICY / CREATE|ALTER POLICY
--   - ALTER TABLE / DROP TABLE
--   - DELETE / TRUNCATE / INSERT / UPDATE（DML）
--   - site_budgets 以外のテーブルへの変更
--   - REVOKE EXECUTE（read/write RPC の EXECUTE は維持）
--   - docs 更新 / commit / push（本工程では行わない）
-- ============================================================


-- ============================================================
-- 事前確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- A. site_budgets の anon / authenticated / PUBLIC 権限
--    期待：SELECT が anon / authenticated に残存（REVOKE 前）。
--          INSERT / UPDATE / DELETE は無い想定（write は RPC 経由）。
--    ★PUBLIC に SELECT があるかを必ず確認する。★
--      検出された場合は、このファイルの PUBLIC REVOKE へ進めず、
--      いったん停止して「PUBLIC に SELECT あり」を報告・確認すること。
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name = 'site_budgets'
  AND  grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND  privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
GROUP  BY table_name, grantee
ORDER  BY table_name, grantee;

-- B. read RPC 2本の存在・SECURITY DEFINER・search_path
--    期待：2本とも security_definer=true / search_path=public, extensions。
SELECT p.proname,
       p.prosecdef,
       p.proconfig,
       pg_get_function_identity_arguments(p.oid) AS args
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_site_budgets_secure', 'get_site_budget_secure')
ORDER  BY p.proname;

-- C. read RPC 2本の EXECUTE 権限
--    期待：anon / authenticated / service_role に EXECUTE。PUBLIC は無し。
SELECT routine_name,
       grantee,
       privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name IN ('list_site_budgets_secure', 'get_site_budget_secure')
  AND  grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER  BY routine_name, grantee;

-- D. write RPC 4本の存在（壊さない基準）
--    期待：4本とも security_definer=true で存在。
SELECT p.proname,
       p.prosecdef,
       pg_get_function_identity_arguments(p.oid) AS args
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('upsert_site_budget_secure',
                     'update_site_budget_secure',
                     'deactivate_site_budget_secure',
                     'restore_site_budget_secure')
ORDER  BY p.proname;

-- E. 現状の RLS 状態・policy 一覧（今回は変更しない・把握のみ）
--    期待：RLS 有効（relrowsecurity=true）。policy は現状のまま（変更しない）。
SELECT relname AS table_name,
       relrowsecurity      AS rls_enabled,
       relforcerowsecurity AS rls_forced
FROM   pg_class
WHERE  relnamespace = 'public'::regnamespace
  AND  relname = 'site_budgets';

SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename = 'site_budgets'
ORDER  BY tablename, cmd, policyname;


-- ============================================================
-- 変更（REVOKE SELECT）
--   ※ ここで初めて DB 状態を変更する。事前確認 OK 後に実行。
-- ============================================================

-- 直接 SELECT の遮断（anon / authenticated）。読み取りは read RPC 経由に一本化。
REVOKE SELECT ON TABLE public.site_budgets FROM anon, authenticated;

-- ※ PUBLIC への REVOKE は原則行わない（既定＝下行はコメントアウトのまま）。
--    事前確認A で PUBLIC に SELECT が検出された場合は、ここで自動実行せず
--    いったん停止・報告し、明示承認が得られたときに限り下行を有効化して実行する。
-- REVOKE SELECT ON TABLE public.site_budgets FROM PUBLIC;


-- ============================================================
-- 事後確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- F. anon / authenticated の SELECT が消えたか
--    期待：site_budgets の anon / authenticated の SELECT 行が出ない。
--          （PUBLIC REVOKE を実行していなければ PUBLIC 行の有無は事前確認A と一致）
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name = 'site_budgets'
  AND  grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND  privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
GROUP  BY table_name, grantee
ORDER  BY table_name, grantee;

-- G. read RPC 2本の EXECUTE 権限が維持されているか
--    期待：anon / authenticated / service_role に EXECUTE 残存。PUBLIC は無し。
SELECT routine_name,
       grantee,
       privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name IN ('list_site_budgets_secure', 'get_site_budget_secure')
  AND  grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER  BY routine_name, grantee;

-- H. read RPC 2本の SECURITY DEFINER / search_path が維持されているか
--    期待：2本とも security_definer=true / search_path=public, extensions。
SELECT p.proname,
       p.prosecdef,
       p.proconfig
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_site_budgets_secure', 'get_site_budget_secure')
ORDER  BY p.proname;

-- I. write RPC 4本が不変で存在しているか（壊していない）
--    期待：4本とも引き続き security_definer=true で存在。
SELECT p.proname,
       p.prosecdef
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('upsert_site_budget_secure',
                     'update_site_budget_secure',
                     'deactivate_site_budget_secure',
                     'restore_site_budget_secure')
ORDER  BY p.proname;

-- J. RLS / policy が不変であること（今回変更していない）
--    期待：RLS 有効のまま。policy 一覧は事前確認E と同じ。
SELECT relname AS table_name,
       relrowsecurity AS rls_enabled
FROM   pg_class
WHERE  relnamespace = 'public'::regnamespace
  AND  relname = 'site_budgets';

SELECT tablename, policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename = 'site_budgets'
ORDER  BY tablename, cmd, policyname;


-- ============================================================
-- ロールバック（必要時のみ・一時復旧用）
--   ※ 通常は実行しない。REVOKE 後に想定外の direct SELECT 依存が本番で発覚し、
--     予算が空表示・401 になった等の緊急時にのみ使用する。
--   ※ Phase 4-C-1 / 4-D-1c で実績のある復旧手順（REVOKE→復旧→原因対処→再REVOKE）。
--     復旧後は原因（未移行の direct read 残存など）を特定・修正し、再度 4-D-2c を実施する。
-- ============================================================
-- GRANT SELECT ON TABLE public.site_budgets TO anon, authenticated;


-- ============================================================
-- 本番確認項目（REVOKE 実行後・ブラウザ / Network）
-- ============================================================
--   admin：
--     - 予算ページ「通常一覧（active）」「取り消し済み（inactive）」で
--       list_site_budgets_secure が 200・従来どおり表示。
--     - 予算編集モーダルで get_site_budget_secure が 200・フォーム充填 OK。
--     - 予算の追加/編集/取消/復元（upsert / update / deactivate / restore_site_budget_secure）が OK。
--   genka：
--     - 原価サマリ（loadData）で list_site_budgets_secure が 200・予算列が従来値どおり。
--     - 現場の予算モーダルで list_site_budgets_secure が 200・年間予算/メモ表示 OK。
--   共通：
--     - site_budgets?select=... が 401 / 出ないこと（direct SELECT 遮断）。
--     - Console 赤エラーなし（favicon 404 等の無関係ノイズを除く）。
--     - npm run test:smoke = 4 passed（ログイン画面・csv-viewer 回帰なし）。


-- ============================================================
-- 触らないもの（この工程の非対象）
-- ============================================================
--   - read RPC（list_site_budgets_secure / get_site_budget_secure）の EXECUTE（維持）
--   - write RPC 4本（upsert / update / deactivate / restore_site_budget_secure）の EXECUTE（維持）
--   - service_role / postgres(owner) の権限（維持）
--   - RLS 有効状態・既存 policy（変更しない。整理は別工程候補）
--   - helper _verify_management_session（非公開のまま・不変前提）
--   - site_budgets 以外のテーブル
--
-- 次工程（本ファイル実行後）：
--   - docs/db-migrations.md /（roadmap.md）へ「Phase 4-D-2c 実行済み」を記録。
--   - これにより Phase 4-D-2（現場予算 site_budgets 読み取り保護）完了。
--   - 以降は 4-D-3 請求書（invoices）など残りの financial 系読み取り保護。
-- ============================================================
