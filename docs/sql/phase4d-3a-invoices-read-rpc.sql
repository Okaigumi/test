-- ============================================================
-- Phase 4-D-3a：invoices read RPC 追加
--   list_invoices_secure / get_invoice_secure
-- ============================================================
-- 【実行ステータス】★実行済み★（2026-07-04）
--   Supabase SQL Editor で本番反映済み（Claude Code CLI からの DB 接続・
--   Supabase CLI 使用なし）。
--   実行：CREATE FUNCTION ×2 / REVOKE EXECUTE FROM PUBLIC ×2 /
--         GRANT EXECUTE TO anon,authenticated,service_role ×2
--         （すべて Success. No rows returned）
--   事前確認：
--     A-1：_verify_management_session 存在・prosecdef=true・
--          proconfig=["search_path=public, extensions"]
--     A-2：helper の anon/authenticated/PUBLIC 直接 EXECUTE なし（0行）
--     B  ：invoices 実型が設計と一致
--          amount=integer/int4(NOT NULL) / category=text(NOT NULL) /
--          description=text(NULL可) / id=uuid(NOT NULL) /
--          invoice_date=date(NOT NULL) / memo=text(NULL可) /
--          site_id=uuid(NULL可) / status=text(NOT NULL) /
--          tax_included=boolean/bool(NOT NULL) / vendor_name=text(NOT NULL)
--          → invoice_date=date・amount=integer・tax_included=boolean を確認、
--            RETURNS TABLE 修正不要。status/category は ::text で正規化して返す。
--     C  ：list_invoices_secure / get_invoice_secure 事前 0行（新規）
--     D  ：invoices の anon/authenticated SELECT 残存（併存ベースライン）
--   事後確認：
--     F  ：2関数とも存在・prosecdef=true・search_path=public, extensions
--     G  ：EXECUTE = 2関数 ×（anon/authenticated/service_role）＝6行
--     G-2：PUBLIC EXECUTE なし（0行）
--     H  ：invoices の anon/authenticated SELECT は引き続き残存＝REVOKE 未実施
--   ★SELECT REVOKE は未実施・新旧併存★（4-D-3c で別段階）。
-- ============================================================
-- 【このファイルの方針（重要）】
--   - additive-only：新規 read RPC を2本 CREATE するだけ。
--   - 既存テーブル / RLS / policy / 権限 / 既存RPC / ヘルパーは一切変更しない。
--   - ★SELECT REVOKE はしない★（invoices の anon/authenticated 直接
--     SELECT はこの段では残す）。新旧併存。
--   - フロント移行（4-D-3b）→ 本番確認 の後に、別段階（4-D-3c）で SELECT を REVOKE。
--   - Phase 4-C-1 の教訓：先に REVOKE しない。
--
-- 【目的】
--   admin-app.html / genka-app.html に残る invoices の直接 SELECT を、
--   secure read RPC 経由へ置き換える（フロント移行は 4-D-3b）ための
--   read RPC を、現行挙動を壊さない形で追加する。
--
-- 【対象（現在 direct SELECT が残っている読み取り・行番号は 4-D-3 着手時点）】
--   - admin-app.html:545 pageInvoices active   （status <> 'rejected', order desc, limit 200）
--   - admin-app.html:581 pageInvoices rejected  （status = 'rejected',  order desc, limit 200）
--   - admin-app.html:615 openInvoiceModal       （id 指定・詳細）
--   - genka-app.html:698 loadInvoices           （invoice_date 期間, status IN (confirmed,posted), order desc）
--   - genka-app.html:760 editInvoice            （id 指定・詳細）
--   - genka-app.html:847 loadData 集計          （invoice_date 期間, status IN (confirmed,posted), 任意 site_id）
--   （フロント置換は 4-D-3b。本ファイルでは HTML を変更しない）
--
-- 【非対象（触らない）】
--   - REVOKE SELECT ON invoices（4-D-3c で別ファイル・別段階）
--   - 既存 invoices write RPC（create/update/reject/restore_invoice_secure ほか）
--   - RLS / policy / service_role / postgres / ヘルパー _verify_management_session
--   - invoices 以外のテーブル、他フェーズの RPC
--   - HTML（4-D-3b）、docs 更新（別作業）
--
-- 【認可】
--   - 既存ヘルパー public._verify_management_session(text) を再利用（Phase 4-D-1/4-D-2 と同一）。
--     経路A：admin_sessions + genka_admins.is_active=true
--     経路B：employee_sessions + employees.role='admin' + is_active=true
--   - 認可のみ利用のため PERFORM で呼ぶ（不正/期限切れは helper 内で RAISE）。
--   - 既存 invoices write RPC はインラインの admin_sessions 単経路検証を使うが、
--     read RPC は read 系（4-D-1/4-D-2）の一貫性を優先し二経路ヘルパーを採用。
--     write RPC 側は変更しない。
--
-- 【EXECUTE 権限の方針（Phase 4-B/4-C/4-D read RPC と同一）】
--   - CREATE 時デフォルトの PUBLIC EXECUTE を REVOKE。
--   - anon/authenticated/service_role にのみ EXECUTE を明示 GRANT。
--
-- 【戻り値（実使用列に限定）】
--   - 両関数とも：
--       id, invoice_date, site_id, vendor_name, category,
--       amount, tax_included, description, memo, status
--   - status は enum / USER-DEFINED の可能性があるため ::text で正規化して返す。
--   - category も将来 enum 化された場合の型不一致を避けるため ::text で正規化して返す。
--   - company_id / created_at は現行フロント未使用のため戻り列に含めない（将来必要時に追加）。
--
-- 【status 条件の設計】
--   - statuses_input（text[]）      ：指定時 inv.status::text = ANY(statuses_input)
--   - exclude_status_input（text）  ：指定時 inv.status::text <> exclude_status_input
--   - 原則としてフロント側で「包含」か「除外」のどちらか一方のみ指定する。
--     （両方 NULL 可＝条件なし。両条件は AND 結合のため同時指定でも安全に評価される。）
-- ============================================================
-- ★★★ 実行前に必須：戻り値／比較の型確認（事前確認B）★★★
--   RETURNS TABLE の宣言型は実カラム型と一致していること。
--   設計時の仮採用：
--     id/site_id uuid / invoice_date date / amount integer /
--     tax_included boolean / vendor_name・description・memo text /
--     category・status は ::text 正規化して返す。
--   実型が異なる場合は CREATE 前に RETURNS TABLE を必ず修正すること。
--   特に以下は不一致なら CREATE 前に停止：
--     invoice_date が date でない / amount が仮定と違う /
--     tax_included が boolean でない。
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
--   ※ grantee は PUBLIC が大文字で返る場合があるため lower() で比較する。
SELECT routine_name, grantee, privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name = '_verify_management_session'
  AND  lower(grantee) IN ('anon', 'authenticated', 'public')
ORDER  BY grantee;

-- 事前確認B：★戻り値／比較の実型確定★
--   invoice_date/amount/tax_included/status/category ほかの実型を確認。
--   data_type と udt_name の両方を見る（enum は data_type='USER-DEFINED'・udt_name=型名）。
--   設計と異なる場合は CREATE 前に RETURNS TABLE の型を合わせること。
--   invoice_date が date でない / amount が仮定と違う / tax_included が boolean でない
--   場合は CREATE 前に停止・報告。
SELECT column_name, data_type, udt_name, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'invoices'
  AND  column_name IN ('id','invoice_date','site_id','vendor_name',
                       'category','amount','tax_included','description','memo','status')
ORDER  BY column_name;

-- 事前確認C：新規2関数が未存在であること
--   期待：0行（新規作成のため）。存在する場合は CREATE 前に停止・報告。
SELECT p.proname
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_invoices_secure', 'get_invoice_secure');

-- 事前確認D：併存ベースライン（この段では REVOKE しない前提の確認）
--   期待：invoices に anon/authenticated の SELECT がある
--         （4-D-3c で REVOKE する対象。今回は残す）。
--   SELECT が既に無い場合は前提崩れとして CREATE 前に停止・報告。
SELECT table_name, grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name   = 'invoices'
  AND  grantee IN ('anon', 'authenticated')
  AND  privilege_type = 'SELECT'
ORDER  BY grantee;


-- ============================================================
-- 変更（CREATE FUNCTION × 2 ＋ EXECUTE 権限設定）
--   ※ 事前確認B の実型に合わせて RETURNS TABLE の型を確定してから実行すること。
-- ============================================================

-- 1. list_invoices_secure
--    管理セッション検証後、invoices を任意条件で絞って返す。
--    status は包含(statuses_input)／除外(exclude_status_input)で表現（原則どちらか一方）。
--    limit_input=NULL は LIMIT NULL＝全件（genka の期間一覧/集計）、
--    200 指定で admin の一覧（active/rejected）を再現。
--    決定性のため ORDER BY invoice_date DESC を付与。
CREATE OR REPLACE FUNCTION public.list_invoices_secure(
  session_token_input  text,
  statuses_input       text[]  DEFAULT NULL,
  exclude_status_input text    DEFAULT NULL,
  date_from_input      date    DEFAULT NULL,
  date_to_input        date    DEFAULT NULL,
  site_id_input        uuid    DEFAULT NULL,
  limit_input          integer DEFAULT NULL
)
RETURNS TABLE (
  id           uuid,
  invoice_date date,
  site_id      uuid,
  vendor_name  text,
  category     text,        -- inv.category::text で正規化して返す
  amount       integer,     -- ★事前確認Bで実型に合わせる（numeric なら numeric）
  tax_included boolean,
  description  text,
  memo         text,
  status       text         -- ★enum の可能性 → inv.status::text で正規化して返す
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- 認可（不正/期限切れは helper 内で RAISE）。戻り値は使わないので PERFORM。
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
    SELECT inv.id, inv.invoice_date, inv.site_id, inv.vendor_name,
           inv.category::text, inv.amount, inv.tax_included, inv.description,
           inv.memo, inv.status::text
    FROM   public.invoices inv
    WHERE  (statuses_input       IS NULL OR inv.status::text = ANY(statuses_input))
      AND  (exclude_status_input IS NULL OR inv.status::text <> exclude_status_input)
      AND  (date_from_input      IS NULL OR inv.invoice_date >= date_from_input)
      AND  (date_to_input        IS NULL OR inv.invoice_date <= date_to_input)
      AND  (site_id_input        IS NULL OR inv.site_id = site_id_input)
    ORDER  BY inv.invoice_date DESC
    LIMIT  limit_input;   -- NULL のとき全件（PostgreSQL の LIMIT NULL）
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_invoices_secure(text, text[], text, date, date, uuid, integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_invoices_secure(text, text[], text, date, date, uuid, integer)
  TO anon, authenticated, service_role;


-- 2. get_invoice_secure
--    管理セッション検証後、id 指定の1件を返す（該当なしは 0 行）。
CREATE OR REPLACE FUNCTION public.get_invoice_secure(
  session_token_input text,
  id_input            uuid
)
RETURNS TABLE (
  id           uuid,
  invoice_date date,
  site_id      uuid,
  vendor_name  text,
  category     text,        -- inv.category::text で正規化して返す
  amount       integer,     -- ★事前確認Bで実型に合わせる
  tax_included boolean,
  description  text,
  memo         text,
  status       text         -- ★inv.status::text で正規化して返す
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
    SELECT inv.id, inv.invoice_date, inv.site_id, inv.vendor_name,
           inv.category::text, inv.amount, inv.tax_included, inv.description,
           inv.memo, inv.status::text
    FROM   public.invoices inv
    WHERE  inv.id = id_input;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_invoice_secure(text, uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_invoice_secure(text, uuid)
  TO anon, authenticated, service_role;


-- ============================================================
-- 事後確認（CREATE/GRANT 後・メタ/権限のみ・実データは読まない）
--   ※ 実データ動作確認は 4-D-3b のフロント移行後に本番画面＋Network で行う。
-- ============================================================

-- 事後確認F：2関数の存在・SECURITY DEFINER・search_path
--   期待：2行、prosecdef=true、proconfig に search_path=public, extensions。
SELECT p.proname, p.prosecdef, p.proconfig
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_invoices_secure', 'get_invoice_secure')
ORDER  BY p.proname;

-- 事後確認G：EXECUTE 権限（anon/authenticated/service_role）
--   期待：6行（2関数 × 3ロール）。
SELECT routine_name, grantee, privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name IN ('list_invoices_secure', 'get_invoice_secure')
  AND  grantee IN ('anon', 'authenticated', 'service_role')
ORDER  BY routine_name, grantee;

-- 事後確認G-2：PUBLIC EXECUTE が無いこと
--   期待：0行（PUBLIC に EXECUTE が無い）。
--   ※ grantee は PUBLIC が大文字で返る場合があるため lower() で比較する。
SELECT routine_name, grantee, privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name IN ('list_invoices_secure', 'get_invoice_secure')
  AND  lower(grantee) = 'public'
ORDER  BY routine_name;

-- 事後確認H：★SELECT が不変（この段で REVOKE していない）★
--   期待：事前確認D と同じ（invoices に anon/authenticated の SELECT が残存）。
SELECT table_name, grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name   = 'invoices'
  AND  grantee IN ('anon', 'authenticated')
  AND  privilege_type = 'SELECT'
ORDER  BY grantee;


-- ============================================================
-- 次工程（本ファイル実行後）
--   4-D-3b：フロント移行（今回は行わない）
--     - admin-app.html:545 pageInvoices active   → list_invoices_secure(exclude_status='rejected', limit=200)
--     - admin-app.html:581 pageInvoices rejected  → list_invoices_secure(statuses=['rejected'], limit=200)
--     - admin-app.html:615 openInvoiceModal       → get_invoice_secure（.single() は使わず data?.[0]）
--     - genka-app.html:698 loadInvoices           → list_invoices_secure(statuses=['confirmed','posted'], from, to)
--     - genka-app.html:760 editInvoice            → get_invoice_secure（.single() は使わず data?.[0]）
--     - genka-app.html:847 loadData 集計          → list_invoices_secure(statuses=['confirmed','posted'], from, to, site_id||null)
--     - token/error ガードを追加（admin=currentUser?.session_token / genka=gCurrentUser?.session_token）。
--       ※ genka loadData(847) は既存 token を再利用。他4関数は token ガードを新規追加。
--     → PR → merge → 本番反映確認（Network で RPC 経由・invoices?select= が出ないこと）
--   4-D-3c：本番で RPC 経由を確認した後に、invoices の anon/authenticated
--     直接 SELECT を REVOKE（別ファイル・別段階）。
--
-- 【停止条件（本ファイル実行時）】
--   - 事前確認Bで invoice_date が date でない / amount が仮定と違う /
--     tax_included が boolean でない / その他実型が仮採用と異なる
--     → CREATE 前に RETURNS TABLE を修正、または停止・報告。
--   - 事前確認Cで同名関数が既存（0行でない）→ 停止・報告。
--   - 事前確認Dで anon/authenticated の SELECT が無い → 前提崩れとして停止・報告。
--   - 事後確認F/G が期待（2行/6行・prosecdef=true）にならない → 停止・報告。
--   - 事後確認G-2で PUBLIC EXECUTE が検出される → 停止・報告。
--   - 事後確認Hで SELECT が消えている（REVOKE していないのに変化）→ 停止・報告。
-- ============================================================
