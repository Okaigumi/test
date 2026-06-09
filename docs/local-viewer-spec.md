# ローカルHTML CSVビューア仕様

## 1. 目的

- `admin-app.html` で出力したCSVをローカルHTMLで読み込む
- Supabase接続なし
- APIキーなし
- DB変更なし
- `file://` で動くオフラインビューア
- 社内の過去工事・出勤簿・原価確認を、CSVバックアップから見やすく確認できるようにする

## 2. 対象CSV

対象は以下4種類。

- `projects_summary.csv`
- `attendance_details.csv`
- `project_cost_details.csv`
- `machine_details.csv`

初期重点は `attendance_details.csv` の出勤簿表示。

## 3. 配置方針

- ビューア本体予定：`local-viewers/csv-viewer.html`
- Git管理対象
- Vercel公開対象外予定
- 実装時に `.vercelignore` へ `local-viewers/` を追加する
- 今回のPhase 2-4-0では `.vercelignore` はまだ変更しない

## 4. CSVパース方針

- 外部ライブラリなし
- 自前RFC4180ステートマシンパーサ
- UTF-8 BOM対応
- CRLF / LF対応
- ダブルクォート対応
- カンマ入り文字列対応
- 改行入り文字列対応
- ヘッダ行から列名マップを作る
- 列順には依存しない
- Excelで保存し直したShift_JIS等のCSVは原則非対応
- 文字化け検知として `�` が含まれる場合は警告する
- 空CSV、ヘッダのみCSVはエラーではなく「データ0件」として正常表示する

## 5. CSV種別判定方針

1列目だけでは判定しない。

CSV種別判定は、ヘッダに含まれる **必須列集合** で行う。

### attendance_details 必須列

```text
report_id
report_date
employee_id
employee_name
normal_mins
overtime_mins
labor_days
labor_cost
report_status
```

### projects_summary 必須列

```text
project_id
site_name
fiscal_year
contract_amount
total_cost
gross_profit
profit_rate
```

### project_cost_details 必須列

```text
invoice_id
invoice_date
project_id
site_name
cost_category
vendor_name
amount
status
```

### machine_details 必須列

```text
machine_id
machine_name
ownership
lease_monthly
owned_cost
is_active
```

判定ルール：

- 期待する必須列集合をすべて含むCSV種別を採用する
- 複数種別に一致した場合は警告し、より一致列数の多いものを優先する
- どの種別にも一致しない場合は「未知のCSV形式です」と明示エラーを表示する
- 列順には依存しない

## 6. attendance_details.csv の重要な集計ルール

必ず守る。

- `normal_mins` は日報全体値であり、複数現場時に同じ値が複数行へ複製される
- `overtime_mins` も日報全体値であり、複数現場時に複製される
- したがって `normal_mins` / `overtime_mins` を生行でSUMしてはいけない
- 時間集計は必ず `report_id` 単位にピボットしてから行う
- `labor_days` は按分後の値なのでSUM可
- `labor_cost` も按分後の値なのでSUM可
- `allocation_ratio` は按分比率であり、表示・検証用として扱う
- `start_time` / `end_time` / `work_type` / `memo` / `report_status` はreport単位属性として扱う

## 7. 出勤日数・稼働件数の定義

実データ確認結果：

- 同一従業員・同一日に複数 report_id があるか確認済み
- 結果：0行
- 現時点では「1人1日1日報」の運用が成立している

ビューア上の定義：

- 出勤日数：従業員ごとの `DISTINCT report_date`
- 稼働件数：`DISTINCT report_id`
- 通常運用では両者は一致する想定
- ただし将来の例外に備え、出勤日数と稼働件数は別々に表示する

## 8. 内部データモデル

### Layer 1: rawRows

CSVそのままの行。

- 1行 = report × 現場
- 現場別 `labor_days` / `labor_cost` 集計に使う
- `normal_mins` / `overtime_mins` の生行SUMは禁止

### Layer 2: reports

`report_id` でピボットした日報単位レコード。

各 `report_id` について：

- `report_date`
- `employee_id`
- `employee_name`
- `work_type`
- `start_time`
- `end_time`
- `normal_mins`
- `overtime_mins`
- `report_status`
- `memo`

などの共有属性は1回だけ採用する。

加えて：

- `site_names`：同一report_id内の `site_name` を集約
- `labor_days_total`：同一report_id内の `labor_days` SUM
- `labor_cost_total`：同一report_id内の `labor_cost` SUM

を持つ。

月別・従業員別サマリーは Layer 2 を使う。

## 9. report_id ピボット時の不一致検知

同一 `report_id` 内で、本来一致すべき共有属性が行ごとに違う場合は警告する。

対象候補：

- `report_date`
- `employee_id`
- `employee_name`
- `normal_mins`
- `overtime_mins`
- `start_time`
- `end_time`
- `work_type`
- `report_status`

不一致があっても即停止はせず、画面に警告を表示する。
集計では1行目の値を採用するが、警告によってCSV生成側やデータ異常を発見できるようにする。

## 10. 画面構成案

初期MVP：

- CSV読み込みエリア
- 読み込み結果サマリー
- CSV種別表示
- 行数表示
- report件数表示
- 対象期間表示
- 警告/エラー表示
- 生テーブル表示

後続：

- 月別サマリー
- 従業員別サマリー
- 従業員別日別明細
- 現場別内訳
- 対象月フィルタ
- 従業員フィルタ
- 現場フィルタ
- report_statusフィルタ
- 印刷ボタン
- 印刷CSS

## 11. 実装フェーズ

### Phase 2-4-0：設計

- `docs/local-viewer-spec.md` 作成
- `docs/roadmap.md` に Phase 2-4 追加

### Phase 2-4-1：CSV読込・パース・種別判定・生テーブル

- `local-viewers/csv-viewer.html` 新規作成
- `.vercelignore` に `local-viewers/` を追加
- ファイル選択でCSV読込
- 自前CSVパーサ
- 必須列集合によるCSV種別判定
- 未知CSV形式の明示エラー
- 生テーブル表示
- 実エクスポートCSVで行数一致確認

### Phase 2-4-2：report_idピボット・月別/従業員別サマリー

- attendance_details の report_id ピボット
- normal_mins / overtime_mins の二重計上防止
- 出勤日数と稼働件数を別々に表示
- 月別サマリー
- 従業員別サマリー
- ピボット時の共有属性不一致警告

### Phase 2-4-3：従業員別日別明細・現場別内訳

- 従業員別の日別出勤簿
- site_names結合表示
- 現場別 labor_days / labor_cost 内訳
- 現場別 labor_cost SUM が全体と一致するか確認

### Phase 2-4-4：フィルタ・印刷CSS

- 対象月
- 従業員
- 現場
- report_status
- 印刷ボタン
- 印刷用CSS

### Phase 2-4-5：他CSV対応

- projects_summary
- project_cost_details
- machine_details
- まずは素テーブル表示
- 必要に応じて簡易サマリー追加

## 12. セキュリティ・安全性

- CSV値を `innerHTML` に直接入れない
- `textContent` またはHTMLエスケープを使う
- memo等にHTMLやJavaScript文字列が含まれていても実行されないようにする
- Supabase接続なし
- APIキーなし
- ローカルファイルはユーザーが選んだものだけ読む
- Vercel公開対象外にする予定

## 13. 完了条件

### Phase 2-4-1

- 実エクスポートCSVを読める
- 行数が一致する
- CSV種別が正しく判定される
- 未知CSV形式で明示エラーが出る
- 生テーブルが表示される
- CSV値がHTMLとして実行されない

### Phase 2-4-2

- `normal_mins` / `overtime_mins` の二重計上がない
- report_id単位にピボットできる
- 出勤日数と稼働件数を別々に表示できる
- 月別・従業員別サマリーが表示できる
- 同一report_id内の共有属性不一致を警告できる

### Phase 2-4-3

- 従業員別日別明細が表示できる
- 現場別内訳が表示できる
- 現場別 `labor_cost` SUM が全体と一致する

### Phase 2-4-4

- フィルタが機能する
- 印刷で表が崩れない

### Phase 2-4-5

- 4CSV種別が表示可能

## 14. 制約

- Excelで保存し直したShift_JIS CSVは原則非対応
- CSV列の増減には、必須列集合で可能な範囲で対応
- 大量データ時の仮想スクロールはMVPでは未対応
- フロント専用作業のため `docs/db-migrations.md` には記録しない

## 15. 現在の実装仕様（Phase 2-4-3時点）

コミット：`c8dcb0c Add paged print-friendly CSV viewer`

### 構成

- 単一HTML構成：`local-viewers/csv-viewer.html`
- Vercel公開対象外：`.vercelignore` で `local-viewers/` を除外
- Supabase接続なし、外部CDNなし、APIキーなし、`file://` で動く

### UI

- 白ベース帳票UI
- 印刷対応（印刷CSS）
- ページ切替型UI

### attendance_details のページ構成

- ダッシュボード
- 月別サマリー
- 従業員別サマリー
- 従業員別 月別出勤簿
- 全体出勤簿
- 生データ
- 警告・エラー

### 遷移・集計

- 従業員別サマリーの従業員名クリックで、対象従業員の月別出勤簿へ遷移
- `normal_mins` / `overtime_mins` は report_id 単位ピボットで二重計上を防止
- `labor_days` / `labor_cost` は按分後値のSUM

### 他CSVの扱い

- 他CSV（projects_summary / project_cost_details / machine_details）は現時点では生データ確認中心
- 今後、CSV種別ごとに不要ボタンを非表示にする予定
- 今後、projects_summary / project_cost_details / machine_details の専用ビューアを整備予定
- `projects_summary.csv` の専用ビューは Phase 2-4-4 で初期実装済み（下記「16. projects_summary.csv 専用ビュー仕様」参照）
- `project_cost_details.csv` / `machine_details.csv` は引き続き生データ確認中心

## 16. projects_summary.csv 専用ビュー仕様（Phase 2-4-4時点）

コミット：`27b18b3 Add projects summary CSV viewer pages`

### 専用ページ

`projects_summary.csv` 読込時は左メニューに以下を表示する。

```text
ダッシュボード
工事一覧
工事詳細
年度別集計
発注者別集計
工事分類別集計
生データ
警告・エラー
```

### 工事一覧

表示列：

```text
工事名
発注者
発注者区分
工事分類
年度
請負金額
合計原価
粗利
原価率
労務費
重機費
材料費
外注費
その他費用
警告
```

仕様：

- 工事名はクリック可能
- `project_id` を優先して工事詳細を特定
- `project_id` がない場合のみ工事名で代替
- 原価率は `total_cost / contract_amount * 100` で算出
- `profit_rate` は利益率であり、原価率には使用しない
- `warnings` 列は存在しないため `—` 表示

### 工事詳細

表示内容：

```text
工事基本情報
金額サマリー
費目別内訳
警告・メモ
```

金額サマリー：

```text
請負金額
合計原価
粗利
原価率
```

費目別内訳：

```text
労務費
重機費
材料費
外注費
ダンプ費
警備費
その他費用
```

注記：

- 原価率は概算参考値
- 重機費・税区分・外注費集計の影響で実際と異なる場合がある
- `projects_summary.csv` には工事ごとの `warnings / notes` 列が存在しない
- 月別費用ビューは複数CSV統合モードで実装予定

### 年度別・発注者別・工事分類別集計

仕様：

- グループごとに請負金額・合計原価・各費目をSUM
- 原価率は、個別工事の単純平均ではなく、グループ合計後に `合計原価 ÷ 請負金額合計 × 100` で算出
- 請負金額が0または空の場合は原価率を `—` 表示
- 発注者名・工事分類が空の場合は `(未設定)` に寄せる

### 検証済み事項

- projects_summary 読込OK
- 工事一覧OK
- 工事名クリックOK
- 工事詳細OK
- 原価率注記OK
- 年度別/発注者別/工事分類別集計OK
- 生データOK
- 警告・エラーOK
- NaN表示なし
- Console重大エラーなし
- 集計突合で合計原価が一致（全体・年度別・発注者別・工事分類別がすべて 770000）
- project_id 欠落なし
- contract_amount 未入力または0が10件あり、請負金額・粗利・原価率が `—` になるのは正常

## 17. project_cost_details.csv 専用ビュー仕様（Phase 2-4-5時点）

コミット：`f4eace0 Add project cost details CSV viewer pages`

### 専用ページ

`project_cost_details.csv` 読込時は左メニューに以下を表示する。

```text
ダッシュボード
請求書一覧
業者別集計
工事別集計
月別集計
費目別集計
確認リスト
生データ
警告・エラー
```

### 列マッピング

```text
amount         金額
invoice_date   請求日・月別集計キー
vendor_name    業者名
site_name      工事名
cost_category  費目
description    摘要
status         状態
memo           メモ
```

費目表示の日本語化：`subcontract`→外注費 / `material`→材料費 / `machine_lease`→重機リース / `other`→その他。
状態表示の日本語化：`confirmed`→確認済み / `posted`→計上済み。

### 請求書一覧

表示列：

```text
請求日
業者名
工事名
費目
摘要
金額
状態
メモ
```

仕様：

- `invoice_date` 昇順、`vendor_name` 昇順で表示
- 金額は右寄せ・カンマ付き
- 空値は `—` 表示
- CSV値は `textContent` / DOM API で描画

### 業者別集計

表示列：

```text
業者名
件数
金額合計
主な費目
主な工事
```

仕様：

- `vendor_name` でグループ化
- 空は `(未設定)`
- `amount` をSUM
- 主な費目・主な工事はユニーク値を最大数件表示

### 工事別集計

表示列：

```text
工事名
件数
金額合計
主な業者
主な費目
```

仕様：

- `site_name` でグループ化
- 空は `(現場なし)`
- `amount` をSUM

### 月別集計

表示列：

```text
月
件数
金額合計
主な業者
主な費目
```

仕様：

- `invoice_date` の `YYYY-MM` でグループ化
- 日付なしは `(日付なし)`
- `amount` をSUM

### 費目別集計

表示列：

```text
費目
件数
金額合計
主な業者
主な工事
```

仕様：

- `cost_category` でグループ化
- 空は `(未設定)`
- `amount` をSUM
- 表示は日本語化する

### 確認リスト

確認項目：

```text
現場名なし
業者名なし
費目なし
金額0円または空
日付なし
同じ業者・同じ日付・同じ金額の重複疑い
外注費の二重計上注意
```

仕様：

- 重複疑いは `vendor_name + invoice_date + amount` の組み合わせで検出
- 対象行はCSVデータ行番号で表示
- 外注費の二重計上注意は、`cost_category = subcontract` の行がある場合に表示
- 外注費注意はエラーではなく確認注意

### 検証済み事項

- `project_cost_details.csv` 読込OK
- 専用メニュー表示OK
- 請求書一覧OK
- 業者別/工事別/月別/費目別集計OK
- 確認リストOK
- 生データOK
- 警告・エラーOK
- NaN表示なし
- Console重大エラーなし
- 確認時点のCSVはデータ行数0
- allAmount / vendor / project / month / category の各合計はすべて0で一致
- 実データ入りCSVでの再検証は今後必要

## 18. machine_details.csv 専用ビュー仕様（Phase 2-4-6時点）

コミット：`4ac86e6 Add machine details CSV viewer pages`

`machine_details.csv` は **重機台帳（1行＝1重機）** であり、稼働明細ではない。
現場別・月別の重機稼働や重機原価は、このCSV単体では正確に算出できない。

### 専用ページ

`machine_details.csv` 読込時は左メニューに以下を表示する。

```text
ダッシュボード
重機一覧
重機別集計
月別集計
現場別集計
確認リスト
生データ
警告・エラー
```

### 列マッピング

```text
machine_id      重機ID
machine_name    重機名
ownership       所有/リース区分
is_active       状態
lease_monthly   リース月額
owned_cost      所有原価
owner_company   所有会社
lease_company   リース会社
lease_start     リース開始
lease_end       リース終了
```

表示の日本語化：`lease`→リース / `owned`→自社保有 / `true`→有効 / `false`→無効。

存在しない列（無理に算出せず `—` または注記表示とする）：

```text
稼働日
工事名/現場名
稼働時間
稼働日数
機種
管理番号
メモ
```

### 重機一覧

表示内容：

```text
日付
重機名
機種
管理番号
工事名
稼働時間/日数
重機費
区分
状態
メモ
所有会社
リース会社
リース開始
リース終了
```

仕様：

- 実在する列は値を表示
- 存在しない列は `—` 表示
- 重機費は、リースなら `lease_monthly`、自社保有なら `owned_cost`
- 金額は右寄せ・カンマ付き
- CSV値は `textContent` / DOM API で描画

### 重機別集計

仕様：

- `machine_id` を優先してグループ化
- `machine_id` がない場合は `machine_name` で代替
- 件数と重機費合計を表示
- 稼働日数、稼働時間、主な現場、最終稼働日は該当列がないため `—`
- 重機費合計はリース月額/所有原価の台帳値合計

### 月別集計

仕様：

- 稼働日列がないため、月別集計は不可
- `lease_start` / `lease_end` はリース期間であり、稼働日ではないため月別稼働集計には使わない
- ページには「日付列がないため月別集計はできません」と注記表示

### 現場別集計

仕様：

- 工事名/現場名列がないため、現場別集計は不可
- ページには「工事名・現場の列がないため現場別集計はできません」と注記表示

### 確認リスト

確認項目：

```text
重機名なし
重機費0円または空
同一 machine_id / 重機名の重複疑い
現場名なし：列なしのため判定対象外
日付なし：列なしのため判定対象外
長期間稼働なし：稼働日列がないため判定不可
```

仕様：

- 重複疑いは同一 `machine_id` / 重機名が複数行ある場合に表示
- 対象行はCSVデータ行番号で表示
- `owned_cost` はMVPでは0になり得るため、重機費0円は必ずしも異常ではない旨を注記
- 長期間稼働なしは、最終稼働日が分かる列がないため判定不可

### 検証済み事項

- `machine_details.csv` 読込OK
- 専用メニュー表示OK
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
- projects_summary / project_cost_details / attendance_details の回帰確認OK
