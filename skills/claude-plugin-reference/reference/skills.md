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
| `<plugin>/skills/<name>/SKILL.md` | `<plugin>:<name>` | `/codex:codex-cli-runtime` 等 (= 補完表示は後述) |
| `<plugin>/commands/<name>.md` | `<plugin>:<name>` | `/codex:setup`、`/codex:review` — 詳細は [commands.md](commands.md) |
| `<plugin>/SKILL.md` (plugin root) | frontmatter `name` or plugin 名 | `/cmux-msg:cmux-msg` |
| `~/.claude/skills/<name>/.claude-plugin/plugin.json` (skills-dir auto-load、v2.1.157〜) | plugin 名 | `claude plugin init` 生成形、詳細 §8.3 |

### 補完表示ルール [実機検証済: ~v2.1.160 + v2.1.183]

canonical は常に `/<plugin>:<name>` (bare 名のフォールバック candidate は無い)。short / full 切替は **配置** で分岐:

| 配置 | 補完表示 | 例 |
|---|---|---|
| `skills/<plugin>/SKILL.md` (= plugin root) | full `/<plugin>:<plugin>` (`/<plugin>` 単独だと曖昧なため) | `/cmux-msg:cmux-msg` |
| `skills/<name>/SKILL.md` (`name ≠ plugin`) | 短縮 `/<name>` + `(<plugin>)` | (仮例: `skills/foo/SKILL.md` → `/foo` `(<plugin>)`) |
| `commands/<name>.md` | full `/<plugin>:<name>` + `(<plugin>)` | `/codex:setup` |

短縮表示の skills 配置は plugin 元が見えないので、他 plugin と命名衝突した時の判別性が低い。user invocable な entry は commands 配置にすると補完で plugin 元が常に出る。

fuzzy match は表示文字列に対して動く: `/statu` で `/codex:status` が full 表示内の部分マッチで候補化される。

### nested `.claude/skills/` の scope-based loading

project root だけでなく **cwd の祖先方向にある任意の `.claude/skills/<name>/SKILL.md` も自動 load** される (v2.1.178 〜)。cwd が `<root>/sub/` で `<root>/sub/.claude/skills/nested-skill/` がある場合、その nested-skill は available-skills 一覧に出る。一方 cwd が `<root>/` だけだと nested-skill は出ない (= scope は cwd 起点で決まる) [実機検証済: v2.1.193]。

- 同名 skill (= root と nested 両方に `name: foo`) が両方 load された場合、両方が available-skills に並ぶ ([spec] CHANGELOG v2.1.178 は disambiguate 名を `<dir>:<name>` 形式と説明、headless listing では両方とも bare `foo` で見えたため Skill tool 経由の addressability は未検証)
- v2.1.178 で nested skills の dir-qualified 名が non-interactive run の permission prompt で block される bug が修正 ([spec] CHANGELOG、headless 検証は未実施)
- v2.1.178 で `.claude/skills` / `.claude/hooks` が symlink の時 Linux sandbox 起動失敗 ([spec] CHANGELOG、macOS 環境のため未検証)

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
| `description` | string | 推奨 | AI invoke trigger / listing (= **AI audience**、短く保つ) | `when_to_use` と合わせて max 1,536 chars [spec] |
| `when_to_use` | string | 任意 | description 補強 (= **AI audience**) | 「ユーザが何を言ったら invoke してほしいか」 |
| `argument-hint` | string | 任意 | 補完中グレー hint (= **ユーザ audience**) | 例: `[issue-number]`, `[filename] [format]` |
| `arguments` | string\|array | 任意 | 位置引数 named getter | `arguments: [issue, branch]` で `$issue` `$branch` 展開可 |
| `disable-model-invocation` | bool | 任意 | true = AI 自動 invoke 不可、manual `/name` のみ | listing から description も削除 = AI コンテキスト食わない (= ユーザ専用 skill 向け) [実機検証済: ~v2.1.156] |
| `user-invocable` | bool | 任意 | false = `/` menu と listing から非表示、AI のみ invoke | background knowledge 用途 |
| `allowed-tools` | string\|array | 任意 | skill active 中に permission 無しで使える tool | `"Bash(git add *) Bash(git commit *)"`、turn 終了で clear |
| `disallowed-tools` | string\|array | 任意 | skill active 中に使えなくなる tool | auto-loop で危険 tool 防止。**[実機検証済: v2.1.170]** `disallowed-tools: Bash` の skill が active な間、Bash 実行は `Permission to use Bash has been denied.` で拒否される (= 次メッセージで解除)。詳細 §6.1 |
| `model` | string | 任意 | model override | **[実機検証済: v2.1.181 (cmux-msg)]** `/model` と同じ全 alias + `inherit` を受け付ける (公式 docs `/en/skills` の「Accepts the same values as `/model`」記述を実機で確認)。値: `default` / `best` / `fable` / `sonnet` / `opus` / `haiku` / `sonnet[1m]` / `opus[1m]` / `opusplan` / full model name (`claude-haiku-4-5` 等)。**注意**: `context: fork` 無しで親 context を引き継ぐ場合、メイン session の context 使用量が target model の window を超えると失敗する。詳細 §9.1 |
| `effort` | string | 任意 | effort override | `low` / `medium` / `high` / `xhigh` / `max` (model 依存。値セットの正本は [hooks.md §6.1](hooks.md#61-共通フィールド)) |
| `context` | string | 任意 | `fork` で subagent 実行 | parent session から isolation |
| `agent` | string | 任意 | `context: fork` 時の subagent type | `Explore` / `Plan` / `general-purpose` / custom |
| `hooks` | object | 任意 | このスキル scoped hook | format は `.claude/settings.json` hooks と同じ |
| `paths` | string\|array | 任意 | glob で skill auto-invoke 対象を限定 | `"src/**/*.ts"` で .ts のみ |
| `shell` | string | 任意 | `!`cmd`` の shell 指定 | `bash` (default) / `powershell` |

[spec、公式 `skills.md` frontmatter reference より]

**v2.1.186 frontmatter 変更点**:
- `display-name` / `default-enabled` / `fallback` / `metadata.*` の 4 key は kebab-case / snake_case / camelCase いずれも受理 ([spec] CHANGELOG v2.1.186、他 field の case 揺れは未保証)
- 壊れた YAML frontmatter は **silent fail せず本文を empty metadata で load** する [実機検証済: v2.1.193]。listing には `- <name>` のみ (description なし) で出る。`/<name>` は引けるが AI 自動 invoke 用 description が無い (公式 docs 記述、`--debug` で parse error 表示)

### audience 別の使い分け (= description / when_to_use / argument-hint)

frontmatter の文字列 field は **読み手 (audience) が違う**。混同すると context を圧迫しつつユーザにも刺さらない設計になる:

- **`description` / `when_to_use` (AI audience)**: skill 発見 / 自動 invoke 判定 / listing 常時 context に乗る。AI が「いつ呼ぶか」を判断できる文を **短く** 書く。ユーザ向け使い方を埋め込まない
- **`argument-hint` (ユーザ audience)**: 補完中スペース後にグレー `[...]` 表示。引数の形 (`[opt1|opt2] <required>` 等) を示す
- **ユーザ向け詳細使い方** (例 / 引数仕様 / 出力形式 / トラブルシュート) は **SKILL.md 本文** か **plugin root SKILL.md** に分離する。本文は invocation 後に読み込まれるので常時 context を圧迫しない

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

**Skill 経由で plugin bin を叩くパターン**:

SKILL.md 本文に `${CLAUDE_PLUGIN_ROOT}/bin/<exe> $ARGUMENTS` と書くと AI へ流入する時点で展開済み絶対パス `/Users/.../plugins/cache/<plugin>/<ver>/bin/<exe> $ARGUMENTS` に置換される (= その plugin instance の bin を確実指定、bash 解決依存なし)。

**permission ガード対策 (実行コマンドの書き方)**: `${CLAUDE_PLUGIN_ROOT}/bin/<exe>` を Bash で直接叩く形は plugin path 個別の `Bash(<absolute path>:*)` rule を要求する。ホスト常駐コマンド (`bash` / `python3` / `bun` / `node` 等) を頭に挟んでフルパスを引数化すると、汎用 rule (`Bash(bash:*)` 等) で通る:

- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run.sh $ARGUMENTS` ← `Bash(bash:*)` で通る
- 純バイナリ (= `bash` 等で実行できない) は wrapper script (= bash / sh) を挟み、wrapper 内で相対パスから bin/<exe> を起動する

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

### 8.2 skill hot-reload の再アナウンス粒度 [spec]

単一 skill の変更時、以前は全 skill listing を context へ再送していたが、v2.1.174 で**変更された skill のみ再アナウンス**するよう修正された (出典: CHANGELOG v2.1.174)。内部挙動 (context への注入粒度) のため headless での直接観測は未実施。

### 8.3 `claude plugin init <name>` で `.claude/skills/` 配置の plugin を scaffold [実機検証済: v2.1.193]

v2.1.157 以降、`.claude/skills/<name>/` 配下に `.claude-plugin/plugin.json` を持つディレクトリは **marketplace 経由なしに自動 load** される (= `<name>@skills-dir` として enable される)。

- `claude plugin init <name>` で `~/.claude/skills/<name>/` に `SKILL.md` + `.claude-plugin/plugin.json` (`"skills": ["./"]` 入り) を生成
- 「次 session で auto-load される」案内が出る (= 即時反映は `/reload-plugins` 必要)
- `--with skills,agents,hooks,mcp,lsp,output-style,channel` でコンポーネント追加 scaffold
- 通常の plugin と同じく `claude plugin disable <name>@skills-dir` で off

### 8.4 user-level skill の autocomplete 重複表示 [未検証]

複数 plugin が enable な時に user-level skill が slash-command autocomplete で重複表示される bug を v2.1.183 で修正 ([spec] CHANGELOG、対話 UI 専用挙動のため headless 観測不能)。

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

### 9.1 `context: fork` 無しで `model` を切替える時の落とし穴 [実機検証済: v2.1.181 (cmux-msg)]

skill / command frontmatter で `model` field を指定すると、その invocation 中だけメインモデルが切り替わるが、**parent session の context (= 会話履歴 + skill/command 本文 + system prompt) は target model に持ち越される**。target model の context window で収まらないと invocation 失敗 → 場合によっては **メイン session が「Context limit reached」状態に陥り継続不能**。

検証マトリクス (Max plan、メイン session が opus-4-7[1m] で 1M context 81% 使用中):

| `model` 指定 | 挙動 |
|---|---|
| `haiku` | ✗ `Context limit reached` (haiku に `[1m]` alias なし、200K のみ) |
| `sonnet` (alias) | ✗ `API Error: Usage credits required for 1M context` — sonnet[1m] は Max plan でも credit 課金、auto-upgrade 対象外 |
| `sonnet[1m]` | ⚠ 動くが usage credit が課金される |
| `opus` (alias) | ✓ OK (Max plan auto 1M upgrade) |
| `claude-opus-4-*` (full name) | ✓ OK (auto 1M upgrade は full name でも効く。公式 docs の「`[1m]` suffix 必要」は API レベルの話、実機では alias / full name 問わず Max plan で 1M upgrade される) |

→ **`context: fork` を併用すれば fresh subagent context になるので、上記の落とし穴を全て回避**できる (= target model の context window を親 context が圧迫しない)。

事故事例: `sonnet` alias で API Error → メイン session が `/clear` も効かない「Context limit reached」状態に陥り、claude session 終了 + `/resume` で復旧。安易な model 切替は session 不安定化のリスクが高い。

### 9.2 公開済 plugin の user slash command 推奨 recipe [実機検証済: v2.1.181 (cmux-msg)]

「bash 1 コマンド叩いて結果を返すだけ」の薄い橋渡し系 user command (= 引数解釈ほぼ不要、独立で実行可能) の推奨 frontmatter:

```yaml
---
description: <一行説明>
argument-hint: <pattern>       # 任意
disable-model-invocation: true # AI listing から hidden、user-only
model: haiku                   # 最軽量、200K で十分
context: fork                  # 親 context 非継承 (= これが無いと §9.1 の事故)
agent: general-purpose         # subagent type
---
```

メリット:
- **メイン session の context size に依存せず安全** (= fresh subagent context、§9.1 の落とし穴を構造的に回避)
- **haiku 最軽量** (= 安い + 早い、しかも haiku は effort 非対応で extended thinking しない、即応)
- 比較: 同じ task を `opus` で叩いていた時は `date` 1 つに ~9 秒かかっていた (= default effort=high の extended thinking が無駄に発動)、haiku は即応
- **AI からもユーザ補完からも見えるかは個別に制御可能** (= `disable-model-invocation` で AI hidden、`_` prefix 命名で補完候補からも先頭曖昧検索で hidden)

参照: cmux-msg v0.30.12 の `commands/<sub>.md` 群がこの recipe を採用。検証履歴は `docs/findings/2026-06-18-slash-command-context-fork-and-model-validation.md`。

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
