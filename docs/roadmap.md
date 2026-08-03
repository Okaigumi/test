# 社内業務システム ロードマップ

## 業務OS構想（Stage S0〜S7）要約

> 詳細な確定版構想は `docs/okai-business-os-plan.md`（岡井組 業務OS構想 全文）を参照する。ここはその要約のみ。

### 最終ゴール

**日報起点の現場・原価・帳票・経営判断基盤**

現場日報を起点に、現場・人員・材料・機械・外注・原価・帳票の情報をつなぎ、現場入力から管理者確認・原価管理・帳票作成・経営判断までを一本の流れでつなぐ社内業務基盤を構築する。

### Stage S0〜S7 一覧

| Stage | 名称 | 目的 |
| ----- | ---- | ---- |
| S0 | 基盤安定・仕様整理 | 構想・進捗・セキュリティ残課題・運用ルールを整理する |
| S1 | 現場入力・基礎データ | 日報・現場・従業員・材料・機械・有休などを正確に蓄積する |
| S2 | 管理者業務の省力化 | 管理者・事務員が毎日の確認作業を短時間で終えられるようにする |
| S3 | 原価管理ダッシュボード完成 | 工事ごとの予算・累計原価・予算残・危険度を判断できるようにする |
| S4 | 帳票・請求・書類連携 | 日報・原価データを月次資料・請求確認・PDF・印刷帳票へつなげる |
| S5 | 社長用 経営コックピット | 全現場の状況・利益危険度・異常・未提出・請求漏れ候補を一覧化する |
| S6 | AI支援・自動チェック | 異常検知・月次コメント・危険理由要約・入力ミス候補検出を支援する |
| S7 | 将来拡張・外部連携 | 写真管理・電子検査・会計・NAS/OneDrive・kintone等との連携を検討する |

### 現在地（Stage別）

| Stage | 現在地 |
| ----- | ------ |
| S0：基盤安定・仕様整理 | 進行中 |
| S1：現場入力・基礎データ | かなり進んでいる |
| S2：管理者業務の省力化 | 半分以上進んでいる |
| S3：原価管理ダッシュボード完成 | 中核部分はかなり進んだ |
| S4：帳票・請求・書類連携 | これから本格化 |
| S5：社長用 経営コックピット | 構想段階。ただし設計は前倒しする |
| S6：AI支援・自動チェック | まだ早い |
| S7：将来拡張・外部連携 | まだ早い |

### 表記ルール（重要）

- 今後の構想は `Stage S0〜S7` 表記で管理する。
- 過去のセキュリティ改修の `Phase 3〜5` 表記は**履歴としてそのまま維持し、書き換えない**（本ファイル下部の「Phase」記録は改変しない）。
- 旧 `Phase 4`（RLSポリシー整理）・旧 `Phase 5`（PIN・ログイン強化）の**残課題は Stage S0 に編入**した扱いとする（既存の Phase 4 / Phase 5 セクションは履歴として残す）。

### 次の一手（PR-1〜PR-8 実行順要約）

各PRの詳細は `docs/okai-business-os-plan.md`（16〜17章）を参照。

**先に進めるもの**
1. **PR-1：構想・roadmap整理**（docsのみ・本PR）
2. **PR-2：セキュリティ棚卸し**（PIN・ログイン・試行制限・保存方式の調査のみ・DB変更なし）
3. **PR-3：PIN強化・セキュリティヘッダー**（PR-2の結果を踏まえ小さく安全に実装。保存方式変更は別PR）
4. **PR-4：RPC未返却列参照の同種バグ調査**（#70/#71 と同種の残存調査・調査のみ）
5. **PR-5：原価管理A4印刷 / PDF保存改善**（表示層中心。印刷専用ページ方式が有力）

**並行して設計だけ進めるもの**
6. **PR-6：社長用トップ画面ワイヤーフレーム**（S5前倒し設計・実装はS3/S4後）
7. **PR-7：管理者用 全社員日報カレンダー設計**
8. **PR-8：帳票・請求・`work_type` 仕様整理**（S4着手前の定義整理）

## 現在地

- 最新実装コミット：a0601ae Merge pull request #16（Phase 3 優先順位3 employee_rates / unit_rates direct write REVOKE 記録）
- 現在フェーズ：Phase 3（残り INSERT / UPDATE のRPC化）優先順位1〜3すべて完了。次の実作業は判断待ち
- 次に判断すべき作業：「運用開始前チェック → 小規模運用開始」へ進むか、「Phase 4 RLSポリシー整理 → Phase 5 PIN・ログイン強化」へ進むか
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

状態：完了（1. sites / site_assignments 完了、2. materials / machines 完了、3. employee_rates / unit_rates 完了）

### 優先順位

1. sites / site_assignments ✅ 完了（2026-06-13）
2. materials / machines ✅ 完了（2026-06-19）
3. employee_rates / unit_rates ✅ 完了（2026-06-30）

### 1. sites / site_assignments（完了）

- secure RPC 追加済み（`docs/sql/sites-site-assignments-secure-rpc.sql`、6関数・デュアルセッション認可）
- `admin-app.html` / `index.html` の現場・配属書き込みを secure RPC へ移行済み
- `anon` / `authenticated` の直接 INSERT / UPDATE を REVOKE 済み（`docs/sql/revoke-sites-site-assignments-direct-write.sql`）
- SELECT は維持（一覧・配属表示のため）
- 書き込みは secure RPC 経由に一本化済み
- REVOKE後の本番動作確認（admin-app / index）OK
- 詳細は docs/db-migrations.md の Phase 3-1 / Phase 3-3 エントリを参照

### 2. materials / machines（完了）

- secure RPC 追加済み（`docs/sql/materials-machines-secure-rpc.sql` / `docs/sql/machines-admin-secure-rpc.sql`、7関数・デュアルセッション認可）
- `index.html`（基本5RPC）/ `admin-app.html`（admin向け2RPC）の外注マスタ・機械書き込みを secure RPC へ移行済み
- `anon` / `authenticated` の直接 INSERT / UPDATE を REVOKE 済み（`docs/sql/revoke-materials-machines-direct-write.sql`）
- SELECT は維持（一覧表示のため）
- 書き込みは secure RPC 経由に一本化済み
- REVOKE後の本番動作確認OK
- 詳細は docs/db-migrations.md の Phase 3 優先順位2 / Phase 3-3 エントリを参照

### 3. employee_rates / unit_rates（完了）

- secure RPC 追加済み（`docs/sql/employee-unit-rates-secure-rpc.sql`、2関数・デュアルセッション認可）
  - `upsert_employee_rate_secure` / `upsert_unit_rate_secure`
- `admin-app.html` / `genka-app.html` の単価・日当の direct upsert を secure RPC 呼び出しへ移行済み（計4箇所）
- `anon` / `authenticated` の直接 INSERT / UPDATE を REVOKE 済み（`docs/sql/revoke-employee-unit-rates-direct-write.sql`）
- SELECT は維持（一覧・単価設定画面の表示のため）
- 書き込みは secure RPC 経由に一本化済み
- REVOKE後の本番動作確認OK（/admin 従業員日当保存・/admin 単価保存・/genka 従業員日当保存・/genka 単価保存）
- RLS / POLICY / RPC EXECUTE / `_verify_management_session` / テーブル定義は変更なし
- 詳細は docs/db-migrations.md の Phase 3 優先順位3 / Phase 3-3 エントリを参照

### 方針

- 直接 INSERT / UPDATE が残っているテーブルを順番にRPC化する
- 既存画面の動作確認後にREVOKEする
- REVOKE前後で本番確認する
- フェーズごとに docs/db-migrations.md へ記録する

## Phase 4：RLSポリシー整理

状態：**✅ 完了（2026-07-19）**（4-A〜4-F-7-c まで全工程完了。stale policy 0本・残存 policy は現役2本（`employees.employees_read_all` / `genka_admins.ga_read`）の意図的保持のみ。クローズ判定の詳細は本セクション末尾「Phase 4 クローズ（2026-07-19）」および docs/db-migrations.md「2026-07-19 Phase 4-F-7-c」参照）

### やること

- pg_policies の棚卸し
- ALL true の広いポリシー確認
- SELECT / INSERT / UPDATE / DELETE の役割整理
- RPC経由に寄せるテーブルの方針整理

### 現状確認（読み取り専用 introspection）

- `docs/sql/phase4-rls-introspection-readonly.sql`（RLS状態・pg_policies・GRANT・View・RPC・Storage の現状把握用・SELECTのみ）

### 4-A-1 subcontractors write lockdown ✅ 完了（2026-06-30）

- Phase 4（RLSポリシー整理）の最初の実施項目。`subcontractors` の orphan write 穴を解消
- `anon` / `authenticated` の直接 INSERT / UPDATE を REVOKE、緩い write policy `sub_write` / `sub_update` を削除
- SELECT 権限と `sub_read` policy は維持（フロントは subcontractors を SELECT のみ使用）
- 本番動作確認OK（index.html / admin-app.html / genka-app.html の業者一覧表示）
- SQL：`docs/sql/phase4a-1-subcontractors-write-lockdown.sql`（実行済み）
- 詳細は docs/db-migrations.md の「2026-06-30 Phase 4-A-1 subcontractors write lockdown 完了」を参照

### 4-A-2 photos upload制限 ✅ 完了（2026-06-30）

- `photos` バケットの upload を制限（過大・非画像アップロードの穴塞ぎ）
- `file_size_limit = 5242880`（5MB）／`allowed_mime_types = ['image/jpeg']` を設定
- `public read` は維持（`reports.photo_urls` の public URL 保存方式・既存写真表示を壊さない）
- `storage.objects` policy（`photos_read` / `photos_upload`）は変更なし
- 本番動作確認OK（既存写真表示・写真クリック表示・新規アップロード・保存・詳細表示）
- SQL：`docs/sql/phase4a-2-photos-upload-limits.sql`（実行済み）
- 詳細は docs/db-migrations.md の「2026-06-30 Phase 4-A-2 photos upload 制限 完了」を参照

### 4-B paid_leave 読み取りRPC化・SELECT遮断 ✅ 完了（2026-06-30）

- `paid_leave_requests` / `paid_leave_grants` の読み取りを secure RPC 経由へ統一
- read RPC 2本追加（`list_my_paid_leave_secure` / `list_paid_leave_admin_secure`）
- フロント移行（index.html `loadLeaveWorker` / `loadLeaveAdmin`、admin-app.html `pageLeave`）→ PR #21 merge済み
- `anon` / `authenticated` の直接 SELECT を REVOKE、`plr_read` / `plg_read` policy を削除
- write系 policy（`plr_write` / `plr_update` / `plg_write` / `plg_update`）は今回残存
- 本番動作確認OK（index 本人/管理・admin-app 管理、エラーなし）
- SQL：`docs/sql/phase4b-paid-leave-read-rpc.sql` / `docs/sql/phase4b-paid-leave-select-revoke.sql`（実行済み）
- 詳細は docs/db-migrations.md の「2026-06-30 Phase 4-B paid_leave 読み取りRPC化・SELECT遮断 完了」を参照

### 4-C-1 本人日報 読み取りRPC化・reports SELECT遮断 ✅ 完了（2026-07-01）

- `reports` の本人日報 direct SELECT を secure RPC 経由へ移行し、`anon` / `authenticated` の `reports` 直接 SELECT を遮断
- read RPC 1本追加（`list_my_reports_secure(text, date, integer)`・employee_sessions 検証・is_active 確認・loadHistory と copyFromYesterday を兼用）
- フロント移行（index.html `loadHistory` / `copyFromYesterday`）→ PR #23 merge済み（merge commit `17d4b7f`）、`index.html` の `from('reports')` は 0 件
- 本番反映確認：Network に `list_my_reports_secure` あり、`reports?select=...` なし
- `anon` / `authenticated` の直接 SELECT を REVOKE（一時REVOKE→GRANT復旧→本番RPC反映確認後に再REVOKE、で最終適用）
- `reports_all` policy / `report_summary` / reports write RPC 3本は未変更
- REVOKE後 本番確認①〜⑦ OK（履歴/写真詳細/編集復元/前日コピー/新規保存/修正保存/写真保存、エラーなし）
- SQL：`docs/sql/phase4c-1-my-reports-read-rpc.sql` / `docs/sql/phase4c-1-reports-select-revoke.sql`（実行済み）
- 詳細は docs/db-migrations.md の「2026-07-01 Phase 4-C-1 本人日報 読み取りRPC化・reports SELECT遮断 完了」を参照

### 4-C-2 index 管理系 report_summary 代替RPC化 ✅ 完了（2026-07-01）

- index.html の管理画面系 `report_summary` direct read を secure RPC 経由へ移行（View 封鎖前の段階として direct read を除去）
- read RPC 1本追加（`list_admin_reports_secure(text, date, date)`・二経路の管理者セッション検証／reports と employees を直接 JOIN するため View 非依存）
- フロント移行（index.html `loadAdminData` / `loadStats`）→ PR #25 merge済み（merge commit `d958fe4`）、`index.html` の `from('report_summary')` は 0 件・`list_admin_reports_secure` は 2 件
- token ガード・error ガード追加。`showSiteDetail` / `exportCSV` は無改修（`window._statsReports` 経由のため）
- 本番反映確認：Network に `list_admin_reports_secure`（status 200）あり、`report_summary?select=...` なし
- `report_summary` View / `reports` 権限 / policy は未変更（View 封鎖・SELECT REVOKE は 4-C-4 対象）
- 本番確認OK（管理タブ/集計タブ/月切替/現場ドリルダウン/CSV出力、Console 赤エラーなし・表示異常なし）
- SQL：`docs/sql/phase4c-2-admin-reports-read-rpc.sql`（実行済み）
- 詳細は docs/db-migrations.md の「2026-07-01 Phase 4-C-2 index 管理系 report_summary 代替read RPC化 完了」を参照

### 4-C-3 genka 原価系 report_summary 代替RPC化 ✅ 完了（2026-07-01）

- genka-app.html の原価集計（`loadData`）の `report_summary` direct read を secure RPC 経由へ移行（View 封鎖前の段階として direct read を除去）
- read RPC 1本追加（`list_genka_reports_secure(text, date, date, uuid)`・二経路の管理者セッション検証／`reports` 単独から原価関連9列を返すため View 非依存・employees JOIN も不要）
- 戻り列：report_date / employee_id / normal_mins / overtime_mins / site_ids / subcontractor_ids / dump_count / dump_company / guard_count
- フロント移行（genka-app.html `loadData`）→ PR #27 merge済み（merge commit `d78005d`）、`genka-app.html` の `from('report_summary')` は 0 件・`list_genka_reports_secure` は 1 件
- token ガード・error ガード追加。`site_id_input` は `siteId||null`（現場フィルタは RPC 内 `site_ids @> ARRAY[...]` で従来の `contains` と等価）。後続の原価集計処理は無改修
- 本番反映確認：Network に `list_genka_reports_secure`（status 200）あり、`report_summary` は `[]`（直接参照）で出ない
- 本番確認OK（原価画面/月切替/現場フィルタ/原価サマリー、金額・件数異常なし。Console 赤エラーは favicon.ico 404 のみで本RPCと無関係）
- `report_summary` View / `reports` 権限 / policy は未変更（View 封鎖・SELECT REVOKE は 4-C-4 対象）
- SQL：`docs/sql/phase4c-3-genka-reports-read-rpc.sql`（実行済み）
- 詳細は docs/db-migrations.md の「2026-07-01 Phase 4-C-3 genka 原価系 report_summary 代替read RPC化 完了」を参照

### 4-C-4 report_summary View 封鎖・不要 GRANT 整理 ✅ 完了（2026-07-02）

- `report_summary` View への `anon` / `authenticated` の直接アクセス権を全 REVOKE し、View 直参照経路を封鎖（4-C-1〜4-C-3 で read RPC 3本へ移行済みのため View 直参照は不要）
- 実行SQLは REVOKE 2本のみ（`REVOKE ALL PRIVILEGES ON public.report_summary FROM anon;` / `... FROM authenticated;`）→ Success. No rows returned
- View は DROP せず存続。`postgres` / `service_role` は変更せず（保守用に SELECT 等を温存）
- PUBLIC は実測で明示付与なし（relacl に PUBLIC エントリなし）のため `REVOKE ... FROM PUBLIC` は実行対象外（SQLファイル内はコメントアウトのまま）
- DB事後確認：relacl=`{postgres=arwdDxtm/postgres, service_role=arwdDxtm/postgres}`、anon/authenticated SELECT不可、postgres/service_role SELECT可、下流View依存0件、RPC 3本（list_admin/genka/my_reports_secure）は SECURITY DEFINER・report_summary 実参照なし維持
- 本番確認OK（従業員画面／管理者ログイン・管理タブ・集計タブ・月切替・現場ドリルダウン・CSV出力／原価画面・月切替・現場フィルタ・原価サマリー。Network に report_summary 直参照なし・list_genka_reports_secure あり、Console 赤エラーなし）
- SQL：`docs/sql/phase4c-4-report-summary-revoke.sql`（実行済み記録へ更新済み）
- 詳細は docs/db-migrations.md の「2026-07-02 Phase 4-C-4 report_summary View 封鎖・不要 GRANT 整理 完了」を参照

### 4-C-5 reports 残存不要権限（TRUNCATE / REFERENCES / TRIGGER）REVOKE ✅ 完了（2026-07-02）

- Phase 4-C 補整理。ライブ確認で `reports` に残っていた `anon` / `authenticated` の TRUNCATE / REFERENCES / TRIGGER を REVOKE（SELECT/INSERT/UPDATE/DELETE は既に遮断済み）。日報カレンダーMVPのブロッカーではないが先に対応。
- 実行SQLは REVOKE 1本のみ（`revoke truncate, references, trigger on table public.reports from anon, authenticated;`）→ Success. No rows returned
- DB事後確認：`reports` の anon / authenticated ともに全7種 false（TRUNCATE/REFERENCES/TRIGGER の残存除去を確認）。`report_summary`・RPC・policy・postgres/service_role は未変更
- SQL：`docs/sql/phase4c-5-reports-extra-privileges-revoke.sql`（実行済み記録へ更新済み）。詳細は docs/db-migrations.md の「2026-07-02 Phase 4-C-5 …完了」を参照

### 4-D-1a 単価系 read RPC 追加 ✅ 完了（2026-07-03）

- Phase 4-D（financial系 読み取り保護）の最初の実施項目。単価系（`unit_rates` / `employee_rates`）の管理画面 direct SELECT を secure read RPC 経由へ移行するための前段として、read RPC を2本追加
- read RPC 2本追加：`list_unit_rates_secure(text)`（戻り `id, category, name, unit_price, unit, updated_at`・全行・`ORDER BY category, name`）／`list_employee_rates_secure(text)`（戻り `id, employee_id, daily_rate, effective_from`・全行＝多世代履歴・`ORDER BY employee_id, effective_from DESC`）
- 認可は既存ヘルパー `_verify_management_session(text)` を再利用（同一対象テーブルの write RPC `upsert_unit_rate_secure` / `upsert_employee_rate_secure` と同型）。両関数とも `SECURITY DEFINER` / `search_path=public, extensions`／REVOKE PUBLIC → GRANT anon,authenticated,service_role
- 事前確認A〜D・事後確認F〜H すべて期待どおり。戻り型は実カラム型と一致確認済み（`unit_price=int4` / `updated_at=timestamptz` / `daily_rate=int4` / `effective_from=date` 等）
- **★SELECT REVOKE は未実施★・新旧併存**（`unit_rates` / `employee_rates` の anon/authenticated 直接 SELECT は残存）。フロント移行（4-D-1b）→本番確認 の後に 4-D-1c で REVOKE
- フロント（`admin-app.html` / `genka-app.html`）は未変更。既存 write RPC・helper・RLS・policy・他テーブルは不変（additive-only）
- SQL：`docs/sql/phase4d-1a-rates-read-rpc.sql`（**実行済み（2026-07-03）**）。詳細は docs/db-migrations.md「2026-07-03 Phase 4-D-1a 単価系 read RPC 追加（実行済み）」参照
- 次工程：**4-D-1b** フロント移行（genka startApp・admin startApp/pageRates の計5箇所を read RPC へ置換 → PR → 本番反映確認）／**4-D-1c** `unit_rates` / `employee_rates` の direct SELECT REVOKE

### 4-D-1b 単価系フロント移行 ✅ 完了（2026-07-03）

- `admin-app.html` / `genka-app.html` に残っていた `unit_rates` / `employee_rates` の direct SELECT 5箇所を、4-D-1a の read RPC（`list_unit_rates_secure` / `list_employee_rates_secure`）経由へ置換
  - genka `startApp`（employee_rates / unit_rates）、admin `startApp`（unit_rates）、admin `pageRates`（employee_rates / unit_rates）
- token ガード追加（startApp＝token 欠落時は該当 sessionStorage 削除→reload／admin `pageRates`＝alert して return）。RPC error は `console.error` のみ、既存 `(data||[])` フォールバック維持。集計・保存・編集描画ロジックは無改変
- データ形状は現行互換（`unit_rates` の map 化・`employee_rates` の effective_from 降順→最新採用は不変）
- `npm run test:smoke` 4 passed。PR #42 merge済み（merge commit `8a227d6`）。変更は `admin-app.html` / `genka-app.html` のみ
- 本番 Network 確認 OK：genka / admin とも `list_unit_rates_secure` / `list_employee_rates_secure` が 200、`unit_rates?select` / `employee_rates?select` は出ない、表示OK・Console 赤エラーなし
- DB変更なし（read RPC は 4-D-1a で追加済みを利用）

### 4-D-1c 単価系 SELECT REVOKE ✅ 完了（2026-07-03）

- 本番で read RPC 経由を確認済みのため、`unit_rates` / `employee_rates` の `anon` / `authenticated` 直接 SELECT を REVOKE（読み取りを read RPC 経由に一本化・新旧併存の解消）
- 実行SQL：`REVOKE SELECT ON TABLE public.unit_rates FROM anon, authenticated;` / `REVOKE SELECT ON TABLE public.employee_rates FROM anon, authenticated;`（各 Success. No rows returned）
- 事前確認A〜E・事後確認F〜J すべて合格。**PUBLIC に SELECT なし → PUBLIC 向け REVOKE は未実行**。read RPC / write RPC の EXECUTE 維持、RLS / policy は不変（policy 整理は別工程候補）
- 本番 Network 確認 OK：両アプリとも read RPC 200・direct SELECT 消失・表示OK・Console 赤エラーなし
- SQL：`docs/sql/phase4d-1c-rates-select-revoke.sql`（**実行済み（2026-07-03）**）。詳細は docs/db-migrations.md「2026-07-03 Phase 4-D-1c 単価系 SELECT REVOKE（実行済み）」参照

### ✅ Phase 4-D-1 単価系 読み取り保護 完了（2026-07-03）

- 4-D-1a（read RPC 追加）→ 4-D-1b（フロント移行）→ 4-D-1c（SELECT REVOKE）まで完了。`unit_rates` / `employee_rates` の読み取りは secure read RPC（管理セッション検証・SECURITY DEFINER）経由に一本化され、anon/authenticated の直接 SELECT は遮断済み。
- 後続の **4-D-2 予算（`site_budgets`）／4-D-3 請求書（`invoices`）** の読み取り保護も、同じ read RPC 追加→フロント移行→SELECT REVOKE の3段で完了済み。

### 4-D-2a site_budgets read RPC 追加 ✅ 完了（2026-07-03）

- Phase 4-D-2（予算 `site_budgets` 読み取り保護）の前段。`admin-app.html` / `genka-app.html` に残る `site_budgets` の direct SELECT（計5箇所）を secure read RPC 経由へ移行するため、read RPC を2本追加
- read RPC 2本追加：`list_site_budgets_secure(text, boolean, uuid, integer, boolean)`（戻り `id, site_id, year, month, budget, memo, is_active, updated_at`・`is_active_input`/`site_id_input`/`year_input`/`annual_only_input` で絞り込み・`ORDER BY year DESC, updated_at DESC`）／`get_site_budget_secure(text, uuid)`（同戻り列・`WHERE id = id_input`・該当なしは0行）
- `annual_only_input`（boolean DEFAULT false）：`false`/`NULL`＝month 条件なし、`true`＝`month IS NULL`（年間予算のみ）。genka の「現場×年度」「年度集計」の年間予算絞り込みを DB 側で再現するために追加。条件式 `(COALESCE(annual_only_input, false) = false OR sb.month IS NULL)`
- 認可は既存ヘルパー `_verify_management_session(text)` を再利用（Phase 4-D-1 read RPC と同型）。両関数とも `SECURITY DEFINER` / `search_path=public, extensions`／REVOKE PUBLIC → GRANT anon,authenticated,service_role
- 事前確認A〜D・事後確認F〜H すべて期待どおり。戻り型は実カラム型と一致確認済み（`year=int4` / `month=int4` / `budget=int4` / `updated_at=timestamptz` / `id・site_id=uuid` / `is_active=bool` / `memo=text`）
- **★SELECT REVOKE は未実施★・新旧併存**（`site_budgets` の anon/authenticated 直接 SELECT は残存）。フロント移行（4-D-2b）→本番確認 の後に 4-D-2c で REVOKE
- フロント（`admin-app.html` / `genka-app.html`）は未変更。既存 write RPC（`upsert/update/deactivate/restore_site_budget_secure`）・helper・RLS・policy・他テーブルは不変（additive-only）
- SQL：`docs/sql/phase4d-2a-site-budgets-read-rpc.sql`（**実行済み（2026-07-03）**・PR #44 merge済み `73668b7`）。詳細は docs/db-migrations.md「2026-07-03 Phase 4-D-2a site_budgets read RPC 追加（★実行済み★）」参照
- 次工程：**4-D-2b** フロント移行（admin pageBudgets①②/openBudgetModal③・genka openBudgetModal④/原価サマリ集計⑤ の計5箇所を read RPC へ置換 → PR → 本番反映確認）／**4-D-2c** `site_budgets` の direct SELECT REVOKE

### 4-D-2b site_budgets フロント移行 ✅ 完了（2026-07-03）

- `admin-app.html` / `genka-app.html` に残っていた `site_budgets` の direct SELECT 5箇所を、4-D-2a の read RPC 経由へ置換
  - admin：`pageBudgets` active① / inactive② → `list_site_budgets_secure`、`openBudgetModal`③ → `get_site_budget_secure`（`.single()` 廃止・`data?.[0]||null`）
  - genka：`openBudgetModal`④（現場×当年・年間予算） / `loadData` 原価サマリ集計⑤ → `list_site_budgets_secure`（`annual_only_input: true`）
- `list_site_budgets_secure` の引数は省略せず全明示（`session_token_input`/`is_active_input`/`site_id_input`/`year_input`/`annual_only_input`）。admin 一覧は `annual_only_input: false`、genka 年間予算は `true`
- token ガード（`currentUser?.session_token` / `gCurrentUser?.session_token`）・error console 追加。`from('site_budgets')` は 0 件
- PR #46 merge済み（merge commit `600ade3`）。変更は `admin-app.html` / `genka-app.html` の2ファイルのみ。`npm run test:smoke` = 4 passed
- DB変更なし（read RPC は 4-D-2a で追加済みを利用）
- 本番 Network 確認 OK：admin/genka とも read RPC が呼ばれ、`site_budgets?select` は出ない・表示OK・Console 赤エラーなし・401/403 なし

### 4-D-2c site_budgets SELECT REVOKE ✅ 完了（2026-07-04）

- 4-D-2a（read RPC 追加）・4-D-2b（フロント移行・本番確認 OK）を経て、`site_budgets` の `anon` / `authenticated` 直接 SELECT を REVOKE。読み取りを secure read RPC 経由に一本化
- 実行SQL：`REVOKE SELECT ON TABLE public.site_budgets FROM anon, authenticated;`（Success. No rows returned）
- 事前確認A〜E・事後確認F〜J すべて合格。事前A で **PUBLIC に SELECT なし → PUBLIC REVOKE 未実行**。read RPC 2本 / write RPC 4本 の EXECUTE 維持・RLS/policy 不変・ロールバック GRANT 未実行
- 本番 Network 確認 OK（REVOKE 後）：admin/genka とも read RPC が 200・`site_budgets?select` は出ない・表示OK・赤エラーなし・401/403 なし（genka 予算モーダルの表示位置が低い件は別 UI 改善候補として切り離し）
- SQL：`docs/sql/phase4d-2c-site-budgets-select-revoke.sql`（**実行済み（2026-07-04）**・PR #47 merge済み `a4dba9f`）。詳細は docs/db-migrations.md「2026-07-04 Phase 4-D-2c site_budgets SELECT REVOKE（★実行済み★）」参照

### ✅ Phase 4-D-2 予算（site_budgets）読み取り保護 完了（2026-07-04）

- 4-D-2a（read RPC 追加）→ 4-D-2b（フロント移行）→ 4-D-2c（SELECT REVOKE）まで完了。`site_budgets` の読み取りは secure read RPC（管理セッション検証・SECURITY DEFINER）経由に一本化され、anon/authenticated の直接 SELECT は遮断済み。
- 後続の **4-D-3 請求書（`invoices`）** の読み取り保護も、同じ read RPC 追加→フロント移行→SELECT REVOKE の3段で完了済み。

### 4-D-3a invoices read RPC 追加 ✅ 完了（2026-07-04）

- Phase 4-D-3（請求書 `invoices` 読み取り保護）の前段。`admin-app.html` / `genka-app.html` に残る `invoices` の direct SELECT（計6箇所）を secure read RPC 経由へ移行するため、read RPC を2本追加
- 追加関数：`list_invoices_secure(text, text[], text, date, date, uuid, integer)`（`statuses_input` 包含 / `exclude_status_input` 除外 / `date_from_input`・`date_to_input` 期間 / `site_id_input` / `limit_input`（NULL=全件）で絞り込み・`ORDER BY invoice_date DESC`）／`get_invoice_secure(text, uuid)`（id 指定1件・該当なし0行）
- 認可は既存ヘルパー `_verify_management_session(text)` を再利用（Phase 4-D-1 / 4-D-2 read RPC と同型）。両関数とも `SECURITY DEFINER` / `search_path=public, extensions`／REVOKE PUBLIC → GRANT anon,authenticated,service_role
- 戻り列は実使用10列 `id, invoice_date, site_id, vendor_name, category, amount, tax_included, description, memo, status`。`status`/`category` は enum 化時の型不一致回避のため比較・戻り値とも `::text` 正規化（実型は両方 `text`）。既存 invoice write RPC（admin_sessions 単経路）は不変
- **★SELECT REVOKE は未実施★・新旧併存**（`invoices` の anon/authenticated 直接 SELECT は残存）。フロント移行（4-D-3b）→本番確認 の後に 4-D-3c で REVOKE
- SQL：`docs/sql/phase4d-3a-invoices-read-rpc.sql`（**実行済み（2026-07-04）**・PR #49 merge済み `9ecd7d7`）。詳細は docs/db-migrations.md「2026-07-04 Phase 4-D-3a invoices read RPC 追加（★実行済み★）」参照
- 次工程：**4-D-3b** フロント移行（admin pageInvoices active/rejected・openInvoiceModal・genka loadInvoices・editInvoice・loadData 集計 の計6箇所を read RPC へ置換 → PR → 本番反映確認）／**4-D-3c** `invoices` の direct SELECT REVOKE

### 4-D-3b invoices フロント移行 ✅ 完了（2026-07-04）

- admin-app.html / genka-app.html に残っていた `invoices` の direct SELECT 6箇所を、4-D-3a の read RPC 経由へ置換
- admin：pageInvoices（通常一覧＝`exclude_status_input:'rejected'` / 取消済み一覧＝`statuses_input:['rejected']`・ともに `limit_input:200`）・openInvoiceModal（`get_invoice_secure`）
- genka：loadInvoices（月次＝`statuses_input:['confirmed','posted']`・期間指定）・editInvoice（`get_invoice_secure`）・loadData 集計（`statuses_input:['confirmed','posted']`・期間・`site_id_input:siteId||null`）
- `.single()` 廃止。詳細取得は `data?.[0] || null` 系に統一。token/error ガード追加。RPC 引数はすべて明示
- PR #51 merge済み（merge commit `4603726`）。DB変更なし（read RPC は 4-D-3a で追加済みを利用）
- 本番 Network 確認 OK：admin（通常/取消済み一覧・編集モーダル）・genka（月次リスト・編集モーダル・原価サマリ集計）とも read RPC が 200・`invoices?select=` なし・表示OK・赤エラーなし・401/403/400 なし

### 4-D-3c invoices SELECT REVOKE ✅ 完了（2026-07-04）

- 4-D-3a（read RPC 追加）・4-D-3b（フロント移行・本番確認 OK）を経て、`invoices` の anon / authenticated 直接 SELECT を REVOKE。読み取りを secure read RPC 経由に一本化
- 実行SQL：`REVOKE SELECT ON TABLE public.invoices FROM anon, authenticated;`
- 事前確認A〜E・事後確認F〜J すべて合格
- PUBLIC SELECT は検出なし。PUBLIC REVOKE 未実行。rollback GRANT 未実行
- read RPC 2本 EXECUTE 維持 / write RPC 4本不変 / RLS・policy 不変
- `REFERENCES` / `TRIGGER` / `TRUNCATE` が anon/authenticated に残存しているが、`invoices` 固有ではなく financial系4テーブル（`invoices` / `employee_rates` / `unit_rates` / `site_budgets`）共通の既存横断パターンのため、今回の SELECT REVOKE とは分離し、後日の権限棚卸し候補として扱う
- 本番 Network 確認 OK（REVOKE 後）：admin/genka とも read RPC が 200・`invoices?select=` なし・表示OK・赤エラーなし・401/403/400 なし
- admin 通常一覧の初回400は管理セッション期限切れが原因で、再ログイン後に解消。REVOKE起因ではない
- SQL：`docs/sql/phase4d-3c-invoices-select-revoke.sql`（**実行済み（2026-07-04）**・PR #52 merge済み `66ecee5`）。詳細は docs/db-migrations.md「2026-07-04 Phase 4-D-3c invoices SELECT REVOKE（★実行済み★）」参照

### ✅ Phase 4-D-3 請求書（invoices）読み取り保護 完了（2026-07-04）

- 4-D-3a（read RPC 追加）→ 4-D-3b（フロント移行）→ 4-D-3c（SELECT REVOKE）まで完了
- `invoices` の読み取りは secure read RPC（管理セッション検証・SECURITY DEFINER）経由に一本化され、anon/authenticated の直接 SELECT は遮断済み
- Phase 4-D の financial系4テーブル（`unit_rates` / `employee_rates` / `site_budgets` / `invoices`）の読み取り保護はすべて完了
- 残課題だった financial系4テーブル共通の `TRUNCATE` / `REFERENCES` / `TRIGGER`（anon/authenticated）権限の棚卸しは **4-D-4 で解消済み**（下記参照）

### 4-D-4 financial系4テーブル 残存不要権限（TRUNCATE / REFERENCES / TRIGGER）REVOKE ✅ 完了（2026-07-04）

- 4-D-1c / 4-D-2c / 4-D-3c で「後日の権限棚卸し候補」として分離していた、financial系4テーブル（`unit_rates` / `employee_rates` / `site_budgets` / `invoices`）共通の `anon` / `authenticated` の TRUNCATE / REFERENCES / TRIGGER を横断的に REVOKE。SELECT/INSERT/UPDATE/DELETE は既に遮断済みのため対象外。
- Stage B 調査（ユーザー手動）：4テーブルとも anon/authenticated は SELECT/INSERT/UPDATE/DELETE=false・TRUNCATE/REFERENCES/TRIGGER=true、public は全 false。RLS 有効・ユーザー定義トリガ0件・financial系を参照先にする FK なし（REFERENCES REVOKE は既存 FK に無影響）・secure RPC は全て SECURITY DEFINER。`site_budgets.anon_can_update_site_budgets` policy は残存だが anon direct UPDATE grant=false のため止めず、policy 棚卸しは別工程候補。
- 実行SQL（1テーブル1文×4本・順番 employee_rates→invoices→site_budgets→unit_rates）：`REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.<table> FROM anon, authenticated;`。実行結果 Success. No rows returned。
- DB事後確認：G（anon/authenticated）・G-2（public）とも対象4テーブルの全権限 false。RPC / RLS / policy / postgres / service_role・フロントは未変更。rollback GRANT 未実行。
- 本番画面確認 OK：admin/genka とも単価・実行予算・請求書・原価サマリが secure RPC（200）で従来どおり表示。`unit_rates?select=` / `employee_rates?select=` / `site_budgets?select=` / `invoices?select=` の direct access なし・赤エラーなし・400/401/403 なし。
- SQL：`docs/sql/phase4d-4-financial-extra-privileges-revoke.sql`（**実行済み（2026-07-04）**・STATUS を EXECUTED に更新済み）。詳細は docs/db-migrations.md「2026-07-04 Phase 4-D-4 …完了（★実行済み★）」を参照。

### 日報カレンダーMVP（本人月別）✅ 完了（2026-07-02）

- 従業員本人が自分の日報提出状況を月別カレンダーで確認できるMVPを `index.html`（履歴タブ）に追加。当月表示・前月/次月移動・日付セルに日報有無/有給/現場名（複数は「◯◯他N」）表示・日付クリックで既存詳細モーダル表示 or 日報入力タブへ誘導
- PR #34 merge済み（merge commit `c76a76f`）。変更ファイルは `index.html` のみ
- 既存の secure RPC を再利用：本人日報＝`list_my_reports_secure`（before_date+limit 方式）、承認済み有給＝`list_my_paid_leave_secure`
- `reports` / `report_summary` / `paid_leave` の direct read は 0 件（RPC経由に統一・Phase 4-C の保護を維持）
- DB変更・新規RPC作成なし。DB非依存でクライアント側描画
- 将来課題：管理者向け全社員カレンダー、`list_my_reports_secure` の from-to 範囲版RPC（過去100件超の古い月の取りこぼし対策）、同日複数日報のセル全件表示（現状は先頭1件＋「+N」）

### 有休表示フェーズ ✅ 完了（PR-A：PR #38 merged / PR-B：PR #39 merged・いずれも 2026-07-02）

- CSV viewer の社内確認用 月次稼働・日報詳細に「有休表示（個人カレンダー）」と「残有給表示（個人選択時ヘッダ）」を追加する機能フェーズ。2PR構成で進行。
- **PR-A（DB＋出力・✅ PR #38 merged・2026-07-02）**：有休CSV出力 secure RPC 2本追加＋`admin-app.html` ZIP拡張＋docs記録
  - 追加RPC：`export_paid_leave_details_secure(text, date, date)`（承認済み有休明細・期間あり・有休1件/行）／`export_paid_leave_balances_secure(text)`（残有給スナップショット・期間なし・従業員1人/行）
  - 両RPCとも二経路検証（`list_paid_leave_admin_secure` 同型）。既存 export 4本の admin_sessions 単経路とは検証方式が異なる点を明記。SECURITY DEFINER / search_path 固定 / REVOKE PUBLIC → GRANT anon,authenticated / helper `csv_export_fiscal_year` 再利用
  - `admin-app.html`：`CSV_COLUMNS` に paid_leave_details / paid_leave_balances 追加、`exportCsvZip` specs に2本追加（details=period:true / balances=period:false）。ZIP は 6CSV 構成（manifest 1.0 後方互換）
  - SQL：`docs/sql/phase4d-paid-leave-export-rpc.sql`（**実行済み（2026-07-02）**）。詳細は docs/db-migrations.md「2026-07-02 Phase 4-D 有休CSV出力 secure RPC 追加（実行済み）」参照
  - 現況：**DB実行済み**（2026-07-02・Supabase SQL Editor。事後確認 D/E/E-2/F すべて期待どおり）＋`admin-app.html` ZIP拡張済み＋docs記録・静的確認まで完了。**PR #38 として merge 済み（2026-07-02・content commit `575bc5d`）**
- **PR-B（viewer表示・DB非依存・✅ PR #39 merged・2026-07-02）**：`local-viewers/csv-viewer.html` に `paid_leave_details` / `paid_leave_balances` 種別追加、社内確認用 個人カレンダーに「有休／有休（午前）／有休（午後）」表示、個人選択時ヘッダに「残有給：○日」表示。有休表示は ZIP 経由のみ。会計提出用・全体カレンダーには含めない。

### 日報無効化機能 ⏸ 保留（仕様再検討のため。DB下地は反映済み・本番UIは撤回）

- **現況：仕様が固まりきっていないため後日対応。本番運用ではまだ使用しない。**
  DB 下地（PR-A/B）は反映済みで**残す**が、本番画面に無効化操作が出ないよう **PR-C の管理者UI（index.html）は撤回**した
  （PR #66 の追加分を revert）。DB / SQL / RPC / RLS の変更・ロールバックはしていない。
  後日、仕様確定後に改めて「本人取消」「管理者無効化」の設計を行い、UI を再実装する。
- 誤作成・不要になった日報を物理削除せず「無効化（soft-void）」で通常の履歴・集計・CSVから
  除外する構想。無効化は管理者のみ・理由必須・監査用にデータは残す。従業員画面には操作を出さない。
  復元は MVP 非対象（is_voided フラグ方式で将来対応可）。UIは index.html の管理者エリア（再実装時）。
- **PR-A（DBカラム追加・additive）**：reports に `is_voided`/`voided_at`/`voided_by`/`voided_by_role`/`void_reason` を追加＋CHECK 2本。
  SQL：`docs/sql/report-void-columns.sql`（**実行済み（2026-07-06）**・ユーザーが Supabase SQL Editor で実行。active_rows=151 / voided_rows=0 / total_rows=151、既存151件はすべて is_voided=false）。本PR単独では履歴・集計・CSVは不変。
- **PR-B（RPC・read/export 除外）**：SQL `docs/sql/report-void-rpc.sql`（**実行済み（2026-07-06）**・ユーザーが Supabase SQL Editor で実行。新設2関数とも SECURITY DEFINER・PUBLIC EXECUTE なし・reports 直接UPDATE なし・read/export 5本に is_voided=false 除外反映）。
  `admin_void_report_secure(text, uuid, text)`（管理者二経路・理由必須・voided_by/by_role サーバ確定・無効化結果を RETURNS TABLE で返す）を追加。
  `list_my_reports_secure` / `list_admin_reports_secure`（**シグネチャ維持**）/ `list_genka_reports_secure` /
  `export_projects_summary_secure` / `export_attendance_details_secure` の各 WHERE に `is_voided=false` 除外を1行追加（本体のみ再定義・権限不変）。
  無効化済み確認用は別RPC `list_admin_reports_with_voided_secure(..., include_voided_input DEFAULT false)`（監査列付き）を新設（PR-C用）。DB実行はユーザー。
- **PR-C（管理者UI）**：index.html 管理者エリアに個別日報一覧＋無効化ボタン（理由入力必須モーダル）、
  「無効化済みも表示」トグル（理由/実行者/日時表示）。**一度 PR #66 で追加・merge したが、仕様再検討のため撤回（revert）**。
  DB下地（PR-A/B の `admin_void_report_secure` / `list_admin_reports_with_voided_secure`・read/export の is_voided=false 除外）は
  残っているため、仕様確定後は UI 再追加のみで復帰できる。**現状 UI は本番に出ない。**

### 次候補（Phase 4-C 完了後の整理・他テーブル読み取り整理）

- Phase 4-C 系（4-C-1〜4-C-4）完了後の整理（`reports_all` policy の整理判断・不要になった View/権限の棚卸しなど）
- Playwright による読み取り専用スモークテスト導入検討（本番の主要画面表示・Network に direct read が出ないことの自動確認。読み取りのみ・DB非変更）
- invoices / site_budgets / employee_rates / unit_rates の管理セッション限定読み取り化（Phase 4-D）
  - 4-D-1 単価系（`unit_rates` / `employee_rates`）：**✅ 完了（2026-07-03）**（4-D-1a read RPC 追加 → 4-D-1b フロント移行 → 4-D-1c SELECT REVOKE すべて実行済み・本番確認OK）
  - 4-D-2 予算（`site_budgets`）：**✅ 完了（2026-07-04）**（4-D-2a read RPC 追加 → 4-D-2b フロント移行 → 4-D-2c SELECT REVOKE すべて実行済み・本番確認OK）
  - 4-D-3 請求書（`invoices`）：✅ 完了（2026-07-04。4-D-3a read RPC 追加・4-D-3b フロント移行・4-D-3c SELECT REVOKE・REVOKE後本番確認まで完了）
- paid_leave の write系 policy 整理（別工程候補）
- 管理者向け日報写真確認導線（管理者が従業員の日報写真を確認できる画面/導線。
  reports / report_summary の読み取り整理と合わせて検討。管理者セッション検証を前提とし、
  photos の public維持／将来の private化・署名URL化方針と整合させる）
- 将来：photos の private化・署名URL化（保存済み public URL の移行設計が必要・別フェーズ）

### 別タスク候補（Phase 4-C-4 とは別）

- 集計タブ（index.html 管理コンソール）の CSV 出力の廃止・管理コンソール側への集約
  - 現状：集計タブ側の CSV 出力は 4-C-4 時点で動作OK。ただし今後は不要にしたい
  - 方針：CSV 出力導線は管理コンソール側のみに集約する
  - 位置づけ：Phase 4-C-4 の範囲外。読み取り整理とは独立した UI 整理タスクとして扱う

### 4-F-7 stale policy cleanup（pg_policies 実測にもとづく整理）

- 4-F-7-a rates（`unit_rates` / `employee_rates` の stale policy 6本 DROP）：**✅ 完了（2026-07-19）**
  （準備 PR #145・実行記録 PR #146。public schema policy 23 → 17。詳細は docs/db-migrations.md「2026-07-19 Phase 4-F-7-a」）
- 4-F-7-b 業務系（`invoices` / `site_budgets` / `paid_leave_requests` / `paid_leave_grants` / `reports` の stale policy 12本 DROP）：**✅ 完了（2026-07-19）**
  - 準備 PR #147（merge `7bf9170`）→ DB 実行 2026-07-19（GUARD＋BODY 1回のみ・Success. No rows returned・再実行禁止）
  - PRE-CHECK C-1〜C-8 / POST-CHECK P-1〜P-5 全合格。**public schema policy 17 → 5**（想定外0）
  - 本番 smoke 全合格（3画面＋同値保存 write smoke。`paid_leave_requests` の新規申請・承認 write は実データ変更を伴うため未実施＝関数属性・ACL・EXECUTE 証拠で補完）
  - `anon_can_update_site_budgets`（4-D-4 以来の policy-review 宿題）・`reports_all`・paid_leave write系 policy はここで解消
  - 詳細は docs/db-migrations.md「2026-07-19 Phase 4-F-7-b」
- 4-F-7-c identity 系（genka_admins の stale write policy 3本 DROP＋現役 read policy 2本の意図的保持）：**✅ 完了（2026-07-19）**
  - 4-F-7-c-1 read-only 実測（I-1〜I-6）で write 系3本（`ga_write` / `ga_update` / `anon_can_update_genka_admins`）の stale を確定（想定外 role なし・write 実効権限 false・write 列 grant 0）
  - 準備 PR #149（merge `823fdd1`）→ DB 実行 2026-07-19（GUARD＋BODY 1回のみ・Success. No rows returned・再実行禁止）
  - PRE-CHECK C-1〜C-6 / POST-CHECK P-1〜P-6 全合格。**public schema policy 5 → 2**（想定外0）
  - 本番 smoke 全合格（3画面のログイン前名前一覧・PIN login/logout/再ログイン・PIN 非露出・管理者同値保存。初回の HTTP 400 は期限切れ session が原因で policy 障害ではなく、再ログイン後成功。新規管理者作成は実データ変更のため未実施＝関数属性・ACL・EXECUTE 証拠で補完）
  - **意図的保持（未整理残ではない）**：`employees.employees_read_all` / `genka_admins.ga_read` の2本は、ログイン前名前一覧の direct SELECT（table-level SELECT=false＋限定列 SELECT grant：employees 7列×2role=14 / genka_admins 3列×2role=6・pin/created_at 非公開）を支える**現役 policy として保持**
  - 詳細は docs/db-migrations.md「2026-07-19 Phase 4-F-7-c」

### Phase 4 クローズ（2026-07-19）

- 「やること」（pg_policies 棚卸し / ALL true の広いポリシー確認 / S・I・U・D の役割整理 / RPC 経由に寄せる方針整理）はすべて完了。stale policy は 0本・残存2本は現役として意図的保持を記録済み。
- **Phase 4（RLSポリシー整理）は完了**（4-F-7-c の完了と本記録をもってクローズ。db-migrations.md「2026-07-19 Phase 4-F-7-c」の「最終状態と Phase 4 クローズ判定」参照）。
- **Phase 5 との境界**：ログイン前 direct SELECT の RPC 化（名前一覧 RPC 化＋列 grant 撤廃）・PIN ハッシュ化・ログイン失敗回数制限は Phase 5「PIN・ログイン強化」の候補として分離し、Phase 4 には含めない。

## Phase 5：PIN・ログイン強化

状態：着手（2026-07-19・5-C-1a 実行済み）

### やること

- PINハッシュ化
- ログイン失敗回数制限
- 一定回数失敗時の一時ロック
- session_token の期限管理強化
- 期限切れセッション削除

### 実施方針（2026-07-19 確定・案D）

- 実施順：**5-A 現状調査 → 5-C 失敗回数制限・一時的な試行抑制 → Phase 6 管理者日報カレンダー → 5-D/5-E PIN ハッシュ化（計画的）→ 5-B 期限切れ session 削除（後段）**。
- **5-F/5-G（ログイン前名前一覧の RPC 化・`employees_read_all`/`ga_read` 撤廃・policy 完全0化）は凍結**（現役 policy・pin/created_at 非公開・table-level SELECT 無効で実質リスク小に対し login 破壊リスクが大きいため）。
- IP 単位 rate limit（PostgREST db-pre-request）は独立後続工程。Phase 5-C は総当り・DoS の**完全防御ではなく軽減**と位置づける。

### 5-C ログイン失敗抑制

- **5-C-1a login throttle テーブル作成：✅ 完了（2026-07-19・実行済み）**
  - 非公開スキーマ `private` に `private.login_throttle`（realm/identifier/fail_count/cooldown_until/last_failed_at/updated_at・PK(realm,identifier)）を新規作成。Data API 向け全ロールから到達不能（USAGE/table 権限を明示 REVOKE・RLS 有効・policy なし・FORCE なし）。owner=postgres。
  - 準備 PR #151（merge `ed98b0c`）→ DB 実行 2026-07-19（GUARD＋BODY 1回のみ・Success. No rows returned・再実行禁止）。PRE C-1〜C-4 / POST P-1〜P-8 全合格。Phase 4 の policy 2本・login RPC 2本は不変。
  - 詳細は docs/db-migrations.md「2026-07-19 Phase 5-C-1a」。
- **5-C-1b login RPC への cooldown 組込：✅ 完了（2026-07-20・実行済み）**
  - `create_employee_session` / `create_admin_session` を **CREATE OR REPLACE**（DROP しない・同 signature/同 RETURNS/同 EXECUTE ACL・クールダウン中も 0行返す互換方式）で account-level cooldown を組込。
  - 準備 PR #153（merge `f15c9f6`）→ GUARD 構文 hotfix PR #154（merge `a0c6854`・`END`→`END;`）。
  - 実行経緯：初回 BODY 実行は GUARD 終端 `END;` 欠落の syntax error → transaction abort（DB 変更なし）。hotfix merge 後に修正版 GUARD＋BODY を1回実行して成功（Success. No rows returned）・成功適用後の再実行なし。
  - PRE（C-1 再確認）/ POST（P-1〜P-6）全合格。本番 3画面 smoke 合格（employee `/`・admin `/admin` の cooldown 動作・genka `/genka` 回帰・終了後 throttle 行0）。
  - 仕様：threshold=5・cooldown=固定60秒・decay=15分・成功時 throttle 行 DELETE・cooldown 中 0行・実在 ID のみ記録。throttle 時刻は `clock_timestamp()`、session 期限は互換維持で `now()`。
  - retry_after 表示（`*_session_v2` additive）・IP 単位 rate limit は独立後続工程。
  - 詳細は docs/db-migrations.md「2026-07-20 Phase 5-C-1b」。

### 5-D employees PIN ハッシュ化（Phase 5-D・5-E 分離方針）

- **5-D 対象：employees のみ**（`genka_admins` は Phase 5-E で対応）
- **5-E 対象：genka_admins**（5-D 完了後に独立工程として実施）
- Phase 5-D と 5-E は設計を共通化しつつ、DB 変更・RPC 更新・smoke を分離して安全に進める。

#### 5-D-1 schema 追加 + login RPC hash 優先 dual-read 化

**状態：✅ 完了（2026-07-23・実行済み）**

- `employees.pin_hash text NULL` 追加（nullable・default なし・既存 11 行は NULL のまま）
- `create_employee_session(uuid,text)` を `CREATE OR REPLACE` で hash 優先 dual-read に更新
  - `pin_hash IS NOT NULL` → `extensions.crypt` による bcrypt 照合のみ（平文 fallback なし）
  - `pin_hash IS NULL`     → 既存の平文 `pin` 照合（移行前互換）
- 対象は `employees` のみ。`genka_admins` / `create_admin_session` は変更しない。
- frontend 変更なし（PIN は plain text で RPC 渡し、照合はすべて DB 側）
- RLS / policy / GRANT / REVOKE 変更なし
- backfill 未実施（5-D-3 で対応）。hash 生成・bcrypt cost は backfill 時に確定。
- plaintext `employees.pin` は引き続き現役（dual-read で互換維持中）
- 準備 PR #164 + fix PR #165・#166・#167（`docs/sql/phase5d-1-employee-pin-hash-dual-read.sql`）
- DB 実行：2026-07-23（Supabase SQL Editor・手動・1回のみ・Success. No rows returned）
- PRE-CHECK 全合格・GUARD 8チェック合格・内部 POST-CHECK（PC-1〜PC-thr-3）全合格
- POST-COMMIT 全合格・本番 smoke 全合格（従業員ログイン / cooldown / 管理者・原価 回帰）
- 新 function fingerprint：length=3798 / md5=`006550c3455e34aa9d1d61bd60bb85ad`
- **Phase 5-D は未完了**（5-D-2 以降が残る）
- 詳細は docs/db-migrations.md「2026-07-23 Phase 5-D-1」参照

#### 5-D-2 employee create / update RPC dual-write 化

**状態：✅ 完了（2026-07-23・実行済み）**

- `create_employee_secure` / `update_employee_secure` を `CREATE OR REPLACE` で dual-write に更新
- bcrypt cost 12・`extensions.crypt(pin_input, extensions.gen_salt('bf', 12))`
- PIN バリデーション：`'^[0-9]{4}$'`（半角数字4桁に厳格化）
- 新規作成：単一 INSERT で `pin` と `pin_hash` を原子的に保存
- PIN 変更：単一 UPDATE で `pin` と `pin_hash` を原子的に更新
- PIN 未変更（`new_pin_input IS NULL`）：`pin` も `pin_hash` も触れない
- frontend 変更なし（PIN は plain text で RPC 渡し、hash 生成は RPC 内）
- genka_admins / `_verify_management_session` は変更しない
- 準備 PR #169（SQL 追加）・fix PR #170（RPC baseline メッセージ修正）
- DB 実行：2026-07-23（Supabase SQL Editor・手動・1回のみ・Success. No rows returned）
- PRE-CHECK 全合格・GUARD 全合格・内部 POST-CHECK（PC-1〜PC-14）全合格
- POST-COMMIT 全合格・Production smoke 全合格
- 新 fingerprint：create len=1433 / md5=`33ea12279533b4a808a4d14bf11bb0a9`
- 新 fingerprint：update len=1915 / md5=`848eec0d7310c84cdffd05939b6c7a3b`
- 最終 DB 状態：total=11 / pin_hash_null=10 / pin_hash_not_null=1（smoke で1件 hash 済み）
- create 本番 smoke は未実施（cleanup RPC 未整備のため・事前計画どおり）
- **Phase 5-D は未完了**（5-D-3 以降が残る）
- 詳細は docs/db-migrations.md「2026-07-23 Phase 5-D-2」参照

#### 5-D-3 backfill

**状態：✅ 完了（2026-07-24・実行済み）**

- 対象 10 件（pin_hash IS NULL）に bcrypt cost 12 で hash 生成
- 既存 hash 済み 1 件は transaction 内で非変更を確認
- ROW_COUNT=10・hash 整合=11・cost12=11
- PRE-CHECK 全合格・BODY 成功・POST-COMMIT 全合格・Production smoke 全合格
- DB 最終状態：total=11 / pin_hash_null=0 / pin_hash_not_null=11
- `employees.pin` は全 11 件保持（dual-read 互換維持）
- 準備 PR #172・実行記録 PR #173
- 詳細は docs/db-migrations.md「2026-07-24 Phase 5-D-3」参照
- **Phase 5-D は未完了**（5-D-5 以降が残る）

#### 5-D-4 observation

**状態：✅ クローズ（2026-08-03）**

- observation 期間：2026-07-27〜2026-07-30（4営業日・1日短縮・残存リスク受容済み）
- 運用異常5項目すべて0件
- 最終 DB 確認：全項目 baseline 一致（total=11 / pin_hash_null=0 / pin_hash_not_null=11 / hash_integrity=11 / cost12=11）
- 詳細は docs/phase5d-4-observation-closeout.md 参照
- **Phase 5-D は未完了**（5-D-5 以降が残る）

#### 5-D の残工程（次工程：5-D-5）

- **5-D-5**（次工程）：login RPC を hash-only 化（`pin_hash IS NULL` fallback を削除）
- **5-D-6**：`employees.pin` 列 DROP（不可逆ゲート・3者合意必須）

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

### 日報カレンダー（Phase 6-C・追加済み・2026-07-21）

admin-app.html の「日報カレンダー」メニューで、管理者が従業員別の日報提出状況を月別カレンダーで確認できる（閲覧専用MVP）。

- 目的：管理者が全従業員の日報提出状況を月別カレンダーで俯瞰する（従業員を選択して1人ずつ月表示）。
- 実装範囲：sidebar に「📅 日報カレンダー」追加（`showPage('reportcal')`）／active 従業員全員を select で選択（`role` 除外なし）／前月・次月・今月移動／`YYYY年M月`見出し／日〜土の曜日行・土日色分け・今日強調／日報提出日の強調表示／同日複数日報の `+N`／日付クリックで当日の全日報を詳細modal表示（開始/終了時刻・通常/残業時間・現場名・材料件数・memo）／空日は「この日の日報はありません」表示のみ（新規作成へ遷移しない）／loading・empty・error表示・スマホ幅対応。
- データ取得：既存 `list_admin_reports_secure(text, date, date)` を**再利用**（月単位で1回取得・月移動時のみ再取得・従業員切替は取得済みデータをクライアント側で再利用）。**新規RPC・signature変更なし**。
- **DB／SQL／RPC／Supabase 設定の変更なし**（frontend `admin-app.html` のみ・174 insertions / 2 deletions）。DB migration ではないため db-migrations.md には記録しない。
- レビュー：security review（critical 0 / high 0）・test evidence review（全合格）・frontend-design review 実施済み（must-fix 0。指摘の S1「`.card-body` による余白統一」・S2「select へ `aria-label`」を commit 前に反映）。
- Preview smoke（Vercel Preview・2026-07-21）：管理者ログイン／section表示／従業員切替／前月・次月・今月／日報マーカー／同日複数 `+N`／詳細modal／空日表示／スマホ表示／`list_admin_reports_secure` HTTP 200／Console 赤エラーなし／既存 admin section 回帰／`/` 本人カレンダー・`/genka` ログイン回帰、すべて合格。
- Production smoke（2026-07-21）：Vercel Production デプロイ SUCCESS。Preview と同じ主要項目・回帰項目を本番（https://system.okaigumi.co.jp/admin）で確認し、すべて合格。
- Git：PR #156（`Phase 6-C: 管理者日報カレンダー MVP（admin-app.html・read-only・DB変更なし）`・MERGED）／implementation commit `93f40c0`／merge commit `25789c6322c139ffbefe848e7bdc43f38c53e1cd`／mergedAt `2026-07-21T02:14:10Z`（Merge commit 方式）。
- 本番確認日：2026-07-21。

対象外（今回のMVPに含めない）：DB／SQL／RPC変更・有休表示・inactive従業員選択・材料名/数量明細・日報作成/編集/無効化UI・全従業員マトリクス・Phase 5関連変更。

後続候補（未着手・完了扱いにしない）：
- inactive（退職・無効化済み）従業員の過去日報閲覧（selector 拡張）
- 管理者向け日別有休表示（admin 対応の日別有休 read の検討）
- 材料名・数量明細の表示（`list_materials_secure` は employee-session 専用のため、admin 対応の別read RPC 検討）
- 全従業員マトリクス（1画面同時表示）
- accessibility 強化（日付セルの keyboard 操作・button `type` 等）
- iPhone Safari でログイン/PINパッド等の連打時にダブルタップ拡大される問題への対策候補：`/`・`/admin`・`/genka` のログイン・PIN操作へ `touch-action: manipulation` を限定適用する案を別PRで検討（viewport によるページ全体の拡大禁止は行わない）。

※ Phase 6 全体は引き続き「一部完了」。上記後続候補・有休表示等は未完了であり、Phase 6 全体を完了扱いにはしない。Phase 6-D（本記録）はこの記録PRの main merge をもってクローズとする。

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

### Phase 7 の分割（2026-07-26 整理）

| Phase | 内容 | 状態 |
|---|---|---|
| 7-A | backup inventory（`docs/backup-recovery-inventory.md`） | **実装・内容確認・commit済み、未push・未merge** |
| 7-B | restore runbook | 未着手 |
| 7-C | smoke checklist／復旧判定表 | 未着手 |
| 7-D | non-production restore test | 未着手 |
| 7-E | backup automation／rotation／off-site | 未着手 |
| 7-F | Storage backup 対象拡張（`notice-attachments` / `invoice-pdfs` / 孤立ファイル） | 未着手 |

### Phase 7-A：backup inventory（2026-07-26・実装・内容確認・commit済み、未push・未merge）

- 2026-07-26 に現行方式による**最新世代バックアップ**（DB / Storage photos）の取得が成功。**完全バックアップではない**。
- 取得世代・サイズ・SHA-256・対象範囲・対象外・実行環境の前提は `docs/backup-recovery-inventory.md` に記録。
- 判明事項：Supabase CLI の `db dump` には **Docker Desktop が必須**（未導入時は `LegacyDockerRunError`）。`docs/backup-policy.md` の前提ツールへ追記した。
- DB dump には `employees.pin` が残存するため、**平文PINを含む可能性のある機密バックアップ**として厳重管理する。
- 復旧可能性は**未検証**（復元手順は 7-B、復元テストは 7-D）。「復旧可能」とは断定しない。
- 状態：Phase 7-A は inventory 作成・内容確認・commit 済み。**未push・未merge・main 未反映**。**Phase 7 全体は未完了**。

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
- 日報カレンダーUI改善（候補・未着手）
  - 現場日報の履歴画面をカレンダー表示にする
  - 従業員が日ごとの日報提出状況・記入漏れ・有給取得日を確認できるようにする
  - 目的は日報未入力の早期発見と従業員本人の自己確認
  - 対象は従業員画面（index.html の日報履歴）。今回は実装しない（着手前の候補）
- 日報の当日取消/削除機能（候補・未着手 / Phase 4-C-1 で判明した別課題）
  - 現状、同じ日・同じ時間に日報を重複入力しても、画面から削除/取消する手段がない
  - 候補設計：本人の当日取消RPC、または管理者取消/削除機能
  - 物理削除より `status='cancelled'` などの論理取消を優先検討
  - 本人取消は employee session 検証・当日限定・確認済み日報の扱いなどセキュリティ設計を伴う
  - 重複入力時の運用改善を目的とする（着手前の候補）

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
- 請求書編集モーダルの表示位置調整（現状は表示位置が下すぎるため、中央またはやや上寄せにする）
- genka 原価サマリ/集計画面の自動集計化（画面切り替え時に自動集計し、実装後は集計ボタンを削除）
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

**完了済み（参考）：**

- Phase 3 残り INSERT / UPDATE のRPC化（優先順位1〜3すべて完了）
  - sites / site_assignments（完了・2026-06-13）
  - materials / machines（完了・2026-06-19）
  - employee_rates / unit_rates（完了・2026-06-30）

**次の実作業は以下の2系統から判断（未着手）：**

A. 運用に出す線
1. 運用開始前チェックを完了する（Phase 1）
2. 小規模運用を開始する（Phase 2）
3. 実際に困った点をメモする
4. 必要に応じて admin-app.html の改善に進む（Phase 6）

B. セキュリティ継続強化の線
1. Phase 4 RLSポリシー整理（pg_policies 棚卸し・役割整理）
2. Phase 5 PIN・ログイン強化（PINハッシュ化・ログイン失敗制限・session_token 期限管理）

※ 日報カレンダーUI改善は Phase 8 業務効率化の候補として追加済み（未着手・実装は運用後判断）
