# CC 新バージョン追従メンテパス

`claude-plugin-reference` の reference docs を新しい Claude Code バージョンへ追従させる定型手順。
AI agent がこれ一本で回せる粒度を目標とする。

## 1. トリガ: 鮮度チェック

```bash
just check-freshness
```

- "fresh" なら終了
- バージョン不一致なら exit 1 + 案内メッセージが出る → 以降の手順へ

SKILL.md `メンテナンス責務` セクションにある invoke 時チェックも同等の判定を行う。

## 2. 差分洗い出し

### 2a. バージョン↔日付の確定

CHANGELOG に日付欄はない。npm の publish 時刻で確定する:

```bash
curl -s https://registry.npmjs.org/@anthropic-ai/claude-code | jq '.time | to_entries | map(select(.key | test("^[0-9]"))) | sort_by(.key | split(".") | map(tonumber)) | .[-20:] | .[] | "\(.key)  \(.value)"' -r
```

### 2b. CHANGELOG 取得とトリアージ

```bash
curl -s https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md | head -400
```

`最終検証バージョン` より新しいエントリだけ読む。以下のキーワードに絞る:
plugin / hook / skill / command / agent / slash / PreToolUse / PostToolUse / SessionStart / Stop / SubagentStop / MessageDisplay / matcher / frontmatter / disallowed-tools / safe-mode / marketplace

関係ない変更 (UI 表示、翻訳、stability fix 等) は **スキップ**。

### 2c. 各変更を 4 カテゴリに仕分け

| カテゴリ | 担当 reference ファイル |
|---|---|
| hook event / matcher / output schema | `hooks.md` |
| skill string substitution / frontmatter / reload | `skills.md` + `commands.md` |
| distribution / CLI / plugin init / safe-mode | `distribution.md` |
| agent field / JSON スキーマ | `agents.md` |

## 3. issue 起票

`docs/issue/YYYY-MM-DD-cc-vX.Y.Z-maintenance.md` を作成。構成:

```markdown
# メンテナンスパス: CC vA.B.C → vX.Y.Z 差分の実機検証 + doc 反映

Status: open
Date: YYYY-MM-DD

## 背景
(旧バージョンと新バージョン、対象期間)

## TODO (執筆後追加 = 未反映の可能性が高い、優先・高)
- [ ] **<変更名>** (<バージョン>): <対象 reference file> §<節番号> を更新。

## TODO (反映漏れ要確認、優先・中)
- [ ] **<変更名>** (<バージョン>): <対象 reference file> に既出か確認。

## 該当なし (= 確認済み、doc 変更不要)
- <スキーマ変更なし> 等

## 完了条件
各 TODO を実機検証 → 該当 reference ファイルへ `[実機検証済: vX.Y.Z]` 付きで反映 →
SKILL.md 冒頭の「最終検証」スタンプを更新 → 本 issue を削除。
```

## 4. 実機検証

### 4a. 並列サブエージェント分割

4 つのカテゴリ (hooks / skills+commands / distribution / agents) を **別々のサブエージェントで並列実行** する。ファイルが重複しなければ編集衝突は起きない。

各サブエージェントへの指示テンプレ:

```
reference ファイル `skills/claude-plugin-reference/reference/<file>.md` の
以下の項目を実機検証し、結果を反映してください:

対象 TODO:
- <TODO 項目をコピー>

実機検証ハーネス (下記の定型集を使用):
- temp project dir: /private/tmp/cc-test-XXXX (mktemp -d)
- claude -p '...' --model claude-haiku-4-5 --permission-mode bypassPermissions --settings <file>
- CLAUDE_CONFIG_DIR は変更しない (認証維持)

[実機検証済: vX.Y.Z] ラベルは実機観測のみに付与。
docs / CHANGELOG 由来は [spec]、観測不能は [未検証] + 出典。
```

### 4b. 検証ハーネス定型集

#### 基本形

```bash
TMPDIR=$(mktemp -d /private/tmp/cc-test-XXXXXX)
# 最小 settings.json (パーミッション付与)
cat > "$TMPDIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Write(*)"],
    "deny": []
  }
}
EOF
# 実行
claude -p 'テスト内容' \
  --model claude-haiku-4-5 \
  --permission-mode bypassPermissions \
  --settings "$TMPDIR/settings.json" \
  2>&1
# cleanup
rm -rf "$TMPDIR"
```

"Warning: no stdin" は無害。無視してよい。

#### Stop / 会話継続系 hook の無限ループ防止

stamp ファイル + `stop_hook_active` の二段ガード:

```bash
# hook script 内 (stop_hook_active は stdin JSON で渡される。env var ではない)
input=$(cat)
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0
STAMP="/tmp/cc-test-stop-hook.stamp"
[ -f "$STAMP" ] && exit 0
touch "$STAMP"
# 本処理 (additionalContext / decision:block を返す)
```

#### additionalContext 注入の確認

固有トークンをモデルに復唱させる:

```
INJECT_TOKEN="VERIFY_TOKEN_12345"
# hook で additionalContext に INJECT_TOKEN を含む文字列を設定
# プロンプト: "INJECT_TOKEN という文字列を含むか答えてください"
# → 出力に INJECT_TOKEN が含まれれば inject 成功
```

#### 個人環境 hook による干渉の回避

個人環境の hook (backtick ガード等) が検証用 Bash を block する場合:

```bash
# テストケースをファイルに書き出して bash file.sh で実行
cat > "$TMPDIR/test.sh" <<'EOF'
echo $(git status)
EOF
bash "$TMPDIR/test.sh"
```

#### string substitution 検証

「本文を逐語出力させる skill」を temp project に置き、引数あり / なし両方で観測する:

```bash
mkdir -p "$TMPDIR/.claude/skills/esctest"
cat > "$TMPDIR/.claude/skills/esctest/SKILL.md" <<'EOF'
---
name: esctest
description: substitution test
---
以下の各行を加工せずそのまま逐語で出力せよ:
$1
\$1
\$100
$ARGUMENTS
EOF
(cd "$TMPDIR" && claude -p '/esctest alpha bravo' --model haiku)   # 引数あり
(cd "$TMPDIR" && claude -p '/esctest' --model haiku)               # 引数なし
```

#### tool gating 検証

対照群 (許可版) と deny 版の 2 本立てで deny メッセージを比較する。

#### `claude plugin init` の非対話実行

```bash
claude plugin init test-plugin        # 作成先は $CLAUDE_CONFIG_DIR/skills/test-plugin/
claude plugin list --json             # enabled / scope を確認
rm -rf "$CLAUDE_CONFIG_DIR/skills/test-plugin"   # 検証後は必ず掃除 (個人環境に skill が残留し、他セッションの skill 一覧に出てしまう)
```

`CLAUDE_CODE_SAFE_MODE=1` は plugin list 出力を変えない (ロード段階のみ作用)。

#### 対話 UI 専用挙動

headless では `/plugin isn't available in this environment.` が返る。
autocomplete、`/plugin` 系コマンドは headless 検証不可 → `[未検証]` + changelog 出典で記載。

## 5. ラベル規律

| ラベル | 適用条件 |
|---|---|
| `[実機検証済: vX.Y.Z]` | 自分の手 (またはサブエージェント) で実機観測した事実 |
| `[spec]` | 公式 docs / CHANGELOG に明示記述、実機未確認 |
| `[未検証]` | 公式記述はあるが実機観測不能 or 未実施 (出典を併記) |
| `[実装の副産物]` | spec 保証なし、挙動から推測 |

### サブエージェント成果の監査ポイント

メイン agent がサブエージェントの成果をレビューする際の確認事項:

- **未観測の「値の例」** — 実際に観測せず推測で書かれた値例に `[実機検証済]` が付いていないか
- **節見出しラベルの過大適用** — 節全体を実機検証していないのに節見出しに `[実機検証済]` を付けていないか
- **対話 UI 専用挙動への実機ラベル** — headless 検証不可な autocomplete 等に実機ラベルが付いていないか
- **docs / changelog 由来の記述** — CHANGELOG の文言そのままで `[実機検証済]` にしていないか

疑わしい箇所は `[spec]` または `[未検証]` に格下げする。

## 6. 仕上げ

```bash
# 1. SKILL.md 冒頭スタンプを更新
#    > **最終検証: Claude Code vX.Y.Z (YYYY-MM-DD)**

# 2. issue ファイルを削除 (解決済み)
rm docs/issue/YYYY-MM-DD-cc-vX.Y.Z-maintenance.md

# 3. journal を記録 (経緯・ハマり所・新発見)
#    docs/journal/YYYY-MM-DD-cc-vX.Y.Z-maintenance.md

# 4. バージョン bump (skills/ が変更されている場合は必須)
just bump-version

# 5. push
just push
```

### journal の記録内容

- 検証した TODO 項目と結果の概要
- changelog 記述と実機挙動が **食い違った** 点 (反証)
- 新たに発見したフィールド・挙動
- 次回担当 agent が再利用できる検証ハーネスの注意点

## 関連

- `skills/claude-plugin-reference/SKILL.md` — invoke 時の鮮度チェック手順
- `docs/STRUCTURE.md` — リポ物理構造
- CHANGELOG: `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`
- npm registry: `https://registry.npmjs.org/@anthropic-ai/claude-code`
