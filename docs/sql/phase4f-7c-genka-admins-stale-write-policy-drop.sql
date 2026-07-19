-- ============================================================
-- Phase 4-F-7-c-2：genka_admins stale write policy cleanup
--   genka_admins の stale write policy 3本を DROP
--   （read policy 2本＝employees_read_all / ga_read は現役のため必ず保持）
-- ============================================================
-- 【実行ステータス】STATUS: EXECUTED 2026-07-19
--   - preparation date：2026-07-19（準備PR #149・merge `823fdd1`）
--   - execution date  ：2026-07-19（Supabase SQL Editor 手動実行・Supabase CLI / psql 未使用）
--   - Result          ：Success. No rows returned
--   - 実行内容：EXECUTION BODY（GUARD G-1〜G-10b＋DROP POLICY 3文・同一transaction）を
--     1回だけ実行。再実行なし。★GUARD＋BODY は今後も再実行禁止★
--     （再実行しても G-1/G-2 が総数2への変化を検知して fail-closed で停止する）
--   - PRE-CHECK 全合格（C-1〜C-6・2026-07-19）：
--       C-1 public_total=5 / drop_targets=3 / keep_targets=2 / other=0
--       C-2 identity 系5本すべて実測定義と完全一致・同名重複なし
--       C-3 genka_admins owner=postgres・RLS=true・FORCE=false・
--           ACL=postgres/service_role のみ・anon/authenticated I/U/D すべて false
--       C-4 列権限：anon/authenticated は SELECT のみ（id/name/is_active）・
--           pin/created_at 非公開・全列 INSERT/UPDATE 不可・PUBLIC 列 grant なし
--       C-5 identity 関連9関数：owner=postgres・SECURITY DEFINER・search_path固定・
--           PUBLIC EXECUTE=false・overloadなし・外部8関数 EXECUTE=true・
--           _verify_management_session のみ非公開
--       C-6 全5 policy guard_condition_met=true（write系3本 stale no-op 確定・
--           read系2本 現役確定）
--   - BODY で削除した policy（3本のみ）：
--       genka_admins：anon_can_update_genka_admins / ga_update / ga_write
--   - ★意図的保持（削除していない・現役2本）★：
--       employees.employees_read_all / genka_admins.ga_read
--       （ログイン前名前一覧を支える現役 policy。未整理残ではない）
--   - POST-CHECK 全合格（P-1〜P-6・2026-07-19）：
--       P-1 public_total=2 / drop_targets=0 / keep_targets=2 / other=0
--       P-2 残存は employees_read_all / ga_read の2本のみ
--           （PERMISSIVE・roles={public}・SELECT・qual=true・with_check=NULL・重複なし）
--       P-3 genka_admins の owner・RLS・FORCE・ACL・I/U/D なし 不変
--       P-4 列権限不変（id/name/is_active SELECT のみ・pin/created_at 非公開）
--       P-5 9関数の owner・SECURITY DEFINER・search_path・PUBLIC EXECUTE なし・
--           overload なし 不変
--       P-6 EXECUTE 不変（外部8関数 true・_verify は false）
--   - 本番 smoke（2026-07-19・全合格）：
--       3画面（従業員・管理コンソール・原価管理）とも：ログアウト状態の名前一覧
--       表示正常 → PIN ログイン → ログアウト → 再ログイン すべて正常・
--       Console 赤エラーなし・Network 応答に PIN なし
--       管理者同値保存：初回は既存 session の期限切れで update_genka_admin_secure
--       HTTP 400（Invalid or expired session・Preserve log ON で過去ログ残存）。
--       ★policy 削除障害ではない★。再ログイン後に同値保存成功・
--       direct REST write なし・名前/有効状態不変。
--       ★未実施の明記★：新規管理者作成（create_genka_admin_secure）は実データ
--       変更を伴うため意図的に未実施。関数属性・ACL・EXECUTE 証拠
--       （C-5/P-5/P-6・SECURITY DEFINER owner bypass により policy 非依存）で補完。
--   - 記録先：docs/db-migrations.md「2026-07-19 Phase 4-F-7-c」
--
-- 【実行方法（重要）】
--   - 実行先：Supabase SQL Editor（手動実行のみ）
--   - Supabase CLI / psql では実行しない。
--   - 手順：PRE-CHECK（C-1〜C-6 を1つずつ・read-only）→ 全合格を確認
--           → EXECUTION BODY（BEGIN〜COMMIT を1回だけ選択実行）
--           → POST-CHECK（P-1〜P-6・read-only）→ smoke checklist。
--   - ★BODY は1回のみ実行。再実行禁止★
--     （2回目は GUARD G-1/G-2 が変化後の状態を検知して fail-closed で停止する）
--
-- 【変更内容】
--   - DB変更文は DROP POLICY 3文のみ。
--   - GRANT / REVOKE / ALTER TABLE / CREATE OR REPLACE FUNCTION / DROP FUNCTION /
--     CREATE POLICY / INSERT / UPDATE / DELETE / TRUNCATE は一切含まない。
--
-- 【対象 policy（削除3本・2026-07-19 read-only 実測 I-1〜I-6 で stale 確定）】
--   public.genka_admins：
--     - anon_can_update_genka_admins  PERMISSIVE roles={anon}   UPDATE qual=true  with_check=true
--     - ga_update                     PERMISSIVE roles={public} UPDATE qual=true  with_check=NULL
--     - ga_write                      PERMISSIVE roles={public} INSERT qual=NULL  with_check=true
--   stale 確定根拠（I-6）：3本とも roles に想定外ロールなし・anon/authenticated の
--   table INSERT/UPDATE 実効権限 false・write 列 grant 0 → 権限段階で遮断済みの no-op。
--
-- 【保持 policy（今回削除しない・現役2本）】
--   public.employees    ：employees_read_all  PERMISSIVE roles={public} SELECT qual=true with_check=NULL
--   public.genka_admins ：ga_read             PERMISSIVE roles={public} SELECT qual=true with_check=NULL
--   現役根拠（I-3/I-4/I-6）：SELECT 列 grant（employees 7列×2ロール=14 /
--   genka_admins 3列×2ロール=6）と組み合わせて、3画面のログイン前
--   名前一覧 direct SELECT（index.html:895 / admin-app.html:291 / genka-app.html:480）を
--   支えている。★この2本は絶対に DROP しない★（削除すると3画面ログイン不能）。
--
-- 【変更しないもの】
--   - employees_read_all / ga_read（現役 read policy）
--   - RLS 有効/無効・FORCE RLS・table ACL・列 grant・RPC 定義・EXECUTE 権限
--   - frontend / Vercel / Supabase 設定
--
-- 【安全性の根拠（write 3本を削除しても動作影響なし）】
--   1. genka_admins の anon / authenticated の table-level INSERT / UPDATE / DELETE は
--      false・write 列 grant 0（I-2/I-3/I-4）。policy が許可していても権限段階で
--      遮断済みのため、3本は「効果を持たない stale permissive policy」。
--   2. genka_admins への write は create_genka_admin_secure / update_genka_admin_secure
--      （SECURITY DEFINER・owner=postgres・I-5）経由のみ。FORCE RLS=false のため
--      owner には RLS が適用されず、policy の有無は RPC の write に影響しない。
--   3. frontend に genka_admins への direct write（.from().update/insert）は 0件。
--   4. employees 側の対になる employees_update_public は 2026-05-30 に DROP 済みの
--      先例あり（db-migrations.md 2026-05-30 セクション）。
--
-- 【schema 基準（実DB確認済み・I-1）】
--   - public schema policy total = 5
--   - 削除対象 = 3（genka_admins write系）
--   - 保持対象 = 2（employees_read_all / ga_read）→ 実行後はこの2本だけが残る
--
-- 【STOP 条件（PRE-CHECK / GUARD のいずれかが不一致なら実行せず停止・報告）】
--   - policy 総数≠5／削除3本・保持2本の定義（roles/cmd/qual/with_check）が実測値と不一致
--   - 想定外 policy の存在／同名 policy 重複
--   - genka_admins の owner≠postgres／RLS 無効／FORCE RLS=true
--   - anon / authenticated に table write 権限または write 列 grant が存在
--   - identity 関連9関数の属性不一致（SECURITY DEFINER / owner / overload /
--     PUBLIC EXECUTE / 外部8関数の EXECUTE 欠落 / _verify の非公開が崩れている）
--   - ga_read を支える SELECT 列 grant の欠落／pin 列の公開
-- ============================================================


-- ============================================================
-- PRE-CHECK（read-only・BODY 実行前に C-1 から順に1つずつ実行）
--   すべて SELECT のみ。DB 状態は変更しない。
-- ============================================================

-- C-1. policy 総数と identity 系の内訳
--   期待：public_total=5 / drop_targets=3 / keep_targets=2 / other=0
SELECT count(*) AS public_total,
       count(*) FILTER (WHERE tablename='genka_admins'
                          AND policyname IN ('anon_can_update_genka_admins','ga_update','ga_write')) AS drop_targets,
       count(*) FILTER (WHERE (tablename='employees'    AND policyname='employees_read_all')
                           OR (tablename='genka_admins' AND policyname='ga_read'))                   AS keep_targets,
       count(*) FILTER (WHERE NOT ( (tablename='genka_admins'
                                     AND policyname IN ('anon_can_update_genka_admins','ga_update','ga_write','ga_read'))
                                 OR (tablename='employees' AND policyname='employees_read_all') ))   AS other_policies
FROM   pg_policies
WHERE  schemaname = 'public';

-- C-2. 5本の完全定義列挙と実測期待値との差分（0行期待）
--   同名重複も detect（same_name_count>1 なら異常）
WITH expected(tablename, policyname, permissive, roles_text, cmd, qual, with_check) AS (
  VALUES
    ('employees',    'employees_read_all',           'PERMISSIVE', '{public}', 'SELECT', 'true', NULL),
    ('genka_admins', 'ga_read',                      'PERMISSIVE', '{public}', 'SELECT', 'true', NULL),
    ('genka_admins', 'ga_write',                     'PERMISSIVE', '{public}', 'INSERT', NULL,   'true'),
    ('genka_admins', 'ga_update',                    'PERMISSIVE', '{public}', 'UPDATE', 'true', NULL),
    ('genka_admins', 'anon_can_update_genka_admins', 'PERMISSIVE', '{anon}',   'UPDATE', 'true', 'true')
),
actual AS (
  SELECT tablename, policyname, permissive, roles::text AS roles_text, cmd, qual, with_check,
         count(*) OVER (PARTITION BY tablename, policyname) AS same_name_count
  FROM   pg_policies
  WHERE  schemaname = 'public'
)
SELECT COALESCE(e.tablename, a.tablename)   AS tablename,
       COALESCE(e.policyname, a.policyname) AS policyname,
       CASE WHEN a.policyname IS NULL THEN 'MISSING_IN_DB'
            WHEN e.policyname IS NULL THEN 'UNEXPECTED_IN_DB'
            WHEN a.same_name_count > 1 THEN 'DUPLICATE_NAME'
            ELSE 'DEF_MISMATCH' END AS diff_kind
FROM   expected e
FULL   OUTER JOIN actual a
       ON  a.tablename  = e.tablename
       AND a.policyname = e.policyname
       AND a.permissive = e.permissive
       AND a.roles_text = e.roles_text
       AND a.cmd        = e.cmd
       AND a.qual       IS NOT DISTINCT FROM e.qual
       AND a.with_check IS NOT DISTINCT FROM e.with_check
WHERE  e.policyname IS NULL OR a.policyname IS NULL OR a.same_name_count > 1;

-- C-3. 両テーブルの owner / RLS / FORCE / ACL と table-level write 実効権限
--   期待：2行。owner=postgres / rls=true / forced=false /
--         ACL は postgres・service_role のみ / write 6判定すべて false。
SELECT c.relname AS table_name,
       pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced,
       c.relacl::text AS table_acl,
       has_table_privilege('anon',          c.oid, 'INSERT') AS anon_insert,
       has_table_privilege('anon',          c.oid, 'UPDATE') AS anon_update,
       has_table_privilege('anon',          c.oid, 'DELETE') AS anon_delete,
       has_table_privilege('authenticated', c.oid, 'INSERT') AS auth_insert,
       has_table_privilege('authenticated', c.oid, 'UPDATE') AS auth_update,
       has_table_privilege('authenticated', c.oid, 'DELETE') AS auth_delete
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'public'
  AND  c.relkind = 'r'
  AND  c.relname IN ('employees','genka_admins')
ORDER  BY c.relname;

-- C-4. 列 grant：SELECT のみ・pin 非公開・write 列 grant 0
--   期待：anon/authenticated × SELECT のみ
--         （employees: can_admin,can_genka,company_id,id,is_active,name,role /
--           genka_admins: id,is_active,name）。pin なし。INSERT/UPDATE 行なし。
SELECT table_name, grantee, privilege_type,
       string_agg(column_name, ',' ORDER BY column_name) AS columns
FROM   information_schema.column_privileges
WHERE  table_schema = 'public'
  AND  table_name IN ('employees','genka_admins')
  AND  grantee IN ('anon','authenticated','PUBLIC','service_role')
GROUP  BY table_name, grantee, privilege_type
ORDER  BY table_name, grantee, privilege_type;

-- C-5. identity 関連9関数の属性
--   期待：9行・overload なし・SECURITY DEFINER=true・owner=postgres・
--         search_path=public, extensions・has_public_execute=false・
--         外部8関数は anon_exec/auth_exec=true・_verify_management_session のみ false。
SELECT p.oid::regprocedure AS signature,
       pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef AS security_definer,
       p.proconfig AS config,
       (p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)) AS has_public_execute,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       count(*) OVER (PARTITION BY p.proname) AS overload_count
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('create_admin_session','create_employee_session',
                     'revoke_admin_session','revoke_employee_session',
                     '_verify_management_session',
                     'create_employee_secure','update_employee_secure',
                     'create_genka_admin_secure','update_genka_admin_secure')
ORDER  BY p.proname;

-- C-6. pin 列の実効 SELECT が false であること（両テーブル・両ロール）
--   期待：4行すべて can_select_pin=false
SELECT t.tbl AS table_name, r.role_name,
       has_column_privilege(r.role_name, 'public.'||t.tbl, 'pin', 'SELECT') AS can_select_pin
FROM   (VALUES ('employees'), ('genka_admins')) t(tbl)
CROSS  JOIN (VALUES ('anon'), ('authenticated')) r(role_name)
ORDER  BY t.tbl, r.role_name;


-- ============================================================
-- EXECUTION BODY（★1回のみ実行・再実行禁止★・現時点では未実行）
--   BEGIN〜COMMIT を1回だけ選択して実行する。
--   fail-closed GUARD（read-only DO block）が1つでも不一致を検知したら
--   RAISE EXCEPTION で transaction 全体が abort する（DB 無変更）。
--   DB 変更文は DROP POLICY 3文のみ。IF EXISTS は意図的に付けない。
--   ★employees_read_all / ga_read（現役 read policy 2本）は絶対に DROP しない★
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_count integer;
  v_rec   record;
BEGIN
  -- G-1. public schema policy total = 5
  SELECT count(*) INTO v_count FROM pg_policies WHERE schemaname = 'public';
  IF v_count <> 5 THEN
    RAISE EXCEPTION 'GUARD G-1 failed: public policy total expected 5, got %', v_count;
  END IF;

  -- G-2. 5本の完全定義一致（削除3本＋保持2本・roles/cmd/qual/with_check 厳密照合）
  SELECT count(*) INTO v_count
  FROM   pg_policies p
  JOIN   (VALUES
           ('employees',    'employees_read_all',           'PERMISSIVE', '{public}', 'SELECT', 'true', NULL),
           ('genka_admins', 'ga_read',                      'PERMISSIVE', '{public}', 'SELECT', 'true', NULL),
           ('genka_admins', 'ga_write',                     'PERMISSIVE', '{public}', 'INSERT', NULL,   'true'),
           ('genka_admins', 'ga_update',                    'PERMISSIVE', '{public}', 'UPDATE', 'true', NULL),
           ('genka_admins', 'anon_can_update_genka_admins', 'PERMISSIVE', '{anon}',   'UPDATE', 'true', 'true')
         ) e(tablename, policyname, permissive, roles_text, cmd, qual, with_check)
    ON  p.tablename   = e.tablename
    AND p.policyname  = e.policyname
    AND p.permissive  = e.permissive
    AND p.roles::text = e.roles_text
    AND p.cmd         = e.cmd
    AND p.qual        IS NOT DISTINCT FROM e.qual
    AND p.with_check  IS NOT DISTINCT FROM e.with_check
  WHERE  p.schemaname = 'public';
  IF v_count <> 5 THEN
    RAISE EXCEPTION 'GUARD G-2 failed: exact definition match expected 5 (3 drop + 2 keep), got % (already dropped? BODY must run only once)', v_count;
  END IF;

  -- G-3. 想定外 policy が 0 本（5本の集合以外が存在しない）
  SELECT count(*) INTO v_count
  FROM   pg_policies
  WHERE  schemaname = 'public'
    AND  NOT ( (tablename='employees'    AND policyname='employees_read_all')
            OR (tablename='genka_admins' AND policyname IN
                ('ga_read','ga_write','ga_update','anon_can_update_genka_admins')) );
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-3 failed: unexpected policies found: %', v_count;
  END IF;

  -- G-4. 同名 policy 重複なし
  SELECT count(*) INTO v_count
  FROM   (SELECT tablename, policyname
          FROM   pg_policies
          WHERE  schemaname = 'public'
          GROUP  BY tablename, policyname
          HAVING count(*) > 1) d;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-4 failed: duplicate policy names found: %', v_count;
  END IF;

  -- G-5. employees / genka_admins：owner=postgres / RLS=true / FORCE=false
  SELECT count(*) INTO v_count
  FROM   pg_class c
  JOIN   pg_namespace n ON n.oid = c.relnamespace
  WHERE  n.nspname = 'public'
    AND  c.relkind = 'r'
    AND  c.relname IN ('employees','genka_admins')
    AND  pg_get_userbyid(c.relowner) = 'postgres'
    AND  c.relrowsecurity = true
    AND  c.relforcerowsecurity = false;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'GUARD G-5 failed: table owner/RLS/FORCE baseline expected 2 tables, got %', v_count;
  END IF;

  -- G-6. anon / authenticated の table-level INSERT / UPDATE / DELETE がすべて false
  FOR v_rec IN
    SELECT t.tbl, r.role_name, pr.priv
    FROM   (VALUES ('public.employees'), ('public.genka_admins')) t(tbl)
    CROSS  JOIN (VALUES ('anon'), ('authenticated')) r(role_name)
    CROSS  JOIN (VALUES ('INSERT'), ('UPDATE'), ('DELETE')) pr(priv)
  LOOP
    IF has_table_privilege(v_rec.role_name, v_rec.tbl, v_rec.priv) THEN
      RAISE EXCEPTION 'GUARD G-6 failed: % has % on %', v_rec.role_name, v_rec.priv, v_rec.tbl;
    END IF;
  END LOOP;

  -- G-7. anon / authenticated の write（INSERT/UPDATE）列 grant が 0
  SELECT count(*) INTO v_count
  FROM   information_schema.column_privileges
  WHERE  table_schema = 'public'
    AND  table_name IN ('employees','genka_admins')
    AND  grantee IN ('anon','authenticated')
    AND  privilege_type IN ('INSERT','UPDATE');
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-7 failed: write column grants expected 0, got %', v_count;
  END IF;

  -- G-8. identity 関連9関数：存在・overload なし・SECURITY DEFINER・owner=postgres
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.proname IN ('create_admin_session','create_employee_session',
                       'revoke_admin_session','revoke_employee_session',
                       '_verify_management_session',
                       'create_employee_secure','update_employee_secure',
                       'create_genka_admin_secure','update_genka_admin_secure');
  IF v_count <> 9 THEN
    RAISE EXCEPTION 'GUARD G-8 failed: expected exactly 9 identity functions (no overload), got %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.proname IN ('create_admin_session','create_employee_session',
                       'revoke_admin_session','revoke_employee_session',
                       '_verify_management_session',
                       'create_employee_secure','update_employee_secure',
                       'create_genka_admin_secure','update_genka_admin_secure')
    AND  p.prosecdef = true
    AND  pg_get_userbyid(p.proowner) = 'postgres';
  IF v_count <> 9 THEN
    RAISE EXCEPTION 'GUARD G-8 failed: SECURITY DEFINER + owner=postgres expected 9, got %', v_count;
  END IF;

  -- G-9a. 9関数に PUBLIC EXECUTE（or proacl NULL）が無い
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.proname IN ('create_admin_session','create_employee_session',
                       'revoke_admin_session','revoke_employee_session',
                       '_verify_management_session',
                       'create_employee_secure','update_employee_secure',
                       'create_genka_admin_secure','update_genka_admin_secure')
    AND  ( p.proacl IS NULL
           OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0) );
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-9a failed: PUBLIC EXECUTE (or default acl) found on % function(s)', v_count;
  END IF;

  -- G-9b. 外部8関数の anon / authenticated EXECUTE が維持（login 断絶防止）
  FOR v_rec IN
    SELECT f.fname, r.role_name
    FROM   (VALUES ('create_admin_session'), ('create_employee_session'),
                   ('revoke_admin_session'), ('revoke_employee_session'),
                   ('create_employee_secure'), ('update_employee_secure'),
                   ('create_genka_admin_secure'), ('update_genka_admin_secure')) f(fname)
    CROSS  JOIN (VALUES ('anon'), ('authenticated')) r(role_name)
  LOOP
    SELECT count(*) INTO v_count
    FROM   pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public'
      AND  p.proname = v_rec.fname
      AND  has_function_privilege(v_rec.role_name, p.oid, 'EXECUTE');
    IF v_count = 0 THEN
      RAISE EXCEPTION 'GUARD G-9b failed: % lacks EXECUTE on %', v_rec.role_name, v_rec.fname;
    END IF;
  END LOOP;

  -- G-9c. _verify_management_session は anon / authenticated に非公開
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.proname = '_verify_management_session'
    AND  ( has_function_privilege('anon', p.oid, 'EXECUTE')
        OR has_function_privilege('authenticated', p.oid, 'EXECUTE') );
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-9c failed: _verify_management_session is exposed to anon/authenticated';
  END IF;

  -- G-10a. ga_read を支える SELECT 列 grant が存在（genka_admins・両ロール）
  SELECT count(*) INTO v_count
  FROM   information_schema.column_privileges
  WHERE  table_schema = 'public'
    AND  table_name = 'genka_admins'
    AND  grantee IN ('anon','authenticated')
    AND  privilege_type = 'SELECT';
  IF v_count < 2 THEN
    RAISE EXCEPTION 'GUARD G-10a failed: genka_admins SELECT column grants expected (login name list), got %', v_count;
  END IF;

  -- G-10b. pin 列が非公開（両テーブル・両ロール）
  FOR v_rec IN
    SELECT t.tbl, r.role_name
    FROM   (VALUES ('employees'), ('genka_admins')) t(tbl)
    CROSS  JOIN (VALUES ('anon'), ('authenticated')) r(role_name)
  LOOP
    IF has_column_privilege(v_rec.role_name, 'public.'||v_rec.tbl, 'pin', 'SELECT') THEN
      RAISE EXCEPTION 'GUARD G-10b failed: pin column is exposed to % on %', v_rec.role_name, v_rec.tbl;
    END IF;
  END LOOP;

  RAISE NOTICE 'GUARD OK: baseline matches; proceeding to DROP 3 stale write policies on genka_admins (keeping employees_read_all / ga_read)';
END
$$;

DROP POLICY anon_can_update_genka_admins
  ON public.genka_admins;

DROP POLICY ga_update
  ON public.genka_admins;

DROP POLICY ga_write
  ON public.genka_admins;

COMMIT;


-- ============================================================
-- POST-CHECK（read-only・COMMIT 後に P-1 から順に実行）
--   各結果は SQL Editor から CSV / 表形式でそのまま貼り戻せる。
-- ============================================================

-- P-1. 削除対象3本が 0 本
--   期待：0行
SELECT tablename, policyname
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename = 'genka_admins'
  AND  policyname IN ('anon_can_update_genka_admins','ga_update','ga_write');

-- P-2a. policy 総数：public_total=2
SELECT count(*) AS public_total
FROM   pg_policies
WHERE  schemaname = 'public';

-- P-2b. 残存 policy が保持2本と完全一致（定義込み・差分 0行）
WITH expected(tablename, policyname, permissive, roles_text, cmd, qual, with_check) AS (
  VALUES
    ('employees',    'employees_read_all', 'PERMISSIVE', '{public}', 'SELECT', 'true', NULL),
    ('genka_admins', 'ga_read',            'PERMISSIVE', '{public}', 'SELECT', 'true', NULL)
),
actual AS (
  SELECT tablename, policyname, permissive, roles::text AS roles_text, cmd, qual, with_check
  FROM   pg_policies
  WHERE  schemaname = 'public'
)
SELECT COALESCE(e.tablename, a.tablename)   AS tablename,
       COALESCE(e.policyname, a.policyname) AS policyname,
       CASE WHEN a.policyname IS NULL THEN 'MISSING_IN_DB'
            WHEN e.policyname IS NULL THEN 'UNEXPECTED_IN_DB'
            ELSE 'DEF_MISMATCH' END AS diff_kind
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

-- P-3. owner / RLS / FORCE / table ACL 不変
--   期待：2行。owner=postgres / rls=true / forced=false / ACL は C-3 と同一。
SELECT c.relname AS table_name,
       pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced,
       c.relacl::text AS table_acl
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'public'
  AND  c.relkind = 'r'
  AND  c.relname IN ('employees','genka_admins')
ORDER  BY c.relname;

-- P-4. 列 grant 不変（SELECT のみ・pin なし・write 列 grant 0）
--   期待：C-4 と同一。
SELECT table_name, grantee, privilege_type,
       string_agg(column_name, ',' ORDER BY column_name) AS columns
FROM   information_schema.column_privileges
WHERE  table_schema = 'public'
  AND  table_name IN ('employees','genka_admins')
  AND  grantee IN ('anon','authenticated','PUBLIC','service_role')
GROUP  BY table_name, grantee, privilege_type
ORDER  BY table_name, grantee, privilege_type;

-- P-5. pin 非公開維持
--   期待：4行すべて can_select_pin=false（C-6 と同一）。
SELECT t.tbl AS table_name, r.role_name,
       has_column_privilege(r.role_name, 'public.'||t.tbl, 'pin', 'SELECT') AS can_select_pin
FROM   (VALUES ('employees'), ('genka_admins')) t(tbl)
CROSS  JOIN (VALUES ('anon'), ('authenticated')) r(role_name)
ORDER  BY t.tbl, r.role_name;

-- P-6. identity 関連9関数の属性・EXECUTE 不変
--   期待：C-5 と同一（9行・SECURITY DEFINER・owner=postgres・PUBLIC EXECUTE なし・
--         外部8関数 EXECUTE=true・_verify のみ false）。
SELECT p.oid::regprocedure AS signature,
       pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef AS security_definer,
       (p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)) AS has_public_execute,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('create_admin_session','create_employee_session',
                     'revoke_admin_session','revoke_employee_session',
                     '_verify_management_session',
                     'create_employee_secure','update_employee_secure',
                     'create_genka_admin_secure','update_genka_admin_secure')
ORDER  BY p.proname;


-- ============================================================
-- EMERGENCY ROLLBACK（通常は実行しない・コメントのまま保持）
--   実行禁止：本番 login / genka_admins 系障害の原因が本工程と確定し、
--   かつ別途明示承認された場合のみ使用する。
--   下記は 2026-07-19 実測（I-1a）の定義どおりの完全復元。
--   実行する場合は該当 CREATE POLICY だけを1文ずつ実行し、
--   実行後に C-2 相当で定義一致を必ず確認すること。
-- ============================================================
-- CREATE POLICY anon_can_update_genka_admins
-- ON public.genka_admins
-- AS PERMISSIVE
-- FOR UPDATE
-- TO anon
-- USING (true)
-- WITH CHECK (true);
--
-- CREATE POLICY ga_update
-- ON public.genka_admins
-- AS PERMISSIVE
-- FOR UPDATE
-- TO public
-- USING (true);
--
-- CREATE POLICY ga_write
-- ON public.genka_admins
-- AS PERMISSIVE
-- FOR INSERT
-- TO public
-- WITH CHECK (true);


-- ============================================================
-- SMOKE CHECKLIST（DB 実行後・本番でユーザーが実施）
--   read policy 2本（employees_read_all / ga_read）は削除していないため、
--   ログイン前の名前一覧が従来どおり表示されることを必ず確認する。
--
-- 【login smoke（最重要・3画面）】
--   [L-1] 従業員画面（index.html）：ログイン前の従業員名一覧が表示される →
--         ログイン成功 → ログアウト → 再ログイン成功
--   [L-2] 管理コンソール（admin-app.html）：ログイン前の管理者名一覧が表示される →
--         ログイン成功 → ログアウト → 再ログイン成功
--   [L-3] 原価管理画面（genka-app.html）：ログイン前の管理者名一覧が表示される →
--         ログイン成功 → ログアウト → 再ログイン成功
--   [共通] PIN が Network 応答（employees / genka_admins の SELECT 結果・RPC 応答）に
--          含まれないこと・Console 赤エラーなし・想定外 401/403 なし
--
-- 【identity write smoke】
--   [W-1] 管理コンソール：既存 genka_admin を内容変更なしで同値保存 →
--         update_genka_admin_secure が HTTP 200 または 204 →
--         genka_admins への direct REST write（.from() 由来の PATCH/POST）が
--         Network に現れないこと
--   [W-2] 新規管理者作成（create_genka_admin_secure）は実データ変更を伴うため
--         原則未実施。関数属性・ACL・EXECUTE 証拠（PRE/POST-CHECK C-5 / P-6・
--         SECURITY DEFINER owner bypass により policy 非依存）で補完する。
--         未実施の場合は記録にその旨を明記すること。
-- ============================================================
