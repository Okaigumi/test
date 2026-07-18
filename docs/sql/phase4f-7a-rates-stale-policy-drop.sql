-- ============================================================
-- Phase 4-F-7-a：rates stale policy cleanup
--   unit_rates / employee_rates の stale permissive policy 6本を DROP
-- ============================================================
-- 【実行ステータス】STATUS: NOT EXECUTED
--
-- 【実行方法（重要）】
--   - 実行先：Supabase SQL Editor（手動実行のみ）
--   - Supabase CLI / psql では実行しない。
--   - 手順：PRE-CHECK（C-1〜C-8 を1つずつ・read-only）→ 全合格を確認
--           → EXECUTION BODY（BEGIN〜COMMIT を1回だけ選択実行）
--           → POST-CHECK（P-1〜P-5・read-only）→ smoke checklist。
--   - ★BODY は1回のみ実行。再実行禁止★
--     （2回目は GUARD G-2 が対象 policy 0本を検知して fail-closed で停止する）
--
-- 【変更内容】
--   - DB変更文は DROP POLICY 6文のみ。
--   - GRANT / REVOKE / ALTER / CREATE FUNCTION / CREATE POLICY /
--     INSERT / UPDATE / DELETE / TRUNCATE は一切含まない。
--
-- 【対象 policy（実DB確定済み定義・2026-07-19 実測）】
--   public.unit_rates（3本）
--     - ur_read   PERMISSIVE roles={public} SELECT qual=true       with_check=NULL
--     - ur_write  PERMISSIVE roles={public} INSERT qual=NULL       with_check=true
--     - ur_update PERMISSIVE roles={public} UPDATE qual=true       with_check=NULL
--   public.employee_rates（3本）
--     - er_read   PERMISSIVE roles={public} SELECT qual=true       with_check=NULL
--     - er_write  PERMISSIVE roles={public} INSERT qual=NULL       with_check=true
--     - er_update PERMISSIVE roles={public} UPDATE qual=true       with_check=NULL
--
-- 【安全性の根拠（policy 6本を削除しても動作影響なし）】
--   1. 両テーブルとも anon / authenticated / PUBLIC の SELECT / INSERT /
--      UPDATE / DELETE 権限はすべて REVOKE 済み（table ACL は postgres /
--      service_role のみ）。policy が許可していても権限段階で遮断済みのため、
--      現存 policy 6本は「効果を持たない stale permissive policy」。
--   2. rates 系 RPC 4本はすべて SECURITY DEFINER・owner=postgres。
--      postgres は両テーブルの owner であり FORCE RLS=false のため、
--      owner には RLS が適用されない → policy の有無は RPC の read/write に
--      一切影響しない。
--        - list_unit_rates_secure(text)
--        - list_employee_rates_secure(text)
--        - upsert_unit_rate_secure(text, text, text, integer, text)
--        - upsert_employee_rate_secure(text, uuid, integer, date)
--   3. frontend（index.html / admin-app.html / genka-app.html）に
--      unit_rates / employee_rates への direct access（.from()）は 0件。
--      すべて上記 secure RPC 経由。
--
-- 【schema 基準（実DB確定済み）】
--   - public schema policy total = 23
--   - 対象 policy total          =  6（ur_* 3本 + er_* 3本）
--   - 対象外 policy total        = 17（本工程で不変であること）
--
-- 【STOP 条件（PRE-CHECK / GUARD のいずれかが不一致なら実行せず停止・報告）】
--   - policy 名・cmd・roles・permissive・qual・with_check の実DB差異
--   - table owner が postgres でない / RLS 無効 / FORCE RLS=true
--   - anon / authenticated / PUBLIC の table 権限残存
--   - RPC の不存在・overload・SECURITY DEFINER でない・owner 不一致
--   - RPC の PUBLIC EXECUTE=true / anon・authenticated EXECUTE 欠落
--   - public schema policy total が 23 でない（対象外への波及リスク）
-- ============================================================


-- ============================================================
-- PRE-CHECK（read-only・BODY 実行前に C-1 から順に1つずつ実行）
--   すべて SELECT のみ。DB 状態は変更しない。
-- ============================================================

-- C-1. policy 総数基準
--   期待：public_total=23 / target_total=6 / others_total=17
SELECT count(*)                                                                   AS public_total,
       count(*) FILTER (WHERE tablename IN ('unit_rates','employee_rates'))       AS target_total,
       count(*) FILTER (WHERE tablename NOT IN ('unit_rates','employee_rates'))   AS others_total
FROM   pg_policies
WHERE  schemaname = 'public';

-- C-2. 対象 policy の全定義列挙
--   期待：ちょうど6行。ヘッダー記載の確定定義
--         （permissive / roles / cmd / qual / with_check）と完全一致。
SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename IN ('unit_rates','employee_rates')
ORDER  BY tablename, policyname;

-- C-3. 期待集合との差分判定
--   期待：0行（MISSING_IN_DB / UNEXPECTED_IN_DB / DEF_MISMATCH のいずれも無し）
WITH expected(tablename, policyname, permissive, roles_text, cmd, qual, with_check) AS (
  VALUES
    ('unit_rates',     'ur_read',   'PERMISSIVE', '{public}', 'SELECT', 'true', NULL),
    ('unit_rates',     'ur_write',  'PERMISSIVE', '{public}', 'INSERT', NULL,   'true'),
    ('unit_rates',     'ur_update', 'PERMISSIVE', '{public}', 'UPDATE', 'true', NULL),
    ('employee_rates', 'er_read',   'PERMISSIVE', '{public}', 'SELECT', 'true', NULL),
    ('employee_rates', 'er_write',  'PERMISSIVE', '{public}', 'INSERT', NULL,   'true'),
    ('employee_rates', 'er_update', 'PERMISSIVE', '{public}', 'UPDATE', 'true', NULL)
),
actual AS (
  SELECT tablename, policyname, permissive, roles::text AS roles_text, cmd, qual, with_check
  FROM   pg_policies
  WHERE  schemaname = 'public'
    AND  tablename IN ('unit_rates','employee_rates')
)
SELECT COALESCE(e.tablename, a.tablename)   AS tablename,
       COALESCE(e.policyname, a.policyname) AS policyname,
       CASE
         WHEN a.policyname IS NULL THEN 'MISSING_IN_DB'
         WHEN e.policyname IS NULL THEN 'UNEXPECTED_IN_DB'
         ELSE 'DEF_MISMATCH'
       END AS diff_kind
FROM   expected e
FULL   OUTER JOIN actual a
       ON  a.tablename  = e.tablename
       AND a.policyname = e.policyname
       AND a.permissive = e.permissive
       AND a.roles_text = e.roles_text
       AND a.cmd        = e.cmd
       AND a.qual       IS NOT DISTINCT FROM e.qual
       AND a.with_check IS NOT DISTINCT FROM e.with_check
WHERE  e.policyname IS NULL OR a.policyname IS NULL;

-- C-4. テーブル存在・owner・RLS・FORCE RLS
--   期待：2行。owner=postgres / rls_enabled=true / rls_forced=false。
SELECT c.relname                    AS table_name,
       pg_get_userbyid(c.relowner)  AS owner,
       c.relrowsecurity             AS rls_enabled,
       c.relforcerowsecurity        AS rls_forced,
       c.relacl::text               AS table_acl
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'public'
  AND  c.relkind = 'r'
  AND  c.relname IN ('unit_rates','employee_rates');

-- C-5a. anon / authenticated / PUBLIC の明示 table 権限
--   期待：0行（SELECT / INSERT / UPDATE / DELETE いずれも無し）
SELECT table_name, grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name IN ('unit_rates','employee_rates')
  AND  grantee IN ('anon','authenticated','PUBLIC')
  AND  privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
ORDER  BY table_name, grantee, privilege_type;

-- C-5b. anon / authenticated の実効 table 権限（PUBLIC 経由の継承も含む）
--   期待：全列 false（16判定すべて false）
SELECT t.tbl                                                     AS table_name,
       r.role_name,
       has_table_privilege(r.role_name, t.tbl, 'SELECT')         AS can_select,
       has_table_privilege(r.role_name, t.tbl, 'INSERT')         AS can_insert,
       has_table_privilege(r.role_name, t.tbl, 'UPDATE')         AS can_update,
       has_table_privilege(r.role_name, t.tbl, 'DELETE')         AS can_delete
FROM   (VALUES ('public.unit_rates'), ('public.employee_rates')) t(tbl)
CROSS  JOIN (VALUES ('anon'), ('authenticated')) r(role_name)
ORDER  BY t.tbl, r.role_name;

-- C-6. RPC 4本の存在・owner・SECURITY DEFINER・overload
--   期待：ちょうど4行（overload なし）。prosecdef=true / owner=postgres /
--         search_path=public, extensions。
SELECT p.oid::regprocedure           AS signature,
       pg_get_function_result(p.oid) AS result_type,
       pg_get_userbyid(p.proowner)   AS owner,
       p.prosecdef                   AS security_definer,
       p.proconfig                   AS config
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_unit_rates_secure','list_employee_rates_secure',
                     'upsert_unit_rate_secure','upsert_employee_rate_secure')
ORDER  BY p.proname, p.oid;

-- C-7. RPC の PUBLIC EXECUTE が無いこと
--   期待：0行（aclexplode に grantee=0（PUBLIC）のエントリが無い。
--         proacl IS NULL（=デフォルト PUBLIC 実行可）も無い）
SELECT p.proname,
       CASE WHEN p.proacl IS NULL THEN 'PROACL_IS_NULL(default: PUBLIC exec)'
            ELSE 'PUBLIC_EXECUTE_ENTRY' END AS problem
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_unit_rates_secure','list_employee_rates_secure',
                     'upsert_unit_rate_secure','upsert_employee_rate_secure')
  AND  ( p.proacl IS NULL
         OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0) );

-- C-8. anon / authenticated の EXECUTE
--   期待：8行すべて can_execute=true（4関数 × 2ロール）
SELECT f.sig                                        AS signature,
       r.role_name,
       has_function_privilege(r.role_name, f.sig, 'EXECUTE') AS can_execute
FROM   (VALUES
         ('public.list_unit_rates_secure(text)'),
         ('public.list_employee_rates_secure(text)'),
         ('public.upsert_unit_rate_secure(text, text, text, integer, text)'),
         ('public.upsert_employee_rate_secure(text, uuid, integer, date)')
       ) f(sig)
CROSS  JOIN (VALUES ('anon'), ('authenticated')) r(role_name)
ORDER  BY f.sig, r.role_name;


-- ============================================================
-- EXECUTION BODY（★1回のみ実行・再実行禁止★）
--   BEGIN〜COMMIT を1回だけ選択して実行する。
--   fail-closed GUARD（read-only DO block）が1つでも不一致を検知したら
--   RAISE EXCEPTION で transaction 全体が abort する（DB 無変更）。
--   DB 変更文は DROP POLICY 6文のみ。IF EXISTS は意図的に付けない
--   （想定外の不存在は GUARD / DROP の失敗として検知する）。
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_count integer;
  v_rec   record;
BEGIN
  -- G-1. public schema policy total = 23
  SELECT count(*) INTO v_count
  FROM   pg_policies
  WHERE  schemaname = 'public';
  IF v_count <> 23 THEN
    RAISE EXCEPTION 'GUARD G-1 failed: public policy total expected 23, got %', v_count;
  END IF;

  -- G-2. 対象 policy total = 6
  SELECT count(*) INTO v_count
  FROM   pg_policies
  WHERE  schemaname = 'public'
    AND  tablename IN ('unit_rates','employee_rates');
  IF v_count <> 6 THEN
    RAISE EXCEPTION 'GUARD G-2 failed: target policy total expected 6, got % (already dropped? BODY must run only once)', v_count;
  END IF;

  -- G-3. 対象外 policy total = 17
  SELECT count(*) INTO v_count
  FROM   pg_policies
  WHERE  schemaname = 'public'
    AND  tablename NOT IN ('unit_rates','employee_rates');
  IF v_count <> 17 THEN
    RAISE EXCEPTION 'GUARD G-3 failed: non-target policy total expected 17, got %', v_count;
  END IF;

  -- G-4. 対象 policy 集合・定義の完全一致（6本すべて）
  SELECT count(*) INTO v_count
  FROM   pg_policies p
  JOIN   (VALUES
           ('unit_rates',     'ur_read',   'PERMISSIVE', '{public}', 'SELECT', 'true', NULL),
           ('unit_rates',     'ur_write',  'PERMISSIVE', '{public}', 'INSERT', NULL,   'true'),
           ('unit_rates',     'ur_update', 'PERMISSIVE', '{public}', 'UPDATE', 'true', NULL),
           ('employee_rates', 'er_read',   'PERMISSIVE', '{public}', 'SELECT', 'true', NULL),
           ('employee_rates', 'er_write',  'PERMISSIVE', '{public}', 'INSERT', NULL,   'true'),
           ('employee_rates', 'er_update', 'PERMISSIVE', '{public}', 'UPDATE', 'true', NULL)
         ) e(tablename, policyname, permissive, roles_text, cmd, qual, with_check)
    ON  p.tablename    = e.tablename
    AND p.policyname   = e.policyname
    AND p.permissive   = e.permissive
    AND p.roles::text  = e.roles_text
    AND p.cmd          = e.cmd
    AND p.qual         IS NOT DISTINCT FROM e.qual
    AND p.with_check   IS NOT DISTINCT FROM e.with_check
  WHERE  p.schemaname = 'public';
  IF v_count <> 6 THEN
    RAISE EXCEPTION 'GUARD G-4 failed: exact policy definition match expected 6, got %', v_count;
  END IF;

  -- G-5. table owner=postgres / RLS enabled=true / FORCE RLS=false（2テーブル）
  SELECT count(*) INTO v_count
  FROM   pg_class c
  JOIN   pg_namespace n ON n.oid = c.relnamespace
  WHERE  n.nspname = 'public'
    AND  c.relkind = 'r'
    AND  c.relname IN ('unit_rates','employee_rates')
    AND  pg_get_userbyid(c.relowner) = 'postgres'
    AND  c.relrowsecurity  = true
    AND  c.relforcerowsecurity = false;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'GUARD G-5 failed: table owner/RLS/FORCE baseline expected 2 tables, got %', v_count;
  END IF;

  -- G-6a. anon / authenticated の実効 table 権限がすべて false（PUBLIC 継承含む）
  FOR v_rec IN
    SELECT t.tbl, r.role_name, pr.priv
    FROM   (VALUES ('public.unit_rates'), ('public.employee_rates')) t(tbl)
    CROSS  JOIN (VALUES ('anon'), ('authenticated')) r(role_name)
    CROSS  JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) pr(priv)
  LOOP
    IF has_table_privilege(v_rec.role_name, v_rec.tbl, v_rec.priv) THEN
      RAISE EXCEPTION 'GUARD G-6a failed: % has % on %', v_rec.role_name, v_rec.priv, v_rec.tbl;
    END IF;
  END LOOP;

  -- G-6b. PUBLIC への明示 table 権限が無い
  SELECT count(*) INTO v_count
  FROM   information_schema.role_table_grants
  WHERE  table_schema = 'public'
    AND  table_name IN ('unit_rates','employee_rates')
    AND  grantee = 'PUBLIC'
    AND  privilege_type IN ('SELECT','INSERT','UPDATE','DELETE');
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-6b failed: PUBLIC table grants expected 0, got %', v_count;
  END IF;

  -- G-7. RPC 4本の存在・overload なし・SECURITY DEFINER・owner=postgres
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.proname IN ('list_unit_rates_secure','list_employee_rates_secure',
                       'upsert_unit_rate_secure','upsert_employee_rate_secure');
  IF v_count <> 4 THEN
    RAISE EXCEPTION 'GUARD G-7 failed: expected exactly 4 RPCs (no overload), got %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.proname IN ('list_unit_rates_secure','list_employee_rates_secure',
                       'upsert_unit_rate_secure','upsert_employee_rate_secure')
    AND  p.prosecdef = true
    AND  pg_get_userbyid(p.proowner) = 'postgres';
  IF v_count <> 4 THEN
    RAISE EXCEPTION 'GUARD G-7 failed: SECURITY DEFINER + owner=postgres expected 4, got %', v_count;
  END IF;

  -- G-8a. RPC の PUBLIC EXECUTE が無い（proacl NULL も不可）
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.proname IN ('list_unit_rates_secure','list_employee_rates_secure',
                       'upsert_unit_rate_secure','upsert_employee_rate_secure')
    AND  ( p.proacl IS NULL
           OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0) );
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-8a failed: PUBLIC EXECUTE (or default acl) found on % RPC(s)', v_count;
  END IF;

  -- G-8b. anon / authenticated の EXECUTE がある（4関数 × 2ロール）
  FOR v_rec IN
    SELECT f.sig, r.role_name
    FROM   (VALUES
             ('public.list_unit_rates_secure(text)'),
             ('public.list_employee_rates_secure(text)'),
             ('public.upsert_unit_rate_secure(text, text, text, integer, text)'),
             ('public.upsert_employee_rate_secure(text, uuid, integer, date)')
           ) f(sig)
    CROSS  JOIN (VALUES ('anon'), ('authenticated')) r(role_name)
  LOOP
    IF NOT has_function_privilege(v_rec.role_name, v_rec.sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'GUARD G-8b failed: % lacks EXECUTE on %', v_rec.role_name, v_rec.sig;
    END IF;
  END LOOP;

  RAISE NOTICE 'GUARD OK: baseline matches; proceeding to DROP 6 stale policies on unit_rates / employee_rates';
END
$$;

DROP POLICY ur_read
  ON public.unit_rates;

DROP POLICY ur_write
  ON public.unit_rates;

DROP POLICY ur_update
  ON public.unit_rates;

DROP POLICY er_read
  ON public.employee_rates;

DROP POLICY er_write
  ON public.employee_rates;

DROP POLICY er_update
  ON public.employee_rates;

COMMIT;


-- ============================================================
-- POST-CHECK（read-only・COMMIT 後に P-1 から順に実行）
-- ============================================================

-- P-1. 対象テーブルの policy が 0 本
--   期待：0行
SELECT tablename, policyname
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename IN ('unit_rates','employee_rates');

-- P-2. policy 総数：public_total=17 / target_total=0 / others_total=17
--   （対象外 17 本が不変であること）
SELECT count(*)                                                                   AS public_total,
       count(*) FILTER (WHERE tablename IN ('unit_rates','employee_rates'))       AS target_total,
       count(*) FILTER (WHERE tablename NOT IN ('unit_rates','employee_rates'))   AS others_total
FROM   pg_policies
WHERE  schemaname = 'public';

-- P-3. table owner / RLS / FORCE RLS / table ACL 不変
--   期待：2行。owner=postgres / rls_enabled=true / rls_forced=false /
--         relacl は postgres / service_role のみ（DROP POLICY は ACL を変えない）
SELECT c.relname                    AS table_name,
       pg_get_userbyid(c.relowner)  AS owner,
       c.relrowsecurity             AS rls_enabled,
       c.relforcerowsecurity        AS rls_forced,
       c.relacl::text               AS table_acl
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'public'
  AND  c.relkind = 'r'
  AND  c.relname IN ('unit_rates','employee_rates');

-- P-4. RPC 属性不変
--   期待：4行（overload なし）。prosecdef=true / owner=postgres /
--         proacl に PUBLIC エントリなし。
SELECT p.oid::regprocedure           AS signature,
       pg_get_userbyid(p.proowner)   AS owner,
       p.prosecdef                   AS security_definer,
       p.proacl                      AS execute_acl
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_unit_rates_secure','list_employee_rates_secure',
                     'upsert_unit_rate_secure','upsert_employee_rate_secure')
ORDER  BY p.proname, p.oid;

-- P-5. anon / authenticated の EXECUTE 不変
--   期待：8行すべて can_execute=true（4関数 × 2ロール）
SELECT f.sig                                        AS signature,
       r.role_name,
       has_function_privilege(r.role_name, f.sig, 'EXECUTE') AS can_execute
FROM   (VALUES
         ('public.list_unit_rates_secure(text)'),
         ('public.list_employee_rates_secure(text)'),
         ('public.upsert_unit_rate_secure(text, text, text, integer, text)'),
         ('public.upsert_employee_rate_secure(text, uuid, integer, date)')
       ) f(sig)
CROSS  JOIN (VALUES ('anon'), ('authenticated')) r(role_name)
ORDER  BY f.sig, r.role_name;


-- ============================================================
-- EMERGENCY ROLLBACK（通常は実行しない・コメントのまま保持）
--   実DB確定定義（2026-07-19 実測）どおりの完全復元。
--   実行する場合は該当 CREATE POLICY だけを選択して1文ずつ実行し、
--   実行後に C-2 / C-3 相当で定義一致を必ず確認すること。
-- ============================================================
-- CREATE POLICY ur_read
-- ON public.unit_rates
-- AS PERMISSIVE
-- FOR SELECT
-- TO public
-- USING (true);
--
-- CREATE POLICY ur_write
-- ON public.unit_rates
-- AS PERMISSIVE
-- FOR INSERT
-- TO public
-- WITH CHECK (true);
--
-- CREATE POLICY ur_update
-- ON public.unit_rates
-- AS PERMISSIVE
-- FOR UPDATE
-- TO public
-- USING (true);
--
-- CREATE POLICY er_read
-- ON public.employee_rates
-- AS PERMISSIVE
-- FOR SELECT
-- TO public
-- USING (true);
--
-- CREATE POLICY er_write
-- ON public.employee_rates
-- AS PERMISSIVE
-- FOR INSERT
-- TO public
-- WITH CHECK (true);
--
-- CREATE POLICY er_update
-- ON public.employee_rates
-- AS PERMISSIVE
-- FOR UPDATE
-- TO public
-- USING (true);


-- ============================================================
-- SMOKE CHECKLIST（DB 実行後・本番でユーザーが実施）
--   実施順の推奨：S-1 → S-2 → S-4（完全無変化）→ S-3（updated_at のみ変化）
--
--   [S-1] admin 画面：単価管理タブで unit_rates / employee_rates 一覧表示
--         - list_unit_rates_secure / list_employee_rates_secure が HTTP 200
--         - 一覧が従来どおり表示される
--   [S-2] genka 画面：起動（startApp）
--         - 同 2 RPC が HTTP 200・原価表示が従来どおり
--   [S-4] admin 画面：employee rate 既存値の同値保存
--         - 既存 1件（employee_id × effective_from）の daily_rate を
--           現在値のまま保存 → upsert_employee_rate_secure HTTP 200
--         - ON CONFLICT で daily_rate=同値 UPDATE。employee_rates に
--           updated_at 列は無く、完全に無変化（恒久的な業務データ変更なし）
--   [S-3] admin 画面：unit rate 既存値の同値保存
--         - 既存 1件（category × name）の unit_price / unit を現在値のまま
--           保存 → upsert_unit_rate_secure HTTP 200
--         - ★注意：ON CONFLICT の DO UPDATE で updated_at のみ now() に
--           更新される（unit_price / unit の業務値は不変）。
--           updated_at の変化も避けたい場合は S-3 を省略し、S-4 と
--           一覧表示（S-1 / S-2）で代替してよい。
--   [共通確認]
--         - 保存前後で list RPC の件数が不変（upsert が INSERT 側に
--           分岐していないこと）
--         - Network に想定外の 401 / 403 が無い
--         - Console に赤エラーが無い
-- ============================================================
