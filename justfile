# claude-plugin-reference push / bump-version / validate
# (push-guard hook 経由でこの task を使うことで、直叩き block を回避)

# ---------- variables ----------

# bump trigger 対象 = plugin 配布物 (skill / README) の変更
# = これらが変更されていれば bump-version 忘れずに必要 ('docs/' 等の開発メタは対象外)
# plugin プロジェクトは本質的提供物が md なので skills/ も bump trigger に含める
bump-trigger-paths := "skills/ README.md"

# version を持つ manifest ファイル (= bump-semver の対象)
version-files := ".claude-plugin/plugin.json .claude-plugin/marketplace.json"

# ---------- main tasks ----------

# push (バージョン bump 済みを前提、全 gate 通過後に push してローカルも更新)
push: ensure-clean validate check-versions check-version-bumped
    bump-semver vcs push --branch main --jj-bookmark-auto-advance
    @just _local-plugin-reload

# push (ドキュメント更新等のみで bump 不要な場合)
push-without-bump: ensure-clean validate check-versions
    bump-semver vcs push --branch main --jj-bookmark-auto-advance
    @just _local-plugin-reload

# version を bump して Release commit を作成 (push は別途 `just push`)
[script]
bump-version bump="patch": ensure-clean
    new_version=$(bump-semver {{ bump }} {{ version-files }} --write --no-hint)
    bump-semver vcs commit -m "Release v${new_version}" {{ version-files }}

# 現在の version を確認
version:
    @bump-semver get {{ version-files }} --no-hint

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
    @bump-semver get {{ version-files }} --no-hint >/dev/null

# push 成功直後の local 反映: 現セッションの marketplace + plugin を update し、
# /reload-plugins 依頼まで出す。push して終わりだと local Claude は古い plugin で
# 動き続けるため、push task に embed して仕組みで強制する。
[private]
_local-plugin-reload:
    claude plugin marketplace update claude-plugin-reference
    claude plugin update claude-plugin-reference@claude-plugin-reference
    @echo ""
    @echo "[hint] /reload-plugins to apply in this session without restart"

# bump-trigger-paths に変更があるなら version も bump されていることを確認
# (plugin の本質的提供物 = skill 等 md が変わったのに version 据え置きの事故を防ぐ)
# bump-semver vcs diff -q で jj/git 分岐を統一 (DR-0020, v0.20.0+)
# Design rationale: 旧 jj 分岐は `|| exit 1` で fetch 漏れを区別していたが、
# bump-semver vcs diff の exit code 3 (VCS error) を捕まえて同じ区別を維持する。
# `|| rc=$?` で set -e を回避しつつ rc を保存。
check-version-bumped:
    #!/usr/bin/env bash
    set -euo pipefail
    # exit 0 = bump-trigger-paths に変更なし → bump 不要
    # exit 1 = 変更あり → version bump 済みかチェックに進む
    # exit 3 = VCS error (main@origin 未 track 等)
    rc=0
    bump-semver vcs diff -q main@origin -- {{ bump-trigger-paths }} || rc=$?
    case "$rc" in
      0) exit 0 ;;
      1) ;;
      *) echo "ERROR: bump-semver vcs diff failed (rc=$rc). main@origin が track されていない可能性。先に 'jj git fetch' / 'git fetch' を試してください" >&2; exit 1 ;;
    esac
    # バージョン更新済みなら success
    bump-semver compare gt .claude-plugin/plugin.json vcs:main@origin:.claude-plugin/plugin.json --no-hint && exit 0
    echo 'ERROR: bump-trigger-paths が変わってるが version 未 bump。"just bump-version" を実行してください' >&2
    exit 1
