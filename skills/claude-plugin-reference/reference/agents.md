# エージェント編 — plugin が配る subagent

> `[spec]` = 公式 docs に明示記述、`[実機検証済]` = 自分の plugin で検証済、`[未検証]` = 公式記述頼りで実機未確認、`[実装の副産物]` = spec 保証なしの挙動
> - 無ラベル行の既定は `[spec]` (公式 docs 由来)。記憶・推測由来の項目は `[未検証]` を明示する。
> - `[実機検証済: ~vX.Y.Z]` の `~` は記述導入時期からの推定バージョン (当時の再検証記録ではない)。

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
| `effort` | No | `low` / `medium` / `high` / `xhigh` / `max`。session の effort を上書き。利用可能段階は model 依存 (値セットの正本は [hooks.md §6.1](hooks.md#61-共通フィールド)) | ○ |
| `maxTurns` | No | 停止までの最大 agentic turn 数 | ○ |
| `skills` | No | 起動時に context へ preload する skill。**description だけでなく skill 本文全体が注入**される。未列挙の skill も Skill tool 経由で呼べる | ○ |
| `memory` | No | 永続メモリスコープ `user` / `project` / `local`。セッション横断学習 | ○ |
| `background` | No | `true` で常に background task として実行。既定 `false` | ○ |
| `isolation` | No | `worktree` で一時 git worktree 上で実行 (default branch 基点の独立コピー、無変更なら自動削除)。**plugin agent では値は `"worktree"` のみ許可** | △ |
| `permissionMode` | No | 6 値: `default` / `plan` / `acceptEdits` / `auto` / `dontAsk` / `bypassPermissions` (= permission_mode 値セットの正本は [hooks.md §6.1](hooks.md#61-共通フィールド)) | **✕ plugin では無視** |
| `mcpServers` | No | この subagent が使う MCP server (名前参照 or inline 定義) | **✕ plugin では無視** |
| `hooks` | No | この subagent にスコープされた lifecycle hook | **✕ plugin では無視** |

### plugin agent の制限 [spec]

> For security reasons, plugin subagents do not support the `hooks`, `mcpServers`, or `permissionMode` frontmatter fields.

`hooks` / `mcpServers` / `permissionMode` は **plugin 同梱 agent では無視される** (security 理由)。必要なら:

- agent ファイルを `.claude/agents/` または `~/.claude/agents/` に**コピー**すれば制限解除 [spec]
- または `settings.json` / `settings.local.json` の `permissions.allow` にルール追加 (ただし**セッション全体に効く**、plugin agent 限定にはならない) [spec]

## 組み込み agent (built-in)

CLI 組み込みの agent (plugin 非経由) も存在する。`claude agents --json` の `init` イベントの `agents` 配列に、plugin 提供分と並んで `Explore` / `general-purpose` / `Plan` / `statusline-setup` 等の名前が確認できる [実機検証済: v2.1.199]。

- **Explore**: main session が `sonnet` / `opus` の場合、Explore subagent の transcript も同じモデルで実行されることを確認 (= モデル継承) [実機検証済: v2.1.199]。CHANGELOG は「main session のモデルを継承 (capped at opus)、従来は haiku 固定」と主張 (v2.1.198) [spec] — opus 超のモデルで main session を起動した際の cap 挙動は、検証中に main session 自体のモデルが途中で fallback する事象が発生し切り分けできず [未検証: TODO]
- **general-purpose**: frontmatter 通り `model: inherit` で動作 (haiku session → haiku subagent を確認) [実機検証済: v2.1.199]

### Agent tool の permission matcher と background 経路

- v2.1.186 で **`Agent(type:foo)` deny rule と `Agent(x,y)` allowed-types 制限が named subagent spawn に対しても enforce** されるよう修正 [spec] (CHANGELOG v2.1.186)
- v2.1.186 で **background subagent の permission prompt は auto-deny でなく main session に surface** されるよう変更 [未検証: 対話 UI 専用、headless 観測不能] (CHANGELOG v2.1.186)
- v2.1.187 で **Agent tool の `schema` parameter / `--json-schema` の structured output**: model が成功後の `StructuredOutput` を無限再呼出ししなくなり、後続ターンも structured output を確実に返す [spec] (CHANGELOG v2.1.187)
- v2.1.153 で **非 plugin agent (project/user/CLI scope) の frontmatter `mcpServers`** が `--strict-mcp-config` / `--bare` / remote mode / enterprise managed MCP / managed-settings allow-deny policy を無視する bug を修正 [spec] (CHANGELOG v2.1.153)。plugin agent は元から `mcpServers` 自体が無視される (上記の制限を参照)

## 名前空間 [spec]

plugin が配る agent は **`<plugin-name>:<agent-name>`** で参照される。

> plugin `plugin-dev` の agent `agent-creator` は UI 上 `plugin-dev:agent-creator` と表示される。

- `name` frontmatter が agent の identity。ファイルパス/ファイル名は identity に影響しない [spec]
- 同一スコープ内で `name` が重複すると、**片方が警告なく破棄**される。tree 全体で `name` をユニークに保つ [spec]
- `[未検証: TODO]` plugin 内でサブフォルダ (`agents/review/perf.md`) を切ったとき、名前空間が `<plugin>:review:perf` のように階層化されるか。project/user scope では「サブフォルダは identity に影響しない」と明記 [spec] があるが、plugin scope での階層化挙動は公式に明記なし → 要実機検証

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

v2.1.178 で **nested `.claude/` の名前衝突は cwd に最も近いものが勝つ** ようになった (agent / workflow / output-style 共通)。project-scope の workflow 保存も最寄りの既存 `.claude/workflows/` を target にする [spec] (CHANGELOG v2.1.178)。

## 起動方法 [spec]

1. **自動委譲**: Claude が `description` を読み、task に合致すれば自動で agent を選んで委譲する
2. **明示呼び出し (自然言語)**: 「Use the security-reviewer subagent to ...」のように prompt で agent 名を指定
3. **Task / Agent tool**: `subagent_type` に agent 名を渡して spawn
   - v2.1.178 で agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) は **`TeamCreate` / `TeamDelete` tool を削除**。各セッションに暗黙の team が常在し、Agent tool の **`name` parameter で teammate を直接 spawn** する。旧 `team_name` parameter は受理されるが ignored [spec] (CHANGELOG v2.1.178)
   - v2.1.198 で agent teams (experimental): API エラーで死んだ teammate は lead に "failed" と報告されるようになり、詰まった teammate へのメッセージ送信で即座に retry させられるよう改善 [spec] (CHANGELOG v2.1.198)
   - v2.1.199 で `SendMessage` tool: re-spawned agent が既存 agent と同名を再利用した際の誤ルーティングを検出し、呼び出し元に retarget を促すよう修正 [spec] (CHANGELOG v2.1.199)
4. **セッション全体を agent 化**: `claude --agent <name>` または `settings.json` の `agent` key
   - plugin の `settings.json` でサポートされるのは `agent` と `subagentStatusLine` の 2 key のみ [spec]
   - `claude agents --dangerously-skip-permissions` (= `--permission-mode bypassPermissions` の alias、`claude agents --help` で存在確認済み [実機検証済: v2.1.199]) は v2.1.196 で dispatch 先 background agent への bypass mode 適用漏れ (auto mode への silent fallback) を修正 [spec] (CHANGELOG v2.1.196)。dispatch 経路自体は対話 UI 専用のため挙動再現は未検証
   - `claude agents` から dispatch した background agent は worktree でのコード作業完了時、質問せず commit / push / draft PR 作成まで自動で行うよう変更 (従来は stop して確認) [spec] (CHANGELOG v2.1.198)。対話 UI 専用のため未検証

### 既定で background 実行 (v2.1.198+)

Agent tool で spawn した subagent は既定で **background task として実行**され、終了時に通知される (従来は gradual rollout) [spec] (CHANGELOG v2.1.198)。`--output-format=stream-json` で観測すると次の system event 列が流れる [実機検証済: v2.1.199]:

`task_started` (`subagent_type` / `prompt` 付き) → 子の tool_use (`parent_tool_use_id` で親の Agent tool_use id と紐付けられ同一ストリームに混在) → `task_progress` (`usage.tool_uses` / `duration_ms`) → `task_updated` (`status: "completed"`) → `task_notification` (`summary` に最終応答、`output_file` に subagent transcript への symlink)

- subagent は起動元 agent からのメッセージを通常のタスク指示として扱うが、**その agent のメッセージがユーザの承認として扱われることは決してない**と明文化された [spec] (CHANGELOG v2.1.198)
- subagent と context compaction は session の extended thinking 設定 (`--effort`) を継承する: `--effort low` の親から spawn した subagent の transcript には `thinking` content block が一切出現しない一方、`--effort max` の親からの subagent には `thinking` block が出現する (内容が空でも type としては出現) ことを確認 [実機検証済: v2.1.199] (CHANGELOG v2.1.198 は「output 品質向上のため」と説明)

### subagent 失敗時の挙動 [spec] (CHANGELOG v2.1.199)

- レート制限 / サーバエラーで打ち切られた subagent は、従来 silently 失敗していたが **部分成果 (partial work) を親 agent に返す**よう修正
- subagent の API エラー (usage limit reached 等) が誤って成功結果として親に報告されるバグを修正、エラーは正しく親 agent に報告される

### subagent 自身による再帰 spawn (ネスト)

subagent (子) も自分の context で `Agent` / `Task` tool を使い、さらに別の subagent (孫) を spawn できる (v2.1.172 で解禁。出典: CHANGELOG v2.1.172「Sub-agents can now spawn their own sub-agents (up to 5 levels deep)」)。

- 子が `Agent` tool を呼んで孫を起動でき、拒否されない (= 親→子→孫の 2 段ネストが成立) [実機検証済: v2.1.174]
- トークン文字列を孫に渡し、孫→子→親と伝言させて最終応答まで往復できる (孫での加工も保持) ことを確認 [実機検証済: v2.1.174]
- **最大 5 階層まで** [spec] (出典: CHANGELOG v2.1.172)。ただし v2.1.174 実測では反証: **183 階層の単一チェーンが一度も spawn 拒否されず成立** (= 拒否としての階層上限は観測されない) [実機検証済: v2.1.174]
- v2.1.181 で foreground subagent も background と同じ 5 段 cap を尊重するよう修正 [spec] (CHANGELOG v2.1.181)。**v2.1.199 で再観測**: Agent tool の再帰 spawn を実施したところ depth 1〜5 までは成立し、6 段目 (depth=5 の環境) では `Agent` tool 自体が ToolSearch で見つからず spawn 不能だった (= 明示的な拒否イベントではなく tool の不可視化で cap が働く) [実機検証済: v2.1.199]。v2.1.174 時点の「183 階層が拒否されず成立」という反証は解消された
- v2.1.187 で depth tracking 修正: **resumed subagent は元の spawn depth を復元**、**forked subagent も depth cap にカウント**される [spec] (CHANGELOG v2.1.187)
- ネストは transcript 上も一直線の親子連鎖として記録される (子の `subagents/agent-*.meta.json` の `toolUseId` = 親 transcript 内の Agent tool_use id、で親子辺を辿れる) [実機検証済: v2.1.174]
- ネストには子が `Agent` / `Task` tool を持つことが前提。`tools` field で除外した場合に spawn 不能になるかは未観測 [未検証]

## `claude agents --json` の出力スキーマ [実機検証済: v2.1.170]

スクリプトから background session の状態を取得する用途向け。

```bash
claude agents --json          # アクティブセッション (background 含む)
claude agents --json --all    # 完了済みセッションも含む
```

各エントリのフィールド:

| フィールド | 型 | 出現条件 | 値の例 |
|---|---|---|---|
| `pid` | number | 常に | `46808` |
| `sessionId` | string | 常に | `"0ac2d19f-0069-..."` |
| `cwd` | string | 常に | `"/path/to/repo"` |
| `kind` | string | 常に | `"background"` / `"interactive"` |
| `startedAt` | number | 常に | Unix ms タイムスタンプ |
| `status` | string | ほぼ常に (起動直後は欠落の場合あり) | `"idle"` / `"busy"` / `"waiting"` |
| `id` | string | **background のみ** | `"0ac2d19f"` (sessionId 先頭 8 文字) |
| `name` | string | background かつ名前あり | `"config-setup-agents"` |
| `state` | string | **background のみ** | `"blocked"` (他の値は未観測) |
| `waitingFor` | string | waiting 状態時のみ (optional) | `"permission prompt"` [実機検証済: v2.1.199] |

- `id`: background session の短縮識別子。`sessionId` の先頭 8 文字と一致する
- `state`: background session の追加状態。`"blocked"` = permission prompt 等で待機中
- `waitingFor`: 実機で `status:"waiting"` と併せて値 `"permission prompt"` を観測 (= 権限確認待ちで停止中の session) [実機検証済: v2.1.199]。観測は `kind:"interactive"` の session のみ、`kind:"background"` での出現有無は未確認
- `--all` [未検証: TODO]: `--help` 文言では「完了済みセッションも含む (the full agent view list)」。完了済みセッションが併存する状態での出力差は実機未観測

## `/agents` wizard の廃止 (v2.1.198)

対話用の agent 作成ウィザード `/agents` は削除された。headless (`-p`) で叩くと以下の案内が返る [実機検証済: v2.1.199]:

> The /agents wizard has been removed. Ask Claude to create or update subagents for you (e.g. "create a code-reviewer subagent that ..."), or edit the files directly: `.claude/agents/` (this project) / `~/.claude/agents/` (all projects)

`claude agents` (スペースなし CLI subcommand、§`claude agents --json`) は background session 管理用の**別機能**で廃止対象ではない。

## skill の `context: fork` + `agent:` との関係 [spec]

skill 側からも agent を指名できる (詳細は [skills.md](skills.md) の Subagent execution)。

- **agent の `skills` field** (agent → skill): subagent が自分の system prompt を持ち、起動時に指定 skill の本文を context へ注入する
- **skill の `context: fork` + `agent:`** (skill → agent): skill 起動時に、その skill 本文を指定 agent の context へ流し込む

向きが逆の関係。`agent:` で custom agent を指す場合、その agent は上記スコープのいずれかに存在する必要がある。

## `[未検証]` 集約 (メンテ TODO 抽出用)

このリポの規律として、未検証項目は格上げ前提で明示する。`[未検証: headless 不可]` は対話 UI 専用で構造的に検証不能、`[未検証: TODO]` はやれば検証できる。

### headless 不可

(該当なし。旧 `/agents` wizard UI に関する項目は wizard 廃止 [実機検証済: v2.1.199] により解消)

### TODO

- [ ] plugin scope でのサブフォルダ → 名前空間階層化の有無 (上記名前空間節)
- [ ] `claude plugin validate` が agent frontmatter のどこまで (必須 field 欠落 / 未サポート field) を検出するか
- [ ] plugin agent で `hooks` / `mcpServers` / `permissionMode` を書いたとき、警告が出るか黙って無視か
- [ ] `agents` field 指定時に既定 `agents/` が本当に走査されなくなる (replaces) かの実機確認
- [ ] `claude agents --json --all` の完了済みセッション出力差 (§claude agents --json、`waitingFor` は v2.1.199 で実機確認済み)
- [ ] Explore built-in agent の「opus 超モデルでの main session 実行時、cap が実際に opus に効くか」(§組み込み agent、v2.1.199 検証時は main session 自体のモデルが途中 fallback し切り分け不能だった)

## 参考 URL (出典)

- [Subagents](https://code.claude.com/docs/en/sub-agents.md) — frontmatter / スコープ / 起動方法の正本
- [Plugins reference — Agents](https://code.claude.com/docs/en/plugins-reference.md) — plugin.json `agents` field / 名前空間 / plugin agent の制限
- [Plugins](https://code.claude.com/docs/en/plugins.md)
