#!/usr/bin/env bash
# .claude/hooks/allow-guard.sh
#
# 目的:
#   岡井組 社内業務システムのread-only調査サブエージェント用ガード。
#   Bashはallowlist方式で、明示的に許可した読み取り系コマンドだけ通す。
#   Read/Grep/Globは秘密ファイル・危険パスへのアクセスを拒否する。
#
# 拒否方式:
#   exit 2 で拒否。理由は標準エラーに出す。stdout JSON方式とは混在させない。

set -euo pipefail

# find は Windows/Git Bash 環境で危険オプション(-delete/-exec/-fprint 等)の検出が不安定なため、
# Bash allowlist から除外する。ファイル探索が必要な場合は Glob ツールを使うこと。
ALLOWED_BASH=(git grep cat ls pwd wc head tail npm)

SECRET_PATH_RE='(^|/)(\.env|\.env\..*|secrets?)(/|$)|secret|credential|private[._-]*key|id_rsa|id_ed25519|settings\.local\.json'
DANGEROUS_PATH_RE='(^|[[:space:]])\.$|(^|[[:space:]])\./($|[[:space:]])|(^|[[:space:]])/|(^|[[:space:]])\.\.($|/|[[:space:]])|[*?[]'

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
  cmd="$(printf '%s' "$input" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/' | head -1 || true)"
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

# Bash以外の Read / Grep / Glob 用ガード
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

# Bash危険構文を先に拒否
case "$cmd" in
  *'>'*)      deny "リダイレクト(>)は禁止: $cmd" ;;
  *'<'*)      deny "リダイレクト/heredoc/プロセス置換(<)は禁止: $cmd" ;;
  *'$('*)     deny "コマンド置換 \$()は禁止: $cmd" ;;
  *'`'*)      deny "コマンド置換(バッククォート)は禁止: $cmd" ;;
  *';'*)      deny "コマンド連結(;)は禁止: $cmd" ;;
  *'&&'*)     deny "コマンド連結(&&)は禁止: $cmd" ;;
  *'||'*)     deny "コマンド連結(||)は禁止: $cmd" ;;
  *'&'*)      deny "バックグラウンド/連結(&)は禁止: $cmd" ;;
esac

IFS='|' read -ra segments <<< "$cmd"

for seg in "${segments[@]}"; do
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [ -z "$seg" ] && deny "空のパイプセグメントは禁止"

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
        status|diff|log) : ;;
        *) deny "git は status/diff/log のみ許可します: $seg" ;;
      esac
      check_secret_path "$seg" "git command"
      # git diff/log は引数なしを許可。危険パス・ワイルドカードが明示された場合のみ拒否
      if printf '%s' "$seg" | grep -qE '(^|[[:space:]])(\.|/|\.\.|\*)($|[[:space:]/])'; then
        case "$seg" in
          *".claude"*) : ;;
          *) deny "git の対象パス指定が広すぎます: $seg" ;;
        esac
      fi
      ;;

    # find は allowlist に含めない（許可しない）。専用分岐は撤去済み。

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
