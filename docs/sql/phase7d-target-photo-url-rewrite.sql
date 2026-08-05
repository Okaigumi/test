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
--
-- ⚠️ psql 変数に関する重要な制約（Phase 7-D で判明・PR-2 で修正）:
--   psql の変数展開（:var / :'var' / :"var"）は、dollar-quote（$$ ... $$）内では
--   行われない。$$ ... $$ の内部は psql の字句解析上「文字列リテラル」として扱われ、
--   :'target_base' は展開されないまま PL/pgSQL へ渡り syntax error となる。
--   → GATE 2 は DO ブロックではなく、\gset + \if（psql メタコマンド）で実装する。
--   → GATE 3 は psql 変数を使わない（inet_server_addr() のみ）ため DO ブロックのままでよい。
--   → STEP 1〜4 は通常 SQL 内での参照であり展開されるため、変更不要。
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
--
-- 停止時の挙動: 実行拒否を正常終了扱いにしないため、psql を非ゼロ終了させる。
--   psql の \quit は終了コード引数を受け取らない（引数を付けても
--   "warning: \quit: extra argument ... ignored" となり終了コードは 0 のまま）。
--   そのため、GATE 0 の ON_ERROR_STOP=on と、psql 変数を含まない静的な
--   DO ブロックの RAISE EXCEPTION を組み合わせて停止する（psql 終了コード 3）。
--   RAISE EXCEPTION 発生時点で以降の SQL は実行されないため、
--   STEP 2 の UPDATE 等の変更処理へは到達しない。
-- ============================================================
\if :{?confirmed}
\else
  \echo 'ERROR: confirmed variable is required. Pass -v confirmed=yes to proceed.'
  DO $gate1_missing$
  BEGIN
    RAISE EXCEPTION 'SAFETY ABORT: confirmed variable is not set. No changes were made.';
  END
  $gate1_missing$;
\endif

\if :confirmed
\else
  \echo 'ERROR: confirmed must be a true value such as yes.'
  DO $gate1_invalid$
  BEGIN
    RAISE EXCEPTION 'SAFETY ABORT: confirmed is not a true value. No changes were made.';
  END
  $gate1_invalid$;
\endif

-- ============================================================
-- GATE 2: TARGET base URL が localhost / 127.0.0.1 を含むこと
-- GATE 1 と同じ psql メタコマンド様式（\if）で実装する。
--
-- 停止時の挙動（重要）:
--   - 判定用の read-only SELECT（\gset 用）は DB へ送信される。
--     「1 文も送信しない」わけではない。
--   - 判定に失敗した場合は、GATE 0 の ON_ERROR_STOP=on と、psql 変数を含まない
--     静的な DO ブロックの RAISE EXCEPTION により psql を非ゼロ終了させる
--     （psql 終了コード 3）。
--   - RAISE EXCEPTION 発生時点で以降の SQL は実行されないため、
--     STEP 2 の UPDATE 等の変更処理へは到達しない。
--   - 呼び出し側スクリプトは psql の終了コードで失敗を検知できる。
-- ============================================================

-- 2-1. 必須変数の設定確認
-- 未設定なら :'var' が展開されず syntax error になるため、判定用 SELECT の前に確認する。
\if :{?target_base}
\else
  \echo 'ERROR: target_base variable is required. Pass -v target_base=... to proceed.'
  DO $gate2_no_target$
  BEGIN
    RAISE EXCEPTION 'SAFETY ABORT: target_base variable is not set. No changes were made.';
  END
  $gate2_no_target$;
\endif

\if :{?source_prefix}
\else
  \echo 'ERROR: source_prefix variable is required. Pass -v source_prefix=... to proceed.'
  DO $gate2_no_source$
  BEGIN
    RAISE EXCEPTION 'SAFETY ABORT: source_prefix variable is not set. No changes were made.';
  END
  $gate2_no_source$;
\endif

-- 2-2. TARGET base URL の安全判定
-- NULL / 複数行を避けるため、CASE で必ず 'yes' / 'no' の 1 行を返す。
-- この SELECT は read-only であり、DB を変更しない。
SELECT CASE
         WHEN :'target_base' = ''                 THEN 'no'
         WHEN :'target_base' LIKE '%supabase.co%' THEN 'no'
         WHEN :'target_base' LIKE '%127.0.0.1%'   THEN 'yes'
         WHEN :'target_base' LIKE '%localhost%'   THEN 'yes'
         ELSE 'no'
       END AS target_ok \gset

\if :target_ok
\else
  \echo 'SAFETY ABORT: target_base must contain 127.0.0.1 or localhost, must not be empty,'
  \echo '              and must not contain supabase.co (Production URL).'
  \echo '              Only the read-only validation SELECT was executed.'
  DO $gate2_not_local$
  BEGIN
    RAISE EXCEPTION 'SAFETY ABORT: target_base is not local. No UPDATE was executed.';
  END
  $gate2_not_local$;
\endif

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
