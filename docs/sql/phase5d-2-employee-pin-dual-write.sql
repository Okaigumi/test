-- ============================================================
-- Phase 5-D-2：employees create / update RPC dual-write 化
-- ============================================================
-- 【実行ステータス】STATUS: PENDING（★DB 未実行★）
--   - preparation date：2026-07-23（準備 PR #169）
--   - execution date  ：未定（3者合意・smoke 計画確認後に Supabase SQL Editor で手動実行）
--   - ★ BODY は1回のみ実行。再実行禁止★
--     （GUARD が baseline fingerprint 不一致・二重適用を fail-closed で停止）
--
-- 【目的】
--   create_employee_secure / update_employee_secure の2本を
--   CREATE OR REPLACE で dual-write（pin + pin_hash 同時書込み）に更新する。
--   - 新規作成：単一 INSERT で pin と pin_hash を原子的に保存
--   - PIN 変更：単一 UPDATE で pin と pin_hash を原子的に更新
--   - PIN 未変更：pin も pin_hash も触れない（backfill は 5-D-3）
--   - bcrypt cost 12・extensions.crypt スキーマ修飾
--   - PIN バリデーション：'^[0-9]{4}$'（半角数字4桁に厳格化）
--
-- 【対象 DB オブジェクト】
--   - public.create_employee_secure(text,text,text,text,uuid,boolean)  — baseline len=1142 / md5=de7f84d9f63970be1dc9d7741716047f
--   - public.update_employee_secure(text,uuid,text,text,boolean,uuid,text) — baseline len=1492 / md5=0e5a7c3d9a0fe80230c643131edaa325
--
-- 【非対象（今回変更しない）】
--   - 既存 11 件の backfill（Phase 5-D-3）
--   - plaintext employees.pin の削除（Phase 5-D-6）
--   - create_employee_session / genka_admins / create_admin_session
--   - _verify_management_session への統一（別工程）
--   - frontend（変更不要）
--   - employees.pin_hash 列（5-D-1 で追加済み）
--   - RLS / policy / GRANT / REVOKE
--
-- 【実行方法（重要）】
--   実行先：Supabase SQL Editor（手動実行のみ）
--   手順：
--     1. Part 1 PRE-CHECK を実行 → 全行が期待値と一致することを確認
--     2. ChatGPT 承認後、Part 2 BODY の BEGIN~COMMIT を1回だけ実行
--     3. NOTICE「GUARD OK」「POST-CHECK all passed」「new fingerprints」を確認・記録
--     4. Part 3 POST-COMMIT を実行 → 結果を ChatGPT へ貼り戻す
--     5. ROLLBACK の <FILL_IN> を Part 3 値で確定してから保存
-- ============================================================


-- ============================================================
-- Part 1：PRE-CHECK（read-only・1本・実行後に全行が期待値と一致することを確認）
-- 非出力：PIN値・pin_hash値・氏名・UUID・token・secret
-- exact OID（to_regprocedure）のみを後続処理に使用
-- ============================================================

WITH

target_fn AS (
  SELECT
    'create_employee_secure'::text   AS fn_name,
    to_regprocedure(
      'public.create_employee_secure(text,text,text,text,uuid,boolean)'
    )                                AS fn_oid
  UNION ALL
  SELECT
    'update_employee_secure'::text,
    to_regprocedure(
      'public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)'
    )
),

fn_count AS (
  SELECT count(*) FILTER (WHERE fn_oid IS NOT NULL)::text AS cnt
  FROM   target_fn
),

fn AS (
  SELECT
    t.fn_name::text                                          AS fn_name,
    p.oid::regprocedure::text                               AS signature,
    pg_get_userbyid(p.proowner)::text                       AS owner,
    p.prosecdef::text                                       AS secdef,
    p.provolatile::text                                     AS volatility,
    COALESCE(array_to_string(p.proconfig, ', '), '(none)')::text AS proconfig,
    length(pg_get_functiondef(p.oid))::text                 AS def_len,
    md5(pg_get_functiondef(p.oid))::text                    AS def_md5
  FROM   target_fn t
  JOIN   pg_proc p ON p.oid = t.fn_oid::oid
  WHERE  t.fn_oid IS NOT NULL
),

col AS (
  SELECT column_name::text, data_type::text, is_nullable::text,
         COALESCE(column_default, '(none)')::text AS col_default
  FROM   information_schema.columns
  WHERE  table_schema = 'public'
    AND  table_name   = 'employees'
    AND  column_name  IN ('pin', 'pin_hash')
),

emp AS (
  SELECT
    count(*)::text                                          AS total,
    count(*) FILTER (WHERE pin_hash IS NULL)::text          AS hash_null,
    count(*) FILTER (WHERE pin_hash IS NOT NULL)::text      AS hash_not_null
  FROM public.employees
),

ext AS (
  SELECT
    e.extname::text, e.extversion::text, n.nspname::text AS ext_schema,
    (to_regprocedure(n.nspname || '.crypt(text,text)') IS NOT NULL)::text         AS crypt_exact,
    (to_regprocedure(n.nspname || '.gen_salt(text,integer)') IS NOT NULL)::text   AS gen_salt_exact
  FROM   pg_extension e
  JOIN   pg_namespace n ON n.oid = e.extnamespace
  WHERE  e.extname = 'pgcrypto'
),

col_prv AS (
  SELECT r.role::text, c.col::text, p.priv::text,
         has_column_privilege(r.role, 'public.employees', c.col, p.priv)::text AS has_priv
  FROM   (VALUES ('anon'::text), ('authenticated'::text))                  r(role)
  CROSS  JOIN (VALUES ('pin'::text), ('pin_hash'::text))                   c(col)
  CROSS  JOIN (VALUES ('SELECT'::text), ('INSERT'::text),
                      ('UPDATE'::text), ('REFERENCES'::text))              p(priv)
),

fn_prv AS (
  SELECT r.role::text, fns.sig::text,
         has_function_privilege(r.role, fns.oid, 'EXECUTE')::text AS can_execute
  FROM   (VALUES ('anon'::text), ('authenticated'::text))  r(role)
  CROSS  JOIN (
    SELECT p.oid, p.oid::regprocedure::text AS sig
    FROM   target_fn t
    JOIN   pg_proc p ON p.oid = t.fn_oid::oid
    WHERE  t.fn_oid IS NOT NULL
  ) fns
),

fn_src AS (
  SELECT
    t.fn_name::text                                                                AS fn_name,
    (p.prosrc ILIKE '%pin_hash%')::text                                           AS refs_pin_hash,
    (p.prosrc NOT ILIKE '%pin_hash%')::text                                       AS pin_hash_absent,
    (p.prosrc ILIKE '%extensions.crypt%')::text                                   AS refs_extensions_crypt,
    (p.prosrc ILIKE '%[0-9]{4}%')::text                                           AS refs_4digit_regex,
    (p.prosrc ILIKE '%admin_sessions%')::text                                     AS uses_admin_sessions,
    (p.prosrc ILIKE '%_verify_management_session%')::text                         AS uses_verify_mgmt_session
  FROM   target_fn t
  JOIN   pg_proc p ON p.oid = t.fn_oid::oid
  WHERE  t.fn_oid IS NOT NULL
),

fn_baseline AS (
  SELECT
    t.fn_name::text,
    (CASE WHEN t.fn_name = 'create_employee_secure'
          THEN md5(pg_get_functiondef(p.oid)) = 'de7f84d9f63970be1dc9d7741716047f'
               AND length(pg_get_functiondef(p.oid)) = 1142
          WHEN t.fn_name = 'update_employee_secure'
          THEN md5(pg_get_functiondef(p.oid)) = '0e5a7c3d9a0fe80230c643131edaa325'
               AND length(pg_get_functiondef(p.oid)) = 1492
          ELSE false
     END)::text AS baseline_match
  FROM   target_fn t
  JOIN   pg_proc p ON p.oid = t.fn_oid::oid
  WHERE  t.fn_oid IS NOT NULL
)

SELECT 'C0_sig_check' AS section,
       'create_exact_oid_exists' AS key,
       (SELECT (fn_oid IS NOT NULL)::text FROM target_fn WHERE fn_name='create_employee_secure') AS value
UNION ALL SELECT 'C0_sig_check', 'update_exact_oid_exists',
       (SELECT (fn_oid IS NOT NULL)::text FROM target_fn WHERE fn_name='update_employee_secure')
UNION ALL SELECT 'C0_sig_check', 'functions_found_(non_null_oid)', cnt FROM fn_count

UNION ALL SELECT 'C1_fn_fp', fn_name || '.signature',  signature  FROM fn
UNION ALL SELECT 'C1_fn_fp', fn_name || '.owner',      owner      FROM fn
UNION ALL SELECT 'C1_fn_fp', fn_name || '.secdef',     secdef     FROM fn
UNION ALL SELECT 'C1_fn_fp', fn_name || '.volatility', volatility FROM fn
UNION ALL SELECT 'C1_fn_fp', fn_name || '.proconfig',  proconfig  FROM fn
UNION ALL SELECT 'C1_fn_fp', fn_name || '.def_len',    def_len    FROM fn
UNION ALL SELECT 'C1_fn_fp', fn_name || '.def_md5',    def_md5    FROM fn
UNION ALL SELECT 'C1_fn_fp', fn_name || '.baseline_match', baseline_match FROM fn_baseline

UNION ALL
SELECT 'C2_col_schema', column_name,
       'type=' || data_type || ' | nullable=' || is_nullable || ' | default=' || col_default
FROM   col
UNION ALL SELECT 'C2_col_schema', 'pin_hash_col_exists',
       (EXISTS (SELECT 1 FROM col WHERE column_name = 'pin_hash'))::text

UNION ALL SELECT 'C3_emp', 'total',             total         FROM emp
UNION ALL SELECT 'C3_emp', 'pin_hash_null',     hash_null     FROM emp
UNION ALL SELECT 'C3_emp', 'pin_hash_not_null', hash_not_null FROM emp

UNION ALL SELECT 'C4_pgcrypto', 'installed',
       (SELECT (count(*)>0)::text FROM pg_extension WHERE extname='pgcrypto')
UNION ALL SELECT 'C4_pgcrypto', 'extname',                   extname        FROM ext
UNION ALL SELECT 'C4_pgcrypto', 'extversion',                extversion     FROM ext
UNION ALL SELECT 'C4_pgcrypto', 'schema',                    ext_schema     FROM ext
UNION ALL SELECT 'C4_pgcrypto', 'crypt(text,text)_exact',    crypt_exact    FROM ext
UNION ALL SELECT 'C4_pgcrypto', 'gen_salt(text,int)_exact',  gen_salt_exact FROM ext

UNION ALL SELECT 'C5_col_privs', role || '.' || col || '.' || priv, has_priv FROM col_prv

UNION ALL SELECT 'C6_fn_privs', role || '.' || sig, can_execute FROM fn_prv

UNION ALL SELECT 'C7_fn_src', fn_name || '.refs_pin_hash',         refs_pin_hash              FROM fn_src
UNION ALL SELECT 'C7_fn_src', fn_name || '.pin_hash_absent_(cur)', pin_hash_absent            FROM fn_src
UNION ALL SELECT 'C7_fn_src', fn_name || '.refs_extensions_crypt', refs_extensions_crypt      FROM fn_src
UNION ALL SELECT 'C7_fn_src', fn_name || '.refs_4digit_regex',     refs_4digit_regex          FROM fn_src
UNION ALL SELECT 'C7_fn_src', fn_name || '.uses_admin_sessions',   uses_admin_sessions        FROM fn_src
UNION ALL SELECT 'C7_fn_src', fn_name || '.uses_verify_mgmt',      uses_verify_mgmt_session   FROM fn_src

ORDER BY 1, 2;

/*
  PRE-CHECK 期待値
  -----------------------------------------------------------------------
  C0_sig_check  create_exact_oid_exists      : true
  C0_sig_check  update_exact_oid_exists      : true
  C0_sig_check  functions_found_(non_null)   : 2
  C1_fn_fp      *.baseline_match             : true（双方とも）
  C1_fn_fp      *.owner                      : postgres
  C1_fn_fp      *.secdef                     : true
  C1_fn_fp      *.volatility                 : v
  C1_fn_fp      *.proconfig                  : search_path=public, extensions
  C2_col_schema  pin                         : type=text | nullable=NO | default=(none)
  C2_col_schema  pin_hash                    : type=text | nullable=YES | default=(none)
  C2_col_schema  pin_hash_col_exists         : true
  C3_emp         total                       : 11
  C3_emp         pin_hash_null               : 11
  C3_emp         pin_hash_not_null           : 0
  C4_pgcrypto    installed / schema          : true / extensions
  C4_pgcrypto    crypt / gen_salt            : true / true
  C5_col_privs   全 16 行                   : false
  C6_fn_privs    anon.* / authenticated.*   : true（EXECUTE 維持確認）
  C7_fn_src      *.pin_hash_absent_(cur)    : true（現行に pin_hash 参照なし）
  C7_fn_src      *.refs_extensions_crypt    : false（現行は crypt 未使用）
  C7_fn_src      *.refs_4digit_regex        : false（現行は length() 比較）
  C7_fn_src      *.uses_admin_sessions      : true
  C7_fn_src      *.uses_verify_mgmt         : false
  -----------------------------------------------------------------------
*/


-- ============================================================
-- Part 2：BODY（★Part 1 全合格・ChatGPT 承認後に1回のみ実行★）
--   BEGIN ~ COMMIT を丸ごと選択して実行する。再実行禁止。
--   GUARD または内部 POST-CHECK 失敗 → 自動 abort → DB 無変更。
-- ============================================================

BEGIN;

-- ---- GUARD（fail-closed） ----
DO $guard$
DECLARE
  v_count       integer;
  v_md5         text;
  v_len         integer;
  v_ext_schema  text;
  v_create_oid  oid;
  v_update_oid  oid;
BEGIN

  -- G-0: exact OID 取得（不存在なら即停止）
  SELECT to_regprocedure(
    'public.create_employee_secure(text,text,text,text,uuid,boolean)'
  )::oid INTO v_create_oid;
  IF v_create_oid IS NULL THEN
    RAISE EXCEPTION
      'GUARD G-0a failed: create_employee_secure(text,text,text,text,uuid,boolean) not found';
  END IF;

  SELECT to_regprocedure(
    'public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)'
  )::oid INTO v_update_oid;
  IF v_update_oid IS NULL THEN
    RAISE EXCEPTION
      'GUARD G-0b failed: update_employee_secure(text,uuid,text,text,boolean,uuid,text) not found';
  END IF;

  -- G-1: create_employee_secure baseline fingerprint
  SELECT md5(pg_get_functiondef(v_create_oid)),
         length(pg_get_functiondef(v_create_oid))
  INTO   v_md5, v_len;
  IF v_md5 <> 'de7f84d9f63970be1dc9d7741716047f' THEN
    RAISE EXCEPTION
      'GUARD G-1a failed: create_employee_secure md5 mismatch (got %, expected de7f84d9f63970be1dc9d7741716047f)',
      v_md5;
  END IF;
  IF v_len <> 1142 THEN
    RAISE EXCEPTION
      'GUARD G-1b failed: create_employee_secure length mismatch (got %, expected 1142)', v_len;
  END IF;

  -- G-2: update_employee_secure baseline fingerprint
  SELECT md5(pg_get_functiondef(v_update_oid)),
         length(pg_get_functiondef(v_update_oid))
  INTO   v_md5, v_len;
  IF v_md5 <> '0e5a7c3d9a0fe80230c643131edaa325' THEN
    RAISE EXCEPTION
      'GUARD G-2a failed: update_employee_secure md5 mismatch (got %, expected 0e5a7c3d9a0fe80230c643131edaa325)',
      v_md5;
  END IF;
  IF v_len <> 1492 THEN
    RAISE EXCEPTION
      'GUARD G-2b failed: update_employee_secure length mismatch (got %, expected 1492)', v_len;
  END IF;

  -- G-3: 両 RPC 属性（owner / SECURITY DEFINER / VOLATILE / search_path 完全一致）
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  WHERE  p.oid IN (v_create_oid, v_update_oid)
    AND  pg_get_userbyid(p.proowner) = 'postgres'
    AND  p.prosecdef   = true
    AND  p.provolatile = 'v'
    AND  p.proconfig   = ARRAY['search_path=public, extensions'];
  IF v_count <> 2 THEN
    RAISE EXCEPTION
      'GUARD G-3 failed: attribute mismatch on one or both RPCs '
      '(expected 2 matching, got %)', v_count;
  END IF;

  -- G-4: employees.pin が text NOT NULL
  SELECT count(*) INTO v_count
  FROM   pg_attribute a
  JOIN   pg_type t ON t.oid = a.atttypid
  WHERE  a.attrelid   = 'public.employees'::regclass
    AND  a.attname    = 'pin'
    AND  NOT a.attisdropped
    AND  t.typname    = 'text'
    AND  a.attnotnull = true;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'GUARD G-4 failed: employees.pin is not text NOT NULL';
  END IF;

  -- G-5a: employees.pin_hash が text NULL で存在する
  SELECT count(*) INTO v_count
  FROM   pg_attribute a
  JOIN   pg_type t ON t.oid = a.atttypid
  WHERE  a.attrelid   = 'public.employees'::regclass
    AND  a.attname    = 'pin_hash'
    AND  NOT a.attisdropped
    AND  t.typname    = 'text'
    AND  a.attnotnull = false;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'GUARD G-5a failed: employees.pin_hash is not text NULL or does not exist';
  END IF;

  -- G-5b: employees.pin_hash に default がない
  SELECT count(*) INTO v_count
  FROM   pg_attrdef ad
  JOIN   pg_attribute a ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
  WHERE  a.attrelid = 'public.employees'::regclass
    AND  a.attname  = 'pin_hash'
    AND  NOT a.attisdropped;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'GUARD G-5b failed: employees.pin_hash has an unexpected default';
  END IF;

  -- G-6a: employees total = 11
  SELECT count(*) INTO v_count FROM public.employees;
  IF v_count <> 11 THEN
    RAISE EXCEPTION
      'GUARD G-6a failed: employees total = % (expected 11). Re-run PRE-CHECK and update spec.',
      v_count;
  END IF;

  -- G-6b: pin_hash IS NOT NULL = 0（backfill 未実施確認）
  SELECT count(*) INTO v_count FROM public.employees WHERE pin_hash IS NOT NULL;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'GUARD G-6b failed: pin_hash IS NOT NULL = % (expected 0)', v_count;
  END IF;

  -- G-7: pgcrypto が extensions スキーマに存在する
  SELECT n.nspname INTO v_ext_schema
  FROM   pg_extension e
  JOIN   pg_namespace n ON n.oid = e.extnamespace
  WHERE  e.extname = 'pgcrypto';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'GUARD G-7 failed: pgcrypto extension not found';
  END IF;
  IF v_ext_schema <> 'extensions' THEN
    RAISE EXCEPTION
      'GUARD G-7 failed: pgcrypto schema is % (expected extensions)', v_ext_schema;
  END IF;

  -- G-8a: extensions.crypt(text,text) が存在する
  IF to_regprocedure(v_ext_schema || '.crypt(text,text)') IS NULL THEN
    RAISE EXCEPTION 'GUARD G-8a failed: extensions.crypt(text,text) not found';
  END IF;

  -- G-8b: extensions.gen_salt(text,integer) が存在する
  IF to_regprocedure(v_ext_schema || '.gen_salt(text,integer)') IS NULL THEN
    RAISE EXCEPTION 'GUARD G-8b failed: extensions.gen_salt(text,integer) not found';
  END IF;

  -- G-9: anon / authenticated の employees.pin / pin_hash 列権限 = 全 false
  IF has_column_privilege('anon',          'public.employees', 'pin',      'SELECT')
     OR has_column_privilege('authenticated', 'public.employees', 'pin',      'SELECT')
     OR has_column_privilege('anon',          'public.employees', 'pin',      'INSERT')
     OR has_column_privilege('authenticated', 'public.employees', 'pin',      'INSERT')
     OR has_column_privilege('anon',          'public.employees', 'pin',      'UPDATE')
     OR has_column_privilege('authenticated', 'public.employees', 'pin',      'UPDATE')
     OR has_column_privilege('anon',          'public.employees', 'pin',      'REFERENCES')
     OR has_column_privilege('authenticated', 'public.employees', 'pin',      'REFERENCES')
     OR has_column_privilege('anon',          'public.employees', 'pin_hash', 'SELECT')
     OR has_column_privilege('authenticated', 'public.employees', 'pin_hash', 'SELECT')
     OR has_column_privilege('anon',          'public.employees', 'pin_hash', 'INSERT')
     OR has_column_privilege('authenticated', 'public.employees', 'pin_hash', 'INSERT')
     OR has_column_privilege('anon',          'public.employees', 'pin_hash', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.employees', 'pin_hash', 'UPDATE')
     OR has_column_privilege('anon',          'public.employees', 'pin_hash', 'REFERENCES')
     OR has_column_privilege('authenticated', 'public.employees', 'pin_hash', 'REFERENCES') THEN
    RAISE EXCEPTION
      'GUARD G-9 failed: unexpected column privilege on employees.pin or pin_hash';
  END IF;

  -- G-10: EXECUTE 権限が anon / authenticated に存在する（維持確認）
  IF NOT has_function_privilege('anon', v_create_oid, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', v_create_oid, 'EXECUTE')
     OR NOT has_function_privilege('anon', v_update_oid, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', v_update_oid, 'EXECUTE') THEN
    RAISE EXCEPTION
      'GUARD G-10 failed: EXECUTE privilege missing on one or both RPCs for anon/authenticated';
  END IF;

  -- G-11: session 検証方式が admin_sessions（_verify_management_session を使っていない）
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  WHERE  p.oid IN (v_create_oid, v_update_oid)
    AND  p.prosrc ILIKE '%admin_sessions%'
    AND  p.prosrc NOT ILIKE '%_verify_management_session%';
  IF v_count <> 2 THEN
    RAISE EXCEPTION
      'GUARD G-11 failed: session verification baseline mismatch '
      '(expected both RPCs to use admin_sessions, got % matching)', v_count;
  END IF;

  RAISE NOTICE 'GUARD OK: all 11 checks passed. Proceeding with BODY.';
END;
$guard$;


-- ---- B-1. create_employee_secure：dual-write 化（Phase 5-D-2） ----
--   変更箇所：
--     - PIN バリデーション：length() <> 4 → !~ '^[0-9]{4}$'
--     - INSERT：pin_hash 列追加・extensions.crypt(cost 12) で同時保存
--   変更しない箇所：
--     - signature / DEFAULT / RETURNS / LANGUAGE / SECURITY DEFINER
--     - search_path / admin_sessions 検証 / name バリデーション / response

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
  -- セッション検証（admin_sessions・変更なし）
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- name バリデーション（変更なし）
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION 'Name is required';
  END IF;

  -- PIN バリデーション（Phase 5-D-2：半角数字4桁の正規表現に厳格化）
  IF pin_input IS NULL OR pin_input !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'PIN must be exactly 4 digits';
  END IF;

  -- INSERT：pin と pin_hash を単一文で原子的に保存（Phase 5-D-2 dual-write）
  -- hash 生成失敗時は INSERT 全体が失敗する（employee 作成も失敗）
  -- PIN 値・hash 値は response に含めない（RETURNING は id, name のみ）
  RETURN QUERY
  INSERT INTO public.employees (name, pin, pin_hash, role, company_id, is_active)
  VALUES (
    trim(name_input),
    pin_input,
    extensions.crypt(pin_input, extensions.gen_salt('bf', 12)),
    role_input,
    company_id_input,
    is_active_input
  )
  RETURNING employees.id, employees.name;
END;
$$;


-- ---- B-2. update_employee_secure：dual-write 化（Phase 5-D-2） ----
--   変更箇所：
--     - PIN バリデーション：length() <> 4 → !~ '^[0-9]{4}$'
--     - PIN 変更 UPDATE：pin_hash 列も同時更新
--   変更しない箇所：
--     - signature / DEFAULT / RETURNS / LANGUAGE / SECURITY DEFINER
--     - search_path / admin_sessions 検証 / name バリデーション
--     - PIN 未変更分岐（pin も pin_hash も触れない）

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
  -- セッション検証（admin_sessions・変更なし）
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- name バリデーション（変更なし）
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION 'Name is required';
  END IF;

  -- PIN バリデーション（Phase 5-D-2：半角数字4桁の正規表現に厳格化）
  -- new_pin_input IS NULL = PIN 未変更（バリデーションスキップ）
  IF new_pin_input IS NOT NULL
     AND new_pin_input !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'PIN must be exactly 4 digits';
  END IF;

  -- PIN 未変更（new_pin_input IS NULL）：name / role / is_active / company_id のみ更新
  -- pin も pin_hash も両方とも触れない（既存 pin_hash NULL 行を勝手に hash 化しない）
  IF new_pin_input IS NULL THEN
    UPDATE public.employees e
    SET    name       = trim(name_input),
           role       = role_input,
           is_active  = is_active_input,
           company_id = company_id_input
    WHERE  e.id = id_input;

  ELSE
  -- PIN 変更あり：pin と pin_hash を単一 UPDATE 文で原子的に更新（Phase 5-D-2 dual-write）
  -- 片方だけ更新される状態を作らない。新しい salt で再 hash（bcrypt cost 12）
    UPDATE public.employees e
    SET    name       = trim(name_input),
           role       = role_input,
           is_active  = is_active_input,
           company_id = company_id_input,
           pin        = new_pin_input,
           pin_hash   = extensions.crypt(new_pin_input, extensions.gen_salt('bf', 12))
    WHERE  e.id = id_input;
  END IF;
END;
$$;


-- ---- 内部 POST-CHECK（fail-closed：失敗 → abort → DB 無変更） ----
DO $postcheck$
DECLARE
  v_count          integer;
  v_text           text;
  v_norm           text;
  v_new_create_len integer;
  v_new_create_md5 text;
  v_new_update_len integer;
  v_new_update_md5 text;
  v_create_oid     oid;
  v_update_oid     oid;
  v_nochange_branch text;
BEGIN

  -- 新 OID 取得（CREATE OR REPLACE 後）
  SELECT to_regprocedure(
    'public.create_employee_secure(text,text,text,text,uuid,boolean)'
  )::oid INTO v_create_oid;
  IF v_create_oid IS NULL THEN
    RAISE EXCEPTION 'POST-CHECK failed: create_employee_secure OID not found after CREATE OR REPLACE';
  END IF;

  SELECT to_regprocedure(
    'public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)'
  )::oid INTO v_update_oid;
  IF v_update_oid IS NULL THEN
    RAISE EXCEPTION 'POST-CHECK failed: update_employee_secure OID not found after CREATE OR REPLACE';
  END IF;

  -- PC-1: 両 RPC 属性が維持されている（proconfig 完全一致）
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  WHERE  p.oid IN (v_create_oid, v_update_oid)
    AND  pg_get_userbyid(p.proowner) = 'postgres'
    AND  p.prosecdef   = true
    AND  p.provolatile = 'v'
    AND  p.proconfig   = ARRAY['search_path=public, extensions'];
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'PC-1 failed: attribute mismatch after CREATE OR REPLACE (got % of 2)', v_count;
  END IF;

  -- PC-2: create の RETURNS TABLE が維持されている
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  WHERE  p.oid = v_create_oid
    AND  p.proretset = true
    AND  pg_get_function_result(p.oid) ILIKE '%id uuid%name text%';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'PC-2 failed: create_employee_secure RETURNS TABLE changed';
  END IF;

  -- PC-3: update の RETURNS void が維持されている
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  WHERE  p.oid = v_update_oid
    AND  p.proretset = false
    AND  pg_get_function_result(p.oid) = 'void';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'PC-3 failed: update_employee_secure RETURNS changed';
  END IF;

  -- PC-4: create に pin_hash を含む INSERT が存在する
  SELECT p.prosrc INTO v_text FROM pg_proc p WHERE p.oid = v_create_oid;
  v_norm := regexp_replace(v_text, '\s+', ' ', 'g');
  IF v_norm NOT ILIKE '%INSERT INTO public.employees%pin_hash%VALUES%' THEN
    RAISE EXCEPTION 'PC-4 failed: create_employee_secure INSERT does not include pin_hash';
  END IF;

  -- PC-5: create に extensions.crypt / extensions.gen_salt / cost 12 / 4桁 regex が存在する
  IF v_text NOT ILIKE '%extensions.crypt%' THEN
    RAISE EXCEPTION 'PC-5a failed: create_employee_secure does not reference extensions.crypt';
  END IF;
  IF v_text NOT ILIKE '%extensions.gen_salt%' THEN
    RAISE EXCEPTION 'PC-5b failed: create_employee_secure does not reference extensions.gen_salt';
  END IF;
  IF v_text NOT ILIKE '%gen_salt(''bf'', 12)%' THEN
    RAISE EXCEPTION 'PC-5c failed: create_employee_secure does not use cost 12';
  END IF;
  IF v_text NOT ILIKE '%[0-9]{4}%' THEN
    RAISE EXCEPTION 'PC-5d failed: create_employee_secure does not use 4-digit regex';
  END IF;

  -- PC-6: create の admin_sessions 検証が維持・_verify_management_session は導入しない
  IF v_text NOT ILIKE '%admin_sessions%' THEN
    RAISE EXCEPTION 'PC-6a failed: create_employee_secure admin_sessions verification missing';
  END IF;
  IF v_text ILIKE '%_verify_management_session%' THEN
    RAISE EXCEPTION 'PC-6b failed: create_employee_secure introduced _verify_management_session (out of scope)';
  END IF;

  -- PC-7: update に pin と pin_hash の同時 UPDATE が存在する（PIN 変更分岐）
  SELECT p.prosrc INTO v_text FROM pg_proc p WHERE p.oid = v_update_oid;
  v_norm := regexp_replace(v_text, '\s+', ' ', 'g');
  IF v_norm NOT ILIKE '%pin_hash = extensions.crypt%' THEN
    RAISE EXCEPTION
      'PC-7 failed: update_employee_secure PIN-change path does not set pin_hash via extensions.crypt';
  END IF;
  IF v_norm NOT ILIKE '%pin = new_pin_input%' THEN
    RAISE EXCEPTION
      'PC-7b failed: update_employee_secure PIN-change path does not set pin';
  END IF;

  -- PC-8: update に PIN 未変更分岐が存在する（new_pin_input IS NULL）
  IF v_text NOT ILIKE '%new_pin_input IS NULL%' THEN
    RAISE EXCEPTION
      'PC-8 failed: update_employee_secure no-change branch (IS NULL) missing';
  END IF;

  -- PC-8b: PIN 未変更分岐（IS NULL 〜 ELSE 間）に pin / pin_hash / hash 生成が混入していない
  -- lower(v_norm) で大小文字を統一した上で、IS NULL THEN と最初の ELSE の間だけを切り出す
  -- split_part(..., 'if new_pin_input is null then', 2) → IS NULL 以降全体
  -- split_part(..., 'else', 1)                         → IS NULL 分岐内（最初の ELSE 手前まで）
  v_nochange_branch :=
    split_part(
      split_part(
        lower(v_norm),
        'if new_pin_input is null then',
        2
      ),
      'else',
      1
    );

  -- 抽出に失敗した場合（空文字列または NULL）は fail-closed で停止
  IF v_nochange_branch IS NULL OR v_nochange_branch = '' THEN
    RAISE EXCEPTION
      'PC-8b failed: could not extract IS NULL branch from update_employee_secure '
      '(structure mismatch -- abort to prevent unverified execution)';
  END IF;

  -- pin = ... が存在しないこと（word-boundary 正規表現・lower 適用済みのため大小文字不問）
  IF v_nochange_branch ~ '(^|[^a-z0-9_])pin[[:space:]]*=' THEN
    RAISE EXCEPTION
      'PC-8b failed: update no-change branch (IS NULL) contains pin assignment '
      '(must not touch pin or pin_hash in no-change path)';
  END IF;

  -- pin_hash = ... が存在しないこと
  IF v_nochange_branch ~ '(^|[^a-z0-9_])pin_hash[[:space:]]*=' THEN
    RAISE EXCEPTION
      'PC-8b failed: update no-change branch (IS NULL) contains pin_hash assignment '
      '(must not touch pin or pin_hash in no-change path)';
  END IF;

  -- crypt(...) / extensions.crypt(...) が存在しないこと
  -- スキーマ修飾の有無・`(`前の空白に依存しない正規表現（lower 適用済みのため大小文字不問）
  -- `.` は [^a-z0-9_] に一致するため extensions.crypt も未修飾 crypt も両方検出する
  IF v_nochange_branch ~ '(^|[^a-z0-9_])crypt[[:space:]]*\(' THEN
    RAISE EXCEPTION
      'PC-8b failed: update no-change branch (IS NULL) calls crypt '
      '(hash generation must not occur in no-change path)';
  END IF;

  -- gen_salt(...) / extensions.gen_salt(...) が存在しないこと
  IF v_nochange_branch ~ '(^|[^a-z0-9_])gen_salt[[:space:]]*\(' THEN
    RAISE EXCEPTION
      'PC-8b failed: update no-change branch (IS NULL) calls gen_salt '
      '(hash generation must not occur in no-change path)';
  END IF;

  -- PC-9: update の extensions.crypt / gen_salt / cost 12 / 4桁 regex が存在する
  IF v_text NOT ILIKE '%extensions.crypt%' THEN
    RAISE EXCEPTION 'PC-9a failed: update_employee_secure does not reference extensions.crypt';
  END IF;
  IF v_text NOT ILIKE '%gen_salt(''bf'', 12)%' THEN
    RAISE EXCEPTION 'PC-9b failed: update_employee_secure does not use cost 12';
  END IF;
  IF v_text NOT ILIKE '%[0-9]{4}%' THEN
    RAISE EXCEPTION 'PC-9c failed: update_employee_secure does not use 4-digit regex';
  END IF;

  -- PC-10: update の admin_sessions 検証が維持・_verify_management_session は導入しない
  IF v_text NOT ILIKE '%admin_sessions%' THEN
    RAISE EXCEPTION 'PC-10a failed: update_employee_secure admin_sessions verification missing';
  END IF;
  IF v_text ILIKE '%_verify_management_session%' THEN
    RAISE EXCEPTION 'PC-10b failed: update_employee_secure introduced _verify_management_session';
  END IF;

  -- PC-11: EXECUTE 権限が維持されている（CREATE OR REPLACE 後）
  IF NOT has_function_privilege('anon', v_create_oid, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', v_create_oid, 'EXECUTE')
     OR NOT has_function_privilege('anon', v_update_oid, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', v_update_oid, 'EXECUTE') THEN
    RAISE EXCEPTION
      'PC-11 failed: EXECUTE privilege lost after CREATE OR REPLACE';
  END IF;

  -- PC-12: 列権限に変化なし（pin / pin_hash）
  IF has_column_privilege('anon', 'public.employees', 'pin', 'SELECT')
     OR has_column_privilege('authenticated', 'public.employees', 'pin', 'SELECT')
     OR has_column_privilege('anon', 'public.employees', 'pin_hash', 'SELECT')
     OR has_column_privilege('authenticated', 'public.employees', 'pin_hash', 'SELECT') THEN
    RAISE EXCEPTION 'PC-12 failed: unexpected column privilege on employees.pin or pin_hash';
  END IF;

  -- PC-13: employees 件数・pin_hash 件数が BODY で変化していない（DML なしを確認）
  SELECT count(*) INTO v_count FROM public.employees;
  IF v_count <> 11 THEN
    RAISE EXCEPTION 'PC-13a failed: employees total changed (expected 11, got %)', v_count;
  END IF;
  SELECT count(*) INTO v_count FROM public.employees WHERE pin_hash IS NOT NULL;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'PC-13b failed: pin_hash IS NOT NULL = % (expected 0, no data changes in 5-D-2 BODY)', v_count;
  END IF;

  -- PC-14: 新 fingerprint を NOTICE 出力（★5-D-3 GUARD / ROLLBACK baseline として記録★）
  SELECT length(pg_get_functiondef(v_create_oid)),
         md5(pg_get_functiondef(v_create_oid))
  INTO   v_new_create_len, v_new_create_md5;

  SELECT length(pg_get_functiondef(v_update_oid)),
         md5(pg_get_functiondef(v_update_oid))
  INTO   v_new_update_len, v_new_update_md5;

  RAISE NOTICE
    '=== Phase 5-D-2 new fingerprints (record for ROLLBACK / 5-D-3 GUARD baseline) ==='
    ' create: len=% md5=%'
    ' update: len=% md5=%',
    v_new_create_len, v_new_create_md5,
    v_new_update_len, v_new_update_md5;

  RAISE NOTICE 'POST-CHECK all passed (PC-1 to PC-14). Ready to COMMIT.';
END;
$postcheck$;

COMMIT;


-- ============================================================
-- Part 3：POST-COMMIT（COMMIT 後に実行・read-only）
-- ★ P-1 の new fingerprints を必ず記録すること ★
-- ============================================================

WITH target_fn AS (
  SELECT 'create_employee_secure'::text AS fn_name,
         to_regprocedure('public.create_employee_secure(text,text,text,text,uuid,boolean)') AS fn_oid
  UNION ALL
  SELECT 'update_employee_secure'::text,
         to_regprocedure('public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)')
)

-- P-1: 新 fingerprint（★ROLLBACK / 5-D-3 GUARD baseline★）
SELECT fn_name::text                             AS function_name,
       p.oid::regprocedure::text                 AS signature,
       pg_get_userbyid(p.proowner)::text          AS owner,
       p.prosecdef::text                         AS security_definer,
       p.provolatile::text                       AS volatility,
       COALESCE(array_to_string(p.proconfig,', '),'(none)')::text AS proconfig,
       length(pg_get_functiondef(p.oid))::text   AS new_def_length,
       md5(pg_get_functiondef(p.oid))::text      AS new_def_md5
FROM   target_fn t
JOIN   pg_proc p ON p.oid = t.fn_oid::oid
WHERE  t.fn_oid IS NOT NULL
ORDER  BY fn_name;

-- P-2: employees 列定義（変化なし確認）
SELECT column_name, data_type, is_nullable,
       COALESCE(column_default, '(none)') AS col_default
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'employees'
  AND  column_name  IN ('pin', 'pin_hash')
ORDER  BY column_name;

-- P-3: employees 件数（BODY で変化なし確認）
SELECT count(*)                                     AS total_rows,
       count(*) FILTER (WHERE pin_hash IS NULL)     AS pin_hash_null,
       count(*) FILTER (WHERE pin_hash IS NOT NULL) AS pin_hash_not_null
FROM   public.employees;

-- P-4: prosrc 確認（dual-write / regex / session 方式）
WITH target_fn AS (
  SELECT 'create_employee_secure'::text AS fn_name,
         to_regprocedure('public.create_employee_secure(text,text,text,text,uuid,boolean)') AS fn_oid
  UNION ALL
  SELECT 'update_employee_secure'::text,
         to_regprocedure('public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)')
)
SELECT
  t.fn_name::text                                                                    AS fn_name,
  (p.prosrc ILIKE '%pin_hash%')::text                                               AS refs_pin_hash,
  (p.prosrc ILIKE '%extensions.crypt%')::text                                       AS refs_extensions_crypt,
  (p.prosrc ILIKE '%gen_salt(''bf'', 12)%')::text                                   AS has_cost_12,
  (p.prosrc ILIKE '%[0-9]{4}%')::text                                               AS has_4digit_regex,
  (p.prosrc ILIKE '%admin_sessions%')::text                                         AS uses_admin_sessions,
  (p.prosrc NOT ILIKE '%_verify_management_session%')::text                         AS no_verify_mgmt_session,
  (regexp_replace(p.prosrc, '\s+', ' ', 'g')
     ILIKE '%INSERT INTO public.employees%pin_hash%VALUES%')::text                  AS create_insert_has_pin_hash,
  (regexp_replace(p.prosrc, '\s+', ' ', 'g')
     ILIKE '%pin_hash = extensions.crypt%')::text                                   AS update_has_pin_hash_set,
  (regexp_replace(p.prosrc, '\s+', ' ', 'g')
     ILIKE '%new_pin_input IS NULL%')::text                                         AS update_has_no_change_branch
FROM   target_fn t
JOIN   pg_proc p ON p.oid = t.fn_oid::oid
WHERE  t.fn_oid IS NOT NULL
ORDER  BY t.fn_name;

-- P-5: 列権限（全 false 維持確認）
WITH target_fn AS (SELECT 1)
SELECT r.role::text, c.col::text, p.priv::text,
       has_column_privilege(r.role, 'public.employees', c.col, p.priv)::text AS has_priv
FROM   (VALUES ('anon'::text), ('authenticated'::text))                  r(role)
CROSS  JOIN (VALUES ('pin'::text), ('pin_hash'::text))                   c(col)
CROSS  JOIN (VALUES ('SELECT'::text), ('INSERT'::text),
                    ('UPDATE'::text), ('REFERENCES'::text))              p(priv)
ORDER  BY r.role, c.col, p.priv;

-- P-6: EXECUTE 権限（true 維持確認）
WITH target_fn AS (
  SELECT 'create_employee_secure'::text AS fn_name,
         to_regprocedure('public.create_employee_secure(text,text,text,text,uuid,boolean)') AS fn_oid
  UNION ALL
  SELECT 'update_employee_secure'::text,
         to_regprocedure('public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)')
)
SELECT r.role::text, p.oid::regprocedure::text AS sig,
       has_function_privilege(r.role, p.oid, 'EXECUTE')::text AS can_execute
FROM   (VALUES ('anon'::text), ('authenticated'::text))  r(role)
CROSS  JOIN (
  SELECT p.oid FROM target_fn t JOIN pg_proc p ON p.oid = t.fn_oid::oid WHERE t.fn_oid IS NOT NULL
) p
ORDER  BY r.role, sig;


-- ============================================================
-- Part 4：EMERGENCY ROLLBACK（★通常は実行しない★）
-- ============================================================
-- 【実行前準備（必須）】
--   Phase 5-D-2 Part 3 P-1 の new fingerprints を
--   下記プレースホルダーへ書き込む。
--   プレースホルダーが '<FILL_IN>' / 0 のまま実行すると ROLLBACK GUARD が停止する。
--
-- 【順序】function 復元 → 旧 fingerprint 一致確認 → 完了
--   employees.pin_hash は DROP しない（5-D-1 で追加済み）。
-- ============================================================

BEGIN;

DO $rb_guard$
DECLARE
  v_count          integer;
  v_md5            text;
  v_len            integer;
  v_create_oid     oid;
  v_update_oid     oid;
  v_new_create_md5 text    := '<FILL_IN_FROM_5D2_POST_COMMIT_create_md5>';
  v_new_create_len integer := 0;
  v_new_update_md5 text    := '<FILL_IN_FROM_5D2_POST_COMMIT_update_md5>';
  v_new_update_len integer := 0;
BEGIN

  -- ★ プレースホルダー未設定チェック（安全ロック）
  IF v_new_create_md5 = '<FILL_IN_FROM_5D2_POST_COMMIT_create_md5>' OR v_new_create_len = 0
     OR v_new_update_md5 = '<FILL_IN_FROM_5D2_POST_COMMIT_update_md5>' OR v_new_update_len = 0 THEN
    RAISE EXCEPTION
      'ROLLBACK GUARD: fill in all four placeholder values '
      'from Phase 5-D-2 Part 3 P-1 before executing rollback';
  END IF;

  -- G-R0: exact OID 取得
  SELECT to_regprocedure(
    'public.create_employee_secure(text,text,text,text,uuid,boolean)'
  )::oid INTO v_create_oid;
  SELECT to_regprocedure(
    'public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)'
  )::oid INTO v_update_oid;
  IF v_create_oid IS NULL OR v_update_oid IS NULL THEN
    RAISE EXCEPTION 'ROLLBACK GUARD G-R0 failed: one or both RPCs not found';
  END IF;

  -- G-R1: create fingerprint が 5-D-2 適用後の値と一致
  SELECT md5(pg_get_functiondef(v_create_oid)),
         length(pg_get_functiondef(v_create_oid))
  INTO   v_md5, v_len;
  IF v_md5 <> v_new_create_md5 OR v_len <> v_new_create_len THEN
    RAISE EXCEPTION
      'ROLLBACK GUARD G-R1 failed: create fingerprint mismatch '
      '(Phase 5-D-2 not applied or different version)';
  END IF;

  -- G-R2: update fingerprint が 5-D-2 適用後の値と一致
  SELECT md5(pg_get_functiondef(v_update_oid)),
         length(pg_get_functiondef(v_update_oid))
  INTO   v_md5, v_len;
  IF v_md5 <> v_new_update_md5 OR v_len <> v_new_update_len THEN
    RAISE EXCEPTION
      'ROLLBACK GUARD G-R2 failed: update fingerprint mismatch';
  END IF;

  -- G-R3: 両 RPC が pin_hash / extensions.crypt を参照している（5-D-2 適用済みの証拠）
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  WHERE  p.oid IN (v_create_oid, v_update_oid)
    AND  p.prosrc ILIKE '%pin_hash%'
    AND  p.prosrc ILIKE '%extensions.crypt%';
  IF v_count <> 2 THEN
    RAISE EXCEPTION
      'ROLLBACK GUARD G-R3 failed: RPCs do not reference pin_hash/extensions.crypt '
      '(Phase 5-D-2 not applied?)';
  END IF;

  RAISE NOTICE 'ROLLBACK GUARD OK: Phase 5-D-2 state confirmed. Proceeding with rollback.';
END;
$rb_guard$;


-- ---- ROLLBACK BODY: 両 RPC を 5-D-2 適用前 baseline へ復元 ----
-- ★ DROP FUNCTION 禁止。CREATE OR REPLACE のみ。★
-- ★ employees.pin_hash 列は DROP しない（5-D-1 で追加済み・5-D-1 ROLLBACK で処理）★

CREATE OR REPLACE FUNCTION public.create_employee_secure(session_token_input text, name_input text, pin_input text, role_input text, company_id_input uuid, is_active_input boolean DEFAULT true)
 RETURNS TABLE(id uuid, name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  -- Verify session token
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Validate inputs
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION 'Name is required';
  END IF;

  IF pin_input IS NULL OR length(pin_input) <> 4 THEN
    RAISE EXCEPTION 'PIN must be 4 digits';
  END IF;

  -- Insert new employee
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
$function$;


CREATE OR REPLACE FUNCTION public.update_employee_secure(session_token_input text, id_input uuid, name_input text, role_input text, is_active_input boolean, company_id_input uuid, new_pin_input text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  -- Verify session token
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE  s.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
      AND  s.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  -- Validate inputs
  IF name_input IS NULL OR trim(name_input) = '' THEN
    RAISE EXCEPTION 'Name is required';
  END IF;

  IF new_pin_input IS NOT NULL AND length(new_pin_input) <> 4 THEN
    RAISE EXCEPTION 'PIN must be 4 digits';
  END IF;

  -- Update without changing PIN
  IF new_pin_input IS NULL THEN
    UPDATE public.employees e
    SET    name       = trim(name_input),
           role       = role_input,
           is_active  = is_active_input,
           company_id = company_id_input
    WHERE  e.id = id_input;
  ELSE
  -- Update including PIN change
    UPDATE public.employees e
    SET    name       = trim(name_input),
           role       = role_input,
           is_active  = is_active_input,
           company_id = company_id_input,
           pin        = new_pin_input
    WHERE  e.id = id_input;
  END IF;
END;
$function$;


-- ---- ROLLBACK 内部確認（fail-closed） ----
DO $rb_check$
DECLARE
  v_md5   text;
  v_len   integer;
  v_count integer;
  v_text  text;
  v_create_oid oid;
  v_update_oid oid;
BEGIN

  SELECT to_regprocedure('public.create_employee_secure(text,text,text,text,uuid,boolean)')::oid
  INTO   v_create_oid;
  SELECT to_regprocedure('public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)')::oid
  INTO   v_update_oid;

  -- RC-1: create fingerprint が baseline（5-D-2 適用前）に戻った
  SELECT md5(pg_get_functiondef(v_create_oid)),
         length(pg_get_functiondef(v_create_oid))
  INTO   v_md5, v_len;
  IF v_md5 <> 'de7f84d9f63970be1dc9d7741716047f' THEN
    RAISE EXCEPTION
      'ROLLBACK RC-1a failed: create md5 after restore = % '
      '(expected de7f84d9f63970be1dc9d7741716047f). '
      'Use pg_get_functiondef to retrieve exact baseline.', v_md5;
  END IF;
  IF v_len <> 1142 THEN
    RAISE EXCEPTION
      'ROLLBACK RC-1b failed: create length after restore = % (expected 1142)', v_len;
  END IF;

  -- RC-2: update fingerprint が baseline に戻った
  SELECT md5(pg_get_functiondef(v_update_oid)),
         length(pg_get_functiondef(v_update_oid))
  INTO   v_md5, v_len;
  IF v_md5 <> '0e5a7c3d9a0fe80230c643131edaa325' THEN
    RAISE EXCEPTION
      'ROLLBACK RC-2a failed: update md5 after restore = %', v_md5;
  END IF;
  IF v_len <> 1492 THEN
    RAISE EXCEPTION
      'ROLLBACK RC-2b failed: update length after restore = % (expected 1492)', v_len;
  END IF;

  -- RC-3: pin_hash 参照と extensions.crypt が消えた（baseline に戻った証拠）
  SELECT p.prosrc INTO v_text FROM pg_proc p WHERE p.oid = v_create_oid;
  IF v_text ILIKE '%pin_hash%' THEN
    RAISE EXCEPTION
      'ROLLBACK RC-3a failed: create still references pin_hash. Abort.';
  END IF;
  IF v_text ILIKE '%extensions.crypt%' THEN
    RAISE EXCEPTION
      'ROLLBACK RC-3b failed: create still references extensions.crypt. Abort.';
  END IF;

  SELECT p.prosrc INTO v_text FROM pg_proc p WHERE p.oid = v_update_oid;
  IF v_text ILIKE '%pin_hash%' THEN
    RAISE EXCEPTION
      'ROLLBACK RC-3c failed: update still references pin_hash. Abort.';
  END IF;
  IF v_text ILIKE '%extensions.crypt%' THEN
    RAISE EXCEPTION
      'ROLLBACK RC-3d failed: update still references extensions.crypt. Abort.';
  END IF;

  -- RC-4: EXECUTE 権限が維持されている
  IF NOT has_function_privilege('anon', v_create_oid, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', v_create_oid, 'EXECUTE')
     OR NOT has_function_privilege('anon', v_update_oid, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', v_update_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'ROLLBACK RC-4 failed: EXECUTE privilege lost after rollback';
  END IF;

  RAISE NOTICE
    'ROLLBACK complete: both RPCs restored to baseline '
    '(create md5=de7f84d9f63970be1dc9d7741716047f / update md5=0e5a7c3d9a0fe80230c643131edaa325).';
END;
$rb_check$;

COMMIT;


-- ============================================================
-- Part 5：DB 実行後 smoke 計画（★DB 実行承認後にユーザーが実施★）
-- ★ 実 PIN 値・hash 値・氏名・UUID は記録しない ★
-- ★ create 経路の本番 smoke は安全なcleanup 方法が確立された場合のみ実施 ★
-- ============================================================
--
-- S-1. 既存従業員の「名前のみ変更」編集（PIN 未変更）
--   操作：/admin 管理画面で既存従業員の名前を変更して保存（PIN 欄は空のまま）
--   確認：DB で pin_hash IS NULL 件数が変わらない（POST-COMMIT P-3 の再実行で確認）
--   目的：update の PIN 未変更分岐が pin_hash を触れていないことを確認
--
-- S-2. 既存従業員の「PIN 変更」編集
--   操作：同じ管理画面で既存従業員の PIN を新しい4桁数字に変更して保存
--   確認：DB で pin_hash IS NOT NULL 件数が 1 増えること（POST-COMMIT P-3 の再実行）
--   目的：update の PIN 変更分岐が pin_hash を正しく生成・保存することを確認
--
-- S-3. 新 PIN でのログイン確認
--   操作：S-2 で PIN を変更した従業員でログイン（index.html）
--   確認：ログイン成功（セッション発行）
--   目的：dual-read と dual-write が整合していることを確認
--
-- S-4. 旧 PIN でのログイン拒否確認
--   操作：S-2 以前の PIN でログイン試行
--   確認：ログイン拒否
--   目的：旧 PIN が無効化されていることを確認
--
-- S-5. 管理者 / 原価管理ログイン回帰確認
--   操作：/admin・/genka でそれぞれ管理者ログイン
--   確認：正常ログイン
--   目的：genka_admins / create_admin_session への影響なし
--
-- S-6. create 経路の確認方針
--   本番 smoke は実施しない（cleanup RPC が未整備のため）。
--   代替確認方法：
--     a. POST-CHECK PC-4 のパターン確認（dual-write コードが存在する）
--     b. Part 3 P-4 の prosrc 確認（create_insert_has_pin_hash=true）
--     c. コードレビュー（Part B full definition による目視確認）
--   create 経路のデータ検証は、安全な cleanup 方法（例：DELETE RPC の整備）が
--   確立された後の次工程（5-D-3 backfill 時など）で実施する。
--
-- S-7. 4桁数字以外の PIN 入力拒否確認（任意）
--   操作：PIN 欄に「1234abc」などを入力して保存試行
--   確認：'PIN must be exactly 4 digits' エラーが表示される
--   目的：PIN バリデーション強化の動作確認
-- ============================================================


-- ============================================================
-- Part 6：実行記録（DB 実行後に記入）
-- ============================================================
-- execution date        ：未定
-- executed by           ：（Supabase SQL Editor・手動）
-- GUARD result          ：未実行
-- BODY result           ：未実行
-- POST-CHECK result     ：未実行
-- new_create_def_length ：<FILL_IN_FROM_5D2_POST_COMMIT_create_length>
-- new_create_def_md5    ：<FILL_IN_FROM_5D2_POST_COMMIT_create_md5>
-- new_update_def_length ：<FILL_IN_FROM_5D2_POST_COMMIT_update_length>
-- new_update_def_md5    ：<FILL_IN_FROM_5D2_POST_COMMIT_update_md5>
-- smoke result          ：未実施
-- docs/db-migrations.md 記録日：未定
-- ============================================================
