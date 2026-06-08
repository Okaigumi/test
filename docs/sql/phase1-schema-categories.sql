-- ============================================================
-- 集計出力機能 Phase 1-1
-- 工事分類・発注者区分マスタ + sites/companies へのカラム追加
-- Supabase SQL Editor で実行（実行済み: 2026-06-08）
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. site_categories テーブル新設
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.site_categories (
  id         uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name       text        NOT NULL UNIQUE,
  is_active  boolean     NOT NULL DEFAULT true,
  sort_order integer     NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.site_categories ENABLE ROW LEVEL SECURITY;

-- 再実行安全化のため既存ポリシーを削除してから作成
DROP POLICY IF EXISTS "sc_select" ON public.site_categories;
CREATE POLICY "sc_select"
  ON public.site_categories
  FOR SELECT
  TO anon, authenticated
  USING (true);

REVOKE INSERT, UPDATE, DELETE ON public.site_categories FROM anon, authenticated;
GRANT  SELECT                 ON public.site_categories TO   anon, authenticated;

-- ------------------------------------------------------------
-- 2. company_categories テーブル新設
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.company_categories (
  id         uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name       text        NOT NULL UNIQUE,
  is_active  boolean     NOT NULL DEFAULT true,
  sort_order integer     NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.company_categories ENABLE ROW LEVEL SECURITY;

-- 再実行安全化のため既存ポリシーを削除してから作成
DROP POLICY IF EXISTS "cc_select" ON public.company_categories;
CREATE POLICY "cc_select"
  ON public.company_categories
  FOR SELECT
  TO anon, authenticated
  USING (true);

REVOKE INSERT, UPDATE, DELETE ON public.company_categories FROM anon, authenticated;
GRANT  SELECT                 ON public.company_categories TO   anon, authenticated;

-- ------------------------------------------------------------
-- 3. 初期データ投入（name UNIQUE により再実行しても重複しない）
-- ------------------------------------------------------------

-- 工事分類
INSERT INTO public.site_categories (name, sort_order) VALUES
  ('民間造成',   1),
  ('公共道路',   2),
  ('河川',       3),
  ('治山',       4),
  ('上下水道',   5),
  ('災害対応',   6),
  ('その他',    99)
ON CONFLICT (name) DO NOTHING;

-- 発注者区分
INSERT INTO public.company_categories (name, sort_order) VALUES
  ('民間',    1),
  ('兵庫県',  2),
  ('西脇市',  3),
  ('国交省',  4),
  ('農政局',  5),
  ('その他', 99)
ON CONFLICT (name) DO NOTHING;

-- ------------------------------------------------------------
-- 4. sites へのカラム追加
-- ------------------------------------------------------------
ALTER TABLE public.sites
  ADD COLUMN IF NOT EXISTS category_id     uuid REFERENCES public.site_categories(id),
  ADD COLUMN IF NOT EXISTS contract_amount integer;

COMMENT ON COLUMN public.sites.category_id
  IS '工事分類 (site_categories.id への FK)';
COMMENT ON COLUMN public.sites.contract_amount
  IS '請負金額（円、税込/税抜の扱いは集計仕様で統一）';

-- ------------------------------------------------------------
-- 5. companies へのカラム追加
-- ------------------------------------------------------------
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES public.company_categories(id);

COMMENT ON COLUMN public.companies.category_id
  IS '発注者区分 (company_categories.id への FK)';

-- ------------------------------------------------------------
-- 6. JOIN 用インデックス追加
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_sites_category_id
  ON public.sites (category_id);

CREATE INDEX IF NOT EXISTS idx_companies_category_id
  ON public.companies (category_id);

COMMIT;

-- ------------------------------------------------------------
-- 7. 確認クエリ（実行後に結果を目視確認する）
-- ------------------------------------------------------------

-- 新テーブル存在確認
SELECT table_name
FROM   information_schema.tables
WHERE  table_schema = 'public'
  AND  table_name IN ('site_categories', 'company_categories')
ORDER  BY table_name;

-- 初期データ確認
SELECT id, name, sort_order FROM public.site_categories    ORDER BY sort_order;
SELECT id, name, sort_order FROM public.company_categories ORDER BY sort_order;

-- sites カラム追加確認
SELECT column_name, data_type, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'sites'
  AND  column_name IN ('category_id', 'contract_amount')
ORDER  BY column_name;

-- companies カラム追加確認
SELECT column_name, data_type, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'companies'
  AND  column_name  = 'category_id';

-- インデックス確認
SELECT indexname, tablename
FROM   pg_indexes
WHERE  schemaname = 'public'
  AND  indexname IN ('idx_sites_category_id', 'idx_companies_category_id')
ORDER  BY indexname;

-- RLS 有効確認
SELECT tablename, rowsecurity
FROM   pg_tables
WHERE  schemaname = 'public'
  AND  tablename IN ('site_categories', 'company_categories');

-- RLS ポリシー確認
SELECT tablename, policyname, cmd, roles
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename IN ('site_categories', 'company_categories');

-- anon/authenticated の書き込み権限が 0 件であること
SELECT grantee, table_name, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema   = 'public'
  AND  table_name     IN ('site_categories', 'company_categories')
  AND  grantee        IN ('anon', 'authenticated')
  AND  privilege_type IN ('INSERT', 'UPDATE', 'DELETE');
