# 作業ルール・進捗管理ルール（workflow-rules）

作成日：2026-06-13
対象：社内業務システムプロジェクト全体
状態：恒久ルール（特定フェーズ専用ではなく、プロジェクトが続く限り継続適用する）

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

以下のタイミングでは、CLIは作業を進める前に進捗管理チャットへ貼るための報告を出すこと。

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

明示指示がない限り、以下を行わない。

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

## 12. 次工程の仕様決定ルール（3 者合意）

開発フロー自動化（custom command 等）の仕様は、以下のルールで決定する。実装は仕様合意後に開始する。

- 仕様は**ユーザー・ChatGPT・Claude の 3 者**で決定する。
- ChatGPT と Claude は**それぞれ独立に**、要望整理・仕様案・工程判断・リスク判断・代替案を検討する。
- Claude は ChatGPT 案を**単に追認せず**、相違点・反対意見・見落としを明示的に提示する。
- 3 者の認識が揃うまで**実装を開始しない**。
- Claude の検討結果・成果は**ChatGPT へ貼り戻す**（Claude 自身が最終判断しない）。
- ユーザーは主に業務要件・使い勝手・優先順位・Preview／本番確認を担当する。

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

## 14. オーナー目的と `/okg-go`（Type 1 frontend-only）運用ルール（恒久）

### オーナー目的と要望の扱い（恒久・全作業に適用）
- オーナーの目的は「**岡井組にとって総合的にプラスになる社内業務システムを作ること**」。
- 画面要望は目的ではなく、その**手段・入口**である。字義どおりに追認しない。
- ChatGPT と Claude は各要望について、**業務効率・社員/管理者/経営者の負担・安全性・信頼性・保守性・費用対効果・過剰実装・代替案**を独立に評価する。
- より良い案があれば**理由とともに提示**する。ただし **3 者合意（ユーザー・ChatGPT・Claude）までは実装しない**。
- Claude の私的 memory 領域は補助情報に過ぎず、**正式な根拠はリポジトリ内文書（本ファイル等）**とする。

### `/okg-go` の責務と境界
- `/okg-go` は **Type 1 frontend-only 専用**（対象例: 表示・文言・CSS・レイアウト・スマホ対応・ボタン・モーダル・カレンダー等）。DB/SQL/RPC/RLS/認証/session/PIN/allow-guard/settings/migration/データ削除等は対象外で、判明したら変更せず停止する。
- 3 者合意済み仕様を入力とし、**preflight → branch → 調査 → Type1/価値確認 → 実装 → 3レビュー（frontend-design・security・test-evidence 必須）→ commit → push → PR作成 → checks → merge判断報告** まで行い、**PR 作成と merge判断報告までで停止**する。
- **merge判断報告 18 項目**（結論／岡井組への効果／推奨と理由／仕様の項目別照合／変更内容／変更していない範囲／既存機能への影響／frontend-design・security・test-evidence 各 review／static・自動テスト／Vercel checks／残存リスク／未確認事項／Preview 確認項目／復旧方法／branch・commit・PR・base・head 整合性／決めてほしいこと）を必須出力する。仕様照合は「実装済み/未実装/変更あり/対象外/確認不能」で分類し、未実装・変更あり・確認不能があれば先頭で明示する。

### merge の分離（恒久）
- **Claude は merge コマンドを提示も実行もしない。** merge の最終判断は ChatGPT とユーザーが行う。
- 流れ: Claude が merge判断報告 → ChatGPT 確認 → ユーザー Preview 確認 → ChatGPT が可と判断した場合のみ実行 1 行を提示 → ユーザーが実行。
