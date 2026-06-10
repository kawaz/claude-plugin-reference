#!/usr/bin/env bash
# plugin-repo-nudge.sh をテーブル駆動で検証。
# CLAUDE_PROJECT_DIR を export して script を直接実行し、
#   - 発火/沈黙 (stdout の有無)
#   - exit 0
#   - 発火時 stdout が valid JSON かつ additionalContext を含む
# を確認する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/plugin-repo-nudge.sh"

[ -x "$HOOK" ] || { echo "FAIL: $HOOK not found or not executable" >&2; exit 1; }

pass=0
fail=0

# usage: assert_case <label> <fire|silent> <project_dir>
assert_case() {
  local label="$1" expect="$2" dir="$3"
  local out rc
  out=$(CLAUDE_PROJECT_DIR="$dir" "$HOOK" </dev/null 2>/dev/null)
  rc=$?

  local ok=1 reason=""

  # 常に exit 0
  if [ "$rc" != 0 ]; then ok=0; reason="exit=$rc (want 0)"; fi

  if [ "$expect" = fire ]; then
    if [ -z "$out" ]; then
      ok=0; reason="${reason:+$reason; }no stdout (want fire)"
    else
      # valid JSON か
      if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
        ok=0; reason="${reason:+$reason; }stdout not valid JSON"
      # additionalContext を含むか
      elif ! printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        ok=0; reason="${reason:+$reason; }missing additionalContext"
      fi
    fi
  else # silent
    if [ -n "$out" ]; then ok=0; reason="${reason:+$reason; }got stdout (want silent)"; fi
  fi

  if [ "$ok" = 1 ]; then
    printf 'PASS  %-45s [%s]\n' "$label" "$expect"
    pass=$((pass+1))
  else
    printf 'FAIL  %-45s [%s] %s\n' "$label" "$expect" "$reason" >&2
    fail=$((fail+1))
  fi
}

# ---- plugin.json 保有 dir → 発火 ----
PLUGIN_DIR="$(mktemp -d)"
trap 'rm -rf "$PLUGIN_DIR"' EXIT
mkdir -p "$PLUGIN_DIR/.claude-plugin"
printf '{"name":"x"}' > "$PLUGIN_DIR/.claude-plugin/plugin.json"
assert_case "plugin.json holder" fire "$PLUGIN_DIR"

# ---- claude-rules-* (ルート直下) → 発火 ----
assert_case "claude-rules root"        fire   "/x/claude-rules-personal"
# ---- claude-rules-* (サブ階層あり) → 発火 ----
assert_case "claude-rules + main"      fire   "/x/claude-rules-personal/main"
# ---- .claude-* 設定ディレクトリ → 発火 ----
assert_case ".claude-personal/y"       fire   "/x/.claude-personal/y"
# ---- .claude ディレクトリ → 発火 ----
assert_case ".claude/y"                fire   "/x/.claude/y"
# ---- .claudexyz (dash なし接尾) → 沈黙 ----
assert_case ".claudexyz (no dash)"     silent "/x/.claudexyz"
# ---- 無関係リポ → 沈黙 ----
assert_case "normal-repo"              silent "/x/normal-repo"

echo ""
if [ "$fail" -gt 0 ]; then
  echo "FAILED: $fail case(s), $pass passed." >&2
  exit 1
fi
echo "All $pass cases passed."
