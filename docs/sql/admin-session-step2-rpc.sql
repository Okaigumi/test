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
