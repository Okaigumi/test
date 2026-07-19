-- ============================================================
-- Phase 5-C-1b：login RPC への account-level cooldown 組込
--   create_employee_session / create_admin_session を CREATE OR REPLACE で
--   private.login_throttle を用いた失敗回数抑制（クールダウン）付きに更新する。
-- ============================================================
-- 【実行ステータス】STATUS: PREPARED / NOT EXECUTED
--   - preparation date：2026-07-19
--   - execution date  ：（未実行・未記入）
--   - Result          ：（未実行・未記入）
--   - ★実DBへは未実行。実行済みと誤認しないこと★
--
-- 【対象 RPC（2本・CREATE OR REPLACE のみ・DROP FUNCTION 禁止）】
--   - public.create_employee_session(uuid, text)
--   - public.create_admin_session(uuid, text)
--   signature / 戻り値（RETURNS TABLE の列）/ EXECUTE ACL / frontend は不変。
--   CREATE OR REPLACE は既存 EXECUTE 権限を保持するため再 GRANT 不要。
--
-- 【抑制仕様】
--   - threshold = 5（5回目の失敗で cooldown 開始＝6回目以降を拒否）
--   - cooldown = 固定 60 秒（上限 60 秒）
--   - decay = 最終失敗から 15 分以上（>=）経過で有効 fail_count を 0 に減衰
--   - cooldown 中は照合せず・fail_count / cooldown_until / updated_at を変更しない（延長しない）
--   - 成功時のみ 1 行を返し throttle 行を DELETE。失敗・cooldown・不存在は 0 行。
--     → 3画面の .maybeSingle() 互換（1行=成功 / 0行=エラー表示）。retry_after 等の
--       戻り列は追加しない。
--   - private.login_throttle は完全修飾名で RPC 内部からのみ参照する（search_path に
--     private を足さない）。
--
-- 【realm / identifier / 実在確認テーブル】
--   - employee：realm='employee'・identifier=employee_id_input・実在確認=public.employees
--   - admin   ：realm='admin'   ・identifier=admin_id_input   ・実在確認=public.genka_admins
--   実在しない UUID は throttle 行を作らず 0 行（誤 PIN と応答統一・テーブル肥大化防止）。
--
-- 【lock / 競合】
--   - ロック順序（両 RPC で統一）：
--       (1) 対象 account 行（employees / genka_admins）を PERFORM ... FOR KEY SHARE で
--           key-share ロック（login RPC 完了まで対象 identifier の削除／key 変更を防ぎ、
--           存在しない identifier の throttle 行＝orphan を作らない）。存在しなければ 0 行。
--       (2) throttle 行を INSERT ... ON CONFLICT DO NOTHING で確保。
--       (3) PK 単一行を SELECT ... FOR UPDATE でロックし直列化（fail_count 取りこぼしなし）。
--       (4) cooldown / decay / PIN 判定 → (5) 成功 or 失敗処理。
--   - 単一 account 行の FOR KEY SHARE と単一 throttle 行の FOR UPDATE のみ。逆順ロックは
--     作らない（deadlock 回避）。単一行・短時間 lock により長時間占有を避ける
--     （function-level timeout は設定しない）。
--   - ★時刻判定★：private.login_throttle の cooldown / decay 判定と失敗時の
--     last_failed_at / cooldown_until / updated_at は、transaction-stable な now()
--     （トランザクション開始時刻で固定）ではなく、ロック取得後に取得した
--     clock_timestamp()（実時間）を使う。now() を使うと FOR UPDATE 待機後に古い時刻で
--     判定し、終了済み cooldown の誤継続・60秒未満/過去の cooldown_until・
--     decay ずれが起こり得るため。
--   - ★session 処理の時刻は現行互換のため now() を維持★（期限切れ session 判定の now()・
--     session 有効期限 now() + interval '8 hours'）。clock_timestamp() 化は throttle の
--     時刻管理だけに限定する。
--   - UPDATE / DELETE はすべて WHERE 付き（realm=… AND identifier=…）。
--
-- 【不変条件 / 禁止】
--   - CREATE OR REPLACE のみ。DROP FUNCTION 禁止。signature / 戻り値 / owner=postgres /
--     SECURITY DEFINER / VOLATILE / search_path=public, extensions / EXECUTE ACL 不変。
--   - proconfig は既存どおり search_path=public, extensions のみ（function-level timeout 追加禁止）。
--   - dynamic SQL 禁止・pg_sleep 禁止・PIN / token を例外文やログへ出さない。
--   - DB 列の古い fail_count + 1 をそのまま使わない（decay 込みの有効値から算出）。
--   - GRANT / REVOKE / ALTER TABLE / policy 変更・helper function 追加は行わない。
--   - デプロイ時の standalone DML は実行しない。DML は CREATE OR REPLACE する関数本体
--     内部にのみ含む（session の DELETE/INSERT・throttle の UPSERT/UPDATE/DELETE）。
--   - Phase 4 policy 2本・login 関連 table ACL・column grant 不変。
--
-- 【防御範囲】
--   - これは account-level の mitigation であり、総当り・DoS の完全防御ではない。
--     複数アカウント並列・分散攻撃には IP 単位 rate limit（PostgREST db-pre-request 等）が
--     別途必要で、それは独立した後続工程とする。
--
-- 【実行方法】
--   - 実行先：Supabase SQL Editor（手動）。Supabase CLI / psql では実行しない。
--   - 手順：PRE-CHECK（C-1〜C-4）→ EXECUTION BODY（BEGIN〜COMMIT を1回だけ）→
--           POST-CHECK（P-1〜P-6）→ smoke checklist。
--   - ★BODY は本番で1回だけ実行★（GUARD が baseline 不一致・二重適用を fail-closed で停止）。
--   - 実 PIN・raw token・個別 UUID・氏名は記録しない。
--
-- 【baseline fingerprint（5C1b0-A9 で実 DB から取得・GUARD G-1 に固定）】
--   - public.create_admin_session(uuid,text)   ：md5=ed50cdc59995b768b5dd31d80666e33d / length=1328
--   - public.create_employee_session(uuid,text)：md5=39b9a7cd8066a74f7e4827a38e677c92 / length=1517
--   ※ これは当該実 DB の pg_get_functiondef 出力に対する値。他環境の値と比較しない。
--
-- 【STOP 条件】
--   - PRE-CHECK / GUARD のいずれか不一致（signature/戻り値/属性/ACL/baseline md5・length/
--     現行が既に throttle 参照/throttle テーブルの状態/Phase 4 policy）。
-- ============================================================


-- ============================================================
-- PRE-CHECK（read-only・BODY 前に C-1 から順に1つずつ実行）
-- ============================================================

-- C-1. login RPC 2本の属性 + 現行定義 fingerprint
--   期待：2行・各 overload=1・owner=postgres・security_definer=true・volatility='v'・
--         search_path=public, extensions・refs_login_throttle=false・
--         md5/length が baseline と一致
--         （admin  md5=ed50cdc59995b768b5dd31d80666e33d / length=1328、
--          employ md5=39b9a7cd8066a74f7e4827a38e677c92 / length=1517）
SELECT p.oid::regprocedure                 AS signature,
       pg_get_function_result(p.oid)        AS result_type,
       pg_get_userbyid(p.proowner)          AS owner,
       p.prosecdef                          AS security_definer,
       p.provolatile                        AS volatility,
       p.proconfig                          AS config,
       count(*) OVER (PARTITION BY p.proname) AS overload_count,
       (p.prosrc ILIKE '%login_throttle%')  AS refs_login_throttle,
       md5(pg_get_functiondef(p.oid))       AS definition_md5,
       length(pg_get_functiondef(p.oid))    AS definition_length
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.oid IN ('public.create_employee_session(uuid,text)'::regprocedure,
                 'public.create_admin_session(uuid,text)'::regprocedure)
ORDER  BY p.oid::regprocedure::text;

-- C-2. EXECUTE ACL（PUBLIC/anon/authenticated/authenticator/service_role）
--   期待：各関数 PUBLIC=false / anon=true / authenticated=true / authenticator=false /
--         service_role=true
SELECT f.sig AS signature, r.role_name,
       CASE WHEN r.role_name = 'PUBLIC'
            THEN (SELECT bool_or(a.grantee = 0) FROM aclexplode(p.proacl) a)
            ELSE has_function_privilege(r.role_name, f.oid, 'EXECUTE') END AS can_execute
FROM   (VALUES
         ('public.create_employee_session(uuid,text)'::regprocedure),
         ('public.create_admin_session(uuid,text)'::regprocedure)) f(oid)
JOIN   LATERAL (SELECT f.oid::regprocedure::text AS sig) s ON true
JOIN   pg_proc p ON p.oid = f.oid
CROSS  JOIN (VALUES ('PUBLIC'),('anon'),('authenticated'),('authenticator'),('service_role')) r(role_name)
ORDER  BY f.oid::regprocedure::text, r.role_name;

-- C-3. private.login_throttle の構造・owner・RLS・policy・到達不能
--   期待：owner=postgres・rls_enabled=true・rls_forced=false・policy 0・
--         schema/table とも5ロール到達不能（下記2クエリ）
SELECT c.relname AS table_name, pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced,
       (SELECT count(*) FROM pg_policies pp
         WHERE pp.schemaname='private' AND pp.tablename='login_throttle') AS policy_count
FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname='private' AND c.relname='login_throttle';

SELECT r.role_name,
       has_schema_privilege(r.role_name, 'private', 'USAGE')                 AS schema_usage,
       has_table_privilege(r.role_name, 'private.login_throttle', 'SELECT')  AS can_select,
       has_table_privilege(r.role_name, 'private.login_throttle', 'INSERT')  AS can_insert,
       has_table_privilege(r.role_name, 'private.login_throttle', 'UPDATE')  AS can_update,
       has_table_privilege(r.role_name, 'private.login_throttle', 'DELETE')  AS can_delete
FROM   (VALUES ('public'),('anon'),('authenticated'),('service_role'),('authenticator')) r(role_name)
ORDER  BY r.role_name;

-- C-4. Phase 4 policy 2本・login 関連4テーブル ACL・column grant
--   期待：policy 差分0行／anon・authenticated の table 権限なし・列 grant は
--         pin/created_at 非公開のまま
--   C-4a policy
WITH expected(tablename, policyname, roles_text, cmd, qual) AS (
  VALUES ('employees','employees_read_all','{public}','SELECT','true'),
         ('genka_admins','ga_read','{public}','SELECT','true')
),
actual AS (SELECT tablename, policyname, roles::text AS roles_text, cmd, qual
           FROM pg_policies WHERE schemaname='public')
SELECT COALESCE(e.tablename,a.tablename) AS tablename,
       COALESCE(e.policyname,a.policyname) AS policyname,
       CASE WHEN a.policyname IS NULL THEN 'MISSING_IN_DB'
            WHEN e.policyname IS NULL THEN 'UNEXPECTED_IN_DB'
            ELSE 'DEF_MISMATCH' END AS diff_kind
FROM expected e FULL OUTER JOIN actual a
  ON a.tablename=e.tablename AND a.policyname=e.policyname
 AND a.roles_text=e.roles_text AND a.cmd=e.cmd AND a.qual IS NOT DISTINCT FROM e.qual
WHERE e.policyname IS NULL OR a.policyname IS NULL;

--   C-4b table 権限（期待：anon/authenticated の I/U/D/SELECT が false・出力 0行が理想）
SELECT table_name, grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema='public'
  AND  table_name IN ('employees','genka_admins','employee_sessions','admin_sessions')
  AND  grantee IN ('anon','authenticated','PUBLIC','authenticator')
ORDER  BY table_name, grantee, privilege_type;

--   C-4c 列 grant（期待：SELECT のみ・pin/created_at 非公開）
SELECT table_name, grantee, privilege_type,
       string_agg(column_name, ',' ORDER BY column_name) AS cols
FROM   information_schema.column_privileges
WHERE  table_schema='public' AND table_name IN ('employees','genka_admins')
  AND  grantee IN ('anon','authenticated')
GROUP  BY table_name, grantee, privilege_type
ORDER  BY table_name, grantee, privilege_type;


-- ============================================================
-- EXECUTION BODY（★本番で1回だけ実行・再実行禁止★・現時点では未実行）
--   BEGIN〜COMMIT を1回だけ実行。GUARD（fail-closed）不一致は RAISE EXCEPTION で
--   transaction 全体を abort（DB 無変更）。DROP FUNCTION は使わない。
-- ============================================================

BEGIN;

DO $guard$
DECLARE
  v_count integer;
  v_emp_md5    text;
  v_emp_len    integer;
  v_adm_md5    text;
  v_adm_len    integer;
BEGIN
  -- G-1. login RPC 2本が各1本・期待属性・baseline fingerprint 完全一致
  SELECT count(*) INTO v_count
  FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname='public'
    AND  p.proname IN ('create_employee_session','create_admin_session');
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'GUARD G-1 failed: expected exactly 2 login RPCs (no overload), got %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname='public'
    AND  p.oid IN ('public.create_employee_session(uuid,text)'::regprocedure,
                   'public.create_admin_session(uuid,text)'::regprocedure)
    AND  p.prosecdef = true
    AND  pg_get_userbyid(p.proowner) = 'postgres'
    AND  p.provolatile = 'v'
    AND  p.proconfig @> ARRAY['search_path=public, extensions'];
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'GUARD G-1 failed: owner/DEFINER/VOLATILE/search_path baseline mismatch (got % of 2)', v_count;
  END IF;

  -- baseline fingerprint（5C1b0-A9 実測・固定値）と完全一致
  SELECT md5(pg_get_functiondef(o)), length(pg_get_functiondef(o))
  INTO   v_emp_md5, v_emp_len
  FROM   (SELECT 'public.create_employee_session(uuid,text)'::regprocedure AS o) x;
  IF v_emp_md5 <> '39b9a7cd8066a74f7e4827a38e677c92' OR v_emp_len <> 1517 THEN
    RAISE EXCEPTION 'GUARD G-1 failed: create_employee_session definition fingerprint mismatch (md5=% len=%)', v_emp_md5, v_emp_len;
  END IF;

  SELECT md5(pg_get_functiondef(o)), length(pg_get_functiondef(o))
  INTO   v_adm_md5, v_adm_len
  FROM   (SELECT 'public.create_admin_session(uuid,text)'::regprocedure AS o) x;
  IF v_adm_md5 <> 'ed50cdc59995b768b5dd31d80666e33d' OR v_adm_len <> 1328 THEN
    RAISE EXCEPTION 'GUARD G-1 failed: create_admin_session definition fingerprint mismatch (md5=% len=%)', v_adm_md5, v_adm_len;
  END IF;

  -- G-2. 現行 RPC が private.login_throttle を未参照（二重適用防止）
  SELECT count(*) INTO v_count
  FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname='public'
    AND  p.proname IN ('create_employee_session','create_admin_session')
    AND  p.prosrc ILIKE '%login_throttle%';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-2 failed: login RPC already references login_throttle (already applied?)';
  END IF;

  -- G-3. private.login_throttle 存在・owner=postgres・RLS on・FORCE off・policy 0・到達不能
  SELECT count(*) INTO v_count
  FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE  n.nspname='private' AND c.relname='login_throttle' AND c.relkind='r'
    AND  pg_get_userbyid(c.relowner)='postgres'
    AND  c.relrowsecurity=true AND c.relforcerowsecurity=false;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'GUARD G-3 failed: private.login_throttle baseline mismatch';
  END IF;

  SELECT count(*) INTO v_count
  FROM   pg_policies WHERE schemaname='private' AND tablename='login_throttle';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-3 failed: private.login_throttle has unexpected policies: %', v_count;
  END IF;

  IF has_schema_privilege('anon','private','USAGE')
     OR has_schema_privilege('authenticated','private','USAGE')
     OR has_table_privilege('anon','private.login_throttle','SELECT')
     OR has_table_privilege('authenticated','private.login_throttle','SELECT') THEN
    RAISE EXCEPTION 'GUARD G-3 failed: private.login_throttle is reachable by anon/authenticated';
  END IF;

  -- G-4. 関連4テーブルが存在
  SELECT count(*) INTO v_count
  FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE  n.nspname='public' AND c.relkind='r'
    AND  c.relname IN ('employees','genka_admins','employee_sessions','admin_sessions');
  IF v_count <> 4 THEN
    RAISE EXCEPTION 'GUARD G-4 failed: expected 4 login-related tables, got %', v_count;
  END IF;

  RAISE NOTICE 'GUARD OK: baseline verified; replacing login RPCs with account-level cooldown';
END;
$guard$;


-- ---- create_employee_session（throttle 組込・戻り値/ signature 不変） ----
CREATE OR REPLACE FUNCTION public.create_employee_session(
  employee_id_input uuid,
  pin_input         text
)
RETURNS TABLE (
  id            uuid,
  name          text,
  role          text,
  is_active     boolean,
  company_id    uuid,
  can_genka     boolean,
  can_admin     boolean,
  session_token text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_emp                  public.employees%ROWTYPE;
  v_token                text;
  v_fail_count           integer;
  v_cooldown_until       timestamptz;
  v_last_failed_at       timestamptz;
  v_effective_fail_count integer;
  v_next_fail_count      integer;
  v_throttle_now         timestamptz;
  v_failed_at            timestamptz;
BEGIN
  -- (1) 実在確認＋対象 account 行の key-share ロック
  --     （login RPC 完了まで対象 identifier の削除／key 変更を防ぎ throttle orphan を回避）
  PERFORM 1
  FROM   public.employees e
  WHERE  e.id = employee_id_input
  FOR    KEY SHARE;

  IF NOT FOUND THEN
    RETURN;                          -- 存在しなければ throttle 行を作らず 0 行
  END IF;

  -- (2) throttle 行を確保
  INSERT INTO private.login_throttle (realm, identifier, fail_count, updated_at)
  VALUES ('employee', employee_id_input, 0, clock_timestamp())
  ON CONFLICT (realm, identifier) DO NOTHING;

  -- (3) 単一行ロック
  SELECT lt.fail_count, lt.cooldown_until, lt.last_failed_at
  INTO   v_fail_count, v_cooldown_until, v_last_failed_at
  FROM   private.login_throttle lt
  WHERE  lt.realm = 'employee' AND lt.identifier = employee_id_input
  FOR UPDATE;

  -- ロック取得後の実時間で throttle 時刻判定を行う
  -- （transaction-stable な now() はロック待機で古くなり得るため使わない）
  v_throttle_now := clock_timestamp();

  -- (4) cooldown 中は照合せず・状態不変で 0 行
  IF v_cooldown_until IS NOT NULL AND v_cooldown_until > v_throttle_now THEN
    RETURN;
  END IF;

  -- (5) decay 込みの有効失敗回数
  IF v_last_failed_at IS NULL OR (v_throttle_now - v_last_failed_at) >= interval '15 minutes' THEN
    v_effective_fail_count := 0;
  ELSE
    v_effective_fail_count := v_fail_count;
  END IF;

  -- (6) PIN + is_active 照合
  SELECT *
  INTO   v_emp
  FROM   public.employees e
  WHERE  e.id        = employee_id_input
    AND  e.pin       = pin_input
    AND  e.is_active = true;

  IF NOT FOUND THEN
    -- (8) 失敗：有効回数 +1 で確定（時刻は実時間 v_failed_at に統一）
    v_failed_at := clock_timestamp();
    v_next_fail_count := v_effective_fail_count + 1;
    UPDATE private.login_throttle
    SET    fail_count     = v_next_fail_count,
           last_failed_at = v_failed_at,
           cooldown_until = CASE WHEN v_next_fail_count >= 5
                                 THEN v_failed_at + interval '60 seconds'
                                 ELSE NULL END,
           updated_at     = v_failed_at
    WHERE  realm = 'employee' AND identifier = employee_id_input;
    RETURN;
  END IF;

  -- (7) 成功：throttle 行 DELETE → 現行どおり session 再発行
  DELETE FROM private.login_throttle
  WHERE  realm = 'employee' AND identifier = employee_id_input;

  DELETE FROM public.employee_sessions s
  WHERE  s.employee_id = employee_id_input
     OR  s.expires_at  < now();

  v_token := encode(gen_random_bytes(32), 'hex');

  INSERT INTO public.employee_sessions (employee_id, token_hash, expires_at)
  VALUES (
    employee_id_input,
    encode(digest(v_token, 'sha256'), 'hex'),
    now() + interval '8 hours'
  );

  RETURN QUERY
  SELECT
    v_emp.id,
    v_emp.name,
    v_emp.role,
    v_emp.is_active,
    v_emp.company_id,
    v_emp.can_genka,
    v_emp.can_admin,
    v_token;
END;
$$;


-- ---- create_admin_session（throttle 組込・戻り値/ signature 不変） ----
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
  v_admin                public.genka_admins%ROWTYPE;
  v_token                text;
  v_fail_count           integer;
  v_cooldown_until       timestamptz;
  v_last_failed_at       timestamptz;
  v_effective_fail_count integer;
  v_next_fail_count      integer;
  v_throttle_now         timestamptz;
  v_failed_at            timestamptz;
BEGIN
  -- (1) 実在確認＋対象 account 行の key-share ロック
  --     （login RPC 完了まで対象 identifier の削除／key 変更を防ぎ throttle orphan を回避）
  PERFORM 1
  FROM   public.genka_admins g
  WHERE  g.id = admin_id_input
  FOR    KEY SHARE;

  IF NOT FOUND THEN
    RETURN;                          -- 存在しなければ throttle 行を作らず 0 行
  END IF;

  -- (2) throttle 行を確保
  INSERT INTO private.login_throttle (realm, identifier, fail_count, updated_at)
  VALUES ('admin', admin_id_input, 0, clock_timestamp())
  ON CONFLICT (realm, identifier) DO NOTHING;

  -- (3) 単一行ロック
  SELECT lt.fail_count, lt.cooldown_until, lt.last_failed_at
  INTO   v_fail_count, v_cooldown_until, v_last_failed_at
  FROM   private.login_throttle lt
  WHERE  lt.realm = 'admin' AND lt.identifier = admin_id_input
  FOR UPDATE;

  -- ロック取得後の実時間で throttle 時刻判定を行う
  -- （transaction-stable な now() はロック待機で古くなり得るため使わない）
  v_throttle_now := clock_timestamp();

  -- (4) cooldown 中は照合せず・状態不変で 0 行
  IF v_cooldown_until IS NOT NULL AND v_cooldown_until > v_throttle_now THEN
    RETURN;
  END IF;

  -- (5) decay 込みの有効失敗回数
  IF v_last_failed_at IS NULL OR (v_throttle_now - v_last_failed_at) >= interval '15 minutes' THEN
    v_effective_fail_count := 0;
  ELSE
    v_effective_fail_count := v_fail_count;
  END IF;

  -- (6) PIN + is_active 照合
  SELECT *
  INTO   v_admin
  FROM   public.genka_admins g
  WHERE  g.id        = admin_id_input
    AND  g.pin       = pin_input
    AND  g.is_active = true;

  IF NOT FOUND THEN
    -- (8) 失敗：有効回数 +1 で確定（時刻は実時間 v_failed_at に統一）
    v_failed_at := clock_timestamp();
    v_next_fail_count := v_effective_fail_count + 1;
    UPDATE private.login_throttle
    SET    fail_count     = v_next_fail_count,
           last_failed_at = v_failed_at,
           cooldown_until = CASE WHEN v_next_fail_count >= 5
                                 THEN v_failed_at + interval '60 seconds'
                                 ELSE NULL END,
           updated_at     = v_failed_at
    WHERE  realm = 'admin' AND identifier = admin_id_input;
    RETURN;
  END IF;

  -- (7) 成功：throttle 行 DELETE → 現行どおり session 再発行
  DELETE FROM private.login_throttle
  WHERE  realm = 'admin' AND identifier = admin_id_input;

  DELETE FROM public.admin_sessions s
  WHERE  s.admin_id  = admin_id_input
     OR  s.expires_at < now();

  v_token := encode(gen_random_bytes(32), 'hex');

  INSERT INTO public.admin_sessions (admin_id, token_hash, expires_at)
  VALUES (
    admin_id_input,
    encode(digest(v_token, 'sha256'), 'hex'),
    now() + interval '8 hours'
  );

  RETURN QUERY
  SELECT v_admin.id, v_admin.name, v_admin.is_active, v_token;
END;
$$;

COMMIT;


-- ============================================================
-- POST-CHECK（read-only・COMMIT 後に P-1 から順に実行）
-- ============================================================

-- P-1. signature/戻り値/owner/DEFINER/VOLATILE/search_path/overload 不変
--   期待：2行・owner=postgres・security_definer=true・volatility='v'・
--         search_path=public, extensions・overload=1
SELECT p.oid::regprocedure AS signature,
       pg_get_function_result(p.oid) AS result_type,
       pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef AS security_definer,
       p.provolatile AS volatility,
       p.proconfig AS config,
       count(*) OVER (PARTITION BY p.proname) AS overload_count
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname='public'
  AND  p.oid IN ('public.create_employee_session(uuid,text)'::regprocedure,
                 'public.create_admin_session(uuid,text)'::regprocedure)
ORDER  BY p.oid::regprocedure::text;

-- P-2. EXECUTE ACL 不変（C-2 と一致）
SELECT f.oid::regprocedure::text AS signature, r.role_name,
       CASE WHEN r.role_name = 'PUBLIC'
            THEN (SELECT bool_or(a.grantee = 0) FROM aclexplode(p.proacl) a)
            ELSE has_function_privilege(r.role_name, f.oid, 'EXECUTE') END AS can_execute
FROM   (VALUES
         ('public.create_employee_session(uuid,text)'::regprocedure),
         ('public.create_admin_session(uuid,text)'::regprocedure)) f(oid)
JOIN   pg_proc p ON p.oid = f.oid
CROSS  JOIN (VALUES ('PUBLIC'),('anon'),('authenticated'),('authenticator'),('service_role')) r(role_name)
ORDER  BY f.oid::regprocedure::text, r.role_name;

-- P-3. 2本とも private.login_throttle を参照・完全修飾・dynamic SQL/pg_sleep なし・
--      threshold/60秒/15分ロジック存在・FOR KEY SHARE・clock_timestamp 使用
--   期待：refs=true / qualified=true / has_dynamic=false / has_pg_sleep=false /
--         has_60s=true / has_15min=true / has_threshold5=true /
--         has_key_share=true / has_clock_timestamp=true /
--         throttle_uses_now=false（throttle 判定に now() を使っていない）
--   ※ throttle_uses_now は「'now()' が failed_at/cooldown/decay へ紛れていないか」の
--     補助検査。session 用の now()（now() + interval '8 hours' 等）は許容されるため、
--     このフラグは false を必須にはせず、true の場合は目視で session 用途のみか確認する。
SELECT p.proname,
       (p.prosrc ILIKE '%login_throttle%')                          AS refs_login_throttle,
       (p.prosrc ILIKE '%private.login_throttle%')                  AS qualified_ref,
       (p.prosrc ILIKE '%execute%format%' OR p.prosrc ILIKE '%execute ''%') AS has_dynamic_sql,
       (p.prosrc ILIKE '%pg_sleep%')                                AS has_pg_sleep,
       (p.prosrc ILIKE '%60 seconds%')                              AS has_60s,
       (p.prosrc ILIKE '%15 minutes%')                              AS has_15min,
       (p.prosrc ILIKE '%>= 5%')                                    AS has_threshold5,
       (p.prosrc ILIKE '%for key share%')                           AS has_key_share,
       (p.prosrc ILIKE '%clock_timestamp()%')                       AS has_clock_timestamp,
       (p.prosrc ILIKE '%v_failed_at + interval%')                  AS cooldown_uses_clock
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname='public'
  AND  p.proname IN ('create_employee_session','create_admin_session')
ORDER  BY p.proname;

-- P-4. private.login_throttle の構造/RLS/policy/ACL 不変（C-3 と同一）
SELECT c.relname AS table_name, pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced,
       (SELECT count(*) FROM pg_policies pp
         WHERE pp.schemaname='private' AND pp.tablename='login_throttle') AS policy_count
FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname='private' AND c.relname='login_throttle';

SELECT r.role_name,
       has_schema_privilege(r.role_name, 'private', 'USAGE')                AS schema_usage,
       has_table_privilege(r.role_name, 'private.login_throttle', 'SELECT') AS can_select,
       has_table_privilege(r.role_name, 'private.login_throttle', 'INSERT') AS can_insert,
       has_table_privilege(r.role_name, 'private.login_throttle', 'UPDATE') AS can_update,
       has_table_privilege(r.role_name, 'private.login_throttle', 'DELETE') AS can_delete
FROM   (VALUES ('public'),('anon'),('authenticated'),('service_role'),('authenticator')) r(role_name)
ORDER  BY r.role_name;

-- P-5. Phase 4 policy 2本・login 関連 table ACL・column grant 不変（C-4 と同一）
--   （C-4a / C-4b / C-4c を再実行し差分がないことを確認）

-- P-6. throttle データ整合性（row_count=0 は必須条件にしない）
--   期待：invalid_realm=0 / negative_fail_count=0 / orphan_employee=0 / orphan_admin=0
--         （total_rows は参考値。正当な cooldown 行等の存在は許容）
--   ★orphan 0 の成立理由★：各 login RPC は throttle 行 INSERT の前に対象 account 行を
--     FOR KEY SHARE でロックするため、RPC 実行中に対象 employee/genka_admin が削除・
--     key 変更されず、実在しない identifier の throttle 行（orphan）が作られない。
SELECT
  (SELECT count(*) FROM private.login_throttle)                                        AS total_rows,
  (SELECT count(*) FROM private.login_throttle WHERE realm NOT IN ('employee','admin')) AS invalid_realm,
  (SELECT count(*) FROM private.login_throttle WHERE fail_count < 0)                    AS negative_fail_count,
  (SELECT count(*) FROM private.login_throttle lt
     WHERE lt.realm='employee'
       AND NOT EXISTS (SELECT 1 FROM public.employees e WHERE e.id = lt.identifier))    AS orphan_employee,
  (SELECT count(*) FROM private.login_throttle lt
     WHERE lt.realm='admin'
       AND NOT EXISTS (SELECT 1 FROM public.genka_admins g WHERE g.id = lt.identifier)) AS orphan_admin;


-- ============================================================
-- EMERGENCY ROLLBACK（通常は実行しない・コメントのまま保持）
--   現行（Phase 5-C-1b 適用前）の login RPC 2本の定義を CREATE OR REPLACE で完全復元する。
--   （下記は 5C1b0-A1 で取得した現行定義全文＝repo 記録と実 DB で差異なしを A1 で確認済み。
--     GUARD の md5 baseline が live 定義を pin している。）
--   ★DROP FUNCTION は使わない★。CREATE OR REPLACE は EXECUTE ACL を保持するため
--   再 GRANT 不要。private.login_throttle は残す（旧 RPC は未参照へ戻るだけで無害）。
--   実行後：3画面 login smoke 合格・EXECUTE ACL（P-2）・Phase 4 policy（P-5）・
--   throttle 到達不能（P-4）を再確認すること。
-- ============================================================
-- CREATE OR REPLACE FUNCTION public.create_employee_session(
--   employee_id_input uuid,
--   pin_input         text
-- )
-- RETURNS TABLE (
--   id            uuid,
--   name          text,
--   role          text,
--   is_active     boolean,
--   company_id    uuid,
--   can_genka     boolean,
--   can_admin     boolean,
--   session_token text
-- )
-- LANGUAGE plpgsql
-- SECURITY DEFINER
-- SET search_path = public, extensions
-- AS $$
-- DECLARE
--   v_emp   public.employees%ROWTYPE;
--   v_token text;
-- BEGIN
--   SELECT *
--   INTO   v_emp
--   FROM   public.employees e
--   WHERE  e.id        = employee_id_input
--     AND  e.pin       = pin_input
--     AND  e.is_active = true;
--
--   IF NOT FOUND THEN
--     RETURN;
--   END IF;
--
--   DELETE FROM public.employee_sessions s
--   WHERE  s.employee_id = employee_id_input
--      OR  s.expires_at  < now();
--
--   v_token := encode(gen_random_bytes(32), 'hex');
--
--   INSERT INTO public.employee_sessions (employee_id, token_hash, expires_at)
--   VALUES (
--     employee_id_input,
--     encode(digest(v_token, 'sha256'), 'hex'),
--     now() + interval '8 hours'
--   );
--
--   RETURN QUERY
--   SELECT
--     v_emp.id,
--     v_emp.name,
--     v_emp.role,
--     v_emp.is_active,
--     v_emp.company_id,
--     v_emp.can_genka,
--     v_emp.can_admin,
--     v_token;
-- END;
-- $$;
--
-- CREATE OR REPLACE FUNCTION public.create_admin_session(
--   admin_id_input uuid,
--   pin_input      text
-- )
-- RETURNS TABLE (
--   id            uuid,
--   name          text,
--   is_active     boolean,
--   session_token text
-- )
-- LANGUAGE plpgsql
-- SECURITY DEFINER
-- SET search_path = public, extensions
-- AS $$
-- DECLARE
--   v_admin  public.genka_admins%ROWTYPE;
--   v_token  text;
-- BEGIN
--   SELECT *
--   INTO   v_admin
--   FROM   public.genka_admins g
--   WHERE  g.id        = admin_id_input
--     AND  g.pin       = pin_input
--     AND  g.is_active = true;
--
--   IF NOT FOUND THEN
--     RETURN;
--   END IF;
--
--   DELETE FROM public.admin_sessions s
--   WHERE  s.admin_id  = admin_id_input
--      OR  s.expires_at < now();
--
--   v_token := encode(gen_random_bytes(32), 'hex');
--
--   INSERT INTO public.admin_sessions (admin_id, token_hash, expires_at)
--   VALUES (
--     admin_id_input,
--     encode(digest(v_token, 'sha256'), 'hex'),
--     now() + interval '8 hours'
--   );
--
--   RETURN QUERY
--   SELECT v_admin.id, v_admin.name, v_admin.is_active, v_token;
-- END;
-- $$;


-- ============================================================
-- SMOKE CHECKLIST（DB 実行後・本番でユーザーが実施）
--   ★実 PIN・raw token・個別 UUID・氏名は記録しない。結果は成功/0行/件数変化で表現。
--   ★テスト終了時は必ず正しい PIN で login し、使用 realm/identifier の throttle 行が
--     残っていないことを件数のみで確認（業務アカウントを cooldown 状態で放置しない）。
--
-- 【employee realm：index.html で threshold/cooldown 一式を1セット】
--   S-1 正しい PIN で通常 login（成功=1行・token 受領）
--   S-2 誤 PIN 1〜4回（毎回 loginError・0行・cooldown なし・即再入力可）
--   S-3 誤 PIN 5回目（loginError・0行・cooldown 開始）
--   S-4 cooldown 中の誤 PIN（loginError・0行・cooldown_until が延長されない＝相対確認）
--   S-5 cooldown 中の正しい PIN（★login 不可・0行★）
--   S-6 cooldown 終了後の正しい PIN（成功=1行）
--   S-7 成功後、該当 realm/identifier の throttle 行が削除（件数のみ確認）
--   S-8 logout 後の再 login（正常）
--
-- 【admin realm：admin-app.html または genka-app.html の一方で1セットだけ】
--   S-1〜S-8 と同一（両画面は同一 create_admin_session・realm='admin' のため重複実施しない）
--
-- 【残る admin 画面（もう一方）】
--   threshold 試験は行わない：正しい PIN で login → logout → 再 login →
--   .maybeSingle() 互換（0行=エラー表示 / 1行=成功）→ 通常のエラー表示のみ確認
--
-- 【共通回帰】
--   - session token 保存仕様（sha256 保存・raw 非永続・8h）不変
--   - Console 赤エラーなし・想定外 401/403 なし
-- ============================================================
