# CLI リファレンス (`claude` コマンド)

[実機検証済: v2.1.177] `claude --help` 由来 (option/subcommand の **実在と choices**) + 個別オプションは実機 invoke で挙動確認したものを実機検証ラベル付き。`[spec]` は help 文の記述に依存し挙動を invoke で確認していないもの。

## 構造

```
claude [options] [command] [prompt]
```

- 引数なし起動 → 対話セッション
- `[prompt]` (位置引数) または stdin → 入力テキスト
- `-p` / `--print` を付けると **non-interactive モード** に切替 (= 1 ターン応答後 exit)
- `[command]` がある場合は subcommand (= `claude plugin list` 等) を実行

非対話モードで使う option は多くが `--print` 必須。詳細は [--print 依存マトリクス](#--print-依存マトリクス) を参照。

## モード切替 (interactive ↔ --print)

| option | 説明 | 依存 |
|---|---|---|
| `-p, --print` | 1 turn で exit。pipe 用途 | - |
| `--output-format <text\|json\|stream-json>` | 出力形式 | `--print` |
| `--input-format <text\|stream-json>` | 入力形式 | `--print` |
| `--include-hook-events` | hook lifecycle event を stream に含める | `--print` + `--output-format=stream-json` |
| `--include-partial-messages` | partial message chunk を含める | `--print` + `--output-format=stream-json` |
| `--replay-user-messages` | stdin の user message を stdout に echo back | `--input-format=stream-json` + `--output-format=stream-json` |
| `--no-session-persistence` | session を `~/.claude*/projects/...` に保存しない | `--print` |
| `--max-budget-usd <amount>` | API コスト上限 (= 超えた時点で打ち切り) | `--print` |
| `--fallback-model <model>` | primary 不在時の fallback (comma-separated 可) | `--print` |
| `--prompt-suggestions [true\|false\|...]` | turn 終了時に `prompt_suggestion` message を emit (preset: true) | `--print` (SDK) |

### --print 依存マトリクス

| option | --print | --output-format | --input-format |
|---|:---:|:---:|:---:|
| `--fallback-model` | ✅ | - | - |
| `--max-budget-usd` | ✅ | - | - |
| `--no-session-persistence` | ✅ | - | - |
| `--include-hook-events` | ✅ | `stream-json` | - |
| `--include-partial-messages` | ✅ | `stream-json` | - |
| `--replay-user-messages` | ✅ | `stream-json` | `stream-json` |
| `--input-format` | ✅ | - | - |
| `--output-format` | ✅ | - | - |

### --print 必須エラーの実観測

[実機検証済: v2.1.177] `--print` が必須な option を `--print` なしで指定すると stderr に:

```
Error: Input must be provided either through stdin or as a prompt argument when using --print
```

(= claude が「これは --print モードのオプションだ」と判断した後 prompt 不在で落ちる)

`--include-partial-messages` だけは別経路で:

```
Error: --include-partial-messages requires --print and --output-format=stream-json.
```

(= partial は output-side 制約も合わせてチェックされる)

### `--output-format=json` の実出力構造

[実機検証済: v2.1.177] **単一プロンプトでも JSON array** が返る (`json` という名前から想像する single object ではない)。要素は `system × N → assistant × M → result × 1` の混合並び:

```jsonc
[
  {"type":"system", ...},   // プラグイン/skill 初期化等の system event
  {"type":"assistant", ...},  // 応答 chunk
  {"type":"result",
    "subtype":"success",       // or "error_max_budget_usd" 等
    "duration_ms":6802,
    "duration_api_ms":0,
    "is_error":false,
    "num_turns":1,
    "stop_reason":"end_turn",
    "session_id":"<uuid>",
    "total_cost_usd":0.10,
    "modelUsage": {
      "claude-haiku-4-5-20251001": {
        "inputTokens":10, "outputTokens":90,
        "cacheReadInputTokens":17415, "cacheCreationInputTokens":49136,
        "webSearchRequests":0, "costUSD":0.10,
        "contextWindow":200000, "maxOutputTokens":32000
      }
    },
    "permission_denials":[],
    "fast_mode_state":"off",
    "uuid":"<uuid>",
    "errors":[],                 // budget exceeded 時はここに reason
    "structured_output": {...}   // --json-schema 指定時のみ。詳細は下記
  }
]
```

実用パターン:

```bash
# 最後の result 要素だけ抜く
claude -p "..." --output-format json | jq '.[-1]'
# assistant 応答テキスト (= result.result, --json-schema なし時)
claude -p "..." --output-format json | jq -r '.[-1].result // empty'
# structured output (= --json-schema あり時)
claude -p "..." --output-format json --json-schema '...' | jq '.[-1].structured_output'
```

### `--max-budget-usd` の cache 込み挙動

[実機検証済: v2.1.177] `total_cost_usd` は **cache read / cache creation を含む累計**。`claude -p "hi"` 一発でも plugin/skill 初期化分の cache create で **$0.10 級まで膨らみうる**。検証スクリプトでは `--max-budget-usd 1.0` 程度を渡しておかないと作業途中で `error_max_budget_usd` で打ち切られる。

打ち切り時の result element:

```json
{"type":"result","subtype":"error_max_budget_usd","is_error":true,"errors":["Reached maximum budget ($0.05)"]}
```

## モデル / effort

| option | 説明 |
|---|---|
| `--model <model>` | エイリアス (`fable` `opus` `sonnet`) または full name (例 `claude-fable-5`) |
| `--effort <low\|medium\|high\|xhigh\|max>` | エフォートレベル |
| `--fallback-model <model[,model]>` | primary 過負荷時の fallback。各 user turn の冒頭で primary を再試行 |

### option バリデーション強度の不揃い

[実機検証済: v2.1.177] `--effort` に未知値を渡すと **warning だけ出して default で続行**:

```
Warning: Unknown --effort value 'invalid' — ignoring it and using the default effort. Valid values: low, medium, high, xhigh, max.
```

一方 `--output-format` / `--input-format` / `--permission-mode` の未知値は **commander の strict choices 違反で即 exit**:

```
error: option '--output-format <format>' argument 'invalid' is invalid. Allowed choices are text, json, stream-json.
```

→ 同じ「choices 制限」でも `--effort` だけ「未知値は無視して default」というゆるい挙動。

### `--effort` の効果観測

[実機検証済: v2.1.177] `--effort` は **debug log にも session jsonl にも `effort` field として出ない** (= 直接観測不能)。間接観測経路:

- session jsonl の `output_tokens` 差 (= 実測 `low`: 256, `max`: 320)
- assistant message の thinking 文字数差 (= 実測 `low`: 271 字, `max`: 430 字 ≈ 1.6 倍)

→ API 側 thinking budget_tokens に反映されていると推定。CLI 側 log では追えないので、効果確認は出力統計に頼る。

## セッション / 履歴

| option | 説明 |
|---|---|
| `-c, --continue` | 直近の会話を **同 cwd** から続行 |
| `-r, --resume [value]` | session ID で resume、または interactive picker (`value` は search term) |
| `--fork-session` | resume 時に新 session ID で fork (= `--resume` / `--continue` と併用) |
| `--session-id <uuid>` | 既存 session を **指定 UUID で起動** (= reproducible) |
| `--from-pr [value]` | PR 番号 / URL に紐づく session を resume |
| `-n, --name <name>` | display name (prompt box / `/resume` picker / terminal title) |
| `--no-session-persistence` | session を保存しない (`--print` 専用) |

[実機検証済: v2.1.177] `--no-session-persistence -p ...` 実行前後で `~/.claude*/projects/<encoded-cwd>/*.jsonl` の数に **差分 0** (= 期待通り `.jsonl` は作られない)。

## 設定ロード / sandbox

| option | 説明 |
|---|---|
| `--settings <file-or-json>` | 設定 JSON file path **または** JSON 文字列 |
| `--setting-sources <user,project,local>` | 読込スコープを限定 (default は全部) |
| `--add-dir <directories...>` | tool アクセス許可ディレクトリ追加 (`--bare` 時は CLAUDE.md 探索 dir も兼ねる) |
| `--mcp-config <configs...>` | MCP server config (JSON file path **または** JSON 文字列、複数可) |
| `--strict-mcp-config` | `--mcp-config` のみ使い、ユーザ設定の MCP server は無視 |
| `--plugin-dir <path>` | local dir or .zip から plugin を **当該セッション限定でロード** (repeatable) |
| `--plugin-url <url>` | URL から .zip を fetch して plugin として load (repeatable) |
| `--agents <json>` | inline JSON で custom agent 定義 — 参照: [agents.md](agents.md) |
| `--agent <agent>` | セッションを丸ごと特定 agent として起動 (`settings.json` の `agent` を上書き) |
| `--system-prompt <prompt>` | system prompt を **完全置換** (default の dynamic section は出力されない) |
| `--append-system-prompt <prompt>` | default system prompt に **追記** |
| `--exclude-dynamic-system-prompt-sections` | 機種依存 section (cwd / env info / memory paths / git status) を **first user message に移動** (= prompt cache 再利用率向上)。`--system-prompt` 時は無視 |
| `--file <specs...>` | 起動時に download する file (`file_id:relative_path` 形式) |

### `--plugin-dir` で local plugin が即ロードされる

[実機検証済: v2.1.177] 仮 plugin (= `<tmp>/myplug/.claude-plugin/plugin.json` + `<tmp>/myplug/skills/myskill/SKILL.md`) を `--plugin-dir <tmp>/myplug` で渡して `-p` 起動すると、応答中の skill 一覧に `myplug:myskill` が現れる (= 通常起動では非表示の名前空間付き skill 名)。CI / SDK での「checkout 内 plugin の dry-run 起動」に使える。

### `--system-prompt` / `--append-system-prompt` の挙動

[実機検証済: v2.1.177]

- `--system-prompt "You always answer in exactly one English word."` → 応答が `Blue.` (= 完全置換成立)
- `--append-system-prompt "Always start your reply with the word ZEBRA."` → 応答の先頭行が `ZEBRA` で始まる (= append 成立、default system prompt と共存)

`--system-prompt` を渡すと `--exclude-dynamic-system-prompt-sections` は無視される (= dynamic section 自体が default system prompt 側に存在するため、置き換え後は対象が消える)。

### `--add-dir` 未指定は **deny** ではなく **permission prompt**

[実機検証済: v2.1.177] 権限外 path を Read しようとすると、`--add-dir` 無し時は **permission deny ではなく user 確認 prompt 待ち** になる。`--print` モードでは prompt 不能なので **blocked として返る** (= 結果は read 失敗だが、理由は権限 deny ではなく「対話できないから」)。`--add-dir <path>` で事前許可しておくと直接読める。

## 権限 / tool 制御

| option | 説明 |
|---|---|
| `--permission-mode <acceptEdits\|auto\|bypassPermissions\|default\|dontAsk\|plan>` | パーミッションモード |
| `--allowedTools, --allowed-tools <tools...>` | allowlist (例: `"Bash(git *) Edit"`、空白 or comma 区切り) |
| `--disallowedTools, --disallowed-tools <tools...>` | denylist |
| `--tools <tools...>` | built-in tool subset を指定。`""` で全 disable、`"default"` で全 enable、`"Bash,Edit,Read"` で個別指定 |
| `--dangerously-skip-permissions` | 全権限 check skip (sandbox 専用) |
| `--allow-dangerously-skip-permissions` | bypass mode を **option として available にする** (= default では bypass にしない、明示要求があれば bypass)。`agents` subcommand 等で「dispatched session にだけ bypass を許可」する用途 |
| `--disable-slash-commands` | 全 skill 無効化 |

`--permission-mode` の choices は `acceptEdits` / `auto` / `bypassPermissions` / `default` / `dontAsk` / `plan` 6 種。未知値は即 error。

## デバッグ / 診断

| option | 説明 |
|---|---|
| `-d, --debug [filter]` | debug ログ有効化 (`--debug api,hooks` allowlist / `--debug '!1p,!file'` denylist) |
| `--debug-file <path>` | debug log を file に書き出し (implicitly enables `--debug`) |
| `--verbose` | config の verbose 設定を上書きで有効化 |
| `--mcp-debug` | **deprecated**。`--debug` に統合済み |
| `--safe-mode` | カスタマイズ無効で起動 (= `CLAUDE_CODE_SAFE_MODE=1`)。詳細は [distribution.md](distribution.md#トラブルシュート----safe-mode-と-bundled-skills-無効化) |
| `--bare` | 最小モード ([下記](#--bare-vs---safe-mode) 参照) |

### `--debug` filter 構文

[実機検証済: v2.1.177] `--debug-file` で log を取り、`[<category>]` prefix を grep すると実カテゴリが見える。観測された category 例 (= 起動 1 回で出てきたもの):

- `[init]` — 初期化シーケンス
- `[auto-mode]` — auto mode 判定
- `[claudeai-mcp]` — claude.ai 連携 MCP
- `[cmux-msg]` — plugin (cmux-msg) 由来
- `[mcp-registry]` — MCP registry

help text の例示 (`api,hooks` / `!1p,!file`) と組み合わせて:

```bash
claude --debug api,hooks -p "..."         # allowlist
claude --debug '!1p,!file' -p "..."       # denylist (! prefix で除外)
claude --debug -p "..."                   # filter 無し = 全 category
claude --debug-file /tmp/debug.log -p "..."   # --debug 不要、file 出力だけで自動有効化
```

未知 category を渡しても **エラーにはならない** (= 該当 category のログが出ないだけ)。

### `--bare` vs `--safe-mode`

両方とも diagnostic / minimal mode だが範囲が違う。

| | `--safe-mode` | `--bare` |
|---|---|---|
| 環境変数 | `CLAUDE_CODE_SAFE_MODE=1` | `CLAUDE_CODE_SIMPLE=1` |
| 用途 | 設定壊れ / hook 暴走の診断 | 最小 footprint で SDK / pipeline 用 |
| CLAUDE.md 自動探索 | ❌ | ❌ |
| **plugin** (= marketplace + skills-dir) | ❌ | ❌ |
| **plugin hooks** | ❌ (= "Skipping plugin hooks - safe mode disables plugins") | ❌ |
| **managed (policy) settings の hooks** | ✅ ("managed settings-file hooks still run") | ❌ (= 想定) |
| **bundled skills** (= `deep-research` / `update-config` / `code-review` 等) | ✅ 残る | ❌ |
| **plugin/user skills** (= `myplug:myskill` / `grill-me` 等) | ❌ | `/skill-name` 経路で resolve は通る |
| LSP / auto-memory / background prefetch / keychain read / attribution | 通常通り | ❌ |
| Anthropic auth | OAuth / keychain / API key すべて | **strict**: `ANTHROPIC_API_KEY` または `apiKeyHelper` (via `--settings`) のみ。OAuth / keychain は読まない |
| 3P provider (Bedrock / Vertex / Foundry) | 通常通り | 通常通り (各 SDK の credential) |
| context 注入経路 | 全部復活して読まれる | `--system-prompt[-file]` / `--append-system-prompt[-file]` / `--add-dir` / `--mcp-config` / `--settings` / `--agents` / `--plugin-dir` を**明示**で渡す |

[実機検証済: v2.1.177]

- `--safe-mode -p "invoke 可能な skill を 1 個挙げて"` → bundled skill (deep-research 等) のみ列挙、plugin skill は不在
- `--safe-mode` の debug log に `Skipping plugin hooks - safe mode disables plugins (managed settings-file hooks still run)` と `[claudeai-mcp] Disabled in safe mode`
- `--bare` で auth 未設定 → `Not logged in · Please run /login` で exit
- `ANTHROPIC_API_KEY=sk-bogus claude --bare -p hi` → `Invalid API key · Fix external API key` (= OAuth は試さない、必ず API key 経路)

> **distribution.md の `--safe-mode` 表との整合**: 同 doc の表は当初「safe-mode で skills が無効」と書いていたが、実機では **bundled skills は残る** (= plugin/user 起源の skill のみ無効)。`disableBundledSkills` との二段構えで全 skill を完全に消す。

## 構造化出力 (`--json-schema`)

[実機検証済: v2.1.177] `--json-schema <schema>` は JSON Schema を渡して **structured output** を強制する。`--output-format json` と組み合わせるのが想定。

```bash
claude -p "Tokyo の人口を返して" \
  --model sonnet \
  --output-format json \
  --json-schema '{"type":"object","properties":{"city":{"type":"string"},"population":{"type":"number"}},"required":["city","population"]}'
```

結果は `--output-format json` の array 末尾 `type:"result"` 要素の **`structured_output` field** (= `.result` ではない):

```jsonc
{
  "type":"result",
  "result":"",                                  // 空文字列 (= テキスト応答は出ない)
  "structured_output": {"city":"Tokyo", "population":13960000}  // ←ここに入る
}
```

抽出:

```bash
claude -p "..." --output-format json --json-schema '...' | jq '.[-1].structured_output'
```

haiku では schema 解釈が弱い場合あり、sonnet 以上推奨。

## 起動連携 / IDE / Chrome

| option | 説明 |
|---|---|
| `--ide` | 起動時に唯一の valid IDE が居れば自動接続 |
| `--chrome` / `--no-chrome` | Chrome 連携 ON/OFF |
| `-w, --worktree [name]` | 起動時に **新 git worktree** を作って入る (任意名) |
| `--tmux` | worktree に tmux session を作る (`--worktree` 必須)。iTerm2 native panes 可、`--tmux=classic` で従来 tmux |
| `--remote-control [name]` | Remote Control 有効化 (= MCP/SDK 経路) |
| `--remote-control-session-name-prefix <prefix>` | auto-generated session 名の prefix (default: hostname) |
| `--brief` | `SendUserMessage` tool (agent → user) を有効化 |
| `--betas <betas...>` | beta header を API request に付与 (API key user のみ) |

## メタ

| option | 説明 |
|---|---|
| `-h, --help` | help 表示 |
| `-v, --version` | バージョン |

## subcommand 一覧

各 subcommand には個別の `--help` がある。全 17 subcommand。

### `claude plugin` / `claude plugins`

| subcommand | 主要 option |
|---|---|
| `init`/`new <name>` | `--with <skills\|agents\|hooks\|mcp\|lsp\|output-style\|channel>`, `--author`, `--author-email`, `--description`, `-f`/`--force` |
| `install`/`i <plugin>` | `--config <key=value>` (userConfig 設定、repeatable), `-s`/`--scope <user\|project\|local>` (default `user`) |
| `list` | `--available` (marketplace の available も含める、`--json` 必須), `--json` |
| `enable <plugin>` | `-s`/`--scope` |
| `disable [plugin]` | `-a`/`--all`, `-s`/`--scope` |
| `uninstall`/`remove <plugin>` | `--keep-data` (data dir 残す), `--prune` (依存も削除), `-s`/`--scope`, `-y`/`--yes` |
| `update <plugin>` | `-s`/`--scope` (`managed` も可) |
| `details <name>` | (component inventory + projected token cost) |
| `prune`/`autoremove` | `--dry-run`, `-s`/`--scope`, `-y`/`--yes` |
| `tag [path]` | `--dry-run`, `-f`/`--force`, `-m`/`--message <msg>` (`%s` で version 展開), `--push`, `--remote` (default `origin`)。`{name}--v{version}` 形式の tag 作成 + plugin.json / marketplace 整合確認 |
| `validate <path>` | `--strict` (warnings を error に昇格、CI 用) |
| `marketplace add <source>` | `--scope <user\|project\|local>`, `--sparse <paths...>` (monorepo の sparse-checkout) |
| `marketplace list` | `--json` |
| `marketplace remove <name>` | `--scope` (省略で全 scope から削除) |
| `marketplace update [name]` | (省略時は全 marketplace を update) |

`claude plugin list` には `--enabled` / `--disabled` フィルタは **無い** (対話 UI `/plugin list` のみ)。詳細は [distribution.md](distribution.md#plugin-list--有効無効フィルタ-実機検証済-v21170)。

### `claude mcp`

| subcommand | 主要 option |
|---|---|
| `add <name> <commandOrUrl> [args...]` | `-t`/`--transport <stdio\|sse\|http>` (default stdio), `-e`/`--env KEY=value`, `-H`/`--header "X-Api-Key: ..."`, `--client-id`, `--client-secret`, `--callback-port`, `-s`/`--scope <local\|user\|project>` (default `local`) |
| `add-json <name> <json>` | `--client-secret`, `-s`/`--scope` |
| `add-from-claude-desktop` | `-s`/`--scope` (Mac / WSL のみ) |
| `list` | (`.mcp.json` の未承認 server は `⏸ Pending approval` 表示) |
| `get <name>` | server 詳細 + health check |
| `remove <name>` | `-s`/`--scope` (省略で実在 scope から削除) |
| `reset-project-choices` | (`.mcp.json` の承認/拒否を全 reset) |
| `serve` | Claude Code MCP server 起動 (`-d`/`--debug`, `--verbose`) |

### `claude auth`

| subcommand | 主要 option |
|---|---|
| `login` | `--claudeai` (default), `--console` (Console API billing), `--email`, `--sso` |
| `logout` | - |
| `status` | `--json` (default), `--text` |

### `claude auto-mode`

| subcommand | 説明 |
|---|---|
| `config` | 現行 auto mode config を JSON 出力 (= user settings + defaults を合成) |
| `defaults` | default の env / allow / soft_deny / hard_deny を JSON 出力 |
| `critique` | custom rule に AI feedback (`--model <model>` で model 切替) |

### `claude agents` (background agents)

[spec] dispatched (= background) session の default を制御。option は **CLI top-level と多くが重複**:

`--add-dir`, `--agent`, `--allow-dangerously-skip-permissions`, `--cwd <path>` (= 起動 cwd でフィルタ), `--dangerously-skip-permissions`, `--effort`, `--json` (= active sessions 一覧、`--all` で完了済みも含む), `--mcp-config`, `--model`, `--permission-mode`, `--plugin-dir`, `--setting-sources`, `--settings`, `--strict-mcp-config`

### `claude project`

| subcommand | 説明 |
|---|---|
| `purge [path]` | project 状態を全削除 (transcripts / tasks / file history / config entry) |

### その他 subcommand

| subcommand | 説明 |
|---|---|
| `doctor` | auto-updater health check。`.mcp.json` の stdio server も spawn される (= trust 必要) |
| `install [target]` | native build install (`--force`, `target` は `stable` / `latest` / specific version) |
| `update` / `upgrade` | update check + install |
| `setup-token` | 長期 auth token セットアップ (Claude subscription 必須) |
| `ultrareview [target]` | cloud 上で multi-agent code review (`--json` で raw bugs.json, `--timeout <minutes>` default 30) |

## 環境変数 (CLI フラグと連動)

| 変数 | 同等オプション / 効果 |
|---|---|
| `CLAUDE_CODE_SAFE_MODE=1` | `--safe-mode` |
| `CLAUDE_CODE_SIMPLE=1` | `--bare` |
| `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1` | `disableBundledSkills: true` settings (= bundled skills のみ無効化) |
| `MCP_CLIENT_SECRET` | `claude mcp add --client-secret` で prompt される値の先読み |
| `ANTHROPIC_API_KEY` | API key 認証 (= `--bare` モードで必須経路の 1 つ) |

## 関連

- [distribution.md](distribution.md) — `--safe-mode` 詳細 / `plugin list` の `--enabled` 非対応 / version bump
- [skills.md](skills.md) — `--disable-slash-commands` で何が止まるか / `--plugin-dir` 経由 skill resolve
- [hooks.md](hooks.md) — `--include-hook-events` で stream に乗る event の構造
- [agents.md](agents.md) — `--agents` (JSON inline) / `--agent` の挙動と `agents` subcommand との関係

## 未検証 TODO

- [ ] `--plugin-url <url>` で fetch 経路と cache 場所
- [ ] `--mcp-config '{...}'` (= inline JSON 文字列) と file path 両方の挙動差
- [ ] `--strict-mcp-config` 時に **`.mcp.json` の project-scope server** が確実に無視されるか
- [ ] `--setting-sources user` だけにした時に `project` / `local` settings が読まれないことの観測
- [ ] `--agents '{...}'` (JSON inline) で複数 agent 定義時の挙動 (`--agent` で個別選択可能か)
- [ ] `--exclude-dynamic-system-prompt-sections` で system prompt の cwd/env/git/memory section が first user message に移動することの実観測
- [ ] `--remote-control` の session-name-prefix 規約
- [ ] `--file file_id:relative_path` の `file_id` 取得経路 (Claude.ai upload 由来 ?)
- [ ] `--betas` の有効 header 値 list (= 現行受理される文字列)
- [ ] `claude project purge` の削除範囲 (= memory / auto-memory / tasks の全 vs 一部)
- [ ] `claude agents --json` の active session schema
- [ ] `--safe-mode` で `managed settings` の hooks が動くことの確認 (現状は debug log 文言ベースの推定)
