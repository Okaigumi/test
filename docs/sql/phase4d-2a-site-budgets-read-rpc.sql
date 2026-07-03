-- ============================================================
-- Phase 4-D-2a：site_budgets read RPC 追加
--   list_site_budgets_secure / get_site_budget_secure
-- ============================================================
-- 【このファイルの方針（重要）】
--   - additive-only：新規 read RPC を2本 CREATE するだけ。
--   - 既存テーブル / RLS / policy / 権限 / 既存RPC / ヘルパーは一切変更しない。
--   - ★SELECT REVOKE はしない★（site_budgets の anon/authenticated 直接
--     SELECT はこの段では残す）。新旧併存。
--   - フロント移行（4-D-2b）→ 本番確認 の後に、別段階（4-D-2c）で SELECT を REVOKE。
--   - Phase 4-C-1 の教訓：先に REVOKE しない。
--
-- 【対象（現在 direct SELECT が残っている読み取り）】
--   - admin-app.html pageBudgets（active/inactive）, openBudgetModal
--   - genka-app.html openBudgetModal, 原価サマリ集計
--   （フロント置換は 4-D-2b。本ファイルでは HTML を変更しない）
--
-- 【認可】
--   - 既存ヘルパー public._verify_management_session(text) を再利用（Phase 4-D-1 と同一）。
--     経路A：admin_sessions + genka_admins.is_active=true
--     経路B：employee_sessions + employees.role='admin' + is_active=true
--   - 認可のみ利用のため PERFORM で呼ぶ（不正/期限切れは helper 内で RAISE）。
--
-- 【EXECUTE 権限の方針（Phase 4-B/4-C/4-D-1 read RPC と同一）】
--   - CREATE 時デフォルトの PUBLIC EXECUTE を REVOKE。
--   - anon/authenticated/service_role にのみ EXECUTE を明示 GRANT。
--
-- 【戻り値（最小集合＋実運用の保険列）】
--   - 両関数とも：id, site_id, year, month, budget, memo, is_active, updated_at
--     （month=年間判定、updated_at=最新採用、is_active=タブ表示 のため保険列を含む）
--
-- 【annual_only_input の意味（重要・誤解防止）】
--   - annual_only_input = false または NULL の場合：month 条件なし（全 month を返す）。
--   - annual_only_input = true             の場合：sb.month IS NULL のみ（年間予算のみ）。
--   - 条件式 (COALESCE(annual_only_input, false) = false OR sb.month IS NULL) により、
--     NULL は false と同一扱い（＝month 条件なし）となる。
-- ============================================================
-- ★★★ 実行前に必須：戻り値の型確認（事前確認B）★★★
--   RETURNS TABLE の宣言型は実カラム型と一致していること。
--   設計時の仮採用：budget integer / year integer / month integer /
--   updated_at timestamptz / id・site_id uuid / memo text / is_active boolean。
--   実型が異なる場合は CREATE 前に RETURNS TABLE を必ず修正すること。
-- ============================================================


-- ============================================================
-- 事前確認（実行直前・スキーマメタ/権限のみ・実データは読まない）
-- ============================================================

-- 事前確認A：ヘルパー存在＆クライアント非公開
--   期待：_verify_management_session が存在・prosecdef=true・
--         proconfig に search_path=public, extensions。
SELECT p.proname, p.prosecdef, p.proconfig
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname = '_verify_management_session';

--   期待：0行（anon/authenticated/public に EXECUTE 権限が無い）
SELECT routine_name, grantee, privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name = '_verify_management_session'
  AND  grantee IN ('anon', 'authenticated', 'public')
ORDER  BY grantee;

-- 事前確認B：★戻り値の型の最終確定★
--   budget/year/month が int4 か、updated_at の tz 有無、他列の実型を確認。
--   設計と異なる場合は CREATE 前に RETURNS TABLE の型を合わせること。
SELECT column_name, data_type, udt_name, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'site_budgets'
  AND  column_name IN ('id','site_id','year','month','budget','memo','is_active','updated_at')
ORDER  BY column_name;

-- 事前確認C：新規2関数が未存在であること
--   期待：0行（新規作成のため）。
SELECT p.proname
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_site_budgets_secure', 'get_site_budget_secure');

-- 事前確認D：併存ベースライン（この段では REVOKE しない前提の確認）
--   期待：site_budgets に anon/authenticated の SELECT がある
--         （4-D-2c で REVOKE する対象。今回は残す）。
SELECT table_name, grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name   = 'site_budgets'
  AND  grantee IN ('anon', 'authenticated')
  AND  privilege_type = 'SELECT'
ORDER  BY grantee;


-- ============================================================
-- 変更（CREATE FUNCTION × 2 ＋ EXECUTE 権限設定）
--   ※ 事前確認B の実型に合わせて RETURNS TABLE の型を確定してから実行すること。
-- ============================================================

-- 1. list_site_budgets_secure
--    管理セッション検証後、site_budgets を任意条件で絞って返す。
--    引数はいずれも省略可（NULL/false=条件なし）。決定性のため ORDER BY 付与。
--    annual_only_input：false/NULL=month 条件なし、true=sb.month IS NULL のみ。
CREATE OR REPLACE FUNCTION public.list_site_budgets_secure(
  session_token_input text,
  is_active_input     boolean DEFAULT NULL,
  site_id_input       uuid    DEFAULT NULL,
  year_input          integer DEFAULT NULL,
  annual_only_input   boolean DEFAULT false
)
RETURNS TABLE (
  id         uuid,
  site_id    uuid,
  year       integer,
  month      integer,
  budget     integer,
  memo       text,
  is_active  boolean,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- 認可（不正/期限切れは helper 内で RAISE）。戻り値は使わないので PERFORM。
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
    SELECT sb.id, sb.site_id, sb.year, sb.month,
           sb.budget, sb.memo, sb.is_active, sb.updated_at
    FROM   public.site_budgets sb
    WHERE  (is_active_input IS NULL OR sb.is_active = is_active_input)
      AND  (site_id_input   IS NULL OR sb.site_id   = site_id_input)
      AND  (year_input      IS NULL OR sb.year      = year_input)
      -- annual_only_input: false/NULL=month 条件なし / true=年間予算(month IS NULL)のみ
      AND  (COALESCE(annual_only_input, false) = false OR sb.month IS NULL)
    ORDER  BY sb.year DESC, sb.updated_at DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_site_budgets_secure(text, boolean, uuid, integer, boolean) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_site_budgets_secure(text, boolean, uuid, integer, boolean)
  TO anon, authenticated, service_role;


-- 2. get_site_budget_secure
--    管理セッション検証後、id 指定の1件を返す（該当なしは 0 行）。
CREATE OR REPLACE FUNCTION public.get_site_budget_secure(
  session_token_input text,
  id_input            uuid
)
RETURNS TABLE (
  id         uuid,
  site_id    uuid,
  year       integer,
  month      integer,
  budget     integer,
  memo       text,
  is_active  boolean,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
    SELECT sb.id, sb.site_id, sb.year, sb.month,
           sb.budget, sb.memo, sb.is_active, sb.updated_at
    FROM   public.site_budgets sb
    WHERE  sb.id = id_input;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_site_budget_secure(text, uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_site_budget_secure(text, uuid)
  TO anon, authenticated, service_role;


-- ============================================================
-- 事後確認（CREATE/GRANT 後・メタ/権限のみ・実データは読まない）
--   ※ 実データ動作確認は 4-D-2b のフロント移行後に本番画面＋Network で行う。
-- ============================================================

-- 事後確認F：2関数の存在・SECURITY DEFINER・search_path
--   期待：2行、prosecdef=true、proconfig に search_path=public, extensions。
SELECT p.proname, p.prosecdef, p.proconfig
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_site_budgets_secure', 'get_site_budget_secure')
ORDER  BY p.proname;

-- 事後確認G：EXECUTE 権限（anon/authenticated/service_role）
--   期待：6行（2関数 × 3ロール）。
SELECT routine_name, grantee, privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name IN ('list_site_budgets_secure', 'get_site_budget_secure')
  AND  grantee IN ('anon', 'authenticated', 'service_role')
ORDER  BY routine_name, grantee;

-- 事後確認G-2：PUBLIC EXECUTE が無いこと
--   期待：proacl に PUBLIC エントリが無い（anon/authenticated/service_role のみ）。
SELECT p.proname, p.proacl
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_site_budgets_secure', 'get_site_budget_secure')
ORDER  BY p.proname;

-- 事後確認H：★SELECT が不変（この段で REVOKE していない）★
--   期待：事前確認D と同じ（site_budgets に anon/authenticated の SELECT が残存）。
SELECT table_name, grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name   = 'site_budgets'
  AND  grantee IN ('anon', 'authenticated')
  AND  privilege_type = 'SELECT'
ORDER  BY grantee;

-- ============================================================
-- 次工程（本ファイル実行後）
--   4-D-2b：フロント移行（今回は行わない）
--     - admin-app.html pageBudgets①② → list_site_budgets_secure(is_active, annual_only=false)
--     - admin-app.html openBudgetModal③ → get_site_budget_secure（.single() は使わず data?.[0]）
--     - genka-app.html openBudgetModal④ → list(is_active=true, site_id, year, annual_only=true)
--                                          ＋ updated_at 降順先頭採用
--     - genka-app.html 集計⑤ → list(is_active=true, year, annual_only=true)
--     - token/error ガードを追加。→ PR → merge → 本番反映確認
--   4-D-2c：本番で RPC 経由を確認した後に、site_budgets の anon/authenticated
--     直接 SELECT を REVOKE（別ファイル・別段階）。
-- ============================================================
