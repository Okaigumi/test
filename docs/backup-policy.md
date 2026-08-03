# バックアップ方針

## 前提・必要ツール

- Node.js（npx が使えること）
- npx --yes supabase（Supabase CLI を npx 経由で実行）
- **Docker Desktop（現行方式では必須）**：現行の Supabase CLI による Windows 上のバックアップ方式では、`db dump` の実行に Docker を使用します。Docker が未導入または未起動だと `LegacyDockerRunError` で失敗します。
  - 検証済み環境：この自宅 PC（Windows）では Docker Desktop を **WSL 2 backend** で使用しています（WSL 2 は本環境での構成であり、全 OS 共通の必須条件ではありません）。
- Windows PowerShell 5.1 以上（PowerShell 7 推奨）
- `.env.backup.local`（接続文字列を記載したローカル専用ファイル）

Node.js と npx がインストールされていない場合、スクリプトは起動直後に停止します。
Docker Desktop が起動していない場合、DBバックアップは dump 実行時に失敗します。事前に Docker Desktop を起動してください。

取得実績（世代・checksum・対象範囲）は `docs/backup-recovery-inventory.md` に記録します。

## バックアップ対象

| 対象 | ファイル | 備考 |
|------|----------|------|
| ロール・権限定義 | roles.sql | DB ロールと権限 |
| スキーマ定義 | schema.sql | テーブル・関数・ポリシー等 |
| データ | data.sql | 全テーブルのレコード（COPY形式） |

### Supabase Storage（写真）について

`index.html` の日報機能は Supabase Storage の `photos` バケットに写真を保存しています。

**DBバックアップだけでは写真データは保護されません。**

写真バックアップは `scripts/backup-supabase-storage.ps1` で実施します（詳細は後述）。

## バックアップ手順

### 1. DBバックアップ（毎回実施）

1. `.env.backup.local` が存在することを確認する
   - 存在しない場合は `.env.backup.local.example` を参考に作成する
2. PowerShell を開き、プロジェクトルートへ移動する
3. スクリプトを実行する

```powershell
.\scripts\backup-supabase.ps1
```

4. `backups\YYYYMMDD-HHMMSS.sql.zip` が作成されたことを確認する
5. zip ファイルを安全な場所（外付けHDD・クラウドストレージ等）に保存する

### 2. Storage 写真バックアップ（DBバックアップの後に実施）

**方式：** `reports.photo_urls` に記録済みの Public URL をもとにダウンロードする。

**対象：** `photos` バケットのうち、日報 (`reports`) テーブルの `photo_urls` に記録された写真のみ。

**対象外（現行方式でバックアップされないもの）：**

- Storage 上の孤立ファイル（アップロード成功後に DB 更新が失敗した例外ケース）
- バケット `notice-attachments`
- バケット `invoice-pdfs`

このため、DB バックアップと Storage バックアップを両方取得しても「完全バックアップ」にはなりません。対象範囲の全体像は `docs/backup-recovery-inventory.md` を参照してください。

**秘密情報：** service role key は使用しない。Supabase Storage List API は使用しない。  
`.env.backup.local` への追加設定は不要（写真は Public URL から直接ダウンロードできる）。

#### 実行手順

1. DBバックアップを完了し、`backups\YYYYMMDD-HHMMSS.sql.zip` が存在することを確認する
2. PowerShell を開き、プロジェクトルートへ移動する
3. スクリプトを実行する

```powershell
.\scripts\backup-supabase-storage.ps1 -SqlZipPath .\backups\YYYYMMDD-HHMMSS.sql.zip
```

4. 結果を確認する

```
OK=N  SKIPPED=0  ERROR=0
Complete : backups\YYYYMMDD-HHMMSS-storage.zip
```

#### 出力

| ファイル | 内容 |
|---------|------|
| `backups\YYYYMMDD-HHMMSS-storage.zip` | zip（ERROR=0 の場合のみ作成） |
| zip内 `photos\{reportId}\{filename}.jpg` | 日報に紐付いた写真ファイル |
| zip内 `storage-backup-manifest.csv` | ファイル単位のダウンロード結果（OK / SKIPPED / ERROR） |
| zip内 `backup-info.txt` | 実行日時・件数サマリー |

#### ERROR が出た場合

- zip は作成されず、`backups\YYYYMMDD-HHMMSS-storage\` フォルダが残る
- 残ったフォルダの `storage-backup-manifest.csv` の ERROR 行を確認する
- 原因を解消してから再実行する
- 再実行時は通常、新しいタイムスタンプのバックアップフォルダが作成され、全 URL を再取得する
- 同じ出力フォルダ内に同名ファイルが既に存在する場合のみ SKIPPED として記録される
- 不要になった ERROR フォルダは内容確認後に手動削除する
- スクリプトは `exit 1` で終了する

#### 再実行時の注意

- 同じ出力フォルダ内に同名ファイルがある場合のみ上書きせず SKIPPED として記録する
- 通常の再実行では新しいタイムスタンプフォルダへ全件ダウンロードされる
- `-DataSqlPath` を使えば zip 展開済みの `data.sql` を直接指定することもできる

```powershell
.\scripts\backup-supabase-storage.ps1 -DataSqlPath .\path\to\data.sql
```

## バックアップのタイミング

- **重要な変更作業の前には必ずバックアップを取ること**
- 作業後も必要に応じてバックアップを取ること
- 最低でも次の作業前には毎回バックアップすること
  - スキーマ変更（テーブル追加・カラム変更）
  - RPC・ポリシーの変更
  - データの一括更新・削除
  - 本番データの手動修正

## GitHubへの管理外ルール

以下のファイルは `.gitignore` により Git 管理対象外です。**絶対に GitHub へ push しないでください。**

| 対象 | 理由 |
|------|------|
| `backups/` | 本番DBの全データ・日報写真を含む |
| `.env.backup.local` | DB接続文字列・パスワードを含む |
| `*.dump` / `*.backup` / `*.sql.zip` | 同上 |

`docs/sql/` 配下のマイグレーションSQLはGit管理対象です。

## 復元時の注意

- 復元は本番DBに直接影響します。必ず内容を確認してから実行してください。
- `roles.sql` → `schema.sql` → `data.sql` の順に適用します。
- 既存データの上書き・削除が発生する場合があるため、復元前にも必ずバックアップを取ること。
- Supabase の RLS・ポリシーが有効な状態では直接の `psql` 実行が必要な場合があります。
- Storage の写真は DB 復元では戻りません。別途 Storage の復元が必要です。

## .env.backup.local の管理

`.env.backup.local.example` を参考に、各PC にローカルで作成してください。

```
SUPABASE_DB_URL="postgresql://postgres.xxxxx:[YOUR-PASSWORD]@xxxxx.pooler.supabase.com:5432/postgres"
```

このファイルは Git 管理外です。PCを変えた場合は再作成が必要です。
