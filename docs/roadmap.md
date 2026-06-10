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

**実装状況：2-4-7-4（工事別月別原価ビュー）まで実装済み。2-4-7-5 以降は未着手。**

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
