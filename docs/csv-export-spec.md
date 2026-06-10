# 集計出力機能 CSV出力仕様（Phase 1-2）

- 対象：集計出力機能 MVP（CSV出力＋ローカルHTMLビューア）
- 作成フェーズ：Phase 1-2「CSV列定義・集計ルール確定」
- 前提スキーマ：Phase 1-1（site_categories / company_categories / sites.category_id / sites.contract_amount / companies.category_id）適用済み
- 対象CSV：projects_summary.csv / attendance_details.csv / project_cost_details.csv / machine_details.csv

---

## 1. 前提・制約（必読）

本仕様の出力値は **MVP段階の概算値** である。以下を理解した上で利用すること。

- **粗利・原価率は概算値**：下記の制約により、会計上の正確な原価・利益とは一致しない。
- **pending日報を含む**：`reports.status` はMVPでは全件対象。未確定（pending）日報の労務・ダンプ・警備費が projects_summary に含まれる。`attendance_details.report_status` 列で判別可能。確定運用が固まり次第 `confirmed` 限定への切替を検討する。
- **重機費が限定的**：工事別原価の重機費は `invoices(category='machine_lease')` のみ反映。owned重機=0円、リース月額は会社全体費用、`machine_locations` は移動記録のみ（稼働時間・日数なし）。原価率は重機費を限定的にしか含まない。
- **税込/税抜を正規化しない**：`invoices.amount` は税込/税抜混在の生値。`tax_included` フラグで区分のみ提示。粗利・原価率は税区分が混在する概算。正規化は後続/Phase2。
- **外注費の二重計上リスク**：subcontract_cost は日報由来（`reports.subcontractor_ids` × `unit_rates`）と請求書由来（`invoices(category='subcontract')`）を合算する。両者が同一外注を指す運用の場合、二重計上になりうる。内訳列（report_/invoice_）で確認可能。
- **VIEW定義の最終確認**：本仕様の `report_summary`（id / status / 参照列）は **2026-06-03 バックアップのVIEW定義**に基づく。実装着手時に**本番 `report_summary` 定義で id・status・参照列の存在を再確認**すること。

---

## 2. 共通CSV仕様

| 項目 | 仕様 |
|------|------|
| 文字コード | **UTF-8 BOM付き**（Excel文字化け防止） |
| 改行コード | **CRLF** |
| 区切り | カンマ |
| エスケープ | 値にカンマ・改行・ダブルクォートを含む場合、値全体をダブルクォートで囲み、内部の `"` は `""` に置換（RFC4180準拠） |
| 日付 | `YYYY-MM-DD` |
| 時刻 | `HH:MM` |
| 金額 | カンマなし整数（円）。負値はマイナス記号 |
| 率（原価率等） | 小数1桁 |
| 按分比率 | 小数2〜4桁 |
| ID | すべて文字列（UUID） |
| 真偽値 | `true` / `false` |
| NULL | 原則空文字。ただし合算金額列は `0` |

### Excelで開く前提の注意点
- BOM必須（無いとShift_JIS解釈で文字化け）。
- 金額はカンマなし（カンマ入りは列ズレ・文字列化）。
- 日付 `YYYY-MM-DD` はExcelが日付型へ自動変換する。元文字列保持が必要なら取込時に「テキスト」指定。
- memo等の改行はクォート囲みで1セルに保持。

---

## 3. 年度計算ルール

```
fiscal_year(d):
  d.month >= 4 → d.year
  d.month <  4 → d.year - 1
```

- 工事年度＝**4月始まり固定**（例：2025年度＝2025-04-01〜2026-03-31）。
- 基準日：
  - projects_summary … `sites.start_date`（分類・予算照合用）
  - attendance_details … `report_date`
  - project_cost_details … `invoice_date`
- 会社損益の起点月切替（`start_month = 4 or 9`）は **Phase 2 RPC** に持ち越し。

---

## 4. JOIN方法（すべてLEFT JOIN）

```
sites.category_id     → site_categories.name      （工事分類）
sites.company_id      → companies.name            （発注者名）
companies.category_id → company_categories.name   （発注者区分）
report_summary.site_ids[]要素 → sites.name        （現場名・配列展開）
report_summary.employee_name                       （従業員名・VIEW内蔵）
employee_rates → daily_rate                         （§6 のルールで選択）
unit_rates(category,name) → unit_price             （ダンプ・警備・外注単価）
machines.company_id   → companies.name            （重機所属会社）
```
マスタ未設定はNULL→空文字で行を残す（INNER JOINで落とさない）。

---

## 5. projects_summary.csv（工事別サマリー）

粒度：**1行 = 1工事 / 1 site**（全期間の累計）

| 列順 | CSV列名 | 取得元 | データ型 | 集計/変換方法 | 必須/任意 | NULL時の扱い | 備考 |
|------|---------|--------|----------|----------------|-----------|--------------|------|
| 1 | project_id | sites.id | 文字列 | UUIDそのまま | 必須 | ― | |
| 2 | site_name | sites.name | 文字列 | そのまま | 必須 | ― | |
| 3 | fiscal_year | 算出 | 整数 | sites.start_date から4月始まり年度 | 任意 | 空文字 | 分類・予算照合用 |
| 4 | category_name | sites.category_id→site_categories.name | 文字列 | LEFT JOIN | 任意 | 空文字 | 工事分類 |
| 5 | client_name | sites.company_id→companies.name | 文字列 | LEFT JOIN | 任意 | 空文字 | 発注者名 |
| 6 | client_category | companies.category_id→company_categories.name | 文字列 | 2段LEFT JOIN | 任意 | 空文字 | 発注者区分 |
| 7 | location | sites.location | 文字列 | そのまま | 任意 | 空文字 | |
| 8 | start_date | sites.start_date | 日付 | YYYY-MM-DD | 任意 | 空文字 | |
| 9 | end_date | sites.end_date | 日付 | YYYY-MM-DD | 任意 | 空文字 | |
| 10 | contract_amount | sites.contract_amount | 整数 | カンマなし | 任意 | 空文字 | 請負金額 |
| 11 | budget | site_budgets.budget | 整数 | §下記ルールで採用（**参考値**） | 任意 | 空文字 | 複数年度按分なし |
| 12 | labor_cost | report_summary | 整数 | 按分後labor合計 | 必須 | 0 | |
| 13 | report_subcontract_cost | reports.subcontractor_ids × unit_rates(subcontractor) | 整数 | 按分後 | 必須 | 0 | 日報由来 |
| 14 | invoice_subcontract_cost | invoices(category='subcontract') | 整数 | site_id一致合算 | 必須 | 0 | 請求書由来 |
| 15 | subcontract_cost_total | 算出 | 整数 | 13+14 | 必須 | 0 | **二重計上注意** |
| 16 | material_cost | invoices(category='material') | 整数 | site_id一致合算 | 必須 | 0 | |
| 17 | machine_cost | invoices(category='machine_lease') | 整数 | site_id一致合算 | 必須 | 0 | リース月額（会社全体）は含めない |
| 18 | dump_cost | report_summary | 整数 | 按分後（dump_count × unit_rates(dump)） | 必須 | 0 | 単価未設定時0 |
| 19 | guard_cost | report_summary | 整数 | 按分後（guard_count × unit_rates(guard)） | 必須 | 0 | 単価未設定時0 |
| 20 | other_cost | invoices(category='other') | 整数 | site_id一致合算 | 必須 | 0 | |
| 21 | total_cost | 算出 | 整数 | 12 + 15 + 16 + 17 + 18 + 19 + 20 | 必須 | 0 | subcontractは_totalを使用 |
| 22 | gross_profit | 算出 | 整数 | contract_amount − total_cost | 任意 | contract無→空 | 税非正規化（概算） |
| 23 | profit_rate | 算出 | 小数 | gross_profit / contract_amount × 100 | 任意 | 空文字 | 小数1桁・概算 |

### budget列の採用ルール（参考値）
- `sites.start_date` から算出した4月始まり `fiscal_year` に一致する `site_budgets.year`、かつ `month IS NULL`、`is_active = true` の年間予算を採用する。
- 原則として同条件の有効な年間予算は1件である前提。
- 同条件で複数件が見つかった場合はデータ不整合として扱い、Phase 2 RPC設計時に検出・警告方法を決める。
- **複数年度工事でも予算の按分・合算は行わない。**
- 注記：**複数年度にまたがる工事では fiscal_year と一致する年度の予算のみを表示し、工事全体の予算とは一致しないことがある。** budget はあくまで参考値。

### 外注費の二重計上に関する注意
- `subcontract_cost_total` は日報由来（13）と請求書由来（14）の合算（既存 genka-app の挙動を踏襲）。
- 同一外注を日報と請求書の両方に記録する運用では二重計上になりうる。内訳列で確認すること。

---

## 6. attendance_details.csv（出勤・人工明細）

粒度：**1行 = 1日報 × 現場（按分後の行分割）**。HTMLビューアでは現場名「・」結合表示も可能とする。

| 列順 | CSV列名 | 取得元 | データ型 | 集計/変換方法 | 必須/任意 | NULL時の扱い | 備考 |
|------|---------|--------|----------|----------------|-----------|--------------|------|
| 1 | report_id | report_summary.id | 文字列 | そのまま | 必須 | ― | |
| 2 | report_date | report_summary.report_date | 日付 | YYYY-MM-DD | 必須 | ― | |
| 3 | fiscal_year | 算出 | 整数 | report_date から4月始まり年度 | 必須 | ― | 年度集計の基準日 |
| 4 | employee_id | report_summary.employee_id | 文字列 | そのまま | 必須 | ― | |
| 5 | employee_name | report_summary.employee_name | 文字列 | そのまま | 必須 | 空文字 | |
| 6 | project_id | site_ids[要素] | 文字列 | 配列展開 | 任意 | 空（現場なし日報） | |
| 7 | site_name | site_ids→sites.name | 文字列 | LEFT JOIN | 任意 | 空（現場なし日報） | |
| 8 | site_count | site_ids長さ | 整数 | array_length | 必須 | 0（現場なし日報） | 按分根拠 |
| 9 | allocation_ratio | 算出 | 小数 | 1/site_count | 任意 | 空（現場なし日報） | 小数2〜4桁 |
| 10 | work_type | report_summary.work_type | 文字列 | そのまま | 任意 | normal | |
| 11 | start_time | report_summary.start_time | 時刻 | HH:MM | 任意 | 空文字 | |
| 12 | end_time | report_summary.end_time | 時刻 | HH:MM | 任意 | 空文字 | |
| 13 | normal_mins | report_summary.normal_mins | 整数 | そのまま | 必須 | 0 | |
| 14 | overtime_mins | report_summary.overtime_mins | 整数 | そのまま | 必須 | 0 | |
| 15 | labor_days | 算出 | 小数 | normal_mins>0なら1×ratio（現場なしは1） | 必須 | 0 | |
| 16 | daily_rate | employee_rates | 整数 | §下記ルールで選択 | 必須 | 22000 | |
| 17 | rate_is_default | 算出 | 真偽 | 既定22000を使った場合 true | 必須 | false | 単価未登録判別 |
| 18 | labor_cost | 算出 | 整数 | (daily_rate＋残業)×ratio（現場なしは全額） | 必須 | 0 | |
| 19 | report_status | report_summary.status | 文字列 | そのまま | 必須 | pending | MVPは全件出力 |
| 20 | memo | report_summary.memo | 文字列 | 改行はクォート | 任意 | 空文字 | |

### daily_rate の選択ルール
- `employee_rates` から **`effective_from <= report_date`** の行を **`effective_from DESC LIMIT 1`** で取得。
- 該当行がない場合のみ既定値 **22000** を使用し、`rate_is_default = true` とする。
- 残業計算：`overtime_mins / 60 × (daily_rate / 8) × 1.25`（既存 genka-app の式を踏襲）。
- ※ 本ルールは既存 genka-app（日付無視で従業員ごと最新単価1件）からの仕様改善。実装時はCSV/ビューアで date-aware に統一する。

### 現場なし日報の扱い
- **工事別原価按分の対象外**（projects_summary には計上されない）。
- **出勤簿として attendance_details.csv には1行出力する。**
- `project_id`＝空、`site_name`＝空、`site_count`＝0、`allocation_ratio`＝空。
- `labor_days` / `labor_cost` は按分せず本人の1日分（全額）を出力。site紐付けがないため原価二重計上は発生しない。

---

## 7. project_cost_details.csv（原価明細・請求書台帳）

定義：**MVPは invoices を主データとする明細**。1行 = 1請求書。
- 人件費は attendance_details.csv 側で表現（本CSVに含めない）。
- ダンプ・警備は projects_summary の集計に含めるが、明細CSVへの展開は後続検討（本CSVに含めない）。

| 列順 | CSV列名 | 取得元 | データ型 | 集計/変換方法 | 必須/任意 | NULL時の扱い | 備考 |
|------|---------|--------|----------|----------------|-----------|--------------|------|
| 1 | invoice_id | invoices.id | 文字列 | そのまま | 必須 | ― | |
| 2 | invoice_date | invoices.invoice_date | 日付 | YYYY-MM-DD | 必須 | ― | |
| 3 | fiscal_year | 算出 | 整数 | invoice_date から4月始まり年度 | 必須 | ― | |
| 4 | project_id | invoices.site_id | 文字列 | そのまま | 任意 | 空（現場なし請求書） | |
| 5 | site_name | site_id→sites.name | 文字列 | LEFT JOIN | 任意 | 空文字 | |
| 6 | client_name | invoices.company_id→companies.name | 文字列 | LEFT JOIN | 任意 | 空文字 | site由来でサーバ設定 |
| 7 | cost_category | invoices.category | 文字列 | そのまま | 必須 | other | subcontract/material/machine_lease/other |
| 8 | vendor_name | invoices.vendor_name | 文字列 | そのまま | 必須 | 空文字 | |
| 9 | amount | invoices.amount | 整数 | **生値・正規化なし** | 必須 | 0 | |
| 10 | tax_included | invoices.tax_included | 真偽 | true/false | 必須 | true | 既定true |
| 11 | status | invoices.status | 文字列 | そのまま | 必須 | confirmed | 出力対象は confirmed+posted |
| 12 | description | invoices.description | 文字列 | そのまま | 任意 | 空文字 | 実在確認済 |
| 13 | memo | invoices.memo | 文字列 | クォート | 任意 | 空文字 | 実在確認済 |

### 出力対象 status
- **`confirmed` + `posted` のみ**を出力。
- `uploaded` / `extracted` / `suggested`（AI取込途中状態）と `rejected` は除外。

### 税込/税抜
- `amount` は `invoices.amount` の生値。**MVPでは税込/税抜の正規化を行わない**。`tax_included` フラグで区分のみ提示。

---

## 8. machine_details.csv（重機台帳）

定義：**MVPは重機台帳として扱う**。1行 = 1重機。

| 列順 | CSV列名 | 取得元 | データ型 | 集計/変換方法 | 必須/任意 | NULL時の扱い | 備考 |
|------|---------|--------|----------|----------------|-----------|--------------|------|
| 1 | machine_id | machines.id | 文字列 | そのまま | 必須 | ― | |
| 2 | machine_name | machines.name | 文字列 | そのまま | 必須 | ― | |
| 3 | ownership | machines.ownership | 文字列 | lease/owned | 必須 | owned | |
| 4 | owner_company | machines.company_id→companies.name | 文字列 | LEFT JOIN | 任意 | 空文字 | 所属/管理会社 |
| 5 | lease_company | machines.lease_company | 文字列 | そのまま | 任意 | 空文字 | leaseのみ |
| 6 | lease_start | machines.lease_start | 日付 | YYYY-MM-DD | 任意 | 空文字 | |
| 7 | lease_end | machines.lease_end | 日付 | YYYY-MM-DD | 任意 | 空文字 | |
| 8 | lease_monthly | machines.lease_monthly | 整数 | カンマなし | 任意 | 空文字 | leaseのみ・会社全体費用 |
| 9 | owned_cost | 固定 | 整数 | **MVPは常に0** | 必須 | 0 | 標準単価/償却はPhase2 |
| 10 | is_active | machines.is_active | 真偽 | true/false | 必須 | true | |

### 注記
- owned重機費は **MVPでは0円扱い**。
- リース月額（lease_monthly）は **会社全体費用** であり、**現場別重機費には基本含めない**。
- `machine_locations` は移動記録であり、**稼働時間・使用日数を持たない**。このため**現場別の重機費は正確には算出できない**。machine_details は台帳の性格。

---

## 9. Phase 2 以降に持ち越す論点

- 会社損益の起点月パラメータ（`fiscal_year_start_month = 4 or 9`）切替（RPC側）
- 税抜正規化ロジック（CSVは生値＋フラグ、計算は後段）
- 管理者セッション付き SECURITY DEFINER 参照系RPC化（出力RPC本体）
- owned重機の標準単価・償却による原価計上
- ダンプ・警備の明細CSV展開（project_cost_details への統合）
- 年度別会社損益集計（attendance/cost の日付ベース）
- `reports.status` を confirmed 限定に切り替える運用判断
- 外注費二重計上の運用ルール確定（日報外注と請求書外注の切り分け）
- `site_budgets` 同条件複数件（データ不整合）の検出・警告方法

---

## 10. CSV出力パッケージ化（将来：Phase 2-4-8）

設計：[`docs/csv-export-package-spec.md`](csv-export-package-spec.md)（Phase 2-4-8-0 設計完了 / 実装未着手）。

- 個別CSV出力（本仕様）に加え、**CSV一式ZIP出力**を将来追加する。
- 出力パッケージの期間指定は**年月のみ**とし、日付指定はしない（裏側で月初〜翌月初未満に変換）。
- ZIPには4CSV（projects_summary / attendance_details / project_cost_details / machine_details）と `manifest.json` を入れる。
- **CSV自体の列仕様は本仕様（§5〜§8）を維持する。ZIP化しても内部のCSV列定義は変更しない。**
- `manifest.json` は出力パッケージのメタ情報（format_version・system・exported_at・period・files[]）として扱う。CSVの内容には含めない。
- 個別CSV出力は廃止せず、予備・検証・トラブル対応用として残す。
- ZIP出力の実装時は、ローカル同梱した JSZip（同梱済み：`vendor/jszip/jszip.min.js`・v3.10.1・MIT OR GPL-3.0-or-later）を使う予定。**外部CDNは使わない。** ライブラリ選定・配置・ライセンス方針は `docs/csv-export-package-spec.md` §13 に従う。
- 管理コンソールCSV出力では、将来的に**年月指定によるCSV一式ZIP出力をメイン導線**にする（UI設計は `docs/csv-export-package-spec.md` §14）。**個別CSV出力は予備として残す。**
- **管理コンソールにCSV一式ZIP出力を実装済み**（Phase 2-4-8-4・`admin-app.html`。コミット `11b01aa`）。期間指定UIは**年月のみ**。ZIP化してもCSV列定義は変更しない。個別CSV出力は詳細・予備として残す。
- ZIP出力の既存RPC呼び出しでは、**開始年月を月初日（例 2026-04 → 2026-04-01）、終了年月を月末日（例 2026-06 → 2026-06-30）に変換**して渡す（既存RPCの `date_to_input` を inclusive 比較で扱う想定に合わせるため）。
- 管理コンソールで出力したZIPは、ローカルCSVビューアーのZIP読込UI（設計：`docs/csv-export-package-spec.md` §16・Phase 2-4-8-5）で読み込む想定。**ZIP内CSVの列仕様は個別CSVと同一。**
- **ローカルCSVビューアーにZIP読込を実装済み**（Phase 2-4-8-6・`local-viewers/csv-viewer.html`。コミット `c867027`）。管理コンソールで出力したZIPを、ローカルCSVビューアーのZIP読込で読み込める実装になった。**ZIP内CSVの列仕様は個別CSVと同一。**
- **管理コンソール出力ZIPとローカルビューアーZIP読込の実ZIP結合確認を実施済み**（Phase 2-4-8-8）。2026-06単月の実ZIP（`okaigumi-csv-export_202606-202606_20260610-1446.zip`）で、4CSV + manifest・manifest rows と実CSV行数の一致・ビューアー読込・複数CSV統合ビュー反映・工事詳細・印刷/PDFまで確認済み（2026-06は project_cost_details 0行のため請求書費用は0件ケースとして確認）。
- ZIP化・パッケージ化を行っても **CSV列仕様（§5〜§8）は変更しない。**
- CSV出力ZIPの月次運用手順は [`docs/csv-export-operation-guide.md`](csv-export-operation-guide.md) を参照。
- 個別CSV出力は詳細・予備として残す。通常運用ではZIP出力を推奨。
- 現時点の保管は pCloud + 外付けHDD暫定バックアップ。
- UGREEN NASync 導入後はNASバックアップ運用を追加する（現時点では未導入・後日購入予定）。
- CSV ZIPは、ビューアーで読み込んだ後、帳票選択メニューから各CSV帳票を確認する方針にする（UX改善方針：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md)・Phase 2-4-9-0 設計）。
- Phase 2-4-9-1（コミット `08be5ac`）で、ZIP読込後の帳票選択メニューを実装済み。単体CSV帳票への接続は次フェーズ（2-4-9-2）予定。
- ZIP読込後の帳票カードは、次フェーズでZIP由来rowsを単体CSVビュー形式で表示する方針（Phase 2-4-9-2-a 設計：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §14）。`project_cost_details` 0件は正常な空表示として扱う。
- Phase 2-4-9-2-b（コミット `64c699b`）で、ZIP内CSVを単体CSVビューへ接続するための前提として handleText 分離を実装済み。帳票カード接続は次フェーズ予定。
- Phase 2-4-9-2-c（コミット `f2b1b1c`）で、ZIP読込後の「工事一覧・原価概要」カードから ZIP内 `projects_summary.csv` を単体CSVビュー形式で表示できるようになった。他帳票は次フェーズ以降で接続予定。
- Phase 2-4-9-2-d（コミット `c7b1cc4`）で、ZIP読込後の「日報・労務費」カードから ZIP内 `attendance_details.csv` を単体CSVビュー形式で表示できるようになった。`project_cost_details` / `machine_details` は次フェーズ以降で接続予定。
- Phase 2-4-9-2-e（コミット `34d5d73`）で、ZIP読込後の「請求書費用」カードから ZIP内 `project_cost_details.csv` を単体CSVビュー形式で表示できるようになった。0件CSVでも正常表示する。`machine_details` は次フェーズで接続予定。
- Phase 2-4-9-2-f（コミット `26d7a30`）で、ZIP読込後の「重機台帳」カードから ZIP内 `machine_details.csv` を単体CSVビュー形式で表示できるようになった。これにより帳票選択メニューの4カードすべてが接続済み。
- Phase 2-4-9-2-g で、ZIP読込後の4帳票単体ビュー接続について総合回帰確認を実施し、全90項目PASSを確認した。これにより Phase 2-4-9-2 は完了。
