#!/usr/bin/env bash
# .claude/hooks/test-allow-guard.sh
#
# allow-guard.sh の判定を、実際の git add/commit/push/PR作成を一切行わずに検証する
# 模擬テスト。hook へ標準入力で模擬 JSON を渡し、exit code のみを検証する。
#   exit 0 = 許可(allow) / exit 2 = 拒否(deny)
#
# current branch / staged は環境変数 ALLOW_GUARD_TEST_BRANCH /
# ALLOW_GUARD_TEST_STAGED で注入する。これらは Claude Code の Bash ツール経由では
# 設定できない(VAR=val cmd 形式が allowlist で拒否される)ため、通常実行時には
# テスト注入が効かない安全設計になっている。
#
# 1件でも想定と異なれば非0で終了する。全件一致なら件数と「すべて想定どおり」を表示。

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/allow-guard.sh"

if [ ! -f "$HOOK" ]; then
  echo "allow-guard.sh が見つかりません: $HOOK" >&2
  exit 1
fi

FEAT="feature/test-branch"
DEF_STAGED="docs/example.sql"

total=0
pass=0
fail=0

# JSON 文字列を組み立てる(backslash と doublequote を JSON エスケープ)
mkjson() {
  local cmd="$1"
  local esc="${cmd//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$esc"
}

# check <expect allow|deny> <branch> <staged> <cmd>
check() {
  local expect="$1" branch="$2" staged="$3" cmd="$4"
  local json code got
  json="$(mkjson "$cmd")"
  total=$((total + 1))
  printf '%s' "$json" | env ALLOW_GUARD_TEST_BRANCH="$branch" ALLOW_GUARD_TEST_STAGED="$staged" bash "$HOOK" >/dev/null 2>&1
  code=$?
  if [ "$code" -eq 0 ]; then got="allow"; else got="deny"; fi
  if [ "$got" = "$expect" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "MISMATCH expected=$expect got=$got (exit=$code) branch=[$branch] staged=[$staged] cmd=[$cmd]" >&2
  fi
}

# check_raw <expect> <branch> <staged> <raw-json>
# 改行/CR など JSON エスケープを厳密に指定したいケース用。
check_raw() {
  local expect="$1" branch="$2" staged="$3" json="$4"
  local code got
  total=$((total + 1))
  printf '%s' "$json" | env ALLOW_GUARD_TEST_BRANCH="$branch" ALLOW_GUARD_TEST_STAGED="$staged" bash "$HOOK" >/dev/null 2>&1
  code=$?
  if [ "$code" -eq 0 ]; then got="allow"; else got="deny"; fi
  if [ "$got" = "$expect" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "MISMATCH(raw) expected=$expect got=$got (exit=$code) branch=[$branch] json=[$json]" >&2
  fi
}

# check_state <expect> <branch> <clean> <sync> <local_refs> <remote_refs> <cmd>
# branch 作成 / main 同期系のように repo 状態に依存する判定を検証する。
# clean = clean|dirty / sync = sync|ahead|behind|nosync / *_refs = 空白区切り既存 branch 名。
check_state() {
  local expect="$1" branch="$2" clean="$3" sync="$4" lrefs="$5" rrefs="$6" cmd="$7"
  local json code got
  json="$(mkjson "$cmd")"
  total=$((total + 1))
  printf '%s' "$json" | env \
    ALLOW_GUARD_TEST_BRANCH="$branch" \
    ALLOW_GUARD_TEST_STAGED="$DEF_STAGED" \
    ALLOW_GUARD_TEST_CLEAN="$clean" \
    ALLOW_GUARD_TEST_SYNC="$sync" \
    ALLOW_GUARD_TEST_LOCAL_REFS="$lrefs" \
    ALLOW_GUARD_TEST_REMOTE_REFS="$rrefs" \
    bash "$HOOK" >/dev/null 2>&1
  code=$?
  if [ "$code" -eq 0 ]; then got="allow"; else got="deny"; fi
  if [ "$got" = "$expect" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "MISMATCH(state) expected=$expect got=$got (exit=$code) branch=[$branch] clean=[$clean] sync=[$sync] lrefs=[$lrefs] rrefs=[$rrefs] cmd=[$cmd]" >&2
  fi
}

# ===== ALLOW: read-only(ブランチ非依存) =====
check allow "$FEAT" "$DEF_STAGED" 'git status'
check allow "main" "$DEF_STAGED" 'git status'
check allow "master" "$DEF_STAGED" 'git status'
check allow "" "$DEF_STAGED" 'git status'
check allow "$FEAT" "$DEF_STAGED" 'git diff'
check allow "$FEAT" "$DEF_STAGED" 'git log'
check allow "$FEAT" "$DEF_STAGED" 'git log --oneline -5'
check allow "$FEAT" "$DEF_STAGED" 'git diff --stat'
check allow "$FEAT" "$DEF_STAGED" 'pwd'
check allow "$FEAT" "$DEF_STAGED" 'npm test'
check allow "$FEAT" "$DEF_STAGED" 'npm run lint'
check allow "$FEAT" "$DEF_STAGED" 'ls -la .claude'
check allow "$FEAT" "$DEF_STAGED" 'cat docs/example.sql'
check allow "$FEAT" "$DEF_STAGED" 'grep -n foo docs/example.sql'

# ===== ALLOW: 非main ブランチでの書込み系 =====
check allow "$FEAT" "$DEF_STAGED" 'git add docs/example.sql'
check allow "$FEAT" "$DEF_STAGED" 'git add admin-app.html docs/example.sql'
check allow "$FEAT" "$DEF_STAGED" 'git add docs/example.sql admin-app.html index.html'
check allow "$FEAT" "$DEF_STAGED" 'git commit -m "docs: test message"'
check allow "$FEAT" "$DEF_STAGED" "git commit -m 'single quote message'"
check allow "$FEAT" "$DEF_STAGED" 'git push -u origin feature/test-branch'
check allow "$FEAT" "$DEF_STAGED" 'gh pr create --base main --head feature/test-branch --fill'

# ===== 回帰: JSON fallback(jq非搭載)で二重引用符メッセージが切り詰められない =====
# \" を含む command が最初の \" で切れて validator に落ちないことを保証する。
check allow "$FEAT" "$DEF_STAGED" 'git commit -m "fix: adjust companies RPC"'
check allow "$FEAT" "$DEF_STAGED" 'git commit -m "update docs/db-migrations.md record"'

# ===== ALLOW: gh 読み取り系(ブランチ非依存) =====
check allow "$FEAT" "$DEF_STAGED" 'gh pr view'
check allow "main" "$DEF_STAGED" 'gh pr view'
check allow "$FEAT" "$DEF_STAGED" 'gh pr view 100'
check allow "$FEAT" "$DEF_STAGED" 'gh pr view 100 --json state,mergeable,statusCheckRollup,url'
check allow "$FEAT" "$DEF_STAGED" 'gh pr view 100 --json headRefName,baseRefName,title,number'
check allow "$FEAT" "$DEF_STAGED" 'gh pr view 99 --json state'
check allow "$FEAT" "$DEF_STAGED" 'gh pr checks'
check allow "main" "$DEF_STAGED" 'gh pr checks'
check allow "$FEAT" "$DEF_STAGED" 'gh pr checks 100'

# ===== DENY: main/master/detached での書込み系 =====
check deny "main" "$DEF_STAGED" 'git add docs/example.sql'
check deny "main" "$DEF_STAGED" 'git commit -m "docs: test message"'
check deny "main" "$DEF_STAGED" 'git push -u origin main'
check deny "main" "$DEF_STAGED" 'gh pr create --base main --head main --fill'
check deny "master" "$DEF_STAGED" 'git add docs/example.sql'
check deny "master" "$DEF_STAGED" 'git commit -m "docs: test message"'
check deny "master" "$DEF_STAGED" 'git push -u origin master'
check deny "master" "$DEF_STAGED" 'gh pr create --base main --head master --fill'
check deny "" "$DEF_STAGED" 'git add docs/example.sql'
check deny "" "$DEF_STAGED" 'git commit -m "docs: test message"'
check deny "" "$DEF_STAGED" 'git push -u origin feature/test-branch'
check deny "" "$DEF_STAGED" 'gh pr create --base main --head feature/test-branch --fill'

# ===== DENY: git add の危険な引数 =====
check deny "$FEAT" "$DEF_STAGED" 'git add .'
check deny "$FEAT" "$DEF_STAGED" 'git add -A'
check deny "$FEAT" "$DEF_STAGED" 'git add --all'
check deny "$FEAT" "$DEF_STAGED" 'git add -a'
check deny "$FEAT" "$DEF_STAGED" 'git add -p docs/example.sql'
check deny "$FEAT" "$DEF_STAGED" 'git add ../x'
check deny "$FEAT" "$DEF_STAGED" 'git add docs/../secret'
check deny "$FEAT" "$DEF_STAGED" 'git add C:/x'
check deny "$FEAT" "$DEF_STAGED" 'git add /etc/passwd'
check deny "$FEAT" "$DEF_STAGED" 'git add "*.sql"'
check deny "$FEAT" "$DEF_STAGED" 'git add docs/*.sql'
check deny "$FEAT" "$DEF_STAGED" 'git add .env'
check deny "$FEAT" "$DEF_STAGED" 'git add .ENV'
check deny "$FEAT" "$DEF_STAGED" 'git add .env.local'
check deny "$FEAT" "$DEF_STAGED" 'git add .claude/settings.local.json'
check deny "$FEAT" "$DEF_STAGED" 'git add .git/config'
check deny "$FEAT" "$DEF_STAGED" 'git add node_modules/x'
check deny "$FEAT" "$DEF_STAGED" 'git add :(exclude)foo'
check deny "$FEAT" "$DEF_STAGED" 'git add'
check deny "$FEAT" "$DEF_STAGED" 'git add ..'

# ===== DENY: git commit の不正形式 / staged 条件 =====
check deny "$FEAT" "$DEF_STAGED" 'git commit -a'
check deny "$FEAT" "$DEF_STAGED" 'git commit --amend'
check deny "$FEAT" "$DEF_STAGED" 'git commit -m a -m b'
check deny "$FEAT" "$DEF_STAGED" 'git commit -F msg.txt'
check deny "$FEAT" "$DEF_STAGED" 'git commit -am "x"'
check deny "$FEAT" "$DEF_STAGED" 'git commit --no-verify -m "x"'
check deny "$FEAT" "$DEF_STAGED" 'git commit -m ""'
check deny "$FEAT" "$DEF_STAGED" 'git commit'
check deny "$FEAT" "" 'git commit -m "docs: test message"'
check deny "$FEAT" ".env" 'git commit -m "docs: test message"'
check deny "$FEAT" ".claude/settings.local.json" 'git commit -m "docs: test message"'
check deny "$FEAT" "$DEF_STAGED" 'git commit -m "$(whoami)"'

# ===== DENY: git push の不正形式 =====
check deny "$FEAT" "$DEF_STAGED" 'git push --force'
check deny "$FEAT" "$DEF_STAGED" 'git push --force origin feature/test-branch'
check deny "$FEAT" "$DEF_STAGED" 'git push -f -u origin feature/test-branch'
check deny "$FEAT" "$DEF_STAGED" 'git push origin HEAD:main'
check deny "$FEAT" "$DEF_STAGED" 'git push -u origin main'
check deny "$FEAT" "$DEF_STAGED" 'git push -u upstream feature/test-branch'
check deny "$FEAT" "$DEF_STAGED" 'git push -u origin feature/other'
check deny "$FEAT" "$DEF_STAGED" 'git push'
check deny "$FEAT" "$DEF_STAGED" 'git push -u origin feature/test-branch --force'
check deny "$FEAT" "$DEF_STAGED" 'git push --mirror'
check deny "$FEAT" "$DEF_STAGED" 'git push --all'

# ===== DENY: gh の禁止サブコマンド / 不正形式 =====
check deny "$FEAT" "$DEF_STAGED" 'gh pr merge'
check deny "$FEAT" "$DEF_STAGED" 'gh pr merge 100'
check deny "$FEAT" "$DEF_STAGED" 'gh pr close'
check deny "$FEAT" "$DEF_STAGED" 'gh pr close 100'
check deny "$FEAT" "$DEF_STAGED" 'gh pr edit'
check deny "$FEAT" "$DEF_STAGED" 'gh pr edit 100 --title x'
check deny "$FEAT" "$DEF_STAGED" 'gh api'
check deny "$FEAT" "$DEF_STAGED" 'gh api repos/owner/repo'
check deny "$FEAT" "$DEF_STAGED" 'gh pr create --base main --head feature/other --fill'
check deny "$FEAT" "$DEF_STAGED" 'gh pr create --base develop --head feature/test-branch --fill'
check deny "$FEAT" "$DEF_STAGED" 'gh pr create --base main --head feature/test-branch --fill --draft'
check deny "$FEAT" "$DEF_STAGED" 'gh pr create --base main --head feature/test-branch'
check deny "$FEAT" "$DEF_STAGED" 'gh pr view 100 --json password'
check deny "$FEAT" "$DEF_STAGED" 'gh pr view 100 --json state,secret'
check deny "$FEAT" "$DEF_STAGED" 'gh pr view --json state'
check deny "$FEAT" "$DEF_STAGED" 'gh pr view abc'
check deny "$FEAT" "$DEF_STAGED" 'gh pr diff'
check deny "$FEAT" "$DEF_STAGED" 'gh repo list'
check deny "$FEAT" "$DEF_STAGED" 'gh pr checks 100 --watch'
check deny "$FEAT" "$DEF_STAGED" 'gh'

# ===== DENY: シェル連結 / パイプ / リダイレクト / サブシェル =====
check deny "$FEAT" "$DEF_STAGED" 'git status; rm -rf /'
check deny "$FEAT" "$DEF_STAGED" 'git status && rm -rf /'
check deny "$FEAT" "$DEF_STAGED" 'git status || echo x'
check deny "$FEAT" "$DEF_STAGED" 'git status | grep x'
check deny "$FEAT" "$DEF_STAGED" 'git status &'
check deny "$FEAT" "$DEF_STAGED" 'git add docs/(x)'
check deny "$FEAT" "$DEF_STAGED" 'git add $(whoami)'
check deny "$FEAT" "$DEF_STAGED" 'git commit -m "x`whoami`"'

# 改行(LF) / CR 埋め込み(JSON エスケープを厳密に指定)
check_raw deny "$FEAT" "$DEF_STAGED" '{"tool_name":"Bash","tool_input":{"command":"git status\ngit push -u origin main"}}'
check_raw deny "$FEAT" "$DEF_STAGED" '{"tool_name":"Bash","tool_input":{"command":"git status\rgit push -u origin main"}}'
# リダイレクトは Bash 危険構文としても拒否
check_raw deny "$FEAT" "$DEF_STAGED" '{"tool_name":"Bash","tool_input":{"command":"git log > out.txt"}}'

# ===== DENY: git/gh の迂回(絶対パス・command・env・-c・エスケープ) =====
check deny "$FEAT" "$DEF_STAGED" '/usr/bin/git status'
check deny "$FEAT" "$DEF_STAGED" '/usr/bin/git commit -m "x"'
check deny "$FEAT" "$DEF_STAGED" 'command git status'
check deny "$FEAT" "$DEF_STAGED" 'env git status'
check deny "$FEAT" "$DEF_STAGED" 'git -c alias.x=commit x'
check deny "$FEAT" "$DEF_STAGED" 'git -c core.pager=cat log'
check deny "$FEAT" "$DEF_STAGED" '\git status'
check deny "$FEAT" "$DEF_STAGED" 'gitx status'
check deny "$FEAT" "$DEF_STAGED" 'ghx pr view'

# ===== DENY: DB / その他禁止コマンド =====
check deny "$FEAT" "$DEF_STAGED" 'supabase db push'
check deny "$FEAT" "$DEF_STAGED" 'psql -c "select 1"'
check deny "$FEAT" "$DEF_STAGED" 'find . -name x'
check deny "$FEAT" "$DEF_STAGED" 'npm install'
check deny "$FEAT" "$DEF_STAGED" 'rm -rf docs'

# =====================================================================
# 追加(workflow improvements): 読み取り拡張 / 安全な branch 作成・main 同期
# =====================================================================

# ----- ALLOW: git branch 読み取り -----
check allow "$FEAT" "$DEF_STAGED" 'git branch --show-current'
check allow "main" "$DEF_STAGED" 'git branch --show-current'
check allow "$FEAT" "$DEF_STAGED" 'git branch --list'
check allow "$FEAT" "$DEF_STAGED" 'git branch -r'

# ----- ALLOW: gh pr list(完全一致) -----
check allow "$FEAT" "$DEF_STAGED" 'gh pr list --state open --json number,title,headRefName'

# ----- ALLOW: gh pr view の拡張 field -----
check allow "$FEAT" "$DEF_STAGED" 'gh pr view 100 --json headRefOid'
check allow "$FEAT" "$DEF_STAGED" 'gh pr view 100 --json mergedAt,mergeCommit,reviewDecision'
check allow "$FEAT" "$DEF_STAGED" 'gh pr view 100 --json state,mergeable,statusCheckRollup,url,headRefName,baseRefName,headRefOid,mergedAt,mergeCommit,reviewDecision'

# ----- ALLOW: 安全な branch 作成(clean・同期済み main から・各許可 prefix) -----
check_state allow "main" "clean" "sync" "" "" 'git switch -c feature/new-cal'
check_state allow "main" "clean" "sync" "" "" 'git switch -c fix/bug-1'
check_state allow "main" "clean" "sync" "" "" 'git switch -c docs/record-x'
check_state allow "main" "clean" "sync" "" "" 'git switch -c chore/cleanup'

# ----- ALLOW: main 切替(clean) / fetch / pull -----
check_state allow "$FEAT" "clean" "sync" "" "" 'git switch main'
check allow "$FEAT" "$DEF_STAGED" 'git fetch --prune origin'
check_state allow "main" "clean" "sync" "" "" 'git pull --ff-only origin main'

# ----- DENY: branch 作成の状態条件違反 -----
check_state deny "$FEAT" "clean" "sync"   "" "" 'git switch -c feature/x'   # 現在 branch が main でない
check_state deny "main" "dirty" "sync"    "" "" 'git switch -c feature/x'   # dirty
check_state deny "main" "clean" "ahead"   "" "" 'git switch -c feature/x'   # ahead
check_state deny "main" "clean" "behind"  "" "" 'git switch -c feature/x'   # behind
check_state deny "main" "clean" "nosync"  "" "" 'git switch -c feature/x'   # diverged/未同期
check_state deny "main" "clean" "sync" "feature/dup" "" 'git switch -c feature/dup'  # local に同名
check_state deny "main" "clean" "sync" "" "feature/dup" 'git switch -c feature/dup'  # remote に同名

# ----- DENY: branch 名の不正 -----
check_state deny "main" "clean" "sync" "" "" 'git switch -c bugfix/x'      # 許可外 prefix
check_state deny "main" "clean" "sync" "" "" 'git switch -c randombranch'  # prefix なし
check_state deny "main" "clean" "sync" "" "" 'git switch -c feature/'      # prefix 直後が空
check_state deny "main" "clean" "sync" "" "" 'git switch -c feature/a..b'  # ..
check_state deny "main" "clean" "sync" "" "" 'git switch -c feature/a@{0}' # @{
check_state deny "main" "clean" "sync" "" "" 'git switch -c feature/a//b'  # //
check_state deny "main" "clean" "sync" "" "" 'git switch -c feature/x.lock' # .lock
check_state deny "main" "clean" "sync" "" "" 'git switch -c feature/a b'   # 空白(5トークン)
check_state deny "main" "clean" "sync" "" "" 'git switch -c feature/a:b'   # 許可外文字 :
check_state deny "main" "clean" "sync" "" "" 'git switch -c feature/a*b'   # 許可外文字 *
check_state deny "main" "clean" "sync" "" "" 'git switch -c /feature/x'    # 先頭スラッシュ

# ----- DENY: 強制作成 / 別コマンド -----
check_state deny "main" "clean" "sync" "" "" 'git switch -C feature/x'
check_state deny "main" "clean" "sync" "" "" 'git switch --create feature/x'
check_state deny "main" "clean" "sync" "" "" 'git checkout -b feature/x'
check_state deny "main" "clean" "sync" "" "" 'git switch feature/other'
check_state deny "main" "clean" "sync" "" "" 'git switch -c main'

# ----- DENY: main 切替の dirty -----
check_state deny "$FEAT" "dirty" "sync" "" "" 'git switch main'

# ----- DENY: fetch の過剰許可 -----
check deny "$FEAT" "$DEF_STAGED" 'git fetch'
check deny "$FEAT" "$DEF_STAGED" 'git fetch origin'
check deny "$FEAT" "$DEF_STAGED" 'git fetch --all'
check deny "$FEAT" "$DEF_STAGED" 'git fetch --prune upstream'
check deny "$FEAT" "$DEF_STAGED" 'git fetch --prune origin --tags'
check deny "$FEAT" "$DEF_STAGED" 'git fetch --prune --force origin'

# ----- DENY: pull の過剰許可 / 条件違反 -----
check deny "main" "$DEF_STAGED" 'git pull'
check deny "main" "$DEF_STAGED" 'git pull origin main'
check deny "main" "$DEF_STAGED" 'git pull --rebase origin main'
check deny "main" "$DEF_STAGED" 'git pull --no-ff origin main'
check deny "main" "$DEF_STAGED" 'git pull --ff-only origin develop'
check_state deny "$FEAT" "clean" "sync" "" "" 'git pull --ff-only origin main'  # main 以外
check_state deny "main" "dirty" "sync" "" "" 'git pull --ff-only origin main'    # dirty

# ----- DENY: git branch の変更系 -----
check deny "$FEAT" "$DEF_STAGED" 'git branch -d feature/x'
check deny "$FEAT" "$DEF_STAGED" 'git branch -D feature/x'
check deny "$FEAT" "$DEF_STAGED" 'git branch -m a b'
check deny "$FEAT" "$DEF_STAGED" 'git branch --delete feature/x'
check deny "$FEAT" "$DEF_STAGED" 'git branch --set-upstream-to origin/main'
check deny "$FEAT" "$DEF_STAGED" 'git branch feature/x'
check deny "$FEAT" "$DEF_STAGED" 'git branch'

# ----- DENY: gh pr list の過剰許可 -----
check deny "$FEAT" "$DEF_STAGED" 'gh pr list'
check deny "$FEAT" "$DEF_STAGED" 'gh pr list --state closed --json number,title,headRefName'
check deny "$FEAT" "$DEF_STAGED" 'gh pr list --state open --json number,title,headRefName,body'
check deny "$FEAT" "$DEF_STAGED" 'gh pr list --state open --json number'
check deny "$FEAT" "$DEF_STAGED" 'gh pr list --state open --json number,title,headRefName --limit 5'
check deny "$FEAT" "$DEF_STAGED" 'gh pr list --state all --json number,title,headRefName'
check deny "$FEAT" "$DEF_STAGED" 'gh pr list --search foo --state open --json number,title,headRefName'

# ----- DENY: gh pr view の未許可 field / gh api 継続拒否 -----
check deny "$FEAT" "$DEF_STAGED" 'gh pr view 100 --json mergedBy'
check deny "$FEAT" "$DEF_STAGED" 'gh pr view 100 --json headRefOid,secret'
check deny "$FEAT" "$DEF_STAGED" 'gh api repos/owner/repo/commits/abc/status'

# ----- DENY: merge / rebase / reset / force push の継続拒否 -----
check deny "main" "$DEF_STAGED" 'git merge feature/x'
check deny "$FEAT" "$DEF_STAGED" 'git rebase main'
check deny "$FEAT" "$DEF_STAGED" 'git reset --hard origin/main'
check deny "$FEAT" "$DEF_STAGED" 'git stash'
check deny "$FEAT" "$DEF_STAGED" 'git push -u origin feature/test-branch --force'

echo "total=$total pass=$pass fail=$fail"
if [ "$fail" -eq 0 ]; then
  echo "すべて想定どおり (${total} 件)"
  exit 0
else
  echo "想定外 ${fail} 件を検出しました" >&2
  exit 1
fi
