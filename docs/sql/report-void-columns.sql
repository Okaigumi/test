-- ============================================================
-- 日報無効化（soft-void）: reports に無効化用カラムを追加
--   is_voided / voided_at / voided_by / voided_by_role / void_reason
-- ============================================================
-- 【このファイルの方針（重要）】
--   - additive-only：reports に列を追加するだけ。既存列・データ・RLS・policy・
--     権限・既存RPC・トリガーは一切変更しない。
--   - 物理削除はしない。無効化は将来の admin 専用RPC（PR-B）でのみ実行する。
--   - 本ファイル（PR-A）だけでは履歴・集計・CSVの結果は一切変わらない
--     （read/export RPC のフィルタ追加は PR-B）。
--   - 既存行はすべて is_voided=false（有効）になる。
--   - 復元は MVP 非対象だが、is_voided フラグ方式のため将来 restore 可能。
--   - voided_by は employees.id / genka_admins.id の2系統があり得るため FK は張らず、
--     出所は voided_by_role（employee_admin / genka_admin）で識別する。
--   - voided_by の NOT NULL 強制 CHECK は今回入れない（PR-B の
--     admin_void_report_secure 側で voided_by を確実にセットする設計とする）。
--
-- 【実行ステータス】★実行済み（2026-07-06）★
--   - ユーザーが Supabase SQL Editor で実行（Claude からの DB 実行なし）。
--   - 事後確認結果：5カラム追加済み／is_voided は boolean・NOT NULL・DEFAULT false／
--     CHECK 制約2本（reports_void_consistency / reports_voided_by_role_valid）作成済み／
--     active_rows=151・voided_rows=0・total_rows=151（active_rows = total_rows・既存151件は
--     すべて is_voided=false）。
--   - PR-A 単独では履歴・集計・CSV の挙動は変わらない。次工程 PR-B で
--     read/export RPC への is_voided=false 除外・admin_void_report_secure を実装予定。
--
-- 【★事後確認で必ず見ること（重要）★】
--   ADD COLUMN IF NOT EXISTS は、既存に「同名だが中途半端な定義」のカラムが
--   あった場合はスキップされ得る。そのため下記「事後確認 F〜H」で必ず確認する：
--     1. 5カラム（is_voided / voided_at / voided_by / voided_by_role / void_reason）が存在
--     2. is_voided が NOT NULL であること
--     3. is_voided の DEFAULT が false であること
--     4. CHECK 制約2本（reports_void_consistency / reports_voided_by_role_valid）が存在
--     5. 既存行がすべて is_voided=false であること（active_rows = total_rows）
--   期待と異なる場合は、以降の PR-B を進める前に手当てすること。
-- ============================================================

-- ------------------------------------------------------------
-- 事前確認（読み取りのみ・メタデータ）
--   A: 追加対象カラムが未存在であること（0行が期待）
--   B: reports 総行数（事後Gの active_rows と一致するか確認用）
-- ------------------------------------------------------------
SELECT column_name
FROM   information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'reports'
  AND  column_name IN ('is_voided','voided_at','voided_by','voided_by_role','void_reason');

SELECT count(*) AS reports_total FROM public.reports;

-- ------------------------------------------------------------
-- 変更（additive）: 列追加（IF NOT EXISTS で冪等）
--   is_voided は NOT NULL DEFAULT false。非volatile な DEFAULT のため
--   PostgreSQL ではメタデータのみの高速追加（全行リライトなし）。既存行は false。
-- ------------------------------------------------------------
ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS is_voided      boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS voided_at      timestamptz,
  ADD COLUMN IF NOT EXISTS voided_by      uuid,
  ADD COLUMN IF NOT EXISTS voided_by_role text,
  ADD COLUMN IF NOT EXISTS void_reason    text;

-- ------------------------------------------------------------
-- CHECK 制約（冪等：存在しない場合のみ追加）
--   いずれも「含意型」または「NULL許容ドメイン」なので、
--   既存の is_voided=false 行はすべて合格＝既存データに影響なし。
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'reports_void_consistency'
      AND conrelid = 'public.reports'::regclass
  ) THEN
    ALTER TABLE public.reports
      ADD CONSTRAINT reports_void_consistency
      CHECK (
        is_voided = false
        OR (voided_at IS NOT NULL
            AND void_reason IS NOT NULL
            AND btrim(void_reason) <> '')
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'reports_voided_by_role_valid'
      AND conrelid = 'public.reports'::regclass
  ) THEN
    ALTER TABLE public.reports
      ADD CONSTRAINT reports_voided_by_role_valid
      CHECK (voided_by_role IS NULL
             OR voided_by_role IN ('employee_admin','genka_admin'));
  END IF;
END$$;

-- ------------------------------------------------------------
-- 事後確認（読み取りのみ）※上記「★事後確認で必ず見ること★」を満たすこと
--   F: 5カラム存在・is_voided が NOT NULL / DEFAULT false
--   G: 全行 is_voided=false（active_rows = total_rows・事前Bと一致）
--   H: CHECK 制約2本が存在
-- ------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default
FROM   information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'reports'
  AND  column_name IN ('is_voided','voided_at','voided_by','voided_by_role','void_reason')
ORDER  BY column_name;

SELECT count(*) FILTER (WHERE is_voided = false) AS active_rows,
       count(*) FILTER (WHERE is_voided = true)  AS voided_rows,
       count(*)                                  AS total_rows
FROM   public.reports;

SELECT conname, pg_get_constraintdef(oid) AS def
FROM   pg_constraint
WHERE  conrelid = 'public.reports'::regclass
  AND  conname IN ('reports_void_consistency','reports_voided_by_role_valid')
ORDER  BY conname;
