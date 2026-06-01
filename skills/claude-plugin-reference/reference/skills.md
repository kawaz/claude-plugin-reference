# スキル編 — SKILL.md frontmatter / string substitution / Dynamic Context Injection / invocation 制御

> `[spec]` = 公式 docs に明示記述、`[実機検証済]` = 自分の plugin で検証済、`[未検証]` = 公式記述頼りで実機未確認、`[実装の副産物]` = spec 保証なしの挙動

## 1. SKILL.md の配置パターン

| 配置 | command 名 | 例 |
|---|---|---|
| `~/.claude/skills/<name>/SKILL.md` | directory 名 | `/summarize-changes` |
| `.claude/skills/<name>/SKILL.md` | directory 名 (project scope) | |
| `.claude/commands/<name>.md` (custom slash command files; project scope) | filename | `/deploy`、`/itumono-nonstop` 等 |
| `~/.claude/commands/<name>.md` (同上; user scope) | filename | 同上 |
| `<plugin>/skills/<name>/SKILL.md` | `<plugin>:<name>` | `/cmux-msg:cmux-msg-list` |
| `<plugin>/commands/<name>.md` | `<plugin>:<name>` | `/codex:setup`、`/codex:review` — 詳細は [commands.md](commands.md) |
| `<plugin>/SKILL.md` (plugin root) | frontmatter `name` or plugin 名 | `/cmux-msg:cmux-msg` |

= **補完表示は常に `/<plugin>:<name>` の namespace 付き**。bare 名 (= `/setup` 等) フォールバックは現バージョンでは無効 [実機検証済 2026-06-02 (codex / gh-monitor plugin)]。短い一般名 (= `read` / `list` / `status` 等) を skill 名にしても他 plugin とのコンフリクトリスクなし。

[実機検証済 (cmux-msg)] plugin root の SKILL.md (or `skills/<plugin-name>/SKILL.md` = plugin 名と同 skill 名) は補完上 `/<plugin>:<plugin>` 形式で表示される。これは「`/<plugin>` で始まる短縮形がそのまま plugin と同名 skill を指す」スタイルで、display renderer が冗長 prefix を collapse している可能性 (= 未確定、要追加検証)。

## 2. Skill folder 内の supporting files

```
my-skill/
├── SKILL.md              # 必須
├── reference.md          # 任意、AI が on-demand で Read
├── examples.md           # 同上
└── scripts/
    └── helper.sh         # 実行可能、bash injection で呼べる
```

- skill 起動時に **`SKILL.md` 本文のみ AI コンテキストに流入**、reference/scripts は流入しない (= on-demand)
- `${CLAUDE_SKILL_DIR}` で skill 自身の dir を参照可、相対 `../` で親に出るのは **セキュリティ境界違反** (= 同 dir 配下のみ参照可) [spec]

## 3. Frontmatter 全 field

```yaml
---
name: skill-name
description: What this skill does (= AI 自動 invoke 判定の key、listing に含まれる)
---
```

| field | 型 | 必須 | 用途 | 備考 |
|---|---|---|---|---|
| `name` | string | 任意 | skill 表示名 | dir 名が優先、plugin root SKILL.md のみ frontmatter `name` が command 名決定 |
| `description` | string | 推奨 | AI invocation trigger / listing | `when_to_use` と合わせて max 1,536 文字で truncate [spec] |
| `when_to_use` | string | 任意 | description 補強 | 「ユーザが何を言ったら invoke してほしいか」 |
| `argument-hint` | string | 任意 | autocomplete hint | 例: `[issue-number]`, `[filename] [format]` |
| `arguments` | string\|array | 任意 | 位置引数 named getter | `arguments: [issue, branch]` で `$issue` `$branch` 展開可 |
| `disable-model-invocation` | bool | 任意 | true = AI 自動 invoke 不可、manual `/name` のみ | listing から description も削除 = AI コンテキスト食わない (= ユーザ専用 skill 向け) [実機検証済] |
| `user-invocable` | bool | 任意 | false = `/` menu と listing から非表示、AI のみ invoke | background knowledge 用途 |
| `allowed-tools` | string\|array | 任意 | skill active 中に permission 無しで使える tool | `"Bash(git add *) Bash(git commit *)"`、turn 終了で clear |
| `disallowed-tools` | string\|array | 任意 | skill active 中に使えなくなる tool | auto-loop で危険 tool 防止 |
| `model` | string | 任意 | model override | `sonnet` / `opus` / `inherit` |
| `effort` | string | 任意 | effort override | `low` / `medium` / `high` / `xhigh` / `max` (model 依存) |
| `context` | string | 任意 | `fork` で subagent 実行 | parent session から isolation |
| `agent` | string | 任意 | `context: fork` 時の subagent type | `Explore` / `Plan` / `general-purpose` / custom |
| `hooks` | object | 任意 | このスキル scoped hook | format は `.claude/settings.json` hooks と同じ |
| `paths` | string\|array | 任意 | glob で skill auto-invoke 対象を限定 | `"src/**/*.ts"` で .ts のみ |
| `shell` | string | 任意 | `!`cmd`` の shell 指定 | `bash` (default) / `powershell` |

[spec、公式 `skills.md` frontmatter reference より]

## 4. String substitution (本文中で展開される変数)

### 4.1 引数展開

| 変数 | 説明 | 例 |
|---|---|---|
| `$ARGUMENTS` | 全引数文字列 (as typed) | `/skill #123 urgent` → `$ARGUMENTS` = `"#123 urgent"` |
| `$N` (= `$0`, `$1`...) | N-th 引数 (shell quoting 適用) | `/skill "hello world" second` → `$0`="hello world", `$1`="second" |
| `$<name>` | frontmatter `arguments: [issue, branch]` の named getter | `$issue` = 1st arg |

### 4.2 環境変数 / plugin 系

| 変数 | 説明 | 確証ステータス |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | plugin installation root | **[実機検証済]** skill template として展開され、claude に流入する本文には絶対パスが入る。bash env としては流入しない (= bash で `echo $CLAUDE_PLUGIN_ROOT` は空)。**mid-session で plugin update した場合は `/reload-plugins` まで古い version path を指す** |
| `${CLAUDE_PLUGIN_DATA}` | plugin data dir (`~/.claude/plugins/data/<id>/`) | [spec] plugin update で保持される (= 永続 state はここに置く) |
| `${CLAUDE_SKILL_DIR}` | skill SKILL.md のあるディレクトリ (plugin skill なら skill subdir、not plugin root) | [spec] supporting file 参照に使う、cwd 非依存 |
| `${CLAUDE_PROJECT_DIR}` | project root | [spec] |
| `${CLAUDE_SESSION_ID}` | session UUID v4 | [spec] |
| `${CLAUDE_EFFORT}` | current effort level | [spec] |
| `${ENV_VAR}` | 任意 env 変数 | [spec] `${HOME}` 等 |
| `${user_config.*}` | plugin.json `userConfig` 値 (plugin 限定) | [spec] |

### 4.3 重要な実機検証結果

**`${CLAUDE_PLUGIN_ROOT}` の経路別の有効性**:

| 経路 | 展開される? |
|---|---|
| SKILL.md template (= claude runtime が読む時) | ✓ [実機検証済 (cmux-msg v0.28.13)] |
| Hook command 内 (= shell env として) | ✓ [spec]、`${CLAUDE_PLUGIN_ROOT}` が env var として hook process に inject |
| Skill から呼ばれた bash 内 (= bash env として) | **✗** [実機検証済] bash で `echo $CLAUDE_PLUGIN_ROOT` は空 — ただし SKILL.md template で展開済の絶対パスが本文に入るので、Skill 経由なら問題なし |

**Skill 経由で plugin bin を叩く正解パターン**:

```md
本 skill 内で本文に `${CLAUDE_PLUGIN_ROOT}/bin/cmux-msg $ARGUMENTS` を Bash で実行してください。
```

→ AI に流入する時には `/Users/kawaz/.claude-personal/plugins/cache/cmux-msg/cmux-msg/0.28.13/bin/cmux-msg $ARGUMENTS` に置換済 (= bash 解決依存なく、その plugin instance の bin を確実指定)

## 5. Dynamic Context Injection (`!`command``)

skill 本文中で `!`command`` または ` ```! ` fenced block を書くと、**skill invocation 時に command を実行し、出力で placeholder を置換** してから claude に渡す。

```md
## 現在の git status

!`git status --short`

## 上記を踏まえて...
```

[spec]

### 制約

- 先頭行 or whitespace 直後のみ認識 (= `KEY=!`cmd`` は literal 扱い)
- **substitution は 1 pass** — command output が `!`...`` を含んでも 2 次展開なし
- Policy で disable 可: `disableSkillShellExecution: true` → `[shell command execution disabled by policy]` に置換 (= bundled & managed skills は exempt) [spec]
- shell は `shell: bash` (default) / `powershell` を frontmatter で選択
- 複数行 command は ` ```! ` fenced block で

## 6. Invocation 制御 (= model-invocable / user-invocable)

| frontmatter 組み合わせ | user invoke | model invoke | listing に description | 本文 load タイミング |
|---|---|---|---|---|
| (default) | ✓ | ✓ | ✓ (常時) | description: 常時、本文: invoke 時 |
| `disable-model-invocation: true` | ✓ | ✗ | ✗ (model 視点で hidden) | description: invoke 後のみ、本文: invoke 時 |
| `user-invocable: false` | ✗ | ✓ | ✓ (description のみ、`/` menu 非表示) | description: 常時、本文: invoke 時 |
| 両方 true & false | ✗ | ✗ | ✗ | (実質無効) |

[spec]

**実機検証 (cmux-msg)**:
- `disable-model-invocation: true` を付けた 6 user skill (`/cmux-msg-peers` 等) は **AI の system-reminder available skills 一覧に出てこない** (= description 含めて context 食わない) → ユーザ専用 slash command として最適 [実機検証済]
- 大本 `skills/cmux-msg/SKILL.md` (= disable-model-invocation 無し) は AI 一覧に出る、`/cmux-msg:cmux-msg` で full namespace 表示

## 7. Skill content lifecycle

- skill invocation 時、本文が **single message として会話に挿入**
- その後 同 turn では skill file を re-read しない (= 「standing instructions」として書く、one-time steps だと忘れられる) [spec]
- compaction で会話が圧縮された場合、invoked skill は最初の 5,000 token まで re-attach (= 複数 skill 時は combined budget 25,000 token、優先度は最近 invoke 順) [spec]
- skill が context から drop されたら **再 invoke** で再度 load

## 8. Skill cache の reload 挙動 (実機検証)

- claude session 起動時に PATH に plugin bin が追加される
- plugin update が走っても **既存 session 内の Skill 解決先は古い cache (= 古い version path) を見続ける** [実機検証済 (cmux-msg)]
- `/reload-plugins` (interactive command、AI からは叩けない) で最新 version cache に切替
- session restart でも同様に最新化
- = SKILL.md 本文に `${CLAUDE_PLUGIN_ROOT}/bin/...` を書いておけば、reload 後の skill invocation 時には新 version の絶対パスが embed される (= 古い cache 問題に巻き込まれない設計)

## 9. Subagent execution (`context: fork`)

```yaml
---
name: research
description: ...
context: fork
agent: Explore
---

Research $ARGUMENTS:
1. Find files
2. Read code
```

- skill 本文が subagent の prompt に
- parent session の history / memory 非継承
- `agent: Explore` (read-only)、`Plan` (planning)、`general-purpose` (default、CLAUDE.md load)、custom `.claude/agents/<name>.md`
- 結果 summary だけ parent に return

[spec]

## 10. settings.json での skill override

```json
{
  "skillOverrides": {
    "legacy-context": "name-only",
    "deploy": "off"
  }
}
```

| value | claude 視点 | `/` menu |
|---|---|---|
| `on` | name + description | yes |
| `name-only` | name only | yes |
| `user-invocable-only` | hidden | yes |
| `off` | hidden | hidden |

[spec]

## 11. 参考 URL (出典)

- [Skills](https://code.claude.com/docs/en/skills.md)
- [Plugins Reference (Path behavior rules)](https://code.claude.com/docs/en/plugins-reference.md)
- [Plugins (overview)](https://code.claude.com/docs/en/plugins.md)
