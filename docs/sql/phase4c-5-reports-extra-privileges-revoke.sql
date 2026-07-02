-- ============================================================
-- Phase 4-C-5：reports 残存不要権限の整理
--                （anon / authenticated の TRUNCATE / REFERENCES / TRIGGER を REVOKE）
-- ============================================================
-- 【実行ステータス】★最終適用済み（2026-07-02）★
--   - Supabase SQL Editor で REVOKE を実行済み。
--
--   【実行 SQL（2026-07-02）】
--     revoke truncate, references, trigger on table public.reports from anon, authenticated;
--       → Success. No rows returned
--
--   【実行前確認結果（2026-07-02）】
--     reports：anon / authenticated ともに
--       can_select=false / can_insert=false / can_update=false / can_delete=false /
--       can_truncate=true / can_references=true / can_trigger=true
--
--   【実行後確認結果（2026-07-02）】
--     reports：anon / authenticated ともに全 false
--       can_select=false / can_insert=false / can_update=false / can_delete=false /
--       can_truncate=false / can_references=false / can_trigger=false
--     → 残存していた TRUNCATE / REFERENCES / TRIGGER の除去を確認。
--
-- 目的：
--   public.reports に対する anon / authenticated の非読み取り不要権限
--   （TRUNCATE / REFERENCES / TRIGGER）を REVOKE する。
--   SELECT / INSERT / UPDATE / DELETE は既に遮断済み（Phase 4-C-1 ほかで対応済み）。
--   本整理はそれらの遮断後に残っていた TRUNCATE / REFERENCES / TRIGGER を除去するもの。
--
-- 背景：
--   Phase 4-C 完了後の Supabase ライブ確認で、reports に anon/authenticated の
--   TRUNCATE / REFERENCES / TRIGGER が残存していることを確認した
--   （report_summary は既に全 REVOKE 済みで残存なし）。
--   日報カレンダー MVP の読み取りブロッカーではないが、Phase 4-C 補整理として先に対応する。
--
-- 対象オブジェクト：
--   public.reports
--
-- 対象ロール：
--   anon
--   authenticated
--
-- 変更（REVOKE × 1）：
--   SELECT / INSERT / UPDATE / DELETE は対象外（既に遮断済み・本SQLでは触れない）。
--   report_summary・RPC・policy・postgres / service_role は一切変更しない。
--
-- ロールバック案（必要時のみ・通常は不要）：
--   -- GRANT TRUNCATE, REFERENCES, TRIGGER ON TABLE public.reports TO anon, authenticated;
--   ※ ただしこれらは元々不要権限のため、原則として復旧しない。


-- ------------------------------------------------------------
-- A. 実行前確認（reports の anon / authenticated 権限の現況）
--    期待：can_select=false / can_insert=false / can_update=false / can_delete=false
--          can_truncate=true / can_references=true / can_trigger=true
-- ------------------------------------------------------------
select
  role_name,
  object_name,
  has_table_privilege(role_name, object_name, 'SELECT')     as can_select,
  has_table_privilege(role_name, object_name, 'INSERT')     as can_insert,
  has_table_privilege(role_name, object_name, 'UPDATE')     as can_update,
  has_table_privilege(role_name, object_name, 'DELETE')     as can_delete,
  has_table_privilege(role_name, object_name, 'TRUNCATE')   as can_truncate,
  has_table_privilege(role_name, object_name, 'REFERENCES') as can_references,
  has_table_privilege(role_name, object_name, 'TRIGGER')    as can_trigger
from (
  values
    ('anon', 'public.reports'),
    ('authenticated', 'public.reports')
) as v(role_name, object_name)
order by object_name, role_name;


-- ------------------------------------------------------------
-- B. 変更本体（REVOKE）
-- ------------------------------------------------------------
revoke truncate, references, trigger on table public.reports from anon, authenticated;


-- ------------------------------------------------------------
-- C. 実行後確認（reports の anon / authenticated 権限）
--    期待：can_select=false / can_insert=false / can_update=false / can_delete=false
--          can_truncate=false / can_references=false / can_trigger=false
-- ------------------------------------------------------------
select
  role_name,
  object_name,
  has_table_privilege(role_name, object_name, 'SELECT')     as can_select,
  has_table_privilege(role_name, object_name, 'INSERT')     as can_insert,
  has_table_privilege(role_name, object_name, 'UPDATE')     as can_update,
  has_table_privilege(role_name, object_name, 'DELETE')     as can_delete,
  has_table_privilege(role_name, object_name, 'TRUNCATE')   as can_truncate,
  has_table_privilege(role_name, object_name, 'REFERENCES') as can_references,
  has_table_privilege(role_name, object_name, 'TRIGGER')    as can_trigger
from (
  values
    ('anon', 'public.reports'),
    ('authenticated', 'public.reports')
) as v(role_name, object_name)
order by object_name, role_name;
