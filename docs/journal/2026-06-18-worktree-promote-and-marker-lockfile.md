# 2026-06-18 worktree promote 手順とバージョンマーカーのロックファイル化

## 経緯

### バージョンマーカーの直書き問題

朝のセッション (zpxzlppk) で、commands.md / skills.md に `[実機検証済: v2.1.181 (cmux-msg)]` マーカーを個別追記した際、SKILL.md 冒頭の「最終検証: Claude Code v2.1.177 (2026-06-13)」スタンプを「ついでに最新化」しようとして利用者目視で阻止された。その対策として、SKILL.md 冒頭に「AI agent 警告」長文ブロックを追加した。

その後の議論で、kawaz から本質的指摘:

> SKILL.mdにそんな長文書くバカがいるかって話よね。マーカーとしての値なら自由文であるmdファイルじゃなくて専用のロックファイル的なのをプロジェクト内に設けるべきでは？

= **「文章で『触るな』と書く」より「物理的に触れない構造にする」べき**。SKILL.md は常時 context にロードされるので長文警告は token 浪費でもある。

### 採用案

1. `skills/claude-plugin-reference/last-verified.txt` (1 行) を新設、内容: `v2.1.177 (2026-06-13)`
2. SKILL.md 冒頭スタンプを `` !`cat ${CLAUDE_SKILL_DIR}/last-verified.txt` `` (Dynamic Context Injection、skills.md §5) で embed
3. 警告ブロックは削除 (= ロックファイルが物理バリアになるので文章不要)
4. § メンテナンス責務 手順 3 を「last-verified.txt を 1 行で書き換え」に更新

### worktree 経由作業で見えた追加課題

`EnterWorktree` で隔離 workspace を作って編集したが、worktree のベースが `myyokrpq` (= main bookmark = v0.2.16) で **今日のコミット zpxzlppk より前**。私の change を main に反映するには:

- zpxzlppk と私の change の統合 (= 警告ブロック追加を取り消す + embed 化を乗せる)
- main bookmark の進行 (= zpxzlppk + 私の change を含む位置に)
- marketplaces 側 checkout の更新 → reload で embed 展開を実機検証
- push

これらが全部「AI が jj 知識から手作業で組み立てる」状態。後続セッションでも同じ手戻りが発生する。

kawaz の指針:

> その作業自体が、worktree内での挙動とjustでのリリースフローの練習や実践の知見になる。まずはどういう手順でやるのが事故が少なく意図通りスムーズに行えるかのパターンを学習して、それからvcsの提案など他関連リポジトリへのissue起票などを進めるのがよい

= **実践 → 知見蓄積 → 上流還元 (bump-semver vcs 拡張 / docs-structure runbook テンプレ)** の順序。

## 現状の jj グラフ (実践開始時点)

```
@  mplxukln 私の change (last-verified.txt + SKILL.md embed 化)   ← worktree-last-verified-lockfile workspace の @
◆  myyokrpq Release v0.2.16 [main]                                ← main bookmark の現在位置
…
   ○  lrukmkrq (no desc)                                          ← default workspace の @
   │ ○  ptkyvvxk (no desc) [worktree-last-verified-lockfile]     ← EnterWorktree が作った空 commit
   ├─╯
   ○  zpxzlppk 警告ブロック追加 + commands.md/skills.md 更新       ← 今日朝の commit、main 未進行
   ├─╯
```

両系統 (= 私の change と zpxzlppk) が myyokrpq から並行で分岐していて、まだ統合されていない。

## 実践手順 (これからやる、事故防止の観点で設計)

### Step 1: zpxzlppk の SKILL.md 警告ブロック追加を取り消す

```bash
jj edit zpxzlppk
# SKILL.md を編集して警告ブロック 7 行を削除
# commands.md / skills.md は触らない
```

確認: zpxzlppk の diff から SKILL.md 変更が消え、commands.md / skills.md の変更だけ残る。

### Step 2: 私の change を zpxzlppk の上に rebase

```bash
jj rebase -r mplxukln -d zpxzlppk
```

jj は子孫を自動追従するので、ptkyvvxk と lrukmkrq の処理は別途確認。

### Step 3: main bookmark を mplxukln に進める

```bash
jj bookmark set main -r mplxukln
```

### Step 4: marketplaces 側 checkout を更新 → reload で embed 検証

marketplaces/claude-plugin-reference は別 checkout なので、それを最新 main まで進める。jj 環境なら `jj git fetch` + bookmark 同期、git 環境なら `git pull`。

reload 後に `/claude-plugin-reference:claude-plugin-reference` を呼んで SKILL.md 冒頭が `v2.1.177 (2026-06-13)` に展開されることを確認。

### Step 5: just push で検証 + push

embed 化は SKILL.md の機能追加扱いなので version bump 必要 (= plugin.json + marketplace.json)。`just bump-version patch` で対応。

## 詰まり所 / 判断ポイント (実践中に追記)

(実践しながら追記)

## 知見の上流還元 (Phase 完了後に起票予定)

### bump-semver vcs に追加すべきサブコマンド

| サブコマンド | 用途 | 既存との関係 |
|---|---|---|
| `vcs is worktree` | 現在 worktree/workspace 内か (bool) | `vcs is clean/dirty/git/jj` パターン |
| `vcs get worktree-name` | hint メッセージ用 | `vcs get current-branch` パターン |
| `vcs promote` | 現 change を default branch に合流 (push せず) | `--jj-bookmark-auto-advance` を push と切り離した版 |

### just push の hint 路線

```just
push:
    @if bump-semver vcs is worktree; then \
        bn=$(bump-semver vcs get default-branch); \
        echo "⚠ worktree にいます ($(bump-semver vcs get worktree-name))。"; \
        echo "  main 反映 → push の手順:"; \
        echo "    just promote   # 現 change を ${bn} へ合流"; \
        echo "    just push      # ${bn} から検証 + push"; \
        exit 1; \
    fi
    # 既存の検証ゲート + vcs push
```

### docs-structure runbook テンプレ

`docs/runbooks/worktree-workflow.md` を kawaz/claude-rules-personal の templates/ に追加。今回の実践で固めた手順をテンプレ化。

### jj-worktree plugin への上流還元ネタ

EnterWorktree (= 内部的に jj 側では jj-workspace 経由) の挙動として、**workspace 作成時に bookmark が無い**問題がある:

- jj 自体は bookmark 不要 (= change_id で十分動く) ので、workspace 作成だけでは bookmark が自動で生えない
- 一方 git は worktree 作成時に `-b/-B` で branch が基本必須 (= worktree = branch checkout)
- これを差異吸収するため、jj 側でも「workspace 名と同じ bookmark を自動セット」する案を検討中

今回の実践でも:
- `worktree-last-verified-lockfile` という bookmark が `ptkyvvxk` (= EnterWorktree が作った空コミット) に貼られていた
- 私が編集を進めた `mplxukln` には bookmark が無い (= 自動追従しない)
- main 進行時に「どの change を bookmark で指すか」の判断が AI に委ねられる

→ jj-worktree plugin (or Claude Code 本体の EnterWorktree 実装) に **「workspace 作成時に bookmark を初期化し、`jj commit` のたびに自動 advance」** の選択肢があると、git 環境との挙動が揃って手順が単純化される。

これは bump-semver vcs / docs-structure runbook とは別の上流還元先。

## 詰まり所 / 判断 (実践中に追記)

### `jj edit zpxzlppk` で WC が切り替わる時の AI 視点の混乱

`jj edit zpxzlppk` を実行すると WC の中身が zpxzlppk のスナップショットに切り替わる。私 (= 現 change mplxukln) が作った journal や last-verified.txt がファイルシステム上から「消えた」ように見える。実際は change として保持されていて、`jj edit mplxukln` で戻れば復活する。

**事故防止のコツ**:
- WC 切り替え前に `jj describe` で現 change に説明文を付けておく (= 後から「これは何の change?」と探しやすい)
- WC 切り替え時、ファイル消失で慌てて `git add` 等の救出操作を打たない (= jj は change を勝手に失わない)
- Edit ツールは WC 切り替えで Read 状態がクリアされる (= 再 Read してから Edit が必要)

### rebase で conflict が出なかった理由

mplxukln (= 私の embed 化、myyokrpq ベース) を zpxzlppk (= 警告ブロック削除後、commands.md/skills.md だけ更新) の上に rebase した時、conflict は出なかった。理由:

- zpxzlppk の SKILL.md 変更は警告ブロック追加だけだった (= 取り消し後は myyokrpq と同じ SKILL.md)
- 私の embed 化は myyokrpq の SKILL.md に対する変更
- 親の SKILL.md が同じなので 3-way merge で素直に乗る

もし zpxzlppk の SKILL.md に他の変更も含まれていたら conflict が出て手解決が必要だった。
**教訓**: 「直近 commit の一部だけ取り消し → 上に乗せる」シナリオでは、取り消し対象が独立した変更か (= 他の変更と混ざってないか) を `jj diff` で事前確認すべき。

### `jj diff -r <change> <path>` で個別ファイルの差分が分かる

シナリオ判断の正本に使える: zpxzlppk が SKILL.md に何を変えたか、commands.md に何を変えたか、を個別に確認できる。これで「警告ブロックだけ取り消す」判断が安全に取れた。

### EnterWorktree のベースが古い問題 (本実践のドリブン要因)

`worktree.baseRef = fresh` (= 既定) だと、worktree のベースが origin/HEAD = `myyokrpq` (= 過去 release commit)。今日の朝に commit した `zpxzlppk` (= main bookmark 未進行) が worktree から見えない。

これにより:
- 私の change は myyokrpq の上に乗ってしまった
- zpxzlppk と統合するには `jj rebase -d zpxzlppk` が必要
- AI セッションが毎回この手戻りを踏む可能性

**解決方向** (上流還元):
- 短期: `worktree.baseRef = head` を試す (= 副作用: 親 WS の未 commit を引きずる)
- 中期: `bump-semver vcs sync` (= `vcs rebase --onto-default`) を justfile の sync task に組み込む
- 長期: EnterWorktree 時に「main bookmark の現位置 + 親 WS の HEAD」のどちらを base にするか hint を出す
