# バックアップ方針

更新日：2026-09-10。取得対象・頻度・検証基準の正本は本書。**現在の実行コマンドと外部パスの指定例は [機密資産の外部保管](private-assets-local-usage.md) に集約する。** 旧コマンドは末尾の履歴のみで、現行手順には使用しない。担当・承認は [運用正本](workflow-rules.md) 第12節に従う。

## 前提・必要ツール

- Node.js（npx が使えること）
- npx --yes supabase（Supabase CLI を npx 経由で実行）
- **Docker Desktop（現行方式では必須）**：現行の Supabase CLI による Windows 上のバックアップ方式では、`db dump` の実行に Docker を使用します。Docker が未導入または未起動だと `LegacyDockerRunError` で失敗します。
  - WindowsでのDocker実行方式は各環境の前提条件に従う。端末別の構成と確認結果はGit管理外の運用記録に残す。
- Windows PowerShell 5.1 以上（PowerShell 7 推奨）
- `.env.backup.local`（接続文字列を記載したローカル専用ファイル）

Node.js と npx がインストールされていない場合、スクリプトは起動直後に停止します。
Docker Desktop が起動していない場合、DBバックアップは dump 実行時に失敗します。実バックアップを承認した利用時に、前提環境を確認してください。ダミー検証は実接続・実バックアップの動作確認を代替しません。

取得実績（世代・checksum・対象範囲）は `docs/backup-recovery-inventory.md` に記録します。

## バックアップ対象

| 対象 | ファイル | 備考 |
|------|----------|------|
| ロール・権限定義 | roles.sql | DB ロールと権限 |
| スキーマ定義 | schema.sql | テーブル・関数・ポリシー等 |
| データ | data.sql | public・private スキーマのレコード（COPY 形式、`--schema public,private`） |

### Supabase Storage（写真）について

`index.html` の日報機能は Supabase Storage の `photos` バケットに写真を保存しています。

**DBバックアップだけでは写真データは保護されません。**

写真バックアップは `scripts/backup-supabase-storage.ps1` で実施します（詳細は後述）。

## バックアップ手順

### 1. DBバックアップ（毎回実施）

1. 外部保管先の `.env.backup.local` の存在を確認する。本文を表示しない
   - 新規作成が必要な場合は `.env.backup.local.example` を参考に外部保管先で本人が設定する
2. PowerShell を開き、プロジェクトルートへ移動する
3. [現在のDBコマンド](private-assets-local-usage.md#コマンドの変更) に従い、絶対パスの `-EnvFile`・`-BackupRoot`・`-TempRoot` を指定して実行する

4. バリデーション（`scripts/validate-backup.ps1`）が自動実行される。全 21 項目 PASS の場合のみ次のステップへ進む。FAIL の場合はスクリプトが `exit 1` で終了し、ZIP は作成されない
5. `<BackupRoot>\yyyyMMdd-HHmmss-fff.sql.zip` が作成されたことを確認する
6. 外部保管先のZIPを保全する。クラウドへ移送する場合は平文ZIPを同期対象へ置かず、別途承認した暗号化移送手順を使用する

#### 出力

| ファイル | 内容 |
|---------|------|
| `<BackupRoot>\yyyyMMdd-HHmmss-fff.sql.zip` | ZIP（バリデーション PASS の場合のみ作成） |
| ZIP 内 `roles.sql` | ロール・権限定義 |
| ZIP 内 `schema.sql` | スキーマ定義 |
| ZIP 内 `data.sql` | データ（public・private スキーマ、COPY 形式） |
| ZIP 内 `backup-info.txt` | 実行サマリー（下記参照） |

バリデーション FAIL の場合、ZIP は作成されず `<TempRoot>\db-<GUID>\` フォルダが調査用に残ります。

サマリーは**今回の検証JSONを安全に取得できた場合のみ**作成する。

| 今回の検証結果 | サマリー・ZIP・終了状態 |
|---|---|
| 有効なJSONがPASSED、終了コード0 | PASSEDサマリーと今回のZIPを作成し、成功時の外部一時dumpを削除する。 |
| 有効なJSONがFAILED、または有効な結果取得後の終了コードが非ゼロ | FAILEDサマリーを今回の外部dumpフォルダへ保存。ZIPを作らず失敗として終了する。JSONがFAILEDなら終了コード0でも成功にしない。 |
| validator不在・例外、終了コード未取得、JSON不在・不正・必須値欠落 | 今回分のサマリーとZIPを作らず失敗終了。外部dumpを調査用に保全する。 |

JSONは単一オブジェクト、必須値非null、PASSED/FAILEDの状態、非負整数の件数・合計整合、文字列のハッシュ欄を確認する。FAIL時に検証できなかったファイルのハッシュが空文字でも、取得できたFAILED結果として保全する。PASSEDでは空欄を認めない。validatorの21検証項目・対象スキーマは変更しない。取得できない結果をn/aや0で補わない。

今回専用のGUID付きdumpフォルダと結果JSONを使用し、過去のサマリーやZIPを今回の結果として再利用しない。既存ZIPを上書きせず、失敗時は過去の成功ZIPが存在しても今回の成功を通知しない。結果JSONの後片付けとDB接続用環境変数の復元はfinallyで行う。

検証：`tests/backup-validation-summary.test.ps1 -TestRoot <新しい外部のダミー専用絶対パス>` の17ケースをPowerShell 5.1／7で確認。既存保存処理26項目も回帰確認。いずれもCLIとvalidatorをスタブ化し、過去成果物のダミーも保全確認した。実DB・実秘密は使用しない。HTTP54ケースはサーバー無変更のため既存証拠を利用する。

#### backup-info.txt の記録内容

| フィールド | 内容 |
|-----------|------|
| backup_timestamp | バックアップ実行日時 |
| supabase_cli | 使用した Supabase CLI バージョン |
| dump_scope_data | data.sql の対象スキーマ（`public, private`） |
| dump_flags_data | dump コマンドに渡したフラグ |
| files | バックアップファイル一覧 |
| sha256_roles / sha256_schema / sha256_data | 各ファイルの SHA-256 ハッシュ値 |
| copy_total / copy_public / copy_private | COPY ブロック数（スキーマ別） |
| copy_auth / copy_storage / copy_other | auth・storage・その他スキーマの COPY 数（0 であること） |
| validation | バリデーション結果（`PASSED` / `FAILED`） |
| classification | `CONFIDENTIAL`（固定） |
| contains_plaintext_pin | `YES`（固定） |
| github_allowed | `NO`（固定） |

#### バリデーション項目（validate-backup.ps1）

`backup-supabase.ps1` は dump 完了後に `scripts/validate-backup.ps1` を自動実行します。全 21 項目が PASS の場合のみ ZIP を作成します。

| カテゴリ | 項目数 | チェック内容 |
|---------|--------|------------|
| ファイル存在 | 3 | roles.sql / schema.sql / data.sql が存在すること |
| ファイルサイズ | 3 | 各ファイルが 0 バイト超であること |
| BOM なし | 3 | UTF-8 BOM が含まれていないこと |
| CRLF なし | 1 | data.sql に CR バイト（0x0D）が含まれていないこと |
| UTF-8 厳密デコード | 1 | data.sql が正規の UTF-8 であること |
| COPY ブロック数 | 1 | data.sql に 1 件以上の COPY ブロックがあること |
| auth COPY = 0 | 1 | auth スキーマの COPY ブロックが 0 件であること |
| storage COPY = 0 | 1 | storage スキーマの COPY ブロックが 0 件であること |
| スコープ外 COPY = 0 | 1 | public・private 以外のスキーマの COPY ブロックが 0 件であること |
| カラム整合性 | 1 | COPY ヘッダーのカラム数とデータ行の TAB 数が一致すること |
| ターミネータ | 1 | 全 COPY ブロックが `\.` で正常終了していること |
| ヘッダー解析可能 | 1 | COPY ヘッダー行が全て正規フォーマットであること |
| SHA-256 | 3 | 各ファイルのハッシュ算出が正常に完了すること（値は backup-info.txt に記録） |

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

1. DBバックアップを完了し、`<BackupRoot>\yyyyMMdd-HHmmss-fff.sql.zip` が存在することを確認する
2. PowerShell を開き、プロジェクトルートへ移動する
3. [現在のStorageコマンド](private-assets-local-usage.md#コマンドの変更) に従い、絶対パスの `-SqlZipPath`・`-BackupRoot`・`-TempRoot` を指定して実行する

4. 結果を確認する

```
OK=N  SKIPPED=0  ERROR=0
Complete : <BackupRoot>\yyyyMMdd-HHmmss-fff-storage.zip
```

#### 出力

| ファイル | 内容 |
|---------|------|
| `<BackupRoot>\yyyyMMdd-HHmmss-fff-storage.zip` | zip（ERROR=0 の場合のみ作成） |
| zip内 `photos\{reportId}\{filename}.jpg` | 日報に紐付いた写真ファイル |
| zip内 `storage-backup-manifest.csv` | ファイル単位のダウンロード結果（OK / SKIPPED / ERROR） |
| zip内 `backup-info.txt` | 実行日時・件数サマリー |

#### ERROR が出た場合

- zip は作成されず、`<BackupRoot>\yyyyMMdd-HHmmss-fff-storage\` フォルダが残る
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

この場合も外部の絶対パスを指定し、`-BackupRoot`・`-TempRoot` は省略しない。完全な例は [現在の利用手順](private-assets-local-usage.md#コマンドの変更) を参照する。

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

このファイルは外部保管先へ置き、リポジトリへコピーしません。PC移行時は承認された暗号化移送・照合手順を使い、存在する資産を一律に再作成しません。

## 旧起動方法の扱い（実行しない）

以前の引数なし・リポジトリ相対パスによる起動方法は、必須の外部パス引数を欠くため使用しない。現在の利用手順に従う。過去成果物の所在・移設・照合結果はGit管理外の運用記録で管理し、承認なく移動・改名・削除しない。
