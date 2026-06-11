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

### 請求書PDF管理・原価登録候補作成（試作品 / 2026-06-11）

状態：試作品実装完了（OCR・AI自動判定・メール取込・フォルダ監視は対象外）

方針：

- PDF原本は請求書単位で1つだけ Storage 保存（工事別に物理移動しない）
- 1枚の請求書に複数工事・複数原価区分が含まれる前提 → 明細行ごとに分解
- 人間がPDFを見ながら明細分解し、明細ごとに原価登録候補を作る
- 原価管理本体への直接登録はまだ行わず、`invoice_cost_registration_queue` に候補(pending)を作るところまで

実装：

- 新規テーブル3つ：`invoice_documents` / `invoice_document_lines` / `invoice_cost_registration_queue`
- 新規 secure RPC 10件（admin セッション検証つき・SECURITY DEFINER）
- Storage バケット `invoice-pdfs`（非公開・署名付きURL表示）
- `admin-app.html` に「🧾 請求書PDF」メニュー（一覧／詳細：左PDF・右フォーム／原価登録候補タブ）
- 制約：PDF以外不可・合計不一致/明細0行は確認不可・確認後は編集不可（確認解除で再編集）
- SQL：`docs/sql/invoice-pdf-secure-rpc.sql`、手順：`docs/db-migrations.md`（2026-06-11）

将来：OCR/AI抽出・取引先マスタ正規化（vendor_id）・原価管理本体への反映（registered化）

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

#### Phase 2-2：CSV出力RPC作成・DB実行（完了）

- helper 2関数（`csv_export_fiscal_year` / `csv_export_effective_daily_rate`）作成：完了
- 外側RPC 4本（`export_projects_summary_secure` / `export_attendance_details_secure` / `export_project_cost_details_secure` / `export_machine_details_secure`）作成：完了
- 6関数すべて SECURITY DEFINER / search_path=public,extensions：確認済み
- helper 2関数は PUBLIC/anon/authenticated から EXECUTE REVOKE（内部用）：確認済み
- 外側RPC 4本のみ anon/authenticated に EXECUTE GRANT：確認済み
- テーブルへの GRANT / REVOKE 追加なし：確認済み
- 記録：docs/db-migrations.md「2026-06-09 集計出力機能 Phase 2-2」
- SQL：docs/sql/csv-export-secure-rpc.sql

**未実装（次工程候補）：**

- admin-app.html からRPCを呼ぶCSV出力UI
- CSV生成処理（UTF-8 BOM / CRLF / RFC4180 / 日本語ファイル名）
- ローカルHTMLビューア設計・実装
- 必要に応じてマスタ系テーブル（companies / employee_rates / machines / sites / subcontractors / unit_rates）の直接INSERT/UPDATE権限整理（将来のマスタ管理RPC化・REVOKE候補）

#### Phase 2-3：admin-app.html CSV出力UI追加（完了）

- `admin-app.html` に「集計出力」セクション・CSV出力ページを追加：完了
- コミット：`0c5af6a Add CSV export UI to admin app`
- 本番確認済み（`https://system.okaigumi.co.jp/admin`）

**実装内容：**

- サイドバーに「集計出力」セクションと「📊 CSV出力」メニュー（`nav-csv`）を追加
- `pageCsv()` で4種類のCSV出力カードを表示
- `CSV_COLUMNS` 固定列順定義（仕様書の列順に固定・`Object.keys()` 不使用）
- `downloadCsv()` 共通関数：UTF-8 BOM（`﻿`）・CRLF・RFC4180エスケープ・Blob download
- warnings件数通知（alert）
- 0件時ヘッダのみCSV出力
- 生成日時付き日本語ファイル名（`meta.generated_at` 優先・`YYYYMMDD-HHmmss`）

**本番確認内容：**

- CSV出力メニュー表示OK
- 4種類CSVダウンロードOK（工事別サマリー / 出勤労務明細 / 請求書明細 / 重機台帳）
- Excel文字化けなし
- Console重大エラーなし

**次工程候補：**

- ローカルHTMLビューア設計・実装
- CSV出力の絞り込みUI拡張（現場別・会社別フィルタ）
- warnings詳細表示
- 必要に応じてマスタ系テーブル直接権限整理

#### Phase 2-4：ローカルHTML CSVビューア（設計開始）

- 方式：統合ビューア方式（4CSVを1ファイルで扱う）
- 予定ファイル：`local-viewers/csv-viewer.html`（Git管理・Vercel公開対象外予定）
- 設計ドキュメント：`docs/local-viewer-spec.md`
- 初期重点：`attendance_details.csv` の出勤簿表示

**重要注意：**

- `normal_mins` / `overtime_mins` は日報全体値（按分なし）。複数現場で同じ値が複数行に複製されるため、**生行SUM禁止**
- 時間集計は必ず `report_id` 単位にピボットしてから行う
- `labor_days` / `labor_cost` は按分後の値なのでSUM可
- 出勤日数（従業員ごと `DISTINCT report_date`）と稼働件数（`DISTINCT report_id`）は別々に表示

**方針：**

- CSV種別判定は1列目ではなく **必須列集合** で行う
- 未知CSV形式は「未知のCSV形式です」と明示エラー
- CSVパースは外部ライブラリなしの自前RFC4180パーサ（UTF-8 BOM / CRLF・LF対応）
- Excelで保存し直したShift_JIS CSVは原則非対応（`�` 検知で警告）
- CSV値は `innerHTML` に直接入れず `textContent`／エスケープ（XSS防止）

**フェーズ分割：**

- Phase 2-4-0：設計（`docs/local-viewer-spec.md` 作成・本追記）
- Phase 2-4-1：CSV読込・自前パーサ・種別判定・生テーブル表示（`.vercelignore` へ `local-viewers/` 追加）
- Phase 2-4-2：report_id ピボット・月別/従業員別サマリー
- Phase 2-4-3：従業員別日別明細・現場別内訳
- Phase 2-4-4：フィルタ・印刷CSS
- Phase 2-4-5：他CSV（projects_summary / project_cost_details / machine_details）対応

**docs方針：**

- Phase 2-4 は `docs/roadmap.md` と `docs/local-viewer-spec.md` に記録する
- DB変更・SQL実行・Supabase権限変更がないため `docs/db-migrations.md` には記録しない

#### Phase 2-4-3：ページ切替型CSVビューア再構成（完了）

- コミット：`c8dcb0c Add paged print-friendly CSV viewer`
- 実装・実ブラウザ確認・commit/push 完了済み

**実装内容：**

- `local-viewers/csv-viewer.html` をページ切替型に再構成
- 白ベースの業務帳票デザインへ変更
- 印刷CSSを追加
- attendance_details CSV向けに以下ページを整備
  - ダッシュボード
  - 月別サマリー
  - 従業員別サマリー
  - 従業員別 月別出勤簿
  - 全体出勤簿
  - 生データ
  - 警告・エラー
- 従業員別サマリーの従業員名クリックで、対象従業員の月別出勤簿へ遷移
- `normal_mins` / `overtime_mins` の二重計上防止を維持
- `labor_days` / `labor_cost` は按分後値のSUMを維持
- CSV値は `textContent` / DOM API で描画し、`innerHTML` に直接入れない
- Supabase接続なし、外部CDNなし、APIキーなし、`file://` で動く

**実ブラウザ確認内容：**

- 白ベース表示
- CSV読込
- ページ切替
- 月別/従業員別の数字突合
- 従業員名クリック遷移
- 全体出勤簿
- 生データ
- 他CSV読込
- 印刷プレビュー
- Console重大エラーなし

**次フェーズ候補：**

- CSV種別ごとの不要ボタン非表示
- 工事別サマリービューアー調整
- 請求書明細ビューアー検討
- 重機台帳ビューアー検討
- 複数CSV統合モード
- 現場別費用の月別ビュー

#### Phase 2-4-4：projects_summary.csv 用 工事別サマリービューアー初期実装（完了）

- 実装コミット：`27b18b3 Add projects summary CSV viewer pages`
- 対象ファイル：`local-viewers/csv-viewer.html`

**実装内容：**

- `projects_summary.csv` 読込時に以下の専用ページを追加
  - 工事一覧
  - 工事詳細
  - 年度別集計
  - 発注者別集計
  - 工事分類別集計
- 工事名クリックで工事詳細へ遷移（`project_id` を優先、なければ工事名で代替）
- 原価率は `total_cost / contract_amount * 100` で自前計算
- CSVの `profit_rate` は利益率であり、原価率表示には使っていない
- 原価率判定バッジを追加
  - 80%未満：通常
  - 80%以上90%未満：注意
  - 90%以上100%未満：要確認
  - 100%以上：赤字・重大
- 原価率は概算参考値である注記を追加（重機費・税区分・外注費集計の影響で実際と異なる場合がある）
- `warnings / notes` 列は `projects_summary.csv` に存在しないため、工事一覧では `—`、工事詳細では注記表示
- 費目別内訳には、合計原価との突合のため以下を表示
  - 労務費
  - 重機費
  - 材料費
  - 外注費
  - ダンプ費
  - 警備費
  - その他費用
- 年度別・発注者別・工事分類別集計はグループごとに金額を合計してから原価率を算出

**実ブラウザ確認内容：**

- projects_summary読込OK
- メニュー表示OK
- 工事一覧OK
- 原価率注記OK
- 工事名クリックOK
- 工事詳細OK
- 年度別集計OK
- 発注者別集計OK
- 工事分類別集計OK
- 生データOK
- 警告・エラーOK
- NaN表示なし
- Console重大エラーなし

**集計突合結果：**

- allTotalCost = 770000
- yearGroupedTotalCost = 770000
- clientGroupedTotalCost = 770000
- categoryGroupedTotalCost = 770000
- yearMatches = true
- clientMatches = true
- categoryMatches = true
- projectIdMissing = 0
- contractAmountMissingOrZero = 10
- `contractAmountMissingOrZero = 10` は、現在のCSVでは請負金額が未入力または0の工事が10件あるという意味で、ビューアーの不具合ではない

**attendance_details 既存機能の確認（回帰なし）：**

- 出勤簿系メニューOK
- 月別サマリーOK
- 従業員別サマリーOK
- 従業員名クリック遷移OK
- 全体出勤簿OK
- 生データOK
- Console重大エラーなし

**次フェーズ候補：**

- project_cost_details.csv 用 請求書明細ビューアー検討
- machine_details.csv 用 重機台帳ビューアー検討
- 複数CSV統合モードによる工事別月別原価ビュー

#### Phase 2-4-5：project_cost_details.csv 用 請求書明細ビューアー初期実装（完了）

- 実装コミット：`f4eace0 Add project cost details CSV viewer pages`
- 対象ファイル：`local-viewers/csv-viewer.html`

**実装内容：**

- `project_cost_details.csv` 読込時に以下の専用ページを追加
  - 請求書一覧
  - 業者別集計
  - 工事別集計
  - 月別集計
  - 費目別集計
  - 確認リスト
- CSV列マッピング
  - 金額：`amount`
  - 日付：`invoice_date`
  - 業者名：`vendor_name`
  - 工事名：`site_name`
  - 費目：`cost_category`
  - 摘要：`description`
  - 状態：`status`
  - メモ：`memo`
- 費目表示の日本語化
  - `subcontract` → 外注費
  - `material` → 材料費
  - `machine_lease` → 重機リース
  - `other` → その他
- 状態表示の日本語化
  - `confirmed` → 確認済み
  - `posted` → 計上済み
- 業者別・工事別・月別・費目別に `amount` をSUMして集計
- 月別集計は `invoice_date` の `YYYY-MM` をキーにする
- 確認リストを追加
  - 現場名なし
  - 業者名なし
  - 費目なし
  - 金額0円または空
  - 日付なし
  - 同じ業者・同じ日付・同じ金額の重複疑い
  - 外注費の二重計上注意
- 外注費の二重計上注意はエラーではなく確認注意として表示
- ダッシュボードに以下を追加
  - 明細件数
  - 金額合計
  - 業者数
  - 工事数
  - 費目数
  - 確認件数
- CSV値は `textContent` / DOM API で描画し、`innerHTML` に入れていない
- Supabase接続情報・外部CDNなし
- `file://` で動作

**実ブラウザ確認内容：**

- `project_cost_details.csv` 読込OK
- メニュー表示OK
- ダッシュボードOK
- 請求書一覧OK
- 業者別集計OK
- 工事別集計OK
- 月別集計OK
- 費目別集計OK
- 確認リストOK
- 生データOK
- 警告・エラーOK
- NaN表示なし
- Console重大エラーなし

**集計突合結果（確認時点の CSV はデータ行数0）：**

```text
allAmount = 0
vendorGroupedAmount = 0
projectGroupedAmount = 0
monthGroupedAmount = 0
categoryGroupedAmount = 0
vendorMatches = true
projectMatches = true
monthMatches = true
categoryMatches = true
missingSite = 0
missingVendor = 0
missingCategory = 0
zeroAmount = 0
missingDate = 0
subcontractRows = 0
```

- データ行数0のため、実データ入り請求書明細での金額表示・業者別集計・重複疑い表示は今後確認が必要
- ただし空CSV状態での表示崩れ・NaN表示・Console重大エラーはなし

**回帰確認：**

- projects_summary.csv
  - projects_summary読込OK
  - 工事一覧OK
  - 工事名クリックOK
  - 工事詳細OK
  - 年度別集計OK
  - Console重大エラーなし
- attendance_details.csv
  - attendance_details読込OK
  - 出勤簿系メニューOK
  - 月別サマリーOK
  - 従業員別サマリーOK
  - 従業員名クリック遷移OK
  - Console重大エラーなし

**次フェーズ候補：**

- `machine_details.csv` 用 重機台帳ビューアー検討
- 複数CSV統合モードによる工事別月別原価ビュー
- 実データ入り `project_cost_details.csv` での請求書明細ビューアー再検証

#### Phase 2-4-6：machine_details.csv 用 重機台帳ビューアー初期実装（完了）

- 実装コミット：`4ac86e6 Add machine details CSV viewer pages`
- 対象ファイル：`local-viewers/csv-viewer.html`

**実装内容：**

- `machine_details.csv` 読込時に以下の専用ページを追加
  - 重機一覧
  - 重機別集計
  - 月別集計
  - 現場別集計
  - 確認リスト
- CSV列マッピング
  - 重機ID：`machine_id`
  - 重機名：`machine_name`
  - 所有/リース区分：`ownership`
  - 状態：`is_active`
  - リース月額：`lease_monthly`
  - 所有原価：`owned_cost`
  - 所有会社：`owner_company`
  - リース会社：`lease_company`
  - リース開始：`lease_start`
  - リース終了：`lease_end`
- 表示の日本語化
  - `lease` → リース
  - `owned` → 自社保有
  - `true` → 有効
  - `false` → 無効
- `machine_details.csv` は重機台帳であり、1行＝1重機として扱う
- 以下の列は `machine_details.csv` に存在しないため、無理に算出せず `—` または注記表示にした
  - 稼働日
  - 工事名/現場名
  - 稼働時間
  - 稼働日数
  - 機種
  - 管理番号
  - メモ
- 重機費は以下の台帳値として表示
  - リース：`lease_monthly`
  - 自社保有：`owned_cost`
- 月別集計は、稼働日列がないため「集計不可」と注記表示
- 現場別集計は、工事名/現場名列がないため「集計不可」と注記表示
- 重機別集計では、重機IDを優先し、なければ重機名でグループ化
- 確認リストを追加
  - 重機名なし
  - 重機費0円または空
  - 同一 `machine_id` / 重機名の重複疑い
  - 現場名なし・日付なしは列がないため判定対象外
  - 長期間稼働なしは稼働日列がないため判定不可
- `owned_cost` はMVPでは0になり得るため、重機費0円は必ずしも異常ではない旨を注記
- CSV値は `textContent` / DOM API で描画し、`innerHTML` に入れていない
- Supabase接続情報・外部CDNなし
- `file://` で動作

**実ブラウザ確認内容：**

- `machine_details.csv` 読込OK
- メニュー表示OK
- ダッシュボードOK
- 重機一覧OK
- 重機別集計OK
- 月別集計OK
- 現場別集計OK
- 確認リストOK
- 生データOK
- 警告・エラーOK
- NaN表示なし
- Console重大エラーなし

**回帰確認：**

- projects_summary.csv
  - projects_summary読込OK
  - 工事一覧OK
  - 工事名クリックOK
  - 工事詳細OK
  - 年度別集計OK
  - Console重大エラーなし
- project_cost_details.csv
  - project_cost_details読込OK
  - 請求書一覧OK
  - 業者別集計OK
  - 確認リストOK
  - Console重大エラーなし
- attendance_details.csv
  - attendance_details読込OK
  - 出勤簿系メニューOK
  - 月別サマリーOK
  - 従業員別サマリーOK
  - 従業員名クリック遷移OK
  - Console重大エラーなし

**重要な仕様注記：**

- `machine_details.csv` は重機台帳であり、稼働明細ではない
- そのため、現場別・月別の重機稼働や重機原価は、このCSV単体では正確に算出できない
- 現場別/月別の重機費分析には、将来的に複数CSV統合モード、または `machine_locations` 等との統合設計が必要
- ただし `machine_locations` は移動記録であり、稼働時間・稼働日数を持たない場合、正確な稼働原価には別途設計が必要

**次フェーズ候補：**

- 複数CSV統合モードによる工事別月別原価ビュー
- 実データ入り `project_cost_details.csv` での請求書明細ビューアー再検証
- 重機費・稼働日・現場紐付けを扱うための将来データ設計検討

#### Phase 2-4-7-0：複数CSV統合モード設計（完了）

- 種別：設計ドキュメントのみ。**実装は未着手。**
- 設計ドキュメント：[`docs/local-viewer-multi-csv-spec.md`](local-viewer-multi-csv-spec.md)（`docs/local-viewer-spec.md` から参照リンクを追加）

**設計対象：**

- ローカルHTML CSVビューアー（`local-viewers/csv-viewer.html`）の「複数CSV統合モード／工事別月別原価ビュー」
- 複数CSVを同時読込し、工事単位で月別原価・労務費・請求書明細・重機情報・確認事項を横断表示する

**対象CSV：**

- `projects_summary.csv`（工事マスタ・最終集計。統合の軸）
- `attendance_details.csv`（労務費・出勤・日報由来明細）
- `project_cost_details.csv`（請求書由来の材料費・外注費・重機リース・その他）
- `machine_details.csv`（重機台帳。稼働明細ではない）

**必須/任意CSV：**

- 必須：`projects_summary.csv`
- 任意：`attendance_details.csv` / `project_cost_details.csv` / `machine_details.csv`
- 不足時は「静かに0」とせず「未読込のため表示不可」と注記表示

**結合方針：**

- 工事の結合キーは `project_id`（= `sites.id`・UUID）を最優先。projects_summary / attendance_details / project_cost_details が共通で保持する
- `site_name` のみの結合は同名工事リスクのため既定で行わない（許可時は警告＋確認リスト記録）
- 現場なし行（project_id 空）は工事別原価に含めず確認リストに計上

**工事別月別原価ビュー方針：**

- 労務費＝`attendance_details.labor_cost` を `project_id` ＋ `report_date`（YYYY-MM）でSUM（report_id ピボット／二重計上防止を踏襲、`normal_mins`/`overtime_mins` は生SUMしない）
- 請求書費用＝`project_cost_details.amount` を `project_id` ＋ `invoice_date`（YYYY-MM）でSUM、`cost_category`（material/subcontract/machine_lease/other）で費目別
- 重機費列は請求書由来の `machine_lease` を用いる
- 月合計は算出可能な費用のみ。含めた費用の定義を明記し、projects_summary.total_cost と一致しないことがある旨を注記
- projects_summary 最終集計値とローカル再集計値の差異はエラーではなく確認事項として表示（税非正規化・外注費二重計上・ダンプ/警備未明細・重機費未反映が主因）

**machine_details の扱い：**

- `machine_details.csv` は重機台帳（1行＝1重機）であり、工事ID・日付・現場を持たない
- そのため **月別/現場別の重機原価には直接使わず**、当面は重機台帳参照として独立表示する
- 工事別月別の重機原価化には、将来 `machine_locations` 等の現場・日付を持つ稼働データとの統合設計が必要（ただし machine_locations は移動記録で稼働時間・日数を持たない場合があり、正確な原価化には追加設計が必要）

**MVP範囲：**

- やる：複数CSV読込／工事一覧／工事詳細／工事別月別原価／労務費月別／請求書費用月別／確認リスト
- やらない：Supabase接続／DB更新／CSV自動保存／PDF・Excel出力／重機の正確な月別現場別原価算出／会計連携／完全な差異解消

**今後の実装ステップ：**

- 2-4-7-1：複数CSV読み込みUIと multiState
- 2-4-7-2：projects_summary + attendance_details 統合（労務費）
- 2-4-7-3：projects_summary + project_cost_details 統合（請求書費用）
- 2-4-7-4：工事別月別原価ビュー
- 2-4-7-5：差異確認・確認リスト
- 2-4-7-6：印刷・UI調整
- 2-4-7-7：machine_details / machine_locations の将来設計

**設計微修正（Phase 2-4-7-2 着手前・docs のみ）：**

- 月別原価ビューの費目カバレッジ表を追加（含める費目／含めない費目を明記）
- 月別原価ビューの合計は `projects_summary.total_cost` と完全一致しない場合があることを明記（ダンプ費・警備費・日報由来外注費・重機台帳費等のカバレッジ差。エラーではなく確認事項）
- 対象工事範囲は、MVPでは進行中工事も含める方針に確定（将来、完了工事のみ表示フィルタの追加余地あり）
- 進行中工事の原価率・粗利・差異判定は参考値扱い（請負金額が0/空なら原価率は `—` 表示）
- 本修正は設計微修正であり、HTML/JS/CSS の実装変更はない

#### Phase 2-4-7-2：projects_summary + attendance_details 統合（完了）

- 実装コミット：`04d1c07 Add multi CSV labor integration`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）

**実装内容：**

- 複数CSV統合ビューに、`projects_summary.csv` と `attendance_details.csv` の労務費統合を追加
- `projects_summary.csv` を工事一覧の軸にする
- `attendance_details.csv` は `project_id` で `projects_summary.csv` と結合（`site_name` 結合は同名工事リスクのため既定で不使用）
- `attendance_details.labor_cost` を `project_id + report_date(YYYY-MM)` で集計
- `labor_days` も `project_id + report_date(YYYY-MM)` で集計
- 日報件数は `report_id` のユニーク数、明細件数は行数
- `normal_mins` / `overtime_mins` は工事別月別で生SUMしない（二重計上防止）
- `labor_cost` は按分後の工事別値として扱う
- `project_id` 空行は集計対象外とし、警告に回す
- 進行中工事も表示対象に含める

**追加した集計データ：**

- `multiState.summaries.laborByProjectId`（project_id → 労務費合計・人工・明細件数・日報件数・対象月数）
- `multiState.summaries.laborMonthlyByProjectId`（project_id → 月別労務費の配列・月昇順）

**追加したUI：**

- 読み込み状況ダッシュボードの労務費合計 / 労務費対象工事件数 / 労務費対象月数
- 簡易工事一覧の労務費列（労務費合計・労務対象月数・日報件数・労務明細件数）
- 工事別 労務費詳細（工事概要 / 月別労務費 / 労務明細）
- 選択工事の労務詳細表示：工事概要・請負金額・projects_summary 上の労務費・attendance_details 由来の労務費合計・差額参考表示・月別労務費・労務明細

**安全性：**

- CSV由来値は `textContent` / DOM API で描画
- inline `onclick` は追加なし（event listener で実装）
- Supabase接続情報・外部CDNなし、`file://` 動作維持

**実ブラウザ確認（OK）：**

- 複数CSV統合モード表示OK
- projects_summary 読込OK / attendance_details 読込OK
- 労務費合計表示OK / 労務費対象工事件数表示OK / 労務費対象月数表示OK
- 簡易工事一覧の労務費合計OK / 労務対象月数OK / 日報件数OK / 明細件数OK
- 工事選択OK / 選択工事の月別労務費OK / 選択工事の労務明細OK
- 空 `project_id` 行は集計除外＋警告表示OK
- NaN表示なし / Console重大エラーなし

**回帰確認（OK）：**

- 4CSV読み込み枠OK / 誤種別CSV警告OK / クリア処理OK
- machine_details が工事別に結合されていないことOK
- 単体CSV読み込みOK
- attendance_details 既存ページOK / projects_summary 既存ページOK / project_cost_details 既存ページOK / machine_details 既存ページOK
- JS構文チェックOK
- CSV由来値は `textContent` / DOM API 描画 / inline `onclick` 不使用 / Supabase接続情報・外部CDNなし

**未実装（次フェーズ以降・未着手）：**

- `project_cost_details.csv` 統合
- 請求書費用月別
- 工事別月別原価の総合計
- `projects_summary.total_cost` との差異確認
- 横断確認リスト
- `machine_details` / `machine_locations` 統合
- 印刷調整

**次フェーズ候補：**

- Phase 2-4-7-3：projects_summary + project_cost_details 統合
  - `project_cost_details.amount` を `project_id + invoice_date(YYYY-MM)` で集計
  - `cost_category` 別に材料費・外注費・重機リース等・その他費用を集計
  - `invoicesByProjectId` を利用
  - 月別原価ビューに向けて、労務費＋請求書費用を統合できる土台を作る

#### Phase 2-4-7-3：projects_summary + project_cost_details 統合（完了）

- 実装コミット：`30aef20 Add multi CSV invoice integration`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）

**実装内容：**

- 複数CSV統合ビューに、`projects_summary.csv` と `project_cost_details.csv` の請求書費用統合を追加
- `projects_summary.csv` を工事一覧の軸にする
- `project_cost_details.csv` は `project_id` で `projects_summary.csv` と結合（`site_name` 結合は同名工事リスクのため既定で不使用）
- `project_cost_details.amount` を `project_id + invoice_date(YYYY-MM)` で集計
- `cost_category` 別に集計：
  - `material`：材料費
  - `subcontract`：外注費
  - `machine_lease`：重機リース等
  - `other`：その他費用
- 未知の `cost_category` は請求書費用合計には含めるが、上記4費目には混ぜず `unknown` に退避し、警告扱いにする
- 請求書件数は `invoice_id` ユニーク数、明細件数は行数、業者数は `vendor_name` ユニーク数
- `project_id` 空行は集計対象外とし、警告に回す
- 進行中工事も表示対象に含める

**追加した集計データ：**

- `multiState.summaries.invoiceByProjectId`（project_id → 請求書費用合計・費目別金額・明細件数・請求書件数・業者数・対象月数）
- `multiState.summaries.invoiceMonthlyByProjectId`（project_id → 月別請求書費用の配列・月昇順）
- `multiState.unknownCostCategories`（未知 cost_category 値の配列）

**追加したUI：**

- 読み込み状況ダッシュボードの請求書費用合計 / 請求書費用対象工事件数 / 請求書費用対象月数 / 業者数 / 材料費合計 / 外注費合計 / 重機リース等合計 / その他費用合計
- 簡易工事一覧の請求書費用列（請求書費用合計・請求書対象月数・請求書明細件数・材料費・外注費・重機リース等・その他）
- 工事別 原価詳細（月別請求書費用 / 請求書明細を追加）
- 選択工事の詳細表示への追加：project_cost_details 由来の請求書費用合計・材料費・外注費・重機リース等・その他費用・請求書明細件数・業者数・月別請求書費用・請求書明細

**安全性：**

- 既存の労務費統合・月別労務費・労務明細は維持
- CSV由来値は `textContent` / DOM API で描画
- inline `onclick` は追加なし（event listener で実装）
- Supabase接続情報・外部CDNなし、`file://` 動作維持

**実ブラウザ確認（OK）：**

- 複数CSV統合モード表示OK
- projects_summary 読込OK / project_cost_details 読込OK
- 請求書費用合計表示OK / 請求書費用対象工事件数表示OK / 請求書費用対象月数表示OK / 業者数表示OK
- 材料費表示OK / 外注費表示OK / 重機リース等表示OK / その他費用表示OK
- 簡易工事一覧の請求書費用合計OK
- 工事選択OK / 選択工事の月別請求書費用OK / 選択工事の請求書明細OK
- 空 `project_id` 行は集計除外＋警告表示OK
- 未知 `cost_category` は警告表示OK
- NaN表示なし / Console重大エラーなし

**回帰確認（OK）：**

- 労務費統合回帰OK / 労務費合計表示OK / 簡易工事一覧の労務費合計OK
- 選択工事の月別労務費OK / 選択工事の労務明細OK
- 4CSV読み込み枠OK / 誤種別CSV警告OK / クリア処理OK
- machine_details が工事別に結合されていないことOK
- 単体CSV読み込みOK
- attendance_details 既存ページOK / projects_summary 既存ページOK / project_cost_details 既存ページOK / machine_details 既存ページOK
- JS構文チェックOK
- CSV由来値は `textContent` / DOM API 描画 / inline `onclick` 不使用 / Supabase接続情報・外部CDNなし

**未実装（次フェーズ以降・未着手）：**

- 労務費＋請求書費用の月別原価総合計
- `projects_summary.total_cost` との差異確認
- 横断確認リスト
- `machine_details` / `machine_locations` 統合
- 印刷調整

**次フェーズ候補：**

- Phase 2-4-7-4：工事別月別原価ビュー
  - 労務費（`attendance_details`）＋請求書費用（`project_cost_details`）を月キー `YYYY-MM` で統合
  - 費目カバレッジ表に沿って月別原価を表示
  - 月合計は算出可能費目のみ（労務費／材料費／外注費（請求書由来）／重機リース等（請求書由来）／その他費用（請求書由来））
  - ダンプ費・警備費・日報由来外注費・machine_details 由来の台帳費はMVPでは含めない
  - 月合計・累計列を用意する
  - `projects_summary.total_cost` との差異確認は Phase 2-4-7-5 で扱う

#### Phase 2-4-7-4：工事別月別原価ビュー（完了）

- 実装コミット：`4fddc44 Add multi CSV monthly cost view`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）

**実装内容：**

- 複数CSV統合ビューに、労務費＋請求書費用を月キーで統合した工事別月別原価ビューを追加
- 労務費は `attendance_details.csv` 由来、請求書費用は `project_cost_details.csv` 由来
- 月キーは `YYYY-MM`
- 追加データ：`multiState.summaries.costMonthlyByProjectId`
- 月別原価ビューで表示する列：月／労務費／材料費／外注費／重機リース等／その他費用／未分類・確認対象／月合計／累計
- 月合計は算出可能費目のみを対象：労務費／材料費／外注費（請求書由来）／重機リース等（請求書由来）／その他費用（請求書由来）
- `unknown cost_category` は月合計に含めず、「未分類・確認対象」として別列表示
- MVPの月合計に含めないもの：ダンプ費／警備費／日報由来外注費／`machine_details` 由来の重機台帳費
- 累計は月順に月合計を加算
- 読み込み状況ダッシュボードに月別原価サマリーを追加：月別原価対象工事件数／月別原価対象月数／月別原価合計
- 簡易工事一覧に追加：月別原価対象月数／月別原価合計
- 工事別詳細に追加：工事別月別原価カード／月別原価合計／月別原価対象月数／月別原価累計最終値
- `projects_summary.total_cost` との差異確認は Phase 2-4-7-5 で扱うため、今回は未実装

**安全性：**

- CSV由来値は `textContent` / DOM API で描画
- inline `onclick` は追加なし（event listener で実装）
- Supabase接続情報・外部CDNなし、`file://` 動作維持

**実ブラウザ確認（OK）：**

- 複数CSV統合モード表示OK
- projects_summary 読込OK / attendance_details 読込OK / project_cost_details 読込OK
- 月別原価対象工事件数表示OK / 月別原価対象月数表示OK / 月別原価合計表示OK
- 簡易工事一覧の月別原価合計OK
- 工事選択OK / 選択工事の工事別月別原価OK / 月合計OK / 累計OK
- 未分類・確認対象が月合計に混ざっていないことOK
- NaN表示なし / Console重大エラーなし

**回帰確認（OK）：**

- 労務費統合回帰OK / 労務費合計表示OK / 簡易工事一覧の労務費合計OK
- 選択工事の月別労務費OK / 選択工事の労務明細OK
- 請求書費用統合回帰OK / 請求書費用合計表示OK / 簡易工事一覧の請求書費用合計OK
- 選択工事の月別請求書費用OK / 選択工事の請求書明細OK / 未知 `cost_category` 警告OK
- 4CSV読み込み枠OK / 誤種別CSV警告OK / クリア処理OK
- machine_details が工事別に結合されていないことOK
- 単体CSV読み込みOK
- attendance_details 既存ページOK / projects_summary 既存ページOK / project_cost_details 既存ページOK / machine_details 既存ページOK
- JS構文チェックOK
- CSV由来値は `textContent` / DOM API 描画 / inline `onclick` 不使用 / Supabase接続情報・外部CDNなし

**未実装（次フェーズ以降・未着手）：**

- `projects_summary.total_cost` との差異確認
- 横断確認リスト
- `machine_details` / `machine_locations` 統合
- 印刷調整

**次フェーズ候補：**

- Phase 2-4-7-5：差異確認・確認リスト
  - `projects_summary.total_cost` と統合ビューの月別原価再集計値の差異を確認事項として表示
  - `projects_summary.labor_cost` と `attendance_details` 由来労務費合計の差異確認
  - `projects_summary.material_cost` 等と `project_cost_details` 由来費用の差異確認
  - 差異はエラーではなく確認事項として扱う
  - 差異の主因注記を表示（税込/税抜の非正規化／外注費二重計上リスク／ダンプ費・警備費の未明細／重機費の台帳未反映／pending日報／unknown cost_category）
  - 複数CSV横断の確認リストを追加（明細なし工事／`projects_summary` に存在しない `project_id`／現場なし行／請負金額未入力／原価率100%以上）

#### Phase 2-4-7-5：差異確認・確認リスト（完了）

- 実装コミット：`f994c45 Add multi CSV reconciliation checks`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）

**実装内容：**

- 複数CSV統合ビューに、`projects_summary.csv` とローカル再集計値の差異確認を追加
- 差異はエラーではなく「確認事項」として表示
- 複数CSV横断の確認リストを追加
- ダッシュボードに追加：差異確認件数／横断確認件数／確認事項合計
- 簡易工事一覧に追加：差異確認／確認事項
- 工事別詳細に差異確認カードを追加
- 統合ビューに確認リストカードを追加
- 追加データ：`multiState.summaries.reconciliationByProjectId` ／ `multiState.crossChecks`

**差異確認で比較する項目：**

- 労務費／材料費／外注費／重機費・重機リース等／その他費用／合計原価
- 比較方針：
  - `projects_summary` 側の集計値
  - `attendance_details` / `project_cost_details` 由来のローカル再集計値
  - 合計原価は月別原価ビューの累計最終値を使う
- `projects_summary.total_cost` と月別原価ビューの合計は完全一致を目的としない（月別原価ビューは費目カバレッジ表に基づく算出可能費目の合計）
- 外注費は `projects_summary.invoice_subcontract_cost`（請求書由来）と比較する（`subcontract_cost_total` は日報由来を含むため不一致）
- 差異の主因注記を表示：税込/税抜の非正規化／外注費二重計上リスク／ダンプ費・警備費の未明細／重機費の台帳未反映／pending日報／unknown cost_category／CSV未読込

**複数CSV横断の確認リスト：**

- projects_summary にあるが attendance_details に明細がない工事
- projects_summary にあるが project_cost_details に明細がない工事
- attendance_details にあるが projects_summary に存在しない project_id
- project_cost_details にあるが projects_summary に存在しない project_id
- project_id が空の attendance_details 行
- project_id が空の project_cost_details 行
- 請負金額が0または空の工事
- 原価率100%以上の工事
- unknown cost_category がある行
- machine_details は工事別月別原価に未反映
- 未読込CSVについては大量の誤警告を出さず、未読込注記に留める
- `machine_details` は工事別には結合せず、未反映の参考注記として扱う

**安全性：**

- CSV由来値は `textContent` / DOM API で描画
- inline `onclick` は追加なし（event listener で実装）
- Supabase接続情報・外部CDNなし、`file://` 動作維持

**実ブラウザ確認（OK）：**

- 複数CSV統合モード表示OK
- projects_summary 読込OK / attendance_details 読込OK / project_cost_details 読込OK
- 差異確認件数表示OK / 横断確認件数表示OK / 確認事項合計表示OK
- 簡易工事一覧の差異確認列OK / 確認リスト表示OK
- 工事選択OK / 選択工事の差異確認カードOK
- 差異はエラーではなく確認事項として表示OK
- NaN表示なし / Console重大エラーなし

**回帰確認（OK）：**

- 工事別月別原価ビュー回帰OK / 月別原価合計表示OK / 工事別月別原価カードOK / 月合計OK / 累計OK / unknown が月合計に混ざっていないことOK
- 労務費統合回帰OK / 労務費合計表示OK / 簡易工事一覧の労務費合計OK / 選択工事の月別労務費OK / 選択工事の労務明細OK
- 請求書費用統合回帰OK / 請求書費用合計表示OK / 簡易工事一覧の請求書費用合計OK / 選択工事の月別請求書費用OK / 選択工事の請求書明細OK / 未知 cost_category 警告OK
- 4CSV読み込み枠OK / 誤種別CSV警告OK / クリア処理OK / machine_details が工事別に結合されていないことOK
- 単体CSV読み込みOK / attendance_details 既存ページOK / projects_summary 既存ページOK / project_cost_details 既存ページOK / machine_details 既存ページOK
- JS構文チェックOK
- CSV由来値は `textContent` / DOM API 描画 / inline `onclick` 不使用 / Supabase接続情報・外部CDNなし

**未実装（次フェーズ以降・未着手）：**

- `machine_details` / `machine_locations` 統合
- 差異の自動修正
- 印刷調整

**次フェーズ候補：**

- Phase 2-4-7-6：印刷・UI調整
- Phase 2-4-7-7：machine_details / machine_locations の将来設計

#### Phase 2-4-7-6：印刷・UI調整（完了）

- 実装コミット：`2809a18 Improve multi CSV print layout`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）

**実装内容：**

- 複数CSV統合ビューの印刷CSSを調整
- 複数CSV統合ビューと工事別原価詳細に「印刷 / PDF保存」ボタンを追加（`window.print()` を `addEventListener` で呼び出し。inline `onclick` は追加なし）
- 印刷専用ヘッダを追加：社内業務システム ローカルCSVビューアー／複数CSV統合ビュー／工事別 原価詳細／印刷日時
- 印刷日時は `beforeprint` で設定
- 現在表示中の内容のみ印刷されるように調整：
  - ホーム表示中は詳細側を印刷対象外
  - 詳細表示中はホーム側を印刷対象外
  - `.hidden` を印刷時にも非表示として維持
- 印刷時に操作UIを非表示：ファイル選択エリア／CSV読み込みカード／印刷ボタン／戻るボタン／詳細ボタン列／モードタブ
- 印刷対象に残すもの：帳票タイトル／読み込み状況／工事一覧／確認リスト／工事別詳細／工事別月別原価／差異確認／月別労務費／月別請求書費用／警告・確認事項／各注記
- 確認リスト・差異確認・工事別月別原価など横幅の広い表の印刷崩れを抑制
- 印刷時の表フォントを小さくし、セル余白・折り返し・金額列の表示を調整
- `thead` の繰り返し、行・カードの改ページ抑制を維持・強化
- バッジを印刷時に背景色依存ではなく罫線＋文字で読めるよう調整
- 白ベース帳票デザインを維持
- 画面表示上も確認リスト・差異確認・注記が読みやすくなるよう調整
- `renderSummaryTable` がコンテナを `clear()` することで、表の前に追加した注記が消えていた表示不具合を修正
- `appendSummaryTable` を追加し、注記を残したまま表を描画できるようにした
- この修正は表示・印刷上の修正であり、集計ロジックは変更していない

**安全性：**

- CSV由来値は `textContent` / DOM API で描画
- inline `onclick` は追加なし
- Supabase接続情報・外部CDNなし、`file://` 動作維持

**印刷/PDF確認（OK）：**

- 複数CSV統合ビューの印刷プレビューOK / 工事別原価詳細の印刷プレビューOK / PDF生成OK
- 印刷専用ヘッダ表示OK / 印刷日時表示OK
- ファイル選択エリア・読み込み操作UIが印刷されないことOK
- 印刷ボタン・戻るボタン・詳細ボタン列が印刷されないことOK
- 確認リストが印刷で読めることOK / 差異確認カードが印刷で読めることOK / 工事別月別原価カードが印刷で読めることOK
- 金額列が大きく崩れていないことOK / 横幅の広い表が大きく破綻していないことOK
- 差異確認の注記が印刷時にも残ることOK

**回帰確認（OK）：**

- 複数CSV統合モード表示OK / 4CSV読込OK
- 確認リスト表示OK / 差異確認件数表示OK / 横断確認件数表示OK / 確認事項合計表示OK
- 簡易工事一覧の差異確認列OK / 工事選択OK / 選択工事の差異確認カードOK / 選択工事の工事別月別原価カードOK
- 月別原価合計表示OK / 月合計OK / 累計OK / unknown が月合計に混ざっていないことOK
- 労務費統合回帰OK / 請求書費用統合回帰OK / 未知 cost_category 警告OK
- 単体CSV読み込みOK / attendance_details 既存ページOK / projects_summary 既存ページOK / project_cost_details 既存ページOK / machine_details 既存ページOK
- 単体CSV側の印刷挙動が大きく壊れていないことOK
- NaN表示なし / Console重大エラーなし / JS構文チェックOK / inline `onclick` 不使用 / Supabase接続情報・外部CDNなし

**未実装（次フェーズ以降・未着手）：**

- `machine_details` / `machine_locations` 統合
- CSV出力仕様変更
- DB更新
- 集計ロジック変更

**次フェーズ候補：**

- Phase 2-4-7-7：machine_details / machine_locations の将来設計
  - 現状の `machine_details.csv` は重機台帳であり、工事別月別原価には直接結合していない
  - 将来的に `machine_locations` や稼働実績データを使って、重機費を工事別・月別原価に反映できるか検討する
  - 台帳費、リース費、実稼働、現場配賦の扱いを設計する

**実装状況：2-4-7-6（印刷・UI調整）まで実装済み。2-4-7-7 以降は未着手。**

### Phase 2-4-8：CSV出力パッケージ化

- 設計ドキュメント：[`docs/csv-export-package-spec.md`](csv-export-package-spec.md)
- 関連：[`docs/csv-export-spec.md`](csv-export-spec.md) / [`docs/local-viewer-multi-csv-spec.md`](local-viewer-multi-csv-spec.md)

#### Phase 2-4-8-0：CSV出力パッケージ仕様設計（完了）

- 状態：設計完了 / 実装：未着手
- 対象：管理コンソールCSV出力、ローカルCSVビューアーZIP読込、`manifest.json`

**目的：**

- 4CSV（projects_summary / attendance_details / project_cost_details / machine_details）を、利用者には1つのZIP出力パッケージとしてまとめて配布・保管・読込できるようにする。
- ローカルCSVビューアーで、ZIPを1つ選ぶだけで複数CSV統合モードに自動反映する。
- 出力日時・対象期間・ファイル一覧・行数を `manifest.json` として同梱する。
- 個別CSV出力は廃止せず、予備・検証・トラブル対応用として残す。

**ZIP方式：**

- 案A：ZIP処理ライブラリをローカル同梱する方式を採用（外部CDN不使用・`file://` 維持・バージョン固定・入手元/ライセンスを docs 記録）。
- ライブラリ追加は次フェーズ（2-4-8-1）で実施し、今回はライブラリファイルを追加しない。
- 将来の配置候補：`local-viewers/vendor/jszip.min.js` または `vendor/jszip/jszip.min.js`（実装前に最終決定）。

**年月のみの期間指定：**

- 期間指定は年月のみ（開始年月 YYYY-MM／終了年月 YYYY-MM）。UIに日付入力は出さない。
- 内部では月初〜翌月初未満に変換（例：2026-04〜2026-06 → 2026-04-01 以上 2026-07-01 未満）。
- ZIPファイル名にも年月範囲を含める（例：`okaigumi-csv-export_202604-202606_20260610-1530.zip`）。

**manifest.json：**

- `format_version` / `system` / `exported_at` / `period`（from_month / to_month / granularity / label）/ `files[]`（type / name / rows）を記録する。
- ビューアー側の自動判定・出力内容確認・将来の互換性管理に使う。

**管理コンソール側の将来UI：**

- 対象期間（開始年月・終了年月）／「CSV一式をZIPで出力（推奨）」／「個別CSV出力（詳細・予備）」。

**ビューアー側の将来UI：**

- 「CSV出力パッケージZIPを読み込む（推奨）」をメイン導線にし、パッケージ情報（出力日時・対象期間・format_version・ファイル一覧/行数）と読み込み結果を表示。
- 「個別CSV読込（詳細・予備）」は残す。ZIP読込後は既存の複数CSV統合処理を再利用する。
- 読み込み判定優先順位：manifest.json の type → ファイル名 → CSVヘッダー。

**注意点：**

- ZIPには原価情報・従業員情報・請求書情報が含まれる。public URL / Vercel公開領域 / public Storage には置かない。
- ZIP原本も編集禁止。加工する場合はコピーを作る。pCloud 保管・NAS 複製・外付けHDD月次退避の対象候補とする。
- ZIP化しても内部のCSV列定義は変更しない（`docs/csv-export-spec.md` を維持）。

**今後の実装ステップ：**

```text
2-4-8-0：CSV出力パッケージ仕様設計（完了）
2-4-8-1：ZIPライブラリ同梱方針整理
2-4-8-2：管理コンソール ZIP出力UI設計
2-4-8-3：管理コンソール ZIP出力実装
2-4-8-4：ローカルCSVビューアー ZIP読込UI設計
2-4-8-5：ローカルCSVビューアー ZIP読込実装
2-4-8-6：manifest.json 検証・表示対応
2-4-8-7：docs・運用手順整理
```

#### Phase 2-4-8-1：ZIPライブラリ同梱方針整理（完了）

- 状態：方針整理完了 / 実装：未着手 / ライブラリ本体追加：未実施
- 設計ドキュメント：[`docs/csv-export-package-spec.md`](csv-export-package-spec.md) §13
- 対象：ZIP生成・ZIP読込に使うJavaScriptライブラリの選定方針、配置方針、ライセンス記録方針

**方針：**

- ZIP処理ライブラリの第一候補は **JSZip**（ブラウザでZIP生成/読込の両対応、JSのみで動作、`file://` 同梱可）。
- 外部CDN不使用／ローカル同梱／バージョン固定／`file://` 動作維持。
- 推奨配置：`vendor/jszip/jszip.min.js`（案B。管理コンソールZIP出力とビューアーZIP読込で共通利用を想定。共通管理しやすい）。
  - ローカルCSVビューアーを pCloud 等で配布する場合は `local-viewers/csv-viewer.html` ＋ `vendor/jszip/jszip.min.js` を一式で配布する必要がある。
- ライセンス・入手元・バージョンを docs に記録する方針（実装時に再確認・固定）。
- **今回はライブラリ本体追加なし（`vendor` ディレクトリ・`*.min.js` も追加しない）。**

**JSZip 調査結果（npm view・方針整理時点）：**

```text
バージョン（npm latest）：3.10.1
ライセンス：(MIT OR GPL-3.0-or-later)
入手元：https://github.com/Stuk/jszip#readme
リポジトリ：git+https://github.com/Stuk/jszip.git
```

**次フェーズ候補：**

- Phase 2-4-8-2：ZIPライブラリ同梱（ライブラリファイル追加を独立コミットで分ける方針を採用）

#### Phase 2-4-8-2：ZIPライブラリ同梱（完了）

- 状態：完了 / 実装：ライブラリ本体の同梱のみ
- 管理コンソール実装：未着手 / ビューアー実装：未着手 / HTML参照追加：未着手
- 設計ドキュメント：[`docs/csv-export-package-spec.md`](csv-export-package-spec.md) §13

**実施内容：**

- JSZip v3.10.1 をリポジトリ内に同梱
  - 配置先：`vendor/jszip/jszip.min.js`
  - ライセンスファイル：`vendor/jszip/LICENSE.markdown`
  - 同梱メモ：`vendor/jszip/README.md`
- ライセンス：`MIT OR GPL-3.0-or-later`
- 入手元：npm package `jszip@3.10.1`
- 外部CDN不使用 / バージョン固定 / `file://` 運用維持方針
- 管理コンソールZIP出力とローカルCSVビューアーZIP読込の共通利用を想定
- **今回はライブラリ追加のみ。** `admin-app.html` への組み込みは未実装。`local-viewers/csv-viewer.html` への組み込みは未実装。HTMLへの `<script src>` 追加は未実装。ZIP出力・ZIP読込ロジックは未実装。

**次フェーズ候補：**

- Phase 2-4-8-3：管理コンソール ZIP出力UI設計

#### Phase 2-4-8-3：管理コンソール ZIP出力UI設計（完了）

- 状態：設計完了 / 実装：未着手
- 設計ドキュメント：[`docs/csv-export-package-spec.md`](csv-export-package-spec.md) §14
- 対象：管理コンソールのCSV出力画面、年月指定UI、ZIP出力ボタン、個別CSV出力の予備化

**設計内容：**

- 対象期間は**年月のみ**（開始年月・終了年月。`<input type="month">` 案。日付指定は出さない。裏側で月初〜翌月初未満に変換）。
- UIは「CSV一式をZIPで出力（推奨）」をメイン導線にする。
- 個別CSV出力は廃止せず、詳細・予備・トラブル対応用として残す。
- ZIP出力時に `manifest.json`（format_version / system / exported_at / period / files[]）生成を前提にする。
- ZIPファイル名ルール：`okaigumi-csv-export_YYYYMM-YYYYMM_YYYYMMDD-HHMM.zip`。
- 出力対象は4CSV。データなしCSVもヘッダーのみ/0行で同梱し、行数を manifest に記録。
- バリデーション：開始/終了年月の空・逆転をエラー、長期間は警告検討、0件でもヘッダー＋manifest出力、ZIP失敗時は個別CSV出力を案内。
- ZIP出力実装時は同梱済み JSZip（`vendor/jszip/jszip.min.js`）を使用予定。外部CDNは使わない。
- **今回は設計のみ。** `admin-app.html` の変更なし。ZIP出力ロジック未実装。HTMLへの `<script>` 追加なし。
- ZIPには原価情報・従業員情報・請求書情報が含まれるため、public領域に置かない。ZIP原本は編集禁止。

**次フェーズ候補：**

- Phase 2-4-8-4：管理コンソール ZIP出力実装

#### Phase 2-4-8-4：管理コンソール ZIP出力実装（完了）

- 実装コミット：`11b01aa Add admin CSV ZIP export`
- 対象ファイル：`admin-app.html`（このファイルのみ変更）
- 設計ドキュメント：[`docs/csv-export-package-spec.md`](csv-export-package-spec.md) §14

**実装内容：**

- 管理コンソールCSV出力ページに、年月指定UIと「CSV一式をZIPで出力（推奨）」ボタンを追加。
- JSZipはローカル同梱ファイル（`vendor/jszip/jszip.min.js`）を参照。外部CDNは追加していない。
- `service_role` 追加なし。inline `onclick` 追加なし（ボタンは id ＋ `addEventListener` で配線）。
- 既存の個別CSV出力は削除せず、詳細・予備として残した。
- 既存のCSV列仕様（`CSV_COLUMNS`）は変更していない。既存RPCを再利用し、新規RPCは作成していない。
- SQL実行・DB変更なし。

**追加UI：**

- 開始年月 `<input type="month">` / 終了年月 `<input type="month">`
- 「CSV一式をZIPで出力（推奨）」ボタン
- 「個別CSV出力（詳細・予備）」見出し ＋ 用途注記

**追加関数：**

- `monthToStartDate` / `monthToEndDate` / `formatPeriodLabel` / `formatZipTimestamp` / `formatExportedAtJst` / `currentMonthStr` / `buildCsvText` / `exportCsvZip`

**ZIP出力内容：** `projects_summary.csv` / `attendance_details.csv` / `project_cost_details.csv` / `machine_details.csv` / `manifest.json`

**ZIPファイル名：** `okaigumi-csv-export_YYYYMM-YYYYMM_YYYYMMDD-HHMM.zip`

**manifest.json：** `format_version` / `system` / `exported_at` / `period.from_month` / `period.to_month` / `period.granularity = month` / `period.label` / `files[].type` / `files[].name` / `files[].rows`

**挙動：**

- ZIP生成中はボタンを disabled にし、文言を「ZIP作成中...」へ変更。完了・失敗後にボタン状態を復元。
- ZIP出力失敗時は個別CSV出力の利用を案内。
- 生成ZIPはリポジトリに残さない。

**年月指定の実装仕様：**

```text
利用者には年月のみ選ばせる。
日付入力は出さない。

開始年月は月初日へ変換する。
例：2026-04 → 2026-04-01

終了年月は、管理コンソールの既存RPCが date_to_input を inclusive 比較で扱う想定に合わせ、月末日へ変換して渡す。
例：2026-06 → 2026-06-30

manifest.json とZIPファイル名には年月粒度の from_month / to_month を記録する。
```

補足：設計上の「月初〜翌月初未満」という考え方は期間概念として維持するが、現行RPC呼び出しでは既存仕様に合わせて終了月の月末日を `date_to_input` に渡す。

**実ブラウザ確認（OK）：**

- 管理コンソール表示OK / CSV出力エリア表示OK
- 開始年月 input type=month OK / 終了年月 input type=month OK
- CSV一式をZIPで出力（推奨）ボタンOK / 個別CSV出力（詳細・予備）が残っていることOK
- JSZip読込確認OK
- 開始年月空・終了年月空・開始年月>終了年月のバリデーションOK（いずれも早期return）
- ZIP生成OK / ZIPファイル名OK / ZIP内に4CSV＋manifest.json があることOK / manifest.json の内容OK
- 個別CSV出力回帰OK / 既存CSV列仕様が壊れていないことOK
- Console重大エラーなし / JS構文チェックOK

**未実装（次フェーズ以降・未着手）：**

- ローカルCSVビューアー側のZIP読込UI
- ローカルCSVビューアー側のZIP読込実装
- ZIP読込後のmanifest表示
- ZIP読込後の複数CSV統合モード自動反映
- 実ログイン環境での実データ最終確認

**次フェーズ候補：**

- Phase 2-4-8-5：ローカルCSVビューアー ZIP読込UI設計
- Phase 2-4-8-6：ローカルCSVビューアー ZIP読込実装
- Phase 2-4-8-7：manifest.json 検証・表示対応

#### Phase 2-4-8-5：ローカルCSVビューアー ZIP読込UI設計（完了）

- 状態：設計完了 / 実装：未着手
- 設計ドキュメント：[`docs/csv-export-package-spec.md`](csv-export-package-spec.md) §16
- 対象：複数CSV統合モード、ZIP読込導線、manifest表示、個別CSV読込の予備化

**設計内容：**

- ZIP読込をメイン導線にする（「CSV出力パッケージZIPを読み込む（推奨）」カードを統合モード上部に追加）。
- 個別CSV読込は削除せず、詳細・予備として残す。
- CSV種別判定は `manifest.json` の `files[].type` を最優先。manifestがない場合は警告し、ファイル名 → CSVヘッダー（既存 `detectCsvType`）にフォールバックする。
- ZIP読込後は既存の複数CSV統合処理（`multiState`・各集計関数・各描画関数・工事別詳細・印刷/PDF）を再利用する。集計ロジック・CSV列仕様は変更しない。
- パッケージ情報表示：ファイル名 / 出力日時 exported_at / 対象期間 period.label / format_version / system / manifest読込状態 ／ ZIP内ファイル一覧（type / name / rows / 読込状態）。
- UI状態：未選択 / 選択済み / 読込中 / 読込成功 / 警告あり / エラー / クリア済み。
- エラー・警告方針：
  - エラー＝ZIPが読めない／JSZip未読込／projects_summaryなし／必須CSVが解析不可／manifest破損でフォールバックも不可。
  - 警告＝manifestなし／format_version未対応／任意CSVなし／unknown CSV／type重複／manifest rowsと実行数の不一致／0行CSV。
  - 0行CSVはエラーではなく行数0扱い。
- JSZip参照パス案：`../vendor/jszip/jszip.min.js`（`csv-viewer.html` は `local-viewers/` 配下、JSZip は `vendor/jszip/` 配下）。外部CDN不使用・`file://` 維持。
- 印刷：ZIP読込後の統合ビュー・パッケージ情報は印刷対象。ZIPファイル選択・読込ボタンは印刷対象外。既存の印刷レイアウトを維持。
- **今回は設計のみ。** `local-viewers/csv-viewer.html` の変更なし。ZIP読込実装なし。HTMLへの `<script>` 追加なし。

**次フェーズ候補：**

- Phase 2-4-8-6：ローカルCSVビューアー ZIP読込実装

#### Phase 2-4-8-6：ローカルCSVビューアー ZIP読込実装（完了）

- 実装コミット：`c867027 Add viewer ZIP package import`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）

**実装内容：**

- ローカルCSVビューアーの複数CSV統合モードに、CSV出力パッケージZIP読込機能を追加
- JSZipはローカル同梱ファイルを参照（`../vendor/jszip/jszip.min.js`）
- 外部CDNは追加していない
- Supabase接続情報・service_role は追加していない
- inline `onclick` は追加していない
- ZIP読込はローカルブラウザ内で完結
- CSV由来値は `textContent` / DOM API で描画
- 既存の個別CSV読込は「詳細・予備」として残した
- ZIP読込は、既存の複数CSV統合処理への入口として実装
- 集計ロジック・CSV列仕様は変更していない
- ZIP読込時は既存の複数CSV状態を一旦クリアし、ZIP内CSVで置換する
- 古い個別CSVと新しいZIP内CSVの混在を防ぐ設計

**追加UI：**

- 「CSV出力パッケージZIPを読み込む（推奨）」カード
- ZIPファイル選択
- 選択中ファイル名表示
- ZIPを読み込むボタン
- クリアボタン
- 状態メッセージ
- パッケージ情報表示
- ZIP内ファイル一覧
- 個別CSV読込（詳細・予備）見出し
- 個別CSV読込の注記

**追加・変更した主な関数：**

- `emptyMultiPackage`
- `zipBaseName`
- `isIgnoredZipEntry`
- `parseZipManifest`
- `buildZipManifestTypeMap`
- `detectZipEntryCsvType`
- `headerCsvTypeOf`
- `setMultiZipStatus`
- `handleMultiZipFileChange`
- `loadMultiZipPackage`
- `clearMultiZipPackage`
- `renderMultiPackageInfo`
- `loadMultiSlotFromText`
- 既存の `loadMultiSlot` は、非finalizeのコア `loadMultiSlotFromText` と薄いラッパにリファクタした（個別CSV読込の挙動は維持）

**ZIP読込ロジック：**

- `JSZip.loadAsync(file)` でZIPを展開
- `__MACOSX`、隠しファイル、フォルダは無視
- manifest.json を探索・解析
- manifest がある場合は `files[].type` をCSV種別判定に優先使用
- manifest がない場合は警告を出し、ファイル名・CSVヘッダー判定にフォールバック
- CSV種別判定順
  1. manifest.json の `files[].type`
  2. ファイル名
  3. CSVヘッダー
- 対象CSV
  - `projects_summary`
  - `attendance_details`
  - `project_cost_details`
  - `machine_details`
- 各CSVを既存スロットへ流し込み
- 最後に `finalizeMulti()` を1回実行
- 既存の集計・描画処理を再利用

**manifest.json の扱い：**

- `exported_at`
- `system`
- `format_version`
- `period.label`
- `files[].type`
- `files[].name`
- `files[].rows`
- manifest rows と実CSV rows の照合
- 未対応 `format_version` は警告して続行
- manifestなし・manifest解析エラーは警告し、フォールバック判定へ進む
- パッケージ情報として、ファイル名・出力日時・対象期間・format_version・system・manifest読込状態を表示
- ZIP内ファイル一覧として、type / name / manifest rows / 実CSV rows / 読込状態を表示

**エラー・警告確認：**

- ZIP読不可エラーOK
- JSZip未読込エラーOK
- projects_summaryなしZIPはエラーOK
- manifestなしZIPは警告＋ファイル名判定OK
- unknown CSV入りZIPは警告OK
- 同一type重複は先頭採用＋警告OK
- manifest rows不一致は警告OK
- 0行CSVはrows 0扱い＋警告OK
- 任意CSVなしは警告または未読込扱いOK

**実ブラウザ確認（OK）：**

- ローカルCSVビューアー表示OK
- 複数CSV統合モード表示OK
- ZIP読込カード表示OK
- ZIPファイル選択OK
- ZIP読込ボタンOK
- クリアボタンOK
- 個別CSV読込（詳細・予備）が残っていることOK
- JSZip読込OK
- 4CSV + manifest 自動読込OK
- パッケージ情報表示OK
- ZIP内ファイル一覧表示OK
- 行数表示OK
- 読み込み状況ダッシュボードOK
- 簡易工事一覧OK
- 確認リストOK
- 工事選択OK
- 工事別月別原価OK
- 差異確認カードOK
- 月別労務費OK
- 月別請求書費用OK
- 請求書明細OK
- 労務明細OK
- NaN表示なし
- Console重大エラーなし
- JS構文チェックOK
- 個別CSV読込回帰OK
- 単体CSVモード回帰OK

**印刷/PDF確認（OK）：**

- ZIP読込後の統合ビュー印刷OK
- パッケージ情報が印刷対象に含まれることOK
- ZIPファイル選択・読込ボタン・クリアボタンは印刷対象外OK
- 確認リスト・差異確認・月別原価の既存印刷レイアウト維持OK

**未実装（次フェーズ以降・未着手）：**

- manifest.json 検証・表示のさらなる強化
- 管理コンソールで出力した実ZIPを使った実ログイン環境での通し確認
- 運用手順整理
- pCloud / NAS への保存運用手順化

**次フェーズ候補：**

- Phase 2-4-8-7：manifest.json 検証・表示対応
- Phase 2-4-8-8：管理コンソールZIPとビューアーZIP読込の結合確認
- Phase 2-4-8-9：docs・運用手順整理

#### Phase 2-4-8-8：管理コンソールZIPとビューアーZIP読込の結合確認（完了）

- 種別：通し確認のみ。**実装変更なし／docs変更前の確認時点では `git status` clean。**
- 管理コンソール側のZIP出力は、岡井さんが本番adminにログインして実施（実ログインが必要なため）。読込側はローカルCSVビューアーで確認。

**確認環境：**

- 本番admin（`https://system.okaigumi.co.jp/admin`）で実ZIP出力
- ローカルHTTP配信
- Playwrightブラウザ
- `local-viewers/csv-viewer.html`

**対象期間：**

- `2026-06` 〜 `2026-06`
- `period.label`：`2026年6月分`

**実ZIP：**

- ファイル名：`okaigumi-csv-export_202606-202606_20260610-1446.zip`
- サイズ：`16,503 bytes`
- ZIPファイル名は命名規則 `okaigumi-csv-export_YYYYMM-YYYYMM_YYYYMMDD-HHMM.zip` に合致

**ZIP内ファイル確認：**

```text
projects_summary.csv：10行
attendance_details.csv：41行
project_cost_details.csv：0行
machine_details.csv：22行
manifest.json：あり
```

- ZIP内に余計な生成物なし
- 各CSVにUTF-8 BOMあり
- 各CSVヘッダーが `CSV_COLUMNS` と一致
- 列数：projects_summary 23列／attendance_details 20列／project_cost_details 13列／machine_details 10列
- manifest rows と実CSVデータ行数は全て一致

**manifest確認：**

- `format_version`：`1.0`
- `system`：`okaigumi-internal-system`
- `exported_at`：`2026-06-10T14:46:14+09:00`
- `period.from_month`：`2026-06`
- `period.to_month`：`2026-06`
- `period.granularity`：`month`
- `period.label`：`2026年6月分`
- `files[].type` あり／`files[].name` あり／`files[].rows` あり

**ビューアーZIP読込確認：**

- 複数CSV統合モード表示OK
- ZIP読込カード表示OK
- ZIPファイル選択OK
- ZIP読込OK
- クリアボタンOK
- JSZip読込OK
- manifest読込状態OK
- 4CSV自動読込OK
- パッケージ情報表示OK
- ZIP内ファイル一覧表示OK
- manifest rows 表示OK
- 実CSV rows 表示OK
- 読込状態表示OK
- Console重大エラーなし

**複数CSV統合ビュー反映：**

- 読み込み状況：projects_summary 10行／attendance_details 41行／project_cost_details 0行／machine_details 22行
- 工事件数：10
- 労務明細：41／請求書明細：0／重機台帳：22
- 労務費合計：902,000円
- 労務費対象工事：7／労務費対象月数：1
- 請求書費用：0円
- 月別原価合計：902,000円
- 差異確認：2／横断確認：24／確認事項：26
- エラー件数：0
- NaN表示なし

**工事詳細確認：**

確認工事：`（一)加古川水系大和川護岸整備工事（その３）`

- 工事詳細表示OK
- 発注者：大志株式会社
- 年度：2025
- projects_summary 労務費：264,000円
- attendance由来 労務費：264,000円
- 差額：0
- 工事別月別原価：2026年6月 264,000円／累計 264,000円
- 差異確認カード：全項目一致
- 月別労務費OK／労務明細OK
- 月別請求書費用：0行／請求書明細：0行
- 空表示でも崩れなし
- 戻る操作OK

**manifest優先判定：**

- 4CSVすべて `manifest` 判定で読み込み済み
- `projects_summary` 正しく割当
- `attendance_details` 正しく割当
- `project_cost_details` 正しく割当
- `machine_details` 正しく割当

**印刷/PDF確認：**

- print emulationで確認
- パッケージ情報は印刷対象
- ZIPファイル選択・読込・クリアボタンは印刷対象外
- 読み込み状況は印刷対象
- 簡易工事一覧は印刷対象
- 確認リストは印刷対象
- 工事詳細の差異確認は印刷対象
- 工事別月別原価は印刷対象
- 戻るボタンは印刷対象外
- PDF保存OK
- 一時フォルダに約144KBのPDFを生成して確認後削除

**Console / 一時ファイル：**

- Console重大エラーなし
- favicon.ico 404 のみで無害
- 展開CSV・manifest・PDF・一時サーバースクリプトはリポジトリ外の一時フォルダで扱った
- 確認後、一時フォルダごと削除済み
- ダウンロードした実ZIP本体は Downloads に残置
- リポジトリ内に `okaigumi-csv-export*`、manifest、展開CSV、`.playwright-cli` 等の混入なし
- `git status` clean

**補足：**

```text
今回の対象期間 2026-06 では project_cost_details.csv が0行だった。
そのため請求書費用・費目別・月別請求書費用は0表示となり、横断確認に「請求書明細なし」が複数表示された。
これは正常な確認事項表示であり、ビューアーの不具合ではない。
```

```text
請求書明細が入っている期間（例：2026-04〜2026-06など）でも一度通し確認すると、費目別・月別請求書費用の反映まで実データで確認できる。
```

**次回候補：**

```text
Phase 2-4-8-7：manifest.json 検証・表示対応（必要になった場合のみ）
請求書明細あり期間での追加通し確認
Phase 2-4-8-9：docs・運用手順整理
pCloud / NAS 保存運用ルール策定
```

**実装状況：Phase 2-4-8 は 2-4-8-6（ローカルCSVビューアー ZIP読込実装）まで実装完了、2-4-8-8（実ZIP結合確認）まで確認完了。管理コンソールZIP出力・ローカルCSVビューアーZIP読込ともに実装済みで、本番admin出力の実ZIPによる通し確認も2026-06単月（請求書0件ケース）で実施済み。2-4-8-7（manifest検証強化）・請求書明細あり期間での追加確認・2-4-8-9（運用手順整理）は未着手。**

#### Phase 2-4-8-9：docs・運用手順整理（完了）

- 種別：docs整理のみ。実装変更なし。
- 新規作成：[`docs/csv-export-operation-guide.md`](csv-export-operation-guide.md)

**記録内容：**

- `docs/csv-export-operation-guide.md` を新規作成。
- CSV一式ZIP出力からローカルCSVビューアー確認までの月次運用手順を整理。
- pCloud / 外付けHDD / 将来UGREEN NASync の役割を整理。
- NASは現時点では未導入。
- 後日 UGREEN NASync を購入予定。
- Phase 2-4-8-9 では、pCloud中心の現行運用と、UGREEN NASync導入後の将来運用を分けて整理した。
- ZIP原本・CSV原本の編集禁止ルールを明記。
- ビューアー配布時の相対パス注意を明記（`local-viewers/` と `vendor/jszip/` の相対位置を維持）。
- 月次確認チェックリストを作成。
- 現時点チェックとUGREEN NASync導入後チェックを分けた。
- 0行CSVの扱いを整理。
- 確認リスト・差異確認の読み方を整理。
- 会計事務所へ渡す場合の注意を整理。
- バックアップ対象を整理。
- 削除・復元ルールを整理。
- セキュリティ注意を整理。
- 未決事項を整理。

**バックアップ運用の整理（現時点／将来）：**

```text
現時点：
  日常保管：pCloud
  暫定バックアップ：外付けHDD

将来：
  日常保管：pCloud
  社内バックアップ：UGREEN NASync（後日購入予定・未導入）
  最終退避：外付けHDD
```

**次回候補：**

```text
Phase 2-4-8-7：manifest.json 検証・表示対応（必要になった場合のみ）
請求書明細あり期間での追加通し確認
UGREEN NASync 導入後のバックアップ運用手順の具体化
```

### Phase 2-4-9：CSVビューアーUX改善（設計開始）

#### Phase 2-4-9-0：CSVビューアー画面構成・ページ遷移設計（完了）

- 種別：設計ドキュメントのみ。**実装は未着手。** `local-viewers/csv-viewer.html` は変更しない。
- 設計ドキュメント：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md)

**記録内容：**

- CSVビューアーUX改善フェーズを開始。
- 現在のZIP読込後に複数CSV統合ビューへ直接入る構成を見直す。
- 単体CSVビューが分かりやすかったため、ZIP読込後も単体CSVビューを中心にする方針へ修正。
- 新しい結論：

```text
ZIP読込
↓
帳票選択
↓
単体CSVと同じ見やすい画面
↓
必要な時だけ月次チェック・差異確認
```

- 複数CSV統合ビューは削除しない。
- ただしメイン画面ではなく、最終確認用の「月次チェック・差異確認」として奥に下げる。
- 個別CSV読込は詳細・トラブル対応用として折りたたむ。
- 今回はdocs設計のみ。
- `local-viewers/csv-viewer.html` は変更しない。
- 実装は次フェーズ以降。

**実装ステップ案：**

```text
Phase 2-4-9-0：画面構成・ページ遷移設計 docs
Phase 2-4-9-1：ZIP読込後メニュー実装
Phase 2-4-9-2：ZIP内CSVを単体CSVビューで表示
Phase 2-4-9-3：月次チェック・差異確認へ名称変更
Phase 2-4-9-4：個別CSV読込を折りたたみ化
Phase 2-4-9-5：PDFボタン・画面文言整理
```

**次フェーズ候補：**

```text
Phase 2-4-9-1：ZIP読込後メニュー実装
```

#### Phase 2-4-9-1：ZIP読込後メニュー実装（完了）

- 実装コミット：`08be5ac Add CSV ZIP report selection menu`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）

**記録内容：**

- ZIP読込後に帳票選択メニューを表示するようにした。
- 追加カード：
  - 工事一覧・原価概要
  - 日報・労務費
  - 請求書費用
  - 重機台帳
  - 月次チェック・差異確認
- 各カードにCSV名、件数、説明、開くボタンを表示。
- `project_cost_details.csv` が0件の場合は、対象期間に請求書登録がない場合は正常である旨を表示。
- 月次チェック・差異確認カードから既存統合ビューへ遷移できる。
- 工事詳細から月次チェック・差異確認へ戻る導線を整理。
- 単体CSV帳票カードは現時点では準備中表示。
- 個別CSV読込は削除せず、詳細・トラブル対応用として残置（見出しを「詳細・トラブル対応用：個別CSV読込」に変更）。
- 既存のZIP読込ロジック、CSV列仕様、集計ロジックは変更していない。
- SQL実行・DB変更なし。
- docs記録は本コミット（実装コミットとは分離）。

**実ブラウザ確認（実ZIP 2026年6月分）：**

- 行数 10 / 41 / 0 / 22 表示OK
- 請求書明細0件の正常案内OK
- 月次チェック・差異確認導線OK／工事詳細・戻る導線OK
- NaNなし／Console重大エラーなし（favicon 404 のみ）
- JS構文チェックOK／print emulation確認OK

**次フェーズ候補：**

```text
Phase 2-4-9-2：ZIP内CSVを単体CSVビューで表示
```

#### Phase 2-4-9-2-a：単体CSVビュー接続方針決定（完了）

- 対象ファイル：`docs/csv-viewer-ux-improvement-spec.md`（§14）ほか docs のみ。
- 設計：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §14。

**記録内容：**

- ZIP内CSVを単体CSVビューで表示する前に、接続方針をdocsで確定。
- 案C：handleTextをパース部とstate構築＋描画部に分離する方針を採用。
- warnings/errors を分離時に取りこぼさない方針を明記。
- 単体fileビュー / ZIP帳票選択メニュー / ZIP由来単体ビュー の3状態を定義。
- ZIP由来単体ビューから帳票選択メニューへ戻る導線を定義。
- 単体ビューの印刷/PDF導線は2-4-9-5で本格整備予定。ただし配置場所は2-4-9-2中に考慮。
- project_cost_details 0件は境界ケースとして正常表示を確認する。
- handleText分離後の回帰確認条件を定義。
- 今回はdocs設計のみ。実装コード変更なし。

**次フェーズ候補：**

```text
Phase 2-4-9-2-b：handleText を parse部 と state構築＋描画部 に分離
```

#### Phase 2-4-9-2-b：handleText を parse部 と state構築＋描画部 に分離（完了）

- 実装コミット：`64c699b Split handleText into parse and render phases`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）
- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §15。

**記録内容：**

- `local-viewers/csv-viewer.html` のみ変更。
- `parseSingleCsvText(text)` を追加。
- `buildSingleStateAndRender(args)` を追加。
- `handleText(fileName, text)` は既存入口として残し、`parseSingleCsvText` → `buildSingleStateAndRender` を呼ぶ薄いラッパに変更。
- 旧handleTextが一体で行っていたCSVパース、種別判定、warnings/errors生成、state構築、reports生成、期間推定、renderAllPages呼び出しを責務分離。
- warnings/errors はparse部で生成し、state構築＋描画部で `state.warnings` / `state.errors` へ反映。
- 単体file読込の既存挙動維持を確認。
- jsdom自動回帰で全53項目PASS。
- project_cost_details 0件正常表示を確認。
- 未知CSVエラー表示を確認。
- ZIP読込後メニューへの影響なし。
- 4帳票カードは準備中表示のまま。
- ZIP帳票カード接続は未実装。
- docs記録は本コミット（実装コミットとは分離）。

**次フェーズ候補：**

```text
Phase 2-4-9-2-c：projects_summary をZIP由来で単体ビュー表示
```

#### Phase 2-4-9-2-c：projects_summary をZIP由来で単体ビュー表示（完了）

- 実装コミット：`f2b1b1c Connect ZIP projects summary to single CSV viewer`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）
- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §16。

**記録内容：**

- `local-viewers/csv-viewer.html` のみ変更。
- 帳票選択メニューの「工事一覧・原価概要」カードから、ZIP内 `projects_summary.csv` を単体CSVビュー形式で表示できるようにした。
- `openZipSingleReport(type)` を追加。
- `backFromZipSingleToMenu()` を追加。
- `openMultiReport(key,title)` は `projects_summary` のみ `openZipSingleReport` へ分岐。
- `loadMultiSlotFromText()` で headers を `multiState.files[slotKey].headers` に保持。
- `buildSingleStateAndRender({ source:'zip', ... })` を使い、既存単体CSVビューを再利用。
- `multiState` は保持したまま、`state` のみZIP由来 `projects_summary` で上書き。
- ZIP由来単体ビュー上部に「帳票選択メニューに戻る」導線を追加。
- 読込元「ZIP内 projects_summary.csv」と対象期間を表示。
- 工事一覧、年度別、発注者別、工事分類別、工事詳細を確認可能。
- 既存の工事詳細→一覧の戻り導線は維持。
- 帳票選択メニューへ戻った後もZIP読込状態を保持。
- 月次チェック・差異確認も引き続き開ける。
- `attendance_details` / `project_cost_details` / `machine_details` は準備中表示のまま。
- PDF保存ボタンは未実装。本格整備は Phase 2-4-9-5 予定。
- jsdom自動回帰で全42項目PASS。
- SQL実行・DB変更なし。
- docs記録は本コミット（実装コミットとは分離）。

**次フェーズ候補：**

```text
Phase 2-4-9-2-d：attendance_details をZIP由来で単体ビュー表示
```

#### Phase 2-4-9-2-d：attendance_details をZIP由来で単体ビュー表示（完了）

- 実装コミット：`c7b1cc4 Connect ZIP attendance details to single CSV viewer`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）
- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §17。

**記録内容：**

- `local-viewers/csv-viewer.html` のみ変更。
- `openMultiReport(key,title)` の分岐条件に `attendance_details` を追加。
- ZIP読込後の帳票選択メニューから「日報・労務費」カードを実接続。
- ZIP内 `attendance_details.csv` を単体CSVビュー形式で表示できるようにした。
- `openZipSingleReport(type)` は既存の汎用処理をそのまま利用。
- `buildSingleStateAndRender({ source:'zip', ... })` を使い、既存 attendance_details 単体CSVビューを再利用。
- `buildAttendanceReports` は無変更。
- report_id ピボット・二重計上防止の維持を確認。
- report_date による minDate / maxDate 推定を確認。
- 月別サマリー、従業員別サマリー、全体サマリー、社員別月別詳細を確認。
- ZIP由来単体ビュー上部の戻る導線、読込元、対象期間表示は projects_summary と同じ仕組みを踏襲。
- 帳票選択メニューへ戻った後もZIP読込状態を保持。
- projects_summary は引き続き接続済み。
- `project_cost_details` / `machine_details` は準備中表示のまま。
- jsdom自動回帰で全47項目PASS。
- SQL実行・DB変更なし。
- docs記録は本コミット（実装コミットとは分離）。

**次フェーズ候補：**

```text
Phase 2-4-9-2-e：project_cost_details をZIP由来で単体ビュー表示
```

#### Phase 2-4-9-2-e：project_cost_details をZIP由来で単体ビュー表示（完了）

- 実装コミット：`34d5d73 Connect ZIP project cost details to single CSV viewer`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）
- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §18。

**記録内容：**

- `local-viewers/csv-viewer.html` のみ変更。
- `openMultiReport(key,title)` の分岐条件に `project_cost_details` を追加。
- ZIP読込後の帳票選択メニューから「請求書費用」カードを実接続。
- ZIP内 `project_cost_details.csv` を単体CSVビュー形式で表示できるようにした。
- `openZipSingleReport(type)` は既存の汎用処理をそのまま利用。
- `buildSingleStateAndRender({ source:'zip', ... })` を使い、既存 project_cost_details 単体CSVビューを再利用。
- `aggregateInvoices` / `computeInvoiceChecks` は無変更。
- 0件CSVでも errors空・dashboard正常表示・NaNなしを確認。
- 0件時に「この期間の請求書明細は0件です。対象期間に請求書登録がない場合は正常です。」の安心文言を条件付き表示。
- データありCSVでは invoice_date による minDate / maxDate 推定を確認。
- 請求書一覧、業者別、工事別、月別、費目別、確認リストを確認。
- ZIP由来単体ビュー上部の戻る導線、読込元、対象期間表示は既存仕組みを踏襲。
- 帳票選択メニューへ戻った後もZIP読込状態を保持。
- projects_summary / attendance_details は引き続き接続済み。
- `machine_details` は準備中表示のまま。
- jsdom自動回帰で全41項目PASS。
- SQL実行・DB変更なし。
- docs記録は本コミット（実装コミットとは分離）。

**次フェーズ候補：**

```text
Phase 2-4-9-2-f：machine_details をZIP由来で単体ビュー表示
```

#### Phase 2-4-9-2-f：machine_details をZIP由来で単体ビュー表示（完了）

- 実装コミット：`26d7a30 Connect ZIP machine details to single CSV viewer`
- 対象ファイル：`local-viewers/csv-viewer.html`（このファイルのみ変更）
- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §19。

**記録内容：**

- `local-viewers/csv-viewer.html` のみ変更。
- `openMultiReport(key,title)` の分岐条件に `machine_details` を追加。
- ZIP読込後の帳票選択メニューから「重機台帳」カードを実接続。
- ZIP内 `machine_details.csv` を単体CSVビュー形式で表示できるようにした。
- `openZipSingleReport(type)` は既存の汎用処理をそのまま利用。
- `buildSingleStateAndRender({ source:'zip', ... })` を使い、既存 machine_details 単体CSVビューを再利用。
- `machineCostRaw` / `computeMachineChecks` は無変更。
- 重機一覧、所有/リース別集計、月額表示、確認リストを確認。
- 0件CSVでも errors空・正常表示・NaNなしを確認。
- ZIP由来単体ビュー上部の戻る導線、読込元、対象期間表示は既存仕組みを踏襲。
- 帳票選択メニューへ戻った後もZIP読込状態を保持。
- projects_summary / attendance_details / project_cost_details / machine_details の4カードすべて接続済み。
- jsdom自動回帰で全40項目PASS。
- SQL実行・DB変更なし。
- docs記録は本コミット（実装コミットとは分離）。

**次フェーズ候補：**

```text
Phase 2-4-9-2-g：全帳票回帰確認
```

#### Phase 2-4-9-2-g：全帳票回帰確認（完了）

- 確認対象：ZIP内CSVを単体CSVビューで表示する4帳票全体。
- 実装変更なし。docs記録は本コミット。
- 確認結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §20。

**記録内容：**

- jsdomで実HTML＋実コードをヘッドレス実行。
- ZIP読込状態は `loadMultiSlotFromText` + `finalizeMulti` で再現。
- periodLabel は 2026年6月分。
- データありZIP＋0件ZIPの2シナリオを連続実行。
- 総合 jsdom 回帰：全90項目PASS。
- PASS件数：90 pass / 0 fail。
- projects_summary：工事一覧・年度別・発注者別・分類別・工事詳細・戻り導線OK。
- attendance_details：月別・従業員別・全体・社員別月別詳細・report_idピボット・二重計上防止OK。
- project_cost_details：請求書一覧・業者別・工事別・月別・費目別・確認リスト・0件正常表示OK。
- machine_details：重機一覧・所有/リース別集計・月額表示・確認リスト・0件正常表示OK。
- 月次チェック・差異確認：確認リスト・警告エラー表示・工事詳細・戻り導線OK。
- 個別CSV読込回帰：4帳票すべてOK。
- ZIP由来単体表示と個別CSV読込が混同しないことを確認。
- 4カード操作後でも月次チェック・差異確認を開けることを確認。
- 戻った後も `multiState.loaded` と rows が保持されることを確認。
- NaN表示なし。
- Console重大エラーなし。
- git status clean。
- SQL実行・DB変更なし。
- Phase 2-4-9-2「ZIP内CSVを単体CSVビューで表示」は完了。

**次フェーズ候補：**

```text
Phase 2-4-9-3：ZIP読込後UXの微調整
または
Phase 2-4-9-5：ZIP由来単体ビューのPDF保存ボタン本格整備
```

※ 現時点では、PDF保存ボタンは未実装のままでよい。

#### Phase 2-4-9-3：ZIP読込後UXの微調整 設計（設計のみ）

- 設計結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §21。

**記録内容：**

- Phase 2-4-9-2 で4帳票接続は完了済み。
- 次は実運用時の分かりやすさを改善する。
- 今回は設計のみで実装変更なし。
- ZIP読込後の基本導線は「帳票選択メニュー → 各帳票 → 帳票選択メニュー」。
- 月次チェック・差異確認は4帳票とは別の横断確認画面として扱う。
- 個別CSV読込は通常運用では目立たせず、詳細・トラブル対応用として折りたたみ候補にする。
- ZIP由来単体ビューの上部には、戻る導線・読込元・対象期間を統一表示する。
- PDF保存ボタンは今後 Phase 2-4-9-5 で整備予定。
- SQL実行・DB変更なし。

**次フェーズ候補：**

```text
Phase 2-4-9-3-a：帳票選択メニュー文言・説明文の微調整
Phase 2-4-9-3-b：個別CSV読込エリアの折りたたみ
Phase 2-4-9-5：ZIP由来単体ビューのPDF保存ボタン本格整備
```

#### Phase 2-4-9-3-a：帳票選択メニュー文言・補足説明の微調整（完了）

- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §22。

**記録内容：**

- 実装コミット：`cca89af Refine ZIP report menu labels and grouping`。
- `local-viewers/csv-viewer.html` のみ変更。
- 帳票選択メニューを「個別帳票を確認」と「横断チェック」の2セクション構造に整理。
- メニュー上部に、通常は4つの個別帳票で確認し、最後に月次チェック・差異確認で全体の違和感を確認する旨の説明を追加。
- 個別帳票セクションに projects_summary / attendance_details / project_cost_details / machine_details の4カードを配置。
- 横断チェックセクションに月次チェック・差異確認カードを配置。
- 4帳票カードの説明文を実運用向けに更新。
- 月次チェック・差異確認カードの説明文を「4帳票をまとめて、確認事項・差異・違和感を確認します。」に統一。
- `.menu-section` / `.menu-section-title` / `.menu-section-desc` の最小CSSを追加。
- `openMultiReport` / `openZipSingleReport` / `buildSingleStateAndRender` / 集計ロジックは無変更。
- 4帳票接続への影響なし。
- 月次チェック・差異確認への影響なし。
- jsdom自動回帰で全32項目PASS。
- SQL実行・DB変更なし。
- docs記録は本コミット。

**次フェーズ候補：**

```text
Phase 2-4-9-3-b：個別CSV読込エリアの折りたたみ
Phase 2-4-9-3-c：ZIP由来単体ビュー上部情報の微調整
Phase 2-4-9-5：印刷・PDF保存導線の整備
```

#### Phase 2-4-9-3-b：個別CSV読込エリアの折りたたみ（完了）

- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §23。

**記録内容：**

- 実装コミット：`d9a87f6 Collapse individual CSV load area in ZIP viewer`。
- `local-viewers/csv-viewer.html` のみ変更。
- 個別CSV読込エリアを「詳細・トラブル対応用」として初期折りたたみ表示に変更。
- 見出し「詳細・トラブル対応用：個別CSV読込」を表示。
- 補足文「通常は上のZIP読込を使ってください。個別CSVを確認したい場合だけ開きます。」を追加。
- 開閉ボタン `#multiIndividualToggle` を追加。
- 折りたたみ本文 `#multiIndividualBody` を追加。
- 既存の `#multiLoadArea` を `#multiIndividualBody` 内へ移動。
- ボタン文言は、閉じている時「個別CSV読込を開く」、開いている時「個別CSV読込を閉じる」。
- `aria-expanded` で開閉状態を表現。
- 未使用 `class="collapsible"` は除去済み。
- 既存の個別CSV読込機能は維持。
- `handleText` 経路は維持。
- `setMode('single')` の意味は変更なし。
- ZIP読込・帳票選択メニュー・4カード接続・月次チェック・集計ロジックは無変更。
- jsdom自動回帰で全35項目PASS。
- SQL実行・DB変更なし。
- docs記録は本コミット。

**次フェーズ候補：**

```text
Phase 2-4-9-3-c：ZIP由来単体ビュー上部情報の微調整
Phase 2-4-9-5：印刷・PDF保存導線の整備
```

#### Phase 2-4-9-3-c：ZIP由来単体ビュー上部情報の微調整（完了）

- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §24。

**記録内容：**

- 実装コミット：`8ca17e0 Clarify ZIP single report header details`。
- `local-viewers/csv-viewer.html` のみ変更。
- ZIP由来単体ビューの上部情報を分かりやすく整理。
- 表示内容を「ZIP内CSVを単体ビューで確認中」「帳票」「読込元」「対象期間」の4行構成に変更。
- 帳票名は `MULTI_MENU_CARDS` の title と統一。
- 読込元は「ZIP内 xxx.csv」として表示。
- 対象期間は `periodLabel` を表示。
- 戻るボタン「← 帳票選択メニューに戻る」は既存のまま維持。
- 個別CSV読込由来の単体ビューは変更なし。
- file読込時の `zipSingleBack` 非表示を維持。
- `openMultiReport` / `buildSingleStateAndRender` / CSV解析 / 集計ロジックは無変更。
- 4帳票すべてで表示確認済み。
- SQL実行・DB変更なし。
- docs記録は本コミット。

**次フェーズ候補：**

```text
Phase 2-4-9-5：印刷・PDF保存導線の整備
```

#### Phase 2-4-9-5：印刷・PDF保存導線の整備 設計（設計のみ）

- 設計の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §25。

**記録内容：**

- Phase 2-4-9-3-c まででZIP読込後UXの微調整は完了済み。
- 次は帳票確認後に保存・共有しやすくするため、印刷・PDF保存導線を整備する。
- 今回は設計のみで実装変更なし。
- PDFライブラリは追加しない。
- ブラウザ標準の `window.print()` を使う。
- ボタン名は「印刷・PDF保存」とする。
- ユーザーがブラウザの印刷画面で「PDFに保存」を選ぶ運用にする。
- ZIP由来単体ビューに「印刷・PDF保存」ボタンを置く方針。
- 月次チェック・差異確認にも「印刷・PDF保存」ボタンを置く方針。
- 帳票選択メニューには置かない方針。
- 個別CSV読込エリアは補助導線のため、まずは対象外にする。
- `file://` 運用を維持する。
- SQL実行・DB変更なし。

**次フェーズ候補：**

```text
Phase 2-4-9-5-a：ZIP由来単体ビューへの印刷・PDF保存ボタン追加
Phase 2-4-9-5-b：月次チェック・差異確認への印刷・PDF保存ボタン追加
Phase 2-4-9-5-c：印刷時CSSの最小調整
```

#### Phase 2-4-9-5-a：ZIP由来単体ビューへの印刷・PDF保存ボタン追加（完了）

- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §26。

**記録内容：**

- 実装コミット：`55f9c0f Add print PDF button to ZIP single viewer`。
- `local-viewers/csv-viewer.html` のみ変更。
- ZIP由来単体ビューに「印刷・PDF保存」ボタンを追加。
- `#zipSingleBack` 内に `#zipSinglePrintBtn` を追加。
- `#zipSinglePrintBtn` は `#zipSingleBack` の `hidden` 制御を継承。
- ZIP由来単体ビューでのみ表示。
- 帳票選択メニューに戻ると非表示。
- 個別CSV読込由来の単体ビューでは非表示。
- click時は `window.print()` のみ実行。
- PDFライブラリは追加しない。
- `inline onclick` は使用しない。`addEventListener` を使用。
- CSV解析・集計ロジックは無変更。
- 月次チェック・差異確認側には今回は追加していない。
- 4帳票すべてで表示確認済み。
- `window.print()` 呼び出し確認済み。
- SQL実行・DB変更なし。
- docs記録は本コミット。

**次フェーズ候補：**

```text
Phase 2-4-9-5-b：月次チェック・差異確認への印刷・PDF保存ボタン追加
Phase 2-4-9-5-c：印刷時CSSの最小調整
```

#### Phase 2-4-9-5-b：月次チェック・差異確認への印刷・PDF保存ボタン追加（完了）

- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §27。

**記録内容：**

- 実装コミット：`7a495ce Move print PDF button to monthly check view`。
- `local-viewers/csv-viewer.html` のみ変更。
- `multiPrintBtn` を `#multiBody` 外側ヘッダから `#multiIntegratedSection` 内へ移動。
- `multiPrintBtn` を `multiIntegratedBack` の右横に配置。
- `multiPrintBtn` の文言を「印刷・PDF保存」に統一。
- `multiDetailPrintBtn` の文言も「印刷・PDF保存」に統一。
- `multiPrintBtn` は `#multiIntegratedSection` の `hidden` 制御を継承。
- 月次チェック・差異確認画面でのみ表示。
- 帳票選択メニュー・ZIP読込ホームでは非表示。
- 既存の `window.print()` `addEventListener` は ID 不変のためそのまま有効。
- ZIP由来単体ビュー用 `zipSinglePrintBtn` は変更なし。
- CSV解析・集計ロジックは無変更。
- 月次チェック内部処理は無変更。
- `window.print()` 呼び出し確認済み。
- SQL実行・DB変更なし。
- docs記録は本コミット。

**次フェーズ候補：**

```text
Phase 2-4-9-5-c：印刷時CSSの最小調整
```

#### Phase 2-4-9-5-c：印刷時CSSの最小調整（完了）

- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §28。

**記録内容：**

- 実装コミット：`b1584c0 Refine print stylesheet for CSV viewer`。
- `local-viewers/csv-viewer.html` のみ変更。
- 既存の `@media print` ブロックを最小調整。
- `.main` に `width:100%` を追加。
- `.card` に `break-inside:avoid` / `page-break-inside:avoid` を追加。
- `table` に `page-break-inside:auto` を追加。
- `tr` に `page-break-inside:avoid` を追加。
- `.no-print` の `display:none!important` は既存維持。
- 操作ボタン類は既存 `no-print` 指定により印刷時非表示。
- ZIP由来単体ビューの帳票本体は印刷対象として維持。
- 月次チェック・差異確認の確認結果は印刷対象として維持。
- 工事詳細表示の内容は印刷対象として維持。
- JS変更なし。HTML構造変更なし。`window.print()` 処理変更なし。
- CSV解析・集計ロジック変更なし。ZIP読込・ZIP出力ロジック変更なし。月次チェック内部処理変更なし。
- SQL実行・DB変更なし。
- docs記録は本コミット。

**次フェーズ候補：**

```text
Phase 2-4-9-6：CSVビューアー運用前最終確認
```

#### Phase 2-4-9-6：CSVビューアー運用前最終確認（完了）

- 確認結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §29。

**記録内容：**

- 確認のみ。実装変更なし。
- 対象：`local-viewers/csv-viewer.html`。
- Phase 2-4-9-2 / 2-4-9-3-a / 2-4-9-3-b / 2-4-9-3-c / 2-4-9-5-a / 2-4-9-5-b / 2-4-9-5-c の累積確認を実施。
- git status clean。
- JS構文チェック OK。
- セキュリティ確認 OK。
- ZIP読込・帳票選択メニュー OK。
- ZIP由来単体ビュー4帳票 OK。
- 月次チェック・差異確認 OK。
- 工事詳細表示 OK。
- 個別CSV読込 OK。
- 印刷CSS OK。
- docs整合性 OK。
- 一時ファイル削除済み。
- SQL実行・DB変更なし。
- 運用前判定：問題なし。CSVビューアーは運用開始可能。
- docs記録は本コミット。

**次フェーズ候補：**

```text
Phase 2-5：運用開始準備・試運用
```

#### Phase 2-4-9-7：高齢者向けGUI改善：CSV一式ZIP主導線化＋可読性・画面整理（完了）

- 実装結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §30。

**実装コミット：**

- b15bb7c Prioritize ZIP CSV flow and improve viewer readability
- 31c4986 Simplify ZIP-first CSV viewer interface

**記録内容：**

- Frontend Design スキルを使用。
- 実運用では単体CSV読込を使わないため、初期導線をCSV一式ZIP読込に一本化。
- 単体CSVタブ、単体CSVファイル選択行、トップ右側の切替ボタン群を通常画面から非表示。
- 個別CSV読込カードを通常画面から非表示。
- 「トラブル対応用」「通常は使いません」「通常は開きません」などの案内も通常画面から非表示。
- 利用者向けの「複数CSV統合」表現を「CSV一式ZIP読込」系へ整理。
- ZIP読込後は帳票選択メニューが目立つように調整。
- 帳票選択メニュー見出しを大きく・濃くした。
- メニュー冒頭説明文を短縮。
- 読込結果の細かい情報をメニュー末尾へ移動。
- 横断チェックカードの色付き背景を撤去し、通常カードと統一。
- 文字サイズ・行間・見出し・説明文・補足文字・ボタン文字を高齢者にも読みやすい方向へ調整。
- 薄いグレー文字のコントラストを改善。
- CSV解析・ZIP読込・集計・月次チェック内部処理は無変更。
- window.print() と @media print は無変更。
- SQL実行・DB変更なし。
- docs記録は本コミット。

**運用前の手動確認推奨：**

- 実ブラウザでの目視確認は未実施。
- 実ブラウザでの印刷プレビュー確認は未実施。
- 実ZIPファイルを使ったブラウザ実読込確認は未実施。

**次フェーズ候補：**

```text
Phase 2-4-9-8：実ブラウザ・実ZIP・印刷プレビューでの手動確認
Phase 2-5：運用開始準備・試運用
```

#### Phase 2-4-9-8：実ブラウザ・実ZIP・印刷プレビューでの手動確認（完了） / Phase 2-4-9-8-a：mode-tabs 非表示不具合の修正（完了）

- 確認・修正結果の詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §31。

**対象コミット：**

- 080522b Document ZIP-first senior-friendly viewer interface
- c2f01e3 Fix hidden CSV mode tabs

**記録内容：**

- 実ブラウザ Chromium でCSVビューアーを確認。
- 実運用相当のCSV一式ZIP（4CSV＋manifest.json）を読み込んで確認。
- 初期表示、ZIP読込、帳票選択メニュー、ZIP由来単体ビュー4帳票、月次チェック・差異確認、工事詳細表示、印刷PDF出力を確認。
- Console重大エラーなし。
- Phase 2-4-9-8 で mode-tabs が実ブラウザで非表示にならない不具合を検出。
- 原因は .hidden より後の .mode-tabs{display:flex} が勝っていたこと（同一詳細度で後勝ち）。jsdom確認では classList のみ見ており computed display を見ていなかったため検出できなかった。
- 重大度は中（印刷出力には影響しないが、通常画面で単体CSV読込へ入れてしまうため運用前に修正すべき）。
- Phase 2-4-9-8-a で .mode-tabs.hidden{display:none!important;} を追加。
- .hidden 全体ではなく .mode-tabs.hidden の targeted fix とした。
- 修正後、実ブラウザで .mode-tabs computed display none を確認（初期表示・ZIP読込後・単体ビュー表示中のいずれでも none）。
- CSV解析・ZIP読込・集計・月次チェック内部処理は無変更。
- window.print() と @media print は無変更。
- SQL実行・DB変更なし。
- docs記録は本コミット。

**残課題（別フェーズ候補）：**

- 観察②：ZIP読込後、ZIP読込カード内のパッケージ詳細＋ZIP内ファイル一覧が上部を占め、帳票選択メニューは下に表示される。メニューをさらに上位へ出す。
- 観察③：月次チェック「簡易工事一覧」の横長表が印刷時に工事名列縦折れ・右端見切れ気味。印刷最適化。

**次フェーズ候補：**

```text
Phase 2-4-9-8-b：ZIP読込後に帳票選択メニューをさらに上位へ表示
Phase 2-4-9-8-c：月次チェック横長表の印刷最適化
Phase 2-5：運用開始準備・試運用
```

#### Phase 2-4-9-8-b：ZIP読込後に帳票選択メニューをさらに上位へ表示（完了）

- 詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §32。

**記録内容：**

- 実装コミット：6ec1ea3 Prioritize report menu after ZIP load
- ZIP読込後に帳票選択メニューがより早く目に入るよう表示順を調整。
- `#multiPackageArea` を帳票選択メニューの後ろへ移設。
- ZIP読込カードを読込後もコンパクト表示。
- パッケージ詳細・ZIP内ファイル一覧・manifest・警告情報を折りたたみ表示へ変更。
- 通常は折りたたみ、警告・エラー時のみ自動展開。
- 実ブラウザで menu top=383px、package details top=1392px を確認。
- CSV解析・ZIP読込・集計・月次チェック内部処理は無変更。
- window.print() と @media print は無変更。

#### Phase 2-4-9-8-d：帳票確認画面の文言・自動読込・配色整理（完了）

- 詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §33。

**記録内容：**

- 実装コミット：512f72e Refine ZIP-first report viewer and admin export flow
- 画面名を「帳票確認」へ整理。
- TOP説明文を「管理コンソールで出力したZIPを選択すると、工事一覧・日報・請求書・重機台帳を確認できます。」へ変更。
- ZIP読込カードを「管理コンソールで出力したZIPを選択」へ変更。
- ZIP選択後に自動読込。
- ZIP読込ボタンを通常画面から非表示。
- 帳票選択メニュー見出しに対象期間を表示。
- raw CSVファイル名、ZIPファイル名、出力日時、ZIP内ファイル一覧を通常画面から非表示。
- 正常時の「読み込んだCSV一式の情報」を通常画面から撤去。
- 警告・エラー時のみ確認事項を表示。
- フォントを BIZ UDPGothic / Yu Gothic UI / Meiryo 系へ調整。
- 薄いブルー系＋白の配色へ調整。

#### Phase 2-4-9-8-e：工事名縦折れ改善（完了）

- 詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §34。

**記録内容：**

- 実装コミット：512f72e Refine ZIP-first report viewer and admin export flow
- 工事名が1文字ずつ縦折れする問題を改善。
- 横スクロール対応や文字縮小ではなく、工事名を上段見出しとして分離。
- 工事一覧・原価概要と月次チェック内の簡易工事一覧をカード/グリッド型に整理。
- 工事名リンクは維持。
- 数値・属性はラベル付きグリッドで表示。
- 実ブラウザで長い工事名が縦折れしないことを確認。
- CSV解析・集計ロジックは無変更。

#### Phase 2-4-9-8-f：管理コンソールCSV出力導線のZIP一本化（完了）

- 詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §35。

**記録内容：**

- 実装コミット：512f72e Refine ZIP-first report viewer and admin export flow
- 管理コンソール側のCSV出力を「CSV一式をZIPで出力」に一本化。
- 「CSV一式をZIPで出力（推奨）」から「（推奨）」を削除。
- ZIP以外の個別CSV出力導線を通常画面から非表示。
- ZIP出力失敗時の案内から「個別CSV出力をご利用ください」を削除。
- 管理コンソール「CSV一式をZIPで出力」→帳票確認「管理コンソールで出力したZIPを選択」の流れに文言を統一。
- ZIP出力処理本体・CSV生成ロジック・DB処理・Supabase処理は無変更。

**残課題（別フェーズ候補）：**

- `#preLoad` の非表示文言に「管理コンソールから出力したZIPを読み込んでください。通常はこちらを使います。」が残る。通常画面には出ないため軽微。
- 非表示領域内には個別CSV出力等の内部向け文言が一部残る。
- 月次チェック診断文・深いサブページ注記にはCSV名が一部残る。
- 月次チェック横長表の印刷最適化は別フェーズ候補。

#### Phase 2-4-9-8-c：月次チェック横長表の印刷最適化（完了）

- 詳細：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §36。

**記録内容：**

- 実装コミット：fe80fbc Optimize monthly check print layout
- 月次チェック・差異確認の印刷/PDF保存時に、簡易工事一覧が紙面で読みやすくなるよう調整。
- @media print 内に project-summary 系カード/ブロック用の印刷CSSを追加。
- 工事ごとのブロックが改ページで割れにくいよう break-inside / page-break-inside を設定。
- 工事名を上段見出しとして印刷。
- 数値・属性をラベル付き4列グリッドで印刷。
- 薄ブルー罫線を印刷時は黒罫線へ置換し、背景グラフィック印刷OFFでも成立するよう調整。
- 右端列の見切れを構造的に回避。
- 工事名の1文字縦折れを防止。
- 画面表示CSSは変更なし。
- window.print() 呼び出しは変更なし。
- CSV解析・ZIP読込・集計ロジックは変更なし。
- SQL実行・DB変更なし。

**次フェーズ候補：**

```text
Phase 2-5：運用開始準備・試運用
別系統：4c77c20 Add invoice PDF registration prototype の内容把握
```

### Phase 2-5：運用開始準備・試運用

CSV出力・ローカルCSVビューアーを実運用へ移すための準備フェーズ。

#### Phase 2-5-a：運用前棚卸し・試運用チェックリスト作成（docs整理）

- 実装コード変更なし（docs整理のみ）。
- 運用前の棚卸し・試運用チェックリストを [`docs/csv-export-operation-guide.md`](csv-export-operation-guide.md) §16 にまとめた。
- 確認の柱：管理コンソールでのCSV一式ZIP出力 → 帳票確認ビューアーでZIP選択・自動読込 → 帳票選択メニュー（対象期間表示）→ 各帳票（工事一覧・日報・請求書・重機台帳）・月次チェック・差異確認・工事詳細・印刷/PDF保存までの一連の動作確認。
- 試運用方針：まず管理者/社内担当者1名 → 実際に見る人1〜2名 → 全社展開はしない。期間は1週間程度。
- ミス・不具合時はZIP再選択・再出力・再試行を基本とし、解決しない場合はZIPファイル名・対象期間・画面名を控えて管理者へ連絡する。
- 運用開始前の未解決項目（軽微）：月次チェック診断文・深いサブページ注記の一部CSV名残存、非表示領域の内部向け文言残存、確認リスト（#multiCrossArea）の印刷可読性は必要に応じ後で調整、請求書PDF登録プロトタイプは別系統。

#### Phase 2-5-b-1：実データZIPでの初回試運用確認（完了）

- 詳細：[`docs/csv-export-operation-guide.md`](csv-export-operation-guide.md) §17。

**記録内容：**

- 実装コード変更なし（確認・docs整理のみ）。
- 実データCSV一式ZIPで初回通し確認を実施。
- 対象期間：2026年6月分。
- 件数：工事10件 / 労務明細53件 / 請求書明細0件 / 重機台帳22件。
- ZIP自動読込、帳票選択、4帳票、月次チェック、工事詳細、印刷導線を確認。
- 全体で NaN なし。
- 工事名縦折れなし。
- 通常画面に raw CSV名・ZIP名は非表示。
- project_cost_details.csv 0行は正常系メッセージ（請求書登録がない期間）として確認。
- 実データZIPはリポジトリ外で扱い、リポジトリへ追加していない。
- 機能ブロッカーなし。1週間試運用へ進める状態。

**次フェーズ候補：**

```text
Phase 2-5-b：管理者/社内担当者1名による1週間試運用
Phase 2-5-c：試運用フィードバック反映
任意改善：異常系エラーメッセージの日本語化
任意確認：請求書明細あり期間ZIPでの追加確認
別系統：4c77c20 Add invoice PDF registration prototype の内容把握
```

## 保留・改善候補

- favicon.ico 追加
- notices の掲載開始日・終了日管理
- staging / production 環境分離
- 操作マニュアル作成
- 社員向け簡易説明資料作成
- CSV出力物・ビューアー保存場所・pCloud + NAS バックアップ運用ルール策定（下記参照）

### CSV出力物・ビューアー保存場所・pCloud + NAS バックアップ運用ルール策定

- 優先度：中
- 状態：未着手
- 位置づけ：CSVビューアー・CSV出力機能が一区切りした後の運用設計フェーズ

**記録内容：**

- CSV出力物、出力パッケージ、ローカルCSVビューアーの保存場所・運用ルールを今後整理する
- クラウド保管先として pCloud の利用を検討する
- pCloud は日常の保管・閲覧・共有先として扱う
- CSV原本は編集禁止とし、加工する場合はコピーを作る運用にする
- ビューアーHTMLは GitHub 管理の正式版を原本とし、pCloud には利用者向けコピーを配置する案を検討する
- 出力物は日付フォルダまたは出力パッケージ単位で保管する
- 将来的には以下のような構成を検討する：

```text
pCloud
└ 社内業務システム
   ├ CSV出力原本
   ├ CSVビューアー
   └ 出力パッケージZIP
```

- 別バックアップ先として社内NAS導入を検討する
- NAS は pCloud の同期・保管データとは別の社内バックアップ先として扱う
- NASには以下を定期複製する案を検討する：
  - CSV出力原本
  - 出力パッケージZIP
  - ビューアー配布コピー
  - Supabase DBバックアップzip
  - photos Storageバックアップzip
- 重要データは、必要に応じてNASから外付けHDDへ月次退避する運用も検討する
- pCloud は保管・共有、NAS は社内別バックアップ、外付けHDD は最後の退避先として役割分担する
- public URL、Vercel公開領域、public Storage にはCSV原本・原価情報・従業員情報・請求書情報を置かない
- 正式運用前に、保存フォルダ構成、命名規則、保存頻度、閲覧権限、復元手順を決める

**今後決めること：**

- pCloud上の正式フォルダ構成
- NAS機種・容量・RAID構成
- pCloudからNASへの複製方法
- NASの世代管理・スナップショット方針
- 外付けHDDへの月次退避の有無
- CSV原本の編集禁止ルール
- ビューアーHTMLの正式版と配布コピーの扱い
- 出力パッケージ方式（CSV一式 + manifest.json + ZIP）の採用可否
- 誰が出力し、誰が閲覧できるか
- 削除・上書き・復元時の対応ルール

## 次にやること

1. 運用開始前チェックを完了する
2. 小規模運用を開始する
3. 実際に困った点をメモする
4. 必要に応じて admin-app.html の改善に進む
5. セキュリティ継続強化として sites / site_assignments RPC化に進む
