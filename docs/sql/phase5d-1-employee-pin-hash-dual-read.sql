-- ============================================================
-- Phase 5-D-1：employees.pin_hash 追加 + 従業員 login RPC hash 優先 dual-read 化
-- ============================================================
-- 【実行ステータス】STATUS: PENDING（★DB 未実行★）
--   - preparation date：2026-07-22（準備 PR #164）
--   - execution date  ：未定（3者合意・smoke 確認後に Supabase SQL Editor で手動実行）
--   - ★ BODY は1回のみ実行。再実行禁止★
--     （GUARD G-4 が pin_hash 既存を検知・GUARD G-2 が md5 不一致を検知して停止）
--
-- 【目的】
--   employees テーブルに pin_hash 列を追加し、
--   create_employee_session RPC の PIN 照合を hash 優先 dual-read に更新する。
--   - pin_hash IS NOT NULL → extensions.crypt による bcrypt 照合のみ（平文 fallback なし）
--   - pin_hash IS NULL     → 既存の平文 pin 照合（移行前互換）
--
-- 【対象 DB オブジェクト】
--   - public.employees（pin_hash text NULL 列追加）
--   - public.create_employee_session(uuid,text)（CREATE OR REPLACE）
--
-- 【非対象（今回変更しない）】
--   - genka_admins / create_admin_session（Phase 5-E で対応）
--   - employee create/update RPC（5-D-2 dual-write で対応）
--   - frontend（変更不要・PIN は plain text で RPC 渡し）
--   - RLS / policy / GRANT / REVOKE
--   - backfill（5-D-3 で対応）
--   - hash 生成・bcrypt cost 決定（backfill 時に確定）
--
-- 【baseline（実 DB 2026-07-22 確認済み）】
--   create_employee_session(uuid,text):
--     owner=postgres / SECURITY DEFINER / VOLATILE
--     proconfig=search_path=public, extensions
--     definition length=3520
--     definition md5=af51db14986a5617de3091086a94db64
--   employees: total=11 / active=11 / inactive=0 / pin NULL=0
--   pgcrypto: version=1.3 / schema=extensions
--     extensions.crypt(text,text): 存在
--     extensions.gen_salt(text,integer): 存在
--
-- 【実行方法（重要）】
--   実行先：Supabase SQL Editor（手動実行のみ）
--   Supabase CLI / psql では実行しない。
--   手順：
--     1. Part 1 PRE-CHECK を実行 → 全行が期待値と一致することを確認
--     2. ChatGPT 承認後、Part 2 BODY の BEGIN~COMMIT を1回だけ実行
--     3. NOTICE「GUARD OK」「POST-CHECK all passed」「new_def_length / new_def_md5」を確認・記録
--     4. Part 3 POST-COMMIT を実行 → 結果を ChatGPT へ貼り戻す
--     5. ROLLBACK SQL の <FILL_IN> プレースホルダーに Part 3 P-1 の値を記入して保存
--
-- 【STOP 条件（PRE-CHECK・GUARD いずれかが不一致なら停止・報告）】
--   - baseline fingerprint（md5/length）不一致
--   - pin_hash が既に存在（再実行・先行実行）
--   - employees.pin が text NOT NULL でない
--   - pgcrypto が extensions スキーマにない / crypt(text,text) が存在しない
--   - PIN 異常件数 > 0
--   - anon/authenticated に employees.pin 実効権限あり
-- ============================================================


-- ============================================================
-- Part 1：PRE-CHECK（read-only・1本・実行後に全行が期待値と一致することを確認）
-- 非出力：PIN値・hash値・氏名・UUID・token・secret
-- ============================================================

WITH

fn AS (
  SELECT p.oid::regprocedure::text                                    AS signature,
         pg_get_userbyid(p.proowner)                                   AS owner,
         p.prosecdef                                                    AS secdef,
         p.provolatile                                                  AS volatility,
         COALESCE(array_to_string(p.proconfig, ', '), '(none)')         AS proconfig,
         length(pg_get_functiondef(p.oid))                              AS def_len,
         md5(pg_get_functiondef(p.oid))                                 AS def_md5
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure
),

col AS (
  SELECT column_name,
         data_type,
         is_nullable,
         COALESCE(column_default, '(none)') AS col_default
  FROM   information_schema.columns
  WHERE  table_schema = 'public'
    AND  table_name   = 'employees'
    AND  column_name  IN ('pin', 'pin_hash')
),

ext AS (
  SELECT e.extname,
         e.extversion,
         n.nspname AS ext_schema,
         to_regprocedure(n.nspname || '.crypt(text,text)')        IS NOT NULL AS crypt_exact,
         to_regprocedure(n.nspname || '.gen_salt(text,integer)')  IS NOT NULL AS gen_salt_exact
  FROM   pg_extension e
  JOIN   pg_namespace n ON n.oid = e.extnamespace
  WHERE  e.extname = 'pgcrypto'
),

emp_stats AS (
  SELECT
    count(*)                                                             AS total,
    count(*) FILTER (WHERE is_active = true)                            AS active_cnt,
    count(*) FILTER (WHERE is_active = false)                           AS inactive_cnt,
    count(*) FILTER (WHERE pin IS NULL)                                 AS pin_null_cnt,
    count(*) FILTER (WHERE pin IS NOT NULL AND pin !~ '^[0-9]{4}$')     AS pin_non4digit_cnt
  FROM public.employees
),

dup AS (
  SELECT count(*) AS dup_groups, COALESCE(sum(c), 0) AS dup_rows
  FROM (
    SELECT count(*) AS c
    FROM   public.employees
    WHERE  pin IS NOT NULL
    GROUP  BY pin
    HAVING count(*) > 1
  ) d
),

prv AS (
  SELECT r.role, p.priv,
         has_column_privilege(r.role, 'public.employees', 'pin', p.priv) AS has_priv
  FROM   (VALUES ('anon'), ('authenticated'))                             r(role)
  CROSS  JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('REFERENCES'))    p(priv)
)

SELECT 'C1_fn_fp'    AS section, 'signature'   AS key, signature    AS value FROM fn
UNION ALL SELECT 'C1_fn_fp', 'owner',       owner                   FROM fn
UNION ALL SELECT 'C1_fn_fp', 'secdef',      secdef::text            FROM fn
UNION ALL SELECT 'C1_fn_fp', 'volatility',  volatility              FROM fn
UNION ALL SELECT 'C1_fn_fp', 'proconfig',   proconfig               FROM fn
UNION ALL SELECT 'C1_fn_fp', 'def_length',  def_len::text           FROM fn
UNION ALL SELECT 'C1_fn_fp', 'def_md5',     def_md5                 FROM fn
UNION ALL SELECT 'C1_fn_fp', 'baseline_match_(md5_and_length)',
       (def_md5 = 'af51db14986a5617de3091086a94db64' AND def_len = 3520)::text FROM fn

UNION ALL
SELECT 'C2_col_schema', column_name,
       'type=' || data_type || ' | nullable=' || is_nullable || ' | default=' || col_default
FROM   col
UNION ALL
SELECT 'C2_col_schema', 'pin_hash_absent',
       (NOT EXISTS (SELECT 1 FROM col WHERE column_name = 'pin_hash'))::text

UNION ALL
SELECT 'C3_pgcrypto', 'installed',
       (count(*) > 0)::text FROM pg_extension WHERE extname = 'pgcrypto'
UNION ALL SELECT 'C3_pgcrypto', 'extname',              extname              FROM ext
UNION ALL SELECT 'C3_pgcrypto', 'extversion',           extversion           FROM ext
UNION ALL SELECT 'C3_pgcrypto', 'schema',               ext_schema           FROM ext
UNION ALL SELECT 'C3_pgcrypto', 'crypt(text,text)_exact',    crypt_exact::text    FROM ext
UNION ALL SELECT 'C3_pgcrypto', 'gen_salt(text,integer)_exact', gen_salt_exact::text FROM ext

UNION ALL SELECT 'C4_emp_stats', 'total',              total::text            FROM emp_stats
UNION ALL SELECT 'C4_emp_stats', 'active',             active_cnt::text       FROM emp_stats
UNION ALL SELECT 'C4_emp_stats', 'inactive',           inactive_cnt::text     FROM emp_stats
UNION ALL SELECT 'C4_emp_stats', 'pin_null',           pin_null_cnt::text     FROM emp_stats
UNION ALL SELECT 'C4_emp_stats', 'pin_non4digit',      pin_non4digit_cnt::text FROM emp_stats
UNION ALL SELECT 'C4_emp_stats', 'dup_pin_groups_(pin_not_null)', dup_groups::text FROM dup
UNION ALL SELECT 'C4_emp_stats', 'dup_pin_rows_(pin_not_null)',   dup_rows::text   FROM dup

UNION ALL
SELECT 'C5_col_privs', role || '.pin.' || priv, has_priv::text FROM prv

ORDER BY 1, 2;

/*
  PRE-CHECK 期待値
  -----------------------------------------------------------------------
  C1_fn_fp  baseline_match_(md5_and_length) : true
  C1_fn_fp  def_length                      : 3520
  C1_fn_fp  def_md5                         : af51db14986a5617de3091086a94db64
  C1_fn_fp  owner                           : postgres
  C1_fn_fp  proconfig                       : search_path=public, extensions
  C1_fn_fp  secdef                          : true
  C1_fn_fp  volatility                      : v
  C2_col_schema  pin                        : type=text | nullable=NO | default=(none)
  C2_col_schema  pin_hash_absent            : true
  C3_pgcrypto  crypt(text,text)_exact       : true
  C3_pgcrypto  gen_salt(text,integer)_exact : true
  C3_pgcrypto  installed                    : true
  C3_pgcrypto  schema                       : extensions
  C4_emp_stats  active                      : 11
  C4_emp_stats  dup_pin_groups              : 0
  C4_emp_stats  dup_pin_rows               : 0
  C4_emp_stats  inactive                   : 0
  C4_emp_stats  pin_non4digit              : 0
  C4_emp_stats  pin_null                   : 0
  C4_emp_stats  total                      : 11
  C5_col_privs  anon.pin.*  / authenticated.pin.*  : すべて false
  -----------------------------------------------------------------------
*/


-- ============================================================
-- Part 2：BODY（★Part 1 全合格・ChatGPT 承認後に1回のみ実行★）
--   BEGIN ~ COMMIT を丸ごと選択して実行する。再実行禁止。
--   GUARD または内部 POST-CHECK 失敗 → 自動 abort → DB 無変更。
-- ============================================================

BEGIN;

-- ---- GUARD（fail-closed：1件でも不一致なら RAISE EXCEPTION で abort） ----
DO $guard$
DECLARE
  v_count      integer;
  v_md5        text;
  v_len        integer;
  v_ext_schema text;
BEGIN

  -- G-1: function 属性（proconfig は完全一致）
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure
    AND  pg_get_userbyid(p.proowner) = 'postgres'
    AND  p.prosecdef   = true
    AND  p.provolatile = 'v'
    AND  p.proconfig   = ARRAY['search_path=public, extensions'];
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'GUARD G-1 failed: attribute mismatch '
      '(expected owner=postgres / SECURITY DEFINER / VOLATILE / '
      'proconfig = ARRAY[search_path=public, extensions] exactly)';
  END IF;

  -- G-2: definition fingerprint（md5 + length が baseline と完全一致）
  SELECT md5(pg_get_functiondef(p.oid)),
         length(pg_get_functiondef(p.oid))
  INTO   v_md5, v_len
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure;

  IF v_md5 <> 'af51db14986a5617de3091086a94db64' THEN
    RAISE EXCEPTION
      'GUARD G-2 failed: md5 mismatch (got %, expected af51db14986a5617de3091086a94db64)',
      v_md5;
  END IF;
  IF v_len <> 3520 THEN
    RAISE EXCEPTION
      'GUARD G-2 failed: length mismatch (got %, expected 3520)', v_len;
  END IF;

  -- G-3: employees.pin が text NOT NULL で存在する
  SELECT count(*) INTO v_count
  FROM   pg_attribute a
  JOIN   pg_type t ON t.oid = a.atttypid
  WHERE  a.attrelid   = 'public.employees'::regclass
    AND  a.attname    = 'pin'
    AND  NOT a.attisdropped
    AND  t.typname    = 'text'
    AND  a.attnotnull = true;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'GUARD G-3 failed: employees.pin is not text NOT NULL (or does not exist)';
  END IF;

  -- G-4: employees.pin_hash が存在しない（二重適用防止）
  SELECT count(*) INTO v_count
  FROM   pg_attribute
  WHERE  attrelid = 'public.employees'::regclass
    AND  attname  = 'pin_hash'
    AND  NOT attisdropped;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'GUARD G-4 failed: employees.pin_hash already exists (already applied?)';
  END IF;

  -- G-5: pgcrypto が extensions スキーマに存在する
  SELECT n.nspname INTO v_ext_schema
  FROM   pg_extension e
  JOIN   pg_namespace n ON n.oid = e.extnamespace
  WHERE  e.extname = 'pgcrypto';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'GUARD G-5 failed: pgcrypto extension not found';
  END IF;
  IF v_ext_schema <> 'extensions' THEN
    RAISE EXCEPTION
      'GUARD G-5 failed: pgcrypto schema is % (expected extensions)', v_ext_schema;
  END IF;

  -- G-6a: extensions.crypt(text,text) が存在する（to_regprocedure で exact）
  IF to_regprocedure(v_ext_schema || '.crypt(text,text)') IS NULL THEN
    RAISE EXCEPTION
      'GUARD G-6a failed: crypt(text,text) not found in pgcrypto schema (%)', v_ext_schema;
  END IF;

  -- G-6b: extensions.gen_salt(text,integer) が存在する
  IF to_regprocedure(v_ext_schema || '.gen_salt(text,integer)') IS NULL THEN
    RAISE EXCEPTION
      'GUARD G-6b failed: gen_salt(text,integer) not found in pgcrypto schema (%)', v_ext_schema;
  END IF;

  -- G-7: employees の PIN 異常件数 = 0
  SELECT count(*) INTO v_count
  FROM   public.employees
  WHERE  pin IS NOT NULL AND pin !~ '^[0-9]{4}$';
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'GUARD G-7 failed: % employees have non-4-digit pin values', v_count;
  END IF;

  -- G-8: anon / authenticated の employees.pin 実効権限が全 false（4権限）
  IF has_column_privilege('anon',          'public.employees', 'pin', 'SELECT')
     OR has_column_privilege('authenticated', 'public.employees', 'pin', 'SELECT')
     OR has_column_privilege('anon',          'public.employees', 'pin', 'INSERT')
     OR has_column_privilege('authenticated', 'public.employees', 'pin', 'INSERT')
     OR has_column_privilege('anon',          'public.employees', 'pin', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.employees', 'pin', 'UPDATE')
     OR has_column_privilege('anon',          'public.employees', 'pin', 'REFERENCES')
     OR has_column_privilege('authenticated', 'public.employees', 'pin', 'REFERENCES') THEN
    RAISE EXCEPTION
      'GUARD G-8 failed: anon or authenticated has unexpected privilege on employees.pin';
  END IF;

  RAISE NOTICE 'GUARD OK: all 8 checks passed. Proceeding with BODY.';
END;
$guard$;


-- ---- B-1. pin_hash 列追加（nullable・default なし・hash 生成なし） ----
ALTER TABLE public.employees
  ADD COLUMN pin_hash text NULL;


-- ---- B-2. create_employee_session を hash 優先 dual-read へ更新 ----
--   変更箇所：step (6) の PIN 照合条件のみ（extensions.crypt でスキーマ修飾）
--   他はすべて Phase 5-C-1b 定義と同一。
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

  -- (6) PIN + is_active 照合（hash 優先 dual-read）
  -- pin_hash IS NOT NULL → bcrypt 照合（平文へ fallback しない）
  -- pin_hash IS NULL     → 平文 pin 照合（移行前互換）
  SELECT *
  INTO   v_emp
  FROM   public.employees e
  WHERE  e.id        = employee_id_input
    AND  CASE
           WHEN e.pin_hash IS NOT NULL THEN
             extensions.crypt(pin_input, e.pin_hash) = e.pin_hash
           ELSE
             e.pin = pin_input
         END
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


-- ---- 内部 POST-CHECK（fail-closed：失敗 → abort → DB 無変更） ----
DO $postcheck$
DECLARE
  v_count         integer;
  v_total         integer;
  v_hash_null     integer;
  v_hash_not_null integer;
  v_text          text;
  v_norm          text;
  v_new_len       integer;
  v_new_md5       text;
  v_pattern       text;
  v_required      text[];
  v_thr_oid       oid;
BEGIN

  -- PC-1: pin_hash が text NULL で追加された（pg_attribute）
  SELECT count(*) INTO v_count
  FROM   pg_attribute a
  JOIN   pg_type t ON t.oid = a.atttypid
  WHERE  a.attrelid   = 'public.employees'::regclass
    AND  a.attname    = 'pin_hash'
    AND  NOT a.attisdropped
    AND  t.typname    = 'text'
    AND  a.attnotnull = false;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'PC-1 failed: pin_hash not added as text NULL (pg_attribute)';
  END IF;

  -- PC-2: pin_hash に default がない（pg_attrdef）
  SELECT count(*) INTO v_count
  FROM   pg_attrdef ad
  JOIN   pg_attribute a ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
  WHERE  a.attrelid = 'public.employees'::regclass
    AND  a.attname  = 'pin_hash'
    AND  NOT a.attisdropped;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'PC-2 failed: pin_hash has an unexpected column default (pg_attrdef)';
  END IF;

  -- PC-3: 件数確認（total=11 / pin_hash IS NULL=11 / IS NOT NULL=0）
  SELECT count(*),
         count(*) FILTER (WHERE pin_hash IS NULL),
         count(*) FILTER (WHERE pin_hash IS NOT NULL)
  INTO   v_total, v_hash_null, v_hash_not_null
  FROM   public.employees;

  IF v_total <> 11 THEN
    RAISE EXCEPTION
      'PC-3 failed: total = % (expected 11). Re-run PRE-CHECK and update spec.', v_total;
  END IF;
  IF v_hash_null <> 11 THEN
    RAISE EXCEPTION
      'PC-3 failed: pin_hash IS NULL count = % (expected 11)', v_hash_null;
  END IF;
  IF v_hash_not_null <> 0 THEN
    RAISE EXCEPTION
      'PC-3 failed: pin_hash IS NOT NULL count = % (expected 0)', v_hash_not_null;
  END IF;

  -- PC-4: employees.pin が引き続き text NOT NULL
  SELECT count(*) INTO v_count
  FROM   pg_attribute a
  JOIN   pg_type t ON t.oid = a.atttypid
  WHERE  a.attrelid   = 'public.employees'::regclass
    AND  a.attname    = 'pin'
    AND  NOT a.attisdropped
    AND  t.typname    = 'text'
    AND  a.attnotnull = true;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'PC-4 failed: employees.pin is no longer text NOT NULL';
  END IF;

  -- PC-5: function 属性（proconfig 完全一致）
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure
    AND  pg_get_userbyid(p.proowner) = 'postgres'
    AND  p.prosecdef   = true
    AND  p.provolatile = 'v'
    AND  p.proconfig   = ARRAY['search_path=public, extensions'];
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'PC-5 failed: create_employee_session attribute mismatch after CREATE OR REPLACE';
  END IF;

  -- PC-6: RETURNS TABLE の列構成が維持されている
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure
    AND  p.proretset = true
    AND  pg_get_function_result(p.oid) ILIKE
           '%id uuid%name text%role text%is_active boolean%'
           '%company_id uuid%can_genka boolean%can_admin boolean%session_token text%';
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'PC-6 failed: RETURNS TABLE definition changed or missing expected columns';
  END IF;

  -- PC-7〜PC-11: prosrc を取得して文字列チェック
  SELECT p.prosrc INTO v_text
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure;

  -- PC-7: pin_hash 参照あり
  IF v_text NOT ILIKE '%pin_hash%' THEN
    RAISE EXCEPTION 'PC-7 failed: function does not reference pin_hash';
  END IF;

  -- PC-8: extensions.crypt 参照あり（スキーマ修飾で確認）
  IF v_text NOT ILIKE '%extensions.crypt%' THEN
    RAISE EXCEPTION
      'PC-8 failed: function does not reference extensions.crypt (schema-qualified required)';
  END IF;

  -- PC-9: hash 優先 CASE パターンが存在する（whitespace 正規化後に比較）
  v_norm := regexp_replace(v_text, '\s+', ' ', 'g');
  IF v_norm NOT ILIKE
       '%WHEN e.pin_hash IS NOT NULL THEN%'
       'extensions.crypt(pin_input, e.pin_hash) = e.pin_hash%'
       'ELSE%e.pin = pin_input%END%' THEN
    RAISE EXCEPTION
      'PC-9 failed: hash-first CASE pattern not found '
      '(WHEN e.pin_hash IS NOT NULL THEN extensions.crypt(...) ELSE e.pin = pin_input END)';
  END IF;

  -- PC-10: OR ベースの平文 fallback が存在しない
  IF v_norm ILIKE '%e.pin = pin_input OR%'
     OR v_norm ILIKE '%OR e.pin = pin_input%' THEN
    RAISE EXCEPTION
      'PC-10 failed: OR-based PIN fallback detected (must use hash-first CASE)';
  END IF;

  -- PC-11: throttle / session ロジック文字列（13文字列）がすべて存在する
  v_required := ARRAY[
    '%FOR KEY SHARE%',
    '%private.login_throttle%',
    '%FOR UPDATE%',
    '%clock_timestamp()%',
    '%15 minutes%',
    '%60 seconds%',
    '%>= 5%',
    '%DELETE FROM private.login_throttle%',
    '%employee_sessions%',
    '%gen_random_bytes%',
    '%digest%',
    '%sha256%',
    '%8 hours%'
  ];
  FOREACH v_pattern IN ARRAY v_required LOOP
    IF v_text NOT ILIKE v_pattern THEN
      RAISE EXCEPTION
        'PC-11 failed: required string % not found in function body', v_pattern;
    END IF;
  END LOOP;

  -- PC-12: pin / pin_hash 列権限（anon/authenticated × 4権限 = 16確認）
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
      'PC-12 failed: anon or authenticated has unexpected privilege on employees.pin or pin_hash';
  END IF;

  -- PC-thr-1: private.login_throttle が存在する
  SELECT count(*) INTO v_count
  FROM   pg_class c
  JOIN   pg_namespace n ON n.oid = c.relnamespace
  WHERE  n.nspname = 'private' AND c.relname = 'login_throttle';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'PC-thr-1 failed: private.login_throttle does not exist';
  END IF;

  SELECT c.oid INTO v_thr_oid
  FROM   pg_class c
  JOIN   pg_namespace n ON n.oid = c.relnamespace
  WHERE  n.nspname = 'private' AND c.relname = 'login_throttle';

  -- PC-thr-2: anon / authenticated の private schema USAGE = false
  IF COALESCE(
       has_schema_privilege('anon',
         (SELECT oid FROM pg_namespace WHERE nspname = 'private'), 'USAGE'),
       false)
     OR COALESCE(
       has_schema_privilege('authenticated',
         (SELECT oid FROM pg_namespace WHERE nspname = 'private'), 'USAGE'),
       false) THEN
    RAISE EXCEPTION
      'PC-thr-2 failed: anon or authenticated has USAGE on private schema';
  END IF;

  -- PC-thr-3: login_throttle 権限（7権限 × 2ロール = 14確認）
  IF has_table_privilege('anon',          v_thr_oid, 'SELECT')
     OR has_table_privilege('anon',          v_thr_oid, 'INSERT')
     OR has_table_privilege('anon',          v_thr_oid, 'UPDATE')
     OR has_table_privilege('anon',          v_thr_oid, 'DELETE')
     OR has_table_privilege('anon',          v_thr_oid, 'TRUNCATE')
     OR has_table_privilege('anon',          v_thr_oid, 'REFERENCES')
     OR has_table_privilege('anon',          v_thr_oid, 'TRIGGER')
     OR has_table_privilege('authenticated', v_thr_oid, 'SELECT')
     OR has_table_privilege('authenticated', v_thr_oid, 'INSERT')
     OR has_table_privilege('authenticated', v_thr_oid, 'UPDATE')
     OR has_table_privilege('authenticated', v_thr_oid, 'DELETE')
     OR has_table_privilege('authenticated', v_thr_oid, 'TRUNCATE')
     OR has_table_privilege('authenticated', v_thr_oid, 'REFERENCES')
     OR has_table_privilege('authenticated', v_thr_oid, 'TRIGGER') THEN
    RAISE EXCEPTION
      'PC-thr-3 failed: anon or authenticated has unexpected privilege on private.login_throttle';
  END IF;

  -- PC-13: 新 function fingerprint を NOTICE 出力（★5-D-2 GUARD / ROLLBACK baseline★）
  SELECT length(pg_get_functiondef(p.oid)),
         md5(pg_get_functiondef(p.oid))
  INTO   v_new_len, v_new_md5
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure;

  RAISE NOTICE
    '=== Phase 5-D-1 new function fingerprint ==='
    ' new_def_length=% / new_def_md5=%'
    ' ★ ROLLBACK GUARD v_new_len / v_new_md5 へ記入・5-D-2 GUARD baseline として記録 ★',
    v_new_len, v_new_md5;

  RAISE NOTICE 'POST-CHECK all passed (PC-1 to PC-thr-3). Ready to COMMIT.';
END;
$postcheck$;

COMMIT;


-- ============================================================
-- Part 3：POST-COMMIT（COMMIT 後に実行・read-only）
-- P-1 の new_def_md5 / new_def_length を必ず記録すること。
-- ============================================================

-- P-1: 新 function fingerprint（★ROLLBACK / 5-D-2 GUARD baseline★）
SELECT p.oid::regprocedure::text                                     AS signature,
       pg_get_userbyid(p.proowner)                                    AS owner,
       p.prosecdef                                                    AS security_definer,
       p.provolatile                                                  AS volatility,
       COALESCE(array_to_string(p.proconfig, ', '), '(none)')         AS proconfig,
       length(pg_get_functiondef(p.oid))                              AS new_def_length,
       md5(pg_get_functiondef(p.oid))                                 AS new_def_md5
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure;

-- P-2: pin_hash 列定義（期待：text / YES / (none)）
SELECT column_name, data_type, is_nullable,
       COALESCE(column_default, '(none)') AS col_default
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'employees'
  AND  column_name  IN ('pin', 'pin_hash')
ORDER  BY column_name;

-- P-3: 件数（期待：total=11 / pin_hash_null=11 / pin_hash_not_null=0）
SELECT count(*)                                     AS total_rows,
       count(*) FILTER (WHERE pin_hash IS NULL)     AS pin_hash_null,
       count(*) FILTER (WHERE pin_hash IS NOT NULL) AS pin_hash_not_null
FROM   public.employees;

-- P-4: function prosrc 文字列確認（extensions.crypt / hash-first CASE / throttle）
SELECT
  (p.prosrc ILIKE '%pin_hash%')                        AS has_pin_hash_ref,
  (p.prosrc ILIKE '%extensions.crypt%')                AS has_extensions_crypt_ref,
  (regexp_replace(p.prosrc, '\s+', ' ', 'g')
     ILIKE '%WHEN e.pin_hash IS NOT NULL THEN%'
            'extensions.crypt(pin_input, e.pin_hash) = e.pin_hash%'
            'ELSE%e.pin = pin_input%END%')             AS hash_first_case_present,
  NOT (regexp_replace(p.prosrc, '\s+', ' ', 'g')
       ILIKE '%e.pin = pin_input OR%'
       OR regexp_replace(p.prosrc, '\s+', ' ', 'g')
       ILIKE '%OR e.pin = pin_input%')                 AS no_or_fallback,
  (p.prosrc ILIKE '%FOR KEY SHARE%')                   AS has_key_share,
  (p.prosrc ILIKE '%private.login_throttle%')          AS has_throttle,
  (p.prosrc ILIKE '%FOR UPDATE%')                      AS has_for_update,
  (p.prosrc ILIKE '%clock_timestamp()%')               AS has_clock_ts,
  (p.prosrc ILIKE '%15 minutes%')                      AS has_15min,
  (p.prosrc ILIKE '%60 seconds%')                      AS has_60s,
  (p.prosrc ILIKE '%>= 5%')                            AS has_threshold5,
  (p.prosrc ILIKE '%DELETE FROM private.login_throttle%') AS has_thr_delete,
  (p.prosrc ILIKE '%employee_sessions%')               AS has_sessions,
  (p.prosrc ILIKE '%gen_random_bytes%')                AS has_token_gen,
  (p.prosrc ILIKE '%digest%')                          AS has_digest,
  (p.prosrc ILIKE '%sha256%')                          AS has_sha256,
  (p.prosrc ILIKE '%8 hours%')                         AS has_8h
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure;

-- P-5: pin / pin_hash 実効権限（期待：全 false）
SELECT r.role, c.col, p.priv,
       has_column_privilege(r.role, 'public.employees', c.col, p.priv) AS has_priv
FROM   (VALUES ('anon'), ('authenticated'))                             r(role)
CROSS  JOIN (VALUES ('pin'), ('pin_hash'))                              c(col)
CROSS  JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('REFERENCES'))    p(priv)
ORDER  BY r.role, c.col, p.priv;

-- P-6a: private.login_throttle の schema USAGE（期待：全 false）
SELECT
  has_schema_privilege(
    'anon',
    (SELECT oid FROM pg_namespace WHERE nspname = 'private'),
    'USAGE'
  ) AS anon_schema_usage,
  has_schema_privilege(
    'authenticated',
    (SELECT oid FROM pg_namespace WHERE nspname = 'private'),
    'USAGE'
  ) AS auth_schema_usage;

-- P-6b: private.login_throttle table 権限（7権限・期待：全 false）
SELECT r.role, p.priv,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_class c
         JOIN   pg_namespace n ON n.oid = c.relnamespace
         WHERE  n.nspname = 'private' AND c.relname = 'login_throttle'
       )
       THEN has_table_privilege(
              r.role,
              (SELECT c.oid FROM pg_class c
               JOIN   pg_namespace n ON n.oid = c.relnamespace
               WHERE  n.nspname = 'private' AND c.relname = 'login_throttle'),
              p.priv
            )
       ELSE NULL END AS has_priv
FROM   (VALUES ('anon'), ('authenticated'))                              r(role)
CROSS  JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),
                    ('TRUNCATE'),('REFERENCES'),('TRIGGER'))             p(priv)
ORDER  BY r.role, p.priv;


-- ============================================================
-- Part 4：EMERGENCY ROLLBACK（★通常は実行しない★）
-- ============================================================
-- 【実行前準備（必須）】
--   Phase 5-D-1 Part 3 P-1 で取得した new_def_md5 / new_def_length を
--   下記 v_new_md5 / v_new_len のプレースホルダーへ書き込む。
--   プレースホルダーが '<FILL_IN>' のまま実行すると ROLLBACK GUARD が停止する。
--
-- 【実行順序】
--   1. function 復元（CREATE OR REPLACE で 5-C-1b baseline へ戻す）
--   2. 復元確認（md5 = af51db14986a5617de3091086a94db64）
--   3. pin_hash DROP（CASCADE なし）
--   4. 最終確認
--   ★ function 復元後に pin_hash DROP。逆順禁止★
--
-- 【注意】
--   - ROLLBACK BODY 内の function 定義（5-C-1b baseline）の md5 が
--     af51db14986a5617de3091086a94db64 と一致しない場合は、
--     docs/sql/phase5c-1b-login-throttle-rpc.sql の ROLLBACK 定義を使用すること。
-- ============================================================

BEGIN;

DO $rb_guard$
DECLARE
  v_count   integer;
  v_md5     text;
  v_len     integer;
  v_new_md5 text    := '<FILL_IN_FROM_5D1_POST_COMMIT_new_def_md5>';
  v_new_len integer := 0;
BEGIN

  -- ★ プレースホルダー未設定チェック（安全ロック）
  IF v_new_md5 = '<FILL_IN_FROM_5D1_POST_COMMIT_new_def_md5>' OR v_new_len = 0 THEN
    RAISE EXCEPTION
      'ROLLBACK GUARD: fill in v_new_md5 and v_new_len '
      'from Phase 5-D-1 Part 3 P-1 before executing rollback';
  END IF;

  -- G-R1: employees.pin_hash が存在する（Phase 5-D-1 適用済みの証拠）
  SELECT count(*) INTO v_count
  FROM   pg_attribute
  WHERE  attrelid = 'public.employees'::regclass
    AND  attname  = 'pin_hash'
    AND  NOT attisdropped;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'ROLLBACK GUARD G-R1 failed: employees.pin_hash does not exist '
      '(Phase 5-D-1 not applied or already rolled back)';
  END IF;

  -- G-R2: current function が pin_hash / extensions.crypt を参照している
  SELECT count(*) INTO v_count
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure
    AND  p.prosrc ILIKE '%pin_hash%'
    AND  p.prosrc ILIKE '%extensions.crypt%';
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'ROLLBACK GUARD G-R2 failed: function does not reference pin_hash/extensions.crypt';
  END IF;

  -- G-R3: current function fingerprint が Phase 5-D-1 適用後の値と一致
  SELECT md5(pg_get_functiondef(p.oid)),
         length(pg_get_functiondef(p.oid))
  INTO   v_md5, v_len
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure;

  IF v_md5 <> v_new_md5 THEN
    RAISE EXCEPTION
      'ROLLBACK GUARD G-R3 failed: md5 mismatch (got %, expected %)', v_md5, v_new_md5;
  END IF;
  IF v_len <> v_new_len THEN
    RAISE EXCEPTION
      'ROLLBACK GUARD G-R3 failed: length mismatch (got %, expected %)', v_len, v_new_len;
  END IF;

  RAISE NOTICE 'ROLLBACK GUARD OK: Phase 5-D-1 state confirmed. Proceeding with rollback.';
END;
$rb_guard$;


-- ---- ROLLBACK BODY: create_employee_session を 5-C-1b baseline へ復元 ----
-- ★ DROP FUNCTION 禁止。CREATE OR REPLACE のみ。★
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


-- ---- ROLLBACK 内部確認（fail-closed） ----
DO $rb_check$
DECLARE
  v_count integer;
  v_md5   text;
  v_len   integer;
  v_text  text;
BEGIN

  -- RC-1: function の md5 が 5-C-1b baseline に戻った
  SELECT md5(pg_get_functiondef(p.oid)),
         length(pg_get_functiondef(p.oid))
  INTO   v_md5, v_len
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure;

  IF v_md5 <> 'af51db14986a5617de3091086a94db64' THEN
    RAISE EXCEPTION
      'ROLLBACK RC-1 failed: md5 after restore = % '
      '(expected af51db14986a5617de3091086a94db64). '
      'Abort. Use docs/sql/phase5c-1b-login-throttle-rpc.sql ROLLBACK section.',
      v_md5;
  END IF;
  IF v_len <> 3520 THEN
    RAISE EXCEPTION
      'ROLLBACK RC-1 failed: length after restore = % (expected 3520). Abort.', v_len;
  END IF;

  -- RC-2: function が pin_hash / crypt を参照しなくなった
  SELECT p.prosrc INTO v_text
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.oid = 'public.create_employee_session(uuid,text)'::regprocedure;

  IF v_text ILIKE '%pin_hash%' THEN
    RAISE EXCEPTION
      'ROLLBACK RC-2 failed: restored function still references pin_hash. '
      'Abort. Do NOT proceed to DROP COLUMN.';
  END IF;
  IF v_text ILIKE '%crypt%' THEN
    RAISE EXCEPTION
      'ROLLBACK RC-2 failed: restored function still references crypt. '
      'Abort. Do NOT proceed to DROP COLUMN.';
  END IF;

  -- RC-3: throttle ロジックが維持されている
  IF v_text NOT ILIKE '%login_throttle%'
     OR v_text NOT ILIKE '%clock_timestamp()%' THEN
    RAISE EXCEPTION
      'ROLLBACK RC-3 failed: throttle logic missing from restored function';
  END IF;

  RAISE NOTICE
    'ROLLBACK function verified (md5=af51db14986a5617de3091086a94db64 / len=3520). '
    'Proceeding to DROP COLUMN pin_hash.';
END;
$rb_check$;


-- ---- ROLLBACK: employees.pin_hash を DROP（CASCADE なし） ----
-- ★ RC-1/RC-2 合格後のみここへ到達する ★
ALTER TABLE public.employees DROP COLUMN pin_hash;


-- ---- ROLLBACK 最終確認（fail-closed） ----
DO $rb_final$
DECLARE
  v_count integer;
BEGIN

  -- RF-1: pin_hash が削除された
  SELECT count(*) INTO v_count
  FROM   pg_attribute
  WHERE  attrelid = 'public.employees'::regclass
    AND  attname  = 'pin_hash'
    AND  NOT attisdropped;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'ROLLBACK RF-1 failed: pin_hash column still exists';
  END IF;

  -- RF-2: employees.pin が text NOT NULL のまま
  SELECT count(*) INTO v_count
  FROM   pg_attribute a
  JOIN   pg_type t ON t.oid = a.atttypid
  WHERE  a.attrelid   = 'public.employees'::regclass
    AND  a.attname    = 'pin'
    AND  NOT a.attisdropped
    AND  t.typname    = 'text'
    AND  a.attnotnull = true;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ROLLBACK RF-2 failed: employees.pin is not text NOT NULL';
  END IF;

  RAISE NOTICE
    'ROLLBACK complete: pin_hash dropped / employees.pin intact / '
    'create_employee_session restored to Phase 5-C-1b baseline.';
END;
$rb_final$;

COMMIT;


-- ============================================================
-- Part 5：DB 実行後 smoke 手順（★DB 実行後にユーザーが実施★）
-- ★実 PIN・hash 値・氏名・UUID は記録しない★
-- ★この段階では実施しない（DB 実行承認後に実施）★
-- ============================================================
-- S-1. 従業員画面（index.html）で既存の正しい PIN でログイン成功
-- S-2. 誤 PIN によるログイン失敗（loginError 表示）
-- S-3. 誤 PIN 5回後の 60 秒 cooldown（5回目以降も拒否）
-- S-4. cooldown 終了後に正しい PIN でログイン成功
-- S-5. admin（/admin）・genka（/genka）ログインに影響がないこと（回帰）
-- S-6. DB 確認（Part 3 P-3）：pin_hash が全 11 行 NULL のまま
-- S-7. Network タブで PIN 値・hash 値が response や request body に含まれないこと
-- ============================================================


-- ============================================================
-- Part 6：実行記録（DB 実行後に記入）
-- ============================================================
-- execution date   ：未定
-- executed by      ：（Supabase SQL Editor・手動）
-- GUARD result     ：未実行
-- BODY result      ：未実行
-- POST-CHECK result：未実行
-- new_def_length   ：<FILL_IN_FROM_5D1_POST_COMMIT_new_def_length>
-- new_def_md5      ：<FILL_IN_FROM_5D1_POST_COMMIT_new_def_md5>
-- smoke result     ：未実施
-- docs/db-migrations.md 記録日：未定
-- ============================================================
