# 管理者セッショントークン型RPC 実装計画

作成日：2026-05-30
状態：SQL未実行・コード未変更・権限削除未実施

---

## 1. 現在の状態

| 項目 | 状態 |
|---|---|
| ブランチ | main |
| working tree | clean から再開予定 |
| SQL実行 | まだ |
| コード変更 | まだ |
| 権限削除 | まだ |

直近コミット：`ac59ef7 Update PIN security migration notes`

---

## 2. 方針

- **採用案：案B 管理者セッショントークン型RPC**
- `admin_sessions` テーブルを作成し、ログイン時にランダムトークンを発行
- ハッシュ：`pgcrypto.digest()` を使用（`sha256(v_token::bytea)` は使わない）
- 生トークン（64文字16進数）はクライアントへ返す。DBには `token_hash` のみ保存
- セッション有効期限：`now() + interval '8 hours'`
- `admin_sessions` への直接アクセスは RLS ポリシーなし = 全ロール禁止
- SECURITY DEFINER RPC 経由のみが操作可能

### 採用理由

- 既存UIをほぼ変更せずに `employees_update_public` を削除できる
- `sessionStorage` に任意の値を書き込んだだけでは管理操作できなくなる
- Supabase Auth 導入（案C）より実装コストが大幅に低い
- PIN再入力型（案A）より UX を維持できる

### 変更対象

- `admin-app.html` のみ（`index.html` / `genka-app.html` は対象外）
- `genka-app.html` は employees / genka_admins の INSERT/UPDATE をしないため今回対象外

---

## 3. 実行予定SQL Step 1：pgcrypto + admin_sessions

```sql
-- ============================================================
-- Step 1: pgcrypto 有効化 + admin_sessions テーブル作成
-- Supabase SQL Editor で実行
-- ============================================================

-- pgcrypto を有効化（digest() / gen_random_bytes() に使用）
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- セッション管理テーブル
CREATE TABLE IF NOT EXISTS public.admin_sessions (
  id          uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_id    uuid        NOT NULL REFERENCES public.genka_admins(id) ON DELETE CASCADE,
  token_hash  text        NOT NULL UNIQUE,
  expires_at  timestamptz NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- RLS 有効化（直接アクセスを全ロール拒否。RPC経由のみ操作可）
ALTER TABLE public.admin_sessions ENABLE ROW LEVEL SECURITY;
-- ポリシーは作成しない = SELECT/INSERT/UPDATE/DELETE すべて直接禁止

-- インデックス
CREATE INDEX IF NOT EXISTS idx_admin_sessions_token_hash
  ON public.admin_sessions (token_hash);

CREATE INDEX IF NOT EXISTS idx_admin_sessions_expires_at
  ON public.admin_sessions (expires_at);

CREATE INDEX IF NOT EXISTS idx_admin_sessions_admin_id
  ON public.admin_sessions (admin_id);
```

---

## 4. 実行予定SQL Step 2：RPC作成（6本）

```sql
-- ============================================================
-- Step 2: RPC 作成（6本）
-- Supabase SQL Editor で実行
-- search_path に extensions を追加
-- （Supabase は pgcrypto を extensions スキーマに置くため
--   digest() の解決に必要）
-- ============================================================


-- ──────────────────────────────────────────────────────────
-- 1. create_admin_session
--    管理者ログイン + セッショントークン発行
--    verify_admin_pin の代替として admin-app.html で使用
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_admin_session(
  admin_id_input uuid,
  pin_input      text
)
RETURNS TABLE (
  id            uuid,
  name          text,
  is_active     boolean,
  session_token text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin  public.genka_admins%ROWTYPE;
  v_token  text;
BEGIN
  -- PIN照合（is_active も確認）
  SELECT *
  INTO   v_admin
  FROM   public.genka_admins g
  WHERE  g.id        = admin_id_input
    AND  g.pin       = pin_input
    AND  g.is_active = true;

  -- 不一致の場合は空を返す（エラーではなく 0行）
  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- 当該管理者の既存セッションと全期限切れセッションを削除（クリーンアップ）
  DELETE FROM public.admin_sessions s
  WHERE  s.admin_id  = admin_id_input
     OR  s.expires_at < now();

  -- 32バイトランダムトークン生成（64文字16進数文字列）
  v_token := encode(gen_random_bytes(32), 'hex');

  -- token_hash のみ保存（生トークンはDBに残さない）
  INSERT INTO public.admin_sessions (admin_id, token_hash, expires_at)
  VALUES (
    admin_id_input,
    encode(digest(v_token, 'sha256'), 'hex'),
    now() + interval '8 hours'
  );

  -- 生トークンをクライアントに返す（pin は返さない）
  RETURN QUERY
  SELECT v_admin.id, v_admin.name, v_admin.is_active, v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_admin_session(uuid, text)
  TO anon, authenticated;


-- ──────────────────────────────────────────────────────────
-- 2. create_employee_secure
--    セッション検証付き 従業員新規登録
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_employee_secure(
  session_token_input text,
  name_input          text,
  pin_input           text,
  role_input          text,
  company_id_input    uuid,
  is_active_input     boolean DEFAULT true
)
RETURNS TABLE (id uuid, name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- セッション検証
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'セッションが無効または期限切れです';
  END IF;

  -- バリデーション
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION '名前は必須です';
  END IF;

  IF pin_input IS NULL OR length(pin_input) <> 4 THEN
    RAISE EXCEPTION 'PINは4桁で入力してください';
  END IF;

  -- INSERT（saveEmployee と同等の payload）
  RETURN QUERY
  INSERT INTO public.employees (name, pin, role, company_id, is_active)
  VALUES (
    trim(name_input),
    pin_input,
    role_input,
    company_id_input,
    is_active_input
  )
  RETURNING employees.id, employees.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_employee_secure(text, text, text, text, uuid, boolean)
  TO anon, authenticated;


-- ──────────────────────────────────────────────────────────
-- 3. update_employee_secure
--    セッション検証付き 従業員編集
--    new_pin_input が NULL の場合は pin を変更しない
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_employee_secure(
  session_token_input text,
  id_input            uuid,
  name_input          text,
  role_input          text,
  is_active_input     boolean,
  company_id_input    uuid,
  new_pin_input       text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- セッション検証
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'セッションが無効または期限切れです';
  END IF;

  -- バリデーション
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION '名前は必須です';
  END IF;

  IF new_pin_input IS NOT NULL AND length(new_pin_input) <> 4 THEN
    RAISE EXCEPTION 'PINは4桁で入力してください';
  END IF;

  -- PIN変更なしの場合
  IF new_pin_input IS NULL THEN
    UPDATE public.employees e
    SET    name       = trim(name_input),
           role       = role_input,
           is_active  = is_active_input,
           company_id = company_id_input
    WHERE  e.id = id_input;
  ELSE
  -- PIN変更ありの場合
    UPDATE public.employees e
    SET    name       = trim(name_input),
           role       = role_input,
           is_active  = is_active_input,
           company_id = company_id_input,
           pin        = new_pin_input
    WHERE  e.id = id_input;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_employee_secure(text, uuid, text, text, boolean, uuid, text)
  TO anon, authenticated;


-- ──────────────────────────────────────────────────────────
-- 4. create_genka_admin_secure
--    セッション検証付き 管理者新規登録
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_genka_admin_secure(
  session_token_input text,
  name_input          text,
  pin_input           text
)
RETURNS TABLE (id uuid, name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- セッション検証
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'セッションが無効または期限切れです';
  END IF;

  -- バリデーション
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION '名前は必須です';
  END IF;

  IF pin_input IS NULL OR length(pin_input) <> 4 THEN
    RAISE EXCEPTION 'PINは4桁で入力してください';
  END IF;

  RETURN QUERY
  INSERT INTO public.genka_admins (name, pin, is_active)
  VALUES (trim(name_input), pin_input, true)
  RETURNING genka_admins.id, genka_admins.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_genka_admin_secure(text, text, text)
  TO anon, authenticated;


-- ──────────────────────────────────────────────────────────
-- 5. update_genka_admin_secure
--    セッション検証付き 管理者編集
--    new_pin_input が NULL の場合は pin を変更しない
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_genka_admin_secure(
  session_token_input text,
  id_input            uuid,
  name_input          text,
  is_active_input     boolean,
  new_pin_input       text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- セッション検証
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'セッションが無効または期限切れです';
  END IF;

  -- バリデーション
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION '名前は必須です';
  END IF;

  IF new_pin_input IS NOT NULL AND length(new_pin_input) <> 4 THEN
    RAISE EXCEPTION 'PINは4桁で入力してください';
  END IF;

  -- PIN変更なし
  IF new_pin_input IS NULL THEN
    UPDATE public.genka_admins g
    SET    name      = trim(name_input),
           is_active = is_active_input
    WHERE  g.id = id_input;
  ELSE
  -- PIN変更あり
    UPDATE public.genka_admins g
    SET    name      = trim(name_input),
           is_active = is_active_input,
           pin       = new_pin_input
    WHERE  g.id = id_input;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_genka_admin_secure(text, uuid, text, boolean, text)
  TO anon, authenticated;


-- ──────────────────────────────────────────────────────────
-- 6. revoke_admin_session
--    ログアウト時にセッションをDBから削除
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_admin_session(
  session_token_input text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  DELETE FROM public.admin_sessions s
  WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex');
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_admin_session(text)
  TO anon, authenticated;
```

---

## 5. 実行後確認SQL

```sql
-- ============================================================
-- Step 3: 実行後の確認SQL（Supabase SQL Editor で実行）
-- ============================================================

-- [1] admin_sessions テーブルの存在とカラム確認
SELECT column_name, data_type, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'admin_sessions'
ORDER BY ordinal_position;
-- 期待: id, admin_id, token_hash, expires_at, created_at の5列

-- [2] RLS が有効か確認
SELECT tablename, rowsecurity
FROM   pg_tables
WHERE  schemaname = 'public'
  AND  tablename  = 'admin_sessions';
-- 期待: rowsecurity = true

-- [3] ポリシーがないこと（直接アクセス拒否）を確認
SELECT policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename  = 'admin_sessions';
-- 期待: 0件

-- [4] インデックスの確認
SELECT indexname, indexdef
FROM   pg_indexes
WHERE  schemaname = 'public'
  AND  tablename  = 'admin_sessions';
-- 期待: primary key + 3インデックス

-- [5] 6本のRPCが存在することを確認
SELECT proname, pronargs
FROM   pg_proc
WHERE  pronamespace = 'public'::regnamespace
  AND  proname IN (
    'create_admin_session',
    'create_employee_secure',
    'update_employee_secure',
    'create_genka_admin_secure',
    'update_genka_admin_secure',
    'revoke_admin_session'
  )
ORDER BY proname;
-- 期待: 6行

-- [6] create_admin_session の動作確認
--     ※ 実際の genka_admins.id と PIN に置き換えて実行
SELECT *
FROM   public.create_admin_session(
  '<実際の genka_admins.id>',
  '<実際のPIN>'
);
-- 期待: id / name / is_active / session_token (64文字16進数) が返る

-- [7] 取得したトークンでセッション検証確認
--     ※ [6] で得た session_token を使用
SELECT EXISTS (
  SELECT 1 FROM public.admin_sessions s
  WHERE  s.token_hash = encode(digest('<session_token>', 'sha256'), 'hex')
    AND  s.expires_at > now()
) AS session_valid;
-- 期待: true

-- [8] revoke_admin_session でログアウト確認
SELECT public.revoke_admin_session('<session_token>');

SELECT EXISTS (
  SELECT 1 FROM public.admin_sessions s
  WHERE  s.token_hash = encode(digest('<session_token>', 'sha256'), 'hex')
) AS session_still_exists;
-- 期待: false（削除されていること）
```

---

## 6. まだ実行禁止のSQL

```sql
-- ============================================================
-- ⚠️ 実行禁止 ⚠️
-- 以下は admin-app.html のフロント変更 + 動作確認が
-- 完全に完了するまで絶対に実行しないこと
--
-- 実行タイミング：
--   ① create_admin_session でログインできることを確認後
--   ② saveEmployee / saveAdmin が secure RPC 経由で動くことを確認後
--   ③ Playwright での自動確認が通ることを確認後
--   上記③まで完了してからのみ実行する
-- ============================================================

BEGIN;

-- employees_update_public を削除（最危険ポリシーの解消）
DROP POLICY IF EXISTS employees_update_public ON public.employees;

-- employees の直接 INSERT / UPDATE を剥奪
-- ※ SELECT は維持（pin列GRANTはd751ec7にて制限済み）
REVOKE INSERT ON public.employees FROM anon, authenticated;
REVOKE UPDATE ON public.employees FROM anon, authenticated;

-- genka_admins の直接 INSERT / UPDATE を剥奪
-- ※ SELECT は維持（ログイン名前一覧に必要）
REVOKE INSERT ON public.genka_admins FROM anon, authenticated;
REVOKE UPDATE ON public.genka_admins FROM anon, authenticated;

COMMIT;

-- 削除後の確認SQL
SELECT policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename  = 'employees'
  AND  cmd IN ('INSERT', 'UPDATE');
-- 期待: employees_update_public が消えていること
```

---

## 7. 次回作業手順

1. `git pull` で最新状態を確認
2. `git status` で working tree が clean であることを確認
3. このファイル（`docs/admin-session-rpc-plan.md`）の内容を再確認
4. Supabase SQL Editor で **Step 1** を実行（pgcrypto + admin_sessions）
5. Supabase SQL Editor で **Step 2** を実行（RPC 6本）
6. **実行後確認SQL** を実行して全項目が期待通りか確認
7. `admin-app.html` の以下を変更：
   - `tryLogin()` → `create_admin_session` RPC を呼ぶ
   - `sessionStorage` に `session_token` を追加保存
   - `saveEmployee()` → `create_employee_secure` / `update_employee_secure` RPC を呼ぶ
   - `saveAdmin()` → `create_genka_admin_secure` / `update_genka_admin_secure` RPC を呼ぶ
   - `aLogout()` → `revoke_admin_session` RPC を呼んでからsessionStorage削除
8. Playwright で自動動作確認
9. 全項目が通ったら「まだ実行禁止のSQL」（権限削除）を実行
10. 再度動作確認
11. `docs/db-migrations.md` に正式記録
12. コミット・push

---

## 8. 注意点

| 項目 | 内容 |
|---|---|
| `search_path = public, extensions` | Supabase は pgcrypto を `extensions` スキーマに置く。`digest()` 解決のため両方指定 |
| `digest(text, 'sha256')` | pgcrypto の関数。戻り値は `bytea`。`encode(..., 'hex')` で16進数文字列に変換 |
| `gen_random_bytes(32)` | 256ビット乱数。総当たり不可能 |
| `OR expires_at < now()` | ログイン時に全期限切れセッションを一括削除。テーブルの肥大化を防ぐ |
| `new_pin_input DEFAULT NULL` | NULL を渡すことで既存PINを維持。PINを変えたい場合のみ4桁文字列を渡す |
| 権限削除は必ず最後 | フロント修正 → 動作確認 → 権限削除の順を厳守 |
| `genka-app.html` への影響 | employees / genka_admins の INSERT/UPDATE をしないため今回対象外 |
| XSS対策 | sessionStorage のトークンは XSS で窃取可能。URL非公開・escapeHtml で軽減 |
| Supabase Auth 化 | 本格的なセキュリティ強化は将来課題として `docs/rls-security-plan.md` §7 参照 |
