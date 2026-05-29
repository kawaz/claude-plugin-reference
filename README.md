# claude-plugin-reference

Claude Code plugin / skill / hooks の **実機検証込み** リファレンス。
公式 docs はふんわりしている (= 「指定したら何が効くか / いつ使えるか」が読み取りきれない) 部分が多いので、自分の plugin 開発で実機検証して確証取った一次情報を集約する。

kawaz/cmux-msg, kawaz/hyoui その他自前 plugin から `${CLAUDE_PLUGIN_ROOT}/...` 経由 or skill 参照で読める。毎 plugin で同じ説明を繰り返さない。

## Install

```
claude plugin marketplace add kawaz/claude-plugin-reference
claude plugin install claude-plugin-reference@claude-plugin-reference
```

## Update

```
claude plugin marketplace update claude-plugin-reference
claude plugin update claude-plugin-reference@claude-plugin-reference
```

## 提供する skill

`claude-plugin-reference:claude-plugin-reference` の 1 skill のみ。skill 本文は目次のみ、詳細は関心別の reference ファイルに分けて on-demand で読む構造:

```
skills/claude-plugin-reference/
├── SKILL.md                    # 目次 (invocation 時に AI 流入)
└── reference/
    ├── distribution.md         # 配布編 (plugin.json / marketplace.json / 配布フロー / version bump)
    ├── hooks.md                # フック編 (全 Hook event 一覧 / matcher / JSON input/output / blockable / 強制力)
    ├── skills.md               # スキル編 (SKILL.md frontmatter / string substitution / Dynamic Context Injection / invocation 制御)
    └── agents.md               # エージェント編 (agents field / agent frontmatter / 名前空間 / スコープ / 起動方法 / plugin agent の制限)
```

## 記述ポリシー

- 各項目は **公式 spec 引用** + **実機検証結果** + **「ふんわりだった挙動 → 確証」** の 3 つを区別
- `spec で保証されている範囲` と `実装の副産物` は区別する規律
- 検証していない項目は `[未検証]` と明示 (= 嘘の確証を撒かない)
- 出典 URL は一次情報リンク (code.claude.com/docs/en/...) を併記

## 参考 URL (出典一次情報)

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins.md)
- [Plugins Reference](https://code.claude.com/docs/en/plugins-reference.md)
- [Skills](https://code.claude.com/docs/en/skills.md)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces.md)
- [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins.md)
- [Hooks Guide](https://code.claude.com/docs/en/hooks-guide.md)
- [Hooks Reference](https://code.claude.com/docs/en/hooks.md)
