# SEC-5D5-PREFLIGHT-001：Phase 5-D-5 着手前 read-only 確認

記録開始：2026-09-21 10:52 JST。正本：[workflow-rules.md](../workflow-rules.md)。反復手順：[loop-workflow.md](../loop-workflow.md)。

## 識別・状態

- 作業ID：`SEC-5D5-PREFLIGHT-001`
- 更新日時・担当：2026-09-21 19:25 JST、Codex task `01a0bc3a-7ee9-7f70-82d9-b650ce736753`
- 状態：DONE（実DBread-only確認PASS。追加訂正版blob `d55ad82a8aee4c439c092a3b82997aada86abc4b` は新規・非関与Claude HレビューPASS／must-fix 0件）
- 今回の終点：Phase 5-D-5の実装前に、実DBの現行RPC fingerprintと全従業員のhash状態を秘密値なしのread-only結果で確認し、実装可否を判断できる材料をそろえる。5-D-5自体には着手しない。
- 正本・仕様の参照と版：`origin/main` commit `b227e3f09a29a1424cbb04c47a54280c7e569475` の `docs/workflow-rules.md`、`docs/roadmap.md`、`docs/db-migrations.md`、`docs/rls-security-plan.md`、`docs/phase5d-4-observation-closeout.md`、`docs/sql/phase5d-1-employee-pin-hash-dual-read.sql`、`docs/sql/phase5d-2-employee-pin-dual-write.sql`、`docs/sql/phase5d-3-employee-pin-hash-backfill.sql`
- 作業先・branch・BASE／HEAD・対象一覧：隔離worktree `phase5d5-readonly-preflight`、branch `codex/sec-5d5-readonly-preflight`、BASE／開始HEAD `b227e3f09a29a1424cbb04c47a54280c7e569475`。編集対象は本作業記録だけ。既存SQLは読み取りのみ。
- 保全対象の差分／競合作業：元worktree `docs/claude-frontdesk-workflow` の既存hook 2件を変更しない。Phase 5-D-5 SQL、アプリ、DB、Supabase、Git履歴、公開状態を変更しない。

## 目的・範囲・判断

- 業務上の目的：2026-08-03に終了した5-D-4観察後の実DB状態が、5-D-5のhash-only化を検討できる前提を維持しているかを、現行値を漏らさず再確認する。
- 変更範囲：リポジトリ内記録・既存SQL・ログイン実装の読み取り照合、本作業記録の追加。実DBでは既存のread-only照合部分と、そのP3／P4未出力を補うcatalog-only queryだけを岡井さんが手動実行した。
- 対象外・保全条件：5-D-5実装SQL、RPC変更、平文fallback削除、`employees.pin`列DROP、データ更新、関数呼出しによるlogin smoke、Git操作、PR、Preview、公開、自動運転。PIN、hash、氏名、UUID、tokenは取得・転記しない。
- 採用方針と理由：`phase5d-3-employee-pin-hash-backfill.sql` Part 3（POST-COMMIT read-only）を再利用する。同queryは集計値、列権限、3 RPCの属性・fingerprint、EXECUTE権限だけを返す設計で、秘密値を結果へ出さない。実行時にP3／P4が0行となったため、固定した合格条件は変えず、関数の特定だけを `to_regprocedure` に置き換えたcatalog-only補助queryで不足分を確認した。P3／P4未出力の原因は未特定であり、保存済みSQL本文は変更していない。
- 却下／保留した案と理由：5-D-5実装SQLの作成は今回の終点外。5-D-6の平文列DROPは不可逆で別作業ID・別承認・3者合意が必要。現時点でlogin RPCを実行するsmokeはsession発行とthrottle更新を伴うためread-only確認に含めない。
- レビュー区分・理由：H。認証・PIN・実DBの着手可否に関する判断記録のため、成果物を確定する場合は非関与Claudeの追加レビューが必要。
- L判定の確認者・日時・結果：対象外（H判定）。

## 合格条件と証拠

| ID | 仕様上の条件 | 確認方法 | 対象版・証拠参照 | 結果 |
|---|---|---|---|---|
| AC-01 | 5-D-1〜4の完了実績と5-D-5／5-D-6の境界が特定できる | roadmap、DB migration記録、5-D-4 closeout、既存3 SQLを相互照合 | HEAD `b227e3f...` | PASS |
| AC-02 | 使う照合はDBを変更せず、秘密値を結果へ出さない | 5-D-3 SQL Part 3の構文とSELECT列を確認する | `docs/sql/phase5d-3-employee-pin-hash-backfill.sql` の「Part 3：POST-COMMIT」 | PASS |
| AC-03 | 全従業員がhash-only化のデータ前提を満たす | Part 3の `P1_counts` を実DBで1回実行し、`hash_null=0`、`hash_notnull=total`、`pin_notnull=total`、`hash_integ_ok=total`、`cost12_ok=total`、かつ `total>0` を確認する | 2026-09-21に岡井さんが返した3列集計。total=11、他の全件条件=11、hash_null=0 | PASS |
| AC-04 | 現行RPCがレビュー済みbaselineから逸脱していない | `P3_rpc_fp` で3 RPCの `baseline_match=true` を確認する。特に `create_employee_session(uuid,text)` は length=3798／md5=`006550c3455e34aa9d1d61bd60bb85ad` | 2026-09-21のcatalog-only補助query結果。3 RPCすべてbaseline_match=true、属性・fingerprint一致 | PASS |
| AC-05 | PIN列への直接権限とRPC実行権限が既知状態を維持する | `P2_col_privs` 全16行=false、`P4_exec_priv` 全6行=trueを確認する | 2026-09-21の3列結果。P2全16行=false、P4全6行=true | PASS |
| AC-06 | 結果を5-D-5実装承認と混同しない | 実DB結果と判定を記録し、5-D-5実装・SQL案・Git・公開は別承認のまま残す | 本記録 | PASS |
| AC-07 | H区分の非関与Claudeレビューでmust-fix 0となる | 固定した本記録と原資料を非関与Claudeがread-only確認する | 追加訂正版blob `d55ad82a8aee4c439c092a3b82997aada86abc4b`、Claude Sonnet 5 session `b52770e8-16d2-4871-985d-cd8a38bf3fd3`、前後一致 | PASS（must-fix 0件） |

- 合格条件・必須テストの固定版と承認参照：2026-09-21、岡井さんの直接指示「推奨の順序で作業を行なってください。ゴールはPhase 5-D-5着手前のread-only確認とします」および、本taskで直前に提示した読み取り調査・作業記録だけの範囲への回答「承認します」。
- 固定版の保全先・比較方法：本branchの未追跡作業記録。レビュー前にblobと完全差分を固定し、レビュー後に一致を確認する。

## リポジトリ側の照合結果

- 5-D-1：`employees.pin_hash text NULL` と、hashを優先しNULL時だけ平文へfallbackする `create_employee_session(uuid,text)` が導入済み。
- 5-D-2：従業員作成・更新RPCがPINとbcrypt cost 12 hashのdual-writeへ移行済み。
- 5-D-3：2026-07-24の記録では全11件をbackfillし、`hash_null=0`、hash整合11、cost 12が11。これは過去の実績であり、今回の実DB確認結果の代替にしない。
- 5-D-4：2026-08-03の観察終了時も同baselineで、業務上の問題報告は0。5-D-5と5-D-6は未開始。
- 現行baseline：`create_employee_session` 3798／`006550c3455e34aa9d1d61bd60bb85ad`、`create_employee_secure` 1433／`33ea12279533b4a808a4d14bf11bb0a9`、`update_employee_secure` 1915／`848eec0d7310c84cdffd05939b6c7a3b`。
- frontendは既存の `create_employee_session` を呼ぶため、5-D-5でsignature・戻り値を維持する限り、着手前確認時点でfrontend変更は不要と判断する。ただし5-D-5の設計・レビューで再確認する。

## 実DB read-only 実行手順

1. Supabase SQL Editorで `docs/sql/phase5d-3-employee-pin-hash-backfill.sql` 全体を実行しない。
2. 同ファイルの `Part 3：POST-COMMIT（COMMIT 後に実行・read-only）` にある、`WITH emp_post AS (` から最後の `ORDER BY 1, 2;` までの単一queryだけを1回実行する。
3. `section`／`key`／`value` の結果だけを転記する。PIN、hash、氏名、UUID、token、スクリーン全体は転記しない。
4. queryがERRORになった場合は再実行せず、エラー文だけを記録して停止する。

判定規則：従業員総数は運用で増減し得るため、過去値11との一致を単独の合格条件にしない。上記AC-03の全件整合、AC-04の固定fingerprint、AC-05の権限がすべて満たされる場合だけ「5-D-5の設計着手を検討可能」とする。これは実装・DB適用・Git操作・公開の承認ではない。

## 実DB read-only 結果

- 最初のPart 3実行：P1 6行とP2 16行は出力されたが、P3／P4は0行。query自体は成功し、DB変更はない。未出力の原因は未特定。`pg_get_function_identity_arguments` が引数名を含む形式を返し、型だけの固定文字列との完全一致が失敗した可能性はあるが未検証である。5-D-3／5-D-4の過去記録では同種の条件でfingerprint一致とされており、今回との差異も未解明のまま残す。補助queryが同じfingerprintを独立に確認したためDB異常の証拠はないが、原因仮説を確定事項にしない。
- P1：total=11、hash_null=0、hash_notnull=11、pin_notnull=11、hash_integ_ok=11、cost12_ok=11。
- P2：anon／authenticated × pin／pin_hash × SELECT／INSERT／UPDATE／REFERENCES の全16行がfalse。
- 補助query：データ表を読まず、`pg_proc`等のcatalogと権限判定だけを読み取る。期待する3 signatureを `to_regprocedure` で特定し、元のP3／P4と同じ固定fingerprint・属性・権限条件を確認した。
- P3：3 RPCすべてowner=postgres、SECURITY DEFINER=true、volatility=v、search_path=`public, extensions`、baseline_match=true。length／md5は本記録の現行baselineと一致。
- P4：anon／authenticatedによる3 RPCのEXECUTE権限6行はすべてtrue。
- 結論：AC-03〜05を満たし、5-D-5の設計着手を検討できる。5-D-5実装、SQL適用、Git操作、公開の承認は含まない。

### catalog-only補助queryの固定本文

最初のPart 3と合格基準は変えず、0行となったP3／P4の関数特定だけを `to_regprocedure` へ置き換えた。以下は岡井さんが別タブで1回だけ実行した全文であり、単一のWITH／SELECT、catalogと権限判定だけで構成される。

```sql
WITH expected(fn_name, signature, expected_len, expected_md5) AS (
  VALUES
    ('create_employee_secure',
     'public.create_employee_secure(text,text,text,text,uuid,boolean)',
     1433, '33ea12279533b4a808a4d14bf11bb0a9'),
    ('update_employee_secure',
     'public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)',
     1915, '848eec0d7310c84cdffd05939b6c7a3b'),
    ('create_employee_session',
     'public.create_employee_session(uuid,text)',
     3798, '006550c3455e34aa9d1d61bd60bb85ad')
),
rpc_fp AS (
  SELECT
    e.fn_name,
    e.signature,
    pg_get_userbyid(p.proowner) AS owner,
    p.prosecdef AS secdef,
    p.provolatile AS volatility,
    COALESCE(array_to_string(p.proconfig, ', '), '(none)') AS proconfig,
    length(pg_get_functiondef(p.oid)) AS def_len,
    md5(pg_get_functiondef(p.oid)) AS def_md5,
    (p.oid IS NOT NULL
      AND length(pg_get_functiondef(p.oid)) = e.expected_len
      AND md5(pg_get_functiondef(p.oid)) = e.expected_md5) AS baseline_match,
    p.oid
  FROM expected e
  LEFT JOIN pg_proc p ON p.oid = to_regprocedure(e.signature)
),
rpc_exec AS (
  SELECT r.role, f.signature,
    CASE WHEN f.oid IS NULL THEN NULL
         ELSE has_function_privilege(r.role, f.oid, 'EXECUTE')
    END AS can_execute
  FROM (VALUES ('anon'::text), ('authenticated'::text)) r(role)
  CROSS JOIN rpc_fp f
)
SELECT 'P3_rpc_fp' AS section, fn_name || '.signature' AS key, signature AS value FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name || '.owner', COALESCE(owner, 'MISSING') FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name || '.secdef', COALESCE(secdef::text, 'MISSING') FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name || '.volatility', COALESCE(volatility::text, 'MISSING') FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name || '.proconfig', COALESCE(proconfig, 'MISSING') FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name || '.def_len', COALESCE(def_len::text, 'MISSING') FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name || '.def_md5', COALESCE(def_md5, 'MISSING') FROM rpc_fp
UNION ALL SELECT 'P3_rpc_fp', fn_name || '.baseline_match', baseline_match::text FROM rpc_fp
UNION ALL SELECT 'P4_exec_priv', role || '.' || signature, COALESCE(can_execute::text, 'MISSING') FROM rpc_exec
ORDER BY 1, 2;
```

### 秘密値なしの生結果

```csv
section,key,value
P1_counts,cost12_ok,11
P1_counts,hash_integ_ok,11
P1_counts,hash_notnull,11
P1_counts,hash_null,0
P1_counts,pin_notnull,11
P1_counts,total,11
P2_col_privs,anon.pin.INSERT,false
P2_col_privs,anon.pin.REFERENCES,false
P2_col_privs,anon.pin.SELECT,false
P2_col_privs,anon.pin.UPDATE,false
P2_col_privs,anon.pin_hash.INSERT,false
P2_col_privs,anon.pin_hash.REFERENCES,false
P2_col_privs,anon.pin_hash.SELECT,false
P2_col_privs,anon.pin_hash.UPDATE,false
P2_col_privs,authenticated.pin.INSERT,false
P2_col_privs,authenticated.pin.REFERENCES,false
P2_col_privs,authenticated.pin.SELECT,false
P2_col_privs,authenticated.pin.UPDATE,false
P2_col_privs,authenticated.pin_hash.INSERT,false
P2_col_privs,authenticated.pin_hash.REFERENCES,false
P2_col_privs,authenticated.pin_hash.SELECT,false
P2_col_privs,authenticated.pin_hash.UPDATE,false
P3_rpc_fp,create_employee_secure.baseline_match,true
P3_rpc_fp,create_employee_secure.def_len,1433
P3_rpc_fp,create_employee_secure.def_md5,33ea12279533b4a808a4d14bf11bb0a9
P3_rpc_fp,create_employee_secure.owner,postgres
P3_rpc_fp,create_employee_secure.proconfig,"search_path=public, extensions"
P3_rpc_fp,create_employee_secure.secdef,true
P3_rpc_fp,create_employee_secure.signature,"public.create_employee_secure(text,text,text,text,uuid,boolean)"
P3_rpc_fp,create_employee_secure.volatility,v
P3_rpc_fp,create_employee_session.baseline_match,true
P3_rpc_fp,create_employee_session.def_len,3798
P3_rpc_fp,create_employee_session.def_md5,006550c3455e34aa9d1d61bd60bb85ad
P3_rpc_fp,create_employee_session.owner,postgres
P3_rpc_fp,create_employee_session.proconfig,"search_path=public, extensions"
P3_rpc_fp,create_employee_session.secdef,true
P3_rpc_fp,create_employee_session.signature,"public.create_employee_session(uuid,text)"
P3_rpc_fp,create_employee_session.volatility,v
P3_rpc_fp,update_employee_secure.baseline_match,true
P3_rpc_fp,update_employee_secure.def_len,1915
P3_rpc_fp,update_employee_secure.def_md5,848eec0d7310c84cdffd05939b6c7a3b
P3_rpc_fp,update_employee_secure.owner,postgres
P3_rpc_fp,update_employee_secure.proconfig,"search_path=public, extensions"
P3_rpc_fp,update_employee_secure.secdef,true
P3_rpc_fp,update_employee_secure.signature,"public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)"
P3_rpc_fp,update_employee_secure.volatility,v
P4_exec_priv,"anon.public.create_employee_secure(text,text,text,text,uuid,boolean)",true
P4_exec_priv,"anon.public.create_employee_session(uuid,text)",true
P4_exec_priv,"anon.public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)",true
P4_exec_priv,"authenticated.public.create_employee_secure(text,text,text,text,uuid,boolean)",true
P4_exec_priv,"authenticated.public.create_employee_session(uuid,text)",true
P4_exec_priv,"authenticated.public.update_employee_secure(text,uuid,text,text,boolean,uuid,text)",true
```

実行時刻はSQL Editor側で記録しておらず未計測。結果は2026-09-21 18:50 JSTまでに本taskへ返却された。初回30分枠終了後にCodexが補助queryを起案・提示し、岡井さんが実行したため枠外操作だった。補助queryの起案・実行前に、正本第6節が要求する対象限定のSQL案承認は記録されていない。岡井さん本人が提示queryを実行したが、これを事前承認の代替にはしない。この逸脱を18:50 JSTに明示し、岡井さんは結果を確認したうえで18:52 JSTに追加30分と記録・レビュー継続を事後承認した。これは事後追認であり、枠内・事前承認済みだったとは扱わない。

補助queryを正本第12節の「固定基準を変えない検証実装訂正」と分類した根拠は次のとおり。元のP3と同じ3 signature、期待length／md5、owner、SECURITY DEFINER、volatility、search_pathを確認し、元のP4と同じanon／authenticated × 3 RPCのEXECUTE権限を確認する。変更したのは関数特定を `pg_get_function_identity_arguments` の文字列比較から `to_regprocedure(signature)` へ置き換えた点だけである。LEFT JOINと`MISSING`出力は、関数不在を無出力にせず不合格にできるfail-closed補強で、期待値・合否条件を削除・緩和しない。補助query起案・実行前承認がなかった手順逸脱とは分けて記録し、使用済み巡数1に計上する。

## 承認

| 操作・範囲 | 出所と対象 | 条件・有効範囲 | 状態 |
|---|---|---|---|
| リポジトリ読み取り、隔離worktree、作業記録1件の追加 | 上記の直接指示と本taskの「承認します」 | Phase 5-D-5着手前確認。既存SQL本文は変更しない | 承認済み |
| 実DBのread-only query手動実行 | Part 3はPhase 5-D-5着手前read-only確認の直接指示と開始承認。補助queryは実行前の対象限定SQL案承認なし、岡井さん本人の実行後に18:52 JSTの継続承認で事後追認 | Part 3を1回。P3／P4未出力後は、固定基準を変えないcatalog-only補助queryを別タブで1回。秘密値を出さない。事前承認欠落は手順逸脱として残す | 実施済み・結果PASS／手順逸脱あり |
| 外部Claudeへの本記録・3列結果の限定送信 | 本taskで「30分延長と、作業記録・今回の3列集計結果を非関与Claudeへ限定送信する承認」を求めた直後の岡井さんの回答「承認します」 | 本記録と秘密値を含まない3列集計結果だけ | 承認済み |
| 外部Claudeへの原資料10ファイルの限定送信・Hレビュー | 送信対象10ファイルと内部設計送信リスクを明示した直後の岡井さんの回答「承認します」 | `CLAUDE.md`、workflow-rules、roadmap、db-migrations、rls-security-plan、5-D-4 closeout、5-D-1〜3 SQL、`index.html`。秘密値・実データなし | 承認済み |
| 5-D-5実装SQL／DB変更／認証実装／追加の診断SQL | 承認なし | 今回の補助query以外は対象外。補助queryの事前承認欠落は上記行に分離 | 未承認 |
| stage・commit・push・PR・Preview | 承認なし | 対象固定・レビュー後に別途確認 | 未承認 |
| merge・本番公開 | 承認なし | 今回の対象外 | 未承認 |

## 実行枠・反復

- 編集担当と競合防止の確認：Codex窓口1名。隔離worktreeで本記録だけを編集する。
- 自動実行の機能・権限・結果回収・停止確認：未確認のため有効化しない。操作は対話中の手動実行だけ。
- 個別のretry禁止等：最初の実DBqueryは1回。P3／P4が0行だったため同queryを再実行せず、原因を分離したcatalog-only補助queryを1回だけ実行した。Codex／Claudeは実DBでSQLを実行しない。
- 初回実装後の自動修正上限：2巡。本作業は実装なし。レビュー指摘への文書修正にも上限を適用する。
- 前作業ID・引継ぎ元の記録：`WF-PILOT-001`。同作業はDONEで、今回の目的・対象は新規。使用済み修正巡数は引き継がない。
- 引き継いだ使用済み巡数：0。
- 当該IDでの使用済み巡数：3。第1巡は既存Part 3のP3／P4未出力に対する固定基準を変えない補助query訂正。第2巡は初回HレビューBLOCKEDのM1〜M5に対する本記録訂正。第3巡は上限到達後に岡井さんが対象限定で承認した、再レビューmust-fix MF-1〜3の記録訂正。
- 累積使用済み巡数：3（通常上限2を超過。追加1巡を岡井さんが明示承認し、残り0巡）。
- 同一失敗・新情報なしの連続回数：0／上限2。
- 時間／利用量の枠・計測／停止手段：初回は2026-09-21 10:52〜11:22 JSTの30分で停止。18:52〜19:22 JSTの30分を追加し、記録更新と非関与Claude Hレビューに限定。再レビューNEEDS_FIX後、岡井さんの対象限定承認により19:20〜19:50 JSTの追加30分・追加1巡を設定し、MF-1〜3の記録訂正と別の新規Claude再レビューだけを行う。

## レビュー

- 必要な担当・観点：非関与Claude。read-only性、秘密値非出力、5-D-5前提の十分性、過去値と現行値の混同、実装承認への越境がないこと。
- 実施担当・セッション／実行ID：接続失敗 session `7f0c3cf1-3d99-48d4-9f57-3e5957b0aaf2` は入力0・出力0でレビュー不成立。初回HレビューはClaude Sonnet 5、session `88bb3aa4-420d-4ced-83fa-29af3b9e4e35`。
- 担当本人による非関与の根拠・設計／編集参加歴・実装会話の継承有無：初回担当は本依頼文だけで開始し、実装会話・推論を継承せず、対象の設計・編集にも参加していないと報告。ただし本人がsession IDを独立観測できなかったため、CLI結果envelopeのsession IDと照合した。
- 非関与条件1で除外した箇所と、その箇所を覆う別担当・対象版・結果：初回担当がM1〜M5と最小解消案を提示し、本訂正へ採用した箇所は初回担当の非関与確認から除外する。訂正版全体を履歴非継承の別の新規Claudeが確認する。
- 依頼資料・原物参照・返却結果の所在と窓口側の照合：初回担当は承認済み10ファイル、本記録、安全な3列結果を確認。返却は本taskのClaude CLI出力。窓口がsession ID、結果、対象実測blobを照合。
- 確認したBASE／HEAD／対象ファイル・内容識別：HEAD `b227e3f09a29a1424cbb04c47a54280c7e569475`、未追跡は本記録1件。依頼blob `c75c2d33...` に対し実測blob `eff6d007...` だったため対象不一致。
- 結果：BLOCKED。内容面ではP1〜P4、5-D-1〜4、5-D-5／6境界を確認したが、固定対象・承認記録・補助query本文・時間記録のmust-fix 5件。
- must-fix、対応、再確認、残る問題：初回M1は訂正版を新blobで固定、M3は2段階の外部送信承認を分離、M4は補助query全文と生結果を追加、M5は実施時刻未計測・枠外操作・18:52の事後追認を明記。安全審査拒否はprocess開始前でsession発行・外部送信なし。その後の明示承認後に初めてsession `88bb3aa4-420d-4ced-83fa-29af3b9e4e35` を起動してレビューが成立した。初回担当由来の訂正を含む全体を別の新規Claudeが再確認した。
- 訂正版H再レビュー：Claude Sonnet 5、session `0c6a4a90-f34d-44b4-bbf4-f56afc860b7b`。本依頼文だけで開始し、対象・初回reviewerの会話／推論を継承せず、設計・編集・SQL作成へ不参加と報告。対象blobは前後とも `796b4672ab63fe26990db23e95d863437466dace` で一致。結果はNEEDS_FIX。
- 再レビューmust-fix：MF-1は補助queryが新規SQL未承認の記載と矛盾し、基準不変訂正の差分・実行前承認なし／事後追認の区別が不足。MF-2はprocess開始前の安全審査拒否と、承認後に成立したsession `88bb...` の時系列表現がなお曖昧。MF-3はP3／P4が0行だった原因を未検証のまま確定事項としており、原因未特定・形式差の推定・過去記録との差異未解明とすべき。内容面ではP1〜P4、補助queryのread-only性と基準不変、5-D境界、限定結論を確認済み。
- 最終H再レビュー：Claude Sonnet 5、session `b52770e8-16d2-4871-985d-cd8a38bf3fd3`。本依頼文だけで開始し、本作業、WF-PILOT-001、過去reviewer 2名の会話・推論を継承せず、設計・編集・修正へ不参加と報告。BASE／HEAD `b227e3f09a29a1424cbb04c47a54280c7e569475`、branch `codex/sec-5d5-readonly-preflight`、未追跡は本記録1件だけ。対象blobは前後とも `d55ad82a8aee4c439c092a3b82997aada86abc4b` で一致。結果PASS、must-fix 0件。
- 非関与条件1の除外と被覆：session `0c6a...` がMF-1〜3と最小解消案を提示し、追加訂正へ採用した箇所は同担当の非関与確認から除外する。これらを含む追加訂正版全体を、履歴非継承・修正不参加のsession `b527...` がblob `d55ad82a...` で確認しPASSした。
- 最終reviewerの任意助言：補助queryの説明を将来更新する場合は「関数特定方法を分離」とする、18:52承認は記録・レビュー継続への事後追認という粒度を維持する、5-D-5設計ではRPCの型だけでなく引数名も維持する、結果転記時に本reviewerの被覆を記録する。must-fixではなく本作業の合否を変えない。
- 検証・レビュー後の対象不変確認：最終review対象は前後 `d55ad82a8aee4c439c092a3b82997aada86abc4b` で一致。本PASS転記だけで現行記録blobは変わるが、レビュー済み仕様・実DB結果・query・承認境界・合格条件は変更していない。

## 変更操作と結果不明の管理

| 操作ID | 対象 | 承認参照 | 状態 | 成否の照合方法・証拠 |
|---|---|---|---|---|
| OP-01 | 隔離worktree／branch作成 | 本taskの承認範囲 | 実施済み | branch、HEAD、upstream、statusを照合 |
| OP-02 | 本作業記録の追加 | 本taskの承認範囲 | 実施済み | working diffとblobを照合 |
| OP-03 | 実DB Part 3 read-only query | 岡井さんのみ実行 | 実施済み・P1／P2取得、P3／P4は0行（原因未特定） | 3列結果をAC-03／05へ照合 |
| OP-04 | P3／P4 catalog-only補助query | 岡井さんのみ実行 | 実施済み・PASS | 3列結果をAC-04／05へ照合 |
| OP-05 | 非関与Claude Hレビュー初回接続 | 限定外部送信の承認 | ERROR・API接続前にConnectionRefused | session `7f0c3cf1-3d99-48d4-9f57-3e5957b0aaf2`、input/output 0 |
| OP-06 | 原資料を含むHレビュー再試行 | 原資料送信は承認範囲外 | 未実施・安全審査で拒否 | process開始前に拒否。外部送信なし |
| OP-07 | 明示承認後の初回Hレビュー | 原資料10ファイルの限定送信承認 | 実施済み・BLOCKED | OP-06とは別操作。承認後に初めてsession `88bb3aa4-420d-4ced-83fa-29af3b9e4e35` を起動、must-fix 5件 |
| OP-08 | BLOCKED指摘への記録訂正（第2巡） | 承認済みの範囲内修正・残り1巡 | 実施済み | M1〜M5対応。新blob固定後に別Claudeレビュー |
| OP-09 | 訂正版の新規・非関与Claude H再レビュー | 原資料10ファイルの限定送信承認 | 実施済み・NEEDS_FIX | session `0c6a4a90-f34d-44b4-bbf4-f56afc860b7b`、対象blob `796b4672...` 前後一致、must-fix 3件 |
| OP-10 | 追加訂正版の新規・非関与Claude H再レビュー | 上限後追加1巡・30分・再レビュー承認 | 実施済み・PASS | session `b52770e8-16d2-4871-985d-cd8a38bf3fd3`、対象blob `d55ad82a8aee4c439c092a3b82997aada86abc4b` 前後一致、must-fix 0件 |

## 再開情報

- 最後に実物照合した状態：2026-09-21 19:25 JST、branch `codex/sec-5d5-readonly-preflight`、HEAD／upstreamとも `b227e3f...`、未追跡は本記録1件だけ。最終review対象blobは前後 `d55ad82a...` で一致。
- 現在動いている処理と終了確認：なし。
- 次に許可された操作：本作業はDONE。Phase 5-D-5の設計・SQL案・実装へ進む場合は、新しい作業ID、対象限定承認、Hレビューを別途用意する。
- 待っている判断・停止理由：本作業内の待機なし。5-D-5実装は未承認のため進まない。
- 後継記録：設計は`SEC-5D5-001`、Production適用と現行状態は`SEC-5D5-EXEC-001`を参照する。本節の未承認表示は着手前確認完了時点の履歴である。
- 記録の保存先と最後の有効版：本ファイルのworking copy。
- 再開時に照合する項目：対象・仕様・承認・差分・担当・回数・残枠・結果不明操作。

## 完了・公開確認

- 実装：対象外（未実施）。
- 必須検証・レビュー：リポジトリ読み取り、実DBread-only確認、追加訂正版HレビューがすべてPASS。
- Git反映・Preview：未実施・未承認。
- 公開承認・本番反映・稼働確認：対象外・未実施。
- 今回の終点に達した根拠：AC-01〜07すべてPASS。現時点のread-only証拠によりPhase 5-D-5の設計着手を検討可能。実装・SQL適用・Git・公開の承認は含まない。
- 岡井さんの対応時間・貼り付け・重複承認・手戻り・引継ぎ漏れ：対応時間は未計測。安全な3列結果の貼り付けはP3／P4、P1／P2の2回。P3／P4未出力により補助query 1回の手戻りが発生。承認は開始、追加30分＋限定送信、原資料10ファイル、上限後追加1巡＋30分の4回。

## 決定・訂正履歴

| 日時 | 決定／訂正 | 根拠・承認参照 | 後継決定／次の対応 |
|---|---|---|---|
| 2026-09-21 10:52 JST | 次案件をPhase 5-D-5着手前read-only確認に限定 | 岡井さんの直接指示 | 実装へ進まず、現行DB証拠を先に取る |
| 2026-09-21 11:02 JST | 新規SQLを作らず5-D-3 Part 3を再利用 | 既存queryが必要な集計・fingerprint・権限を秘密値なしで返す | 岡井さんの1回実行結果を待つ |
| 2026-09-21 18:50 JST | Part 3のP3／P4未出力を、固定基準を変えないcatalog-only補助queryで確認 | 原因は未特定。保存済みSQLとDBは変更せず、関数特定方法だけを訂正。事前の対象限定SQL案承認なし | P3／P4 PASS。手順逸脱を残し、使用済み巡数1 |
| 2026-09-21 18:52 JST | 30分延長と限定外部送信を承認 | 岡井さんの回答「承認します」 | 記録固定後、非関与Claude Hレビューへ進む |
| 2026-09-21 18:58 JST | Hレビュー未成立で停止 | 初回はAPI接続前ConnectionRefused。原資料を含む再試行は限定承認を超えるため安全審査で実行前拒否 | 外部送信なし。原資料の対象限定承認が得られるまで再試行しない |
| 2026-09-21 19:00 JST | 原資料10ファイルの限定送信を追加承認 | 対象と内部設計送信リスクを明示した直後の岡井さんの「承認します」 | session `88bb...` でHレビュー実施 |
| 2026-09-21 19:05 JST | 初回HレビューBLOCKEDのM1〜M5を第2巡で訂正 | session `88bb...` の実測とmust-fix。固定基準は変更しない | 上限到達。別の新規Claudeで訂正版全体を再レビュー |
| 2026-09-21 19:14 JST | 訂正版H再レビューはNEEDS_FIX | session `0c6a4a90-f34d-44b4-bbf4-f56afc860b7b`。対象blob `796b4672...` 前後一致、must-fix 3件 | 上限到達のため自動修正せず停止。追加1巡の対象限定承認待ち |
| 2026-09-21 19:20 JST | must-fix 3件の記録訂正に追加1巡・30分を承認 | 岡井さんの回答「承認します」 | MF-1〜3だけを訂正し、別の新規Claudeで固定版全体を再レビュー |
| 2026-09-21 19:25 JST | 追加訂正版H再レビューPASS | session `b52770e8-16d2-4871-985d-cd8a38bf3fd3`。対象blob `d55ad82a8aee4c439c092a3b82997aada86abc4b` 前後一致、must-fix 0件 | SEC-5D5-PREFLIGHT-001をDONE。5-D-5実装は別作業ID・別承認 |
