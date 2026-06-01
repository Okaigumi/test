# バックアップ方針

## 前提・必要ツール

- Node.js（npx が使えること）
- npx --yes supabase（Supabase CLI を npx 経由で実行）
- Windows PowerShell 5.1 以上（PowerShell 7 推奨）
- `.env.backup.local`（接続文字列を記載したローカル専用ファイル）

Node.js と npx がインストールされていない場合、スクリプトは起動直後に停止します。

## バックアップ対象

| 対象 | ファイル | 備考 |
|------|----------|------|
| ロール・権限定義 | roles.sql | DB ロールと権限 |
| スキーマ定義 | schema.sql | テーブル・関数・ポリシー等 |
| データ | data.sql | 全テーブルのレコード（COPY形式） |

### Supabase Storage（写真）について

`index.html` の日報機能は Supabase Storage の `photos` バケットに写真を保存しています。

**DBバックアップだけでは写真データは保護されません。**

写真データを保護する場合は Supabase ダッシュボードから Storage バケットを別途エクスポートするか、Supabase の有料プランのバックアップ機能を利用してください。

## バックアップ手順

1. `.env.backup.local` が存在することを確認する
   - 存在しない場合は `.env.backup.local.example` を参考に作成する
2. PowerShell を開き、プロジェクトルートへ移動する
3. スクリプトを実行する

```powershell
.\scripts\backup-supabase.ps1
```

4. `backups\YYYYMMDD-HHMMSS.sql.zip` が作成されたことを確認する
5. zip ファイルを安全な場所（外付けHDD・クラウドストレージ等）に保存する

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
| `backups/` | 本番DBの全データを含む |
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
