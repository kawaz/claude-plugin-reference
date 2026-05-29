---
name: claude-plugin-reference
description: Claude Code plugin / skill / hooks の実機検証込みリファレンス。詳細は reference/ 配下を必要に応じて Read で読む。
---

詳細な仕様は `${CLAUDE_SKILL_DIR}/reference/` 配下を Read してください。

- [distribution.md](reference/distribution.md) — 配布編 (plugin.json / marketplace.json / 配布フロー / version bump)
- [hooks.md](reference/hooks.md) — フック編 (全 hook event / matcher / JSON input/output schema / blockable / 強制力)
- [skills.md](reference/skills.md) — スキル編 (SKILL.md frontmatter / string substitution / Dynamic Context Injection / invocation 制御)

各ファイルは `[spec 明示] / [実機検証済] / [未検証] / [実装の副産物]` のラベルで確証範囲を区別。`[未検証]` 項目は TODO、検証したら格上げ。
