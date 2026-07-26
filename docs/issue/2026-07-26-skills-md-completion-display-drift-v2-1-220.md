---
title: skills.md の補完表示ルールが現行 v2.1.220 と乖離している可能性
status: open
category: tech-memo
created: 2026-07-26T17:23:19+09:00
last_read:
open_entered: 2026-07-26T17:23:19+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: claude-rules-personal (cross-project write)
---

# skills.md の補完表示ルールが現行 v2.1.220 と乖離している可能性

## 概要

`reference/skills.md` の「§1 補完表示ルール」[実機検証済: ~v2.1.160 + v2.1.183] が、`skills/<name>/SKILL.md` (name ≠ plugin) の配置について「短縮 `/<name>` + `(<plugin>)` 表示」と記載している。しかし v2.1.220 の実機では **full 表示 `/<plugin>:<name>` + `(<plugin>)`** になっているように見える。

## 背景

kawaz/claude-rules-personal での実測 (2026-07-26、Claude Code v2.1.220)。`rules-personal` plugin に `skills/<slug>/SKILL.md` 形式で 25 個の skill を配置し、対話 UI で `/personal` と入力した時の補完表示:

```
/rules-personal:cross-env-ssh-signing   (rules-personal) ...
/rules-personal:docs-knowledge-flow     (rules-personal) ...
/rules-personal:docs-structure          (rules-personal) ...
/rules-personal:gh-image-attach         (rules-personal) ...
```

いずれも plugin prefix 付きの full 表示。短縮 `/<name>` にはなっていない。

該当箇所は `skills.md` §1 の「補完表示ルール」の表、および直後の「短縮表示の skills 配置は plugin 元が見えないので、他 plugin と命名衝突した時の判別性が低い。user invocable な entry は commands 配置にすると補完で plugin 元が常に出る」という結論。この結論が現行版でも成立するかが変わる (= 成立しないなら、commands 配置を推す理由が 1 つ減る)。

### 補足: AI 側の識別子は両配置で同一 (実測)

使い捨て plugin (`skills/zzskillside/SKILL.md` と `commands/zzcmdside.md` を両方持つ) を install して `claude -p` で列挙させた結果、両方とも `<plugin>:<name>` 形式:

```
plprobe:zzcmdside
plprobe:zzskillside
```

AI から見える識別子には配置による差が無い。差があるとすれば補完表示だけ、という切り分けになる。

### 部外者からのフラグとしての注記

- 対話 UI の補完表示は headless で再現しないため、こちらの観測は「1 環境・1 バージョンでのスクリーンショット目視」に留まる。バージョン差か、こちらの環境固有 (skillOverrides 等) かの切り分けはしていない
- reference 側の最終検証は v2.1.199、現行は v2.1.220 なので、この間の変更の可能性がある
- 実際に記述を直すかどうか、どう直すかは当事者側で裏取りしてから判断してほしい

出所: 2026-07-26 の claude-rules-personal セッション発 (cross-project write)。

## 受け入れ条件

- [ ] v2.1.220 (または現行版) の実機で `skills/<name>/SKILL.md` (name ≠ plugin) 配置の補完表示を再検証する
- [ ] full 表示への変化が確認されたら `skills.md` §1 の記載・結論 (短縮表示の判別性低下 → commands 配置推奨の根拠) を更新する
- [ ] 変化なし (= こちらの環境固有の問題) と判明したら、その旨を記録して close する
