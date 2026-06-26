# フック編 — 全 Hook event / matcher / JSON input/output schema / blockable / 強制力

cmux-msg / hyoui / その他 plugin で hooks を書く時のリファレンス。各 event について「タイミング / 主要用途 / 何ができるか / JSON input/output schema」を整理。

> `[spec]` = 公式 docs に明示記述、`[実機検証済]` = 自分の plugin で検証済、`[未検証]` = 公式記述頼りで実機未確認、`[実装の副産物]` = spec 保証なしの挙動
> - 無ラベル行の既定は `[spec]` (公式 docs 由来)。記憶・推測由来の項目は `[未検証]` を明示する。
> - `[実機検証済: ~vX.Y.Z]` の `~` は記述導入時期からの推定バージョン (当時の再検証記録ではない)。

## 1. 配置と発見順序

| 位置 | スコープ | 共有可 |
|---|---|---|
| `~/.claude/settings.json` の `hooks` | user 全体 | × |
| `.claude/settings.json` の `hooks` | project | ✓ (git 管理) |
| `.claude/settings.local.json` の `hooks` | project | × (gitignore) |
| plugin の `hooks/hooks.json` | plugin enable 中 | ✓ (plugin bundle) |
| skill / agent frontmatter の `hooks` | その component 有効期間中 | ✓ |
| Managed policy settings | 組織全体 | (deny rule は常に優先) |

複数 scope に同一 event があれば **並行実行** (= 一方が他方を上書きしない、merge)。[spec]

`PreToolUse` の permission decision が複数 hook で衝突した場合、**最も制限的な結果が勝つ** (`deny > ask > allow`)。[spec]

### project-scope の正本 / 紛らわしい誤配置

- **正本**: `.claude/settings.json` の `hooks` field [実機検証済: v2.1.193]
- **`.claude/hooks.json` 単独ファイルは認識されない** — 「`hooks/hooks.json`」は **plugin 専用形式** (= plugin root 直下の `hooks/hooks.json`)。project-scope で `.claude/hooks.json` を置いても silent に無視されるので注意 [実機検証済: v2.1.193, side effect file の発火記録なしで確認]
- `--settings <file>` 経路の `hooks` field も発火する。user-scope settings (= `~/.claude/settings.json` 等) と **additive merge** されて両方の hook が並行発火する [実機検証済: v2.1.193]
- **複数 `--settings` は last-wins** (= CC は最後の 1 個のみ採用、hook arrays の concat はしない)。cmux 等は事前に deep merge して `--settings` 1 個で渡す回避策を取る [実機検証済: v2.1.193, cmux-claude-wrapper 内コメント記述と一致]
- **workspace trust 未取得** の workspace では `permissions.allow` は ignored になるが、**`hooks` field は発火する** (非対称) [実機検証済: v2.1.193]

## 2. Hook event 一覧

### 2.1 セッション系

| event | matcher 値 | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `SessionStart` | `startup` / `resume` / `clear` / `compact` | session 開始 / resume / clear / compact 後 | env 初期化 / meta 書き込み / direnv 連携 / skill 動的設置 | additionalContext で文脈 inject / `sessionTitle` で title 設定 / `reloadSkills:true` で skill 再スキャン (= §6.2、[実機検証済: v2.1.170]) | × (exit 2 は stderr 表示のみ) |
| `SessionEnd` | (なし) | session 終了直前 | cleanup / 永続化 | (output 無視) | × |
| `post-session` | (なし) | **session 終了後・workspace 削除前** (self-hosted runner 専用) | 未コミット成果の snapshot / log export | 子プロセスの SIGTERM→SIGKILL 猶予 (既定 5s) を設定可 | [未検証: headless 不可] |
| `Setup` | `init` / `maintenance` | `--init-only` or `-p --init/--maintenance` 実行時 | 初期化処理 | (用途限定) | × |

> **`post-session` (changelog 2.1.169) [未検証: headless 不可]**: self-hosted runner (CI runner 等) のライフサイクルで、session 終了 → workspace 削除の **間** に走る lifecycle hook。ローカル対話 / headless `claude -p` には「workspace 削除フェーズ」が存在しないため **構造的に実機検証不能** (= 個人環境では発火させられない)。公式 hooks reference (code.claude.com/docs/en/hooks.md) にも未記載で、出典は CHANGELOG 2.1.169 のみ。
> **SessionEnd との差**: `SessionEnd` は session 終了「直前」に走り output は無視される汎用 cleanup フック。`post-session` は session 終了「後」かつ runner が workspace を破棄する「前」という self-hosted runner 限定のタイミングで、未コミット作業の退避 / ログ持ち出しと、子プロセス強制終了の猶予時間調整を目的とする。

### 2.2 ユーザ入力系

| event | matcher | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `UserPromptSubmit` | (なし) | ユーザ prompt submit 直後、claude 処理前 | input ログ / 自動 prompt 加工 | additionalContext inject、exit 2 で turn 拒否 | ✓ (exit 2) |
| `UserPromptExpansion` | skill/command 名 | user-typed command が prompt 展開される直前 | 展開内容の filter | exit 2 で block | ✓ |

### 2.3 ツール系 (最重要、blockable 多)

| event | matcher | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `PreToolUse` | tool 名 (regex / alternation) | tool call 実行直前 | permission gate / input rewrite | `permissionDecision: allow/deny/ask/defer`、`updatedInput` で tool 引数差し替え | ✓ (deny は **bypassPermissions mode でも効く**) |
| `PostToolUse` | tool 名 | tool 成功直後 | format / lint / log | exit 2 で turn block | ✓ |
| `PostToolUseFailure` | tool 名 | tool 失敗直後 | エラー処理 | additionalContext inject | ✓ |
| `PostToolBatch` | (なし) | parallel tool 群が全 resolve した後 | batch 後処理 | additionalContext | ✓ |
| `PermissionRequest` | tool 名 | permission dialog 表示直前 | auto-approve | `behavior: allow/deny/ask`、`updatedPermissions` で mode 切替 | ✓ |
| `PermissionDenied` | tool 名 | auto-mode classifier の deny 後 | retry 制御 | `retry: true` で再試行 | ✓ |

### 2.4 Turn 終端系

| event | matcher | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `Stop` | (なし) | 毎 turn 終了直後 | task 完了確認 | `decision: "block"` + `reason` で turn 再開 (max 8 連続)。または `hookSpecificOutput.additionalContext` で **hook error 扱いにせず** feedback 注入して会話継続 [実機検証済: v2.1.170] | ✓ |
| `StopFailure` | (なし) | turn が API error で失敗 | エラー報告 | (output 無視) | × |
| `Notification` | type (e.g. `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`) | notification 表示直前 | desktop 通知 / sound | terminalSequence で OSC 777 等 | × |

### 2.5 Compaction / Cwd / FS 系

| event | matcher | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `PreCompact` | (なし) | context compaction 直前 | 永続化 | additionalContext | [未検証: TODO] |
| `PostCompact` | (なし) | compaction 完了直後 | re-init | additionalContext | [未検証: TODO] |
| `CwdChanged` | (なし) | working dir 変更時 | direnv / env reload | `CLAUDE_ENV_FILE` 書き込みで bash tool に env 反映 | [未検証: TODO] |
| `ConfigChange` | source (`user_settings` / `project_settings` / `local_settings` / `policy_settings` / `skills`) | config file が外部で変更 | reload 制御 | `decision: "block"` で block 可 | ✓ |
| `FileChanged` | file pattern | watched file 変更 | リアクション処理 | additionalContext | [未検証: TODO] |
| `WorktreeCreate` | (なし) | git worktree 作成時 | hook into worktree setup | default git behavior を replace 可 | ✓ |
| `WorktreeRemove` | (なし) | git worktree 削除時 | cleanup | [未検証: TODO] | [未検証: TODO] |
| `InstructionsLoaded` | reason (= source 値セットの正本: `session_start` / `nested_traversal` / `path_glob_match` / `include` / `compact`) | CLAUDE.md / rules がコンテキスト load 時 | rule 監査 | [未検証: TODO] | [未検証: TODO] |

### 2.6 Subagent / Task 系

| event | matcher | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `SubagentStart` | agent type | subagent spawn 直前 | log / 拒否 | [未検証: TODO] | [未検証: TODO] |
| `SubagentStop` | agent type | subagent 終了直後 | result 加工 | `decision: "block"` + `reason` で subagent turn 再開、または `hookSpecificOutput.additionalContext` で feedback 注入し継続 (= Stop と同等)。発火は [実機検証済: v2.1.170]、additionalContext の注入先は subagent コンテキスト [spec] | ✓ [spec、block 動作は未検証] |
| `TaskCreated` | (なし) | TaskCreate 生成直前 | task 監査 | [未検証: TODO] | [未検証: TODO] |
| `TaskCompleted` | (なし) | task completion 直前 | result 確認 | [未検証: TODO] | [未検証: TODO] |
| `TeammateIdle` | (なし) | teammate idle 状態 | スケジューリング | [未検証: TODO] | [未検証: TODO] |

### 2.7 MCP 系

| event | matcher | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `Elicitation` | mcp server 名 | MCP server がユーザ input request 時 | UI 介入 | [未検証: TODO] | [未検証: TODO] |
| `ElicitationResult` | mcp server 名 | ユーザ応答後、server に返す前 | filter | [未検証: TODO] | [未検証: TODO] |

### 2.8 その他

| event | matcher | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `MessageDisplay` | (なし、常時発火) | assistant message text 表示直前 (streaming delta ごと + final) | logging / 表示テキストの transform・hide | `hookSpecificOutput.displayContent` で **画面表示のみ** 置換 (transcript と claude が見る本文は元のまま) [実機検証済: v2.1.170] | × (表示置換のみ、turn は止まらない) |

`MessageDisplay` の stdin 固有フィールド [実機検証済: v2.1.170]:

| field | 値 |
|---|---|
| `delta` | この発火で表示されるテキスト断片 (= streaming chunk または final 全文) |
| `final` | bool。`true` なら message の最終表示 |
| `index` | 同一 message 内の発火順序 |
| `message_id` | 対象 assistant message の UUID |
| `turn_id` | turn の UUID |

`hookSpecificOutput.displayContent` を返すと headless `-p` の最終出力でも置換が反映される (= 表示パイプラインに効く)。表示専用なので block 能力は無い。

## 3. hooks.json 構造

```json
{
  "hooks": {
    "<EventName>": [
      {
        "matcher": "<pattern>",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh",
            "timeout": 600,
            "if": "Bash(git *)"
          }
        ]
      }
    ]
  }
}
```

- `EventName`: 大文字キャメルケース (`SessionStart` / `PreToolUse` 等、case-sensitive)
- 第 2 層 `matcher` グループ: 複数定義可、各々独立 (= 並行実行)
- 第 3 層 hook handler: `type` 指定 (= `command` / `http` / `mcp_tool` / `prompt` / `agent`)

### matcher 構文

| pattern | 説明 | 例 |
|---|---|---|
| `""` (空) | 全マッチ | tool 系以外で多用 |
| `"ToolName"` | 完全一致 | `"Edit"` |
| `"Tool1\|Tool2"` | alternation (regex ではなく文字列、backslash escape 必須) | `"Edit\|Write"` |
| `"Tool1,Tool2"` | comma 区切り alternation。両 tool で hook 発火 [実機検証済: v2.1.193]。以前は silent に発火しない bug があったが v2.1.191 で修正 [spec] | `"Bash,Read"` |
| `^Notebook` / `mcp__.*` | regex | MCP tool 命名 `mcp__<server>__<tool>` を `.*` で拾える |
| event 固有値 | SessionStart の `startup`/`resume`/`clear`/`compact` 等 | (event ごとに値が違う) |

### `if` field (v2.1.85+, blockable event 限定)

tool 引数で filter:

```json
{ "matcher": "Bash", "hooks": [{ "if": "Bash(git *)", "command": "..." }] }
```

`Edit(*.ts)` / `Bash(git *)` 形式。**blockable event のみ** (`PreToolUse` / `PostToolUse` / `PostToolUseFailure` / `PermissionRequest` / `PermissionDenied`)。

#### `Bash(...)` パターンの実コマンドマッチ挙動 [実機検証済: v2.1.170]

`Bash(<glob>)` は **コマンド文字列をそのまま glob 比較するのではなく、shell 構文を解析してサブコマンドごとに判定**する。`$()` / backtick 内 / leading `VAR=value` assignment / `&&`・`;` 区切りの各サブコマンドが展開され、いずれかが glob にマッチすれば発火する。「`$()` / `$VAR` を含むと無条件で全発火」ではない (= その誤発火は v2.1.163 で修正済)。

`if: "Bash(git *)"` で各種コマンドを headless 実行した実測マトリクス:

| Bash コマンド | 発火 | 理由 |
|---|---|---|
| `echo hello` | × | サブコマンドに `git` 無し |
| `git log --oneline` | ✓ | コマンド名 `git` 一致 |
| `FOO=bar git status` | ✓ | leading assignment 除去後 `git status` が一致 |
| `echo $(git status)` | ✓ | `$()` 内の `git status` を判定 |
| `` echo `git status` `` | ✓ | backtick 内の `git status` を判定 |
| `echo $HOME` | × | `$VAR` 展開しても `git` サブコマンド無し → 発火しない |
| `echo $(date)` | × | `$()` 内に `git` 無し → 発火しない |

ポイント: `$VAR` / `$()` を含むだけでは発火せず、**展開後に実際にコマンド名がマッチするかどうか**で決まる。公式 docs では「コマンド名より深く指定したパターン (`Bash(git push *)` 等) は `$()`/backtick/`$VAR` を含むコマンドに対して保守的に発火する (fail-open)」とされ、パース不能なコマンドも fail-open で発火する。本検証の `git *` はコマンド名のみ指定なので、上表どおり厳密判定が効く。

#### `Read(...)` / `Edit(...)` / `Write(...)` の path パターンマッチ挙動 [実機検証済: v2.1.177]

file 系 tool の `if` は **tool が触る file path** を glob 比較する。CHANGELOG 2.1.176 で「`Edit(src/**)` / `Read(~/.ssh/**)` / `Read(.env)` 等の documented pattern が正しくマッチするよう修正」された。v2.1.177 で実測したマトリクス:

| `if` パターン | 操作対象 | 発火 | 判定 |
|---|---|---|---|
| `Read(.env)` | `Read .env` | ✓ | dotfile 完全一致 |
| `Read(.env)` | `Read src/app.ts` | × | 別 path |
| `Read(src/**)` | `Read src/app.ts` | ✓ | 相対 glob (project dir 基準) |
| `Read(src/**)` | `Read plain.txt` | × | glob 外 |
| `Edit(src/**)` | `Edit src/app.ts` | ✓ | 相対 glob |
| `Edit(src/**)` | `Edit lib/util.ts` | × | glob スコープ境界 (`src/**` は `lib/**` を弾く) |
| `Write(out/**)` | `Write out/result.txt` | ✓ | 相対 glob |

ポイント:
- 相対 glob (`src/**` / `out/**`) は **project dir 基準**で解決される。
- dotfile 完全一致 (`.env`) も効く。
- glob のスコープ境界が正しく効く (`Edit(src/**)` は `lib/util.ts` の Edit を発火させない)。
- **注意**: `Edit` tool は実行前に対象を **Read** する。そのため `Edit src/app.ts` 時には `Edit(src/**)` だけでなく `Read(src/**)` の `if` も評価・発火する。Edit 専用 hook を書いたつもりでも、同じ path に対する Read 系 `if` が先に走る点に注意。
- **`~` ホーム展開 glob も効く**: `Read(~/.ssh/**)` や `Read(~/<dir>/**)` のような `~` 始まりパターンは home 展開されてマッチする (home 直下・`~/.ssh/**` の両方で発火を実機確認、`~` パターンが project 内 path を誤マッチしないことも確認)。これで CHANGELOG 2.1.176 が挙げた 3 例 (`Edit(src/**)` / `Read(.env)` / `Read(~/.ssh/**)`) すべてが実機追認済み。
- **mid-pattern wildcard も効く**: `Read(secrets-*/config.json)` のように path 途中に `*` を含むパターンは settings.json の `permissions.deny` で受理 + 実機 match する (v2.1.172 で startup 時 reject される bug が修正) [実機検証済: v2.1.193, deny rule 経路で確認]。

#### `Tool(param:value)` syntax (settings.json permission rule 限定) [実機検証済: v2.1.193]

v2.1.178 で permission rule に `Tool(param:value)` 形式 (= tool 入力 param の値で match、`*` wildcard 可、例 `Agent(model:opus)`) が追加された [spec]。ただし **native matcher を持つ tool (`Bash` / `Read` / `Edit` / `Write` 等) では rule loader が以下の warning を吐いて当該 rule を無視する** [実機検証済: v2.1.193]:

```
Permission deny rule "Bash(command:...)" targets command as a raw string and will not match — use Bash(…) for Bash's own matcher.
Permission deny rule "Read(file_path:...)" targets file_path as a raw string and will not match — use Read(…) for Read's own matcher.
```

= Bash/Read/Edit/Write は従来の `Bash(<command pattern>)` / `Read(<path pattern>)` 形式 (§3 既述) を使う。`param:` 形式が有効なのは native matcher を持たない tool (例: `Task(subagent_type:...)` 形式は loader 受理を確認) のみ [実機検証済: v2.1.193, loader 受理のみ確認。実際の deny 動作は subagent spawn を伴うため [未検証: TODO]]。

## 4. Hook command の type 種別

| type | 主な field | timeout default | 用途 |
|---|---|---|---|
| `command` | `command` (shell), `args` (exec form), `statusMessage`, `once` | 600s (10 min) | 通常の script |
| `http` | `url`, `headers`, `allowedEnvVars` | 600s | REST 連携 |
| `mcp_tool` | `server`, `tool`, `arguments` | 600s | MCP tool 経由 |
| `prompt` | `prompt`, `model` (default `haiku`) | 30s | claude に判断 |
| `agent` | `prompt`, `maxTurns` | 60s | subagent 実行 |

`UserPromptSubmit` event の hook は強制的に 30s に short-circuit。[spec]

### `command` type の shell-form / exec-form [実機検証済: v2.1.170]

- **shell-form** (`command: "..."` のみ): shell (bash) で実行。`#` 以降は comment、`&&` / pipe / 変数展開も効く。
- **exec-form** (`command: "..."` + `args: [...]`): shell を介さず argv を **literal** で渡す。`args` の各要素はそのまま引数になり、`#` も comment 化されない。
- → §9.0 の plugin 識別子マーカー (`... #marker`) は **shell-form 限定**。exec-form では `#marker` が literal 引数になる。

## 5. Hook process の env

| 変数 | 値 | 範囲 |
|---|---|---|
| `CLAUDE_PROJECT_DIR` | **cwd 起点で解決** ([実機検証済: v2.1.193] `--settings file` 配置 dir / `--add-dir` は反映しない、cwd ≠ project root の場合 `$CLAUDE_PROJECT_DIR/...` を使う hook command は silent fail) | 全 hook |
| `CLAUDE_PLUGIN_ROOT` | `$CLAUDE_CONFIG_DIR/plugins/cache/<id>/<version>/` | plugin hook のみ |
| `CLAUDE_PLUGIN_DATA` | `$CLAUDE_CONFIG_DIR/plugins/data/<id>/` (= plugin update でも保持) | plugin hook のみ |
| `CLAUDE_ENV_FILE` | temp file path、source して env 反映 | CwdChanged / SessionStart 等 |

[実機検証済: ~v2.1.156 (cmux-msg)] hook 起動時の cwd は **stdin の `cwd` field と一致しない可能性** — hook 内で操作したい場合は `cd "$cwd"` で明示移動が必要。

## 6. JSON input schema

### 6.1 共通フィールド

`session_id` / `cwd` / `hook_event_name` / `transcript_path` の 4 つは、**`SessionStart` / `UserPromptSubmit` / `PreToolUse` / `Stop` の 4 event で実測**して全て揃っていた [実機検証済: v2.1.170]。「全 event 共通フィールド」という一般化自体は公式 hooks docs の共通フィールド表 [spec] によるもので、上記 4 event 以外への一般化はその spec 記述が根拠 (= 全 event を個別に実測したわけではない)。`permission_mode` / `effort` は **event とモデルに依存**して来る/来ない。

```json
{
  "session_id": "<UUID v4>",
  "cwd": "/current/working/directory",
  "hook_event_name": "<EventName>",
  "transcript_path": "/path/to/transcript.jsonl",
  "permission_mode": "default|plan|acceptEdits|auto|dontAsk|bypassPermissions",
  "effort": { "level": "low|medium|high|xhigh|max" }
}
```

| field | 範囲 | 備考 |
|---|---|---|
| `session_id` / `cwd` / `hook_event_name` / `transcript_path` | 全 event ([spec] の共通フィールド表) | 4 event (`SessionStart` / `UserPromptSubmit` / `PreToolUse` / `Stop`) で実測 [実機検証済: v2.1.170]、全 event への一般化は [spec] |
| `permission_mode` | 一部 event のみ | **有効値 6 種 (= permission_mode 値セットの正本)**: `default` / `plan` / `acceptEdits` / `auto` / `dontAsk` / `bypassPermissions` [spec]。**`SessionStart` には来ない** [実機検証済: v2.1.170]。各 event の JSON 例で要確認 [spec] |
| `effort` | tool-use 文脈の event (`PreToolUse` / `PostToolUse` / `Stop` / `SubagentStop`) かつ effort 対応モデル時のみ | `{"level": ...}`。**effort 値セットの正本** = `low` / `medium` / `high` / `xhigh` / `max` [spec、`xhigh` の出典は公式 docs 由来で実機未観測]。opus で `high` を観測、haiku では欠落 [実機検証済: v2.1.170]。`$CLAUDE_EFFORT` env でも参照可 [spec] |
| `agent_id` / `agent_type` | subagent 文脈で発火する hook のみ非 null | main thread では両方 `null`。subagent (`--agent` / Task) 内では `agent_type` に agent 名 (custom subagent は frontmatter の `name`) [実機検証済: v2.1.170。Task `general-purpose` 内 PreToolUse で確認] |

> **注 (負の確定事実)**: `claude_config_dir` / `project_root` という field は **どの event の stdin にも来ない** (公式 hooks docs の共通フィールド表にも無い) [実機検証済: v2.1.170]。それらしき記述を二次情報で見ても追加しないこと。config dir / project root が要るなら env (`$CLAUDE_PROJECT_DIR` 等、§5) を使う。

### 6.2 event 固有フィールド

#### PreToolUse / PostToolUse

```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "npm test" },
  "tool_use_id": "toolu_...",            // PreToolUse で観測 [実機検証済: v2.1.170]
  "tool_output": { "result": "..." }     // PostToolUse のみ
}
```

#### SessionStart

input:

```json
{ "source": "startup" }   // or "resume" / "clear" / "compact"
```

output `hookSpecificOutput` 固有フィールド [実機検証済: v2.1.170]:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Current branch: feat/x",
    "sessionTitle": "feat-x-worktree",
    "reloadSkills": true,
    "watchPaths": ["/abs/path/to/watch"]
  }
}
```

| field | 効果 |
|---|---|
| `additionalContext` | 最初の prompt 前に claude のコンテキストへ注入 [実機検証済: v2.1.170] |
| `sessionTitle` | session title を設定 (= `/rename` 相当)。`source` が `startup` / `resume` の時のみ有効、`clear` / `compact` では無視 [spec、JSON 受理は実機確認済] |
| `reloadSkills` | `true` で SessionStart hook 完了後に skill / command directory を再スキャン → **hook が動的に設置した skill が同一 session 内で使用可能になる** [実機検証済: v2.1.170。hook で SKILL.md を設置 → 同 session でその skill が起動できることを確認] |
| `watchPaths` | この session 中 `FileChanged` を監視する絶対パス配列 [spec] |

#### UserPromptSubmit

```json
{ "prompt": "<user typed text>" }
```

#### Stop

```json
{
  "stop_hook_active": false,
  "last_assistant_message": "...",   // [実機検証済: v2.1.170]
  "background_tasks": [],             // [実機検証済: v2.1.170]
  "session_crons": []                // [実機検証済: v2.1.170]
}
```

`stop_hook_active: true` の時は max 8 連続 block 後に自動 continue (= 無限 block 防止)。`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` env で cap 調整可。
(`conversation_length` は [spec]、実測では上記 `last_assistant_message` / `background_tasks` / `session_crons` を観測。)

#### ConfigChange

```json
{
  "source": "user_settings|project_settings|local_settings|policy_settings|skills",
  "file_path": "/path/to/changed/file"
}
```

#### PermissionRequest / PermissionDenied

```json
{
  "tool_name": "Bash",
  "permission_prompt_type": "...",
  "reason": "..."   // Denied のみ
}
```

#### Notification

```json
{
  "notification_type": "permission_prompt|idle_prompt|auth_success|elicitation_dialog|..."
}
```

詳細は event ごとに公式 docs (= `hooks.md`) 参照。[spec]

## 7. JSON output schema + exit code

### 7.1 共通 output JSON

```json
{
  "continue": true,
  "suppressOutput": false,
  "systemMessage": "...",
  "terminalSequence": "\\033]777;notify;Title;Body\\007",
  "additionalContext": "Text to inject into Claude's context",
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny|allow|ask|defer",
    "permissionDecisionReason": "...",
    "updatedInput": { "command": "rewritten" },
    "updatedPermissions": [
      { "type": "setMode", "mode": "bypassPermissions|acceptEdits|default", "destination": "session|settings" }
    ]
  }
}
```

- `additionalContext`: claude のコンテキストに inject される追加テキスト (= tool event で `stdout` text を直接出してもこれに入る)。`Stop` / `SubagentStop` でも `hookSpecificOutput.additionalContext` が有効で、**hook error 扱いにならず会話を継続したまま** feedback を注入できる [実機検証済: v2.1.170]
- `systemMessage`: **UI 通知専用** — 画面に `<EventName>:<source> says: <text>` 形式で表示されるだけで、**AI context には注入されない** (= AI に直接「context に含まれるか」と聞かせて `Yes` を引き出せない、`additionalContext` と用途が違う) [実機検証済: v2.1.193]
- `hookSpecificOutput`: event ごとの decision (= PreToolUse なら permission、PermissionRequest なら behavior)

### SessionStart hook で AI を自走させる経路は存在しない [実機検証済: v2.1.193]

引数 prompt 無し起動 (`claude` のみ) で AI を自走 trigger する hook output 経路は **無い**。検証した 6 mode 全 fail: `additionalContext` / 推測フィールド `injectAsUserPrompt` / `hookSpecificOutput.userMessage` / top-level `userPrompt` / `systemMessage` / async 経路の 2 行目 `systemMessage`。`additionalContext` は AI context に届くが「AI が自発的に何か実行する」ことはない (= ユーザの prompt submit が turn を回す前提)。自動実行を期待する plugin は**起動時の引数 prompt** をユーザに要求する必要がある。

### async hook 経路 [実機検証済: v2.1.193]

stdout 1 行目に `{"async": true, "asyncTimeout": <ms>}` を出力すると **claude プロセス側が hook を background 化**して session 開始を待たない。完了時に「`Async hook <hookName> completed`」UI 通知が出る (= sync の「`<EventName>:<source> hook success:`」と別経路)。

- `asyncTimeout` 既定 15000 ms、`forceSyncExecution: true` 指定で sync 強制
- **自動検出経路あり**: 1 行目 JSON が async response shape を持てば `async: true` 明記なしでも async 化 (= バイナリ内部 `ome()` 判定)
- exit 後、stdout の **2 行目以降を行ごとに JSON parse**、最初の **非 async** JSON 行が hook response として採用される (= `metrics` キーは hook metrics event に forward)
- async response の value は **bool/finite-number に限定** (= 公式 docs に「short strings 可」と書かれているのは誤り、ensure_agent_sdk.py の Anthropic 実装コメント由来)
- **async 経路の `systemMessage` も UI 通知** (= AI context に届かないのは sync 経路と同じ)
- 出典: `claude-plugins-official/security-guidance` の `hooks/ensure_agent_sdk.py:722-740` が venv 構築を bg 化するため明示 async を返す canonical 例

### 7.2 Exit code 意味

| exit code | 意味 | behavior |
|---|---|---|
| **0** | 成功、decision なし | stdout JSON があれば parse & apply、text なら additionalContext へ |
| **2** | block / error | event ごとに block (= PreToolUse: tool block、UserPromptSubmit: turn 拒否、Stop: turn 再開、SessionStart/SessionEnd/Notification は ignored) |
| **その他** | non-blocking error | warning 表示、execution 継続、stderr 1 行目が transcript に |

### 7.3 PreToolUse permission decision の細部

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "..."
  }
}
```

| decision | 効果 |
|---|---|
| `allow` | permission prompt skip。**deny rule は依然有効** (= hook は restriction を tighten はできるが loosen はできない) |
| `deny` | tool call block。**bypassPermissions mode でも有効** (= policy として enforce) |
| `ask` | normal permission prompt flow |
| `defer` | 公式 hooks docs が `permissionDecision` の有効値として列挙 [spec] (allow/deny/ask/defer)。ただし `defer` の具体的挙動 (= 何に委譲するか) は docs の該当節に明記がなく、「non-interactive mode (`-p` flag) でのみ有効」という従来記述は裏取りできていない [未検証: TODO] |

## 8. Hook の強制力 (Permission との関係)

| 優先 | rule | 効果 |
|---|---|---|
| 1 (最強) | Hook `deny` (exit 2 or `permissionDecision: deny`) | tool call 必ず block (bypassPermissions でも) |
| 2 | Permission rule `deny` | hook で override 不可 |
| 3 | Hook `allow` | permission prompt skip、ただし deny rule は再チェック |
| 4 | Permission prompt / auto-mode classifier | normal flow |

= Hook は **policy として enforce 可能**、permission settings を override する形ではなく追加制約として動く。[spec]

## 9. 実装上の落とし穴 (実機検証 / 経験則)

### 9.0 ベストプラクティス: Plugin 識別子マーカーを command 末尾に埋める

claude runtime は hook block / error の表示で **展開前の command string** を identifier として使う:

```
PreToolUse:Bash hook error: [${CLAUDE_PLUGIN_ROOT}/hooks/push-guard.sh]: BLOCK: ...
                            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                            展開前の literal、ここから plugin 名が読み取れない
```

= **どの plugin から出たエラーか identify できない** 問題。

回避策: hooks.json の command 末尾に **bash comment 形式の plugin 識別子マーカー** を埋める:

```json
{
  "type": "command",
  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/push-guard.sh\" #push-guard"
}
```

- パスは **必ず `"..."` でクオート**する (`"${CLAUDE_PLUGIN_ROOT}/.../xxx.sh"`)。展開後の実体パスに空白が含まれる環境で word splitting して壊れるのを防ぐ。
- bash shell-form では `#` 以降が comment 扱い = script 実行に影響しない [実機検証済: v2.1.170。settings.json hook で `echo X #marker` を発火 → 出力は `X` のみ。加えて kawaz/claude-push-guard v0.3.1 / 本リポの SessionStart hook で配備、block/inject とも正常動作]
- claude runtime の error 表示は **展開前 command string を `[...]` に literal でそのまま出す**ので、`#push-guard` がそこに見える = plugin 名を識別可 [実機検証済: v2.1.170。下記参照]

```
PreToolUse:Bash hook error: [${CLAUDE_PLUGIN_ROOT}/hooks/push-guard.sh #push-guard]: BLOCK: ...
                                                                       ^^^^^^^^^^^
                                                                       これで plugin 名わかる
```

**実機で確認した error ヘッダ形式** [実機検証済: v2.1.170]: settings.json 直書きの PreToolUse(Bash) hook を `exit 2 #blockmarker-DDD` で発火させたところ、`--output-format json` の tool_result error に以下が literal で出た (grep `hook error: \[.*#blockmarker-DDD\]` が pass):

```
PreToolUse:Bash hook error: [echo BLOCKED_BY_HOOK_XYZ >&2; exit 2 #blockmarker-DDD]: BLOCKED_BY_HOOK_XYZ
```

`[...]` の中身は command 文字列の literal で、末尾 `#marker` もそこに含まれる = この workaround の核心メカニズムは確認済み。

**制約**:
- shell-form (= `command: "..."` のみ) で有効。exec-form (= `command` + `args` 同時指定) では `#` が **literal 引数として渡される** (comment 化されない) → exec-form では別経路 (= env var inject 等) が必要 [実機検証済: v2.1.170。`args:["a","#marker","b"]` を仕込むと script の argv が `[a] [#marker] [b]` で受理されることを確認]
- **plugin 経由 (`${CLAUDE_PLUGIN_ROOT}` 付き) で、error ヘッダに展開前 (literal `${CLAUDE_PLUGIN_ROOT}`) と展開後 (実体パス) のどちらが出るかは plugin install 環境が必要なため本ハーネスでは [未検証: TODO]**。確認できたのは「error ヘッダに command 文字列が literal で出て、末尾 `#marker` もそこに含まれる」という共通部分まで
- runtime の error message format が将来変わると無効化される可能性 [実装の副産物に依存]
- 本来は claude runtime が展開後パスを表示するか hook output に plugin name を付けるべき (= upstream に feedback したい話)

### 9.1 その他のハマり所

- **JSON output に shell profile の echo が混入** → invalid JSON、hook output 無視。`if [[ $- == *i* ]]; then echo ...; fi` で interactive-only guard を [実機検証推奨]
- **hook command の wd は stdin の `cwd` と違う** → `cd "$cwd" && ...` で明示移動 [実機検証済: ~v2.1.156 (cmux-msg)]
- **多 hook の updatedInput 衝突** → 最後に finish した hook が勝つ (= deterministic order なし、coordinator hook を 1 つに集約推奨) [spec]
- **Stop hook の max 8 連続 block** → 9 回目で自動 continue、`stop_hook_active` field で判定可 [spec]

## 10. 比較マトリクス — IO field × event / exit code × event

### 10.1 Input JSON フィールド × event (= どの event でどの field が stdin に含まれるか)

| field | 含まれる event | 値の例 |
|---|---|---|
| **`session_id`** | 全 event (共通) — 4 event 実測 [実機検証済: v2.1.170] + 全 event 一般化は [spec] | UUID v4 |
| **`cwd`** | 全 event (共通) — 4 event 実測 [実機検証済: v2.1.170] + 全 event 一般化は [spec] | event 起動時の cwd |
| **`hook_event_name`** | 全 event (共通) — 4 event 実測 [実機検証済: v2.1.170] + 全 event 一般化は [spec] | `"PreToolUse"` 等 |
| **`transcript_path`** | 全 event (共通) — 4 event 実測 [実機検証済: v2.1.170] + 全 event 一般化は [spec] | `.jsonl` ファイルパス |
| **`permission_mode`** | 一部 event (`SessionStart` には来ない) [実機検証済: v2.1.170] | `default` / `plan` / `acceptEdits` / `auto` / `dontAsk` / `bypassPermissions` の 6 値 [spec] |
| **`effort`** | tool-use 文脈 event (`PreToolUse` / `PostToolUse` / `Stop` / `SubagentStop`) + effort 対応モデル時のみ [実機検証済: v2.1.170] | `{"level":"low\|medium\|high\|xhigh\|max"}` |
| `tool_name` | `PreToolUse` / `PostToolUse` / `PostToolUseFailure` / `PermissionRequest` / `PermissionDenied` | `"Bash"` 等 |
| `tool_input` | `PreToolUse` / `PostToolUse` / `PostToolUseFailure` | `{"command": "npm test"}` 等 |
| `tool_use_id` | `PreToolUse` で観測 [実機検証済: v2.1.170] | `"toolu_..."` |
| `tool_output` | `PostToolUse` のみ | tool 結果 JSON |
| `error` | `PostToolUseFailure` | エラー内容 |
| `permission_prompt_type` | `PermissionRequest` | dialog 種別 |
| `reason` | `PermissionDenied` | deny 理由 |
| `prompt` | `UserPromptSubmit` / `UserPromptExpansion` | user 入力 text |
| `source` | `SessionStart` (`startup`/`resume`/`clear`/`compact`) / `Setup` (`init`/`maintenance`) / `ConfigChange` (`user_settings`/...、正本は §6.2 ConfigChange) / `InstructionsLoaded` (正本は §2.5 の reason 値セット) | event ごとに値が違う |
| `conversation_length` | `Stop` [spec] | turn 数 |
| `stop_hook_active` | `Stop` [実機検証済: v2.1.170] | bool、`true` なら既 block 中 |
| `last_assistant_message` / `background_tasks` / `session_crons` | `Stop` [実機検証済: v2.1.170] | 直近 assistant message / 実行中 BG task 配列 / cron 配列 |
| `error_type` | `StopFailure` | `"rate_limit"` / `"server_error"` 等 |
| `notification_type` | `Notification` | `"permission_prompt"` / `"idle_prompt"` 等 |
| `agent_id` / `agent_type` | subagent 文脈で発火する **任意の** hook (`SubagentStart` / `SubagentStop` に限らず、subagent 内 `PreToolUse` 等も含む) [実機検証済: v2.1.170] | agent 識別子 / agent 種別。main thread では両方 `null` |
| `exit_code` | `SubagentStop` | subagent exit code |
| `file_path` | `ConfigChange` / `FileChanged` | 変更ファイル |
| `old_cwd` / `new_cwd` | `CwdChanged` | dir 変更 |
| `mcp_server_name` | `Elicitation` / `ElicitationResult` | MCP server 名 |
| `delta` / `final` / `index` / `message_id` / `turn_id` | `MessageDisplay` [実機検証済: v2.1.170] | 表示テキスト断片 / 最終フラグ / 発火順 / message UUID / turn UUID |

[spec / 一部未検証]

### 10.2 Output JSON フィールド × event (= どの event でどの field が解釈されるか)

| field | 解釈される event | 効果 |
|---|---|---|
| `continue` | 全 event | false で event 種別ごとの「次の処理」を block |
| `suppressOutput` | tool 系 event (`PreToolUse` / `PostToolUse` 等) | tool output の表示を抑制 |
| `systemMessage` | 全 event | claude へ system message として inject |
| `additionalContext` | tool 系 event + `UserPromptSubmit` + `Stop` / `SubagentStop` [実機検証済: v2.1.170] | claude のコンテキストに追加 text inject。Stop/SubagentStop では hook error 扱いにせず会話継続したまま注入 |
| `terminalSequence` | `Notification` | terminal protocol (OSC 等) で desktop notify |
| `hookSpecificOutput.permissionDecision` | **`PreToolUse` のみ** | `allow` / `deny` / `ask` / `defer` |
| `hookSpecificOutput.permissionDecisionReason` | `PreToolUse` | 上記の理由 text |
| `hookSpecificOutput.updatedInput` | `PreToolUse` | tool 引数 rewrite (= 複数 hook 衝突時は最後の hook 勝ち) |
| `hookSpecificOutput.behavior` | **`PermissionRequest` のみ** | `allow` / `deny` / `ask` |
| `hookSpecificOutput.updatedPermissions` | `PreToolUse` / `PermissionRequest` | `setMode` で `bypassPermissions` / `acceptEdits` / `default` を session/settings に |
| `hookSpecificOutput.retry` | `PermissionDenied` | `true` で tool call 再試行 |
| `hookSpecificOutput.displayContent` | **`MessageDisplay` のみ** [実機検証済: v2.1.170] | 画面表示テキストを置換 (transcript / claude が見る本文は不変) |
| `hookSpecificOutput.sessionTitle` / `reloadSkills` / `watchPaths` | **`SessionStart` のみ** [実機検証済: v2.1.170] | title 設定 / skill 再スキャン / FileChanged 監視パス |
| `decision: "block"` + `reason` | `Stop` / `SubagentStop` / `UserPromptSubmit` | turn 再開 (Stop / SubagentStop) or turn 拒否 (UserPromptSubmit) |

[spec / 一部未検証]

### 10.3 Exit code × event (= 同 exit code でも event ごとに効果が変わる)

`0` (= 成功、decision なし) は全 event 共通: stdout JSON があれば parse & apply、text なら additionalContext へ inject。

`exit 2` (= block / error) の効果が event ごとに大きく違うのが要点:

| event | exit 2 の効果 | 補足 |
|---|---|---|
| `PreToolUse` | **tool call block** | claude に reason (stderr) 返す |
| `PostToolUse` | **turn block** | claude に reason 返して turn 再開 |
| `PostToolUseFailure` | turn block [未検証: TODO] | |
| `PostToolBatch` | turn block [未検証: TODO] | |
| `UserPromptSubmit` | **turn 拒否** | prompt を claude に渡さず終了 |
| `UserPromptExpansion` | **block** | command 展開を中断 |
| `PermissionRequest` | **deny 扱い** | permission dialog を deny で終わらせる |
| `PermissionDenied` | [未検証: TODO] | retry に効くか未確認 |
| `ConfigChange` | **block** | config reload を中断 |
| `WorktreeCreate` | **block** (= default git behavior を replace) | hook が完全に worktree create を肩代わり |
| `Stop` | **turn 再開** | 最大 8 連続 block 後に自動 continue (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` で cap 調整可) |
| `SessionStart` | **stderr 表示のみ** (block 不可) | execution 継続 |
| `Setup` | 同上 | |
| `SessionEnd` | **ignored** | output / exit code 完全無視 |
| `StopFailure` | **ignored** | 同上 |
| `Notification` | **block 不可** | stderr 表示のみ |
| その他の lifecycle event (PreCompact / CwdChanged / FileChanged 等) | [未検証: TODO] | 多くは [実装の副産物] と思われる |

`exit !0, !2` (= その他 exit code) は全 event 共通で **non-blocking warning**: stderr 1 行目が transcript に記録、execution 継続。

[spec / 一部未検証]

### 10.4 hook type × event (= prompt / agent hook が使える event)

`command` / `http` / `mcp_tool` は全 event で使える前提。`prompt` / `agent` が全 event で使えるか・一部 event 限定かは [未検証: TODO]。通常は `command` 形式で十分。`prompt` / `agent` は AI に判断させる場面 (= 「Stop hook で task 完了したか claude に判定させる」等) で使う。詳細は §4 と公式 docs 参照。

## 10.5 `[未検証]` 集約 (メンテ TODO 抽出用)

未検証項目を 1 箇所に集約 (= 格上げ対象の機械抽出用)。`[未検証: headless 不可]` は対話 UI / runner ライフサイクル等で構造的に検証不能、`[未検証: TODO]` はやれば検証できる。

### headless 不可 (= 構造的に検証不能)

- [ ] `post-session` event — self-hosted runner の workspace 削除フェーズが必要 (§2.1)

### TODO (= 検証可能、格上げ対象)

- [ ] `PreCompact` / `PostCompact` / `CwdChanged` / `FileChanged` の出力解釈・blockable (§2.5)
- [ ] `WorktreeRemove` / `InstructionsLoaded` の出力解釈・blockable (§2.5)
- [ ] `SubagentStart` / `TaskCreated` / `TaskCompleted` / `TeammateIdle` の出力解釈・blockable (§2.6)
- [ ] `Elicitation` / `ElicitationResult` の挙動 (MCP server 必要、§2.7)
- [ ] `SubagentStop` の `decision: "block"` での turn 再開 (§2.6)
- [ ] `permissionDecision: defer` の具体挙動 (§7.3)
- [ ] plugin 経由 (`${CLAUDE_PLUGIN_ROOT}` 付き) hook の error ヘッダに展開前/展開後どちらのパスが出るか (§9.0)
- [ ] `exit 2` の効果: `PostToolUseFailure` / `PostToolBatch` / `PermissionDenied` / その他 lifecycle event (§10.3)
- [ ] `prompt` / `agent` hook type が全 event で使えるか (§10.4)
- [ ] `Tool(param:value)` 形式の native-matcher なし tool (Task 等) での実 deny 動作 (§3 末尾)

## 11. 参考 URL (出典)

- [Hooks Guide](https://code.claude.com/docs/en/hooks-guide.md) — 実装ガイド、ユースケース
- [Hooks Reference](https://code.claude.com/docs/en/hooks.md) — 完全 schema、全 event 一覧
- [Plugins Reference](https://code.claude.com/docs/en/plugins-reference.md) — `hooks/hooks.json` の plugin 内配置
