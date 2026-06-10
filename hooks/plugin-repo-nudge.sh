#!/bin/bash
# SessionStart hook: 以下いずれかに該当するなら、claude-plugin-reference skill の
# 参照を促す additionalContext を inject する:
#   (a) Claude Code plugin リポ (= .claude-plugin/plugin.json 保有)
#   (b) パスに /claude-rules-*/ を含む (= rule overlay リポ作業中)
#   (c) パスに /.claude を含む (= Claude 設定ディレクトリ等を直接触っている)
# plugin / skill / hooks / commands / agents の仕様を試行錯誤せず一次リファレンスに当てさせる狙い。
#
# plugin hook は enable 中の "全" セッションで発火するため、対象外では沈黙する。
#
# NOTE: set -e は使わない。フック自体の不具合はユーザ作業を巻き込まないよう無害に通過させる。

cat >/dev/null 2>&1 # stdin の hook payload は使わないが drain しておく

root="${CLAUDE_PROJECT_DIR:-$PWD}"

hit=0
[ -f "$root/.claude-plugin/plugin.json" ] && hit=1
case "$root" in
  */.claude*|*/claude-rules-*/*) hit=1 ;;
esac

[ "$hit" = 1 ] || exit 0

msg="このリポジトリは Claude Code plugin / rules 関連です。plugin / skill / hooks / commands / agents の仕様は試行錯誤せず claude-plugin-reference skill (/claude-plugin-reference:claude-plugin-reference) を参照してください。"

# additionalContext を JSON で返す。msg に \" や \\ を含めないので printf 直書きで valid JSON。
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
exit 0
