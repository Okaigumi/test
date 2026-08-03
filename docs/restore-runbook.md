# Phase 7-B Restore Runbook

**状態：main反映済み（PR #175 MERGED・2026-08-03）。Phase 7-D restore testは未開始。復旧可能性は未検証。**

---

## 1. 目的

Phase 7-A で取得したバックアップ（DB ZIP および Storage 写真 ZIP）から、local Supabase 環境（restore-lab）へデータを復元する手順を定義する。

Phase 7-D の非本番 restore test で使用することを目的とし、Production（SOURCE）への直接 restore は採用しない。

本ドキュメントは main 反映済み（PR #175 MERGED・2026-08-03T06:48:08Z・merge commit `8f317420a909503bc1c54f7e01acb088b139e93f`）。Phase 7-D restore test 開始前に Phase 7-C smoke checklist を作成し、ChatGPT・岡井さん・Claude の 3 者で内容を確認すること。

---

## 2. 適用範囲

- **対象**：Phase 7-D 非本番 restore test（local Supabase / restore-lab）
- **対象外**：Production への直接 restore（Phase 7-B の範囲外）
- **バックアップ取得日**：2026-07-26
- **Phase 7-A の状態**：PR #174 MERGED（2026-08-03）。Phase 7-A docs は main 反映済み

---

## 3. 復旧可能・復旧不能の区分

### DB ZIP から復元される範囲

`supabase db dump` の通常動作により、次のスキーマは dump に**含まれない**：

- `auth` schema（Supabase 管理）
- `storage` schema（Supabase 管理）
- extension 管理 schema

したがって、DB ZIP からは以下を**復元しない**：

- `storage.buckets`・`storage.objects`
- Storage policy・Storage bucket 設定
- Supabase Auth 管理データ

DB ZIP から復元される主な対象：

| 対象 | ファイル |
|------|---------|
| DB roles・権限定義 | roles.sql |
| public schema（テーブル・RPC・View・RLS・policy） | schema.sql |
| public schema 全テーブルデータ | data.sql |
| private schema（`private.login_throttle` 定義・データ） | schema.sql / data.sql に含まれる可能性あり（Step C-4 で確認） |

### Storage ZIP から別途復元する対象

- `photos` バケット写真 4 件（`storage-backup-manifest.csv` OK=4）

### 復旧不能（現行バックアップ非対象）

| 対象 | 理由 |
|------|------|
| `notice-attachments` 実ファイル | バックアップ未取得（Phase 7-F で対応検討） |
| `invoice-pdfs` 実ファイル | バックアップ未取得・非公開バケット（Phase 7-F で対応検討） |
| Storage 孤立ファイル | バックアップ対象外 |
| Supabase project 設定 | バックアップ対象外 |
| Vercel 環境変数・DNS | バックアップ対象外 |
| 2026-07-26 以降の変更 | RPO（このバックアップの対象外） |

### Storage schema 独自変更の再現

DB dump には Storage schema は含まれないため、以下の独自変更は repo 内の既存 SQL・記録を source of truth として Phase 7-D の TARGET に別途適用する：

- `photos` bucket 設定（file_size_limit / allowed_mime_types）
- `photos` 関連 policy（`photos_read` / `photos_upload`）
- `notice-attachments` 関連 policy（`notice_attachments_insert`）
- `invoice-pdfs` 関連 policy（`invoice_pdfs_insert` / `invoice_pdfs_select`）

参照 SQL：`docs/sql/phase4a-2-photos-upload-limits.sql`、`docs/sql/notice-attachments-rpc.sql`、`docs/sql/invoice-pdf-secure-rpc.sql`

---

## 4. SOURCE / TARGET 定義

| 用語 | 指す環境 | 接続情報 |
|------|---------|---------|
| **SOURCE** | 本番 Supabase（Production） | `SUPABASE_DB_URL`（`.env.backup.local` 記載、backup 取得専用） |
| **TARGET** | local restore-lab（local Supabase Docker） | `RESTORE_TARGET_DB_URL`（restore-lab 起動後に取得・docs には記録しない） |

### 混同防止ガード（全操作に適用）

- restore コマンドには `RESTORE_TARGET_DB_URL` のみ使用する
- `SUPABASE_DB_URL`（SOURCE 接続文字列）を restore コマンドに使用してはならない
- TARGET host が `127.0.0.1` または `localhost` であることを実行前に確認する
- SOURCE の project ref・host がコマンドや環境変数に含まれていないことを確認する
- SOURCE host が検出されたら即停止する
- DB write は各 human gate 後に岡井さんだけが実行する（Claude は実行しない）

---

## 5. 実行者・承認者

| 役割 | 担当 |
|------|------|
| 承認者（human gate） | 岡井さん |
| DB write・psql 実行者 | 岡井さん（Claude は実行しない） |
| 手順サポート | Claude |
| 仕様確認・最終判断 | ChatGPT |

---

## 6. 必要ツール

| ツール | 用途 | 自宅 PC 状態 |
|--------|------|------------|
| PowerShell 5.1+ | スクリプト実行・ファイル操作 | ✅ 組み込み |
| `Expand-Archive` | ZIP 展開 | ✅ PowerShell 組み込み |
| `Get-FileHash` | checksum 確認 | ✅ PowerShell 組み込み |
| psql（PostgreSQL client） | DB restore | **要確認**（下記参照） |
| Docker Desktop | local Supabase 起動 | ✅ 導入済み（4.83.0） |
| Supabase CLI | local Supabase 起動・管理 | ✅ 導入済み（2.109.1） |
| Node.js / npx | Supabase CLI 補助 | ✅ 導入済み（v24.16.0） |
| ブラウザ（Chrome 等） | application smoke | ✅ 既存 |

### psql 実行方式（Phase 7-D 開始前に選択）

Phase 7-D の DB restore 実行時に次の 2 候補から選択する：

**候補 A: host PC へのインストール**
- 自宅 PC 上に PostgreSQL client をインストール
- `psql` を直接呼び出して local Supabase DB に接続
- 接続先（典型値）：`postgresql://postgres:postgres@127.0.0.1:54322/postgres`

**候補 B: local Supabase Postgres コンテナ内の psql**
- `docker exec` で local Supabase Postgres コンテナ内の psql を使用
- ホストへのインストール不要
- 実際のコンテナ名・コマンド形式は Phase 7-D 前に `supabase status` で確認する

どちらを使用するかは Phase 7-D 開始前の human gate で決定する。

---

## 7. restore-lab 準備

restore-lab は **repo 外**の専用フォルダに構築する。`C:\Users\okai1\Documents\test\` 配下には作成しない。`supabase/config.toml` を repo に追加しない。

```text
C:\Users\<USER>\Documents\supabase-restore-lab\    ← 実パスは Phase 7-D 時に決定
├ supabase\         ← supabase init で生成（restore-lab 専用）
├ backups\          ← backup 作業コピー（ZIP 展開済みファイル）
├ html-smoke\       ← application smoke 用一時 HTML コピー
└ .env.restore      ← TARGET 接続情報の一時保管（作業終了後削除）
```

### Step R-1: restore-lab フォルダ作成

```powershell
New-Item -ItemType Directory -Path "C:\Users\<USER>\Documents\supabase-restore-lab"
Set-Location "C:\Users\<USER>\Documents\supabase-restore-lab"
```

### Step R-2: supabase init（restore-lab 内のみ）

```powershell
# restore-lab フォルダ内で実行する（repo 内では実行しない）
supabase init
```

### Step R-3: local Supabase 起動

```powershell
supabase start
# 起動完了後にコンソールへ表示される以下の情報を記録する（docs には記録しない）：
#   DB URL          → RESTORE_TARGET_DB_URL として使用
#   API URL         → http://127.0.0.1:54321（典型値）
#   anon key        → application smoke 用（local 専用・docs 非記録）
#   Studio URL      → http://127.0.0.1:54323（典型値）
supabase status   # 起動状態の確認
```

---

## 8. checksum 確認

**backup 原本 ZIP は変更・上書きしない。作業コピーを作成してから展開する。**

### Step C-1: DB ZIP checksum 確認

```powershell
Get-FileHash "C:\Users\okai1\Documents\test\backups\20260726-222121.sql.zip" -Algorithm SHA256
# 期待値：D15A576B153552D422E1EE4A142BE5F63D2CB16B2CD66CC6AF67BC097D263C84
# 不一致の場合は即停止する
```

### Step C-2: Storage ZIP checksum 確認

```powershell
Get-FileHash "C:\Users\okai1\Documents\test\backups\20260726-222706-storage.zip" -Algorithm SHA256
# 期待値：5E6692E3A5E094910D8A778EE0B99A25F247B5348F0DF7952AE9E6C270D1B1C9
# 不一致の場合は即停止する
```

### Step C-3: DB ZIP 作業コピー作成・展開

```powershell
# 原本は変更しない。restore-lab/backups\ へコピーしてから展開する
Copy-Item "C:\Users\okai1\Documents\test\backups\20260726-222121.sql.zip" `
          -Destination ".\backups\"
Expand-Archive ".\backups\20260726-222121.sql.zip" `
               -DestinationPath ".\backups\20260726-db\"
# 展開後の確認：roles.sql / schema.sql / data.sql / backup-info.txt が存在すること
```

### Step C-4: data.sql 内の COPY 対象確認（read-only）

```powershell
# session・throttle が data.sql に含まれるかを確認する
Select-String -Path ".\backups\20260726-db\data.sql" `
              -Pattern "^COPY.*(employee_sessions|admin_sessions|login_throttle)"
```

この結果を Phase 7-D の記録に残す。Step S-1 以降の処理に影響する。

---

## 9. target 識別・本番誤操作防止

**DB write の前に必ず実施する。**

### Step T-1: RESTORE_TARGET_DB_URL の目視確認

`RESTORE_TARGET_DB_URL` の host 部分が `127.0.0.1` または `localhost` であることを確認する。

- ✅ 許可例：`postgresql://postgres:postgres@127.0.0.1:54322/postgres`
- ❌ 停止：SOURCE の project ref・host が検出された場合

### Step T-2: TARGET DB 接続確認（read-only）

psql で TARGET に接続し、接続先を確認する：

```sql
-- 確認のみ（read-only）
SELECT version(), current_database(), inet_server_addr(), inet_server_port();
```

`127.0.0.1` または `localhost` 以外が返った場合は即停止する。

---

## 10. default privileges 事前処理

**必ず schema.sql 適用前に実施する。**

目的：
- target 側のデフォルト default privileges によって `anon` / `authenticated` へ過大な GRANT が自動付与されるのを防止する
- Phase 4 で撤廃した direct access が restore 後に復活しないよう保護する
- dump 内の明示的な GRANT / REVOKE が期待どおりに動作する状態を確保する

背景：

- Phase 4-F-1（`postgres` owner 分の default privileges REVOKE）は SOURCE で実行済み（2026-07-09）
- Phase 4-F-1b（`supabase_admin` owner 分）は未実施・backlog
- 新規 Supabase プロジェクトでは `supabase_admin` owner の default privileges が `anon` / `authenticated` に `arwdDxtm`（全権限）を自動付与する状態で始まる可能性がある

### Step D-1: TARGET の default privileges 確認（read-only）

```sql
-- 確認のみ
SELECT defaclrole::regrole, defaclnamespace::regnamespace, defaclobjtype, defaclacl
FROM pg_default_acl
WHERE defaclnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
```

`anon` / `authenticated` への広い default privileges が確認された場合は Step D-2 を実施する。

### Step D-2: 必要に応じた default privileges REVOKE（仕様例）

Step D-1 で過大な default privileges が確認された場合、schema.sql 適用前に実施する。

以下は仕様例であり、**Phase 7-D 前に ChatGPT・岡井さんの承認を得ること**。実行は TARGET DB のみ。

```sql
-- 【仕様例 / Phase 7-D 前にレビューすること】
-- ⚠️ TARGET DB のみで実行。SOURCE（Production）では絶対に実行しない。

-- postgres owner 分（Phase 4-F-1 相当）
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON TABLES FROM anon, authenticated;

-- supabase_admin owner 分（Phase 4-F-1b 相当・実行ロール要件を事前確認すること）
-- 実際の SQL は Phase 7-D 前に別途確認する
```

---

## 11. DB restore

### restore 方式

roles.sql・schema.sql・data.sql を **1 回の psql 呼び出し**で適用する。

```text
psql
  --single-transaction
  --variable ON_ERROR_STOP=1
  --file roles.sql
  --file schema.sql
  --command "SET session_replication_role = replica"
  --file data.sql
  --dbname <RESTORE_TARGET_DB_URL>
```

- `--single-transaction`：全体を 1 トランザクションとし、途中失敗時は全体を ROLLBACK する
- `--variable ON_ERROR_STOP=1`：最初のエラーで即停止する（部分適用を防ぐ）
- `SET session_replication_role = replica`：FK トリガーを無効化し COPY 形式データを安全に投入する
- 適用順序（roles.sql → schema.sql → data.sql）は変更不可

### Windows PowerShell 実行コマンド候補

実際のコマンドは psql 実行方式（候補 A / 候補 B）の選択後に確定する。以下は構造例。

**候補 A: host PC の psql**

```powershell
# ⚠️ <RESTORE_TARGET_DB_URL> の実値は restore-lab 内のみで参照する
# ⚠️ SOURCE 接続文字列（SUPABASE_DB_URL）は絶対に使用しない
psql `
  --single-transaction `
  --variable ON_ERROR_STOP=1 `
  --file ".\backups\20260726-db\roles.sql" `
  --file ".\backups\20260726-db\schema.sql" `
  --command "SET session_replication_role = replica" `
  --file ".\backups\20260726-db\data.sql" `
  --dbname "<RESTORE_TARGET_DB_URL>"
```

**候補 B: local Supabase Postgres コンテナ内の psql**

```text
# コンテナ名・ファイルのマウント方法は Phase 7-D 前に確認する
# docker exec を使用してコンテナ内 psql で同等の引数を渡す形式
```

### Step R-DB-1: ⚠️ restore 実行前 human gate

岡井さんが明示承認後に実行する。確認事項：

- [ ] TARGET host が `127.0.0.1` であること（Step T-1 確認済み）
- [ ] checksum 確認済み（Step C-1 確認済み）
- [ ] default privileges 確認済み（Step D-1 / D-2 完了済み）
- [ ] 作業コピーから実行すること（原本 ZIP は変更しない）
- [ ] SOURCE 接続文字列がコマンドに含まれていないこと

### Step R-DB-2: ⚠️ restore 実行

psql コマンドを実行する。エラー発生時は `ON_ERROR_STOP=1` により即停止する。

**既知の競合リスク（Phase 7-D 実施時に確認）：**

- **roles.sql**：Supabase 管理ロール（postgres / anon / authenticated / service_role 等）との定義競合でエラーが発生する可能性がある。エラー内容を確認し、Supabase 管理ロールへの `CREATE ROLE` 文のスキップ方針を Phase 7-D 前に確認する
- **schema.sql**：`supabase_admin` owner 関連のエラーが発生する可能性がある（Phase 7-D 実施時に確認）

### Step R-DB-3: restore 完了確認（read-only）

```sql
-- テーブル存在確認
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' ORDER BY table_name;

-- private schema 確認
SELECT schema_name FROM information_schema.schemata
WHERE schema_name = 'private';
```

---

## 12. restore 直後の session / throttle 処理

data.sql には以下が含まれる可能性がある（Step C-4 で確認）：

- `public.employee_sessions`
- `public.admin_sessions`
- `private.login_throttle`

**SOURCE Production DB ではこれらを絶対に削除しない。TARGET DB のみで実施する。**

### Step S-1: restore 直後の件数確認（read-only）

```sql
-- 確認のみ（read-only）
SELECT 'employee_sessions' AS tbl, COUNT(*) AS cnt FROM public.employee_sessions
UNION ALL
SELECT 'admin_sessions',           COUNT(*)       FROM public.admin_sessions;

SELECT COUNT(*) AS throttle_cnt, MAX(cooldown_until) AS max_cooldown
FROM private.login_throttle;
```

件数を Phase 7-D の記録に残す。

### Step S-2: ⚠️ human approval

確認事項：

- [ ] restore 直後の件数を記録したか
- [ ] TARGET（local）に接続していることを確認したか
- [ ] SOURCE Production DB では絶対に実行しないことを確認したか

### Step S-3: ⚠️ session / throttle の TARGET 限定削除

岡井さんが明示承認後に TARGET DB のみで実行する：

```sql
-- ⚠️ TARGET DB のみ。SOURCE（Production）では絶対に実行しない。
-- ⚠️ 実行前に Step T-1 の TARGET 確認を再確認すること。
DELETE FROM public.employee_sessions;
DELETE FROM public.admin_sessions;
DELETE FROM private.login_throttle;
```

削除件数を記録する。

### Step S-4: 削除後の確認（read-only）

```sql
SELECT COUNT(*) FROM public.employee_sessions;   -- 期待：0
SELECT COUNT(*) FROM public.admin_sessions;      -- 期待：0
SELECT COUNT(*) FROM private.login_throttle;     -- 期待：0
```

login smoke（Step A-4）では新規 login を発行し、セッションを新規作成する。

---

## 13. Storage bucket / policy 再現

DB dump には Storage schema は含まれない。Supabase Studio またはStorage API を使い別途再現する。

source of truth：repo 内の既存 SQL・記録

- `docs/db-migrations.md`（Phase 4-A-2・notice-attachments・invoice-pdfs 記録）
- `docs/sql/phase4a-2-photos-upload-limits.sql`
- `docs/sql/notice-attachments-rpc.sql`
- `docs/sql/invoice-pdf-secure-rpc.sql`

### Step SB-1: local Storage サービス確認

`supabase start` 完了後、local Storage API が `http://127.0.0.1:54321/storage/v1/` でアクセスできることを確認する。

### Step SB-2: photos バケット作成・設定

Supabase Studio（`http://127.0.0.1:54323`）またはStorage API で以下を設定する：

| 設定項目 | 値 |
|---------|---|
| bucket name | `photos` |
| public | true（public read） |
| file_size_limit | 5,242,880 bytes（5 MB） |
| allowed_mime_types | `['image/jpeg']` |

### Step SB-3: photos 関連 policy 再現

`docs/db-migrations.md` Phase 4-A-2 記録および `docs/sql/phase4a-2-photos-upload-limits.sql` を参照し、`storage.objects` の `photos_read` / `photos_upload` policy を再現する。具体的な SQL 最終版は Phase 7-D 前に別途レビューする。

### Step SB-4: notice-attachments / invoice-pdfs（Phase 7-D local では対象外）

現行バックアップに実ファイルが存在しないため、Phase 7-D local 段階では「復元不能・対象外」として記録する。Phase 7-F で対応を検討する。

---

## 14. photos アップロード

### Step P-1: Storage ZIP 作業コピー展開

```powershell
Copy-Item "C:\Users\okai1\Documents\test\backups\20260726-222706-storage.zip" `
          -Destination ".\backups\"
Expand-Archive ".\backups\20260726-222706-storage.zip" `
               -DestinationPath ".\backups\20260726-storage\"
# 展開後の確認：photos\ (4 件) / storage-backup-manifest.csv / backup-info.txt
```

### Step P-2: manifest 確認（read-only）

`storage-backup-manifest.csv` を参照し、4 件全てが OK であることを確認する：

- 期待：OK=4 / SKIPPED=0 / ERROR=0

### Step P-3: 4 件のアップロード

`storage-backup-manifest.csv` の `local_path` 列に記載された object path に従い、photos 4 件を local Storage の photos バケットへアップロードする。

アップロードの具体的なコマンド（Supabase Storage API への `Invoke-WebRequest`・Supabase CLI storage 操作・Studio 手動アップロードのいずれか）は Phase 7-D 前に確認する。

### Step P-4: アップロード後確認

local Storage 管理画面（Studio）または API で object 件数が 4 件であることを確認する。

---

## 15. TARGET 内 photos URL 変換

`reports.photo_urls` に保存された URL は SOURCE project ref を含む形式のため、TARGET local Storage URL へ変換する。

- SOURCE URL 形式：`https://[SOURCE_PROJECT_REF].supabase.co/storage/v1/object/public/photos/...`
- TARGET URL 形式（典型値）：`http://127.0.0.1:54321/storage/v1/object/public/photos/...`

**TARGET DB 内のみで実施する。SOURCE Production DB では絶対に実行しない。**

**⚠️ 最終 SQL は Phase 7-D 前に別途レビューする。以下は要件レベルの仕様案。**

### Step PU-1: 変換前確認（read-only）

```sql
-- SOURCE host を含む photo_urls 件数を確認する（read-only）
-- ※ [SOURCE_HOST_PATTERN] の実値は Phase 7-D 前に確認する
SELECT COUNT(*) AS source_url_reports
FROM public.reports
WHERE EXISTS (
  SELECT 1 FROM UNNEST(photo_urls) AS u
  WHERE u LIKE '%[SOURCE_HOST_PATTERN]%'
);
```

確認した件数を記録する。

### Step PU-2: ⚠️ human approval

確認事項：

- [ ] TARGET 接続確認済み（Step T-1 完了済み）
- [ ] SOURCE host 含む件数記録済み
- [ ] SOURCE Production DB では絶対に実行しないことを確認済み

### Step PU-3: ⚠️ TARGET 内 URL 変換

岡井さんが明示承認後に TARGET DB のみで実行する（SQL 最終版は Phase 7-D 前にレビュー）：

```text
【要件レベル仕様案 / 実 SQL は Phase 7-D 前に別途レビューすること】
要件：
- reports.photo_urls 配列内の各 URL について
- SOURCE host 部分を TARGET local Storage host に置換する
- 対象：photo_urls が NULL でなく 1 件以上の行
- UPDATE は TARGET DB のみで実行する
- SOURCE（Production）DB では絶対に実行しない
```

### Step PU-4: 変換後確認（read-only）

```sql
-- SOURCE host 残存件数が 0 であることを確認する
-- ※ [SOURCE_HOST_PATTERN] の実値は Phase 7-D 前に確認する
SELECT COUNT(*) AS remaining_source_urls
FROM public.reports
WHERE EXISTS (
  SELECT 1 FROM UNNEST(photo_urls) AS u
  WHERE u LIKE '%[SOURCE_HOST_PATTERN]%'
);
-- 期待：0
```

変換後に SOURCE host 残存 0 を確認してから application smoke へ進む。

---

## 16. DB post-check

read-only で実施する。

### 固定期待値（repo 記録から確定）

| 確認項目 | 期待値 | 根拠 |
|---------|--------|------|
| `employees` 件数 | 11 | Phase 5-D-3 実行記録 |
| `employees.pin_hash` NULL 件数 | 0 | Phase 5-D-3 実行記録 |
| bcrypt cost（`pin_hash` 先頭文字列） | 12 | Phase 5-D-3 実行記録 |
| `private.login_throttle` owner | postgres | Phase 5-C-1a 記録 |
| `private.login_throttle` RLS | enabled、policy 0 本 | Phase 5-C-1a 記録 |
| `admin_sessions` / `employee_sessions` RLS | enabled、policy 0 本 | Phase 3 記録 |
| secure RPC の SECURITY DEFINER | 全 secure RPC で true | Phase 3〜5 記録 |
| secure RPC の search_path | `public, extensions` | Phase 3〜5 記録 |

### restore 後に記録する値（Phase 7-D で確認）

| 確認項目 | 確認方法 |
|---------|---------|
| public schema テーブル数 | `information_schema.tables WHERE table_schema='public'` |
| `reports` 件数 | `SELECT COUNT(*) FROM public.reports` |
| `employee_sessions` 件数（session 削除後） | `SELECT COUNT(*)`（期待：0） |
| `admin_sessions` 件数（session 削除後） | `SELECT COUNT(*)`（期待：0） |
| `private.login_throttle` 件数（削除後） | `SELECT COUNT(*)`（期待：0） |
| anon / authenticated の CRUD grant 状態 | `information_schema.role_table_grants` |
| TARGET の default privileges 現状 | `pg_default_acl`（Step D-1 との比較） |
| RLS 有効テーブル一覧 | `pg_class.relrowsecurity` で確認。Phase 4/5 の記録（`docs/db-migrations.md`）で RLS 対象と確定した application table の baseline と一致すること。public schema 内の全テーブルに一律で RLS 有効とは断定しない |

### 注意事項

- RLS 有効テーブルの期待値は「public schema 内の全テーブルで一律 RLS 有効」とは断定しない。Phase 4/5 の記録（`docs/db-migrations.md`）で RLS 対象と確定した application table の baseline と一致することを確認する（参照：Phase 3 / Phase 4-B〜4-F 各実行記録）
- `reports` 件数はバックアップ取得時点の値であり、Phase 7-D 前に repo から確定できない
- session 件数はバックアップ取得時の状態に依存する（Step C-4 参照）

---

## 17. Storage post-check

| 確認項目 | 期待値 |
|---------|--------|
| photos バケット存在 | あり（public） |
| photos object 件数 | 4（manifest OK=4 に一致） |
| object path | manifest の `local_path` 列と一致 |
| MIME type | image/jpeg |
| photos URL（変換後） | TARGET local Storage URL を指すこと |

notice-attachments・invoice-pdfs は「復元不能・対象外」として記録する。

---

## 18. application smoke

3 つの本番 HTML（`index.html` / `admin-app.html` / `genka-app.html`）は変更しない。restore-lab 内に一時コピーを作成し、smoke 完了後に削除する。

### Step A-1: 一時 HTML コピー作成

```powershell
Copy-Item "C:\Users\okai1\Documents\test\index.html"     -Destination ".\html-smoke\"
Copy-Item "C:\Users\okai1\Documents\test\admin-app.html" -Destination ".\html-smoke\"
Copy-Item "C:\Users\okai1\Documents\test\genka-app.html" -Destination ".\html-smoke\"
```

### Step A-2: URL・key 置換

一時コピー 3 ファイルの Supabase URL 定数と anon key 定数を TARGET local 値へ書き換える：

| 対象 | 変更前 | 変更後 |
|------|--------|--------|
| Supabase URL | `https://[SOURCE_PROJECT_REF].supabase.co` | `http://127.0.0.1:54321` |
| anon key | SOURCE anon key | local anon key（`supabase status` で取得） |

**anon key の実値は docs へ記録しない。** restore-lab 内の一時ファイルのみに存在する状態とする。

### Step A-3: SOURCE URL 残存確認

```powershell
# 3 ファイル内に SOURCE URL が残存しないことを確認する
# [SOURCE_HOST_PATTERN] の実値は Phase 7-D 前に確認する
Select-String -Path ".\html-smoke\*.html" -Pattern "[SOURCE_HOST_PATTERN]"
# 0 件であることを確認する。1 件でも残存する場合は smoke を開始しない
```

### Step A-4: browser smoke（read-only 操作）

一時 HTML をローカル HTTP サーバーまたは `file://` で開く。**ブラウザの Network tab を常に開いた状態**で実施する。

**停止条件：** `127.0.0.1:54321` 以外への Supabase 通信が検出された場合は即停止する。

| 確認項目 | 期待 |
|---------|------|
| 従業員ログイン（正しい PIN） | 成功 |
| 管理画面ログイン | 成功 |
| 原価画面ログイン | 成功 |
| 日報一覧表示 | 件数正常 |
| 写真表示 | TARGET local Storage URL からの表示 |
| Network tab 接続先 | `127.0.0.1:54321` のみ |

**write smoke を実施するかは Phase 7-D 開始前 human gate で決定する。**

### Step A-5: ⚠️ 一時 HTML コピー削除

smoke 完了後に削除する：

```powershell
Remove-Item ".\html-smoke\*.html" -Force
# 削除済みであることを確認する
Get-ChildItem ".\html-smoke\"
```

---

## 19. 合否判定

### 合格条件（必須）

- [ ] checksum 一致（DB ZIP・Storage ZIP 両方）
- [ ] DB restore 完了（エラーなし）
- [ ] `employees` 件数：11
- [ ] `employees.pin_hash` NULL 件数：0
- [ ] session / throttle 削除後に件数が 0
- [ ] 従業員ログイン成功
- [ ] 管理画面ログイン成功
- [ ] 原価画面ログイン成功
- [ ] 日報一覧表示正常
- [ ] Network tab で SOURCE への通信なし

### 条件付き合格候補

- photos 表示：URL 変換後に TARGET local Storage から表示できること（Step PU-4 完了後）
- write smoke：実施する場合のみ確認

### 不合格条件

- roles.sql / schema.sql / data.sql 適用エラー（`ON_ERROR_STOP=1` により停止済み）
- TARGET でなく SOURCE への接続が検出された場合
- login 失敗（正しい PIN で）
- Network tab で SOURCE host への通信検出

---

## 20. cleanup

### Phase 7-D 完了後の cleanup

```powershell
# local Supabase 停止
supabase stop

# 作業コピー削除（原本 backup ZIP は削除しない）
Remove-Item -Recurse -Force ".\backups\20260726-db\"
Remove-Item -Recurse -Force ".\backups\20260726-storage\"

# 一時 HTML（Step A-5 で削除済みであることを確認）
Get-ChildItem ".\html-smoke\"

# TARGET 接続情報の一時ファイル削除
Remove-Item -Force ".\.env.restore"
```

restore-lab フォルダ自体の保持・削除は Phase 7-D 後の human gate で決定する。

---

## 21. rollback・再試行方針

### DB restore 失敗

`--single-transaction` により ROLLBACK 済み。TARGET DB を初期化（`supabase stop` → `supabase start`）して Step R-DB-1 から再試行する。

### Storage upload 失敗

アップロード済み object を Studio またはAPI で削除し、Step P-3 から再試行する。

### URL 変換失敗

TARGET DB を初期化して Step R-DB-1 から再試行する。

### 再試行の原則

- 原本 ZIP は変更しない
- SOURCE（Production）への操作は一切行わない
- 再試行のたびに Step T-1 の TARGET 確認を実施する

---

## 22. 既知の制限

| 制限 | 内容 |
|------|------|
| 復旧可能性未検証 | Phase 7-D 完了まで実証なし |
| `notice-attachments` 実ファイル | 現行バックアップ非対象（Phase 7-F） |
| `invoice-pdfs` 実ファイル | 現行バックアップ非対象（Phase 7-F） |
| Storage 孤立ファイル | バックアップ対象外 |
| 2026-07-26 以降のデータ損失 | RPO |
| roles.sql 競合 | Supabase 管理ロールとの定義競合が発生する可能性（Phase 7-D 実施時に確認） |
| schema.sql supabase_admin エラー | 発生する可能性（Phase 7-D 実施時に確認） |
| data.sql 含有スキーマ | session / throttle の実際の含有は Step C-4 で確認 |
| supabase_admin default privileges | Phase 4-F-1b 未実施。Step D-1/D-2 で TARGET 確認・対処 |
| psql 実行方式 | 候補 A / 候補 B を Phase 7-D 前に選択 |
| write smoke 実施可否 | Phase 7-D 前 human gate で決定 |
| photos URL 変換 SQL 最終版 | Phase 7-D 前に別途レビュー |
| Storage policy 再現 SQL 最終版 | Phase 7-D 前に別途レビュー |
| local Storage へのアップロードコマンド | Phase 7-D 前に確認 |
| local 環境の実測 port / key | `supabase start` 実行後に確認 |

---

## 23. Phase 7-C / 7-D への引き継ぎ

### Phase 7-B の状態

```
Phase 7-B restore runbook：main反映済み（PR #175 MERGED・2026-08-03）。
Phase 7-C：未開始。Phase 7-D restore test：未開始。
復旧可能性は未検証。
```

Phase 7-A（PR #174）は MERGED（2026-08-03）。Phase 7-A docs は main 反映済み。

### Phase 7-C（smoke checklist）への引き継ぎ

Phase 7-B（本書）§16〜§18 のpost-check 項目を yes / no で答えられる一行形式にチェックリスト化する。Phase 7-D 実施時の記録用紙として使用する。

**Phase 7-C 成果物（作成済み）：**
- checklist：`docs/phase7c-restore-smoke-checklist.md`
- post-check SQL（read-only）：`docs/sql/phase7c-restore-postcheck.sql`
- photo URL rewrite SQL（TARGET のみ）：`docs/sql/phase7d-target-photo-url-rewrite.sql`
- Storage policy restore SQL（TARGET のみ）：`docs/sql/phase7d-storage-policy-restore.sql`

### Phase 7-D 開始前 human gate

以下が全て揃ってから Phase 7-D を開始する：

- [ ] Phase 7-B runbook（本書）について 3 者合意済み
- [ ] Phase 7-C smoke checklist（`docs/phase7c-restore-smoke-checklist.md`）作成済み
- [ ] psql 実行方式：Docker exec（local Supabase DB コンテナ内 psql）に決定済み
- [ ] restore-lab 専用フォルダ：`C:\Users\okai1\Documents\supabase-restore-lab` に決定済み
- [ ] 岡井さんが「Phase 7-D 開始してよい」と明示承認済み

### Phase 7-D 完了後の次工程

- Phase 7-D 合格後 → Phase 7-A（PR #174）merge を検討
- Phase 7-E：automation / rotation / off-site
- Phase 7-F：Storage backup 拡張（notice-attachments / invoice-pdfs）
