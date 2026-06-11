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

## 16. Phase 2-4-9-2-c：projects_summary ZIP由来単体ビュー接続 実装結果

### 16.1 実装コミット

```text
f2b1b1c Connect ZIP projects summary to single CSV viewer
```

### 16.2 変更範囲

```text
local-viewers/csv-viewer.html のみ
```

### 16.3 実装内容

```text
- 帳票選択メニューの「工事一覧・原価概要」カードを実接続
- ZIP内 projects_summary.csv を、既存の単体CSVビューと同じ構成で表示
- buildSingleStateAndRender({ source:'zip', ... }) を利用
- state はZIP由来 projects_summary で上書き
- multiState は保持
- 帳票選択メニューに戻る導線を追加
```

### 16.4 追加・変更した主な関数・UI

```text
openZipSingleReport(type)
- ZIP由来の1CSVを単体ビューで表示する
- 現時点では projects_summary のみ実接続
- multiState.rows[type] / multiState.files[type] を利用
- buildSingleStateAndRender({ source:'zip', ... }) を呼ぶ

backFromZipSingleToMenu()
- ZIP由来単体ビューから帳票選択メニューへ戻る
- viewerBody と戻る導線を隠す
- showMultiMenu() で帳票選択メニューへ復帰
- multiState は保持

openMultiReport(key,title)
- projects_summary かつ読込済みの場合のみ openZipSingleReport へ分岐
- 他3種別は準備中表示のまま

loadMultiSlotFromText()
- multiState.files[slotKey].headers を追加保持
- ZIP由来単体ビュー表示時に buildSingleStateAndRender へ渡す

#zipSingleBack
- ZIP由来単体ビュー用の戻る導線
- 「← 帳票選択メニューに戻る」
- 読込元と対象期間を表示
```

### 16.5 headers の扱い

```text
ZIP読込時に loadMultiSlotFromText が算出していた headers を、multiState.files[slotKey].headers として保持するようにした。
これにより、raw CSV text がなくても ZIP由来 rows と headers から単体CSVビューを再構築できる。
0行CSVでも headers は取得できるため、今後 project_cost_details 0件表示にも有効。
CSV列仕様そのものは変更していない。
```

### 16.6 戻る導線

```text
ZIP由来単体ビュー上部に「← 帳票選択メニューに戻る」を表示。
押下すると viewerBody を隠し、帳票選択メニューへ戻る。
multiState は消さないため、戻った後も月次チェック・差異確認や他カードを開ける。
既存の工事詳細→工事一覧の戻り導線は変更していない。
```

### 16.7 回帰確認結果

```text
jsdomで実HTML＋実コードをヘッドレス実行し、全42項目PASS。

確認内容：
- ZIP読込状態を loadMultiSlotFromText + finalizeMulti で再現
- 工事一覧・原価概要カード「開く」からZIP由来 projects_summary 単体ビュー表示OK
- 読込元「ZIP内 projects_summary.csv」表示OK
- 対象期間「2026年6月分」表示OK
- 工事一覧表示OK
- 年度別集計表示OK
- 発注者別集計表示OK
- 工事分類別集計表示OK
- 工事詳細表示OK
- 工事詳細→一覧戻りOK
- 帳票選択メニューに戻るOK
- 戻った後もZIP読込状態保持OK
- 月次チェック・差異確認を開けるOK
- 他3カードは準備中表示のままOK
- 個別CSV読込回帰OK
- ZIP由来単体表示と個別CSV読込が混同しないことOK
- NaNなし
- JS構文チェックOK
- git diff --check OK
```

### 16.8 未実装

```text
- attendance_details のZIP由来単体ビュー接続
- project_cost_details のZIP由来単体ビュー接続
- machine_details のZIP由来単体ビュー接続
- ZIP由来単体ビューのPDF保存ボタン
- 月次チェック・差異確認の内部名称整理
- 個別CSV読込の折りたたみ化
```

次フェーズ：

```text
Phase 2-4-9-2-d：attendance_details をZIP由来で単体ビュー表示
```

## 17. Phase 2-4-9-2-d：attendance_details ZIP由来単体ビュー接続 実装結果

### 17.1 実装コミット

```text
c7b1cc4 Connect ZIP attendance details to single CSV viewer
```

### 17.2 変更範囲

```text
local-viewers/csv-viewer.html のみ
```

### 17.3 実装内容

```text
- 帳票選択メニューの「日報・労務費」カードを実接続
- ZIP内 attendance_details.csv を、既存の単体CSVビューと同じ構成で表示
- openMultiReport(key,title) の分岐条件に attendance_details を追加
- openZipSingleReport(type) は既存汎用処理を利用
- buildSingleStateAndRender({ source:'zip', ... }) を利用
- state はZIP由来 attendance_details で上書き
- multiState は保持
- 帳票選択メニューに戻る導線は projects_summary と同じものを利用
```

### 17.4 追加・変更した主な関数

```text
openMultiReport(key,title)
- projects_summary に加え、attendance_details も openZipSingleReport へ分岐
- project_cost_details / machine_details は準備中表示のまま

openZipSingleReport(type)
- 既存の汎用処理をそのまま利用
- multiState.rows[type] / multiState.files[type] を buildSingleStateAndRender へ渡す

buildSingleStateAndRender(args)
- 既存処理を変更せず利用
- csvType が attendance_details の場合、buildAttendanceReports(rows) を呼ぶ

buildAttendanceReports(rows)
- 変更なし
```

### 17.5 report_id ピボット・二重計上防止

```text
attendance_details は report_id 単位で日報を集約する。
同一 report_id が複数現場に分かれている場合でも、normal_mins / overtime_mins / night_mins / holiday_mins を二重計上しない。
一方、labor_cost は現場別按分SUMとして扱う。
今回の実装では buildAttendanceReports を変更せず、ZIP由来rowsでも既存ロジックをそのまま通す方針とした。
```

確認結果：

```text
テストCSVで以下を確認した。
- reports=2件
- R1 normal_mins=480
- R1 overtime_mins=60
- R1 labor_cost_total=60000
- minDate=2026-06-01
- maxDate=2026-06-20
- NaNなし
```

### 17.6 戻る導線

```text
ZIP由来 attendance_details 単体ビューでも、既存の #zipSingleBack を使用。
「← 帳票選択メニューに戻る」からメニューへ復帰する。
読込元「ZIP内 attendance_details.csv」と対象期間を表示する。
社員別月別詳細から従業員別一覧へ戻る既存導線は変更していない。
```

### 17.7 回帰確認結果

```text
jsdomで実HTML＋実コードをヘッドレス実行し、全47項目PASS。

確認内容：
- ZIP読込状態を loadMultiSlotFromText + finalizeMulti で再現
- 日報・労務費カード「開く」からZIP由来 attendance_details 単体ビュー表示OK
- 読込元「ZIP内 attendance_details.csv」表示OK
- 対象期間「2026年6月分」表示OK
- 月別サマリー表示OK
- 従業員別サマリー表示OK
- 全体サマリー表示OK
- 社員別月別詳細表示OK
- 社員別月別詳細→従業員別一覧戻りOK
- 帳票選択メニューに戻るOK
- 戻った後もZIP読込状態保持OK
- 月次チェック・差異確認を開けるOK
- projects_summary の接続済み状態も維持
- project_cost_details / machine_details は準備中表示のままOK
- 個別CSV読込回帰OK
- ZIP由来単体表示と個別CSV読込が混同しないことOK
- NaNなし
- JS構文チェックOK
- git diff --check OK
```

### 17.8 未実装

```text
- project_cost_details のZIP由来単体ビュー接続
- machine_details のZIP由来単体ビュー接続
- ZIP由来単体ビューのPDF保存ボタン
- 月次チェック・差異確認の内部名称整理
- 個別CSV読込の折りたたみ化
```

次フェーズ：

```text
Phase 2-4-9-2-e：project_cost_details をZIP由来で単体ビュー表示
```

## 18. Phase 2-4-9-2-e：project_cost_details ZIP由来単体ビュー接続 実装結果

### 18.1 実装コミット

```text
34d5d73 Connect ZIP project cost details to single CSV viewer
```

### 18.2 変更範囲

```text
local-viewers/csv-viewer.html のみ
```

### 18.3 実装内容

```text
- 帳票選択メニューの「請求書費用」カードを実接続
- ZIP内 project_cost_details.csv を、既存の単体CSVビューと同じ構成で表示
- openMultiReport(key,title) の分岐条件に project_cost_details を追加
- openZipSingleReport(type) は既存汎用処理を利用
- buildSingleStateAndRender({ source:'zip', ... }) を利用
- state はZIP由来 project_cost_details で上書き
- multiState は保持
- renderDashboard() に project_cost_details 0件時の安心文言を条件付き追加
- 帳票選択メニューに戻る導線は既存仕組みを利用
```

### 18.4 追加・変更した主な関数

```text
openMultiReport(key,title)
- projects_summary / attendance_details に加え、project_cost_details も openZipSingleReport へ分岐
- machine_details は準備中表示のまま

renderDashboard()
- project_cost_details かつ rows=0 の場合のみ、0件が正常である旨の安心文言を表示

openZipSingleReport(type)
- 既存の汎用処理をそのまま利用
- multiState.rows[type] / multiState.files[type] を buildSingleStateAndRender へ渡す

buildSingleStateAndRender(args)
- 既存処理を変更せず利用

aggregateInvoices(rows, keyFn, emptyLabel)
- 変更なし

computeInvoiceChecks(rows)
- 変更なし
```

### 18.5 0件CSVの正常表示

```text
project_cost_details は実ZIP 2026年6月分で0件だった。
これはエラーではなく、対象期間に請求書登録がない正常ケースとして扱う。
今回、ZIP由来 project_cost_details 単体ビューでも、0件CSVを errors空・正常表示として扱えることを確認した。
```

確認結果：

```text
- 0件でも errors空
- 初期ページ dashboard が正常表示
- 明細件数0
- 金額合計0円
- NaNなし
- 請求書一覧は既存の「データ0件です。」表示
- 確認リストも異常扱いになりすぎない
- 「この期間の請求書明細は0件です。対象期間に請求書登録がない場合は正常です。」を条件付き表示
```

### 18.6 invoice_date 期間推定

```text
データあり project_cost_details CSVでは invoice_date から state.minDate / state.maxDate を推定する既存処理を確認した。
0件CSVでは minDate / maxDate が空でもエラーにしない。
ZIP由来単体ビュー上部の対象期間表示は manifest の periodLabel を使うため、0件でも「2026年6月分」と表示できる。
```

確認結果：

```text
データありCSVで以下を確認した。
- minDate=2026-06-10
- maxDate=2026-06-25
- 請求書一覧表示OK
- 業者別表示OK
- 工事別表示OK
- 月別表示OK
- 費目別表示OK
- 確認リスト表示OK
- NaNなし
```

### 18.7 戻る導線

```text
ZIP由来 project_cost_details 単体ビューでも、既存の #zipSingleBack を使用。
「← 帳票選択メニューに戻る」からメニューへ復帰する。
読込元「ZIP内 project_cost_details.csv」と対象期間を表示する。
単体ビュー内の請求書各ページ・確認リストのページ切替とは別導線として扱う。
```

### 18.8 回帰確認結果

```text
jsdomで実HTML＋実コードをヘッドレス実行し、全41項目PASS。

確認内容：
- ZIP読込状態を loadMultiSlotFromText + finalizeMulti で再現
- 請求書費用カード「開く」からZIP由来 project_cost_details 単体ビュー表示OK
- 読込元「ZIP内 project_cost_details.csv」表示OK
- 対象期間「2026年6月分」表示OK
- 0件CSVでも errors空OK
- 0件CSVでも dashboard 正常表示OK
- 0件時の安心文言表示OK
- 請求書一覧OK
- 業者別集計OK
- 工事別集計OK
- 月別集計OK
- 費目別集計OK
- 確認リストOK
- データありCSVでは invoice_date から minDate / maxDate 推定OK
- 帳票選択メニューに戻るOK
- 戻った後もZIP読込状態保持OK
- projects_summary / attendance_details の接続済み状態も維持
- machine_details は準備中表示のままOK
- 個別CSV読込回帰OK
- ZIP由来単体表示と個別CSV読込が混同しないことOK
- NaNなし
- JS構文チェックOK
- git diff --check OK
```

### 18.9 未実装

```text
- machine_details のZIP由来単体ビュー接続
- ZIP由来単体ビューのPDF保存ボタン
- 月次チェック・差異確認の内部名称整理
- 個別CSV読込の折りたたみ化
```

次フェーズ：

```text
Phase 2-4-9-2-f：machine_details をZIP由来で単体ビュー表示
```

## 19. Phase 2-4-9-2-f：machine_details ZIP由来単体ビュー接続 実装結果

### 19.1 実装コミット

```text
26d7a30 Connect ZIP machine details to single CSV viewer
```

### 19.2 変更範囲

```text
local-viewers/csv-viewer.html のみ
```

### 19.3 実装内容

```text
- 帳票選択メニューの「重機台帳」カードを実接続
- ZIP内 machine_details.csv を、既存の単体CSVビューと同じ構成で表示
- openMultiReport(key,title) の分岐条件に machine_details を追加
- openZipSingleReport(type) は既存汎用処理を利用
- buildSingleStateAndRender({ source:'zip', ... }) を利用
- state はZIP由来 machine_details で上書き
- multiState は保持
- 4カードすべてがZIP由来単体ビューへ接続済みになった
```

### 19.4 追加・変更した主な関数

```text
openMultiReport(key,title)
- projects_summary / attendance_details / project_cost_details に加え、machine_details も openZipSingleReport へ分岐
- これにより4カードすべてが実接続済みになった

openZipSingleReport(type)
- 既存の汎用処理をそのまま利用
- multiState.rows[type] / multiState.files[type] を buildSingleStateAndRender へ渡す

buildSingleStateAndRender(args)
- 既存処理を変更せず利用

machineCostRaw(row)
- 変更なし

computeMachineChecks(rows)
- 変更なし
```

### 19.5 machine_details 表示確認

```text
ZIP由来 machine_details 単体ビューで、既存単体CSVビューの重機台帳表示を再利用した。
工事別原価への重機費連携は今回の対象外であり、集計ロジックの意味変更は行っていない。
```

確認結果：

```text
テストCSVで以下を確認した。
- 重機一覧表示OK
- ユンボ表示OK
- ダンプ表示OK
- 月額120,000表示OK
- 所有/リース別集計OK
- active / ownership 表示OK
- 確認リスト表示OK
- dashboard / 一覧 / 集計 / 確認リストでNaNなし
```

### 19.6 0件CSVの正常表示

```text
0件 machine_details CSVでも、errors空・正常表示・NaNなしを確認した。
```

確認結果：

```text
- 0件でも errors空
- 初期ページ dashboard が正常表示
- 重機一覧でNaNなし
- 確認リストでNaNなし
- 読込元「ZIP内 machine_details.csv」表示OK
```

### 19.7 戻る導線

```text
ZIP由来 machine_details 単体ビューでも、既存の #zipSingleBack を使用。
「← 帳票選択メニューに戻る」からメニューへ復帰する。
読込元「ZIP内 machine_details.csv」と対象期間を表示する。
単体ビュー内の重機各ページのページ切替とは別導線として扱う。
```

### 19.8 4カード全接続

```text
Phase 2-4-9-2-f により、帳票選択メニューの4カードすべてがZIP由来単体ビューへ接続済みになった。
```

接続済み：

```text
- projects_summary：工事一覧・原価概要
- attendance_details：日報・労務費
- project_cost_details：請求書費用
- machine_details：重機台帳
```

### 19.9 回帰確認結果

```text
jsdomで実HTML＋実コードをヘッドレス実行し、全40項目PASS。

確認内容：
- ZIP読込状態を loadMultiSlotFromText + finalizeMulti で再現
- 重機台帳カード「開く」からZIP由来 machine_details 単体ビュー表示OK
- 読込元「ZIP内 machine_details.csv」表示OK
- 対象期間「2026年6月分」表示OK
- 重機一覧表示OK
- 所有/リース別集計OK
- 月額表示OK
- 確認リストOK
- active / ownership 表示OK
- 0件CSVでも正常表示OK
- 帳票選択メニューに戻るOK
- 戻った後もZIP読込状態保持OK
- projects_summary / attendance_details / project_cost_details の接続済み状態も維持
- 4カードすべて実接続済みOK
- 個別CSV読込回帰OK
- ZIP由来単体表示と個別CSV読込が混同しないことOK
- NaNなし
- JS構文チェックOK
- git diff --check OK
```

### 19.10 未実装

```text
- ZIP由来単体ビューのPDF保存ボタン
- 月次チェック・差異確認の内部名称整理
- 個別CSV読込の折りたたみ化
- 重機費の工事別原価連携
```

次フェーズ：

```text
Phase 2-4-9-2-g：全帳票回帰確認
```

## 20. Phase 2-4-9-2-g：全帳票回帰確認 結果

### 20.1 確認概要

```text
Phase 2-4-9-2-c〜f で接続した4帳票について、ZIP読込後の帳票選択メニューから単体CSVビューを開き、各ビュー・戻り導線・月次チェック・個別CSV読込回帰を総合確認した。
```

### 20.2 確認方法

```text
jsdomで local-viewers/csv-viewer.html の実HTML＋実コードをヘッドレス実行。
ZIP読込状態は loadMultiSlotFromText + finalizeMulti で再現。
periodLabel は 2026年6月分。
データありZIP＋0件ZIPの2シナリオを連続実行。
検証スクリプト・テストCSVはリポジトリ外の一時フォルダに作成し、実行後に削除した。
```

### 20.3 結果

```text
総合 jsdom 回帰：全90項目PASS
PASS件数：90 pass / 0 fail
EXIT 0
```

### 20.4 projects_summary 確認結果

```text
- 工事一覧・原価概要カード「開く」OK
- ZIP由来 projects_summary 単体ビュー表示OK
- 読込元「ZIP内 projects_summary.csv」表示OK
- 対象期間「2026年6月分」表示OK
- 工事一覧表示OK
- 年度別集計表示OK
- 発注者別集計表示OK
- 工事分類別集計表示OK
- 工事詳細表示OK
- 工事詳細→工事一覧戻りOK
- 帳票選択メニュー戻りOK
- 戻った後もZIP読込状態保持OK
- NaNなし
```

### 20.5 attendance_details 確認結果

```text
- 日報・労務費カード「開く」OK
- ZIP由来 attendance_details 単体ビュー表示OK
- 読込元「ZIP内 attendance_details.csv」表示OK
- 対象期間「2026年6月分」表示OK
- 月別サマリー表示OK
- 従業員別サマリー表示OK
- 全体サマリー表示OK
- 社員別月別詳細表示OK
- 社員別月別詳細→従業員別一覧戻りOK
- 帳票選択メニュー戻りOK
- NaNなし
```

report_id ピボット確認：

```text
- reports=2
- R1 normal_mins=480
- R1 overtime_mins=60
- normal_mins / overtime_mins は複製を二重計上しない
- labor_cost_total=60000
- site 2件集約OK
```

### 20.6 project_cost_details 確認結果

```text
- 請求書費用カード「開く」OK
- ZIP由来 project_cost_details 単体ビュー表示OK
- 読込元「ZIP内 project_cost_details.csv」表示OK
- 対象期間「2026年6月分」表示OK
- 請求書一覧表示OK
- 業者別集計表示OK
- 工事別集計表示OK
- 月別集計表示OK
- 費目別集計表示OK
- 確認リスト表示OK
- 帳票選択メニュー戻りOK
- NaNなし
```

データありCSV確認：

```text
- invoice_date から minDate=2026-06-10 / maxDate=2026-06-25 推定OK
```

0件CSV確認：

```text
- 0件でも errors空
- dashboard正常表示
- 安心文言表示OK
- 「この期間の請求書明細は0件です。対象期間に請求書登録がない場合は正常です。」表示OK
- 確認リストが異常扱いになりすぎない
- NaNなし
```

### 20.7 machine_details 確認結果

```text
- 重機台帳カード「開く」OK
- ZIP由来 machine_details 単体ビュー表示OK
- 読込元「ZIP内 machine_details.csv」表示OK
- 対象期間「2026年6月分」表示OK
- 重機一覧表示OK
- ユンボ表示OK
- 月額120,000表示OK
- 所有/リース別集計表示OK
- 確認リスト表示OK
- active / ownership 表示OK
- 帳票選択メニュー戻りOK
- NaNなし
```

0件CSV確認：

```text
- 0件でも errors空
- dashboard正常表示
- 重機一覧・確認リストでNaNなし
```

### 20.8 月次チェック・差異確認

```text
- 月次チェック・差異確認カード「開く」OK
- 簡易工事一覧表示OK
- 確認リスト表示OK
- 警告エラー表示OK
- 工事詳細表示OK
- 工事詳細の概要・差異確認描画OK
- 工事詳細→月次チェック・差異確認戻りOK
- 月次チェック・差異確認→帳票選択メニュー戻りOK
- 4カード操作後でも問題なく開ける
- 連続オープンで表示が混ざらない
- NaNなし
```

### 20.9 戻り導線・状態保持

```text
- ZIP由来単体ビュー→帳票選択メニューOK
- 工事詳細→工事一覧OK
- 社員別月別詳細→従業員別一覧OK
- 月次チェック・差異確認→帳票選択メニューOK
- 月次チェック内工事詳細→月次チェック・差異確認OK
- 戻った後も multiState.loaded 維持OK
- 戻った後も各CSV rows 維持OK
- 複数カードを連続して開いても表示が混ざらない
```

### 20.10 個別CSV読込回帰

```text
- 個別CSV projects_summary.csv 読込OK
- 個別CSV attendance_details.csv 読込OK
- 個別CSV project_cost_details.csv 読込OK
- 個別CSV machine_details.csv 読込OK
- file読込時に zipSingleBack 非表示OK
- 単体file読込の初期表示OK
- ZIP由来表示と個別CSV読込が混同しない
- NaNなし
```

### 20.11 最終判定

```text
- NaN表示なし
- Console重大エラーなし
- git diff --check エラーなし
- git status clean
- SQL実行なし
- DB変更なし
- 実装変更なし
- Phase 2-4-9-2「ZIP内CSVを単体CSVビューで表示」は完了
```

### 20.12 残課題

```text
- ZIP由来単体ビューのPDF保存ボタン本格整備
- 月次チェック・差異確認の内部名称整理
- 個別CSV読込の折りたたみ化
- 重機費の工事別原価連携
```

## 21. Phase 2-4-9-3：ZIP読込後UXの微調整 設計

### 21.1 背景

```text
Phase 2-4-9-2 で、ZIP読込後の帳票選択メニューから4帳票すべてを単体CSVビュー形式で表示できるようになった。
次は実運用時に迷わないよう、画面上の文言・導線・補助表示を整理する。
```

### 21.2 現在の画面構成

```text
CSV確認ビューアー
├ ZIP読込ホーム
├ 帳票選択メニュー
│  ├ 工事一覧・原価概要
│  ├ 日報・労務費
│  ├ 請求書費用
│  ├ 重機台帳
│  └ 月次チェック・差異確認
├ ZIP由来単体ビュー
│  ├ projects_summary
│  ├ attendance_details
│  ├ project_cost_details
│  └ machine_details
└ 詳細・トラブル対応用：個別CSV読込
```

### 21.3 UX方針

```text
- 通常運用ではZIP読込を主導線にする
- 帳票選択メニューを起点にする
- 4帳票は「個別確認」
- 月次チェック・差異確認は「横断確認」
- 個別CSV読込は通常時には目立たせすぎない
- 戻る導線は常に「帳票選択メニューに戻る」を基本にする
- 画面上部に読込元と対象期間を表示し、どのCSVを見ているか迷わないようにする
```

### 21.4 帳票選択メニューの改善候補

```text
- 4帳票カードと月次チェックカードを視覚的に分ける
- 月次チェック・差異確認カードには「4帳票をまとめて確認」と説明を追加する
- 各カードに「通常確認」「詳細確認」などの短い補足を付ける
- 0件でも正常な帳票は、カードまたは画面内で安心できる文言を出す
- 読込済み件数をより見やすくする
```

### 21.5 個別CSV読込エリアの整理候補

```text
個別CSV読込は、ZIP出力パッケージを使えない場合やトラブル時の詳細確認用として残す。
ただし通常運用ではZIP読込が主導線になるため、個別CSV読込エリアは折りたたみ候補とする。
```

候補：

```text
- 初期表示では折りたたむ
- 見出しを「詳細・トラブル対応用：個別CSV読込」にする
- 「通常はZIPを読み込んでください」という補足を追加する
- クリックで展開する
```

### 21.6 PDF保存ボタン方針

```text
PDF保存ボタンは Phase 2-4-9-5 で本格整備する。
今回のUX整理では、どの画面にPDFボタンを置くかだけ方針化する。
```

候補：

```text
- ZIP由来単体ビューの上部にPDF保存ボタンを置く
- 月次チェック・差異確認にもPDF保存ボタンを置く
- 帳票選択メニュー自体にはPDF保存ボタンを置かない
- ファイル読込由来の単体CSVビューでも将来的には同じ印刷導線を検討する
```

### 21.7 実装順序案

```text
Phase 2-4-9-3-a：帳票選択メニュー文言・補足説明の微調整
Phase 2-4-9-3-b：個別CSV読込エリアの折りたたみ
Phase 2-4-9-3-c：ZIP由来単体ビュー上部情報の微調整
Phase 2-4-9-5：PDF保存ボタン本格整備
```

### 21.8 今回は実装しないこと

```text
- UI変更
- PDF保存ボタン追加
- 個別CSV読込折りたたみ実装
- 月次チェック・差異確認の名称変更
- CSS変更
- JavaScript変更
```

## 22. Phase 2-4-9-3-a：帳票選択メニュー文言・補足説明の微調整 実装結果

### 22.1 実装コミット

```text
cca89af Refine ZIP report menu labels and grouping
```

### 22.2 変更範囲

```text
local-viewers/csv-viewer.html のみ
```

### 22.3 実装内容

```text
- 帳票選択メニューを2セクション構造に整理
- 「個別帳票を確認」セクションを追加
- 「横断チェック」セクションを追加
- 上部説明文を追加
- 4帳票カードの説明文を更新
- 月次チェック・差異確認カードの説明文を更新
- 最小CSSを追加
```

### 22.4 画面構成

```text
帳票選択メニュー
├ 個別帳票を確認
│  ├ 工事一覧・原価概要
│  ├ 日報・労務費
│  ├ 請求書費用
│  └ 重機台帳
└ 横断チェック
   └ 月次チェック・差異確認
```

### 22.5 追加・変更した主なUI

```text
メニュー上部説明：
確認したい帳票を選んでください。通常は4つの個別帳票で内容を確認し、最後に「月次チェック・差異確認」で全体の違和感を確認します。

個別帳票セクション：
- 見出し：個別帳票を確認
- 補足：各CSVを見やすい単体ビューで確認します。

横断チェックセクション：
- 見出し：横断チェック
- 補足：4帳票をまとめて、確認事項・差異・違和感を確認します。
```

### 22.6 カード説明文

```text
工事一覧・原価概要：
工事別の請負金額・原価・粗利を確認します。

日報・労務費：
日報・労務費を月別・従業員別に確認します。

請求書費用：
請求書明細を業者別・工事別・費目別に確認します。

重機台帳：
重機一覧、所有・リース、月額を確認します。

月次チェック・差異確認：
4帳票をまとめて、確認事項・差異・違和感を確認します。
```

### 22.7 変更しなかったもの

```text
- openMultiReport の接続ロジック
- openZipSingleReport
- buildSingleStateAndRender
- CSV解析処理
- 集計ロジック
- 月次チェック・差異確認の内部処理
- PDF保存ボタン
- 個別CSV読込エリア
```

### 22.8 回帰確認結果

```text
jsdomで実HTML＋実コードをヘッドレス実行し、全32項目PASS。

確認内容：
- ZIP読込状態を loadMultiSlotFromText + finalizeMulti で再現
- 帳票選択メニュー表示OK
- 上部説明表示OK
- 「個別帳票を確認」表示OK
- 4帳票カードが個別帳票側に表示OK
- 「横断チェック」表示OK
- 月次チェック・差異確認カードが横断チェック側に表示OK
- 4帳票カードを開けるOK
- 各帳票から帳票選択メニューに戻れるOK
- 月次チェック・差異確認を開けるOK
- 月次チェック・差異確認から帳票選択メニューに戻れるOK
- ZIP読込状態保持OK
- NaNなし
- Console重大エラーなし
- JS構文チェックOK
- git diff --check OK
```

### 22.9 次フェーズ

```text
Phase 2-4-9-3-b：個別CSV読込エリアの折りたたみ
```

## 23. Phase 2-4-9-3-b：個別CSV読込エリアの折りたたみ 実装結果

### 23.1 実装コミット

```text
d9a87f6 Collapse individual CSV load area in ZIP viewer
```

### 23.2 変更範囲

```text
local-viewers/csv-viewer.html のみ
```

### 23.3 実装目的

```text
通常運用ではZIP読込を主導線にするため、個別CSV読込エリアを「詳細・トラブル対応用」として折りたたみ表示に変更した。
```

### 23.4 画面構成

```text
詳細・トラブル対応用：個別CSV読込
├ 補足説明
├ 開閉ボタン
└ 折りたたみ本文
   ├ 詳細注記
   └ 既存の個別CSV読込UI
```

### 23.5 実装内容

```text
- #multiIndividualToggle を追加
- #multiIndividualBody を追加
- #multiIndividualBody は初期 hidden
- #multiLoadArea を #multiIndividualBody 内へ移動
- aria-expanded を false / true で切り替える
- aria-controls="multiIndividualBody" を設定
- 既存の .hidden クラスを利用
- 新規CSSなし
- inline onclick なし
- 未使用 class="collapsible" は除去済み
```

### 23.6 変更しなかったもの

```text
- ZIP読込エリア
- 帳票選択メニュー
- 4帳票カード接続
- 月次チェック・差異確認
- handleText 経路
- setMode('single') の意味
- CSV解析処理
- 集計ロジック
- PDF保存ボタン
```

### 23.7 回帰確認結果

```text
jsdomで実HTML＋実コードをヘッドレス実行し、全35項目PASS。
初期折りたたみ、開閉、aria-expanded、個別4種CSV読込、ZIPメニュー、4カード、月次チェック、NaNなし、Console重大エラーなしを確認。
```

## 24. Phase 2-4-9-3-c：ZIP由来単体ビュー上部情報の微調整 実装結果

### 24.1 実装コミット

```text
8ca17e0 Clarify ZIP single report header details
```

### 24.2 変更範囲

```text
local-viewers/csv-viewer.html のみ
```

### 24.3 実装目的

ZIP読込後に4帳票を単体CSVビューで開いたとき、今どの帳票を見ているか、ZIP由来の表示であること、読込元CSV、対象期間、帳票選択メニューへの戻り導線を分かりやすくする。

### 24.4 表示内容

ZIP由来単体ビューでは、`#zipSingleSource` に以下を表示する。

```text
- ZIP内CSVを単体ビューで確認中
- 帳票：<帳票名>
- 読込元：ZIP内 <fileName>
- 対象期間：<periodLabel>
```

### 24.5 対象帳票

```text
- projects_summary：工事一覧・原価概要
- attendance_details：日報・労務費
- project_cost_details：請求書費用
- machine_details：重機台帳
```

### 24.6 実装内容

```text
- openZipSingleReport(type) 内の ZIP由来単体ビュー用表示を調整
- #zipSingleSource を clear() してから DOM API で再構築
- 表示は textContent を使用
- 帳票名は MULTI_MENU_CARDS の title と統一
- 対象期間は multiState.package.periodLabel を使用
- periodLabel がない場合は「—」を表示
- 戻るボタン「← 帳票選択メニューに戻る」は既存のまま維持
```

### 24.7 変更しなかったもの

```text
- 個別CSV読込由来の単体ビュー
- file読込時の zipSingleBack 非表示
- openMultiReport
- buildSingleStateAndRender
- CSV解析処理
- 集計ロジック
- ZIP読込ロジック
- 月次チェック・差異確認
- PDF保存ボタン
```

### 24.8 回帰確認結果

```text
- 4帳票すべてで上部情報表示OK
- 帳票名表示OK
- 読込元「ZIP内 xxx.csv」表示OK
- 対象期間「2026年6月分」表示OK
- 帳票選択メニューへ戻る導線OK
- 戻った後も multiState.loaded 維持OK
- 戻った後も rows 維持OK
- 個別CSV読込エリアの折りたたみ維持OK
- file読込時 zipSingleBack 非表示OK
- 月次チェックへの影響なし
- NaNなし
- Console重大エラーなし
- JS構文チェックOK
- git diff --check OK
```

### 24.9 最終判定

ZIP由来単体ビューと個別CSV読込由来の単体ビューの区別が分かりやすくなった。4帳票接続・集計・月次チェック・個別CSV読込への影響はない。

## 25. Phase 2-4-9-5：印刷・PDF保存導線の整備 設計

### 25.1 背景

Phase 2-4-9-3-c までで、ZIP読込後の4帳票表示・帳票選択メニュー・個別CSV読込補助導線・ZIP由来単体ビュー上部情報が整理された。
次は、確認した帳票や横断チェック結果を印刷・PDF保存しやすくする導線を整える。

### 25.2 基本方針

PDF生成ライブラリは追加しない。
ブラウザ標準の `window.print()` を使い、ユーザーが印刷画面で「PDFに保存」を選ぶ運用にする。

### 25.3 ボタン名

```text
印刷・PDF保存
```

### 25.4 配置対象

```text
配置する：
- ZIP由来単体ビュー
- 月次チェック・差異確認

配置しない：
- 帳票選択メニュー
- ZIP読込ホーム
- 初期折りたたみの個別CSV読込エリア
```

### 25.5 ZIP由来単体ビューの方針

4帳票それぞれの単体ビュー上部に「印刷・PDF保存」ボタンを置く。
対象は表示中の単体帳票とする。

```text
- projects_summary：工事一覧・原価概要
- attendance_details：日報・労務費
- project_cost_details：請求書費用
- machine_details：重機台帳
```

### 25.6 月次チェック・差異確認の方針

月次チェック・差異確認にも「印刷・PDF保存」ボタンを置く。
横断確認結果を保存・共有できるようにする。

```text
- 確認リスト
- 差異確認
- 工事別まとめ
- 工事詳細表示
```

### 25.7 実装方針

```text
- window.print() を呼ぶだけの軽い実装にする
- 外部PDFライブラリは追加しない
- file:// 運用を維持する
- inline onclick は使わない
- addEventListener を使う
- 既存の印刷ボタン・印刷CSSがある場合は流用する
- 必要最小限のCSSだけ追加する
```

### 25.8 今回は実装しないこと

```text
- PDFライブラリ導入
- PDFファイル名の自動指定
- 自動ダウンロード
- サーバー保存
- Supabase Storage 保存
- 帳票選択メニューのPDF化
- ZIP生成処理の変更
- CSV解析・集計ロジックの変更
```

### 25.9 実装順序案

```text
Phase 2-4-9-5-a：ZIP由来単体ビューへの印刷・PDF保存ボタン追加
Phase 2-4-9-5-b：月次チェック・差異確認への印刷・PDF保存ボタン追加
Phase 2-4-9-5-c：印刷時CSSの最小調整
```

## 26. Phase 2-4-9-5-a：ZIP由来単体ビューへの印刷・PDF保存ボタン追加 実装結果

### 26.1 実装コミット

```text
55f9c0f Add print PDF button to ZIP single viewer
```

### 26.2 変更範囲

```text
local-viewers/csv-viewer.html のみ
```

### 26.3 実装目的

ZIP由来単体ビューで表示中の帳票を、ブラウザ標準の印刷機能から印刷・PDF保存できるようにする。

### 26.4 実装内容

```text
- #zipSingleBack 内に #zipSinglePrintBtn を追加
- ボタン文言は「印刷・PDF保存」
- #zipSinglePrintBtn は #zipSingleBack の子要素として配置
- #zipSingleBack の hidden 制御をそのまま継承
- click時は window.print() を実行
- addEventListener を使用
- inline onclick は使用しない
- PDFライブラリは追加しない
- 外部CDNは追加しない
```

### 26.5 表示対象

```text
- projects_summary：工事一覧・原価概要
- attendance_details：日報・労務費
- project_cost_details：請求書費用
- machine_details：重機台帳
```

### 26.6 表示しない対象

```text
- 帳票選択メニュー
- ZIP読込ホーム
- 初期折りたたみの個別CSV読込エリア
- 個別CSV読込由来の単体ビュー
- 月次チェック・差異確認
```

### 26.7 変更しなかったもの

```text
- CSV解析処理
- 集計ロジック
- ZIP出力ロジック
- ZIP読込ロジック
- openMultiReport
- openZipSingleReport の帳票切替ロジック
- buildSingleStateAndRender
- 個別CSV読込エリア
- 月次チェック・差異確認
- 印刷CSSの本格調整
```

### 26.8 回帰確認結果

```text
- 4帳票すべてで「印刷・PDF保存」ボタン表示OK
- window.print() 呼び出しOK
- 帳票選択メニューへ戻るとボタン非表示OK
- 個別CSV読込時はボタン非表示OK
- 月次チェック側には今回の新ボタンなし
- NaNなし
- Console重大エラーなし
- JS構文チェックOK
- git diff --check OK
```

### 26.9 最終判定

ZIP由来単体ビューで、外部PDFライブラリなしに印刷・PDF保存導線を追加できた。既存の帳票表示・集計・ZIP読込・個別CSV読込・月次チェックへの影響はない。

## 27. Phase 2-4-9-5-b：月次チェック・差異確認への印刷・PDF保存ボタン追加 実装結果

### 27.1 実装コミット

```text
7a495ce Move print PDF button to monthly check view
```

### 27.2 変更範囲

```text
local-viewers/csv-viewer.html のみ
```

### 27.3 実装目的

月次チェック・差異確認画面で、横断チェック結果をブラウザ標準の印刷機能から印刷・PDF保存できるようにする。

### 27.4 実装内容

```text
- multiPrintBtn を #multiBody 外側ヘッダから #multiIntegratedSection 内へ移動
- multiPrintBtn を multiIntegratedBack の右横に配置
- multiPrintBtn の文言を「印刷・PDF保存」に統一
- multiDetailPrintBtn の文言も「印刷・PDF保存」に統一
- multiPrintBtn は #multiIntegratedSection の hidden 制御を継承
- 既存の window.print() addEventListener は ID 不変のためそのまま有効
- 新しいPDFライブラリは追加しない
- 外部CDNは追加しない
- inline onclick は使用しない
```

### 27.5 表示対象

```text
- 月次チェック・差異確認
- 確認リスト
- 差異確認
- 工事別まとめ
- 工事詳細表示
```

### 27.6 表示しない対象

```text
- ZIP読込ホーム
- 帳票選択メニュー
- 初期折りたたみの個別CSV読込エリア
- 個別CSV読込由来の単体ビュー
```

### 27.7 変更しなかったもの

```text
- ZIP由来単体ビュー用 zipSinglePrintBtn
- CSV解析処理
- 集計ロジック
- ZIP出力ロジック
- ZIP読込ロジック
- openMultiReport
- openZipSingleReport
- showMultiIntegrated の内部集計処理
- 個別CSV読込エリア
- 印刷CSSの本格調整
```

### 27.8 回帰確認結果

```text
- 月次チェック・差異確認画面で multiPrintBtn 表示OK
- multiPrintBtn 文言「印刷・PDF保存」OK
- multiPrintBtn 押下で window.print() 呼び出しOK
- 帳票選択メニューへ戻ると親セクション hidden により非表示OK
- multiState.loaded 維持OK
- 4帳票 rows 保持OK
- zipSinglePrintBtn は変更なし・動作OK
- 個別CSV読込への影響なし
- 月次チェック内部処理への影響なし
- NaNなし
- Console重大エラーなし
- JS構文チェックOK
- git diff --check OK
```

### 27.9 最終判定

月次チェック・差異確認画面で、外部PDFライブラリなしに印刷・PDF保存導線を利用できるようになった。帳票選択メニューやZIP読込ホームでは表示されず、既存のZIP由来単体ビュー・個別CSV読込・集計処理への影響はない。
