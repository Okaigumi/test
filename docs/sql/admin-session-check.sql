-- ============================================================
-- Step 3: 実行後の確認SQL
-- Supabase SQL Editor で実行
-- ============================================================

-- [1] admin_sessions テーブルの存在とカラム確認
-- 期待: id, admin_id, token_hash, expires_at, created_at の5列
SELECT column_name, data_type, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'admin_sessions'
ORDER BY ordinal_position;


-- [2] RLS が有効か確認
-- 期待: rowsecurity = true
SELECT tablename, rowsecurity
FROM   pg_tables
WHERE  schemaname = 'public'
  AND  tablename  = 'admin_sessions';


-- [3] ポリシーがないこと（直接アクセス拒否）を確認
-- 期待: 0件
SELECT policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename  = 'admin_sessions';


-- [4] インデックスの確認
-- 期待: primary key + 3インデックス（token_hash / expires_at / admin_id）
SELECT indexname, indexdef
FROM   pg_indexes
WHERE  schemaname = 'public'
  AND  tablename  = 'admin_sessions';


-- [5] 6本のRPCが存在することを確認
-- 期待: 6行
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


-- [6] create_admin_session の動作確認
-- ※ 実際の genka_admins.id と PIN に置き換えて実行
-- 期待: id / name / is_active / session_token (64文字16進数) が返る
SELECT *
FROM   public.create_admin_session(
  '<実際の genka_admins.id を入れる>',
  '<実際のPINを入れる>'
);


-- [7] 取得したトークンでセッション検証確認
-- ※ [6] で得た session_token を使用
-- 期待: true
SELECT EXISTS (
  SELECT 1 FROM public.admin_sessions s
  WHERE  s.token_hash = encode(digest('<上記のsession_tokenを入れる>', 'sha256'), 'hex')
    AND  s.expires_at > now()
) AS session_valid;


-- [8] revoke_admin_session でログアウト確認
-- ※ [6] で得た session_token を使用
SELECT public.revoke_admin_session('<上記のsession_tokenを入れる>');

-- 期待: false（削除されていること）
SELECT EXISTS (
  SELECT 1 FROM public.admin_sessions s
  WHERE  s.token_hash = encode(digest('<上記のsession_tokenを入れる>', 'sha256'), 'hex')
) AS session_still_exists;
