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

---

## 2026-06-30 Phase 4-B paid_leave 読み取りRPC化・SELECT遮断 完了

### 目的

- `paid_leave_requests` / `paid_leave_grants` の直接 SELECT を閉じ、読み取りを
  secure RPC（SECURITY DEFINER）経由へ統一する。既存 write RPC は壊さない。

### 追加済み read RPC

- `list_my_paid_leave_secure(text)`（本人用・employee_sessions 検証）
- `list_paid_leave_admin_secure(text)`（管理者用・二経路検証）
- ※SQL記録：`docs/sql/phase4b-paid-leave-read-rpc.sql`（PUBLIC EXECUTE を外し
  anon/authenticated/service_role に明示 GRANT）

### フロント移行

- `index.html` `loadLeaveWorker` → `list_my_paid_leave_secure`
- `index.html` `loadLeaveAdmin` → `list_paid_leave_admin_secure`
- `admin-app.html` `pageLeave` → `list_paid_leave_admin_secure`

### 本番反映

- PR #21 merge 済み（merge commit：`7f67be8`）、本番画面確認 OK

### 実行済み DB 変更（`docs/sql/phase4b-paid-leave-select-revoke.sql` を Supabase SQL Editor で実行）

- 適用結果：**Success. No rows returned**（実行日 2026-06-30）

```sql
REVOKE SELECT ON public.paid_leave_requests FROM anon, authenticated;
REVOKE SELECT ON public.paid_leave_grants   FROM anon, authenticated;
DROP POLICY IF EXISTS plr_read ON public.paid_leave_requests;
DROP POLICY IF EXISTS plg_read ON public.paid_leave_grants;
```

### 事前確認

- `paid_leave_requests` / `paid_leave_grants` に anon/authenticated SELECT 残存を確認
- INSERT/UPDATE/DELETE 権限なしを確認
- `plr_read` / `plg_read` / write系 policy を確認
- 新 read RPC 2本の存在・EXECUTE 権限を確認
- 既存 write RPC 3本の存在を確認

### 事後確認

- anon/authenticated SELECT 消滅
- `plr_read` / `plg_read` 消滅
- write系 policy 4本は残存（`plr_write` / `plr_update` / `plg_write` / `plg_update`）
- 新 read RPC 2本の EXECUTE 権限維持（anon/authenticated/service_role、PUBLIC なし）
- 既存 write RPC 3本維持（security_definer=true）
  - `create_paid_leave_request_secure`
  - `review_paid_leave_request_secure`
  - `save_paid_leave_grant_secure`

### REVOKE 後の本番画面確認

- 本番 index 本人有給：OK
- 本番 index 管理者有給：OK
- 本番 admin-app 有給管理：OK
- エラーなし

### 触らなかったもの

- write系 policy（`plr_write` / `plr_update` / `plg_write` / `plg_update`）は残存
- `reports` / `report_summary` / `photos` / `invoices` / `site_budgets` 等は未着手
- paid_leave 以外のテーブルは未変更

### 次工程候補

- write系 policy の整理（別工程候補。write RPC 経由の書き込みに影響しないことを
  事前確認した上で実施）
- Phase 4-C 以降で `reports` / `report_summary` の読み取り整理

### SQL記録ファイル

- `docs/sql/phase4b-paid-leave-read-rpc.sql`
- `docs/sql/phase4b-paid-leave-select-revoke.sql`

---

## 2026-07-01 Phase 4-C-1 本人日報 読み取りRPC化・reports SELECT遮断 完了

### 目的

- `reports` の本人日報 direct SELECT を secure RPC（SECURITY DEFINER）経由へ移行し、
  `anon` / `authenticated` の `reports` 直接 SELECT を遮断する。既存 write RPC は壊さない。

### 追加済み read RPC

- `list_my_reports_secure(text, date, integer)`（本人用・employee_sessions 検証、
  employees を JOIN し is_active=true も確認）
  - 引数：`session_token_input` / `before_date_input`（DEFAULT NULL）/ `limit_input`（DEFAULT 30・1〜100 に丸め）
  - loadHistory と copyFromYesterday を1本で兼用（`report_date < before_date_input` の最新分を DESC で返す）
- ※SQL記録：`docs/sql/phase4c-1-my-reports-read-rpc.sql`（PUBLIC EXECUTE を外し
  anon/authenticated/service_role に明示 GRANT）

### フロント移行

- `index.html` `loadHistory` → `list_my_reports_secure`（before_date=NULL / limit=30）
- `index.html` `copyFromYesterday` → `list_my_reports_secure`（before_date=today / limit=1）
- 移行後、`index.html` 内の `from('reports')` は 0 件

### 本番反映

- PR #23 merge 済み（merge commit：`17d4b7f`）
- 本番反映確認：Network に `list_my_reports_secure` あり、`reports?select=...` の direct SELECT なし

### 実行済み DB 変更（`docs/sql/phase4c-1-reports-select-revoke.sql` を Supabase SQL Editor で実行）

- 適用結果：**Success. No rows returned**（実行日 2026-07-01）

```sql
REVOKE SELECT ON public.reports FROM anon, authenticated;
```

- 経緯：一時REVOKE → 本番旧 direct SELECT が 401 で履歴空表示 → `GRANT SELECT` で復旧 →
  PR #23 merge・本番 RPC 反映確認後に再REVOKE、という順で最終適用。

### 事前確認（A〜F）

- `reports` に anon/authenticated SELECT 残存・INSERT/UPDATE/DELETE なしを確認
- `reports_all` policy（ALL / {public} / true / true）を確認
- `list_my_reports_secure` の存在・SECURITY DEFINER・search_path・EXECUTE 権限を確認
- 既存 write RPC 3本の存在を確認
- `report_summary` 未変更を確認

### 事後確認（G〜K）

- `reports` の anon/authenticated SELECT = false
- `reports_all` policy 未変更（残存）
- `list_my_reports_secure` EXECUTE 維持（anon/authenticated/service_role、PUBLIC なし）
- 既存 write RPC 3本維持（security_definer=true）
  - `create_report_secure`
  - `update_report_secure`
  - `update_report_photo_secure`
- `report_summary` 未変更

### REVOKE 後の本番画面確認（①〜⑦）

- 日報履歴表示 OK
- 写真バッジ・詳細表示 OK
- 修正ボタン・編集復元 OK
- 前日コピー OK
- 新規保存 OK
- 修正保存 OK
- 写真保存 OK
- Console 赤エラーなし

### 触らなかったもの

- `reports_all` policy（cmd=ALL の単一 policy。整理は別ステップで判断）
- `report_summary` View（4-C-4 で封鎖予定）
- `reports` write RPC 3本
- `genka-app.html` / `admin-app.html`

### 次工程

- Phase 4-C-2 以降で `report_summary` の代替 read RPC 化と View 封鎖を進める
  - 4-C-2：index 管理系（loadAdminData / loadStats）
  - 4-C-3：genka 原価系（loadData）
  - 4-C-4：report_summary View 封鎖・不要 GRANT 整理

### 補足（別課題）

- 同日・同時間の日報を重複入力した場合、画面から削除／取消する手段が未実装。
  Phase 4-C とは別課題として `docs/roadmap.md` の Phase 8 候補へ記録
  （本人の当日取消RPC、または管理者取消/削除機能。物理削除より論理取消を優先検討）。

### SQL記録ファイル

- `docs/sql/phase4c-1-my-reports-read-rpc.sql`
- `docs/sql/phase4c-1-reports-select-revoke.sql`

## 2026-07-01 Phase 4-C-2 index 管理系 report_summary 代替read RPC化 完了

### 目的

- index.html の管理画面系（`loadAdminData` / `loadStats`）が使う `report_summary` の
  direct read を secure RPC（SECURITY DEFINER）経由へ移行し、View 封鎖（4-C-4）前の段階として
  index.html から direct read を除去する。`report_summary` View / `reports` 権限は変更しない。

### 追加済み read RPC

- `list_admin_reports_secure(text, date, date)`（管理者用・二経路の管理者セッション検証）
  - 引数：`session_token_input` / `from_date_input`（DEFAULT NULL）/ `to_date_input`（DEFAULT NULL）
  - 検証：employee_sessions＋employees（role='admin'／is_active）、または admin_sessions＋genka_admins
  - `reports` と `employees` を直接 JOIN（`e.name AS employee_name`）するため `report_summary` View に非依存
    （4-C-4 の View 封鎖後も動作する設計）。日付範囲で WHERE、`report_date DESC, e.name` で返す
  - from > to は RAISE EXCEPTION、管理者でなければ 'Invalid or expired session' を RAISE
  - loadAdminData（from=to=当日）と loadStats（from=月初 / to=月末）を1本で兼用
- ※SQL記録：`docs/sql/phase4c-2-admin-reports-read-rpc.sql`（PUBLIC EXECUTE を外し
  anon/authenticated/service_role に明示 GRANT）

### 実行済み DB 変更（`docs/sql/phase4c-2-admin-reports-read-rpc.sql` を Supabase SQL Editor で実行・2026-07-01）

- `CREATE OR REPLACE FUNCTION public.list_admin_reports_secure(...)`（SECURITY DEFINER /
  `SET search_path = public, extensions` / STABLE）
- `REVOKE EXECUTE ON FUNCTION public.list_admin_reports_secure(...) FROM PUBLIC;`
- `GRANT EXECUTE ON FUNCTION public.list_admin_reports_secure(...) TO anon, authenticated, service_role;`
- 危険SQL（DROP / DELETE / TRUNCATE / ALTER / UPDATE / INSERT）なし

### フロント移行

- `index.html` `loadAdminData` → `list_admin_reports_secure`（from_date=to_date=当日）
- `index.html` `loadStats` → `list_admin_reports_secure`（from_date=月初 / to_date=月末）
- token ガード（`state.currentUser?.session_token` 未取得時 return）・error ガード追加
- `showSiteDetail` / `exportCSV` は無改修（`window._statsReports` 経由のため RPC 戻り値の shape が従来と一致）
- 移行後、`index.html` の `from('report_summary')` は 0 件、`list_admin_reports_secure` は 2 件

### 本番反映

- PR #25 merge 済み（merge commit：`d958fe4`）
- 本番反映確認：Network に `list_admin_reports_secure`（status 200）あり、`report_summary?select=...` なし

### DB 確認

- `list_admin_reports_secure` の存在・SECURITY DEFINER・`search_path = public, extensions` を確認
- EXECUTE：anon / authenticated / service_role に付与、PUBLIC EXECUTE なし
- 管理者 Console から RPC 動作確認 OK（success: true / error: null / data: Array(1) / status: 200）
- `report_summary` View 未変更
- `reports` 権限 / policy 未変更

### 本番画面確認

- 管理タブ表示 OK
- 集計タブ表示 OK
- 月切替 OK
- 現場ドリルダウン OK
- CSV 出力 OK
- Network で `list_admin_reports_secure` あり（status 200）／`report_summary?select=...` なし
- Console 赤エラーなし・表示異常なし

### 触らなかったもの

- `report_summary` View（4-C-4 で封鎖・SELECT REVOKE 予定）
- `reports` 権限 / policy
- `genka-app.html`（`report_summary` 参照1件は 4-C-3 対象として未変更）
- `admin-app.html`

### 次工程

- 4-C-3：genka 原価系（genka-app.html `loadData` の `report_summary` 参照移行）
- 4-C-4：`report_summary` View 封鎖・不要 GRANT 整理（anon/authenticated SELECT の REVOKE）

### SQL記録ファイル

- `docs/sql/phase4c-2-admin-reports-read-rpc.sql`

## 2026-07-01 Phase 4-C-3 genka 原価系 report_summary 代替read RPC化 完了

### 目的

- genka-app.html の原価集計（`loadData`）が使う `report_summary` の
  direct read を secure RPC（SECURITY DEFINER）経由へ移行し、View 封鎖（4-C-4）前の段階として
  genka-app.html から direct read を除去する。`report_summary` View / `reports` 権限は変更しない。

### 追加済み read RPC

- `list_genka_reports_secure(text, date, date, uuid)`（原価管理用・二経路の管理者セッション検証）
  - 引数：`session_token_input` / `from_date_input`（DEFAULT NULL）/ `to_date_input`（DEFAULT NULL）/
    `site_id_input`（DEFAULT NULL）
  - 検証：employee_sessions＋employees（role='admin'／is_active）、または admin_sessions＋genka_admins
    （genka の実利用経路は後者）
  - 戻り列：report_date / employee_id / normal_mins / overtime_mins / site_ids /
    subcontractor_ids / dump_count / dump_company / guard_count
  - `reports` 単独から生成（原価に必要な列はすべて reports 由来のため employees JOIN 不要）。
    `report_summary` View に非依存で、4-C-4 の View 封鎖後も動作する設計
  - `site_id_input` があれば `site_ids @> ARRAY[site_id_input]::uuid[]`（genka の
    `contains('site_ids',[siteId])` と等価）。from > to は RAISE EXCEPTION、
    管理者でなければ 'Invalid or expired session' を RAISE
- ※SQL記録：`docs/sql/phase4c-3-genka-reports-read-rpc.sql`（PUBLIC EXECUTE を外し
  anon/authenticated/service_role に明示 GRANT）

### 実行済み DB 変更（`docs/sql/phase4c-3-genka-reports-read-rpc.sql` を Supabase SQL Editor で実行・2026-07-01）

- `CREATE OR REPLACE FUNCTION public.list_genka_reports_secure(...)`（SECURITY DEFINER /
  `SET search_path = public, extensions` / STABLE）… Success. No rows returned
- `REVOKE EXECUTE ON FUNCTION public.list_genka_reports_secure(...) FROM PUBLIC;` … Success. No rows returned
- `GRANT EXECUTE ON FUNCTION public.list_genka_reports_secure(...) TO anon, authenticated, service_role;` … Success. No rows returned
- 危険SQL（DROP / DELETE / TRUNCATE / ALTER / UPDATE / INSERT）なし

### フロント移行

- `genka-app.html` `loadData` → `list_genka_reports_secure`（from_date=月初 / to_date=月末 /
  site_id=`siteId||null`）
- token ガード（`gCurrentUser?.session_token` 未取得時 return）・error ガード
  （`console.error('原価日報取得エラー:', reportsError)` → return）追加
- 後続の原価集計処理（`reps.forEach` の労務/外注/ダンプ/警備の按分・集計、
  invoices / site_budgets / machines / employee_rates / unit_rates 取得）は無改修
- 移行後、`genka-app.html` の `from('report_summary')` は 0 件、`list_genka_reports_secure` は 1 件

### 本番反映

- PR #27 merge 済み（merge commit：`d78005d`）
- 本番反映確認：Network に `list_genka_reports_secure`（status 200）あり、
  `report_summary` は `[]`（direct read）で出ない

### DB 確認（事後確認 I〜M）

- I：関数存在・SECURITY DEFINER=true・`search_path = public, extensions`・
  args=(session_token_input text, from_date_input date, to_date_input date, site_id_input uuid)：OK
- J：EXECUTE = anon / authenticated / service_role：OK ／ J-2：PUBLIC EXECUTE なし（proacl）：OK
- K：関数定義本文に report_summary 実SQL参照なし（from/join public.report_summary = 0 等）：OK
- L：reports 権限 未変更（anon / authenticated 直接 SELECT なし）：OK
- M：report_summary 権限 未変更（anon / authenticated SELECT あり・封鎖は 4-C-4 対象）：OK

### 本番画面確認（動作確認 N）

- 場所：https://system.okaigumi.co.jp/genka（genka 管理者ログイン）
- 原価画面 OK / 月切替 OK / 現場フィルタ OK / 原価サマリー OK（金額・件数異常なし）
- Console から `sb.rpc('list_genka_reports_secure', ...)`：success=true / error=null /
  data=Array(4) / status=200
- Console 赤エラーは favicon.ico 404 のみ（本 RPC と無関係）

### 触らなかったもの

- `report_summary` View（4-C-4 で封鎖・SELECT REVOKE 予定）
- `reports` 権限 / policy
- 既存 `list_admin_reports_secure`（4-C-2）
- `index.html` / `admin-app.html`

### 次工程

- 4-C-4：`report_summary` View 封鎖・不要 GRANT 整理（anon/authenticated SELECT の REVOKE）。
  4-C-2 / 4-C-3 の RPC はいずれも View 非依存のため、封鎖後も動作する想定
- （4-C-4 の直前〜直後で Playwright による動的確認の導入を検討）

### SQL記録ファイル

- `docs/sql/phase4c-3-genka-reports-read-rpc.sql`

---

## 2026-07-02 Phase 4-C-4 report_summary View 封鎖・不要 GRANT 整理 完了

### 目的

- `report_summary` View への `anon` / `authenticated` の直接アクセス権を全て REVOKE し、
  フロントからの View 直参照経路を封鎖する。
- 管理者 / 原価 / 本人日報の読み取りは既に read RPC 3本（SECURITY DEFINER）へ移行済みのため、
  View 直参照は不要。View 自体は DROP せず存続させる。

### 方針（確定）

- View は DROP しない。`report_summary` View 自体は残す。
- `postgres` はそのまま（変更しない）。
- `service_role` はそのまま（保守用に SELECT 等を温存）。
- `anon` / `authenticated` から `report_summary` の権限を全 REVOKE する。
- 実行 SQL は REVOKE のみ。GRANT はロールバック案としてコメントに記載。

### 実行済み DB 変更（`docs/sql/phase4c-4-report-summary-revoke.sql` を Supabase SQL Editor で実行・2026-07-02）

```sql
REVOKE ALL PRIVILEGES ON public.report_summary FROM anon;
REVOKE ALL PRIVILEGES ON public.report_summary FROM authenticated;
```

- 実行結果：Success. No rows returned（各文）
- 危険SQL（DROP / DELETE / TRUNCATE / ALTER / UPDATE / INSERT）なし。変更行は REVOKE 2本のみ。

### PUBLIC 対応

- 実測で `report_summary` の relacl に PUBLIC エントリ（先頭が `=` の項目）は存在せず、
  PUBLIC への明示付与なし。
- そのため `REVOKE SELECT ON public.report_summary FROM PUBLIC;` は **実行していない**
  （no-op のため実行対象外）。SQLファイル内ではコメントアウトのまま維持。

### DB 事後確認結果

- `report_summary` の relacl：`{postgres=arwdDxtm/postgres, service_role=arwdDxtm/postgres}`
  - anon / authenticated の項目が relacl から消滅（REVOKE 成功）
  - postgres / service_role は `arwdDxtm` のまま残存（保守用に温存）
- anon：SELECT 不可 ／ authenticated：SELECT 不可
- postgres：SELECT 可 ／ service_role：SELECT 可
- 下流 View 依存：0 件（変化なし）
- RPC 3本は SECURITY DEFINER かつ `report_summary` 実参照なし（維持）：
  - `list_admin_reports_secure`
  - `list_genka_reports_secure`
  - `list_my_reports_secure`
- `report_summary` View は DROP せず存続（relkind=v）

### 本番画面確認（2026-07-02）

- 従業員画面：OK
- 管理者ログイン：OK ／ 管理タブ：OK ／ 集計タブ：OK ／ 月切替：OK ／
  現場ドリルダウン：OK ／ CSV 出力：OK
- 原価画面：OK ／ 原価 月切替：OK ／ 原価 現場フィルタ：OK ／ 原価サマリー：OK
- Network に `report_summary`（View 直参照）：なし
- Network に `list_genka_reports_secure`（RPC 経由）：あり
- Console 赤エラー：なし

### 触らなかったもの

- `report_summary` View 定義（DROP せず存続）
- `postgres` / `service_role` の権限（保守用に温存）
- `reports` 権限 / policy
- read RPC 3本の定義（`list_admin_reports_secure` / `list_genka_reports_secure` /
  `list_my_reports_secure`）
- `index.html` / `admin-app.html` / `genka-app.html` のコード

### 申し送り（Phase 4-C-4 とは別タスク）

- 集計タブ（index.html 管理コンソール）の CSV 出力は今回 OK だが、今後は不要にしたい。
  CSV 出力は管理コンソール側のみに集約する方針。
  → Phase 4-C-4 の範囲外。`docs/roadmap.md` の候補へ記録。

### 次工程

- Phase 4-C 系（4-C-1〜4-C-4）完了後の整理。
- Playwright による読み取り専用スモークテスト導入の検討。

### SQL記録ファイル

- `docs/sql/phase4c-4-report-summary-revoke.sql`（実行済み記録へ更新済み）

## 2026-07-02 Phase 4-C-5 reports 残存不要権限（TRUNCATE / REFERENCES / TRIGGER）REVOKE 完了

### 目的

- `public.reports` に残っていた `anon` / `authenticated` の非読み取り不要権限
  （TRUNCATE / REFERENCES / TRIGGER）を REVOKE する。
- SELECT / INSERT / UPDATE / DELETE は既に遮断済み（Phase 4-C-1 ほか）。本整理は
  それらの遮断後に残っていた TRUNCATE / REFERENCES / TRIGGER の除去のみ。
- 日報カレンダー MVP の読み取りブロッカーではないが、Phase 4-C 補整理として先に対応。

### 背景（Phase 4-C 完了後のライブ確認結果）

- `report_summary`：anon / authenticated ともに全権限 false（残存なし・4-C-4 で対応済み）。
- `reports`：anon / authenticated ともに SELECT/INSERT/UPDATE/DELETE=false だが、
  TRUNCATE / REFERENCES / TRIGGER = true が残存していた。

### 方針（確定）

- 実行 SQL は REVOKE 1本のみ。
- `report_summary` / RPC / policy / `postgres` / `service_role` は一切変更しない。
- `index.html` / `admin-app.html` / `genka-app.html` は変更しない。

### 実行済み SQL（`docs/sql/phase4c-5-reports-extra-privileges-revoke.sql` を Supabase SQL Editor で実行・2026-07-02）

```sql
revoke truncate, references, trigger on table public.reports from anon, authenticated;
```

- 実行結果：Success. No rows returned
- 危険SQL（DROP / DELETE / TRUNCATE / ALTER / UPDATE / INSERT / CREATE）なし。変更は REVOKE 1本のみ。

### 実行前確認結果（ユーザー提供・2026-07-02）

```text
role_name,object_name,can_select,can_insert,can_update,can_delete,can_truncate,can_references,can_trigger
anon,public.report_summary,false,false,false,false,false,false,false
authenticated,public.report_summary,false,false,false,false,false,false,false
anon,public.reports,false,false,false,false,true,true,true
authenticated,public.reports,false,false,false,false,true,true,true
```

- `reports`：anon / authenticated ともに can_truncate=true / can_references=true / can_trigger=true（要除去）。
- `report_summary`：全 false（対象外・確認のみ）。

### 実行後確認結果（Supabase SQL Editor・2026-07-02）

```text
role_name,object_name,can_select,can_insert,can_update,can_delete,can_truncate,can_references,can_trigger
anon,public.reports,false,false,false,false,false,false,false
authenticated,public.reports,false,false,false,false,false,false,false
```

- `reports`：anon / authenticated ともに全 7 種 false（SELECT/INSERT/UPDATE/DELETE は従来どおり遮断、TRUNCATE/REFERENCES/TRIGGER の残存を除去）。期待どおり。

### 触らないもの

- `report_summary`（既に全 REVOKE 済み）
- read RPC 5本 / write RPC / policy
- `postgres` / `service_role` の権限
- フロント（`index.html` / `admin-app.html` / `genka-app.html`）

### SQL記録ファイル

- `docs/sql/phase4c-5-reports-extra-privileges-revoke.sql`（実行済み記録へ更新済み）

## 2026-07-02 Phase 4-D 有休CSV出力 secure RPC 追加（★実行済み★）

### 目的

- 社内確認用 月次稼働・日報詳細（CSV viewer）で「有休表示」「残有給表示」を行うための CSV 出力用 read RPC を2本追加する
- 直接テーブル権限を増やさず、RPC EXECUTE のみで有休データを取得できる構造にする
- CSV 整形はフロント責務とし、RPC は jsonb エンベロープ `{ meta, warnings, rows }` を返す（既存 export 系と同型）

### 実行ステータス

- **実行済み**（2026-07-02）。Supabase SQL Editor で本番反映済み。
  - 事後確認 D：関数2本存在・`security_definer=true`・`config=search_path=public, extensions`・引数想定どおり。
  - 事後確認 E：両関数とも `anon` / `authenticated` に EXECUTE あり。`PUBLIC` なし。
  - 事後確認 E-2：`proacl` は `{postgres=X,anon=X,authenticated=X,service_role=X}`（すべて `/postgres`）。先頭空の `=X/postgres`（PUBLIC EXECUTE）なし。
  - 事後確認 F：既存有休RPC 5本＋追加2本＝計7本が存在、すべて `security_definer=true`。

### 追加するSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/phase4d-paid-leave-export-rpc.sql` | 有休CSV出力 RPC 2本（事前確認 / CREATE・REVOKE・GRANT / 事後確認） |

### 追加する関数（2本）

| 関数名 | 期間 | 粒度 | 用途 |
|---|---|---|---|
| `export_paid_leave_details_secure(text, date, date)` | あり | 有休1件/行 | 承認済み有休の明細（paid_leave_details.csv） |
| `export_paid_leave_balances_secure(text)` | なし | 従業員1人/行 | 残有給スナップショット（paid_leave_balances.csv） |

- 両関数とも `SECURITY DEFINER` / `SET search_path = public, extensions`
- CREATE 時デフォルトの PUBLIC EXECUTE を REVOKE し、`anon` / `authenticated` にのみ GRANT（既存 export 系に合わせ service_role は付与しない）
- テーブルへの GRANT / REVOKE なし。helper `csv_export_fiscal_year(date, integer)` を再利用（新規 helper なし）

### 管理者検証（既存 export 4本との差異）

- 既存 export 4本（`csv-export-secure-rpc.sql`）は **admin_sessions 単経路**。
- 本2本は有休系 RPC として `list_paid_leave_admin_secure` と同型の **二経路検証** を採用：
  - a. `employee_sessions` + `employees.role = 'admin'`
  - b. `admin_sessions` + `genka_admins.is_active = true`
  - どちらも不成立なら `RAISE EXCEPTION 'Invalid or expired session'`。
- この差異は本エントリと PR 本文に明記する。

### 列・対象者ポリシー

- `paid_leave_details`：列 `employee_id, employee_name, leave_date, fiscal_year, leave_type, status`。`reason` は含めない。`leave_type` は生値（full/am/pm、表示ラベルは閲覧側で変換）。`status='approved'` のみ。履歴保持のため `employees.is_active` では絞らない。
- `paid_leave_balances`：列 `employee_id, employee_name, granted_total, used_total, remaining`。`granted_total`=付与の全年度合計、`used_total`=承認済みの full=1.0 / am,pm=0.5 合計、`remaining`=差。対象は `e.is_active = true` かつ付与または承認済み有休を持つ従業員（`role='admin'` は除外しない）。残有給は全期間累積のため期間フィルタしない。

### 触らないもの

- 既存 export 4本 / helper 2本
- 有休系 既存 RPC 5本（`create_/review_/save_/list_my_/list_paid_leave_admin_`）
- `paid_leave_requests` / `paid_leave_grants` のテーブル権限・policy
- フロント（`index.html` / `genka-app.html`）／CSV viewer（本エントリでは変更なし・PR-B で対応）

### 併せて実施（PR-A・DB非依存の同梱変更）

- `admin-app.html`：ZIP 出力の `CSV_COLUMNS` に `paid_leave_details` / `paid_leave_balances` を追加、`exportCsvZip` の specs に2本追加（details=period:true / balances=period:false）。ZIP は 6CSV 構成（manifest 1.0 後方互換）。

### 影響範囲

- DB：新規 RPC 2本追加のみ。既存テーブル・RPC・policy・権限・helper は不変。
- admin-app.html：ZIP に2本追加。既存4CSV・個別出力・manifest 形式は不変（後方互換）。旧ZIP（4CSV）読込も従来どおり。

---

## 2026-07-03 Phase 4-D-1a 単価系 read RPC 追加（★実行済み★）

### 目的

- `unit_rates`（単価）/ `employee_rates`（従業員日給）の管理画面 direct SELECT を、将来 secure read RPC 経由へ移行するための前段として、read RPC を2本追加する
- Phase 4-D（financial系 読み取り保護）の最初の実施項目（4-D-1 単価系）
- この段では **read RPC 追加のみ**。SELECT REVOKE はしない（新旧併存）

### 実行ステータス

- **実行済み**（2026-07-03）。Supabase SQL Editor で本番反映済み。
  - 実行：CREATE FUNCTION ×2 / REVOKE EXECUTE FROM PUBLIC ×2 / GRANT EXECUTE TO anon,authenticated,service_role ×2（すべて Success. No rows returned）
  - 事前確認 A-1：`_verify_management_session` 存在・`SECURITY DEFINER=true`・`search_path=public, extensions`
  - 事前確認 A-2：ヘルパーの `anon`/`authenticated`/`public` 直接 EXECUTE なし（0行）
  - 事前確認 B：戻り型が設計と一致
    - `employee_rates`：`daily_rate=integer/int4` / `effective_from=date` / `employee_id=uuid` / `id=uuid`
    - `unit_rates`：`category/name/unit=text` / `id=uuid` / `unit_price=integer/int4` / `updated_at=timestamp with time zone/timestamptz`
  - 事前確認 C：`list_unit_rates_secure` / `list_employee_rates_secure` 事前 0行（新規）
  - 事前確認 D：`unit_rates` / `employee_rates` とも `anon`/`authenticated` SELECT 残存（4行）
  - 事後確認 F：2関数とも存在・`SECURITY DEFINER=true`・`search_path=public, extensions`
  - 事後確認 G：EXECUTE = 2関数 ×（anon/authenticated/service_role）＝6行
  - 事後確認 G-2：PUBLIC EXECUTE なし（`proacl` は postgres/anon/authenticated/service_role のみ）
  - 事後確認 H：`unit_rates` / `employee_rates` の `anon`/`authenticated` SELECT は引き続き残存（4行）＝REVOKE 未実施

### 追加したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/phase4d-1a-rates-read-rpc.sql` | 単価系 read RPC 2本（事前確認A〜D / CREATE・REVOKE・GRANT / 事後確認F〜H） |

### 追加した関数（2本）

| 関数名 | 戻り列 | 並び |
|---|---|---|
| `list_unit_rates_secure(text)` | `id, category, name, unit_price, unit, updated_at`（全行） | `ORDER BY category, name` |
| `list_employee_rates_secure(text)` | `id, employee_id, daily_rate, effective_from`（全行・多世代履歴） | `ORDER BY employee_id, effective_from DESC` |

- 両関数とも `SECURITY DEFINER` / `SET search_path = public, extensions`
- 認可は既存ヘルパー `public._verify_management_session(text)` を `PERFORM` で再利用（admin_sessions+genka_admins OR employee_sessions role=admin の二経路。不正/期限切れは helper 内で RAISE）。同一対象テーブルの write RPC（`upsert_unit_rate_secure` / `upsert_employee_rate_secure`）と同じヘルパー
- CREATE 時デフォルトの PUBLIC EXECUTE を REVOKE し、`anon` / `authenticated` / `service_role` に GRANT
- `employee_rates` は全行返し（従業員ごと最新採用はフロント側ロジックに委譲）

### 触らないもの / この段の状態

- **SELECT REVOKE 未実施**：`unit_rates` / `employee_rates` の `anon`/`authenticated` 直接 SELECT は残存。**新旧併存**状態
- 既存 write RPC・helper `_verify_management_session`・RLS・policy・他テーブル・Storage は不変（additive-only）
- フロント（`admin-app.html` / `genka-app.html`）は未変更

### 次工程

- 4-D-1b：フロント移行（`genka-app.html` startApp、`admin-app.html` startApp / pageRates の計5箇所の direct SELECT を read RPC へ置換）→ PR → merge → 本番反映確認（Network に `list_*_secure` あり / direct SELECT なし）
- 4-D-1c：本番で RPC 経由を確認した後に `unit_rates` / `employee_rates` の `anon`/`authenticated` 直接 SELECT を REVOKE（別ファイル・別段階）

### 影響範囲

- DB：新規 RPC 2本追加のみ。既存テーブル・RPC・policy・権限・helper は不変。
- フロント：変更なし（本エントリでは HTML 無改変）。

---

## 2026-07-03 Phase 4-D-1c 単価系 SELECT REVOKE（★実行済み★）

### 目的

- 4-D-1a（read RPC 追加）・4-D-1b（フロント移行・本番 Network 確認 OK）を経て、`unit_rates` / `employee_rates` の `anon` / `authenticated` 直接 SELECT を REVOKE し、読み取りを secure read RPC 経由に一本化する
- Phase 4-D-1（単価系 読み取り保護）の最終段。これにより 4-D-1 完了

### 実行ステータス

- **実行済み**（2026-07-03）。Supabase SQL Editor で本番反映済み。
  - 実行SQL：
    - `REVOKE SELECT ON TABLE public.unit_rates FROM anon, authenticated;` → Success. No rows returned
    - `REVOKE SELECT ON TABLE public.employee_rates FROM anon, authenticated;` → Success. No rows returned
  - 事前確認 A〜E：すべて合格
    - A：両テーブルとも anon/authenticated に SELECT 残存（REVOKE前）・INSERT/UPDATE なし。**PUBLIC に SELECT なし → PUBLIC 向け REVOKE は未実行**
    - B：read RPC 2本 存在・`security_definer=true`・`search_path=public, extensions`
    - C：read RPC 2本 EXECUTE = anon/authenticated/service_role・PUBLIC なし
    - D：write RPC 2本（`upsert_unit_rate_secure` / `upsert_employee_rate_secure`）存在
    - E：RLS 有効・policy 現状把握（変更しない）
  - 事後確認 F〜J：すべて合格
    - F：unit_rates / employee_rates の anon/authenticated SELECT 消滅
    - G：read RPC 2本 EXECUTE 維持（anon/authenticated/service_role・PUBLIC なし）
    - H：read RPC 2本 `security_definer=true`・`search_path=public, extensions` 維持
    - I：write RPC 2本 不変で存在
    - J：RLS 有効のまま・policy 不変

### 本番 Network 確認（REVOKE 後）

- genka：`list_unit_rates_secure` / `list_employee_rates_secure` あり（200）、`unit_rates?select` / `employee_rates?select` なし、画面表示OK、Console 赤エラーなし
- admin：同上（両 read RPC 200・direct SELECT なし・表示OK・赤エラーなし）

### 実行したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/phase4d-1c-rates-select-revoke.sql` | 事前確認A〜E / REVOKE SELECT ×2 / 事後確認F〜J / ロールバック（GRANT・コメントアウト） |

### 触らなかったもの

- read RPC / write RPC の EXECUTE 権限（維持）
- `service_role` / `postgres`(owner) の権限（維持）
- RLS 有効状態・既存 policy（変更なし。policy 整理は別工程候補）
- helper `_verify_management_session`（非公開のまま不変）
- `unit_rates` / `employee_rates` 以外のテーブル

### 影響範囲

- DB：`unit_rates` / `employee_rates` の anon/authenticated 直接 SELECT を REVOKE のみ。DROP POLICY / ALTER TABLE / DML / 他テーブル変更なし。
- フロント：変更なし（HTML 無改変。読み取りは 4-D-1b で既に read RPC 経由に移行済み）。
- これにより **Phase 4-D-1（単価系 読み取り保護）完了**。以降は 4-D-2 予算（`site_budgets`）／4-D-3 請求書（`invoices`）。

---

## 2026-07-03 Phase 4-D-2a site_budgets read RPC 追加（★実行済み★）

### 目的

- `site_budgets`（現場予算）の管理画面 direct SELECT を、将来 secure read RPC 経由へ移行するための前段として、read RPC を2本追加する
- Phase 4-D（financial系 読み取り保護）の 4-D-2（予算）の最初の実施項目
- この段では **read RPC 追加のみ**。SELECT REVOKE はしない（新旧併存）

### 実行ステータス

- **実行済み**（2026-07-03）。Supabase SQL Editor で本番反映済み。
  - 実行：CREATE FUNCTION ×2 / REVOKE EXECUTE FROM PUBLIC ×2 / GRANT EXECUTE TO anon,authenticated,service_role ×2（すべて Success. No rows returned）
  - 事前確認 A：`_verify_management_session` 存在・`SECURITY DEFINER=true`・`search_path=public, extensions`
  - 事前確認 A-2：ヘルパーの `anon`/`authenticated`/`public` 直接 EXECUTE なし（0行）
  - 事前確認 B：戻り型が設計と一致
    - `site_budgets`：`id=uuid` / `site_id=uuid`（NOT NULL）／`year=integer/int4`・`budget=integer/int4`・`is_active=boolean/bool`・`updated_at=timestamp with time zone/timestamptz`（NOT NULL）／`month=integer/int4`・`memo=text`（nullable）
  - 事前確認 C：`list_site_budgets_secure` / `get_site_budget_secure` 事前 0行（新規）
  - 事前確認 D：`site_budgets` の `anon`/`authenticated` SELECT 残存（併存ベースライン）
  - 事後確認 F：2関数とも存在・`SECURITY DEFINER=true`・`search_path=public, extensions`
  - 事後確認 G：EXECUTE = 2関数 ×（anon/authenticated/service_role）＝6行
  - 事後確認 G-2：PUBLIC EXECUTE なし（`proacl` は postgres/anon/authenticated/service_role のみ）
  - 事後確認 H：`site_budgets` の `anon`/`authenticated` SELECT は引き続き残存＝REVOKE 未実施

### 実行したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/phase4d-2a-site-budgets-read-rpc.sql` | site_budgets read RPC 2本（事前確認A〜D / CREATE・REVOKE・GRANT / 事後確認F〜H） |

### 追加した関数（2本）

| 関数名 | 戻り列 | 絞り込み / 並び |
|---|---|---|
| `list_site_budgets_secure(text, boolean, uuid, integer, boolean)` | `id, site_id, year, month, budget, memo, is_active, updated_at` | 引数 `is_active_input` / `site_id_input` / `year_input` / `annual_only_input` で絞り込み・`ORDER BY year DESC, updated_at DESC` |
| `get_site_budget_secure(text, uuid)` | 同上 | `WHERE id = id_input`（該当なしは 0 行） |

- 両関数とも `SECURITY DEFINER` / `SET search_path = public, extensions`
- 認可は既存ヘルパー `public._verify_management_session(text)` を `PERFORM` で再利用（admin_sessions+genka_admins OR employee_sessions role=admin の二経路。不正/期限切れは helper 内で RAISE）。Phase 4-D-1 の read RPC と同型
- CREATE 時デフォルトの PUBLIC EXECUTE を REVOKE し、`anon` / `authenticated` / `service_role` に GRANT
- `annual_only_input`（boolean DEFAULT false）：`false`/`NULL`＝month 条件なし（全 month）／`true`＝`month IS NULL`（年間予算のみ）。条件式 `(COALESCE(annual_only_input, false) = false OR sb.month IS NULL)`。genka の「現場×年度」「年度集計」で年間予算のみを DB 側で絞るために追加

### 触らないもの / この段の状態

- **SELECT REVOKE 未実施**：`site_budgets` の `anon`/`authenticated` 直接 SELECT は残存。**新旧併存**状態
- 既存 write RPC（`upsert_site_budget_secure` / `update_site_budget_secure` / `deactivate_site_budget_secure` / `restore_site_budget_secure`）・helper `_verify_management_session`・RLS・policy・他テーブル・Storage は不変（additive-only）
- フロント（`admin-app.html` / `genka-app.html`）は未変更

### 次工程

- 4-D-2b：フロント移行（`admin-app.html` pageBudgets①② / openBudgetModal③、`genka-app.html` openBudgetModal④ / 原価サマリ集計⑤ の計5箇所の direct SELECT を read RPC へ置換）→ PR → merge → 本番反映確認（Network に `list_site_budgets_secure` / `get_site_budget_secure` あり / `site_budgets?select` なし）
- 4-D-2c：本番で RPC 経由を確認した後に `site_budgets` の `anon`/`authenticated` 直接 SELECT を REVOKE（別ファイル・別段階）

### 影響範囲

- DB：新規 RPC 2本追加のみ。既存テーブル・RPC・policy・権限・helper は不変。
- フロント：変更なし（本エントリでは HTML 無改変）。

---

## 2026-07-04 Phase 4-D-2c site_budgets SELECT REVOKE（★実行済み★）

### 目的

- 4-D-2a（read RPC 追加）・4-D-2b（フロント移行・本番 Network 確認 OK）を経て、`site_budgets`（現場予算）の `anon` / `authenticated` 直接 SELECT を REVOKE し、読み取りを secure read RPC 経由に一本化する
- Phase 4-D-2（予算 `site_budgets` 読み取り保護）の最終段。これにより 4-D-2 完了

### 実行ステータス

- **実行済み**（2026-07-04）。Supabase SQL Editor で本番反映済み（Claude Code CLI からの DB 接続・Supabase CLI 使用なし）。
  - 実行SQL：
    - `REVOKE SELECT ON TABLE public.site_budgets FROM anon, authenticated;` → Success. No rows returned
  - 事前確認 A〜E：すべて合格
    - A：anon/authenticated に SELECT 残存（REVOKE前）・INSERT/UPDATE/DELETE なし。**PUBLIC に SELECT なし → PUBLIC 向け REVOKE は未実行**
    - B：read RPC 2本（`list_site_budgets_secure` / `get_site_budget_secure`）存在・`security_definer=true`・`search_path=public, extensions`
    - C：read RPC 2本 EXECUTE = anon/authenticated/service_role（6行）・PUBLIC なし
    - D：write RPC 4本（`upsert_site_budget_secure` / `update_site_budget_secure` / `deactivate_site_budget_secure` / `restore_site_budget_secure`）存在・`security_definer=true`・`search_path=public, extensions`
    - E：RLS 有効（`relrowsecurity=true` / `relforcerowsecurity=false`）・policy（`anon_can_update_site_budgets` / `sb_read` / `sb_update` / `sb_write`）現状把握（変更しない）
  - 事後確認 F〜J：すべて合格
    - F：`site_budgets` の anon/authenticated SELECT 消滅（PUBLIC も無し・想定外DML権限なし）
    - G：read RPC 2本 EXECUTE 維持（anon/authenticated/service_role・PUBLIC なし）
    - H：read RPC 2本 `security_definer=true`・`search_path=public, extensions` 維持
    - I：write RPC 4本 不変で存在
    - J：RLS 有効のまま・policy 4本 不変

### 本番 Network 確認（REVOKE 後）

- admin：予算 active/inactive 一覧で `list_site_budgets_secure`、編集モーダルで `get_site_budget_secure` が出る（追加モーダルは RPC 呼び出しなし）。`site_budgets?select` なし・画面表示OK・Console 赤エラーなし・401/403 なし
- genka：原価サマリ・予算モーダルで `list_site_budgets_secure` が出る。`site_budgets?select` なし・表示OK・赤エラーなし・401/403 なし
- ※ genka 予算モーダルの表示位置が低い件は RPC/REVOKE とは無関係の UI 改善候補として切り離し（別工程）

### 実行したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/phase4d-2c-site-budgets-select-revoke.sql` | 事前確認A〜E / REVOKE SELECT（anon,authenticated）/ 事後確認F〜J / ロールバック（GRANT・コメントアウト）/ PUBLIC REVOKE（コメントアウト・検出時は停止確認） |

### 触らなかったもの

- read RPC（`list_site_budgets_secure` / `get_site_budget_secure`）/ write RPC 4本の EXECUTE 権限（維持）
- `service_role` / `postgres`(owner) の権限（維持）
- RLS 有効状態・既存 policy（変更なし。policy 整理は別工程候補）
- helper `_verify_management_session`（非公開のまま不変）
- `site_budgets` 以外のテーブル
- PUBLIC 向け SELECT（事前A で検出なし＝REVOKE 対象外）・ロールバック GRANT（未実行）

### 影響範囲

- DB：`site_budgets` の anon/authenticated 直接 SELECT を REVOKE のみ。DROP POLICY / ALTER TABLE / DML / 他テーブル変更なし。
- フロント：変更なし（HTML 無改変。読み取りは 4-D-2b で既に read RPC 経由に移行済み）。
- これにより **Phase 4-D-2（予算 `site_budgets` 読み取り保護）完了**。以降は 4-D-3 請求書（`invoices`）。

---

## 2026-07-04 Phase 4-D-3a invoices read RPC 追加（★実行済み★）

### 目的

- `invoices`（請求書）の管理画面 direct SELECT を、将来 secure read RPC 経由へ移行するための前段として、read RPC を2本追加する
- Phase 4-D（financial系 読み取り保護）の 4-D-3（請求書）の最初の実施項目
- この段では **read RPC 追加のみ**。SELECT REVOKE はしない（新旧併存）

### 実行ステータス

- **実行済み**（2026-07-04）。Supabase SQL Editor で本番反映済み（Claude Code CLI からの DB 接続・Supabase CLI 使用なし）。
  - 実行：CREATE FUNCTION ×2 / REVOKE EXECUTE FROM PUBLIC ×2 / GRANT EXECUTE TO anon,authenticated,service_role ×2（すべて Success. No rows returned）
  - 事前確認 A-1：`_verify_management_session` 存在・`prosecdef=true`・`proconfig=["search_path=public, extensions"]`
  - 事前確認 A-2：ヘルパーの `anon`/`authenticated`/`PUBLIC` 直接 EXECUTE なし（0行）
  - 事前確認 B：`invoices` 実型が設計と一致
    - `amount=integer/int4`（NOT NULL）／`invoice_date=date`（NOT NULL）／`tax_included=boolean/bool`（NOT NULL）／`id=uuid`（NOT NULL）／`status=text`（NOT NULL）／`category=text`（NOT NULL）／`vendor_name=text`（NOT NULL）／`site_id=uuid`（nullable）／`description=text`・`memo=text`（nullable）
    - → `invoice_date=date`・`amount=integer`・`tax_included=boolean` を確認し `RETURNS TABLE` 修正不要。`status`/`category` は `::text` で正規化して返す方針どおり
  - 事前確認 C：`list_invoices_secure` / `get_invoice_secure` 事前 0行（新規）
  - 事前確認 D：`invoices` の `anon`/`authenticated` SELECT 残存（併存ベースライン）
  - 事後確認 F：2関数とも存在・`prosecdef=true`・`search_path=public, extensions`
  - 事後確認 G：EXECUTE = 2関数 ×（anon/authenticated/service_role）＝6行
  - 事後確認 G-2：PUBLIC EXECUTE なし（0行）
  - 事後確認 H：`invoices` の `anon`/`authenticated` SELECT は引き続き残存＝REVOKE 未実施

### 実行したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/phase4d-3a-invoices-read-rpc.sql` | invoices read RPC 2本（事前確認A〜D / CREATE・REVOKE・GRANT / 事後確認F〜H・G-2） |

### 追加した関数（2本）

| 関数名 | 戻り列 | 絞り込み / 並び |
|---|---|---|
| `list_invoices_secure(text, text[], text, date, date, uuid, integer)` | `id, invoice_date, site_id, vendor_name, category, amount, tax_included, description, memo, status` | 引数 `statuses_input`（`status::text = ANY`）/ `exclude_status_input`（`status::text <>`）/ `date_from_input` / `date_to_input`（`invoice_date` 範囲）/ `site_id_input` で絞り込み・`ORDER BY invoice_date DESC` ・`LIMIT limit_input`（NULL=全件） |
| `get_invoice_secure(text, uuid)` | 同上 | `WHERE id = id_input`（該当なしは 0 行） |

- 両関数とも `SECURITY DEFINER` / `SET search_path = public, extensions`
- 認可は既存ヘルパー `public._verify_management_session(text)` を `PERFORM` で再利用（admin_sessions+genka_admins OR employee_sessions role=admin の二経路。不正/期限切れは helper 内で RAISE）。Phase 4-D-1 / 4-D-2 の read RPC と同型
- CREATE 時デフォルトの PUBLIC EXECUTE を REVOKE し、`anon` / `authenticated` / `service_role` に GRANT
- `status`・`category` は enum / USER-DEFINED 型化された場合の戻り型不一致を避けるため、比較・戻り値とも `::text` で正規化（今回の実型は両方 `text`）。`statuses_input` と `exclude_status_input` は原則どちらか一方のみ指定（両条件 AND 結合）
- 戻り列は実使用10列に限定（`company_id` / `created_at` は現行フロント未使用のため含めない）

### 触らないもの / この段の状態

- **SELECT REVOKE 未実施**：`invoices` の `anon`/`authenticated` 直接 SELECT は残存。**新旧併存**状態
- 既存 write RPC（`create_invoice_secure` / `update_invoice_secure` / `reject_invoice_secure` / `restore_invoice_secure` ほか・admin_sessions 単経路検証）・helper `_verify_management_session`・RLS・policy・他テーブル・Storage は不変（additive-only）
- フロント（`admin-app.html` / `genka-app.html`）は未変更

### 次工程

- 4-D-3b：フロント移行（`admin-app.html` pageInvoices active/rejected・openInvoiceModal、`genka-app.html` loadInvoices・editInvoice・loadData 集計 の計6箇所の direct SELECT を read RPC へ置換）→ token/error ガード追加（.single() 廃止）→ PR → merge → 本番反映確認（Network に `list_invoices_secure` / `get_invoice_secure` あり / `invoices?select` なし）
- 4-D-3c：本番で RPC 経由を確認した後に `invoices` の `anon`/`authenticated` 直接 SELECT を REVOKE（別ファイル・別段階）

### 影響範囲

- DB：新規 RPC 2本追加のみ。既存テーブル・RPC・policy・権限・helper は不変。
- フロント：変更なし（本エントリでは HTML 無改変）。

---

## 2026-07-04 Phase 4-D-3c invoices SELECT REVOKE（★実行済み★）

### 目的

- 4-D-3a（read RPC 追加）・4-D-3b（フロント移行・本番 Network 確認 OK）を経て、`invoices`（請求書）の `anon` / `authenticated` 直接 SELECT を REVOKE し、読み取りを secure read RPC 経由に一本化する
- Phase 4-D-3（請求書 `invoices` 読み取り保護）の最終段。これにより 4-D-3 完了

### 実行ステータス

- **実行済み**（2026-07-04）。Supabase SQL Editor で本番反映済み（Claude Code CLI からの DB 接続・Supabase CLI 使用なし）。
  - 実行SQL：
    - `REVOKE SELECT ON TABLE public.invoices FROM anon, authenticated;` → Success. No rows returned
  - 事前確認 A〜E：すべて合格
    - A：anon/authenticated に SELECT 残存（REVOKE前）・INSERT/UPDATE/DELETE なし。**PUBLIC に SELECT なし → PUBLIC 向け REVOKE は未実行**
      - ※ `REFERENCES` / `TRIGGER` / `TRUNCATE` は anon/authenticated に残存。ただし `invoices` 固有ではなく `employee_rates` / `unit_rates` / `site_budgets` にも共通の**既存横断パターン**のため、今回の SELECT REVOKE とは分離し「後日の権限棚卸し候補」として扱う（本工程の対象外）
    - B：read RPC 2本（`list_invoices_secure` / `get_invoice_secure`）存在・`security_definer=true`・`search_path=public, extensions`
    - C：read RPC 2本 EXECUTE = anon/authenticated/service_role（6行）・PUBLIC なし（0行）
    - D：write RPC 4本（`create_invoice_secure` / `update_invoice_secure` / `reject_invoice_secure` / `restore_invoice_secure`）存在・`security_definer=true`・`search_path=public, extensions`
    - E：RLS 有効（`relrowsecurity=true` / `relforcerowsecurity=false`）・policy（`inv_read`(SELECT) / `inv_update`(UPDATE) / `inv_write`(INSERT)）現状把握（変更しない）
  - 事後確認 F〜J：すべて合格
    - F：`invoices` の anon/authenticated SELECT 消滅（PUBLIC も無し・INSERT/UPDATE/DELETE なし）。`REFERENCES`/`TRIGGER`/`TRUNCATE` は事前A と同じく残存（既存横断パターン・今回対象外）
    - G：read RPC 2本 EXECUTE 維持（anon/authenticated/service_role・PUBLIC なし）
    - H：read RPC 2本 `security_definer=true`・`search_path=public, extensions` 維持
    - I：write RPC 4本 不変で存在（`security_definer=true`・`search_path=public, extensions`）
    - J：RLS 有効のまま・policy 3本（`inv_read` / `inv_update` / `inv_write`）不変

### 本番 Network 確認（REVOKE 後）

- admin：A-1 通常一覧・A-2 取消済み一覧で `list_invoices_secure`（200）、A-3 編集モーダルで `get_invoice_secure`（200）。`invoices?select` なし・表示OK・Console 赤エラーなし・401/403 なし・HTTP 400 なし
  - ※ A-1 の初回 HTTP 400 は管理セッション期限切れが原因で、再ログイン後に解消（REVOKE 起因ではない）
- genka：B-1 月次請求書リスト・B-3 原価サマリ集計で `list_invoices_secure`（200）、B-2 編集モーダルで `get_invoice_secure`（200）。`invoices?select` なし・表示OK・赤エラーなし・401/403 なし・HTTP 400 なし
- ※ 請求書編集モーダルの表示位置が下すぎる件（admin/genka）は RPC/REVOKE とは無関係の UI 改善候補として切り離し（別工程）

### 実行したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/phase4d-3c-invoices-select-revoke.sql` | 事前確認A〜E / REVOKE SELECT（anon,authenticated）/ 事後確認F〜J / ロールバック（GRANT・コメントアウト）/ PUBLIC REVOKE（コメントアウト・検出時は停止確認） |

### 触らなかったもの

- read RPC（`list_invoices_secure` / `get_invoice_secure`）/ write RPC 4本の EXECUTE 権限（維持）
- `service_role` / `postgres`(owner) の権限（維持）
- RLS 有効状態・既存 policy（変更なし。policy 整理は別工程候補）
- helper `_verify_management_session`（非公開のまま不変）
- `invoices` 以外のテーブル
- PUBLIC 向け SELECT（事前A で検出なし＝REVOKE 対象外）・ロールバック GRANT（未実行）
- `REFERENCES` / `TRIGGER` / `TRUNCATE`（financial系4テーブル共通の既存横断パターン・後日の権限棚卸し候補として分離）

### 影響範囲

- DB：`invoices` の anon/authenticated 直接 SELECT を REVOKE のみ。DROP POLICY / ALTER TABLE / DML / 他テーブル変更なし。
- フロント：変更なし（HTML 無改変。読み取りは 4-D-3b で既に read RPC 経由に移行済み）。
- これにより **Phase 4-D-3（請求書 `invoices` 読み取り保護）完了**。

## 2026-07-04 Phase 4-D-4 financial系4テーブル 残存不要権限（TRUNCATE / REFERENCES / TRIGGER）REVOKE 完了（★実行済み★）

### 目的

- financial系4テーブル（`unit_rates` / `employee_rates` / `site_budgets` / `invoices`）に残っていた `anon` / `authenticated` の非読み取り不要権限（TRUNCATE / REFERENCES / TRIGGER）を REVOKE する。
- SELECT / INSERT / UPDATE / DELETE は Phase 4-D-1 / 4-D-2 / 4-D-3 で既に遮断済み・読み取りは secure read RPC 経由に一本化済み。本整理は各段（4-D-1c / 4-D-2c / 4-D-3c）で「後日の権限棚卸し候補」として分離していた TRUNCATE / REFERENCES / TRIGGER の横断的な後片付け。

### 背景（Stage B 調査結果・ユーザーが Supabase SQL Editor で手動確認）

- 権限：4テーブルとも anon/authenticated は SELECT/INSERT/UPDATE/DELETE=false・TRUNCATE/REFERENCES/TRIGGER=true（要除去）。public は全権限 false。
- RLS：4テーブルとも `relrowsecurity=true` / `relforcerowsecurity=false`。
- policy：`employee_rates`=er_read/er_update/er_write、`invoices`=inv_read/inv_update/inv_write、`site_budgets`=anon_can_update_site_budgets/sb_read/sb_update/sb_write、`unit_rates`=ur_read/ur_update/ur_write。
  - ※ `site_budgets.anon_can_update_site_budgets` は既存 policy として残存。ただし anon の direct UPDATE grant は false のため本 REVOKE 判断は止めず、後日の policy 棚卸し候補として記録。
- トリガ：4テーブルともユーザー定義トリガ 0 件。
- FK：`employee_rates→employees` / `invoices→companies,sites` / `site_budgets→companies,sites` / `unit_rates→companies`。financial系を参照先にする FK はなし（＝REFERENCES を REVOKE しても既存 FK に影響なし。REFERENCES は新規 FK 作成権限で、既存 FK 制約は保持）。
- secure RPC：financial系 secure RPC はすべて `prosecdef=true` / `owner=postgres` / `search_path=public, extensions` 固定。

### 方針（確定）

- 実行 SQL は REVOKE のみ（1テーブル1文×4本）。順番：employee_rates → invoices → site_budgets → unit_rates。
- RPC / RLS / policy / `postgres` / `service_role` は一切変更しない。`index.html` / `admin-app.html` / `genka-app.html` も変更しない。

### 実行済み SQL（`docs/sql/phase4d-4-financial-extra-privileges-revoke.sql` を Supabase SQL Editor で実行・2026-07-04）

```sql
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.employee_rates FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.invoices FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.site_budgets FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.unit_rates FROM anon, authenticated;
```

- 実行結果：Success. No rows returned（4本とも）。
- 危険SQL（DROP / DELETE / TRUNCATE 実行 / ALTER / UPDATE / INSERT / CREATE）なし。変更は REVOKE 4本のみ。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし（DB 実行はユーザーが手動）。

### 実行後確認結果（Post-check・Supabase SQL Editor・2026-07-04）

- G（anon / authenticated）：対象4テーブル（`unit_rates` / `employee_rates` / `site_budgets` / `invoices`）とも全権限 false（SELECT/INSERT/UPDATE/DELETE は従来どおり遮断、TRUNCATE/REFERENCES/TRIGGER の残存を除去）。期待どおり。
- G-2（public）：対象4テーブルとも全権限 false（不変・今回 public は未変更）。期待どおり。

### 本番画面確認（Stage E・REVOKE 後）

今回 REVOKE した TRUNCATE / REFERENCES / TRIGGER はフロントの PostgREST クライアントが使わない DDL 系権限のため、画面挙動への影響はなく「リグレッションが出ていないこと」を確認。

- admin：単価マスタ（`list_unit_rates_secure` / `list_employee_rates_secure` 200）・実行予算（`list_site_budgets_secure` / `get_site_budget_secure` 200）・請求書（`list_invoices_secure` / `get_invoice_secure` 200）とも従来どおり。
- genka：単価読込（`list_unit_rates_secure` / `list_employee_rates_secure` 200）・実行予算読込（`list_site_budgets_secure` 200）・請求書/原価サマリ（`list_invoices_secure` / `get_invoice_secure` 200）とも従来どおり。
- 共通：`unit_rates?select=` / `employee_rates?select=` / `site_budgets?select=` / `invoices?select=` の direct access なし。Console 赤エラーなし・HTTP 400 / 401 / 403 なし。

### 実行したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/phase4d-4-financial-extra-privileges-revoke.sql` | 事前確認A〜F / REVOKE TRUNCATE,REFERENCES,TRIGGER（4テーブル・1文ずつ）/ 事後確認G・G-2 / rollback（GRANT・コメントアウト）。STATUS を EXECUTED に更新済み |

### 触らなかったもの

- read RPC / write RPC（定義・EXECUTE・SECURITY DEFINER）
- RLS 有効状態・既存 policy（`site_budgets.anon_can_update_site_budgets` 含む。policy 棚卸しは別工程候補）
- `service_role` / `postgres`(owner) の権限
- SELECT / INSERT / UPDATE / DELETE（既に遮断済み・本工程では未変更）
- フロント（`index.html` / `admin-app.html` / `genka-app.html`）
- rollback GRANT（未実行・コメントアウトのまま）

### 影響範囲

- DB：financial系4テーブルの anon/authenticated の TRUNCATE / REFERENCES / TRIGGER を REVOKE のみ。DROP POLICY / ALTER TABLE / DML / 他テーブル変更なし。
- フロント：変更なし。
- これにより Phase 4-D-3c 以降に残課題としていた「financial系4テーブル共通の TRUNCATE / REFERENCES / TRIGGER 権限棚卸し」を解消。**Phase 4-D-4 完了**。

---

## 2026-07-06 日報無効化 PR-A: reports に無効化カラム追加（★実行済み★）

### 目的

- 日報を物理削除せず「無効化（soft-void）」で扱うための土台として、reports に
  無効化用カラムを additive に追加する。無効化の実処理（admin RPC）と
  read/export の除外は PR-B、管理者UIは PR-C で行う。

### 追加カラム

| カラム | 型 | 既定 | 用途 |
|---|---|---|---|
| `is_voided` | boolean NOT NULL | false | 無効化フラグ |
| `voided_at` | timestamptz | NULL | 無効化日時 |
| `voided_by` | uuid | NULL | 実行管理者の id（FKなし） |
| `voided_by_role` | text | NULL | 出所（employee_admin / genka_admin） |
| `void_reason` | text | NULL | 無効化理由（必須はRPC/CHECKで担保） |

### CHECK 制約

- `reports_void_consistency`：is_voided=false、または（voided_at IS NOT NULL かつ void_reason 非空）
- `reports_voided_by_role_valid`：voided_by_role は NULL / 'employee_admin' / 'genka_admin'
- ※ `is_voided=true ⇒ voided_by IS NOT NULL` の CHECK は今回入れない。PR-B の
  `admin_void_report_secure` 側で voided_by を確実にセットする設計とする。

### 実行ステータス

- **実行済み（2026-07-06）**。SQL：`docs/sql/report-void-columns.sql`（additive-only）を
  ユーザーが Supabase SQL Editor で実行。
- 事後確認 F〜H 結果（すべて期待どおり）：
  - (1) 5カラム（`is_voided` / `voided_at` / `voided_by` / `voided_by_role` / `void_reason`）追加済み
  - (2) `is_voided` が **NOT NULL**、(3) `is_voided` の **DEFAULT が false**（型 boolean）
  - `void_reason` text / `voided_at` timestamptz / `voided_by` uuid / `voided_by_role` text（いずれも nullable）
  - (4) CHECK 制約2本（`reports_void_consistency` / `reports_voided_by_role_valid`）作成済み
  - (5) `active_rows=151` / `voided_rows=0` / `total_rows=151`（active_rows = total_rows・既存151件は
    すべて `is_voided=false`）
- PR-A 単独では履歴・集計・CSV の挙動は変わらない。**次工程 PR-B**：`admin_void_report_secure` 追加と、
  read/export RPC（`list_my_reports_secure` / `list_admin_reports_secure`（include_voided 追加）/
  `list_genka_reports_secure` / `export_projects_summary_secure` / `export_attendance_details_secure`）への
  `is_voided=false` 除外。

### 影響範囲 / 非影響

- reports に列追加のみ。既存列・データ・RLS・policy・権限・既存RPC・トリガーは不変。
- 既存行はすべて is_voided=false。**本PR単独では履歴・集計・CSVの結果は変わらない**
  （read/export RPC の除外フィルタは PR-B）。

---

## 2026-07-06 日報無効化 PR-B: 無効化RPC追加・read/export の無効化除外（★実行済み★）

### 目的

- PR-A で追加した `is_voided` を実運用するため、(A) 通常 read/export RPC に `is_voided=false` 除外、
  (B) 管理者専用の無効化RPC `admin_void_report_secure`、(C) 無効化済み確認用
  `list_admin_reports_with_voided_secure` を追加する。管理者UIは PR-C。

### 変更・追加内容（SQL：`docs/sql/report-void-rpc.sql`・additive/本体再定義のみ）

- **A. 既存 read/export に除外追加**（本体のみ CREATE OR REPLACE・引数/戻り列/権限/認可は不変）：
  `list_my_reports_secure` / `list_admin_reports_secure` / `list_genka_reports_secure` /
  `export_projects_summary_secure` / `export_attendance_details_secure` の各 WHERE に
  `AND r.is_voided = false` を1行追加（原本との差分は当該1行のみ・diff 検証済み）。
  `export_project_cost_details_secure` / `export_machine_details_secure` は reports を直接読まないため対象外。
- **B. `admin_void_report_secure(text, uuid, text)`**：管理者二経路検証（employee_admin / genka_admin）、
  理由必須（空白のみ不可）、`is_voided=true` / `voided_at=now()` / `voided_by`＝実行者id /
  `voided_by_role`＝出所 / `void_reason=btrim(reason)`。既に無効化済みは 'Report already voided'、
  存在しない id は 'Report not found'。`RETURNS TABLE`（report_id, is_voided, voided_at, voided_by,
  voided_by_role, void_reason）で無効化結果を返す。物理削除しない・復元RPCは作らない。
- **C. `list_admin_reports_with_voided_secure(text, date, date, boolean DEFAULT false)`**：
  既存 `list_admin_reports_secure`（シグネチャ維持・通常集計用）とは別に新設。
  `include_voided_input=false` で有効のみ、true で無効化済みも含め、監査列（is_voided/voided_*）を返す。PR-C の管理者UI用。
- **D. 権限**：新設2関数のみ `REVOKE EXECUTE ... FROM PUBLIC` → `GRANT ... TO anon, authenticated, service_role`。
  A の5関数は CREATE OR REPLACE で既存 ACL 保持（再GRANTなし）。reports への直接 UPDATE 権限は付与しない。RLS/policy 不変。

### 実行ステータス

- **実行済み（2026-07-06）**。ユーザーが Supabase SQL Editor で実行。事前確認 P1/P2・事後確認 Q1〜Q4 実施。
- 事後確認結果（すべて期待どおり）：
  - Q1：`admin_void_report_secure` / `list_admin_reports_with_voided_secure` とも存在・
    `SECURITY DEFINER=true`・`search_path=public, extensions`・引数想定どおり。
  - Q2：新設2関数の `PUBLIC EXECUTE` なし（0行・Success. No rows returned）。
  - Q3：`reports` への `anon` / `authenticated` 直接 UPDATE 権限なし（0行・Success. No rows returned）。
  - 追加EXECUTE：新設2関数とも `anon` / `authenticated` / `service_role` に EXECUTE あり（can_execute=true）。
  - A の5関数（`list_my_reports_secure` / `list_admin_reports_secure` / `list_genka_reports_secure` /
    `export_projects_summary_secure` / `export_attendance_details_secure`）は `is_voided=false` 除外を反映済み。
- PR-B 単独では UI はまだ無い。**次工程 PR-C**：index.html 管理者エリアに個別日報一覧＋無効化ボタン＋
  「無効化済みも表示」トグルを追加（`admin_void_report_secure` / `list_admin_reports_with_voided_secure` を利用）。

### 影響範囲 / 非影響

- 実行後：通常の本人履歴・本人カレンダー・管理集計・原価集計・CSV(projects_summary/attendance) から
  `is_voided=true` の日報が除外される。有効日報の集計値・件数は不変（既存151件は is_voided=false）。
- 既存の日報作成（create_report_secure）・編集（update_report_secure）は不変。UI 変更なし（PR-C で対応）。

## 2026-07-08 PR-4C-1 旧PIN照合RPC verify_employee_pin / verify_admin_pin の EXECUTE REVOKE（★実行済み★）

### 目的

- PR-4A introspection で残存が判明した旧RPC `verify_employee_pin(uuid, text)` /
  `verify_admin_pin(uuid, text)`（SECURITY DEFINER・平文PIN照合 `pin = pin_input`・
  成功時にユーザー情報返却）から `PUBLIC` / `anon` / `authenticated` の EXECUTE を剥奪し、
  anon からの PIN 総当たり・在籍/PIN一致判定に使える外部実行経路を遮断する。
- 現行ログインは `create_*_session` に統一済みで、フロントからの `verify_*_pin` 呼び出しはゼロ件
  （`index.html` / `admin-app.html` / `genka-app.html` はいずれも `create_*_session`）。

### 変更内容（SQL：`docs/sql/pr4c-revoke-old-pin-verify-rpcs.sql`・REVOKE のみ）

- `verify_employee_pin(uuid, text)` / `verify_admin_pin(uuid, text)` の EXECUTE を
  `PUBLIC` / `anon` / `authenticated` から REVOKE（各3文・計6文）。
- DROP はしない（可逆な REVOKE を優先。別PRでログイン3導線の動作確認後に DROP を検討）。
- 関数定義・引数・戻り値・SECURITY DEFINER・RLS/policy は不変。GRANT/ALTER/CREATE/DROP なし。
- 関数オーナー（postgres）の EXECUTE は対象外。service_role は明示GRANTなしのため対象外。

### 実行ステータス

- **実行済み（2026-07-08）**。ユーザーが Supabase SQL Editor で実行。REVOKE本体は `Success. No rows returned`。
- 事後確認（すべて期待どおり）：
  - `has_function_privilege`：`verify_employee_pin(uuid,text)` / `verify_admin_pin(uuid,text)` とも
    anon=false / authenticated=false / public=false。
  - `information_schema.routine_privileges`：対象3ロールの EXECUTE 行は 0 rows。
- 本番ログイン確認（REVOKE 後も正常）：
  - `/` 従業員ログイン OK
  - `/admin` 管理者ログイン OK
  - `/genka` 原価管理ログイン OK

### 影響範囲 / 非影響

- 影響：旧RPC2本は `PUBLIC` / `anon` / `authenticated` から実行不可になった。関数本体（平文照合ロジック）は
  DB に残存（DROP は別PR）。オーナー実行経路は保持。
- 非影響：現行ログイン（`create_*_session` 経由）・その他の業務RPC・RLS/policy は不変。UI 変更なし。

### 関連

- PR #75（`feature/revoke-old-pin-verify-rpcs`、merge commit `433300e`）。
- SQL：`docs/sql/pr4c-revoke-old-pin-verify-rpcs.sql`。
- 残課題：旧RPC2本の `DROP FUNCTION`（PR-4C-2 候補）。

## 2026-07-08 PR-4C-2 旧PIN照合RPC verify_employee_pin / verify_admin_pin の DROP FUNCTION（★実行済み★）

### 目的

- PR-4C-1 で外部 EXECUTE を REVOKE 済みの旧RPC `verify_employee_pin(uuid, text)` /
  `verify_admin_pin(uuid, text)`（SECURITY DEFINER・平文PIN照合 `pin = pin_input`）を
  DB から完全撤去し、平文PIN照合ロジックの残存を無くす。
- 現行ログインは `create_*_session` に統一済みで、フロントからの `verify_*_pin` 呼び出しはゼロ件。

### 変更内容（SQL：`docs/sql/pr4c2-drop-old-pin-verify-rpcs.sql`・DROP のみ）

- `verify_employee_pin(uuid, text)` / `verify_admin_pin(uuid, text)` を `DROP FUNCTION IF EXISTS ... RESTRICT`（2文）。
- `CASCADE` は不使用（`RESTRICT` 明示）。A-2 依存確認が 0 rows のときのみ DROP 実行。
- 関数の再作成・GRANT/ALTER/CREATE/REVOKE・RLS/policy 変更なし。HTML/JS/認証/PIN処理の変更なし。

### 実行ステータス

- **実行済み（2026-07-08）**。ユーザーが Supabase SQL Editor で実行。DROP 本体は `Success. No rows returned`。
- 実行前確認（すべて期待どおり）：
  - A-1：対象2関数の存在確認 OK。
  - A-2：DB内依存確認（`pg_depend`）は 0 rows。
  - A-3：`has_function_privilege` → `anon` / `authenticated` / `public` とも両関数 false。
- 実行後確認：`pg_proc` 上で対象2関数は 0 rows（消滅を確認）。
- 本番ログイン確認（DROP 後も正常）：
  - `/` 従業員ログイン OK
  - `/admin` 管理者ログイン OK
  - `/genka` 原価管理ログイン OK

### 影響範囲 / 非影響

- 影響：旧RPC2本（平文PIN照合ロジック）が DB から消滅。PR-4C-1 の REVOKE と合わせ、旧RPC経由の
  外部実行経路・平文照合ロジックともに完全撤去された。
- 非影響：現行ログイン（`create_*_session` 経由）・その他の業務RPC・RLS/policy は不変。UI 変更なし。

### 関連

- PR #77（`feature/drop-old-pin-verify-rpcs`、merge commit `602594b`）。
- SQL：`docs/sql/pr4c2-drop-old-pin-verify-rpcs.sql`。
- 前段：PR-4C-1（EXECUTE REVOKE、PR #75 / merge `433300e`）。

---

## 2026-07-08 Phase 4-E-1 employees / genka_admins 残存不要権限（TRUNCATE / REFERENCES / TRIGGER / MAINTAIN）REVOKE 完了（★実行済み★）

### 目的

- `employees` / `genka_admins` に残っていた `anon` / `authenticated` の非読み取り不要権限（TRUNCATE / REFERENCES / TRIGGER / MAINTAIN）を REVOKE する。
- SELECT は列レベル付与に限定済み（2026-05-28）、INSERT / UPDATE は REVOKE 済み（2026-05-30）。書き込みは `*_secure` RPC、ログインは `create_*_session` RPC 経由。本整理は Phase 4-D-4（financial系）と同種の、テーブルレベル残存権限の後片付け。
- MAINTAIN は PostgreSQL 17 で追加されたテーブルレベル保守権限（VACUUM / ANALYZE / CLUSTER / REINDEX / REFRESH MATERIALIZED VIEW / LOCK TABLE）。Supabase の PG17 デフォルト GRANT ALL の副作用で `anon` / `authenticated` に付与されており、アプリ（PostgREST CRUD / RPC）は使わないため余剰権限として除去。先例 `docs/sql/phase4c-4-report-summary-revoke.sql` も MAINTAIN を REVOKE 済み。

### 背景（Pre-check 調査結果・ユーザーが Supabase SQL Editor で手動確認）

- A-0：PostgreSQL 17.6（`server_version_num` = 170006）。MAINTAIN キーワードが使える前提を確認。
- A：`employees` / `genka_admins` とも `anon` / `authenticated` は SELECT/INSERT/UPDATE/DELETE=false・TRUNCATE/REFERENCES/TRIGGER/MAINTAIN=true（要除去）。
- A-2：public は両テーブル全権限 false。
- A-3〜A-5b：列レベル SELECT は期待セットのみ（下記 G-3 参照）。pin の SELECT なし・真の列単位 REFERENCES なし。
- B：両テーブル `relrowsecurity=true`。C：想定外 policy なし。D：ユーザー定義トリガ 0 件。
- E：既知 FK のみ、計9件（`employees` / `genka_admins` を参照先にする FK）。
  - `employee_rates.employee_id -> employees`
  - `employee_sessions.employee_id -> employees`
  - `machine_locations.moved_by -> employees`
  - `paid_leave_grants.employee_id -> employees`
  - `paid_leave_requests.employee_id -> employees`
  - `paid_leave_requests.reviewed_by -> employees`
  - `reports.employee_id -> employees`
  - `site_assignments.employee_id -> employees`
  - `admin_sessions.admin_id -> genka_admins`
  - ※ REFERENCES は新規 FK 作成権限であり、既存 FK 制約は REVOKE の影響を受けない。
- F：session / secure RPC はすべて `prosecdef=true` / `owner=postgres`。
- STOP 条件への該当なし。

### 方針（確定）

- 実行 SQL は REVOKE のみ（1テーブル1文×2本）。順番：employees → genka_admins。
- RPC / RLS / policy / `postgres` / `service_role` / 列レベル SELECT / pin は一切変更しない。`index.html` / `admin-app.html` / `genka-app.html` も変更しない。

### 実行済み SQL（`docs/sql/phase4e-1-employees-admins-extra-privileges-revoke.sql` を Supabase SQL Editor で実行・2026-07-08）

```sql
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.employees FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.genka_admins FROM anon, authenticated;
```

- 実行結果：Success. No rows returned（2本とも）。
- 危険SQL（DROP / DELETE / TRUNCATE 実行 / ALTER / UPDATE / INSERT / CREATE / GRANT）なし。変更は REVOKE 2本のみ。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし（DB 実行はユーザーが手動）。

### 実行後確認結果（Post-check・Supabase SQL Editor・2026-07-08）

- G（anon / authenticated）：`employees` / `genka_admins` とも SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN が全て false。期待どおり。
- G-2（public）：両テーブルとも全権限 false（不変）。期待どおり。
- G-3（列SELECT維持）：`employees`（id, name, role, is_active, company_id, can_genka, can_admin）/ `genka_admins`（id, name, is_active）を `anon` / `authenticated` とも維持。pin の SELECT なし。
- G-4（pin REFERENCES）：`employees.pin` / `genka_admins.pin` とも `anon` / `authenticated` で false。
- G-5（attacl 再確認）：真の列単位権限は既定の SELECT のみ。pin 行なし・REFERENCES 行なし・SELECT 以外なし。

### 本番画面確認（REVOKE 後）

今回 REVOKE した TRUNCATE / REFERENCES / TRIGGER / MAINTAIN はフロントの PostgREST クライアントが使わない DDL / 保守系権限のため、画面挙動への影響なし（リグレッションなしを確認）。

- `/` 従業員ログイン OK
- `/admin` 管理者ログイン OK
- `/genka` 原価ログイン OK

### 実行したSQLファイル

| ファイル | 内容 |
|---|---|
| `docs/sql/phase4e-1-employees-admins-extra-privileges-revoke.sql` | A-0 バージョン確認 / 事前確認 A〜F / REVOKE TRUNCATE,REFERENCES,TRIGGER,MAINTAIN（2テーブル・1文ずつ）/ 事後確認 G・G-2・G-3・G-4・G-5 / rollback（GRANT・コメントアウト）。STATUS を EXECUTED に更新済み |

### 触らなかったもの

- RLS 有効状態・既存 policy（pre-check のみ）
- read RPC / write RPC / session RPC（定義・EXECUTE・SECURITY DEFINER）
- `service_role` / `postgres`(owner) の権限
- 列レベル SELECT・pin（非付与のまま維持）
- SELECT / INSERT / UPDATE / DELETE（既に遮断済み・本工程では未変更）
- フロント（`index.html` / `admin-app.html` / `genka-app.html`）
- rollback GRANT（未実行・コメントアウトのまま）

### 影響範囲

- DB：`employees` / `genka_admins` の `anon` / `authenticated` の TRUNCATE / REFERENCES / TRIGGER / MAINTAIN を REVOKE のみ。DROP POLICY / ALTER TABLE / DML / 他テーブル変更なし。
- フロント：変更なし。
- **Phase 4-E-1 完了**。

### 関連

- PR #79（script追加、merge commit `ac629cd`）/ PR #80（REFERENCES precheck 修正、merge commit `d8357a0`）/ PR #81（MAINTAIN 追加、merge commit `013b7d5`）。
- SQL：`docs/sql/phase4e-1-employees-admins-extra-privileges-revoke.sql`。
- 申し送り：financial系4テーブル（`unit_rates` / `employee_rates` / `site_budgets` / `invoices`）にも PG17 由来の MAINTAIN が残存している可能性（Phase 4-D-4 は MAINTAIN 未対応）。別工程で要確認（Phase 4-E-2 候補）。


## 2026-07-09 Phase 4-E-2 financial系4テーブル MAINTAIN 残存確認 → pre-check クリーンにつき REVOKE 未実行（★DB変更なし★）

### 目的

- Phase 4-D-4 で未対応だった financial系4テーブルの PostgreSQL 17 由来 MAINTAIN 残存を確認し、残っていれば `anon` / `authenticated` から REVOKE するための確認工程（Phase 4-E-1 の申し送り「Phase 4-E-2 候補」の消化）。

### 対象

- `employee_rates`
- `invoices`
- `site_budgets`
- `unit_rates`
- 対象ロール：`anon` / `authenticated`
- 対象権限：MAINTAIN のみ（SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER は Phase 4-D / 4-D-4 で対応済み）

### 初回 Pre-check（Supabase SQL Editor・ユーザー手動・2026-07-09）

- A-0：PostgreSQL 17.6（`server_version_num` = 170006）。MAINTAIN キーワードが使える前提を確認。
- A：4テーブルとも `anon` / `authenticated` は SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER=false・**MAINTAIN のみ true**（残存＝除去対象）。
- A-5a：relacl に **MAINTAIN のみ 8行**（4テーブル × `anon` / `authenticated`）。
- A-2：PUBLIC は4テーブルとも全権限 false。
- → MAINTAIN 残存を確認し、除去用の SQL ファイルを作成する方針に。

### SQLファイル作成・PR #83

- `docs/sql/phase4e-2-financial-maintain-revoke.sql` を追加（A-0 / A / A-2 / A-5a 事前確認、REVOKE MAINTAIN 4文、G / G-2 / G-5 事後確認、rollback コメントの最小構成）。
- merge commit `9e6e209`（PR #83）。作成時点の STATUS は `NOT EXECUTED`。

### 実行直前 Pre-check（Supabase SQL Editor・ユーザー手動・2026-07-09）

- REVOKE 本体を流す直前に再確認したところ、対象は既にクリーンだった：
  - A：4テーブル × `anon` / `authenticated` の8権限（SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN）が**全て false**。
  - A-5a：relacl は `anon` / `authenticated` で **0 rows**。
  - A-2：PUBLIC は4テーブルとも全権限 false。

### 最終再確認（Supabase SQL Editor・ユーザー手動・2026-07-09）

- 対象4テーブル × `anon` / `authenticated` の8権限が**全て false**であることを再確認（クリーンで安定）。

### 判断

- 目標状態（`anon` / `authenticated` に MAINTAIN が付いていない状態）を既に満たしていたため、**REVOKE 本体4文は未実行**。
- **DB変更なし**。
- **Phase 4-E-2 は「対応不要確認」としてクローズ**。

### 未確定事項

- 初回 pre-check（MAINTAIN 残存・relacl に MAINTAIN 8行）から、実行直前 pre-check / 最終再確認（全権限 false・relacl 0 rows）への**状態変化の契機は未特定**。
- 別経路での REVOKE 実行の可能性を含むが、**このワークフローでは REVOKE を実行していない**。

### pg_default_acl 申し送り（別課題・棚卸し候補）

- `pg_default_acl` に、`public / postgres / r`（＝owner postgres、対象 relkind='r'=テーブル）と `public / supabase_admin / r` の default privileges として、`anon` / `authenticated` 向け `arwdDxtm` が残存。
  - ACL 文字：a=INSERT r=SELECT w=UPDATE d=DELETE D=TRUNCATE x=REFERENCES t=TRIGGER **m=MAINTAIN**。
- このため、**今後 public に新規作成されるテーブルには全権限（MAINTAIN 含む）が再付与される可能性**がある。
- Phase 4-E-2 では変更せず、**default privileges の棚卸しを別課題（別工程）** として扱う（`ALTER DEFAULT PRIVILEGES` は未実行）。

### 触らなかったもの

- REVOKE 未実行（本体4文は SQL ファイル内に保持・未適用）。
- RLS 有効状態・既存 policy・read/write RPC 定義・EXECUTE・SECURITY DEFINER。
- 列レベル権限・`service_role` / `postgres`(owner) の権限。
- `pg_default_acl`（`ALTER DEFAULT PRIVILEGES` 未実行）。
- フロント（`admin-app.html` / `genka-app.html` 等 HTML/JS）・auth / PIN 処理。
- `docs/roadmap.md`。

### 確認手段

- DB 確認はすべてユーザーが Supabase SQL Editor で手動実行。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

### 関連

- PR #83（`docs/sql/phase4e-2-financial-maintain-revoke.sql` 追加、merge commit `9e6e209`）。
- SQL：`docs/sql/phase4e-2-financial-maintain-revoke.sql`（STATUS を `NOT EXECUTED - SKIPPED` に更新）。
- Phase 4-E-1（本ファイル 2026-07-08 セクション）の申し送りをクローズ。
- 別課題：`pg_default_acl` の default privileges 棚卸し（MAINTAIN 含む全権限の新規テーブル再付与）。


## 2026-07-09 Phase 4-F-1 public default privileges cleanup（postgres owner / future tables）（★実行済み★）

### 目的

- owner `postgres` で `public` に今後作成される新規テーブルへ、`anon` / `authenticated` に広い default privileges が自動付与されるのを停止する。
- Phase 4-E-2 で確認された「PG17 由来 MAINTAIN の再付与源」への対応（既存テーブルは clean だが、新規 public テーブルには MAINTAIN 含む全権限が再付与され得た）。

### 対象

- `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public`
- `ON TABLES`
- `FROM anon, authenticated`
- 権限：SELECT / INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN

### 非対象

- owner `supabase_admin` 分の default privileges（別課題・後述）
- grantee `postgres` / `service_role`（温存）
- 既存テーブルの relacl・direct grants
- RLS / policy / RPC 定義
- HTML / JS / auth / PIN
- `public` 以外の schema（storage / auth / realtime / graphql / graphql_public / extensions 等）
- sequences / functions / types / schemas への default privileges

### Pre-check（Supabase SQL Editor・ユーザー手動・2026-07-09）

- A-0：PostgreSQL 17.6（`server_version_num` = 170006）、`is_pg17_or_newer` = true。
- A：`postgres` / `public` / `r` に `anon=arwdDxtm`、`authenticated=arwdDxtm` を確認。`supabase_admin` / `public` / `r` にも同様の default privileges あり（ただし NON-SCOPE）。
- B：owner `postgres` / `public` / `anon`, `authenticated` の default privileges = DELETE / INSERT / MAINTAIN / REFERENCES / SELECT / TRIGGER / TRUNCATE / UPDATE（8権限）。
- C：global default privileges `(all schemas)`（`defaclnamespace = 0`）は 0 rows（per-schema REVOKE を打ち消す global default なし）。
- D：`current_user` = postgres、`session_user` = postgres、`is_member_postgres` = true（実行可）。
- STOP 条件への該当なし。

### 実行 SQL（`docs/sql/phase4f-1-public-default-privileges-revoke.sql` を Supabase SQL Editor で実行・2026-07-09）

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON TABLES FROM anon, authenticated;
```

- 実行結果：`Success. No rows returned`。
- 危険 SQL（DROP / DELETE / TRUNCATE 実行 / 既存テーブル ALTER / DML / GRANT）なし。変更は owner postgres 分の default privileges REVOKE 1文のみ。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし（DB 実行はユーザーが手動）。

### 実行後確認結果（Post-check・Supabase SQL Editor・2026-07-09）

- G：owner `postgres` / `public` / `anon`, `authenticated` は 0 rows（8権限が default から除去済み）。期待どおり。
- G-2：owner `postgres` / `public` / `postgres`, `service_role` は8権限が残存（温存 OK）。期待どおり。
- G-3：owner `supabase_admin` / `public` は `anon` / `authenticated` / `postgres` / `service_role` とも8権限が残存。今回 NON-SCOPE のため成功/失敗判定の対象外（backlog）。

### 影響範囲

- 既存テーブルには影響なし（default privileges は作成時点の付与ルールで、既存テーブルの relacl は不変）。
- 以後、owner `postgres` で `public` に作成される **future tables** のみ対象（`anon` / `authenticated` への自動付与が止まる）。書き込み/読み取りは従来どおり secure RPC 経由。

### 触らなかったもの

- owner `supabase_admin` の default privileges（未変更）。
- grantee `postgres` / `service_role` の default privileges（温存）。
- 既存テーブルの relacl・direct grants、RLS / policy / RPC、列レベル権限。
- HTML / JS / auth / PIN、`public` 以外の schema、sequences / functions。
- `docs/roadmap.md`。

### 申し送り（backlog）

- owner `supabase_admin` 分の default privileges は残存（`anon` / `authenticated` に arwdDxtm）。実行ロールのメンバーシップ要件があるため Phase 4-F-1b 候補として別扱い。
- 既存テーブルの direct grants / stale policies は Phase 4-F-2 以降で対応候補。

### 確認手段

- DB 確認・実行はすべてユーザーが Supabase SQL Editor で手動実行。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

### 関連

- PR #85（`docs/sql/phase4f-1-public-default-privileges-revoke.sql` 追加、merge commit `fd8a3a3`）。
- SQL：`docs/sql/phase4f-1-public-default-privileges-revoke.sql`（STATUS を `EXECUTED (2026-07-09)` に更新）。
- Phase 4-E-2（本ファイル 2026-07-09 セクション）で確認した MAINTAIN 再付与源への対応。

## 2026-07-09 Phase 4-F-2A existing public tables extra privileges cleanup（TRUNCATE / REFERENCES / TRIGGER / MAINTAIN）（★実行済み★）

### 目的

- 既存 public テーブルの `anon` / `authenticated` に残る非CRUD系 direct grants（`pg_class.relacl`）を除去する。
- 対象権限は `TRUNCATE / REFERENCES / TRIGGER / MAINTAIN`。Supabase PG17 の default GRANT ALL の残渣で、アプリは使用していない（読み取りは direct SELECT / secure read RPC、書き込みは secure RPC 経由）。
- Phase 4-F-1 は future tables の default privileges が対象。今回 4-F-2A は existing tables の direct grants のみが対象（別オブジェクト・別メカニズム）。

### 対象（全15テーブル・2バッチ・全15文）

- Batch 1（4権限 REVOKE・13テーブル）：`admin_sessions` / `companies` / `company_categories` / `employee_sessions` / `machine_locations` / `machines` / `materials` / `paid_leave_grants` / `paid_leave_requests` / `site_assignments` / `site_categories` / `sites` / `subcontractors`
- Batch 2（`MAINTAIN` のみ REVOKE・2テーブル）：`notices` / `reports`

### 非対象

- `SELECT / INSERT / UPDATE / DELETE`（CRUD は不変）
- RLS / policy
- RPC
- HTML / JS / auth / PIN
- default privileges（owner `postgres` / future tables は Phase 4-F-1 で対応済み）
- owner `supabase_admin` 分の default privileges（別 backlog）
- stale policies の DROP POLICY（Phase 4-F-3 候補）
- `employees` / `genka_admins`（Phase 4-E-1 で対応済み）
- financial 系4テーブル（Phase 4-D-4 / 4-E-2 で対応済み）
- session テーブル（`admin_sessions` / `employee_sessions`）の CRUD grant（別工程で慎重に扱う）

### Pre-check（Supabase SQL Editor・ユーザー手動・2026-07-09）

- A-0：PostgreSQL 17.6（`server_version_num` = 170006）、`is_pg17_or_newer` = true。
- A：15テーブル × `anon` / `authenticated` × 8権限のマトリクスを確認。
  - Batch 1 の13テーブルは `TRUNCATE / REFERENCES / TRIGGER / MAINTAIN` が true。
  - `notices` / `reports` は `MAINTAIN` のみ true。
  - CRUD（`SELECT / INSERT / UPDATE / DELETE`）はテーブルごとに既存状態を記録し、post-check で不変確認する前提。
- A-2：対象15テーブル以外で4権限（`TRUNCATE / REFERENCES / TRIGGER / MAINTAIN`）を保持するテーブル = 0 rows（完全性ガード）。
- A-3：REVOKE 対象権限の実在確認。
- A-4：CRUD の pre 状態をスナップショット記録。
- A-5：PUBLIC の該当権限 = 0 rows（情報確認）。
- STOP 条件への該当なし。

### 実行 SQL（`docs/sql/phase4f-2a-existing-extra-privileges-revoke.sql` を Supabase SQL Editor で実行・2026-07-09）

- EXECUTION BODY 全15文（Batch 1：13文 / Batch 2：2文）を実行。
- 実行結果：`Success. No rows returned`。
- 危険 SQL（DROP / DELETE / TRUNCATE 実行 / DML / GRANT / ALTER DEFAULT PRIVILEGES / DROP POLICY）なし。変更は既存テーブル relacl からの非CRUD権限 REVOKE のみ。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし（DB 実行はユーザーが手動）。

### 実行後確認結果（Post-check・Supabase SQL Editor・2026-07-09）

- G：対象15テーブルで `TRUNCATE / REFERENCES / TRIGGER / MAINTAIN` が全て false、CRUD は A-4 スナップショットから不変。期待どおり。
- G-2：public 全体で対象4権限を保持するテーブル = 0 rows。期待どおり。
- G-3：対象15テーブルで対象4権限 = 0 rows。期待どおり。

### 影響範囲

- アプリ動作への影響なし（除去したのは未使用の非CRUD権限のみ）。CRUD / RLS / RPC は不変。

### 触らなかったもの

- CRUD grant（`SELECT / INSERT / UPDATE / DELETE`）、RLS / policy / RPC、列レベル権限。
- default privileges（Phase 4-F-1 済み）、owner `supabase_admin` 分（別 backlog）。
- stale policies、`employees` / `genka_admins`、financial 系4テーブル、session テーブルの CRUD grant。
- HTML / JS / auth / PIN、`docs/roadmap.md`。

### 確認手段

- DB 確認・実行はすべてユーザーが Supabase SQL Editor で手動実行。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

### 関連

- PR #87（`docs/sql/phase4f-2a-existing-extra-privileges-revoke.sql` 追加、merge commit `87b22d5`、commit `945d8ec`）。
- SQL：`docs/sql/phase4f-2a-existing-extra-privileges-revoke.sql`（STATUS を `EXECUTED (2026-07-09)` に更新）。

## 2026-07-10 Phase 4-F-2B-1 未使用カテゴリテーブル direct SELECT grant 除去（★実行済み★）

### 目的

- 未使用のカテゴリマスタ2件について、`anon` / `authenticated` の direct SELECT grant（`pg_class.relacl`）を除去する。
- フロント3ファイル（index.html / admin-app.html / genka-app.html）から対象2テーブルへの直接参照は 0 件（Phase 4-F-2B B-1..B-4 で確認済み）。

### 対象（2テーブル・全2文）

- `company_categories` / `site_categories`（各 `REVOKE SELECT ... FROM anon, authenticated;`・アルファベット順）

### 非対象

- `INSERT / UPDATE / DELETE`
- RLS / policy（DROP POLICY なし）
- RPC / function / EXECUTE grants
- view definitions
- HTML / JS / auth / PIN
- default privileges
- other tables

### Pre-check（Supabase SQL Editor・ユーザー手動・2026-07-10）

- P-1a：両テーブル存在、RLS 有効、`anon` / `authenticated` の SELECT = true、INSERT / UPDATE / DELETE = false。
- P-1b：SELECT policy `cc_select`（`company_categories`）/ `sc_select`（`site_categories`）の存在を確認。
- P-2a：参照 routine は `export_projects_summary_secure(...)` のみ。SECURITY DEFINER = true、owner = `postgres`、owner は両テーブルを SELECT 可能。
- P-2b：対象2テーブルを参照する view / materialized view = 0 rows。
- P-3：relacl 上の明示的 SELECT grant = 4 rows。
- STOP 条件への該当なし。

### 実行 SQL（`docs/sql/phase4f-2b-1-unused-category-select-revoke.sql` を Supabase SQL Editor で実行・2026-07-10）

- `REVOKE SELECT ON TABLE public.company_categories FROM anon, authenticated;`
- `REVOKE SELECT ON TABLE public.site_categories FROM anon, authenticated;`
- 実行結果：`Success. No rows returned`。
- 危険 SQL（DROP / DELETE / TRUNCATE / DML / GRANT / ALTER DEFAULT PRIVILEGES / DROP POLICY）なし。変更は既存テーブル relacl からの SELECT grant 除去のみ。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし（DB 実行はユーザーが手動）。

### 実行後確認結果（Post-check・Supabase SQL Editor・2026-07-10）

- Q-1：両テーブル × `anon` / `authenticated` で SELECT = false。期待どおり。
- Q-2a：INSERT / UPDATE / DELETE は全て false のまま不変。期待どおり。
- Q-2b：`cc_select` / `sc_select` policy は残存（DROP POLICY なし）。期待どおり。
- Q-3：relacl 上の明示的 SELECT grant = 0 rows。期待どおり。

### 影響評価（設計上）

- フロント3ファイルから対象2テーブルへの直接参照 0 件。
- 実DBで検出された依存 routine は `export_projects_summary_secure(...)` のみで、SECURITY DEFINER・owner `postgres`・owner は両テーブルを SELECT 可能。
- view / materialized view 依存は 0 件。
- 以上から、設計上アプリ動作への影響はないと判断。
- 本番画面のスモークテストは本工程では未実施。

### policy 残存メモ（`cc_select` / `sc_select`）

- policy は意図的に残置。
- 現在は `anon` / `authenticated` の実効 SELECT 権限が false のため、現在の grant 状態では実効上使われない。
- 将来 SELECT が再 GRANT された場合は再び評価対象になる。
- Phase 4-F-3 の stale policy 掃除候補。

### 確認手段

- DB 確認・実行はすべてユーザーが Supabase SQL Editor で手動実行。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

### 関連

- PR #89（`docs/sql/phase4f-2b-1-unused-category-select-revoke.sql` 追加、merge commit `a505948`、commit `03ccba1`）。
- SQL：`docs/sql/phase4f-2b-1-unused-category-select-revoke.sql`（STATUS を `EXECUTED (2026-07-10)` に更新）。

## 2026-07-10 Phase 4-F-2B-2 companies direct INSERT / UPDATE grant 除去（★実行済み★）

### 目的

- `public.companies` に残存していた `anon` / `authenticated` の direct INSERT / UPDATE grant（`pg_class.relacl`）を除去する。

### 対象（1テーブル・全1文）

- `public.companies` の `anon` / `authenticated` の INSERT / UPDATE のみ。

### 非対象

- `SELECT`
- `DELETE`
- RLS
- `companies_select_public` policy
- RPC / function / EXECUTE grants
- view / materialized view
- trigger
- foreign key / constraint
- HTML / JS / auth / PIN
- default privileges
- other tables
- `docs/roadmap.md`

### Pre-check（Supabase SQL Editor・ユーザー手動・2026-07-10）

- C-1：`companies` 存在、`relkind = r`、RLS enabled = true、FORCE RLS = false。
- C-2：`anon` / `authenticated` とも SELECT / INSERT / UPDATE = true、DELETE = false。
- C-3：`companies_select_public`（SELECT）policy 1件のみ。INSERT / UPDATE policy なし。
- C-4：relacl 上の明示的 INSERT / UPDATE 直接 grant = 4 rows。
- C-5：companies を参照する routine 7件（`create_machine_admin_secure` / `create_site_secure` / `export_machine_details_secure` / `export_project_cost_details_secure` / `export_projects_summary_secure` / `update_machine_admin_secure` / `update_site_secure`）。全件 SECURITY DEFINER = true、owner = `postgres`、companies への INSERT / UPDATE なし。
- C-6：companies を参照する view / materialized view = 0 rows。
- C-7：companies 上のユーザー定義 trigger・companies へ書き込む trigger 関数 = 0 rows。
- C-8：companies を参照する FK = 7件（`employees` / `invoices` / `machines` / `site_budgets` / `sites` / `subcontractors` / `unit_rates`）。情報確認のみ。
- STOP 条件への該当なし。

### 実行 SQL（`docs/sql/phase4f-2b-2-companies-write-revoke.sql` を Supabase SQL Editor で実行・2026-07-10）

- `REVOKE INSERT, UPDATE ON TABLE public.companies FROM anon, authenticated;`
- 実行結果：`Success. No rows returned`。
- 危険 SQL（DROP / DELETE / TRUNCATE / DML / GRANT / ALTER DEFAULT PRIVILEGES / DROP POLICY）なし。変更は既存テーブル relacl からの INSERT / UPDATE grant 除去のみ。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし（DB 実行はユーザーが手動）。

### 実行後確認結果（Post-check・Supabase SQL Editor・2026-07-10）

- Q-1：`anon` / `authenticated` とも SELECT = true、INSERT = false、UPDATE = false、DELETE = false。期待どおり。
- Q-2：`companies_select_public` policy 残存、INSERT / UPDATE policy なし（DROP POLICY なし）。期待どおり。
- Q-3：relacl 上の明示的 INSERT / UPDATE 直接 grant = 0 rows。期待どおり。
- Q-4：`anon` / `authenticated` とも SELECT = true を維持。期待どおり。

### 影響評価

- リポジトリ調査と実DB確認で、`anon` / `authenticated` を使う companies 書き込み経路は検出されなかった。
- SELECT 権限と `companies_select_public` policy は維持。
- 特権ロールによる DB 管理操作は今回の REVOKE 対象外。
- 本工程では本番画面のスモークテスト未実施。

### 確認手段

- DB 確認・実行はすべてユーザーが Supabase SQL Editor で手動実行。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

### 関連

- PR #91（`docs/sql/phase4f-2b-2-companies-write-revoke.sql` 追加、merge commit `e18a9f3`、commit `d9f6f39`）。
- SQL：`docs/sql/phase4f-2b-2-companies-write-revoke.sql`（STATUS を `EXECUTED (2026-07-10)` に更新）。

---

## 2026-07-10 Phase 4-F-3 category stale policy除去（★実行済み★）

### 目的

- `company_categories.cc_select` / `site_categories.sc_select` を除去する。
- Phase 4-F-2B-1 で anon / authenticated の SELECT grant を除去済みのため、現在の grant 状態ではこの2 policy は実効上使われていない。
- 将来 SELECT が再 GRANT された場合に再び許可経路となる潜在状態を解消する（policy 層の defense-in-depth 整理）。

### 対象（2 policy・全2文）

- `DROP POLICY cc_select ON public.company_categories;`
- `DROP POLICY sc_select ON public.site_categories;`

### 非対象

- table grants
- SELECT / INSERT / UPDATE / DELETE 権限
- RLS enabled / FORCE RLS
- RPC / function / EXECUTE grants
- view / materialized view
- HTML / JS / auth / PIN
- default privileges
- other tables
- `employees_update_public`
- その他すべての policy
- `docs/roadmap.md`

### Pre-check（Supabase SQL Editor・ユーザー手動・2026-07-10）

- D-1：`company_categories` / `site_categories` とも存在、`relkind = r`、RLS enabled = true、FORCE RLS = false。
- D-2：両テーブル × `anon` / `authenticated` の SELECT table privilege = false。
- D-3：対象テーブルの policy は `cc_select` / `sc_select` の2件のみ（PERMISSIVE / roles = {anon,authenticated} / cmd = SELECT / qual = true / with_check = null）。
- D-4：`authenticator` と `supabase_storage_admin` は両テーブル SELECT = false。`postgres` は両テーブル SELECT = true だが、BYPASSRLS = true かつ両テーブルの owner のため、そのアクセスは `cc_select` / `sc_select` に依存しない。
- D-5a：対象テーブルを参照する routine は `export_projects_summary_secure(...)` 1件のみ。SECURITY DEFINER = true、owner = `postgres`、owner は両テーブル SELECT 可能、BYPASSRLS = true、両テーブルの owner。policy 依存なし。
- D-5b：view / materialized view 依存 = 0 rows。
- STOP 条件への該当なし。

### 実行 SQL（`docs/sql/phase4f-3-category-stale-policy-drop.sql` を Supabase SQL Editor で実行・2026-07-10）

- `DROP POLICY cc_select ON public.company_categories;` → 実行結果：`Success. No rows returned`。
- `DROP POLICY sc_select ON public.site_categories;` → 実行結果：`Success. No rows returned`。
- `IF EXISTS` / `CASCADE` なし。grant 変更・RLS 状態変更・他 policy への干渉なし。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし（DB 実行はユーザーが手動）。

### 実行後確認結果（Post-check・Supabase SQL Editor・2026-07-10）

- Q-1：対象2テーブルの policy = 0 rows（`cc_select` / `sc_select` 消失）。期待どおり。
- Q-2：両テーブルとも RLS enabled = true、FORCE RLS = false を維持。期待どおり。
- Q-3：両テーブル × `anon` / `authenticated` の CRUD table privilege（SELECT / INSERT / UPDATE / DELETE）は全て false。期待どおり。
- Q-4：relacl 上の `anon` / `authenticated` 向け CRUD grant = 0 rows のまま不変。期待どおり。

### 影響評価

- table grants は不変。
- RLS 状態（enabled / FORCE RLS）は不変。
- SECURITY DEFINER routine（`export_projects_summary_secure(...)`）の定義・権限は不変。
- 本工程では RPC スモークテスト・本番画面スモークテストは未実施。

### 確認手段

- DB 確認・実行はすべてユーザーが Supabase SQL Editor で手動実行。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

### 関連

- PR #93（`docs/sql/phase4f-3-category-stale-policy-drop.sql` 追加、merge commit `8fbea4d`、commit `4d8866e`）。
- SQL：`docs/sql/phase4f-3-category-stale-policy-drop.sql`（STATUS を `EXECUTED (2026-07-10)` に更新）。

## 2026-07-11 Phase 4-F-2B-3 session direct grant除去（★実行済み★）

### 目的

- `public.admin_sessions` / `public.employee_sessions` について、`anon` / `authenticated` に残存していた direct SELECT / INSERT / UPDATE grant を除去する。
- session アクセスを SECURITY DEFINER RPC 経路のみに限定する。
- DELETE は実行前から false のため対象外。

### 対象SQL（EXECUTION BODY・2文・1文ずつ手動実行）

- `REVOKE SELECT, INSERT, UPDATE ON TABLE public.admin_sessions FROM anon, authenticated;`
- `REVOKE SELECT, INSERT, UPDATE ON TABLE public.employee_sessions FROM anon, authenticated;`

### 非対象（本工程では触れない）

- DELETE grant（実行前から false）。
- postgres / service_role / table owner の権限。
- RLS 設定。
- policy。
- RPC / function 定義。
- EXECUTE grants。
- trigger。
- view / materialized view。
- FK / constraint。
- HTML / JS。
- `docs/roadmap.md`。
- default privileges。
- その他すべての table / role / privilege。

### 実行前確認結果（Pre-check S-1〜S-9・Supabase SQL Editor・2026-07-11）

- S-1：両テーブル存在、relkind = `r`、RLS = true、FORCE RLS = false。
- S-2：両テーブル × `anon` / `authenticated` で SELECT = true、INSERT = true、UPDATE = true、DELETE = false。
- S-3：policy = 0 rows。
- S-4：relacl 上、`anon` / `authenticated` は SELECT / INSERT / UPDATE のみ。DELETE なし。postgres / service_role は対象外。
- S-5：session 参照 routine 42 本。全て SECURITY DEFINER = true、owner は全て postgres、owner の必要権限は全て true、RLS バイパス条件成立、search_path 固定。session INSERT routine 2 本、UPDATE routine 0 本、DELETE routine 4 本。
- S-6：`create_admin_session` / `revoke_admin_session` / `create_employee_session` / `revoke_employee_session` の 4 本は `anon` / `authenticated` とも EXECUTE = true。
- S-7：view / materialized view 依存 = 0 rows。
- S-8：trigger 依存 = 0 rows。
- S-9：`admin_sessions.admin_id → genka_admins(id) ON DELETE CASCADE`、`employee_sessions.employee_id → employees(id) ON DELETE CASCADE`、token_hash UNIQUE 各 1 件、session テーブルを参照する逆 FK なし。

### 実行結果

- admin_sessions REVOKE：`Success. No rows returned`。
- employee_sessions REVOKE：`Success. No rows returned`。

### 文間スモーク

- admin_sessions 実行後：admin-app 新規ログイン OK / 画面表示 OK / RPC 利用 OK / logout OK、genka-app 新規ログイン OK / 画面表示 OK / RPC 利用 OK / logout OK。
- employee_sessions 実行後：従業員画面 新規ログイン OK / 画面表示 OK / 日報系 RPC 利用 OK / logout OK。

### 実行後確認結果（Post-check P-1〜P-7・Supabase SQL Editor・2026-07-11）

- P-1：両テーブル × `anon` / `authenticated` の SELECT / INSERT / UPDATE / DELETE は全て false。
- P-2：relacl 上の `anon` / `authenticated` 向け CRUD grant = 0 rows。
- P-3：RLS = true、FORCE RLS = false を維持。
- P-4：policy = 0 rows を維持。
- P-5：login / logout RPC 4 本は存在。`anon` / `authenticated` の全 8 組み合わせで EXECUTE = true。
- P-6：session 参照 routine 42 本。全て SECURITY DEFINER、owner は全て postgres、owner 権限・RLS bypass・search_path 固定を維持。INSERT 2 本、UPDATE 0 本、DELETE 4 本で不変。
- P-7：postgres / service_role は両テーブルとも DELETE / INSERT / MAINTAIN / REFERENCES / SELECT / TRIGGER / TRUNCATE / UPDATE の 8 権限を維持（合計 32 行）。対象外権限に変化なし。

### 確認手段

- DB 確認・実行はすべてユーザーが Supabase SQL Editor で手動実行。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

### 関連

- PR #95（`docs/sql/phase4f-2b-3-session-direct-grant-revoke.sql` 追加、merge commit `a9e6cd3`、SQL 追加 commit `c9c8e42`）。
- SQL：`docs/sql/phase4f-2b-3-session-direct-grant-revoke.sql`（STATUS を `EXECUTED (2026-07-11)` に更新）。

## 2026-07-11 Phase 4-F-2B-4 companies read RPC追加（★実行済み★）

### 目的

- admin-app.html の companies direct SELECT を RPC へ移行する準備。
- management session 検証付き read RPC を追加。
- frontend 移行、SELECT REVOKE、policy DROP は後続工程。

### 追加RPC

- `public.list_companies_secure(session_token_input text)`
- `RETURNS TABLE (id uuid, name text)`
- `WHERE is_active = true`
- `ORDER BY name`
- `STABLE`
- `SECURITY DEFINER`
- `SET search_path = public, extensions`

### 認証

- `public._verify_management_session(text)` を内部利用。
- helper は `anon` / `authenticated` から直接 EXECUTE 不可。

### 実行結果（Supabase SQL Editor・1文ずつ手動実行・2026-07-11）

- CREATE FUNCTION：Success. No rows returned
- REVOKE ALL FROM PUBLIC：Success. No rows returned
- GRANT EXECUTE TO anon, authenticated：Success. No rows returned

### 実行前確認結果（Pre-check C-1〜C-8・Supabase SQL Editor・2026-07-11）

- C-1〜C-8：全通過。
- companies は RLS = true、FORCE RLS = false、owner = postgres。
- `anon` / `authenticated` は SELECT = true。
- relacl 上は SELECT のみ。
- `companies_select_public` 存在。
- companies 参照 routine 7 本は全て SECURITY DEFINER。
- `_verify_management_session` は安全に流用可能。
- frontend 実使用列は id / name のみ。
- `list_companies_secure` は未作成だった。

### 実行後確認結果（Post-check P-1〜P-5・Supabase SQL Editor・2026-07-11）

- `list_companies_secure(text)` 存在。
- 戻り値 `TABLE (id uuid, name text)`。
- SECURITY DEFINER = true。
- STABLE = true。
- owner = postgres。
- search_path 固定。
- PUBLIC EXECUTE = false。
- `anon` / `authenticated` EXECUTE = true。
- companies table 権限不変。
- RLS / FORCE RLS 不変。
- `companies_select_public` 不変。
- management session 検証あり。
- `is_active = true`。
- `ORDER BY name`。
- companies への write なし。

### 非対象（今回触れていない）

- admin-app.html。
- table SELECT REVOKE。
- `companies_select_public` DROP。
- companies データ。
- RLS 変更。
- docs/roadmap.md。
- 他テーブル。

### 確認手段

- DB 確認・実行はユーザーが Supabase SQL Editor で手動実行。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。
- frontend 未移行のため画面スモークは未実施。

### 関連

- PR #97（`docs/sql/phase4f-2b-4-companies-read-rpc.sql` 追加、merge commit `1f015c4`、SQL 追加 commit `b71ec09`）。
- SQL：`docs/sql/phase4f-2b-4-companies-read-rpc.sql`（STATUS を `EXECUTED (2026-07-11)` に更新）。

## 2026-07-11 Phase 4-F-2B-4 companies direct read撤廃（★実行済み★）

### 目的

- companies 取得を secure RPC へ完全移行。
- anon / authenticated の direct SELECT を撤廃。
- 不要な public SELECT policy を削除。

### 前提

- RPC 追加 PR #97。
- RPC 実行記録 PR #98。
- frontend 移行 PR #99。
- PR #99 merge commit `defb0d8`。
- 本番で会社ドロップダウン・会社名表示 確認済み。

### 実行SQL

- `REVOKE SELECT ON TABLE public.companies FROM anon, authenticated`
- `DROP POLICY companies_select_public ON public.companies`

### 実行結果（Supabase SQL Editor・1文ずつ手動実行・2026-07-11）

- 2 文とも Success. No rows returned。
- Supabase SQL Editor でユーザーが 1 文ずつ手動実行。

### 実行前確認結果（Pre-check・Supabase SQL Editor・2026-07-11）

- anon / authenticated SELECT = true。
- INSERT / UPDATE / DELETE = false。
- `companies_select_public` 1 件。
- `is_active = true` の SELECT policy。

### 実行後確認結果（Post-check・Supabase SQL Editor・2026-07-11）

- anon / authenticated SELECT = false。
- companies policy_count = 0。
- 本番再ログイン後も会社ドロップダウン正常。
- 最終本番スモーク正常。

### 最終状態

- frontend は `list_companies_secure` を使用。
- companies direct SELECT なし。
- anon / authenticated table SELECT 権限なし。
- companies policy 0 件。
- RLS = true。
- FORCE RLS = false。
- companies データ変更なし。

### 非対象（今回触れていない）

- INSERT / UPDATE / DELETE。
- RPC 定義変更。
- frontend 追加変更。
- 他テーブル。
- docs/roadmap.md。

### 確認手段

- DB 確認・実行はユーザーが Supabase SQL Editor で手動実行。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

### 関連

- PR #97 / PR #98 / PR #99（merge commit `defb0d8`）。
- SQL：`docs/sql/phase4f-2b-4-companies-read-rpc.sql`。
- SQL：`docs/sql/phase4f-2b-4-companies-direct-read-revoke.sql`（STATUS `EXECUTED (2026-07-11)`）。

## 2026-07-11 Phase 4-F-2B-4 materials read RPC追加（★実行済み★）

### 目的

- index.html の materials direct SELECT を secure RPC へ移行する準備。
- employee session 検証付き read RPC を追加。
- frontend 移行、SELECT REVOKE、policy DROP は後続工程。

### 追加RPC

- `public.list_materials_secure(session_token_input text)`
- `RETURNS TABLE (id uuid, name text)`
- `WHERE is_active = true`
- `ORDER BY name`
- `STABLE`
- `SECURITY DEFINER`
- `SET search_path = public, extensions`

### 認証（session検証）

- `public.employee_sessions` と `public.employees` を JOIN。
- token hash 照合（`encode(digest(session_token_input, 'sha256'), 'hex')`）。
- `expires_at > now()`。
- `employees.is_active = true`。
- 無効・期限切れ時は `Invalid or expired session` を RAISE。
- 共通 helper は新設せず inline 検証（既存 employee-session RPC 踏襲）。

### 実行結果（Supabase SQL Editor・1 batch で手動実行・2026-07-11）

- CREATE FUNCTION / REVOKE ALL FROM PUBLIC / GRANT EXECUTE TO anon, authenticated を
  1 つの batch として手動実行。
- Success. No rows returned。

### 実行後確認結果（統合 Post-check・Supabase SQL Editor・2026-07-11）

- 関数属性・owner・search_path 正常（SECURITY DEFINER = true、STABLE = true、
  owner = postgres、search_path 固定）。
- PUBLIC EXECUTE なし。
- `anon` / `authenticated` EXECUTE あり。
- employee session 検証あり（employee_sessions / employees 参照、`expires_at > now()`、
  `employees.is_active = true`）。
- materials read-only（materials への write なし、`is_active = true`、`ORDER BY name`）。
- active 10 件。
- table grant / RLS / policy は現時点で不変（anon / authenticated の materials SELECT は
  まだ true、RLS = true、FORCE RLS = false、owner = postgres、policy_count = 1、
  `materials_read_all` 不変）。

### スモークテスト（ブラウザ Console・有効 employee session・2026-07-11）

- ブラウザ Console から有効な employee session で RPC 実行。
- error = null、count = 10、rows = Array(10)。
- session token 実値は記録しない。

### 最終状態

- RPC 作成済み。
- frontend はまだ direct SELECT。
- anon / authenticated の materials SELECT はまだ true。
- `materials_read_all` policy はまだ存在。
- materials データ変更なし。

### 非対象（今回触れていない）

- index.html。
- table SELECT REVOKE。
- `materials_read_all` policy DROP。
- RLS 変更。
- materials データ。
- docs/roadmap.md。
- 他テーブル。

### 確認手段

- DB 確認・実行はユーザーが Supabase SQL Editor で手動実行。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

### 関連

- PR #102（`docs/sql/phase4f-2b-4-materials-read-rpc.sql` 追加、merge commit `8fa4c82`、
  SQL 追加 commit `113f690`）。
- SQL：`docs/sql/phase4f-2b-4-materials-read-rpc.sql`（STATUS を `EXECUTED (2026-07-11)` に更新）。

## 2026-07-11 Phase 4-F-2B-4 materials frontend移行・最終権限確認（★完了★）

### 目的

- index.html の materials direct read を `list_materials_secure` RPC へ移行し、materials 読み取りを secure RPC 経由に一本化する。
- 移行後の最終状態（frontend / 本番 / DB 権限）を確認し、materials 読み取り保護の完了を記録する。

### 前提

- materials read RPC 追加 PR #102（`list_materials_secure` 作成・実行済み）。
- RPC 実行記録 PR #103。
- 本エントリで frontend 移行 PR #104 と最終 DB post-check を記録する。

### frontend移行

- 対象: `index.html` のみ。
- PR #104（merge commit `bfe54da`）。
- `loadMaterials()` の materials direct read（`sb.from('materials').select('*').eq('is_active',true).order('name')`）を `sb.rpc('list_materials_secure', {session_token_input: token})` へ移行。
- session token は既存の `state.currentUser?.session_token` を再利用（新規認証・token 保存処理の追加なし）。
- `state.materials = data || []` を維持。
- 後続の `renderMaterialRows()` / `renderMaster()` を維持。
- RPC エラー時は `console.error('list_materials_secure failed:', error)` で記録。
- `.from('materials')` 残存 0 件。
- materials 利用カラムは `id` / `name` のみ（RPC 戻り値 `TABLE (id uuid, name text)` で成立）。

### Preview・本番確認

- 従業員ログイン OK。
- 日報入力画面 OK。
- 材料一覧 10 件表示。
- 材料選択 OK。
- Console エラーなし。
- `list_materials_secure failed` なし。
- Network で RPC 成功。
- materials direct GET なし。
- Vercel Production Ready。

### 最終DB post-check（Supabase SQL Editor・read-only 確認）

- RLS = true。
- FORCE RLS = false。
- anon / authenticated SELECT = false。
- anon / authenticated INSERT / UPDATE / DELETE = false。
- policies = []。
- total_count = 12。
- active_count = 10。
- inactive_count = 2。
- null_active_count = 0。
- `list_materials_secure`：SECURITY DEFINER = true、STABLE = true、owner = postgres、`RETURNS TABLE (id uuid, name text)`、search_path = `public, extensions`。
- anon / authenticated EXECUTE = true。
- PUBLIC EXECUTE = false。

### 画面10件とDB総数12件の整合

- 画面表示は 10 件、materials 総数は 12 件。
- `list_materials_secure` は `is_active = true` の active 10 件のみ返し、inactive 2 件を返さないため、画面 10 件と DB 総数 12 件は矛盾しない。

### 権限変更SQLについて

- 権限撤廃用 SQL は事前条件確認で `materials_read_all policy not found` により停止した。
- `REVOKE SELECT` と `DROP POLICY` より前で停止したため、当該 SQL による DB 変更は実行されていない。
- その後の read-only 確認で、SELECT 権限なし・policy なしの最終安全状態を確認した。
- 追加 DB 変更は不要と判断した。
- いつ、どの操作でその状態になったかは確定していないため記載しない。

### 最終状態

- frontend は `list_materials_secure` を使用（direct read なし）。
- anon / authenticated の materials SELECT なし。
- materials policy 0 件。
- materials 読み取りは secure RPC（employee session 検証・SECURITY DEFINER）経由に一本化。
- materials データ変更なし。

### 非対象（今回触れていない）

- docs/roadmap.md。
- SQL ファイル新規作成。
- SQL 実行 / DB 変更。
- 他テーブル。
- RPC 定義変更。
- frontend 追加変更。

### 確認手段

- DB 確認はユーザーが Supabase SQL Editor で read-only 実行。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

### 関連

- PR #102（materials read RPC SQL 追加）。
- PR #103（DB 実行記録）。
- PR #104（frontend 移行、merge commit `bfe54da`）。
- SQL：`docs/sql/phase4f-2b-4-materials-read-rpc.sql`。

## 2026-07-11 Phase 4-F-2B-5 machines read RPC追加（★実行済み★）

### 目的

- machines direct read 撤廃の前段として、secure read RPC を2本追加。
- index.html（従業員画面）用と、admin-app.html / genka-app.html（management 画面）用を分離。
- この段階では frontend 移行・SELECT REVOKE・policy 削除は未実施（後続工程）。

### 追加RPC

1. `public.list_machines_secure(session_token_input text)`

- employee session inline 検証（`list_materials_secure` と同型）。
- active machines のみ（`is_active = true`）。
- `ORDER BY name`。
- `RETURNS TABLE (id uuid, name text, ownership text, lease_company text, lease_start date, lease_end date, lease_monthly integer)`。

2. `public.list_machines_admin_secure(session_token_input text, include_inactive_input boolean DEFAULT false)`

- `public._verify_management_session(text)` を再利用（無改変）。
- `include_inactive_input` = false / NULL：active のみ。
- `include_inactive_input` = true：inactive を含む全件。
- `ORDER BY name`。
- `RETURNS TABLE (id uuid, name text, company_id uuid, ownership text, lease_company text, lease_start date, lease_end date, lease_monthly integer, is_active boolean)`。

### 認証・権限

両 RPC とも：

- SECURITY DEFINER。
- STABLE。
- owner = postgres。
- `SET search_path = public, extensions`。
- PUBLIC EXECUTE なし。
- anon EXECUTE あり。
- authenticated EXECUTE あり。
- machines への write 処理なし（read-only）。

### 関連PR

- PR #106（`docs/sql/phase4f-2b-5-machines-read-rpc.sql` 追加、merge commit `00d35e8`、SQL 追加 commit `69f173a`）。
- SQL：`docs/sql/phase4f-2b-5-machines-read-rpc.sql`（STATUS を `EXECUTED (2026-07-11)` に更新）。

### 実行結果（Supabase SQL Editor・手動実行・2026-07-11）

- ユーザーが Supabase SQL Editor で EXECUTION BODY を手動実行。
- 結果：Success. No rows returned。
- Supabase CLI / psql / 外部 DB 接続は未使用。

### 実行前確認結果（Pre-check C-1〜C-9・Supabase SQL Editor・2026-07-11）

- C-1〜C-9：全合格。
- machines：schema = public、relkind = 'r'、RLS = true、FORCE RLS = false、owner = postgres。
- anon / authenticated：SELECT = true、INSERT / UPDATE / DELETE = false。
- RPC 前提の9列（id / name / company_id / ownership / lease_company / lease_start / lease_end / lease_monthly / is_active）の存在・型一致。
- policy 3件：`machines_write` / `machines_read_all` / `machines_update`（記録のみ・無変更）。
- employee session 検証カラム5件（employee_sessions.employee_id / token_hash / expires_at、employees.id / is_active）存在。
- `_verify_management_session(text)`：SECURITY DEFINER = true、owner = postgres、search_path = public, extensions。
- 新設予定 RPC 2本は事前に 0 件（未作成）。
- machines 件数：total = 26、active = 22、inactive = 4、null_active = 0。
- 既存 machines write RPC 5本の存在・属性確認済み（P-6 の基準スナップショット）。

### 実行後確認結果（Post-check P-1〜P-6・Supabase SQL Editor・2026-07-11）

- P-1〜P-6：全合格。
- 新設 RPC 2本存在。
- SECURITY DEFINER = true、STABLE、owner = postgres、search_path 固定。
- RETURNS TABLE：employee 用 7列 / admin 用 9列（宣言どおり）。
- anon / authenticated EXECUTE = true。
- PUBLIC EXECUTE なし。
- machines table 権限は事前値（C-2）から不変。
- RLS / FORCE RLS 不変。
- policy 3件不変。
- 既存 write RPC 5本不変。

### スモークテスト（有効な employee / management session・2026-07-11）

- employee RPC（`list_machines_secure`）：error = null、count = 22。既存 active direct read count = 22。sameRows = true（集合一致）。
- admin RPC（`list_machines_admin_secure`）：
  - include_inactive = false：error = null、count = 22。
  - include_inactive = true：error = null、count = 26。
  - include_inactive = null：error = null、count = 22。
- session token 実値は記録しない。

### 最終状態

- RPC 作成と DB 確認までは完了。
- machines table の anon / authenticated SELECT 権限はまだ維持。
- `machines_read_all` policy はまだ存在。
- frontend はまだ direct read（5箇所）。
- frontend 移行後に権限撤廃・policy 整理の判断へ進む。

### 非対象（今回触れていない）

- frontend 変更（index.html / admin-app.html / genka-app.html）。
- anon / authenticated の machines SELECT REVOKE。
- `machines_read_all` policy DROP。
- `machines_update` / `machines_write` policy 変更。
- 既存 machines write RPC 5本の変更。
- machine_locations direct read 対応（別工程候補）。
- docs/roadmap.md。
- 他テーブル。

### 確認手段

- DB 確認・実行はユーザーが Supabase SQL Editor で手動実行。
- スモークテストは Browser Console で実施（実 token 値は記録しない）。
- 手順・実測値の詳細は `docs/sql/phase4f-2b-5-machines-read-rpc.sql` に記録。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

## 2026-07-12 Phase 4-F-2B-5 machines direct read撤廃（★実行済み★）

### 目的

- machines の読み取りを secure RPC 経由へ一本化。
- frontend direct read 移行後、anon / authenticated の SELECT 権限を撤廃。
- SELECT 用 policy `machines_read_all` を削除。

### 前提

- frontend 移行 PR #108 merge 済み（merge commit `80ba140`）。
- frontend 3画面（index.html / admin-app.html / genka-app.html）を read RPC へ移行済み。
- リポジトリ全体で `.from('machines')` は 0 件。
- Preview・本番の3画面確認済み。
- read RPC 2本（`list_machines_secure` / `list_machines_admin_secure`）が本番動作確認済み。

### 関連PR・SQL

- 撤廃 SQL PR #109（`docs/sql/phase4f-2b-5-machines-direct-read-revoke.sql` 追加、merge commit `ea4903a`（full: `ea4903ae68109b73643e7f9fe486ee276bc8e6ff`）、SQL 追加 commit `683112c`）。
- SQL：`docs/sql/phase4f-2b-5-machines-direct-read-revoke.sql`（STATUS を `EXECUTED (2026-07-12)` に更新）。

### 実行SQL（Supabase SQL Editor・1文ずつ手動実行・2026-07-12）

1. `REVOKE SELECT ON TABLE public.machines FROM anon, authenticated;`
2. `DROP POLICY machines_read_all ON public.machines;`

### 実行結果

- 2文とも Success. No rows returned。
- Supabase SQL Editor でユーザーが 1 文ずつ手動実行。
- DB 接続・Supabase CLI・psql は未使用。
- rollback は未実行。

### 実行前確認結果（Pre-check C-1〜C-7・Supabase SQL Editor・2026-07-12）

- C-1〜C-7：全合格。
- public.machines：relkind = 'r'、RLS = true、FORCE RLS = false、owner = postgres。
- anon / authenticated：SELECT = true、INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN = false。
- policy 3件（定義完全一致）：
  - `machines_read_all`：PERMISSIVE / {public} / SELECT / qual = true / with_check = null。
  - `machines_update`：PERMISSIVE / {public} / UPDATE / qual = true / with_check = null。
  - `machines_write`：PERMISSIVE / {public} / INSERT / qual = null / with_check = true。
- read RPC 2本（`list_machines_secure(text)` / `list_machines_admin_secure(text, boolean)`）：SECURITY DEFINER、STABLE、owner = postgres、search_path = public, extensions。anon / authenticated EXECUTE = true。PUBLIC EXECUTE なし。
- write RPC 5本（`create_machine_secure` / `update_machine_secure` / `deactivate_machine_secure` / `create_machine_admin_secure` / `update_machine_admin_secure`）：SECURITY DEFINER、VOLATILE、owner = postgres、search_path = public, extensions。
- 件数参考値：total = 26、active = 22、inactive = 4、null_active = 0（件数は合否基準ではない）。

### 実行後確認結果（Post-check P-1〜P-6・Supabase SQL Editor・2026-07-12）

- P-1〜P-6：全合格。
- anon / authenticated：SELECT = false。その他7権限（INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN）もすべて false。
- policy：`machines_read_all` 削除済み。`machines_update` / `machines_write` 残存。policy 総数 = 2。
- table 属性：relkind = 'r'、RLS = true、FORCE RLS = false、owner = postgres（不変）。
- read RPC 2本：属性不変。anon / authenticated EXECUTE = true。PUBLIC EXECUTE なし。
- write RPC 5本：属性不変。
- 件数参考値：total = 26、active = 22、inactive = 4、null_active = 0（件数は合否基準ではない）。

### 本番スモークテスト（Browser DevTools・2026-07-12・実 token 値は記録しない）

#### 従業員画面（index.html）

- 重機一覧・現在地・移動・設定 正常。
- `list_machines_secure` Status 200。
- machines direct read なし。
- Console エラーなし。

#### 管理画面（admin-app.html）

- 全26件・無効4件の表示 正常。
- 編集・新規追加モーダル 正常。
- `list_machines_admin_secure` Status 200。
- machines direct read なし。
- Console エラーなし。

#### 原価管理画面（genka-app.html）

- 原価集計・リース料表示 正常。
- `list_machines_admin_secure` Status 200。
- machines direct read なし。
- Console エラーなし。

### 最終状態

- anon / authenticated の machines SELECT 権限は撤廃済み。
- `machines_read_all` policy は削除済み。
- `machines_update` / `machines_write` policy は維持（変更なし）。
- read RPC 2本は正常。
- write RPC 5本は正常。
- RLS / FORCE RLS / owner は不変。
- machines の読み取りは secure RPC 経由へ一本化。
- Phase 4-F-2B-5 machines read 保護工程（read RPC 追加 → frontend 移行 → direct read 撤廃）は完了。

### 非対象（今回触れていない）

- `machines_update` / `machines_write` policy の削除。
- write RPC の変更。
- machine_locations direct read 対応（別工程候補）。
- frontend 追加変更。
- docs/roadmap.md。
- 他テーブル。
- rollback 実行。

### 確認手段

- DB 確認・実行はユーザーが Supabase SQL Editor で手動実行。
- スモークテストは本番3画面で Browser DevTools（Console / Network）により実施（実 token 値は記録しない）。
- 手順・実測値の詳細は `docs/sql/phase4f-2b-5-machines-direct-read-revoke.sql` の pre-check / post-check に記録。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

## 2026-07-13 Phase 4-F-2B-6 machine_locations read RPC追加（★実行済み★）

### 目的

- machine_locations direct read 撤廃の前段として、employee 用 secure read RPC を2本追加。
- index.html（従業員画面）の重機タブが machine_locations を直接読まずに済むようにする。
  - `loadMachineLocations()`：重機ごとの最新位置を取る N+1 direct read。
  - `openMachineMove()`：指定重機の移動履歴10件の direct read。
- この段階では frontend 移行・SELECT REVOKE・policy 削除は未実施（後続工程）。

### Git / PR

- Phase 4-F-2B-6 machine_locations read RPC追加。
- PR #111。
- merge commit：`5c74904`。
- SQL source commit：`a186845`。
- SQL：`docs/sql/phase4f-2b-6-machine-locations-read-rpc.sql`（STATUS を `EXECUTED (2026-07-13)` に更新）。

### 追加RPC

1. `public.list_machine_current_locations_secure(session_token_input text)`

- employee session inline 検証（`list_machines_secure` と同型）。
- active machines のみ（`JOIN machines ON is_active = true`）。
- active machine ごとの最新位置を最大1件（`DISTINCT ON (machine_id)`）。
- 位置履歴のない active machine は返却行なし。
- `ORDER BY machine_id, moved_at DESC, id DESC`。
- `RETURNS TABLE (machine_id uuid, site_id uuid, moved_at timestamptz, memo text)`。

2. `public.list_machine_location_history_secure(session_token_input text, machine_id_input uuid)`

- employee session inline 検証（RPC 1 と同型）。
- active machines のみ（`JOIN machines ON is_active = true`）。
- 指定 machine の移動履歴を最大10件。
- 不存在・inactive machine は 0件。
- `ORDER BY moved_at DESC, id DESC`、`LIMIT 10`。
- `RETURNS TABLE (machine_id uuid, site_id uuid, moved_at timestamptz, memo text)`。

### 認証・権限

両 RPC とも：

- SECURITY DEFINER = true。
- STABLE。
- owner = postgres。
- `SET search_path = public, extensions`。
- PUBLIC EXECUTE なし。
- anon EXECUTE あり。
- authenticated EXECUTE あり。
- machine_locations への write 処理なし（read-only）。

### 実行結果（Supabase SQL Editor・手動実行・2026-07-13）

- ユーザーが Supabase SQL Editor で EXECUTION BODY を手動実行。
- 結果：Success. No rows returned。
- `public.list_machine_current_locations_secure(text)` 作成済み。
- `public.list_machine_location_history_secure(text, uuid)` 作成済み。
- Supabase CLI / psql / 外部 DB 接続は未使用（DB 実行はユーザーが手動で実施）。

### 実行前確認結果（Pre-check C-1〜C-12・Supabase SQL Editor・2026-07-13）

- C-1〜C-12：全合格。
- machine_locations：relkind = 'r'、RLS = true、FORCE RLS = false、owner = postgres。
- total rows = 41。
- distinct machine_id = 20。
- active machines = 22。
- active machine で最新位置あり = 20。
- active machine で履歴なし = 2。
- orphan machine_id = 0。
- orphan site_id = 0。
- duplicate (machine_id, moved_at) = 0。
- DISTINCT ON と従来の machine 別 LIMIT 1 の mismatch = 0。
- 新規 RPC 名衝突 = 0。
- 複合 index なし（現件数では index 追加なし）。

### 実行後確認結果（Post-check P-1〜P-7・Supabase SQL Editor・2026-07-13）

- P-1〜P-7：全合格。
- 新設 RPC 2本存在。
- signature 正常（`(text)` / `(text, uuid)`）。
- RETURNS TABLE 正常（両 RPC とも machine_id uuid / site_id uuid / moved_at timestamptz / memo text の4列）。
- SECURITY DEFINER = true、STABLE、owner = postgres、search_path 固定。
- anon / authenticated EXECUTE = true。
- PUBLIC EXECUTE なし。
- machine_locations table 権限は事前値（C-3）から不変。
- RLS / FORCE RLS 不変。
- policy 2件不変（`ml_read` / `ml_write`）。
- `create_machine_location_secure` 不変。

### スモークテスト（有効な employee session・2026-07-13）

- `list_machine_current_locations_secure`：error = null、count = 20、返却列正常。
- `list_machine_location_history_secure`：error = null、tested machine の履歴取得（当該 machine 1件）、10件上限 OK、moved_at 降順 OK。
- negative（無効 token）：両 RPC とも `Invalid or expired session`。HTTP 400 は意図した RPC 例外。
- negative（存在しない machine UUID）：error = null、0件（smoke test 実測済み）。
- inactive machine：RPC 設計上は 0件になるが（`JOIN machines ON is_active = true`）、個別の smoke test は未実施。
- session token 実値は記録しない。

### 最終状態

- RPC 作成と DB 確認までは完了。
- machine_locations table の anon / authenticated SELECT 権限はまだ維持。
- `ml_read` / `ml_write` policy はまだ存在。
- frontend はまだ direct read（index.html 2箇所）。
- frontend 移行後に権限撤廃・policy 整理の判断へ進む。

### 非変更事項（今回の DB 実行で触れていない）

- machine_locations の anon / authenticated SELECT grant。
- `ml_read` policy。
- `ml_write` policy。
- RLS / FORCE RLS。
- `create_machine_location_secure`。
- frontend（index.html の direct read 2件）。
- machine_locations の SELECT REVOKE。
- policy 削除。
- docs/roadmap.md。
- 他テーブル。

### 次工程（未完了）

- frontend 移行（index.html の direct read 2件を RPC へ移行）。
- N+1 解消。
- Preview / Production 確認。
- machine_locations の SELECT REVOKE。
- `ml_read` 削除。
- Phase 4-F-2B-6 の最終クローズ。

### 確認手段

- DB 確認・実行はユーザーが Supabase SQL Editor で手動実行。
- スモークテストは有効な employee session で実施（実 token 値は記録しない）。
- 手順・実測値の詳細は `docs/sql/phase4f-2b-6-machine-locations-read-rpc.sql` の pre-check / post-check に記録。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

## 2026-07-13 Phase 4-F-2B-6（side step）machine_locations write RPC PUBLIC EXECUTE 撤廃（★実行済み★）

### 位置づけ

- Phase 4-F-2B-6 の side step。machine_locations direct read 撤廃の pre-check 中に、write RPC へ明示的な PUBLIC EXECUTE 付与が判明したため、先に PUBLIC のみ撤廃した。
- 本記録の merge 後、元の machine_locations direct read 撤廃の pre-check に復帰する（direct read 撤廃 BODY はまだ未実行）。

### 発見経緯

- `docs/sql/phase4f-2b-6-machine-locations-direct-read-revoke.sql` の pre-check（write RPC baseline）実行中に、`create_machine_location_secure` の ACL に明示 PUBLIC EXECUTE を検出。
- 関数内部で employee session を検証しており認証バイパスは確認されていないが、PUBLIC EXECUTE は不要な過剰権限のため撤廃。

### 対象

- `public.create_machine_location_secure(text, uuid, uuid, text)`

### Git / PR

- SQL：`docs/sql/phase4f-2b-6-machine-location-write-rpc-public-execute-revoke.sql`（STATUS を `EXECUTED 2026-07-13` に更新）。
- SQL source PR：#115（merge commit `2086f3f`）。

### 実行結果（Supabase SQL Editor・手動実行・2026-07-13）

- ユーザーが Supabase SQL Editor で EXECUTION BODY を手動実行：

```sql
BEGIN;
REVOKE EXECUTE
ON FUNCTION public.create_machine_location_secure(text, uuid, uuid, text)
FROM PUBLIC;
COMMIT;
```

- 結果：Success. No rows returned。
- Supabase CLI / psql / 外部 DB 接続は未使用（DB 実行はユーザーが手動で実施）。

### 変更内容

- PUBLIC EXECUTE のみ REVOKE。

### 保持（非変更）

- anon / authenticated / postgres / service_role の EXECUTE は維持。
- 関数定義・属性（SECURITY DEFINER / VOLATILE / owner postgres / search_path / result type = TABLE(id uuid)）は不変。
- machine_locations data / table grants / `ml_read` / `ml_write` / RLS / FORCE RLS は不変。
- read RPC 2本（`list_machine_current_locations_secure` / `list_machine_location_history_secure`）は不変。

### 実行前確認結果（Pre-check C-1〜C-4 + C-3b・2026-07-13）

- C-1〜C-4 + C-3b：全合格。
- C-3b：execute_acl_count = 5、grantees = {PUBLIC, anon, authenticated, postgres, service_role}、grantable_count = 0。

### 実行後確認結果（Post-check P-1〜P-5 + P-2b / P-2c・2026-07-13）

- P-1〜P-5 + P-2b / P-2c：全合格。
- P-2b：PUBLIC EXECUTE = 0行。
- P-2c：execute_acl_count = 4、grantees = {anon, authenticated, postgres, service_role}、grantable_count = 0。
- P-3 / P-4：関数属性・定義とも C-1 / C-4 から不変。

### スモークテスト

- 実データを追加する write smoke test は実施していない（不要な移動履歴を作成しない方針）。write path 健全性は P-3 / P-4（属性・定義不変）と P-1 / P-2（ロール別 EXECUTE 維持）で担保。

### rollback

- 未実施（コメントの参照用のみ）。

### 次工程

- 元の machine_locations direct read 撤廃（`docs/sql/phase4f-2b-6-machine-locations-direct-read-revoke.sql`）の pre-check に復帰。BODY はまだ未実行。

### 確認手段

- DB 確認・実行はユーザーが Supabase SQL Editor で手動実行。
- 手順・実測値の詳細は `docs/sql/phase4f-2b-6-machine-location-write-rpc-public-execute-revoke.sql` の pre-check / post-check に記録。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

## 2026-07-13 Phase 4-F-2B-6 machine_locations direct read撤廃（★実行済み★・machine_locations read保護 完了）

### 目的

- machine_locations の読み取りを secure read RPC 経由へ一本化し、anon / authenticated の直接 SELECT 経路を閉じる。
- frontend 移行・本番確認の完了後に、direct SELECT grant と `ml_read` policy を撤廃。

### 対象

- `public.machine_locations`

### Git / PR

- frontend read RPC 移行：PR #113（merge commit `d50d585`）。
- direct read 撤廃 SQL：`docs/sql/phase4f-2b-6-machine-locations-direct-read-revoke.sql`（PR #114・merge commit `6fd9673`。STATUS を `EXECUTED 2026-07-13` に更新）。
- side step（write RPC PUBLIC EXECUTE 撤廃）：SQL PR #115（merge commit `2086f3f`）／ 実行記録 PR #116（merge commit `6f79dd3`）。
  ※ PR #114 の merge commit は `6fd9673`、PR #116 の merge commit は `6f79dd3`。別物のため混同しない。

### 実行結果（Supabase SQL Editor・手動実行・2026-07-13）

- ユーザーが Supabase SQL Editor で EXECUTION BODY を手動実行（単一トランザクション）：

```sql
BEGIN;
REVOKE SELECT ON TABLE public.machine_locations FROM anon, authenticated;
DROP POLICY ml_read ON public.machine_locations;
COMMIT;
```

- 結果：Success. No rows returned。
- Supabase CLI / psql / 外部 DB 接続は未使用（DB 実行はユーザーが手動で実施）。

### 変更内容

- anon / authenticated の machine_locations SELECT を REVOKE。
- `ml_read` policy を DROP。

### 保持（非変更）

- `ml_write` policy は維持（PERMISSIVE / {public} / INSERT / with_check true）。
- RLS / FORCE RLS / owner は不変（true / false / postgres）。
- read RPC 2本（`list_machine_current_locations_secure` / `list_machine_location_history_secure`）は不変。
- write RPC `create_machine_location_secure(text, uuid, uuid, text)` は不変（PUBLIC EXECUTE は side step で撤廃済み）。

### 実行前確認結果（Pre-check C-1〜C-7・2026-07-13）

- C-1〜C-7：全合格。
- C-2b：anon / authenticated の SELECT ACL（is_grantable=false）・PUBLIC SELECT なし。
- C-3：policy_count = 2（ml_read + ml_write）。
- C-4c/C-4d：read RPC の anon/authenticated EXECUTE=true・PUBLIC EXECUTE=0行。
- C-5c：write RPC PUBLIC EXECUTE=0行（side step 撤廃結果を確認）。
- C-7：total_rows = 42（過去記録41件から実データ1件増。BODY 実行前の増加で問題なし。P-6 との不変比較には42件を使用）。

### 実行後確認結果（Post-check P-1〜P-6・2026-07-13）

- P-1〜P-6：全合格。
- P-1：anon / authenticated とも8権限すべて false（SELECT 撤廃）。
- P-1b：PUBLIC / anon / authenticated の SELECT ACL = 0行。
- P-2：policy_count = 1（ml_write のみ・定義不変）。ml_read 削除済み。
- P-3：RLS true / FORCE RLS false / owner postgres（不変）。
- P-4：read RPC 2本不変（属性・返却列4件・EXECUTE・PUBLIC EXECUTE 0行）。
- P-5：write RPC 不変（属性・result type=TABLE(id uuid)・args・EXECUTE・PUBLIC EXECUTE 0行）。
- P-6：total_rows = 42（C-7 と一致。BODY による data 変更なし）。

### 本番スモークテスト（2026-07-13・実 token 値は記録しない）

- 重機一覧・現在地・移動履歴の表示 OK。
- `list_machine_current_locations_secure` = 200、`list_machine_location_history_secure` = 200。
- `/rest/v1/machine_locations` direct read = 0件。Console 赤エラーなし。
- 実データを追加する write smoke test は未実施（不要な移動履歴を作成しない方針）。write RPC 属性・定義・EXECUTE 維持は DB post-check（P-5）で確認済み。

### rollback

- 未実施（コメントの参照用のみ）。

### 最終状態

- machine_locations の読み取りは secure read RPC 経由へ一本化。direct read 0件。
- **Phase 4-F-2B-6 machine_locations read 保護工程（read RPC 追加 → frontend 移行 → direct read 撤廃、および side step の write RPC PUBLIC EXECUTE 撤廃）は完了。**

### 確認手段

- DB 確認・実行はユーザーが Supabase SQL Editor で手動実行。
- 本番スモークテストは Browser DevTools（Console / Network）で実施（実 token 値は記録しない）。
- 手順・実測値の詳細は `docs/sql/phase4f-2b-6-machine-locations-direct-read-revoke.sql` の pre-check / post-check に記録。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。

## 2026-07-13 Phase 4-F-2B-7 subcontractors read RPC追加（★実行済み★・read RPCのDB実行工程完了）

### 位置づけ

- Phase 4-F-2B-7 subcontractors read 保護（read RPC 追加 → frontend 移行 → direct read 撤廃）の第1工程。
- 本記録で完了したのは **read RPC の DB 実行工程のみ**。Phase 4-F-2B-7 全体はまだ完了していない（次工程は後述）。

### 目的

- subcontractors direct read 撤廃の前段として、secure read RPC を2本追加。
- index.html（従業員画面）と genka-app.html（原価管理画面）が subcontractors を直接読まずに済むようにする。
- admin-app.html:330 の direct read は代入のみで未使用（死にコード）のため、frontend 工程では移行でなく削除予定。
- この段階では frontend 移行・SELECT REVOKE・policy 削除は未実施（後続工程）。

### Git / PR

- SQL：`docs/sql/phase4f-2b-7-subcontractors-read-rpc.sql`（STATUS を `EXECUTED 2026-07-13` に更新）。
- SQL source PR：#118（merge commit `f832954`）。

### 追加RPC

1. `public.list_subcontractors_secure(session_token_input text)`

- employee session inline 検証（`list_machines_secure` / `list_materials_secure` と同型）。
- active subcontractors のみ。
- `ORDER BY name, id`（id は決定的順序のための第2キー）。
- `RETURNS TABLE (id uuid, name text)`。

2. `public.list_subcontractors_admin_secure(session_token_input text)`

- 既存 helper `public._verify_management_session(text)` を再利用（`list_companies_secure` / `list_machines_admin_secure` と同型）。
- active subcontractors のみ。`ORDER BY name, id`。
- `RETURNS TABLE (id uuid, name text)`。
- include_inactive 引数なし（inactive を表示する画面が存在しないため意図的に省略）。

### 認証・権限

両 RPC とも：

- SECURITY DEFINER = true。
- STABLE。
- owner = postgres。
- `SET search_path = public, extensions`。
- PUBLIC EXECUTE なし。
- anon / authenticated EXECUTE あり（postgres / service_role も EXECUTE = true）。
- is_grantable = false・explicit ACL。
- subcontractors への write 処理なし（read-only）。

### 実行結果（Supabase SQL Editor・手動実行・2026-07-13）

- ユーザーが Supabase SQL Editor で EXECUTION BODY（plain CREATE FUNCTION 2本・BEGIN/COMMIT 単一トランザクション）を1回だけ手動実行。
- 結果：Success. No rows returned。
- `public.list_subcontractors_secure(text)` 作成済み。
- `public.list_subcontractors_admin_secure(text)` 作成済み。
- 同じ BODY の再実行なし。
- Supabase CLI / psql / 外部 DB 接続は未使用（DB 実行はユーザーが手動で実施）。

### 実行前確認結果（Pre-check C-1〜C-12・Supabase SQL Editor・2026-07-13）

- C-1〜C-12：全合格。
- C-1：relkind = 'r'、RLS = true、FORCE RLS = false、owner = postgres。
- C-2 / C-2b：anon / authenticated は SELECT のみ true（他7権限 false）。PUBLIC 権限なし・is_grantable = false。raw ACL = `{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}`。
- C-3：id uuid NOT NULL DEFAULT gen_random_uuid() / name text NOT NULL / is_active boolean NOT NULL DEFAULT true / created_at timestamptz NOT NULL DEFAULT now() / company_id uuid NULL。
- C-4：PK = subcontractors_pkey(id)（primary / unique / valid / ready）、FK = subcontractors_company_id_fkey（company_id → companies(id)）、constraints validated = true。
- C-5：policy_count = 1（sub_read / PERMISSIVE / {public} / SELECT / qual = true / with_check = null）。
- C-6：employee_sessions（employee_id uuid / token_hash text / expires_at timestamptz）確認済み。既存 secure RPC と同じ session 検証方式を使用可能。
- C-7：`_verify_management_session(text)` = SECURITY DEFINER true / VOLATILE / owner postgres / search_path = public, extensions。admin session と admin-role employee session の両方を検証（token hash / expiry / active / admin role、無効 session は例外）。
- C-8：新 RPC 名衝突 0件（実行直前の再確認でも 0件）。
- C-9 / C-9b：`export_projects_summary_secure` baseline 記録（SECURITY DEFINER / STABLE / owner postgres / search_path 固定 / subcontractors read-only 参照 / PUBLIC EXECUTE なし / anon・authenticated・postgres・service_role EXECUTE = true / explicit ACL / is_grantable = false）。
- C-10：total = 3、active = 3、inactive = 0、is_active null = 0。
- C-11：company_id orphan = 0、reports.subcontractor_ids orphan = 0。
- C-12：name 重複 0。unit_rates(category='subcontractor') と名前一致：大須賀商店 / 岡井重機 / 高瀬興行 各1件・いずれも 0円/式（0円は意図した運用）。unit_rates に is_active 列は存在しないことも実測済み。

### 実行後確認結果（Post-check P-1〜P-8・Supabase SQL Editor・2026-07-13）

- P-1〜P-8：全合格。
- P-1：両 RPC とも identity_arguments = `session_token_input text`、RETURNS TABLE(id uuid, name text)、SECURITY DEFINER = true、STABLE、owner = postgres、search_path = public, extensions。
- P-2：各名前とも1本のみ。想定外 overload なし。
- P-3：返却列は両 RPC とも (1) id uuid、(2) name text。
- P-4 / P-4b：anon / authenticated / postgres / service_role EXECUTE = true、PUBLIC 行なし、explicit ACL、is_grantable = false。raw ACL = `{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}`。
- P-5：subcontractors table 権限は事前値（C-2）から不変（SELECT true・他7権限 false）。
- P-6：RLS = true / FORCE RLS = false / owner = postgres 不変。policy_count = 1（sub_read 定義不変）。
- P-7 / P-7b：`export_projects_summary_secure` 不変（属性・identity arguments・EXECUTE・explicit ACL・is_grantable = false）。
- P-8（negative）：`list_subcontractors_secure` は invalid employee session を拒否、`list_subcontractors_admin_secure` は invalid management session を拒否。両方 PASS。

### ブラウザConsoleスモークテスト（本番・有効session・2026-07-13・実 token 値は記録しない）

- 従業員画面（index.html・employee session）`list_subcontractors_secure`：
  rpc_error = null、direct_error = null、rpc_count = 3、direct_count = 3、rpc_columns = ['id','name']、columns_ok = true、set_match = true（現行 direct read `select id,name / is_active=true / order name` と集合一致）。
- 原価管理画面（genka-app.html・management session）`list_subcontractors_admin_secure`：
  rpc_error = null、direct_error = null、rpc_count = 3、direct_count = 3、rpc_columns = ['id','name']、columns_ok = true、set_match = true。

### rollback

- 未実行（SQL ファイル末尾のコメント参照用のみ）。

### 最終状態（この工程の到達点）

- read RPC 2本の作成と DB 確認・RPC 単体スモークまでは完了（read RPC の DB 実行工程完了）。
- subcontractors table の anon / authenticated SELECT 権限はまだ維持。
- `sub_read` policy はまだ存在。
- frontend はまだ direct read（index.html / admin-app.html / genka-app.html の3件）。
- **Phase 4-F-2B-7 全体はまだ完了していない。**

### 次工程（未完了）

- frontend RPC 移行（index.html:998 → `list_subcontractors_secure`、genka-app.html:535 → `list_subcontractors_admin_secure`）。
- admin-app.html:330 の死にコード削除（`_subcontractors` ごと除去）。
- 本番 frontend 確認（direct read 0件化の確認を含む）。
- subcontractors の SELECT REVOKE。
- `sub_read` policy DROP。
- Phase 4-F-2B-7 の最終クローズ。

### 確認手段

- DB 確認・実行はユーザーが Supabase SQL Editor で手動実行。
- スモークテストは本番 Browser DevTools Console で有効 session により実施（実 token 値は記録しない）。
- 手順・実測値の詳細は `docs/sql/phase4f-2b-7-subcontractors-read-rpc.sql` の pre-check / post-check に記録。
- Claude Code CLI からの DB 接続・Supabase CLI・psql 使用なし。
