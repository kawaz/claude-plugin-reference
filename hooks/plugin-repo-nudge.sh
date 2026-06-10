#!/bin/bash
# SessionStart hook: 以下いずれかに該当するなら、claude-plugin-reference skill の
# 参照を促す additionalContext を inject する:
#   (a) Claude Code plugin リポ (= .claude-plugin/plugin.json 保有)
#   (b) パス要素に claude-rules-* を含む (= rule overlay リポ作業中、リポルート直下でも発火)
#   (c) パス要素が .claude または .claude-* で始まる (= Claude 設定ディレクトリ、例 ~/.claude-personal)
# plugin / skill / hooks / commands / agents の仕様を試行錯誤せず一次リファレンスに当てさせる狙い。
#
# plugin hook は enable 中の "全" セッションで発火するため、対象外では沈黙する。
#
# NOTE: set -e は使わない。フック自体の不具合はユーザ作業を巻き込まないよう無害に通過させる。

cat >/dev/null 2>&1 # stdin の hook payload は使わないが drain しておく

root="${CLAUDE_PROJECT_DIR:-$PWD}"

hit=0
[ -f "$root/.claude-plugin/plugin.json" ] && hit=1
# Design rationale: パス要素境界で判定するため $root の末尾に "/" を付けて正規化し、
# 各パターンを */<elem>/* 形式で書く。これにより:
#   - `*/.claude/*` : `.claude` ディレクトリ要素 (例 ~/.claude/...) のみマッチ。
#     旧 `*/.claude*` の部分一致 (= `.claudexyz` 誤マッチ) を回避するため狭めた。
#   - `*/.claude-*/*` : `.claude-personal` 等 dash 付き接尾の設定ディレクトリにマッチ。
#     `.claudexyz` (dash なし接尾) には意図的にマッチさせない。
#   - `*/claude-rules-*/*` : 正規化で末尾 "/" を足したので、リポルート
#     (`.../kawaz/claude-rules-personal`) を直接指す場合も `claude-rules-personal/` として
#     マッチする。旧パターンは末尾に追加 1 階層を要求しルート直下で発火しなかったため広げた。
case "$root/" in
  */.claude/*|*/.claude-*/*|*/claude-rules-*/*) hit=1 ;;
esac

[ "$hit" = 1 ] || exit 0

# Design rationale: msg は英語固定。本 plugin は marketplace で公開配布され、additionalContext は
# model-facing (= モデルはセッション言語で応答するので注入言語に依存しない)。日本語固定だと
# 非日本語圏ユーザの全セッションに日本語が注入されてしまうため英語に寄せる。
msg="This project contains Claude Code plugin/config files. Do not trial-and-error the plugin / skill / hooks / commands / agents specs - consult the /claude-plugin-reference:claude-plugin-reference skill first."

# additionalContext を JSON で返す。msg に \" や \\ を含めないので printf 直書きで valid JSON。
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
exit 0
