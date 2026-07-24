-- ============================================================
-- Phase 5-D-3：employees PIN hash backfill
-- ============================================================
-- 【実行ステータス】STATUS: PREPARED / NOT EXECUTED
--   - preparation date：2026-07-24（準備 PR #172）
--   - execution date  ：未定（3者合意・smoke 計画確認後に Supabase SQL Editor で手動実行）
--
-- 【目的】
--   `employees.pin_hash IS NULL` の 10 件に対して bcrypt cost 12 で
--   pin_hash を一括生成（backfill）する。
--   - active / inactive を問わず、pin_hash IS NULL の全 10 件が対象
--   - 既に hash 済みの 1 件は変更禁止
--   - employees.pin は保持（dual-read 互換を維持）
--   - login / create / update RPC は変更しない
--   - frontend 変更なし
--
-- 【重要：hash-first dual-read の挙動】
--   pin_hash IS NOT NULL の行では create_employee_session は
--   bcrypt 照合のみを行い、平文 pin への fallback をしない。
--   backfill 後に hash 整合が確認できなければ対象従業員はログイン不能になる。
--   このため hash 整合確認を同一 transaction 内で行い、
--   1 件でも不一致なら COMMIT 前に例外で全体 abort する。
--   「平文 fallback により業務継続できる」の前提は置かない。
--
-- 【GUARD baseline（実 DB 確認済み・2026-07-24 時点）】
--   create_employee_secure(text,text,text,text,uuid,boolean): len=1433 / md5=33ea12279533b4a808a4d14bf11bb0a9
--   update_employee_secure(text,uuid,text,text,boolean,uuid,text): len=1915 / md5=848eec0d7310c84cdffd05939b6c7a3b
--   create_employee_session(uuid,text):                           len=3798 / md5=006550c3455e34aa9d1d61bd60bb85ad
--
-- 【実行方法】
--   1. Part 1 PRE-CHECK を実行 → 全行が期待値と一致することを確認
--   2. ChatGPT 承認後、Part 2 BODY の BEGIN~COMMIT を1回だけ実行
--   3. NOTICE「GUARD OK」「POST-CHECK all passed」を確認
--   4. Part 3 POST-COMMIT を実行 → 結果を ChatGPT へ貼り戻す
--   5. Production smoke を実施（Part 5）
-- ============================================================


-- ============================================================
-- Part 1：PRE-CHECK（read-only・BODY 実行前に実施）
-- PIN値・hash値・氏名・UUID は一切出力しない
-- ============================================================

WITH

-- C1: employees 件数・列状態
emp_counts AS (
  SELECT
    count(*)                                                AS total,
    count(*) FILTER (WHERE pin_hash IS NULL)               AS hash_null,
    count(*) FILTER (WHERE pin_hash IS NOT NULL)           AS hash_notnull,
    count(*) FILTER (WHERE pin IS NULL)                    AS pin_null
  FROM public.employees
),

-- C2: NULL 対象 10 件の pin が全て半角数字4桁であること（件数のみ）
pin_validation AS (
  SELECT count(*) AS abnormal_count
  FROM   public.employees
  WHERE  pin_hash IS NULL
    AND  (pin IS NULL OR pin !~ '^[0-9]{4}$')
),

-- C3: 既存 hash 済み 1 件の整合・cost 12 確認（件数のみ・hash値・UUID は出力しない）
existing_hash_check AS (
  SELECT
    count(*) FILTER (
      WHERE pin_hash IS NOT NULL
        AND extensions.crypt(pin, pin_hash) = pin_hash
    ) AS hash_integrity_ok,
    count(*) FILTER (
      WHERE pin_hash IS NOT NULL
        AND pin_hash ~ '^\$2[aby]\$12\$'
    ) AS cost12_ok
  FROM public.employees
),

-- C4: employees 列 schema
col_schema AS (
  SELECT column_name, data_type, is_nullable,
         COALESCE(column_default,'(none)') AS col_default
  FROM   information_schema.columns
  WHERE  table_schema = 'public'
    AND  table_name   = 'employees'
    AND  column_name  IN ('pin','pin_hash')
),

-- C5: pgcrypto
pgcrypto_info AS (
  SELECT
    e.extname, e.extversion, n.nspname AS ext_schema,
    (to_regprocedure(n.nspname||'.crypt(text,text)') IS NOT NULL)::text        AS crypt_ok,
    (to_regprocedure(n.nspname||'.gen_salt(text,integer)') IS NOT NULL)::text  AS gen_salt_ok
  FROM   pg_extension e
  JOIN   pg_namespace n ON n.oid = e.extnamespace
  WHERE  e.extname = 'pgcrypto'
),

-- C6: pin / pin_hash 列権限（全 false 期待）
col_privs AS (
  SELECT r.role::text, c.col::text, p.priv::text,
         has_column_privilege(r.role,'public.employees',c.col,p.priv)::text AS has_priv
  FROM   (VALUES ('anon'::text),('authenticated'::text))                    r(role)
  CROSS  JOIN (VALUES ('pin'::text),('pin_hash'::text))                     c(col)
  CROSS  JOIN (VALUES ('SELECT'::text),('INSERT'::text),
                      ('UPDATE'::text),('REFERENCES'::text))                p(priv)
),

-- C7: GUARD baseline RPC fingerprint
rpc_fp AS (
  SELECT
    n.nspname::text                                          AS schema_name,
    p.oid::regprocedure::text                               AS signature,
    p.proname::text                                         AS fn_name,
    pg_get_userbyid(p.proowner)::text                       AS owner,
    p.prosecdef::text                                       AS secdef,
    p.provolatile::text                                     AS volatility,
    COALESCE(array_to_string(p.proconfig,', '),'(none)')::text AS proconfig,
    length(pg_get_functiondef(p.oid))::text                 AS def_len,
    md5(pg_get_functiondef(p.oid))::text                    AS def_md5,
    (CASE p.proname
      WHEN 'create_employee_secure'  THEN
        md5(pg_get_functiondef(p.oid)) = '33ea12279533b4a808a4d14bf11bb0a9'
        AND length(pg_get_functiondef(p.oid)) = 1433
      WHEN 'update_employee_secure'  THEN
        md5(pg_get_functiondef(p.oid)) = '848eec0d7310c84cdffd05939b6c7a3b'
        AND length(pg_get_functiondef(p.oid)) = 1915
      WHEN 'create_employee_session' THEN
        md5(pg_get_functiondef(p.oid)) = '006550c3455e34aa9d1d61bd60bb85ad'
        AND length(pg_get_functiondef(p.oid)) = 3798
      ELSE false
    END)::text AS baseline_match
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.proname IN ('create_employee_secure','update_employee_secure','create_employee_session')
    AND  (
           (p.proname = 'create_employee_secure'
            AND pg_get_function_identity_arguments(p.oid) = 'text, text, text, text, uuid, boolean')
        OR (p.proname = 'update_employee_secure'
            AND pg_get_function_identity_arguments(p.oid) = 'text, uuid, text, text, boolean, uuid, text')
        OR (p.proname = 'create_employee_session'
            AND pg_get_function_identity_arguments(p.oid) = 'uuid, text')
    )
)

-- 出力：件数・boolean・fingerprint のみ
SELECT 'C1_emp_counts' AS section, 'total'        AS key, total::text        AS value FROM emp_counts
UNION ALL SELECT 'C1_emp_counts','hash_null',      hash_null::text             FROM emp_counts
UNION ALL SELECT 'C1_emp_counts','hash_notnull',   hash_notnull::text          FROM emp_counts
UNION ALL SELECT 'C1_emp_counts','pin_null',       pin_null::text              FROM emp_counts
UNION ALL SELECT 'C2_pin_valid','abnormal_count_in_null_targets', abnormal_count::text FROM pin_validation
UNION ALL SELECT 'C3_existing_hash','hash_integrity_ok', hash_integrity_ok::text FROM existing_hash_check
UNION ALL SELECT 'C3_existing_hash','cost12_ok',    cost12_ok::text             FROM existing_hash_check
UNION ALL SELECT 'C4_col_schema', column_name,
       'type='||data_type||' | nullable='||is_nullable||' | default='||col_default
FROM   col_schema
UNION ALL SELECT 'C5_pgcrypto','extname',    extname     FROM pgcrypto_info
UNION ALL SELECT 'C5_pgcrypto','extversion', extversion  FROM pgcrypto_info
UNION ALL SELECT 'C5_pgcrypto','schema',     ext_schema  FROM pgcrypto_info
UNION ALL SELECT 'C5_pgcrypto','crypt_ok',   crypt_ok    FROM pgcrypto_info
UNION ALL SELECT 'C5_pgcrypto','gen_salt_ok',gen_salt_ok FROM pgcrypto_info
UNION ALL SELECT 'C6_col_privs', role||'.'||col||'.'||priv, has_priv FROM col_privs
UNION ALL SELECT 'C7_rpc_fp', fn_name||'.signature',  signature      FROM rpc_fp
UNION ALL SELECT 'C7_rpc_fp', fn_name||'.owner',      owner          FROM rpc_fp
UNION ALL SELECT 'C7_rpc_fp', fn_name||'.secdef',     secdef         FROM rpc_fp
UNION ALL SELECT 'C7_rpc_fp', fn_name||'.volatility', volatility     FROM rpc_fp
UNION ALL SELECT 'C7_rpc_fp', fn_name||'.proconfig',  proconfig      FROM rpc_fp
UNION ALL SELECT 'C7_rpc_fp', fn_name||'.def_len',    def_len        FROM rpc_fp
UNION ALL SELECT 'C7_rpc_fp', fn_name||'.def_md5',    def_md5        FROM rpc_fp
UNION ALL SELECT 'C7_rpc_fp', fn_name||'.baseline_match', baseline_match FROM rpc_fp
ORDER BY 1, 2;

/*
  PRE-CHECK 期待値
  -----------------------------------------------------------------------
  C1_emp_counts  total         : 11
  C1_emp_counts  hash_null     : 10
  C1_emp_counts  hash_notnull  : 1
  C1_emp_counts  pin_null      : 0
  C2_pin_valid   abnormal_count_in_null_targets : 0
  C3_existing_hash  hash_integrity_ok : 1
  C3_existing_hash  cost12_ok         : 1
  C4_col_schema  pin     : type=text | nullable=NO | default=(none)
  C4_col_schema  pin_hash: type=text | nullable=YES | default=(none)
  C5_pgcrypto    schema       : extensions
  C5_pgcrypto    crypt_ok     : true
  C5_pgcrypto    gen_salt_ok  : true
  C6_col_privs   全 16 行     : false
  C7_rpc_fp      *.baseline_match : true（3本とも）
  -----------------------------------------------------------------------
*/


-- ============================================================
-- Part 2：BODY（★Part 1 全合格・ChatGPT 承認後に1回のみ実行★）
--   BEGIN ~ COMMIT を丸ごと選択して実行する。再実行禁止。
--   GUARD または POST-CHECK 失敗 → 自動 abort → DB 無変更。
-- ============================================================

BEGIN;

-- ロック取得（5秒でタイムアウト → abort して利用の少ない時間帯に再実行）
SET LOCAL lock_timeout      = '5s';
SET LOCAL statement_timeout = '60s';

-- SHARE ROW EXCLUSIVE: employee の create / update / delete を待機させる
--   login 等の SELECT は継続可能（SHARE ROW EXCLUSIVE は ACCESS SHARE と競合しない）
--   GUARD から UPDATE、POST-CHECK まで対象集合を安定させる
LOCK TABLE public.employees IN SHARE ROW EXCLUSIVE MODE;

DO $$
DECLARE
  v_total            integer;
  v_hash_null        integer;
  v_hash_notnull     integer;
  v_abnormal_pin     integer;
  v_hash_integ       integer;
  v_cost12           integer;
  v_updated          integer;
  v_hash_integ_post  integer;
  v_cost12_post      integer;
  v_pin_notnull      integer;
  -- 既存 hash 済み 1 件の一時保持（transaction 終了時に破棄・永続化しない）
  v_existing_uuid    uuid;
  v_existing_pinhash text;
  v_preserved        boolean;
BEGIN

  -- ===== transaction 内 GUARD =====

  -- G-1: ロック取得後に件数再確認
  SELECT count(*),
         count(*) FILTER (WHERE pin_hash IS NULL),
         count(*) FILTER (WHERE pin_hash IS NOT NULL)
  INTO   v_total, v_hash_null, v_hash_notnull
  FROM   public.employees;

  IF v_total <> 11 THEN
    RAISE EXCEPTION 'GUARD G-1 failed: total = % (expected 11)', v_total;
  END IF;
  IF v_hash_null <> 10 THEN
    RAISE EXCEPTION 'GUARD G-2 failed: pin_hash IS NULL = % (expected 10)', v_hash_null;
  END IF;
  IF v_hash_notnull <> 1 THEN
    RAISE EXCEPTION 'GUARD G-3 failed: pin_hash IS NOT NULL = % (expected 1)', v_hash_notnull;
  END IF;

  -- G-2: NULL 対象 10 件の pin が全て有効な4桁数字
  SELECT count(*) INTO v_abnormal_pin
  FROM   public.employees
  WHERE  pin_hash IS NULL
    AND  (pin IS NULL OR pin !~ '^[0-9]{4}$');
  IF v_abnormal_pin <> 0 THEN
    RAISE EXCEPTION 'GUARD G-4 failed: % rows in NULL targets have invalid pin', v_abnormal_pin;
  END IF;

  -- G-3: 既存 hash 済み 1 件の整合・cost 12 確認
  SELECT count(*) INTO v_hash_integ
  FROM   public.employees
  WHERE  pin_hash IS NOT NULL
    AND  extensions.crypt(pin, pin_hash) = pin_hash;
  IF v_hash_integ <> 1 THEN
    RAISE EXCEPTION 'GUARD G-5 failed: existing hash integrity check = % (expected 1)', v_hash_integ;
  END IF;

  SELECT count(*) INTO v_cost12
  FROM   public.employees
  WHERE  pin_hash IS NOT NULL
    AND  pin_hash ~ '^\$2[aby]\$12\$';
  IF v_cost12 <> 1 THEN
    RAISE EXCEPTION 'GUARD G-6 failed: existing hash cost 12 check = % (expected 1)', v_cost12;
  END IF;

  -- G-4: 既存 hash 済み 1 件の UUID と pin_hash を一時変数へ保存
  --      （transaction 終了時に破棄・SELECT 結果・NOTICE・docs への出力禁止）
  SELECT id, pin_hash
  INTO   STRICT v_existing_uuid, v_existing_pinhash
  FROM   public.employees
  WHERE  pin_hash IS NOT NULL;
  -- STRICT: 0行または複数行なら例外 → 期待通り1行でなければ abort

  RAISE NOTICE 'GUARD OK: 10 NULL targets confirmed. Proceeding with backfill.';

  -- ===== UPDATE（backfill） =====

  UPDATE public.employees
  SET    pin_hash = extensions.crypt(pin, extensions.gen_salt('bf', 12))
  WHERE  pin_hash IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 10 THEN
    RAISE EXCEPTION 'UPDATE failed: updated % rows (expected 10)', v_updated;
  END IF;

  -- ===== transaction 内 POST-CHECK =====

  -- PC-1: 件数
  SELECT count(*),
         count(*) FILTER (WHERE pin_hash IS NULL),
         count(*) FILTER (WHERE pin_hash IS NOT NULL),
         count(*) FILTER (WHERE pin IS NOT NULL)
  INTO   v_total, v_hash_null, v_hash_notnull, v_pin_notnull
  FROM   public.employees;

  IF v_total <> 11 THEN
    RAISE EXCEPTION 'PC-1 failed: total = %', v_total;
  END IF;
  IF v_hash_null <> 0 THEN
    RAISE EXCEPTION 'PC-2 failed: pin_hash IS NULL = % (expected 0)', v_hash_null;
  END IF;
  IF v_hash_notnull <> 11 THEN
    RAISE EXCEPTION 'PC-3 failed: pin_hash IS NOT NULL = % (expected 11)', v_hash_notnull;
  END IF;
  IF v_pin_notnull <> 11 THEN
    RAISE EXCEPTION 'PC-4 failed: pin IS NOT NULL = % (expected 11)', v_pin_notnull;
  END IF;

  -- PC-2: 全 11 件の hash 整合（hash-first dual-read で全員ログイン可能であること）
  SELECT count(*) INTO v_hash_integ_post
  FROM   public.employees
  WHERE  extensions.crypt(pin, pin_hash) = pin_hash;
  IF v_hash_integ_post <> 11 THEN
    RAISE EXCEPTION
      'PC-5 failed: hash integrity = % of 11 (any failure → abort to prevent login lockout)',
      v_hash_integ_post;
  END IF;

  -- PC-3: 全 11 件が bcrypt cost 12
  SELECT count(*) INTO v_cost12_post
  FROM   public.employees
  WHERE  pin_hash ~ '^\$2[aby]\$12\$';
  IF v_cost12_post <> 11 THEN
    RAISE EXCEPTION 'PC-6 failed: cost 12 check = % of 11', v_cost12_post;
  END IF;

  -- PC-4: 既存 hash 済み 1 件の pin_hash が保存前と完全一致
  --       （UUID・hash 値は RAISE NOTICE・出力に含めない）
  SELECT (pin_hash = v_existing_pinhash) INTO v_preserved
  FROM   public.employees
  WHERE  id = v_existing_uuid;

  IF NOT v_preserved THEN
    RAISE EXCEPTION
      'PC-7 failed: pre-existing hash was modified (must not change)';
  END IF;

  RAISE NOTICE
    'POST-CHECK all passed: total=11 / null=0 / notnull=11 / hash_ok=11 / cost12=11 / existing_preserved=true';
END;
$$;

COMMIT;


-- ============================================================
-- Part 3：POST-COMMIT（COMMIT 後に実行・read-only）
-- PIN値・hash値・氏名・UUID は一切出力しない
-- ============================================================

WITH

emp_post AS (
  SELECT
    count(*)                                                AS total,
    count(*) FILTER (WHERE pin_hash IS NULL)               AS hash_null,
    count(*) FILTER (WHERE pin_hash IS NOT NULL)           AS hash_notnull,
    count(*) FILTER (WHERE pin IS NOT NULL)                AS pin_notnull,
    count(*) FILTER (WHERE extensions.crypt(pin,pin_hash) = pin_hash) AS hash_integ_ok,
    count(*) FILTER (WHERE pin_hash ~ '^\$2[aby]\$12\$')  AS cost12_ok
  FROM public.employees
),

col_privs AS (
  SELECT r.role::text, c.col::text, p.priv::text,
         has_column_privilege(r.role,'public.employees',c.col,p.priv)::text AS has_priv
  FROM   (VALUES ('anon'::text),('authenticated'::text))                    r(role)
  CROSS  JOIN (VALUES ('pin'::text),('pin_hash'::text))                     c(col)
  CROSS  JOIN (VALUES ('SELECT'::text),('INSERT'::text),
                      ('UPDATE'::text),('REFERENCES'::text))                p(priv)
),

rpc_fp AS (
  SELECT
    p.proname::text                                         AS fn_name,
    p.oid::regprocedure::text                               AS signature,
    pg_get_userbyid(p.proowner)::text                       AS owner,
    p.prosecdef::text                                       AS secdef,
    p.provolatile::text                                     AS volatility,
    COALESCE(array_to_string(p.proconfig,', '),'(none)')::text AS proconfig,
    length(pg_get_functiondef(p.oid))::text                 AS def_len,
    md5(pg_get_functiondef(p.oid))::text                    AS def_md5,
    (CASE p.proname
      WHEN 'create_employee_secure'  THEN
        md5(pg_get_functiondef(p.oid)) = '33ea12279533b4a808a4d14bf11bb0a9'
        AND length(pg_get_functiondef(p.oid)) = 1433
      WHEN 'update_employee_secure'  THEN
        md5(pg_get_functiondef(p.oid)) = '848eec0d7310c84cdffd05939b6c7a3b'
        AND length(pg_get_functiondef(p.oid)) = 1915
      WHEN 'create_employee_session' THEN
        md5(pg_get_functiondef(p.oid)) = '006550c3455e34aa9d1d61bd60bb85ad'
        AND length(pg_get_functiondef(p.oid)) = 3798
      ELSE false
    END)::text AS baseline_match
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'public'
    AND  p.proname IN ('create_employee_secure','update_employee_secure','create_employee_session')
    AND  (
           (p.proname = 'create_employee_secure'
            AND pg_get_function_identity_arguments(p.oid) = 'text, text, text, text, uuid, boolean')
        OR (p.proname = 'update_employee_secure'
            AND pg_get_function_identity_arguments(p.oid) = 'text, uuid, text, text, boolean, uuid, text')
        OR (p.proname = 'create_employee_session'
            AND pg_get_function_identity_arguments(p.oid) = 'uuid, text')
    )
),

rpc_exec AS (
  SELECT r.role::text, fns.sig::text,
         has_function_privilege(r.role, fns.oid, 'EXECUTE')::text AS can_execute
  FROM   (VALUES ('anon'::text),('authenticated'::text))  r(role)
  CROSS  JOIN (
    SELECT p.oid, p.oid::regprocedure::text AS sig
    FROM   pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE  n.nspname='public'
      AND  p.proname IN ('create_employee_secure','update_employee_secure','create_employee_session')
      AND  (
             (p.proname='create_employee_secure'
              AND pg_get_function_identity_arguments(p.oid)='text, text, text, text, uuid, boolean')
          OR (p.proname='update_employee_secure'
              AND pg_get_function_identity_arguments(p.oid)='text, uuid, text, text, boolean, uuid, text')
          OR (p.proname='create_employee_session'
              AND pg_get_function_identity_arguments(p.oid)='uuid, text')
      )
  ) fns
)

SELECT 'P1_counts' AS section, 'total'         AS key, total::text         AS value FROM emp_post
UNION ALL SELECT 'P1_counts','hash_null',      hash_null::text              FROM emp_post
UNION ALL SELECT 'P1_counts','hash_notnull',   hash_notnull::text           FROM emp_post
UNION ALL SELECT 'P1_counts','pin_notnull',    pin_notnull::text            FROM emp_post
UNION ALL SELECT 'P1_counts','hash_integ_ok',  hash_integ_ok::text          FROM emp_post
UNION ALL SELECT 'P1_counts','cost12_ok',      cost12_ok::text              FROM emp_post
UNION ALL SELECT 'P2_col_privs', role||'.'||col||'.'||priv, has_priv        FROM col_privs
UNION ALL SELECT 'P3_rpc_fp', fn_name||'.signature',      signature          FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name||'.owner',          owner              FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name||'.secdef',         secdef             FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name||'.volatility',     volatility         FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name||'.proconfig',      proconfig          FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name||'.def_len',        def_len            FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name||'.def_md5',        def_md5            FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name||'.baseline_match', baseline_match     FROM rpc_fp
UNION ALL SELECT 'P4_exec_priv', role||'.'||sig,          can_execute        FROM rpc_exec
ORDER BY 1, 2;

/*
  POST-COMMIT 期待値
  -----------------------------------------------------------------------
  P1_counts  total           : 11
  P1_counts  hash_null       : 0
  P1_counts  hash_notnull    : 11
  P1_counts  pin_notnull     : 11
  P1_counts  hash_integ_ok   : 11（全員が新 hash でログイン可能）
  P1_counts  cost12_ok       : 11
  P2_col_privs  全 16 行     : false
  P3_rpc_fp  *.baseline_match: true（3本とも）
  P4_exec_priv  全 6 行      : true
  -----------------------------------------------------------------------
*/


-- ============================================================
-- Part 4：rollback / forward-fix 方針
-- ============================================================
-- 【COMMIT 前】
--   GUARD または transaction 内 POST-CHECK が失敗した場合、
--   RAISE EXCEPTION により transaction 全体が自動 abort する。
--   DB 変更は残らない。再実行禁止ガード（hash_null <> 10）が機能する。
--
-- 【COMMIT 後：rollback SQL は用意しない】
--   理由：
--   1. pin_hash を NULL へ戻すには対象 10 件を特定する必要があり、
--      UUID を永続記録することになりセキュリティ上問題。
--   2. hash-first dual-read 動作中に pin_hash = NULL へ戻すと、
--      全員が平文 fallback に戻り、セキュリティ状態が後退する。
--   3. backfill が正常完了した状態（hash_integ_ok=11）では、
--      ログイン不能は発生しない。
--   4. 問題が発生した場合は forward-fix を 3 者合意で作成する：
--      - create/update RPC が正常ならば、問題従業員を管理画面から
--        PIN 再設定（update_employee_secure 経由）すれば hash が再生成される。
-- ============================================================


-- ============================================================
-- Part 5：Production smoke 計画（★DB 実行後にユーザーが実施★）
-- 氏名・PIN・UUID は記録しない
-- ============================================================
-- S-1. DB final count 確認
--   操作：POST-COMMIT P1 を再実行
--   確認：hash_null=0 / hash_notnull=11
--
-- S-2. 旧 NULL 対象（backfill 対象）の代表 1 名でログイン成功
--   操作：index.html で正しい PIN を入力してログイン
--   確認：成功（bcrypt hash-first 照合が機能）
--
-- S-3. 同一従業員で誤 PIN を 1 回だけ入力
--   操作：誤 PIN でログイン試行
--   確認：拒否
--   注意：throttle の fail_count が 1 増加（閾値5に達しない）
--
-- S-4. 正しい PIN で再ログインして throttle を正常化
--   操作：正しい PIN でログイン
--   確認：成功（throttle 行が削除される）
--
-- S-5. 5-D-2 ですでに hash 済みだった代表 1 名でログイン成功
--   操作：index.html でログイン
--   確認：成功（既存 hash が維持されていること）
--
-- S-6. 管理者ログイン成功（/admin）
--
-- S-7. 原価管理ログイン成功（/genka）
--
-- 全員手作業確認は不要：同一の UPDATE 文で全 10 件を backfill しており、
-- hash_integ_ok=11 がPOST-CHECK で確認済みのため代表確認で十分。
-- ============================================================


-- ============================================================
-- Part 6：実行記録（DB 実行後に記入）
-- ============================================================
-- execution date     ：未定
-- executed by        ：（Supabase SQL Editor・手動）
-- GUARD result       ：未実行
-- BODY result        ：未実行
-- POST-CHECK result  ：未実行
-- smoke result       ：未実施
-- db-migrations 記録日：未定
-- ============================================================
