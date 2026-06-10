# 配布編 — plugin.json / marketplace.json / 配布フロー

## マニフェストファイルの作成
plugin を配布するにはリポジトリ内の以下の2つのパスにマニフェストファイルを配置する。

- [.claude-plugin/marketplace.json](../../../.claude-plugin/marketplace.json)
- [.claude-plugin/plugin.json](../../../.claude-plugin/plugin.json)

このプラグインのマニフェストファイルが最小テンプレとして使えます。
触るのは `name` / `description` / `version` / `repository` の 4 field。残り固定でOK。

## README に install/update 手順を記載

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

実際にこのリポで動かしている justfile (= 実体との一致を `check-embedded-justfile-sync` gate が push 時に機械検証するので、このコードブロックは drift しない)。`jj/git push` 直叩きは push-guard hook が block するので、品質ゲートを通すこの task 経由で push する。

自分の plugin に流用するときは: `claude-plugin-reference` の箇所を自分の plugin 名 / marketplace 名に置換。本リポ固有の gate (`check-outdated-translations` = ja/en 翻訳ペア運用、`check-freshness` = リファレンス鮮度、`check-embedded-justfile-sync` = 本ファイルとの同期、`test` = tests/ 保有リポのみ) は自リポの構成に合わせて取捨選択する。

設計方針 (kawaz/* plugin リポ共通):

- **jj/git 分岐は `bump-semver vcs` サブコマンドに委譲** (DR-0020)。`vcs push` / `vcs is clean` /
  `vcs commit` / `vcs diff` が VCS を自動判定するので、`is-jj` / `is-git` の手書き分岐や
  `jj bookmark set` の手打ちは持たない。
- **just 変数 (`name := value`) は使わない**。固定パスリストでも positional / dependency 引数渡しか
  リテラル直書きにする。理由は quote 安全性だけでなく、**全 plugin リポで justfile が同形に揃い、
  読み手が迷わず差分も減る (省コンテキスト)** こと。`personal-docs-structure` skill の「task runner」節に準拠。
- **bump-trigger は配布物のみ**。skill のみの plugin は `skills/ README*.md`、hook のみの plugin (例: push-guard)
  は `hooks/`、skill + hook 両方持つ本リポは `skills/ README.md README-ja.md hooks/` の 4 つ。
  `docs/` 等の開発メタや `justfile` 自体は trigger 外 (= それらだけの変更では version bump 不要)。

```justfile
# claude-plugin-reference push / bump-version / validate
# (push-guard hook 経由でこの task を使うことで、直叩き block を回避)

# ---------- settings ----------

set positional-arguments

# ---------- main tasks ----------

# push (バージョン bump 済みを前提、全 gate 通過後に push してローカルも更新)
push: ensure-clean validate test check-versions check-version-bumped check-outdated-translations check-embedded-justfile-sync
    bump-semver vcs push --branch main --jj-bookmark-auto-advance
    just on-success-release

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

# tests/ 配下のテストを実行 (1 つでも fail したら exit 非 0)
test:
    @for f in tests/*.test.sh; do bash "$f" || exit 1; done

# ---------- internal recipes (push の依存) ----------

# uncommitted change がない状態か確認 (git/jj-agnostic, DR-0020)
ensure-clean:
    bump-semver vcs is clean

# plugin.json と marketplace.json の version 一致を保証 (multi-file 整合性)。
# bump-semver get は multi-file 時に内部で整合チェック (不一致は error 表示で exit 非 0)。
[private]
check-versions:
    @bump-semver get .claude-plugin/plugin.json .claude-plugin/marketplace.json --no-hint >/dev/null

# release 成功後の local 反映: marketplace + plugin を update (CI 無しは push から直接 / CI ありは watch 経由)
on-success-release:
    claude plugin marketplace update claude-plugin-reference
    claude plugin update claude-plugin-reference@claude-plugin-reference
    @echo ""
    @echo "[hint] /reload-plugins to apply in this session without restart"

# bump-trigger (skills/ README*.md hooks/) 変更時に version bump 済か検証 (変更なしならスキップ)
check-version-bumped: (_check-version-bumped "skills/" "README.md" "README-ja.md" "hooks/")

# 翻訳ペア (*-ja.md = 正本、*.md = 英訳) の commit-lag を検出 (= 正本 > 翻訳の場合エラー)。
# 詳細は docs-structure skill / kawaz/bump-semver の justfile を参照。
check-outdated-translations: ensure-clean
    bump-semver vcs outdated 'glob:**/*-ja.md' '$1/$2.md'

# trigger paths の diff があれば version が main@origin より上がっているか検証。
# bump-semver vcs diff -q で jj/git 分岐を統一 (DR-0020, v0.20.0+)。
# exit 0=変更なし / 1=変更あり / 3=VCS error を case で区別、`|| rc=$?` で set -e 回避。
[private]
[script]
_check-version-bumped *target_paths:
    rc=0
    bump-semver vcs diff -q main@origin -- "$@" || rc=$?
    case "$rc" in
      0) exit 0 ;;
      1) ;;
      *) echo "ERROR: bump-semver vcs diff failed (rc=$rc). main@origin が track されていない可能性。先に 'jj git fetch' / 'git fetch' を試してください" >&2; exit 1 ;;
    esac
    bump-semver compare gt .claude-plugin/plugin.json vcs:main@origin:.claude-plugin/plugin.json --no-hint && exit 0
    echo 'ERROR: bump-trigger が変わってるが version 未 bump。"just bump-version" を実行してください' >&2
    exit 1

# distribution.md の埋め込み justfile が実体と一致するか検証 (= 「実際に動かしている justfile」の看板を仕組みで保証)。
# 不一致なら diff を表示して fail。同期は reference/distribution.md の ```justfile ブロックを実体で置き換える。
[private]
[script]
check-embedded-justfile-sync:
    doc=skills/claude-plugin-reference/reference/distribution.md
    embedded=$(awk '/^```justfile$/{f=1;next} /^```$/{f=0} f' "$doc")
    if [ "$embedded" != "$(cat justfile)" ]; then
      echo "ERROR: $doc の埋め込み justfile が実体と不一致。実体の内容でコードブロックを更新してください" >&2
      diff <(printf '%s\n' "$embedded") justfile >&2 || true
      exit 1
    fi

# ---------- reference freshness ----------

# SKILL.md の最終検証スタンプと claude --version を semver 比較し、陳腐化を検出する。
# 現行 = スタンプ → fresh (exit 0) / 現行 > スタンプ → stale (exit 1) /
# 現行 < スタンプ → fresh 扱い (= 現行側が古いだけ、メンテ不要。exit 0)。
# push の deps には含めない (= 任意実行)。
[script]
check-freshness:
    current=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    stamped=$(grep -oE 'Claude Code v[0-9]+\.[0-9]+\.[0-9]+' skills/claude-plugin-reference/SKILL.md | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    if [ -z "$current" ]; then
      echo "ERROR: claude --version の取得に失敗しました" >&2
      exit 1
    fi
    if [ -z "$stamped" ]; then
      echo "ERROR: SKILL.md の最終検証スタンプが見つかりません" >&2
      exit 1
    fi
    if [ "$current" = "$stamped" ]; then
      echo "fresh: v${current}"
      exit 0
    fi
    rc=0
    bump-semver compare gt "$current" "$stamped" -qq || rc=$?
    case "$rc" in
      0)
        echo "stale: SKILL.md の最終検証 v${stamped} / 現行 claude v${current}"
        echo "メンテパス実施を検討してください: docs/runbooks/cc-version-maintenance.md"
        exit 1 ;;
      1)
        echo "fresh: SKILL.md の最終検証 v${stamped} (現行 claude v${current} の方が古い環境)" ;;
      *)
        echo "ERROR: bump-semver compare failed (rc=$rc)" >&2
        exit 1 ;;
    esac
```

### 運用フロー [実機検証済]

1. **内容を commit** (version 据え置き): `jj commit -m "..."`
2. **`just bump-version`** — `ensure-clean` を確認 → version を `--write` で上げ、`Release vX.Y.Z` commit を独立で作る
3. **`just push`** — gate を通過 → `bump-semver vcs push --jj-bookmark-auto-advance` が `main` を進めて push → `on-success-release` が marketplace/plugin を update

ポイント:

- **Release commit を内容 commit と分離**: `bump-version` が version-files だけの commit を独立で作る。内容 commit も祖先として一緒に push される。
- **bookmark 前進は `bump-semver vcs push --jj-bookmark-auto-advance` に委譲** (DR-0026): jj の `@-` (= 直近の Release commit) に `main` を自動追従させる。手書きの `jj bookmark set main -r @-` は不要。
- **`ensure-clean` が @ empty を要求**: jj は working copy が自動 commit 化されるため、`bump-semver vcs is clean` が「@ が empty change か」で判定する。
- **`check-version-bumped`**: 配布物 (= bump-trigger) が `main@origin` から変わっているのに version が上がっていなければ fail。`docs/` / `justfile` 等だけの変更では bump 不要。
- **local 反映を push から呼ぶ**: push して終わりだと現セッションの Claude は古い plugin cache で動き続ける。`on-success-release` を push から呼んで「仕組みで強制」する (CI 無しリポは push 完了 = release 成功なので即実行)。既存セッションへの適用は `/reload-plugins` をユーザに依頼 (update はキャッシュ更新まで)。

#### CI があるリポの場合 (= push 直後に update できない)

`.github/workflows/` で tag/release を作るリポ (バイナリ配布等) は、push 直後に update すると CI が
artifact を作る前なので早すぎる。その場合は push に inline せず `on-success-release` recipe を分離し、
`gh-monitor:watch-workflow` の `--on-success <workflow> 'just on-success-release'` で **CI green 後に**
update を発火させる。

この「push → watch → CI green → on-success-release」パターンの**参考実装は kawaz/bump-semver の justfile**
(`push` が watch-workflow ヒントを echo → `on-success-release` で `brew upgrade`)。kawaz/claude-gh-monitor は
これを plugin の `claude plugin update` に適用した例 (やっていることは同じ)。

| リポ種別 | local 反映の置き場所 | 発火タイミング |
|---|---|---|
| CI 無し (hook / skill のみ) | `on-success-release` recipe を push から直接呼ぶ | push 直後 |
| CI あり (release.yml で artifact) | `on-success-release` recipe を watch 経由で呼ぶ | `watch-workflow --on-success` 経由、CI green 後 |

参考実装: **kawaz/bump-semver** (`brew upgrade`) / **kawaz/claude-gh-monitor** (plugin update 適用)。

## plugin list — 有効/無効フィルタ [実機検証済: v2.1.170]

CLI の `claude plugin list` には `--enabled` / `--disabled` フィルタは**存在しない**。
有効フィルタはインタラクティブセッション内の `/plugin list` スラッシュコマンドにのみ存在する。

| コンテキスト | コマンド | フィルタ対応 |
|---|---|---|
| CLI | `claude plugin list` | `--json` で `enabled` フィールドが出る、フィルタなし [実機検証済: v2.1.170] |
| インタラクティブセッション | `/plugin list --enabled` / `/plugin list --disabled` | 有効/無効プラグインのみ表示 [未検証 (対話 UI 専用)] 出典: CHANGELOG v2.1.163 |
| シェルスクリプト等 | `claude plugin list --json \| jq '[.[] \| select(.enabled)]'` | `enabled` フィールドで手動フィルタ [実機検証済: v2.1.170] |

- headless (`claude -p '/plugin list ...'`) は `/plugin isn't available in this environment.` を返す (= `/plugin` 系 slash command は対話 UI 専用) [実機検証済: v2.1.170]

```bash
# 有効プラグインのみ抽出 (CLI 経路)
claude plugin list --json | jq '[.[] | select(.enabled == true)]'
# 無効プラグインのみ抽出
claude plugin list --json | jq '[.[] | select(.enabled == false)]'
```

## skills-dir 自動ロード plugin と `plugin init` [実機検証済: v2.1.170]

`.claude-plugin/plugin.json` マニフェストを持つディレクトリを skills dir 以下に置くと、
marketplace install なしで次セッションから `<name>@skills-dir` として自動ロードされる。

### `plugin init` でのスキャフォールド

```bash
claude plugin init my-tool
```

- 作成先: `$CLAUDE_CONFIG_DIR/skills/my-tool/` (公式 docs 表記は `~/.claude/skills/` だが
  実際は `CLAUDE_CONFIG_DIR/skills/` に作成される) [実機検証済: v2.1.170]
- 生成物: `.claude-plugin/plugin.json` + `SKILL.md` の最小構成
- 次セッション以降 `my-tool@skills-dir` として自動ロード、`/reload-plugins` で即時適用も可

### skills-dir plugin の配置ルール

| skills dir | スコープ | ロード条件 |
|---|---|---|
| `$CLAUDE_CONFIG_DIR/skills/` (= personal) | ユーザ全プロジェクト | 常時 |
| `<cwd>/.claude/skills/` (= project) | そのプロジェクトのみ | workspace trust 承認後 |

**`.claude/skills/` と `.claude/plugins/` の区別**: `@skills-dir` のソースは `skills/` のみ。
`plugins/` は marketplace インストール済み plugin のキャッシュ置き場であり、
ユーザが直接置いて自動ロードさせる対象ではない。[実機検証済: v2.1.170]

| 配置場所 | ロード方式 | plugin list での表示 |
|---|---|---|
| `$CLAUDE_CONFIG_DIR/skills/<name>/.claude-plugin/plugin.json` あり | `@skills-dir` 自動ロード | `<name>@skills-dir`、`Status: ✔ loaded` |
| `$CLAUDE_CONFIG_DIR/skills/<name>/SKILL.md` のみ (manifest なし) | plain skill として直接ロード | `plugin list` には出ない |
| `$CLAUDE_CONFIG_DIR/plugins/cache/` | marketplace install 済み | `<name>@<marketplace>`、`Status: ✔ enabled` |

### skills-dir plugin の無効化・削除

```bash
# 無効化 (ディレクトリは残る)
claude plugin disable my-tool@skills-dir
# 削除: ディレクトリごと削除するだけ (uninstall コマンド不要)
rm -rf "$CLAUDE_CONFIG_DIR/skills/my-tool"
```

## `defaultEnabled: false` — インストール時無効化 [spec]

出典: [Plugins Reference](https://code.claude.com/docs/en/plugins-reference.md)。実機検証は未実施 (= install→enable の往復が必要で重いため spec 引用に留める)。

`plugin.json` または marketplace entry に `defaultEnabled: false` を設定すると、
インストール直後は無効状態になる。ユーザが明示的に有効化するまでロードされない。

```json
{
  "name": "optional-tool",
  "defaultEnabled": false
}
```

- ユーザが一度でも `claude plugin enable` / `/plugin enable` で有効化すると、
  その設定が `enabledPlugins` に書き込まれ、以降は `defaultEnabled` の変更に影響されない
- 依存先として require された場合は自動的に有効化される (依存元が active の間は `defaultEnabled` 無視)
- v2.1.154 以降のみ有効。旧バージョンはこの field を無視してインストール時に有効化する

同じ field は marketplace entry にも書ける。marketplace entry の値が `plugin.json` より優先される。

## トラブルシュート — `--safe-mode` と bundled skills 無効化

フラグ / 環境変数の実在は `claude --help` で確認済み [実機検証済: v2.1.170]。無効化範囲の一覧は公式 settings docs 由来 [spec] (各項目の個別実機検証は未実施)。

### `--safe-mode` / `CLAUDE_CODE_SAFE_MODE`

すべてのカスタマイズ (CLAUDE.md・skills・plugins・hooks・MCP servers・custom commands/agents 等) を
無効にして起動する。設定壊れ・hook 暴走の診断に使う。Admin managed (policy) 設定は有効のまま。

```bash
# フラグで起動
claude --safe-mode

# 環境変数で同等
CLAUDE_CODE_SAFE_MODE=1 claude
```

`--safe-mode` が無効化する範囲:
- CLAUDE.md の自動ロード
- すべての plugins (marketplace install 済み + skills-dir)
- hooks
- MCP servers (ユーザ設定分)
- skills・custom commands・agents
- output styles・workflows・custom themes・keybindings

auth・model 選択・built-in tools・permissions は通常通り動く。

### `disableBundledSkills` / `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS`

`--safe-mode` より細かい粒度の設定。Claude Code に同梱された bundled skills と workflows だけを
非表示にする。plugin / `.claude/skills/` / `.claude/commands/` の skills は**影響を受けない**。

```json
// settings.json
{ "disableBundledSkills": true }
```

```bash
# 環境変数で同等
CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1 claude
```

| 設定 | plugin/user skills | bundled skills | hooks | MCP |
|---|---|---|---|---|
| `--safe-mode` | 無効 | 無効 | 無効 | 無効 |
| `disableBundledSkills: true` | **有効のまま** | 無効 | 有効のまま | 有効のまま |

`/init` 等の built-in slash command は `disableBundledSkills: true` でもタイプ可能だが、
モデルからは非表示になる。

## version 管理

- plugin.json に `version` 設定済 → その文字列に pin、ユーザは version 変更時のみ更新通知 [spec]
- 未設定 → git commit SHA fallback (= 毎 commit が新 version 扱い) [spec]

## 参考 URL (出典)

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins.md)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces.md)
- [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins.md)
