---
title: /model ピッカーカスタマイズ env 群の cli.md 収載検討
status: open
category: idea
created: 2026-07-13T11:01:53+09:00
last_read:
open_entered: 2026-07-13T11:01:53+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 自リポ TODO
---

# /model ピッカーカスタマイズ env 群の cli.md 収載検討

## 概要

`/model` ピッカーのカスタマイズに関わる環境変数群 (`ANTHROPIC_CUSTOM_MODEL_OPTION*`,
`ANTHROPIC_DEFAULT_*_MODEL`, settings の `availableModels` 系) を `cli.md` に
収載するか検討する。

## 背景

v2.1.207 バイナリの strings で以下を確認 (バイナリ文字列からの発見、実機でのピッカー
表示確認は未実施):

- `ANTHROPIC_CUSTOM_MODEL_OPTION` / `_NAME` / `_DESCRIPTION` / `_SUPPORTED_CAPABILITIES`
  — カスタムエントリを 1 個追加できる模様
- `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL`
  — 標準エントリの実体差し替え。`FABLE` のみ `_NAME` / `_DESCRIPTION` も存在
- settings の `availableModels` / `enforceAvailableModels` / `modelOverrides`
  — allowlist、managed settings 想定

用途実例: CLIProxyAPI (ローカルプロキシ) 経由で外部モデルを `/model` に出す運用が
個人環境の shell rc 設定で実例として存在する。

## 受け入れ条件

- [ ] 各 env var / settings フィールドの実機挙動を検証 (TUI でのピッカー表示確認)
- [ ] 検証結果をもとに `cli.md` への収載要否・書き方を判断
- [ ] 収載する場合は [未検証] マーカーで開始し、検証が進んだら確度を上げる
