# CSV出力・ZIPパッケージ・ローカルCSVビューアー運用手順

> 関連設計：
> - 出力パッケージ仕様：[`docs/csv-export-package-spec.md`](csv-export-package-spec.md)
> - CSV列仕様：[`docs/csv-export-spec.md`](csv-export-spec.md)
> - 複数CSV統合ビュー：[`docs/local-viewer-multi-csv-spec.md`](local-viewer-multi-csv-spec.md)
> - ローカルビューアー基本設計：[`docs/local-viewer-spec.md`](local-viewer-spec.md)

## 1. 目的

- 管理コンソールから月次・期間指定でCSV一式ZIPを出力する。
- ZIPには4CSVと `manifest.json` を含める。
- ローカルCSVビューアーでZIPを1つ読み込み、複数CSV統合ビューで確認する。
- 原価・労務・請求書・重機台帳の確認を社内で行う。
- 必要に応じて会計事務所や社内確認用にCSV・PDFを利用する。

## 2. 対象ファイル

ZIP内ファイル：

```text
projects_summary.csv
attendance_details.csv
project_cost_details.csv
machine_details.csv
manifest.json
```

説明：

- `projects_summary.csv`：工事概要・請負金額・原価概要
- `attendance_details.csv`：日報・労務費明細
- `project_cost_details.csv`：請求書費用明細
- `machine_details.csv`：重機台帳
- `manifest.json`：出力日時・対象期間・CSV種別・行数情報

## 3. 月次出力手順

管理者向けの手順：

```text
1. 管理コンソールにログインする
2. CSV出力ページを開く
3. 開始年月・終了年月を選択する
4. 「CSV一式をZIPで出力（推奨）」を押す
5. ZIPファイル名を確認する
6. ZIPを所定フォルダに保存する
7. ローカルCSVビューアーでZIPを読み込む
8. 統合ビュー・確認リスト・差異確認を確認する
9. 必要に応じてPDF保存する
10. ZIP原本と確認PDFを保管する
11. 現時点では外付けHDDへ暫定バックアップする
12. UGREEN NASync導入後は、NASへも定期複製する
```

ZIPファイル名ルール：

```text
okaigumi-csv-export_YYYYMM-YYYYMM_YYYYMMDD-HHMM.zip
```

例：

```text
okaigumi-csv-export_202606-202606_20260610-1446.zip
```

### ビューアーでの確認導線（Phase 2-4-9-0 設計、実装は次フェーズ以降）

設計：[`docs/csv-viewer-ux-improvement-spec.md`](csv-viewer-ux-improvement-spec.md)

- ZIPを読み込んだ後は、まず帳票選択メニューから見たい帳票を選ぶ方針に変更する。
- 通常確認は、工事一覧・日報労務費・請求書費用・重機台帳の各帳票画面を使う。
- 月次チェック・差異確認は、最終確認や不一致確認のために使う。
- 個別CSV読込は通常運用では使わず、トラブル対応用とする。
- 上記の新導線はビューアー側の改修後に有効になる。改修前は、ZIP読込後に複数CSV統合ビューへ直接入る現行構成のまま。

## 4. 推奨フォルダ構成

pCloudを日常保管、外付けHDDを現時点の暫定バックアップ、UGREEN NASyncを将来の社内バックアップとして整理する。

### 現時点：pCloud 日常保管

```text
pCloud/
└ 岡井組_社内業務システム/
   ├ 00_ビューアー/
   │  ├ local-viewers/
   │  │  └ csv-viewer.html
   │  └ vendor/
   │     └ jszip/
   │        └ jszip.min.js
   ├ 01_CSV出力ZIP原本/
   │  └ 2026/
   │     └ 2026-06/
   │        └ okaigumi-csv-export_202606-202606_YYYYMMDD-HHMM.zip
   ├ 02_確認PDF/
   │  └ 2026/
   │     └ 2026-06/
   ├ 03_会計事務所提出用/
   │  └ 2026/
   │     └ 2026-06/
   └ 99_運用メモ/
```

### 現時点：外付けHDD 暫定バックアップ

```text
外付けHDD/
└ 岡井組_社内業務システム_月次退避/
   ├ CSV出力ZIP原本/
   ├ 確認PDF/
   ├ ビューアー配布コピー/
   └ Supabaseバックアップ/
```

### 将来：UGREEN NASync 導入後の想定フォルダ構成

```text
UGREEN_NASync/
└ 岡井組_社内業務システム_バックアップ/
   ├ CSV出力ZIP原本/
   ├ 確認PDF/
   ├ ビューアー配布コピー/
   └ Supabaseバックアップ/
```

注意：

- NASは現時点では未導入。
- 後日、UGREEN NASync を購入予定。
- NAS導入後は、pCloud内のCSV出力ZIP原本・確認PDF・ビューアー配布コピー・Supabaseバックアップを定期複製する予定。
- NAS導入までは、外付けHDDを暫定バックアップ先として扱う。

## 5. ビューアー配布時の注意

- `csv-viewer.html` 単体だけをコピーしない。
- `local-viewers/csv-viewer.html` と `vendor/jszip/jszip.min.js` の相対位置を維持する。
- pCloudやUSBで配布する場合も、以下の構成を保つ。

```text
配布フォルダ/
├ local-viewers/
│  └ csv-viewer.html
└ vendor/
   └ jszip/
      └ jszip.min.js
```

理由：

```text
csv-viewer.html は ../vendor/jszip/jszip.min.js を参照しているため。
```

## 6. 保存ルール

- ZIP原本は編集禁止。
- CSV原本も編集禁止。
- 加工する場合は必ずコピーを作る。
- ZIPを展開したCSVを編集して原本扱いしない。
- PDF保存物は確認記録として扱う。
- 会計事務所へ渡す場合は、必要なファイルだけコピーして渡す。
- public URL、Vercel公開領域、public Storageには置かない。
- メール添付する場合は送信先を確認する。
- pCloud共有リンクを作る場合は閲覧権限・有効期限に注意する。

## 7. 月次確認チェックリスト

### 現時点の月次チェック

```text
□ ZIPファイル名が対象年月と一致している
□ ZIP内に4CSV + manifest.json がある
□ manifest の from_month / to_month が対象年月と一致している
□ manifest rows と実CSV行数が一致している
□ ローカルCSVビューアーでZIP読込できる
□ projects_summary が読み込まれている
□ attendance_details が読み込まれている
□ project_cost_details が読み込まれている
□ machine_details が読み込まれている
□ 確認リストに重大な異常がない
□ 差異確認を確認した
□ NaN表示がない
□ 必要な工事詳細を確認した
□ 必要に応じてPDF保存した
□ ZIP原本をpCloudに保存した
□ 外付けHDDへ暫定バックアップした
□ 一時展開したCSVを削除した
```

### UGREEN NASync導入後の追加チェック

```text
□ pCloudからUGREEN NASyncへバックアップした
□ UGREEN NASync側にZIP原本が保存されている
□ UGREEN NASync側に確認PDFが保存されている
□ UGREEN NASyncの同期またはバックアップログを確認した
□ UGREEN NASyncの空き容量を確認した
```

## 8. 0行CSVの扱い

- 0行CSVは直ちにエラーではない。
- 対象期間に請求書がなければ `project_cost_details.csv` が0行になることがある。
- ビューアーでは警告または確認事項として表示される。
- 0行でもヘッダーとmanifest rowsが正しければ正常扱い。
- ただし、想定外に0行の場合は対象期間・登録状況を確認する。

## 9. 確認リスト・差異確認の扱い

- 差異確認はエラーではなく確認事項。
- `projects_summary` と再集計値が一致しない場合は、登録タイミング・対象期間・未分類費用を確認する。
- `project_cost_details` が0行の場合、請求書明細なしの確認事項が出ることがある。
- `machine_details` は現状、重機台帳として扱い、工事別月別原価に直接配賦しない。
- 最終判断は帳票・請求書・日報の実態確認で行う。

## 10. 会計事務所へ渡す場合

- 原則、ZIP原本または必要CSVのコピーを渡す。
- ZIP原本を渡す場合、原価・従業員・請求書情報を含むことを理解する。
- 必要があればPDF確認表も添付する。
- 送付前に対象期間を確認する。
- 不要な期間や不要なCSVを渡さない。
- 共有リンクの権限・期限を設定する。

## 11. バックアップ運用

### 現時点

```text
日常保管：pCloud
暫定バックアップ：外付けHDD
```

### 将来

```text
日常保管：pCloud
社内バックアップ：UGREEN NASync
最終退避：外付けHDD
```

バックアップ対象：

- CSV出力ZIP原本
- 確認PDF
- ビューアー配布コピー
- Supabase DBバックアップzip
- Supabase Storage photosバックアップzip

注意：

- ZIP原本とDBバックアップは性質が違うため、フォルダを分ける。
- CSV出力ZIPは業務確認・会計確認用。
- DBバックアップは復旧用。
- Storage photosバックアップは写真復旧用。
- お知らせ添付のPDF/画像を今後バックアップ対象に含める場合は別途方針を決める。
- UGREEN NASync導入までは、外付けHDDを暫定バックアップ先として扱う。

## 12. 削除・復元ルール

- ZIP原本は原則削除しない。
- 誤って出力したZIPは「誤出力」フォルダへ移す。
- 削除前にpCloudと外付けHDDの保存状況を確認する。
- UGREEN NASync導入後は、NAS側にバックアップがあるかも確認する。
- 復元時は、現時点ではpCloud、外付けHDDの順で確認する。
- UGREEN NASync導入後は、pCloud、UGREEN NASync、外付けHDDの順で確認する。
- 原本かコピーかを必ず確認する。
- 復元後はビューアーで読み込めるか確認する。

## 13. セキュリティ注意

- ZIPには原価情報・従業員情報・請求書情報が含まれる。
- CSVやZIPをpublicに置かない。
- GitHubへ実データZIPをcommitしない。
- Vercel公開領域へ置かない。
- Supabase public Storageへ置かない。
- 共有リンクをむやみに作らない。
- 共有後は不要になったリンクを停止する。
- メール誤送信に注意する。

## 14. 推奨運用頻度

- 月次：CSV一式ZIP出力、ビューアー確認、pCloud保存、外付けHDD暫定バックアップ。
- UGREEN NASync導入後の月次：pCloudからUGREEN NASyncへの複製確認。
- 四半期：請求書明細あり期間で統合確認。
- 半期：ビューアー配布コピーの更新確認。
- 年次：年度別フォルダ整理、外付けHDD退避。

## 15. 未決事項

- pCloud正式フォルダ名
- UGREEN NASync の購入時期
- UGREEN NASync の容量
- UGREEN NASync のRAID構成
- pCloudからUGREEN NASyncへの同期方法
- UGREEN NASync のスナップショット設定
- UGREEN NASync 導入までの外付けHDDバックアップ頻度
- 外付けHDD退避頻度
- 会計事務所への標準提出形式
- ZIP原本の保存年限
- 閲覧権限者
- 削除承認ルール
- お知らせ添付ファイルのバックアップ対象化
