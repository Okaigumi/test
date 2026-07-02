-- ============================================================
-- Phase 4-C-4：report_summary View 封鎖・不要 GRANT 整理
--                （anon / authenticated から全 REVOKE）
-- ============================================================
-- 【実行ステータス】★最終適用済み（2026-07-02）★
--   - report_summary View への anon / authenticated の全権限を REVOKE 済み。
--
--   【実行 SQL（2026-07-02）】
--     REVOKE ALL PRIVILEGES ON public.report_summary FROM anon;
--     REVOKE ALL PRIVILEGES ON public.report_summary FROM authenticated;
--       → Success. No rows returned（各文）
--     ※ PUBLIC への REVOKE は実行していない（実測で明示付与なし＝no-op のため
--        実行対象外。下記「変更」セクションのコメント方針どおり）。
--
--   【DB 事後確認結果（2026-07-02）】
--     - report_summary の relacl：
--         {postgres=arwdDxtm/postgres, service_role=arwdDxtm/postgres}
--       → anon / authenticated の項目が relacl から消滅（REVOKE 成功）。
--       → postgres / service_role は arwdDxtm のまま残存（保守用に温存）。
--     - anon          ：SELECT 不可
--     - authenticated ：SELECT 不可
--     - postgres      ：SELECT 可
--     - service_role  ：SELECT 可
--     - 下流 View 依存：0 件（変化なし）
--     - RPC 3本は SECURITY DEFINER かつ report_summary 実参照なし（維持）：
--         list_admin_reports_secure
--         list_genka_reports_secure
--         list_my_reports_secure
--     - report_summary View は DROP せず存続（relkind=v）。
--
--   【本番確認結果（2026-07-02）】
--     [従業員画面 / index.html]
--       - 従業員画面：OK
--     [管理者 / index.html 管理コンソール]
--       - 管理者ログイン：OK
--       - 管理タブ：OK
--       - 集計タブ：OK
--       - 月切替：OK
--       - 現場ドリルダウン：OK
--       - CSV 出力：OK
--     [原価 / genka-app.html]
--       - 原価画面：OK
--       - 原価 月切替：OK
--       - 原価 現場フィルタ：OK
--       - 原価サマリー：OK
--     [Network / Console]
--       - Network に report_summary（View 直参照）：なし
--       - Network に list_genka_reports_secure（RPC 経由）：あり
--       - Console 赤エラー：なし
--
--   【現在の DB 状態（2026-07-02 時点・最終）】
--     - report_summary への anon / authenticated 直接アクセスは全て遮断済み。
--     - 管理者 / 原価 / 本人日報の読み取りは read RPC 3本（SECURITY DEFINER）へ
--       一本化済み。View 直参照は本番 Network 上でも消滅を確認。
--     - report_summary View 自体は存続（DROP しない方針どおり）。
--     - service_role / postgres の SELECT は保守用に温存。
--
--   【4-C-4 とは別タスク（申し送り）】
--     - 集計タブ（index.html 管理コンソール）の CSV 出力は今回 OK だが、
--       今後は不要にしたい。CSV 出力は管理コンソール側のみに集約する方針。
--       → これは Phase 4-C-4 の範囲外。別タスクとして扱う。
--
--   ※ SQL 本文（REVOKE 2本・事前確認 A〜D・事後確認 E〜H）は変更していない。
--     本ファイルは再実行時にもそのまま使える。
--
-- 目的：
--   report_summary View への anon / authenticated の直接アクセス権
--   （INSERT/SELECT/UPDATE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN）を
--   全て REVOKE し、フロントからの View 直参照経路を封鎖する。
--   本人日報 / 管理者 / 原価いずれの読み取りも、既に SECURITY DEFINER の
--   read RPC 3本（list_my_reports_secure / list_admin_reports_secure /
--   list_genka_reports_secure）へ移行済みのため、View 直参照は不要。
--
-- このファイルの方針（確定）：
--   - View は DROP しない。report_summary View 自体は残す。
--   - postgres はそのまま（変更しない）。
--   - service_role はそのまま（保守用に SELECT 等を温存）。
--   - anon / authenticated から report_summary の権限を全 REVOKE する。
--   - 実行 SQL は REVOKE のみ。GRANT はロールバック案としてコメントに書く。
--   - PUBLIC には明示付与が無い（下記事前確認結果参照）ため、PUBLIC への
--     REVOKE は既定でコメントアウト（no-op のため実行対象に含めない）。
--
-- 実行前提（すべて完了済み）：
--   - read RPC 3本が SECURITY DEFINER で稼働中：
--       list_my_reports_secure(text, date, integer)  … 本人日報
--       list_admin_reports_secure                    … 管理者
--       list_genka_reports_secure                    … 原価
--     いずれも report_summary を実参照していない（下記事前確認結果参照）。
--   - report_summary に依存する下流 View：0 件。
--   - 他の public 関数の report_summary 実参照：0 件。
--   - reports は anon / authenticated の直接 SELECT 無し（Phase 4-C-1 済）。
--   - フロント（index.html / genka-app.html / admin-app.html）は
--     report_summary 直参照から read RPC へ移行済み（コード側で確認済み・
--     SQL では確認不可）。
--
-- 事前確認結果（Phase 4-C-4 設計前確認・確定値）：
--   - report_summary に依存する下流 View：0 件
--   - 稼働 RPC 3本は SECURITY DEFINER かつ report_summary 実参照なし
--   - 他 public 関数の report_summary 実参照：0 件
--   - reports は anon / authenticated の SELECT なし
--   - report_summary の relacl：
--       {postgres=arwdDxtm/postgres,
--        anon=arwDxtm/postgres,
--        authenticated=arwDxtm/postgres,
--        service_role=arwdDxtm/postgres}
--     ・PUBLIC エントリ（先頭が "=" の項目）は無い＝PUBLIC 明示付与なし。
--     ・anon / authenticated = a,r,w,D,x,t,m
--         = INSERT, SELECT, UPDATE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--           （DELETE=小文字 d は付いていない）。
--     ・postgres / service_role = a,r,w,d,D,x,t,m（DELETE 込み）。
--
-- 実行対象：
--   REVOKE ALL PRIVILEGES ON public.report_summary FROM anon;
--   REVOKE ALL PRIVILEGES ON public.report_summary FROM authenticated;
--   （PUBLIC はコメントアウト・下記「変更」セクション参照）
--
-- ロールバック案（概要・詳細は末尾「ロールバック SQL」参照）：
--   anon / authenticated に元の 7 権限を GRANT で戻す。
--   postgres / service_role は変更しないためロールバック不要。
--
-- 実行方法（実行する場合）：
--   Supabase SQL Editor で各セクションを順に実行。
--   「事前確認」→「変更（REVOKE）」→「事後確認」の順。
--   ※ 変更は REVOKE 2本のみ。DROP / DELETE / UPDATE / INSERT / ALTER は無い。
-- ============================================================


-- ============================================================
-- 事前確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- A. report_summary の relacl（現状の権限一覧・権威的確認）
--    期待：anon / authenticated に arwDxtm が残っている。
--          postgres / service_role は arwdDxtm。PUBLIC エントリは無い。
SELECT c.relname    AS object_name,
       c.relkind    AS relkind,      -- 'v' = view
       r.rolname    AS owner,
       c.relacl     AS relacl
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles r     ON r.oid = c.relowner
WHERE n.nspname = 'public'
  AND c.relname = 'report_summary';

-- A-2. report_summary の anon / authenticated / PUBLIC 権限（information_schema 側）
--    期待：anon / authenticated に 7 権限
--          （INSERT/SELECT/UPDATE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN）。
--          PUBLIC は 0 行（明示付与なし）。
SELECT table_name AS view_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'report_summary'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
GROUP BY table_name, grantee
ORDER BY grantee;

-- B. report_summary に依存する下流 View 依存確認
--    期待：0 行（report_summary に依存する下流ビューは存在しない）。
SELECT dependent.relname AS dependent_view,
       dependent.relkind AS dependent_kind
FROM pg_depend d
JOIN pg_rewrite rw    ON rw.oid = d.objid
JOIN pg_class  dependent ON dependent.oid = rw.ev_class
JOIN pg_class  src    ON src.oid = d.refobjid
JOIN pg_namespace n   ON n.oid = src.relnamespace
WHERE n.nspname = 'public'
  AND src.relname = 'report_summary'
  AND dependent.relname <> 'report_summary'   -- 自己参照（ビュー自身のルール）を除外
  AND dependent.relkind IN ('v', 'm')
ORDER BY dependent_view;

-- C. RPC 3本が report_summary を実参照していないことの確認
--    期待：3本とも report_summary を本文に含まない（match=false）。
--          （SECURITY DEFINER である点も併せて確認）
SELECT p.proname AS function_name,
       p.prosecdef AS security_definer,
       (pg_get_functiondef(p.oid) ILIKE '%report_summary%') AS references_report_summary
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
        'list_my_reports_secure',
        'list_admin_reports_secure',
        'list_genka_reports_secure'
      )
ORDER BY p.proname;

-- C-2. 他の public 関数まで含めた report_summary 実参照の全数確認（保険）
--    期待：0 行（report_summary を本文参照する public 関数は存在しない）。
SELECT p.proname AS function_name
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND pg_get_functiondef(p.oid) ILIKE '%report_summary%'
ORDER BY p.proname;

-- D. reports の anon / authenticated 直接 SELECT が無いことの確認
--    期待：0 行（Phase 4-C-1 で REVOKE 済み）。
SELECT table_name,
       grantee,
       privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'reports'
  AND grantee IN ('anon', 'authenticated')
  AND privilege_type = 'SELECT'
ORDER BY grantee;


-- ============================================================
-- 変更（REVOKE のみ）
-- ============================================================
-- report_summary View への anon / authenticated の全権限を REVOKE する。
-- View は DROP しない。postgres / service_role は変更しない。

REVOKE ALL PRIVILEGES ON public.report_summary FROM anon;
REVOKE ALL PRIVILEGES ON public.report_summary FROM authenticated;

-- PUBLIC について：
--   事前確認 A / A-2 のとおり、report_summary の relacl に PUBLIC エントリ
--   （先頭が "=" の項目）は存在せず、PUBLIC への明示付与は無い。
--   よって PUBLIC への REVOKE は no-op（状態は変わらない）であり、実行対象に
--   含めない方針とする（実行 SQL を最小・監査容易に保つため）。
--   もし将来 A / A-2 で PUBLIC の SELECT が観測された場合のみ、次行を有効化する。
-- REVOKE SELECT ON public.report_summary FROM PUBLIC;


-- ============================================================
-- 事後確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- E. report_summary の relacl（REVOKE 後）
--    期待：relacl から anon / authenticated の項目が消える。
--          postgres / service_role は arwdDxtm のまま残る。
SELECT c.relname    AS object_name,
       c.relkind    AS relkind,      -- 'v' = view（DROP していない担保）
       r.rolname    AS owner,
       c.relacl     AS relacl
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles r     ON r.oid = c.relowner
WHERE n.nspname = 'public'
  AND c.relname = 'report_summary';

-- E-2. anon / authenticated に権限が残っていないことの確認
--    期待：0 行（anon / authenticated の権限は全て消えている）。
SELECT table_name AS view_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'report_summary'
  AND grantee IN ('anon', 'authenticated')
GROUP BY table_name, grantee
ORDER BY grantee;

-- E-3. has_table_privilege による確定確認
--    期待：anon / authenticated の SELECT / INSERT / UPDATE がすべて false。
SELECT 'report_summary' AS view_name,
       has_table_privilege('anon',          'public.report_summary', 'SELECT') AS anon_select,
       has_table_privilege('anon',          'public.report_summary', 'INSERT') AS anon_insert,
       has_table_privilege('anon',          'public.report_summary', 'UPDATE') AS anon_update,
       has_table_privilege('authenticated', 'public.report_summary', 'SELECT') AS auth_select,
       has_table_privilege('authenticated', 'public.report_summary', 'INSERT') AS auth_insert,
       has_table_privilege('authenticated', 'public.report_summary', 'UPDATE') AS auth_update;

-- F. service_role / postgres が残っていることの確認
--    期待：service_role / postgres の SELECT が true（保守用に温存）。
SELECT 'report_summary' AS view_name,
       has_table_privilege('service_role', 'public.report_summary', 'SELECT') AS service_role_select,
       has_table_privilege('postgres',     'public.report_summary', 'SELECT') AS postgres_select;

-- G. 下流 View 依存が変わっていないことの確認（REVOKE 後も 0 件のまま）
--    期待：0 行。
SELECT dependent.relname AS dependent_view,
       dependent.relkind AS dependent_kind
FROM pg_depend d
JOIN pg_rewrite rw    ON rw.oid = d.objid
JOIN pg_class  dependent ON dependent.oid = rw.ev_class
JOIN pg_class  src    ON src.oid = d.refobjid
JOIN pg_namespace n   ON n.oid = src.relnamespace
WHERE n.nspname = 'public'
  AND src.relname = 'report_summary'
  AND dependent.relname <> 'report_summary'
  AND dependent.relkind IN ('v', 'm')
ORDER BY dependent_view;

-- H. RPC 3本が report_summary 非依存のままであることの確認
--    期待：3本とも references_report_summary = false・security_definer = true。
SELECT p.proname AS function_name,
       p.prosecdef AS security_definer,
       (pg_get_functiondef(p.oid) ILIKE '%report_summary%') AS references_report_summary
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
        'list_my_reports_secure',
        'list_admin_reports_secure',
        'list_genka_reports_secure'
      )
ORDER BY p.proname;


-- ============================================================
-- ロールバック SQL（コメントのみ・通常は実行しない）
-- ============================================================
-- 元の状態へ戻す場合は、anon / authenticated に元の 7 権限を GRANT で戻す。
-- （relacl の arwDxtm と一致：INSERT/SELECT/UPDATE/TRUNCATE/REFERENCES/
--   TRIGGER/MAINTAIN。DELETE は元々付いていないので戻さない。）
--
--   GRANT INSERT, SELECT, UPDATE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--     ON public.report_summary TO anon;
--   GRANT INSERT, SELECT, UPDATE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--     ON public.report_summary TO authenticated;
--
-- service_role / postgres は本ファイルで変更しないため、ロールバック不要。


-- ============================================================
-- 危険 SQL チェック（実行済み・2026-07-02 実測反映）
--   - DROP        なし（View は残した：事後確認 relkind=v で確認済み）
--   - DELETE      なし
--   - UPDATE      なし
--   - INSERT      なし
--   - ALTER TABLE なし
--   - REVOKE 対象は public.report_summary のみ（anon / authenticated）
--   - PUBLIC への REVOKE は実行せず（実測で明示付与なし＝no-op・対象外）
--   - 実際に実行した変更行は REVOKE 2本のみ。残りは SELECT（確認）とコメント。
--   - 実行結果：Success. No rows returned（各文）。想定外の副作用なし。
-- ============================================================
