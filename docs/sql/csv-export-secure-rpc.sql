-- ============================================================
-- 集計出力機能 Phase 2-2  CSV出力 セキュアRPC（未実行・確認用）
-- 仕様の正：docs/csv-export-spec.md
--
-- 構成（この順で定義）：
--   1. public.csv_export_fiscal_year            (helper)
--   2. public.csv_export_effective_daily_rate   (helper)
--   3. public.export_projects_summary_secure    (RPC)
--   4. public.export_attendance_details_secure  (RPC)
--   5. public.export_project_cost_details_secure(RPC)
--   6. public.export_machine_details_secure     (RPC)
--
-- 共通方針：
--   * 管理者セッション付き SECURITY DEFINER 参照系（6関数すべて DEFINER）
--   * 6関数すべて SET search_path = public, extensions（digest() 解決のため）
--   * helper 2関数：REVOKE EXECUTE FROM PUBLIC のみ（anon/authenticated へGRANTしない）
--   * 外側4RPC：REVOKE EXECUTE FROM PUBLIC ＋ GRANT EXECUTE TO anon, authenticated
--   * テーブルへの GRANT / REVOKE は一切行わない（DEFINER がオーナー権限で読む）
--   * 戻り値は jsonb エンベロープ { meta, warnings, rows }
--   * CSV整形（UTF-8 BOM / CRLF / RFC4180 / 日本語ファイル名）はフロント責務
--
-- ファンアウト防止：reports/invoices/site_budgets を sites に直接JOINして
--   SUMしない。費目を site_id 単位CTEで事前集計し filtered_sites へ LEFT JOIN。
--
-- 労務費（gated）：
--   overtime_cost  = overtime_mins/60.0 * (daily_rate/8.0) * 1.25
--   labor_cost_raw = CASE WHEN normal_mins>0 THEN daily_rate + overtime_cost ELSE 0 END
--   allocated_raw  = labor_cost_raw / site_count   (現場なしは labor_cost_raw)
--   最終 labor_cost = round(SUM(allocated_raw))     ←丸めはここ1回だけ
--   ※中間は numeric 保持。残業割増も site_count で均等按分。
--
-- site_ids は uuid[] NOT NULL DEFAULT '{}'（NULLにならない）。
--   現場なし＝array_length(site_ids,1) IS NULL。
--   projects_summary は現場なし日報を含めない。attendance_details は1行出す。
--
-- fiscal_year_start_month（4 or 9）：将来の会社損益集計用に受取・検証・meta
--   反映のみ。各CSVの fiscal_year 列は工事年度＝4月始まり固定で算出する。
-- ============================================================


-- ============================================================
-- 1. helper: csv_export_fiscal_year(d, start_month)
--    工事年度（既定4月始まり）の年を返す。d が NULL なら NULL。
-- ============================================================
CREATE OR REPLACE FUNCTION public.csv_export_fiscal_year(d date, start_month integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT CASE
           WHEN d IS NULL THEN NULL
           WHEN extract(month FROM d) >= start_month THEN extract(year FROM d)::int
           ELSE extract(year FROM d)::int - 1
         END
$$;

REVOKE EXECUTE ON FUNCTION public.csv_export_fiscal_year(date, integer)
FROM PUBLIC, anon, authenticated;


-- ============================================================
-- 2. helper: csv_export_effective_daily_rate(emp_id, on_date)
--    on_date 時点で有効な最新単価（effective_from <= on_date の最新1件）。
--    該当があれば is_default=false。該当なしのときだけ 22000 / is_default=true。
-- ============================================================
CREATE OR REPLACE FUNCTION public.csv_export_effective_daily_rate(emp_id uuid, on_date date)
RETURNS TABLE (daily_rate integer, is_default boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  WITH chosen AS (
    SELECT er.daily_rate
    FROM   public.employee_rates er
    WHERE  er.employee_id = emp_id
      AND  er.effective_from <= on_date
    ORDER  BY er.effective_from DESC
    LIMIT  1
  )
  SELECT
    COALESCE((SELECT daily_rate FROM chosen), 22000) AS daily_rate,
    NOT EXISTS (SELECT 1 FROM chosen)                AS is_default;
$$;

REVOKE EXECUTE ON FUNCTION public.csv_export_effective_daily_rate(uuid, date)
FROM PUBLIC, anon, authenticated;


-- ============================================================
-- 3. RPC: export_projects_summary_secure
--    工事別原価サマリ（projects_summary.csv）
-- ============================================================
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

REVOKE EXECUTE ON FUNCTION public.export_projects_summary_secure(
  text, integer, uuid, uuid, uuid, uuid, boolean, boolean, text[], date, date
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.export_projects_summary_secure(
  text, integer, uuid, uuid, uuid, uuid, boolean, boolean, text[], date, date
) TO anon, authenticated;


-- ============================================================
-- 4. RPC: export_attendance_details_secure
--    出勤・労務明細（attendance_details.csv）
--    取得元は reports + employees を直接参照（report_summary は使わない）。
-- ============================================================
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

REVOKE EXECUTE ON FUNCTION public.export_attendance_details_secure(
  text, date, date, integer, uuid, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.export_attendance_details_secure(
  text, date, date, integer, uuid, boolean
) TO anon, authenticated;


-- ============================================================
-- 5. RPC: export_project_cost_details_secure
--    請求書明細（project_cost_details.csv）
--    主データは invoices。reports / report_summary は使わない。
-- ============================================================
CREATE OR REPLACE FUNCTION public.export_project_cost_details_secure(
  session_token_input            text,
  date_from_input                date    DEFAULT NULL,
  date_to_input                  date    DEFAULT NULL,
  fiscal_year_start_month_input  integer DEFAULT 4,   -- 受取・検証・meta反映のみ（列は4月固定）
  site_id_input                  uuid    DEFAULT NULL,
  company_id_input               uuid    DEFAULT NULL,
  invoice_statuses_input         text[]  DEFAULT ARRAY['confirmed','posted']
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_allowed  text[] := ARRAY['uploaded','extracted','suggested','confirmed','posted','rejected'];
  v_statuses text[];
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

  -- 4) invoice_statuses（NULL全体→既定／NULL要素・不正値を弾く）
  v_statuses := COALESCE(invoice_statuses_input, ARRAY['confirmed','posted']);
  IF EXISTS (SELECT 1 FROM unnest(v_statuses) x WHERE x IS NULL OR x <> ALL(v_allowed)) THEN
    RAISE EXCEPTION 'invoice_statuses に NULL または許可されない値が含まれています';
  END IF;

  WITH rows AS (
    SELECT
      i.id::text                              AS invoice_id,
      to_char(i.invoice_date, 'YYYY-MM-DD')   AS invoice_date,
      public.csv_export_fiscal_year(i.invoice_date, 4) AS fiscal_year,  -- ★4月固定
      i.site_id::text                         AS project_id,
      st.name                                 AS site_name,
      co.name                                 AS client_name,
      i.category                              AS cost_category,
      i.vendor_name,
      i.amount,                               -- 生値（正規化なし）
      i.tax_included,
      i.status,
      i.description,
      i.memo
    FROM public.invoices i
    LEFT JOIN public.sites     st ON st.id = i.site_id
    LEFT JOIN public.companies co ON co.id = i.company_id
    WHERE i.status = ANY(v_statuses)
      AND (date_from_input IS NULL OR i.invoice_date >= date_from_input)
      AND (date_to_input   IS NULL OR i.invoice_date <= date_to_input)
      AND (site_id_input    IS NULL OR i.site_id    = site_id_input)
      AND (company_id_input IS NULL OR i.company_id = company_id_input)
  )
  SELECT jsonb_build_object(
    'meta', jsonb_build_object(
       'csv_type', 'project_cost_details',
       'generated_at', now(),
       'fiscal_year_start_month', v_fy_start,
       'fiscal_year_basis', '工事年度（4月始まり固定・invoice_date 由来）',
       'invoice_statuses', to_jsonb(v_statuses),
       'row_count', (SELECT count(*) FROM rows),
       'notes', jsonb_build_array(
         '対象は invoice_statuses のステータスの請求書のみです。',
         '既定では confirmed + posted を対象にしています。',
         'uploaded / extracted / suggested / rejected は既定では除外されます。',
         'amount は税込/税抜を正規化しない生値です。',
         '税区分は tax_included で確認してください。',
         'fiscal_year は工事年度（4月始まり固定・invoice_date 由来）です。fiscal_year_start_month は本CSVの列計算には使用しません。'
       )
    ),
    'warnings', '[]'::jsonb,
    'rows', COALESCE(
       (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.invoice_date, r.invoice_id) FROM rows r),
       '[]'::jsonb)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.export_project_cost_details_secure(
  text, date, date, integer, uuid, uuid, text[]
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.export_project_cost_details_secure(
  text, date, date, integer, uuid, uuid, text[]
) TO anon, authenticated;


-- ============================================================
-- 6. RPC: export_machine_details_secure
--    重機台帳・リース情報（machine_details.csv）
--    主データは machines。machine_locations は使わない。
-- ============================================================
CREATE OR REPLACE FUNCTION public.export_machine_details_secure(
  session_token_input              text,
  include_inactive_machines_input  boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_include_inactive boolean;
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

  -- 2) boolean NULL対策
  v_include_inactive := COALESCE(include_inactive_machines_input, false);

  WITH rows AS (
    SELECT
      m.id::text                          AS machine_id,
      m.name                              AS machine_name,
      m.ownership,
      co.name                             AS owner_company,
      m.lease_company,
      to_char(m.lease_start, 'YYYY-MM-DD') AS lease_start,
      to_char(m.lease_end,   'YYYY-MM-DD') AS lease_end,
      m.lease_monthly,
      0::bigint                           AS owned_cost,   -- MVPは常に0
      m.is_active
    FROM public.machines m
    LEFT JOIN public.companies co ON co.id = m.company_id
    WHERE (v_include_inactive OR m.is_active = true)
  )
  SELECT jsonb_build_object(
    'meta', jsonb_build_object(
       'csv_type', 'machine_details',
       'generated_at', now(),
       'include_inactive_machines', v_include_inactive,
       'row_count', (SELECT count(*) FROM rows),
       'notes', jsonb_build_array(
         'owned重機費は MVP では 0 円扱いです。',
         'lease_monthly は会社全体費用であり、現場別重機費には含めていません。',
         'machine_locations は移動記録のみで、稼働時間・使用日数がないため、現場別重機費は正確には算出できません。',
         '本CSVは重機台帳・リース情報の確認用です。'
       )
    ),
    'warnings', '[]'::jsonb,
    'rows', COALESCE(
       (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.machine_name) FROM rows r),
       '[]'::jsonb)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.export_machine_details_secure(text, boolean)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.export_machine_details_secure(text, boolean)
  TO anon, authenticated;
