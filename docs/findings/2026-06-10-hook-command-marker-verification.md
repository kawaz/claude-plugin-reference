# hook command の `#marker` 扱い + stdin 共通フィールドの実機検証

- Date: 2026-06-10
- 対象 Claude Code: v2.1.170
- 検証手段: temp project dir + `.claude/settings.json` の hooks + `claude -p` headless (`--permission-mode bypassPermissions`)
- 出力確認は目視でなく **固有トークンの grep**

## 判明した事実

### A. hook command の shell-form / exec-form と `#marker`

1. **shell-form** (`{"type":"command","command":"..."}` のみ) は shell (bash) で実行され、`#` 以降は **comment 扱い**で実行に影響しない。
   - `echo SHELLFORM_OUT_TOKEN_AAA #shellmarker-BBB` → 出力は `SHELLFORM_OUT_TOKEN_AAA` のみ。
2. **exec-form** (`command` + `args` 配列) は **hooks 設定で受理され、shell を介さず argv を literal で渡す**。
   - `command: "<script>"`, `args: ["execarg1", "#execmarker-CCC", "execarg3"]` → script の argv は `[execarg1] [#execmarker-CCC] [execarg3]`。`#execmarker-CCC` は comment にならず **literal 引数**として届く。
   - → §9.0 の「exec-form では `#` が literal 引数として渡される」仮説は **裏付けられた**。
3. **block error 表示に command 文字列が literal で出る**。PreToolUse(Bash) で `exit 2 #blockmarker-DDD` を踏ませると、error envelope は:

   ```
   PreToolUse:Bash hook error: [echo BLOCKED_BY_HOOK_XYZ >&2; exit 2 #blockmarker-DDD]: BLOCKED_BY_HOOK_XYZ
   ```

   `[...]` 内に **展開前の command 文字列がそのまま (= `#blockmarker-DDD` 込みで) 出る**。grep `hook error: \[.*#blockmarker-DDD\]` が pass。
   - → §9.0 の「command 末尾の `#marker` で error 表示から plugin を識別できる」ベストプラクティスの **核心メカニズムが実機で確認された**。

#### 未検証で残る範囲 (峻別)

- 上記 3 は **settings.json 直書きの command hook** で検証した。`${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh #marker` のように **plugin 経由**で、変数展開後 (= 実体パス) と展開前 (= `${CLAUDE_PLUGIN_ROOT}` literal) のどちらが error header に出るかは **plugin install 環境が必要なため本ハーネスでは未検証**。確認できたのは「error header には command 文字列が literal で出て、末尾の `#marker` もそこに含まれる」という共通部分まで。

### B. stdin 共通フィールド (SessionStart / UserPromptSubmit / PreToolUse / Stop で実測)

実測した共通フィールドは: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode` (一部 event のみ), `effort` (tool-use 文脈 event + effort 対応モデルのみ)。

| field | SessionStart | UserPromptSubmit | PreToolUse | Stop | 備考 |
|---|---|---|---|---|---|
| `session_id` | ✓ | ✓ | ✓ | ✓ | UUID v4 |
| `transcript_path` | ✓ | ✓ | ✓ | ✓ | `.jsonl` パス |
| `cwd` | ✓ | ✓ | ✓ | ✓ | |
| `hook_event_name` | ✓ | ✓ | ✓ | ✓ | |
| `permission_mode` | **✗** | ✓ | ✓ | ✓ | SessionStart には来ない (公式「Not all events receive this field」と一致) |
| `effort` | ✗ | ✗ | ✓ | ✓ | opus で `{"level":"high"}`。haiku では PreToolUse/Stop でも来ない (= effort 非対応モデルでは欠落) |
| `claude_config_dir` | **✗** | **✗** | **✗** | **✗** | **どの event でも来ない** → hooks.md の記述は誤り |
| `project_root` | **✗** | **✗** | **✗** | **✗** | **同上、来ない** |
| `agent_id` | — | — | main: null / subagent: 値あり | null | subagent 文脈のみ非 null |
| `agent_type` | — | — | main: null / subagent: `"general-purpose"` | null | subagent 文脈のみ非 null |

- **`claude_config_dir` / `project_root` は実機で 1 度も観測されず**。公式 hooks docs の共通フィールド表にも無い。hooks.md の「全 event 共通」記述は事実誤りと確定 → 削除。
- **`permission_mode`** の有効値は公式で **6 値**: `default` / `plan` / `acceptEdits` / `auto` / `dontAsk` / `bypassPermissions`。実機で観測できたのは `bypassPermissions` のみ (検証時の起動 mode)。
- **`effort`** は `{"level": "<low|medium|high|xhigh|max>"}` オブジェクト。tool-use 文脈で発火する event (PreToolUse / PostToolUse / Stop / SubagentStop) かつ **モデルが effort パラメータ対応時のみ**。opus で `high` を観測、haiku では欠落。`$CLAUDE_EFFORT` env でも参照可 [spec]。
- **`agent_id` / `agent_type`** は subagent 文脈で発火する hook にのみ非 null で入る。main thread では両方 `null`。subagent (Task tool, `general-purpose`) 内の PreToolUse で `agent_id: "af00cf978411a8036"`, `agent_type: "general-purpose"` を観測。

### C. 副産物として観測した event 固有フィールド (今回新規確認)

- PreToolUse: `tool_use_id` (例 `"toolu_..."`) が stdin に含まれる。
- Stop: `last_assistant_message`, `background_tasks` (配列), `session_crons` (配列) が含まれる。

## 検証の詳細

### A-1/A-2 shell-form vs exec-form

| 形式 | 設定 | 実測 | 結論 |
|---|---|---|---|
| shell-form | `command: "echo X #shellmarker-BBB"` | 出力 `X` のみ | `#` 以降 comment ⇒ 影響なし |
| exec-form | `command: "<script>"`, `args: ["a","#execmarker-CCC","b"]` | argv = `[a] [#execmarker-CCC] [b]` | `args` 受理 + `#` は literal 引数 |

### A-3 block error の literal command 表示

設定 `PreToolUse(Bash)` hook = `echo BLOCKED_BY_HOOK_XYZ >&2; exit 2 #blockmarker-DDD`。
`--output-format json` の出力を `jq -r '.. | strings'` で抽出 → grep `hook error: \[.*#blockmarker-DDD\]` が pass。
error header 実物:

```
PreToolUse:Bash hook error: [echo BLOCKED_BY_HOOK_XYZ >&2; exit 2 #blockmarker-DDD]: BLOCKED_BY_HOOK_XYZ
```

`[...]` = 展開前 command 文字列の literal、末尾 `#blockmarker-DDD` 込み。

### B stdin dump

各 event の hook に `cat > <file>` を仕込み、`claude -p` 1 回で全 event 発火 → JSON を `jq` で確認。effort 確認は opus、agent_* 確認は Task subagent 経由で再実行。

## 出典

- 公式 hooks reference: https://code.claude.com/docs/en/hooks.md (共通フィールド表 / permission_mode 6 値 / effort / agent_id / agent_type)
