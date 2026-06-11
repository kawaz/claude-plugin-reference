# claude-plugin-reference Design

> English | [日本語](./DESIGN-ja.md)

## Domain

A reference that **aggregates field-verified primary-source information** to address two pain points in Claude Code plugin development: "official docs alone don't make the behavior clear" and "every plugin repeats the same explanations."

The target audience is both AI agents (Claude Code itself) and humans. A single SKILL is provided whose table of contents streams into context on AI invocation.

## Architecture

### Overall layout

```
claude-plugin-reference (plugin)
├── skills/claude-plugin-reference/   # Single skill: ToC + on-demand reference
│   ├── SKILL.md                       # ToC only. Streams into AI context on invocation
│   └── reference/                     # Per-topic details (loaded on demand)
│       ├── distribution.md
│       ├── hooks.md
│       ├── skills.md
│       ├── commands.md
│       └── agents.md
└── hooks/                             # SessionStart nudge
    ├── hooks.json
    └── plugin-repo-nudge.sh
```

### Skill: two-tier ToC + on-demand reference

SKILL.md is kept to **just a table of contents**, minimizing the always-streamed context. When the AI wants a specific topic, it opens `reference/<topic>.md` via Read. This gives us:

- Cheaper skill invocation (= AI can use it casually for "just a quick look")
- Localized impact when adding topics (= add a new file without touching existing references)

### Hook: SessionStart nudge

On `SessionStart`, injects a one-line `additionalContext`. The condition is an **OR**:

1. `.claude-plugin/plugin.json` exists (= working in a plugin repo)
2. A `CLAUDE_PROJECT_DIR` path element **starts with** `claude-rules-` (= kawaz's rule-overlay repo naming convention; fires even at the repo root). This is a prefix match, so unrelated repos sharing the prefix also fire — accepted as a known false-positive trade-off.
3. A `CLAUDE_PROJECT_DIR` path element is exactly `.claude`, or **starts with** `.claude-` (= directly editing a Claude config dir, e.g. `~/.claude-personal`)

Matching is done at path-element boundaries (= append a trailing `/` to `$root` and match `*/<elem>/*`), on the literal (non-realpath-resolved) path string. This avoids false positives on unrelated dirs with a dash-less suffix like `.claudexyz`, and still fires when `claude-rules-personal` is the repo root itself.

The `hooks.json` matcher is the empty string (`""`) = it intentionally fires on every SessionStart source (startup / resume / clear / compact).

Silent for non-matching sessions (= plugin hooks fire in *every* enabled session, so the design avoids noise).

### Distribution flow

Built around `bump-semver` + `justfile` to **consolidate gates at push**:

- `just push` is the entry point (= direct `jj git push` is blocked by the push-guard hook)
- The canonical gate list is the `push` recipe's `deps` in `justfile` (= single source of truth; do not re-enumerate here, it drifts). Key intents: working-tree clean, plugin spec validation, tests, multi-file version consistency, bump-required-on-trigger-change, translation-lag detection, embedded-justfile sync, bare-label detection.
- After a successful push, `on-success-release` auto-updates the marketplace / plugin locally

See [STRUCTURE.md](./STRUCTURE.md) and `justfile` for details.

## Key design decisions

Zero DRs at the moment (= structure is still simple). When decisions multiply, they'll be carved out into `docs/decisions/DR-NNNN-*.md` and tracked via INDEX.md.

## Related documents

- [STRUCTURE.md](./STRUCTURE.md) — Physical structure
- [README.md](../README.md) — User-facing overview / install
