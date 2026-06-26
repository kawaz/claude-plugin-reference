# SessionStart hook で AI を自走 trigger できるか検証

- 期間: 2026-06-26 (cc v2.1.193 実機)
- 発端: cmux-msg の SessionStart hook で「subscribe を Monitor で起動してください」と additionalContext 注入していても、kawaz の引数 prompt 無し起動では AI が何もしない (= 既知仕様確認の話) → そこから「async hook」UI 文言と未公開フィールド可能性の検証に派生
- 結果: hooks.md / cli.md に確定 12 件追記、release v0.2.24

## 主要発見 (= reference に反映済み)

### 1. AI 自走 trigger 経路は存在しない
6 mode 全 fail: `additionalContext` / 推測フィールド `injectAsUserPrompt` / `userMessage` / top-level `userPrompt` / `systemMessage` / async + 2 行目 `systemMessage`。引数 prompt (= ユーザ submit) が turn を回す前提が確定。

### 2. `systemMessage` は UI 通知専用 (新発見)
`SessionStart:<source> says: <text>` 形式で画面表示されるが、AI context には注入されない (= `additionalContext` と用途が違う)。`asyncSystemMessage` mode で 2 行目 `systemMessage` を出しても結果は同じ。

### 3. async hook 経路 (前ターン保留分も含む)
- 1 行目 `{"async": true, "asyncTimeout": <ms>}` で claude が hook を background 化、session 開始を待たない
- 完了時 UI に「`Async hook <hookName> completed`」(sync の「`<EventName>:<source> hook success:`」と別経路)
- 自動検出経路あり (= 1 行目 JSON が async response shape を持てば async 化、バイナリ `ome()` 判定)
- exit 後 stdout 2 行目以降を行ごとに JSON parse、最初の非 async 行を hook response として採用
- response value は bool/finite-number に限定 (公式 docs の「short strings 可」記述は誤り)
- canonical 実装: `claude-plugins-official/security-guidance/hooks/ensure_agent_sdk.py:722-740` の Anthropic 実装コメント

### 4. project-scope hook の配置正本
- 正本: `.claude/settings.json` の `hooks` field
- **`.claude/hooks.json` 単独は認識されない** (= 「hooks/hooks.json」は plugin 専用形式)
- `--settings <file>` の `hooks` field も load (= user-scope と additive merge)
- 複数 `--settings` は **last-wins** (= CC は最後の 1 個のみ、hook arrays の concat はしない)
- `$CLAUDE_PROJECT_DIR` は **cwd 起点で解決** (= `--settings file` 配置 dir でも `--add-dir` でもない、`--settings` 経由 hook の command path は絶対 path 推奨)
- workspace trust 未取得時: `permissions.allow` は ignored / `hooks` field は発火 (非対称)

### 5. CLI 周辺
- `claude` 引数なし = agents モード (= 入力で新規 session が bg 化)、通常 session には `--session-id <uuid>`
- `--safe-mode` は hook 含め全 customizations disable (= hook 検証 isolation には使えない)
- cmux-claude-wrapper のコメントが「v2.1.169 で first-wins → last-wins」と書いていたが v2.1.193 でも last-wins で変わらず (= kawaz の「cmux 記述は当時のスナップショットなので現バージョン確認すべき」指摘で実機再確認した結果)

## 検証の途中で踏んだ誤り (= 同じ誤りを次回踏まないための記録)

### `.claude/hooks.json` 単独ファイル
最初に検証 hook を `.claude/hooks.json` に書いた → kawaz interactive 検証で XPRB token が AI 応答に出ない → 「project scope の hook は `.claude/settings.json` の `hooks` field が正本」と気づいて修正 → 動作確認。`hooks.json` は plugin 専用形式 (= plugin root 直下の `hooks/hooks.json`) で、project scope では認識されないことが root cause。reference 表は元々正しく記載していたが、誤読していた。

### `--safe-mode` で hook 検証 isolation を試行
個人 plugin (cmux-msg / security-guidance 等) の SessionStart hook 干渉を避けるため `--safe-mode` で起動しようとしたが、起動 UI に「`Safe mode: all customizations are disabled (..., hooks, ...)`」と明示されていた。**hook も含めて全 customizations disable** = 検証対象 hook 自体が動かないので isolation 手段にならない。

### `--settings <file>` 経由 hook の silent fail
最初は「`--settings` で渡した settings.json の `hooks` field は load されない」と誤判定。実際は load されていたが、私が hook command に `$CLAUDE_PROJECT_DIR/.claude/hooks/probe.sh` と書いており `$CLAUDE_PROJECT_DIR` は **cwd 起点**で解決 → 別 cwd で起動すると `probe.sh` が見つからず silent fail。**絶対 path で書き直し → 発火確認**で訂正。kawaz の「cmux-claude-wrapper を見てみて」指摘がこの誤判定の修正に直接効いた。

### `--bare` で個人 plugin 排除
個人 plugin 干渉を避けるため `--bare` も試したが、`--bare` は **認証情報も読まない** (= `Not logged in · Please run /login`)。temp dir + tty 検証では使えない。

## 検証ハーネスの再利用パターン

将来の hook 検証で再利用できる雛形を `/private/tmp/cc-prompt-trigger-probe/` に置いていたが cleanup 済み。再現したい場合の構成メモ:

- temp project 直下に `.claude/settings.json` (= hooks field 含む)
- hook script は `.claude/hooks/probe.sh` で **side effect file** (= `/tmp/cc-probe-fired` に append) + stdout に切替可能な JSON output (env で mode 選択)
- probe.sh の `command` path は **絶対 path** で書く (= `$CLAUDE_PROJECT_DIR` を使わない)
- workspace trust は `~/.claude*/.claude.json` の `projects.<path>.hasTrustDialogAccepted: true` で事前付与 (= interactive 起動で trust dialog を出さない)
- 個人 plugin の SessionStart hook (= cmux-msg / security-guidance / claude-plugin-reference 等) は **並行発火する**ことを前提に、検証 token は unique 文字列 (= `XPRB-AC-7f2k9q3m` のような偶然衝突しない値) で区別
- 引数 prompt 無し起動には `--session-id "$(uuidgen | tr A-Z a-z)"` が必要 (= 引数なしだと agents モード起動でセッションが bg 化する)
- kawaz の手動検証は tmux で複数 pane に分けて並列実行可 (= 6 mode 同時に画面で観察)

## 次回担当への引き継ぎ

- runbook (`docs/runbooks/cc-version-maintenance.md`) は今回触っていない。今回の検証は cc バージョン追従のメンテパスとは別経路 (= 既存挙動の確定検証)
- `Tool(param:value)` 罠 (= 前 release で hooks.md §3 末尾に追記済) と同じく、`systemMessage` の UI 通知専用挙動 / `--settings` last-wins / `$CLAUDE_PROJECT_DIR` の cwd 解決は plugin 開発者がハマる罠の代表例として hooks.md 検索性を意識した節立てにした
- `injectAsUserPrompt` / `userMessage` / top-level `userPrompt` は確定で「存在しないフィールド」なので、将来追加されるなら CHANGELOG 監視で気づく想定

## 関連

- workflow / 関連 PR: なし (= 直接編集で完結)
- runbook: 触らず
- previous release: v0.2.23 (= cc v2.1.177 → v2.1.193 メンテパス、`docs/journal/2026-06-26-cc-v2.1.193-maintenance.md`)
- 検証で参照した plugin: `claude-plugins-official/security-guidance/2.0.6/hooks/ensure_agent_sdk.py` / `cmux-msg/0.30.13/src/hooks/session-start.ts` / `/Applications/cmux.app/Contents/Resources/bin/cmux-claude-wrapper`
