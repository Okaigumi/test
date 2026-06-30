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

---

## 2026-05-31 paid_leave_requests / paid_leave_grants secure RPC 化 + REVOKE

### 目的

- 有給申請・承認/却下・有給付与を従業員セッショントークン付き RPC 経由に限定する
- `employee_id` / `reviewed_by` をフロントから信用せず、DB 側で `session_token` から確定する
- 管理者処理（承認/却下・有給付与）は RPC 内で `employees.role = 'admin'` をサーバー側で確認する
- `paid_leave_requests` / `paid_leave_grants` の直接 INSERT / UPDATE 権限を削除する

### 追加したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/paid-leave-secure-rpc.sql` | 有給申請・承認・付与 secure RPC 3本 |

### 作成したRPC

| RPC名 | 用途 |
|---|---|
| `create_paid_leave_request_secure(session_token_input, ...)` | 有給申請 INSERT。`employee_id` はセッションから確定。`status = 'pending'` 固定 |
| `review_paid_leave_request_secure(session_token_input, id_input, status_input)` | 有給申請の承認/却下。`role = 'admin'` をサーバー確認。`reviewed_by` はセッションから確定 |
| `save_paid_leave_grant_secure(session_token_input, employee_id_input, year_input, days_input)` | 有給付与 UPSERT。`role = 'admin'` をサーバー確認。対象従業員の存在確認あり |

- セッション検証: `employee_sessions` テーブルと `employees` を JOIN して `employee_id` / `role` を確定
- 全 RPC: `LANGUAGE plpgsql`, `SECURITY DEFINER`, `SET search_path = public, extensions`
- `GRANT EXECUTE TO anon, authenticated`

### フロント変更（index.html）

| 関数 | 変更内容 |
|---|---|
| `submitLeaveRequest()` | `paid_leave_requests.insert({employee_id,...})` → `create_paid_leave_request_secure`。`employee_id`・`status` を削除 |
| `reviewLeave(reqId, status)` | `paid_leave_requests.update({status, reviewed_by, reviewed_at})` → `review_paid_leave_request_secure`。`reviewed_by`・`reviewed_at` を削除 |
| `saveGrant()` | `paid_leave_grants.upsert({...})` → `save_paid_leave_grant_secure` |

- 3処理すべてで `state.currentUser?.session_token` を `session_token_input` として使用
- `session_token` がなければ alert して処理中断

### 削除した権限

```sql
REVOKE INSERT ON public.paid_leave_requests FROM anon, authenticated;
REVOKE UPDATE ON public.paid_leave_requests FROM anon, authenticated;
REVOKE INSERT ON public.paid_leave_grants   FROM anon, authenticated;
REVOKE UPDATE ON public.paid_leave_grants   FROM anon, authenticated;
```

### 確認結果

- RPC 3本: 存在確認済み
- anon / authenticated に RPC EXECUTE 権限: 6件（3本 × 2ロール）
- `paid_leave_requests` の anon/authenticated INSERT/UPDATE: 0件
- `paid_leave_grants` の anon/authenticated INSERT/UPDATE: 0件
- 本番 `index.html` で有給申請・承認/却下・有給付与確認済み
- Console 赤エラーなし

### 残課題（次フェーズ）

- 全テーブル権限棚卸し
- RLS ポリシー整理
- PIN のハッシュ化（bcrypt / pgcrypto）
- ログイン失敗回数制限
- sessionStorage token の管理強化

### 関連コミット

- `d786ee8` Add paid leave secure RPC SQL
- `7176ba5` Use secure RPCs for paid leave

---

## 2026-05-31 public スキーマ DELETE 権限の全削除

### 目的

- `public` スキーマ内の全テーブルについて、`anon` / `authenticated` からの直接 DELETE を禁止する
- 物理削除を封じ、`is_active = false` / `status = 'rejected'` などの論理削除運用に統一する
- フロント改ざんや誤操作によるレコード削除を防止する

### 事前確認

- `index.html` / `admin-app.html` / `genka-app.html` の全コードで `.delete()` 使用が **0件** であることを確認
- 既存の削除系処理はすべて論理削除（`is_active = false` / `status = 'rejected'`）で実装済み
- 直接 INSERT / UPDATE が残るテーブルは存在するが、今回は DELETE のみ対象

### 実行したSQL

```sql
REVOKE DELETE ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
```

### 確認結果

- anon / authenticated の DELETE 権限: **0件**
- `index.html`: ログイン・日報・有給画面・現場/外注/重機の論理削除系処理 OK
- `admin-app.html`: ログイン・全機能 OK
- `genka-app.html`: ログイン・全機能 OK
- Console 赤エラーなし

### 今回触っていない権限

- INSERT（一部テーブルで残存）
- UPDATE（一部テーブルで残存）
- SELECT（変更なし）

### 残課題（次フェーズ）

- `sites` / `site_assignments` / `materials` / `machines` / `machine_locations` の RPC 化
- `employee_rates` / `unit_rates` の RPC 化
- 全 RLS ポリシー整理
- PIN のハッシュ化（bcrypt / pgcrypto）
- ログイン失敗回数制限
- sessionStorage token の管理強化

---

## 2026-05-31 machine_locations secure RPC 化 + REVOKE

### 目的

- 重機移動履歴の登録をセッショントークン付き RPC 経由に限定する
- `moved_by` をフロントから信用せず、DB 側で `session_token` から `employee_id` を確定する
- `machine_locations` の直接 INSERT / UPDATE 権限を削除する

### 追加したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/machine-location-secure-rpc.sql` | 重機移動記録 secure RPC 1本 |

### 作成したRPC

| RPC名 | 用途 |
|---|---|
| `create_machine_location_secure(session_token_input, machine_id_input, site_id_input, memo_input)` | 重機移動記録 INSERT。`moved_by` はセッションから確定。`machine_id` / `site_id` の存在確認あり |

- 全従業員（role 制限なし）が記録可能
- `moved_by` はフロントから受け取らずサーバー確定
- `moved_at` は DB デフォルト `now()`
- `SECURITY DEFINER`, `SET search_path = public, extensions`
- `GRANT EXECUTE TO anon, authenticated`

### フロント変更（index.html）

| 関数 | 変更内容 |
|---|---|
| `confirmMachineMove()` | `machine_locations.insert({..., moved_by: state.currentUser.id})` → `create_machine_location_secure`。`moved_by`・`moved_at` を削除。エラーハンドリング追加 |

### 削除した権限

```sql
REVOKE INSERT ON public.machine_locations FROM anon, authenticated;
REVOKE UPDATE ON public.machine_locations FROM anon, authenticated;
```

### 確認結果

- `create_machine_location_secure`: 存在確認済み
- anon / authenticated に RPC EXECUTE 権限あり
- `machine_locations` の anon/authenticated INSERT/UPDATE/DELETE: 0件
- 本番 `index.html` で重機移動記録・現在位置更新確認済み
- Console 赤エラーなし

### 残課題（次フェーズ）

- `sites` / `site_assignments` の RPC 化
- `materials` / `machines` の RPC 化
- `employee_rates` / `unit_rates` の RPC 化
- 全 RLS ポリシー整理
- PIN のハッシュ化（bcrypt / pgcrypto）
- ログイン失敗回数制限
- sessionStorage token の管理強化

### 関連コミット

- `acf57e6` Add machine location secure RPC SQL
- `bdf101c` Use secure RPC for machine locations

---

## 2026-06-01 paid_leave RPC admin_sessions 対応 + admin-app.html 有給管理追加

### 目的

- admin-app.html から有給申請の承認/却下・有給付与を操作できるようにする
- admin-app.html は `admin_sessions`（genka_admins ユーザー）でセッション管理するが、既存の有給 RPC は `employee_sessions` 固定だった
- `CREATE OR REPLACE` で 2 本の RPC を修正し、`admin_sessions` 経由のセッションも受け付けるよう拡張した
- 直接書き込み権限は一切復活させていない

### 修正したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/paid-leave-admin-session-compatible-rpc.sql` | 有給 RPC 2 本の `admin_sessions` 対応修正（Supabase SQL Editor で実行済み） |

### 修正したRPC

| RPC名 | 変更内容 |
|---|---|
| `review_paid_leave_request_secure` | `employee_sessions` で管理者が確認できない場合、`admin_sessions + genka_admins` でも検証するよう拡張。`reviewed_by`: `employee_sessions` 経由は `employees.id`、`admin_sessions` 経由は `NULL` |
| `save_paid_leave_grant_secure` | 同上の検証拡張。`v_employee_id` を書き込みに使わないため `NULL` 問題なし |

- 引数名・戻り値は既存仕様から変更なし
- `SECURITY DEFINER`, `SET search_path = public, extensions` は維持
- `GRANT EXECUTE TO anon, authenticated` は維持
- `paid_leave_requests` / `paid_leave_grants` の直接 INSERT/UPDATE 権限は復活させていない

### フロント変更（admin-app.html のみ）

| 変更内容 | 詳細 |
|---|---|
| サイドバーに「有給管理」追加 | 人員セクションに 🌴 有給管理（`nav-leave`）を追加 |
| `showPage()` に `leave` を追加 | `titles` / `pages` マップに `leave` エントリ追加 |
| `pageLeave()` 追加 | 従業員別有給状況テーブル + 未処理申請テーブルを表示 |
| `reviewLeaveRequest(reqId, status)` 追加 | 承認/却下 → `review_paid_leave_request_secure` |
| `openLeaveGrantModal(empId)` 追加 | 付与モーダル。名前は `_employees` から取得（onclick 属性への埋め込みを避けた安全設計） |
| `saveLeaveGrant()` 追加 | 付与保存 → `save_paid_leave_grant_secure` |

- `index.html` 側の既存有給機能は変更・削除していない
- `genka-app.html` は変更していない
- Storage / photos 関連は変更していない

### 確認結果

- `review_paid_leave_request_secure` / `save_paid_leave_grant_secure`: 存在確認済み
- `paid_leave_requests` / `paid_leave_grants` の anon/authenticated 直接 INSERT/UPDATE: 0件（変化なし）
- 本番 `admin-app.html` で有給管理画面表示・付与・承認/却下・ログアウト確認済み
- `index.html` 側への状態反映確認済み
- Console 赤エラーなし

### 関連コミット

- `b74897f` Add paid leave management to admin app

---

## 2026-06-02 notices 管理RPC追加 + 権限整理

### 目的

- admin-app.html からお知らせの新規作成・編集・公開/非公開切替ができるよう notices 管理 RPC を追加する
- notices への直接 INSERT / UPDATE を `anon` / `authenticated` から削除し、RPC 経由のみに限定する
- anon / authenticated の SELECT は `index.html` のお知らせ表示用に残す

### 追加したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/notices-admin-rpc.sql` | notices 管理 RPC 3本 |

### 作成したRPC

| RPC名 | 用途 |
|---|---|
| `list_notices_admin_secure(session_token_input)` | お知らせ一覧取得（非公開含む全件）。管理者セッション検証付き |
| `create_notice_secure(session_token_input, ...)` | お知らせ INSERT。管理者セッション検証付き |
| `update_notice_secure(session_token_input, id_input, ...)` | お知らせ UPDATE。管理者セッション検証付き |

- 全 RPC: `LANGUAGE plpgsql`, `SECURITY DEFINER`, `SET search_path = public, extensions`
- セッション検証: `admin_sessions` テーブルで `token_hash` 照合
- `GRANT EXECUTE TO anon, authenticated`

### 削除した権限

```sql
REVOKE INSERT     ON public.notices FROM anon, authenticated;
REVOKE UPDATE     ON public.notices FROM anon, authenticated;
REVOKE DELETE     ON public.notices FROM anon, authenticated;
REVOKE TRUNCATE   ON public.notices FROM anon, authenticated;
REVOKE REFERENCES ON public.notices FROM anon, authenticated;
REVOKE TRIGGER    ON public.notices FROM anon, authenticated;
```

### 残した権限

- `anon` / `authenticated` の `notices` SELECT は **残存**
  - `index.html` の従業員向けお知らせ表示（`is_active = true` 絞り込み）で使用

### バグ修正

#### update_notice_secure の id ambiguous エラー修正（コミット `1909c0b`）

`UPDATE public.notices SET ... WHERE id = id_input` の記述で PostgreSQL が `id` をカラムと引数の両方に解釈し `ERROR: column reference "id" is ambiguous` が発生した。`public.notices` に別名 `n` を付け、`n.id = id_input` と明示して解消。

### 確認結果

- RPC 3本: 存在確認済み
- anon / authenticated に RPC EXECUTE 権限あり
- `notices` の anon/authenticated INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER: 0件
- `notices` SELECT は anon/authenticated に残存（index.html 表示用）
- 本番 `https://system.okaigumi.co.jp/admin` で以下を確認済み：
  - お知らせ管理メニュー表示
  - お知らせ一覧表示
  - 公開/非表示切替
  - 本文編集
  - 従業員画面（index.html）への表示/非表示反映

### 関連コミット

- `acf24c6` Add admin notice management
- `1909c0b` Fix notice update RPC id reference

---

## 2026-06-03 notices 添付機能追加（カラム追加・RPC拡張・Storage）

### 目的

- admin-app.html のお知らせ管理から画像またはPDFを1件添付できるようにする
- 従業員画面 index.html でお知らせに画像プレビューまたはPDFリンクを表示する
- notices テーブルに attachment 系カラムを追加し、Storage バケット `notice-attachments` を整備する

### 追加したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/notice-attachments-rpc.sql` | notices カラム追加・CHECK 制約・RPC 5本再作成/追加・Storage policy |

### notices テーブル追加カラム

```sql
ALTER TABLE public.notices
  ADD COLUMN IF NOT EXISTS attachment_url  TEXT,
  ADD COLUMN IF NOT EXISTS attachment_path TEXT,
  ADD COLUMN IF NOT EXISTS attachment_type TEXT,
  ADD COLUMN IF NOT EXISTS attachment_name TEXT,
  ADD COLUMN IF NOT EXISTS updated_at      TIMESTAMPTZ;
```

### CHECK 制約

```sql
ALTER TABLE public.notices
  ADD CONSTRAINT notices_attachment_type_check
  CHECK (attachment_type IS NULL OR attachment_type IN ('image', 'pdf'));
```

| 値 | 意味 |
|---|---|
| NULL | 添付なし |
| 'image' | 画像（JPEG / PNG / WebP） |
| 'pdf' | PDF |

### 既存RPC 3本の戻り値拡張（DROP + CREATE）

PostgreSQL では RETURNS TABLE の列構成変更に CREATE OR REPLACE が使えないため、DROP FUNCTION IF EXISTS + CREATE FUNCTION で再作成。GRANT EXECUTE も再付与。

| RPC名 | 変更内容 |
|---|---|
| `list_notices_admin_secure` | 戻り値に attachment_url / path / type / name / updated_at を追加 |
| `create_notice_secure` | 同上。INSERT 時に `updated_at = now()` を付与 |
| `update_notice_secure` | 同上。UPDATE の SET に `updated_at = now()` を追加 |

### 追加RPC 2本

| RPC名 | 用途 |
|---|---|
| `update_notice_attachment_secure(session_token_input, id_input, ...)` | 添付保存・差し替え。`attachment_type` の値チェックあり。Storage アップロードはフロント側で先行実施 |
| `delete_notice_attachment_secure(session_token_input, id_input)` | `attachment_*` カラムを NULL 化のみ。Storage 上のファイルは削除しない |

- 全 RPC: `LANGUAGE plpgsql`, `SECURITY DEFINER`, `SET search_path = public, extensions`
- セッション検証: `admin_sessions` テーブルで `token_hash` 照合
- `GRANT EXECUTE TO anon, authenticated`（全 5 本）

### Storage バケット設定（Supabase ダッシュボードで実施）

| 項目 | 設定値 |
|---|---|
| バケット名 | `notice-attachments` |
| 公開設定 | public bucket |
| ファイルサイズ上限 | 10 MB |
| 許可 MIME type | image/jpeg / image/png / image/webp / application/pdf |

### Storage RLS policy

| ポリシー | 内容 |
|---|---|
| `notice_attachments_insert` | anon に `notices/` prefix 配下への INSERT を許可 |
| DELETE policy | 意図的に作成しない（public URL から path が判明した場合の第三者削除を防ぐため） |
| SELECT policy | public bucket のため不要（作成しない） |

### 添付削除の方針

- `delete_notice_attachment_secure` は DB の `attachment_*` カラムを NULL 化するのみ
- Storage 上のファイルは削除しない（孤立ファイルは当面許容）
- 必要に応じて手動または管理スクリプトで整理する予定

### フロント変更

#### admin-app.html

| 変更内容 | 詳細 |
|---|---|
| フォームに添付UI追加 | `input[type=file]`（accept: JPEG/PNG/WebP/PDF）、現在の添付プレビュー表示、削除ボタン |
| 一覧テーブルに添付列追加 | 画像 / PDF のリンク表示、添付なしは `-` |
| `saveNotice()` 拡張 | ファイル検証（MIME・サイズ）→ Storage upload → `getPublicUrl` → `update_notice_attachment_secure` |
| `deleteNoticeAttachment(id)` 追加 | `delete_notice_attachment_secure` RPC のみ呼び出し。Storage remove は使用しない |

#### index.html

| 変更内容 | 詳細 |
|---|---|
| `escapeAttr()` 追加 | URL を href 属性に安全に埋め込むためのヘルパー（`escapeHtml` と同実装） |
| `loadNotice()` 拡張 | `attachment_type` で画像 / PDF / 添付なしを分岐表示。画像は `width:100%; max-height:240px`、PDF はボタン風リンク |

### 確認結果

- notices テーブルに attachment 系カラム 5 本追加済み
- `notices_attachment_type_check` 制約: 存在確認済み
- RPC 5 本存在確認済み（list / create / update / update_attachment / delete_attachment）
- anon / authenticated に RPC EXECUTE 権限: 10 件確認済み
- `notices` の anon/authenticated SELECT: 残存（index.html 表示用）
- `notice-attachments` バケット: public、INSERT-only policy
- 本番 `https://system.okaigumi.co.jp/admin` で以下を確認済み：
  - 画像添付・PDF添付・既存お知らせへの添付追加・添付削除・公開/非公開切替
- 本番 `https://system.okaigumi.co.jp/` で以下を確認済み：
  - 従業員画面での画像表示・PDF リンク表示
- Console 重大エラーなし

### 関連コミット

- `8a0e811` Add notice attachment support

---

## 2026-06-03 public.cost_entries テーブル削除

### 目的

未使用のまま残存していた `public.cost_entries` テーブルを物理削除する。

### 削除理由

以下のすべてを確認した上で削除を実施した。

| 確認項目 | 結果 |
|---|---|
| データ行数 | 0 行 |
| HTML コード参照（index.html / admin-app.html / genka-app.html） | 0 件 |
| docs/sql/ 参照 | 0 件（`ce_delete` ポリシー削除履歴は 2026-05-28 の記録に存在するが、テーブル自体の SELECT/INSERT/UPDATE 参照はなし） |
| scripts/ 参照 | 0 件 |
| 外部キーによる参照（他テーブルから cost_entries を参照する FK） | なし |
| VIEW からの参照 | なし |
| FUNCTION / RPC からの参照 | なし |
| TRIGGER | なし |
| 旧設計由来と思われる未使用テーブル | 該当 |

### 削除前バックアップ

| ファイル | 内容 |
|---|---|
| `backups/20260603-163056.sql.zip` | DB フルバックアップ（roles / schema / data） |
| `backups/20260603-163212-storage.zip` | Storage photos バックアップ |

### 削除前の cost_entries 定義（バックアップより）

```sql
CREATE TABLE IF NOT EXISTS "public"."cost_entries" (
    "id"          uuid        DEFAULT gen_random_uuid() NOT NULL,
    "site_id"     uuid,
    "report_date" date        NOT NULL,
    "category"    text        NOT NULL,
    "description" text,
    "amount"      integer     DEFAULT 0 NOT NULL,
    "created_at"  timestamptz DEFAULT now() NOT NULL
);
```

- `site_id` → `public.sites(id)` への外部キー（自テーブルからのみ。被参照なし）
- RLS 有効。ポリシー 3 件存在（`ce_read` / `ce_update` / `ce_write`）

### 実行したSQL

```sql
DROP TABLE IF EXISTS public.cost_entries RESTRICT;
```

- `CASCADE` は使用しない
- `RESTRICT` により、万一参照が残っていた場合はエラーで停止する設計

### RLS ポリシーの扱い

テーブル削除に伴い、以下のポリシーも自動削除された。

| ポリシー名 | 種別 |
|---|---|
| `ce_read` | SELECT |
| `ce_update` | UPDATE |
| `ce_write` | INSERT |

### GRANT の扱い

以下の権限もテーブル削除に伴い自動削除された。

```sql
-- 削除前に存在していた権限（参考）
GRANT SELECT, INSERT, UPDATE ON public.cost_entries TO anon;
GRANT SELECT, INSERT, UPDATE ON public.cost_entries TO authenticated;
GRANT ALL ON public.cost_entries TO service_role;
```

### 削除後確認

```sql
-- テーブルが存在しないこと
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'cost_entries';
-- → 0 行

-- OID が NULL であること
SELECT to_regclass('public.cost_entries');
-- → null

-- ポリシーが存在しないこと
SELECT policyname
FROM pg_policies
WHERE tablename = 'cost_entries';
-- → 0 行
```

### ローカルファイル変更

- `docs/db-migrations.md` のみ（本エントリ追記）
- HTML / scripts / backups / `.env.backup.local` は変更なし

---

## 2026-06-08 集計出力機能 Phase 1-1 — 工事分類・発注者区分マスタ追加

### 目的

- 工事（現場）に「工事分類」を紐付けるための `site_categories` マスタを追加する
- 発注者（会社）に「発注者区分」を紐付けるための `company_categories` マスタを追加する
- CSV 集計出力機能における工事一覧（projects_summary.csv）の工事分類・発注者区分列に対応する
- `sites` に `category_id`（工事分類）と `contract_amount`（請負金額）を追加する
- `companies` に `category_id`（発注者区分）を追加する

### 追加したテーブル

#### `public.site_categories`（工事分類マスタ）

| カラム | 型 | 内容 |
|---|---|---|
| `id` | uuid | PRIMARY KEY |
| `name` | text | 工事分類名（UNIQUE） |
| `is_active` | boolean | 論理削除フラグ（DEFAULT true） |
| `sort_order` | integer | 表示順（DEFAULT 0） |
| `created_at` | timestamptz | 作成日時 |

#### `public.company_categories`（発注者区分マスタ）

| カラム | 型 | 内容 |
|---|---|---|
| `id` | uuid | PRIMARY KEY |
| `name` | text | 発注者区分名（UNIQUE） |
| `is_active` | boolean | 論理削除フラグ（DEFAULT true） |
| `sort_order` | integer | 表示順（DEFAULT 0） |
| `created_at` | timestamptz | 作成日時 |

### 追加したカラム

| テーブル | カラム | 型 | 内容 |
|---|---|---|---|
| `public.sites` | `category_id` | uuid FK → site_categories(id)（NULL可）| 工事分類 |
| `public.sites` | `contract_amount` | integer（NULL可）| 請負金額（円、税込/税抜の扱いは集計仕様で統一）|
| `public.companies` | `category_id` | uuid FK → company_categories(id)（NULL可）| 発注者区分 |

### 追加したインデックス

| インデックス名 | 対象 | 用途 |
|---|---|---|
| `idx_sites_category_id` | `public.sites (category_id)` | 集計時の工事分類 JOIN 高速化 |
| `idx_companies_category_id` | `public.companies (category_id)` | 集計時の発注者区分 JOIN 高速化 |

### 初期データ

**site_categories**

| name | sort_order |
|---|---|
| 民間造成 | 1 |
| 公共道路 | 2 |
| 河川 | 3 |
| 治山 | 4 |
| 上下水道 | 5 |
| 災害対応 | 6 |
| その他 | 99 |

**company_categories**

| name | sort_order |
|---|---|
| 民間 | 1 |
| 兵庫県 | 2 |
| 西脇市 | 3 |
| 国交省 | 4 |
| 農政局 | 5 |
| その他 | 99 |

### RLS・権限

| テーブル | SELECT | INSERT / UPDATE / DELETE |
|---|---|---|
| `site_categories` | anon / authenticated 許可 | anon / authenticated 禁止（ダッシュボード直接操作）|
| `company_categories` | anon / authenticated 許可 | anon / authenticated 禁止（ダッシュボード直接操作）|

- 両テーブルとも RLS 有効・SELECT ポリシー（`USING (true)`）を設定
- ポリシーは `DROP POLICY IF EXISTS` → `CREATE POLICY` の形で再実行安全とした
- `anon` / `authenticated` の INSERT / UPDATE / DELETE 権限なしを確認済み
- 将来 admin-app.html に管理 UI を追加するタイミングで管理者セッション付き secure RPC を作成する

### 税込/税抜の扱い

- `sites.contract_amount` は「請負金額（円）」として保持する
- 税込/税抜の統一は工程2（CSV出力RPC設計）で確定するため、本フェーズでは断定しない

### 既存画面・RPC への影響

- `index.html` / `admin-app.html` / `genka-app.html`：影響なし（新カラムは既存 payload に含まれず NULL のまま）
- 既存 secure RPC 全般：影響なし（sites / companies の新カラムを参照しない）
- `report_summary` VIEW：影響なし（sites / companies を JOIN していない）

### 確認結果

- `site_categories` / `company_categories` テーブル: 存在確認済み
- 初期データ: site_categories 7 件 / company_categories 6 件 投入確認済み
- `sites` に `category_id` / `contract_amount` 追加確認済み
- `companies` に `category_id` 追加確認済み
- `idx_sites_category_id` / `idx_companies_category_id` 作成確認済み
- 両テーブル RLS 有効・SELECT ポリシー設定済み
- `anon` / `authenticated` の書き込み権限: 0 件

### 実行したSQL

`docs/sql/phase1-schema-categories.sql`

### ローカルファイル変更

- `docs/sql/phase1-schema-categories.sql` 新規作成
- `docs/db-migrations.md`（本エントリ追記）
- `docs/roadmap.md`（集計出力機能 Phase 1-1 完了を追記）
- HTML / scripts / backups / `.env.backup.local` は変更なし

---

## 2026-06-09 集計出力機能 Phase 2-2 — CSV出力 secure RPC 作成

### 目的

- CSV 集計出力（projects_summary / attendance_details / project_cost_details / machine_details）の元データを生成する、管理者セッション付き SECURITY DEFINER 参照系 RPC を Supabase 本番 DB に作成する
- 直接テーブル権限を増やさず、RPC EXECUTE のみで集計データを取得できる構造にする
- CSV 整形（UTF-8 BOM / CRLF / RFC4180 / 日本語ファイル名）はフロント責務とし、RPC は jsonb エンベロープ `{ meta, warnings, rows }` を返す

### 追加したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/csv-export-secure-rpc.sql` | helper 2関数 + CSV出力 RPC 4本（計6関数） |

### 作成した関数（6本）

| 関数名 | 種別 | 用途 |
|---|---|---|
| `csv_export_fiscal_year(d date, start_month integer)` | helper | 工事年度（4月始まり）算出。内部利用 |
| `csv_export_effective_daily_rate(emp_id uuid, on_date date)` | helper | report_date 時点の有効日当単価取得。該当なしのみ既定22000 / is_default=true。内部利用 |
| `export_projects_summary_secure(...)` | RPC | 工事別原価サマリ（projects_summary.csv） |
| `export_attendance_details_secure(...)` | RPC | 出勤・労務明細（attendance_details.csv） |
| `export_project_cost_details_secure(...)` | RPC | 請求書明細（project_cost_details.csv） |
| `export_machine_details_secure(...)` | RPC | 重機台帳・リース情報（machine_details.csv） |

- 6関数すべて `SECURITY DEFINER`, `SET search_path = public, extensions`
- RPC のセッション検証: `encode(digest(session_token_input, 'sha256'), 'hex')` で `admin_sessions.token_hash` と照合、`expires_at > now()`、無効時 `RAISE EXCEPTION`

### 設計上のポイント

- **ファンアウト防止**: `reports / invoices / site_budgets` を `sites` に直接 JOIN して SUM せず、費目別に site_id 単位 CTE（labor / rep_sub / dump / guard / inv / budget）で事前集計してから `filtered_sites` へ LEFT JOIN
- **労務費 gated**: `normal_mins > 0` のときのみ「日当 + 残業割増」を計上、`normal_mins = 0` は労務費0。中間計算は numeric 保持し、`round()` は最終出力行で1回。残業割増もどの現場か判定できないため `site_count` で均等按分
- **現場なし日報**（`site_ids` 空配列）: projects_summary の工事別原価には含めない。attendance_details では1行出力し labor_cost は按分せず全額
- **fiscal_year**: 各CSVの fiscal_year 列は工事年度＝4月始まり固定。引数 `fiscal_year_start_month`（4 or 9）は受取・検証・meta反映のみで列計算には使わない（将来の会社損益集計用）

### 権限設計

| 対象 | EXECUTE 権限 |
|---|---|
| helper 2関数 | `REVOKE EXECUTE FROM PUBLIC, anon, authenticated`（内部用・直接呼び出し不可） |
| 外側 RPC 4本 | `REVOKE EXECUTE FROM PUBLIC` + `GRANT EXECUTE TO anon, authenticated` |

- ローカル `docs/sql/csv-export-secure-rpc.sql` の helper 2関数 REVOKE 文は、DB 実行済み状態（`FROM PUBLIC, anon, authenticated`）に合わせて修正済み
- テーブルへの GRANT / REVOKE は一切追加・削除していない

### マスタ系テーブルの既存権限（今回触らず）

- `companies / employee_rates / machines / sites / subcontractors / unit_rates` の `anon / authenticated` 直接 INSERT / UPDATE 権限が残存しているが、これは既存状態として扱い、今回の CSV 出力 RPC では変更していない
- 将来のマスタ管理 RPC 化・REVOKE 候補として扱う（roadmap Phase 3 参照）

### 確認結果（実行後）

- 6関数すべて存在確認済み
- 6関数すべて `SECURITY DEFINER`
- 6関数すべて `search_path = public, extensions`
- helper 2本: `anon_exec = false / auth_exec = false`
- 外側 RPC 4本: `anon_exec = true / auth_exec = true`
- テーブル権限は既存状態から増加なし（INSERT/UPDATE/DELETE の新規付与 0件）

### 未実装（次工程）

- admin-app.html から RPC を呼ぶ CSV 出力 UI
- CSV 生成処理（UTF-8 BOM / CRLF / RFC4180 / 日本語ファイル名）
- ローカル HTML ビューア設計・実装

### ローカルファイル変更

- `docs/sql/csv-export-secure-rpc.sql` 新規作成（helper 2関数の REVOKE 文は DB 実行済み状態に合わせ済み）
- `docs/db-migrations.md`（本エントリ追記）
- `docs/roadmap.md`（集計出力機能 Phase 2-2 完了を追記）
- HTML / scripts / backups / `.env.backup.local` は変更なし

---

## 2026-06-09 集計出力機能 Phase 2-3 — admin-app.html CSV出力UI追加

### DB変更

**なし。SQL実行なし。**

### フロント変更

| ファイル | 内容 |
|---|---|
| `admin-app.html` | 「集計出力」メニュー・CSV出力ページ・CSV生成関数を追加 |

### 使用RPC

| RPC名 | 用途 |
|---|---|
| `export_projects_summary_secure` | 工事別サマリー CSV |
| `export_attendance_details_secure` | 出勤・労務明細 CSV |
| `export_project_cost_details_secure` | 請求書明細 CSV |
| `export_machine_details_secure` | 重機台帳 CSV |

- CSV生成はフロント側責務（RPC はjsonbエンベロープ `{ meta, warnings, rows }` を返す）
- セッション検証は既存 `currentUser?.session_token` 方式を踏襲

### 実装内容

- サイドバーに「集計出力」セクション・「📊 CSV出力」メニュー（`nav-csv`）を追加
- `pageCsv()` で4種類のCSV出力カードを表示
- `CSV_COLUMNS` 固定列順定義（仕様書の列順に固定・`Object.keys()` 不使用）
- `downloadCsv()` 共通関数：UTF-8 BOM（`﻿`）・CRLF・RFC4180エスケープ・Blob download
- `buildCsvFilename()` ：`meta.generated_at` 優先・`YYYYMMDD-HHmmss` の生成日時付き日本語ファイル名
- warnings件数通知（alert）・0件時ヘッダのみCSV出力

### 確認結果

- 本番 `https://system.okaigumi.co.jp/admin` で確認済み
- CSV出力メニュー表示OK
- 4種類CSVダウンロードOK（工事別サマリー / 出勤労務明細 / 請求書明細 / 重機台帳）
- Excel文字化けなし（UTF-8 BOM有効）
- Console重大エラーなし

### 関連コミット

- `0c5af6a` Add CSV export UI to admin app

### ローカルファイル変更

- `admin-app.html`（CSV出力UI追加）
- `docs/db-migrations.md`（本エントリ追記）
- `docs/roadmap.md`（集計出力機能 Phase 2-3 完了を追記）
- docs/sql / scripts / backups / `.env.backup.local` は変更なし

---

## 2026-06-11 請求書PDF管理・原価登録候補作成（試作品）

### 概要

人間がPDFを見ながら 1枚の請求書を複数明細に分解し、明細ごとに「原価登録候補」を作る試作機能。
OCR・AI自動判定・メール取り込み・フォルダ監視は **未実装**。
PDF原本は請求書単位で 1つだけ Storage に保存（工事別に物理移動しない）、工事別の見え方はDB明細＋PDFリンクで実現。

**既存の原価管理本体（`invoices` / `report_summary` 等）には一切触れていない。**
削除済みの `public.cost_entries` は復活させていない（独立した3テーブルを新規作成）。

### DB変更（`docs/sql/invoice-pdf-secure-rpc.sql` を Supabase SQL Editor で実行）

**新規テーブル（3つ）**

| テーブル | 用途 |
|---|---|
| `invoice_documents` | 請求書本体（PDF 1枚 = 1レコード） |
| `invoice_document_lines` | 請求書明細行（複数工事・複数原価区分に対応） |
| `invoice_cost_registration_queue` | 原価登録候補（明細ごと・pending/registered/excluded） |

- 3テーブルとも `anon`/`authenticated` は INSERT/UPDATE/DELETE を REVOKE、SELECT のみ GRANT
- 書き込みは全て secure RPC 経由
- `invoice_documents.status` CHECK：`unprocessed / editing / amount_mismatch / confirmed / queued / excluded / error`
- `invoice_cost_registration_queue.status` CHECK：`pending / registered / excluded`
- `project_id` / `vendor_id` は疎結合のため FK を張らず uuid 列のみ（`sites` 等の構造変更なし）

**新規RPC（10件・全て admin セッション検証つき / SECURITY DEFINER）**

| RPC名 | 用途 |
|---|---|
| `create_invoice_document_secure` | Storage アップロード後にレコード作成（unprocessed） |
| `list_invoice_documents_secure` | 一覧（明細数・明細合計を集計） |
| `get_invoice_document_secure` | 1件取得 |
| `list_invoice_document_lines_secure` | 明細行一覧 |
| `save_invoice_document_secure` | 基本情報更新＋明細を全置換＋status再計算（confirmed/queuedは保存拒否） |
| `confirm_invoice_document_secure` | 確認済み化（明細1行以上・合計一致が必須） |
| `unconfirm_invoice_document_secure` | 確認解除（pending候補を削除し editing に戻す） |
| `create_cost_registration_queue_secure` | confirmed の明細ごとに pending 候補を作成→queued |
| `list_cost_registration_queue_secure` | 候補一覧（元PDFパス含む） |
| `exclude_invoice_document_secure` | 請求書を除外 |

**Storage（ダッシュボードで作成 → SQL）**

- Bucket：`invoice-pdfs`（★非公開 / Public OFF）
- Path：`original/{yyyy}/{mm}/{uuid}.pdf`、MIME：application/pdf、Size：10MB
- RLS：`invoice_pdfs_insert`（`original/` 配下のみ INSERT）／`invoice_pdfs_select`（署名付きURL用 SELECT）
- 非公開バケットのため、フロントは `createSignedUrl()` でプレビュー表示

### フロント変更

| ファイル | 内容 |
|---|---|
| `admin-app.html` | 「🧾 請求書PDF」メニュー・一覧/候補タブ・詳細画面（左PDF・右フォーム）・明細編集・合計チェック・確認/確認解除・原価登録候補作成を追加 |

### 重要な制約（実装済み）

- PDF以外アップロード不可（MIME＋拡張子チェック）
- 請求書合計 ≠ 明細合計 のとき確認不可（フロント無効化＋RPCでも拒否）
- 明細0行のとき確認不可（フロント＋RPC両方）
- 確認済み後は編集不可（フォーム disabled＋RPC `save` 拒否）、「確認解除」で再編集可
- 原価管理本体への直接登録はせず、`invoice_cost_registration_queue` に候補(pending)を作成するのみ

### 実行手順（本番反映時）

1. Supabase ダッシュボードで `invoice-pdfs` バケットを **非公開** で作成（MIME=application/pdf、10MB）
2. `docs/sql/invoice-pdf-secure-rpc.sql` をセクションごとに実行
3. 末尾の確認クエリ [1]〜[4] で テーブル3・RPC10・権限・Storageポリシー2 を確認
4. `admin-app.html` をデプロイ

### ローカルファイル変更

- `admin-app.html`（請求書PDF UI追加）
- `docs/sql/invoice-pdf-secure-rpc.sql`（新規）
- `docs/db-migrations.md`（本エントリ追記）
- `docs/roadmap.md`（試作品の進捗を追記）
- 既存の invoices / genka-app.html / index.html は変更なし

---

## 2026-06-13 Phase 3-1 sites / site_assignments secure RPC 適用

### 概要

`sites` / `site_assignments` の書き込みを secure RPC 化するための関数群を追加した。
今回は **RPC追加のみ**（additive-only）で、既存テーブル・既存RLS・既存POLICY・既存GRANT には一切触れていない。
フロント（`admin-app.html` / `index.html`）はまだ `sites` / `site_assignments` を直接書き込んでいるため、
`anon` の INSERT / UPDATE の REVOKE は今回は行わない。

### DB変更（`docs/sql/sites-site-assignments-secure-rpc.sql` を Supabase SQL Editor で実行）

- 適用結果：**Success. No rows returned**

**作成された関数（6件・全て SECURITY DEFINER / SET search_path = public, extensions）**

| 関数名 | 種別 | 用途 |
|---|---|---|
| `public._verify_management_session` | 内部ヘルパー | セッション検証（admin_sessions または employee_sessions role=admin）。クライアント非公開 |
| `public.create_site_secure` | 公開RPC | 現場の新規作成 |
| `public.update_site_secure` | 公開RPC | 現場の更新（is_active / category_id / contract_amount は対象外） |
| `public.deactivate_site_secure` | 公開RPC | 現場の論理削除＋配属の一括無効化 |
| `public.set_site_assignment_secure` | 公開RPC | 配属の単一トグル（ON=upsert / OFF=update） |
| `public.replace_site_assignments_secure` | 公開RPC | 配属の一括洗い替え（原子的） |

**認可方針（デュアルセッション）**

- 有効な `admin_sessions` ＋ `genka_admins.is_active = true`
- または、有効な `employee_sessions` ＋ `employees.role = 'admin'` ＋ `employees.is_active = true`

### 適用後確認

- 6関数の存在確認：OK
- 全6関数が SECURITY DEFINER：OK
- 全6関数が SET search_path = public, extensions：OK
- 公開RPC 5本に `anon` / `authenticated` の EXECUTE あり：OK
- 内部ヘルパー `_verify_management_session` は `anon` / `authenticated` の EXECUTE = false：OK

### 注意

- 今回はRPC追加のみ。既存テーブル・既存RLS・既存POLICY・既存GRANT には触れていない
- まだフロントは直接 `sites` / `site_assignments` を書き込んでいる
- したがって `anon` の INSERT / UPDATE の REVOKE はまだ行わない
- 次フェーズは `admin-app.html` / `index.html` の RPC 移行

### ローカルファイル変更

- `docs/db-migrations.md`（本エントリ追記）
- `docs/sql/sites-site-assignments-secure-rpc.sql` は PR #2（merge commit e9cea5b）で追加済み・本エントリでは変更なし
- 既存の admin-app.html / index.html / genka-app.html は変更なし

---

## 2026-06-13 Phase 3-3 sites / site_assignments direct write REVOKE 適用

### 概要

`sites` / `site_assignments` への `anon` / `authenticated` の直接 INSERT / UPDATE 権限を剥奪した。
Phase 3-2 で admin-app.html / index.html の書き込みが全て secure RPC 経由に移行され、本番動作確認も
完了したため、直接書き込み経路を遮断する。SELECT は維持（一覧・配属表示に必要）、DELETE は対象外
（論理削除運用・物理 DELETE ポリシーは過去フェーズで削除済み）。

### DB変更（`docs/sql/revoke-sites-site-assignments-direct-write.sql` を Supabase SQL Editor で実行）

- 適用結果：**Success. No rows returned**

```sql
REVOKE INSERT ON public.sites            FROM anon, authenticated;
REVOKE UPDATE ON public.sites            FROM anon, authenticated;
REVOKE INSERT ON public.site_assignments FROM anon, authenticated;
REVOKE UPDATE ON public.site_assignments FROM anon, authenticated;
```

### 適用後確認

- `public.sites` の anon / authenticated：SELECT=true / INSERT=false / UPDATE=false / DELETE=false
- `public.site_assignments` の anon / authenticated：SELECT=true / INSERT=false / UPDATE=false / DELETE=false
- secure RPC 5本（`create_site_secure` / `update_site_secure` / `deactivate_site_secure` /
  `set_site_assignment_secure` / `replace_site_assignments_secure`）の anon / authenticated EXECUTE=true

### 本番再確認

- `admin-app.html`：現場作成 / 配属保存 / 現場編集 / 配属変更 / 無効化 OK
- `index.html`：マスタ管理タブ表示 / 現場追加 / 期間・場所更新 / 配属ON/OFF / 無効化 OK

### 注意

- SELECT は維持
- DELETE は対象外
- RPC EXECUTE は維持
- 既存RLSポリシー・既存RPC・既存テーブル定義には触れていない
- これにより `sites` / `site_assignments` の直接 INSERT / UPDATE 経路は遮断済み

### ローカルファイル変更

- `docs/db-migrations.md`（本エントリ追記）
- `docs/sql/revoke-sites-site-assignments-direct-write.sql` は PR #6（merge commit 86b2b6a）で追加済み・本エントリでは変更なし
- 既存の admin-app.html / index.html / genka-app.html は変更なし

---

## 2026-06-18 Phase 3 優先順位2 materials / machines secure RPC 追加

### 概要

`materials` / `machines`（マスタ）の書き込みを secure RPC 化するための関数群を追加した。
今回は **RPC追加のみ**（additive-only）で、既存テーブル・既存RLS・既存POLICY・既存テーブルGRANT には一切触れていない。
フロント（`admin-app.html` / `index.html`）はまだ `materials` / `machines` を直接書き込んでいるため、
`anon` / `authenticated` の直接 INSERT / UPDATE は今回 **REVOKE しない**。
認可は Phase 3-1 で作成済みの既存ヘルパー `public._verify_management_session(text)` を **再利用**し、新規ヘルパーは作成していない。
`machine_locations` は対象外（書き込みは既に `create_machine_location_secure` で RPC 化済み）。

### DB変更（`docs/sql/materials-machines-secure-rpc.sql` を Supabase SQL Editor で実行）

- 適用結果：**Success. No rows returned**

**作成された関数（5件・全て SECURITY DEFINER / SET search_path = public, extensions）**

| 関数名 | 種別 | 用途 |
|---|---|---|
| `public.create_material_secure` | 公開RPC | 材料（外注マスタ用途）の新規作成 |
| `public.deactivate_material_secure` | 公開RPC | 材料の論理削除（is_active=false） |
| `public.create_machine_secure` | 公開RPC | 重機の新規作成（company_id は触らない） |
| `public.update_machine_secure` | 公開RPC | 重機の更新（is_active / company_id / created_at は対象外） |
| `public.deactivate_machine_secure` | 公開RPC | 重機の論理削除（is_active=false） |

**認可方針（デュアルセッション・既存ヘルパー再利用）**

- 各RPC先頭で `PERFORM public._verify_management_session(session_token_input)` を呼ぶ
- 有効な `admin_sessions` ＋ `genka_admins.is_active = true`
- または、有効な `employee_sessions` ＋ `employees.role = 'admin'` ＋ `employees.is_active = true`
- 新規ヘルパーは作成していない（Phase 3-1 の `_verify_management_session` を再利用）

**設計メモ**

- `is_active` はクライアント入力を受けず、create時は true 固定、deactivate は false の論理削除
- `name` は `btrim` して空文字を拒否
- machines の `ownership` は NULL/空文字なら 'owned' 扱い、許可値は 'owned' / 'lease'（既存フロント準拠）、それ以外は例外
- machines の `ownership = 'owned'` 時は lease_company / lease_start / lease_end / lease_monthly を NULL 化（自社所有機にリース情報を残さない／既存フロント挙動と一致）
- `lease_monthly` は NULL または 0以上、`lease_start` / `lease_end` 両方ある場合は start <= end を検証
- machines の `company_id` は nullable のため、create / update いずれでも触らない（既存UI互換）
- materials は `company_id` 列を持たないため対象外
- UPDATE / deactivate は対象id不在時に例外（`Material not found` / `Machine not found`）、各RPCは `RETURNING id` を返す

### 適用後確認

- 5関数の存在確認：OK
- 全5関数が SECURITY DEFINER = true：OK
- 全5関数が SET search_path = public, extensions：OK
- 5関数に `anon` / `authenticated` の EXECUTE あり：OK
- 内部ヘルパー `_verify_management_session` は `anon` / `authenticated` / `public` から EXECUTE 不可のまま維持：OK
- `materials` / `machines` のテーブル権限は適用前と同一（direct INSERT / UPDATE 残存）：OK
- `materials` / `machines` の RLS 状態は適用前と同一：OK
- `materials` / `machines` の POLICY 内容は適用前と同一：OK
- additive-only の副作用なし：OK

**新規5関数の PUBLIC EXECUTE について（記録）**

- 新規5関数は `GRANT EXECUTE ... TO anon, authenticated` を付与しており、関数作成時のデフォルトにより **PUBLIC EXECUTE も true** である。
- これらは公開RPCであり、内部で必ず `_verify_management_session` を通すため、未認証ロールが呼んでもセッション検証で弾かれる。よって現時点では進行可とする。
- ただし「公開RPCの PUBLIC EXECUTE = true」である点は記録対象として残す（将来、最小権限化として PUBLIC からの REVOKE ＋ anon/authenticated への明示 GRANT に整理する余地あり）。

### 注意

- 今回はRPC追加のみ。既存テーブル・既存RLS・既存POLICY・既存テーブルGRANT・REVOKE には触れていない
- まだフロントは直接 `materials` / `machines` を書き込んでいる（direct INSERT / UPDATE 権限は残存）
- したがって `anon` / `authenticated` の直接 INSERT / UPDATE の REVOKE はまだ行わない
- 次工程は Phase 3-2：`admin-app.html`（machines 新規/編集）・`index.html`（materials 追加/無効化・machines 追加/無効化/編集）の RPC 移行
- REVOKE は Phase 3-2 のフロント移行・本番動作確認が完了してから（Phase 3-3 相当）行う

### ローカルファイル変更

- `docs/db-migrations.md`（本エントリ追記）
- `docs/sql/materials-machines-secure-rpc.sql` は別途追加済み・本エントリでは変更なし
- 既存の admin-app.html / index.html / genka-app.html は変更なし

---

## 2026-06-19 Phase 3 優先順位2 machines admin向け secure RPC 追加

### 概要

`admin-app.html` の machines 保存処理（新規/更新）は `company_id` と `is_active` を扱うため、
既存の `create_machine_secure` / `update_machine_secure`（`company_id` を扱わず、create は `is_active=true` 固定、
update は `is_active` を変更しない）へ単純置換すると、管理画面の「会社割当」と「有効/無効の手動切替」が**機能後退**する。
そのため admin 画面専用に、`company_id` と `is_active` を受け取る admin 向け RPC 2本を **additive-only** で追加した。
今回は **RPC追加のみ**で、既存の materials/machines secure RPC 5本（`docs/sql/materials-machines-secure-rpc.sql`）は**変更していない**。
認可は既存ヘルパー `public._verify_management_session(text)` を**再利用**し、新規ヘルパーは作成していない。

### DB変更（`docs/sql/machines-admin-secure-rpc.sql` を Supabase SQL Editor で実行）

- 適用結果：**Success. No rows returned**

**作成された関数（2件・全て SECURITY DEFINER / SET search_path = public, extensions）**

| 関数名 | 種別 | 用途 |
|---|---|---|
| `public.create_machine_admin_secure` | 公開RPC | 重機の新規作成（admin向け。`company_id` / `is_active` をクライアントから受け取る） |
| `public.update_machine_admin_secure` | 公開RPC | 重機の更新（admin向け。`company_id` / `is_active` を反映、`created_at` は対象外） |

**認可方針（デュアルセッション・既存ヘルパー再利用）**

- 各RPC先頭で `PERFORM public._verify_management_session(session_token_input)` を呼ぶ
- 有効な `admin_sessions` ＋ `genka_admins.is_active = true`
- または、有効な `employee_sessions` ＋ `employees.role = 'admin'` ＋ `employees.is_active = true`
- 新規ヘルパーは作成していない（既存 `_verify_management_session` を再利用）

**既存5RPCとの差分（admin向けRPC追加の理由）**

- 既存 `create_machine_secure` / `update_machine_secure` は `company_id` を引数に持たず、`is_active` もクライアントから受け取らない
- `admin-app.html` の保存 payload は `company_id`（所有会社・未設定可）と `is_active`（有効/無効の手動切替）を含む
- 単純置換では会社割当・有効/無効切替が表現できず機能後退するため、admin専用の追加RPCで対応する方針とした

**設計メモ**

- `name` は `btrim` して空文字を拒否
- `is_active_input` は NULL を拒否（`is_active is required`）
- `company_id_input` は NULL 許容。非NULL時は `public.companies` への存在確認を明示的に行い、不在なら例外（`Company not found`）
- `ownership` は NULL/空文字なら 'owned' 扱い、許可値は 'owned' / 'lease'、それ以外は例外
- `ownership = 'owned'` 時は lease_company / lease_start / lease_end / lease_monthly を NULL 化
- `lease_monthly` は NULL または 0以上、`lease_start` / `lease_end` 両方ある場合は start <= end を検証
- create 時は machines に name / company_id / is_active / ownership / lease_* を INSERT
- update 時は machines の name / company_id / is_active / ownership / lease_* を UPDATE（`created_at` は触らない）、対象id不在時は例外（`Machine not found`）
- 各RPCは `RETURNING id` を返す

### 適用後確認

- 2関数（`create_machine_admin_secure` / `update_machine_admin_secure`）の存在確認：OK
- 両関数が SECURITY DEFINER = true：OK
- 両関数が SET search_path = public, extensions：OK
- 両関数に `anon` / `authenticated` の EXECUTE あり：OK
- 内部ヘルパー `_verify_management_session` は `anon` / `authenticated` / `public` から EXECUTE 不可のまま維持：OK
- `machines` のテーブル権限は適用前と同一（direct INSERT / UPDATE 残存）：OK
- `machines` の RLS 状態は適用前と同一：OK
- `machines` の POLICY 内容は適用前と同一：OK
- additive-only の副作用なし：OK

**新規2関数の PUBLIC EXECUTE について（記録）**

- 新規2関数は `GRANT EXECUTE ... TO anon, authenticated` を付与しており、関数作成時のデフォルトにより **PUBLIC EXECUTE も true** である。
- これらは公開RPCであり、内部で必ず `_verify_management_session` を通すため、未認証ロールが呼んでもセッション検証で弾かれる。よって現時点では進行可とする。
- ただし「公開RPCの PUBLIC EXECUTE = true」である点は記録対象として残す（既存5RPCと同様、将来 PUBLIC からの REVOKE ＋ anon/authenticated への明示 GRANT に整理する余地あり）。

### 注意

- 今回はRPC追加のみ。既存テーブル・既存RLS・既存POLICY・既存テーブルGRANT・REVOKE には触れていない
- 既存の materials/machines secure RPC 5本は変更していない
- まだフロントは直接 `machines` を書き込んでいる（direct INSERT / UPDATE 権限は残存）
- したがって `anon` / `authenticated` の直接 INSERT / UPDATE の REVOKE はまだ行わない
- 次工程は Phase 3-2：`admin-app.html`（machines 新規/編集 → admin向けRPC）・`index.html`（materials 追加/無効化・machines 追加/無効化/編集 → 既存5RPC）の RPC 移行
- REVOKE は Phase 3-2 のフロント移行・本番動作確認が完了してから（Phase 3-3 相当）行う

### ローカルファイル変更

- `docs/db-migrations.md`（本エントリ追記）
- `docs/sql/machines-admin-secure-rpc.sql` は別途追加済み・本エントリでは変更なし
- 既存の admin-app.html / index.html / genka-app.html は変更なし

---

## 2026-06-19 Phase 3-3 materials / machines direct write REVOKE

### 概要

`materials` / `machines` への `anon` / `authenticated` の直接 INSERT / UPDATE 権限を剥奪した。
Phase 3-2 で `index.html` / `admin-app.html` の書き込みが secure RPC 7本へ移行され、本番動作確認も
完了したため、直接書き込み経路を遮断する。SELECT は維持（一覧・参照に必要。`genka-app.html` も
machines を SELECT 参照）、RPC EXECUTE は維持、RLS / POLICY は変更しない。

### DB変更（`docs/sql/revoke-materials-machines-direct-write.sql` を Supabase SQL Editor で実行）

- 適用済み

```sql
REVOKE INSERT, UPDATE ON TABLE public.materials FROM anon, authenticated;
REVOKE INSERT, UPDATE ON TABLE public.machines  FROM anon, authenticated;
```

**REVOKE対象**

- `public.materials` の `INSERT`, `UPDATE` from `anon`, `authenticated`
- `public.machines` の `INSERT`, `UPDATE` from `anon`, `authenticated`

**REVOKEしなかったもの（このSQLでは触らない）**

- `SELECT`（維持）
- secure RPC 7本の `EXECUTE`（維持）
- `_verify_management_session`（外部非公開のまま維持）
- RLS（変更なし）
- POLICY（変更なし）
- その他テーブル権限（変更なし）

### 適用後確認

- `materials` / `machines` の `anon` / `authenticated` から `INSERT` / `UPDATE` が消滅：OK
- `materials` / `machines` の `SELECT` は維持：OK
- secure RPC 7本（`create_material_secure` / `deactivate_material_secure` / `create_machine_secure` /
  `update_machine_secure` / `deactivate_machine_secure` / `create_machine_admin_secure` /
  `update_machine_admin_secure`）の `anon` / `authenticated` EXECUTE：**14行維持**：OK
- `_verify_management_session` は `anon` / `authenticated` / `public` から EXECUTE 不可のまま：OK
- RLS 状態は変更なし（`machines,true,false` / `materials,true,false`）：OK
- POLICY 一覧は変更なし：OK

### 本番動作確認

- 従業員画面 `/`：外注追加 / 外注無効化 / 重機追加 / 重機設定保存 / 重機無効化：OK
- 管理画面 `/admin`：重機新規追加 / 重機編集 / 会社割当 / 有効・無効切替 / 自社・リース設定：OK

### 結論

- Phase 3 優先順位2 materials / machines は、フロントRPC移行と direct write REVOKE が完了
- `materials` / `machines` への直接 `INSERT` / `UPDATE` は、コード上もDB権限上も廃止
- 読み取り `SELECT` は従来どおり維持

### 注意

- 今回は権限剥奪（REVOKE）のみ。RPC関数・RLS・POLICY・SELECT・EXECUTE には触れていない
- `materials` / `machines` の直接 INSERT / UPDATE 経路は遮断済み

### ローカルファイル変更

- `docs/db-migrations.md`（本エントリ追記）
- `docs/sql/revoke-materials-machines-direct-write.sql` は別途作成済み・本エントリでは内容変更なし
- 既存の admin-app.html / index.html / genka-app.html は変更なし

---

## 2026-06-30 Phase 3 優先順位3 employee_rates / unit_rates secure RPC 追加

### 概要

`employee_rates` / `unit_rates`（単価マスタ）の書き込みを secure RPC 化するための関数群を追加した。
今回は **RPC追加のみ**（additive-only）で、既存テーブル・既存RLS・既存POLICY・既存テーブルGRANT には一切触れていない。
フロント（`admin-app.html` / `genka-app.html`）はまだ `employee_rates` / `unit_rates` を直接 upsert しているため、
`anon` / `authenticated` の直接 INSERT / UPDATE は今回 **REVOKE しない**。
認可は Phase 3-1 で作成済みの既存ヘルパー `public._verify_management_session(text)` を **再利用**し、新規ヘルパーは作成していない。
materials / machines（優先順位2）が `index.html` ＋ `admin-app.html` だったのに対し、今回の書き込み元は
**`admin-app.html` ＋ `genka-app.html`** の2画面である点が差分（`index.html` には単価書き込みなし）。

### DB変更（`docs/sql/employee-unit-rates-secure-rpc.sql` を Supabase SQL Editor で実行）

- 適用結果：**Success. No rows returned**

**作成された関数（2件・全て SECURITY DEFINER / SET search_path = public, extensions）**

| 関数名 | 種別 | 用途 |
|---|---|---|
| `public.upsert_employee_rate_secure(text, uuid, integer, date)` | 公開RPC | 従業員日当の upsert（`employee_id, effective_from` で衝突時は `daily_rate` のみ更新） |
| `public.upsert_unit_rate_secure(text, text, text, integer, text)` | 公開RPC | 単価（ダンプ/警備/外注等）の upsert（`category, name` で衝突時は `unit_price` / `unit` / `updated_at` を更新） |

**認可方針（デュアルセッション・既存ヘルパー再利用）**

- 各RPC先頭で `PERFORM public._verify_management_session(session_token_input)` を呼ぶ
- 有効な `admin_sessions` ＋ `genka_admins.is_active = true`
- または、有効な `employee_sessions` ＋ `employees.role = 'admin'` ＋ `employees.is_active = true`
- 新規ヘルパーは作成していない（Phase 3-1 の `_verify_management_session` を再利用）

**設計メモ**

- 両RPCとも `RETURNS uuid`。upsert された行の `id` を返す
- `upsert_employee_rate_secure`
  - `employee_id_input` が NULL なら例外（`Employee id is required`）
  - `daily_rate_input` が NULL または負数なら例外（`Daily rate must be zero or positive`）
  - `effective_from_input` が NULL なら例外（`Effective from date is required`）
  - `public.employees` に対象 id が存在しなければ例外（`Employee not found`）。`is_active` 等の未確認列は条件に使わない
  - `ON CONFLICT (employee_id, effective_from) DO UPDATE` で `daily_rate` のみ更新。`hourly_rate` / `created_at` は触らない
  - employee_rates は effective-dated 履歴テーブルのため、同日 upsert は当日レートの更新になる（既存フロント挙動と一致）
- `upsert_unit_rate_secure`
  - `category_input` / `name_input` / `unit_input` は `btrim` して空文字を拒否
  - `unit_price_input` は NULL または負数なら例外（`Unit price must be zero or positive`）
  - `ON CONFLICT (category, name) DO UPDATE` で `unit_price` / `unit` / `updated_at` を更新
  - `updated_at` はクライアント入力を信頼せず、INSERT / UPDATE いずれも **サーバ側 `now()`** を使う
  - `company_id` は触らない（既存UI互換）

### 適用後確認

- 2関数の存在確認：OK
- 全2関数が SECURITY DEFINER = true：OK
- 全2関数が SET search_path = public, extensions：OK
- 2関数に `anon` / `authenticated` の EXECUTE あり（`upsert_employee_rate_secure` × anon/authenticated、`upsert_unit_rate_secure` × anon/authenticated）：OK
- 内部ヘルパー `_verify_management_session` は `anon` / `authenticated` / `public` から EXECUTE 不可のまま維持（0行）：OK
- `employee_rates` / `unit_rates` のテーブル定義は変更なし：OK
- `employee_rates` / `unit_rates` の RLS 状態は変更なし：OK
- `employee_rates` / `unit_rates` の POLICY 内容は変更なし：OK
- REVOKE なし・direct INSERT / UPDATE 権限は残存：OK
- additive-only の副作用なし：OK

**新規2関数の PUBLIC EXECUTE について（記録）**

- 新規2関数は `GRANT EXECUTE ... TO anon, authenticated` を付与しており、関数作成時のデフォルトにより **PUBLIC EXECUTE も true** である。
- これらは公開RPCであり、内部で必ず `_verify_management_session` を通すため、未認証ロールが呼んでもセッション検証で弾かれる。よって現時点では進行可とする。
- 「公開RPCの PUBLIC EXECUTE = true」である点は記録対象として残す（優先順位2と同じ整理。将来 PUBLIC からの REVOKE ＋ anon/authenticated への明示 GRANT に整理する余地あり）。

### 注意

- 今回はRPC追加のみ。既存テーブル・既存RLS・既存POLICY・既存テーブルGRANT・REVOKE には触れていない
- まだフロントは直接 `employee_rates` / `unit_rates` を upsert している（direct INSERT / UPDATE 権限は残存）
- したがって `anon` / `authenticated` の直接 INSERT / UPDATE の REVOKE はまだ行わない
- 次工程：`admin-app.html`（`saveEmpRate` / `saveUnitRate`）・`genka-app.html`（`saveEmpRate` / `saveUnitRate`）の RPC 移行（計4箇所）
- REVOKE はフロント移行・本番動作確認が完了してから（Phase 3-3 相当）行う

### ローカルファイル変更

- `docs/db-migrations.md`（本エントリ追記）
- `docs/sql/employee-unit-rates-secure-rpc.sql` は別途追加済み・本エントリでは変更なし
- 既存の admin-app.html / index.html / genka-app.html は変更なし

---

## 2026-06-30 Phase 3 優先順位3 employee_rates / unit_rates direct write REVOKE 完了

### 概要

`employee_rates` / `unit_rates` への `anon` / `authenticated` の直接 INSERT / UPDATE 権限を剥奪した。
フロント（`admin-app.html` / `genka-app.html`）の単価書き込みは既に secure RPC 2本
（`upsert_employee_rate_secure` / `upsert_unit_rate_secure`）へ移行され、本番動作確認も完了したため、
直接書き込み経路を遮断する。SELECT は維持（一覧・単価設定画面の表示に必要。`admin-app.html` /
`genka-app.html` がともに SELECT 参照）、RPC EXECUTE は維持、RLS / POLICY は変更しない。

### DB変更（`docs/sql/revoke-employee-unit-rates-direct-write.sql` を Supabase SQL Editor で実行）

- 適用結果：**Success. No rows returned**

```sql
REVOKE INSERT, UPDATE ON TABLE public.employee_rates FROM anon, authenticated;
REVOKE INSERT, UPDATE ON TABLE public.unit_rates     FROM anon, authenticated;
```

**REVOKE対象**

- `public.employee_rates` の `INSERT`, `UPDATE` from `anon`, `authenticated`
- `public.unit_rates` の `INSERT`, `UPDATE` from `anon`, `authenticated`

**REVOKEしなかったもの（このSQLでは触らない）**

- `SELECT`（維持）
- `REFERENCES` / `TRIGGER` / `TRUNCATE`（今回触っていない）
- secure RPC 2本の `EXECUTE`（維持）
- `_verify_management_session`（外部非公開のまま維持）
- RLS（変更なし）
- POLICY（変更なし）
- テーブル定義（変更なし）

### 適用後確認

- table privileges：`employee_rates` / `unit_rates` とも `anon` / `authenticated` から `INSERT` / `UPDATE` が消滅、`SELECT` は残存：OK
- secure RPC EXECUTE：`upsert_employee_rate_secure` × anon/authenticated、`upsert_unit_rate_secure` × anon/authenticated の **4行維持**：OK
- `_verify_management_session` は `anon` / `authenticated` / `public` から EXECUTE 不可のまま（0行）：OK
- RLS 状態：`employee_rates`（rls_enabled = true, rls_forced = false）/ `unit_rates`（rls_enabled = true, rls_forced = false）で変更なし：OK
- POLICY：`employee_rates`（`er_read` / `er_update` / `er_write`）・`unit_rates`（`ur_read` / `ur_update` / `ur_write`）が残存・変更なし：OK

### 本番動作確認

- 管理画面 `/admin`：従業員日当保存 / 単価保存：OK
- 原価画面 `/genka`：従業員日当保存 / 単価保存：OK

### 結論

- `employee_rates` / `unit_rates` への直接 `INSERT` / `UPDATE` は、コード上もDB権限上も廃止
- 単価・日当の保存は secure RPC 経由に一本化され、REVOKE後も本番4項目（/admin・/genka の日当・単価保存）が動作
- 読み取り `SELECT` は従来どおり維持

### 注意

- 今回は権限剥奪（REVOKE）のみ。RPC関数・RLS・POLICY・SELECT・EXECUTE・テーブル定義には触れていない
- `employee_rates` / `unit_rates` の直接 INSERT / UPDATE 経路は遮断済み
- 次工程：`docs/roadmap.md` への反映（Phase 3 優先順位3 完了扱い）、commit、push、PR作成

### ローカルファイル変更

- `docs/db-migrations.md`（本エントリ追記）
- `docs/sql/revoke-employee-unit-rates-direct-write.sql` は別途作成済み・本エントリでは内容変更なし
- 既存の admin-app.html / index.html / genka-app.html は変更なし

---

## 2026-06-30 Phase 4-A-1 subcontractors write lockdown 完了

### 概要

Phase 4（RLSポリシー整理）の最初の実施項目。`subcontractors` はフロント3アプリで SELECT のみ
使用しているにも関わらず、`anon` / `authenticated` に直接 INSERT / UPDATE の GRANT と、緩い
write policy（`sub_write` / `sub_update` = public true）が残存していた（フロント未使用の orphan な
書き込み経路。API直叩きで通る穴）。この write 経路を塞ぐ。SELECT 権限と `sub_read` policy は
維持（業者一覧の表示に必要）。DELETE は既に public 全テーブルで REVOKE 済みのため対象外。

### DB変更（`docs/sql/phase4a-1-subcontractors-write-lockdown.sql` を Supabase SQL Editor で実行）

- 適用結果：**Success. No rows returned**

```sql
REVOKE INSERT, UPDATE ON TABLE public.subcontractors FROM anon, authenticated;
DROP POLICY IF EXISTS sub_write  ON public.subcontractors;
DROP POLICY IF EXISTS sub_update ON public.subcontractors;
```

**対象**

- `public.subcontractors` の `INSERT`, `UPDATE` を `anon`, `authenticated` から REVOKE
- 緩い write policy `sub_write` / `sub_update` を削除

**触らなかったもの**

- `SELECT` 権限（維持）
- `sub_read` policy（維持）
- `DELETE`（既に public 全テーブルで REVOKE 済みのため対象外）
- RLS 有効状態・テーブル定義・他テーブル（変更なし）

### 適用後確認

- table privileges：`subcontractors` の `anon` / `authenticated` は `SELECT` のみ。INSERT / UPDATE / DELETE は残存なし：OK
- policy：`sub_read` は残存、`sub_write` / `sub_update` は削除済み：OK
- 書き込み権限の明示チェック：`anon` / `authenticated` に INSERT / UPDATE / DELETE なし（0行）：OK

### 本番動作確認

- 従業員画面 `index.html`：外注選択チップ（業者一覧）表示：OK
- 管理画面 `admin-app.html`：初期ロードの業者一覧取得：OK
- 原価画面 `genka-app.html`：初期ロードの業者一覧取得：OK

### 結論

- `subcontractors` への直接 INSERT / UPDATE は DB権限・policy 両面で廃止（orphan write 穴を解消）
- フロントは `subcontractors` を SELECT のみ使用のため画面影響なし
- 読み取り `SELECT` と `sub_read` policy は従来どおり維持

### 注意

- 今回は subcontractors 限定の write 権限剥奪＋緩い write policy 削除のみ
- 次工程（Phase 4 残）：photos upload 制限、report_summary / reports / paid_leave_* の読み取り整理
- 整理用SQL・REVOKE案・POLICY削除案・migration案は別フェーズで個別に扱う

### ローカルファイル変更

- `docs/db-migrations.md`（本エントリ追記）
- `docs/sql/phase4a-1-subcontractors-write-lockdown.sql` は別途作成済み（実行済みSQL案として保持）
- 既存の admin-app.html / index.html / genka-app.html は変更なし

---

## 2026-06-30 Phase 4-A-2 photos upload 制限 完了

### 概要

public な `photos` バケットは `file_size_limit` / `allowed_mime_types` が未設定で、任意サイズ・
任意MIMEのアップロードを許す状態だった（ストレージ濫用・非画像投入の穴）。bucket 設定で
「最大5MB・image/jpeg のみ」に制限し、アップロードを絞る。`public = true`（read）は維持し、
`storage.objects` の policy（`photos_read` / `photos_upload`）は変更しない。
フロント（index.html）は upload 時 `contentType:'image/jpeg'` 固定・縮小後JPEG（最大1280x720・
品質0.7）・最大5枚のため、本制限の範囲内で従来どおり動作する。

### DB変更（`docs/sql/phase4a-2-photos-upload-limits.sql` を Supabase SQL Editor で実行）

- 適用結果：**Success**

```sql
UPDATE storage.buckets
SET
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg']
WHERE id = 'photos';
```

**対象**

- `storage.buckets` の `id = 'photos'` の `file_size_limit` / `allowed_mime_types` のみ

**触らなかったもの**

- `photos` の `public`（true 維持＝read 維持）
- `storage.objects` の policy（`photos_read` / `photos_upload` とも変更なし）
- 他バケット（`notice-attachments` / `invoice-pdfs`）
- 他テーブル

### 適用後確認

- `photos` の `public = true` 維持：OK
- `photos` の `file_size_limit = 5242880`（5MB）：OK
- `photos` の `allowed_mime_types = ["image/jpeg"]`：OK
- `photos_read` policy 変更なし：OK
- `photos_upload` policy 変更なし：OK

### 本番動作確認（index.html）

- 既存写真表示（詳細モーダル）：OK
- 写真クリックで別タブ表示：OK
- 新規写真アップロード：OK
- 保存（update_report_photo_secure 経由）：OK
- 詳細表示：OK
- Console 重大エラーなし：OK

### 結論

- `photos` への過大・非画像アップロードを bucket 設定で遮断（最大5MB・image/jpeg のみ）
- `public read` は維持＝`reports.photo_urls` の public URL 保存方式・既存写真表示は影響なし
- private化・署名URL化は未実施（別フェーズ）、`storage.objects` policy も未変更

### 注意

- 今回は `photos` バケットの設定値（file_size_limit / allowed_mime_types）変更のみ
- INSERT policy の role 絞り込み・private化・署名URL化は anon 運用前提と保存URL方式に抵触するため対象外
- 次工程（Phase 4 残）：report_summary / reports / paid_leave_* の読み取り整理、financial系の
  管理セッション限定読み取り化、管理者向け日報写真確認導線（photos の public維持／将来private化方針と整合）

### ローカルファイル変更

- `docs/db-migrations.md`（本エントリ追記）
- `docs/sql/phase4a-2-photos-upload-limits.sql` は別途作成済み（実行済みSQL案として保持）
- 既存の admin-app.html / index.html / genka-app.html は変更なし
