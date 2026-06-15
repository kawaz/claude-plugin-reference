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

[実機検証済: ~v2.1.159 (codex plugin)] 上 3 軸は同一 plugin 内で混在可能。例: codex plugin は `commands/review.md` (= user-only contract), `commands/setup.md` (= 両用途), `skills/codex-cli-runtime/SKILL.md` (= AI-only internal helper, `user-invocable: false`), `agents/codex-rescue.md` (= AI delegate サブエージェント) を併用している。

## 2. 役割マッピング (= どこに置くか)

| 意図 | 置き場所 | 設定 |
|---|---|---|
| ユーザがスラッシュで打つ contract、AI に勝手にやられたくない (= 単一ファイルで完結) | `commands/` | `disable-model-invocation: true` |
| ユーザもよく打つが AI 自律起動も歓迎 (= 単一ファイル) | `commands/` | (なし) |
| ユーザ手動起動が主だが skill 固有機能が必要 (= supporting files / `context: fork` / `paths` / `hooks` / named `arguments` 等) | `skills/` | `disable-model-invocation: true` |
| AI が空気読んで起動する主体、ユーザはたまに打つ | `skills/` | (なし) |
| AI 専用 / 他 skill/agent から import される内部 helper | `skills/` | `user-invocable: false` |
| AI delegate 専用サブエージェント | `agents/` | `skills:` で helper import |

判断軸:
- **ユーザの明示性 vs AI 自律性のどちらが第一意図か** → ユーザ第一なら commands、AI 第一なら skills
- **AI に勝手に invoke されると困るか** (= 破壊的・shared state 操作) → 困るなら `disable-model-invocation: true` で contract 化
- **単独で動かす意図がない内部 contract か** (= 他から import される helper) → `user-invocable: false` の skill

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
| `description` | string | 推奨 | listing に表示 / AI 自動 invoke trigger | `disable-model-invocation: true` の時は AI 視点で hidden |
| `argument-hint` | string | 任意 | autocomplete hint | 例: `[--wait\|--background] [focus ...]` |
| `disable-model-invocation` | bool | 任意 | true = AI 自動 invoke 不可、manual `/<plugin>:<name>` のみ | listing から description も削除 = AI context 食わない |
| `allowed-tools` | string\|array | 任意 | このコマンド実行中に permission 無しで使える tool | turn 終了で clear |
| `disallowed-tools` | string\|array | 任意 | このコマンド実行中に使えなくなる tool | 危険 tool 防止。skill と共通機構、実機挙動は [skills.md §6.1](skills.md#61-disallowed-tools-の実機挙動-実機検証済-v21170) ([実機検証済: v2.1.170]) |
| `model` | string | 任意 | model override | `sonnet` / `opus` / `inherit` |

skill との frontmatter 差分:
- skill にある `name` / `when_to_use` / `arguments` / `paths` / `context` / `agent` / `hooks` / `shell` は command にはない (= command は file 名から決まる、subagent 化もしない)
- command にある `argument-hint` は skill にもあるが、command のほうが「補完で見せる」用途が強い

## 4. 補完表示の挙動 (実機検証)

command の補完表示も skill と同じ 3 パターンルールに従う ([skills.md §1 の補完表示ルール](skills.md#1-skillmd-の配置パターン)参照)。command 名は plugin 名 prefix を持たないことが多いので (= `setup`, `review`, `status`)、多くは full namespace `/<plugin>:<name>` 表示になる。

実機例 [実機検証済: ~v2.1.160 2026-06-02]:
- `/codex` 補完 → `/codex:setup` `/codex:status` `/codex:rescue` `/codex:review` `/codex:cancel` `/codex:adversarial-review` (= 全 full namespace、prefix 不一致)
- `/statu` 補完 → `/status` (built-in), `/statusline`, `/codex:status` `(codex)`, `/usage`, `/ide`。bare `/status` で codex 側は **canonical 候補としては出ず**、full 表示 `/codex:status` 内の `status` 部分マッチで出る
- `/gh-` 補完 → `/gh-monitor:watch-pr` `/gh-monitor:watch-workflow` (= namespace 付きのみ)

**含意**:
- command / skill 名に `setup` / `status` のような **一般語**を使っても namespace 必須なのでコンフリクトしない
- 逆に短縮形 `/<name>` で打たせたいなら、名前を plugin 名 prefix で揃える (= cmux-msg の `cmux-msg-list` 方式)。command でも同じ
- これは現バージョンの実機挙動で spec 保証ではない (= 将来版で再確認推奨)

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
