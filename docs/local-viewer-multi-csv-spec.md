# ローカルCSVビューアー 複数CSV統合モード設計（工事別月別原価ビュー）

- 対象：ローカルHTML CSVビューアー（`local-viewers/csv-viewer.html`）の次フェーズ
- フェーズ：Phase 2-4-7-0「複数CSV統合モード設計」
- 状態：**設計のみ。実装は未着手。**
- 関連：[`docs/local-viewer-spec.md`](local-viewer-spec.md) / [`docs/csv-export-spec.md`](csv-export-spec.md) / [`docs/roadmap.md`](roadmap.md)
- 名称案：**複数CSV統合モード** / **工事別月別原価ビュー**

本ドキュメントは設計仕様であり、ここに書かれた関数名・データ構造・列名は実装時の指針である。
列名はすべて `docs/csv-export-spec.md`（Phase 1-2 CSV列定義）に準拠する。判断できない結合キー・列は「13. 未確定事項」に明記する。

---

## 1. 目的

- 完了工事・過去工事の原価を、ローカル（オフライン）で確認する。
- 工事別に月別原価を確認する。
- 工事別に労務費・請求書明細・重機情報を横断して確認する。
- CSVバックアップを単なる保存ではなく、閲覧・分析に使えるようにする。
- Supabase接続なし、APIキーなし、外部CDNなし、`file://` で動くローカルHTMLビューアーとして維持する。

既存の単体CSV専用ビュー（attendance_details / projects_summary / project_cost_details / machine_details）は維持したうえで、新たに「複数CSVを同時に読み込んで工事単位で横断表示する」モードを追加する。

---

## 2. 対象CSV

```text
projects_summary.csv
attendance_details.csv
project_cost_details.csv
machine_details.csv
```

役割：

```text
projects_summary.csv
→ 工事マスタ・最終集計・請負金額・発注者・工事分類。統合ビューの「工事」軸。

attendance_details.csv
→ 労務費・出勤日・従業員・日報由来の工事別労務明細（report_date / labor_cost）。

project_cost_details.csv
→ 請求書由来の材料費・外注費・重機リース・その他費用など（invoice_date / amount / cost_category）。

machine_details.csv
→ 重機台帳（1行＝1重機）。稼働日・現場・稼働時間を持たないため、
   単体では月別/現場別重機費を出せない。当面は台帳参照に留める。
```

---

## 3. CSV読み込み方式

### 採用方式（初期実装）

**方式A（4つのファイル選択枠）＋ 自動判定補助** を採用する。

```text
方式A：4つのファイル選択枠を用意する
  - projects_summary
  - attendance_details
  - project_cost_details
  - machine_details

方式B（不採用・将来拡張）：複数ファイルを一括選択して、CSV種別判定で自動振り分ける
```

採用理由：

- どのCSVが読み込まれているか分かりやすい。
- 不足CSVを明示しやすい。
- 間違ったCSVを読み込んだときに警告しやすい。
- 将来、一括ドロップ（方式B）にも拡張しやすい。

「自動判定補助」とは：各枠に読み込まれたファイルに対し、既存の `detectCsvType()` を実行し、枠の期待種別と一致しない場合に警告を出す（例：projects_summary 枠に attendance_details を入れたら警告）。

### 読込UIに含める要素

- 読込済みCSVの表示（ファイル名・種別・行数）
- 行数表示
- CSV種別表示（`detectCsvType()` の結果）
- 必須CSV / 任意CSV の区分表示
- 各枠の再読み込み / クリア、全体クリア
- **UTF-8 BOM対応**（既存パーサの BOM 除去を流用）
- **既存CSVパーサ（`parseCsvToMatrix` 等）の利用**
- **CSV種別判定は既存ロジック（`detectCsvType` / `CSV_TYPES`）を使う**

既存の単体モードのパーサ・種別判定をそのまま流用し、複数CSVモード用に新規パーサは作らない。

---

## 4. 必須CSV・任意CSV

```text
必須：
  projects_summary.csv

任意：
  attendance_details.csv
  project_cost_details.csv
  machine_details.csv
```

理由：

- 工事一覧・工事詳細・工事別月別原価の「軸」は projects_summary（工事マスタ）。
- 労務費の月別内訳は attendance_details が必要。
- 請求書由来の月別内訳は project_cost_details が必要。
- machine_details は台帳であり、月別/現場別重機費の算出には不十分。

不足CSVがある場合の表示方針：

```text
projects_summary 未読込
→ 統合モードを開始できない（必須）。「工事マスタCSVを読み込んでください」と表示。

attendance_details 未読込
→ 労務費の月別内訳は表示不可（「労務明細CSV未読込」と注記、該当列は —）。

project_cost_details 未読込
→ 請求書由来の月別内訳は表示不可（「請求書明細CSV未読込」と注記、該当列は —）。

machine_details 未読込
→ 重機台帳情報は表示不可（重機情報ページに「重機台帳CSV未読込」と注記）。
```

不足を「静かに0」とせず、「未読込のため表示不可」と分かるように表示する。

---

## 5. 結合キー設計

`docs/csv-export-spec.md` で確認した実際の列名で記述する。

### 確定している結合キー

3つのCSVは **`project_id`（= `sites.id`・UUID文字列）** を共通の工事キーとして持つ。

```text
projects_summary.csv
  - project_id   （= sites.id・必須）        ← 工事キー（マスタ側）
  - site_name    （= sites.name・必須）

attendance_details.csv
  - project_id   （= site_ids要素 = sites.id・任意※現場なし日報は空）
  - site_name    （= sites.name・任意）
  - report_date  （月キー）
  - labor_cost   （労務費）

project_cost_details.csv
  - project_id   （= invoices.site_id = sites.id・任意※現場なし請求書は空）
  - site_name    （= sites.name・任意）
  - invoice_date （月キー）
  - amount       （金額・生値）
  - cost_category（subcontract / material / machine_lease / other）

machine_details.csv
  - machine_id   （= machines.id）
  - machine_name （= machines.name）
  - ※ project_id / site_id / 日付 を持たない
```

### 結合方針

- **工事の結合キーは `project_id`（= sites.id）を最優先とする。** 3CSVとも同一の `sites.id` を指すため、UUID一致で安全に結合できる。
- `project_id` が空の行：
  - attendance_details … 現場なし日報（按分対象外）。工事別原価には計上しない（出勤簿としては存在する）。
  - project_cost_details … 現場なし請求書。工事別原価には計上できない → 確認リストに計上。
- **`site_name` だけの結合は同名工事リスクがあるため行わない。** ID優先。
- `project_id` が空で `site_name` のみある行を名称で代替結合するかは任意機能とし、行う場合は **必ず警告を出し、確認リストに「site_name 代替結合が発生した行」として記録する**（既定はOFF推奨）。

### machine_details の扱い（重要）

- `machine_details.csv` は工事ID（site_id）も日付も持たないため、**工事別・月別原価には直接結合できない。**
- 当面 machine_details は「重機台帳参照」として独立表示し、**工事別月別原価には直接足し込まない。**
- 重機費の工事別月別反映には、将来 `machine_locations`（現場・日付を持つ稼働データ）や別の稼働明細CSVが必要。
  - ただし `machine_locations` は移動記録であり稼働時間・使用日数を持たないため、正確な稼働原価化には追加設計が必要（csv-export-spec §8 注記）。
- なお、請求書由来の重機リース費（`project_cost_details.cost_category = machine_lease`）は工事・日付を持つため、月別原価の「重機費」として **machine_details とは別に** 反映できる（「8. 月別原価の計算ルール」参照）。

---

## 6. 内部データモデル設計

既存の単体CSV `state` とは **別に** 複数CSV用 `multiState` を持つ。

```js
multiState = {
  loaded: false,             // projects_summary（必須）が読み込まれたら true
  files: {                   // 読込済みファイルのメタ（名前・種別・行数）
    projects_summary: null,  // {fileName, csvType, rowCount} | null
    attendance_details: null,
    project_cost_details: null,
    machine_details: null
  },
  rows: {                    // パース済み行（オブジェクト配列）
    projects_summary: [],
    attendance_details: [],
    project_cost_details: [],
    machine_details: []
  },
  indexes: {                 // project_id をキーにした索引（結合用）
    projectsById: Map,             // project_id -> projects_summary 行
    attendanceByProjectId: Map,    // project_id -> attendance_details 行[]
    invoicesByProjectId: Map,      // project_id -> project_cost_details 行[]
    machinesById: Map              // machine_id -> machine_details 行（工事には紐付かない）
  },
  warnings: [],
  errors: []
}
```

実装方針：

- 既存の単体CSV `state` には手を加えず、`multiState` を新設する。
- 既存の単体CSVビューを壊さない（単体モードと統合モードを分離）。
- 複数CSVモードは **別ページ/別モード** として追加する（単体ビューと排他または併存切替）。
- 既存のCSVパーサ・種別判定を流用する。
- `indexes` は読込完了時に1回構築し、各ページ描画で再利用する。

---

## 7. 表示ページ設計

複数CSV統合モードで追加するページ案：

```text
統合ダッシュボード
工事一覧
工事詳細
工事別月別原価
労務明細
請求書明細
重機情報
確認リスト
生データ
```

### 統合ダッシュボード

```text
読込済みCSV（種別ごとに 読込済/未読込）
工事件数（projects_summary 行数）
労務明細件数（attendance_details 行数）
請求書明細件数（project_cost_details 行数）
重機台帳件数（machine_details 行数）
警告件数
不足CSV（未読込の任意CSV一覧）
```

### 工事一覧

`projects_summary.csv` を軸に表示。工事名クリックで工事詳細へ遷移（`project_id` をキーに）。

```text
工事名
発注者（client_name）
工事分類（category_name）
年度（fiscal_year）
請負金額（contract_amount）
合計原価（total_cost）
月別原価有無（attendance/invoice いずれかに該当 project_id の明細があるか）
労務明細有無（attendanceByProjectId に該当 project_id があるか）
請求書明細有無（invoicesByProjectId に該当 project_id があるか）
警告
```

### 工事詳細

工事名クリックで表示。`project_id` で各CSVを横断。

```text
工事基本情報（site_name / client_name / category_name / fiscal_year / location / start_date / end_date）
請負金額（contract_amount）
projects_summary 上の合計原価（total_cost）
attendance_details 由来の労務費（該当 project_id の labor_cost 合計）
project_cost_details 由来の請求書金額（該当 project_id の amount 合計）
差異（projects_summary 値とローカル再集計値の差。9章のルール）
警告（差異・現場なし・原価率100%以上 等）
```

工事詳細内は、月別原価 / 労務明細 / 請求書明細 / 重機情報へのページ切替（タブ）を用意する。

### 工事別月別原価（主目的）

選択工事（`project_id`）の月別原価表。

```text
月（YYYY-MM）
労務費（attendance_details）
請求書金額（project_cost_details 合計）
材料費（cost_category=material）
外注費（cost_category=subcontract）
その他費用（cost_category=other）
重機費（machine_lease。machine_details 由来ではない点に注意）
月合計（算出可能な費用のみ）
累計
```

重要：

- 労務費は `attendance_details.report_date` を月キー（YYYY-MM）にする。
- 請求書費用は `project_cost_details.invoice_date` を月キーにする。
- **重機費は machine_details.csv 単体では出せない。** 月別の「重機費」列は請求書由来の `cost_category=machine_lease` を用いる。machine_details 由来の台帳値（リース月額等）は月別原価に足し込まない。
- 月別合計には算出可能な費用のみを含める。
- 表上部・列見出しに「何を含めた合計か」を明記する（労務費＋請求書由来費目。台帳リース月額・owned重機費・ダンプ/警備は含まない 等）。

### 労務明細

選択工事に紐づく `attendance_details.csv` の行を表示。

```text
日付（report_date）
従業員（employee_name）
通常時間（normal_mins）
残業時間（overtime_mins）
人工（labor_days）
労務費（labor_cost）
日報状態（report_status）
メモ（memo）
```

- 既存 attendance_details の **report_id ピボット／二重計上防止方針を再利用**する。
  `normal_mins` / `overtime_mins` を rawRows で生SUMしない（report_id 単位で集約してから扱う）。
- 金額は `labor_cost` を使う。

### 請求書明細

選択工事に紐づく `project_cost_details.csv` の行を表示。

```text
請求日（invoice_date）
業者名（vendor_name）
費目（cost_category・日本語化）
摘要（description）
金額（amount）
状態（status・日本語化）
メモ（memo）
```

### 重機情報

MVPでは machine_details を **台帳として独立表示**（工事ごとではない）。

```text
重機名（machine_name）
区分（ownership・日本語化）
状態（is_active・日本語化）
リース月額（lease_monthly）
所有会社（owner_company）
リース会社（lease_company）
```

- 工事との紐付け列がないため、**選択工事ごとの重機情報としては表示できない旨を明記**する。

### 確認リスト（横断チェック）

```text
projects_summary にあるが attendance_details に明細がない工事
projects_summary にあるが project_cost_details に明細がない工事
attendance_details にあるが projects_summary に存在しない project_id
project_cost_details にあるが projects_summary に存在しない project_id
site_name 代替結合が発生した行（代替結合を許可した場合のみ）
請負金額未入力（contract_amount 空/0）
原価率が100%以上（profit_rate が負、または total_cost ≧ contract_amount）
外注費二重計上注意（report_subcontract_cost と invoice 由来 subcontract の併存）
machine_details は工事別月別原価に未反映（恒常的な注記）
```

---

## 8. 月別原価の計算ルール

### 労務費

```text
attendance_details の labor_cost を、project_id + report_date(月 YYYY-MM) でSUM
```

注意：

- attendance_details 側で複数現場按分済み（`allocation_ratio` 反映後の `labor_cost`）なら、その値をそのままSUMする。
- `normal_mins` / `overtime_mins` を rawRows で生SUMしない（按分前の値であり原価ではない）。
- 労務費の金額は `labor_cost` を使う。
- 月キーは `report_date` の先頭7文字（YYYY-MM）。
- 現場なし日報（project_id 空）は工事別原価に含めない。

### 請求書費用

```text
project_cost_details の amount を、project_id + invoice_date(月 YYYY-MM) でSUM
```

費目別（`cost_category`）：

```text
material       → 材料費
subcontract    → 外注費
machine_lease  → 重機費（請求書由来のリース費）
other          → その他費用
```

- 月キーは `invoice_date` の先頭7文字（YYYY-MM）。
- `amount` は税込/税抜混在の生値（正規化しない）。合計は概算である旨を注記。

### 重機費

```text
machine_details.csv は台帳であり、日付・現場がないため、工事別月別原価には直接反映しない。
月別原価表の「重機費」列は、project_cost_details の cost_category=machine_lease（請求書由来）を用いる。
```

将来案：

```text
machine_locations など、現場・日付を持つ重機稼働データと統合して算出する。
ただし machine_locations が移動記録のみで稼働時間・日数を持たない場合は、
正確な原価化（稼働時間×単価等）には追加設計が必要。
```

### 月合計・累計

- 月合計 ＝ 労務費 ＋（材料費 ＋ 外注費 ＋ 重機費(machine_lease) ＋ その他費用）。
- 累計 ＝ 当月までの月合計の積み上げ。
- **含めない**：machine_details 由来の台帳リース月額・owned重機費（0円）、ダンプ費・警備費（project_cost_details に明細がないため。projects_summary 側にのみ集計されている）。
- 合計の定義を表に明記し、projects_summary.total_cost と一致しないことがある旨を注記する。

### 月別原価ビューの費目カバレッジ

月別原価ビューは、複数CSVから再集計できる費目だけを表示する。
そのため、`projects_summary.total_cost` と完全一致しないことがある。

| 費目            | 月別原価ビューでの扱い      | 参照CSV                    | 月キー          | 備考                                               |
| ------------- | ---------------- | ------------------------ | ------------ | ------------------------------------------------ |
| 労務費           | 含める              | attendance_details.csv   | report_date  | labor_cost は按分後値をSUMする                           |
| 材料費           | 含める              | project_cost_details.csv | invoice_date | cost_category = material                         |
| 外注費（請求書由来）    | 含める              | project_cost_details.csv | invoice_date | cost_category = subcontract                      |
| 重機リース等（請求書由来） | 含める              | project_cost_details.csv | invoice_date | cost_category = machine_lease                    |
| その他費用（請求書由来）  | 含める              | project_cost_details.csv | invoice_date | cost_category = other                            |
| ダンプ費          | MVPでは含めない        | —                        | —            | 日報由来で、現在の月別統合対象CSVには独立明細として含まれない                 |
| 警備費           | MVPでは含めない        | —                        | —            | 日報由来で、現在の月別統合対象CSVには独立明細として含まれない                 |
| 外注費（日報由来）     | MVPでは含めない、または要確認 | —                        | —            | projects_summary には含まれるが、月別統合ビューでは請求書由来外注費と混同しない |
| 重機台帳費         | 直接は含めない          | machine_details.csv      | —            | 台帳であり、工事ID・日付・現場を持たないため月別原価には直接足し込まない            |

#### 重要注記

```text
月別原価ビューの月別合計は、MVPでは「算出可能な月別明細の合計」であり、projects_summary.total_cost と同じ意味ではない。

projects_summary.total_cost には、ダンプ費・警備費・日報由来外注費・重機費等が含まれる可能性がある。

そのため、月別原価ビューの合計が projects_summary.total_cost より小さくなることは、設計上あり得る。

この差異はエラーではなく、費目カバレッジ差による確認事項として扱う。
```

---

## 9. 差異確認ルール

`projects_summary.csv`（既存RPCの最終集計値）と、明細CSVからローカル再集計した金額の差異を確認事項として表示する。

```text
労務費：
  projects_summary.labor_cost
  vs attendance_details 由来 labor_cost 合計（project_id 一致）

請求書系：
  projects_summary.material_cost            vs project_cost_details(material) 合計
  projects_summary.invoice_subcontract_cost vs project_cost_details(subcontract) 合計
  projects_summary.machine_cost             vs project_cost_details(machine_lease) 合計
  projects_summary.other_cost               vs project_cost_details(other) 合計

合計：
  projects_summary.total_cost
  vs 統合ビューでローカル算出できる合計（8章の月合計の総和）
```

注意：

- projects_summary は既存RPCの最終集計値、統合ビューはローカル再集計値。
- 差異が出た場合は **エラーではなく確認事項** として表示する。
- 差異の主因として想定されるもの（注記する）：
  - 税込/税抜の非正規化（amount 生値）。
  - 外注費の二重計上リスク（日報由来 `report_subcontract_cost` と請求書由来 `invoice_subcontract_cost` の合算）。`subcontract_cost_total` は両者合算であり、請求書明細のみの再集計とは一致しない。
  - ダンプ費・警備費は projects_summary にのみ含まれ、project_cost_details には明細がない。
  - 重機費は projects_summary では machine_lease 請求書のみ、台帳リース月額・owned は含まない。
  - pending 日報を含む（report_status で判別可能）。

---

## 10. 画面UI設計

既存の白ベース帳票UIに合わせる。

- 左メニューに「複数CSV統合」または「統合ビュー」を追加し、単体CSVビューと統合ビューを分ける。
- ファイル読込状況（種別・行数・必須/任意・不足）を画面上部に表示。
- 不足CSVを明示する。
- 工事名クリックで工事詳細に遷移（`project_id` をキーに）。
- 工事詳細内にタブまたはページ切替（月別原価 / 労務明細 / 請求書明細 / 重機情報）を用意。
- 印刷時は現在ページのみ印刷（既存の印刷CSS方針を踏襲）。
- CSV由来値は **`textContent` / DOM API で描画**（`innerHTML` に入れない）。
- Supabase接続なし、外部CDNなし、`file://` で動作。

---

## 11. 実装ステップ案

```text
Phase 2-4-7-0：複数CSV統合モード設計（完了）
Phase 2-4-7-1：複数CSV読み込みUIと multiState（完了）
Phase 2-4-7-2：projects_summary + attendance_details 統合（労務費）（完了）
Phase 2-4-7-3：projects_summary + project_cost_details 統合（請求書費用）（完了）
Phase 2-4-7-4：工事別月別原価ビュー（完了）
Phase 2-4-7-5：差異確認・確認リスト（完了）
Phase 2-4-7-6：印刷・UI調整（完了）
Phase 2-4-7-7：machine_details / machine_locations の将来設計
```

### 実装済み機能：Phase 2-4-7-2（projects_summary + attendance_details 統合）

実装コミット：`04d1c07 Add multi CSV labor integration`（対象：`local-viewers/csv-viewer.html`）

- `projects_summary.csv` と `attendance_details.csv` は `project_id` で結合する
- `attendance_details.labor_cost` を工事別・月別に集計する
- 月キーは `report_date` の `YYYY-MM`
- `labor_days` も同じ月キーで集計する
- 日報件数は `report_id` ユニーク数
- 明細件数は行数
- `normal_mins` / `overtime_mins` は工事別月別で生SUMしない
- `labor_cost` は既に按分後の値として扱う
- `project_id` 空行は集計対象外
- 追加された集計データ：
  - `multiState.summaries.laborByProjectId`
  - `multiState.summaries.laborMonthlyByProjectId`
- 表示内容：
  - ダッシュボードの労務費合計
  - 労務費対象工事件数
  - 労務費対象月数
  - 簡易工事一覧の労務費列
  - 工事別労務費詳細
  - 月別労務費
  - 労務明細
- 差額は参考表示であり、本格的な差異確認は Phase 2-4-7-5 で扱う
- `project_cost_details` 統合は未実装
- 月別原価総合計は未実装

#### 設計上の注意（Phase 2-4-7-2 時点）

```text
Phase 2-4-7-2 時点では、統合ビューで表示される月別金額は労務費のみである。
月別原価ビューの総合計ではない。
請求書費用、ダンプ費、警備費、日報由来外注費、重機費などはまだ含まれない。
```

### 実装済み機能：Phase 2-4-7-3（projects_summary + project_cost_details 統合）

実装コミット：`30aef20 Add multi CSV invoice integration`（対象：`local-viewers/csv-viewer.html`）

- `projects_summary.csv` と `project_cost_details.csv` は `project_id` で結合する
- `project_cost_details.amount` を工事別・月別に集計する
- 月キーは `invoice_date` の `YYYY-MM`
- `cost_category` 別に以下を集計する：
  - `material`
  - `subcontract`
  - `machine_lease`
  - `other`
- 未知の `cost_category` は請求書費用合計には含めるが、4費目には混ぜず `unknown` として扱う
- 請求書件数は `invoice_id` ユニーク数
- 明細件数は行数
- 業者数は `vendor_name` ユニーク数
- `project_id` 空行は集計対象外
- 追加された集計データ：
  - `multiState.summaries.invoiceByProjectId`
  - `multiState.summaries.invoiceMonthlyByProjectId`
  - `multiState.unknownCostCategories`
- 表示内容：
  - ダッシュボードの請求書費用合計
  - 請求書費用対象工事件数
  - 請求書費用対象月数
  - 業者数
  - 費目別合計
  - 簡易工事一覧の請求書費用列
  - 工事別原価詳細
  - 月別請求書費用
  - 請求書明細
- 労務費統合は既存どおり維持
- 月別原価総合計は未実装
- 差異確認は Phase 2-4-7-5 で扱う

#### 設計上の注意（Phase 2-4-7-3 時点）

```text
Phase 2-4-7-3 時点では、統合ビューで表示される金額は「労務費」と「請求書費用」を個別に確認できる段階である。

労務費＋請求書費用を合算した工事別月別原価ビューは、Phase 2-4-7-4 で実装する。

月別合計は、費目カバレッジ表に従い、算出可能な費目のみを対象にする。
```

### 実装済み機能：Phase 2-4-7-4（工事別月別原価ビュー）

実装コミット：`4fddc44 Add multi CSV monthly cost view`（対象：`local-viewers/csv-viewer.html`）

- 労務費と請求書費用を月キー `YYYY-MM` で統合する
- 労務費は `multiState.summaries.laborMonthlyByProjectId` を使う
- 請求書費用は `multiState.summaries.invoiceMonthlyByProjectId` を使う
- 統合結果は `multiState.summaries.costMonthlyByProjectId` に保持する
- 月別原価行の項目：
  - 月
  - 労務費
  - 材料費
  - 外注費
  - 重機リース等
  - その他費用
  - 未分類・確認対象
  - 月合計
  - 累計
- 月合計は、費目カバレッジ表に含まれる算出可能費目のみ
- 月合計の計算式：

```text
月合計 = 労務費 + 材料費 + 外注費 + 重機リース等 + その他費用
```

- `unknown cost_category` は月合計に含めず、未分類・確認対象として別表示
- 累計は月順に月合計を加算する
- ダッシュボードと簡易工事一覧に月別原価サマリーを追加
- 工事別詳細に工事別月別原価カードを追加
- `projects_summary.total_cost` との差異確認は未実装で、Phase 2-4-7-5 で扱う

#### 設計上の注意（Phase 2-4-7-4 時点）

```text
Phase 2-4-7-4 時点では、月別原価ビューは「算出可能な月別明細の合計」を表示する。

この月別原価合計は、projects_summary.total_cost と完全一致することを目的としない。

ダンプ費・警備費・日報由来外注費・machine_details由来の台帳費はMVPの月合計には含めない。

projects_summary.total_cost との差異は Phase 2-4-7-5 で確認事項として扱う。
```

### 実装済み機能：Phase 2-4-7-5（差異確認・確認リスト）

実装コミット：`f994c45 Add multi CSV reconciliation checks`（対象：`local-viewers/csv-viewer.html`）

- `projects_summary` とローカル再集計値の差異確認を実装
- 差異はエラーではなく確認事項として扱う
- 差異確認結果は `multiState.summaries.reconciliationByProjectId` に保持する
- 横断確認リストは `multiState.crossChecks` に保持する
- 差異確認対象：
  - 労務費
  - 材料費
  - 外注費
  - 重機費 / 重機リース等
  - その他費用
  - 合計原価
- 合計原価のローカル再集計値は、月別原価ビューの累計最終値を使う
- 月別原価ビューは算出可能費目のみの合計であり、`projects_summary.total_cost` との完全一致は目的としない
- 外注費は `projects_summary.invoice_subcontract_cost`（請求書由来）と比較する（`subcontract_cost_total` は日報由来を含むため不一致になりうる）
- 確認リストに含める内容：
  - 明細なし工事
  - `projects_summary` に存在しない `project_id`
  - `project_id` 空行
  - 請負金額未入力
  - 原価率100%以上
  - unknown cost_category
  - machine_details 工事別未反映
- 未読込CSVがある場合、大量の誤警告を出さず、未読込注記として扱う
- `machine_details` は工事別原価には直接結合しない
- ダッシュボード、簡易工事一覧、工事別詳細に確認事項表示を追加

#### 設計上の注意（Phase 2-4-7-5 時点）

```text
Phase 2-4-7-5 時点では、差異確認は自動修正ではなく確認支援である。

差異があること自体をエラーとは扱わない。

差異の主因は、税込/税抜の非正規化、外注費二重計上リスク、ダンプ費・警備費の未明細、重機費の台帳未反映、pending日報、unknown cost_category、CSV未読込などが想定される。

運用上は、確認リストを起点にCSV出力元・原価入力・費目分類を確認する。
```

### 実装済み機能：Phase 2-4-7-6（印刷・UI調整）

実装コミット：`2809a18 Improve multi CSV print layout`（対象：`local-viewers/csv-viewer.html`）

- 複数CSV統合ビューに印刷 / PDF保存用の表示調整を追加
- ホーム画面と工事別詳細画面に印刷ボタンを追加
- 印刷時専用ヘッダを追加
- `beforeprint` で印刷日時を設定
- 操作UIを印刷対象外にする
- 現在表示中の内容のみ印刷されるようにする
- 確認リスト、差異確認、工事別月別原価など横幅の広い表の印刷崩れを抑制
- 印刷時は白ベース、罫線、縮小フォント、折り返し、改ページ抑制を使って読みやすくする
- 差異確認の注記が印刷にも残るようにする
- `appendSummaryTable` を追加し、表前の注記が `renderSummaryTable` の `clear()` によって消える表示不具合を修正
- 集計ロジック、差異確認ロジック、確認リストのロジックは変更していない

#### 設計上の注意（Phase 2-4-7-6 時点）

```text
Phase 2-4-7-6 は表示・印刷の整備フェーズであり、原価集計ロジックは変更しない。

印刷結果は、社内確認・会計事務所共有・PDF保存のための確認資料として扱う。

印刷時も、差異はエラーではなく確認事項として表示する。
```

### 将来仕様：CSV出力パッケージZIP読込（Phase 2-4-8・設計のみ）

設計：[`docs/csv-export-package-spec.md`](csv-export-package-spec.md)（Phase 2-4-8-0 設計完了 / 実装未着手）。

- ZIP読込をメイン導線にする。
- 個別CSV読込は消さず、詳細・予備として残す。
- ZIP読込後は既存の複数CSV統合処理を再利用する。
- CSV種別は `manifest.json` の `files[].type` を優先して判定する。
- `manifest.json` がない場合はファイル名 → CSVヘッダー（既存 `detectCsvType`）判定にフォールバックする。
- 既存の労務費統合・請求書費用統合・月別原価・差異確認・確認リスト・印刷UIはそのまま利用する（壊さない）。
- ZIP読込対応・ZIPライブラリのローカル同梱は次フェーズ以降（2-4-8-2〜）で実装する。本フェーズ（2-4-8-1）まではライブラリ本体を追加しない設計のみ。
- ZIP読込の実装時は、ローカル同梱した JSZip（同梱済み：`vendor/jszip/jszip.min.js`・v3.10.1）を使う予定。**外部CDNは使わず、`file://` 動作を維持する。** ライブラリ方針は `docs/csv-export-package-spec.md` §13 に従う。
- ZIP読込UI・読み込みロジックは次フェーズ以降（2-4-8-5〜）で実装する。ZIP読込後は既存の複数CSV統合処理を再利用する。
- 管理コンソールのZIP出力UI（`docs/csv-export-package-spec.md` §14）は、ローカルCSVビューアーのZIP読込を前提としたパッケージ（4CSV＋manifest.json）を生成する。ビューアー側は `manifest.json` の `files[].type` をCSV種別判定に使う。
- **管理コンソール側のZIP出力は実装済み**（Phase 2-4-8-4・`admin-app.html`）。**ローカルCSVビューアー側のZIP読込は未実装。** 次フェーズ以降（2-4-8-5/2-4-8-6）で、管理コンソールのZIPを読み込むUIと処理を追加する。

#### ZIP読込UI設計（Phase 2-4-8-5・設計のみ）

設計：[`docs/csv-export-package-spec.md`](csv-export-package-spec.md) §16。

- ZIP読込UIをメイン導線として複数CSV統合モード上部に追加する設計。
- 個別CSV読込は削除せず、詳細・予備として残す。
- ZIP内の `manifest.json` を読み、`files[].type` でCSV種別を判定する。
- manifestがない場合はファイル名 → CSVヘッダー（既存 `detectCsvType`）でフォールバックする。
- ZIP読込後は既存の `multiState` と各種集計関数・描画関数を再利用する（集計ロジック・CSV列仕様は変更しない）。
- パッケージ情報（ファイル名・出力日時・対象期間・format_version・system・ファイル一覧/行数）を統合ビューに表示する。
- ZIP読込ボタン・ファイル選択は印刷対象外、パッケージ情報は印刷対象にする。
- 実装は次フェーズ以降（2-4-8-6〜）。本フェーズでは設計のみ。

### 実装済み機能：Phase 2-4-8-6（CSV出力パッケージZIP読込実装）

実装コミット：`c867027 Add viewer ZIP package import`（対象：`local-viewers/csv-viewer.html`）

- ZIP読込実装済み。
- JSZipは `../vendor/jszip/jszip.min.js` をローカル参照（外部CDN不使用・`file://` 維持）。
- ZIP読込カードを複数CSV統合モード上部に追加。
- 個別CSV読込は詳細・予備として残す。
- `multiState.package` にパッケージ情報（ファイル名・出力日時・対象期間・format_version・system・manifest読込状態・ファイル一覧・警告/エラー）を保持。
- CSV種別判定は manifest優先 → ファイル名 → CSVヘッダー（既存 `detectCsvType`）の順。
- `loadMultiSlotFromText` によりZIP内CSVを既存スロットへ流し込む（既存 `loadMultiSlot` は非finalizeのコア `loadMultiSlotFromText` と薄いラッパにリファクタ）。
- ZIP読込時は既存の複数CSV状態を一旦クリアし、ZIP内CSVで置換（古いCSVとの混在防止）。
- 全CSV流し込み後に既存 `finalizeMulti()` を1回実行。
- 既存の労務費統合・請求書費用統合・月別原価・差異確認・確認リスト・印刷UIを再利用。
- CSV列仕様や集計ロジックは変更しない。
- CSV由来値は `textContent` / DOM API で描画。inline `onclick` は追加なし。Supabase接続情報・service_role は追加なし。
- 印刷時はパッケージ情報を残し、ZIPファイル選択・読込・クリアボタンは印刷対象外。

#### 設計上の注意（Phase 2-4-8-6 時点）

- ZIP読込は、既存の複数CSV統合処理への入力導線であり、集計ロジックそのものは変更しない。
- CSV列仕様は個別CSV読込と同一。
- ZIP読込後も個別CSV読込を予備導線として残す。
- `manifest.json` はCSV種別判定とパッケージ情報表示に使うが、manifestがない場合もファイル名・CSVヘッダー判定で可能な範囲で読み込む。

### 実ZIP結合確認済み（Phase 2-4-8-8）

- 管理コンソール（本番admin）で出力した実ZIPを、ローカルCSVビューアーで読込成功。
- 実ZIP：`okaigumi-csv-export_202606-202606_20260610-1446.zip`（2026-06単月）。
- manifest優先判定で4CSV（projects_summary / attendance_details / project_cost_details / machine_details）を正しく割当成功。
- manifest rows と実CSV行数が全て一致することを実確認。
- 0行CSV（project_cost_details）は、エラーではなく警告・確認事項として扱えることを実確認。
- 複数CSV統合ビュー反映・工事詳細（差異確認・月別原価・労務明細）・印刷/PDF確認済み。
- 請求書明細あり期間（例：2026-04〜2026-06）での追加確認は任意の今後候補。

### 運用手順（Phase 2-4-8-9）

- ローカルCSVビューアーの運用手順は [`docs/csv-export-operation-guide.md`](csv-export-operation-guide.md) を参照。
- ZIP読込を通常運用の推奨導線とする。
- 個別CSV読込は検証・トラブル対応用に残す。
- 配布時はJSZipとの相対パス維持が必要（`local-viewers/` と `vendor/jszip/` の相対位置）。
- 現時点では pCloud と外付けHDDを前提に配布・保管し、UGREEN NASync導入後はNASにも配布コピーを保管する（NASは現時点では未導入・後日購入予定）。

### UX改善方針（Phase 2-4-9-0）

設計：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md)

- 複数CSV統合ビューは、今後メイン導線ではなく「月次チェック・差異確認」として扱う。
- ZIP読込後は、まず帳票選択メニューを表示する設計に修正する。
- 単体CSVビューの分かりやすさを活かし、projects_summary / attendance_details / project_cost_details / machine_details の各画面へ遷移できるようにする。
- 既存の複数CSV統合機能は、工事別突き合わせ・差異確認・確認リスト用として残す。
- 個別CSV読込は詳細・トラブル対応用として折りたたむ。
- 本方針は Phase 2-4-9-0 の設計のみ。集計ロジック・CSV列仕様は変更しない。実装は次フェーズ以降。

### ZIP読込後メニュー実装済み（Phase 2-4-9-1）

実装コミット：`08be5ac Add CSV ZIP report selection menu`

- ZIP読込後の初期表示は、既存統合ビューではなく帳票選択メニューになった。
- 既存統合ビューは「月次チェック・差異確認」として、メニューから開く構成になった。
- 現時点では、工事一覧・原価概要／日報・労務費／請求書費用／重機台帳カードは準備中表示。
- 月次チェック・差異確認は既存の確認リスト・差異確認・工事詳細を利用する。
- 次フェーズ（2-4-9-2）でZIP内CSVを単体CSVビューへ接続する。

### ZIP由来単体ビュー接続方針（Phase 2-4-9-2-a・設計のみ）

設計：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §14。

```text
ZIP由来単体ビュー接続方針：
- ZIP読込後の multiState.rows を利用して、既存単体CSVビューに接続する
- handleText を分離し、単体file読込とZIP由来単体表示で共通のstate構築＋描画処理を使う
- multiState は保持したまま、ZIP由来単体ビュー表示時のみ state を該当CSVで上書きする
- ZIP由来単体ビューの戻り先は帳票選択メニュー
- warnings/errors の引き継ぎを明確にし、単体file読込とZIP由来表示の警告差分を最小化する
```

本方針は Phase 2-4-9-2-a の docs 設計のみ。集計ロジック・CSV列仕様は変更しない。実装は次フェーズ（2-4-9-2-b〜）。

### handleText分離 実装済み（Phase 2-4-9-2-b）

実装コミット：`64c699b Split handleText into parse and render phases`。詳細は [`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §15。

- ZIP由来単体ビュー接続の前提となる handleText 分離を実装した（`parseSingleCsvText` / `buildSingleStateAndRender` を追加）。
- 現時点では帳票カード接続は未実装で、4帳票カードは準備中表示のまま。
- 次フェーズ（2-4-9-2-c）で projects_summary から接続する。

### projects_summary ZIP由来単体ビュー接続 実装済み（Phase 2-4-9-2-c）

実装コミット：`f2b1b1c Connect ZIP projects summary to single CSV viewer`。詳細は [`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §16。

- 「工事一覧・原価概要」カードから ZIP内 `projects_summary.csv` を単体CSVビュー形式で表示できるようにした。
- `attendance_details` / `project_cost_details` / `machine_details` は引き続き準備中表示。

---

## 12. MVP範囲

### MVPでやる

```text
複数CSV読込
工事一覧
工事詳細
工事別月別原価
労務費月別
請求書費用月別
確認リスト
```

### MVPではやらない

```text
Supabase接続
DB更新
CSVの自動保存
PDF出力
Excel出力
重機の正確な月別・現場別原価算出
会計連携
完全な差異解消
```

### 対象工事の範囲

MVPでは、`projects_summary.csv` に含まれる全工事を対象とする。
完了工事だけでなく、進行中工事も表示対象に含める。

理由：

- 進行中工事の原価累計を確認できる方が実務上有用
- 完了後の確認だけでなく、途中段階で原価の偏りや未入力を発見できる
- ローカルCSVビューアーは確認・分析用であり、会計確定値だけを扱うものではない

注意：

- 進行中工事は請負金額が未入力または未確定の場合がある
- 進行中工事では原価率・粗利・差異判定は参考値扱いにする
- 請負金額が0または空の場合、原価率は `—` 表示にする
- 将来的には、完了工事のみ / 進行中含む / 年度別 などのフィルタを追加できるようにする

---

## 13. 未確定事項

```text
- 各CSVで共通する工事ID列名の最終確認
  （現時点では projects_summary / attendance_details / project_cost_details の
   project_id が共通の sites.id である前提。実データでの一致を実装前に再確認する）
- site_name 代替結合を許容するか（既定はOFF。許容する場合の警告・確認リスト記録方法）
- machine_locations を統合対象にするか
- 重機費をどのデータから月別・現場別に出すか
  （請求書由来 machine_lease のみで足りるか、台帳/稼働データ統合が必要か）
- 請求書の税込/税抜扱い（正規化しないままの差異表示で運用上問題ないか）
- 外注費二重計上の表示方法（report_ と invoice_ をどう並記・警告するか）
- 統合モードと単体モードのUI上の切替方式（排他/併存）
```

確定済み（旧・未確定事項からの更新）：

```text
対象工事範囲：MVPでは進行中工事も含む方針に確定。将来、完了工事のみ表示するフィルタを追加する余地あり。
```
