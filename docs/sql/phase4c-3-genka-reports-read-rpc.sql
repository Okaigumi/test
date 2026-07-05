-- ============================================================
-- Phase 4-C-3：genka 原価系 report_summary 代替 read RPC 追加
--   （list_genka_reports_secure）
-- ============================================================
-- 【実行ステータス】★実行済み（2026-07-01）★
--   - Supabase SQL Editor で「事前確認A〜H」→「変更（CREATE / REVOKE / GRANT）」
--     →「事後確認I〜N」の順に実行済み。
--   - 実行結果：
--       CREATE OR REPLACE FUNCTION public.list_genka_reports_secure(text, date, date, uuid)
--                                                              … Success. No rows returned
--       REVOKE EXECUTE ... FROM PUBLIC                        … Success. No rows returned
--       GRANT EXECUTE ... TO anon, authenticated, service_role … Success. No rows returned
--   - 事後確認I〜M：OK
--       I 関数存在・SECURITY DEFINER=true・search_path=public, extensions・
--         args=(session_token_input text, from_date_input date,
--               to_date_input date, site_id_input uuid)：OK
--       J EXECUTE：anon / authenticated / service_role = true：OK
--       J-2 PUBLIC EXECUTE：なし（proacl に =X/postgres なし）：OK
--       K report_summary 実SQL参照なし：OK
--           from public.report_summary = 0 / join public.report_summary = 0 /
--           from report_summary = 0 / join report_summary = 0
--           （事前確認G のコメント内に現れる report_summary 文字列は診断用で問題なし）
--       L reports 権限：未変更（anon / authenticated の直接 SELECT なし）：OK
--       M report_summary 権限：未変更（anon / authenticated SELECT あり・
--           封鎖は 4-C-4 対象）：OK
--   - 動作確認N：OK
--       場所：https://system.okaigumi.co.jp/genka
--       genka 管理者ログイン状態の Console から
--         sb.rpc('list_genka_reports_secure', ...) を実行：
--         success=true / error=null / data=Array(4) / status=200
--
--   【DB事前確認結果の記録（2026-07-01 Supabase・実行済みの調査結果）】
--       A reports 必要列9列：OK
--           report_date / employee_id / normal_mins / overtime_mins /
--           site_ids / subcontractor_ids / dump_count / dump_company / guard_count
--       B report_summary 対応列9列：OK（A と同型で View に存在）
--       C list_admin_reports_secure 二経路認可ロジック：流用 OK
--           （4-C-2 の inline 二経路検証をそのまま踏襲）
--       D admin_sessions / genka_admins 必要列：OK
--           admin_sessions(admin_id, token_hash, expires_at) /
--           genka_admins(id, is_active)
--       E reports の anon / authenticated 直接 SELECT：なし（4-C-1 で REVOKE 済）OK
--       F NULL傾向：OK
--           reports rows       = 135
--           dump_company_null  = 131（NULL 多いが front で '未選択' に吸収）
--           sub_ids_null       = 0
--           site_ids_null      = 0
--           min_date           = 2026-06-01
--           max_date           = 2026-07-06
--           list_genka_reports_secure 未存在：OK（新規）
--       G site_ids フィルタ等価性（contains ⇔ @>）：OK
--           reports_count        = 31
--           report_summary_count = 31
--           counts_match         = true
--       H reports 単独で必要列充足（employees JOIN 不要）：OK
--
--   【このファイルで変更していないもの（実行後も不変）】
--   - report_summary View の権限・定義・封鎖：未実施（→ Phase 4-C-4）
--   - reports の SELECT 等の権限：未変更
--   - policy（reports_all 等）：未変更
--   - 既存 RPC（list_admin_reports_secure / reports write / paid_leave / csv 等）：未変更
--   - genka-app.html のフロント移行（loadData）：未実施（別ステップ）
--   - docs（roadmap / db-migrations 等）への記録：未実施（別ステップ）
--
-- 目的：
--   genka-app.html の原価集計（loadData）が現在直接参照している
--   report_summary View を、将来 View 封鎖できるよう
--   管理者セッション検証付きの read RPC 経由へ移行する。その前段として
--   本 RPC を1本 additive に追加する（新旧併存）。
--
-- 対象フロント（移行先）：
--   - genka-app.html loadData（対象月・from=月初 / to=月末、現場フィルタ siteId）
--     ※ genka は日報を原価計算の集計にのみ使用し、個票 DOM を出さないため、
--        供給元が本 RPC に変わるだけで集計ロジックの改修は原則不要。
--
-- 【重要方針】report_summary は参照しない（report_summary 非依存）：
--   実測（2026-07-01 Supabase）で、genka が使う9列
--     employee_id / report_date / normal_mins / overtime_mins /
--     site_ids / subcontractor_ids / dump_count / dump_company / guard_count
--   は すべて public.reports の列であることを確認済み（事前確認 A / H）。
--   genka は employee_name を使わないため employees JOIN も不要。
--   よって本 RPC は report_summary を参照せず、reports 単独から
--   同等の結果を生成する（4-C-4 で View を封鎖しても本 RPC は影響を受けない）。
--
-- 認可方式（4-C-2 list_admin_reports_secure と同じ二経路検証・inline）：
--   - 共通ヘルパーは新設せず、inline で検証する。
--   - token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
--   - 経路A：employee_sessions + employees（role='admin' かつ is_active=true）
--   - 経路B：admin_sessions + genka_admins（is_active=true）
--   - どちらも不成立なら RAISE EXCEPTION 'Invalid or expired session'。
--   ※ genka の実利用は経路B（admin_sessions + genka_admins）だが、
--     4-C-2 と実装パターンを揃えるため二経路のまま踏襲する。
--
-- 【EXECUTE 権限の方針（Phase 4-B / 4-C-1 / 4-C-2 と同一）】
--   - 新規関数は CREATE 時にデフォルト付与される PUBLIC EXECUTE を外す。
--   - anon / authenticated / service_role にのみ EXECUTE を明示 GRANT する。
--     （genka-app.html は anon key で動作するため anon への GRANT が必須）
--
-- このファイルの方針（重要）：
--   - report_summary View は一切触らない（権限・定義とも変更しない）。
--     → View 封鎖・不要 GRANT 整理は Phase 4-C-4 で実施。
--   - reports の権限（SELECT 等）を変更しない。
--   - reports の policy（reports_all）を変更しない。
--   - 既存 list_admin_reports_secure は一切変更しない。
--   - index.html / admin-app.html は触らない。
--   - フロント移行前の「新旧併存」用。既存の直接 SELECT と新 RPC が
--     同時に成立する状態を作る。
--
-- 実行方法（実行する場合）：
--   Supabase SQL Editor で各セクションを順に実行。
--   「事前確認」→「変更（CREATE / REVOKE / GRANT）」→「事後確認」の順。
--   ※ 実行順：CREATE 1本 → REVOKE PUBLIC 1本 → GRANT 1本。
--
-- 検証パターンの流用元：
--   - 二経路管理者検証：phase4c-2-admin-reports-read-rpc.sql の list_admin_reports_secure
--   - read RPC の枠組み：phase4c-1-my-reports-read-rpc.sql の list_my_reports_secure
--   - site_ids 配列フィルタ（@>）：genka-app.html loadData の contains('site_ids',[siteId])
-- ============================================================


-- ============================================================
-- 事前確認A〜H（SELECTのみ・DB状態は変更しない）
--   ※ 2026-07-01 に実行済み（結果は上部ヘッダに記録）。
--      再実行しても DB は変更されない。
-- ============================================================

-- A. reports の必要列9列の存在・型・NULL可否（RETURNS TABLE の型合わせ根拠）
--    期待：report_date date / employee_id uuid /
--          normal_mins,overtime_mins,dump_count,guard_count integer /
--          site_ids,subcontractor_ids uuid[]（udt_name='_uuid'） /
--          dump_company text。
SELECT column_name, data_type, udt_name, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'reports'
  AND column_name IN (
        'report_date', 'employee_id', 'normal_mins', 'overtime_mins',
        'site_ids', 'subcontractor_ids', 'dump_count', 'dump_company', 'guard_count'
      )
ORDER BY column_name;

-- B. report_summary が上記 reports 列をそのまま持つか（移行前後の集計一致の根拠）
--    期待：A と同じ9列・同型が View に存在。
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'report_summary'
  AND column_name IN (
        'report_date', 'employee_id', 'normal_mins', 'overtime_mins',
        'site_ids', 'subcontractor_ids', 'dump_count', 'dump_company', 'guard_count'
      )
ORDER BY column_name;

-- C. 既存 list_admin_reports_secure の定義（二経路認可ロジックの流用元確認）
--    期待：1件・security_definer=true・volatility='s'（STABLE）・
--          定義本文に二経路検証（employee_sessions+admin / admin_sessions+genka_admins）と
--          SET search_path。→ 本 RPC はこの認可・宣言部を踏襲。
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS args,
       p.prosecdef                               AS security_definer,
       p.provolatile                             AS volatility,
       pg_get_functiondef(p.oid)                 AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_admin_reports_secure';

-- D. admin_sessions / genka_admins の必要列（genka 経路の認可に使用）
--    期待：admin_sessions(admin_id, token_hash, expires_at) /
--          genka_admins(id, is_active)。
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
        (table_name = 'admin_sessions' AND column_name IN ('admin_id', 'token_hash', 'expires_at'))
     OR (table_name = 'genka_admins'   AND column_name IN ('id', 'is_active'))
      )
ORDER BY table_name, column_name;

-- E. reports の anon/authenticated 直接権限（現況把握・SECURITY DEFINER 前提の裏取り）
--    期待：4-C-1 で SELECT は REVOKE 済（＝出ない）。
--          本 RPC は SECURITY DEFINER なので anon の reports 直 SELECT が無くても動く。
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name   = 'reports'
  AND grantee IN ('anon', 'authenticated')
ORDER BY grantee, privilege_type;

-- F. 実データでの NULL 傾向・値域（型確定の補助）
--    期待（2026-07-01 実測）：rows=135 / dump_company_null=131 /
--          sub_ids_null=0 / site_ids_null=0 /
--          min_date=2026-06-01 / max_date=2026-07-06。
SELECT
  count(*)                                          AS rows,
  count(*) FILTER (WHERE dump_company IS NULL)       AS dump_company_null,
  count(*) FILTER (WHERE subcontractor_ids IS NULL)  AS sub_ids_null,
  count(*) FILTER (WHERE site_ids IS NULL)           AS site_ids_null,
  min(report_date)                                  AS min_date,
  max(report_date)                                  AS max_date
FROM public.reports;

-- G. site_ids フィルタ等価性（genka の contains ⇔ RPC の @> が一致するか）
--    現在の genka は .contains('site_ids',[siteId]) を使用。RPC は同月・同現場を
--    site_ids @> ARRAY[:siteId]::uuid[] で再現する。両者の件数が一致することを確認。
--    ※ :from / :to / :siteId は確認時に対象月・任意現場を指定して実行する。
--    期待（実測）：reports_count = report_summary_count = 31、counts_match = true。
SELECT
  (SELECT count(*) FROM public.reports r
     WHERE r.report_date >= :from AND r.report_date <= :to
       AND r.site_ids @> ARRAY[:siteId]::uuid[])                    AS reports_count,
  (SELECT count(*) FROM public.report_summary v
     WHERE v.report_date >= :from AND v.report_date <= :to
       AND v.site_ids @> ARRAY[:siteId]::uuid[])                    AS report_summary_count,
  (
    (SELECT count(*) FROM public.reports r
       WHERE r.report_date >= :from AND r.report_date <= :to
         AND r.site_ids @> ARRAY[:siteId]::uuid[])
    =
    (SELECT count(*) FROM public.report_summary v
       WHERE v.report_date >= :from AND v.report_date <= :to
         AND v.site_ids @> ARRAY[:siteId]::uuid[])
  )                                                                 AS counts_match;

-- H. list_genka_reports_secure がまだ存在しないことの確認
--    期待：0行（新規）。既に存在する場合は CREATE OR REPLACE で置換される。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_genka_reports_secure'
ORDER BY p.proname;


-- ============================================================
-- 変更（CREATE OR REPLACE FUNCTION × 1 / REVOKE × 1 / GRANT × 1）
--   実行順：CREATE 1本 → REVOKE PUBLIC 1本 → GRANT 1本
-- ============================================================

-- ------------------------------------------------------------
-- 1. list_genka_reports_secure(session_token_input, from_date_input,
--                              to_date_input, site_id_input)
--    原価管理用。二経路（employee_sessions role=admin / admin_sessions+genka_admins）で
--    セッション検証し、日付範囲（＋任意の現場フィルタ）で日報の原価関連列を返す。
--    report_summary は参照せず、reports 単独から生成する（employees JOIN 不要）。
--      - loadData: from_date_input = 月初, to_date_input = 月末,
--                  site_id_input = 現場フィルタ（未選択なら NULL）
--    並び順：report_date DESC（genka は map 集計のため順序非依存。parity 目的）。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_genka_reports_secure(
  session_token_input text,
  from_date_input     date DEFAULT NULL,
  to_date_input       date DEFAULT NULL,
  site_id_input       uuid DEFAULT NULL
)
RETURNS TABLE (
  report_date        date,
  employee_id        uuid,
  normal_mins        integer,
  overtime_mins      integer,
  site_ids           uuid[],
  subcontractor_ids  uuid[],
  dump_count         integer,
  dump_company       text,
  guard_count        integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_role     text;
  v_is_admin boolean := false;
BEGIN
  -- 経路A：employee_sessions の管理者
  --   （token 一致 / 未失効 / employees.is_active=true / role='admin'）
  SELECT e.role
  INTO   v_role
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true
  LIMIT 1;

  IF FOUND AND v_role = 'admin' THEN
    v_is_admin := true;
  END IF;

  -- 経路B：admin_sessions + genka_admins（genka の実利用経路）
  IF NOT v_is_admin THEN
    IF EXISTS (
      SELECT 1
      FROM   public.admin_sessions s
      JOIN   public.genka_admins g ON g.id = s.admin_id
      WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
        AND  s.expires_at > now()
        AND  g.is_active  = true
    ) THEN
      v_is_admin := true;
    END IF;
  END IF;

  -- どちらの経路でも管理者と確認できなければ拒否
  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- 日付範囲の防御的チェック（4-C-2 と同じ例外文）
  IF from_date_input IS NOT NULL AND to_date_input IS NOT NULL
     AND from_date_input > to_date_input THEN
    RAISE EXCEPTION 'from_date は to_date 以前の日付を指定してください';
  END IF;

  -- 原価集計用の日報列を日付範囲（＋任意の現場）で返す。
  --   report_summary は参照せず reports 単独から生成（4-C-4 の View 封鎖に耐える）。
  --   site_id_input がある場合は site_ids 配列に含む行のみ
  --   （genka の contains('site_ids',[siteId]) と等価な @> で再現）。
  RETURN QUERY
  SELECT r.report_date,
         r.employee_id,
         r.normal_mins,
         r.overtime_mins,
         r.site_ids,
         r.subcontractor_ids,
         r.dump_count,
         r.dump_company,
         r.guard_count
  FROM   public.reports r
  WHERE  (from_date_input IS NULL OR r.report_date >= from_date_input)
    AND  (to_date_input   IS NULL OR r.report_date <= to_date_input)
    AND  (site_id_input   IS NULL OR r.site_ids @> ARRAY[site_id_input]::uuid[])
  ORDER  BY r.report_date DESC;
END;
$$;


-- ------------------------------------------------------------
-- 2. REVOKE PUBLIC EXECUTE → GRANT EXECUTE（最小権限）
--    CREATE FUNCTION 時にデフォルト付与される PUBLIC の EXECUTE を外し、
--    anon / authenticated / service_role にのみ明示的に付与する。
--    （SECURITY DEFINER のため、後フェーズで report_summary / reports の
--      直接 SELECT を REVOKE しても RPC 経由の読み取りは動作継続する）
--    ※ 実行順：CREATE 1本 → REVOKE 1本 → GRANT 1本
--    ※ 引数リストは (text, date, date, uuid)。
-- ------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.list_genka_reports_secure(text, date, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_genka_reports_secure(text, date, date, uuid) TO anon, authenticated, service_role;


-- ============================================================
-- 事後確認I〜N（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- I. 作成された関数 / SECURITY DEFINER / search_path / args
--    期待：list_genka_reports_secure が security_definer=true、
--          config に search_path=public, extensions、
--          args=(session_token_input text, from_date_input date,
--                to_date_input date, site_id_input uuid)。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       p.proconfig      AS config,           -- {search_path=public, extensions} を期待
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_genka_reports_secure'
ORDER BY p.proname;

-- J. EXECUTE 権限（anon / authenticated / service_role に付与されているか）
--    期待：anon / authenticated / service_role の3行が出る。
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name = 'list_genka_reports_secure'
  AND grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER BY routine_name, grantee;

-- J-2. proacl 直接確認（PUBLIC EXECUTE が外れていることの権威的チェック）
--    期待：proacl に =X/postgres（先頭が空＝PUBLIC）が無い。
--          anon=X/postgres / authenticated=X/postgres / service_role=X/postgres が有る。
SELECT p.proname,
       p.proacl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_genka_reports_secure'
ORDER BY p.proname;

-- K. list_genka_reports_secure が report_summary を参照していないことの確認
--    期待：0行（定義本文に 'report_summary' の文字列が現れない）。
SELECT p.proname,
       (pg_get_functiondef(p.oid) ILIKE '%report_summary%') AS references_report_summary
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'list_genka_reports_secure'
  AND pg_get_functiondef(p.oid) ILIKE '%report_summary%';

-- L. reports の権限が未変更であることの確認
--    期待：Phase 4-C-1 完了後の状態（anon/authenticated の直接 SELECT は
--          REVOKE 済＝出ない。INSERT/UPDATE/DELETE も無い）から変化していないこと。
--    ※ 本ファイルは reports 権限を一切変更しない。
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

-- M. report_summary が未変更であることの確認（今回触っていない担保）
--    期待：view のまま、anon / authenticated の SELECT も従来どおり残存
--          （REVOKE / View 封鎖は 4-C-4 で実施）。
SELECT table_name AS view_name,
       grantee,
       privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'report_summary'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND privilege_type = 'SELECT'
ORDER BY grantee;

-- N. 動作確認の観点（実トークンは本ファイルに書かない）
--    Supabase 上での確認は以下の観点で行う（フロント or SQL Editor）：
--      N-1. 有効な genka 管理者セッショントークンで
--             SELECT * FROM public.list_genka_reports_secure(:token, :from, :to, NULL);
--           を実行し、report_summary を同一範囲で SELECT した結果と
--           件数・内容（report_date/employee_id/各原価列）が一致すること。
--      N-2. site_id_input を指定し、genka の contains('site_ids',[siteId]) と
--           同じ現場フィルタ結果になること（事前確認 G と同じ 31 件等）。
--      N-3. 非管理者（従業員）トークン / 無効・期限切れトークンで
--             'Invalid or expired session' が返る（行が返らない）こと。
--      N-4. from > to を渡すと 'from_date は to_date 以前…' の例外になること。
--    ※ 実トークンは SQL ファイルに記載しない。


-- ============================================================
-- このSQLで「行わない」こと（危険SQLチェック）：
--   - DROP TABLE / DROP VIEW なし
--   - DELETE / TRUNCATE なし
--   - ALTER TABLE なし
--   - データ UPDATE / INSERT なし（関数定義以外の DML なし）
--   - report_summary の権限変更・定義変更・封鎖なし（→ Phase 4-C-4）
--   - reports の SELECT 権限変更なし
--   - policy（reports_all 等）の変更・削除なし
--   - View 封鎖なし
--   - 既存 RPC（list_admin_reports_secure / reports write / paid_leave / csv 等）の変更なし
--   本ファイルの変更は「関数1本の CREATE OR REPLACE ＋ その EXECUTE 権限の
--   REVOKE PUBLIC / GRANT」のみ（additive）。
-- ============================================================
