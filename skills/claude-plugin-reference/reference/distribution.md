# 配布編 — plugin.json / marketplace.json / 配布フロー

## マニフェストファイルの作成
plugin を配布するにはリポジトリ内の以下の2つのパスにマニフェストファイルを配置する。

- [.claude-plugin/marketplace.json](../../../.claude-plugin/marketplace.json)
- [.claude-plugin/plugin.json](../../../.claude-plugin/plugin.json)

このプラグインのマニフェストファイルが最小テンプレとして使えます。
触るのは `name` / `description` / `version` / `repository` の 4 field。残り固定でOK。

## README に install/update　手順を記載

```
# インストール手順
claude plugin marketplace add <user>/<repo>
claude plugin install <plugin-name>@<marketplace-name>
```

```
# アップデート手順
claude plugin marketplace update <marketplace-name>
claude plugin update <plugin-name>@<marketplace-name>
```

実例サンプル: [README.md](../../../README.md)

## version 管理ワークフロー (justfile, jj/git 両対応) [実機検証済]

実際にこのリポで動かしている justfile。`jj/git push` 直叩きは push-guard hook が block するので、
品質ゲートを通すこの task 経由で push する。`<plugin-name>` / `<marketplace-name>` は自分のに置換。

```justfile
# jj/git 判定
is-jj := path_exists('.jj')
is-git := if is-jj == "true" { "false" } else { path_exists('.git') }

# bump trigger 対象 = plugin の配布物 (md が本体なので skills/ も含める。docs/ 等の開発メタは対象外)
bump-trigger-paths := "skills/ README.md"
# version を持つ manifest (bump-semver の対象)
version-files := ".claude-plugin/plugin.json .claude-plugin/marketplace.json"

push: ensure-clean check-version-bumped
    jj bookmark set main -r @-
    jj git push --bookmark main --allow-new
    # push 成功後はローカル環境も更新
    claude plugin marketplace update <marketplace-name>
    claude plugin update <plugin-name>@<marketplace-name>

# version bump 専用の Release commit を作る (push は別途 `just push`)
bump-version bump="patch": ensure-clean
    new_version=$(bump-semver {{ bump }} {{ version-files }} --write --no-hint) && jj commit -m "Release v${new_version}"

version:
    @bump-semver get {{ version-files }} --no-hint

validate:
    claude plugin validate .

# --- internal recipes (push の依存) ---

# uncommitted change がない (= @ が empty change) ことを要求
ensure-clean:
    if {{ is-jj }}; then [ "$(jj log -r @ --no-graph -T 'empty')" = "true" ]; fi
    if {{ is-git }}; then [ -z "$(git status --porcelain)" ]; fi

# bump-trigger-paths に変更があるのに version 据え置きの事故を防ぐ
# bump-semver vcs diff -q で jj/git 分岐を統一 (DR-0020, v0.20.0+)
check-version-bumped:
    #!/usr/bin/env bash
    set -euo pipefail
    # exit 0 = 変更なし → bump 不要 / 1 = 変更あり / 3 = VCS error
    rc=0
    bump-semver vcs diff -q main@origin -- {{ bump-trigger-paths }} || rc=$?
    case "$rc" in
      0) exit 0 ;;
      1) ;;
      *) echo "ERROR: bump-semver vcs diff failed (rc=$rc). main@origin 未 track? 先に 'jj git fetch' / 'git fetch'" >&2; exit 1 ;;
    esac
    bump-semver compare gt .claude-plugin/plugin.json vcs:main@origin:.claude-plugin/plugin.json --no-hint && exit 0
    echo 'ERROR: 配布物が変わってるが version 未 bump。"just bump-version" を実行' >&2
    exit 1
```

### 運用フロー [実機検証済]

1. **内容を commit** (version 据え置き): `jj commit -m "..."`
2. **`just bump-version`** — `ensure-clean` (@ が empty) を確認 → version を `--write` で上げ、`Release vX.Y.Z` commit を独立で作る
3. **`just push`** — `ensure-clean` + `check-version-bumped` を通過 → `main` bookmark を `@-` (= Release commit) に set → push → ローカルの marketplace/plugin も更新

ポイント:

- **Release commit を内容 commit と分離**: `bump-version` が version-files だけの commit を独立で作る。`push` が `main` を `@-` に置くので、内容 commit も祖先として一緒に push される。
- **`ensure-clean` が @ empty を要求**: jj は working copy が自動 commit 化されるため、未コミット変更の有無を「@ が empty change か」で判定する。
- **`check-version-bumped`**: `bump-trigger-paths` (= 配布物) が `main@origin` から変わっているのに version が上がっていなければ fail。`docs/` 等の開発メタだけの変更では bump 不要。`bump-semver vcs diff -q` で jj/git 両対応 (DR-0020)、`--quiet` の exit code (0=変更なし / 1=変更あり / 3=VCS error) を case で分岐。
- 既存セッションへの反映は `/reload-plugins` をユーザに依頼する (marketplace/plugin update はキャッシュ更新まで)。

## version 管理

- plugin.json に `version` 設定済 → その文字列に pin、ユーザは version 変更時のみ更新通知 [spec]
- 未設定 → git commit SHA fallback (= 毎 commit が新 version 扱い) [spec]

## 参考 URL (出典)

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins.md)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces.md)
- [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins.md)
