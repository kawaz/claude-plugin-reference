---
title: SessionStart hook をプロジェクト構造対応で強化 + SKILL.md 内に動的優先度表示
status: open
category: request
created: 2026-06-19T15:03:41+09:00
last_read:
open_entered: 2026-06-19T15:03:41+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/claude-nandakke (2026-06-19 設計セッション中の dogfooding 気付き)
---

# SessionStart hook をプロジェクト構造対応で強化 + SKILL.md 内に動的優先度表示

## 概要

現状の SessionStart hook は「マニフェスト (= plugin.json 等) があれば claude-plugin-reference skill のロードを促す」止まり。**どの reference/*.md を読むかは AI エージェント任せ** になっており、AI が必要な reference を読まずに議論を進めて誤判定する事例が発生した。

プロジェクト構造を見て「これは必読」と AI を誘導する仕組みを 2 案検討する。

## 背景

2026-06-19 の kawaz/claude-nandakke 設計セッション中、川津と AI (Claude) が plugin 関連の設計議論を進めていて、以下のミスが複数回発生:

- ` \!\`command\`` 記法が動的に展開されるか? を AI が **「未サポート / 検証必要」と誤推測**
  → 指摘で `reference/skills.md §5` を読んだら **Dynamic Context Injection として既に標準サポート** だった
- `_` prefix で hidden command にできるか? を AI が議論したが、**`reference/skills.md §9.2` の `_` prefix + `disable-model-invocation: true` 組み合わせを読まずに進めていた**
- commands と skills の関連性 (= 互いに代替候補) を AI が見落として一方だけで議論

ルート原因: AI は SessionStart hook で「skill ロード促す」というメッセージを受けたが、**どの reference/*.md を読むかの判断が AI 任せ** で、description (~220 tokens) だけで知った気になって本体を読まなかった。

## 提案 (= 案 2 つ、両建ても可)

### 案 A: SessionStart hook をプロジェクト構造対応で強化

hook script でプロジェクト構造を grep し、関連 reference を必読指定:

```sh
# 擬似コード
if [ -d "$CLAUDE_PROJECT_DIR/skills" ] || [ -d "$CLAUDE_PROJECT_DIR/commands" ]; then
  echo "**必読**: reference/skills.md & reference/commands.md (skills/ または commands/ あり)"
  # commands と skills は runtime 同一機構で互いに代替候補、1 セットで読む
fi
if [ -d "$CLAUDE_PROJECT_DIR/hooks" ] || [ -f "$CLAUDE_PROJECT_DIR/hooks/hooks.json" ]; then
  echo "**必読**: reference/hooks.md"
fi
if [ -d "$CLAUDE_PROJECT_DIR/agents" ]; then
  echo "**必読**: reference/agents.md"
fi
```

session 冒頭の system-reminder として注入されるので proactive。

### 案 B: SKILL.md 内に Dynamic Context Injection で動的優先度表示

` \!\`command\`` (= Dynamic Context Injection、reference/skills.md §5) を使って skill 起動時に評価:

```markdown
- [skills.md](reference/skills.md) & [commands.md](reference/commands.md) \! `[[ -d "$CLAUDE_PROJECT_DIR/skills" || -d "$CLAUDE_PROJECT_DIR/commands" ]] && echo '— **必読セット** (skills/ または commands/ あり)'`
- [hooks.md](reference/hooks.md) \! `[[ -d "$CLAUDE_PROJECT_DIR/hooks" ]] && echo '— **必読**'`
- [agents.md](reference/agents.md) \! `[[ -d "$CLAUDE_PROJECT_DIR/agents" ]] && echo '— **必読**'`
```

skill 起動時に評価されるので reactive (= skill が呼ばれるまで効かない)。

### 両建ての利点

- 案 A: session 冒頭で proactive に促す (= skill 呼ばれる前に効く)
- 案 B: skill 内で詳細な動的優先度を示す (= skill 起動後に効く)
- 互いに補完関係。実装判断は当事者で。

## 一次資料

- `reference/skills.md §5` Dynamic Context Injection (` \!\`command\``)
- `reference/skills.md §9.2` `_` prefix + `disable-model-invocation: true` で hidden command パターン
- `reference/builtin-slash-commands.md` commands と skills の使い分け

## 受け入れ条件

- [ ] 案 A (SessionStart hook 強化) または 案 B (SKILL.md 動的表示) の採否を判断
- [ ] commands/skills は「1 セット (= 互いに代替候補)」として扱う原則を反映
- [ ] 起票元 (= ある別リポ) のセッションで観察された AI のミスパターンを軽減できることを確認

## TODO

<!-- wip 時のみ -->

## 解決時の記録先

- 単純なコード修正のみ: 記録不要 (commit message で足りる)
- 設計判断を伴う: decisions/DR-NNNN-...md
- 運用上の再発可能性: runbooks/<topic>.md
- 経緯・ハマり所: journal/YYYY-MM-DD-<slug>.md

close 時はこのファイルを docs/issue/archive/ へ移動する(削除しない。経緯を DB として残す)。

## 部外者起票としての注記

- 本 issue は別リポでの実体験から起票された dogfooding feedback
- 当事者 (= claude-plugin-reference 側) が「本当にこの問題が起きるか」「どの案が筋か」を判断する材料として
- 鵜呑みにせず、実装判断は当事者の責任で
