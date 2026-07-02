-- ============================================================
-- Phase 4-D：有休CSV出力 セキュアRPC（★実行済み★）
-- ============================================================
-- 【実行ステータス】実行済み
--   - 作成日：2026-07-02
--   - 実行日：2026-07-02（Supabase SQL Editor で本番反映済み）
--   - 事後確認 D/E/E-2/F すべて期待どおり（関数2本 security_definer=true /
--     search_path=public, extensions / GRANT anon,authenticated / PUBLIC EXECUTE なし /
--     既存有休RPC 5本＋追加2本＝計7本 存在）。
--
-- 目的：
--   社内確認用 月次稼働・日報詳細（CSV viewer）で
--   有休表示・残有給表示を行うための CSV 出力用 read RPC を2本追加する。
--     1. export_paid_leave_details_secure(text, date, date)
--        … 承認済み有休の明細（期間あり・有休1件/行）
--     2. export_paid_leave_balances_secure(text)
--        … 従業員別の残有給スナップショット（期間なし・従業員1人/行）
--
-- 管理者検証（重要・既存 export 4本との差異）：
--   - 既存 export 4本（csv-export-secure-rpc.sql）は admin_sessions 単経路。
--   - 本2本は有休系 RPC として list_paid_leave_admin_secure と同型の
--     「二経路検証」を採用する：
--       a. employee_sessions + employees.role = 'admin'
--       b. admin_sessions + genka_admins.is_active = true
--     どちらも不成立なら RAISE EXCEPTION。
--   - この差異は PR 本文・docs（db-migrations）にも明記する。
--
-- 共通方針（既存 export 系を踏襲）：
--   - SECURITY DEFINER / SET search_path = public, extensions（digest() 解決）
--   - 戻り値は jsonb エンベロープ { meta, warnings, rows }
--   - CREATE 時デフォルトの PUBLIC EXECUTE を REVOKE し、
--     anon / authenticated にのみ GRANT（service_role は付与しない＝既存 export 系に合わせる）
--   - テーブルへの GRANT / REVOKE は一切行わない（DEFINER がオーナー権限で読む）
--   - helper csv_export_fiscal_year(date, integer) を再利用（新規 helper は作らない）
--   - 既存 write/read RPC 5本（create_/review_/save_/list_my_/list_admin_）は不変
--
-- 対象者ポリシー：
--   - details：対象期間内の承認済み有休明細。履歴保持のため
--     employees.is_active では絞らない（退職者の過去有休も出力する）。
--   - balances：出力時点の残有給スナップショット。
--     e.is_active = true の従業員のみ対象（無効化済み従業員は除外）。
--     role='admin' は除外しない（実在従業員が管理者権限を持つ場合があるため）。
--
-- 実行方法：
--   Supabase SQL Editor で各セクションを順に実行。
--   「事前確認」→「変更（CREATE/REVOKE/GRANT）」→「事後確認」の順。
--   ※ 2026-07-02 に上記手順で実行済み（再実行時は CREATE OR REPLACE のため冪等）。
-- ============================================================


-- ============================================================
-- 事前確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- A. helper csv_export_fiscal_year が存在すること（再利用元）
--    期待：1行返る（security_definer=true）。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       p.proconfig      AS config,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'csv_export_fiscal_year'
ORDER BY p.proname;

-- B. 既存の有休系 RPC 一覧（write 3 / read 2 が存在する基準。壊していないかの確認用）
--    期待：create_/review_/save_/list_my_/list_paid_leave_admin_ が存在。
--    本ファイル実行後に export_paid_leave_details_/balances_ の2本が増える。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname LIKE '%paid_leave%'
ORDER BY p.proname;

-- C. paid_leave 2テーブルの列（案の前提確認）
--    期待：paid_leave_requests に leave_date/leave_type/status、
--          paid_leave_grants に year/granted が存在。
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('paid_leave_requests', 'paid_leave_grants')
ORDER BY table_name, ordinal_position;


-- ============================================================
-- 変更（CREATE OR REPLACE FUNCTION × 2 / REVOKE × 2 / GRANT × 2）
--   実行順：CREATE 2本 → REVOKE PUBLIC 2本 → GRANT 2本
-- ============================================================

-- ------------------------------------------------------------
-- 1. export_paid_leave_details_secure(session_token_input, date_from_input, date_to_input)
--    承認済み有休の明細。期間あり。粒度＝有休1件/行。
--    列：employee_id, employee_name, leave_date, fiscal_year, leave_type, status
--    reason は含めない。leave_type は生値（表示ラベルは閲覧側で変換）。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.export_paid_leave_details_secure(
  session_token_input text,
  date_from_input     date DEFAULT NULL,
  date_to_input       date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_is_admin boolean := false;
  v_role     text;
  v_result   jsonb;
BEGIN
  -- 二経路検証（list_paid_leave_admin_secure と同型）
  -- 経路a：employee_sessions + employees.role = 'admin'
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

  -- 経路b：admin_sessions + genka_admins.is_active
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

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- 日付範囲チェック
  IF date_from_input IS NOT NULL AND date_to_input IS NOT NULL
     AND date_from_input > date_to_input THEN
    RAISE EXCEPTION 'date_from は date_to 以前の日付を指定してください';
  END IF;

  -- 承認済み有休の明細を集約（履歴保持のため employees.is_active では絞らない）
  WITH rows AS (
    SELECT
      r.employee_id::text                            AS employee_id,
      e.name                                         AS employee_name,
      to_char(r.leave_date, 'YYYY-MM-DD')            AS leave_date,
      public.csv_export_fiscal_year(r.leave_date, 4) AS fiscal_year,   -- ★4月固定
      r.leave_type                                   AS leave_type,    -- full/am/pm 生値
      r.status                                       AS status         -- 'approved' 固定
    FROM public.paid_leave_requests r
    JOIN public.employees e ON e.id = r.employee_id
    WHERE r.status = 'approved'
      AND (date_from_input IS NULL OR r.leave_date >= date_from_input)
      AND (date_to_input   IS NULL OR r.leave_date <= date_to_input)
  )
  SELECT jsonb_build_object(
    'meta', jsonb_build_object(
       'csv_type', 'paid_leave_details',
       'generated_at', now(),
       'row_count', (SELECT count(*) FROM rows),
       'notes', jsonb_build_array(
         '承認済み(status=approved)の有休のみを対象にしています。',
         'leave_type は full/am/pm の生値です（表示ラベルは閲覧側で変換します）。',
         'fiscal_year は工事年度（4月始まり固定・leave_date 由来）です。',
         '履歴保持のため、退職などで無効化された従業員の過去有休も出力します。'
       )
    ),
    'warnings', '[]'::jsonb,
    'rows', COALESCE(
       (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.leave_date, r.employee_name) FROM rows r),
       '[]'::jsonb)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;


-- ------------------------------------------------------------
-- 2. export_paid_leave_balances_secure(session_token_input)
--    従業員別の残有給スナップショット。期間なし（全期間累積）。粒度＝従業員1人/行。
--    列：employee_id, employee_name, granted_total, used_total, remaining
--    granted_total = paid_leave_grants の全年度合計
--    used_total    = 承認済み requests の full=1.0 / am,pm=0.5 の合計
--    remaining     = granted_total - used_total
--    対象：e.is_active = true の従業員のみ（admin ロールは除外しない）。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.export_paid_leave_balances_secure(
  session_token_input text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_is_admin boolean := false;
  v_role     text;
  v_result   jsonb;
BEGIN
  -- 二経路検証（1. と同一）
  -- 経路a：employee_sessions + employees.role = 'admin'
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

  -- 経路b：admin_sessions + genka_admins.is_active
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

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- 付与＝全年度合計 / 使用＝approved(full=1.0, am/pm=0.5) / 残＝差。
  -- e.is_active = true の従業員のうち、付与か承認済み有休を持つ者を対象。
  WITH g AS (
    SELECT employee_id, SUM(granted)::numeric AS granted_total
    FROM   public.paid_leave_grants
    GROUP  BY employee_id
  ),
  u AS (
    SELECT employee_id,
           SUM(CASE WHEN leave_type = 'full' THEN 1.0 ELSE 0.5 END)::numeric AS used_total
    FROM   public.paid_leave_requests
    WHERE  status = 'approved'
    GROUP  BY employee_id
  ),
  rows AS (
    SELECT
      e.id::text                               AS employee_id,
      e.name                                   AS employee_name,
      COALESCE(g.granted_total, 0)             AS granted_total,
      COALESCE(u.used_total, 0)                AS used_total,
      COALESCE(g.granted_total, 0) - COALESCE(u.used_total, 0) AS remaining
    FROM public.employees e
    LEFT JOIN g ON g.employee_id = e.id
    LEFT JOIN u ON u.employee_id = e.id
    WHERE e.is_active = true
      AND (g.employee_id IS NOT NULL OR u.employee_id IS NOT NULL)
  )
  SELECT jsonb_build_object(
    'meta', jsonb_build_object(
       'csv_type', 'paid_leave_balances',
       'generated_at', now(),
       'row_count', (SELECT count(*) FROM rows),
       'notes', jsonb_build_array(
         '残有給は全期間の累積です（対象期間で絞り込んでいません）。',
         'granted_total は付与の全年度合計です。',
         'used_total は承認済み有休の合計（全日=1.0、午前休/午後休=0.5）です。',
         '対象は is_active=true の従業員で、付与または承認済み有休を持つ者のみです。'
       )
    ),
    'warnings', '[]'::jsonb,
    'rows', COALESCE(
       (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.employee_name) FROM rows r),
       '[]'::jsonb)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;


-- ------------------------------------------------------------
-- 3. REVOKE PUBLIC EXECUTE → GRANT EXECUTE（最小権限）
--    CREATE 時デフォルト付与の PUBLIC EXECUTE を外し、
--    anon / authenticated にのみ明示 GRANT する（既存 export 系に合わせる）。
--    ※ 実行順：CREATE 2本 → REVOKE 2本 → GRANT 2本
-- ------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.export_paid_leave_details_secure(text, date, date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.export_paid_leave_balances_secure(text)            FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.export_paid_leave_details_secure(text, date, date) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.export_paid_leave_balances_secure(text)            TO anon, authenticated;


-- ============================================================
-- 事後確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- D. 作成された関数 / SECURITY DEFINER / search_path
--    期待：2関数が security_definer=true、config に search_path=public, extensions。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       p.proconfig      AS config,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('export_paid_leave_details_secure', 'export_paid_leave_balances_secure')
ORDER BY p.proname;

-- E. EXECUTE 権限（anon / authenticated に付与され、PUBLIC が無いか）
--    期待：anon / authenticated の2行ずつ。PUBLIC は出ない。
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name IN ('export_paid_leave_details_secure', 'export_paid_leave_balances_secure')
  AND grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER BY routine_name, grantee;

-- E-2. proacl 直接確認（PUBLIC EXECUTE が外れていることの権威的チェック）
--    期待：proacl に =X/postgres（先頭空＝PUBLIC）が無い。
--          anon=X/postgres / authenticated=X/postgres が有る。
SELECT p.proname,
       p.proacl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('export_paid_leave_details_secure', 'export_paid_leave_balances_secure')
ORDER BY p.proname;

-- F. 既存 有休系 RPC 5本が変化していないことの確認
--    期待：create_/review_/save_/list_my_/list_paid_leave_admin_ が引き続き存在。
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
        'create_paid_leave_request_secure',
        'review_paid_leave_request_secure',
        'save_paid_leave_grant_secure',
        'list_my_paid_leave_secure',
        'list_paid_leave_admin_secure'
      )
ORDER BY p.proname;

-- ============================================================
-- このファイルに「含めていない」もの（PR-A の別ステップ／後続PR）：
--   - admin-app.html の ZIP 出力拡張（CSV_COLUMNS / exportCsvZip specs）… PR-A 後半
--   - docs/db-migrations.md / docs/roadmap.md への記録            … PR-A 後半
--   - csv-viewer.html の表示対応（有休カレンダー・残有給ヘッダ）    … PR-B
-- ============================================================
