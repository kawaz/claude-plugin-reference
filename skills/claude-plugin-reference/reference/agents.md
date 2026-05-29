# エージェント編 — plugin が配る subagent

plugin は専用の subagent (カスタムエージェント) を同梱できる。skill が「context に流し込む手順書」なのに対し、agent は「別 context window で動く専用ワーカー」。Claude が task に応じて自動委譲したり、ユーザが明示的に呼び出したりする。

## 配置 (Location)

- 既定は **plugin root の `agents/` ディレクトリ** [spec]
- `.md` ファイル 1 つ = agent 1 つ。**再帰スキャン**されるのでサブフォルダで整理できる [spec]
- `.claude-plugin/` の中ではなく **plugin root** に置く (`.claude-plugin/` に入るのは `plugin.json` のみ) [spec]

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json
└── agents/
    ├── security-reviewer.md
    └── review/
        └── perf.md
```

## plugin.json の `agents` フィールド

既定の `agents/` 以外を使いたい場合のみ指定する。**省略時は `agents/` を自動走査するので不要** [spec]。

| field | 型 | 意味 |
|---|---|---|
| `agents` | `string` \| `array` | カスタム agent ファイルのパス。既定の `agents/` を**置き換える** (replaces) |

```json
{ "agents": ["./custom/agents/reviewer.md"] }
```

> **注意 [spec]**: `skills` は既定 `skills/` に**追加** (in addition) だが、`agents` と `commands` は既定を**置き換える** (replaces)。`agents` を書くと `agents/` 配下は走査されなくなるので、カスタムパスを足すなら既定分も明示的に列挙する。

## agent ファイルの形式

YAML frontmatter + Markdown body。**body がそのまま system prompt** になる [spec]。subagent は full な Claude Code system prompt を受け取らず、**この body + 作業ディレクトリ等の基本環境のみ**で動く [spec]。

```markdown
---
name: security-reviewer
description: コード変更のセキュリティ観点レビュー。脆弱性が疑われる diff で proactive に使う
model: sonnet
tools: Read, Grep, Glob, Bash
---

You are a security reviewer. 変更を分析し、脆弱性・権限昇格・入力検証漏れを指摘する。
...
```

## frontmatter フィールド一覧 [spec]

出典: [sub-agents.md](https://code.claude.com/docs/en/sub-agents.md) の supported frontmatter fields 表。

| field | 必須 | 意味・値 | plugin agent |
|---|---|---|---|
| `name` | **Yes** | 識別子 (lowercase + hyphen)。hook はこの値を `agent_type` として受け取る。**ファイル名と一致しなくてよい** (identity は `name` のみ) | ○ |
| `description` | **Yes** | いつ委譲すべきか。Claude はこれを読んで自動委譲を判断する | ○ |
| `tools` | No | 使えるツール。**省略時は全継承**。Skill の preload は `Skill` を列挙せず `skills` field を使う | ○ |
| `disallowedTools` | No | 拒否するツール。継承/指定リストから除外 | ○ |
| `model` | No | `sonnet` / `opus` / `haiku` / full model ID (例 `claude-opus-4-8`) / `inherit`。**既定 `inherit`** | ○ |
| `effort` | No | `low` / `medium` / `high` / `xhigh` / `max`。session の effort を上書き。利用可能段階は model 依存 | ○ |
| `maxTurns` | No | 停止までの最大 agentic turn 数 | ○ |
| `skills` | No | 起動時に context へ preload する skill。**description だけでなく skill 本文全体が注入**される。未列挙の skill も Skill tool 経由で呼べる | ○ |
| `memory` | No | 永続メモリスコープ `user` / `project` / `local`。セッション横断学習 | ○ |
| `background` | No | `true` で常に background task として実行。既定 `false` | ○ |
| `isolation` | No | `worktree` で一時 git worktree 上で実行 (default branch 基点の独立コピー、無変更なら自動削除)。**plugin agent では値は `"worktree"` のみ許可** | △ |
| `permissionMode` | No | `default` / `acceptEdits` / `auto` / `dontAsk` / `bypassPermissions` / `plan` | **✕ plugin では無視** |
| `mcpServers` | No | この subagent が使う MCP server (名前参照 or inline 定義) | **✕ plugin では無視** |
| `hooks` | No | この subagent にスコープされた lifecycle hook | **✕ plugin では無視** |

### plugin agent の制限 [spec]

> For security reasons, plugin subagents do not support the `hooks`, `mcpServers`, or `permissionMode` frontmatter fields.

`hooks` / `mcpServers` / `permissionMode` は **plugin 同梱 agent では無視される** (security 理由)。必要なら:

- agent ファイルを `.claude/agents/` または `~/.claude/agents/` に**コピー**すれば制限解除 [spec]
- または `settings.json` / `settings.local.json` の `permissions.allow` にルール追加 (ただし**セッション全体に効く**、plugin agent 限定にはならない) [spec]

## 名前空間 [spec]

plugin が配る agent は **`<plugin-name>:<agent-name>`** で参照される。

> plugin `plugin-dev` の agent `agent-creator` は UI 上 `plugin-dev:agent-creator` と表示される。

- `name` frontmatter が agent の identity。ファイルパス/ファイル名は identity に影響しない [spec]
- 同一スコープ内で `name` が重複すると、**片方が警告なく破棄**される。tree 全体で `name` をユニークに保つ [spec]
- `[未検証]` plugin 内でサブフォルダ (`agents/review/perf.md`) を切ったとき、名前空間が `<plugin>:review:perf` のように階層化されるか。project/user scope では「サブフォルダは identity に影響しない」と明記 [spec] があるが、plugin scope での階層化挙動は公式に明記なし → 要実機検証

## 配置スコープと優先度 [spec]

同名 agent が複数スコープにある場合、優先度が高い方が勝つ。

| スコープ | 場所 | 備考 |
|---|---|---|
| managed | managed settings の `.claude/agents/` | 組織管理者配布。**project/user より優先** |
| project | `.claude/agents/` | リポジトリ共有。再帰スキャン |
| user | `~/.claude/agents/` | 全プロジェクト共通。再帰スキャン |
| plugin | plugin root `agents/` | plugin 有効時。`<plugin>:<name>` で参照 |
| CLI | `--agents` flag (JSON) | 現セッションのみ。`prompt` で system prompt を渡す |

`.claude/agents/` と `~/.claude/agents/` は**再帰スキャン**され、`agents/review/` 等のサブフォルダで整理できる (identity は `name` のみなのでパスは無関係) [spec]。

## 起動方法 [spec]

1. **自動委譲**: Claude が `description` を読み、task に合致すれば自動で agent を選んで委譲する
2. **明示呼び出し (自然言語)**: 「Use the security-reviewer subagent to ...」のように prompt で agent 名を指定
3. **Task / Agent tool**: `subagent_type` に agent 名を渡して spawn
4. **セッション全体を agent 化**: `claude --agent <name>` または `settings.json` の `agent` key
   - plugin の `settings.json` でサポートされるのは `agent` と `subagentStatusLine` の 2 key のみ [spec]

## skill の `context: fork` + `agent:` との関係 [spec]

skill 側からも agent を指名できる (詳細は [skills.md](skills.md) の Subagent execution)。

- **agent の `skills` field** (agent → skill): subagent が自分の system prompt を持ち、起動時に指定 skill の本文を context へ注入する
- **skill の `context: fork` + `agent:`** (skill → agent): skill 起動時に、その skill 本文を指定 agent の context へ流し込む

向きが逆の関係。`agent:` で custom agent を指す場合、その agent は上記スコープのいずれかに存在する必要がある。

## `[未検証]` TODO

このリポの規律として、未検証項目は格上げ前提で明示する。

- [ ] plugin scope でのサブフォルダ → 名前空間階層化の有無 (上記名前空間節)
- [ ] `claude plugin validate` が agent frontmatter のどこまで (必須 field 欠落 / 未サポート field) を検出するか
- [ ] plugin agent で `hooks` / `mcpServers` / `permissionMode` を書いたとき、警告が出るか黙って無視か
- [ ] `agents` field 指定時に既定 `agents/` が本当に走査されなくなる (replaces) かの実機確認
- [ ] `/agents` UI 上での plugin agent の表示・有効化挙動

## 参考 URL (出典)

- [Subagents](https://code.claude.com/docs/en/sub-agents.md) — frontmatter / スコープ / 起動方法の正本
- [Plugins reference — Agents](https://code.claude.com/docs/en/plugins-reference.md) — plugin.json `agents` field / 名前空間 / plugin agent の制限
- [Plugins](https://code.claude.com/docs/en/plugins.md)
