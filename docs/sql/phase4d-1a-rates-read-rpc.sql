-- ============================================================
-- Phase 4-D-1a：単価系 read RPC 追加
--   list_unit_rates_secure / list_employee_rates_secure
-- ============================================================
-- 【実行ステータス】☆未実行☆
--   - このファイルはまだ Supabase SQL Editor で実行していない。
--   - 実行は別段階（承認後）。実行後に docs/db-migrations.md /
--     docs/roadmap.md へ「実行済み」記録を追記する（今は追記しない）。
--
-- 【このファイルの方針（重要）】
--   - additive-only：新規 read RPC を2本 CREATE するだけ。
--   - 既存テーブル / RLS / policy / 権限 / 既存RPC / ヘルパーは一切変更しない。
--   - ★SELECT REVOKE はしない★（unit_rates / employee_rates の
--     anon / authenticated 直接 SELECT はこの段では残す）。
--   - 新旧併存：既存の direct SELECT と新 read RPC が同時に成立する状態を作る。
--     フロント移行（4-D-1b）→ 本番確認 の後に、別段階（4-D-1c）で SELECT を REVOKE する。
--   - Phase 4-C-1 の教訓：先に REVOKE しない（本番フロント未移行のまま REVOKE すると
--     単価画面が空表示 / 401 になる）。
--
-- 【対象（現在 direct SELECT が残っている読み取り）】
--   - unit_rates      ： admin-app.html startApp / pageRates、genka-app.html startApp
--   - employee_rates  ： admin-app.html pageRates、genka-app.html startApp
--   （フロント置換は 4-D-1b。本ファイルでは HTML を変更しない）
--
-- 【認可】
--   - 既存ヘルパー public._verify_management_session(text) を再利用する。
--     経路A：admin_sessions + genka_admins.is_active = true
--     経路B：employee_sessions + employees.role='admin' + is_active=true
--   - 同一対象テーブル（unit_rates / employee_rates）の既存 write RPC
--     （upsert_unit_rate_secure / upsert_employee_rate_secure）と同じヘルパーを使い、
--     局所的一貫性を保つ。共通ヘルパーは新設しない。
--   - ヘルパーは RETURNS TABLE だが、認可のみ利用するため PERFORM で呼ぶ
--     （不正 / 期限切れセッションは helper 内で RAISE EXCEPTION）。
--
-- 【EXECUTE 権限の方針（Phase 4-B / 4-C read RPC と同一）】
--   - CREATE 時にデフォルト付与される PUBLIC EXECUTE を REVOKE する。
--   - anon / authenticated / service_role にのみ EXECUTE を明示 GRANT する。
--
-- 【戻り値（最小集合＋実運用の保険列）】
--   - list_unit_rates_secure     ： id, category, name, unit_price, unit, updated_at
--   - list_employee_rates_secure ： id, employee_id, daily_rate, effective_from
--   - employee_rates は多世代の履歴テーブル（1従業員に複数行）。全行返しとし、
--     「effective_from 降順 → 従業員ごと最新採用」は既存フロント側ロジックに任せる。
--
-- ============================================================
-- ★★★ 実行前に必須：戻り値の型確認（事前確認B）★★★
--   RETURNS TABLE の宣言型は実カラム型と一致していること。
--   下記「事前確認B」（information_schema.columns・スキーマメタのみ／実データは読まない）を
--   先に実行し、設計と実型が異なる場合は CREATE 前に RETURNS TABLE の型を必ず修正すること。
--   特に注意（設計時は下記を仮採用している）：
--     - unit_rates.unit_price : integer を仮採用。実型が numeric なら RETURNS を numeric に変更。
--     - unit_rates.updated_at : timestamptz を仮採用。実型が timestamp（tzなし）なら
--                               RETURNS を timestamp に変更。
--     - unit_rates.category/name/unit : text 想定。
--     - employee_rates.daily_rate : integer 想定（upsert 第3引数 integer /
--                                   csv_export_effective_daily_rate 戻り daily_rate integer と整合）。
--     - employee_rates.effective_from : date 想定。id / employee_id : uuid 想定。
-- ============================================================


-- ============================================================
-- 事前確認（実行直前・スキーマメタ / 権限のみ・実データは読まない）
--   ※ これらは SELECT のみで DB 状態を変更しない。
-- ============================================================

-- 事前確認A：ヘルパー存在＆クライアント非公開
--   期待：_verify_management_session が存在・prosecdef=true（SECURITY DEFINER）・
--         proconfig に search_path=public, extensions。
SELECT p.proname, p.prosecdef, p.proconfig
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname = '_verify_management_session';

--   期待：0行（anon / authenticated / public に EXECUTE 権限が無い）
SELECT routine_name, grantee, privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name = '_verify_management_session'
  AND  grantee IN ('anon', 'authenticated', 'public')
ORDER  BY grantee;

-- 事前確認B：★戻り値の型の最終確定★
--   updated_at の tz 有無 / unit_price が int4 か numeric か / 各列の実型を確認する。
--   実型が設計（上記）と異なる場合は CREATE 前に RETURNS TABLE の型を合わせること。
SELECT table_name, column_name, data_type, udt_name
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  ( (table_name = 'unit_rates'
          AND column_name IN ('id','category','name','unit_price','unit','updated_at'))
      OR (table_name = 'employee_rates'
          AND column_name IN ('id','employee_id','daily_rate','effective_from')) )
ORDER  BY table_name, column_name;

-- 事前確認C：新規2関数が未存在であること
--   期待：0行（新規作成のため）。
SELECT p.proname
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_unit_rates_secure', 'list_employee_rates_secure');

-- 事前確認D：併存ベースライン（この段では REVOKE しない前提の確認）
--   期待：unit_rates / employee_rates とも anon / authenticated に SELECT がある。
--         （4-D-1c で REVOKE する対象。今回は残す）
SELECT table_name, grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name IN ('unit_rates', 'employee_rates')
  AND  grantee IN ('anon', 'authenticated')
  AND  privilege_type = 'SELECT'
ORDER  BY table_name, grantee;


-- ============================================================
-- 変更（CREATE FUNCTION × 2 ＋ EXECUTE 権限設定）
--   ※ 事前確認B の実型に合わせて RETURNS TABLE の型を確定してから実行すること。
-- ============================================================

-- 1. list_unit_rates_secure
--    管理セッション検証後、unit_rates 全行を決定的順序で返す。
--    フロントは 'category:name' で map 化するため順序非依存だが、
--    決定性のため ORDER BY を付与する。挙動は現行 direct SELECT と等価。
CREATE OR REPLACE FUNCTION public.list_unit_rates_secure(
  session_token_input text
)
RETURNS TABLE (
  id          uuid,
  category    text,
  name        text,
  unit_price  integer,
  unit        text,
  updated_at  timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- 認可（不正 / 期限切れは helper 内で RAISE）。戻り値は使わないので PERFORM。
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
    SELECT ur.id, ur.category, ur.name, ur.unit_price, ur.unit, ur.updated_at
    FROM   public.unit_rates ur
    ORDER  BY ur.category, ur.name;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_unit_rates_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_unit_rates_secure(text)
  TO anon, authenticated, service_role;


-- 2. list_employee_rates_secure
--    管理セッション検証後、employee_rates 全行（多世代履歴）を返す。
--    「従業員ごと最新採用」はフロント側（effective_from 降順→先勝ち）に任せる。
--    決定性のため employee_id, effective_from DESC で ORDER BY する。
CREATE OR REPLACE FUNCTION public.list_employee_rates_secure(
  session_token_input text
)
RETURNS TABLE (
  id             uuid,
  employee_id    uuid,
  daily_rate     integer,
  effective_from date
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
    SELECT er.id, er.employee_id, er.daily_rate, er.effective_from
    FROM   public.employee_rates er
    ORDER  BY er.employee_id, er.effective_from DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_employee_rates_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_employee_rates_secure(text)
  TO anon, authenticated, service_role;


-- ============================================================
-- 事後確認（CREATE / GRANT 後・メタ / 権限のみ・実データは読まない）
--   ※ 実データ動作確認（実際に行が返るか）は本ファイルでは行わない。
--     本番実データ読み取りを避けるため、動作確認は 4-D-1b のフロント移行後に
--     本番画面＋Network（list_*_secure が出る / direct SELECT が出ない）で行う。
-- ============================================================

-- 事後確認F：2関数の存在・SECURITY DEFINER・search_path
--   期待：2行、prosecdef=true、proconfig に search_path=public, extensions。
SELECT p.proname, p.prosecdef, p.proconfig
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_unit_rates_secure', 'list_employee_rates_secure')
ORDER  BY p.proname;

-- 事後確認G：EXECUTE 権限（anon / authenticated / service_role）
--   期待：6行（2関数 × 3ロール）。
SELECT routine_name, grantee, privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name IN ('list_unit_rates_secure', 'list_employee_rates_secure')
  AND  grantee IN ('anon', 'authenticated', 'service_role')
ORDER  BY routine_name, grantee;

-- 事後確認G-2：PUBLIC EXECUTE が無いこと
--   期待：proacl に PUBLIC（=X/postgres）エントリが無い
--   （anon=X/… / authenticated=X/… / service_role=X/… のみ）。
SELECT p.proname, p.proacl
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_unit_rates_secure', 'list_employee_rates_secure')
ORDER  BY p.proname;

-- 事後確認H：テーブル SELECT が不変であること（この段で REVOKE していない）
--   期待：事前確認D と同じ（unit_rates / employee_rates とも
--         anon / authenticated に SELECT が残存）。
SELECT table_name, grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name IN ('unit_rates', 'employee_rates')
  AND  grantee IN ('anon', 'authenticated')
  AND  privilege_type = 'SELECT'
ORDER  BY table_name, grantee;

-- ============================================================
-- 次工程（本ファイル実行後）
--   4-D-1b：フロント移行（今回は行わない）
--     - genka-app.html startApp：employee_rates / unit_rates の direct SELECT を
--       list_employee_rates_secure / list_unit_rates_secure に置換
--     - admin-app.html startApp：unit_rates の direct SELECT を置換
--     - admin-app.html pageRates：employee_rates / unit_rates の direct SELECT を置換
--     - token ガード・error ガードを追加。後続の集計 / エディタ描画は原則無改修。
--     → PR → merge → 本番反映確認（Network に list_*_secure あり / direct SELECT なし）
--   4-D-1c：本番で RPC 経由を確認した後に、unit_rates / employee_rates の
--     anon / authenticated 直接 SELECT を REVOKE（別ファイル・別段階）。
-- ============================================================
