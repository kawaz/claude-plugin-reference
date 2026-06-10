# claude-plugin-reference push / bump-version / validate
# (push-guard hook 経由でこの task を使うことで、直叩き block を回避)

# ---------- settings ----------

set positional-arguments

# ---------- main tasks ----------

# push (バージョン bump 済みを前提、全 gate 通過後に push してローカルも更新)
push: ensure-clean validate check-versions check-version-bumped check-outdated-translations
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
