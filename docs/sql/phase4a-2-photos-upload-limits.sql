-- ============================================================
-- Phase 4-A-2：photos Storage bucket upload 制限
-- 対象：storage.buckets の id = 'photos' のみ
--
-- 状態：実行済み（2026-06-30 Supabase SQL Editor で適用）
--   - 適用結果：Success
--   - 事後確認OK：public=true 維持／file_size_limit=5242880／
--     allowed_mime_types=["image/jpeg"]／photos_read・photos_upload policy 変更なし
--   - 本番画面確認OK：既存写真表示・写真クリック表示・新規アップロード・保存・詳細表示・エラーなし
--   - 記録：docs/db-migrations.md「2026-06-30 Phase 4-A-2 photos upload 制限 完了」
--
-- 目的：
--   public な photos bucket は file_size_limit / allowed_mime_types が未設定で、
--   任意サイズ・任意MIMEのアップロードを許してしまう（ストレージ濫用・非画像投入の穴）。
--   bucket 設定で「最大5MB・image/jpeg のみ」に制限し、upload を絞る。
--
-- 方針（重要・最小変更）：
--   - 変更するのは storage.buckets の photos 行の
--     file_size_limit と allowed_mime_types のみ。
--   - public = true は維持（reports.photo_urls に public URL を保存しており、
--     新規・既存写真の表示が public read に依存するため read は絞らない）。
--   - storage.objects の policy（photos_read / photos_upload）は変更しない。
--     特に photos_upload の public INSERT は維持（アプリは anon キー運用で
--     auth.uid()=NULL のため、role 絞り込みは upload を即停止させる）。
--   - private化・署名URL化は行わない（別フェーズ。保存済み public URL の移行設計が必要）。
--
-- フロント整合（index.html）：
--   - upload は contentType:'image/jpeg' 固定 → allowed_mime_types=['image/jpeg'] と一致
--   - resizeImage で最大1280x720・JPEG品質0.7に再エンコード＋最大5枚
--     → 生成サイズは概ね数百KB級。5MB(5242880)上限なら正規アップロードに余裕あり
--
-- 触らないもの：
--   - notice-attachments / invoice-pdfs バケット
--   - storage.objects の policy（read/insert とも）
--   - photos の public フラグ
--   - 他テーブル・他バケット
-- ============================================================


-- ============================================================
-- 1. 事前確認（読み取り専用・DB変更なし）
-- ============================================================

-- 1-1. photos bucket の現在設定
--      期待（変更前）：public=true / file_size_limit=NULL / allowed_mime_types=NULL
SELECT id,
       name,
       public,
       file_size_limit,
       allowed_mime_types
FROM storage.buckets
WHERE id = 'photos';

-- 1-2. photos に関係する storage.objects policy の現状
--      期待：photos_read（SELECT）/ photos_upload（INSERT）が存在（今回は変更しない）
SELECT policyname,
       cmd,
       roles,
       qual,
       with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND policyname IN ('photos_read', 'photos_upload')
ORDER BY policyname;


-- ============================================================
-- 2. 変更SQL案（レビュー後に実行）
--    photos bucket に file_size_limit=5MB / allowed_mime_types=image/jpeg を設定
--    public は変更しない・policy は変更しない
-- ============================================================
UPDATE storage.buckets
SET file_size_limit    = 5242880,              -- 5MB
    allowed_mime_types = ARRAY['image/jpeg']
WHERE id = 'photos';


-- ============================================================
-- 3. 事後確認（読み取り専用・DB変更なし）
-- ============================================================

-- 3-1. photos bucket の設定確認
--      期待（変更後）：public=true / file_size_limit=5242880 /
--      allowed_mime_types={image/jpeg}
SELECT id,
       name,
       public,
       file_size_limit,
       allowed_mime_types
FROM storage.buckets
WHERE id = 'photos';

-- 3-2. policy が変更されていないことの確認
--      期待：photos_read / photos_upload が事前確認(1-2)と同一のまま
SELECT policyname,
       cmd,
       roles,
       qual,
       with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND policyname IN ('photos_read', 'photos_upload')
ORDER BY policyname;

-- 3-3. 他バケット（notice-attachments / invoice-pdfs）が無変更であることの参考確認
--      （今回は触っていないため、設定が従来どおりであること）
SELECT id,
       name,
       public,
       file_size_limit,
       allowed_mime_types
FROM storage.buckets
WHERE id IN ('notice-attachments', 'invoice-pdfs')
ORDER BY id;

-- ============================================================
-- 実行後の進め方：
--   3-1 で 5242880 / {image/jpeg} / public=true を確認し、
--   3-2 で policy 不変、3-3 で他バケット不変を確認する。
--   その後、index.html の日報写真アップロード（最大5枚・jpeg）と
--   履歴の写真表示を本番で動作確認する。
--   ※ INSERT policy の role 絞り込み・private化・署名URL化は本ファイルでは扱わない。
-- ============================================================
