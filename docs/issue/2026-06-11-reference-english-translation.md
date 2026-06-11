# reference 本体の英訳ペア化検討

- status: idea
- 起票: 2026-06-11

## 背景 / 問題

表紙 (README) は日英ペア (`README.md` / `README-ja.md`) で英語読者にも届く。
しかし **reference 本体 (`skills/claude-plugin-reference/reference/*.md` + SKILL.md) は
現在日本語のみ**。「表紙は英語なのに本文が読めない」状態で、英語圏ユーザの期待値と
実体がずれる (README.md にこの旨の note は追記済)。

## 提案

reference 本体の英訳ペア化を検討する。論点:

- 翻訳ペア運用 (`*-ja.md` = 正本 / `*.md` = 英訳) を reference にも広げるか
- 広げる場合、`check-outdated-translations` の対象を README / DESIGN に加えて
  `skills/.../reference/*.md` まで拡大 (commit-lag 検出の網を広げる)
- 翻訳メンテコスト (= reference は頻繁に実機検証で更新される) と読者層の
  トレードオフ判断

## 留意

- skills/ は bump-trigger paths に入っているので、英訳追加は version bump を伴う
- 翻訳より「英語を正本にして日本語を従にする」逆転案もありうる (= 公開配布物として
  英語一次のほうが広い читатель に届く) — 方針ごと検討

## TODO

- [ ] 英訳ペア化の是非判断 (コスト vs 読者層)
- [ ] 採用時: `check-outdated-translations` の glob 対象拡大
- [ ] 正本言語 (ja 正本 / en 正本) の方針決定
