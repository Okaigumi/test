# バックアップ棚卸し（backup inventory）

作成日：2026-07-26
対象：Phase 7-A（backup inventory）
状態：**Phase 7-A：main反映済み（PR #174 MERGED・2026-08-03）。Phase 7全体は未完了。**（作成日：2026-07-26）

復旧可能性：**Phase 7-D（2026-08-05）で検証済み・CONFIRMED**（`docs/phase7d-restore-test-record.md`）。本ファイルは 2026-07-26 時点の取得実績の棚卸しであり、以下の本文は作成当時の記述を維持する。

---

## 1. このファイルの目的

- 現行方式で取得したバックアップの「世代・内容・検証値・対象範囲」を記録する
- **何がバックアップされていて、何がされていないか**を明示する
- 復旧手順（runbook）を書く前提となる在庫表を用意する

手順そのものは `docs/backup-policy.md` を正本とする。本ファイルは取得実績と対象範囲の棚卸しに限定する。

---

## 2. 今回の取得（2026-07-26）

現行方式による**最新世代バックアップ**を取得した。**完全バックアップではない**（対象外は Section 4 を参照）。

### 2-1. Database

| 項目 | 内容 |
|---|---|
| 取得日時 | 2026-07-26 22:21 JST |
| ファイル名 | `20260726-222121.sql.zip` |
| 保管先 | `backups/`（Git 管理外） |
| サイズ | 56,233 bytes |
| SHA-256 | `D15A576B153552D422E1EE4A142BE5F63D2CB16B2CD66CC6AF67BC097D263C84` |
| 実行結果 | 成功 |
| DB への書き込み | なし（read-only の dump のみ） |

zip 内容：

- `roles.sql`
- `schema.sql`
- `data.sql`
- `backup-info.txt`

### 2-2. Storage（photos）

| 項目 | 内容 |
|---|---|
| 取得日時 | 2026-07-26 22:27 JST |
| ファイル名 | `20260726-222706-storage.zip` |
| 保管先 | `backups/`（Git 管理外） |
| サイズ | 383,316 bytes |
| SHA-256 | `5E6692E3A5E094910D8A778EE0B99A25F247B5348F0DF7952AE9E6C270D1B1C9` |
| 対象 | `reports.photo_urls` から参照される `photos` バケットのファイル |
| 対象写真 | 4 件 |
| 結果 | OK=4 / SKIPPED=0 / ERROR=0 |
| 実行結果 | 成功 |
| Storage への書き込み | なし（ダウンロードのみ） |

---

## 3. 機密区分（重要）

- DB dump には現時点で `employees.pin` 列が残存している（Phase 5-D の hash 化は dual-write 段階であり、`pin` 列の DROP は未実施）。
- したがって **この DB dump は平文 PIN を含む可能性がある機密バックアップ**として扱う。
- 取扱い：
  - GitHub へ push しない
  - 共有ストレージへ平文のまま置かない（暗号化方針は Phase 7-E で決定する）
  - 不要世代は内容を確認のうえ確実に破棄する
  - 第三者・社外へ渡さない

---

## 4. 対象範囲と制限（バックアップされていないもの）

今回取得したのは「現行方式による最新世代バックアップ」であり、**完全バックアップではない**。以下は**対象外**である。

| 対象外 | 補足 |
|---|---|
| Storage バケット `notice-attachments` | 現行スクリプトの対象外 |
| Storage バケット `invoice-pdfs` | 現行スクリプトの対象外（非公開バケット・署名付きURL方式） |
| Storage 内の孤立ファイル | `reports.photo_urls` から参照されないファイルは取得されない |
| Supabase project 設定 | プロジェクト設定・API 設定・拡張機能設定など |
| Auth 設定 | 認証プロバイダ・メール設定など |
| 環境変数そのもの | 値は取得・記録しない |
| Vercel / DNS / 各サービスのアカウント設定 | デプロイ設定・ドメイン・外部サービス側の設定 |

復旧時の含意：**上記は DB / Storage の復元だけでは戻らない**。Phase 7-B（restore runbook）で手動再設定手順として扱う必要がある。

### 復旧可能性について（重要）

本ファイルは「バックアップファイルが取得できたこと」と「その内容・checksum・対象範囲」を記録したものであり、**復旧できることを検証したものではない**。

- 復元手順（runbook）は未作成（Phase 7-B）
- 非本番環境での復元テストは未実施（Phase 7-D）
- したがって現時点で **「復旧可能」と断定しない**。復旧可能性は未検証である。

**【2026-08-05 追記】** 上記は本ファイル作成時（2026-07-26）の記述である。Phase 7-B（restore runbook）は作成・main 反映済み、Phase 7-D（非本番 restore test）は 2026-08-05 に実施し、**Restore Viability：CONFIRMED**（`docs/phase7d-restore-test-record.md`）。ただし復元対象は Section 4 の対象範囲に限られ、対象外項目（`notice-attachments` / `invoice-pdfs` / 孤立ファイル / project 設定 / Auth 設定 / Vercel・DNS）が復元されないことに変更はない。

**【2026-08-05 追記・要対応】** Phase 7-D の検証で、DB dump の `data.sql` に `auth` / `storage` の COPY が **27 ブロック含まれていた**事実を確認した。これは Section 3（機密区分）および Section 4（対象範囲）の前提に影響する可能性がある。**原因分析・dump scope の見直し・機密区分の再評価は PR-3（backup pipeline hardening）で実施する。** 現時点で特定のスクリプトを原因と断定しない。それまでの間、既存 backup ZIP は Section 3 の機密取扱い（GitHub へ push しない／平文で共有ストレージへ置かない／第三者へ渡さない）を継続する。

---

## 5. 実行環境上の発見（2026-07-26）

### 5-1. Docker Desktop が必須

- 現行の Supabase CLI による Windows 上のバックアップ方式では、`db dump` の実行に **Docker Desktop が必要**である。
- Docker 未導入の状態では `LegacyDockerRunError` で失敗した。
- 対応として、自宅 PC（Windows）へ **Docker Desktop を導入し、WSL 2 backend で動作**させた。

### 5-2. 検証時の環境バージョン

| ツール | バージョン |
|---|---|
| Docker Desktop | 4.83.0 |
| Docker Engine | 29.6.2 |
| Supabase CLI | 2.109.1 |
| Node.js | v24.16.0 |

### 5-3. 一時ファイルの後始末

- 失敗時に作成された一時フォルダは**削除済み**。
- `backups/` に残っているのは、有効な 2 つの ZIP のみ（Section 2 の 2 ファイル）。

### 5-4. docs 側の不足

- `docs/backup-policy.md` の「前提・必要ツール」に **Docker Desktop の記載が不足**していた。
  → 本 Phase 7-A で追記する。

---

## 6. 保管上の注意

- `backups/` は Git 管理外（`.gitignore` により除外）
- backup ZIP を GitHub へ push しない
- `.env.backup.local` を Git 管理しない
- **docs へ記録してよいもの**：ファイル名・サイズ・SHA-256 checksum・取得日時・件数サマリー
- **docs へ記録してはいけないもの**：接続文字列・DB password・secret 値・API key・写真 URL・氏名・UUID・PIN・hash 値
- 自宅 PC だけを唯一の保管先にしない（単一障害点になる）
- オフサイト保管／暗号化／世代管理（rotation）は **Phase 7-E で決定する**（本 Phase では未決定）

---

## 7. Phase 7 の分割（現在地）

| Phase | 内容 | 状態 |
|---|---|---|
| 7-A | backup inventory（本ファイル） | **main反映済み（PR #174 MERGED・2026-08-03）** |
| 7-B | restore runbook（復旧手順書） | **main反映済み（PR #175 MERGED・2026-08-03）** |
| 7-C | smoke checklist／復旧判定表 | **完了・main反映済み（PR #178 MERGED・2026-08-04）** |
| 7-D | non-production restore test（非本番での復元テスト） | **技術検証完了（2026-08-05）。Restore Viability：CONFIRMED。正式クローズは PR-2 merge 後** |
| 7-E | backup automation／rotation／off-site | 未着手 |
| 7-F | Storage backup 対象拡張（`notice-attachments` / `invoice-pdfs` / 孤立ファイル） | 未着手 |

Phase 7-A：main反映済み（PR #174 MERGED・2026-08-03）。Phase 7-B：restore runbook 作成・main反映済み（PR #175 MERGED・2026-08-03）。Phase 7-C：完了・main反映済み（PR #178 MERGED・2026-08-04）。Phase 7-D：2026-08-05 実施・技術検証完了・復旧可能性 CONFIRMED。**Phase 7 全体は未完了**（7-E / 7-F 未着手）であり、本ファイル作成をもって Phase 7 をクローズとはしない。

---

## 8. 次にやること（未実施）

- push / PR 作成 / main merge の可否判断（明示指示待ち・いずれも未実施）
- Phase 7-B（restore runbook）の着手判断
- Phase 7-D（非本番での復元テスト）による復旧可能性の検証
