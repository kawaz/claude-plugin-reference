---
name: claude-plugin-reference
description: Claude Code の plugin / skills / hooks / commands / agents / marketplace / CLI / 組み込み slash command の実機検証済みリファレンス (field-verified reference)。SKILL.md frontmatter fields, hook events & JSON I/O schemas, matcher syntax, string substitution (${CLAUDE_PLUGIN_ROOT} 等), plugin.json / marketplace.json, 配布フロー / version bump, `claude` CLI 全 option / subcommand / `--print` モード / `--safe-mode` vs `--bare` / `--json-schema` 出力構造, 組み込み slash command 全網羅 (= `/clear` `/compact` `/plugin` `/code-review` `/fork` 等の bundled command + skill + workflow) を扱う。plugin 開発・hook 作成・skill 定義・CLI 使い方・組み込み command 確認の際に必ず参照する。
---

> **最終検証: Claude Code v2.1.177 (2026-06-13)**
>
> このスタンプは「このバージョンまでの公式 changelog 差分を消化済み」の意であり、全項目をこのバージョンで再観測したという意味ではない。各項目の実測バージョンは個別ラベル (例 `[実機検証済: v2.1.170]`) が正。

`${CLAUDE_SKILL_DIR}/reference/` 配下のうち、**必要なトピックのファイルのみ Read** してください (context 最小化のための二段構成)。

- [distribution.md](reference/distribution.md) — 配布編 (plugin.json / marketplace.json / 配布フロー / version bump)
- [hooks.md](reference/hooks.md) — フック編 (全 hook event / matcher / JSON input/output schema / blockable / 強制力)
- [skills.md](reference/skills.md) — スキル編 (SKILL.md frontmatter / string substitution / Dynamic Context Injection / invocation 制御)
- [commands.md](reference/commands.md) — コマンド編 (`commands/*.md` の役割 / 書式テンプレ / skills との使い分け / 3 軸構造)
- [agents.md](reference/agents.md) — エージェント編 (plugin の agents field / agent frontmatter / 名前空間 / スコープ / 起動方法 / plugin agent の制限)
- [cli.md](reference/cli.md) — CLI 編 (`claude` の全 option / `--print` 依存マトリクス / `--output-format=json` 構造 / `--json-schema` 出力先 / `--safe-mode` vs `--bare` / 全 subcommand)
- [builtin-slash-commands.md](reference/builtin-slash-commands.md) — 組み込み slash command 編 (対話 UI の `/<name>` 全 ~100 件 / bundled skill / workflow / alias / 削除済 + バイナリ実装との突合)

各ファイルは `[spec] / [実機検証済] / [未検証] / [実装の副産物]` のラベルで確証範囲を区別。`[未検証]` 項目は TODO、検証したら格上げ。**検証済み項目には可能な限り確認した Claude Code バージョンを併記する** (例: `[実機検証済: v2.1.170]`)。

## メンテナンス責務 (鮮度の維持)

このリファレンスの価値は **「常に最新 Claude Code で検証済み」** であること。invoke 時に必ず以下を確認する:

1. `claude --version` で現行バージョンを取得し、冒頭の **最終検証** バージョンと比較する。
2. **現行 > 最終検証** なら、ドキュメントが陳腐化している可能性をユーザに **簡潔に告知** する (= 勝手に重い再監査を始めて作業を脱線させない)。
   例: 「本 reference の最終検証は v2.1.170、現行は vX.Y.Z。差分チェックのメンテナンスパスを実施しますか?」
3. **ユーザがメンテナンスを承認 / 明示的にメンテ目的で invoke した場合のみ**、以下を実施:
   - 末尾の出典 URL (plugins / hooks / skills / sub-agents の公式 docs) を**再取得**し、最終検証バージョン以降の **差分** を洗う。
   - 変わった挙動・新 event / 新 field / 新 frontmatter を **実機で検証**し、該当 reference ファイルを更新。検証した項目には `[実機検証済: vX.Y.Z]` を付与。
   - `[未検証]` TODO のうち現行で検証可能になったものを格上げ。
   - 冒頭の **最終検証** スタンプを現行バージョン + 当日日付に更新。
   - 手順詳細 (issue 起票テンプレ / 検証ハーネス定型 / ハマり所) はリポ内 `docs/runbooks/cc-version-maintenance.md` を参照 (リポ checkout 内でのメンテ時のみ到達可)。
4. 単に plugin 開発で参照しているだけ (= メンテ目的でない) なら、**告知のみ**で通常作業を続ける。
