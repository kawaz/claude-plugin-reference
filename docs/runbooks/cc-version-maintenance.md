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

### 2c. 各変更を 7 カテゴリに仕分け

| カテゴリ | 担当 reference ファイル |
|---|---|
| hook event / matcher / output schema / blockable | `hooks.md` |
| skill frontmatter / string substitution / Dynamic Context Injection / invocation 制御 | `skills.md` |
| `commands/*.md` 書式 / skills との使い分け / 3 軸構造 | `commands.md` |
| agents field / agent frontmatter / 名前空間 / 起動方法 | `agents.md` |
| plugin.json / marketplace.json / 配布フロー / version bump | `distribution.md` |
| `claude` CLI option / `--print` / `--output-format=json` / `--json-schema` / `--safe-mode` / `--bare` / subcommand | `cli.md` |
| 組み込み slash command (`/clear` `/compact` `/plugin` `/code-review` `/fork` 等) / bundled skill / workflow / alias | `builtin-slash-commands.md` |

1 変更が複数ファイルに該当するなら両方に積む (重複 OK)。どこにも該当しない変更は `_unassigned` バケツに入れて人間判定。

## 3. issue 起票 (= Workflow 経路では optional)

Workflow tool 経路で triage → apply を 1 ターンで回す場合、TODO 一覧は workflow の structured output に乗るので **メンテパス用 issue の起票は省略してよい**。履歴は §7 の journal で十分残る。

それでも次のいずれかに該当するなら issue を起票 (= `/local-issue:write`):

- メンテパスの実行中に中断・再開が必要 (例: 検証コストが重く 1 ターンで完結しない)
- 反映後に未解決の follow-up TODO が残る (= 「_unassigned 判定」「再観測 TODO」「他資産フラグの routing」等を後続作業に渡したい)

起票する場合の構成:

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

### 4a. 並列実行 (Workflow tool 推奨)

7 つの reference ファイルは互いに独立しているので **並列実行可能**。担当 TODO がある file だけ起動すれば良い。

実行手段は次の 2 通り:

- **Workflow tool** (推奨): triage → 7 file 並列 apply → synthesize を 1 つの workflow script に組み、メイン会話を 1 ターンで完結させる。同 script を `Workflow({scriptPath, resumeFromRunId})` で resume すれば cache 済みの triage は再計算されない。
- **Agent tool の `run_in_background: true` を 7 並列**: workflow を組むほどでもない小修正なら直接 Agent でも可。ただし状態管理はメインの責任。

### 4b. サブエージェント指示テンプレ (= prompt に必ず含める)

```
reference ファイル `skills/claude-plugin-reference/reference/<file>.md` の
以下の項目を実機検証し、結果を反映してください:

対象 TODO:
- <TODO 項目をコピー>

実機検証ハーネス (下記の定型集を使用):
- temp project dir: /private/tmp/cc-test-XXXX (mktemp -d)
- claude -p '...' --model claude-haiku-4-5 --permission-mode bypassPermissions --settings <file>
- CLAUDE_CONFIG_DIR は変更しない (認証維持)
- 個人 hook plugin (= リポ直下を CLAUDE_PROJECT_DIR にすると bash-safety 等が干渉) を避けるため、temp dir 内で claude を起動する

省コンテキスト原則 (kawaz feedback `reference-lean-details-to-journal`):
- reference 本文は **1 項目 = 1 文 + ラベル + バージョン** に圧縮。
- 試行過程・逐語エラー・観測コマンド出力等の細かい記録は **本文に書かない** (= 詳細は journal へ)。
- 例外: changelog 記述と実機挙動が食い違った点は本文 1 行で明示 (= 反証は読者の判断に影響)。
- 表面 API (= 新 hook event / frontmatter field / substitution 変数 / CLI フラグ / slash command) は実機検証に寄せる。CC 内部挙動の変化は [spec] 1 行で寝かせる。

ラベル付与方針:
- [実機検証済: vX.Y.Z] は自分で観測した事実のみ
- docs / CHANGELOG 由来は [spec]
- 観測不能は [未検証] + 出典 URL
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

**workspace trust + auto-mode classifier 干渉の workaround**: temp dir 起動だと workspace trust 未取得で `Ignoring N permissions.allow entries from .claude/settings.json: this workspace has not been trusted.` の警告が出て `permissions.allow` が破棄される。さらに auto-mode classifier が `.claude.json` への trust 書き込みを self-modification として deny する。回避策: 上記のように `--settings <file>` 経路で settings を引数渡しする → `permissions.allow` は依然適用されないが、**`permissions.deny` と `hooks` は適用される** (= permission gating / hook 発火検証はこれで十分)。観測: cc v2.1.193 (`docs/journal/2026-06-26-cc-v2.1.193-maintenance.md`)。

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
- **省コンテキスト違反** — reference 本文に逐語エラー・試行過程・観測コマンド出力の貼り付けが混入していないか (= journal 行きの内容が本文に残っていないか)。`reference-lean-details-to-journal` 違反は格下げではなく **本文から journal への移動** で修正

疑わしい箇所は `[spec]` または `[未検証]` に格下げする。

## 6. 適用余地レビュー (新機能 → 既存 rule / skill / plugin)

reference への反映だけで終わらせない。**実機検証で挙動を理解したこのタイミングで**、確定した新 capability / 仕様変更が kawaz の既存資産を**簡単化・堅牢化・陳腐化**させないかを 1 度だけ問う。機能を理解したて = 最も低コストで気づける瞬間。

### やること (= 軽量フラグのみ。実装はしない)

各「[実機検証済] で確定した新 capability」について自問:

- この機能で、既存の自作 **hook plugin** (`claude-push-guard` / `claude-bash-safety` / draft `gh-issue-guard` 等) の自前パース/判定を置換 or 補助できないか
- 既存の **rule / skill** の手順が、新フィールド・新オプションで簡潔になないか
- 手製ワークアラウンドが新機能で**不要**にならないか

候補が出たら **フラグするだけ**:

1. journal (§7) に「適用候補: <新機能> → <対象資産> (<簡単化/堅牢化/陳腐化>)」を 1 行記録
2. 対象資産が**別リポ/別 overlay**にある場合 (= ほぼ常にそう) は、`dogfooding-feedback-upstream` ルールに従い **owning repo の `docs/issue/` に起票** or 担当セッションへ共有。**この runbook 内で他リポの実装に着手しない**

### 起票するときの姿勢 (= 部外者は実装を指図しない)

このパスのメイン agent は対象資産から見れば**部外者**。`dogfooding-feedback-upstream` の
「部外者として起票するときの姿勢」に従い、起票は次に徹する:

- **フラグ + 一次資料の提示**に留める: 「この機能使えそう」「賢い所と fail-open になる条件は
  `claude-plugin-reference` の `reference/<file>.md` §X を見て確認して」まで。**実装の適用方法は
  当事者セッションに考えさせる** (具体的な diff/コードを渡さない)
- **起票前に該当性を自分で確認**: 対象のコードを読み、本当に該当するか確かめる。的外れな issue は
  当事者の時間を奪うノイズ (例: コマンド名マッチ機能を、クォート解析が責務の hook に提案しない)
- 推測混じりかもしれない前提で「裏取りしてから採否を決めて」と明記する

### 注意 (= スコープ肥大の予防)

- このステップは**候補抽出と routing まで**。実際の置換実装は owning repo 側の別作業。
- ほとんどのパスは「候補なし」で no-op。空振りで良い (毎回フルに全 plugin を精査しない、新機能起点で逆引きするだけ)。
- guard 系への `if` 適用を検討する場合: コマンド名止まりパターン (`Bash(git *)`) は厳密判定だが、深いパターン (`Bash(git push *)`) は `$()`/`$VAR`/パース不能で fail-open。guard では過剰発火は安全側だが「`if` だけで完璧に絞れる」前提は置かない (= script 側の検査は残す)。

## 7. 仕上げ

```bash
# 1. last-verified.txt を 1 行で更新 (SKILL.md 冒頭スタンプの embed 元)
#    "vX.Y.Z (YYYY-MM-DD)" の 1 行のみ。SKILL.md 本文は触らない。
echo "vX.Y.Z (YYYY-MM-DD)" > skills/claude-plugin-reference/last-verified.txt

# 2. issue を close (= local-issue plugin が archive へ移動)
#    /local-issue:update <slug> close
#    旧フロー (rm docs/issue/...) は廃止

# 3. journal を記録 (経緯・ハマり所・新発見)
#    docs/journal/YYYY-MM-DD-cc-vX.Y.Z-maintenance.md
#    省コンテキスト原則のため、reference に書けなかった詳細はここに落とす

# 4. バージョン bump (skills/ または hooks/ が変更されている場合は必須)
just bump-version

# 5. push (= push-guard hook が直 push をブロックするので必ずこの経路)
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
