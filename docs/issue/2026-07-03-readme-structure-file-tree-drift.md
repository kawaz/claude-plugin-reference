---
title: README / README-ja / STRUCTURE.md のファイルツリーが実体と乖離
status: idea
category: idea
created: 2026-07-03T13:51:26+09:00
last_read:
open_entered:
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: claude-rules-personal
---

# README / README-ja / STRUCTURE.md のファイルツリーが実体と乖離

## 概要

`reference/` 配下の実ファイル数と、`README.md` / `README-ja.md` / `STRUCTURE.md` に記載されたファイルツリーの記載数に乖離が見られる (部外者観測: 実ファイル 7 件 vs ツリー記載 5 件)。`SKILL.md` 自体の内容は最新のように見える。

## 背景

kawaz の個人リポ群を横断監査した際の観測。この観測は部外者 (claude-rules-personal セッション) からのものであり、diff の網羅性や具体的にどのファイルが未記載かの特定は裏取りできていない。ドキュメントのファイルツリー追従の要否・具体的な差分は担当側 (claude-plugin-reference 側) で確認の上で判断してほしい。

出所: 2026-07-03 の個人エコシステム横断監査 (claude-rules-personal セッション発)。

## 受け入れ条件

- [ ] `reference/` 配下の実ファイル一覧と `README.md` / `README-ja.md` / `STRUCTURE.md` のファイルツリー記載を突き合わせ、乖離の有無を確認する
- [ ] 乖離があれば該当ドキュメントを実体に追従させる (または追従不要と判断した理由を記録する)
