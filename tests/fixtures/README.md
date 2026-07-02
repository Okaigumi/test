# tests/fixtures

Playwright 読み取り専用スモーク用の**合成ダミーデータ**置き場です。

## 重要（厳守）

- ここに置くデータは **すべて架空** です。実データ・実在の従業員名・実在の現場名・
  実際の金額や勤務実績・実際の有休情報は **一切含めません**。
- 従業員名は `テスト太郎` `テスト花子` `テスト次郎`、現場名は `架空現場A` `架空現場B`、
  日付は実在しない未来年 `2099` を使い、明らかにダミーと分かる値にしています。
- PII・社内情報は含めません。

## paid-leave-package/

管理コンソール出力ZIP（6CSV + manifest.json）の中身を、CSVテキストとして保持しています。
バイナリZIPはコミットせず、テスト実行時に `tests/helpers/zip.ts` でこれらから
ZIPを生成して csv-viewer に読み込ませます。

- `manifest.json` … 種別・行数・対象期間（2099年1月）
- `projects_summary.csv` … 工事2件（架空現場A/B）
- `attendance_details.csv` … 日報5件（テスト太郎/花子/次郎）
- `project_cost_details.csv` … 請求書2件
- `machine_details.csv` … 重機2件
- `paid_leave_details.csv` … 有休3件（full/am/pm を各1件）
- `paid_leave_balances.csv` … 残有給2件（テスト太郎/花子のみ。テスト次郎は意図的に無し
  ＝「残有給：—（データなし）」表示の確認用）
