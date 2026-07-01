-- ============================================================
-- Phase 4-C-1：reports direct SELECT 遮断（anon / authenticated）
-- ============================================================
-- 【実行ステータス】⚠一時実行済み → GRANT復旧済み → 最終未適用⚠
--   - 実行日：2026-07-01
--   - 経緯：
--       1) 一時REVOKE を実行：
--            REVOKE SELECT ON public.reports FROM anon, authenticated;
--            → Success. No rows returned
--       2) 発生事象：本番フロントがまだ旧 direct SELECT 版のままだったため、
--          日報履歴が空表示になった。
--          Console で reports の direct SELECT
--          （reports?select=*&employee_id=...&order=report_date.desc&limit=30 / limit=1）
--          が 401 になっているのを確認。
--       3) 復旧：
--            GRANT SELECT ON public.reports TO anon, authenticated;
--            → Success. No rows returned
--            → 日報履歴 OK・Console 赤エラーなし で復旧確認。
--   - したがって、このファイルの REVOKE は「最終未適用」扱い。
--
--   【現在のDB状態（2026-07-01 時点）】
--     - reports の SELECT は anon / authenticated に「復旧済み（付与あり）」。
--     - list_my_reports_secure は DB 作成済み（新旧併存状態）。
--     - index.html の RPC 移行はローカルのみ。本番フロントには未反映。
--
--   【再実行条件（重要）】
--     - このブランチ（phase4c-1-my-reports-rpc）を PR / merge し、
--       本番フロントが RPC 版（list_my_reports_secure 使用・from('reports') 0件）に
--       反映されたことを確認してから、あらためて本ファイルの REVOKE を実施する。
--     - 順序を誤って先に REVOKE すると、本番の旧フロントが 401 で空表示になる。
--
--   ※ SQL 本文（REVOKE 文・事前確認 A〜F・事後確認 G〜K）は変更していない。
--     本ファイルは再実行時にそのまま使える。
--
-- 目的：
--   本人日報フロント（index.html copyFromYesterday / loadHistory）を
--   list_my_reports_secure（SECURITY DEFINER read RPC）へ移行した後、
--   reports テーブルへの anon / authenticated の直接 SELECT を遮断する。
--   これにより「フロントは RPC 経由のみで自分の日報を読む」状態に一本化する。
--
-- 前提（すべて完了済み）：
--   - list_my_reports_secure：DB 作成済み（SECURITY DEFINER / search_path 固定 /
--     EXECUTE=anon,authenticated,service_role・PUBLIC なし）。
--   - index.html：copyFromYesterday / loadHistory を list_my_reports_secure へ移行済み。
--   - 画面確認 OK（日報履歴表示 / 写真バッジ・詳細 / 修正ボタン・編集復元 /
--     前日コピー / Console 赤エラーなし）。
--   - index.html 内の from('reports') は 0 件（コード側で確認済み。SQL では確認不可）。
--
-- このファイルの方針（重要）：
--   - reports の anon / authenticated 直接 SELECT のみを REVOKE する。
--   - reports_all policy は今回いきなり DROP しない（cmd=ALL の単一 policy のため、
--     write RPC への影響確認を別ステップに分けて慎重に扱う）。
--   - report_summary View は今回一切触らない（権限・定義とも変更しない）。
--     report_summary は postgres owner / bypassrls View のため、reports の
--     SELECT REVOKE 後も index 管理画面・genka 原価画面は一旦継続動作する想定。
--     report_summary の封鎖は 4-C-4 で代替 RPC 移行後に実施予定。
--   - 既存 write RPC（create_report_secure / update_report_secure /
--     update_report_photo_secure）は一切変更しない。SECURITY DEFINER のため
--     reports の直接 SELECT を REVOKE しても RPC 経由の読み書きは動作継続する。
--
-- 実行方法（実行する場合）：
--   Supabase SQL Editor で各セクションを順に実行。
--   「事前確認」→「変更（REVOKE）」→「事後確認」の順。
--   ※ 変更は REVOKE SELECT 1本のみ。
-- ============================================================


-- ============================================================
-- 事前確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- A. reports の anon / authenticated / PUBLIC 権限
--    期待：anon / authenticated に SELECT が「まだ残っている」。
--          INSERT / UPDATE / DELETE は無い（Phase 3 で REVOKE 済）。
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
--    期待：reports_all（cmd=ALL / roles={public} / qual=true / with_check=true）が残存。
--    ※ 今回このファイルでは DROP / 変更しない。現状把握のみ。
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

-- C. list_my_reports_secure の存在 / SECURITY DEFINER / search_path
--    期待：存在・security_definer=true・config に search_path=public, extensions。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       p.proconfig      AS config,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_my_reports_secure'
ORDER BY p.proname;

-- D. list_my_reports_secure の EXECUTE 権限
--    期待：anon / authenticated / service_role に EXECUTE、PUBLIC は無い。
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name = 'list_my_reports_secure'
  AND grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER BY routine_name, grantee;

-- E. 既存 reports write RPC 3本の存在 / SECURITY DEFINER / search_path
--    期待：3本が存在・security_definer=true・search_path=public, extensions。
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

-- F. report_summary が未変更であることの確認（今回触らない担保）
--    期待：view のまま、owner=postgres、reloptions=null、
--          anon / authenticated の SELECT も従来どおり残存。
SELECT c.relname     AS object_name,
       c.relkind     AS relkind,
       r.rolname     AS owner,
       c.reloptions  AS reloptions
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles r     ON r.oid = c.relowner
WHERE n.nspname = 'public'
  AND c.relname = 'report_summary';

-- F-2. report_summary の anon / authenticated / PUBLIC SELECT 権限（未変更確認）
SELECT table_name AS view_name,
       grantee,
       privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'report_summary'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND privilege_type = 'SELECT'
ORDER BY grantee;

-- ※ index.html 内の from('reports') が 0 件であることは SQL では確認できない。
--   → コード側で確認済み（grep 結果 0 件）。本人日報取得は list_my_reports_secure に一本化済み。


-- ============================================================
-- 変更（REVOKE SELECT × 1 のみ）
-- ============================================================
-- reports の anon / authenticated 直接 SELECT を遮断する。
-- reports_all policy は DROP しない。report_summary は触らない。
-- write RPC（SECURITY DEFINER）は本 REVOKE の影響を受けない。

REVOKE SELECT ON public.reports FROM anon, authenticated;


-- ============================================================
-- 事後確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- G. reports の anon / authenticated / PUBLIC 権限
--    期待：anon / authenticated の SELECT が「消えている」。
--          INSERT / UPDATE / DELETE は元々無いので出ない（＝この結果は空になる想定）。
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

-- G-2. has_table_privilege による確定確認
--    期待：anon / authenticated の reports SELECT が false。
SELECT 'reports' AS table_name,
       has_table_privilege('anon',          'public.reports', 'SELECT') AS anon_select,
       has_table_privilege('authenticated', 'public.reports', 'SELECT') AS auth_select;

-- H. reports_all policy がまだ残っていることの確認（今回は残す）
--    期待：reports_all（cmd=ALL / roles={public} / qual=true / with_check=true）が残存。
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

-- I. list_my_reports_secure の EXECUTE 権限が維持されていること
--    期待：anon / authenticated / service_role に EXECUTE、PUBLIC は無い。
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name = 'list_my_reports_secure'
  AND grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER BY routine_name, grantee;

-- I-2. list_my_reports_secure の PUBLIC EXECUTE が無いことの権威的確認（proacl）
--    期待：proacl に =X/postgres（先頭が空＝PUBLIC）が無い。
SELECT p.proname,
       p.proacl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_my_reports_secure'
ORDER BY p.proname;

-- J. 既存 reports write RPC 3本が不変であることの確認
--    期待：3本が引き続き security_definer=true・search_path=public, extensions で存在。
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

-- K. report_summary が未変更であることの確認（今回触っていない担保）
--    期待：view・owner=postgres・reloptions=null、anon/authenticated SELECT 残存。
SELECT c.relname     AS object_name,
       c.relkind     AS relkind,
       r.rolname     AS owner,
       c.reloptions  AS reloptions
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles r     ON r.oid = c.relowner
WHERE n.nspname = 'public'
  AND c.relname = 'report_summary';

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
-- このファイルで「行わない」こと / 今後の予定：
--   - reports_all policy は今回残す（DROP しない）。
--     reports_all の DROP / 整理は、本 REVOKE 後の本番確認と
--     write RPC 動作確認が済んでから、別ステップで判断する。
--   - report_summary は今回変更しない。
--     4-C-2 / 4-C-3 で代替 read RPC へ移行後、4-C-4 で封鎖する。
--
-- REVOKE 後に確認する画面（本番）：
--   [本人日報 / index.html]
--     - 従業員 日報履歴
--     - 写真詳細
--     - 編集復元
--     - 前日コピー
--     - 日報新規保存
--     - 日報修正保存
--     - 写真保存
--   [report_summary 経由（今回 REVOKE の影響を受けない想定）]
--     - index 管理者の提出状況・集計
--     - genka 原価画面
-- ============================================================
