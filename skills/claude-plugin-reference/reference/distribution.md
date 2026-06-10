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
品質ゲートを通すこの task 経由で push する。`claude-plugin-reference` の箇所は自分の plugin 名 / marketplace 名に置換。

設計方針 (kawaz/* plugin リポ共通):

- **jj/git 分岐は `bump-semver vcs` サブコマンドに委譲** (DR-0020)。`vcs push` / `vcs is clean` /
  `vcs commit` / `vcs diff` が VCS を自動判定するので、`is-jj` / `is-git` の手書き分岐や
  `jj bookmark set` の手打ちは持たない。
- **just 変数 (`name := value`) は使わない**。固定パスリストでも positional / dependency 引数渡しか
  リテラル直書きにする。理由は quote 安全性だけでなく、**全 plugin リポで justfile が同形に揃い、
  読み手が迷わず差分も減る (省コンテキスト)** こと。`personal-docs-structure` skill の「task runner」節に準拠。
- **bump-trigger は配布物のみ**。skill plugin は `skills/ README.md`、hook のみの plugin (例: push-guard)
  は `hooks/`。`docs/` 等の開発メタや `justfile` 自体は trigger 外 (= それらだけの変更では version bump 不要)。

```justfile
# ---------- settings ----------

set positional-arguments

# ---------- main tasks ----------

# push (バージョン bump 済みを前提、全 gate 通過後に push してローカルも更新)
push: ensure-clean validate check-versions check-version-bumped
    bump-semver vcs push --branch main --jj-bookmark-auto-advance
    @just _local-plugin-reload

# version を bump して Release commit を作成 (push は別途 `just push`)
[script]
bump-version bump="patch": ensure-clean
    new_version=$(bump-semver "$1" .claude-plugin/plugin.json .claude-plugin/marketplace.json --write --no-hint)
    bump-semver vcs commit -m "Release v${new_version}" .claude-plugin/plugin.json .claude-plugin/marketplace.json

# 現在の version を確認
version:
    @bump-semver get .claude-plugin/plugin.json .claude-plugin/marketplace.json --no-hint

# plugin spec を validate
validate:
    claude plugin validate .

# ---------- internal recipes (push の依存) ----------

# uncommitted change がない状態か確認 (git/jj-agnostic, DR-0020)
ensure-clean:
    bump-semver vcs is clean

# plugin.json と marketplace.json の version 一致を保証 (multi-file 整合性)
[private]
check-versions:
    @bump-semver get .claude-plugin/plugin.json .claude-plugin/marketplace.json --no-hint >/dev/null

# push 成功直後の local 反映 (CI 無しリポの canonical: push task に embed して仕組みで強制)
[private]
_local-plugin-reload:
    claude plugin marketplace update claude-plugin-reference
    claude plugin update claude-plugin-reference@claude-plugin-reference
    @echo "[hint] /reload-plugins to apply in this session without restart"

# bump-trigger (skills/ README.md) 変更時に version bump 済か検証 (変更なしならスキップ)
check-version-bumped: (_check-version-bumped "skills/" "README.md")

# trigger paths の diff があれば version が main@origin より上がっているか検証
# exit 0=変更なし / 1=変更あり / 3=VCS error を case で区別、`|| rc=$?` で set -e 回避
[private]
[script]
_check-version-bumped *target_paths:
    rc=0
    bump-semver vcs diff -q main@origin -- "$@" || rc=$?
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
2. **`just bump-version`** — `ensure-clean` を確認 → version を `--write` で上げ、`Release vX.Y.Z` commit を独立で作る
3. **`just push`** — gate を通過 → `bump-semver vcs push --jj-bookmark-auto-advance` が `main` を進めて push → `_local-plugin-reload` が marketplace/plugin を update

ポイント:

- **Release commit を内容 commit と分離**: `bump-version` が version-files だけの commit を独立で作る。内容 commit も祖先として一緒に push される。
- **bookmark 前進は `bump-semver vcs push --jj-bookmark-auto-advance` に委譲** (DR-0026): jj の `@-` (= 直近の Release commit) に `main` を自動追従させる。手書きの `jj bookmark set main -r @-` は不要。
- **`ensure-clean` が @ empty を要求**: jj は working copy が自動 commit 化されるため、`bump-semver vcs is clean` が「@ が empty change か」で判定する。
- **`check-version-bumped`**: 配布物 (= bump-trigger) が `main@origin` から変わっているのに version が上がっていなければ fail。`docs/` / `justfile` 等だけの変更では bump 不要。
- **local 反映を push に embed**: push して終わりだと現セッションの Claude は古い plugin cache で動き続ける。`_local-plugin-reload` を push task に組み込んで「仕組みで強制」する。既存セッションへの適用は `/reload-plugins` をユーザに依頼 (update はキャッシュ更新まで)。

#### CI があるリポの場合 (= push 直後に update できない)

`.github/workflows/` で tag/release を作るリポ (バイナリ配布等) は、push 直後に update すると CI が
artifact を作る前なので早すぎる。その場合は push に inline せず `on-success-release` recipe を分離し、
`gh-monitor:watch-workflow` の `--on-success <workflow> 'just on-success-release'` で **CI green 後に**
update を発火させる。

この「push → watch → CI green → on-success-release」パターンの**大元は kawaz/bump-semver の justfile**
(`push` が watch-workflow ヒントを echo → `on-success-release` で `brew upgrade`)。kawaz/claude-gh-monitor は
これを plugin の `claude plugin update` に適用した例 (やっていることは同じ)。

| リポ種別 | local 反映の置き場所 | 発火タイミング |
|---|---|---|
| CI 無し (hook / skill のみ) | push recipe に inline (`_local-plugin-reload`) | push 直後 |
| CI あり (release.yml で artifact) | `on-success-release` 別 recipe | `watch-workflow --on-success` 経由、CI green 後 |

実装例: **kawaz/bump-semver** (大元、`brew upgrade`) / **kawaz/claude-gh-monitor** (plugin update 適用)。

## version 管理

- plugin.json に `version` 設定済 → その文字列に pin、ユーザは version 変更時のみ更新通知 [spec]
- 未設定 → git commit SHA fallback (= 毎 commit が新 version 扱い) [spec]

## 参考 URL (出典)

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins.md)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces.md)
- [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins.md)
