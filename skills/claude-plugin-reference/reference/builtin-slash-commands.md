# 組み込み slash command リファレンス (対話 UI)

[spec] 一次資料は公式 docs ([code.claude.com/docs/en/commands](https://code.claude.com/docs/en/commands)、2026-06 時点)。本書はそれを **カテゴリ別** に再編 + バイナリ実装との突合 + cli.md / distribution.md との cross-link。

> **このページの担当範囲**:
> - 対話セッション中に `/` で打つ **組み込み slash command** (= Anthropic 同梱) を網羅。
> - **bundled skills / workflows** (= `/<name>` でも呼べるが実態は skill/workflow) は別ラベルで明示。
> - **MCP prompts** (`/mcp__<server>__<prompt>`) は動的で対象外。
> - **custom commands / user skills** (= `commands/*.md` / `skills/*/SKILL.md`) は [commands.md](commands.md) / [skills.md](skills.md) 参照。
> - **CLI フラグ / subcommand** (= `claude --print` / `claude plugin list` 等) は [cli.md](cli.md) 参照。

凡例:
- ` [Skill]` — 公式 docs で `Skill` ラベル付き (= bundled skill。`SKILL.md` 同等構造、AI 自動 invoke もあり得る)
- ` [Workflow]` — 公式 docs で `Workflow` ラベル付き (= bundled dynamic workflow、background で subagent 展開)
- `[min: vX.Y.Z]` — その version 以降で実装
- `[max: vX.Y.Z]` — その version 以前のみ (= 後継版で削除)
- alias は本コマンド行末に併記

## Skill のスタック起動 (`/skill-a /skill-b do XYZ`)

先頭から連続する `/name` トークンを skill 名として複数個認識し、末尾のテキストを各 skill の引数として渡す。上限は公式 docs ([code.claude.com/docs/en/commands](https://code.claude.com/docs/en/commands)) で「最大 6 skill」と明記 [spec v2.1.199] — CHANGELOG v2.1.199 の「先頭 5 skill まで」という表記と数値が食い違う。headless (`-p`) では skill ごとの実際のロード有無が安定して再現できず、上限値自体の実機確認はできず [未検証 v2.1.199]。

## セットアップ / 起動

| command | 説明 |
|---|---|
| `/init` | `CLAUDE.md` 骨子生成。`CLAUDE_CODE_NEW_INIT=1` でスキル/フック/メモリも含む interactive flow |
| `/login` | Anthropic アカウントにログイン |
| `/logout` | サインアウト |
| `/setup-bedrock` | Bedrock 認証/リージョン/モデル pin (`CLAUDE_CODE_USE_BEDROCK=1` 時のみ表示) |
| `/setup-vertex` | Vertex AI 認証 (`CLAUDE_CODE_USE_VERTEX=1` 時のみ表示) |
| `/terminal-setup` | 端末 keybinding 設定 (VS Code / Cursor / Devin Desktop / Alacritty / Zed 専用表示) |
| `/keybindings` | キーボードショートカット設定ファイルを開く |
| `/install-github-app` | Claude GitHub Actions セットアップ wizard。Actions workflow セットアップ自体は optional に変更 [spec v2.1.187] |
| `/install-slack-app` | Claude Slack app の OAuth flow |
| `/web-setup` | ローカル `gh` 経由で claude.ai/code への GitHub 連携 |
| `/remote-env` | Cloud agent のデフォルト環境を選ぶ |

## セッション制御

| command | 説明 |
|---|---|
| `/clear [prompt]` — alias `/reset` `/new` | 新規会話開始。直前は `/resume` で復帰可、`/clear` 前の中身は `/rewind` でも巻き戻せる [spec v2.1.191]。**引数はクリア後の最初のプロンプトとして投入される** [実機検証済: v2.1.237] — 引数なしだと後継セッションは何も始めず指示待ちで止まり、引数付きだとその指示で即作業を開始する。公式ドキュメントは `[name]` = picker のラベルと記載 [spec v2.1.191] |
| `/compact [instructions]` | これまでの会話を要約して context 解放 (rules/skills/memory の生存範囲は `/en/context-window` 参照) |
| `/context [all]` | コンテキスト消費を色付きグリッドで可視化 |
| `/resume [session]` — alias `/continue` | session 復帰。v2.1.144 以降 `bg` マーク付きで background session も picker に出る |
| `/branch [name]` | ここから会話を分岐 (= 元会話は preserved)。background subagent に渡したいなら `/fork` |
| `/fork <directive>` [min: 2.1.161] | 現会話を継承した background subagent を起こす。結果は会話に戻る。<v2.1.161 では `/branch` の alias |
| `/rewind` — alias `/checkpoint` `/undo` | 会話/コードを過去地点まで巻き戻し、または選択 message から要約。`/clear` 前の地点にも遡れる [spec v2.1.191] |
| `/rename [name]` | session 名変更 (prompt bar に出る)。name 省略で auto |
| `/recap` | 現 session の 1 行要約をその場で生成 (自動 recap は離席復帰時) |
| `/diff` | uncommitted change + 各 turn の diff を interactive viewer で |
| `/copy [N]` | 直近 assistant 応答を clipboard へ。`N` で N 番前、コードブロックは picker (= `w` でファイル書き出し) |
| `/export [filename]` | 会話を plain text で書き出し / クリップボード |
| `/exit` — alias `/quit` | 終了。attached background session 中は **detach のみ** (session は走り続ける) |

## モデル / モード / effort

| command | 説明 |
|---|---|
| `/model [model]` | モデル切替 (= 既定としても保存)。s で session-only 切替、cached でない context 再読込の確認あり |
| `/effort [level\|auto]` | `low`/`medium`/`high`/`xhigh`/`max`/`ultracode` / `auto` から選択 (= モデルにより可選肢差、`max`/`ultracode` は session-only)。`ultracode` は xhigh + 自動 workflow orchestration |
| `/fast [on\|off]` | fast mode 切替 |
| `/plan [description]` | plan mode 突入。description で初動タスク指定 |
| `/sandbox` | sandbox mode toggle (対応プラットフォーム限定) |
| `/advisor [model\|off]` [min: 2.1.98] | advisor tool を有効化。`opus` / `sonnet` / `fable` [min: 2.1.170] / full model ID。引数なしで picker |
| `/goal [condition\|clear]` | ゴール条件を設定 (= claude が達成まで turn を継続)。`clear` `stop` `off` `reset` `none` `cancel` で解除 |
| `/btw <question>` | 会話履歴を汚さない side question |

## 権限 / アクセス制御

| command | 説明 |
|---|---|
| `/permissions` — alias `/allowed-tools` | allow/ask/deny ルール管理。`auto mode` の最近の denials も review 可。Recently-denied tab で承認した denial は close 時に永続化される [spec v2.1.191] |
| `/add-dir <path>` | 当該 session に作業 dir を追加。追加 dir 配下の `.claude/` 設定は **読まない** (CLAUDE.md 探索だけ)。既に working dir のときは案内メッセージのみで重複追加しない [spec v2.1.193] |
| `/cd <path>` [min: 2.1.169] | session を新 dir に移す (= prompt cache 保持、新 dir の CLAUDE.md は append、project storage 移動)。trust 未取得 dir は確認。<v2.1.169 で `Unknown command` |

## 設定 / 表示

| command | 説明 |
|---|---|
| `/config` — alias `/settings` | Settings UI 起動 (theme / model / output style 等)。`/config key=value [key=value ...]` で interactive / `-p` / Remote Control から直接 set [実機検証済: v2.1.193 (CHANGELOG 初出 v2.1.181)]。`/config --help` で利用可能 key 一覧 (`thinking` / `model` / `theme` / `outputStyle` / `permissionMode` / `editor` / `workflowKeywordTriggerEnabled` 等) [実機検証済: v2.1.193 (CHANGELOG 初出 v2.1.183)]。interactive UI では Enter/Space で toggle、Esc で save+close [未検証 v2.1.183] |
| `/status` | Settings UI を Status タブで開く (= version / model / account / connectivity)。応答中も動く |
| `/theme` | カラーテーマ切替 (auto / light / dark / 色覚配慮 / ANSI / `~/.claude/themes/` の custom) |
| `/tui [default\|fullscreen]` | TUI renderer 切替 + 会話保持で再起動。`fullscreen` で flicker-free alt-screen |
| `/focus` | last prompt + tool 1 行 + 最終応答だけの focus view toggle。fullscreen 限定。`viewMode` で session 越え固定 |
| `/scroll-speed` | マウスホイールスクロール速度 (fullscreen 限定、JetBrains terminal 非対応) |
| `/color [color\|default]` | prompt bar 色変更 (`red blue green yellow purple orange pink cyan` / `default`)。Remote Control 接続中は claude.ai/code 側に sync |
| `/statusline` | status line 自動設定 (説明 or 引数なしで shell prompt から推定) |
| `/voice [hold\|tap\|off]` | voice dictation toggle (Claude.ai アカウント必須) |

## plugin / skills / hooks / MCP / agents

| command | 説明 |
|---|---|
| `/plugin [subcommand]` | plugin 管理。引数なしで menu、または `list` / `install` / `enable` / `disable` 直叩き。CLI 等価: [`claude plugin`](cli.md#claude-plugin--claude-plugins)。v2.1.195 で `plugin.json` の `name` と marketplace entry name が異なる場合に Enable/Disable が動作しないバグを修正 [spec v2.1.195] |
| `/reload-plugins [--force]` | 有効 plugin を再読み込み。component reload 数を報告。MCP tool 一覧が変わって prompt cache 失効する場合は **`--force` 無しなら skip + warn** |
| `/reload-skills` [min: 2.1.152] | skill / commands dir を再 scan (= 起動中に追加/変更された skill を反映) |
| `/skills` | 利用可能 skill 一覧。`t` で token 数ソート、`Space` で hide → `Enter` で保存 |
| `/hooks` | hook 設定確認 (tool event 用)。仕様は [hooks.md](hooks.md) |
| `/mcp [reconnect <server>\|enable\|disable [<server>\|all]]` | MCP server 接続と OAuth 管理。CLI 等価: [`claude mcp`](cli.md#claude-mcp) |
| `/memory` | `CLAUDE.md` 編集 + auto-memory ON/OFF + auto-memory entry view |

## レビュー / 検証 / 修正

| command | 説明 |
|---|---|
| `/code-review [low\|medium\|high\|xhigh\|max\|ultra] [--fix] [--comment] [target]` [Skill] | working tree diff のレビュー。`--fix` で適用、`--comment` で GH PR inline、`ultra` で [`/ultrareview`](#ultrareview-related)。v2.1.154 以降は `/simplify` が cleanup-only 経路で分離。内部実装: v2.1.196 で 5 つの cleanup finder を 1 つに統合、token 使用量 ~25% 削減 (ユーザ向け挙動に変更なし) [spec v2.1.196] |
| `/simplify [target]` [Skill] [min: 2.1.154] | 4 つの review agent (reuse / simplification / efficiency / abstraction) 並列で cleanup 適用。**bug 探しはしない** → bug は `/code-review`。<v2.1.154 では `/code-review --fix` の alias |
| `/review [PR]` | PR を **ローカル** session でレビュー。v2.1.186 以降は `/code-review medium` と同じ review engine を使用 [spec]。cloud は `/code-review ultra` |
| `/security-review` | 現在 branch の git diff を脆弱性観点でレビュー (injection / auth / data exposure) |
| `/verify` [Skill] [min: 2.1.145] | アプリを実起動して change を実機検証 (test/type じゃなく挙動を見る) |
| `/run` [Skill] [min: 2.1.145] | アプリを起動して change が動いているか観察 (verify との分担: `/run` は driving、`/verify` は assertion) |
| `/run-skill-generator` [Skill] [min: 2.1.145] | `/run` / `/verify` 用の project-specific skill を生成 |
| `/fewer-permission-prompts` [Skill] | transcript を scan して頻出 read-only Bash/MCP を `.claude/settings.json` allowlist に追加 |
| `/debug [description]` [Skill] | session の debug log を ON 化して読む (= `claude --debug` で起動してなければ mid-session でも capture 開始) |

## バックグラウンド / 並列実行

| command | 説明 |
|---|---|
| `/background [prompt]` — alias `/bg` | この session を background agent として detach。`claude agents` で監視可 |
| `/batch <instruction>` [Skill] | リポ全体規模の変更を 5-30 単位に分解 + 並列実行。各 unit が独立 git worktree で subagent → PR。git リポ必須 |
| `/tasks` — alias `/bashes` | background で走っている全 task の管理 |
| `/stop` | 現在 attach 中の background session を停止 (transcript / worktree は保持)。detach のみは `/exit` or `←` |
| `/workflows` | 動作中 workflow の progress view (= 監視 / pause / resume / save)。dynamic-workflow の prompt trigger keyword は `ultracode` (旧 `workflow`、v2.1.158 で rename) [実機検証済: v2.1.193]、または `"run a workflow"` / `"workflow:"` 等の explicit phrase のみで発火 (= 単なる `workflow` 一語ではトリガしない、purple shimmer highlight) [未検証 v2.1.178] |
| `/loop [interval] [prompt]` [Skill] — alias `/proactive` | prompt を session 内で reactive 実行。interval 省略で self-pace、prompt 省略で `.claude/loop.md` or autonomous maintenance |
| `/schedule [description]` — alias `/routines` | routine 作成/更新/list/run。Anthropic 管理 cloud で実行 |
| `/teleport` — alias `/tp` | claude.ai/web session を端末に引き寄せ (= branch + 会話を fetch)。claude.ai サブスク必須 |
| `/autofix-pr [prompt]` | claude.ai/web cloud session 起動 → 現 branch PR を監視して CI 失敗 / reviewer comment に修正 push (= `gh pr view` で PR 自動検出、別 PR を見るなら先に checkout) |
| `/desktop` — alias `/app` | 現 session を Claude Code Desktop app で継続 (mac/win + サブスク) |
| `/remote-control` — alias `/rc` | この session を claude.ai 経由の remote control に晒す |

## クラウド / リサーチ / 計画

| command | 説明 |
|---|---|
| `/deep-research <question>` [Workflow] | web 検索 fan-out → cross-check → 引用付きレポート合成 |
| `/ultraplan <prompt>` | ultraplan session で plan 作成 → browser でレビュー → リモート実行 or 端末送り |
| `/ultrareview [PR]` <a id="ultrareview-related"></a> | cloud sandbox で multi-agent code review。優先呼出は `/code-review ultra` (これは alias 経路)。Pro/Max で 3 free run、以降 usage credits |
| `/claude-api [migrate\|managed-agents-onboard]` [Skill] | プロジェクト言語 (Py/TS/Java/Go/Ruby/C#/PHP/cURL) で API reference を load。`anthropic` / `@anthropic-ai/sdk` import で自動 activate。`migrate` で旧モデルから新モデルへの code 更新、`managed-agents-onboard` で Managed Agent 作成 walkthrough |
| `/dataviz [request]` [Skill] [min: 2.1.198] | チャート/ダッシュボードのデザイン指針。データに応じた chart form 選択・色の役割割当を行い、同梱 script で colorblind safety / contrast を検証。brand-neutral な placeholder palette を独自色へ差し替える前提 [実機検証済: v2.1.199] |

## チーム / 配布 / 紹介

| command | 説明 |
|---|---|
| `/team-onboarding` | 過去 30 日の使用履歴から onboarding guide を生成 (= markdown、新メンバが first message に貼る用)。claude.ai サブスク (Pro/Max/Team/Ent) は share link も返す |
| `/passes` | Claude Code の 1 週間無料パス共有 (= 対象アカウントのみ表示) |
| `/stickers` | Claude Code ステッカー注文 |
| `/feedback [report]` — alias `/bug` `/share` | フィードバック / バグ報告 / 会話共有 |

## 利用状況 / 課金

| command | 説明 |
|---|---|
| `/usage` — alias `/cost` `/stats` | session 課金 + plan 上限 + activity stats。Pro/Max/Team/Ent で skill/subagent/plugin/MCP 別 breakdown あり。`/stats` は Stats タブで開く |
| `/usage-credits` | usage credits 設定 (旧称 `/extra-usage`) |
| `/upgrade` | plan upgrade ページを開く (Pro/Max plan で表示) |
| `/privacy-settings` | privacy 設定 (Pro/Max のみ表示) |
| `/release-notes` | changelog を interactive picker で表示 |
| `/insights` | session 履歴を分析したレポート生成 (= プロジェクト領域 / 操作パターン / 摩擦点) |

## トラブル / 診断

| command | 説明 |
|---|---|
| `/doctor` | Claude Code installation + 設定の診断。`f` で claude に修正させる。CLI 等価: [`claude doctor`](cli.md#その他-subcommand) |
| `/heapdump` | JS heap snapshot + memory breakdown を `~/Desktop` (Linux で無ければ home) に書く |
| `/help` | help と利用可能コマンドの一覧表示 |

## 削除済 / 後継

| command | 説明 |
|---|---|
| `/pr-comments [PR]` [max: 2.1.90] | v2.1.91 で削除。代わりに直接 claude に「この PR の comment 見て」と頼む |
| `/vim` [max: 2.1.91] | v2.1.92 で削除。`/config` → Editor mode で切替 |
| `/agents` [max: 2.1.197] | v2.1.198 で subagent 設定 wizard を削除 [実機検証済: v2.1.199]。代わりに claude に subagent の作成/管理を頼むか `.claude/agents/` (project) / `~/.claude/agents/` (全 project) を直接編集。background agent 管理の [`claude agents`](cli.md#claude-agents-background-agents) CLI とは別物 |

## モバイル / その他

| command | 説明 |
|---|---|
| `/mobile` — alias `/ios` `/android` | iOS/Android アプリ DL の QR |
| `/chrome` | Claude in Chrome 設定 |
| `/ide` | IDE 連携管理 + 状態 |
| `/radio` | Claude FM lo-fi (Bedrock/Vertex/Foundry 不可) |
| `/powerup` | アニメ付きの機能チュートリアル |

## MCP prompts (動的)

MCP server が公開する prompt は **動的** に `/mcp__<server>__<prompt>` 形式で出現。詳細は [code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp) (公式)。本書では列挙不可 (= 接続 server 依存)。

## プロンプト prefix

| prefix | 説明 |
|---|---|
| `!<command>` | bash mode: 入力をシェル実行。v2.1.186 以降は実行後 Claude が結果に自動応答するのが既定 [spec]。従来の「context 投入のみ」挙動に戻すには `settings.json` の `"respondToBashCommands": false` [実機検証済: v2.1.193 で flag 認識を確認] |
| `#<text>` | memory mode: `CLAUDE.md` / auto-memory への追記 |
| `@<path>` | path mention: 当該ファイルを context に load |

## バイナリ実装との突合

[実機検証済: v2.1.177] `claude` バイナリ (`/Users/<user>/.local/share/claude/versions/2.1.177`) を `strings | grep 'name:"<cmd>"'` した結果 (= 内部登録の構造化テーブル):

```
agents background clear compact config context doctor exit export help
hooks ide init login logout mcp memory model permissions plugin
release-notes reload-plugins resume review skills status terminal-setup theme usage
```

(全 28 件)

公式 docs (上記) には載っていて strings に **出ない** ものは、別の登録経路 (= function-pointer 直接 / lazy-load module / alias-only 等) を取っている可能性が高い。差分があるからといって docs 側が誤りとは限らない (= strings は実装の一断面)。

突合の用途: `claude --version` 更新時に **`name:"<cmd>"` 抽出 → 前回 snapshot との diff → 新規追加 command の検出** ができる。`docs/runbooks/cc-version-maintenance.md` に手順候補:

```bash
CLAUDE_BIN=/Users/<user>/.local/share/claude/versions/<ver>
strings "$CLAUDE_BIN" 2>/dev/null \
  | grep -oE 'name:"(clear|compact|cost|config|plugin|plugins|agents|mcp|skill|skills|model|status|init|logout|login|review|memory|resume|background|reload-plugins|reload-skills|permissions|ide|approved-tools|export|terminal-setup|bug|doctor|help|hooks|migrate-installer|release-notes|allowed-tools|disallowed-tools|exit|vim|continue|undo|redo|context|usage|safe-mode|theme|verbose|todo|loop|fork|branch|cd|chrome|copy|debug|advisor|claude-api|simplify|workflow|workflows|run|verify|run-skill-generator|fewer-permission-prompts|focus|goal|heapdump|insights|rename|rewind|sandbox|schedule|scroll-speed|security-review|setup-bedrock|setup-vertex|share|fast|feedback|btw|color|recap|copy|stats|stickers|stop|tasks|team-onboarding|teleport|remote-env|remote-control|tui|ultraplan|ultrareview|upgrade|usage-credits|voice|web-setup|powerup|privacy-settings|radio|passes|mobile|ios|android|install-github-app|install-slack-app|keybindings|reset|new|app|desktop|allowed-tools|bg|continue|tp|reset|cost|stats|rc|allcompartments|automated-reasoning-policies)"' \
  | sort -u
```

(= `name:"`プレフィクスで abuser な false positive を抑制した allowlist 突合)

## 関連

- [cli.md](cli.md) — CLI フラグ / subcommand 全網羅 (`--disable-slash-commands` で全 skill を止める方法も)
- [commands.md](commands.md) — plugin が定義する custom slash command の書式 (`commands/*.md`)
- [skills.md](skills.md) — SKILL.md frontmatter / Skills as commands の機構 (公式 docs では「custom commands have been merged into skills」)
- [distribution.md](distribution.md) — bundled skills を別経路で disable する `disableBundledSkills` 設定

## 出典

- [Claude Code commands reference](https://code.claude.com/docs/en/commands) (= 本書の正本、公式 docs)
- [Claude Code skills (bundled)](https://code.claude.com/docs/en/skills#bundled-skills)
- [Claude Code workflows (bundled)](https://code.claude.com/docs/en/workflows#bundled-workflows)
- [Claude Code MCP prompts as commands](https://code.claude.com/docs/en/mcp#use-mcp-prompts-as-commands)

## 未検証 TODO

- [ ] 各 `[Skill]` ラベル command の実体 (= `~/.claude/<bundled>/skills/<name>/SKILL.md` 等) の所在地確認
- [ ] `/plan` の prompt 渡し有無で entry 動作差
- [ ] `/effort ultracode` 適用時の workflow auto-trigger の発火条件
- [ ] `/cd` の prompt cache 保持実態 (= 本当に system prompt 再構築しないか debug log で確認)
- [ ] `/reload-plugins --force` 必須となる「MCP tool 増減 + cache 失効」判定の境界
- [ ] `/remote-control` と `--remote-control` (CLI flag) の挙動差
- [ ] `/fork` と `/branch` の subagent 仕様差 (= [min: 2.1.161] 以降)
