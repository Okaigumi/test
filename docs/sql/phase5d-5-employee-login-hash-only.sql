-- ============================================================
-- Phase 5-D-5：従業員login RPC hash-only化
-- ============================================================
-- STATUS: DRAFT / NOT EXECUTED / DO NOT RUN UNTIL H REVIEW PASS
--
-- 目的:
--   public.create_employee_session(uuid,text) の認証条件から
--   pin_hash IS NULL 時の employees.pin 平文fallbackだけを削除する。
--
-- 変更しないもの:
--   signature / 引数名 / RETURNS TABLE / owner / SECURITY DEFINER /
--   search_path / volatility / EXECUTE ACL / throttle / session発行 /
--   employees.pin列 / create・update RPC / admin・genka認証。
--
-- 実行者: 岡井さんのみ（Supabase SQL Editor・明示承認後）。
-- Codex／Claudeは実DBで実行しない。
-- ============================================================


-- ============================================================
-- Part 1：PRE-CHECK（read-only・BODYより先に単独実行）
-- 秘密値・氏名・UUID・tokenは出力しない。
-- ============================================================

WITH
emp AS (
  SELECT
    count(*) AS total,
    count(*) FILTER (WHERE pin_hash IS NULL) AS hash_null,
    count(*) FILTER (WHERE pin_hash IS NOT NULL) AS hash_notnull,
    count(*) FILTER (WHERE pin IS NOT NULL) AS pin_notnull,
    count(*) FILTER (
      WHERE pin_hash IS NOT NULL
        AND extensions.crypt(pin, pin_hash) = pin_hash
    ) AS hash_integrity,
    count(*) FILTER (WHERE pin_hash ~ '^\$2[aby]\$12\$') AS cost12
  FROM public.employees
),
fn AS (
  SELECT
    p.oid,
    p.oid::regprocedure::text AS signature,
    pg_get_userbyid(p.proowner)::text AS owner,
    p.prosecdef,
    p.provolatile::text AS volatility,
    COALESCE(array_to_string(p.proconfig, ', '), '(none)') AS proconfig,
    pg_get_function_result(p.oid) AS result_type,
    length(pg_get_functiondef(p.oid)) AS def_len,
    md5(pg_get_functiondef(p.oid)) AS def_md5,
    regexp_replace(p.prosrc, '\s+', ' ', 'g') AS norm
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.create_employee_session(uuid,text)')
),
writer_fn AS (
  SELECT e.fn_name,
         (p.oid IS NOT NULL
          AND length(pg_get_functiondef(p.oid)) = e.expected_len
          AND md5(pg_get_functiondef(p.oid)) = e.expected_md5) AS baseline_match
  FROM (VALUES
    ('create_employee_secure'::text,
     'public.create_employee_secure(text,text,text,text,uuid,boolean)'::text,
     1433, '33ea12279533b4a808a4d14bf11bb0a9'::text),
    ('update_employee_secure'::text,
     'public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)'::text,
     1915, '848eec0d7310c84cdffd05939b6c7a3b'::text)
  ) e(fn_name, signature, expected_len, expected_md5)
  LEFT JOIN pg_proc p ON p.oid = to_regprocedure(e.signature)
),
col_priv AS (
  SELECT count(*) FILTER (
    WHERE has_column_privilege(r.role, 'public.employees', c.col, p.priv)
  ) AS unexpected_grants
  FROM (VALUES ('anon'::text), ('authenticated'::text)) r(role)
  CROSS JOIN (VALUES ('pin'::text), ('pin_hash'::text)) c(col)
  CROSS JOIN (VALUES ('SELECT'::text), ('INSERT'::text),
                     ('UPDATE'::text), ('REFERENCES'::text)) p(priv)
),
exec_priv AS (
  SELECT count(*) FILTER (
    WHERE has_function_privilege(
      r.role,
      to_regprocedure(f.signature),
      'EXECUTE'
    )
  ) AS allowed_count
  FROM (VALUES ('anon'::text), ('authenticated'::text)) r(role)
  CROSS JOIN (VALUES
    ('public.create_employee_secure(text,text,text,text,uuid,boolean)'::text),
    ('public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)'::text),
    ('public.create_employee_session(uuid,text)'::text)
  ) f(signature)
),
public_exec AS (
  SELECT count(*) AS grant_count
  FROM pg_proc p
  CROSS JOIN LATERAL aclexplode(
    COALESCE(p.proacl, acldefault('f', p.proowner))
  ) acl
  WHERE p.oid = to_regprocedure('public.create_employee_session(uuid,text)')
    AND acl.grantee = 0
    AND acl.privilege_type = 'EXECUTE'
)
SELECT 'P1_counts' AS section, 'total' AS key, total::text AS value FROM emp
UNION ALL SELECT 'P1_counts', 'hash_null', hash_null::text FROM emp
UNION ALL SELECT 'P1_counts', 'hash_notnull', hash_notnull::text FROM emp
UNION ALL SELECT 'P1_counts', 'pin_notnull', pin_notnull::text FROM emp
UNION ALL SELECT 'P1_counts', 'hash_integrity', hash_integrity::text FROM emp
UNION ALL SELECT 'P1_counts', 'cost12', cost12::text FROM emp
UNION ALL SELECT 'P2_rpc', 'signature', COALESCE(signature, 'MISSING') FROM fn
UNION ALL SELECT 'P2_rpc', 'owner', COALESCE(owner, 'MISSING') FROM fn
UNION ALL SELECT 'P2_rpc', 'secdef', COALESCE(prosecdef::text, 'MISSING') FROM fn
UNION ALL SELECT 'P2_rpc', 'volatility', COALESCE(volatility, 'MISSING') FROM fn
UNION ALL SELECT 'P2_rpc', 'proconfig', COALESCE(proconfig, 'MISSING') FROM fn
UNION ALL SELECT 'P2_rpc', 'result_type', COALESCE(result_type, 'MISSING') FROM fn
UNION ALL SELECT 'P2_rpc', 'def_len', COALESCE(def_len::text, 'MISSING') FROM fn
UNION ALL SELECT 'P2_rpc', 'def_md5', COALESCE(def_md5, 'MISSING') FROM fn
UNION ALL SELECT 'P2_rpc', 'has_hash_branch',
  COALESCE((norm ILIKE '%WHEN e.pin_hash IS NOT NULL THEN%extensions.crypt(pin_input, e.pin_hash) = e.pin_hash%')::text, 'MISSING') FROM fn
UNION ALL SELECT 'P2_rpc', 'has_plaintext_fallback',
  COALESCE((norm ILIKE '%ELSE e.pin = pin_input%')::text, 'MISSING') FROM fn
UNION ALL SELECT 'P2_writer_rpc', fn_name || '.baseline_match', baseline_match::text FROM writer_fn
UNION ALL SELECT 'P3_priv', 'unexpected_column_grants', unexpected_grants::text FROM col_priv
UNION ALL SELECT 'P3_priv', 'required_execute_grants', allowed_count::text FROM exec_priv
UNION ALL SELECT 'P3_priv', 'public_execute_grants', grant_count::text FROM public_exec
ORDER BY 1, 2;

/*
PRE-CHECK合格条件:
  total > 0
  hash_null = 0
  hash_notnull = pin_notnull = hash_integrity = cost12 = total
  signature = public.create_employee_session(uuid,text)
  owner=postgres / secdef=true / volatility=v
  proconfig=search_path=public, extensions
  def_len=3798 / def_md5=006550c3455e34aa9d1d61bd60bb85ad
  has_hash_branch=true / has_plaintext_fallback=true
  create_employee_secure.baseline_match=true
  update_employee_secure.baseline_match=true
  unexpected_column_grants=0 / required_execute_grants=6 /
  public_execute_grants は観測値として記録する（未観測のため合否条件にしない）
  BODYは実行前ACL全文を保存し、CREATE OR REPLACE後に同一性を検証する
*/


-- ============================================================
-- Part 2：BODY（★未実行。Hレビュー・明示承認後に1回だけ★）
-- ============================================================

BEGIN;

DO $guard$
DECLARE
  v_total integer;
  v_hash_null integer;
  v_hash_notnull integer;
  v_pin_notnull integer;
  v_hash_integrity integer;
  v_cost12 integer;
  v_count integer;
  v_norm text;
  v_acl_before text;
BEGIN
  SELECT
    count(*),
    count(*) FILTER (WHERE pin_hash IS NULL),
    count(*) FILTER (WHERE pin_hash IS NOT NULL),
    count(*) FILTER (WHERE pin IS NOT NULL),
    count(*) FILTER (
      WHERE pin_hash IS NOT NULL
        AND extensions.crypt(pin, pin_hash) = pin_hash
    ),
    count(*) FILTER (WHERE pin_hash ~ '^\$2[aby]\$12\$')
  INTO v_total, v_hash_null, v_hash_notnull,
       v_pin_notnull, v_hash_integrity, v_cost12
  FROM public.employees;

  IF v_total <= 0
     OR v_hash_null <> 0
     OR v_hash_notnull <> v_total
     OR v_pin_notnull <> v_total
     OR v_hash_integrity <> v_total
     OR v_cost12 <> v_total THEN
    RAISE EXCEPTION
      'G-1 failed: employee hash precondition mismatch '
      '(total %, null %, notnull %, pin %, integrity %, cost12 %)',
      v_total, v_hash_null, v_hash_notnull,
      v_pin_notnull, v_hash_integrity, v_cost12;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.create_employee_session(uuid,text)')
    AND pg_get_userbyid(p.proowner) = 'postgres'
    AND p.prosecdef = true
    AND p.provolatile = 'v'
    AND p.proconfig = ARRAY['search_path=public, extensions']
    AND length(pg_get_functiondef(p.oid)) = 3798
    AND md5(pg_get_functiondef(p.oid)) = '006550c3455e34aa9d1d61bd60bb85ad';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'G-2 failed: current login RPC baseline mismatch';
  END IF;

  SELECT count(*) INTO v_count
  FROM (VALUES
    ('public.create_employee_secure(text,text,text,text,uuid,boolean)'::text,
     1433, '33ea12279533b4a808a4d14bf11bb0a9'::text),
    ('public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)'::text,
     1915, '848eec0d7310c84cdffd05939b6c7a3b'::text)
  ) e(signature, expected_len, expected_md5)
  JOIN pg_proc p ON p.oid = to_regprocedure(e.signature)
  WHERE length(pg_get_functiondef(p.oid)) = e.expected_len
    AND md5(pg_get_functiondef(p.oid)) = e.expected_md5;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'G-2b failed: create/update dual-write RPC baseline mismatch';
  END IF;

  SELECT regexp_replace(p.prosrc, '\s+', ' ', 'g') INTO v_norm
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.create_employee_session(uuid,text)');

  IF v_norm NOT ILIKE
       '%WHEN e.pin_hash IS NOT NULL THEN%'
       'extensions.crypt(pin_input, e.pin_hash) = e.pin_hash%'
       'ELSE e.pin = pin_input%END%' THEN
    RAISE EXCEPTION 'G-3 failed: expected dual-read branch not found';
  END IF;

  SELECT count(*) INTO v_count
  FROM (VALUES ('anon'::text), ('authenticated'::text)) r(role)
  CROSS JOIN (VALUES ('pin'::text), ('pin_hash'::text)) c(col)
  CROSS JOIN (VALUES ('SELECT'::text), ('INSERT'::text),
                     ('UPDATE'::text), ('REFERENCES'::text)) p(priv)
  WHERE has_column_privilege(r.role, 'public.employees', c.col, p.priv);
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'G-4 failed: unexpected direct pin/pin_hash privilege';
  END IF;

  SELECT count(*) INTO v_count
  FROM (VALUES ('anon'::text), ('authenticated'::text)) r(role)
  CROSS JOIN (VALUES
    ('public.create_employee_secure(text,text,text,text,uuid,boolean)'::text),
    ('public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)'::text),
    ('public.create_employee_session(uuid,text)'::text)
  ) f(signature)
  WHERE has_function_privilege(r.role, to_regprocedure(f.signature), 'EXECUTE');
  IF v_count <> 6 THEN
    RAISE EXCEPTION 'G-5 failed: required RPC EXECUTE count = % (expected 6)', v_count;
  END IF;

  SELECT COALESCE(p.proacl::text, '<NULL>') INTO v_acl_before
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.create_employee_session(uuid,text)');
  IF v_acl_before IS NULL THEN
    RAISE EXCEPTION 'G-6 failed: login RPC ACL could not be captured';
  END IF;
  PERFORM set_config('okg.sec5d5_acl_before', v_acl_before, true);

  RAISE NOTICE 'GUARD passed: hash-only migration preconditions confirmed';
END;
$guard$;


-- step (6) のPIN照合条件だけをhash-onlyへ変更する。
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

  -- (6) PIN + is_active 照合（hash-only）
  -- pin_hashがない行は認証しない。employees.pinは参照しない。
  SELECT *
  INTO   v_emp
  FROM   public.employees e
  WHERE  e.id        = employee_id_input
    AND  e.pin_hash IS NOT NULL
    AND  extensions.crypt(pin_input, e.pin_hash) = e.pin_hash
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


DO $postcheck$
DECLARE
  v_count integer;
  v_total integer;
  v_hash_null integer;
  v_hash_integrity integer;
  v_cost12 integer;
  v_norm text;
  v_len integer;
  v_md5 text;
  v_pattern text;
  v_required text[];
  v_acl_after text;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE pin_hash IS NULL),
         count(*) FILTER (
           WHERE pin_hash IS NOT NULL
             AND extensions.crypt(pin, pin_hash) = pin_hash
         ),
         count(*) FILTER (WHERE pin_hash ~ '^\$2[aby]\$12\$')
  INTO v_total, v_hash_null, v_hash_integrity, v_cost12
  FROM public.employees;
  IF v_total <= 0 OR v_hash_null <> 0
     OR v_hash_integrity <> v_total OR v_cost12 <> v_total THEN
    RAISE EXCEPTION 'PC-1 failed: employee hash state changed';
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.create_employee_session(uuid,text)')
    AND pg_get_userbyid(p.proowner) = 'postgres'
    AND p.prosecdef = true
    AND p.provolatile = 'v'
    AND p.proconfig = ARRAY['search_path=public, extensions']
    AND p.proretset = true
    AND pg_get_function_result(p.oid) ILIKE
      '%id uuid%name text%role text%is_active boolean%'
      '%company_id uuid%can_genka boolean%can_admin boolean%session_token text%';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'PC-2 failed: RPC signature/attributes/result mismatch';
  END IF;

  SELECT regexp_replace(p.prosrc, '\s+', ' ', 'g'),
         length(pg_get_functiondef(p.oid)), md5(pg_get_functiondef(p.oid))
  INTO v_norm, v_len, v_md5
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.create_employee_session(uuid,text)');

  IF v_norm NOT ILIKE '%e.pin_hash IS NOT NULL%'
     OR v_norm NOT ILIKE '%extensions.crypt(pin_input, e.pin_hash) = e.pin_hash%'
     OR v_norm ILIKE '%e.pin = pin_input%'
     OR v_norm ILIKE '%WHEN e.pin_hash IS NOT NULL THEN%' THEN
    RAISE EXCEPTION 'PC-3 failed: hash-only predicate/fallback check failed';
  END IF;

  v_required := ARRAY[
    '%FOR KEY SHARE%',
    '%private.login_throttle%',
    '%FOR UPDATE%',
    '%clock_timestamp()%',
    '%15 minutes%',
    '%60 seconds%',
    '%v_next_fail_count >= 5%',
    '%DELETE FROM private.login_throttle%',
    '%DELETE FROM public.employee_sessions%',
    '%INSERT INTO public.employee_sessions%',
    '%gen_random_bytes(32)%',
    '%digest(v_token, ''sha256'')%',
    '%8 hours%'
  ];
  FOREACH v_pattern IN ARRAY v_required LOOP
    IF v_norm NOT ILIKE v_pattern THEN
      RAISE EXCEPTION 'PC-4 failed: invariant marker % missing', v_pattern;
    END IF;
  END LOOP;

  IF v_len = 3798 AND v_md5 = '006550c3455e34aa9d1d61bd60bb85ad' THEN
    RAISE EXCEPTION 'PC-5 failed: function fingerprint did not change';
  END IF;

  SELECT count(*) INTO v_count
  FROM (VALUES ('anon'::text), ('authenticated'::text)) r(role)
  CROSS JOIN (VALUES ('pin'::text), ('pin_hash'::text)) c(col)
  CROSS JOIN (VALUES ('SELECT'::text), ('INSERT'::text),
                     ('UPDATE'::text), ('REFERENCES'::text)) p(priv)
  WHERE has_column_privilege(r.role, 'public.employees', c.col, p.priv);
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'PC-6 failed: unexpected direct pin/pin_hash privilege';
  END IF;

  SELECT count(*) INTO v_count
  FROM (VALUES ('anon'::text), ('authenticated'::text)) r(role)
  CROSS JOIN (VALUES
    ('public.create_employee_secure(text,text,text,text,uuid,boolean)'::text),
    ('public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)'::text),
    ('public.create_employee_session(uuid,text)'::text)
  ) f(signature)
  WHERE has_function_privilege(r.role, to_regprocedure(f.signature), 'EXECUTE');
  IF v_count <> 6 THEN
    RAISE EXCEPTION 'PC-7 failed: required RPC EXECUTE count = %', v_count;
  END IF;

  SELECT COALESCE(p.proacl::text, '<NULL>') INTO v_acl_after
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.create_employee_session(uuid,text)');
  IF v_acl_after IS DISTINCT FROM
       current_setting('okg.sec5d5_acl_before', true) THEN
    RAISE EXCEPTION 'PC-8 failed: login RPC ACL changed';
  END IF;

  SELECT count(*) INTO v_count
  FROM (VALUES
    ('public.create_employee_secure(text,text,text,text,uuid,boolean)'::text,
     1433, '33ea12279533b4a808a4d14bf11bb0a9'::text),
    ('public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)'::text,
     1915, '848eec0d7310c84cdffd05939b6c7a3b'::text)
  ) e(signature, expected_len, expected_md5)
  JOIN pg_proc p ON p.oid = to_regprocedure(e.signature)
  WHERE length(pg_get_functiondef(p.oid)) = e.expected_len
    AND md5(pg_get_functiondef(p.oid)) = e.expected_md5;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'PC-9 failed: create/update dual-write RPC baseline changed';
  END IF;

  RAISE NOTICE 'POST-CHECK passed: new_def_length=% / new_def_md5=%', v_len, v_md5;
END;
$postcheck$;

COMMIT;


-- ============================================================
-- Part 3：POST-COMMIT（read-only・結果を記録）
-- ============================================================

WITH emp AS (
  SELECT count(*) AS total,
         count(*) FILTER (WHERE pin_hash IS NULL) AS hash_null,
         count(*) FILTER (WHERE extensions.crypt(pin, pin_hash) = pin_hash) AS hash_integrity,
         count(*) FILTER (WHERE pin_hash ~ '^\$2[aby]\$12\$') AS cost12
  FROM public.employees
), fn AS (
  SELECT length(pg_get_functiondef(p.oid)) AS def_len,
         md5(pg_get_functiondef(p.oid)) AS def_md5,
         regexp_replace(p.prosrc, '\s+', ' ', 'g') AS norm
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.create_employee_session(uuid,text)')
)
SELECT 'counts' AS section, 'total' AS key, total::text AS value FROM emp
UNION ALL SELECT 'counts', 'hash_null', hash_null::text FROM emp
UNION ALL SELECT 'counts', 'hash_integrity', hash_integrity::text FROM emp
UNION ALL SELECT 'counts', 'cost12', cost12::text FROM emp
UNION ALL SELECT 'rpc', 'def_len', def_len::text FROM fn
UNION ALL SELECT 'rpc', 'def_md5', def_md5 FROM fn
UNION ALL SELECT 'rpc', 'has_hash_only',
  ((norm ILIKE '%e.pin_hash IS NOT NULL%')
   AND (norm ILIKE '%extensions.crypt(pin_input, e.pin_hash) = e.pin_hash%'))::text FROM fn
UNION ALL SELECT 'rpc', 'has_plaintext_fallback',
  (norm ILIKE '%e.pin = pin_input%')::text FROM fn
ORDER BY 1, 2;


-- ============================================================
-- Part 4：rollback案（コメント解除・再レビュー・明示承認後だけ実行）
-- ============================================================
-- COMMIT前: GUARD／POST-CHECK失敗でtransaction全体をabortする。
-- COMMIT後: 下記は5-D-1のstep (6)を含むdual-read定義へ戻す案。
-- 新fingerprintには依存せず、hash-only構造・属性・writer baselineを
-- fail-closedで確認し、ACL全文をtransaction内で前後比較する。
-- 現時点では全体をコメント化しており実行不可。コメント解除後の版を
-- H再レビューし、対象版と実行を岡井さんが明示承認するまで実行しない。
-- DROP FUNCTION、employees列変更、データ更新、ACL変更は行わない。

/*
BEGIN;

DO $rollback_guard$
DECLARE
  v_count integer;
  v_norm text;
  v_acl_before text;
BEGIN
  SELECT count(*), min(regexp_replace(p.prosrc, '\s+', ' ', 'g')),
         min(COALESCE(p.proacl::text, '<NULL>'))
  INTO v_count, v_norm, v_acl_before
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.create_employee_session(uuid,text)')
    AND pg_get_userbyid(p.proowner) = 'postgres'
    AND p.prosecdef = true
    AND p.provolatile = 'v'
    AND p.proconfig = ARRAY['search_path=public, extensions'];
  IF v_count <> 1
     OR v_norm NOT ILIKE '%e.pin_hash IS NOT NULL%'
     OR v_norm NOT ILIKE '%extensions.crypt(pin_input, e.pin_hash) = e.pin_hash%'
     OR v_norm ILIKE '%e.pin = pin_input%'
     OR v_acl_before IS NULL THEN
    RAISE EXCEPTION 'RB-G-1 failed: expected hash-only RPC/attributes not found';
  END IF;
  PERFORM set_config('okg.sec5d5_rb_acl_before', v_acl_before, true);

  SELECT count(*) INTO v_count
  FROM (VALUES
    ('public.create_employee_secure(text,text,text,text,uuid,boolean)'::text,
     1433, '33ea12279533b4a808a4d14bf11bb0a9'::text),
    ('public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)'::text,
     1915, '848eec0d7310c84cdffd05939b6c7a3b'::text)
  ) e(signature, expected_len, expected_md5)
  JOIN pg_proc p ON p.oid = to_regprocedure(e.signature)
  WHERE length(pg_get_functiondef(p.oid)) = e.expected_len
    AND md5(pg_get_functiondef(p.oid)) = e.expected_md5;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'RB-G-2 failed: writer baseline mismatch';
  END IF;
END;
$rollback_guard$;

CREATE OR REPLACE FUNCTION public.create_employee_session(
  employee_id_input uuid,
  pin_input         text
)
RETURNS TABLE (
  id uuid, name text, role text, is_active boolean, company_id uuid,
  can_genka boolean, can_admin boolean, session_token text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_emp public.employees%ROWTYPE;
  v_token text;
  v_fail_count integer;
  v_cooldown_until timestamptz;
  v_last_failed_at timestamptz;
  v_effective_fail_count integer;
  v_next_fail_count integer;
  v_throttle_now timestamptz;
  v_failed_at timestamptz;
BEGIN
  PERFORM 1 FROM public.employees e
  WHERE e.id = employee_id_input FOR KEY SHARE;
  IF NOT FOUND THEN RETURN; END IF;

  INSERT INTO private.login_throttle (realm, identifier, fail_count, updated_at)
  VALUES ('employee', employee_id_input, 0, clock_timestamp())
  ON CONFLICT (realm, identifier) DO NOTHING;

  SELECT lt.fail_count, lt.cooldown_until, lt.last_failed_at
  INTO v_fail_count, v_cooldown_until, v_last_failed_at
  FROM private.login_throttle lt
  WHERE lt.realm = 'employee' AND lt.identifier = employee_id_input
  FOR UPDATE;

  v_throttle_now := clock_timestamp();
  IF v_cooldown_until IS NOT NULL AND v_cooldown_until > v_throttle_now THEN
    RETURN;
  END IF;
  IF v_last_failed_at IS NULL
     OR (v_throttle_now - v_last_failed_at) >= interval '15 minutes' THEN
    v_effective_fail_count := 0;
  ELSE
    v_effective_fail_count := v_fail_count;
  END IF;

  SELECT * INTO v_emp
  FROM public.employees e
  WHERE e.id = employee_id_input
    AND CASE
          WHEN e.pin_hash IS NOT NULL THEN
            extensions.crypt(pin_input, e.pin_hash) = e.pin_hash
          ELSE e.pin = pin_input
        END
    AND e.is_active = true;

  IF NOT FOUND THEN
    v_failed_at := clock_timestamp();
    v_next_fail_count := v_effective_fail_count + 1;
    UPDATE private.login_throttle
    SET fail_count = v_next_fail_count,
        last_failed_at = v_failed_at,
        cooldown_until = CASE WHEN v_next_fail_count >= 5
                              THEN v_failed_at + interval '60 seconds'
                              ELSE NULL END,
        updated_at = v_failed_at
    WHERE realm = 'employee' AND identifier = employee_id_input;
    RETURN;
  END IF;

  DELETE FROM private.login_throttle
  WHERE realm = 'employee' AND identifier = employee_id_input;
  DELETE FROM public.employee_sessions s
  WHERE s.employee_id = employee_id_input OR s.expires_at < now();
  v_token := encode(gen_random_bytes(32), 'hex');
  INSERT INTO public.employee_sessions (employee_id, token_hash, expires_at)
  VALUES (employee_id_input, encode(digest(v_token, 'sha256'), 'hex'),
          now() + interval '8 hours');
  RETURN QUERY SELECT v_emp.id, v_emp.name, v_emp.role, v_emp.is_active,
    v_emp.company_id, v_emp.can_genka, v_emp.can_admin, v_token;
END;
$$;

DO $rollback_postcheck$
DECLARE
  v_count integer;
  v_norm text;
  v_acl_after text;
BEGIN
  SELECT count(*), min(regexp_replace(p.prosrc, '\s+', ' ', 'g')),
         min(COALESCE(p.proacl::text, '<NULL>'))
  INTO v_count, v_norm, v_acl_after
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.create_employee_session(uuid,text)')
    AND pg_get_userbyid(p.proowner) = 'postgres'
    AND p.prosecdef = true
    AND p.provolatile = 'v'
    AND p.proconfig = ARRAY['search_path=public, extensions'];
  IF v_count <> 1
     OR v_norm NOT ILIKE '%WHEN e.pin_hash IS NOT NULL THEN%'
     OR v_norm NOT ILIKE '%ELSE e.pin = pin_input%'
     OR v_acl_after IS DISTINCT FROM
          current_setting('okg.sec5d5_rb_acl_before', true) THEN
    RAISE EXCEPTION 'RB-PC-1 failed: dual-read restore/ACL check failed';
  END IF;
END;
$rollback_postcheck$;

COMMIT;
*/


-- ============================================================
-- Part 5：Production smoke計画（DB適用後、岡井さんが手動）
-- ============================================================
-- S-1: POST-COMMIT結果が全件hash整合、fallback=false。
-- S-2: 代表従業員1名で正しいPINログイン成功。
-- S-3: 同じ従業員で誤PINを1回だけ入力し拒否を確認。
-- S-4: 正しいPINで再ログインし、throttle正常化を確認。
-- S-5: inactive従業員が0行応答のまま認証されないことを確認。
-- S-6: 管理者login、原価管理loginの回帰なし。
-- S-7: index.htmlのlogin/logoutと主要画面表示に回帰なし。
-- PIN・氏名・UUID・tokenは記録しない。
