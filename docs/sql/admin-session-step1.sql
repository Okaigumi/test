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
