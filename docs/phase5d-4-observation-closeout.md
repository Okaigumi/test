# Phase 5-D-4 observation closeout

## クローズ判定

Phase 5-D-4 observation：2026-08-03 にクローズ。
運用観察5項目すべて0件、最終 read-only DB 確認は全項目 baseline 一致。
4営業日への短縮による残存リスクは受容済み。

## 観察期間

| 項目 | 値 |
|---|---|
| 当初予定 | 2026-07-27〜2026-07-31（5営業日） |
| 実施期間 | 2026-07-27〜2026-07-30（4営業日） |
| 短縮判断 | 岡井さんの判断により1営業日短縮 |
| 最終 read-only DB 確認 | 2026-08-03 |

### 残存リスク（1営業日短縮）

当初予定より1営業日短縮したことにより、以下の残存リスクがある。

- observation 期間が1営業日少ない分、稀頻度の認証異常が観察されなかった可能性を排除できない
- 受容根拠：observation 期間中の運用異常5項目すべて0件、かつ最終 DB 確認が baseline と完全一致したことにより、実害リスクは十分に低いと3者が判断した

## 運用観察結果（2026-07-27〜2026-07-30）

岡井さん確認：

| 確認項目 | 結果 |
|---|---|
| 正しい PIN でログインできない事象 | 0件 |
| cooldown / lockout 重大異常 | 0件 |
| 管理画面（/admin）ログイン回帰 | 0件 |
| 原価管理（/genka）ログイン回帰 | 0件 |
| 認証画面 / Network 新規重大エラー | 0件 |

## 最終 read-only DB 確認結果（2026-08-03）

実行：岡井さん（Supabase SQL Editor・read-only）
SQL：`docs/sql/phase5d-3-employee-pin-hash-backfill.sql` Part 3（POST-COMMIT・read-only）を流用

PIN 値・PIN hash 値・氏名・UUID は記録しない。

### employees

| 項目 | 値 |
|---|---|
| total | 11 |
| pin_hash NULL | 0 |
| pin_hash NOT NULL | 11 |
| `employees.pin` NOT NULL | 11 |
| hash integrity | 11 / 11 |
| bcrypt cost 12 | 11 / 11 |

### column privileges

`employees.pin` および `employees.pin_hash` 列に対する anon / authenticated 権限（全16項目）：

| role | column | privilege | 値 |
|---|---|---|---|
| anon | pin | SELECT / INSERT / UPDATE / REFERENCES | すべて false |
| anon | pin_hash | SELECT / INSERT / UPDATE / REFERENCES | すべて false |
| authenticated | pin | SELECT / INSERT / UPDATE / REFERENCES | すべて false |
| authenticated | pin_hash | SELECT / INSERT / UPDATE / REFERENCES | すべて false |

### RPC fingerprint

| 関数 | owner | SECURITY DEFINER | volatility | search_path | len | md5 | baseline_match |
|---|---|---|---|---|---|---|---|
| `create_employee_secure(text,text,text,text,uuid,boolean)` | postgres | true | v | public, extensions | 1433 | `33ea12279533b4a808a4d14bf11bb0a9` | true |
| `update_employee_secure(text,uuid,text,text,boolean,uuid,text)` | postgres | true | v | public, extensions | 1915 | `848eec0d7310c84cdffd05939b6c7a3b` | true |
| `create_employee_session(uuid,text)` | postgres | true | v | public, extensions | 3798 | `006550c3455e34aa9d1d61bd60bb85ad` | true |

### EXECUTE privileges

上記3 RPC に対する anon / authenticated の EXECUTE 権限（全6項目）：すべて true。

## 認証関連変更の有無

| 確認項目 | 結果 |
|---|---|
| observation 期間中の認証関連変更 | なし |
| 2026-07-27 以降の main commit | なし |
| PR #174（docs/phase7a-backup-inventory） | backup 関連 docs のみ（db-migrations.md 変更なし） |
| PR #175（docs/phase7b-restore-runbook） | restore runbook docs のみ（db-migrations.md 変更なし） |
| DB 変更 | なし |
| Production 変更 | なし |
| application 変更 | なし |

## Phase 5-D 現在地

**Phase 5-D 全体は未完了。**

| Phase | 状態 |
|---|---|
| 5-D-1 schema 追加 + login RPC hash 優先 dual-read 化 | 完了（2026-07-23） |
| 5-D-2 create / update RPC dual-write 化 | 完了（2026-07-23） |
| 5-D-3 employees PIN hash backfill | 完了（2026-07-24） |
| 5-D-4 observation | **クローズ（2026-08-03）** |
| 5-D-5 login RPC hash-only 化 | 未開始 |
| 5-D-6 `employees.pin` DROP | 未開始 |

現時点の DB 状態：

- `employees.pin`：11件残存（削除していない）
- login：hash-first dual-read のまま（hash-only 化は 5-D-5 で実施予定）
- create / update：dual-write のまま
- hash-only 化・pin 列 DROP は今回行っていない

## 3者合意

| 担当 | 確認内容 |
|---|---|
| 岡井さん | 運用異常5項目すべて0件（2026-07-27〜2026-07-30）を確認 |
| ChatGPT | 運用結果および最終 DB 確認結果からクローズ条件合格と判定（2026-08-03） |
| Claude | repo 履歴・PR 差分・認証変更なし・fingerprint 証拠整合性を確認し、クローズ可能と判断（2026-08-03） |

Claude による証拠確認の内容：

- main HEAD が `7ab6630bf21ab6775ad88552c4ac7ed358369fa0`（Phase 5-D-3 closeout）であり、2026-07-27 以降の main commit がゼロであることを git log で確認
- PR #174・#175 の変更ファイルが backup / restore 関連 docs のみであり、認証・DB 関連変更を含まないことを git diff で確認
- fingerprint 期待値がSQL ファイル（`docs/sql/phase5d-3-employee-pin-hash-backfill.sql`）の記録値と完全一致することを確認
- Phase 5-D-4 closeout 記録がこれまで存在しなかったことを repo 全体 Grep で確認
