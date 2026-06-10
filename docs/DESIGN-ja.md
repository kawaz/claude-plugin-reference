# claude-plugin-reference 設計

> [English](./DESIGN.md) | 日本語

## ドメイン

Claude Code の plugin 開発で「公式 docs だけだと挙動が読み取れない」「毎 plugin で同じ説明を繰り返す」という課題に対して、**実機検証で確証取った一次情報を集約**するリファレンス。

対象読者は AI agent (Claude Code 自身) と人間の両方。SKILL を 1 本提供し、AI invocation 時に目次が context へ流入する。

## アーキテクチャ

### 全体構成

```
claude-plugin-reference (plugin)
├── skills/claude-plugin-reference/   # 単一 skill: 目次 + on-demand reference
│   ├── SKILL.md                       # 目次のみ。invocation 時に AI 流入
│   └── reference/                     # 関心別の詳細 (on-demand 読込)
│       ├── distribution.md
│       ├── hooks.md
│       ├── skills.md
│       ├── commands.md
│       └── agents.md
└── hooks/                             # SessionStart nudge
    ├── hooks.json
    └── plugin-repo-nudge.sh
```

### skill: 目次 + on-demand reference の二段構成

SKILL.md は **目次のみ** に絞り、AI 流入する常時 context を最小化する。AI が特定トピックを読みたくなったら `reference/<topic>.md` を Read で開く形。これにより:

- skill invocation のコストを軽くできる (= AI が「ちょっと参照したい」気軽さで使える)
- トピック追加時の影響を局所化 (= 既存 reference を触らずに新ファイルを足せる)

### hook: SessionStart nudge

`SessionStart` で `additionalContext` を 1 文 inject する。判定は **OR**:

1. `.claude-plugin/plugin.json` 保有 (= plugin リポ作業中)
2. `CLAUDE_PROJECT_DIR` のパス要素に `claude-rules-*` を含む (= rule overlay リポ作業中、リポルート直下でも発火)
3. `CLAUDE_PROJECT_DIR` のパス要素が `.claude` または `.claude-*` で始まる (= Claude 設定ディレクトリを直接触っている、例 `~/.claude-personal`)

判定はパス要素境界で行う (= `$root` の末尾に `/` を足して `*/<elem>/*` でマッチ)。これにより `.claudexyz` のような dash なし接尾の無関係ディレクトリには誤発火せず、`claude-rules-personal` をリポルートで直接指す場合も発火する。

`hooks.json` の matcher は空文字 (`""`) = SessionStart の全 source (startup / resume / clear / compact) で発火する意図。

該当しないセッションでは沈黙 (= plugin hook は enable 中の全セッションで発火するため、ノイズを出さない設計)。

### 配布フロー

`bump-semver` + `justfile` で **push に gate を集約**する設計:

- `just push` を入口とする (= 直 `jj git push` は push-guard hook で block)
- gate: `ensure-clean` → `validate` → `check-versions` (multi-file 整合) → `check-version-bumped` (trigger paths 変更時に bump 必須) → `check-outdated-translations` (翻訳 lag 検出)
- push 成功後に `on-success-release` で marketplace / plugin を自動 update

詳細は [STRUCTURE.md](./STRUCTURE.md) と `justfile`。

## 主要な設計判断

DR は現時点ゼロ (= 構造がまだシンプル)。判断が複数化したら `docs/decisions/DR-NNNN-*.md` に切り出して INDEX.md で管理する。

## 関連ドキュメント

- [STRUCTURE.md](./STRUCTURE.md) — 物理構造
- [README-ja.md](../README-ja.md) — ユーザ向け概要 / インストール
