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
