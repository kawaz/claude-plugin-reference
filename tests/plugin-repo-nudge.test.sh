#!/bin/bash
# plugin-repo-nudge.sh をテーブル駆動で検証。
# CLAUDE_PROJECT_DIR を export して script を直接実行し、
#   - 発火/沈黙 (stdout の有無)
#   - exit 0
#   - 発火時 stdout が valid JSON かつ additionalContext が非空文字列
# を確認する。加えて hooks.json 自体の構文 + command クオートも検証する。

set -uo pipefail

command -v jq >/dev/null || { echo "FAIL: jq required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/plugin-repo-nudge.sh"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"

[ -x "$HOOK" ] || { echo "FAIL: $HOOK not found or not executable" >&2; exit 1; }

pass=0
fail=0

check() {
  # usage: check <label> <ok:1|0> [reason]
  local label="$1" ok="$2" reason="${3:-}"
  if [ "$ok" = 1 ]; then
    printf 'PASS  %-55s\n' "$label"
    pass=$((pass+1))
  else
    printf 'FAIL  %-55s %s\n' "$label" "$reason" >&2
    fail=$((fail+1))
  fi
}

# 発火時 stdout が valid JSON かつ additionalContext が非空文字列か判定。
# 空文字列退行 (additionalContext="") を検出するため length > 0 を見る。
verify_fire() {
  local out="$1"
  [ -n "$out" ] || { echo "no stdout (want fire)"; return 1; }
  printf '%s' "$out" | jq -e . >/dev/null 2>&1 || { echo "stdout not valid JSON"; return 1; }
  printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1 \
    || { echo "additionalContext missing or empty"; return 1; }
  return 0
}

# usage: assert_case <label> <fire|silent> <project_dir> [args...]
assert_case() {
  local label="$1" expect="$2" dir="$3"; shift 3
  local out rc reason=""
  out=$(CLAUDE_PROJECT_DIR="$dir" "$HOOK" "$@" </dev/null 2>/dev/null)
  rc=$?

  local ok=1
  if [ "$rc" != 0 ]; then ok=0; reason="exit=$rc (want 0)"; fi

  if [ "$expect" = fire ]; then
    local vr; vr=$(verify_fire "$out") || { ok=0; reason="${reason:+$reason; }$vr"; }
  else
    if [ -n "$out" ]; then ok=0; reason="${reason:+$reason; }got stdout (want silent)"; fi
  fi

  check "$label [$expect]" "$ok" "$reason"
}

# ---- plugin.json 保有 dir → 発火 ----
PLUGIN_DIR="$(mktemp -d)"
trap 'rm -rf "$PLUGIN_DIR"' EXIT
mkdir -p "$PLUGIN_DIR/.claude-plugin"
printf '{"name":"x"}' > "$PLUGIN_DIR/.claude-plugin/plugin.json"
assert_case "plugin.json holder"           fire   "$PLUGIN_DIR"

# ---- 既存の基本ケース ----
assert_case "claude-rules root"            fire   "/x/claude-rules-personal"
assert_case "claude-rules + main"          fire   "/x/claude-rules-personal/main"
assert_case ".claude-personal/y"           fire   "/x/.claude-personal/y"
assert_case ".claude/y"                    fire   "/x/.claude/y"
assert_case ".claudexyz (no dash)"         silent "/x/.claudexyz"
assert_case "normal-repo"                  silent "/x/normal-repo"

# ---- 境界ケース (実測挙動の固定) ----
# .claude がルート要素そのもの (末尾要素) → 発火 (末尾 "/" 正規化で */.claude/* にマッチ)
assert_case ".claude as leaf element"      fire   "/x/.claude"
# prefix マッチであり contains ではない: 要素が claude-rules- で "始まる" 必要がある
assert_case "my-claude-rules-foo (contains, not prefix)" silent "/x/my-claude-rules-foo/work"
# claude-rules- (接尾が空) → 発火 (境界の意図確定: prefix だけで判定)
assert_case "claude-rules- (empty suffix)" fire   "/x/claude-rules-/work"
# .claude-plugin はパス要素マッチ経路で発火 (plugin.json 不在でも .claude-* にマッチ)
assert_case ".claude-plugin/sub element"   fire   "/x/.claude-plugin/sub"

# ---- スペースを含むパス → 正常動作 ----
assert_case "space in path (fire)"         fire   "/tmp/has space/claude-rules-x/work"
assert_case "space in path (silent)"       silent "/tmp/has space/normal-repo/work"

# ---- hooks.json と同形の引数を付けて呼んでも挙動不変 ----
assert_case "with #marker arg (fire)"      fire   "/x/claude-rules-personal" "#claude-plugin-reference"
assert_case "with #marker arg (silent)"    silent "/x/normal-repo"           "#claude-plugin-reference"

# ---- CLAUDE_PROJECT_DIR 未設定時の $PWD fallback ----
FB_FIRE="$(mktemp -d)/claude-rules-x"
mkdir -p "$FB_FIRE"
out=$( (cd "$FB_FIRE" && unset CLAUDE_PROJECT_DIR && "$HOOK" </dev/null 2>/dev/null) ); rc=$?
ok=1; reason=""
[ "$rc" = 0 ] || { ok=0; reason="exit=$rc"; }
vr=$(verify_fire "$out") || { ok=0; reason="${reason:+$reason; }$vr"; }
check "PWD fallback fire [fire]" "$ok" "$reason"
rm -rf "$(dirname "$FB_FIRE")"

FB_SILENT="$(mktemp -d)/normal-repo"
mkdir -p "$FB_SILENT"
out=$( (cd "$FB_SILENT" && unset CLAUDE_PROJECT_DIR && "$HOOK" </dev/null 2>/dev/null) ); rc=$?
ok=1; reason=""
[ "$rc" = 0 ] || { ok=0; reason="exit=$rc"; }
[ -z "$out" ] || { ok=0; reason="${reason:+$reason; }got stdout (want silent)"; }
check "PWD fallback silent [silent]" "$ok" "$reason"
rm -rf "$(dirname "$FB_SILENT")"

# ---- 実 SessionStart 風 JSON payload を stdin に流して exit 0 + 正常出力 ----
payload='{"hook_event_name":"SessionStart","source":"startup","session_id":"x","cwd":"/tmp","transcript_path":"/tmp/t"}'
out=$(CLAUDE_PROJECT_DIR="/x/claude-rules-personal" "$HOOK" <<<"$payload" 2>/dev/null); rc=$?
ok=1; reason=""
[ "$rc" = 0 ] || { ok=0; reason="exit=$rc"; }
vr=$(verify_fire "$out") || { ok=0; reason="${reason:+$reason; }$vr"; }
check "real SessionStart payload on stdin [fire]" "$ok" "$reason"

# ---- hooks.json 構文 + command クオート検証 ----
ok=1; reason=""
if ! jq empty "$HOOKS_JSON" >/dev/null 2>&1; then
  ok=0; reason="hooks.json is not valid JSON"
else
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$HOOKS_JSON")
  # ${CLAUDE_PLUGIN_ROOT}... の前後がダブルクオートで囲まれていること
  # (空白を含む cache パスでの word splitting 回帰を検出)
  case "$cmd" in
    '"${CLAUDE_PLUGIN_ROOT}'*'"'*) ;;
    *) ok=0; reason="command not double-quoted: [$cmd]" ;;
  esac
fi
check "hooks.json: valid + command quoted" "$ok" "$reason"

echo ""
if [ "$fail" -gt 0 ]; then
  echo "FAILED: $fail case(s), $pass passed." >&2
  exit 1
fi
echo "All $pass cases passed."
