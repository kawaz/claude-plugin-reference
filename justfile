# claude-plugin-reference push / bump-version / validate
# (push-guard hook 経由でこの task を使うことで、直叩き block を回避)

# ---------- settings ----------

set positional-arguments

# ---------- main tasks ----------

# push (バージョン bump 済みを前提、全 gate 通過後に push してローカルも更新)
push: check-on-default-branch ensure-clean validate test check-versions check-version-bumped check-outdated-translations check-embedded-justfile-sync check-bare-labels
    bump-semver vcs push --branch main --jj-bookmark-auto-advance
    just on-success-release

# version を bump して Release commit を作成 (push は別途 `just push`)
[script]
bump-version bump="patch": ensure-clean
    new_version=$(bump-semver "$1" .claude-plugin/plugin.json .claude-plugin/marketplace.json --write --no-hint)
    bump-semver vcs commit --allow-nonexistent-path -m "Release v${new_version}" .claude-plugin/plugin.json .claude-plugin/marketplace.json

# 現在の version を確認
version:
    @bump-semver get .claude-plugin/plugin.json .claude-plugin/marketplace.json --no-hint

# plugin spec を validate
validate:
    claude plugin validate .

# tests/ 配下のテストを実行 (1 つでも fail したら exit 非 0)。
# tests/*.test.sh が 0 件なら glob が literal のまま残るため [ -e "$f" ] で防御 (= skip)。
test:
    @for f in tests/*.test.sh; do [ -e "$f" ] || continue; bash "$f" || exit 1; done

# ---------- internal recipes (push の依存) ----------

# 現在の bookmark/branch が default (= main) 上にあるか確認 (DR-0038 dogfood)。
# `vcs is on-default-branch` の反転 — `vcs is worktree` ベースだと kawaz の
# jj 運用 (main workspace 自体が secondary workspace) で main からの push が
# 誤検出される (bump-semver v0.40.1 DR-0038 Adoption pattern 節)。validate/test
# 等を先に走らせると無駄が大きいので push 最初の dep に置く。
[private]
[script]
check-on-default-branch:
    if ! bump-semver vcs is on-default-branch; then
        bn=$(bump-semver vcs get default-branch)
        printf >&2 "⚠ default branch (%s) に合流してから push してください\n  1. just sync         # %s@origin に rebase\n  2. just promote      # %s bookmark を current commit に forward\n  3. %s ワークスペースに移動して just push\n" "$bn" "$bn" "$bn" "$bn"
        exit 1
    fi

# 現在の worktree を default branch (= origin/<default>) に rebase (DR-0038)
sync:
    bump-semver vcs sync --onto $(bump-semver vcs get default-branch)@origin

# default branch を現在の commit に forward (DR-0038、push しない)
promote:
    bump-semver vcs promote

# uncommitted change がない状態か確認 (git/jj-agnostic, DR-0020)
ensure-clean:
    bump-semver vcs is clean

# plugin.json と marketplace.json の version 一致を保証 (multi-file 整合性)。
# bump-semver get は multi-file 時に内部で整合チェック (不一致は error 表示で exit 非 0)。
[private]
check-versions:
    @bump-semver get .claude-plugin/plugin.json .claude-plugin/marketplace.json --no-hint >/dev/null

# release 成功後の local 反映: marketplace + plugin を update (CI 無しは push から直接 / CI ありは watch 経由)。
# 各 update は warn 降格: push は既に成功済なので、ここで失敗しても release 自体は完了している。
# (失敗時に exit 非 0 にすると「push 済みなのに just push 失敗表示 → 再実行は version gate で弾かれ詰む」)。
# 単独再実行可: `just on-success-release` でこの local 反映だけやり直せる。
on-success-release:
    @claude plugin marketplace update claude-plugin-reference || echo "[warn] marketplace update 失敗。push は成功済み。'just on-success-release' で単独再実行可" >&2
    @claude plugin update claude-plugin-reference@claude-plugin-reference || echo "[warn] plugin update 失敗。push は成功済み。'just on-success-release' で単独再実行可" >&2
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

# skills/ 内の「裸の検証ラベル」を検出して fail させる (= バージョン併記の徹底)。
# 許容形式: `[実機検証済: vX.Y.Z]` / `[実機検証済: ~vX.Y.Z]` (= コロン + 任意で ~ + v 始まり)。
# fail 対象: `[実機検証済]` (裸) / `[実機検証済 2026-...]` (日付のみ) / `[実機検証済 (plugin名)]` 等。
#
# Design rationale: grep -P (PCRE 否定先読み) は [script] recipe の sh で /usr/bin/grep (BSD)
# に解決され使えない。BSD/GNU 両対応のため「全 `[...]` ラベルを -oE で抽出 → 許容形式を -v で除外」
# の 2 段 grep にする。さらに以下は意図的な非ラベルなので除外 (= false positive 回避):
#   - ラベル凡例行 (`[spec]` と `[未検証]` が同一行に並ぶ定義行)
#   - 記法例の行 (`例:` を含む説明行)
#   - コードフェンス (```) 内の行 (= 埋め込み justfile 等のコード例。本 recipe 自身のパターン
#     文字列が embedded justfile 経由で skills/ に現れるため、除外しないと自己検知する)
[private]
[script]
check-bare-labels:
    bad=$(grep -rnoE '\[実機検証済[^]]*\]' skills/ \
      | grep -vE '\[実機検証済: ~?v' \
      | while IFS= read -r line; do
          [ -n "$line" ] || continue
          file=${line%%:*}
          rest=${line#*:}
          lno=${rest%%:*}
          in_fence=$(awk -v n="$lno" 'NR>=n{exit} /^```/{f=1-f} END{print f+0}' "$file")
          [ "$in_fence" = "1" ] && continue
          src=$(sed -n "${lno}p" "$file")
          printf '%s' "$src" | grep -qE '\[spec\].*\[未検証\]' && continue
          printf '%s' "$src" | grep -qE '例[:： ]' && continue
          printf '%s\n' "$line"
        done)
    if [ -n "$bad" ]; then
      echo 'ERROR: skills/ bare verification labels found (accepted: [実機検証済: vX.Y.Z] / [実機検証済: ~vX.Y.Z])' >&2
      printf '%s\n' "$bad" >&2
      exit 1
    fi

# ---------- reference freshness ----------

# SKILL.md の最終検証スタンプと「現行 Claude Code バージョン」を semver 比較し、陳腐化を検出する。
# 現行 = スタンプ → fresh (exit 0) / 現行 > スタンプ → stale (exit 1) /
# 現行 < スタンプ → fresh 扱い (= 現行側が古いだけ、メンテ不要。exit 0)。
# 比較相手は 2 系統:
#   1. ローカル `claude --version` (= 実行環境の版)
#   2. npm registry の `@anthropic-ai/claude-code` latest (= 世の中の最新版)。
#      ネットワーク失敗時は warn して skip (= gate を壊さない)。
# スタンプ抽出は `> **最終検証:` 行限定にアンカー (本文に "Claude Code vX.Y.Z" を書いても誤検出しない)。
# push の deps には含めない (= 任意実行)。
[script]
check-freshness:
    current=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    stamped=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' skills/claude-plugin-reference/last-verified.txt | head -1)
    if [ -z "$current" ]; then
      echo "ERROR: claude --version の取得に失敗しました" >&2
      exit 1
    fi
    if [ -z "$stamped" ]; then
      echo "ERROR: last-verified.txt の最終検証スタンプが見つかりません (期待形式: 'vX.Y.Z (YYYY-MM-DD)')" >&2
      exit 1
    fi
    # --- npm registry latest との比較 (best-effort) ---
    npm_latest=$(curl -fsS --max-time 10 https://registry.npmjs.org/@anthropic-ai/claude-code 2>/dev/null | jq -r '."dist-tags".latest' 2>/dev/null)
    if [ -z "$npm_latest" ] || [ "$npm_latest" = null ]; then
      echo "[warn] npm registry latest の取得に失敗 (= ネットワーク等)。npm 比較は skip" >&2
    else
      nrc=0
      bump-semver compare gt "$npm_latest" "$stamped" -qq || nrc=$?
      case "$nrc" in
        0) echo "stale(npm): SKILL.md の最終検証 v${stamped} / npm latest v${npm_latest}"
           echo "メンテパス実施を検討してください: docs/runbooks/cc-version-maintenance.md" ;;
        1) echo "fresh(npm): npm latest v${npm_latest} <= スタンプ v${stamped}" ;;
        *) echo "[warn] bump-semver compare(npm) failed (rc=$nrc)。npm 比較は skip" >&2 ;;
      esac
    fi
    # --- ローカル claude --version との比較 (本 recipe の exit code を決める) ---
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
