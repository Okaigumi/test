# Phase 7-D 非本番 restore test 実行記録

**判定：**

| 項目 | 結果 |
|---|---|
| Phase 7-D Technical Validation | **COMPLETE** |
| Restore Viability | **CONFIRMED** |
| Phase 7-D Close | **正式クローズ済み（2026-08-06）** |

Phase 7-A で取得したバックアップ（DB ZIP / Storage photos ZIP）から、local restore-lab へ DB・Storage・写真 URL・アプリケーション動作までを復元し、read smoke・write smoke まで合格した。**バックアップからの復旧可能性は実証済みである。**

**【2026-08-06 正式クローズ】** クローズ条件（§15）はすべて充足した。

| 条件 | 状態 |
|---|---|
| PR-1（本実行記録）の main merge | 完了・merge commit `3b084ecb49c14bda7b169b385a529185abb6eb57` |
| PR-2（restore tooling fixes）の main merge | 完了・PR #182・merge commit `d3c1295d1b62b7b282bf3a1e60ba9a51dbaba584` |
| 3 者（岡井さん・ChatGPT・Claude）合意 | 完了・3 者とも「クローズ可」 |
| Production への変更 | なし |

当初クローズを保留していた理由は、restore そのものの問題ではなく、**tooling（post-check SQL / photo URL rewrite SQL）と documentation（restore runbook）側の不備**により「repo の正本どおりに実行して同じ結果を再現できる」状態でなかったことである。この不備は PR-2 で解消し、修正後の正本 SQL を無改変実行して再検証合格した（§14）。

**Phase 7-D のみを正式クローズとする。Phase 7 全体は引き続き未完了**（7-E / 7-F 未着手）であり、`data.sql` への `auth` / `storage` COPY 27 ブロック混入の**原因分析は PR-3（backup pipeline hardening）に残す**。

---

## 1. 実施概要

| 項目 | 内容 |
|---|---|
| 実施日 | 2026-08-05 |
| 実施環境 | 自宅 PC（Windows） |
| restore-lab | `C:\Users\okai1\Documents\supabase-restore-lab`（repo 外） |
| 使用バックアップ | DB：`20260726-222121.sql.zip` / Storage：`20260726-222706-storage.zip`（取得日 2026-07-26） |
| TARGET | local Supabase（Docker）・`127.0.0.1` のみ |
| SOURCE（Production） | **接続なし・変更なし** |
| 実行者 | 岡井さん（DB write・psql・Storage 操作すべて） |
| 手順の正本 | `docs/restore-runbook.md`（Phase 7-B）／`docs/phase7c-restore-smoke-checklist.md`（Phase 7-C） |

### 安全ガードの実績

- TARGET が localhost であることを実行前に確認済み
- restore は clean TARGET に対してのみ実施
- 明示 `BEGIN` / `COMMIT` による単一 transaction 方式
- SOURCE（Production）への接続・書き込み・dump 再取得：**すべて 0 件**
- SAFETY ABORT 該当事象：**0 件**

---

## 2. DB restore 結果

| 項目 | 結果 |
|---|---|
| 適用順序 | `roles.sql` → `schema.sql` → `data-restore-safe.sql` |
| transaction | 明示 `BEGIN` / `COMMIT` の単一 transaction |
| COMMIT | 確認済み |
| 除外した COPY | `auth` / `storage` の COPY 27 ブロック |
| 除外した setval | `auth` refresh_tokens sequence setval 1 件 |
| 結果 | **成功** |

---

## 3. data.sql 検証と派生ファイル破損（重要）

### 3-1. 原本 `data.sql`（正常）

| 項目 | 実測 |
|---|---|
| COPY 総数 | 49 |
| `public` / `private` COPY | 22 |
| `auth` / `storage` COPY | 27 |
| 列数不一致 | 0 |
| 文字コード | UTF-8 正常 |
| mojibake | 0 |
| `genka_admins` | 5 列 / 5 項目で正常 |

**原本 `data.sql` は破損していない。**

### 3-2. 破損した派生ファイル（使用禁止）

| ファイル | 列数不一致 | 扱い |
|---|---|---|
| `data-target.sql` | 109 | **使用禁止** |
| `data-restore.sql` | 117 | **使用禁止** |
| `data-restore-v2.sql` | 117 | **使用禁止** |

### 3-3. 破損原因（確定）

1. Windows PowerShell 5.1 の `Get-Content` を `-Encoding` 未指定で使用した
2. UTF-8 原本を CP932 として誤読し mojibake が発生した
3. 日本語直後の TAB が CP932 の後続バイトとして巻き込まれ、**列区切りが消失**した
4. `StreamWriter` / `WriteAllLines` により CRLF 化された
5. 結果、restore 時に `genka_admins.is_active`（boolean）へ timestamp が流入し、400 / boolean 変換エラーとなった

**恒久ルール（PR-2 で `docs/restore-runbook.md` へ明記する）：Windows PowerShell 5.1 の `Get-Content` / `WriteAllLines` による SQL ファイル加工を禁止する。**

### 3-4. 正式に使用したファイル：`data-restore-safe.sql`

生成条件：

- `UTF8Encoding(false, true)` による strict UTF-8 読込
- `UTF8Encoding(false)` による BOM なし書込
- `NewLine = LF`
- `auth` / `storage` の COPY 除外
- `auth` / `storage` の setval 除外

検証結果：

| 項目 | 実測 |
|---|---|
| COPY 数 / 終端数 | 22 / 22 |
| 列数不一致 | 0 |
| `auth` / `storage` 操作 | 0 |
| 半角カナ | 0 |
| CR | 0 |
| BOM | なし |

---

## 4. DB post-check 結果

### 4-1. 実測値

| 確認項目 | 実測 |
|---|---|
| public テーブル数 | 21 |
| private テーブル数 | 1 |
| `employees` | 11 |
| `reports` | 215 |
| `genka_admins` | 1 |
| `sites` | 20 |
| `site_assignments` | 30 |
| `site_budgets` | 10 |
| `employee_rates` | 13 |
| `unit_rates` | 7 |
| `materials` | 12 |
| `machines` | 26 |
| `notices` | 4 |
| `invoices` | 10 |
| `employees.pin_hash` NULL | 0 |
| bcrypt cost | 12 |
| `public` / `private` 22 テーブルの RLS | すべて enabled |

`employees` 11 件・`pin_hash` NULL 0 件・bcrypt cost 12 は、Phase 5-D-3 実行記録の baseline と一致する。

### 4-2. スキーマ実在確認

| テーブル | 結果 |
|---|---|
| `public.rates` | **不存在** |
| `public.employee_rates` | 存在 |
| `public.unit_rates` | 存在 |

### 4-3. post-check SQL の stale 参照と、実際の確認経路（restore 失敗ではない）

正本 `docs/sql/phase7c-restore-postcheck.sql` は SECTION 1-2 で `public.rates` を参照しており、**この stale 参照により途中停止した**。

実際の確認経路は次のとおりである。

1. 正本 SQL は `public.rates` の stale 参照で途中停止した
2. その後、**代替の read-only SQL により主要項目を確認**し、4-1 / 4-2 の実測値を取得した
3. 確認できた主要項目：`employees`=11／`reports`=215／`pin_hash` NULL=0／bcrypt cost=12／`public`・`private` 22 テーブル RLS enabled／`public.rates` 不存在／`employee_rates`・`unit_rates` 存在

補足：

- `public.rates` は**現行スキーマに存在しないテーブル**であり、正しくは `employee_rates` / `unit_rates` である
- これは **restore の失敗ではなく、post-check SQL 側の stale 参照**である
- **ただし、正本 SQL 全体をそのまま完走させた証拠はない。** 上記の主要項目は代替 read-only SQL により確認したものである
- 修正は **PR-2** で実施する。修正後に正本 SQL を完走させる再検証は PR-2 の検証項目とする
- **→ 2026-08-06 の PR-2 再検証（§14-2）で完走・終了コード 0 を確認し、本項の残課題は解消した**

---

## 5. session / throttle 処理

local TARGET 内のみで削除し COMMIT 済み。SOURCE（Production）では実行していない。

| テーブル | 削除後の件数 |
|---|---|
| `public.employee_sessions` | 0 |
| `public.admin_sessions` | 0 |
| `private.login_throttle` | 0 |

---

## 6. Storage restore 結果

**使用 SQL：`docs/sql/phase7d-storage-policy-restore.sql`（正本をそのまま実行）。代替 SQL・手動代替手順は使用していない。**

| 項目 | 結果 |
|---|---|
| `photos` bucket | 作成済み |
| public | true |
| file_size_limit | 5,242,880 bytes（5 MB） |
| allowed_mime_types | `image/jpeg` |
| `storage.objects` RLS | enabled |
| `photos_read` policy | 作成済み |
| `photos_upload` policy | 作成済み |
| COMMIT | 確認済み |
| post-check | 合格 |
| Storage ZIP manifest | 4 件すべて OK |
| アップロード | JPEG 4 件 |
| HTTP 応答 | 200 × 4 |
| `storage.objects` photos 件数 | 4 |
| Content-Type | `image/jpeg` |
| Content-Length | 元ファイルサイズと一致 |

---

## 7. photo_urls rewrite 結果

local TARGET のみで更新。

| 項目 | 結果 |
|---|---|
| UPDATE | 4 |
| COMMIT | 済み |
| local を指す photo_urls | 4 |
| SOURCE を指す photo_urls | 0 |

### 既存 SQL の不具合（restore 失敗ではない）

`docs/sql/phase7d-target-photo-url-rewrite.sql` は、GATE 2 の `DO` ブロック内で psql 変数 `:'target_base'` を参照している。psql は dollar-quote（`$$ ... $$`）内を変数展開しないため、**syntax error となり実行できなかった**。

- 代替の runtime SQL で local TARGET のみを更新し、上記の結果を得た
- 一時 runtime SQL は削除済み
- 修正は **PR-2** で実施する
- **→ 2026-08-06 の PR-2 再検証（§14-3）で正本 SQL の無改変実行に成功し、本項の残課題は解消した**

---

## 8. application smoke 結果

### 8-1. 実施条件

- repo 外へコピーして実施：`C:\Users\okai1\Documents\supabase-restore-lab\html-smoke`
- **repo 内の HTML（`index.html` / `admin-app.html` / `genka-app.html`）は変更していない**
- 一時 HTML のみ local Supabase URL / local client key へ置換
- 実値（local key）は docs へ記録しない

### 8-2. read smoke（3 画面・すべて合格）

| # | 画面 | 結果 |
|---|---|---|
| 1 | `index.html`（従業員） | 従業員ログイン成功／`list_my_reports_secure` 成功／日報カレンダー・一覧表示／2026-07-26 backup 時点のデータ表示／写真付き日報 4 件のうち 1 件を開き写真表示成功 |
| 2 | `admin-app.html`（管理者） | 管理者ログイン成功／現場一覧等の表示／`list_sites_admin_secure` 等の RPC 成功 |
| 3 | `genka-app.html`（原価管理） | 原価管理者ログイン成功／原価画面表示／重大 Console エラーなし |

3 画面共通：

- Request URL は `127.0.0.1:54321` のみ
- RPC はすべて 200
- **`supabase.co` への業務通信なし**

### 8-3. write smoke（合格）

初回試行：

- `upsert_employee_rate_secure` が 400 Bad Request（`Invalid or expired session`）

原因（切り分け済み）：

- session / throttle cleanup で `admin_sessions` を 0 件にした後も、**ブラウザの localStorage に古い token が残っていた**ため
- **RPC の不具合ではない**

対応：

- `localStorage.clear()` / `sessionStorage.clear()` の後に再ログイン

再実施：

| 項目 | 結果 |
|---|---|
| 操作 | 既存 employee rate を同値で保存 |
| RPC | `upsert_employee_rate_secure` |
| 応答 | 200 OK |
| 画面 | 保存成功表示 |
| 保存前後の値 | 同一 |
| Request URL | `127.0.0.1:54321` |

**write smoke 合格。**

この事象は runbook に未記載であり、**stale browser session の clear / 再ログイン手順**として PR-2 で追記する。

---

## 9. cleanup / 停止状態

| 項目 | 状態 |
|---|---|
| 一時 HTML サーバー | 停止済み（port 5500 listening：False） |
| local Supabase | 停止済み（supabase DB running：False） |
| Docker volume | 保持 |
| `input` / `work` / `html-smoke` / 検証ファイル | 保持 |
| backup 原本 ZIP | 変更なし |
| Production / Vercel | **変更なし** |

Docker volume と検証ファイルを保持しているため、PR-2 の SQL 修正後に**同一環境で再検証することが可能**である。

---

## 10. 既知制約（Known Constraints）

`docs/phase7c-restore-smoke-checklist.md` の定義に従い、以下は FAIL 条件としない。

| # | 内容 |
|---|---|
| KC-1 | `notice-attachments` 実ファイル：現行バックアップ非対象（Phase 7-F） |
| KC-2 | `invoice-pdfs` 実ファイル：現行バックアップ非対象（Phase 7-F） |
| KC-3 | Storage 孤立ファイル：バックアップ対象外 |
| KC-4 | バックアップ取得日（2026-07-26）以降のデータ：RPO 外 |
| KC-5 | `photos_upload` が PUBLIC INSERT policy（employee session 検証なし・path 制限なし）。restore-lab では Production 実装を忠実に再現した。将来のセキュリティレビュー候補であり、今回 Production の変更は行っていない |

---

## 11. backup dump の内容に関する記録（事実のみ）

今回の検証において、**backup dump の `data.sql` に `auth` / `storage` の COPY が 27 ブロック含まれていた**ことを確認した。

一方、`docs/restore-runbook.md` §3 および `docs/backup-recovery-inventory.md` は「DB dump に `auth` / `storage` は含まれない」という前提で記述されている。

- 本記録では、**この事実の記録のみ**を行う
- 原因の特定・`scripts/backup-supabase.ps1` の設計改善・dump scope の見直しは **PR-3（backup pipeline hardening）で実施する**
- 現時点で特定のスクリプトを原因と断定しない
- 機密区分への影響（`docs/backup-recovery-inventory.md` §3）についても PR-3 で評価する

---

## 12. 判明した tooling / documentation 課題

restore そのものではなく、tooling と documentation 側の課題である。

| # | 対象 | 内容 | 対応 PR |
|---|---|---|---|
| T-1 | `docs/sql/phase7c-restore-postcheck.sql` | stale な `public.rates` 参照。`employee_rates` / `unit_rates` へ更新が必要 | PR-2（**修正済み・§14-2 で再検証合格**） |
| T-2 | `docs/sql/phase7d-target-photo-url-rewrite.sql` | `DO` ブロック内の psql 変数参照が syntax error。変数を SQL literal へ安全に渡す方式へ修正が必要 | PR-2（**修正済み・§14-3 で再検証合格**） |
| T-3 | `docs/restore-runbook.md` | PowerShell 5.1 での SQL 加工禁止／UTF-8 strict・LF・TAB 保持手順／clean TARGET 限定／明示 BEGIN・COMMIT 方式／stale browser session の clear・再ログイン手順／application smoke 手順／localhost-only 確認／SOURCE・TARGET URL の取り扱い／失敗時の rollback 検証手順 | PR-2（**改訂済み・runbook §24**） |
| T-4 | `scripts/backup-supabase.ps1` | schema dump と data dump の対象スキーマ範囲の不一致／schema・data を別プロセス・別 snapshot で取得している点／`backup-info.txt` の時刻・scope・checksum 等の不足 | PR-3 |
| T-5 | restore 用自動検査（新規） | COPY header 列数と byte `0x09` の実測／mojibake・CR・BOM 検査／orphan COPY 検出／`auth`・`storage` 操作 0 の確認／auto restore smoke／成功後のみ ZIP 化／SHA256・manifest 生成 | PR-3 |

---

## 13. 正本 SQL の実行状況と記録の範囲

### 13-1. 正本 SQL の実行状況

| 正本 SQL | 実行状況 |
|---|---|
| `docs/sql/phase7d-storage-policy-restore.sql` | **正本どおり実行・post-check 合格済み**（§6 参照）。代替 SQL・手動代替手順は使用していない |
| `docs/sql/phase7c-restore-postcheck.sql` | 2026-08-05：**`public.rates` の stale 参照で途中停止**（§4-3）。→ 2026-08-06 PR-2 修正後：**無改変で SECTION 0〜5 完走・終了コード 0**（§14-2） |
| `docs/sql/phase7d-target-photo-url-rewrite.sql` | 2026-08-05：**psql 変数展開エラーにより実行不可**（§7）。→ 2026-08-06 PR-2 修正後：**無改変で実行成功・冪等性および negative test 合格**（§14-3） |

正本 SQL 2 本（post-check / photo URL rewrite）を修正し、修正後に正本のまま完走させる再検証を行うことは PR-2 の検証項目としていたが、**2026-08-06 に完了・合格した（§14）。** これにより「repo の正本どおりに実行して同じ結果を再現できる」状態に戻っている。

### 13-2. 記録の範囲（区別すべき 3 点）

- **`docs/phase7c-restore-smoke-checklist.md` の 46 項目について、項目別チェック表は未作成である。** 各項目の PASS / FAIL / BLOCKED / KNOWN CONSTRAINT の内訳は記録していない
- **主要検証結果は、本実行記録の本文（§2〜§9）に記録済みである。** DB restore・data.sql 検証・post-check 実測値・session / throttle・Storage restore・photo_urls rewrite・read smoke・write smoke がこれにあたる
- **Restore Viability：CONFIRMED の判定は、この主要検証結果に基づく。** 46 項目の項目別内訳の有無によって左右されるものではない

46 項目の項目別チェック表を今後どう運用するかは、PR-2 で次の方針に確定した。**項目別チェック表は毎回必須としない。主要検証結果と不合格項目を記録する運用とする。**

---

## 14. PR-2 tooling 修正後の再検証（2026-08-06）

PR-2 で正本 SQL を修正したうえで、**修正後の正本を無改変で実行**して再検証した。実施は岡井さん（Claude は DB 操作を行っていない）。

### 14-1. 実施時点の区別（重要）

本節の件数は **application / write smoke を実施した後の TARGET 状態**である。§4-1 の restore 直後 baseline とは別時点の値であり、突き合わせてはならない。

| 項目 | restore 直後 baseline（§4-1・§5・§7） | 本節の smoke 後再検証 |
|---|---|---|
| `reports` | 215 | 216 |
| `employee_rates` | 13 | 14 |
| `employee_sessions` | 0 | 1 |
| `admin_sessions` | 0 | 1 |
| `private.login_throttle` | 0 | 0 |
| photos（local URL） | 4 | 5 |

差分は §8 の write smoke と、smoke 時の再ログインによる正常な状態変化である。**restore の失敗ではない。**

### 14-2. `phase7c-restore-postcheck.sql`（修正後・無改変実行）

| 確認項目 | 結果 |
|---|---|
| SECTION 0〜5 の完走 | **完走**（途中停止なし） |
| psql 終了コード | **0** |
| expected objects（SECTION 0-1） | 23 件・全件存在 |
| unexpected objects（SECTION 0-2） | **0 件** |
| base_tables（SECTION 0-3） | 22 |
| rls_enabled | 22 |
| rls_disabled | **0** |
| views | 1（`public.report_summary`） |
| RLS 個別確認（SECTION 2-1） | 22 件すべて `rls_enabled=true` |

§4-3 で「正本 SQL 全体をそのまま完走させた証拠はない」としていた点は、**本再検証により解消した。** `public.rates` の stale 参照修正は合格である。

なお本再検証では、期待リストからの `public.notice_attachments` 削除と、`public.company_categories` / `public.site_categories` の追加が必要であることが SECTION 0 の drift 検出により判明し、正本へ反映済みである。

### 14-3. `phase7d-target-photo-url-rewrite.sql`（修正後・無改変実行）

**正常系（冪等性確認）：**

| 確認項目 | 結果 |
|---|---|
| GATE 1 / GATE 2 / GATE 3 | すべて通過 |
| `reports_with_source_url` | 0 |
| UPDATE | **0**（冪等） |
| `remaining_source_url_reports` | 0 |
| `final_source_url_check` | 0 |
| local URL | 5 件 |
| Storage 実体との一致 | 5/5（missing=0） |
| psql 終了コード | **0** |

§7 で「psql 変数展開エラーにより実行不可」としていた点は、**本再検証により解消した。**

**negative test（GATE 2・非 local なダミー `target_base` を指定）：**

| 確認項目 | 結果 |
|---|---|
| SAFETY ABORT の表示 | あり |
| psql 終了コード | **3** |
| BEGIN / UPDATE / COMMIT | **未到達** |
| 実行前後の DB 状態 | 216 / 5 / 5 / 0 で一致（**DB 変更なし**） |

### 14-4. `phase7d-storage-policy-restore.sql`（negative test）

| 確認項目 | 結果 |
|---|---|
| `confirmed` 未設定時の拒否 | あり |
| SAFETY ABORT の表示 | あり |
| psql 終了コード | **3** |
| bucket / policy 変更処理 | **未到達** |

### 14-5. gate 方式の確定（`\quit` は使用不可）

当初 PR-2 では `\quit 2` / `\quit 3` による非ゼロ終了を実装したが、negative test で**機能しないことが実証された**（`warning: \quit: extra argument "3" ignored` が出力され、終了コードは 0 のまま）。psql の `\quit` は終了コード引数を受け取らない。

そのため、全ての実行拒否経路を次の方式へ変更した。

1. ファイル冒頭で `\set ON_ERROR_STOP on`
2. `\echo` で拒否理由を表示
3. **psql 変数を一切含まない静的な `DO` ブロック**で `RAISE EXCEPTION`

この方式で psql 終了コード 3 が得られることを、14-3 / 14-4 の negative test で確認した。runbook §24-5 に恒久ルールとして記録済み。

---

## 15. Phase 7-D close 条件（すべて充足・2026-08-06 正式クローズ）

- [x] restore test 実施・技術検証完了
- [x] Restore Viability：CONFIRMED
- [x] 実行記録の main 反映（本ファイル・PR-1・merge commit `3b084ecb49c14bda7b169b385a529185abb6eb57`）
- [x] 正本 SQL の修正と、修正後の無改変実行による再検証合格（§14・2026-08-06）
- [x] **PR-2（restore tooling fixes）の main merge**（PR #182・merge commit `d3c1295d1b62b7b282bf3a1e60ba9a51dbaba584`）
- [x] 3 者（岡井さん・ChatGPT・Claude）による「Phase 7-D クローズ可」の合意（2026-08-06）

**Phase 7-D 正式クローズ日：2026-08-06。** クローズ対象は Phase 7-D のみであり、Phase 7 全体は未完了である。

---

## 16. 次工程

- ~~**PR-2**：restore tooling fixes~~ → **完了**（PR #182 merged・2026-08-06）
- **PR-3**：backup pipeline hardening（backup script 改善 / validation 追加 / scope 見直し／`data.sql` への `auth` / `storage` COPY 27 ブロック混入の原因分析）→ Phase 7-E の前提整備。**未着手**
- **Phase 7-E**：backup automation／rotation／off-site（未着手）
- **Phase 7-F**：Storage backup 対象拡張（`notice-attachments` / `invoice-pdfs` / 孤立ファイル）（未着手）

**Phase 7 全体は引き続き未完了**である。本記録および Phase 7-D の正式クローズ（2026-08-06）をもって Phase 7 をクローズとはしない。
