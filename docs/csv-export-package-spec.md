# CSV出力パッケージ仕様

- 対象：管理コンソール（`admin-app.html`）のCSV出力 と ローカルCSVビューアー（`local-viewers/csv-viewer.html`）の複数CSV統合モード
- フェーズ：Phase 2-4-8-0「CSV出力パッケージ仕様設計」
- 状態：**設計完了。実装は未着手。**
- 対象：管理コンソールCSV出力、ローカルCSVビューアーZIP読込、`manifest.json`
- 関連：[`docs/csv-export-spec.md`](csv-export-spec.md) / [`docs/local-viewer-multi-csv-spec.md`](local-viewer-multi-csv-spec.md) / [`docs/roadmap.md`](roadmap.md)

本ドキュメントは設計仕様であり、ここに書かれたファイル名・構造・キーは実装時の指針である。
個々のCSV列定義は `docs/csv-export-spec.md`（Phase 1-2 CSV列定義）に準拠し、ZIP化しても変更しない。

---

## 1. 目的

- 管理コンソールが出力する4つのCSVを、利用者には1つのZIP出力パッケージとしてまとめて配布・保管・読み込みできるようにする。
- ローカルCSVビューアーで、ZIPを1つ選ぶだけで複数CSV統合モードに自動反映できるようにする。
- 出力パッケージのメタ情報（出力日時・対象期間・ファイル一覧・行数）を `manifest.json` として同梱し、ビューアー側の自動判定・出力内容確認・将来の互換性管理に使う。
- Supabase接続なし、外部CDNなし、`file://` で動くローカルHTMLビューアーとして維持する。

対象CSV（既存）：

```text
projects_summary.csv
attendance_details.csv
project_cost_details.csv
machine_details.csv
```

---

## 2. 基本方針

現在、管理コンソールのCSV出力は上記4ファイルに分かれている。
今後は、これら4CSVを内部的には個別に生成しつつ、利用者には1つのZIPファイルとして出力できるようにする。

```text
管理コンソール
→ 4CSVを生成
→ manifest.json を生成
→ 1つのZIPとしてダウンロード

ローカルCSVビューアー
→ ZIPを1つ選択
→ ZIP内の4CSVとmanifest.jsonを読み込む
→ 既存の複数CSV統合モードに自動反映
```

- 個別CSV出力は**廃止しない**。予備・検証・トラブル対応用として残す。
- ZIP化しても内部のCSV列定義は変更しない（`docs/csv-export-spec.md` を維持）。

### ZIP方式

**案A：ZIP処理ライブラリをローカル同梱する方式** を採用する。

- 外部CDNからZIPライブラリを読み込まない。
- `file://` で動作する状態を維持する。
- ZIPライブラリはリポジトリ内に同梱する。
- バージョンを固定する。
- ライブラリの入手元・バージョン・ライセンスを docs に記録する。
- ライブラリ追加は次フェーズ以降（2-4-8-1）で実施する。**今回はライブラリファイルを追加しない。**

将来の配置候補（実装前に最終決定）：

```text
local-viewers/vendor/jszip.min.js
```

または

```text
vendor/jszip/jszip.min.js
```

---

## 3. ZIPファイル名

対象年月範囲と出力日時が分かる形式にする。

推奨形式：

```text
okaigumi-csv-export_YYYYMM-YYYYMM_YYYYMMDD-HHMM.zip
```

例：

```text
okaigumi-csv-export_202604-202606_20260610-1530.zip
```

単月の場合：

```text
okaigumi-csv-export_202606-202606_20260610-1530.zip
```

---

## 4. ZIP内ファイル構成

ZIP内は以下を基本構成とする。

```text
okaigumi-csv-export_202604-202606_20260610-1530.zip
├ projects_summary.csv
├ attendance_details.csv
├ project_cost_details.csv
├ machine_details.csv
└ manifest.json
```

- 4CSVは原則すべて同梱する。
- 対象期間に該当データがないCSVは、ヘッダーのみまたは0行CSVとして同梱してよい。
- `manifest.json` に各CSVの行数を記録する（0行も行数0として記録）。

---

## 5. manifest.json

ZIP内には `manifest.json` を入れる。
manifest は、ビューアー側の自動判定・出力内容確認・将来の互換性管理に使う。

基本構造案：

```json
{
  "format_version": "1.0",
  "system": "okaigumi-internal-system",
  "exported_at": "2026-06-10T15:30:00+09:00",
  "period": {
    "from_month": "2026-04",
    "to_month": "2026-06",
    "granularity": "month",
    "label": "2026年4月〜2026年6月分"
  },
  "files": [
    { "type": "projects_summary", "name": "projects_summary.csv", "rows": 12 },
    { "type": "attendance_details", "name": "attendance_details.csv", "rows": 340 },
    { "type": "project_cost_details", "name": "project_cost_details.csv", "rows": 86 },
    { "type": "machine_details", "name": "machine_details.csv", "rows": 18 }
  ]
}
```

記録する項目：

- `format_version`
- `system`
- `exported_at`
- `period.from_month`
- `period.to_month`
- `period.granularity`
- `period.label`
- `files[].type`
- `files[].name`
- `files[].rows`

---

## 6. 出力期間

CSV出力パッケージの期間指定は **年月のみ** とする。日付指定は不要。

管理コンソール側の入力：

```text
開始年月：YYYY-MM
終了年月：YYYY-MM
```

例：

```text
開始年月：2026-04
終了年月：2026-06
表示ラベル：2026年4月〜2026年6月分
```

単月の場合：

```text
開始年月：2026-06
終了年月：2026-06
表示：2026年6月分
```

内部処理では、年月から日付範囲へ変換する。

```text
開始年月 2026-04 → 2026-04-01 以上
終了年月 2026-06 → 2026-07-01 未満
```

重要：

- 利用者には年月のみ選ばせる。
- UIに日付入力は出さない。
- SQL/RPC/集計処理では、裏側で月初〜翌月初未満に変換する。
- manifest には年月粒度で記録する。
- ZIPファイル名にも年月範囲を含める。

---

## 7. 管理コンソールUI案

管理コンソールのCSV出力画面は、将来的に以下の構成にする。

```text
CSV出力
├ 対象期間
│  ├ 開始年月
│  └ 終了年月
├ CSV一式をZIPで出力（推奨）
└ 個別CSV出力（詳細・予備）
   ├ projects_summary
   ├ attendance_details
   ├ project_cost_details
   └ machine_details
```

- 原則、通常運用では「CSV一式をZIPで出力」を使う。
- 個別CSV出力は、以下の用途で残す：
  - 検証
  - トラブル対応
  - 一部CSVだけ確認したい場合
  - ZIP読込に問題があった場合の切り分け

---

## 8. ローカルCSVビューアーUI案

ローカルCSVビューアーの複数CSV統合モードは、将来的に以下の構成へ変更する。

```text
複数CSV統合
├ CSV出力パッケージZIPを読み込む（推奨）
│  ├ ZIPファイル選択
│  ├ パッケージ情報
│  │  ├ 出力日時
│  │  ├ 対象期間
│  │  ├ format_version
│  │  └ ファイル一覧・行数
│  └ 読み込み結果
│     ├ projects_summary：OK / 行数
│     ├ attendance_details：OK / 行数
│     ├ project_cost_details：OK / 行数
│     └ machine_details：OK / 行数
└ 個別CSV読込（詳細・予備）
   ├ projects_summary
   ├ attendance_details
   ├ project_cost_details
   └ machine_details
```

重要方針：

- ZIP読込をメイン導線にする。
- 個別CSV読込は消さずに残す（「詳細・予備」扱い）。
- ZIP読込後は、既存の複数CSV統合処理を再利用する。
- 既存の労務費統合・請求書費用統合・月別原価・差異確認・確認リスト・印刷UIは壊さない。

---

## 9. 読み込み判定

ビューアーでZIPを読み込む場合、CSV種別の判定優先順位は以下とする。

```text
1. manifest.json の files[].type を優先
2. manifest がない場合はファイル名で判定
3. それでも不明な場合はCSVヘッダーで判定（既存 detectCsvType を流用）
```

---

## 10. エラー・警告方針

- `projects_summary.csv` がない場合はエラー（統合モードの必須CSV）。
- 任意CSV（attendance_details / project_cost_details / machine_details）がない場合は警告または未読込扱い。
- CSV種別が重複する場合は警告。
- 未知CSVが入っている場合は警告。
- `manifest.json` がない場合は警告しつつ、ファイル名・ヘッダー判定にフォールバックする。
- `format_version` が未対応の場合は警告。
- 0行CSVはエラーではなく、行数0として扱う。

---

## 11. セキュリティ・保管方針

- CSV出力パッケージZIPには、原価情報・従業員情報・請求書情報が含まれる。
- public URL、Vercel公開領域、public Storage には置かない。
- pCloud 等の保管先ではアクセス権限に注意する。
- CSV原本と同じく、ZIP原本も編集禁止とする。
- 加工する場合はコピーを作る。
- ZIPはpCloud上のCSV出力原本または出力パッケージフォルダに保存する。
- NASにはZIPもバックアップ対象として複製する。
- 外付けHDDへの月次退避対象にも含める候補とする。

（関連：`docs/roadmap.md`「CSV出力物・ビューアー保存場所・pCloud + NAS バックアップ運用ルール策定」）

---

## 12. 実装ステップ

ライブラリファイル追加を独立コミットで分ける方針を採用し、以下の番号構成とする。

```text
2-4-8-0：CSV出力パッケージ仕様設計（完了）
2-4-8-1：ZIPライブラリ同梱方針整理（完了）
2-4-8-2：ZIPライブラリ同梱（完了）
2-4-8-3：管理コンソール ZIP出力UI設計
2-4-8-4：管理コンソール ZIP出力実装
2-4-8-5：ローカルCSVビューアー ZIP読込UI設計
2-4-8-6：ローカルCSVビューアー ZIP読込実装
2-4-8-7：manifest.json 検証・表示対応
2-4-8-8：docs・運用手順整理
```

### 次フェーズ候補

```text
Phase 2-4-8-3：管理コンソール ZIP出力UI設計
```

---

## 13. ZIPライブラリ同梱方針（Phase 2-4-8-1）

- 状態：方針整理完了 / 実装：未着手 / ライブラリ本体追加：未実施
- 対象：ZIP生成・ZIP読込に使うJavaScriptライブラリの選定方針、配置方針、ライセンス記録方針
- **本フェーズではライブラリ本体（`*.min.js` 等）・`vendor` ディレクトリは追加しない。**

### 13.1 採用候補

ZIP処理ライブラリの第一候補は **JSZip** とする。

採用理由：

- ブラウザ上でZIP生成・ZIP読込の両方に対応できる
- 管理コンソール側のZIP生成に使える
- ローカルCSVビューアー側のZIP読込に使える
- JavaScriptだけで動作する
- `file://` 環境でのローカルビューアー運用に適している
- 外部CDNを使わず、ローカル同梱できる
- 今後のCSV出力パッケージ化と相性が良い

#### JSZip 調査結果（npm view, 取得時点）

```text
ライブラリ名：JSZip
バージョン（npm latest）：3.10.1
ライセンス：(MIT OR GPL-3.0-or-later)
入手元（homepage）：https://github.com/Stuk/jszip#readme
リポジトリ：git+https://github.com/Stuk/jszip.git
```

注記：上記は方針整理時点の npm 情報。実装時（2-4-8-2/2-4-8-3）に公式配布元・npm情報・ライセンスを再確認し、**バージョンを固定**する。

#### 同梱済みライブラリ（Phase 2-4-8-2 で実施）

```text
同梱済みライブラリ：
- JSZip v3.10.1
- 配置先：vendor/jszip/jszip.min.js
- ライセンスファイル：vendor/jszip/LICENSE.markdown
- 同梱メモ：vendor/jszip/README.md
- ライセンス：MIT OR GPL-3.0-or-later
- 入手元：npm package jszip@3.10.1
```

- 今回（2-4-8-2）はライブラリ本体の同梱のみ。
- 管理コンソール側のZIP生成実装は未着手。
- ローカルCSVビューアー側のZIP読込実装は未着手。
- HTMLからの読み込み（`<script src>` 追加）は未着手。
- 実装時はローカルファイル（`vendor/jszip/jszip.min.js`）として読み込む。**外部CDNは使わない。**

### 13.2 同梱方式

- 外部CDNから読み込まない
- ZIPライブラリはリポジトリ内に同梱する
- バージョンを固定する
- `file://` で動く構成を維持する
- ライブラリの出所・バージョン・ライセンスを docs に記録する

### 13.3 配置候補の比較

#### 案A：local-viewers配下に置く

```text
local-viewers/vendor/jszip.min.js
```

- メリット：ローカルCSVビューアーとの関係が分かりやすい／pCloud等にビューアー一式として配布しやすい／`file://` 運用時にパス関係を把握しやすい
- デメリット：管理コンソール側でも使う場合、別途参照パスを考える必要がある／ZIP生成とZIP読込で同じライブラリを共有する設計としては少し局所的

#### 案B：共通vendor配下に置く

```text
vendor/jszip/jszip.min.js
```

- メリット：管理コンソール側とローカルCSVビューアー側で共通ライブラリとして扱える／サードパーティライブラリの置き場として整理しやすい／将来、他ライブラリが増えた場合も拡張しやすい
- デメリット：ローカルCSVビューアーを単体配布する場合、`vendor` フォルダも一緒にコピーする必要がある／`file://` 運用時の相対パスを慎重に設計する必要がある

### 13.4 推奨方針

```text
推奨：案B vendor/jszip/jszip.min.js
```

理由：

- 管理コンソールのZIP出力とローカルCSVビューアーのZIP読込の両方で使う可能性があるため
- サードパーティライブラリを共通管理できるため
- バージョン・ライセンス・更新履歴を一元管理しやすいため

ただし、ローカルCSVビューアーを pCloud 等で配布する場合は、以下の一式を配布対象とする必要がある。

```text
local-viewers/csv-viewer.html
vendor/jszip/jszip.min.js
```

### 13.5 ライセンス記録方針

実際にライブラリを追加するフェーズでは、以下を必ず記録する。

```text
ライブラリ名
バージョン
入手元
ライセンス
取得日
配置パス
用途
更新方針
```

記録例：

```text
ライブラリ名：JSZip
バージョン：実装時に固定（方針整理時点の npm latest は 3.10.1）
入手元：npm または公式配布元（https://github.com/Stuk/jszip）
ライセンス：(MIT OR GPL-3.0-or-later)（実装時に再確認）
配置パス：vendor/jszip/jszip.min.js
用途：CSV出力パッケージZIPの生成・読込
更新方針：むやみに最新版へ更新せず、動作確認後に更新
```

### 13.6 セキュリティ方針

- 外部CDNを使わない
- 実行時に外部通信しない
- ZIP内のCSVはローカルで処理する
- CSV内容を外部へ送信しない
- ZIPには原価情報・従業員情報・請求書情報が含まれるため、public領域に置かない
- ZIPファイル名・manifestに必要以上の個人情報を入れない
- ZIP読込時は想定外ファイル・未知CSV・重複CSVを警告扱いにする
- ZIP内ファイルをHTMLとして実行しない
- CSV由来値は引き続き `textContent` / DOM API で表示する

### 13.7 実装時の注意

- ライブラリ追加コミットと実装コミットは分ける
- ライブラリ追加時は、minifiedファイルだけでなく出所・ライセンスを docs に記録する
- 外部CDN読み込みは禁止
- `script src` はローカルファイルのみ
- `file://` での動作確認を行う
- ZIP生成・ZIP読込の両方で同じバージョンを使う
- 既存CSV列仕様は変更しない
- 既存の個別CSV出力・個別CSV読込は残す
- ZIP対応後も個別CSVによるトラブル切り分けを可能にする

---

## 14. 管理コンソール ZIP出力UI設計（Phase 2-4-8-3）

- 状態：設計完了 / 実装：未着手
- 対象：管理コンソール（`admin-app.html`）のCSV出力画面、年月指定UI、ZIP出力ボタン、個別CSV出力の予備化
- 本フェーズは設計のみ。`admin-app.html` は変更しない。ZIP出力ロジックは実装しない。

### 14.1 基本方針

管理コンソールのCSV出力は、将来的に以下の構成にする。

```text
CSV出力
├ 対象期間
│  ├ 開始年月
│  └ 終了年月
├ CSV一式をZIPで出力（推奨）
└ 個別CSV出力（詳細・予備）
   ├ projects_summary
   ├ attendance_details
   ├ project_cost_details
   └ machine_details
```

- 通常運用では **「CSV一式をZIPで出力」** をメイン導線にする。
- 個別CSV出力は廃止せず、詳細・予備・トラブル対応用として残す。

### 14.2 対象期間UI

対象期間は **年月のみ**。日付指定は出さない。

```text
開始年月：YYYY-MM
終了年月：YYYY-MM
```

- 入力タイプ案：`<input type="month">`
- 表示例：`2026年4月〜2026年6月分`／単月は `2026年6月分`
- 内部処理では年月から日付範囲へ変換：
  - 開始年月 2026-04 → 2026-04-01 以上
  - 終了年月 2026-06 → 2026-07-01 未満

重要方針：

- 利用者には年月のみ選ばせる。
- 日付入力は出さない。
- SQL/RPC/集計処理では裏側で月初〜翌月初未満に変換する。
- `manifest.json` には年月粒度で記録する。
- ZIPファイル名にも年月範囲を含める。

### 14.3 ZIP出力ボタン

メインボタン：`CSV一式をZIPで出力（推奨）`

役割：

- 4CSVを内部生成する
- `manifest.json` を生成する
- JSZip（`vendor/jszip/jszip.min.js`）で1つのZIPにまとめる
- ZIPをダウンロードする

※ 本フェーズでは実装しない（UI設計のみ）。

### 14.4 個別CSV出力の扱い

既存の個別CSV出力は残す（配置案：`個別CSV出力（詳細・予備）`）。

残す理由：

- ZIP出力に問題があった場合の切り分け
- 1CSVだけ確認したい場合
- 会計事務所や社内確認で一部だけ渡したい場合
- 既存運用からの移行期間に必要
- ZIP読込側の検証にも使える

通常運用ではZIP出力を推奨する。

### 14.5 出力対象CSV

ZIPに含めるCSVは4つ：

```text
projects_summary.csv
attendance_details.csv
project_cost_details.csv
machine_details.csv
```

- 対象期間にデータがないCSVも、原則ヘッダーのみまたは0行CSVとして同梱する。
- `manifest.json` に行数を記録する。

### 14.6 ZIPファイル名

```text
okaigumi-csv-export_YYYYMM-YYYYMM_YYYYMMDD-HHMM.zip
```

例：`okaigumi-csv-export_202604-202606_20260610-1530.zip`／単月 `okaigumi-csv-export_202606-202606_20260610-1530.zip`

### 14.7 manifest.json

管理コンソール側でZIP出力するとき `manifest.json` を生成する（構造は §5 に準拠）。

```json
{
  "format_version": "1.0",
  "system": "okaigumi-internal-system",
  "exported_at": "2026-06-10T15:30:00+09:00",
  "period": {
    "from_month": "2026-04",
    "to_month": "2026-06",
    "granularity": "month",
    "label": "2026年4月〜2026年6月分"
  },
  "files": [
    { "type": "projects_summary", "name": "projects_summary.csv", "rows": 12 },
    { "type": "attendance_details", "name": "attendance_details.csv", "rows": 340 },
    { "type": "project_cost_details", "name": "project_cost_details.csv", "rows": 86 },
    { "type": "machine_details", "name": "machine_details.csv", "rows": 18 }
  ]
}
```

### 14.8 画面表示案

CSV出力画面に表示する説明：

```text
通常は「CSV一式をZIPで出力」を使用してください。
個別CSV出力は、検証・トラブル対応・一部CSV確認用です。
```

ZIP出力ボタン付近の説明：

```text
4つのCSVとmanifest.jsonを1つのZIPにまとめて出力します。
ローカルCSVビューアーでは、このZIPを1つ読み込むだけで複数CSV統合ビューを利用できます。
```

### 14.9 エラー・バリデーション方針

- 開始年月が空ならエラー
- 終了年月が空ならエラー
- 開始年月 > 終了年月ならエラー
- 対象期間が長すぎる場合は警告または確認表示を検討
- 出力対象が0件でも、ヘッダー付きCSVと `manifest.json` を出力できるようにする
- ZIP生成に失敗した場合は、個別CSV出力を案内する

### 14.10 セキュリティ・運用注意

- ZIPには原価情報・従業員情報・請求書情報が含まれる
- public URL、Vercel公開領域、public Storage には置かない
- pCloud・NAS等の保存先では権限管理に注意する
- ZIP原本は編集禁止
- 加工する場合はコピーを作る
- ZIPはCSV原本と同等以上に機密性の高いファイルとして扱う

### 14.11 実装時の注意

- JSZipは `vendor/jszip/jszip.min.js` を使う
- 外部CDNは使わない
- 既存の個別CSV出力関数を可能な限り再利用する
- 4CSVの列仕様は変更しない
- ZIP化してもCSV中身の列定義は維持する
- 個別CSV出力は削除しない
- ZIP出力実装コミットとビューアーZIP読込実装コミットは分ける
- ZIP出力後、ローカルCSVビューアーで読み込めることを確認する

---

## 15. 実装済み機能：Phase 2-4-8-4（管理コンソール ZIP出力実装）

実装コミット：`11b01aa Add admin CSV ZIP export`（対象：`admin-app.html`）

- 管理コンソールにZIP出力UIを実装。
- 開始年月・終了年月は `<input type="month">`。
- 個別CSV出力は詳細・予備として残す。
- JSZipは `vendor/jszip/jszip.min.js` をローカル参照。外部CDN不使用。
- 4CSVと `manifest.json` をZIPに格納。
- 既存RPCと既存CSV列定義を再利用（新規RPCなし）。
- ZIPファイル名は `okaigumi-csv-export_YYYYMM-YYYYMM_YYYYMMDD-HHMM.zip`。
- `manifest.json` は §5 仕様通り生成。
- 管理コンソール側では、終了年月を月末日に変換して既存RPCへ渡す。
  - 理由：既存RPCの `date_to_input` が inclusive 比較で使われる想定に合わせるため。
- ZIP出力実装は完了。ビューアー側ZIP読込は未実装。

### 設計上の注意（Phase 2-4-8-4 時点）

```text
CSV出力パッケージの利用者向け期間指定は年月粒度で統一する。

管理コンソール実装では、既存RPC仕様に合わせ、開始年月は月初日、終了年月は月末日に変換してRPCへ渡す。

manifest.json とZIPファイル名には年月情報のみを保持し、日付粒度の操作を利用者に見せない。
```

---

## 16. ローカルCSVビューアー ZIP読込UI設計（Phase 2-4-8-5）

- 状態：設計完了 / 実装：未着手
- 対象：ローカルCSVビューアー（`local-viewers/csv-viewer.html`）の複数CSV統合モード、ZIP読込導線、manifest表示、個別CSV読込の予備化
- 本フェーズは設計のみ。`local-viewers/csv-viewer.html` は変更しない。ZIP読込は実装しない。HTMLへの `<script>` 追加もしない。

### 16.1 基本方針

複数CSV統合モードは、将来的に以下の構成にする。

```text
複数CSV統合
├ CSV出力パッケージZIPを読み込む（推奨）
│  ├ ZIPファイル選択
│  ├ パッケージ情報
│  ├ ZIP内ファイル一覧
│  ├ 読み込み結果
│  └ 読み込み実行・クリア
└ 個別CSV読込（詳細・予備）
   ├ projects_summary
   ├ attendance_details
   ├ project_cost_details
   └ machine_details
```

- 通常運用では **ZIP読込をメイン導線** にする。
- 個別CSV読込は削除せず、詳細・予備・トラブル対応用として残す。

### 16.2 ZIP読込カード

複数CSV統合モードの上部に「CSV出力パッケージZIPを読み込む（推奨）」カードを追加する。

UI案：ZIPファイル選択 / 選択中ファイル名 / パッケージ情報 / 読み込み結果 / ZIPを読み込む・クリア

説明文：

```text
管理コンソールで出力したCSV一式ZIPを選択してください。
4つのCSVとmanifest.jsonを自動で読み込み、複数CSV統合ビューに反映します。
```

### 16.3 個別CSV読込の扱い

既存の個別CSV読込UIは残す（見出し案：`個別CSV読込（詳細・予備）`）。

注記案：

```text
個別CSV読込は、検証・トラブル対応・一部CSVのみ確認したい場合に使用します。通常運用ではZIP読込を推奨します。
```

- 既存の4CSV個別読込は削除しない。
- 既存の複数CSV統合処理は壊さない。
- ZIP読込後も個別CSVで再読込・差し替えできるかは実装時に検討する。
- 少なくともトラブル時に個別CSV読込へ戻れる設計にする。

### 16.4 ZIP読込後の表示情報

パッケージ情報：

```text
ファイル名 / 出力日時 exported_at / 対象期間 period.label / format_version / system / manifest 読込状態
```

ZIP内ファイル一覧（type / name / rows / 読込状態）。表示例：

```text
projects_summary：projects_summary.csv / 12行 / OK
attendance_details：attendance_details.csv / 340行 / OK
project_cost_details：project_cost_details.csv / 86行 / OK
machine_details：machine_details.csv / 18行 / OK
manifest.json：OK
```

### 16.5 CSV種別判定方針

優先順位：

```text
1. manifest.json の files[].type
2. ファイル名
3. CSVヘッダー（既存 detectCsvType）
```

- manifest.json がある場合は files[].type を最優先にする。
- manifest.json がない場合は警告を出し、ファイル名・ヘッダー判定へフォールバックする。
- unknown CSV がある場合は警告する。
- 同一 type が重複する場合は警告する。
- projects_summary がない場合はエラー。
- 任意CSVがない場合は未読込扱いまたは警告。
- 0行CSVはエラーではなく、行数0として扱う。

### 16.6 既存処理の再利用

ZIP読込後は、既存の複数CSV統合処理を再利用する。

```text
multiState / 各CSV読込処理 /
buildMultiLaborSummaries / buildMultiInvoiceSummaries / buildMultiMonthlyCostSummaries /
buildMultiReconciliation / buildMultiCrossChecks /
renderMultiStatus / renderMultiProjectList / renderMultiCrossChecks /
工事別詳細表示 / 印刷・PDF保存
```

- ZIP読込は「4CSVを自動で各枠に流し込む入口」として扱う。
- 集計ロジックは変更しない。CSV列仕様は変更しない。
- ZIP対応後も個別CSV読込と同じ結果になることを目標にする。

### 16.7 UI状態

```text
未選択 / 選択済み / 読込中 / 読込成功 / 警告あり / エラー / クリア済み
```

状態ごとの表示例：

```text
未選択：ZIPファイルを選択してください
選択済み：ファイル名を表示
読込中：ZIP読込中...
読込成功：CSV一式を読み込みました
警告あり：一部CSVに警告があります
エラー：projects_summary.csv が見つかりません
```

### 16.8 エラー・警告方針

エラー扱い：

```text
ZIPファイルが読めない
JSZipが読み込めない
projects_summary が見つからない
CSVとして解析できない必須ファイル
manifest.json が壊れていて、フォールバック判定もできない
```

警告扱い：

```text
manifest.json がない
format_version が未対応
任意CSVがない
unknown CSV が含まれる
同一CSV type が重複
manifest の rows と実CSV行数が合わない
0行CSV
```

0行CSVは原則エラーではなく、行数0として扱う。

### 16.9 JSZip参照パス

`local-viewers/csv-viewer.html` からJSZipを参照する場合の相対パス：

```html
<script src="../vendor/jszip/jszip.min.js"></script>
```

理由：`csv-viewer.html` は `local-viewers/` 配下、JSZip は `vendor/jszip/` 配下のため、相対パスは `../vendor/jszip/jszip.min.js`。

- 外部CDNは使わない。
- `file://` 動作を維持する。
- pCloud等で配布する場合は、`local-viewers/csv-viewer.html` と `vendor/jszip/jszip.min.js` の相対位置を保つ必要がある。

### 16.10 セキュリティ方針

- ZIP読込はローカルブラウザ内で完結する。
- CSV内容を外部送信しない。
- 外部CDNは使わない。
- ZIP内ファイルをHTMLとして実行しない。
- ZIP内のCSV由来値は引き続き `textContent` / DOM API で描画する（`innerHTML` にCSV由来値を入れない）。
- 原価情報・従業員情報・請求書情報を含むため、ZIPの取り扱いはCSV原本と同等以上に注意する。

### 16.11 印刷/PDFとの関係

- ZIP読込後の統合ビューも印刷対象。
- パッケージ情報は印刷対象に含める。
- ZIPファイル選択や読込ボタンは印刷対象外。
- 確認リスト・差異確認・月別原価の印刷レイアウトは既存を維持する。

### 16.12 実装ステップ案

```text
2-4-8-6：ローカルCSVビューアー ZIP読込実装
2-4-8-7：manifest.json 検証・表示対応
2-4-8-8：管理コンソールZIPとビューアーZIP読込の結合確認
2-4-8-9：docs・運用手順整理
```

実装を細かく分けるなら：

```text
2-4-8-6：ビューアーJSZip読込導線追加
2-4-8-7：ZIP展開・CSV自動割当
2-4-8-8：manifest検証・パッケージ情報表示
2-4-8-9：実ZIP結合確認・docs整理
```

---

## 17. 実装済み機能：Phase 2-4-8-6（ローカルCSVビューアー ZIP読込実装）

実装コミット：`c867027 Add viewer ZIP package import`（対象：`local-viewers/csv-viewer.html`）

- ローカルCSVビューアーにZIP読込機能を実装。
- JSZipは `../vendor/jszip/jszip.min.js` をローカル参照（外部CDN不使用）。
- ZIP読込UIを複数CSV統合モード上部に追加。
- 個別CSV読込は詳細・予備として残す。
- ZIP内CSVはmanifest優先でCSV種別判定。
- manifestなしの場合はファイル名・CSVヘッダーでフォールバック。
- 既存の `multiState` と集計・描画処理を再利用。
- ZIP読込時は既存状態を置換し、古いCSVとの混在を防止。
- パッケージ情報・ZIP内ファイル一覧を表示。
- エラー・警告表示を実装。
- 印刷時はパッケージ情報を残し、ZIP操作UIは印刷対象外。
- ZIP読込実装は完了。
- 管理コンソールZIPとの実ログイン環境での実ZIPによる通し確認は次フェーズ以降。

### 設計上の注意（Phase 2-4-8-6 時点）

```text
ZIP読込は、既存の複数CSV統合処理への入力導線であり、集計ロジックそのものは変更しない。

CSV列仕様は個別CSV読込と同一である。

ZIP読込後も個別CSV読込を予備導線として残す。

manifest.json はCSV種別判定とパッケージ情報表示に使うが、manifestがない場合もファイル名・CSVヘッダー判定で可能な範囲で読み込む。
```

---

## 18. 実確認済み：Phase 2-4-8-8（管理コンソールZIPとビューアーZIP読込の結合確認）

種別：通し確認のみ（実装変更なし）。本番adminで出力した実ZIPを使って確認済み。

- 対象期間：2026-06〜2026-06（`period.label`：`2026年6月分`）
- ZIPファイル名：`okaigumi-csv-export_202606-202606_20260610-1446.zip`（16,503 bytes）
- ZIP内5ファイル確認済み（projects_summary 10行 / attendance_details 41行 / project_cost_details 0行 / machine_details 22行 / manifest.json）
- 各CSVにUTF-8 BOMあり・ヘッダーは `CSV_COLUMNS` と一致・列数 23/20/13/10
- manifest確認済み（format_version 1.0 / system / exported_at +09:00 / period / files[].type・name・rows）
- manifest rows と実CSV行数は全て一致
- ローカルCSVビューアーでZIP読込成功（パッケージ情報・ZIP内ファイル一覧・読込状態表示OK）
- manifest優先判定で4CSVを正しく割当成功
- 複数CSV統合ビュー反映成功（工事件数10・労務費合計902,000円・月別原価合計902,000円・エラー0・NaNなし）
- 工事詳細表示成功（差異確認カード全項目一致・月別原価・労務明細）
- 印刷/PDF確認成功（パッケージ情報・確認リスト・差異確認・月別原価は印刷対象、ZIP操作UI・戻るボタンは印刷対象外、PDF保存OK）
- 一時ファイル（展開CSV・manifest・PDF・一時サーバースクリプト）はリポジトリ外で扱い、確認後に削除済み。リポジトリ混入なし。
- 2026-06は project_cost_details が0行のため、請求書費用統合は0件ケースとして確認済み（0行CSVはエラーではなく警告・確認事項として扱う動作を実確認）。
- 請求書明細あり期間（例：2026-04〜2026-06）での追加確認は今後の候補。

---

## 19. 運用手順・保管方針（Phase 2-4-8-9）

- 運用手順は [`docs/csv-export-operation-guide.md`](csv-export-operation-guide.md) に整理済み。
- ZIP原本は編集禁止。
- 現時点では pCloud を日常保管、外付けHDDを暫定バックアップとして扱う。
- UGREEN NASync は後日購入予定（現時点では未導入）。
- UGREEN NASync導入後の保存運用は operation guide を参照。
- ビューアー配布時は `local-viewers/` と `vendor/jszip/` の相対位置を維持する。

---

## 20. ZIP読込後のUX方針（Phase 2-4-9-0）

設計：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md)

- ZIP読込後のUX方針を修正する。
- ZIP読込後に直接統合ビューへ入るのではなく、帳票選択メニューを表示する。
- 各CSVは単体CSVビュー相当の画面で確認できるようにする。
- 統合ビューは「月次チェック・差異確認」として最終確認用に残す。
- 本方針は設計のみ。実装は次フェーズ以降（ZIP読込・出力ロジック・CSV列仕様は変更しない）。

### Phase 2-4-9-1 実装済み（帳票選択メニュー）

実装コミット：`08be5ac Add CSV ZIP report selection menu`

- CSV ZIP読込後、帳票選択メニューを表示する実装が追加された。
- 各CSVの行数をカードに表示する。
- `project_cost_details.csv` が0件の場合も正常案内を表示する。
- 統合ビューは「月次チェック・差異確認」としてメニューから開く。
- 各単体CSV帳票カードから単体CSVビューへの接続は次フェーズ（2-4-9-2）で実施予定。
- ZIP読込後の帳票カードは、次フェーズでZIP由来rowsを単体CSVビュー形式で表示する方針（Phase 2-4-9-2-a 設計：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md) §14）。`project_cost_details` 0件は正常な空表示として扱う。
- Phase 2-4-9-2-b（コミット `64c699b`）で、ZIP内CSVを単体CSVビューへ接続するための前提として handleText 分離を実装済み。帳票カード接続は次フェーズ予定。
- Phase 2-4-9-2-c（コミット `f2b1b1c`）で、ZIP読込後の「工事一覧・原価概要」カードから ZIP内 `projects_summary.csv` を単体CSVビュー形式で表示できるようになった。他帳票は次フェーズ以降で接続予定。
- Phase 2-4-9-2-d（コミット `c7b1cc4`）で、ZIP読込後の「日報・労務費」カードから ZIP内 `attendance_details.csv` を単体CSVビュー形式で表示できるようになった。`project_cost_details` / `machine_details` は次フェーズ以降で接続予定。
- Phase 2-4-9-2-e（コミット `34d5d73`）で、ZIP読込後の「請求書費用」カードから ZIP内 `project_cost_details.csv` を単体CSVビュー形式で表示できるようになった。0件CSVでも正常表示する。`machine_details` は次フェーズで接続予定。
- Phase 2-4-9-2-f（コミット `26d7a30`）で、ZIP読込後の「重機台帳」カードから ZIP内 `machine_details.csv` を単体CSVビュー形式で表示できるようになった。これにより帳票選択メニューの4カードすべてが接続済み。
- Phase 2-4-9-2-g で、ZIP読込後の4帳票単体ビュー接続について総合回帰確認を実施し、全90項目PASSを確認した。これにより Phase 2-4-9-2 は完了。
- Phase 2-4-9-3 で、ZIP読込後UXの微調整方針を整理した。通常運用ではZIP読込を主導線とし、個別CSV読込は詳細・トラブル対応用として扱う。
- Phase 2-4-9-3-a で、ZIP読込後の帳票選択メニューを「個別帳票を確認」と「横断チェック」に分け、運用時に迷いにくい文言へ調整した。
- Phase 2-4-9-3-b で、個別CSV読込エリアを「詳細・トラブル対応用」として初期折りたたみに変更した。通常運用ではZIP読込を主導線とし、個別CSV読込は補助導線として残す。
- Phase 2-4-9-3-c で、ZIP由来単体ビューの上部情報を整理し、帳票名・読込元CSV・対象期間を分かりやすく表示するようにした。
- Phase 2-4-9-5 で、帳票確認後の印刷・PDF保存導線を整備する方針を整理した。PDFライブラリは追加せず、ブラウザ標準の `window.print()` を使う。
- Phase 2-4-9-5-a で、ZIP由来単体ビューに「印刷・PDF保存」ボタンを追加した。PDFライブラリは追加せず、ブラウザ標準の `window.print()` を使う。
- Phase 2-4-9-5-b で、月次チェック・差異確認画面にも「印刷・PDF保存」導線を整理した。PDFライブラリは追加せず、ブラウザ標準の `window.print()` を使う。
- Phase 2-4-9-5-c で、印刷時CSSを最小調整した。操作UIは印刷時に非表示とし、帳票本体・月次チェック結果・工事詳細表示を印刷対象として残す。
- Phase 2-4-9-6 で、CSVビューアーの運用前最終確認を実施し、ZIP読込・単体帳票・月次チェック・印刷導線・個別CSV読込について重大な問題なしと判定した。
- Phase 2-4-9-7 で、高齢者向けGUI改善としてCSV一式ZIP読込を初期導線にし、単体CSV読込・個別CSV読込を通常画面から外した。ZIP読込後は帳票選択メニューを主役にし、文字サイズ・コントラスト・説明文も読みやすい方向へ調整した。
- Phase 2-4-9-8 で、実ブラウザ・実ZIP・印刷PDF出力による手動確認を実施した。確認中に見つかった mode-tabs 非表示不具合は Phase 2-4-9-8-a で修正済み。
- Phase 2-4-9-8-d〜8-f で、管理コンソール側の出力導線を「CSV一式をZIPで出力」に一本化し、帳票確認画面では「管理コンソールで出力したZIP」を選択して自動読込する流れに整理した。ZIP以外の出力導線は通常画面から非表示とした。
