#!/usr/bin/env bash
# .claude/hooks/allow-guard.sh
#
# 目的:
#   岡井組 社内業務システムの Claude Code / read-only 調査サブエージェント用ガード。
#   Bash は allowlist 方式。読み取り系コマンドに加え、非 main ブランチ上での
#   限定的な書込み系(git add/commit/push, gh pr create/view/checks)だけを、
#   厳格な形式検証を通ったものに限って許可する。
#   Read/Grep/Glob は秘密ファイル・危険パスへのアクセスを拒否する。
#
# 拒否方式:
#   exit 2 で拒否。理由は標準エラーに出す。stdout JSON方式とは混在させない。
#   解析不能・想定外は必ず拒否(fail-closed)。
#
# テスト用の注入について(重要):
#   current branch / staged 一覧は、環境変数 ALLOW_GUARD_TEST_BRANCH /
#   ALLOW_GUARD_TEST_STAGED が「セットされている場合のみ」その値を使う。
#   通常運用では、これらは未設定であり実 git から取得する。
#   Claude Code の Bash ツール経由では `VAR=val cmd` 形式の先頭トークンが
#   allowlist に無く拒否されるため、モデルはこれらの環境変数を注入できない。
#   よってテスト注入は外部テストハーネス(test-allow-guard.sh)専用であり、
#   通常実行時には効かない安全設計になっている。

set -euo pipefail

# find は Windows/Git Bash 環境で危険オプション(-delete/-exec/-fprint 等)の検出が不安定なため、
# Bash allowlist から除外する。ファイル探索が必要な場合は Glob ツールを使うこと。
ALLOWED_BASH=(git gh grep cat ls pwd wc head tail npm)

SECRET_PATH_RE='(^|/)(\.env|\.env\..*|secrets?)(/|$)|secret|credential|private[._-]*key|id_rsa|id_ed25519|settings\.local\.json'
DANGEROUS_PATH_RE='(^|[[:space:]])\.$|(^|[[:space:]])\./($|[[:space:]])|(^|[[:space:]])/|(^|[[:space:]])\.\.($|/|[[:space:]])|[*?[]'

LF=$'\n'
CR=$'\r'

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // .toolName // empty' 2>/dev/null || true)"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  read_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
  grep_path="$(printf '%s' "$input" | jq -r '.tool_input.path // empty' 2>/dev/null || true)"
  grep_glob="$(printf '%s' "$input" | jq -r '.tool_input.glob // empty' 2>/dev/null || true)"
  glob_pattern="$(printf '%s' "$input" | jq -r '.tool_input.pattern // empty' 2>/dev/null || true)"
else
  tool_name="$(printf '%s' "$input" | grep -oE '"tool_?name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/' | head -1 || true)"
  # command はメッセージ内に \" (エスケープ済み二重引用符) を含み得るため、
  # 単純な "[^"]*" では最初の \" で切り詰められてしまう。
  # JSON文字列(エスケープ対応)として抽出し、そのあと \" と \\ を復元する。
  cmd="$(printf '%s' "$input" | grep -oE '"command"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"' | head -1 | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)"
  cmd="${cmd//\\\"/\"}"
  cmd="${cmd//\\\\/\\}"
  read_path="$(printf '%s' "$input" | grep -oE '"(file_path|path)"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/' | head -1 || true)"
  grep_path="$read_path"
  grep_glob="$(printf '%s' "$input" | grep -oE '"glob"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/' | head -1 || true)"
  glob_pattern="$(printf '%s' "$input" | grep -oE '"pattern"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/' | head -1 || true)"
fi

deny() {
  echo "拒否(allow-guard): $1" >&2
  echo "tool=${tool_name:-unknown} command=${cmd:-}" >&2
  exit 2
}

check_secret_path() {
  local value="${1:-}"
  local label="${2:-path}"

  [ -z "$value" ] && return 0

  if printf '%s' "$value" | grep -qiE "$SECRET_PATH_RE"; then
    deny "${label} が秘密ファイル/秘密ディレクトリを指しています: $value"
  fi
}

check_dangerous_path() {
  local value="${1:-}"
  local label="${2:-path}"

  [ -z "$value" ] && return 0

  if printf '%s' "$value" | grep -qE "$DANGEROUS_PATH_RE"; then
    deny "${label} が広すぎる/危険なパス指定です: $value"
  fi
}

# ---- 書込み系 git / gh 用ヘルパー ----

# current branch を取得する。テスト注入(ALLOW_GUARD_TEST_BRANCH)がセット済みなら
# その値を使う(空文字なら detached とみなす)。未設定なら実 git から取得。
get_current_branch() {
  if [ -n "${ALLOW_GUARD_TEST_BRANCH+x}" ]; then
    printf '%s' "$ALLOW_GUARD_TEST_BRANCH"
  else
    git symbolic-ref --quiet --short HEAD 2>/dev/null || true
  fi
}

# staged ファイル一覧(改行区切り)を取得する。テスト注入(ALLOW_GUARD_TEST_STAGED)が
# セット済みならその値を使う。未設定なら実 git から取得。
get_staged_files() {
  if [ -n "${ALLOW_GUARD_TEST_STAGED+x}" ]; then
    printf '%s' "$ALLOW_GUARD_TEST_STAGED"
  else
    git diff --cached --name-only 2>/dev/null || true
  fi
}

# working tree の状態を返す("clean" / それ以外は "dirty")。
# テスト注入(ALLOW_GUARD_TEST_CLEAN)がセット済みならその値を使う。未設定なら実 git。
# 取得不能・想定外は "dirty" として fail-closed に倒す。
get_worktree_state() {
  if [ -n "${ALLOW_GUARD_TEST_CLEAN+x}" ]; then
    printf '%s' "$ALLOW_GUARD_TEST_CLEAN"
  else
    local st
    st="$(git status --porcelain 2>/dev/null || printf '__ERR__')"
    if [ "$st" = "__ERR__" ]; then
      printf 'dirty'
    elif [ -z "$st" ]; then
      printf 'clean'
    else
      printf 'dirty'
    fi
  fi
}

# local HEAD と origin/main の同期状態を返す("sync" なら完全一致、それ以外は "nosync")。
# テスト注入(ALLOW_GUARD_TEST_SYNC)がセット済みならその値を使う。未設定なら実 git。
# 片方でも取得できなければ "nosync" として fail-closed に倒す。
get_main_sync_state() {
  if [ -n "${ALLOW_GUARD_TEST_SYNC+x}" ]; then
    printf '%s' "$ALLOW_GUARD_TEST_SYNC"
  else
    local head origin
    head="$(git rev-parse --verify --quiet HEAD 2>/dev/null || true)"
    origin="$(git rev-parse --verify --quiet refs/remotes/origin/main 2>/dev/null || true)"
    if [ -n "$head" ] && [ -n "$origin" ] && [ "$head" = "$origin" ]; then
      printf 'sync'
    else
      printf 'nosync'
    fi
  fi
}

# 空白区切りリストに needle が含まれるか(含まれれば 0)。
_ref_in_list() {
  local needle="$1" list="$2" tok
  for tok in $list; do
    if [ "$tok" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

# 指定 branch 名の local ref が存在するか(存在すれば 0)。
# テスト注入(ALLOW_GUARD_TEST_LOCAL_REFS: 空白区切り)がセット済みならそれを使う。
local_branch_exists() {
  local name="$1"
  if [ -n "${ALLOW_GUARD_TEST_LOCAL_REFS+x}" ]; then
    _ref_in_list "$name" "$ALLOW_GUARD_TEST_LOCAL_REFS"
  else
    if git show-ref --verify --quiet "refs/heads/$name"; then
      return 0
    else
      return 1
    fi
  fi
}

# 指定 branch 名の origin ref が存在するか(存在すれば 0)。
# テスト注入(ALLOW_GUARD_TEST_REMOTE_REFS: 空白区切り)がセット済みならそれを使う。
remote_branch_exists() {
  local name="$1"
  if [ -n "${ALLOW_GUARD_TEST_REMOTE_REFS+x}" ]; then
    _ref_in_list "$name" "$ALLOW_GUARD_TEST_REMOTE_REFS"
  else
    if git show-ref --verify --quiet "refs/remotes/origin/$name"; then
      return 0
    else
      return 1
    fi
  fi
}

# 書込み可能ブランチであることを保証し、WRITABLE_BRANCH にセットする。
# detached HEAD / main / master は拒否。deny() は本体シェルで呼ぶ($()内で呼ばない)。
WRITABLE_BRANCH=""
require_writable_branch() {
  local b
  b="$(get_current_branch)"
  if [ -z "$b" ]; then
    deny "detached HEAD では書込み系(add/commit/push/pr create)を拒否します"
  fi
  case "$b" in
    main|master) deny "main/master ブランチでは書込み系を拒否します: $b" ;;
  esac
  WRITABLE_BRANCH="$b"
}

validate_git_add() {
  local seg="$1"
  require_writable_branch

  local _toks
  read -ra _toks <<< "$seg"
  # _toks[0]=git, _toks[1]=add, 以降がパス
  if [ "${#_toks[@]}" -lt 3 ]; then
    deny "git add: 追加パスが指定されていません: $seg"
  fi

  local i p
  for ((i = 2; i < ${#_toks[@]}; i++)); do
    p="${_toks[$i]}"
    case "$p" in
      -*) deny "git add: オプション/全件追加は禁止です(明示パスのみ): $p" ;;
      .)  deny "git add: '.' は禁止です" ;;
      ..) deny "git add: '..' は禁止です" ;;
      /*) deny "git add: 絶対パスは禁止です: $p" ;;
    esac
    if printf '%s' "$p" | grep -qE '^[A-Za-z]:'; then
      deny "git add: 絶対パス(ドライブ指定)は禁止です: $p"
    fi
    case "$p" in
      *:*) deny "git add: ':'(pathspec magic/ドライブ)は禁止です: $p" ;;
    esac
    if printf '%s' "$p" | grep -qE '(^|/)\.\.(/|$)'; then
      deny "git add: '..' セグメントは禁止です: $p"
    fi
    case "$p" in
      *'*'*|*'?'*|*'['*|*']'*) deny "git add: glob 指定は禁止です: $p" ;;
    esac
    case "$p" in
      *'\'*) deny "git add: バックスラッシュパスは禁止です: $p" ;;
    esac
    case "$p" in
      .git|.git/*|*/.git|*/.git/*) deny "git add: .git は禁止です: $p" ;;
      node_modules|node_modules/*|*/node_modules|*/node_modules/*) deny "git add: node_modules は禁止です: $p" ;;
    esac
    check_secret_path "$p" "git add path"
  done
}

validate_git_commit() {
  local seg="$1"
  require_writable_branch

  # 許可するのは `git commit -m "<空でないメッセージ>"` の1形式のみ
  # (二重引用符 または 単一引用符)。-a/--amend/複数-m/-F/--no-verify 等は
  # 追加トークンとなり、この完全一致パターンで自動的に拒否される。
  local re='^git commit -m ("[^"]+"|'\''[^'\'']+'\'')$'
  if ! printf '%s' "$seg" | grep -qE "$re"; then
    deny "git commit は 'git commit -m \"<message>\"' の1形式のみ許可します: $seg"
  fi

  local staged
  staged="$(get_staged_files)"
  if [ -z "$staged" ]; then
    deny "git commit: staged 変更がありません(commit 対象なし)"
  fi

  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if printf '%s' "$f" | grep -qiE "$SECRET_PATH_RE"; then
      deny "git commit: staged に秘匿ファイルが含まれます: $f"
    fi
  done <<< "$staged"
}

validate_git_push() {
  local seg="$1"
  require_writable_branch

  local expected="git push -u origin $WRITABLE_BRANCH"
  if [ "$seg" != "$expected" ]; then
    deny "git push は 'git push -u origin <現在の非mainブランチ>' のみ許可します: $seg"
  fi
}

# 読み取り専用 git branch。--show-current / --list / -r のみ完全一致で許可。
# -d/-D/-m/--delete/--set-upstream-to や branch 作成(git branch <name>)は拒否。
validate_git_branch() {
  local seg="$1"
  case "$seg" in
    "git branch --show-current"|"git branch --list"|"git branch -r") return 0 ;;
    *) deny "git branch は --show-current / --list / -r のみ許可します(削除/改名/作成は禁止): $seg" ;;
  esac
}

# branch 名の厳格検証。許可 prefix・危険パターン・文字集合・git 標準検証(eval しない)。
# deny() は本体で呼ぶ(サブシェル内では呼ばない)。
validate_branch_name() {
  local name="$1"
  # 許可 prefix(prefix 直後が空でないこと)
  case "$name" in
    feature/?*|fix/?*|docs/?*|chore/?*) : ;;
    *) deny "git switch -c: 許可 prefix (feature/ fix/ docs/ chore/) 以外、または prefix 直後が空です: $name" ;;
  esac
  # 危険パターン
  case "$name" in
    /*)      deny "git switch -c: branch 名が / で始まっています: $name" ;;
    */)      deny "git switch -c: branch 名が / で終わっています: $name" ;;
    *..*)    deny "git switch -c: branch 名に '..' を含みます: $name" ;;
    *//*)    deny "git switch -c: branch 名に連続 '//' を含みます: $name" ;;
    *@\{*)   deny "git switch -c: branch 名に '@{' を含みます: $name" ;;
    *.lock)  deny "git switch -c: branch 名が .lock で終わっています: $name" ;;
  esac
  # 文字集合ホワイトリスト(英数と . _ / - のみ。空白・制御文字・shell 記号・@ 等を排除)
  if printf '%s' "$name" | grep -qE '[^A-Za-z0-9._/-]'; then
    deny "git switch -c: branch 名に許可されない文字を含みます(A-Za-z0-9._/- のみ)"
  fi
  # git 標準検証。ユーザー入力は引用して渡すのみ(eval しない・展開しない)。
  if ! git check-ref-format --branch "$name" >/dev/null 2>&1; then
    deny "git switch -c: git check-ref-format --branch に失敗しました: $name"
  fi
}

# git switch: 'git switch main'(clean 必須) と
# 'git switch -c <feature|fix|docs|chore>/<name>'(厳格条件) のみ許可。
# -C / --create / checkout -b 等の強制作成・その他形式は拒否。
validate_git_switch() {
  local seg="$1"
  # 強制作成系を明示拒否
  case "$seg" in
    "git switch -C"*|"git switch --create"*)
      deny "git switch の -C/--create(強制作成)は禁止です: $seg" ;;
  esac

  # (a) main への切替: clean のみ許可(現在 branch は問わない=merge 後の戻りを許可)
  if [ "$seg" = "git switch main" ]; then
    if [ "$(get_worktree_state)" != "clean" ]; then
      deny "git switch main: working tree が clean ではありません"
    fi
    return 0
  fi

  # (b) branch 作成: トークン厳密 4 個(git switch -c <name>)
  local _toks
  read -ra _toks <<< "$seg"
  if [ "${#_toks[@]}" -eq 4 ] && [ "${_toks[1]}" = "switch" ] && [ "${_toks[2]}" = "-c" ]; then
    local name="${_toks[3]}"
    validate_branch_name "$name"

    local cur
    cur="$(get_current_branch)"
    if [ "$cur" != "main" ]; then
      deny "git switch -c: 現在 branch が main ではありません: ${cur:-<detached>}"
    fi
    if [ "$(get_worktree_state)" != "clean" ]; then
      deny "git switch -c: working tree が clean ではありません"
    fi
    if [ "$(get_main_sync_state)" != "sync" ]; then
      deny "git switch -c: local HEAD と origin/main が完全一致していません"
    fi
    if local_branch_exists "$name"; then
      deny "git switch -c: 同名の local branch が既に存在します: $name"
    fi
    if remote_branch_exists "$name"; then
      deny "git switch -c: 同名の origin branch が既に存在します: $name"
    fi
    return 0
  fi

  deny "git switch は 'git switch main' または 'git switch -c <feature|fix|docs|chore>/<name>' のみ許可します: $seg"
}

# git fetch: 'git fetch --prune origin' のみ完全一致で許可。
validate_git_fetch() {
  local seg="$1"
  if [ "$seg" != "git fetch --prune origin" ]; then
    deny "git fetch は 'git fetch --prune origin' のみ許可します: $seg"
  fi
}

# git pull: 'git pull --ff-only origin main' のみ、かつ main 上・clean のときだけ許可。
validate_git_pull() {
  local seg="$1"
  if [ "$seg" != "git pull --ff-only origin main" ]; then
    deny "git pull は 'git pull --ff-only origin main' のみ許可します: $seg"
  fi
  local cur
  cur="$(get_current_branch)"
  if [ "$cur" != "main" ]; then
    deny "git pull: 現在 branch が main ではありません: ${cur:-<detached>}"
  fi
  if [ "$(get_worktree_state)" != "clean" ]; then
    deny "git pull: working tree が clean ではありません"
  fi
}

validate_gh_pr_view() {
  local seg="$1"
  if [ "$seg" = "gh pr view" ]; then
    return 0
  fi
  if printf '%s' "$seg" | grep -qE '^gh pr view [0-9]+$'; then
    return 0
  fi
  if printf '%s' "$seg" | grep -qE '^gh pr view [0-9]+ --json [A-Za-z,]+$'; then
    local fields fld oldifs
    fields="$(printf '%s' "$seg" | sed -E 's/^gh pr view [0-9]+ --json //')"
    oldifs="$IFS"
    IFS=','
    for fld in $fields; do
      case "$fld" in
        state|mergeable|statusCheckRollup|url|title|number|headRefName|baseRefName|headRefOid|mergedAt|mergeCommit|reviewDecision) : ;;
        *) IFS="$oldifs"; deny "gh pr view --json: 許可されていないフィールドです: $fld" ;;
      esac
    done
    IFS="$oldifs"
    return 0
  fi
  deny "gh pr view の形式が不正です: $seg"
}

validate_gh_pr_checks() {
  local seg="$1"
  if [ "$seg" = "gh pr checks" ]; then
    return 0
  fi
  if printf '%s' "$seg" | grep -qE '^gh pr checks [0-9]+$'; then
    return 0
  fi
  deny "gh pr checks の形式が不正です: $seg"
}

validate_gh_pr_create() {
  local seg="$1"
  require_writable_branch
  local expected="gh pr create --base main --head $WRITABLE_BRANCH --fill"
  if [ "$seg" != "$expected" ]; then
    deny "gh pr create は 'gh pr create --base main --head <現在ブランチ> --fill' のみ許可します: $seg"
  fi
}

# gh pr list: 完全一致 'gh pr list --state open --json number,title,headRefName' のみ許可。
# --state 別値・追加 field・--limit/--search/--repo 等の追加引数は拒否。
validate_gh_pr_list() {
  local seg="$1"
  if [ "$seg" != "gh pr list --state open --json number,title,headRefName" ]; then
    deny "gh pr list は 'gh pr list --state open --json number,title,headRefName' のみ許可します: $seg"
  fi
}

validate_gh() {
  local seg="$1"
  local a2 a3
  a2="$(printf '%s' "$seg" | awk '{print $2}')"
  case "$a2" in
    api) deny "gh api は禁止です: $seg" ;;
    pr)  : ;;
    *)   deny "gh は pr の view/checks/create/list のみ許可します: $seg" ;;
  esac
  a3="$(printf '%s' "$seg" | awk '{print $3}')"
  case "$a3" in
    view)   validate_gh_pr_view "$seg" ;;
    checks) validate_gh_pr_checks "$seg" ;;
    create) validate_gh_pr_create "$seg" ;;
    list)   validate_gh_pr_list "$seg" ;;
    merge|close|edit) deny "gh pr $a3 は禁止です: $seg" ;;
    *) deny "gh pr は view/checks/create/list のみ許可します: $seg" ;;
  esac
}

# ---- Bash以外の Read / Grep / Glob 用ガード ----
case "${tool_name:-}" in
  Read)
    check_secret_path "$read_path" "Read path"
    check_dangerous_path "$read_path" "Read path"
    exit 0
    ;;
  Grep)
    check_secret_path "$grep_path" "Grep path"
    check_secret_path "$grep_glob" "Grep glob"
    check_dangerous_path "$grep_path" "Grep path"
    check_dangerous_path "$grep_glob" "Grep glob"
    exit 0
    ;;
  Glob)
    check_secret_path "$read_path" "Glob path"
    check_secret_path "$glob_pattern" "Glob pattern"
    check_dangerous_path "$read_path" "Glob path"
    check_dangerous_path "$glob_pattern" "Glob pattern"
    exit 0
    ;;
esac

# Bash以外で、取るべき情報が無ければ許可
if [ -z "${cmd:-}" ]; then
  exit 0
fi

# find は allowlist から除外済みのため、下のセグメント検査で
# 「許可されていないBashコマンドです: find」として拒否される。専用分岐は設けない。

# Bash危険構文を先に拒否(コマンド連結・パイプ・サブシェル・リダイレクト・
# コマンド置換・改行/CR を fail-closed で全拒否)
case "$cmd" in
  *'>'*)   deny "リダイレクト(>)は禁止: $cmd" ;;
  *'<'*)   deny "リダイレクト/heredoc/プロセス置換(<)は禁止: $cmd" ;;
  *'$('*)  deny "コマンド置換 \$()は禁止: $cmd" ;;
  *'`'*)   deny "コマンド置換(バッククォート)は禁止: $cmd" ;;
  *';'*)   deny "コマンド連結(;)は禁止: $cmd" ;;
  *'&&'*)  deny "コマンド連結(&&)は禁止: $cmd" ;;
  *'||'*)  deny "コマンド連結(||)は禁止: $cmd" ;;
  *'|'*)   deny "パイプ(|)は禁止: $cmd" ;;
  *'&'*)   deny "バックグラウンド/連結(&)は禁止: $cmd" ;;
  *'('*)   deny "サブシェル/グループ化 '(' は禁止: $cmd" ;;
  *')'*)   deny "サブシェル/グループ化 ')' は禁止: $cmd" ;;
  *"$LF"*) deny "改行(LF)は禁止: $cmd" ;;
  *"$CR"*) deny "復帰(CR)は禁止: $cmd" ;;
esac

# パイプは上で拒否済みのため、実質1セグメント。構造は維持する。
IFS='|' read -ra segments <<< "$cmd"

for seg in "${segments[@]}"; do
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [ -z "$seg" ] && deny "空のセグメントは禁止"

  first="$(printf '%s' "$seg" | awk '{print $1}')"

  ok=0
  for allowed in "${ALLOWED_BASH[@]}"; do
    if [ "$first" = "$allowed" ]; then
      ok=1
      break
    fi
  done

  [ "$ok" -eq 1 ] || deny "許可されていないBashコマンドです: $first"

  case "$first" in
    git)
      sub="$(printf '%s' "$seg" | awk '{print $2}')"
      case "$sub" in
        status|diff|log)
          check_secret_path "$seg" "git command"
          # git diff/log は引数なしを許可。危険パス・ワイルドカードが明示された場合のみ拒否
          if printf '%s' "$seg" | grep -qE '(^|[[:space:]])(\.|/|\.\.|\*)($|[[:space:]/])'; then
            case "$seg" in
              *".claude"*) : ;;
              *) deny "git の対象パス指定が広すぎます: $seg" ;;
            esac
          fi
          ;;
        add)    validate_git_add "$seg" ;;
        commit) validate_git_commit "$seg" ;;
        push)   validate_git_push "$seg" ;;
        branch) validate_git_branch "$seg" ;;
        switch) validate_git_switch "$seg" ;;
        fetch)  validate_git_fetch "$seg" ;;
        pull)   validate_git_pull "$seg" ;;
        *) deny "git は status/diff/log/add/commit/push/branch/switch/fetch/pull のみ許可します: $seg" ;;
      esac
      ;;

    gh)
      validate_gh "$seg"
      ;;

    # find は allowlist に含めない(許可しない)。専用分岐は撤去済み。

    grep)
      check_secret_path "$seg" "grep command"
      if printf '%s' "$seg" | grep -qE '(^|[[:space:]])\./?($|[[:space:]])|(^|[[:space:]])/|(^|[[:space:]])\.\.($|/|[[:space:]])|[*?[]'; then
        deny "grep の対象パスが広すぎる/危険です: $seg"
      fi
      ;;

    cat|head|tail|ls|wc)
      check_secret_path "$seg" "$first command"
      if printf '%s' "$seg" | grep -qE '(^|[[:space:]])\./?($|[[:space:]])|(^|[[:space:]])/|(^|[[:space:]])\.\.($|/|[[:space:]])|[*?[]'; then
        deny "$first の対象パスが広すぎる/危険です: $seg"
      fi
      ;;

    npm)
      case "$seg" in
        "npm test"|"npm run lint") : ;;
        *) deny "npm は完全一致で npm test / npm run lint のみ許可します: $seg" ;;
      esac
      ;;
  esac
done

exit 0
