-- ============================================================
-- Phase 4-F-7-b：business stale policy cleanup
--   invoices / site_budgets / paid_leave_requests / paid_leave_grants /
--   reports の stale permissive policy 12本を DROP
-- ============================================================
-- 【実行ステータス】STATUS: EXECUTED 2026-07-19
--   - preparation date：2026-07-19（準備PR #147・merge `7bf9170`）
--   - execution date  ：2026-07-19（Supabase SQL Editor 手動実行・Supabase CLI / psql 未使用）
--   - Result          ：Success. No rows returned
--   - 実行内容：EXECUTION BODY（GUARD G-1〜G-8＋DROP POLICY 12文・同一transaction）を
--     1回だけ実行。再実行なし。
--   - ★BODY は実行済み。再実行禁止★（再実行しても GUARD G-2 が対象policy 0本を
--     検知して fail-closed で停止する）
--   - PRE-CHECK 全合格（C-1〜C-8・2026-07-19）：
--       C-1 public_total=17 / target=12 / identity=5 / other=0
--       C-2 対象12本の名前・roles・cmd・qual・with_check 想定どおり
--       C-3 期待集合との差分0行・C-4 5テーブル owner=postgres・RLS=true・FORCE=false
--       C-5 anon/authenticated の table 権限なし（明示0行・実効40判定 false）
--       C-6〜C-8 対象参照30関数：SECURITY DEFINER=true・owner=postgres・
--       search_path=public, extensions・PUBLIC EXECUTE=false・
--       anon/authenticated EXECUTE=true
--   - BODY で削除した policy（12本のみ・identity 系5本は未変更）：
--       invoices：inv_read / inv_write / inv_update
--       site_budgets：sb_read / sb_write / sb_update / anon_can_update_site_budgets
--       paid_leave_requests：plr_write / plr_update
--       paid_leave_grants：plg_write / plg_update
--       reports：reports_all
--   - POST-CHECK 全合格（P-1〜P-5・2026-07-19）：
--       P-1 対象5テーブル policy 0行
--       P-2 public_total=17→5・残存は identity 系5本（employees_read_all /
--           ga_read / ga_write / ga_update / anon_can_update_genka_admins）と
--           完全一致・想定外0
--       P-3 5テーブルの owner・RLS・FORCE・ACL 不変
--       P-4 対象30関数の SECURITY DEFINER・owner・search_path・
--           PUBLIC EXECUTE なし 不変
--       P-5 anon/authenticated EXECUTE 維持
--   - 本番 smoke（2026-07-19・全合格）：
--       従業員画面：ログイン・日報入力/履歴/カレンダー・有休情報 正常・
--       関連RPC成功・Console赤エラーなし・対象テーブル direct REST なし
--       管理コンソール：ログイン・日報一覧・有休管理・請求書一覧・実行予算一覧 正常
--       原価管理画面：ログイン・ダッシュボード・日報原価/請求書/予算表示・
--       現場/期間切替 正常
--       write smoke：現場予算 同値保存（get_site_budget_secure 200 /
--       update_site_budget_secure 204）・請求書 同値保存・日報 同値保存・
--       有休付与日数 同値保存 すべて合格・direct REST なし
--       ★未実施の明記★：paid_leave_requests の新規申請・承認は実データ変更を
--       伴うため意図的に未実施。PRE/POST-CHECK の関数属性・ACL・EXECUTE 証拠
--       （SECURITY DEFINER owner bypass により policy 非依存）で補完。
--   - 記録先：docs/db-migrations.md「2026-07-19 Phase 4-F-7-b」
--
-- 【実行方法（重要）】
--   - 実行先：Supabase SQL Editor（手動実行のみ）
--   - Supabase CLI / psql では実行しない。
--   - 手順：PRE-CHECK（C-1〜C-8 を1つずつ・read-only）→ 全合格を確認
--           → C-2 の実測 qual / with_check を本ファイル末尾の EMERGENCY ROLLBACK
--             コメントと照合（差異があれば ROLLBACK コメントを実測値へ修正してから進む）
--           → EXECUTION BODY（BEGIN〜COMMIT を1回だけ選択実行）
--           → POST-CHECK（P-1〜P-5・read-only）→ smoke checklist。
--   - ★BODY は1回のみ実行。再実行禁止★
--     （2回目は GUARD G-2 が対象 policy 0本を検知して fail-closed で停止する）
--
-- 【変更内容】
--   - DB変更文は DROP POLICY 12文のみ。
--   - GRANT / REVOKE / ALTER TABLE / CREATE OR REPLACE FUNCTION / DROP FUNCTION /
--     CREATE POLICY / INSERT / UPDATE / DELETE / TRUNCATE は一切含まない。
--
-- 【対象 policy（12本・2026-07-19 read-only SQL A〜J で存在確認済み）】
--   public.invoices（3本）           ：inv_read / inv_write / inv_update
--   public.site_budgets（4本）       ：sb_read / sb_write / sb_update /
--                                      anon_can_update_site_budgets（roles={anon}）
--   public.paid_leave_requests（2本）：plr_write / plr_update
--   public.paid_leave_grants（2本）  ：plg_write / plg_update
--   public.reports（1本）            ：reports_all（cmd=ALL）
--   ※ policy 条件はすべて実質無制限（qual / with_check が true または NULL）の
--     旧 policy であることを実DBで確認済み。GUARD G-4 でも「無制限であること」を
--     fail-closed で再検証する（条件付き policy が紛れていたら abort）。
--
-- 【対象外（今回削除しない・Phase 4-F-7-c で扱う identity 系5本）】
--   public.employees    ：employees_read_all（login前の名前リスト取得を支える現役候補）
--   public.genka_admins ：ga_read / ga_write / ga_update / anon_can_update_genka_admins
--   GUARD G-3 で「対象外 policy がこの5本と完全一致」を検証し、想定外があれば abort。
--
-- 【変更しないもの】
--   - RLS 有効/無効・FORCE RLS・table ACL・RPC 定義・RPC owner・RPC EXECUTE 権限
--   - frontend / Vercel / Supabase 設定
--
-- 【安全性の根拠（policy 12本を削除しても動作影響なし）】
--   1. 対象5テーブルとも anon / authenticated の table 権限は SELECT / INSERT /
--      UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN すべて false
--      （実DB確認済み）。policy が許可していても権限段階で遮断済みのため、
--      現存 policy 12本は「効果を持たない stale permissive policy」。
--   2. 対象テーブルを操作する secure RPC はすべて SECURITY DEFINER・owner=postgres・
--      search_path=public, extensions 固定（実DB確認済み）。FORCE RLS=false のため
--      owner には RLS が適用されず、policy の有無は RPC の read/write に影響しない。
--   3. frontend（index.html / admin-app.html / genka-app.html）に対象5テーブルへの
--      direct access（.from()）は 0件。すべて secure RPC 経由。
--
-- 【schema 基準（実DB確認済み）】
--   - public schema policy total = 17
--   - 対象 policy total          = 12
--   - 対象外（identity系）total  =  5（実行後はこの5本だけが残る想定）
--
-- 【STOP 条件（PRE-CHECK / GUARD のいずれかが不一致なら実行せず停止・報告）】
--   - policy 名・テーブル・cmd・roles の実DB差異／qual・with_check が無制限でない
--   - 対象外 policy が identity 系5本と一致しない
--   - table owner が postgres でない / RLS 無効 / FORCE RLS=true
--   - anon / authenticated の table 権限残存
--   - 対象テーブル参照 RPC に SECURITY DEFINER でないもの・owner 不一致・
--     PUBLIC EXECUTE あり
--   - public schema policy total が 17 でない
-- ============================================================


-- ============================================================
-- PRE-CHECK（read-only・BODY 実行前に C-1 から順に1つずつ実行）
--   すべて SELECT のみ。DB 状態は変更しない。
-- ============================================================

-- C-1. policy 総数基準
--   期待：public_total=17 / target_total=12 / identity_total=5 / other_total=0
SELECT count(*) AS public_total,
       count(*) FILTER (WHERE tablename IN ('invoices','site_budgets','paid_leave_requests',
                                            'paid_leave_grants','reports'))            AS target_total,
       count(*) FILTER (WHERE tablename IN ('employees','genka_admins'))               AS identity_total,
       count(*) FILTER (WHERE tablename NOT IN ('invoices','site_budgets','paid_leave_requests',
                                                'paid_leave_grants','reports',
                                                'employees','genka_admins'))           AS other_total
FROM   pg_policies
WHERE  schemaname = 'public';

-- C-2. 対象 policy 12本の全定義列挙
--   期待：ちょうど12行。qual / with_check はすべて true または NULL（無制限）。
--   ★この実測値を EMERGENCY ROLLBACK コメントと照合し、差異があれば
--     ROLLBACK コメント側を実測値へ修正してから BODY に進むこと★
SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename IN ('invoices','site_budgets','paid_leave_requests',
                     'paid_leave_grants','reports')
ORDER  BY tablename, policyname;

-- C-3. 期待集合との差分判定（名前・cmd・roles・無制限性）
--   期待：0行
WITH expected(tablename, policyname, cmd, roles_text) AS (
  VALUES
    ('invoices',            'inv_read',                     'SELECT', '{public}'),
    ('invoices',            'inv_write',                    'INSERT', '{public}'),
    ('invoices',            'inv_update',                   'UPDATE', '{public}'),
    ('site_budgets',        'sb_read',                      'SELECT', '{public}'),
    ('site_budgets',        'sb_write',                     'INSERT', '{public}'),
    ('site_budgets',        'sb_update',                    'UPDATE', '{public}'),
    ('site_budgets',        'anon_can_update_site_budgets', 'UPDATE', '{anon}'),
    ('paid_leave_requests', 'plr_write',                    'INSERT', '{public}'),
    ('paid_leave_requests', 'plr_update',                   'UPDATE', '{public}'),
    ('paid_leave_grants',   'plg_write',                    'INSERT', '{public}'),
    ('paid_leave_grants',   'plg_update',                   'UPDATE', '{public}'),
    ('reports',             'reports_all',                  'ALL',    '{public}')
),
actual AS (
  SELECT tablename, policyname, cmd, roles::text AS roles_text,
         ( (qual       IS NULL OR btrim(qual)       = 'true')
       AND (with_check IS NULL OR btrim(with_check) = 'true') ) AS is_unrestricted
  FROM   pg_policies
  WHERE  schemaname = 'public'
    AND  tablename IN ('invoices','site_budgets','paid_leave_requests',
                       'paid_leave_grants','reports')
)
SELECT COALESCE(e.tablename, a.tablename)   AS tablename,
       COALESCE(e.policyname, a.policyname) AS policyname,
       CASE WHEN a.policyname IS NULL                    THEN 'MISSING_IN_DB'
            WHEN e.policyname IS NULL                    THEN 'UNEXPECTED_IN_DB'
            WHEN a.is_unrestricted IS NOT TRUE           THEN 'NOT_UNRESTRICTED'
            ELSE 'DEF_MISMATCH' END AS diff_kind
FROM   expected e
FULL   OUTER JOIN actual a
       ON  a.tablename  = e.tablename
       AND a.policyname = e.policyname
       AND a.cmd        = e.cmd
       AND a.roles_text = e.roles_text
WHERE  e.policyname IS NULL OR a.policyname IS NULL OR a.is_unrestricted IS NOT TRUE;

-- C-4. 対象5テーブルの存在・owner・RLS・FORCE RLS・ACL
--   期待：5行。owner=postgres / rls_enabled=true / rls_forced=false。
SELECT c.relname                    AS table_name,
       pg_get_userbyid(c.relowner)  AS owner,
       c.relrowsecurity             AS rls_enabled,
       c.relforcerowsecurity        AS rls_forced,
       c.relacl::text               AS table_acl
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'public'
  AND  c.relkind = 'r'
  AND  c.relname IN ('invoices','site_budgets','paid_leave_requests',
                     'paid_leave_grants','reports')
ORDER  BY c.relname;

-- C-5a. anon / authenticated / PUBLIC の明示 table 権限
--   期待：0行
SELECT table_name, grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name IN ('invoices','site_budgets','paid_leave_requests',
                      'paid_leave_grants','reports')
  AND  grantee IN ('anon','authenticated','PUBLIC')
ORDER  BY table_name, grantee, privilege_type;

-- C-5b. anon / authenticated の実効 table 権限（PUBLIC 継承含む）
--   期待：40判定（5テーブル×2ロール×4権限）すべて false
SELECT t.tbl AS table_name, r.role_name,
       has_table_privilege(r.role_name, t.tbl, 'SELECT') AS can_select,
       has_table_privilege(r.role_name, t.tbl, 'INSERT') AS can_insert,
       has_table_privilege(r.role_name, t.tbl, 'UPDATE') AS can_update,
       has_table_privilege(r.role_name, t.tbl, 'DELETE') AS can_delete
FROM   (VALUES ('public.invoices'), ('public.site_budgets'),
               ('public.paid_leave_requests'), ('public.paid_leave_grants'),
               ('public.reports')) t(tbl)
CROSS  JOIN (VALUES ('anon'), ('authenticated')) r(role_name)
ORDER  BY t.tbl, r.role_name;

-- C-6. 対象5テーブルを参照する全関数の属性（prosrc ベース）
--   期待：全行 security_definer=true / owner=postgres / config に search_path。
--   ★目視照合★：出力に少なくとも次の既知 client RPC が含まれることを確認する
--     （prosrc LIKE 方式は網羅検出だが、以下が欠けていたら検出漏れ疑いで停止）：
--     invoices     ：list_invoices_secure / get_invoice_secure / create_invoice_secure /
--                    update_invoice_secure / reject_invoice_secure / restore_invoice_secure
--     site_budgets ：list_site_budgets_secure / get_site_budget_secure /
--                    upsert_site_budget_secure / update_site_budget_secure /
--                    deactivate_site_budget_secure / restore_site_budget_secure
--     paid_leave   ：list_my_paid_leave_secure / list_paid_leave_admin_secure /
--                    create_paid_leave_request_secure / review_paid_leave_request_secure /
--                    save_paid_leave_grant_secure / export_paid_leave_*_secure
--     reports      ：list_my_reports_secure / list_admin_reports_secure /
--                    list_genka_reports_secure / create_report_secure /
--                    update_report_secure / update_report_photo_secure /
--                    admin_void_report_secure
SELECT p.oid::regprocedure           AS signature,
       pg_get_function_result(p.oid) AS result_type,
       pg_get_userbyid(p.proowner)   AS owner,
       p.prosecdef                   AS security_definer,
       p.proconfig                   AS config
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.prokind = 'f'
  AND  ( p.prosrc LIKE '%invoices%' OR p.prosrc LIKE '%site_budgets%'
      OR p.prosrc LIKE '%paid_leave_requests%' OR p.prosrc LIKE '%paid_leave_grants%'
      OR p.prosrc LIKE '%reports%' )
ORDER  BY p.proname, p.oid;

-- C-7. 同関数群に PUBLIC EXECUTE（または proacl NULL）が無いこと
--   期待：0行
SELECT p.oid::regprocedure AS signature,
       CASE WHEN p.proacl IS NULL THEN 'PROACL_IS_NULL(default: PUBLIC exec)'
            ELSE 'PUBLIC_EXECUTE_ENTRY' END AS problem
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.prokind = 'f'
  AND  ( p.prosrc LIKE '%invoices%' OR p.prosrc LIKE '%site_budgets%'
      OR p.prosrc LIKE '%paid_leave_requests%' OR p.prosrc LIKE '%paid_leave_grants%'
      OR p.prosrc LIKE '%reports%' )
  AND  ( p.proacl IS NULL
         OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0) );

-- C-8. client 向け関数（名前が _ で始まらない）の anon / authenticated EXECUTE
--   期待：全行 anon_exec=true かつ auth_exec=true
SELECT p.oid::regprocedure AS signature,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.prokind = 'f'
  AND  p.proname NOT LIKE '\_%'
  AND  ( p.prosrc LIKE '%invoices%' OR p.prosrc LIKE '%site_budgets%'
      OR p.prosrc LIKE '%paid_leave_requests%' OR p.prosrc LIKE '%paid_leave_grants%'
      OR p.prosrc LIKE '%reports%' )
ORDER  BY p.proname;


-- ============================================================
-- EXECUTION BODY（★1回のみ実行・再実行禁止★・現時点では未実行）
--   BEGIN〜COMMIT を1回だけ選択して実行する。
--   fail-closed GUARD（read-only DO block）が1つでも不一致を検知したら
--   RAISE EXCEPTION で transaction 全体が abort する（DB 無変更）。
--   DB 変更文は DROP POLICY 12文のみ。IF EXISTS は意図的に付けない
--   （想定外の不存在は GUARD / DROP の失敗として検知する）。
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_count integer;
  v_rec   record;
BEGIN
  -- G-1. public schema policy total = 17
  SELECT count(*) INTO v_count FROM pg_policies WHERE schemaname = 'public';
  IF v_count <> 17 THEN
    RAISE EXCEPTION 'GUARD G-1 failed: public policy total expected 17, got %', v_count;
  END IF;

  -- G-2. 対象 policy total = 12
  SELECT count(*) INTO v_count
  FROM   pg_policies
  WHERE  schemaname = 'public'
    AND  tablename IN ('invoices','site_budgets','paid_leave_requests',
                       'paid_leave_grants','reports');
  IF v_count <> 12 THEN
    RAISE EXCEPTION 'GUARD G-2 failed: target policy total expected 12, got % (already dropped? BODY must run only once)', v_count;
  END IF;

  -- G-3. 対象外 policy が identity 系5本と完全一致
  SELECT count(*) INTO v_count
  FROM   pg_policies p
  JOIN   (VALUES ('employees','employees_read_all'),
                 ('genka_admins','ga_read'),
                 ('genka_admins','ga_write'),
                 ('genka_admins','ga_update'),
                 ('genka_admins','anon_can_update_genka_admins')
         ) e(tablename, policyname)
    ON  p.tablename = e.tablename AND p.policyname = e.policyname
  WHERE  p.schemaname = 'public';
  IF v_count <> 5 THEN
    RAISE EXCEPTION 'GUARD G-3 failed: identity policy exact-match expected 5, got %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM   pg_policies
  WHERE  schemaname = 'public'
    AND  tablename NOT IN ('invoices','site_budgets','paid_leave_requests',
                           'paid_leave_grants','reports','employees','genka_admins');
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-3 failed: unexpected policies outside known tables: %', v_count;
  END IF;

  -- G-4. 対象12本の集合一致（名前・cmd・roles）＋ 無制限（qual/with_check が true/NULL）
  SELECT count(*) INTO v_count
  FROM   pg_policies p
  JOIN   (VALUES
           ('invoices',            'inv_read',                     'SELECT', '{public}'),
           ('invoices',            'inv_write',                    'INSERT', '{public}'),
           ('invoices',            'inv_update',                   'UPDATE', '{public}'),
           ('site_budgets',        'sb_read',                      'SELECT', '{public}'),
           ('site_budgets',        'sb_write',                     'INSERT', '{public}'),
           ('site_budgets',        'sb_update',                    'UPDATE', '{public}'),
           ('site_budgets',        'anon_can_update_site_budgets', 'UPDATE', '{anon}'),
           ('paid_leave_requests', 'plr_write',                    'INSERT', '{public}'),
           ('paid_leave_requests', 'plr_update',                   'UPDATE', '{public}'),
           ('paid_leave_grants',   'plg_write',                    'INSERT', '{public}'),
           ('paid_leave_grants',   'plg_update',                   'UPDATE', '{public}'),
           ('reports',             'reports_all',                  'ALL',    '{public}')
         ) e(tablename, policyname, cmd, roles_text)
    ON  p.tablename   = e.tablename
    AND p.policyname  = e.policyname
    AND p.cmd         = e.cmd
    AND p.roles::text = e.roles_text
  WHERE  p.schemaname = 'public'
    AND  (p.qual       IS NULL OR btrim(p.qual)       = 'true')
    AND  (p.with_check IS NULL OR btrim(p.with_check) = 'true');
  IF v_count <> 12 THEN
    RAISE EXCEPTION 'GUARD G-4 failed: exact match (name/cmd/roles + unrestricted) expected 12, got %', v_count;
  END IF;

  -- G-5. 対象5テーブル owner=postgres / RLS=true / FORCE=false
  SELECT count(*) INTO v_count
  FROM   pg_class c
  JOIN   pg_namespace n ON n.oid = c.relnamespace
  WHERE  n.nspname = 'public'
    AND  c.relkind = 'r'
    AND  c.relname IN ('invoices','site_budgets','paid_leave_requests',
                       'paid_leave_grants','reports')
    AND  pg_get_userbyid(c.relowner) = 'postgres'
    AND  c.relrowsecurity = true
    AND  c.relforcerowsecurity = false;
  IF v_count <> 5 THEN
    RAISE EXCEPTION 'GUARD G-5 failed: table owner/RLS/FORCE baseline expected 5 tables, got %', v_count;
  END IF;

  -- G-6a. anon / authenticated の実効 table 権限がすべて false（40判定）
  FOR v_rec IN
    SELECT t.tbl, r.role_name, pr.priv
    FROM   (VALUES ('public.invoices'), ('public.site_budgets'),
                   ('public.paid_leave_requests'), ('public.paid_leave_grants'),
                   ('public.reports')) t(tbl)
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
    AND  table_name IN ('invoices','site_budgets','paid_leave_requests',
                        'paid_leave_grants','reports')
    AND  grantee = 'PUBLIC';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-6b failed: PUBLIC table grants expected 0, got %', v_count;
  END IF;

  -- G-7. 対象テーブル参照関数はすべて SECURITY DEFINER・owner=postgres
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.prokind = 'f'
    AND  ( p.prosrc LIKE '%invoices%' OR p.prosrc LIKE '%site_budgets%'
        OR p.prosrc LIKE '%paid_leave_requests%' OR p.prosrc LIKE '%paid_leave_grants%'
        OR p.prosrc LIKE '%reports%' )
    AND  ( p.prosecdef = false OR pg_get_userbyid(p.proowner) <> 'postgres' );
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-7 failed: % referencing function(s) not SECURITY DEFINER / not owned by postgres', v_count;
  END IF;

  -- G-8. 同関数群に PUBLIC EXECUTE（or proacl NULL）が無い
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.prokind = 'f'
    AND  ( p.prosrc LIKE '%invoices%' OR p.prosrc LIKE '%site_budgets%'
        OR p.prosrc LIKE '%paid_leave_requests%' OR p.prosrc LIKE '%paid_leave_grants%'
        OR p.prosrc LIKE '%reports%' )
    AND  ( p.proacl IS NULL
           OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0) );
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-8 failed: PUBLIC EXECUTE (or default acl) found on % function(s)', v_count;
  END IF;

  RAISE NOTICE 'GUARD OK: baseline matches; proceeding to DROP 12 stale policies on 5 business tables';
END
$$;

DROP POLICY inv_read
  ON public.invoices;

DROP POLICY inv_write
  ON public.invoices;

DROP POLICY inv_update
  ON public.invoices;

DROP POLICY sb_read
  ON public.site_budgets;

DROP POLICY sb_write
  ON public.site_budgets;

DROP POLICY sb_update
  ON public.site_budgets;

DROP POLICY anon_can_update_site_budgets
  ON public.site_budgets;

DROP POLICY plr_write
  ON public.paid_leave_requests;

DROP POLICY plr_update
  ON public.paid_leave_requests;

DROP POLICY plg_write
  ON public.paid_leave_grants;

DROP POLICY plg_update
  ON public.paid_leave_grants;

DROP POLICY reports_all
  ON public.reports;

COMMIT;


-- ============================================================
-- POST-CHECK（read-only・COMMIT 後に P-1 から順に実行）
--   各結果は SQL Editor から CSV / 表形式でそのまま貼り戻せる。
-- ============================================================

-- P-1. 対象5テーブルの policy が 0 本
--   期待：0行
SELECT tablename, policyname
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename IN ('invoices','site_budgets','paid_leave_requests',
                     'paid_leave_grants','reports');

-- P-2a. policy 総数：public_total=5 / target_total=0 / identity_total=5
SELECT count(*) AS public_total,
       count(*) FILTER (WHERE tablename IN ('invoices','site_budgets','paid_leave_requests',
                                            'paid_leave_grants','reports'))  AS target_total,
       count(*) FILTER (WHERE tablename IN ('employees','genka_admins'))     AS identity_total
FROM   pg_policies
WHERE  schemaname = 'public';

-- P-2b. 残存 policy が identity 系5本と完全一致（差分 0行）
WITH expected(tablename, policyname) AS (
  VALUES ('employees','employees_read_all'),
         ('genka_admins','ga_read'),
         ('genka_admins','ga_write'),
         ('genka_admins','ga_update'),
         ('genka_admins','anon_can_update_genka_admins')
),
actual AS (
  SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
)
SELECT COALESCE(e.tablename, a.tablename)   AS tablename,
       COALESCE(e.policyname, a.policyname) AS policyname,
       CASE WHEN a.policyname IS NULL THEN 'MISSING_IN_DB'
            WHEN e.policyname IS NULL THEN 'UNEXPECTED_IN_DB' END AS diff_kind
FROM   expected e
FULL   OUTER JOIN actual a
       ON a.tablename = e.tablename AND a.policyname = e.policyname
WHERE  e.policyname IS NULL OR a.policyname IS NULL;

-- P-3. 対象5テーブルの owner / RLS / FORCE / ACL 不変
--   期待：5行。owner=postgres / rls_enabled=true / rls_forced=false /
--         table_acl は実行前（C-4）と同一。
SELECT c.relname                    AS table_name,
       pg_get_userbyid(c.relowner)  AS owner,
       c.relrowsecurity             AS rls_enabled,
       c.relforcerowsecurity        AS rls_forced,
       c.relacl::text               AS table_acl
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'public'
  AND  c.relkind = 'r'
  AND  c.relname IN ('invoices','site_budgets','paid_leave_requests',
                     'paid_leave_grants','reports')
ORDER  BY c.relname;

-- P-4. 対象テーブル参照関数の属性不変
--   期待：C-6 と同一（security_definer=true / owner=postgres / config 不変）。
SELECT p.oid::regprocedure           AS signature,
       pg_get_userbyid(p.proowner)   AS owner,
       p.prosecdef                   AS security_definer,
       p.proconfig                   AS config,
       (p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)) AS has_public_execute
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.prokind = 'f'
  AND  ( p.prosrc LIKE '%invoices%' OR p.prosrc LIKE '%site_budgets%'
      OR p.prosrc LIKE '%paid_leave_requests%' OR p.prosrc LIKE '%paid_leave_grants%'
      OR p.prosrc LIKE '%reports%' )
ORDER  BY p.proname, p.oid;

-- P-5. client 向け参照関数の anon / authenticated EXECUTE 不変
--   期待：C-8 と同一（全行 true / true）。
SELECT p.oid::regprocedure AS signature,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.prokind = 'f'
  AND  p.proname NOT LIKE '\_%'
  AND  ( p.prosrc LIKE '%invoices%' OR p.prosrc LIKE '%site_budgets%'
      OR p.prosrc LIKE '%paid_leave_requests%' OR p.prosrc LIKE '%paid_leave_grants%'
      OR p.prosrc LIKE '%reports%' )
ORDER  BY p.proname;


-- ============================================================
-- EMERGENCY ROLLBACK（通常は実行しない・コメントのまま保持）
--   実行前に必ず PRE-CHECK C-2 の実測 qual / with_check と照合し、
--   差異があれば実測値どおりに修正してから使用すること。
--   （既知確定：reports_all = ALL / USING true / WITH CHECK true、
--     anon_can_update_site_budgets = UPDATE / TO anon / USING true / WITH CHECK true。
--     他10本は read=USING true / write=WITH CHECK true / update=USING true を仮置き）
--   実行する場合は該当 CREATE POLICY だけを1文ずつ実行し、
--   実行後に C-2 / C-3 相当で定義一致を必ず確認すること。
-- ============================================================
-- CREATE POLICY inv_read
-- ON public.invoices
-- AS PERMISSIVE
-- FOR SELECT
-- TO public
-- USING (true);
--
-- CREATE POLICY inv_write
-- ON public.invoices
-- AS PERMISSIVE
-- FOR INSERT
-- TO public
-- WITH CHECK (true);
--
-- CREATE POLICY inv_update
-- ON public.invoices
-- AS PERMISSIVE
-- FOR UPDATE
-- TO public
-- USING (true);
--
-- CREATE POLICY sb_read
-- ON public.site_budgets
-- AS PERMISSIVE
-- FOR SELECT
-- TO public
-- USING (true);
--
-- CREATE POLICY sb_write
-- ON public.site_budgets
-- AS PERMISSIVE
-- FOR INSERT
-- TO public
-- WITH CHECK (true);
--
-- CREATE POLICY sb_update
-- ON public.site_budgets
-- AS PERMISSIVE
-- FOR UPDATE
-- TO public
-- USING (true);
--
-- CREATE POLICY anon_can_update_site_budgets
-- ON public.site_budgets
-- AS PERMISSIVE
-- FOR UPDATE
-- TO anon
-- USING (true)
-- WITH CHECK (true);
--
-- CREATE POLICY plr_write
-- ON public.paid_leave_requests
-- AS PERMISSIVE
-- FOR INSERT
-- TO public
-- WITH CHECK (true);
--
-- CREATE POLICY plr_update
-- ON public.paid_leave_requests
-- AS PERMISSIVE
-- FOR UPDATE
-- TO public
-- USING (true);
--
-- CREATE POLICY plg_write
-- ON public.paid_leave_grants
-- AS PERMISSIVE
-- FOR INSERT
-- TO public
-- WITH CHECK (true);
--
-- CREATE POLICY plg_update
-- ON public.paid_leave_grants
-- AS PERMISSIVE
-- FOR UPDATE
-- TO public
-- USING (true);
--
-- CREATE POLICY reports_all
-- ON public.reports
-- AS PERMISSIVE
-- FOR ALL
-- TO public
-- USING (true)
-- WITH CHECK (true);


-- ============================================================
-- SMOKE CHECKLIST（DB 実行後・本番でユーザーが実施・1ログインセッション統合方式）
--   実施順の推奨：S-1 employee → S-2 admin → S-3 genka
--
--   [S-1] employee 画面（index.html）：ログイン → 日報一覧表示 →
--         既存日報を1件開き「何も変えず保存」（update_report_secure の同値 UPDATE。
--         SET 句は業務列のみで updated_at / photo / voided 列は触らないため完全無変化）
--         → 有給一覧表示 → ログアウト
--         - list_my_reports_secure / list_my_paid_leave_secure HTTP 200
--         - update_report_secure HTTP 200 または 204・一覧の内容不変
--   [S-2] admin 画面（admin-app.html）：ログイン → 請求書一覧・詳細 →
--         予算一覧 → 有給管理一覧 → 日報管理一覧 → ログアウト
--         - list_invoices_secure / get_invoice_secure / list_site_budgets_secure /
--           list_paid_leave_admin_secure / list_admin_reports_secure HTTP 200
--   [S-3] genka 画面（genka-app.html）：ログイン → 原価サマリ表示
--         （invoices + site_budgets + reports の集計）→ ログアウト
--         - list_genka_reports_secure / list_invoices_secure /
--           list_site_budgets_secure HTTP 200
--   [共通確認]
--         - Network に想定外の 401 / 403 が無い
--         - Console に赤エラーが無い
--         - 各一覧の件数が実行前と不変
-- ============================================================
