-- ============================================================
-- 日報無効化（soft-void）PR-B:
--   A. 既存 read/export RPC に is_voided=false 除外を追加（本体のみ再定義）
--   B. admin_void_report_secure（管理者のみ・理由必須・無効化結果を返す）新設
--   C. list_admin_reports_with_voided_secure（無効化済み確認用・監査列付き）新設
--   D. 新設2関数の権限（REVOKE PUBLIC → GRANT anon,authenticated,service_role）
-- ============================================================
-- 【前提】PR-A（docs/sql/report-void-columns.sql）で reports に
--   is_voided / voided_at / voided_by / voided_by_role / void_reason ＋CHECK2本を
--   追加済み（2026-07-06 実行済み・既存151件はすべて is_voided=false）。
--
-- 【このファイルの方針（重要）】
--   - A の5関数は「本体（RETURN QUERY / WITH）」のみ再定義し、WHERE 末尾に
--     `AND r.is_voided = false` を1行足すだけ。引数・戻り列・LANGUAGE・SECURITY/検証・
--     認可・GRANT は変更しない。CREATE OR REPLACE は既存 ACL を保持するため、
--     既存関数の REVOKE/GRANT は再発行しない（権限不変）。
--   - reports への直接 UPDATE 権限は付与しない。無効化は admin_void_report_secure
--     （SECURITY DEFINER）経由のみ。RLS / policy は変更しない。
--   - 物理削除はしない。復元RPCは今回作らない（is_voided フラグ方式で将来対応可）。
--   - 既存 list_admin_reports_secure はシグネチャ維持（通常集計用）。無効化済み確認は
--     別関数 list_admin_reports_with_voided_secure（PR-C の管理者UI用）で行う。
--
-- 【実行ステータス】★未実行★
--   - ユーザーが Supabase SQL Editor で実行予定（Claude からの DB 実行なし）。
--   - 実行後、docs/db-migrations.md の該当エントリを「実行済み」に更新する。
-- ============================================================


-- ------------------------------------------------------------
-- 事前確認（読み取りのみ）
--   P1: 対象関数の現行シグネチャ（DROP不要・CREATE OR REPLACE で置換できることの確認）
--   P2: reports の有効/無効件数（実行前ベースライン）
-- ------------------------------------------------------------
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, p.prosecdef
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_my_reports_secure','list_admin_reports_secure',
                     'list_genka_reports_secure','export_projects_summary_secure',
                     'export_attendance_details_secure',
                     'admin_void_report_secure','list_admin_reports_with_voided_secure')
ORDER  BY p.proname;

SELECT count(*) FILTER (WHERE is_voided = false) AS active_rows,
       count(*) FILTER (WHERE is_voided = true)  AS voided_rows,
       count(*)                                  AS total_rows
FROM   public.reports;


-- ============================================================
-- A. read/export RPC への is_voided=false 除外（本体のみ再定義）
-- ============================================================

-- A-1. list_my_reports_secure（本人履歴・本人カレンダー）
--   変更点：WHERE 末尾に `AND r.is_voided = false` を追加（他は現行と同一）。
CREATE OR REPLACE FUNCTION public.list_my_reports_secure(
  session_token_input text,
  before_date_input   date    DEFAULT NULL,
  limit_input         integer DEFAULT 30
)
RETURNS TABLE (
  id                  uuid,
  report_date         date,
  employee_id         uuid,
  start_time          time,
  end_time            time,
  normal_mins         integer,
  overtime_mins       integer,
  site_ids            uuid[],
  material_ids        uuid[],
  material_quantities jsonb,
  subcontractor_ids   uuid[],
  sub_machines        jsonb,
  work_type           text,
  memo                text,
  photo_count         integer,
  photo_urls          text[],
  dump_count          integer,
  dump_company        text,
  guard_count         integer,
  status              text,
  created_at          timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
  v_limit       integer;
BEGIN
  -- セッション検証：トークンから employee_id をサーバ側で確定
  -- （employees を JOIN し is_active = true も確認：Phase 4-B read と同型）
  SELECT es.employee_id
  INTO   v_employee_id
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true
  LIMIT 1;

  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- limit を 1〜100 に丸める（NULL は既定 30 扱い）
  v_limit := GREATEST(1, LEAST(COALESCE(limit_input, 30), 100));

  -- 本人分の reports 行のみ返す
  -- （employee_id は v_employee_id 固定。before_date_input があれば
  --   report_date < before_date_input を付与＝前日コピー用）
  RETURN QUERY
  SELECT r.id,
         r.report_date,
         r.employee_id,
         r.start_time,
         r.end_time,
         r.normal_mins,
         r.overtime_mins,
         r.site_ids,
         r.material_ids,
         r.material_quantities,
         r.subcontractor_ids,
         r.sub_machines,
         r.work_type,
         r.memo,
         r.photo_count,
         r.photo_urls,
         r.dump_count,
         r.dump_company,
         r.guard_count,
         r.status,
         r.created_at
  FROM   public.reports r
  WHERE  r.employee_id = v_employee_id
    AND  (before_date_input IS NULL OR r.report_date < before_date_input)
    AND  r.is_voided = false          -- ★PR-B: 無効化済みを除外
  ORDER  BY r.report_date DESC
  LIMIT  v_limit;
END;
$$;


-- A-2. list_admin_reports_secure（管理者集計・通常用／シグネチャ維持）
--   変更点：WHERE 末尾に `AND r.is_voided = false` を追加（他は現行と同一）。
CREATE OR REPLACE FUNCTION public.list_admin_reports_secure(
  session_token_input text,
  from_date_input     date DEFAULT NULL,
  to_date_input       date DEFAULT NULL
)
RETURNS TABLE (
  report_date         date,
  employee_id         uuid,
  employee_name       text,
  start_time          time without time zone,
  end_time            time without time zone,
  normal_mins         integer,
  overtime_mins       integer,
  site_ids            uuid[],
  material_ids        uuid[],
  material_quantities jsonb,
  memo                text
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

  -- 経路B：admin_sessions + genka_admins
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

  -- 日付範囲の防御的チェック（csv RPC と同様）
  IF from_date_input IS NOT NULL AND to_date_input IS NOT NULL
     AND from_date_input > to_date_input THEN
    RAISE EXCEPTION 'from_date は to_date 以前の日付を指定してください';
  END IF;

  -- 全従業員分の日報を日付範囲で返す（report_summary 相当を reports+employees で生成）
  RETURN QUERY
  SELECT r.report_date,
         r.employee_id,
         e.name AS employee_name,
         r.start_time,
         r.end_time,
         r.normal_mins,
         r.overtime_mins,
         r.site_ids,
         r.material_ids,
         r.material_quantities,
         r.memo
  FROM   public.reports r
  JOIN   public.employees e ON e.id = r.employee_id
  WHERE  (from_date_input IS NULL OR r.report_date >= from_date_input)
    AND  (to_date_input   IS NULL OR r.report_date <= to_date_input)
    AND  r.is_voided = false          -- ★PR-B: 無効化済みを除外
  ORDER  BY r.report_date DESC, e.name;
END;
$$;


-- A-3. list_genka_reports_secure（原価集計）
--   変更点：WHERE 末尾に `AND r.is_voided = false` を追加（他は現行と同一）。
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
    AND  r.is_voided = false          -- ★PR-B: 無効化済みを除外
  ORDER  BY r.report_date DESC;
END;
$$;


-- A-4. export_projects_summary_secure（CSV: 工事別原価）
--   変更点：rep CTE の WHERE 末尾に `AND r.is_voided = false` を追加（他は現行と同一）。
CREATE OR REPLACE FUNCTION public.export_projects_summary_secure(
  session_token_input            text,
  fiscal_year_start_month_input  integer DEFAULT 4,   -- 受取・検証・meta反映のみ（列は4月固定）
  site_id_input                  uuid    DEFAULT NULL,
  company_id_input               uuid    DEFAULT NULL,
  site_category_id_input         uuid    DEFAULT NULL,
  company_category_id_input      uuid    DEFAULT NULL,
  include_inactive_sites_input   boolean DEFAULT false,
  include_pending_reports_input  boolean DEFAULT true,
  invoice_statuses_input         text[]  DEFAULT ARRAY['confirmed','posted'],
  date_from_input                date    DEFAULT NULL,
  date_to_input                  date    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_allowed          text[] := ARRAY['uploaded','extracted','suggested','confirmed','posted','rejected'];
  v_statuses         text[];
  v_pending          boolean;
  v_include_inactive boolean;
  v_fy_start         integer;
  v_result           jsonb;
BEGIN
  -- 1) 管理者セッション検証
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'セッションが無効または期限切れです';
  END IF;

  -- 2) fiscal_year_start_month（NULL→4 / 4・9のみ）。列計算には使わない
  v_fy_start := COALESCE(fiscal_year_start_month_input, 4);
  IF v_fy_start NOT IN (4, 9) THEN
    RAISE EXCEPTION 'fiscal_year_start_month は 4 または 9 のみ指定できます';
  END IF;

  -- 3) 日付範囲チェック
  IF date_from_input IS NOT NULL AND date_to_input IS NOT NULL
     AND date_from_input > date_to_input THEN
    RAISE EXCEPTION 'date_from は date_to 以前の日付を指定してください';
  END IF;

  -- 4) invoice_statuses（NULL全体→既定／NULL要素・不正値を弾く）
  v_statuses := COALESCE(invoice_statuses_input, ARRAY['confirmed','posted']);
  IF EXISTS (SELECT 1 FROM unnest(v_statuses) x WHERE x IS NULL OR x <> ALL(v_allowed)) THEN
    RAISE EXCEPTION 'invoice_statuses に NULL または許可されない値が含まれています';
  END IF;

  -- 5) boolean NULL対策
  v_pending          := COALESCE(include_pending_reports_input, true);
  v_include_inactive := COALESCE(include_inactive_sites_input, false);

  WITH
  -- 対象site集合（全フィルタをここで一元化）
  filtered_sites AS (
    SELECT s.*
    FROM   public.sites s
    LEFT JOIN public.companies co ON co.id = s.company_id
    WHERE  (v_include_inactive OR s.is_active = true)
      AND  (site_id_input             IS NULL OR s.id          = site_id_input)
      AND  (company_id_input          IS NULL OR s.company_id  = company_id_input)
      AND  (site_category_id_input    IS NULL OR s.category_id = site_category_id_input)
      AND  (company_category_id_input IS NULL OR co.category_id = company_category_id_input)
  ),
  -- 日報を site_id 単位に展開(現場なし＝空配列は除外＝工事別原価対象外)
  rep AS (
    SELECT r.id, r.report_date, r.employee_id,
           r.normal_mins, r.overtime_mins,
           r.subcontractor_ids, r.dump_count, r.dump_company, r.guard_count,
           x.site_id,
           array_length(r.site_ids, 1) AS site_count
    FROM   public.reports r
    CROSS JOIN LATERAL unnest(r.site_ids) AS x(site_id)
    WHERE  array_length(r.site_ids, 1) >= 1          -- 現場なし日報は除外
      AND  (v_pending OR r.status = 'confirmed')
      AND  (date_from_input IS NULL OR r.report_date >= date_from_input)
      AND  (date_to_input   IS NULL OR r.report_date <= date_to_input)
      AND  r.is_voided = false          -- ★PR-B: 無効化済みを除外
  ),
  -- 労務費：gated。中間numeric保持（残業も丸めない）。site_count で均等按分
  labor_cte AS (
    SELECT rep.site_id,
           SUM(
             CASE WHEN rep.normal_mins > 0
                  THEN rt.daily_rate
                       + rep.overtime_mins / 60.0 * (rt.daily_rate / 8.0) * 1.25
                  ELSE 0 END
             / rep.site_count
           ) AS labor_cost   -- numeric（未丸め）
    FROM   rep
    CROSS JOIN LATERAL public.csv_export_effective_daily_rate(rep.employee_id, rep.report_date) rt
    GROUP  BY rep.site_id
  ),
  -- 日報由来 外注費（中間 numeric）
  rep_sub_cte AS (
    SELECT rep.site_id,
           SUM(COALESCE(ur.unit_price, 0)::numeric / rep.site_count) AS report_subcontract_cost
    FROM   rep
    CROSS JOIN LATERAL unnest(rep.subcontractor_ids) AS sc(subcontractor_id)
    JOIN   public.subcontractors sub ON sub.id = sc.subcontractor_id
    LEFT JOIN public.unit_rates ur
           ON ur.category = 'subcontractor' AND ur.name = sub.name
    GROUP  BY rep.site_id
  ),
  -- ダンプ費：dump_company がNULLなら未マッチ＝0円。中間 numeric
  dump_cte AS (
    SELECT rep.site_id,
           SUM((rep.dump_count * COALESCE(ur.unit_price, 0))::numeric / rep.site_count) AS dump_cost
    FROM   rep
    LEFT JOIN public.unit_rates ur
           ON ur.category = 'dump' AND ur.name = rep.dump_company
    WHERE  rep.dump_count > 0
    GROUP  BY rep.site_id
  ),
  -- 警備費（中間 numeric）
  guard_cte AS (
    SELECT rep.site_id,
           SUM((rep.guard_count * COALESCE(ur.unit_price, 0))::numeric / rep.site_count) AS guard_cost
    FROM   rep
    LEFT JOIN public.unit_rates ur
           ON ur.category = 'guard' AND ur.name = '警備員'
    WHERE  rep.guard_count > 0
    GROUP  BY rep.site_id
  ),
  -- 請求書：site_id 単位で事前集計（machine は machine_lease のみ）
  inv_cte AS (
    SELECT i.site_id,
           SUM(CASE WHEN i.category = 'subcontract'  THEN i.amount ELSE 0 END) AS invoice_subcontract_cost,
           SUM(CASE WHEN i.category = 'material'      THEN i.amount ELSE 0 END) AS material_cost,
           SUM(CASE WHEN i.category = 'machine_lease' THEN i.amount ELSE 0 END) AS machine_cost,
           SUM(CASE WHEN i.category = 'other'         THEN i.amount ELSE 0 END) AS other_cost
    FROM   public.invoices i
    WHERE  i.site_id IS NOT NULL
      AND  i.status = ANY(v_statuses)
      AND  (date_from_input IS NULL OR i.invoice_date >= date_from_input)
      AND  (date_to_input   IS NULL OR i.invoice_date <= date_to_input)
    GROUP  BY i.site_id
  ),
  -- 予算：filtered_sites 基準・year=fiscal_year(4月固定)・month IS NULL・is_active、件数取得
  budget_cte AS (
    SELECT b.site_id,
           count(*)      AS budget_count,
           max(b.budget) AS budget_value   -- count=1 のときのみ採用
    FROM   public.site_budgets b
    JOIN   filtered_sites s2 ON s2.id = b.site_id
    WHERE  b.month IS NULL
      AND  b.is_active = true
      AND  b.year = public.csv_export_fiscal_year(s2.start_date, 4)   -- ★4月固定
    GROUP  BY b.site_id
  ),
  -- filtered_sites へ各費目を LEFT JOIN。金額はここで最終 round（1回だけ）
  calc AS (
    SELECT
      s.id::text                                  AS project_id,
      s.name                                      AS site_name,
      public.csv_export_fiscal_year(s.start_date, 4) AS fiscal_year,  -- ★4月固定
      sc.name                                     AS category_name,
      co.name                                     AS client_name,
      cc.name                                     AS client_category,
      s.location                                  AS location,
      to_char(s.start_date, 'YYYY-MM-DD')         AS start_date,
      to_char(s.end_date,   'YYYY-MM-DD')         AS end_date,
      s.contract_amount                           AS contract_amount,
      CASE WHEN bud.budget_count = 1 THEN bud.budget_value ELSE NULL END AS budget,
      round(COALESCE(l.labor_cost, 0))::bigint    AS labor_cost,                 -- 最終丸め
      round(COALESCE(rs.report_subcontract_cost, 0))::bigint AS report_subcontract_cost,
      COALESCE(iv.invoice_subcontract_cost, 0)::bigint       AS invoice_subcontract_cost,
      COALESCE(iv.material_cost, 0)::bigint       AS material_cost,
      COALESCE(iv.machine_cost, 0)::bigint        AS machine_cost,
      round(COALESCE(d.dump_cost, 0))::bigint      AS dump_cost,                 -- 最終丸め
      round(COALESCE(g.guard_cost, 0))::bigint     AS guard_cost,                -- 最終丸め
      COALESCE(iv.other_cost, 0)::bigint          AS other_cost
    FROM filtered_sites s
    LEFT JOIN public.site_categories    sc ON sc.id = s.category_id
    LEFT JOIN public.companies          co ON co.id = s.company_id
    LEFT JOIN public.company_categories cc ON cc.id = co.category_id
    LEFT JOIN labor_cte    l   ON l.site_id   = s.id
    LEFT JOIN rep_sub_cte  rs  ON rs.site_id  = s.id
    LEFT JOIN dump_cte     d   ON d.site_id   = s.id
    LEFT JOIN guard_cte    g   ON g.site_id   = s.id
    LEFT JOIN inv_cte      iv  ON iv.site_id  = s.id
    LEFT JOIN budget_cte   bud ON bud.site_id = s.id
  ),
  finalrows AS (
    SELECT
      project_id, site_name, fiscal_year, category_name, client_name, client_category,
      location, start_date, end_date, contract_amount, budget,
      labor_cost,
      report_subcontract_cost,
      invoice_subcontract_cost,
      (report_subcontract_cost + invoice_subcontract_cost)            AS subcontract_cost_total,
      material_cost, machine_cost, dump_cost, guard_cost, other_cost,
      (labor_cost
        + report_subcontract_cost + invoice_subcontract_cost
        + material_cost + machine_cost + dump_cost + guard_cost + other_cost) AS total_cost
    FROM calc
  ),
  finalrows2 AS (
    SELECT
      f.*,
      CASE WHEN f.contract_amount IS NOT NULL
           THEN f.contract_amount - f.total_cost ELSE NULL END AS gross_profit,
      CASE WHEN f.contract_amount IS NOT NULL AND f.contract_amount > 0
           THEN round((f.contract_amount - f.total_cost)::numeric / f.contract_amount * 100, 1)
           ELSE NULL END AS profit_rate
    FROM finalrows f
  ),
  -- budget重複 warning（filtered_sites 基準で rows と完全一致）
  budget_warn AS (
    SELECT jsonb_agg(jsonb_build_object(
             'code',            'budget_duplicate',
             'site_id',         s.id::text,
             'site_name',       s.name,
             'fiscal_year',     public.csv_export_fiscal_year(s.start_date, 4),
             'duplicate_count', bud.budget_count,
             'message',         '同一年度の年間予算が複数登録されています。データ不整合のため budget は空にしています。'
           )) AS warr
    FROM budget_cte bud
    JOIN filtered_sites s ON s.id = bud.site_id
    WHERE bud.budget_count > 1
  )
  SELECT jsonb_build_object(
    'meta', jsonb_build_object(
       'csv_type', 'projects_summary',
       'generated_at', now(),
       'fiscal_year_start_month', v_fy_start,
       'fiscal_year_basis', '工事年度（4月始まり固定・sites.start_date 由来）',
       'invoice_statuses', to_jsonb(v_statuses),
       'include_pending_reports', v_pending,
       'row_count', (SELECT count(*) FROM finalrows2),
       'notes', jsonb_build_array(
         '外注費は日報由来(report_subcontract_cost)と請求書由来(invoice_subcontract_cost)を合算しています。両者が同一外注を指す運用では二重計上になりうるため、内訳列で確認してください。',
         '労務費は normal_mins>0 のときのみ日当＋残業割増を計上します。',
         'normal_mins=0 の日報は労務費0です。',
         '残業割増はどの現場に紐づくか判定できないため、通常労務費と同じく site_count で均等按分しています。',
         '現場なし日報（site_ids が空）は projects_summary の工事別原価には含めません。',
         '現場なし日報が存在する期間では、本CSVの労務費合計は attendance_details の労務費合計と一致しない可能性があります。',
         '金額は中間計算を numeric のまま保持し、CSV出力行の最終段階でのみ丸めています。',
         'fiscal_year は工事年度（4月始まり固定）です。',
         'fiscal_year_start_month は本CSVの列計算には使用しません（将来の会社損益集計用）。',
         '粗利・原価率は税込/税抜を正規化しない概算です。重機費は invoices(machine_lease) のみで、リース月額・owned重機は含みません。',
         CASE WHEN v_pending THEN 'pending(未確定)日報を含みます。' ELSE 'confirmed日報のみを対象にしています。' END
       )
    ),
    'warnings', COALESCE((SELECT warr FROM budget_warn), '[]'::jsonb),
    'rows', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.site_name) FROM finalrows2 r), '[]'::jsonb)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;


-- A-5. export_attendance_details_secure（CSV: 出勤・労務明細）
--   変更点：expanded CTE の WHERE 末尾に `AND r.is_voided = false` を追加（他は現行と同一）。
CREATE OR REPLACE FUNCTION public.export_attendance_details_secure(
  session_token_input            text,
  date_from_input                date    DEFAULT NULL,
  date_to_input                  date    DEFAULT NULL,
  fiscal_year_start_month_input  integer DEFAULT 4,   -- 受取・検証のみ（列は4月固定）
  site_id_input                  uuid    DEFAULT NULL,
  include_pending_reports_input  boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_pending  boolean;
  v_fy_start integer;
  v_result   jsonb;
BEGIN
  -- 1) 管理者セッション検証
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'セッションが無効または期限切れです';
  END IF;

  -- 2) fiscal_year_start_month（NULL→4 / 4・9のみ）。列計算には使わない
  v_fy_start := COALESCE(fiscal_year_start_month_input, 4);
  IF v_fy_start NOT IN (4, 9) THEN
    RAISE EXCEPTION 'fiscal_year_start_month は 4 または 9 のみ指定できます';
  END IF;

  -- 3) 日付範囲チェック
  IF date_from_input IS NOT NULL AND date_to_input IS NOT NULL
     AND date_from_input > date_to_input THEN
    RAISE EXCEPTION 'date_from は date_to 以前の日付を指定してください';
  END IF;

  -- 4) boolean NULL対策
  v_pending := COALESCE(include_pending_reports_input, true);

  WITH expanded AS (
    -- LEFT JOIN LATERAL unnest により、現場なし日報（空配列）は site_id=NULL の1行が残る
    SELECT
      r.id          AS report_id,
      r.report_date,
      r.employee_id,
      e.name        AS employee_name,
      r.work_type,
      r.start_time,
      r.end_time,
      r.normal_mins,
      r.overtime_mins,
      r.status      AS report_status,
      r.memo,
      x.site_id,
      CASE WHEN array_length(r.site_ids, 1) IS NULL THEN 0
           ELSE array_length(r.site_ids, 1) END AS site_count
    FROM public.reports r
    JOIN public.employees e ON e.id = r.employee_id
    LEFT JOIN LATERAL unnest(r.site_ids) AS x(site_id) ON true
    WHERE (v_pending OR r.status = 'confirmed')
      AND (date_from_input IS NULL OR r.report_date >= date_from_input)
      AND (date_to_input   IS NULL OR r.report_date <= date_to_input)
      -- site_id_input 指定時：その現場の行のみ。現場なし(x.site_id=NULL)は比較がNULL→除外
      AND (site_id_input IS NULL OR x.site_id = site_id_input)
      AND r.is_voided = false          -- ★PR-B: 無効化済みを除外
  ),
  rows AS (
    SELECT
      ex.report_id::text                          AS report_id,
      to_char(ex.report_date, 'YYYY-MM-DD')       AS report_date,
      public.csv_export_fiscal_year(ex.report_date, 4) AS fiscal_year,  -- ★4月固定
      ex.employee_id::text                        AS employee_id,
      ex.employee_name,
      ex.site_id::text                            AS project_id,    -- 現場なしは NULL
      st.name                                     AS site_name,     -- 現場なしは NULL
      ex.site_count,
      CASE WHEN ex.site_count > 0
           THEN round(1.0 / ex.site_count, 4) ELSE NULL END AS allocation_ratio,
      ex.work_type,
      to_char(ex.start_time, 'HH24:MI')           AS start_time,
      to_char(ex.end_time,   'HH24:MI')           AS end_time,
      ex.normal_mins,
      ex.overtime_mins,
      -- labor_days：normal_mins>0 のときだけ。複数現場=1/site_count、現場なし=1
      CASE WHEN ex.normal_mins > 0
           THEN round(CASE WHEN ex.site_count > 0 THEN 1.0 / ex.site_count ELSE 1 END, 4)
           ELSE 0 END                             AS labor_days,
      rt.daily_rate,
      rt.is_default                               AS rate_is_default,
      -- gated：normal_mins>0 のときのみ日当＋残業。中間numeric→按分（現場なしは÷1）→最終1回round
      round(
        CASE WHEN ex.normal_mins > 0
             THEN rt.daily_rate
                  + ex.overtime_mins / 60.0 * (rt.daily_rate / 8.0) * 1.25
             ELSE 0 END
        / (CASE WHEN ex.site_count > 0 THEN ex.site_count ELSE 1 END)
      )::bigint                                   AS labor_cost,
      ex.report_status,
      ex.memo
    FROM expanded ex
    CROSS JOIN LATERAL public.csv_export_effective_daily_rate(ex.employee_id, ex.report_date) rt
    LEFT JOIN public.sites st ON st.id = ex.site_id
  )
  SELECT jsonb_build_object(
    'meta', jsonb_build_object(
       'csv_type', 'attendance_details',
       'generated_at', now(),
       'fiscal_year_start_month', v_fy_start,
       'fiscal_year_basis', '工事年度（4月始まり固定・report_date 由来）',
       'include_pending_reports', v_pending,
       'row_count', (SELECT count(*) FROM rows),
       'notes', jsonb_build_array(
         '複数現場の日報は site_count で均等按分し、現場ごとに行分割しています。',
         '現場なし日報（site_ids が空）は project_id/site_name=空・site_count=0・allocation_ratio=空で1行出力します。',
         '現場なし日報の labor_cost は按分せず全額を出します（ただし normal_mins=0 の場合は労務費0）。',
         '労務費は normal_mins>0 のときのみ日当＋残業割増を計上します。残業割増はどの現場に紐づくか判定できないため site_count で均等按分しています。',
         '金額は中間計算を numeric のまま保持し、CSV出力行の最終段階でのみ丸めています。',
         '現場なし日報は projects_summary の工事別原価には含まれません。そのため現場なし日報がある期間では projects_summary の労務費合計と一致しない可能性があります。',
         'daily_rate は report_date 時点で有効な最新単価です。該当がない場合のみ既定22000を用い、rate_is_default=true としています。',
         CASE WHEN v_pending THEN 'pending(未確定)日報を含みます。' ELSE 'confirmed日報のみを対象にしています。' END
       )
    ),
    'warnings', '[]'::jsonb,
    'rows', COALESCE(
       (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.report_date, r.employee_name, r.site_name) FROM rows r),
       '[]'::jsonb)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;


-- ============================================================
-- B. admin_void_report_secure（管理者のみ・理由必須・無効化結果を返す）
--    RETURNS TABLE で無効化後の監査情報を返す。物理削除しない。復元は今回作らない。
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_void_report_secure(
  session_token_input text,
  report_id_input     uuid,
  reason_input        text
)
RETURNS TABLE (
  report_id      uuid,
  is_voided      boolean,
  voided_at      timestamptz,
  voided_by      uuid,
  voided_by_role text,
  void_reason    text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor uuid;
  v_role  text;
  v_rows  integer;
BEGIN
  -- 理由必須（NULL・空白のみ不可）
  IF reason_input IS NULL OR btrim(reason_input) = '' THEN
    RAISE EXCEPTION '無効化理由は必須です';
  END IF;

  -- 経路A：employee_sessions + employees.role='admin'（実行者IDを確定）
  SELECT e.id
  INTO   v_actor
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true
    AND  e.role        = 'admin'
  LIMIT 1;

  IF FOUND THEN
    v_role := 'employee_admin';
  ELSE
    -- 経路B：admin_sessions + genka_admins（実行者IDを確定）
    SELECT g.id
    INTO   v_actor
    FROM   public.admin_sessions s
    JOIN   public.genka_admins g ON g.id = s.admin_id
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
      AND  g.is_active  = true
    LIMIT 1;

    IF FOUND THEN
      v_role := 'genka_admin';
    END IF;
  END IF;

  -- どちらの経路でも管理者と確認できなければ拒否（従業員・失効を含む）
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- 無効化（既に無効化済みは対象外＝冪等ガード）。CHECK制約を満たす形でセット。
  RETURN QUERY
  UPDATE public.reports r
  SET    is_voided      = true,
         voided_at      = now(),
         voided_by      = v_actor,
         voided_by_role = v_role,
         void_reason    = btrim(reason_input)
  WHERE  r.id = report_id_input
    AND  r.is_voided = false
  RETURNING r.id, r.is_voided, r.voided_at, r.voided_by, r.voided_by_role, r.void_reason;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    IF EXISTS (SELECT 1 FROM public.reports WHERE id = report_id_input) THEN
      RAISE EXCEPTION 'Report already voided';   -- 既に無効化済み
    ELSE
      RAISE EXCEPTION 'Report not found';        -- 存在しない report_id
    END IF;
  END IF;
END;
$$;


-- ============================================================
-- C. list_admin_reports_with_voided_secure（無効化済み確認用・監査列付き）
--    既存 list_admin_reports_secure はシグネチャ維持（通常集計）。本関数は PR-C の
--    管理者UI（無効化操作・無効化済み表示）用。include_voided_input で切替。
-- ============================================================
CREATE OR REPLACE FUNCTION public.list_admin_reports_with_voided_secure(
  session_token_input   text,
  from_date_input       date    DEFAULT NULL,
  to_date_input         date    DEFAULT NULL,
  include_voided_input  boolean DEFAULT false
)
RETURNS TABLE (
  report_id           uuid,
  report_date         date,
  employee_id         uuid,
  employee_name       text,
  start_time          time without time zone,
  end_time            time without time zone,
  normal_mins         integer,
  overtime_mins       integer,
  site_ids            uuid[],
  material_ids        uuid[],
  material_quantities jsonb,
  memo                text,
  is_voided           boolean,
  voided_at           timestamptz,
  voided_by           uuid,
  voided_by_role      text,
  void_reason         text
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

  -- 経路B：admin_sessions + genka_admins
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

  IF from_date_input IS NOT NULL AND to_date_input IS NOT NULL
     AND from_date_input > to_date_input THEN
    RAISE EXCEPTION 'from_date は to_date 以前の日付を指定してください';
  END IF;

  -- include_voided_input=false（既定）は有効日報のみ。true は無効化済みも含める。
  -- report.id と監査列（voided_*）を返す（PR-C の表示・無効化操作で使用）。
  RETURN QUERY
  SELECT r.id AS report_id,
         r.report_date,
         r.employee_id,
         e.name AS employee_name,
         r.start_time,
         r.end_time,
         r.normal_mins,
         r.overtime_mins,
         r.site_ids,
         r.material_ids,
         r.material_quantities,
         r.memo,
         r.is_voided,
         r.voided_at,
         r.voided_by,
         r.voided_by_role,
         r.void_reason
  FROM   public.reports r
  JOIN   public.employees e ON e.id = r.employee_id
  WHERE  (from_date_input IS NULL OR r.report_date >= from_date_input)
    AND  (to_date_input   IS NULL OR r.report_date <= to_date_input)
    AND  (COALESCE(include_voided_input, false) OR r.is_voided = false)
  ORDER  BY r.report_date DESC, e.name;
END;
$$;


-- ============================================================
-- D. 新設2関数の権限（既存 secure RPC と同一方針）
--    ※ A の5関数は CREATE OR REPLACE のため既存 ACL を保持（再GRANTしない＝権限不変）。
--    ※ reports への直接 UPDATE 権限は付与しない（無効化は本RPC経由のみ）。
-- ------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.admin_void_report_secure(text, uuid, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_void_report_secure(text, uuid, text)
       TO anon, authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.list_admin_reports_with_voided_secure(text, date, date, boolean) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_admin_reports_with_voided_secure(text, date, date, boolean)
       TO anon, authenticated, service_role;


-- ------------------------------------------------------------
-- 事後確認（読み取りのみ）
--   Q1: 新設2関数が存在・SECURITY DEFINER・search_path 固定
--   Q2: 新設2関数の PUBLIC EXECUTE が無いこと（0行期待）
--   Q3: reports に対する anon/authenticated の直接 UPDATE 権限が無いこと（0行期待）
--   Q4: 動作の目視（任意・本番データ注意）：
--       - 管理者トークンで1件無効化 → 戻り行の is_voided=true / voided_by_role を確認
--       - その後 list_my/admin/genka・CSV(projects_summary/attendance) から当該行が消えること
--       - list_admin_reports_with_voided_secure(..., true) では監査列付きで見えること
-- ------------------------------------------------------------
SELECT p.proname, p.prosecdef, p.proconfig,
       pg_get_function_identity_arguments(p.oid) AS args
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('admin_void_report_secure','list_admin_reports_with_voided_secure')
ORDER  BY p.proname;

SELECT p.proname
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('admin_void_report_secure','list_admin_reports_with_voided_secure')
  AND  has_function_privilege('public', p.oid, 'EXECUTE');   -- 0行期待（PUBLIC に無い）

SELECT grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public' AND table_name = 'reports'
  AND  privilege_type = 'UPDATE'
  AND  grantee IN ('anon','authenticated');                  -- 0行期待（直接UPDATEなし）
