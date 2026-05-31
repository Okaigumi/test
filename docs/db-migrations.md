# DB Migrations

Supabase SQL Editor で直接実行したDB変更・RLSポリシー変更の履歴。

---

## 2026-05-28 sites INSERT RLS policy

### 背景

admin-app.html の現場新規追加時に、以下のRLSエラーが発生した。

```text
保存エラー：new row violates row-level security policy for table "sites"
```

### 原因

`sites` テーブルに SELECT / UPDATE の RLS ポリシーは存在していたが、INSERT 用ポリシーが存在しなかったため、`anon` ロールからの現場新規追加が拒否されていた。

### 確認SQL

```sql
SELECT
  schemaname,
  tablename,
  policyname,
  cmd,
  roles,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'sites'
ORDER BY policyname;
```

### 実行したSQL

```sql
CREATE POLICY "anon_can_insert_sites"
  ON public.sites
  FOR INSERT
  TO anon
  WITH CHECK (true);
```

> ⚠️ 開発段階の暫定対応。`anon` ロールへの全行 INSERT 許可は本番運用前に見直すこと。
> 参照：`docs/rls-security-plan.md` §6 短期対応案

### 再実行時のエラー（ポリシー存在確認）

```text
ERROR: 42710: policy "anon_can_insert_sites" for table "sites" already exists
```

ポリシーは既に作成済みであることを確認。SQLは再実行せず。

### 結果

`anon_can_insert_sites` ポリシーが有効な状態であることを確認し、現場新規追加が正常に動作することを確認した。

### 関連コミット

- `c43e501` Rename site delete action to disable

---

## 2026-05-28 site_budgets soft delete column

### 背景

`site_budgets` テーブルに論理削除カラムを追加し、取り消し済み予算を物理削除せず管理できるようにした。

### 実行したSQL

```sql
ALTER TABLE public.site_budgets
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.site_budgets.is_active
  IS '通常予算: true / 取り消し済み予算: false';
```

### カラム仕様

| 値 | 意味 |
|---|---|
| `is_active = true` | 通常予算（有効） |
| `is_active = false` | 取り消し済み予算（論理削除済み） |

物理 DELETE は行わず、`is_active = false` への UPDATE で取り消しを表現する。

### 結果

- 既存データは `is_active = true`
- `admin-app.html` / `genka-app.html` では `is_active = true` の予算のみ一覧・集計対象
- 取り消し済み予算は `is_active = false` としてDBに残る

---

## 2026-05-28 RLS security hardening — DELETE policy removal

### 背景

アプリコードがすべて論理削除（`is_active = false` / `status = 'rejected'`）で実装されていることを確認した上で、`public` スキーマの物理 DELETE を許可する RLS ポリシーを削除した。

### 実行したSQL

```sql
DROP POLICY IF EXISTS inv_delete ON public.invoices;
DROP POLICY IF EXISTS sa_delete ON public.site_assignments;
DROP POLICY IF EXISTS sb_delete ON public.site_budgets;
DROP POLICY IF EXISTS ce_delete ON public.cost_entries;
```

### 削除したポリシー

| テーブル | ポリシー名 |
|---|---|
| `public.invoices` | `inv_delete` |
| `public.site_assignments` | `sa_delete` |
| `public.site_budgets` | `sb_delete` |
| `public.cost_entries` | `ce_delete` |

### 確認SQL

```sql
SELECT
  tablename,
  policyname,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND cmd = 'DELETE'
ORDER BY tablename, policyname;
```

### 確認結果

```text
Success. No rows returned
```

`public` スキーマの DELETE 許可 RLS ポリシーは **0件**。

### 補足

- `cost_entries` はアプリコード上で未使用であることをリポジトリ全検索で確認済み
- アプリ側の `.delete()` 呼び出しはリポジトリ全体で0件であることを確認済み
- 物理 DELETE が必要になった場合は、Edge Function 経由で実装する方針（`docs/rls-security-plan.md` §8-1 参照）

---

## 2026-05-28 RLS security hardening / RPC login

### 背景

フロントエンドが `employees` / `genka_admins` テーブルを直接参照し、PIN照合に関係する処理をクライアント側で行っていた。PIN列がフロント側に返る構成を避けるため、PIN照合をDB側RPCに移行した。

### 実行したSQL

```sql
-- 従業員PINログイン用RPC
CREATE OR REPLACE FUNCTION public.verify_employee_pin(
  employee_id_input uuid,
  pin_input text
)
RETURNS TABLE (
  id uuid,
  name text,
  role text,
  is_active boolean,
  company_id uuid,
  can_genka boolean,
  can_admin boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    e.id,
    e.name,
    e.role,
    e.is_active,
    e.company_id,
    e.can_genka,
    e.can_admin
  FROM public.employees e
  WHERE e.id = employee_id_input
    AND e.pin = pin_input
    AND e.is_active = true
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.verify_employee_pin(uuid, text) TO anon;
GRANT EXECUTE ON FUNCTION public.verify_employee_pin(uuid, text) TO authenticated;

-- 管理者PINログイン用RPC
CREATE OR REPLACE FUNCTION public.verify_admin_pin(
  admin_id_input uuid,
  pin_input text
)
RETURNS TABLE (
  id uuid,
  name text,
  is_active boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    g.id,
    g.name,
    g.is_active
  FROM public.genka_admins g
  WHERE g.id = admin_id_input
    AND g.pin = pin_input
    AND g.is_active = true
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.verify_admin_pin(uuid, text) TO anon;
GRANT EXECUTE ON FUNCTION public.verify_admin_pin(uuid, text) TO authenticated;
```

### 変更内容

- `public.verify_employee_pin(uuid, text)` を作成
- `public.verify_admin_pin(uuid, text)` を作成
- 従業員PIN・管理者PINをDB側で照合し、`pin` 列をフロントに返さない構成にした
- `index.html` / `admin-app.html` / `genka-app.html` のログイン処理がRPCを使うようになった

### 補足

- RPCは `SECURITY DEFINER`
- `search_path` は `public`
- 戻り値に `pin` は含めない
- フロント側の `sessionStorage` に保存される `user` / `adminUser` / `genkaUser` に `pin` が含まれない
- `employees.pin` / `genka_admins.pin` の直接SELECT権限制限は完了済み（`d751ec7`）
- フロントエンドから `pin` 列を直接読む処理は廃止済み

### 次フェーズ課題（未対応）

- `employees_update_public` ポリシーの縮小
- `employees` / `genka_admins` の INSERT / UPDATE 権限整理
- PINのハッシュ化（bcrypt / pgcrypto）
- Supabase Auth / Edge Function 化
- 管理者操作のサーバー側認可

### 関連コミット

- `7c4c0f1` Use RPC for employee PIN login
- `c31954d` Use RPC for admin PIN login
- `9a88234` Use RPC for genka admin PIN login
- `d751ec7` Document PIN column select restriction

---

## 2026-05-28 RLS security hardening — restrict PIN column SELECT

### 背景

ログイン処理を `verify_employee_pin` / `verify_admin_pin` RPC に移行したため、フロントエンドが `employees.pin` / `genka_admins.pin` を直接SELECTする必要がなくなった。

そのため、`anon` / `authenticated` から `pin` 列の直接SELECT権限を外し、必要な列だけを明示的にSELECT許可する構成に変更した。

### 実行したSQL

```sql
BEGIN;

REVOKE SELECT ON public.employees FROM anon, authenticated;
REVOKE SELECT ON public.genka_admins FROM anon, authenticated;

GRANT SELECT (
  id,
  name,
  role,
  is_active,
  company_id,
  can_genka,
  can_admin
) ON public.employees TO anon, authenticated;

GRANT SELECT (
  id,
  name,
  is_active
) ON public.genka_admins TO anon, authenticated;

COMMIT;
```

### 確認結果

```text
Success. No rows returned
```

`employees.pin` / `genka_admins.pin` に対する `anon` / `authenticated` の直接SELECT権限は0件。

### 動作確認

以下の本番画面でログイン確認済み。

- `index.html`：従業員ログインOK
- `admin-app.html`：管理者ログインOK
- `genka-app.html`：管理者ログインOK

---

## 2026-05-30 RLS security hardening — admin session RPC + permission cleanup

### 目的

- `employees_update_public` ポリシー（anon による employees 全行UPDATE）を削除する
- `employees` / `genka_admins` への直接 INSERT / UPDATE 権限を剥奪する
- 管理者操作をセッショントークン付きRPC経由に限定し、sessionStorage偽装だけでは操作できない構造にする

### 追加したテーブル

#### `public.admin_sessions`

| カラム | 型 | 内容 |
|---|---|---|
| `id` | uuid | PRIMARY KEY |
| `admin_id` | uuid | `genka_admins.id` への外部キー |
| `token_hash` | text | SHA-256ハッシュ（生トークンは保存しない） |
| `expires_at` | timestamptz | 有効期限（ログインから8時間） |
| `created_at` | timestamptz | 作成日時 |

- RLS 有効化・直接アクセス用ポリシーなし（全ロールの直接操作を禁止）
- SECURITY DEFINER RPC 経由のみ操作可能

### 追加したRPC（6本）

| RPC名 | 用途 |
|---|---|
| `create_admin_session(admin_id_input, pin_input)` | PIN照合 + セッショントークン発行。`verify_admin_pin` の代替 |
| `create_employee_secure(session_token_input, ...)` | セッション検証付き 従業員新規登録 |
| `update_employee_secure(session_token_input, ...)` | セッション検証付き 従業員編集（PIN省略可） |
| `create_genka_admin_secure(session_token_input, ...)` | セッション検証付き 管理者新規登録 |
| `update_genka_admin_secure(session_token_input, ...)` | セッション検証付き 管理者編集（PIN省略可） |
| `revoke_admin_session(session_token_input)` | ログアウト時にセッションをDBから削除 |

- 全RPC: `SECURITY DEFINER`, `SET search_path = public, extensions`
- セッション検証: `encode(digest(token, 'sha256'), 'hex')` で token_hash と照合
- セッション無効時は `RAISE EXCEPTION 'Invalid or expired session'`
- `GRANT EXECUTE TO anon, authenticated`

### フロント変更（admin-app.html のみ）

| 関数 | 変更内容 |
|---|---|
| `tryLogin()` | `verify_admin_pin` → `create_admin_session` RPC に変更。`session_token` が sessionStorage に保存される |
| `saveEmployee()` | `sb.from('employees').update/insert` → `update_employee_secure` / `create_employee_secure` RPC に変更 |
| `saveAdmin()` | `sb.from('genka_admins').update/insert` → `update_genka_admin_secure` / `create_genka_admin_secure` RPC に変更 |
| `aLogout()` | `async` 化。`revoke_admin_session` RPC を呼んでから sessionStorage 削除・リロード |

### 削除・縮小した権限

```sql
-- 最危険ポリシーの削除
DROP POLICY IF EXISTS employees_update_public ON public.employees;

-- employees 直接 INSERT / UPDATE を剥奪
REVOKE INSERT ON public.employees FROM anon, authenticated;
REVOKE UPDATE ON public.employees FROM anon, authenticated;

-- genka_admins 直接 INSERT / UPDATE を剥奪
REVOKE INSERT ON public.genka_admins FROM anon, authenticated;
REVOKE UPDATE ON public.genka_admins FROM anon, authenticated;
```

### 確認結果

- `admin_sessions` RLS: true
- `admin_sessions` ポリシー: 0件（直接アクセス禁止）
- RPC 6本: 存在確認済み
- `employees_update_public`: 削除済み（0件）
- `employees` / `genka_admins` の anon/authenticated INSERT/UPDATE: 0件
- 本番 `admin-app.html` でログイン・従業員保存・管理者保存・ログアウト確認済み

### 残課題（次フェーズ）

- PINのハッシュ化（bcrypt / pgcrypto）
- Supabase Auth / Edge Function 化による本格認証
- sessionStorage token の XSS 対策
- `genka-app.html` のログイン方式を `create_admin_session` に統一（現状は `verify_admin_pin` のまま）

### 関連コミット

- `26f6e77` Use admin session RPCs for admin management
- `1cd42b8` Add ASCII admin session RPC SQL
- `dcea1bb` Add admin session SQL files
- `cb51a4a` Add admin session RPC plan

---

## 2026-05-31 invoices / site_budgets secure RPC 化 + REVOKE

### 目的

- `invoices` / `site_budgets` への直接 INSERT / UPDATE 権限を `anon` / `authenticated` から削除する
- 請求書・実行予算操作を管理者セッショントークン付き RPC 経由に限定し、sessionStorage 偽装だけでは操作できない構造にする
- 年間予算（month IS NULL）の重複行を防ぐ

### 追加・更新したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/invoice-budget-secure-rpc.sql` | invoices / site_budgets 用 secure RPC 8本 |
| `docs/sql/site-budget-upsert-null-fix.sql` | 年間予算重複防止インデックス + upsert_site_budget_secure 修正 |

### 作成・更新したRPC

| RPC名 | 用途 |
|---|---|
| `create_invoice_secure` | 請求書 INSERT（セッション検証付き。company_id はサーバー側で sites から取得） |
| `update_invoice_secure` | 請求書 UPDATE（セッション検証付き。company_id はサーバー側で取得） |
| `reject_invoice_secure` | 請求書 status = 'rejected'（論理削除） |
| `restore_invoice_secure` | 請求書 status = 'confirmed'（復元） |
| `upsert_site_budget_secure` | 実行予算 INSERT ON CONFLICT DO UPDATE（month NULL 重複対策済み） |
| `update_site_budget_secure` | 実行予算 UPDATE by id（admin 編集パス専用） |
| `deactivate_site_budget_secure` | 実行予算 is_active = false（論理削除） |
| `restore_site_budget_secure` | 実行予算 is_active = true（重複チェック内蔵） |

- 全 RPC: `LANGUAGE plpgsql`, `SECURITY DEFINER`, `SET search_path = public, extensions`
- セッション検証: `encode(digest(session_token_input, 'sha256'), 'hex')` で `admin_sessions.token_hash` と照合
- `GRANT EXECUTE TO anon, authenticated`

### フロント変更

#### admin-app.html

| 関数 | 変更内容 |
|---|---|
| `saveInvoice()` | `invoices.insert/update` → `create_invoice_secure` / `update_invoice_secure` |
| `deleteInvoice()` | `invoices.update({status:'rejected'})` → `reject_invoice_secure` |
| `restoreInvoice()` | `invoices.update({status:'confirmed'})` → `restore_invoice_secure` |
| `saveBudget()` | `site_budgets.upsert/update` → `upsert_site_budget_secure` / `update_site_budget_secure` |
| `deleteBudget()` | `site_budgets.update({is_active:false})` → `deactivate_site_budget_secure` |
| `restoreBudget()` | 3クエリ（SELECT+重複チェック+UPDATE）→ `restore_site_budget_secure` 1本に集約 |

#### genka-app.html

| 関数 | 変更内容 |
|---|---|
| `saveInvoice()` | `invoices.insert` → `create_invoice_secure` |
| `updateInvoice()` | `invoices.update` → `update_invoice_secure` |
| `deleteInvoice()` | `invoices.update({status:'rejected'})` → `reject_invoice_secure` |
| `saveBudget()` | `site_budgets.upsert` → `upsert_site_budget_secure` |
| `openBudgetModal()` | `.maybeSingle()` → `.order('updated_at',{ascending:false}).limit(1)` に変更（重複行があっても最新1件を採用し画面が落ちないようにした） |

### site_budgets 重複対策

#### 背景

PostgreSQL の UNIQUE 制約は NULL を「互いに等しくない」として扱うため、`ON CONFLICT (site_id, year, month)` は `month IS NULL` の重複を検出できなかった。同じ現場・年度の年間予算が複数 INSERT できる状態だった。

#### 実施内容

1. 既存の重複データを整理（最新1件のみ `is_active = true`、古い重複行は `is_active = false`）
2. 部分ユニークインデックスを追加:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS site_budgets_annual_active_unique
  ON public.site_budgets (site_id, year)
  WHERE month IS NULL AND is_active = true;
```

3. `upsert_site_budget_secure` の conflict target を変更:

```sql
ON CONFLICT (site_id, year) WHERE month IS NULL AND is_active = true
DO UPDATE SET ...
```

### 削除した権限

```sql
REVOKE INSERT ON public.invoices    FROM anon, authenticated;
REVOKE UPDATE ON public.invoices    FROM anon, authenticated;
REVOKE INSERT ON public.site_budgets FROM anon, authenticated;
REVOKE UPDATE ON public.site_budgets FROM anon, authenticated;
```

### 確認結果

- secure RPC 8本: 存在確認済み
- anon / authenticated に RPC EXECUTE 権限: 16件（8本 × 2ロール）
- `invoices` の anon/authenticated INSERT/UPDATE: 0件
- `site_budgets` の anon/authenticated INSERT/UPDATE: 0件
- `site_budgets` の有効重複（同 site_id + year + month IS NULL + is_active=true）: 0件
- 本番 `admin-app.html` で請求書・実行予算の全操作確認済み
- 本番 `genka-app.html` で請求書・実行予算の全操作確認済み
- Console 赤エラーなし

### 残課題（次フェーズ）

- PIN のハッシュ化（bcrypt / pgcrypto）
- ログイン失敗回数制限
- Supabase Auth / Edge Function 化による本格認証
- sessionStorage token の XSS 対策
- `reports` / `paid_leave_requests` の RPC 化検討

### 関連コミット

- `bee2a12` Add invoice and budget secure RPC SQL
- `d6712be` Use secure RPCs for admin invoices and budgets
- `ede5b67` Use secure RPCs for genka invoices and budgets
- `2ec7182` Handle duplicate annual budgets in genka app
- `c1575bb` Fix annual site budget upsert conflicts

---

## 2026-05-31 reports secure RPC 化 + REVOKE

### 目的

- `reports` への直接 INSERT / UPDATE 権限を `anon` / `authenticated` から削除する
- 日報登録・修正・写真URL更新を従業員セッショントークン付き RPC 経由に限定する
- `employee_id` をフロント（sessionStorage）から信用せず、DB側で `session_token` から確定する構造にする

### 追加したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/employee-report-secure-rpc.sql` | employee_sessions テーブル + 従業員セッション・日報操作 RPC 5本 |

### 追加したテーブル

#### `public.employee_sessions`

| カラム | 型 | 内容 |
|---|---|---|
| `id` | uuid | PRIMARY KEY |
| `employee_id` | uuid | `employees.id` への外部キー（ON DELETE CASCADE） |
| `token_hash` | text | SHA-256 ハッシュ（生トークンは保存しない） |
| `expires_at` | timestamptz | 有効期限（ログインから8時間） |
| `created_at` | timestamptz | 作成日時 |

- RLS 有効化・直接アクセス用ポリシーなし（全ロールの直接操作を禁止）
- SECURITY DEFINER RPC 経由のみ操作可能
- インデックス: `token_hash`, `expires_at`, `employee_id`

### 作成したRPC

| RPC名 | 用途 |
|---|---|
| `create_employee_session(employee_id_input, pin_input)` | PIN照合 + セッショントークン発行。`verify_employee_pin` の代替 |
| `revoke_employee_session(session_token_input)` | ログアウト時にセッションをDBから削除 |
| `create_report_secure(session_token_input, ...)` | セッション検証 + `employee_id` サーバー確定 + 日報 INSERT |
| `update_report_secure(session_token_input, id_input, ...)` | セッション検証 + 本人確認（`employee_id` 一致）+ 日報 UPDATE |
| `update_report_photo_secure(session_token_input, id_input, ...)` | セッション検証 + 本人確認 + `photo_urls` / `photo_count` UPDATE |

- 全 RPC: `LANGUAGE plpgsql`, `SECURITY DEFINER`, `SET search_path = public, extensions`
- セッション検証: `encode(digest(session_token_input, 'sha256'), 'hex')` で `employee_sessions.token_hash` と照合
- `employee_id` は引数から受け取らず、セッションから `v_employee_id` として確定
- update 系は `WHERE id = id_input AND employee_id = v_employee_id` で本人のみ更新可能
- `GRANT EXECUTE TO anon, authenticated`

### フロント変更（index.html）

| 関数 | 変更内容 |
|---|---|
| `tryLogin()` | `verify_employee_pin` → `create_employee_session`。戻り値に `session_token` が追加される |
| `logout()` | `function` → `async function`。`revoke_employee_session` を呼んでから sessionStorage 削除 |
| `submitReport()` 新規 | `reports.insert(payload)` → `create_report_secure(rpcArgs)`。`employee_id` を引数から削除 |
| `submitReport()` 修正 | `reports.update(payload)` → `update_report_secure({...rpcArgs, id_input: editingReportId})` |
| 写真URL更新 | `reports.update({photo_urls, photo_count})` → `update_report_photo_secure({session_token_input, id_input, ...})` |

- `sessionStorage.currentUser` に `session_token` が含まれるようになった
- `payload` から `employee_id`, `status`, `photo_urls`, `photo_count` を除去

### 削除した権限

```sql
REVOKE INSERT ON public.reports FROM anon, authenticated;
REVOKE UPDATE ON public.reports FROM anon, authenticated;
```

### 確認結果

- `employee_sessions` RLS: true
- `employee_sessions` ポリシー: 0件（直接アクセス禁止）
- RPC 5本: 存在確認済み
- anon / authenticated に RPC EXECUTE 権限: 10件（5本 × 2ロール）
- `reports` の anon/authenticated INSERT/UPDATE: 0件
- 本番 `index.html` で従業員ログイン・日報新規登録・日報修正・写真付き日報・ログアウト確認済み
- Console 赤エラーなし

### 残課題（次フェーズ）

- `paid_leave_requests` の RPC 化
- PIN のハッシュ化（bcrypt / pgcrypto）
- ログイン失敗回数制限
- Supabase Auth / Edge Function 化による本格認証
- sessionStorage token の XSS 対策

### 関連コミット

- `3f3163c` Add employee report secure RPC SQL
- `dad8f4c` Use secure RPCs for employee reports
