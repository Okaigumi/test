---
description: 現在の Git / PR / checks / 工程状態を read-only で収集し、ChatGPT とユーザーが判断しやすい短い形式で報告する（write 操作なし・最終判断はしない）
argument-hint: "[PR番号(任意・整数のみ)]"
allowed-tools: Bash(git status:*), Bash(git branch --show-current), Bash(git branch --list), Bash(git branch -r), Bash(git log:*), Bash(git diff:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr checks:*)
---

# /okg-status — read-only 工程ステータス

あなたは岡井組システムの開発フローにおける **read-only の状態レポータ** です。
このコマンドは現在の Git / PR / checks / 工程状態を収集し、決められた短い形式で報告するだけです。
**write 操作・最終判断・merge 可否/Phase 完了の断定は絶対に行いません。**

引数（PR番号・任意）: `$ARGUMENTS`

---

## 0. 絶対の禁止事項（このコマンドは常に read-only）

以下は理由を問わず実行しない:
- ファイル変更 / `git add` / `git commit` / `git push`
- branch 作成・切替（`git switch` / `git checkout`）
- PR 作成・編集・close・merge（`gh pr create/edit/close/merge`）
- `git fetch` / `git pull` / `gh api` / script 実行
- DB 接続 / SQL / Supabase / Vercel 操作
- `reset` / `rebase` / `merge` / force push
- shell metacharacter を使った複合コマンド（`|` `>` `;` `&&` `||` `$()` 等）

使ってよいのは下記「§2 収集コマンド」の read-only 形式のみ（すべて allow-guard 許可済み）。

---

## 1. 引数（PR番号）の検証

1. `$ARGUMENTS` が空 → **引数なしモード**（§3-A）。
2. `$ARGUMENTS` が正規表現 `^[0-9]+$` に完全一致 → その整数を PR 番号として使用（§3-B）。
3. それ以外（記号・空白・複数トークン・非数値を含む）→ **GitHub コマンドを一切実行せず**、`## 停止条件` に「不正な PR 番号を受け取ったため中止」と記して停止。

未検証の値を shell へ渡さない。`eval` しない。値を展開してコマンド組み立てに使わない。PR 番号は上記検証を通った整数だけを、固定コマンド `gh pr view <整数>` / `gh pr checks <整数>` の末尾に置く。Bash ツール呼び出し時は、検証済み整数リテラルをコマンド末尾へ連結するだけとし、変数展開・`eval`・文字列再解釈をしない（`$ARGUMENTS` をそのままコマンド文字列へ差し込まない）。

---

## 2. 収集コマンド（read-only・allow-guard 許可形式のみ）

必要なものだけを順に実行する。1コマンド=1呼び出し（パイプ・リダイレクト・連結を使わない）。

Git:
- `git branch --show-current`
- `git log -1 --format=%H`
- `git log -1 --format=%H origin/main`
- `git status -sb`
- `git status --short`
- `git diff --name-only`
- `git diff --cached --name-only`
- `git diff --check`
- `git branch --list`（必要時）
- `git branch -r`（必要時）

GitHub:
- `gh pr list --state open --json number,title,headRefName`
- `gh pr view`（現在 branch の PR。無い場合は非ゼロで終了する＝「PRなし」）
- `gh pr view <整数> --json number,state,mergeable,reviewDecision,headRefName,baseRefName,headRefOid,statusCheckRollup,url,mergedAt,mergeCommit`
- `gh pr checks` / `gh pr checks <整数>`

注意: `git log -1 --format=%H origin/main` は remote-tracking ref の参照であり fetch は行わない（最後の fetch 時点の値）。ネットワーク同期はしない。

---

## 3. 収集の流れ

### 3-A. 引数なし
1. current branch / local HEAD / origin/main HEAD / `git status -sb`（ahead·behind・dirty）/ changed・staged files / `git diff --check` を取得。
2. current branch が `main` → `gh pr list --state open --json number,title,headRefName` を取得。open PR が空なら「PRなし」。
3. current branch が非 main → `gh pr view`（＋成功時 `gh pr view --json ...` と `gh pr checks`）で紐づく PR を取得。PR が無ければ「このbranchに紐づくPRなし」。

### 3-B. 引数あり（検証済み整数 N）
1. 3-A の Git 情報に加え、`gh pr view N --json ...` と `gh pr checks N` を取得。
2. PR が存在しない場合（コマンドが「見つからない」で終了）と、取得失敗（ネットワーク/権限等）を **区別**して報告する。

---

## 4. 工程状態の分類（事実からの推定）

収集した事実だけから、次のいずれかに分類する（推測で断定しない・不明は「判定不能／要確認」）:
- main待機中（main・clean・open PR 0）
- 実装中・未commit（非main・changed files あり・staged なし）
- staged済み・commit前（staged あり）
- commit済み・未push（`git status -sb` に `ahead` 表示・PR なし）
- push済み・PR未作成（remote に branch あり・PR なし）
- PR open・checks待ち（PR open・checks pending）
- PR open・checks成功（PR open・checks success）
- PR open・checks失敗（PR open・checks failure）
- merge済み・main未同期（PR merged・local main が origin/main より behind）
- main同期済み・closeout待ち（merged 後 main=origin/main・記録未確認）
- clean・完了候補（main・clean・関連 PR merged）
- 判定不能／要確認

**「完了」「merge してよい」等の最終判断は下さない。** 事実と Claude の推奨を示し、判断は ChatGPT とユーザーへ返す。

---

## 5. checks の表現

`statusCheckRollup` / `gh pr checks` から、各 context を `SUCCESS / PENDING / FAILURE / なし` に要約する（赤があれば明示）。長い JSON は転載せず、`context=state` の要点のみ。

---

## 6. 失敗・不明の扱い

- 取得に失敗したら推測で補完しない。当該項目は `unknown（確認不能）` と表示。
- 「PR/checks が存在しない」ことと「取得に失敗した」ことを区別する。
- detached HEAD・conflict（`git diff --check` の衝突マーカー・`UU` 等）を検出したら `## 重要なリスク` に警告。
- dirty のときは changed files 名を列挙してよいが、**ファイル内容本文は表示しない**。
- 判定不能なら安全側（停止を推奨）に倒す。

---

## 7. 出力形式（この順・先頭固定）

```markdown
## 結論
現在の状態を1〜2行で。

## Claudeの推奨
次に進む合理的な工程を平易に。最終判断は ChatGPT とユーザーへ返す。

## ChatGPTとユーザーに決めてほしいこと
判断が必要な事項だけ最大3件（なければ「特になし」）。

## 重要なリスク
重大なものだけ。なければ「特になし」。

## 現在の状態
- branch:
- HEAD:
- origin/main:
- working tree:
- PR:
- checks:
- 推定工程:

## 停止条件
確認できなかった事項・不一致・警告。なければ「なし」。

## 詳細証拠
必要な Git / PR 情報だけ（commit hash・PR番号・URL は可）。長いログは載せない。
```

### 出力ルール
- 結論を最初に出す。技術詳細を先頭に並べない。長いログを転載しない。
- token / PIN / UUID / メール / secret / 氏名 / 本番データを出さない。commit hash と PR 番号と PR URL は表示可。
- 「ユーザー判断待ち」で終わらせず、**Claude の推奨を必ず提示**する。ただし merge 可否・Phase 完了は Claude が最終決定しない。
- 最後に必ず: 「**この結果を ChatGPT へ貼り戻してください。**」と案内する。
- 報告は簡潔に。冗長な繰り返しをしない。
