# コマンド編 — `commands/*.md` の役割 / 書式 / skills との使い分け

> 本書は **plugin が定義する custom slash command** (= `commands/*.md`) の話。**組み込み slash command** (= `/clear` `/compact` `/plugin` `/code-review` 等の Anthropic 同梱) のリファレンスは [builtin-slash-commands.md](builtin-slash-commands.md) を参照。

> `[spec]` = 公式 docs に明示記述、`[実機検証済]` = 自分の plugin で検証済、`[未検証]` = 公式記述頼りで実機未確認、`[実装の副産物]` = spec 保証なしの挙動
> - 無ラベル行の既定は `[spec]` (公式 docs 由来)。記憶・推測由来の項目は `[未検証]` を明示する。
> - `[実機検証済: ~vX.Y.Z]` の `~` は記述導入時期からの推定バージョン (当時の再検証記録ではない)。

**本質**: command は runtime 上は skills と同一機構。`commands/` は「ユーザ slash 第一意図」を表す配置上の慣習であり、技術的な別物ではない。

## 1. コマンドの位置づけ

公式 docs (= Skills docs) は「Custom commands have been merged into skills」「`.claude/commands/deploy.md` と `.claude/skills/deploy/SKILL.md` は both create `/deploy` and work the same way」と説明している (= runtime / docs 上は custom command surface は skills に統合)。

ただし **plugin layout 上は `commands/*.md` が残っており**、`slash-command first` の配置として使い分けられる [実機検証済: ~v2.1.159 (codex plugin / gh-monitor)]。`commands/<name>.md` は **ユーザが意図的にスラッシュで打つ entry** を第一意図にした置き方で、`disable-model-invocation: true` を組み合わせて AI 自動 invoke を切れる ([§3](#3-frontmatter-全-field) 参照)。

skill との対比:

| 構造 | 第一意図 | 表示 | AI 自動 invoke | ユーザ slash | 補完 |
|---|---|---|---|---|---|
| **command** (`commands/<name>.md`) | ユーザがスラッシュで打つ entry | `/<plugin>:<name>` | option (`disable-model-invocation`) | ✓ | argument-hint で hint 出せる |
| **skill** (`skills/<name>/SKILL.md`) | AI が description マッチで起動 | `/<plugin>:<name>` | デフォルト ✓ | ✓ | description で AI トリガ |
| **agent** (`agents/<name>.md`) | AI が delegate するサブエージェント | ユーザ非可視 | Agent tool 経由 | ✗ | `skills:` で内部 skill を import 可 |

[実機検証済: ~v2.1.159 (codex plugin)] 上 3 軸は同一 plugin 内で混在可能。例: codex plugin は `commands/review.md` (= コマンド実行型、user-only contract), `commands/setup.md` (= 両用途), `skills/codex-cli-runtime/SKILL.md` (= ガイド型、cli 使い方が AI に流入、`user-invocable: false` で内部 helper), `agents/codex-rescue.md` (= AI delegate サブエージェント) を併用している。

## 2. 役割マッピング (= どこに置くか)

| 意図 | 置き場所 | 設定 |
|---|---|---|
| **コマンド実行型** (= invoke 自体が action / 仕事の実行) | `commands/<name>.md` | 必要なら `disable-model-invocation: true` |
| **ガイド / 指南型** (= invoke で使い方 context が流入、AI が後続判断・実行) | `skills/<name>/SKILL.md` | (なし) |
| AI 専用 helper (= 内部 import 用) | `skills/<name>/SKILL.md` | `user-invocable: false` |
| AI delegate サブエージェント | `agents/<name>.md` | `skills:` で helper import |

判断軸:
- **invoke が「実行」か「context 流入」か** → 実行なら commands、流入なら skills
- **AI に勝手に invoke されると困るか** (= 破壊的・shared state) → `disable-model-invocation: true`
- **ユーザに見せたくないか** → `user-invocable: false`
- 補完表示は配置で挙動が変わる ([skills.md §1](skills.md#1-skillmd-の配置パターン))

## 3. Frontmatter 全 field

```yaml
---
description: Run a Codex code review against local git state
argument-hint: '[--wait|--background] [--base <ref>] [--scope auto|working-tree|branch]'
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(node:*), Bash(git:*), AskUserQuestion
---
```

| field | 型 | 必須 | 用途 | 備考 |
|---|---|---|---|---|
| `description` | string | 推奨 | listing 表示 / AI 自動 invoke trigger (= **AI audience**) | 常時 context に乗るので **短く保つ**。`disable-model-invocation: true` の時は AI 視点で hidden。audience 別の使い分けは [skills.md §3 audience 別の使い分け](skills.md#audience-別の使い分け--description--when_to_use--argument-hint) 参照 |
| `argument-hint` | string | 任意 | autocomplete hint (= **ユーザ audience**) | 補完中スペース後にグレー `[...]` 表示、もう 1 文字打つと消える。例: `[--wait\|--background] [focus ...]` |
| `disable-model-invocation` | bool | 任意 | true = AI 自動 invoke 不可、manual `/<plugin>:<name>` のみ | listing から description も削除 = AI context 食わない |
| `allowed-tools` | string\|array | 任意 | このコマンド実行中に permission 無しで使える tool | turn 終了で clear |
| `disallowed-tools` | string\|array | 任意 | このコマンド実行中に使えなくなる tool | 危険 tool 防止。skill と共通機構、実機挙動は [skills.md §6.1](skills.md#61-disallowed-tools-の実機挙動-実機検証済-v21170) ([実機検証済: v2.1.170]) |
| `model` | string | 任意 | model override | 値セットは [skills.md §3 model 行](skills.md#3-frontmatter-全-field) と同じ (= `/model` の全 alias + `inherit` + full model name)。**`context: fork` 無しでの `model` 切替の落とし穴は [skills.md §9.1](skills.md#91-context-fork-無しで-model-を切替える時の落とし穴-実機検証済-v21181-cmux-msg)** [実機検証済: v2.1.181 (cmux-msg)] |
| `context` | string | 任意 | `fork` で subagent 実行 (skill と同じ機構) | **[実機検証済: v2.1.181 (cmux-msg)]** 公式 docs では skills 固有 field として記載されるが、commands でも動作する (= reference §1 「runtime 上同一機構」の実証)。詳細 [skills.md §9](skills.md#9-subagent-execution-context-fork) |
| `agent` | string | 任意 | `context: fork` 時の subagent type | **[実機検証済: v2.1.181 (cmux-msg)]** `Explore` / `Plan` / `general-purpose` (default) / custom。commands でも動作 |

skill との frontmatter 差分:
- skill にある `name` / `when_to_use` / `arguments` / `paths` / `hooks` / `shell` は command にはない (= command は file 名から決まる)
- **`context: fork` / `agent` は実機では commands でも動作** (= reference §1 「runtime 上同一機構」、公式 docs では skill 固有として記載されるが commands でも有効) [実機検証済: v2.1.181 (cmux-msg)]
- 公開済 plugin の user slash command (= bash 橋渡し系) のベスプラ recipe は [skills.md §9.2](skills.md#92-公開済-plugin-の-user-slash-command-推奨-recipe-実機検証済-v21181-cmux-msg)
- command にある `argument-hint` は skill にもあるが、command のほうが「補完で見せる」用途が強い

## 4. 補完表示の挙動 (実機検証)

詳細は [skills.md §1 補完表示ルール](skills.md#1-skillmd-の配置パターン)。commands 配置は一般語名でも full namespace `/<plugin>:<name>` 表示になり plugin 元が明示される。

実機例 [実機検証済: ~v2.1.160 + v2.1.183]:
- `/codex` 補完 → `/codex:setup` `/codex:status` etc. (= 全 full namespace)
- `/statu` 補完 → built-in `/status` + `/codex:status` `(codex)` 等が fuzzy match 候補化 (= 短縮形からも到達可能)

ユーザが短縮形 `/<name>` を打っても fuzzy match で候補に出るので、commands 配置 (= full namespace 表示) でも実用上問題ない。

### 4.1 補完メニューでのクリック挙動 [未検証: headless 不可]

補完メニューで slash command を**クリックすると即実行されず、prompt 入力欄に挿入される**。実行するには Enter を押す。

- 出典: CHANGELOG v2.1.162「Clicking a slash command in the autocomplete menu now fills it into your prompt instead of running it immediately; press Enter to run」
- 対話 TUI 専用挙動のため headless (`claude -p`) では検証不可 → `[未検証: headless 不可]`、changelog 文言を出典として記載
- 含意: 引数を要する command (= `argument-hint` 付き) でクリック後に引数を追記できる。`§3` の `argument-hint` がより活きる

## 5. 書式の best practice (= 命令調 + 構造化)

codex plugin の commands ファイルを見ると、**小さい wrapper command** は Run → If → Output rules の 3 段が綺麗に揃っており、AI が「次のアクションは何か」を即座に判別しやすい。**複雑な command** は Core constraint / Execution mode / Argument handling / Foreground flow / Background flow / Output rules のように **要件ごとに section を分ける**スタイルを取る。

### 5.1 小さな wrapper command の型 (= Run / If / Output rules 3 段)

例: `commands/setup.md` のような「外部 binary を 1 回叩いて結果ルーティング」型。

```markdown
---
description: ...
argument-hint: '[--enable-X|--disable-X]'
allowed-tools: Bash(node:*), AskUserQuestion
---

Run:

\`\`\`bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/foo.mjs" $ARGUMENTS
\`\`\`

If the result says X and Y is available:
- Use `AskUserQuestion` exactly once to ask whether Claude should Z now.
- Put the install option first and suffix it with `(Recommended)`.
- Use these two options:
  - `Z (Recommended)`
  - `Skip for now`
- If the user chooses Z, run:

\`\`\`bash
some-command
\`\`\`

If X is already done or Y is unavailable:
- Do not ask about Z.

Output rules:
- Present the final output to the user.
- If installation was skipped, present the original output.
- If X is installed but not authenticated, preserve the guidance to run `!foo login`.
```

### 5.2 複雑な command の型 (= 要件ごとに section)

例: `commands/review.md` のような「複数モード・background/foreground 制御・引数解釈・複雑な分岐」が必要な command:

```markdown
---
description: Run a Codex code review against local git state
argument-hint: '[--wait|--background] [--base <ref>] [--scope auto|working-tree|branch]'
disable-model-invocation: true
---

## Core constraint
- 必ず守る invariant、誤動作で取り返しがつかない事項
- 例: 「review-only、fix 自動適用しない」

## Execution mode
- --wait / --background の選択
- 規模見積もりロジック

## Argument handling
- 引数を `task` に渡す方針

## Foreground flow
1. ... (= --wait 時の処理)

## Background flow
1. ... (= --background 時の処理)

## Output rules
- 最終出力の format
```

### 5.3 共通する書式の本質

書式タイプは違っても以下は共通 (= ルール記述の一般原則「具体的・完結・省コンテキスト」と同じ思想):

1. **section の境界がはっきりしている**: AI が分岐の網羅性を目視で確認できる (= 3 段でも 6 section でも同じ効果)
2. **命令調 (= 命令文・箇条書き)**: prose 最小、敬語・前置きなし
3. **rationale を書かない**: コマンドは "what to do now" 専用、"why" は DR / docs に逃がす
4. **具体的なコマンドを inline で**: 「別 doc 参照」しない

これにより:
- AI が「何を読むべきか」即決できる
- ユーザがスラッシュ補完で見る description (= frontmatter `description`) と本体内容の役割分担が明確化
- 分岐の未定義部分が目視で見つかる

## 6. 参考実装

- **codex plugin (`openai/codex-plugin-cc`)**: commands / skills / agents の 3 軸 + visibility 制御を 1 plugin で実用している模範例
  - `commands/setup.md`, `commands/rescue.md` — 両用途 (ユーザ + AI)
  - `commands/review.md`, `commands/adversarial-review.md`, `commands/status.md`, `commands/cancel.md`, `commands/result.md` — `disable-model-invocation: true` のユーザ専用 contract
  - `skills/codex-cli-runtime/SKILL.md`, `skills/codex-result-handling/SKILL.md`, `skills/gpt-5-4-prompting/SKILL.md` — `user-invocable: false` の内部 helper
  - `agents/codex-rescue.md` — AI delegate サブエージェント、`skills:` で内部 helper を import

## 7. 関連

- [skills.md](skills.md) — skill 編 (= invocation 制御の表は section 6)
- [agents.md](agents.md) — agent 編
- [distribution.md](distribution.md) — 配布フロー

## `[未検証]` 集約 (メンテ TODO 抽出用)

未検証項目を 1 箇所に集約 (= 格上げ対象の機械抽出用)。`[未検証: headless 不可]` は対話 UI 専用で構造的に検証不能、`[未検証: TODO]` はやれば検証できる。

### headless 不可

- [ ] 補完メニューでの slash command クリック → prompt 挿入挙動 (§4.1、対話 TUI 専用)

### TODO

- (現状なし。補完表示ルール (§4) は spec 保証でなく現バージョンの実機挙動のため、将来版での再確認は推奨)

## 8. 参考 URL (出典)

- [Commands](https://code.claude.com/docs/en/commands.md) (= 公式 commands リファレンス。live 確認済 2026-06-11)
- [Skills](https://code.claude.com/docs/en/skills.md) (custom command は skills に統合されている旨を明記)
