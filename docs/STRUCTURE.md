# リポジトリ物理構造

```
claude-plugin-reference/
  README.md / README-ja.md        ユーザ向けエントリ (日本語原本 + 英訳)
  LICENSE                          MIT License (kawaz リポジトリ規約)
  justfile                         task runner (canonical)
  .claude-plugin/
    plugin.json                    plugin マニフェスト
    marketplace.json               marketplace 宣言 (自己 publish)
  skills/
    claude-plugin-reference/
      SKILL.md                     skill 目次 (invocation 時 AI 流入)
      reference/                   関心別 reference (on-demand 読込)
        distribution.md
        hooks.md
        skills.md
        commands.md
        agents.md
  hooks/
    hooks.json                     SessionStart 登録
    plugin-repo-nudge.sh           判定 + additionalContext inject
  docs/                            設計・運用・履歴 (docs-structure skill 参照)
    DESIGN-ja.md / DESIGN.md       現実装の説明 (日英ペア)
    STRUCTURE.md                   本ファイル (物理構造)
    issue/                         自リポ TODO / 受付窓口
                                     YYYY-MM-DD-<slug>.md
    decisions/                     (将来) DR が増えたら新設
    journal/                       (任意) 日々の生記録
    findings/                      (任意) 単発調査の確定事実
    runbooks/                      (任意) 運用・復旧手順
```

## task runner (justfile)

canonical 実装は kawaz/bump-semver の justfile。本リポでは以下 recipe を提供:

| recipe | 役割 |
|---|---|
| `push` | 全 gate 通過後に `bump-semver vcs push` + `on-success-release` |
| `bump-version [level]` | `.claude-plugin/plugin.json` と `marketplace.json` の version を更新 + Release commit |
| `version` | 現在の version 表示 |
| `validate` | `claude plugin validate .` 実行 |
| `ensure-clean` | working tree が clean か検証 |
| `check-versions` | plugin.json と marketplace.json の version 整合 |
| `check-version-bumped` | trigger paths (`skills/` `README*.md` `hooks/`) 変更時に bump 必須 |
| `check-outdated-translations` | `*-ja.md` 正本 > `*.md` 翻訳の lag を検出 |
| `on-success-release` | marketplace + plugin を update |

push の deps 順序:

```
push: ensure-clean validate check-versions check-version-bumped check-outdated-translations
```

## 配布フロー

1. ローカルで実装 + コミット
2. trigger paths を変更したら `just bump-version` で `.claude-plugin/plugin.json` `marketplace.json` を bump + Release commit
3. `just push` で gate 通過 → bump-semver が main に push
4. `on-success-release` で marketplace cache を更新 + plugin を local で auto-update
5. (CI/CD で release artifact を作る workflow は持たない。push = リリース完了)

## bump-trigger paths

`hooks/`、`skills/`、`README*.md` を bump trigger に指定。これらが変更された push は version 進行が必須。docs / justfile 等の変更だけなら bump 不要。

## 翻訳ペア

| 正本 (ja) | 翻訳 (en) |
|---|---|
| `README-ja.md` | `README.md` |
| `docs/DESIGN-ja.md` | `docs/DESIGN.md` |

`check-outdated-translations` recipe が `bump-semver vcs outdated 'glob:**/*-ja.md' '$1/$2.md'` で commit-lag を検出する。

## 関連

- [docs/DESIGN-ja.md](./DESIGN-ja.md) — 現実装の説明
- [README-ja.md](../README-ja.md) — ユーザ向け概要
