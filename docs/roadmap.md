# 社内業務システム ロードマップ

## 現在地

- 最新実装コミット：8a0e811 Add notice attachment support
- 現在フェーズ：運用開始前チェック
- 運用状態：小規模運用開始直前
- 作業PC運用：平日は仕事用PC、それ以外は自宅PC。GitHub経由で同期。
- 作業開始時ルール：git pull --ff-only / git status / git log --oneline -5 を確認
- 作業終了時ルール：変更があれば commit / push し、working tree clean を確認

## 完了済みフェーズ

### セキュリティ・RPC化

- 管理者セッションRPC化：完了
- 従業員セッションRPC化：完了
- employees / genka_admins の直接 INSERT / UPDATE 権限削除：完了
- invoices / site_budgets RPC化：完了
- reports（日報）RPC化：完了
- paid_leave_requests / paid_leave_grants RPC化：完了
- machine_locations RPC化：完了
- public スキーマ全テーブル DELETE 権限REVOKE：完了

### ドキュメント

- docs/db-migrations.md 整備：進行中、主要フェーズ記録済み
- docs/sql 配下に各RPC SQLを保存済み

### ローカルDBバックアップ基盤構築

- scripts/backup-supabase.ps1 作成：完了
- .env.backup.local.example 作成：完了
- .gitignore 作成（backups/ / .env.backup.local 等を除外）：完了
- docs/backup-policy.md 作成：完了
- バックアップスクリプト作成（scripts/backup-supabase.ps1）：完了
- 実バックアップ取得確認：完了

### Storage photos バックアップ

- Supabase Storage photos バケットのバックアップ方式決定：完了
- Storage photos バックアップスクリプト作成（scripts/backup-supabase-storage.ps1）：完了
- Storage photos バックアップ実行確認（OK=2 / ERROR=0）：完了

### 正式ドメイン設定（Vercelカスタムドメイン）

- ドメイン取得（okaigumi.co.jp）：完了（XServer）
- Vercel にカスタムドメイン system.okaigumi.co.jp を追加：完了
- XServer DNS に system の CNAME レコードを追加：完了
- DNS反映・Vercel側確認：完了
- 正式URLでの動作確認：完了

**正式URL（社内案内はこちらに統一）**

| 用途 | URL |
|------|-----|
| 従業員用（日報） | https://system.okaigumi.co.jp/ |
| 管理者用 | https://system.okaigumi.co.jp/admin |
| 原価管理用 | https://system.okaigumi.co.jp/genka |

- `/admin` と `/genka` は `vercel.json` の rewrite により短縮URLとして動作
- DNS は XServer で管理
- 旧URL `test-zeta-snowy-21.vercel.app` は開発・確認用として引き続き使用可能

## Phase 1：運用開始前チェック

状態：進行中

### やること

- TEST表示・テストお知らせの整理
- テスト従業員の無効化
- テスト現場の無効化
- テスト請求書の却下
- テスト予算の無効化
- 社員PINの確認
- 管理者権限の確認
- スマホ表示確認
- Console の致命的エラー確認
- 社員に渡すURLの整理

### URL整理

**正式URL（社内案内はこちらに統一）**

- 従業員用：https://system.okaigumi.co.jp/
- 管理者用：https://system.okaigumi.co.jp/admin
- 原価管理用：https://system.okaigumi.co.jp/genka

**開発・確認用URL（旧Vercel URL）**

- https://test-zeta-snowy-21.vercel.app/
- https://test-zeta-snowy-21.vercel.app/admin-app.html
- https://test-zeta-snowy-21.vercel.app/genka-app.html

## Phase 2：小規模運用開始

状態：未着手

### 方針

最初から全社員に展開せず、岡井さん・管理担当者・数名の従業員で小さく始める。

### 確認すること

- 日報が毎日登録できるか
- 写真添付が問題ないか
- 有給申請・承認が分かりやすいか
- 重機移動記録が現場で使えるか
- 管理画面で従業員・現場・請求書・予算を扱えるか
- 原価画面の集計が実務に合っているか

## Phase 3：残り INSERT / UPDATE のRPC化

状態：未着手

### 優先順位

1. sites / site_assignments
2. materials / machines
3. employee_rates / unit_rates

### 方針

- 直接 INSERT / UPDATE が残っているテーブルを順番にRPC化する
- 既存画面の動作確認後にREVOKEする
- REVOKE前後で本番確認する
- フェーズごとに docs/db-migrations.md へ記録する

## Phase 4：RLSポリシー整理

状態：未着手

### やること

- pg_policies の棚卸し
- ALL true の広いポリシー確認
- SELECT / INSERT / UPDATE / DELETE の役割整理
- RPC経由に寄せるテーブルの方針整理

## Phase 5：PIN・ログイン強化

状態：未着手

### やること

- PINハッシュ化
- ログイン失敗回数制限
- 一定回数失敗時の一時ロック
- session_token の期限管理強化
- 期限切れセッション削除

## Phase 6：admin-app.html 改善

状態：一部完了

### 完了

- 有給管理メニュー追加（admin-app.html サイドバー）
- 既存RPC（review_paid_leave_request_secure / save_paid_leave_grant_secure）を admin_sessions 対応に修正
- 本番動作確認済み（従業員別有給状況・承認/却下・有給付与）
- お知らせ管理メニュー追加（admin-app.html サイドバー）
- notices 管理 RPC 3本追加（list_notices_admin_secure / create_notice_secure / update_notice_secure）
- notices の anon/authenticated 直接書き込み権限削除（INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER を REVOKE）
- anon/authenticated の SELECT は index.html のお知らせ表示用に残存
- 本番動作確認済み（https://system.okaigumi.co.jp/admin）
- お知らせ添付機能追加（画像・PDF 各1件）
- notices に attachment_url / attachment_path / attachment_type / attachment_name / updated_at を追加
- CHECK制約 notices_attachment_type_check 追加（NULL / image / pdf のみ）
- 既存RPC 3本の戻り値を attachment 系カラム・updated_at 含む構成に拡張
- 添付専用RPC 2本追加（update_notice_attachment_secure / delete_notice_attachment_secure）
- Storage バケット notice-attachments 作成（public、INSERT-only policy）
- admin-app.html・index.html に添付UI・表示実装
- 本番動作確認済み（https://system.okaigumi.co.jp/admin・https://system.okaigumi.co.jp/）

### 候補

- 社員権限管理の見やすさ改善
- テストデータ整理用の管理UI

### 有給管理（追加済み）

admin-app.html の「有給管理」メニューで以下が操作できる。
- 従業員別有給状況の確認（付与・使用・残日数）
- 未処理申請の承認・却下（review_paid_leave_request_secure）
- 従業員への有給付与（save_paid_leave_grant_secure）
- index.html 側の既存有給機能は残存（削除していない）

### お知らせ管理・添付（追加済み）

admin-app.html の「お知らせ管理」メニューで以下が操作できる。
- お知らせ一覧表示（非公開含む全件・添付有無アイコン付き）
- お知らせ新規作成（create_notice_secure）
- 本文編集（update_notice_secure）
- 公開/非公開切替（is_active による表示/非表示管理。物理削除は行わない）
- 画像またはPDF 1件の添付（update_notice_attachment_secure）
- 添付削除（delete_notice_attachment_secure によるDB上のNULL化のみ）
- 添付差し替えは新ファイルを選んで保存すると上書き

index.html の従業員画面でのお知らせ表示：
- 添付なし: 本文のみ（従来通り）
- 画像添付: `width:100%; max-height:240px` のプレビュー。クリックで別タブ表示
- PDF添付: 「📄 ファイル名」のボタン風リンク。クリックで別タブ表示

Storage 設計：
- バケット: `notice-attachments`（public）
- path: `notices/{noticeId}/{timestamp}_{sanitized_filename}`
- INSERT-only policy。DELETE policy は意図的に作成しない
- 添付削除時は Storage ファイルを残し DB の attachment_* を NULL 化
- 孤立ファイルは当面許容、必要に応じて手動整理

お知らせ自体の削除機能は実装せず、`is_active = false` による非表示管理に統一。
本番確認済み URL: https://system.okaigumi.co.jp/admin / https://system.okaigumi.co.jp/

## Phase 7：バックアップ・復旧

状態：一部完了

### 完了

- ローカルDBバックアップ基盤構築（scripts/backup-supabase.ps1）
- バックアップ方針ドキュメント（docs/backup-policy.md）
- 実バックアップ取得確認
- Supabase Storage photos バケットのバックアップ方式決定（reports.photo_urls Public URL 方式）
- Storage photos バックアップスクリプト作成（scripts/backup-supabase-storage.ps1）
- Storage photos バックアップ実行確認（OK=2 / ERROR=0）

### 残り

- 重要テーブルのCSVエクスポート手順整理
- 復旧手順作成
- 復旧テスト

## Phase 8：業務効率化

状態：一部着手（集計出力機能の設計開始）

### 候補

- 請求書PDF自動読み取り
- 請求元別自動振り分け
- 現場別原価集計
- 月次Excel出力
- 日報集計
- 材料・外注・重機集計
- スマホUI改善

### 集計出力機能（CSV出力 + ローカルHTMLビューア）

方針・前提仕様：

- MVPはCSV出力＋ローカルHTMLビューア
- 工事年度は4月始まりの公共発注年度
- 会社損益集計は将来RPC側で起点月パラメータ4または9により切替
- 複数現場日報はsite_ids件数で均等按分
- 現場なし日報は工事按分対象外
- 発注者・工事分類はマスタ参照方式
- 発注者はcompaniesの個社名とcompany_categoriesの発注者区分の二層構造
- 出力RPCは将来、管理者セッション付きSECURITY DEFINER参照系RPCで実装する

対象CSV：projects_summary.csv / project_cost_details.csv / attendance_details.csv / machine_details.csv

#### Phase 1-1：スキーマ追加（完了）

- `site_categories`（工事分類マスタ）新設：完了
- `company_categories`（発注者区分マスタ）新設：完了
- `sites` に `category_id` / `contract_amount` 追加：完了
- `companies` に `category_id` 追加：完了
- JOIN用インデックス（idx_sites_category_id / idx_companies_category_id）追加：完了
- RLS SELECT policy 設定・書き込み権限なし確認：完了
- 初期データ投入（site_categories 7件 / company_categories 6件）：完了
- 記録：docs/db-migrations.md「2026-06-08 集計出力機能 Phase 1-1」
- SQL：docs/sql/phase1-schema-categories.sql

## 保留・改善候補

- favicon.ico 追加
- notices の掲載開始日・終了日管理
- staging / production 環境分離
- 操作マニュアル作成
- 社員向け簡易説明資料作成

## 次にやること

1. 運用開始前チェックを完了する
2. 小規模運用を開始する
3. 実際に困った点をメモする
4. 必要に応じて admin-app.html の改善に進む
5. セキュリティ継続強化として sites / site_assignments RPC化に進む
