-- ============================================================
-- Phase 4-D-3c：invoices（請求書）SELECT REVOKE
-- ============================================================
-- 【実行ステータス】☆未実行☆
--   - このSQLはまだ実行しない（SQLファイル作成のみ）。
--   - Supabase SQL Editor での手動実行は未実施。実行後にこの行を
--     ★実行済み★ に更新し、実行日・事前A〜E/事後F〜J・本番確認結果を追記する。
--
-- 【目的】
--   - invoices の anon / authenticated 直接 SELECT を遮断し、読み取りを
--     以下2本の read RPC 経由に限定する（新旧併存の解消）。
--       list_invoices_secure
--       get_invoice_secure
--   - Phase 4-D-3（請求書 invoices 読み取り保護）の最終段。これにより 4-D-3 完了。
--
-- 【前提（すべて完了済み）】
--   - 4-D-3a：read RPC 2本追加済み（list_invoices_secure / get_invoice_secure・
--     SECURITY DEFINER・search_path=public, extensions・
--     EXECUTE=anon,authenticated,service_role・PUBLIC なし）。PR #49 merge・DB実行済み。
--   - 4-D-3b：フロント移行済み（admin-app.html / genka-app.html の
--     invoices direct SELECT 6箇所を read RPC へ置換）。PR #51 merge（merge commit 4603726）。
--   - ★4-D-3b 本番 Network 確認 OK★：
--       admin：通常一覧・取消済み一覧で list_invoices_secure、編集モーダルで
--              get_invoice_secure が呼ばれる（200）。
--       genka：月次請求書リスト・原価サマリ集計で list_invoices_secure、
--              編集モーダルで get_invoice_secure が呼ばれる（200）。
--       共通：invoices?select=... は出ない。Console 赤エラーなし・401/403 なし・HTTP 400 なし。
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
-- 【非対象（この工程で触らないもの・意図的）】
--   - read RPC 定義変更なし（list_invoices_secure / get_invoice_secure・EXECUTE 維持）
--   - write RPC 変更なし（create_invoice_secure / update_invoice_secure /
--     reject_invoice_secure / restore_invoice_secure・認可方式も変更しない）
--   - RLS 変更なし
--   - policy 変更なし
--   - helper 変更なし（_verify_management_session は非公開のまま不変）
--   - service_role / postgres(owner) 変更なし
--   - HTML 変更なし
--   - docs/db-migrations.md / docs/roadmap.md 更新なし（本ファイルでは行わない）
--   - Supabase CLI 不使用
--
-- 【このファイルに含めない（意図的・禁止）】
--   - DROP POLICY / CREATE|ALTER POLICY
--   - ALTER TABLE / DROP TABLE
--   - DELETE / TRUNCATE / INSERT / UPDATE（DML）
--   - invoices 以外のテーブルへの変更
--   - REVOKE EXECUTE（read/write RPC の EXECUTE は維持）
--   - docs 更新 / commit / push（本工程では行わない）
-- ============================================================


-- ============================================================
-- 事前確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- A. invoices の anon / authenticated / PUBLIC 権限
--    期待：SELECT が anon / authenticated に残存（REVOKE 前）。
--          INSERT / UPDATE / DELETE は無い想定（write は RPC 経由）。
--    ★PUBLIC に SELECT があるかを必ず確認する。★
--      PUBLIC は大小文字差を避けるため lower(grantee) で判定する。
--      検出された場合は、このファイルの PUBLIC REVOKE へ進めず、
--      いったん停止して「PUBLIC に SELECT あり」を報告・確認すること。
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name = 'invoices'
  AND  lower(grantee) IN ('anon', 'authenticated', 'public')
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
  AND  p.proname IN ('list_invoices_secure', 'get_invoice_secure')
ORDER  BY p.proname;

-- C. read RPC 2本の EXECUTE 権限
--    期待：anon / authenticated / service_role に EXECUTE（2関数×3ロール=6行）。PUBLIC は無し。
SELECT routine_name,
       grantee,
       privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name IN ('list_invoices_secure', 'get_invoice_secure')
  AND  lower(grantee) IN ('anon', 'authenticated', 'service_role', 'public')
ORDER  BY routine_name, grantee;

-- D. write RPC 4本の存在（壊さない基準）
--    期待：4本とも security_definer=true / search_path=public, extensions で存在。
--    ★既存 write RPC の認可方式（admin_sessions 単経路）は変更しない。★
SELECT p.proname,
       p.prosecdef,
       p.proconfig,
       pg_get_function_identity_arguments(p.oid) AS args
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('create_invoice_secure',
                     'update_invoice_secure',
                     'reject_invoice_secure',
                     'restore_invoice_secure')
ORDER  BY p.proname;

-- E. 現状の RLS 状態・policy 一覧（今回は変更しない・把握のみ）
--    期待：RLS 有効（relrowsecurity=true）。policy は現状のまま（変更しない）。
SELECT relname AS table_name,
       relrowsecurity      AS rls_enabled,
       relforcerowsecurity AS rls_forced
FROM   pg_class
WHERE  relnamespace = 'public'::regnamespace
  AND  relname = 'invoices';

SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename = 'invoices'
ORDER  BY tablename, cmd, policyname;


-- ============================================================
-- 変更（REVOKE SELECT）
--   ※ ここで初めて DB 状態を変更する。事前確認 OK 後に実行。
-- ============================================================

-- 直接 SELECT の遮断（anon / authenticated）。読み取りは read RPC 経由に一本化。
REVOKE SELECT ON TABLE public.invoices FROM anon, authenticated;

-- ※ PUBLIC への REVOKE は原則行わない（既定＝下行はコメントアウトのまま）。
--    事前確認A で PUBLIC に SELECT が検出された場合は、ここで自動実行せず
--    いったん停止・報告し、明示承認が得られたときに限り下行を有効化して実行する。
-- REVOKE SELECT ON TABLE public.invoices FROM PUBLIC;


-- ============================================================
-- 事後確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- F. anon / authenticated の SELECT が消えたか
--    期待：invoices の anon / authenticated の SELECT 行が出ない。
--          INSERT/UPDATE/DELETE などの想定外DML権限も無い。
--          （PUBLIC REVOKE を実行していなければ PUBLIC 行の有無は事前確認A と一致）
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name = 'invoices'
  AND  lower(grantee) IN ('anon', 'authenticated', 'public')
  AND  privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
GROUP  BY table_name, grantee
ORDER  BY table_name, grantee;

-- G. read RPC 2本の EXECUTE 権限が維持されているか
--    期待：anon / authenticated / service_role に EXECUTE 残存（6行）。PUBLIC は無し。
SELECT routine_name,
       grantee,
       privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name IN ('list_invoices_secure', 'get_invoice_secure')
  AND  lower(grantee) IN ('anon', 'authenticated', 'service_role', 'public')
ORDER  BY routine_name, grantee;

-- H. read RPC 2本の SECURITY DEFINER / search_path が維持されているか
--    期待：2本とも security_definer=true / search_path=public, extensions。
SELECT p.proname,
       p.prosecdef,
       p.proconfig
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_invoices_secure', 'get_invoice_secure')
ORDER  BY p.proname;

-- I. write RPC 4本が不変で存在しているか（壊していない）
--    期待：4本とも引き続き security_definer=true / search_path=public, extensions で存在。
SELECT p.proname,
       p.prosecdef,
       p.proconfig
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('create_invoice_secure',
                     'update_invoice_secure',
                     'reject_invoice_secure',
                     'restore_invoice_secure')
ORDER  BY p.proname;

-- J. RLS / policy が不変であること（今回変更していない）
--    期待：RLS 有効のまま。policy 一覧は事前確認E と同じ。
SELECT relname AS table_name,
       relrowsecurity AS rls_enabled
FROM   pg_class
WHERE  relnamespace = 'public'::regnamespace
  AND  relname = 'invoices';

SELECT tablename, policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename = 'invoices'
ORDER  BY tablename, cmd, policyname;


-- ============================================================
-- ロールバック（必要時のみ・一時復旧用）
--   ※ 通常は実行しない（コメントアウトのまま）。REVOKE 後に想定外の direct SELECT
--     依存が本番で発覚し、請求書が空表示・401/403 になった等の緊急時にのみ使用する。
--   ※ Phase 4-C-1 / 4-D-1c / 4-D-2c で実績のある復旧手順
--     （REVOKE→復旧→原因対処→再REVOKE）。
--     復旧後は原因（未移行の direct read 残存など）を特定・修正し、再度 4-D-3c を実施する。
-- ============================================================
-- GRANT SELECT ON TABLE public.invoices TO anon, authenticated;


-- ============================================================
-- 本番確認項目（REVOKE 実行後・ブラウザ / Network）
-- ============================================================
--   admin：
--     - 通常一覧（active）で list_invoices_secure が 200・従来どおり表示。
--     - 取消済み一覧（rejected）で list_invoices_secure が 200・従来どおり表示。
--     - 請求書編集モーダルで get_invoice_secure が 200・フォーム充填 OK。
--     - 請求書の追加/編集/取消/復元（create / update / reject / restore_invoice_secure）が OK。
--   genka：
--     - 月次請求書リスト（loadInvoices）で list_invoices_secure が 200・従来どおり表示。
--     - 請求書編集モーダル（editInvoice）で get_invoice_secure が 200・フォーム充填 OK。
--     - 原価サマリ集計（loadData）で list_invoices_secure が 200・請求書反映額が従来どおり。
--   共通：
--     - invoices?select=... が 401 / 出ないこと（direct SELECT 遮断）。
--     - Console 赤エラーなし（favicon 404 等の無関係ノイズを除く）。
--     - 401 / 403 / HTTP 400 なし。
--     - npm run test:smoke = 4 passed（ログイン画面・csv-viewer 回帰なし）。


-- ============================================================
-- 触らないもの（この工程の非対象）
-- ============================================================
--   - read RPC（list_invoices_secure / get_invoice_secure）の EXECUTE（維持）
--   - write RPC 4本（create / update / reject / restore_invoice_secure）の EXECUTE・
--     認可方式（admin_sessions 単経路）（維持）
--   - service_role / postgres(owner) の権限（維持）
--   - RLS 有効状態・既存 policy（変更しない。整理は別工程候補）
--   - helper _verify_management_session（非公開のまま・不変前提）
--   - invoices 以外のテーブル
--
-- 次工程（本ファイル実行後）：
--   - docs/db-migrations.md /（roadmap.md）へ「Phase 4-D-3c 実行済み」を記録。
--   - これにより Phase 4-D-3（請求書 invoices 読み取り保護）完了。
--   - 以降は 4-D の残り（employee_rates / unit_rates は 4-D-1 で完了済み）や
--     financial 系読み取り保護の棚卸し。
-- ============================================================
