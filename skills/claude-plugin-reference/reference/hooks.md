# フック編 — 全 Hook event / matcher / JSON input/output schema / blockable / 強制力

cmux-msg / hyoui / その他 plugin で hooks を書く時のリファレンス。各 event について「タイミング / 主要用途 / 何ができるか / JSON input/output schema」を整理。

> `[spec]` = 公式 docs に明示記述、`[実機検証済]` = 自分の plugin で検証済、`[未検証]` = 公式記述頼りで実機未確認 (TODO)、`[実装の副産物]` = spec 保証なしの挙動

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

## 2. Hook event 一覧

### 2.1 セッション系

| event | matcher 値 | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `SessionStart` | `startup` / `resume` / `clear` / `compact` | session 開始 / resume / clear / compact 後 | env 初期化 / meta 書き込み / direnv 連携 | additionalContext で claude に文脈 inject | × (exit 2 は stderr 表示のみ) |
| `SessionEnd` | (なし) | session 終了直前 | cleanup / 永続化 | (output 無視) | × |
| `Setup` | `init` / `maintenance` | `--init-only` or `-p --init/--maintenance` 実行時 | 初期化処理 | (用途限定) | × |

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
| `Stop` | (なし) | 毎 turn 終了直後 | task 完了確認 | `decision: "block"` + `reason` で turn 再開 (max 8 連続) | ✓ |
| `StopFailure` | (なし) | turn が API error で失敗 | エラー報告 | (output 無視) | × |
| `Notification` | type (e.g. `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`) | notification 表示直前 | desktop 通知 / sound | terminalSequence で OSC 777 等 | × |

### 2.5 Compaction / Cwd / FS 系

| event | matcher | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `PreCompact` | (なし) | context compaction 直前 | 永続化 | additionalContext | [未検証] |
| `PostCompact` | (なし) | compaction 完了直後 | re-init | additionalContext | [未検証] |
| `CwdChanged` | (なし) | working dir 変更時 | direnv / env reload | `CLAUDE_ENV_FILE` 書き込みで bash tool に env 反映 | [未検証] |
| `ConfigChange` | source (`user_settings` / `project_settings` / `local_settings` / `policy_settings` / `skills`) | config file が外部で変更 | reload 制御 | `decision: "block"` で block 可 | ✓ |
| `FileChanged` | file pattern | watched file 変更 | リアクション処理 | additionalContext | [未検証] |
| `WorktreeCreate` | (なし) | git worktree 作成時 | hook into worktree setup | default git behavior を replace 可 | ✓ |
| `WorktreeRemove` | (なし) | git worktree 削除時 | cleanup | [未検証] | [未検証] |
| `InstructionsLoaded` | reason (`session_start` / `nested_traversal` / `path_glob_match` / `include` / `compact`) | CLAUDE.md / rules がコンテキスト load 時 | rule 監査 | [未検証] | [未検証] |

### 2.6 Subagent / Task 系

| event | matcher | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `SubagentStart` | agent type | subagent spawn 直前 | log / 拒否 | [未検証] | [未検証] |
| `SubagentStop` | agent type | subagent 終了直後 | result 加工 | [未検証] | [未検証] |
| `TaskCreated` | (なし) | TaskCreate 生成直前 | task 監査 | [未検証] | [未検証] |
| `TaskCompleted` | (なし) | task completion 直前 | result 確認 | [未検証] | [未検証] |
| `TeammateIdle` | (なし) | teammate idle 状態 | スケジューリング | [未検証] | [未検証] |

### 2.7 MCP 系

| event | matcher | タイミング | 主要用途 | 何ができるか | blockable |
|---|---|---|---|---|---|
| `Elicitation` | mcp server 名 | MCP server がユーザ input request 時 | UI 介入 | [未検証] | [未検証] |
| `ElicitationResult` | mcp server 名 | ユーザ応答後、server に返す前 | filter | [未検証] | [未検証] |

### 2.8 その他

| event | matcher | タイミング | 主要用途 | blockable |
|---|---|---|---|---|
| `MessageDisplay` | (なし) | assistant message text 表示中 | logging / streaming 介入 | [未検証] |

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
| `^Notebook` / `mcp__.*` | regex | MCP tool 命名 `mcp__<server>__<tool>` を `.*` で拾える |
| event 固有値 | SessionStart の `startup`/`resume`/`clear`/`compact` 等 | (event ごとに値が違う) |

### `if` field (v2.1.85+, blockable event 限定)

tool 引数で filter:

```json
{ "matcher": "Bash", "hooks": [{ "if": "Bash(git *)", "command": "..." }] }
```

`Edit(*.ts)` / `Bash(git *)` 形式。**blockable event のみ** (`PreToolUse` / `PostToolUse` / `PostToolUseFailure` / `PermissionRequest` / `PermissionDenied`)。

## 4. Hook command の type 種別

| type | 主な field | timeout default | 用途 |
|---|---|---|---|
| `command` | `command` (shell), `args` (exec form), `statusMessage`, `once` | 600s (10 min) | 通常の script |
| `http` | `url`, `headers`, `allowedEnvVars` | 600s | REST 連携 |
| `mcp_tool` | `server`, `tool`, `arguments` | 600s | MCP tool 経由 |
| `prompt` | `prompt`, `model` (default `haiku`) | 30s | claude に判断 |
| `agent` | `prompt`, `maxTurns` | 60s | subagent 実行 |

`UserPromptSubmit` event の hook は強制的に 30s に short-circuit。[spec]

## 5. Hook process の env

| 変数 | 値 | 範囲 |
|---|---|---|
| `CLAUDE_PROJECT_DIR` | project root (= git toplevel or cwd) | 全 hook |
| `CLAUDE_PLUGIN_ROOT` | `~/.claude/plugins/cache/<id>/<version>/` | plugin hook のみ |
| `CLAUDE_PLUGIN_DATA` | `~/.claude/plugins/data/<id>/` (= plugin update でも保持) | plugin hook のみ |
| `CLAUDE_ENV_FILE` | temp file path、source して env 反映 | CwdChanged / SessionStart 等 |

[実機検証済 (cmux-msg)] hook 起動時の cwd は **stdin の `cwd` field と一致しない可能性** — hook 内で操作したい場合は `cd "$cwd"` で明示移動が必要。

## 6. JSON input schema

### 6.1 共通フィールド (全 event)

```json
{
  "session_id": "<UUID v4>",
  "cwd": "/current/working/directory",
  "hook_event_name": "<EventName>",
  "transcript_path": "/path/to/transcript.jsonl",
  "permission_mode": "default|bypassPermissions|acceptEdits",
  "claude_config_dir": "$CLAUDE_CONFIG_DIR",
  "project_root": "/project/root"
}
```

### 6.2 event 固有フィールド

#### PreToolUse / PostToolUse

```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "npm test" },
  "tool_output": { "result": "..." }   // PostToolUse のみ
}
```

#### SessionStart

```json
{ "source": "startup" }   // or "resume" / "clear" / "compact"
```

#### UserPromptSubmit

```json
{ "prompt": "<user typed text>" }
```

#### Stop

```json
{ "conversation_length": 42, "stop_hook_active": false }
```

`stop_hook_active: true` の時は max 8 連続 block 後に自動 continue (= 無限 block 防止)。`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` env で cap 調整可。

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

- `additionalContext`: claude のコンテキストに inject される追加テキスト (= tool event で `stdout` text を直接出してもこれに入る)
- `hookSpecificOutput`: event ごとの decision (= PreToolUse なら permission、PermissionRequest なら behavior)

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
| `defer` | non-interactive mode (`-p` flag) でのみ有効 |

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
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/push-guard.sh #push-guard"
}
```

- bash shell-form では `#` 以降が comment 扱い = script 実行に影響しない [実機検証推奨]
- claude runtime の error 表示は literal の command string をそのまま出すので、`#push-guard` が見える = plugin 名を識別可

```
PreToolUse:Bash hook error: [${CLAUDE_PLUGIN_ROOT}/hooks/push-guard.sh #push-guard]: BLOCK: ...
                                                                       ^^^^^^^^^^^
                                                                       これで plugin 名わかる
```

**制約**:
- shell-form (= `command: "..."` のみ) で有効。exec-form (= `command` + `args` 同時指定) では `#` が literal 引数として渡される可能性 → exec-form では別経路 (= env var inject 等) [未検証]
- runtime の error message format が将来変わると無効化される可能性 [実装の副産物に依存]
- 本来は claude runtime が展開後パスを表示するか hook output に plugin name を付けるべき (= upstream に feedback したい話)



- **JSON output に shell profile の echo が混入** → invalid JSON、hook output 無視。`if [[ $- == *i* ]]; then echo ...; fi` で interactive-only guard を [実機検証推奨]
- **hook command の wd は stdin の `cwd` と違う** → `cd "$cwd" && ...` で明示移動 [実機検証済 (cmux-msg)]
- **多 hook の updatedInput 衝突** → 最後に finish した hook が勝つ (= deterministic order なし、coordinator hook を 1 つに集約推奨) [spec]
- **Stop hook の max 8 連続 block** → 9 回目で自動 continue、`stop_hook_active` field で判定可 [spec]

## 10. 比較マトリクス — IO field × event / exit code × event

### 10.1 Input JSON フィールド × event (= どの event でどの field が stdin に含まれるか)

| field | 含まれる event | 値の例 |
|---|---|---|
| **`session_id`** | 全 event (共通) | UUID v4 |
| **`cwd`** | 全 event (共通) | event 起動時の cwd |
| **`hook_event_name`** | 全 event (共通) | `"PreToolUse"` 等 |
| **`transcript_path`** | 全 event (共通) | `.jsonl` ファイルパス |
| **`permission_mode`** | 全 event (共通) | `default` / `bypassPermissions` / `acceptEdits` |
| **`claude_config_dir`** | 全 event (共通) | `$CLAUDE_CONFIG_DIR` 値 |
| **`project_root`** | 全 event (共通) | project root |
| `tool_name` | `PreToolUse` / `PostToolUse` / `PostToolUseFailure` / `PermissionRequest` / `PermissionDenied` | `"Bash"` 等 |
| `tool_input` | `PreToolUse` / `PostToolUse` / `PostToolUseFailure` | `{"command": "npm test"}` 等 |
| `tool_output` | `PostToolUse` のみ | tool 結果 JSON |
| `error` | `PostToolUseFailure` | エラー内容 |
| `permission_prompt_type` | `PermissionRequest` | dialog 種別 |
| `reason` | `PermissionDenied` | deny 理由 |
| `prompt` | `UserPromptSubmit` / `UserPromptExpansion` | user 入力 text |
| `source` | `SessionStart` (`startup`/`resume`/`clear`/`compact`) / `Setup` (`init`/`maintenance`) / `ConfigChange` (`user_settings`/...) / `InstructionsLoaded` (`session_start`/`compact`/...) | event ごとに値が違う |
| `conversation_length` | `Stop` | turn 数 |
| `stop_hook_active` | `Stop` | bool、`true` なら既 block 中 |
| `error_type` | `StopFailure` | `"rate_limit"` / `"server_error"` 等 |
| `notification_type` | `Notification` | `"permission_prompt"` / `"idle_prompt"` 等 |
| `agent_type` | `SubagentStart` / `SubagentStop` | agent 種別 |
| `exit_code` | `SubagentStop` | subagent exit code |
| `file_path` | `ConfigChange` / `FileChanged` | 変更ファイル |
| `old_cwd` / `new_cwd` | `CwdChanged` | dir 変更 |
| `mcp_server_name` | `Elicitation` / `ElicitationResult` | MCP server 名 |

[spec / 一部未検証]

### 10.2 Output JSON フィールド × event (= どの event でどの field が解釈されるか)

| field | 解釈される event | 効果 |
|---|---|---|
| `continue` | 全 event | false で event 種別ごとの「次の処理」を block |
| `suppressOutput` | tool 系 event (`PreToolUse` / `PostToolUse` 等) | tool output の表示を抑制 |
| `systemMessage` | 全 event | claude へ system message として inject |
| `additionalContext` | 主に tool 系 event + `UserPromptSubmit` | claude のコンテキストに追加 text inject |
| `terminalSequence` | `Notification` | terminal protocol (OSC 等) で desktop notify |
| `hookSpecificOutput.permissionDecision` | **`PreToolUse` のみ** | `allow` / `deny` / `ask` / `defer` |
| `hookSpecificOutput.permissionDecisionReason` | `PreToolUse` | 上記の理由 text |
| `hookSpecificOutput.updatedInput` | `PreToolUse` | tool 引数 rewrite (= 複数 hook 衝突時は最後の hook 勝ち) |
| `hookSpecificOutput.behavior` | **`PermissionRequest` のみ** | `allow` / `deny` / `ask` |
| `hookSpecificOutput.updatedPermissions` | `PreToolUse` / `PermissionRequest` | `setMode` で `bypassPermissions` / `acceptEdits` / `default` を session/settings に |
| `hookSpecificOutput.retry` | `PermissionDenied` | `true` で tool call 再試行 |
| `decision: "block"` + `reason` | `Stop` / `UserPromptSubmit` | turn 再開 (Stop) or turn 拒否 (UserPromptSubmit) |

[spec / 一部未検証]

### 10.3 Exit code × event (= 同 exit code でも event ごとに効果が変わる)

`0` (= 成功、decision なし) は全 event 共通: stdout JSON があれば parse & apply、text なら additionalContext へ inject。

`exit 2` (= block / error) の効果が event ごとに大きく違うのが要点:

| event | exit 2 の効果 | 補足 |
|---|---|---|
| `PreToolUse` | **tool call block** | claude に reason (stderr) 返す |
| `PostToolUse` | **turn block** | claude に reason 返して turn 再開 |
| `PostToolUseFailure` | turn block [未検証] | |
| `PostToolBatch` | turn block [未検証] | |
| `UserPromptSubmit` | **turn 拒否** | prompt を claude に渡さず終了 |
| `UserPromptExpansion` | **block** | command 展開を中断 |
| `PermissionRequest` | **deny 扱い** | permission dialog を deny で終わらせる |
| `PermissionDenied` | [未検証] | retry に効くか未確認 |
| `ConfigChange` | **block** | config reload を中断 |
| `WorktreeCreate` | **block** (= default git behavior を replace) | hook が完全に worktree create を肩代わり |
| `Stop` | **turn 再開** | 最大 8 連続 block 後に自動 continue (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` で cap 調整可) |
| `SessionStart` | **stderr 表示のみ** (block 不可) | execution 継続 |
| `Setup` | 同上 | |
| `SessionEnd` | **ignored** | output / exit code 完全無視 |
| `StopFailure` | **ignored** | 同上 |
| `Notification` | **block 不可** | stderr 表示のみ |
| その他の lifecycle event (PreCompact / CwdChanged / FileChanged 等) | [未検証] | 多くは [実装の副産物] と思われる |

`exit !0, !2` (= その他 exit code) は全 event 共通で **non-blocking warning**: stderr 1 行目が transcript に記録、execution 継続。

[spec / 一部未検証]

### 10.4 hook type × event (= prompt / agent hook が使える event)

| event | command (default) | http | mcp_tool | prompt | agent |
|---|---|---|---|---|---|
| 全 event | ✓ | ✓ | ✓ | ✓ ([未検証] 一部 event のみ?) | ✓ ([未検証] 一部 event のみ?) |

通常は `command` 形式で十分。`prompt` / `agent` は AI に判断させる場面 (= 「Stop hook で task 完了したか claude に判定させる」等) で使う。詳細は §4 と公式 docs 参照。

## 11. 参考 URL (出典)

- [Hooks Guide](https://code.claude.com/docs/en/hooks-guide.md) — 実装ガイド、ユースケース
- [Hooks Reference](https://code.claude.com/docs/en/hooks.md) — 完全 schema、全 event 一覧
- [Plugins Reference](https://code.claude.com/docs/en/plugins-reference.md) — `hooks/hooks.json` の plugin 内配置
