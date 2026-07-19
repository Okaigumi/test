-- ============================================================
-- Phase 5-C-1a：private schema ＋ private.login_throttle 作成
--   ログイン失敗回数抑制（アカウント単位クールダウン）の状態保持テーブルを
--   Data API から到達不能な非公開スキーマに新規作成する。
-- ============================================================
-- 【実行ステータス】STATUS: PREPARED / NOT EXECUTED
--   - preparation date：2026-07-19
--   - execution date  ：（未実行・未記入）
--   - Result          ：（未実行・未記入）
--   - ★実DBへは未実行。実行済みと誤認しないこと★
--
-- 【実行方法（重要）】
--   - 実行先：Supabase SQL Editor（手動実行のみ）
--   - Supabase CLI / psql では実行しない。
--   - 手順：PRE-CHECK（C-1〜C-4 を1つずつ・read-only）→ 全合格を確認
--           → EXECUTION BODY（BEGIN〜COMMIT を1回だけ選択実行）
--           → POST-CHECK（P-1〜P-8・read-only）。
--   - ★BODY は1回のみ実行。再実行禁止★
--     （2回目は GUARD G-1 が private スキーマ既存を検知して fail-closed で停止する）
--
-- 【変更内容（additive-only）】
--   - CREATE SCHEMA private（owner=postgres 明示）
--   - CREATE TABLE private.login_throttle（owner=postgres・RLS 有効・policy なし）
--   - private スキーマ USAGE と login_throttle table 権限を明示 REVOKE
--   - login RPC / frontend / 既存 policy / 既存テーブルは一切変更しない。
--   - GRANT / CREATE POLICY / 既存オブジェクトへの ALTER / DML は含まない。
--
-- 【対象（新規作成）】
--   - private スキーマ（新規・実測で未存在を確認済み・2026-07-19）
--   - private.login_throttle：
--       realm          text        NOT NULL CHECK (realm IN ('employee','admin'))
--       identifier     uuid        NOT NULL            -- employee_id / admin_id（実在IDのみ・5-C-1b で運用）
--       fail_count     integer     NOT NULL DEFAULT 0 CHECK (fail_count >= 0)
--       cooldown_until timestamptz
--       last_failed_at timestamptz
--       updated_at     timestamptz NOT NULL DEFAULT now()
--       PRIMARY KEY (realm, identifier)
--
-- 【到達不能化の方針（GRANT しないだけでなく明示 REVOKE＋POST-CHECK）】
--   - private スキーマの USAGE を PUBLIC / anon / authenticated / service_role /
--     authenticator から明示 REVOKE。
--   - login_throttle の table 権限を同5ロールから明示 REVOKE。
--   - RLS 有効・policy なし・★FORCE RLS は付けない★
--       （FORCE を付けると owner=postgres にも RLS が及び、policy 0 のため
--         SECURITY DEFINER RPC（owner 実行）すら 0 行になり破綻する。
--         owner は非 FORCE 時に RLS を bypass する。非 owner は
--         「USAGE なし＋table 権限なし＋RLS で 0 行」の三重で到達不能）。
--   - 5-C-1b の SECURITY DEFINER・owner=postgres の login RPC だけが、
--     完全修飾名 private.login_throttle でアクセスする（search_path 非依存）。
--
-- 【非対象（今回変更しない）】
--   - create_employee_session / create_admin_session（throttle 参照組込は 5-C-1b）
--   - employees.employees_read_all / genka_admins.ga_read（現役 policy・保持）
--   - 列 grant・RLS 設定（public）・frontend・roadmap。
--
-- 【権限検査の表記（重要・実測の教訓）】
--   - REVOKE 文ではキーワード PUBLIC を使う。
--   - has_schema_privilege / has_table_privilege 等の検査関数では文字列 'public'
--     を使う（'PUBLIC' は role does not exist エラーになるため使わない）。
--
-- 【STOP 条件（PRE-CHECK / GUARD / POST-CHECK のいずれかが不一致なら停止・報告）】
--   - private スキーマ or private.login_throttle が既に存在（再実行・名前衝突）
--   - employees / genka_admins が存在しない
--   - POST で anon/authenticated/service_role/authenticator/PUBLIC のいずれかに
--     USAGE または table 権限が残る
--   - RLS 無効 / policy が付いた / FORCE RLS が付いた
--   - カラム・PK・CHECK（realm / fail_count>=0）が設計と相違・owner≠postgres
--   - public schema policy が既知2本（employees_read_all / ga_read）と
--     完全一致しない（件数だけ合っても定義が違えば STOP）
-- ============================================================


-- ============================================================
-- PRE-CHECK（read-only・BODY 実行前に C-1 から順に1つずつ実行）
--   すべて SELECT のみ。DB 状態は変更しない。
-- ============================================================

-- C-1. private スキーマが存在しないこと
--   期待：0行
SELECT n.nspname
FROM   pg_namespace n
WHERE  n.nspname = 'private';

-- C-2. private.login_throttle が存在しないこと
--   期待：0行
SELECT c.relname
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'private' AND c.relname = 'login_throttle';

-- C-3. 参照先テーブルが存在すること（identifier 参照先の健全性）
--   期待：2行（employees / genka_admins）
SELECT c.relname
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'public' AND c.relkind = 'r'
  AND  c.relname IN ('employees','genka_admins')
ORDER  BY c.relname;

-- C-4. public schema policy が既知2本と完全一致（件数＋定義）
--   期待：差分0行（employees_read_all / ga_read の roles/cmd/qual まで一致）
WITH expected(tablename, policyname, roles_text, cmd, qual) AS (
  VALUES
    ('employees',    'employees_read_all', '{public}', 'SELECT', 'true'),
    ('genka_admins', 'ga_read',            '{public}', 'SELECT', 'true')
),
actual AS (
  SELECT tablename, policyname, roles::text AS roles_text, cmd, qual
  FROM   pg_policies WHERE schemaname = 'public'
)
SELECT COALESCE(e.tablename, a.tablename)   AS tablename,
       COALESCE(e.policyname, a.policyname) AS policyname,
       CASE WHEN a.policyname IS NULL THEN 'MISSING_IN_DB'
            WHEN e.policyname IS NULL THEN 'UNEXPECTED_IN_DB'
            ELSE 'DEF_MISMATCH' END AS diff_kind
FROM   expected e
FULL   OUTER JOIN actual a
       ON  a.tablename  = e.tablename
       AND a.policyname = e.policyname
       AND a.roles_text = e.roles_text
       AND a.cmd        = e.cmd
       AND a.qual       IS NOT DISTINCT FROM e.qual
WHERE  e.policyname IS NULL OR a.policyname IS NULL;


-- ============================================================
-- EXECUTION BODY（★1回のみ実行・再実行禁止★・現時点では未実行）
--   BEGIN〜COMMIT を1回だけ選択して実行する。
--   fail-closed GUARD（read-only DO block）が1つでも不一致を検知したら
--   RAISE EXCEPTION で transaction 全体が abort する（DB 無変更）。
--   変更は「スキーマ作成・テーブル作成・明示 REVOKE・RLS 有効化」のみ。
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_count integer;
BEGIN
  -- G-1. private スキーマ未存在
  SELECT count(*) INTO v_count FROM pg_namespace WHERE nspname = 'private';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-1 failed: schema "private" already exists (re-run? name collision?)';
  END IF;

  -- G-2. private.login_throttle 未存在
  SELECT count(*) INTO v_count
  FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE  n.nspname = 'private' AND c.relname = 'login_throttle';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-2 failed: table private.login_throttle already exists';
  END IF;

  -- G-3. 参照先 employees / genka_admins が存在
  SELECT count(*) INTO v_count
  FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE  n.nspname = 'public' AND c.relkind = 'r'
    AND  c.relname IN ('employees','genka_admins');
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'GUARD G-3 failed: expected employees + genka_admins (2), got %', v_count;
  END IF;

  RAISE NOTICE 'GUARD OK: creating schema private and table private.login_throttle (Data API unreachable)';
END
$$;

-- スキーマ作成（owner を明示）
CREATE SCHEMA private AUTHORIZATION postgres;

-- スキーマ USAGE を明示 REVOKE（REVOKE 文ではキーワード PUBLIC を使用）
REVOKE ALL ON SCHEMA private FROM PUBLIC;
REVOKE ALL ON SCHEMA private FROM anon, authenticated, service_role, authenticator;

-- テーブル作成
CREATE TABLE private.login_throttle (
  realm          text        NOT NULL CHECK (realm IN ('employee','admin')),
  identifier     uuid        NOT NULL,
  fail_count     integer     NOT NULL DEFAULT 0 CHECK (fail_count >= 0),
  cooldown_until timestamptz,
  last_failed_at timestamptz,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (realm, identifier)
);

-- 実行ロール依存を避けて owner を確定
ALTER TABLE private.login_throttle OWNER TO postgres;

-- テーブル権限を明示 REVOKE（キーワード PUBLIC ＋ 各ロール）
REVOKE ALL ON private.login_throttle FROM PUBLIC;
REVOKE ALL ON private.login_throttle FROM anon, authenticated, service_role, authenticator;

-- RLS 有効化（policy は作らない・FORCE しない）
ALTER TABLE private.login_throttle ENABLE ROW LEVEL SECURITY;

COMMIT;


-- ============================================================
-- POST-CHECK（read-only・COMMIT 後に P-1 から順に実行）
--   各結果は SQL Editor から CSV / 表形式でそのまま貼り戻せる。
--   ※ 権限検査関数では文字列 'public' を使用（'PUBLIC' は不可）。
-- ============================================================

-- P-1. private スキーマ存在・owner=postgres
--   期待：1行・owner=postgres
SELECT n.nspname AS schema_name, pg_get_userbyid(n.nspowner) AS owner
FROM   pg_namespace n
WHERE  n.nspname = 'private';

-- P-2. スキーマ USAGE が5ロールすべて false
--   期待：public/anon/authenticated/service_role/authenticator の usage 全 false
SELECT r.role_name,
       has_schema_privilege(r.role_name, 'private', 'USAGE')  AS usage_priv,
       has_schema_privilege(r.role_name, 'private', 'CREATE') AS create_priv
FROM   (VALUES ('public'),('anon'),('authenticated'),('service_role'),('authenticator')) r(role_name)
ORDER  BY r.role_name;

-- P-3. login_throttle 存在・owner=postgres
--   期待：1行・owner=postgres
SELECT c.relname AS table_name, pg_get_userbyid(c.relowner) AS owner
FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'private' AND c.relname = 'login_throttle';

-- P-4. table 権限（SELECT/INSERT/UPDATE/DELETE）が5ロールすべて false
--   期待：20判定すべて false
SELECT r.role_name,
       has_table_privilege(r.role_name, 'private.login_throttle', 'SELECT') AS can_select,
       has_table_privilege(r.role_name, 'private.login_throttle', 'INSERT') AS can_insert,
       has_table_privilege(r.role_name, 'private.login_throttle', 'UPDATE') AS can_update,
       has_table_privilege(r.role_name, 'private.login_throttle', 'DELETE') AS can_delete
FROM   (VALUES ('public'),('anon'),('authenticated'),('service_role'),('authenticator')) r(role_name)
ORDER  BY r.role_name;

-- P-5. RLS enabled=true / forced=false
--   期待：1行・rls_enabled=true・rls_forced=false
SELECT c.relname AS table_name, c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced
FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'private' AND c.relname = 'login_throttle';

-- P-6. login_throttle の policy 数 = 0
--   期待：0行
SELECT policyname
FROM   pg_policies
WHERE  schemaname = 'private' AND tablename = 'login_throttle';

-- P-7a. カラム構成・型・default
--   期待：realm/identifier/fail_count/cooldown_until/last_failed_at/updated_at が設計どおり
SELECT ordinal_position, column_name, data_type, is_nullable, column_default
FROM   information_schema.columns
WHERE  table_schema = 'private' AND table_name = 'login_throttle'
ORDER  BY ordinal_position;

-- P-7b. PRIMARY KEY と CHECK 制約（realm IN(...) / fail_count >= 0）
--   期待：PK (realm, identifier)・CHECK 2本（realm ドメイン・fail_count 非負）
SELECT c.conname, c.contype, pg_get_constraintdef(c.oid) AS definition
FROM   pg_constraint c
JOIN   pg_class t ON t.oid = c.conrelid
JOIN   pg_namespace n ON n.oid = t.relnamespace
WHERE  n.nspname = 'private' AND t.relname = 'login_throttle'
ORDER  BY c.contype, c.conname;

-- P-8. 回帰：public schema policy が既知2本と完全一致（C-4 と同一・不変確認）
--   期待：差分0行
WITH expected(tablename, policyname, roles_text, cmd, qual) AS (
  VALUES
    ('employees',    'employees_read_all', '{public}', 'SELECT', 'true'),
    ('genka_admins', 'ga_read',            '{public}', 'SELECT', 'true')
),
actual AS (
  SELECT tablename, policyname, roles::text AS roles_text, cmd, qual
  FROM   pg_policies WHERE schemaname = 'public'
)
SELECT COALESCE(e.tablename, a.tablename)   AS tablename,
       COALESCE(e.policyname, a.policyname) AS policyname,
       CASE WHEN a.policyname IS NULL THEN 'MISSING_IN_DB'
            WHEN e.policyname IS NULL THEN 'UNEXPECTED_IN_DB'
            ELSE 'DEF_MISMATCH' END AS diff_kind
FROM   expected e
FULL   OUTER JOIN actual a
       ON  a.tablename  = e.tablename
       AND a.policyname = e.policyname
       AND a.roles_text = e.roles_text
       AND a.cmd        = e.cmd
       AND a.qual       IS NOT DISTINCT FROM e.qual
WHERE  e.policyname IS NULL OR a.policyname IS NULL;


-- ============================================================
-- EMERGENCY ROLLBACK（通常は実行しない・コメントのまま保持）
--   ★順序が重要★：本テーブルは 5-C-1a 単独時点では login RPC から参照されない
--   （throttle 参照組込は 5-C-1b）。5-C-1b 適用後にロールバックする場合は、
--   必ず先に login RPC を旧定義へ CREATE OR REPLACE で戻し、login smoke 合格を
--   確認してから、以下でテーブル→スキーマの順に削除すること。
--   （login RPC が参照中の状態でテーブルを先に削除しない）。
--   private スキーマは他オブジェクトが無い場合のみ削除する（CASCADE は使わない）。
-- ============================================================
-- -- 1) login RPC が private.login_throttle を参照していないことを確認（5-C-1b 未適用 or 旧定義へ復元済み）
-- -- 2) テーブル削除
-- DROP TABLE private.login_throttle;
-- -- 3) スキーマ削除（空のときのみ・CASCADE を使わない）
-- DROP SCHEMA private;


-- ============================================================
-- 次工程 5-C-1b への申し送り（実測・設計の固定事項）
-- ============================================================
-- - login RPC（create_employee_session / create_admin_session）は
--   同一 signature・同一 RETURNS TABLE・同一挙動のまま CREATE OR REPLACE で
--   throttle 判定を組み込む（DROP しない）。クールダウン中も「0行」を返す互換方式。
--   retry_after_seconds の画面表示は後続の *_session_v2（additive）で対応する。
-- - private.login_throttle には完全修飾名でアクセスし、search_path に private を足さない。
-- - authenticator は safeupdate 有効のため、throttle の UPDATE / DELETE は必ず
--   WHERE（realm = ... AND identifier = ...）付きにする（WHERE 無しは拒否される）。
-- - statement_timeout=8s / lock_timeout=8s のため、行ロック（FOR UPDATE）や
--   UPSERT は単一行・短時間に限定する。
-- - 初回同時アクセスは「INSERT ... ON CONFLICT (realm, identifier) DO NOTHING で
--   行確保 → SELECT ... FOR UPDATE」または「単一 UPSERT＋RETURNING」で原子化する。
-- - クールダウン発動条件は「5回目の失敗で cooldown 開始＝6回目以降を拒否」で統一。
-- - 実在 identifier のみ記録（不存在 ID は行を作らず、応答は誤 PIN と統一）。
-- - IP 単位 rate limit（db-pre-request）は Phase 5-C 本体に含めず独立後続工程。
--   Phase 5-C の完了記録では「総当り・DoS の完全防御ではなく軽減」と定性記載する
--   （概算時間値は正式記録に使わない）。
-- ============================================================
