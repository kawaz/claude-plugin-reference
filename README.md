# claude-plugin-reference

> English | [日本語](./README-ja.md)

A **field-verified** reference for Claude Code plugins / skills / hooks.
The official docs are vague in places (= "what takes effect when you specify X / when can you use Y" is hard to read off), so this repo collects primary-source info confirmed via real-world plugin development.

Loadable from any other plugin or session via skill reference (`claude-plugin-reference:claude-plugin-reference`) — so the same explanations don't get repeated in every plugin.

> Note: the reference body is currently **Japanese only**. This README (cover page) is bilingual, but the on-demand `reference/*.md` files are not yet translated.

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

## Provided skill

A single skill: `claude-plugin-reference:claude-plugin-reference`. The SKILL body is just a table of contents; details live in topic-specific reference files loaded on demand:

```
skills/claude-plugin-reference/
├── SKILL.md                    # ToC (streamed to the AI on invocation)
└── reference/
    ├── distribution.md         # Distribution (plugin.json / marketplace.json / flow / version bump)
    ├── hooks.md                # Hooks (all Hook events / matcher / JSON I/O / blockable / strength)
    ├── skills.md               # Skills (SKILL.md frontmatter / string substitution / Dynamic Context Injection / invocation control)
    ├── commands.md             # Commands (role of commands/*.md / format / vs. skills / 3-axis structure)
    └── agents.md               # Agents (agents field / agent frontmatter / namespacing / scope / launch / plugin agent restrictions)
```

## Provided hook

Ships a single `SessionStart` hook (`hooks/plugin-repo-nudge.sh`). It injects a one-line `additionalContext` saying "consult this skill first instead of trial-and-error" when any of the following is true (silent otherwise):

- Project root has `.claude-plugin/plugin.json`
- A `CLAUDE_PROJECT_DIR` path element **starts with** `claude-rules-` (= derived from kawaz's rule-overlay repo naming convention; fires even at the repo root, and also on unrelated repos that share the same prefix)
- A `CLAUDE_PROJECT_DIR` path element is exactly `.claude`, or **starts with** `.claude-` (= directly editing a Claude config directory, e.g. `~/.claude-personal`). Does not fire on a dash-less suffix like `.claudexyz`

The goal is to prevent plugin / skill / hook trial-and-error mistakes at the entry point.

## Writing policy

- Each item distinguishes **official spec citation**, **field verification result**, and **"was vague → now confirmed"**
- Discipline of separating `what spec guarantees` from `implementation side effects`
- Unverified items are marked `[未検証]` (= unverified; no fake confirmations spread)
- Source URLs cite primary references (code.claude.com/docs/en/...)

## Reference URLs (primary sources)

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins.md)
- [Plugins Reference](https://code.claude.com/docs/en/plugins-reference.md)
- [Skills](https://code.claude.com/docs/en/skills.md)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces.md)
- [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins.md)
- [Hooks Guide](https://code.claude.com/docs/en/hooks-guide.md)
- [Hooks Reference](https://code.claude.com/docs/en/hooks.md)

## Documentation

- [docs/DESIGN.md](./docs/DESIGN.md) — Current implementation (domain + architecture)
- [docs/STRUCTURE.md](./docs/STRUCTURE.md) — Repository physical structure

## License

MIT License, Yoshiaki Kawazu (@kawaz)
