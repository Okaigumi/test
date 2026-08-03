-- ============================================================
-- Phase 7-D TARGET ONLY: reports.photo_urls SOURCE URL rewrite
-- ⚠️  TARGET（local restore-lab）DB のみで使用する。
-- ⚠️  SOURCE（Production）DB では絶対に実行しない。
-- ⚠️  psql 変数による明示的 human gate 付き。
-- ============================================================
--
-- 実行方法（docker exec psql）:
--   docker exec -i $DB_CONTAINER psql -U postgres -d postgres \
--     -v source_prefix='https://[SOURCE_PROJECT_REF].supabase.co/storage/v1/object/public/photos/' \
--     -v target_base='http://127.0.0.1:54321/storage/v1/object/public/photos/' \
--     -v confirmed='yes' \
--     -f /tmp/phase7d-target-photo-url-rewrite.sql
--
-- 変数説明:
--   source_prefix  : SOURCE の Storage photos URL prefix（実値は index.html の SUPABASE_URL から確認）
--   target_base    : local restore-lab の Storage URL（supabase start 後に supabase status で確認）
--   confirmed      : 'yes' のみ処理を継続。未設定または 'yes' 以外なら中止。
--
-- 注意:
--   - SOURCE host 実値を Git へ固定しない（実行時に変数で渡す）
--   - TARGET base が localhost / 127.0.0.1 以外なら中止
--   - UNNEST ... WITH ORDINALITY で配列順序を保持
--   - NULL / 空配列を安全に通過させる
--   - 再実行しても壊れない（冪等）
--   - PIN・氏名・session token を出力しない
-- ============================================================

-- ============================================================
-- GATE 0: ON_ERROR_STOP — DO $$ RAISE EXCEPTION 発生時に即停止
-- ============================================================
\set ON_ERROR_STOP on

-- ============================================================
-- GATE 1: confirmed 変数チェック
-- confirmed=yes / confirmed=true / confirmed=1 → TRUE（続行）
-- confirmed=no  / confirmed=false / confirmed=0 → FALSE（停止）
-- 未設定 → 停止
-- ============================================================
\if :{?confirmed}
\else
  \echo 'ERROR: confirmed variable is required. Pass -v confirmed=yes to proceed.'
  \quit
\endif

\if :confirmed
\else
  \echo 'ERROR: confirmed must be a true value such as yes.'
  \quit
\endif

-- ============================================================
-- GATE 2: TARGET base URL が localhost / 127.0.0.1 を含むこと
-- ============================================================
DO $$
DECLARE
  v_target text := :'target_base';
BEGIN
  IF v_target IS NULL OR v_target = '' THEN
    RAISE EXCEPTION 'target_base is not set. Aborting.';
  END IF;
  IF v_target NOT LIKE '%127.0.0.1%'
     AND v_target NOT LIKE '%localhost%' THEN
    RAISE EXCEPTION
      'target_base does not contain 127.0.0.1 or localhost. Got: %. SAFETY ABORT.',
      v_target;
  END IF;
  IF v_target LIKE '%supabase.co%' THEN
    RAISE EXCEPTION
      'target_base contains supabase.co (Production URL). SAFETY ABORT.';
  END IF;
END;
$$;

-- ============================================================
-- GATE 3: TARGET DB が localhost / unix socket であること
-- ============================================================
DO $$
DECLARE
  v_addr text;
BEGIN
  SELECT inet_server_addr()::text INTO v_addr;
  IF v_addr IS NOT NULL
     AND v_addr NOT IN ('127.0.0.1', '::1') THEN
    RAISE EXCEPTION
      'inet_server_addr() = %. Not a local connection. SAFETY ABORT.',
      v_addr;
  END IF;
END;
$$;

-- ============================================================
-- STEP 1: 変換前確認（read-only）
-- STEP 2 UPDATE と同じ prefix 先頭一致条件で件数を表示
-- この件数が STEP 2 の UPDATE 件数・STEP 3 の残存 0件と整合する
-- ============================================================
SELECT
  COUNT(*) AS reports_with_source_url
FROM public.reports
WHERE photo_urls IS NOT NULL
  AND array_length(photo_urls, 1) > 0
  AND EXISTS (
    SELECT 1
    FROM UNNEST(photo_urls) AS u
    WHERE u LIKE (:'source_prefix' || '%')
  );

-- ============================================================
-- STEP 2: UPDATE（UNNEST WITH ORDINALITY で順序保持）
-- SOURCE prefix に完全一致する要素だけ変換。object path は維持。
-- ============================================================
BEGIN;

UPDATE public.reports
SET photo_urls = (
  SELECT ARRAY_AGG(
    CASE
      WHEN u LIKE (:'source_prefix' || '%')
        THEN :'target_base' || substring(u FROM length(:'source_prefix') + 1)
      ELSE u
    END
    ORDER BY ord
  )
  FROM UNNEST(photo_urls) WITH ORDINALITY AS t(u, ord)
)
WHERE photo_urls IS NOT NULL
  AND array_length(photo_urls, 1) > 0
  AND EXISTS (
    SELECT 1
    FROM UNNEST(photo_urls) AS u2
    WHERE u2 LIKE (:'source_prefix' || '%')
  );

-- ============================================================
-- STEP 3: 変換後確認（COMMIT 前）
-- SOURCE prefix 残存件数が 0 であることを確認
-- ============================================================
SELECT
  COUNT(*) AS remaining_source_url_reports
FROM public.reports
WHERE photo_urls IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM UNNEST(photo_urls) AS u
    WHERE u LIKE (:'source_prefix' || '%')
  );
-- 期待: 0。0 以外なら ROLLBACK して原因調査。

COMMIT;

-- ============================================================
-- STEP 4: COMMIT 後の最終確認（read-only）
-- ============================================================
SELECT
  COUNT(*) AS final_source_url_check
FROM public.reports
WHERE photo_urls IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM UNNEST(photo_urls) AS u
    WHERE u LIKE (:'source_prefix' || '%')
  );
-- 期待: 0
