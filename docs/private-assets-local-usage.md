# 機密資産の外部保管

機密ファイルはリポジトリ・配信ルート・クラウド同期ルート外の専用保管先に置く。端末別の実パス、資産配置、移設・照合結果はGit管理外の運用記録で管理する。保管先をリポジトリ内のシンボリックリンクやジャンクション経由で参照しない。既存資産は承認なく移動・改名・削除しない。

## コマンドの変更

**以前の引数なし・リポジトリ相対パスの起動は使えない。** DB・Storageとも絶対パスの `-BackupRoot` と `-TempRoot` が必須。DBは `-EnvFile` も必須。Storageの `-SqlZipPath` / `-DataSqlPath` は従来どおり選択できるが、外部の絶対パスを指定する。未指定時はPowerShellの必須引数として扱われ、リポジトリ内に自動出力するフォールバックはない。

以下は架空のパスを使った例で、そのまま実行しない。Git管理外の運用記録から検証済みの外部絶対パスを確認して置き換え、実DB接続・実バックアップが別途承認された場合だけ使用する。

```powershell
$privateRoot = 'C:\PrivateAssets' # 架空例。実行前に検証済みの外部絶対パスへ置き換える。
& .\scripts\backup-supabase.ps1 `
  -EnvFile "$privateRoot\.env.backup.local" `
  -BackupRoot "$privateRoot\backups" -TempRoot "$privateRoot\tmp"

# 新たに取得したDB ZIPの実ファイル名を指定する
& .\scripts\backup-supabase-storage.ps1 `
  -SqlZipPath "$privateRoot\backups\<取得したファイル名>.sql.zip" `
  -BackupRoot "$privateRoot\backups" -TempRoot "$privateRoot\tmp"
```

展開済みSQLを使用する場合も、DB ZIPの例の代わりに次の外部絶対パスを指定する（実行には同じ承認条件が適用される）。

```powershell
$privateRoot = 'C:\PrivateAssets' # 架空例。実行前に検証済みの外部絶対パスへ置き換える。
& .\scripts\backup-supabase-storage.ps1 `
  -DataSqlPath "$privateRoot\tmp\<承認した展開フォルダ>\data.sql" `
  -BackupRoot "$privateRoot\backups" -TempRoot "$privateRoot\tmp"
```

`validate-backup.ps1` は既存の `-BackupDir` / `-ResultPath` で外部パスを使用できる。DBバックアップから呼ぶ際は自動で指定される。秘密値を引数へ直接記入したり、.envを画面表示しない。

## 保管・失敗時の扱い

- `private-asset-paths.ps1` はリポジトリ・Git作業ツリー・検出したOneDrive/Dropbox配下、相対パス、UNC/デバイスパス、既存のリンクを拒否する。他の同期製品・配信ツールの登録先は運用時に確認する。
- DBのSQL作業フォルダと検証結果JSONは `TempRoot` 配下、最終ZIPは `BackupRoot` 配下。成功時にSQL作業フォルダを削除し、失敗時は調査用に外部tmp内へ保全する。結果JSONはfinallyで削除する。DB接続用プロセス環境変数は終了時に元へ戻す。
- Storageの入力ZIP展開は `TempRoot` 配下の専用フォルダを使用し、読込み成功・例外の両方で削除する。写真等の出力は `BackupRoot` 配下。ダウンロード失敗時は従来どおり外部の出力フォルダを保全する。
- 出力ZIP名は衝突を減らすためミリ秒を追加した `yyyyMMdd-HHmmss-fff`。既存ZIPを強制上書きしない。既存ZIPは承認なく改名せず、外部絶対パスを既存引数に指定して利用する。
- 通常削除は媒体からの完全消去の保証ではない。後片付けはパス・実体・内容一覧を確認し、作業が作成した専用フォルダだけを対象とする。

## 配信と検証

Playwrightの既存サーバーは127.0.0.1でリポジトリを配信するが、実体パスの境界、隠しパス、backups、秘密・内部用ディレクトリ、アーカイブ等をGET/HEADとも拒否する。外部保管は必須であり、この拒否だけに依存しない。別のサーバーでも機密資産の親ディレクトリを配信しない。公開・接続設定の変更は別途承認する。

回帰検証は実秘密を使わない。

```powershell
node --test tests/static-server-security.test.mjs
# 合成fixtureの作成先はGit・同期・配信ルート外に明示する
& .\tests\private-assets-paths.test.ps1 -TestRoot C:\適切な作業領域\private-assets-dummy-test
```

PowerShell検証は一時的なコードコピーとダミー入力を使い、npx・HTTP取得・検証JSONをスタブに置き換える。実DB・実Storageへアクセスしない。検証用ダミーはTestRoot配下に残し、実行結果を確認可能にする。検証用サーバーは生成したダミーの公開ルートだけを使用する。

ダミー検証の保証範囲はパス指定・保存先・配信拒否であり、実バックアップやデプロイ環境の動作保証ではない。実行環境ごとの確認結果と資産照合結果はGit管理外の運用記録に残す。実運用前に、利用するサーバー・同期製品・CLIの接続情報の取扱いを確認する。
