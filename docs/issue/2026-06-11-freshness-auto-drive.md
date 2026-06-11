# 鮮度チェックの自動駆動 (pull 型 → push 型)

- status: idea
- 起票: 2026-06-11

## 背景 / 問題

`check-freshness` recipe は SKILL.md の最終検証スタンプと「現行 Claude Code バージョン」
(ローカル `claude --version` + npm registry latest) を semver 比較し、陳腐化を検出する。
しかし **発火トリガが手動プル型** = 「kawaz が思い出して `just check-freshness` を叩く」
ことに依存している。これは構造的弱点で、忘れると stale が放置される。

## 提案

鮮度チェックを **自動駆動 (push 型)** にする。候補:

1. scheduled agent / launchd で週次に `just check-freshness` を回す
2. GitHub Actions の `schedule` (cron) で週次 check → stale なら自動で
   `docs/issue/YYYY-MM-DD-stale-vX.Y.Z.md` を起票 (or 既存 issue を更新)
3. 上記いずれかで stale 検出時に通知 (= kawaz に push)

## 留意

- STRUCTURE.md は現状「CI/CD で release artifact を作る workflow は持たない」方針。
  GH Actions 案を採るならこの方針の一部見直しになる (= `nudge-pattern-userconfig` issue の
  「tests のみ回す最小 GH Actions」と統合検討してもよい)。
- npm latest 比較は既に `check-freshness` に実装済 (= ネットワーク失敗時は warn skip)。
  自動駆動側はこの exit code / 出力を解釈すればよい。

## TODO

- [ ] 駆動方式の選定 (launchd / scheduled agent / GH Actions cron)
- [ ] stale 時の起票・通知フロー設計
- [ ] STRUCTURE.md の「CI/CD なし」方針との整合判断
