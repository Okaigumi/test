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
