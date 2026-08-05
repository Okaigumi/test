# Phase 7-C Restore Smoke Checklist

**目的：** Phase 7-D restore test の実施記録用紙。Phase 7-B restore runbook を参照しながら使用する。

**状態：** 完了・main反映済み（PR #178 MERGED・2026-08-04）。Phase 7-D restore test は 2026-08-05 に実施・技術検証完了。restore viability：**CONFIRMED**。DB／Production 変更なし。

**実施結果の正本：** `docs/phase7d-restore-test-record.md`。本 checklist は Phase 7-C の成果物（記録様式）であり、実施結果は書き込まない。

Phase 7-D では本 checklist 46 項目の**項目別チェック表は未作成**であり、主要検証結果は実行記録の本文に記録されている。**Restore Viability：CONFIRMED の判定はその主要検証結果に基づく**（実行記録 §13 参照）。46 項目の運用方針は PR-2 の runbook 改訂時に整理する。

**restore本体コマンド：** `docs/restore-runbook.md` を正本とする。本 checklist へ複製しない。

**post-check SQL：** `docs/sql/phase7c-restore-postcheck.sql`（read-only）

**補助 SQL（TARGET のみ）：**
- `docs/sql/phase7d-target-photo-url-rewrite.sql`
- `docs/sql/phase7d-storage-policy-restore.sql`

---

## 判定体系

| 判定 | 条件 |
|---|---|
| **PASS** | 全必須項目一致・login 成功・write smoke 成功・SOURCE 通信なし |
| **FAIL** | 必須項目不一致・login 失敗・write 失敗・checksum 不一致 |
| **BLOCKED** | psql 方式未決定・policy 定義未取得・roles.sql 競合未解決・human gate 未承認 |
| **KNOWN CONSTRAINT** | 既知制約（notice-attachments / invoice-pdfs 復元不能 等） |
| **SAFETY ABORT** | SOURCE host 検出・Production URL 通信・localhost 以外の TARGET・SOURCE DB write の兆候 |

**SAFETY ABORT は FAIL より上位。即時全中断・原因記録。**

全必須項目合格時：
```
RESTORE VIABILITY: CONFIRMED WITH KNOWN LIMITATIONS
```

---

## 既知制約（Known Constraints）

以下は FAIL 条件にしない。Phase 7-D 記録に明示する。

| # | 内容 |
|---|---|
| KC-1 | `notice-attachments` 実ファイル：現行バックアップ非対象（Phase 7-F） |
| KC-2 | `invoice-pdfs` 実ファイル：現行バックアップ非対象（Phase 7-F） |
| KC-3 | Storage 孤立ファイル：バックアップ対象外 |
| KC-4 | バックアップ取得日（2026-07-26）以降のデータ：RPO 外 |
| KC-5 | `photos_upload` が PUBLIC INSERT policy（employee session 検証なし・path 制限なし）。restore-lab で Production 実装を忠実に再現するが、将来のセキュリティレビュー候補。今回 Production 変更は行わない。 |

---

## 7C-0 Pre-flight

> restore 開始前に全項目を確認する。1件でも FAIL または SAFETY ABORT があれば進めない。

---

- [ ] **7C-0-01**
  - 確認内容：restore-lab フォルダが `C:\Users\okai1\Documents\supabase-restore-lab` に存在し、repo 外であること
  - 期待結果：フォルダ存在・`C:\Users\okai1\Documents\test\` の外
  - 担当：岡井さん
  - 実行方法：`Test-Path "C:\Users\okai1\Documents\supabase-restore-lab"` → True
  - 証拠：PowerShell 出力
  - 結果：[ PASS / FAIL ]
  - 停止条件：存在しない、または repo 内パスの場合は BLOCKED
  - 備考：runbook §7 参照

---

- [ ] **7C-0-02**
  - 確認内容：local Supabase が起動中で、DB コンテナが 1件だけ動作していること
  - 期待結果：`docker ps --filter "name=supabase_db" --format "{{.Names}}"` が 1行だけ返る
  - 担当：岡井さん
  - 実行方法：`docker ps --filter "name=supabase_db" --format "{{.Names}}"`
  - 証拠：コンテナ名を記録（例：`supabase_db_supabase-restore-lab`）
  - 結果：[ PASS / FAIL / BLOCKED ]
  - 停止条件：0件 → BLOCKED（supabase start 未完了）。2件以上 → BLOCKED（複数コンテナ競合）
  - 備考：`$DB_CONTAINER` 変数に記録して以降のステップで使用

---

- [ ] **7C-0-03**
  - 確認内容：TARGET DB が localhost / unix socket 接続であること
  - 期待結果：`inet_server_addr()` が `NULL`（unix socket）または `127.0.0.1`
  - 担当：岡井さん
  - 実行方法：`docker exec $DB_CONTAINER psql -U postgres -d postgres -c "SELECT inet_server_addr(), inet_server_port(), current_database();"`
  - 証拠：出力を記録
  - 結果：[ PASS / SAFETY ABORT ]
  - 停止条件：`127.0.0.1` / `NULL` 以外 → **SAFETY ABORT**
  - 備考：runbook §9 Step T-1 相当

---

- [ ] **7C-0-04**
  - 確認内容：DB ZIP checksum が一致すること
  - 期待結果：`D15A576B153552D422E1EE4A142BE5F63D2CB16B2CD66CC6AF67BC097D263C84`
  - 担当：岡井さん
  - 実行方法：`Get-FileHash "C:\Users\okai1\Documents\test\backups\20260726-222121.sql.zip" -Algorithm SHA256`
  - 証拠：Hash 値を記録
  - 結果：[ PASS / FAIL ]
  - 停止条件：不一致 → FAIL・進行不可
  - 備考：原本 ZIP は変更しない

---

- [ ] **7C-0-05**
  - 確認内容：Storage ZIP checksum が一致すること
  - 期待結果：`5E6692E3A5E094910D8A778EE0B99A25F247B5348F0DF7952AE9E6C270D1B1C9`
  - 担当：岡井さん
  - 実行方法：`Get-FileHash "C:\Users\okai1\Documents\test\backups\20260726-222706-storage.zip" -Algorithm SHA256`
  - 証拠：Hash 値を記録
  - 結果：[ PASS / FAIL ]
  - 停止条件：不一致 → FAIL・進行不可
  - 備考：原本 ZIP は変更しない

---

- [ ] **7C-0-06**
  - 確認内容：html-smoke フォルダに SOURCE URL が残存しないこと
  - 期待結果：0件（一時 HTML コピーがある場合は URL 置換済み）
  - 担当：岡井さん
  - 実行方法：`Select-String -Path ".\html-smoke\*.html" -Pattern "supabase\.co"` → 0件
  - 証拠：出力を記録（0件であること）
  - 結果：[ PASS / SAFETY ABORT ]
  - 停止条件：1件でも検出 → **SAFETY ABORT**
  - 備考：runbook §18 Step A-3 参照。html-smoke 未作成なら本項 SKIP（ smoke 前に再確認）

---

- [ ] **7C-0-07**
  - 確認内容：必要ツールが利用可能であること
  - 期待結果：全ツールが利用可能
  - 担当：岡井さん
  - 実行方法：`docker --version`・`supabase --version`（restore-lab 内）
  - 証拠：バージョン出力を記録
  - 結果：[ PASS / BLOCKED ]
  - 停止条件：未導入 / 起動していない → BLOCKED
  - 備考：Docker Desktop 4.83.0 / Supabase CLI 2.109.1（参考）

---

## 7C-1 DB restore 前

> runbook §8〜§10 を参照。全項目 PASS 後に岡井さんが human gate を承認してから restore 実行。

---

- [ ] **7C-1-01**
  - 確認内容：DB ZIP 作業コピーの展開が完了し、3ファイルが存在すること
  - 期待結果：`roles.sql`・`schema.sql`・`data.sql` の 3件が `.\backups\20260726-db\` に存在
  - 担当：岡井さん
  - 実行方法：runbook §8 Step C-3 を実行後、`Get-ChildItem ".\backups\20260726-db\"` で確認
  - 証拠：ファイル一覧
  - 結果：[ PASS / FAIL ]
  - 停止条件：ファイル欠落 → FAIL
  - 備考：原本 ZIP は変更しない

---

- [ ] **7C-1-02**
  - 確認内容：data.sql に session / throttle の COPY 文が含まれるか確認
  - 期待結果：実測値を記録（含まれていても含まれていなくても FAIL にしない）
  - 担当：岡井さん
  - 実行方法：runbook §8 Step C-4（`Select-String`）を実行
  - 証拠：マッチ結果を記録
  - 結果：[ 記録のみ ]
  - 停止条件：なし（情報記録）
  - 備考：runbook §12 の session / throttle 削除ステップへ引き継ぐ

---

- [ ] **7C-1-03**
  - 確認内容：TARGET DB の default privileges 確認（Step D-1）
  - 期待結果：実測値を記録。過大 grant（anon / authenticated に `arwdDxtm` 等）が確認された場合は Step D-2 を実施
  - 担当：岡井さん（Claude サポート）
  - 実行方法：runbook §10 Step D-1 SQL を docker exec psql で実行
  - 証拠：クエリ結果を記録
  - 結果：[ PASS / D-2要 ]
  - 停止条件：過大 grant 検出かつ Step D-2 未承認の場合は proceed しない
  - 備考：runbook §10 参照

---

- [ ] **7C-1-04**
  - 確認内容：SQL ファイルをコンテナへ転送済みであること
  - 期待結果：`docker exec $DB_CONTAINER ls /tmp/*.sql` が 3件返る
  - 担当：岡井さん
  - 実行方法：`docker cp` 後に `docker exec $DB_CONTAINER ls /tmp/roles.sql /tmp/schema.sql /tmp/data.sql`
  - 証拠：ファイル存在確認出力
  - 結果：[ PASS / FAIL ]
  - 停止条件：転送失敗 → FAIL
  - 備考：参照コマンド構造は前回設計案参照

---

- [ ] **7C-1-05**
  - 確認内容：restore 実行前 human gate（岡井さん明示承認）
  - 期待結果：岡井さんが承認後に restore を実行
  - 担当：岡井さん
  - 実行方法：7C-0〜7C-1-04 を全確認後に岡井さんが「実行」と明示する
  - 証拠：承認記録
  - 結果：[ 承認済み / 未承認 ]
  - 停止条件：未承認のまま restore 実行 → SAFETY ABORT
  - 備考：runbook §11 Step R-DB-1 参照

---

## 7C-2 DB restore 後・固定期待値

> `docs/sql/phase7c-restore-postcheck.sql` を docker exec psql で実行し、以下を確認する。

---

- [ ] **7C-2-01**
  - 確認内容：`employees` 件数
  - 期待結果：**11**
  - 担当：岡井さん
  - 実行方法：postcheck SQL の `employees_total` セクション
  - 証拠：クエリ出力
  - 結果：[ PASS / FAIL ]　実測値：___
  - 停止条件：11以外 → FAIL（続行不可）
  - 備考：Phase 5-D-3 実行記録より確定

---

- [ ] **7C-2-02**
  - 確認内容：`employees.pin_hash` NOT NULL 件数
  - 期待結果：**11**
  - 担当：岡井さん
  - 実行方法：postcheck SQL
  - 証拠：クエリ出力
  - 結果：[ PASS / FAIL ]　実測値：___
  - 停止条件：11以外 → FAIL
  - 備考：Phase 5-D-3 実行記録

---

- [ ] **7C-2-03**
  - 確認内容：`employees.pin_hash` NULL 件数
  - 期待結果：**0**
  - 担当：岡井さん
  - 実行方法：postcheck SQL
  - 証拠：クエリ出力
  - 結果：[ PASS / FAIL ]　実測値：___
  - 停止条件：1件以上 → FAIL
  - 備考：Phase 5-D-3 実行記録

---

- [ ] **7C-2-04**
  - 確認内容：`employees.pin` NOT NULL 件数（Phase 5-D-6 未実施のため pin 列は残存）
  - 期待結果：**11**（DROP 未実施のため 11件残存が正常）
  - 担当：岡井さん
  - 実行方法：postcheck SQL
  - 証拠：クエリ出力
  - 結果：[ PASS / FAIL ]　実測値：___
  - 停止条件：0件（pin 列が消えている）→ 要調査
  - 備考：Phase 5-D-6 は未開始。pin 列 DROP は未実施。pin が 0件は異常。

---

- [ ] **7C-2-05**
  - 確認内容：`pin_hash` の bcrypt cost が 12（`$2b$12$` または `$2a$12$` or `$2y$12$`）
  - 期待結果：全 11件が `^\$2[aby]\$12\$` に一致
  - 担当：岡井さん
  - 実行方法：postcheck SQL（bcrypt prefix チェック）
  - 証拠：クエリ出力（一致件数 = 11）
  - 結果：[ PASS / FAIL ]　実測値：___
  - 停止条件：11未満 → FAIL
  - 備考：Phase 5-D-3 実行記録

---

- [ ] **7C-2-06**
  - 確認内容：`private.login_throttle` の owner と RLS 状態
  - 期待結果：owner = `postgres`、RLS enabled、policy 0本
  - 担当：岡井さん
  - 実行方法：postcheck SQL
  - 証拠：クエリ出力
  - 結果：[ PASS / FAIL ]
  - 停止条件：不一致 → FAIL
  - 備考：Phase 5-C-1a 記録

---

- [ ] **7C-2-07**
  - 確認内容：`employee_sessions` と `admin_sessions` の RLS 状態
  - 期待結果：両テーブルとも RLS enabled・policy 0本
  - 担当：岡井さん
  - 実行方法：postcheck SQL
  - 証拠：クエリ出力
  - 結果：[ PASS / FAIL ]
  - 停止条件：不一致 → FAIL
  - 備考：Phase 3 記録

---

- [ ] **7C-2-08**
  - 確認内容：session / throttle 削除後の件数
  - 期待結果：`employee_sessions` = 0、`admin_sessions` = 0、`private.login_throttle` = 0
  - 担当：岡井さん（runbook §12 Step S-3 実行後）
  - 実行方法：postcheck SQL（削除後確認）
  - 証拠：クエリ出力
  - 結果：[ PASS / FAIL ]
  - 停止条件：0以外 → FAIL
  - 備考：削除前件数は 7C-3 に記録

---

## 7C-3 DB restore 後・実測記録

> 以下は固定期待値なし。Phase 7-D 記録として実測値を残す。

---

- [ ] **7C-3-01**
  - 確認内容：public schema テーブル数
  - 期待結果：実測値を記録（固定値なし）
  - 担当：岡井さん
  - 実行方法：postcheck SQL
  - 証拠：クエリ出力
  - 結果：[ 記録 ]　実測値：___

---

- [ ] **7C-3-02**
  - 確認内容：`reports` 件数（バックアップ取得時点）
  - 期待結果：実測値を記録
  - 担当：岡井さん
  - 実行方法：postcheck SQL
  - 証拠：クエリ出力
  - 結果：[ 記録 ]　実測値：___

---

- [ ] **7C-3-03**
  - 確認内容：session / throttle 削除前件数
  - 期待結果：実測値を記録（削除前に記録してから削除する）
  - 担当：岡井さん
  - 実行方法：postcheck SQL（Step S-1 前に実行）
  - 証拠：クエリ出力
  - 結果：[ 記録 ]　employee_sessions:___ admin_sessions:___ throttle:___

---

- [ ] **7C-3-04**
  - 確認内容：anon / authenticated の direct table grant 状態
  - 期待結果：Phase 4-F 完了後は 0件（実測値を記録・0件でなければ要調査）
  - 担当：岡井さん（ChatGPT サポート）
  - 実行方法：postcheck SQL（grants セクション）
  - 証拠：クエリ出力
  - 結果：[ 記録 / 0件PASS / 0件以外は要確認 ]　実測値：___

---

- [ ] **7C-3-05**
  - 確認内容：RLS 有効テーブル一覧（`db-migrations.md` baseline と比較）
  - 期待結果：Phase 3〜5 で RLS 設定されたテーブルが enabled
  - 担当：岡井さん（Claude サポート）
  - 実行方法：postcheck SQL（RLS セクション）
  - 証拠：クエリ出力
  - 結果：[ PASS / 不一致は要確認 ]

---

- [ ] **7C-3-06**
  - 確認内容：critical RPC の存在・owner・SECURITY DEFINER・search_path
  - 期待結果：postcheck SQL の期待値と一致
  - 担当：岡井さん（Claude サポート）
  - 実行方法：postcheck SQL（RPC セクション）
  - 証拠：クエリ出力
  - 結果：[ PASS / FAIL ]

---

## 7C-4 Storage restore

> runbook §13〜§15・`docs/sql/phase7d-storage-policy-restore.sql` を参照。

---

- [ ] **7C-4-01**
  - 確認内容：photos バケットが作成・設定されていること
  - 期待結果：`public=true`・`file_size_limit=5242880`・`allowed_mime_types={image/jpeg}`
  - 担当：岡井さん
  - 実行方法：`docs/sql/phase7d-storage-policy-restore.sql` の post-check セクション（または Studio 確認）
  - 証拠：クエリ出力または Studio スクリーンショット
  - 結果：[ PASS / FAIL ]
  - 停止条件：存在しない / 設定不一致 → FAIL

---

- [ ] **7C-4-02**
  - 確認内容：`storage.objects` RLS が enabled であること
  - 期待結果：`relrowsecurity = true`
  - 担当：岡井さん
  - 実行方法：postcheck SQL（Storage RLS セクション）
  - 証拠：クエリ出力
  - 結果：[ PASS / BLOCKED ]
  - 停止条件：RLS disabled → BLOCKED（自動変更せず・3者確認後に対処）
  - 備考：local Supabase のデフォルト状態を確認

---

- [ ] **7C-4-03**
  - 確認内容：`photos_read`・`photos_upload` policy が Production baseline と一致すること
  - 期待結果：`docs/sql/phase7d-storage-policy-restore.sql` で設定した定義と一致
  - 担当：岡井さん
  - 実行方法：postcheck SQL（photos policy セクション）
  - 証拠：クエリ出力
  - 結果：[ PASS / FAIL ]
  - 停止条件：policy なし / 定義不一致 → FAIL
  - 備考：KC-5（PUBLIC INSERT は既知リスク）

---

- [ ] **7C-4-04**
  - 確認内容：photos 既存 4件が全件 local Storage にアップロードされていること
  - 期待結果：object 件数 = 4・manifest OK=4 と一致
  - 担当：岡井さん
  - 実行方法：runbook §14 Step P-3・P-4 完了後、Studio または API で object 件数確認
  - 証拠：object 一覧（path・size・MIME を 4件全件記録）
  - 結果：[ PASS / FAIL ]　実測件数：___
  - 停止条件：4件未満 → FAIL

---

- [ ] **7C-4-05**
  - 確認内容：`reports.photo_urls` の SOURCE URL 残存が 0件であること（URL 変換後）
  - 期待結果：SOURCE URL を含む rows = 0
  - 担当：岡井さん
  - 実行方法：`docs/sql/phase7d-target-photo-url-rewrite.sql` の事後確認セクション
  - 証拠：クエリ出力（0件）
  - 結果：[ PASS / FAIL ]
  - 停止条件：1件以上 → FAIL（application smoke に進まない）
  - 備考：TARGET DB のみ。SOURCE では絶対実行しない

---

- [ ] **7C-4-06**
  - 確認内容：Production Storage への通信が発生していないこと
  - 期待結果：Storage 操作中・後に Production URL への通信なし
  - 担当：岡井さん
  - 実行方法：Network tab（または Supabase status）で確認
  - 証拠：確認記録
  - 結果：[ PASS / SAFETY ABORT ]
  - 停止条件：Production Storage URL への通信検出 → **SAFETY ABORT**

---

## 7C-5 Application smoke

> runbook §18 参照。html-smoke フォルダの一時 HTML を使用。本番 HTML は変更しない。

---

- [ ] **7C-5-01**
  - 確認内容：html-smoke の一時 HTML に SOURCE URL が残存しないこと（smoke 開始前再確認）
  - 期待結果：0件
  - 担当：岡井さん
  - 実行方法：`Select-String -Path ".\html-smoke\*.html" -Pattern "supabase\.co"` → 0件
  - 証拠：出力（0件）
  - 結果：[ PASS / SAFETY ABORT ]
  - 停止条件：1件以上 → **SAFETY ABORT**

---

- [ ] **7C-5-02**
  - 確認内容：従業員ログイン（正しい PIN）が成功すること
  - 期待結果：ログイン成功・セッション発行
  - 担当：岡井さん
  - 実行方法：`index.html`（html-smoke）をブラウザで開き、既存従業員 PIN でログイン
  - 証拠：画面確認・ログイン成功
  - 結果：[ PASS / FAIL ]
  - 停止条件：失敗 → FAIL（続行不可）
  - 備考：Network tab を常に開く

---

- [ ] **7C-5-03**
  - 確認内容：管理画面ログインが成功すること
  - 期待結果：管理画面ログイン成功
  - 担当：岡井さん
  - 実行方法：`admin-app.html`（html-smoke）で管理者 PIN ログイン
  - 証拠：画面確認
  - 結果：[ PASS / FAIL ]
  - 停止条件：失敗 → FAIL
  - 備考：Network tab 確認

---

- [ ] **7C-5-04**
  - 確認内容：原価画面ログインが成功すること
  - 期待結果：原価管理ダッシュボードが表示される
  - 担当：岡井さん
  - 実行方法：`genka-app.html`（html-smoke）でログイン
  - 証拠：画面確認
  - 結果：[ PASS / FAIL ]
  - 停止条件：失敗 → FAIL
  - 備考：Network tab 確認

---

- [ ] **7C-5-05**
  - 確認内容：日報一覧が表示されること
  - 期待結果：日報一覧が件数正常に表示される
  - 担当：岡井さん
  - 実行方法：従業員ログイン後に日報タブを表示
  - 証拠：件数を記録（7C-3-02 の `reports` 件数と整合）
  - 結果：[ PASS / FAIL ]　表示件数：___

---

- [ ] **7C-5-06**
  - 確認内容：写真が TARGET local Storage URL から表示されること
  - 期待結果：写真が `http://127.0.0.1:54321/storage/v1/object/public/photos/...` から読み込まれる
  - 担当：岡井さん
  - 実行方法：日報詳細で写真を表示・Network tab の img src を確認
  - 証拠：Network tab のリクエスト URL を記録（最低 1件）
  - 結果：[ PASS / FAIL / KNOWN CONSTRAINT ]
  - 停止条件：SOURCE URL（`supabase.co`）から読み込んでいる → SAFETY ABORT

---

- [ ] **7C-5-07**
  - 確認内容：Network tab の接続先が local のみであること
  - 期待結果：全リクエストが `127.0.0.1:54321` のみ（Supabase Production URL なし）
  - 担当：岡井さん
  - 実行方法：browser DevTools Network tab を全操作中に監視
  - 証拠：確認記録（Production URL なし）
  - 結果：[ PASS / SAFETY ABORT ]
  - 停止条件：Production URL（`supabase.co`）への通信検出 → **SAFETY ABORT**

---

- [ ] **7C-5-08**
  - 確認内容：write smoke（日報 1件作成 + 写真 1件アップロード）
  - 期待結果：日報が作成され、写真が local Storage に保存・read-back 確認
  - 担当：岡井さん
  - 実行方法：
    1. 従業員ログイン（7C-5-02 セッション継続）
    2. 日報 1件登録（現場・日付・JPEG写真 1件）
    3. `list_my_reports_secure` で read-back 確認
    4. 登録した日報の写真を browser で表示（TARGET URL から）
    5. Network tab で Production 通信なし確認
  - 証拠：日報 ID を記録・写真 URL を記録・Network tab 確認
  - 結果：[ PASS / FAIL ]　作成日報 ID：___　写真 object path：___
  - 停止条件：DB write 失敗・Storage upload 失敗・Production 通信検出（SAFETY ABORT）
  - 備考：従業員新規作成・更新・PIN 変更は対象外。restore-lab 破棄で cleanup。

---

## 7C-6 Cleanup / 最終判定

---

- [ ] **7C-6-01**
  - 確認内容：html-smoke の一時 HTML コピーが削除されていること
  - 期待結果：`html-smoke\*.html` が 0件
  - 担当：岡井さん
  - 実行方法：runbook §18 Step A-5 実行後に `Get-ChildItem ".\html-smoke\"` → 0件
  - 証拠：ディレクトリ確認
  - 結果：[ PASS / FAIL ]

---

- [ ] **7C-6-02**
  - 確認内容：DB backup 作業コピーが削除されていること（原本 ZIP は保持）
  - 期待結果：`.\backups\20260726-db\` が削除済み。原本 ZIP は残存
  - 担当：岡井さん
  - 実行方法：runbook §20 cleanup 実行後に確認
  - 証拠：フォルダ確認
  - 結果：[ PASS / FAIL ]

---

- [ ] **7C-6-03**
  - 確認内容：`.env.restore` 等の一時ファイルが削除されていること
  - 期待結果：一時ファイルなし
  - 担当：岡井さん
  - 実行方法：`Test-Path ".\\.env.restore"` → False
  - 証拠：確認記録
  - 結果：[ PASS / FAIL ]

---

- [ ] **7C-6-04**
  - 確認内容：repo working tree が clean であること
  - 期待結果：変更なし
  - 担当：岡井さん（Claude サポート）
  - 実行方法：`git status -sb` → clean
  - 証拠：git status 出力
  - 結果：[ PASS / FAIL ]

---

- [ ] **7C-6-05**
  - 確認内容：Production DB / Storage が無変更であること
  - 期待結果：Production への write / delete / policy 変更なし
  - 担当：3者確認
  - 実行方法：今回の操作を振り返り、Production 操作がなかったことを確認
  - 証拠：確認記録
  - 結果：[ PASS / SAFETY ABORT ]
  - 停止条件：Production 変更の形跡 → **SAFETY ABORT**

---

- [ ] **7C-6-06**
  - 確認内容：最終判定・3者合意
  - 期待結果：全必須項目 PASS または KNOWN CONSTRAINT のみ
  - 担当：3者合意（岡井さん・ChatGPT・Claude）
  - 実行方法：本 checklist を 3者でレビュー
  - 証拠：判定記録
  - 結果：[ PASS / FAIL / BLOCKED ]
  - 備考：合格時 → `RESTORE VIABILITY: CONFIRMED WITH KNOWN LIMITATIONS`

---

## Phase 7-D 開始前 gate（runbook §23 より）

全て揃ってから Phase 7-D を開始する：

- [ ] Phase 7-B runbook（`docs/restore-runbook.md`）について 3者合意済み
- [ ] Phase 7-C smoke checklist（本書）作成済み
- [ ] psql 実行方式（Docker exec）決定済み
- [ ] restore-lab 専用フォルダ（`C:\Users\okai1\Documents\supabase-restore-lab`）の場所決定済み
- [ ] 岡井さんが「Phase 7-D 開始してよい」と明示承認済み

---

## 実施記録

| 項目 | 記録 |
|---|---|
| Phase 7-D 実施日 | |
| 実施者 | 岡井さん |
| restore-lab パス | `C:\Users\okai1\Documents\supabase-restore-lab` |
| DB container 名 | |
| backup DB ZIP | `20260726-222121.sql.zip` |
| backup Storage ZIP | `20260726-222706-storage.zip` |
| 最終判定 | |
| KNOWN CONSTRAINTS | KC-1〜KC-5 |
