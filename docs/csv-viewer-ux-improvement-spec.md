# CSVビューアーUX改善仕様

> 関連設計：
> - 複数CSV統合ビュー：[`docs/local-viewer-multi-csv-spec.md`](local-viewer-multi-csv-spec.md)
> - ローカルビューアー基本設計：[`docs/local-viewer-spec.md`](local-viewer-spec.md)
> - 出力パッケージ仕様：[`docs/csv-export-package-spec.md`](csv-export-package-spec.md)
> - 運用手順：[`docs/csv-export-operation-guide.md`](csv-export-operation-guide.md)
>
> 本書は Phase 2-4-9-0（画面構成・ページ遷移設計）の設計ドキュメント。**実装はまだ行わない。** `local-viewers/csv-viewer.html` の HTML/JS/CSS は変更しない。

## 1. 現状の問題

- ZIP読込後に、いきなり複数CSV統合ビューへ入るため情報量が多い。
- 単体CSVビューは分かりやすいが、ZIP読込後の導線では活かされていない。
- 複数CSV統合ビューは、通常の帳票確認画面ではなく、工事別の突き合わせ・差異確認用である。
- 個別CSV読込とZIP読込の役割が画面上で分かりにくい。
- 事務担当者が「どの画面を見ればよいか」を判断しづらい。
- 確認事項・差異確認が最初から多く見えると、エラーのように感じやすい。

## 2. 新しい結論

最重要方針：

```text
ZIP読込
↓
帳票選択
↓
単体CSVと同じ見やすい画面
↓
必要な時だけ月次チェック・差異確認
```

説明：

- ZIPは4CSVをまとめて読み込む入口。
- ZIP読込後、まず帳票選択メニューを表示する。
- 各帳票は、既存の単体CSVビューを再利用して表示する。
- 複数CSV統合ビューは、メイン画面ではなく「月次チェック・差異確認」として奥に下げる。
- 個別CSV読込は、詳細・トラブル対応用として折りたたみにする。

## 3. 画面構成

```text
CSV確認ビューアー
├ 1. ZIP読込ホーム
├ 2. 帳票選択メニュー
│  ├ 工事一覧・原価概要
│  ├ 日報・労務費
│  ├ 請求書費用
│  ├ 重機台帳
│  └ 月次チェック・差異確認
├ 3. 各帳票画面
│  ├ projects_summary 単体ビュー
│  ├ attendance_details 単体ビュー
│  ├ project_cost_details 単体ビュー
│  └ machine_details 単体ビュー
└ 4. 詳細・トラブル対応
   └ 個別CSV読込
```

## 4. ページ遷移

```text
起動
 ↓
ZIP読込ホーム
 ↓ ZIPを選択して読込
帳票選択メニュー
 ├ 工事一覧・原価概要を見る
 │   ↓
 │  projects_summary 単体ビュー
 │
 ├ 日報・労務費を見る
 │   ↓
 │  attendance_details 単体ビュー
 │
 ├ 請求書費用を見る
 │   ↓
 │  project_cost_details 単体ビュー
 │
 ├ 重機台帳を見る
 │   ↓
 │  machine_details 単体ビュー
 │
 └ 月次チェック・差異確認を見る
     ↓
    工事別まとめ確認ビュー
```

戻る導線：

```text
各帳票画面
 ↓
帳票選択メニューに戻る

工事詳細画面
 ↓
月次チェック・差異確認に戻る
 ↓
帳票選択メニューに戻る
```

## 5. ZIP読込ホーム

最初の画面は、ZIP読込に集中した画面にする。

表示案：

```text
社内業務システム CSV確認ビューアー

① 管理コンソールでCSV一式ZIPを出力
② この画面でZIPを読み込む
③ 見たい帳票を選ぶ
④ 必要に応じてPDF保存

[ ZIPファイルを選択 ]
選択中：未選択

[ CSV一式ZIPを読み込む ]

保存先の目安：
P:\05_社内業務システム\01_CSV出力ZIP原本\2026\2026-06
```

個別CSV読込は最初から大きく見せず、折りたたみ表示にする。

```text
▼ 詳細・トラブル対応用：個別CSVを読み込む
```

## 6. ZIP読込後の帳票選択メニュー

ZIP読込後、いきなり統合ビューを表示せず、まず帳票選択メニューを出す。

表示案：

```text
CSV一式ZIPを読み込みました

対象期間：2026年6月分
出力日時：2026-06-10 14:46
ZIPファイル：okaigumi-csv-export_202606-202606_20260610-1446.zip

どの画面を見ますか？
```

カード構成：

```text
[ 工事一覧・原価概要 ]
projects_summary.csv
工事件数：10件
請負金額・原価・利益率を確認します。
[ 開く ]

[ 日報・労務費 ]
attendance_details.csv
労務明細：41件
社員別・工事別・月別の労務費を確認します。
[ 開く ]

[ 請求書費用 ]
project_cost_details.csv
請求書明細：0件
材料費・外注費・重機リース等を確認します。
[ 開く ]

[ 重機台帳 ]
machine_details.csv
重機台帳：22件
所有・リース・月額・稼働状態を確認します。
[ 開く ]

[ 月次チェック・差異確認 ]
4CSVを工事別にまとめて確認します。
差異確認・確認リスト・月別原価を見ます。
[ 開く ]
```

## 7. 各帳票画面

ZIPから読み込んだCSVを、既存の単体CSVビューと同じ構成で表示する。

### 工事一覧・原価概要

元データ：

```text
projects_summary.csv
```

画面表示：

```text
工事一覧・原価概要

読込元：ZIP内 projects_summary.csv
対象期間：2026年6月分

[ 帳票選択に戻る ] [ PDF保存 ]
```

表示内容：

```text
工事一覧
年度別集計
発注者別集計
工事分類別集計
工事詳細
```

### 日報・労務費

元データ：

```text
attendance_details.csv
```

画面表示：

```text
日報・労務費

読込元：ZIP内 attendance_details.csv
対象期間：2026年6月分

[ 帳票選択に戻る ] [ PDF保存 ]
```

表示内容：

```text
月別労務費
社員別労務費
工事別労務費
日報明細
社員別詳細
```

### 請求書費用

元データ：

```text
project_cost_details.csv
```

画面表示：

```text
請求書費用

読込元：ZIP内 project_cost_details.csv
対象期間：2026年6月分

[ 帳票選択に戻る ] [ PDF保存 ]
```

0行の場合：

```text
この期間の請求書明細は0件です。
対象期間に請求書登録がない場合は正常です。
```

表示内容：

```text
請求書一覧
業者別集計
工事別集計
月別集計
費目別集計
確認リスト
```

### 重機台帳

元データ：

```text
machine_details.csv
```

画面表示：

```text
重機台帳

読込元：ZIP内 machine_details.csv
対象期間：2026年6月分

[ 帳票選択に戻る ] [ PDF保存 ]
```

表示内容：

```text
重機一覧
所有・リース別集計
月額リース費
所有機械費
稼働中/停止中
重複疑い
```

## 8. 月次チェック・差異確認

現在の「複数CSV統合ビュー」は削除せず、名称と位置づけを変更する。

```text
旧：複数CSV統合ビュー
新：月次チェック・差異確認
```

説明文：

```text
この画面は、4CSVを工事別に突き合わせて、
差異・未登録・確認事項を探すための確認画面です。
通常の帳票確認は、各帳票画面を使用してください。
```

表示内容：

```text
月次確認サマリー
確認リスト
差異確認
工事別一覧
工事別詳細
月別原価
労務費とprojects_summaryの差異
請求書費用の有無
```

## 9. 上部ナビゲーション

ZIP読込後は、全画面の上にナビゲーションを出す設計にする。

```text
[ 帳票選択 ]
[ 工事一覧 ]
[ 日報・労務費 ]
[ 請求書費用 ]
[ 重機台帳 ]
[ 月次チェック ]
[ ZIPを読み直す ]
```

## 10. 個別CSV読込の扱い

個別CSV読込は削除しない。
ただし、通常運用では目立たせない。

表示案：

```text
▼ 詳細・トラブル対応用：個別CSV読込
```

説明文：

```text
通常運用ではZIP読込を使用してください。
個別CSV読込は、検証・トラブル対応・一部CSVのみ確認したい場合に使用します。
```

## 11. 実装方針

既存機能を最大限再利用する。

再利用するもの：

```text
既存の単体CSVビュー
既存のZIP読込処理
既存のmultiState
既存の複数CSV統合処理
既存の印刷/PDF処理
```

新しく必要なもの：

```text
ZIP読込後メニュー
ZIP由来CSVを単体CSVビューへ渡す処理
帳票選択ナビ
個別CSV読込の折りたたみ
「複数CSV統合ビュー」→「月次チェック・差異確認」への名称変更
```

重要方針：

- 集計ロジックは増やさない。
- CSV列仕様は変更しない。
- ZIP読込後の表示導線を変える。
- 単体CSVビューの分かりやすさを中心にする。
- 月次チェック・差異確認は最終確認用として残す。

## 12. 実装ステップ案

```text
Phase 2-4-9-0：画面構成・ページ遷移設計 docs
Phase 2-4-9-1：ZIP読込後メニュー実装
Phase 2-4-9-2：ZIP内CSVを単体CSVビューで表示
Phase 2-4-9-3：月次チェック・差異確認へ名称変更
Phase 2-4-9-4：個別CSV読込を折りたたみ化
Phase 2-4-9-5：PDFボタン・画面文言整理
```

## 13. 実装結果：Phase 2-4-9-1（ZIP読込後メニュー実装）

- 実装コミット：`08be5ac Add CSV ZIP report selection menu`
- 対象ファイル：`local-viewers/csv-viewer.html`

### 現時点の仕様

- ZIP読込後、帳票選択メニューを表示する。
- 4つの単体CSV帳票カード（工事一覧・原価概要／日報・労務費／請求書費用／重機台帳）は準備中表示。
- 月次チェック・差異確認カードは既存統合ビューへ接続済み。
- 個別CSV読込は残置（見出し「詳細・トラブル対応用：個別CSV読込」）。

### 追加UI

- `#multiMenuCard`
- `#multiMenuArea`
- `#multiIntegratedSection`
- `#multiMenuMsg`

### 追加・変更した主な関数

- `renderMultiMenu()`
- `openMultiReport()`
- `showMultiMenu()`
- `showMultiIntegrated()`
- `MULTI_MENU_CARDS`（定数）
- `showMultiHome()` の表示先変更（データ変更時のホームを帳票選択メニューに）
- `setMode('multi')` の表示制御追加（メニュー描画＋メニュー/統合セクションの表示切替）

### 確認結果

- 実ZIP 2026年6月分で表示確認
- 行数 10 / 41 / 0 / 22 表示OK
- 請求書明細0件の正常案内OK
- 月次チェック・差異確認導線OK
- 工事詳細・戻る導線OK
- NaNなし
- Console重大エラーなし（favicon 404 のみ・無害）
- JS構文チェックOK
- print emulation確認OK

### 未実装（次フェーズ）

- 各単体CSV帳票カードから既存単体CSVビューへの接続。
- これは Phase 2-4-9-2 で実施予定。

## 14. Phase 2-4-9-2-a：単体CSVビュー接続方針決定

> 本章は Phase 2-4-9-2「ZIP内CSVを単体CSVビューで表示」の**実装前の接続方針（docs設計のみ）**。`local-viewers/csv-viewer.html` の実装は変更しない。

### 採用方針

```text
- ZIP内CSVを単体CSVビューで表示する実装方針は、案Cを採用する
- handleText(fileName, text) を以下の2段階に分離する
  1. CSVテキストをパースして headers / rows / csvType / warnings / errors を作る処理
  2. headers / rows / csvType / warnings / errors から state を構築して renderAllPages() する処理
- 単体file読込とZIP由来単体表示の両方で、同じ state構築＋描画処理を使う
```

仮の関数名（実装時に確定）：`parseSingleCsvText(text)` / `buildSingleStateAndRender(args)`。

### 案Cを採用する理由

```text
- 単体CSVビューは state をグローバル参照して描画する構造である
- ZIP読込後は multiState.rows に rows 配列が残っている
- ZIP内CSVの raw text は保持されていない
- raw text を新たに保持して handleText に再投入する案Aは、再パース・二重保持になる
- rows から直接 state を構築する案Bは、handleText 後半処理のロジック複製が起きやすい
- 案Cなら、既存の単体CSV描画を再利用でき、ロジック複製を避けられる
- Phase 2-4-8-6 の loadMultiSlot / loadMultiSlotFromText 分離と同じ設計思想で一貫性がある
```

### warnings/errors の引き継ぎ方

重要事項：

```text
parseSingleCsvText 相当の関数は、headers / rows / csvType だけでなく warnings / errors も返す。

buildSingleStateAndRender 相当の関数は、warnings / errors を必ず受け取り、state.warnings / state.errors に反映する。
```

理由：

```text
handleText には、文字化け検知、空CSV、ヘッダなし、列数不一致、複数種別一致などの警告・エラー生成が含まれる。
これらを分離時に取りこぼすと、単体file読込とZIP由来単体表示で警告・エラー表示が食い違う。
```

設計：

```text
単体file読込：
text
→ parseSingleCsvText(text)
→ { headers, rows, csvType, warnings, errors }
→ buildSingleStateAndRender({ fileName, source:'file', csvType, headers, rows, warnings, errors })

ZIP由来単体表示：
multiState.rows[type]
multiState.files[type]
multiState の警告情報
→ buildSingleStateAndRender({ fileName, source:'zip', csvType, headers, rows, warnings, errors })
```

補足：

```text
ZIP由来では raw text がないため、文字化け検知など raw text 依存の警告はZIP読込時点で生成済みのものを引き継ぐか、ZIP読込時の検証結果として扱う。
重複して警告を生成しない。
```

### 状態遷移と戻り先

3状態を定義する。

```text
A. 単体fileビュー
B. ZIP帳票選択メニュー / 月次チェック・差異確認
C. ZIP由来単体ビュー
```

状態ごとの役割：

```text
A. 単体fileビュー
- ユーザーが個別CSVを読み込んだ状態
- state は file由来CSVを保持
- 戻り先は通常の単体CSV画面内

B. ZIP帳票選択メニュー / 月次チェック・差異確認
- ZIPを読み込んだ状態
- multiState が4CSVを保持
- 帳票選択メニュー、月次チェック・差異確認、工事詳細を行き来する

C. ZIP由来単体ビュー
- 帳票選択メニューから、ZIP内CSVの1つを単体ビュー形式で開いた状態
- state はZIP由来CSVで上書きされる
- multiState は保持したまま
- 戻るボタンは「帳票選択メニューに戻る」
```

状態遷移図：

```text
起動
 ↓
ZIP読込
 ↓
帳票選択メニュー
 ├ 工事一覧・原価概要
 │   ↓
 │  ZIP由来 projects_summary 単体ビュー
 │   ↓
 │  帳票選択メニューに戻る
 │
 ├ 日報・労務費
 │   ↓
 │  ZIP由来 attendance_details 単体ビュー
 │   ↓
 │  帳票選択メニューに戻る
 │
 ├ 請求書費用
 │   ↓
 │  ZIP由来 project_cost_details 単体ビュー
 │   ↓
 │  帳票選択メニューに戻る
 │
 ├ 重機台帳
 │   ↓
 │  ZIP由来 machine_details 単体ビュー
 │   ↓
 │  帳票選択メニューに戻る
 │
 └ 月次チェック・差異確認
     ↓
    月次チェック・差異確認
     ↓
    帳票選択メニューに戻る
```

注意事項：

```text
- ZIP由来単体ビューで state を上書きしても、multiState は維持する
- 帳票選択メニューへ戻ったときにZIP読込状態が消えないこと
- その後、別の帳票カードを開けること
- 個別CSV読込を行った場合は、通常の単体fileビューとして扱う
- 個別CSV読込とZIP由来単体ビューの戻り先を混同しない
```

### 印刷/PDF導線

現状：

```text
- 単体CSVビューには専用の印刷/PDFボタンがない
- 複数CSV側には印刷/PDF系の導線がある
```

方針：

```text
Phase 2-4-9-2 では、ZIP由来単体ビューへの接続を優先する。
ただし、ZIP由来単体ビューの上部には将来的に「この帳票をPDF保存」ボタンを置ける設計にする。
```

暫定対応：

```text
- 2-4-9-2 では既存のブラウザ印刷挙動を壊さない
- PDFボタンの本格整備は Phase 2-4-9-5 で扱う
- ただし、2-4-9-2-c で projects_summary を接続した時点で、ボタン配置場所だけは崩れないよう考慮する
```

### project_cost_details 0件の扱い

```text
project_cost_details は実ZIP 2026年6月分では0件だった。
これは接続検証には不向きというだけでなく、0件CSVを正常表示できるか確認する境界ケースとして重要である。
```

方針：

```text
2-4-9-2-e では、project_cost_details 0件時にエラーではなく正常な空表示になることを確認する。
表示文言は「この期間の請求書明細は0件です。対象期間に請求書登録がない場合は正常です。」に寄せる。
```

### 回帰確認の合格条件

handleText分離後、単体file読込の挙動は分離前と完全一致させる。

確認対象：

```text
- CSV種別判定
- warnings
- errors
- rows件数
- headers
- state.csvType
- state.csvLabel
- state.reports
- minDate / maxDate
- renderAllPages の描画結果
- 初期表示ページ
- 詳細画面
- 戻り導線
- NaNなし
- Console重大エラーなし
```

CSV別確認：

```text
projects_summary.csv：
- 工事一覧
- 工事詳細
- 年度別集計
- 発注者別集計
- 工事分類別集計

attendance_details.csv：
- buildAttendanceReports
- report_id ピボット
- 二重計上防止
- 月別サマリー
- 従業員別サマリー
- 従業員別月別表示

project_cost_details.csv：
- invoice_date 期間推定
- 請求書一覧
- 業者別集計
- 工事別集計
- 月別集計
- 費目別集計
- 確認リスト
- 0件時の正常表示

machine_details.csv：
- 重機一覧
- 所有・リース別集計
- 月額表示
- 確認リスト
```

### 実装ステップ（Phase 2-4-9-2）

```text
2-4-9-2-a：単体CSVビュー接続方針決定（docs）
2-4-9-2-b：handleText を parse部 と state構築＋描画部 に分離
2-4-9-2-c：projects_summary をZIP由来で単体ビュー表示
2-4-9-2-d：attendance_details をZIP由来で単体ビュー表示
2-4-9-2-e：project_cost_details をZIP由来で単体ビュー表示
2-4-9-2-f：machine_details をZIP由来で単体ビュー表示
2-4-9-2-g：全帳票回帰確認
```

## 15. Phase 2-4-9-2-b：handleText分離 実装結果

### 15.1 実装コミット

```text
64c699b Split handleText into parse and render phases
```

### 15.2 変更範囲

```text
local-viewers/csv-viewer.html のみ
```

### 15.3 追加・変更した関数

```text
parseSingleCsvText(text)
- CSVテキストを解析するparse部
- 文字化け検知
- parseCsvToMatrix
- headers作成
- detectCsvType
- rows作成
- __extra_N の超過列保持
- 列数不一致チェック
- warnings/errors生成
- stateには触れない

buildSingleStateAndRender(args)
- parse結果からstateを構築して描画する処理
- fileName/source/csvType/csvLabel/headers/rows/warnings/errors を受け取る
- state.loaded/fileName/csvType/csvLabel/headers/rows/reports/warnings/errors/minDate/maxDate/generatedAt を構築
- attendance_detailsではbuildAttendanceReportsを呼ぶ
- project_cost_detailsではinvoice_dateからminDate/maxDateを推定
- renderAllPages()
- 初期表示は従来どおり
- 致命的エラー時はmessagesページへ

handleText(fileName, text)
- 既存入口として残置
- parseSingleCsvText(text)
- buildSingleStateAndRender({ source:'file', ...parsed })
- という薄いラッパに変更
```

### 15.4 維持した仕様

```text
- CSV列仕様変更なし
- 既存集計ロジックの意味変更なし
- renderAllPages の呼び出しタイミング維持
- 単体CSV読込後の初期表示維持
- projects_summary の工事一覧・工事詳細維持
- attendance_details のreport_idピボット・二重計上防止維持
- project_cost_details のinvoice_date期間推定維持
- machine_details の既存表示維持
- warnings/errors の表示維持
- ZIP帳票カード接続は未実装
```

### 15.5 回帰確認結果

```text
jsdomで実HTML＋実コードをヘッドレス実行し、全53項目PASS。

確認内容：
- projects_summary：種別判定、工事一覧、工事詳細、NaNなし
- attendance_details：rows=3→reports=2、report_idピボット、二重計上防止、月別・従業員別表示、min/maxDate
- project_cost_details：invoice_dateでmin/maxDate推定、請求書一覧、確認リスト、NaNなし
- project_cost_details 0件：errors空、正常表示、dashboard表示、NaNなし
- machine_details：重機一覧、月額表示、確認リスト、NaNなし
- 未知CSV：csvType=null、errorsあり、messagesページ、headers保持
- ZIP側：openMultiReportは準備中表示のまま
- multiState/finalizeMulti/帳票選択メニュー描画は不変
```

### 15.6 未実装

```text
- ZIP帳票カードから単体CSVビューへの接続
- openMultiReport の本格接続
- ZIP由来単体ビューの戻る導線
- ZIP由来単体ビューのPDF保存ボタン
```

次フェーズ：

```text
Phase 2-4-9-2-c：projects_summary をZIP由来で単体ビュー表示
```
