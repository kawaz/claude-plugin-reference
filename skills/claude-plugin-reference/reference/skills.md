# スキル編 — SKILL.md frontmatter / string substitution / Dynamic Context Injection / invocation 制御

> `[spec]` = 公式 docs に明示記述、`[実機検証済]` = 自分の plugin で検証済、`[未検証]` = 公式記述頼りで実機未確認、`[実装の副産物]` = spec 保証なしの挙動
> - 無ラベル行の既定は `[spec]` (公式 docs 由来)。記憶・推測由来の項目は `[未検証]` を明示する。
> - `[実機検証済: ~vX.Y.Z]` の `~` は記述導入時期からの推定バージョン (当時の再検証記録ではない)。

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

### 補完表示ルール [実機検証済: ~v2.1.160 2026-06-02 (cmux-msg / gh-monitor / codex)]

候補文字列は常に canonical な `/<plugin>:<name>`。bare 名 (= `/list` 等) でのフォールバック candidate は無い (= namespace 必須)。表示時に renderer が以下 3 パターンで分岐する:

| 条件 | 表示 | 例 |
|---|---|---|
| `name` が `plugin` と **完全一致** | full `/<plugin>:<plugin>` (= `/<plugin>` 単独だと plugin 起動と曖昧なため回避) | `/cmux-msg:cmux-msg` |
| `name` が `plugin` を **prefix に持つ** (≠ 完全一致) | 短縮 `/<name>` + `(<plugin>)` suffix (= 冗長 prefix `<plugin>:` を collapse) | `/cmux-msg-list` `(cmux-msg)` |
| `name` が `plugin` を prefix に持たない | full `/<plugin>:<name>` + `(<plugin>)` suffix | `/gh-monitor:watch-pr`, `/codex:setup` |

**含意 (= 命名規約として使える)**:
- skill 名を plugin 名 prefix で揃える (= `cmux-msg-list`, `cmux-msg-read`) と、補完で短縮形 `/cmux-msg-list` が打てる (= UX 良好、cmux-msg が採用している規約)
- plugin 名と無関係な短い名前 (= `watch-pr`) は full namespace `/gh-monitor:watch-pr` になる。一般語の skill 名でも namespace 必須なので **他 plugin とのコンフリクトリスクは無い**が、補完では常に `<plugin>:` prefix を打つ必要がある
- 補完マッチングは **表示文字列 (full or 短縮) に対して**行われる。`/statu` で `/codex:status` が候補に出るのは full 表示内の `status` 部分マッチ
- これは現バージョンの実機挙動。公式 spec で保証された UI 仕様ではないため、将来版での再確認は推奨

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
| `disable-model-invocation` | bool | 任意 | true = AI 自動 invoke 不可、manual `/name` のみ | listing から description も削除 = AI コンテキスト食わない (= ユーザ専用 skill 向け) [実機検証済: ~v2.1.156] |
| `user-invocable` | bool | 任意 | false = `/` menu と listing から非表示、AI のみ invoke | background knowledge 用途 |
| `allowed-tools` | string\|array | 任意 | skill active 中に permission 無しで使える tool | `"Bash(git add *) Bash(git commit *)"`、turn 終了で clear |
| `disallowed-tools` | string\|array | 任意 | skill active 中に使えなくなる tool | auto-loop で危険 tool 防止。**[実機検証済: v2.1.170]** `disallowed-tools: Bash` の skill が active な間、Bash 実行は `Permission to use Bash has been denied.` で拒否される (= 次メッセージで解除)。詳細 §6.1 |
| `model` | string | 任意 | model override | `sonnet` / `opus` / `inherit` |
| `effort` | string | 任意 | effort override | `low` / `medium` / `high` / `xhigh` / `max` (model 依存。値セットの正本は [hooks.md §6.1](hooks.md#61-共通フィールド)) |
| `context` | string | 任意 | `fork` で subagent 実行 | parent session から isolation |
| `agent` | string | 任意 | `context: fork` 時の subagent type | `Explore` / `Plan` / `general-purpose` / custom |
| `hooks` | object | 任意 | このスキル scoped hook | format は `.claude/settings.json` hooks と同じ |
| `paths` | string\|array | 任意 | glob で skill auto-invoke 対象を限定 | `"src/**/*.ts"` で .ts のみ |
| `shell` | string | 任意 | `!`cmd`` の shell 指定 | `bash` (default) / `powershell` |

[spec、公式 `skills.md` frontmatter reference より]

## 4. String substitution (本文中で展開される変数)

### 4.1 引数展開

> **注意: `$0` が 1st 引数** (= shell の「`$0` はスクリプト名、`$1` が 1st」慣習と**異なる**)。`$1` を 1st 引数のつもりで書くと 1 個ずれる。off-by-one 事故の定番なので skill 作成時は必ず確認。

| 変数 | 説明 | 例 |
|---|---|---|
| `$ARGUMENTS` | 全引数文字列 (as typed) | `/skill #123 urgent` → `$ARGUMENTS` = `"#123 urgent"` |
| `$N` (= `$0`, `$1`...) | N-th 引数 (shell quoting 適用) | `/skill "hello world" second` → `$0`="hello world", `$1`="second" |
| `$<name>` | frontmatter `arguments: [issue, branch]` の named getter | `$issue` = 1st arg |

### 4.1.1 リテラル `$` のエスケープ (`\$`) [実機検証済: v2.1.170]

本文中で展開対象トークン (`$N` / `$ARGUMENTS` / `$<name>`) の前のリテラル `$` を出したい場合、直前に `\` を 1 個置いてエスケープする (`\$1.00`)。展開対象でない `$` の前の `\` はそのまま残る。

検証: temp project の `.claude/skills/<name>/SKILL.md` 本文に各パターンを並べ、`claude -p '/<name> alpha bravo'` で本文を逐語 echo させて観測。

| 本文の記述 | `/x alpha bravo` (引数あり) | `/x` (引数なし) | 解釈 |
|---|---|---|---|
| `$1` | `bravo` | (空) | 2nd 引数に展開 (= `$0` が 1st) |
| `\$1` | `$1` | `$1` | エスケープ → リテラル `$1` (引数有無に依らず) |
| `\$100` | `$100` | `$100` | `$1` は数字前で展開対象だが `\` で抑止 → リテラル |
| `$ARGUMENTS` | `alpha bravo` | (空) | 全引数に展開 |
| `\$ARGUMENTS` | `$ARGUMENTS` | `$ARGUMENTS` | エスケープ → リテラル |
| `$0` | `alpha` | (空) | 1st 引数 |
| `\\$1` | `\\bravo` | `\\` | 二重 `\` は両方残り、`$1` は通常展開される (= エスケープ成立せず) |
| `price is \$1.00` | `price is $1.00` | `price is $1.00` | prose 中の金額表記の標準形 |
| `cost\$50` | `cost$50` | `cost$50` | 行頭でなくても `\$` は有効 |

**ポイント**:
- `\$` は「単一の `\` が展開トークン直前にあるとき」だけエスケープ成立。`\\$1` のように `\` が 2 個だと `\\` がそのまま残り `$1` は展開される
- エスケープは引数の有無に依存しない (= 引数 0 個でも `\$1` はリテラル `$1` のまま)
- `${CLAUDE_*}` 系 (4.2) は別機構。本エスケープは `$N` / `$ARGUMENTS` / `$<name>` の引数展開トークン向け

### 4.2 環境変数 / plugin 系

| 変数 | 説明 | 確証ステータス |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | plugin installation root | **[実機検証済: ~v2.1.156]** skill template として展開され、claude に流入する本文には絶対パスが入る。bash env としては流入しない (= bash で `echo $CLAUDE_PLUGIN_ROOT` は空)。**mid-session で plugin update した場合は `/reload-plugins` まで古い version path を指す** |
| `${CLAUDE_PLUGIN_DATA}` | plugin data dir (`$CLAUDE_CONFIG_DIR/plugins/data/<id>/`) | [spec] plugin update で保持される (= 永続 state はここに置く) |
| `${CLAUDE_SKILL_DIR}` | skill SKILL.md のあるディレクトリ (plugin skill なら skill subdir、not plugin root) | **[実機検証済: v2.1.170 (本リポ自身)]** supporting file 参照に使う、cwd 非依存。本リポの SKILL.md 自身が `${CLAUDE_SKILL_DIR}/reference/` で reference を参照して現に動作している (§4.4 の 2026-06-10 検証履歴も根拠) |
| `${CLAUDE_PROJECT_DIR}` | project root | [spec] |
| `${CLAUDE_SESSION_ID}` | session UUID v4 | [spec] |
| `${CLAUDE_EFFORT}` | current effort level | [spec] |
| `${ENV_VAR}` | 任意 env 変数 | [spec] `${HOME}` 等 |
| `${user_config.*}` | plugin.json `userConfig` 値 (plugin 限定) | [spec] |

### 4.3 重要な実機検証結果

**`${CLAUDE_PLUGIN_ROOT}` の経路別の有効性**:

| 経路 | 展開される? |
|---|---|
| SKILL.md template (= claude runtime が読む時) | ✓ [実機検証済: ~v2.1.156 (cmux-msg v0.28.13)] |
| Hook command 内 (= shell env として) | ✓ [spec]、`${CLAUDE_PLUGIN_ROOT}` が env var として hook process に inject |
| Skill から呼ばれた bash 内 (= bash env として) | **✗** [実機検証済: ~v2.1.156] bash で `echo $CLAUDE_PLUGIN_ROOT` は空 — ただし SKILL.md template で展開済の絶対パスが本文に入るので、Skill 経由なら問題なし |

**Skill 経由で plugin bin を叩く正解パターン**:

```md
本 skill 内で本文に `${CLAUDE_PLUGIN_ROOT}/bin/cmux-msg $ARGUMENTS` を Bash で実行してください。
```

→ AI に流入する時には `/Users/kawaz/.claude-personal/plugins/cache/cmux-msg/cmux-msg/0.28.13/bin/cmux-msg $ARGUMENTS` に置換済 (= bash 解決依存なく、その plugin instance の bin を確実指定)

### 4.4 展開境界 (= 推移しない) [実機検証済: v2.1.170]

template 変数 (`${CLAUDE_SKILL_DIR}` / `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PROJECT_DIR}` 等) は **「harness が直接ロードするファイル」でのみ展開**される single-pass 機構。そこから「参照される側」「subagent 側」「bash subprocess」へは **推移しない** (= shell の env と同じく明示伝達が必要)。

| 場所 | 展開? | 補足 |
|---|---|---|
| `SKILL.md` 本文 | ✓ | Skill 起動時、context 流入直前に展開 |
| `hooks.json` の `command` 文字列 | ✓ | hook 起動時に展開し shell exec |
| `.claude-plugin/*.json` / `marketplace.json` | (該当箇所のみ) | plugin 規約による |
| supporting files (`instruction.md` / `reference/*.md` 等) | **✗** | SKILL.md が `${CLAUDE_SKILL_DIR}/instruction.md` を指しても、その file の **中身は raw** |
| subagent の prompt | **✗** | Agent tool の `prompt` は親が組み立てる時点で展開済の値を埋める必要あり |
| Bash 起動 script の env | **✗** | `echo $CLAUDE_PLUGIN_ROOT` は空 (= 4.3 と同じ)。本文の `${...}` は展開済で流入するが bash 自身は env を持たない |
| MCP サーバ / 外部プロセスの env | **✗** | 親から明示伝達しない限り見えない |

**How to apply**:

1. **supporting file (instruction.md 等) でパス参照したい**: supporting file 内に `${CLAUDE_SKILL_DIR}` と書いても literal で残る (= Read が ENOENT)。SKILL.md 本文 or subagent prompt 側で展開済の絶対パスを組み立てて渡す。
2. **Bash script でパス参照したい**: SKILL.md 本文の bash code block 内の `${CLAUDE_SKILL_DIR}` は展開対象。ただし script 内で `$CLAUDE_SKILL_DIR` を読むと空なので、env / 引数で明示伝達する (`SKILL_DIR="${CLAUDE_SKILL_DIR}" bash "${CLAUDE_SKILL_DIR}/scripts/run.sh"`)。
3. **subagent prompt で指示したい**: Agent tool の prompt は親 context で組み立てるので `${CLAUDE_SKILL_DIR}` を直接埋め込めば展開済の値が乗る。subagent は独立 context だが、prompt に `CLAUDE_SKILL_DIR=${CLAUDE_SKILL_DIR}` の形で絶対パスが書かれていれば、その配下の `instruction.md` 等を Read できる。

**検証履歴**:

- `personal-gh-image-attach` skill で `${CLAUDE_SKILL_DIR}` を SKILL.md 本文に記載 → Skill 起動時に `/Users/kawaz/.claude-personal/skills/personal-gh-image-attach` (= symlink パス、resolve 後の実体ではない) に展開されることを確認 [実機検証済: v2.1.170 2026-06-10]
- 冒頭プロローグとして `Base directory for this skill: <path>` が自動付与される
- `${CLAUDE_PLUGIN_ROOT}` の bash env 内では空 [実機検証済: v2.1.170 (claude-plugin-reference)]

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
- `disable-model-invocation: true` を付けた 6 user skill (`/cmux-msg-peers` 等) は **AI の system-reminder available skills 一覧に出てこない** (= description 含めて context 食わない) → ユーザ専用 slash command として最適 [実機検証済: ~v2.1.156]
- 大本 `skills/cmux-msg/SKILL.md` (= disable-model-invocation 無し) は AI 一覧に出る、`/cmux-msg:cmux-msg` で full namespace 表示

### 6.1 `disallowed-tools` の実機挙動 [実機検証済: v2.1.170]

skill frontmatter の `disallowed-tools` に挙げた tool は、その skill が active な間 (= 本文 invoke 後、次のユーザメッセージまで) Claude の利用可能 tool プールから除外される。

検証マトリクス (temp project の `.claude/skills/<name>/SKILL.md` で `Bash` を対象に観測):

| frontmatter | skill 本文の指示 | 観測結果 |
|---|---|---|
| `disallowed-tools: Bash` | 「Bash で echo を実行せよ」 | `Permission to use Bash has been denied.` で拒否 |
| `allowed-tools: Bash(echo:*)` (disallowed なし) | 同上 | echo 成功 (= 対照群) |

- 拒否は permission denial の形で返る (= tool 自体が消えるのでなく実行が deny される)
- 用途: 自律 loop skill で `AskUserQuestion` を封じる / 破壊的 tool を一時的に外す等
- 全 skill / prompt 横断で恒久 block したい場合は permission settings の deny rule を使う (= こちらは skill scoped)

## 7. Skill content lifecycle

- skill invocation 時、本文が **single message として会話に挿入**
- その後 同 turn では skill file を re-read しない (= 「standing instructions」として書く、one-time steps だと忘れられる) [spec]
- compaction で会話が圧縮された場合、invoked skill は最初の 5,000 token まで re-attach (= 複数 skill 時は combined budget 25,000 token、優先度は最近 invoke 順) [spec]
- skill が context から drop されたら **再 invoke** で再度 load

## 8. Skill cache の reload 挙動 (実機検証)

- claude session 起動時に PATH に plugin bin が追加される
- plugin update が走っても **既存 session 内の Skill 解決先は古い cache (= 古い version path) を見続ける** [実機検証済: ~v2.1.156 (cmux-msg)]
- `/reload-plugins` (interactive command、AI からは叩けない) で最新 version cache に切替
- session restart でも同様に最新化
- = SKILL.md 本文に `${CLAUDE_PLUGIN_ROOT}/bin/...` を書いておけば、reload 後の skill invocation 時には新 version の絶対パスが embed される (= 古い cache 問題に巻き込まれない設計)

### 8.1 `/reload-skills` (= skill ディレクトリ再スキャン) [実機検証済: v2.1.170]

session 再起動なしに skill ディレクトリ群を再スキャンする slash command。`/reload-plugins` が plugin cache の version 切替なのに対し、こちらは **skill 定義 (SKILL.md / `commands/*.md`) の再読み込み** に使う。

- 実行すると `Reloaded skills: N skills available (no changes)` を返す
- `.claude/skills/<new>/SKILL.md` を新規追加してから実行すると available カウントに反映される (= project scope の新規 skill を拾う) ことを実機確認
- headless (`claude -p '/reload-skills'`) でも動作する (= 単純に再スキャンして要約を返すだけ。対話 UI 専用ではない)
- 用途: skill を編集 / 追加した直後、同一 session 内で反映させたいとき。`/reload-plugins` (plugin 版) と対をなす

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

## `[未検証]` 集約 (メンテ TODO 抽出用)

未検証項目を 1 箇所に集約 (= 格上げ対象の機械抽出用)。`[未検証: headless 不可]` は構造的に検証不能、`[未検証: TODO]` はやれば検証できる。

### headless 不可

- (現状なし)

### TODO

- [ ] `skillOverrides` の各 value (`on` / `name-only` / `user-invocable-only` / `off`) の実機挙動 (§10、現状 [spec])
- [ ] `paths` glob による skill auto-invoke 限定の実機挙動 (§3、現状 [spec])
- [ ] compaction 時の skill re-attach token budget (5,000 / combined 25,000) の実測 (§7、現状 [spec])

## 11. 参考 URL (出典)

- [Skills](https://code.claude.com/docs/en/skills.md)
- [Plugins Reference (Path behavior rules)](https://code.claude.com/docs/en/plugins-reference.md)
- [Plugins (overview)](https://code.claude.com/docs/en/plugins.md)
