-- invoice-pdf-secure-rpc.sql
--
-- 請求書PDF管理・原価登録候補作成（試作品）
--
-- 概要：
--   人間がPDFを見ながら 1枚の請求書を複数明細に分解し、
--   明細ごとに「原価登録候補（queue）」を作成するための機能。
--   OCR / AI自動判定 / メール取り込み / フォルダ監視は含まない。
--
--   PDF原本は請求書単位で 1つだけ Storage に保存し（工事別に物理移動しない）、
--   工事別の見え方は DB 上の明細データ＋PDFリンクで実現する。
--
-- 設計方針（既存の secure RPC 設計に合わせる）：
--   - 直接テーブル操作は禁止（anon/authenticated は INSERT/UPDATE/DELETE 不可）
--   - 全ての書き込みは SECURITY DEFINER の *_secure RPC 経由
--   - 各 RPC は admin_sessions のトークンを検証してから処理する
--     （notice-attachments-rpc.sql / invoice-budget-secure-rpc.sql と同じ方式）
--   - 既存の invoices / report_summary など「原価管理本体」には一切触れない
--     （cost_entries など存在しないテーブルは復活させない）
--
-- 原価管理本体への直接登録はまだ行わない。
--   confirmed → invoice_cost_registration_queue に登録候補(pending)を作るところまで。
--
-- Storage（Supabase ダッシュボードで作成）：
--   Bucket : invoice-pdfs  （★非公開 / Public OFF）
--   Path   : original/{yyyy}/{mm}/{uuid}.pdf
--   MIME   : application/pdf のみ（フロント側でも検証）
--   Size   : 10MB 上限（バケットポリシー）
--
--   NOTE: 先に invoice-pdfs バケットを「非公開」で作成してから、
--         この SQL を実行し、その後にフロント（admin-app.html）を反映する。
--
-- 実行方法：Supabase SQL Editor で、セクションごとに順番に実行する。
-- ============================================================


-- ============================================================
-- 1. テーブル作成
-- ============================================================

-- ---- 1-1. invoice_documents（請求書本体 / PDF 1枚 = 1レコード） ----
CREATE TABLE IF NOT EXISTS public.invoice_documents (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  file_path          text NOT NULL,                 -- Storage 内のパス（original/yyyy/mm/uuid.pdf）
  original_file_name text,                           -- 元のファイル名（表示用）
  vendor_id          uuid,                           -- 取引先マスタID（試作品では未使用 / nullable）
  vendor_name        text,                           -- 取引先名（自由入力）
  invoice_date       date,                           -- 請求日
  billing_month      text,                           -- 請求月（'YYYY-MM'）
  total_amount       integer,                        -- 請求書合計金額（税込総額）
  tax_amount         integer,                        -- 税額
  status             text NOT NULL DEFAULT 'unprocessed',
  memo               text,
  uploaded_by        text,                           -- アップロードした管理者名
  uploaded_at        timestamptz NOT NULL DEFAULT now(),
  confirmed_by       text,                           -- 確認済みにした管理者名
  confirmed_at       timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.invoice_documents
  DROP CONSTRAINT IF EXISTS invoice_documents_status_check;
ALTER TABLE public.invoice_documents
  ADD CONSTRAINT invoice_documents_status_check
  CHECK (status IN (
    'unprocessed',   -- 未処理（アップロード直後）
    'editing',       -- 入力中
    'amount_mismatch', -- 差額あり
    'confirmed',     -- 確認済み
    'queued',        -- 原価登録候補作成済み
    'excluded',      -- 除外
    'error'          -- エラー
  ));


-- ---- 1-2. invoice_document_lines（請求書明細行） ----
CREATE TABLE IF NOT EXISTS public.invoice_document_lines (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_document_id uuid NOT NULL
                        REFERENCES public.invoice_documents(id) ON DELETE CASCADE,
  line_no             integer,
  project_id          uuid,            -- 工事（sites.id を想定 / FK は張らず疎結合に）
  project_name        text,            -- 工事名（表示用スナップショット）
  cost_category       text,            -- 原価区分（材料費・外注費 等）
  description         text,            -- 摘要
  amount              integer,         -- 金額
  tax_amount          integer,         -- 税額
  tax_type            text,            -- 税区分（試作品では未使用 / nullable）
  memo                text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoice_document_lines_doc
  ON public.invoice_document_lines (invoice_document_id);


-- ---- 1-3. invoice_cost_registration_queue（原価登録候補） ----
CREATE TABLE IF NOT EXISTS public.invoice_cost_registration_queue (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_document_id      uuid NOT NULL
                             REFERENCES public.invoice_documents(id) ON DELETE CASCADE,
  invoice_document_line_id uuid
                             REFERENCES public.invoice_document_lines(id) ON DELETE CASCADE,
  project_id               uuid,
  vendor_id                uuid,
  vendor_name              text,
  cost_category            text,
  description              text,
  amount                   integer,
  billing_month            text,
  invoice_date             date,
  pdf_path                 text,       -- 元PDFへのリンク用（invoice_documents.file_path のコピー）
  status                   text NOT NULL DEFAULT 'pending',
  registered_at            timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.invoice_cost_registration_queue
  DROP CONSTRAINT IF EXISTS invoice_cost_registration_queue_status_check;
ALTER TABLE public.invoice_cost_registration_queue
  ADD CONSTRAINT invoice_cost_registration_queue_status_check
  CHECK (status IN ('pending', 'registered', 'excluded'));

CREATE INDEX IF NOT EXISTS idx_invoice_cost_queue_doc
  ON public.invoice_cost_registration_queue (invoice_document_id);


-- ============================================================
-- 2. 権限：直接書き込みを禁止、SELECT のみ許可
--    （書き込みは全て *_secure RPC 経由）
-- ============================================================
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.invoice_documents,
           public.invoice_document_lines,
           public.invoice_cost_registration_queue
  FROM anon, authenticated;

GRANT SELECT
  ON TABLE public.invoice_documents,
           public.invoice_document_lines,
           public.invoice_cost_registration_queue
  TO anon, authenticated;


-- ============================================================
-- 3. RPC（全て admin セッション検証つき / SECURITY DEFINER）
-- ============================================================

-- ---- 3-1. create_invoice_document_secure ----
--   PDF を Storage にアップロードした後に呼ぶ。
--   レコードを status='unprocessed' で作成して返す。
DROP FUNCTION IF EXISTS public.create_invoice_document_secure(text, text, text, text);

CREATE FUNCTION public.create_invoice_document_secure(
  session_token_input      text,
  file_path_input          text,
  original_file_name_input text,
  uploaded_by_input        text
)
RETURNS public.invoice_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row public.invoice_documents;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  IF file_path_input IS NULL OR trim(file_path_input) = '' THEN
    RAISE EXCEPTION 'file_path is required';
  END IF;

  INSERT INTO public.invoice_documents (file_path, original_file_name, uploaded_by, status)
  VALUES (trim(file_path_input), original_file_name_input, uploaded_by_input, 'unprocessed')
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_invoice_document_secure(text, text, text, text)
  TO anon, authenticated;


-- ---- 3-2. list_invoice_documents_secure ----
--   一覧表示用。明細数・明細合計を集計して返す。
DROP FUNCTION IF EXISTS public.list_invoice_documents_secure(text);

CREATE FUNCTION public.list_invoice_documents_secure(
  session_token_input text
)
RETURNS TABLE (
  id                 uuid,
  file_path          text,
  original_file_name text,
  vendor_id          uuid,
  vendor_name        text,
  invoice_date       date,
  billing_month      text,
  total_amount       integer,
  tax_amount         integer,
  status             text,
  memo               text,
  uploaded_by        text,
  uploaded_at        timestamptz,
  confirmed_by       text,
  confirmed_at       timestamptz,
  created_at         timestamptz,
  updated_at         timestamptz,
  line_count         bigint,
  line_total         bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  RETURN QUERY
  SELECT d.id, d.file_path, d.original_file_name, d.vendor_id, d.vendor_name,
         d.invoice_date, d.billing_month, d.total_amount, d.tax_amount, d.status,
         d.memo, d.uploaded_by, d.uploaded_at, d.confirmed_by, d.confirmed_at,
         d.created_at, d.updated_at,
         COALESCE(l.cnt, 0)  AS line_count,
         COALESCE(l.amt, 0)  AS line_total
  FROM   public.invoice_documents d
  LEFT JOIN (
    SELECT invoice_document_id,
           count(*)                  AS cnt,
           coalesce(sum(amount), 0)  AS amt
    FROM   public.invoice_document_lines
    GROUP BY invoice_document_id
  ) l ON l.invoice_document_id = d.id
  WHERE  d.status <> 'excluded'
  ORDER BY d.uploaded_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_invoice_documents_secure(text)
  TO anon, authenticated;


-- ---- 3-3. get_invoice_document_secure ----
DROP FUNCTION IF EXISTS public.get_invoice_document_secure(text, uuid);

CREATE FUNCTION public.get_invoice_document_secure(
  session_token_input text,
  id_input            uuid
)
RETURNS public.invoice_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row public.invoice_documents;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  SELECT * INTO v_row FROM public.invoice_documents WHERE id = id_input;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice document not found';
  END IF;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_invoice_document_secure(text, uuid)
  TO anon, authenticated;


-- ---- 3-4. list_invoice_document_lines_secure ----
DROP FUNCTION IF EXISTS public.list_invoice_document_lines_secure(text, uuid);

CREATE FUNCTION public.list_invoice_document_lines_secure(
  session_token_input    text,
  invoice_document_id_input uuid
)
RETURNS SETOF public.invoice_document_lines
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  RETURN QUERY
  SELECT * FROM public.invoice_document_lines
  WHERE  invoice_document_id = invoice_document_id_input
  ORDER BY line_no NULLS LAST, created_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_invoice_document_lines_secure(text, uuid)
  TO anon, authenticated;


-- ---- 3-5. save_invoice_document_secure ----
--   請求書基本情報を更新し、明細を「全削除→全挿入」で置き換える。
--   lines_json は明細行の JSON 配列：
--     [{"line_no":1,"project_id":"uuid|null","project_name":"...",
--       "cost_category":"材料費","description":"...","amount":1000,
--       "tax_amount":100,"tax_type":null,"memo":null}, ...]
--   保存後に status を再計算（明細あり かつ 合計不一致 → amount_mismatch、それ以外 → editing）。
--   confirmed / queued の請求書は保存不可（確認解除が必要）。
DROP FUNCTION IF EXISTS public.save_invoice_document_secure(
  text, uuid, text, date, text, integer, integer, text, jsonb);

CREATE FUNCTION public.save_invoice_document_secure(
  session_token_input  text,
  id_input             uuid,
  vendor_name_input    text,
  invoice_date_input   date,
  billing_month_input  text,
  total_amount_input   integer,
  tax_amount_input     integer,
  memo_input           text,
  lines_json           jsonb
)
RETURNS public.invoice_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row        public.invoice_documents;
  v_status     text;
  v_line_count integer;
  v_line_total bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  SELECT * INTO v_row FROM public.invoice_documents WHERE id = id_input;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice document not found';
  END IF;

  IF v_row.status IN ('confirmed', 'queued') THEN
    RAISE EXCEPTION '確認済みのため編集できません。確認解除してから編集してください。';
  END IF;

  -- 明細を置き換え
  DELETE FROM public.invoice_document_lines WHERE invoice_document_id = id_input;

  INSERT INTO public.invoice_document_lines (
    invoice_document_id, line_no, project_id, project_name, cost_category,
    description, amount, tax_amount, tax_type, memo)
  SELECT id_input,
         (e->>'line_no')::integer,
         NULLIF(e->>'project_id','')::uuid,
         e->>'project_name',
         e->>'cost_category',
         e->>'description',
         NULLIF(e->>'amount','')::integer,
         NULLIF(e->>'tax_amount','')::integer,
         e->>'tax_type',
         e->>'memo'
  FROM   jsonb_array_elements(COALESCE(lines_json, '[]'::jsonb)) AS e;

  SELECT count(*), coalesce(sum(amount), 0)
    INTO v_line_count, v_line_total
    FROM public.invoice_document_lines
   WHERE invoice_document_id = id_input;

  IF v_line_count > 0 AND total_amount_input IS NOT NULL
     AND v_line_total <> total_amount_input THEN
    v_status := 'amount_mismatch';
  ELSE
    v_status := 'editing';
  END IF;

  UPDATE public.invoice_documents
  SET    vendor_name   = vendor_name_input,
         invoice_date  = invoice_date_input,
         billing_month = billing_month_input,
         total_amount  = total_amount_input,
         tax_amount    = tax_amount_input,
         memo          = memo_input,
         status        = v_status,
         updated_at    = now()
  WHERE  id = id_input
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_invoice_document_secure(
  text, uuid, text, date, text, integer, integer, text, jsonb)
  TO anon, authenticated;


-- ---- 3-6. confirm_invoice_document_secure ----
--   確認済みにする。制約：
--     - 明細が1行以上ある
--     - 請求書合計が入力済み
--     - 請求書合計 = 明細合計（差額0）
DROP FUNCTION IF EXISTS public.confirm_invoice_document_secure(text, uuid, text);

CREATE FUNCTION public.confirm_invoice_document_secure(
  session_token_input text,
  id_input            uuid,
  confirmed_by_input  text
)
RETURNS public.invoice_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row        public.invoice_documents;
  v_line_count integer;
  v_line_total bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  SELECT * INTO v_row FROM public.invoice_documents WHERE id = id_input;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice document not found';
  END IF;

  IF v_row.status = 'queued' THEN
    RAISE EXCEPTION 'すでに原価登録候補が作成されています。';
  END IF;

  SELECT count(*), coalesce(sum(amount), 0)
    INTO v_line_count, v_line_total
    FROM public.invoice_document_lines
   WHERE invoice_document_id = id_input;

  IF v_line_count = 0 THEN
    RAISE EXCEPTION '明細が1行もないため確認済みにできません。';
  END IF;

  IF v_row.total_amount IS NULL THEN
    RAISE EXCEPTION '請求書合計金額が未入力です。';
  END IF;

  IF v_line_total <> v_row.total_amount THEN
    RAISE EXCEPTION '請求書合計と明細合計が一致しないため確認済みにできません（差額: %）。',
      (v_row.total_amount - v_line_total);
  END IF;

  UPDATE public.invoice_documents
  SET    status       = 'confirmed',
         confirmed_by = confirmed_by_input,
         confirmed_at = now(),
         updated_at   = now()
  WHERE  id = id_input
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirm_invoice_document_secure(text, uuid, text)
  TO anon, authenticated;


-- ---- 3-7. unconfirm_invoice_document_secure（確認解除） ----
--   confirmed / queued を編集可能な状態（editing / amount_mismatch）に戻す。
--   queued の場合、未登録(pending)の登録候補は削除する（登録済みは残す）。
DROP FUNCTION IF EXISTS public.unconfirm_invoice_document_secure(text, uuid);

CREATE FUNCTION public.unconfirm_invoice_document_secure(
  session_token_input text,
  id_input            uuid
)
RETURNS public.invoice_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row        public.invoice_documents;
  v_status     text;
  v_line_count integer;
  v_line_total bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  SELECT * INTO v_row FROM public.invoice_documents WHERE id = id_input;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice document not found';
  END IF;

  IF v_row.status NOT IN ('confirmed', 'queued') THEN
    RAISE EXCEPTION '確認済みまたは候補作成済みの請求書のみ確認解除できます。';
  END IF;

  -- 未登録(pending)の登録候補のみ削除
  DELETE FROM public.invoice_cost_registration_queue
  WHERE  invoice_document_id = id_input AND status = 'pending';

  SELECT count(*), coalesce(sum(amount), 0)
    INTO v_line_count, v_line_total
    FROM public.invoice_document_lines
   WHERE invoice_document_id = id_input;

  IF v_line_count > 0 AND v_row.total_amount IS NOT NULL
     AND v_line_total <> v_row.total_amount THEN
    v_status := 'amount_mismatch';
  ELSE
    v_status := 'editing';
  END IF;

  UPDATE public.invoice_documents
  SET    status       = v_status,
         confirmed_by = NULL,
         confirmed_at = NULL,
         updated_at   = now()
  WHERE  id = id_input
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.unconfirm_invoice_document_secure(text, uuid)
  TO anon, authenticated;


-- ---- 3-8. create_cost_registration_queue_secure（原価登録候補作成） ----
--   confirmed の請求書の明細ごとに pending の登録候補を作成する。
--   原価管理本体（invoices 等）への直接登録は行わない。
--   再実行に備え、既存の pending 候補は作り直す（registered は残す）。
DROP FUNCTION IF EXISTS public.create_cost_registration_queue_secure(text, uuid);

CREATE FUNCTION public.create_cost_registration_queue_secure(
  session_token_input text,
  id_input            uuid
)
RETURNS SETOF public.invoice_cost_registration_queue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row public.invoice_documents;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  SELECT * INTO v_row FROM public.invoice_documents WHERE id = id_input;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice document not found';
  END IF;

  IF v_row.status NOT IN ('confirmed', 'queued') THEN
    RAISE EXCEPTION '確認済みの請求書のみ原価登録候補を作成できます。';
  END IF;

  -- 既存の未登録候補のみ作り直す
  DELETE FROM public.invoice_cost_registration_queue
  WHERE  invoice_document_id = id_input AND status = 'pending';

  INSERT INTO public.invoice_cost_registration_queue (
    invoice_document_id, invoice_document_line_id, project_id, vendor_id,
    vendor_name, cost_category, description, amount, billing_month,
    invoice_date, pdf_path, status)
  SELECT l.invoice_document_id, l.id, l.project_id, v_row.vendor_id,
         v_row.vendor_name, l.cost_category, l.description, l.amount,
         v_row.billing_month, v_row.invoice_date, v_row.file_path, 'pending'
  FROM   public.invoice_document_lines l
  WHERE  l.invoice_document_id = id_input;

  UPDATE public.invoice_documents
  SET    status = 'queued', updated_at = now()
  WHERE  id = id_input;

  RETURN QUERY
  SELECT * FROM public.invoice_cost_registration_queue
  WHERE  invoice_document_id = id_input
  ORDER BY created_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_cost_registration_queue_secure(text, uuid)
  TO anon, authenticated;


-- ---- 3-9. list_cost_registration_queue_secure ----
--   原価登録候補の一覧（元PDFを開くための pdf_path を含む）。
DROP FUNCTION IF EXISTS public.list_cost_registration_queue_secure(text);

CREATE FUNCTION public.list_cost_registration_queue_secure(
  session_token_input text
)
RETURNS SETOF public.invoice_cost_registration_queue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  RETURN QUERY
  SELECT * FROM public.invoice_cost_registration_queue
  ORDER BY created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_cost_registration_queue_secure(text)
  TO anon, authenticated;


-- ---- 3-10. exclude_invoice_document_secure（請求書を除外） ----
DROP FUNCTION IF EXISTS public.exclude_invoice_document_secure(text, uuid);

CREATE FUNCTION public.exclude_invoice_document_secure(
  session_token_input text,
  id_input            uuid
)
RETURNS public.invoice_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row public.invoice_documents;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired admin session';
  END IF;

  -- 未登録(pending)の登録候補は除外扱いにする
  UPDATE public.invoice_cost_registration_queue
  SET    status = 'excluded', updated_at = now()
  WHERE  invoice_document_id = id_input AND status = 'pending';

  UPDATE public.invoice_documents
  SET    status = 'excluded', updated_at = now()
  WHERE  id = id_input
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice document not found';
  END IF;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.exclude_invoice_document_secure(text, uuid)
  TO anon, authenticated;


-- ============================================================
-- 4. Storage RLS（invoice-pdfs バケット / 非公開）
--
--    この app は Supabase Auth を使わず anon キーで動くため、
--    Storage ポリシーで admin_sessions を検証することはできない
--    （USING / WITH CHECK からリクエストヘッダや auth.uid() を参照不可）。
--
--    試作品の方針：
--    - INSERT は invoice-pdfs バケットの original/ 配下のみ許可
--    - SELECT は invoice-pdfs バケットのみ許可
--      （非公開バケットの署名付きURL生成に必要）
--    - DELETE ポリシーは作らない（誤削除防止）
--    - バケット側の MIME=application/pdf / 10MB 制限も追加の防御層
--
--    invoice-pdfs バケットを「非公開」で作成した後に実行する。
--    DROP + CREATE で再実行可能。
-- ============================================================

DROP POLICY IF EXISTS invoice_pdfs_insert ON storage.objects;
CREATE POLICY invoice_pdfs_insert
ON storage.objects FOR INSERT TO anon, authenticated
WITH CHECK (
  bucket_id = 'invoice-pdfs'
  AND name LIKE 'original/%'
);

DROP POLICY IF EXISTS invoice_pdfs_select ON storage.objects;
CREATE POLICY invoice_pdfs_select
ON storage.objects FOR SELECT TO anon, authenticated
USING (
  bucket_id = 'invoice-pdfs'
);


-- ============================================================
-- 5. 確認クエリ（各ブロックを個別に実行）
-- ============================================================

-- [1] 3テーブルの存在確認
SELECT table_name
FROM   information_schema.tables
WHERE  table_schema = 'public'
  AND  table_name IN (
    'invoice_documents',
    'invoice_document_lines',
    'invoice_cost_registration_queue'
  )
ORDER BY table_name;

-- [2] RPC の存在確認（10件）
SELECT routine_name
FROM   information_schema.routines
WHERE  routine_schema = 'public'
  AND  routine_name IN (
    'create_invoice_document_secure',
    'list_invoice_documents_secure',
    'get_invoice_document_secure',
    'list_invoice_document_lines_secure',
    'save_invoice_document_secure',
    'confirm_invoice_document_secure',
    'unconfirm_invoice_document_secure',
    'create_cost_registration_queue_secure',
    'list_cost_registration_queue_secure',
    'exclude_invoice_document_secure'
  )
ORDER BY routine_name;

-- [3] テーブル権限（anon/authenticated は SELECT のみ）
SELECT grantee, table_name, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name IN (
    'invoice_documents',
    'invoice_document_lines',
    'invoice_cost_registration_queue'
  )
  AND  grantee IN ('anon', 'authenticated')
ORDER BY table_name, grantee, privilege_type;

-- [4] Storage ポリシー（invoice_pdfs_insert / invoice_pdfs_select の2件）
SELECT policyname, cmd, roles
FROM   pg_policies
WHERE  schemaname = 'storage'
  AND  tablename  = 'objects'
  AND  policyname LIKE 'invoice_pdfs%'
ORDER BY policyname;
