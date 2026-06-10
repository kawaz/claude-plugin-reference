#!/bin/bash
# SessionStart hook: このリポが Claude Code plugin (= .claude-plugin/plugin.json 保有) なら、
# claude-plugin-reference skill の参照を促す additionalContext を inject する。
# plugin / skill / hooks / commands / agents の仕様を試行錯誤せず一次リファレンスに当てさせる狙い。
#
# plugin hook は enable 中の "全" セッションで発火するため、manifest 有無で条件分岐し、
# plugin repo 以外では沈黙する (= ノイズを出さない)。判定は CLAUDE_PROJECT_DIR (= 全 hook で利用可)。
#
# NOTE: set -e は使わない。フック自体の不具合はユーザ作業を巻き込まないよう無害に通過させる。

cat >/dev/null 2>&1 # stdin の hook payload は使わないが drain しておく

root="${CLAUDE_PROJECT_DIR:-$PWD}"

# plugin manifest が無ければ何もしない (= plugin repo 以外では沈黙)
[ -f "$root/.claude-plugin/plugin.json" ] || exit 0

msg="このリポジトリは Claude Code plugin です (.claude-plugin/plugin.json 検出)。plugin / skill / hooks / commands / agents の仕様は試行錯誤せず claude-plugin-reference skill (/claude-plugin-reference:claude-plugin-reference) を参照してください。"

# additionalContext を JSON で返す。msg に \" や \\ を含めないので printf 直書きで valid JSON。
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
exit 0
