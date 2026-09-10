# 作業ルール・進捗管理ルール（workflow-rules）

作成日：2026-06-13
対象：社内業務システムプロジェクト全体
更新日：2026-09-10（Codex主体の運用へ適用）
状態：恒久ルール（特定フェーズ専用ではなく、プロジェクトが続く限り継続適用する）

本書を運用の正本とする。入口は [AGENTS.md](../AGENTS.md)、Claudeの担当範囲は [CLAUDE.md](../CLAUDE.md) を参照。製品仕様・フェーズの完了実績・承認基準は今回変更しない。役割と承認済み作業の進め方は第12節、Type 1とmergeの境界は第14節に集約する。

第11・13節は当時の履歴であり、旧役割分担や「未実装」は記録時点の状態を表す。旧文書の役割記述との相違には第12節を適用するが、実行権限や保護設定を拡大する根拠にはしない。

---

## 1. このファイルの目的

- 社内業務システムプロジェクト全体の作業ルールを定義する
- 進捗管理チャットへ報告すべきタイミングと報告内容を定義する
- 実装チャットと進捗管理チャットを混ぜないためのルールを定義する
- 作業中に本流から逸れないようにする

---

## 2. 基本方針

- 原則、同時に進める実装は1つだけにする
- 本流以外は保留扱いにする
- 進捗管理チャットでは、作業指示よりも判断・整理を優先する
- 読み取り専用確認と変更作業を混ぜない
- 作業範囲を超えそうになったら、作業を止めて報告する
- 未コミット変更やブランチのズレがある場合は、作業前に状態確認を優先する

---

## 3. 本流管理ルール

- 作業開始時に、現在の本流を確認する
- 本流とは、現時点で最優先で進める1つの作業テーマを指す
- 本流以外の作業が出た場合は、原則として保留扱いにする
- 本流を変更する場合は、進捗管理チャットで判断してから行う

---

## 4. 進捗管理チャットへ報告すべきタイミング

以下のタイミングでは、Codexは進捗管理チャットへ貼れる報告を出す。承認済み範囲内の報告は再承認待ちを意味せず、第12節に従って続行する。

- 作業単位が一区切りついたとき
- 次フェーズに進めそうだと判断したとき
- SQL作成に進みたくなったとき
- SQL実行に進みたくなったとき
- コード修正が必要に見えたとき
- docs更新が必要に見えたとき
- git add / commit / push が必要に見えたとき
- reset / stash / ファイル削除 / 破棄操作が必要に見えたとき
- 本流以外の作業が混ざりそうになったとき
- 未コミット変更を検出したとき
- ローカルブランチが origin/main と大きくズレているとき
- デバッグに入るべきか迷ったとき

---

## 5. git運用ルール

- 作業開始時に現在ブランチ、git status、git log --oneline -5 を確認する
- main が origin/main とズレている場合は、勝手に作業を進めない
- ahead / behind がある場合は、作業前に報告する
- local-only commit がある場合は、勝手に消さない
- reset / stash / checkout / branch作成 / rebase / merge / pull / push は、明示指示がある場合のみ行う
- origin/main を基点に作業する必要がある場合は、専用ブランチを作る方針を提案する
- 作業ツリーが clean でない場合は、まず状態確認を優先する

---

## 6. 禁止事項

次の操作は承認範囲外では行わない。承認済みタスクに含まれる調査・仕様案・コード／文書の修正・検証・自己修正・記録を工程ごとに再承認へ分割しない。Git変更・DB実行等の区別は第12節に従う。

- SQL作成
- SQL実行
- コード修正
- docs更新
- git add
- commit
- push
- reset
- stash
- rebase
- merge
- ファイル削除
- 破棄操作
- 本流以外の実装作業
- ついでのリファクタリング
- ついでのUI改善

---

## 7. 記録先の役割分担

| ファイル | 役割 |
|---|---|
| `docs/roadmap.md` | プロジェクト全体の進捗、現在地、フェーズ計画、次にやることを記録する |
| `docs/db-migrations.md` | DB変更、SQL適用、確認SQL、影響範囲を時系列で記録する |
| `docs/rls-security-plan.md` | セキュリティ改修の設計方針、RLS/RPC/Auth等の考え方を記録する |
| `docs/workflow-rules.md` | 作業ルール、進捗管理ルール、報告タイミング、git運用ルール、禁止事項を記録する |

---

## 8. フェーズ番号体系の注意

`docs/roadmap.md` と `docs/rls-security-plan.md` ではフェーズ番号体系が異なるため、作業時にはどちらのPhaseを指しているか明示すること。

- 例：roadmap.md の Phase 3 は「残り INSERT / UPDATE のRPC化」、rls-security-plan.md の Phase 3 は「Supabase Auth 導入」であり、同じ番号でも内容が異なる
- 原則として、現在の作業管理では **docs/roadmap.md 側のフェーズ体系を優先する**
- rls-security-plan.md は設計文書として参照する

---

## 9. 進捗管理チャット用の報告フォーマット

進捗管理チャットへ貼る報告は、以下のフォーマットを使用する。

```md
## 作業報告

### 現在の本流
-

### 現在の作業
-

### 実施内容
-

### 確認できたこと
-

### 未確認・不明点
-

### 発見したリスク
-

### 現在の作業範囲内か
範囲内 / 範囲外の可能性あり

### 本流以外に混ざりそうな作業
-

### 未コミット変更の有無
-

### ブランチ状態
-

### 次に進んでよいかの判断材料
-

### CLIとしての提案
- 継続
- 停止して判断待ち
- 別チャットへ分離
- 次フェーズ移行の相談
```

---

## 10. 作業の区切りごとの報告義務（進捗管理チャット貼り付け用）

作業が以下のような「区切り」に到達した場合、CLIは次に進む前に、進捗管理チャットへそのまま貼れる形式で、**現在地・完了内容・確認結果・次にやること**を必ず整理して報告する。

この報告は Section 4（報告すべきタイミング）を具体化したものであり、区切りごとの報告を毎回省略しないことを徹底するための恒久ルールとする。

### 区切りの例

- DB実行完了
- DB事後確認完了
- 本番確認完了
- docs記録完了
- commit完了
- push完了
- PR作成完了
- PR merge完了
- main追従完了
- ブランチ整理完了
- フェーズ完了
- 次工程へ移る直前
- 作業を中断する直前

### 報告文に原則として含める項目

- 現在地（どのフェーズ・どの区切りにいるか）
- 完了した作業
- 確認結果（DB事後確認・本番確認・git status など、確認できた事実）
- 未実施のこと（今回あえてやっていないこと）
- 次にやること
- 注意点や別タスク候補（本流外として切り出したもの・申し送り事項）

### 補足

- 区切りに到達したら、次の変更作業へ進む前に、まずこの報告を出す。
- 報告の詳細フォーマットが必要な場合は Section 9 のフォーマットを併用してよい。
- 報告は「進捗管理チャットへそのまま貼れる」ことを前提とし、実装チャットの作業ログと混ぜない（Section 1・Section 2 参照）。

---

## 11. allow-guard 許可範囲の拡張（2026-07-21・PR #158 記録）

承認ゲート付き開発フローの基盤として、`.claude/hooks/allow-guard.sh` に「安全な Git／GitHub 操作」を追加した開発運用・安全基盤の改善記録。**これは application の Phase 完了実績ではなく、また DB 変更（migration）でもない。** DB／SQL／RPC／application（HTML）は一切変更していない。

### 目的
- 承認ゲート付き開発フローのために、危険操作は遮断したまま、read-only 情報取得と「安全な条件を満たしたときだけの Git 操作」を Claude Code の Bash tool から実行できるようにする。

### Git / PR
- PR #158「Expand allow-guard for safe workflow operations」（state: MERGED・Merge commit 方式）。
- implementation commit `d006e0402dc1482b60f8e6fbc27a06c6013e4440`。
- merge commit `1e8758f1130dfaea84b46ac7173ca1a5e97cfcb1`。
- mergedAt `2026-07-21T06:03:19Z`。
- 変更ファイルは 2 つのみ：`.claude/hooks/allow-guard.sh` / `.claude/hooks/test-allow-guard.sh`（341 insertions / 4 deletions）。

### 追加した安全な許可
- `git branch --show-current` / `git branch --list` / `git branch -r`（read-only のみ）。
- `gh pr list --state open --json number,title,headRefName`（この 1 形式の完全一致のみ）。
- `gh pr view --json` の read-only field 拡張（`headRefOid` / `mergedAt` / `mergeCommit` / `reviewDecision` を追加。未知 field が 1 つでも含まれれば拒否）。
- 条件付き `git switch -c <feature|fix|docs|chore>/<name>`（現在 branch が main・working tree clean・local HEAD == origin/main・同名の local/remote branch なし・branch 名の厳格検証を満たしたときのみ）。
- `git switch main`（working tree clean のときのみ）。
- `git fetch --prune origin`（完全一致のみ）。
- `git pull --ff-only origin main`（main 上・clean のときのみ）。

### 引き続き禁止している危険操作（変更なし）
- `gh pr merge` / `git merge` / `git rebase` / `git reset` / force push / `git commit --amend`。
- main への直接 `git add` / `commit` / `push`。
- 任意の `gh api` / 任意スクリプト実行 / `supabase` / `psql`。
- shell metacharacter（パイプ・リダイレクト・`;`・`&&`・`||`・`$()` 等）を含むコマンド。
- `git checkout -b` / `git switch -C` / `--create`、branch の削除・改名・作成（`git branch <name>` 等）。

### テスト・レビュー
- allow-guard テスト：total 206 / pass 206 / fail 0（ユーザーが `bash .claude/hooks/test-allow-guard.sh` を実行して確認）。
- security review（read-only）：critical 0 / high 0（medium/low の指摘はいずれも既存の `git check-ref-format` や前段の fail-closed ゲートで実害なしと確認・任意ハードニングは未適用）。
- test evidence review（read-only）：全確認合格。
- 新 hook 経由の branch 作成 実地確認：`git switch -c docs/allow-guard-workflow-improvements-record` が main／clean／同期済み／許可 prefix／同名 branch なしの条件を満たして**成功**。

### 状態と次工程
- **custom command は未実装**（今回は allow-guard の許可範囲拡張のみ）。`.claude/commands/` は作成していない。
- 次工程：承認ゲート付き開発フロー全体を、ユーザー・ChatGPT・Claude の 3 者で検討し、仕様合意後に custom command の MVP へ進む（下記 Section 12）。

---

## 12. Codex主体の役割・承認・実行手順（2026-09-10承認）

### 役割

- 岡井さんは業務要件、優先順位、使い勝手、Preview／本番確認、承認が必要な重要判断を担当する。
- Codexは調査、仕様案、実装、検証、自己修正、記録まで完結する。判断根拠と未確認事項を示し、必要な独立レビューの対象を絞る。
- Claudeは必要箇所の独立レビューを担当する。対象差分・仕様・証拠について、重要度、具体的な箇所、影響、解消案を返す。全文の再調査や毎工程の中継、恒常的な実装担当にはしない。Codexは指摘を検証し、修正・再確認・採否の記録まで担当する。
- 独立レビューを依頼する判断材料は、セキュリティ境界、データ損失の可能性、大きな設計判断、自己点検で解消できない不確実性。毎回の3者合意を開始条件にはしない。個別仕様で明示された独立レビュー条件は省略しない。

### 承認の扱い

- 合意済みの目的・範囲・制約内では、技術判断、必要な修正、検証、記録を継続する。同じ承認を岡井さんへ繰り返し求めない。「続けて」は直前の合意範囲を引き継ぎ、未承認の操作へ拡大しない。
- 範囲追加、製品仕様／承認基準の変更、取り返しのつかない操作、実DB・実バックアップ・公開・認証やOrca設定の変更は、その操作まで既存承認に含まれるか確認する。含まれない場合、根拠・影響・推奨案を具体化し、不足分をまとめて一度に確認する。
- stage・commit・push・PR作成・branch変更等は、当該Git操作を含む明示承認が必要。コード／文書編集の承認だけで実行しない。mergeは第14節に従う。DB変更・SQL実行は岡井さんが行い、Codex／Claudeは実行しない。
- sandbox・hook・OSのアクセス制御は承認とは別に適用される。拒否時は操作と理由を記録し、正規のワークスペース選択や許可手続きを使う。管理者実行、ACL／所有者変更、保護無効化、別手段による迂回はしない。

### 作業の進め方

1. 本書、現在の本流・仕様、承認範囲を確認し、HEAD・差分・他の実行中作業を確認する。既存の未コミット変更を保全し、同時実装は第2節の1件を守る。
2. Codexが影響、既存の呼出元、代替案を調べ、仕様との照合と実施方針を示す。範囲内の工程切替で再承認を待たない。
3. 承認範囲だけを実装し、変更に適した検証を行う。既存の有効な証拠で確認できる項目は再実行せず、変更・失敗・不足がある項目に絞る。
4. Codexが差分、仕様、秘密情報の混入、既存機能への影響、文書参照を自己点検する。必要な箇所だけClaudeの独立レビューを受け、指摘の解消を確認する。
5. 第7節の記録先へ結果・証拠・未確認事項を残し、第9・10節に沿って報告する。未承認のGit操作、DB、公開等へ進まない。

### 機密資産と既存コマンド

- 機密資産の入力・出力・一時保存と利用例は [機密資産の外部保管](private-assets-local-usage.md) を参照する。Orcaの通常作業フォルダや一般読取り対象に機密保管先を追加しない。秘密本文・パスワード・接続トークンをログ、差分、報告へ出さない。
- `/okg-go`は旧実装機能を停止し、ClaudeのType 1限定read-onlyレビュー入口へ変更した。`/okg-status`はread-onlyの状態報告をCodexへ返す。両commandに編集・Git変更の権限はない。通常のCodex作業は本書に従い、commandをCodexの自動実行基盤とは扱わない。hook・settingsは変更していない。

---

## 13. custom command `/okg-status` 追加（2026-07-21・PR #160 記録）

承認ゲート付き開発フロー MVP の第 1 弾として、read-only の工程ステータス報告コマンド `/okg-status` を追加した開発運用・安全基盤の記録。**application の Phase 完了実績ではなく、DB 変更（migration）でもない。** application HTML／SQL／RPC／DB／allow-guard／settings は変更していない。

### Git / PR
- PR #160「Add read-only okg status command」（state: MERGED・Merge commit 方式）。
- implementation commit `bee14337686b645530be330208ab9e0531052bf6`。
- merge commit `94ec9557c41705b9dafe7523d10de598ad72b17d`。
- mergedAt `2026-07-21T07:27:13Z`。
- 追加ファイルは 1 つのみ：`.claude/commands/okg-status.md`。

### 実装内容
- Git／PR／checks／工程状態を **read-only** で収集し、決定ブロック（結論→推奨→決めてほしいこと→リスク→状態→停止条件→証拠）を先頭固定で短く報告する。
- 引数なし（現状把握）と PR 番号指定に対応。PR 番号は `^[0-9]+$`（数字のみ）を検証し、不正時は GitHub コマンドを実行せず停止。
- Claude の推奨は示すが、**merge 可否・Phase 完了などの最終判断は行わず ChatGPT とユーザーへ返す**。
- write 操作・merge・DB 操作を行わない。secret／PIN／token／UUID／氏名／本番データを出力しない（commit hash・PR 番号・URL のみ可）。

### 実運用確認（2026-07-21）
- 引数なし：main・clean・main=origin/main・open PR 0 の待機状態を正しく判定。
- `/okg-status 160`：PR #160 の MERGED・head commit・merge commit・mergedAt・Vercel checks SUCCESS を取得し、merge commit と main HEAD の一致を確認。

### レビュー
- security review（read-only）：critical 0 / high 0（medium/low の指摘は allow-guard による二重防御・doc クリア化で対応済み）。
- test-evidence review（read-only）：全確認合格。read-only 保証を確認済み。

### 状態と次工程
- `/okg-status`：**実装・merge・実運用確認 完了**。
- **`/okg-go` は未実装。`/okg-closeout` は未実装。**
- 次工程：3 者合意（Section 12）のうえ、Type 1（frontend-only）専用の `/okg-go` の仕様検討へ進む。

---

## 14. オーナー目的とType 1 frontend-only運用ルール（恒久）

### オーナー目的と要望の扱い（恒久・全作業に適用）
- オーナーの目的は「**岡井組にとって総合的にプラスになる社内業務システムを作ること**」。
- 画面要望は目的ではなく、その**手段・入口**である。字義どおりに追認しない。
- Codexは各要望について、**業務効率・社員/管理者/経営者の負担・安全性・信頼性・保守性・費用対効果・過剰実装・代替案**を評価し、必要箇所の独立レビューは第12節に従う。
- より良い案があれば**理由とともに提示**する。承認済み範囲内の判断はCodexが進め、範囲や仕様の重要変更は第12節に従う。
- Claude の私的 memory 領域は補助情報に過ぎず、**正式な根拠はリポジトリ内文書（本ファイル等）**とする。

### CodexのType 1実装とClaudeのレビュー入口
- この工程と `/okg-go` のレビューは **Type 1 frontend-only 専用**（対象例: 表示・文言・CSS・レイアウト・スマホ対応・ボタン・モーダル・カレンダー等）。DB/SQL/RPC/RLS/認証/session/PIN/allow-guard/settings/migration/データ削除等は対象外で、判明したら変更せず停止する。
- 承認済み仕様を入力とし、**preflight → branch → 調査 → Type1/価値確認 → 実装 → 3レビュー（frontend-design・security・test-evidence 必須）→ commit → push → PR作成 → checks → merge判断報告** を品質上の工程とする。Codexが実装と3観点の自己点検を担当し、Claudeの独立レビューは第12節の必要箇所に限定する。Git／PR操作はその操作の承認がある場合だけ実行し、**PR 作成と merge判断報告までで停止**する。`/okg-go`自体は実装・Git操作を行わず、必要な独立レビューのみを返す。
- **merge判断報告 18 項目**（結論／岡井組への効果／推奨と理由／仕様の項目別照合／変更内容／変更していない範囲／既存機能への影響／frontend-design・security・test-evidence 各 review／static・自動テスト／Vercel checks／残存リスク／未確認事項／Preview 確認項目／復旧方法／branch・commit・PR・base・head 整合性／決めてほしいこと）を必須出力する。仕様照合は「実装済み/未実装/変更あり/対象外/確認不能」で分類し、未実装・変更あり・確認不能があれば先頭で明示する。

### Type 1固有の実装前提と修正制限（旧commandから移管）
- 新規Type 1実装の開始前提はmain・clean・競合なし・open PR 0・ahead/divergeなし、合意BASEとorigin/mainの一致、予定branch名の重複なし。dirtyな差分の読取りレビューにはcleanを要求しない。前提不一致を自動で片付けず、現在の変更を保全する。
- fetch・pull・branch作成も第12節の明示承認が必要。tracking refの読取りだけでは最新同期を保証しない。
- 自己修正はreviewerがmust-fixと明示し、合意ファイル・仕様内、局所的、業務仕様を変更しない場合に限り最大2回。severityだけで機械判断しない。medium/lowは自動修正せず報告する。
- critical/high未解消、仕様外must-fix、2回で未解消、reviewer間の重大矛盾は停止して根拠と対応案を示す。必要な独立レビューが得られなければ未確認として報告する。旧command固有のSkill／subagent起動必須は廃し、3観点の品質確認は維持する。

### merge の分離（恒久）
- **Claudeはmergeコマンドを提示も実行もしない。Codexもmergeを実行しない。** Codexは証拠に基づく推奨を示し、最終承認と実行は岡井さんが行う。
- 流れ: Codexがmerge判断報告 → 必要箇所の独立レビューと指摘解消 → 岡井さんのPreview確認・承認 → Codexが対象を限定した実行1行を提示 → 岡井さんが実行。品質基準と人による実行の分離は維持する。
