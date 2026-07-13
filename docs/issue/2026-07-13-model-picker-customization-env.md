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

### gateway model discovery 経路 (実機検証済み、より強力)

`CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1` + `ANTHROPIC_BASE_URL` + firstParty
認証の組合せで、base URL の `/v1/models?limit=1000` を fetch し、返ってきた全モデルを
"From gateway" として `/model` ピッカーに自動追加する経路を実機確認した。

- cache: `<config-dir>/cache/gateway-models.json`
- v2.1.207 で `-p` 実行により cache 生成を実機確認 (30 モデル)
- ピッカー表示自体の目視確認は未実施 (TUI)
- 関連バイナリ関数: `$5l` (gate 条件) / `q5l` (fetch) / `mkr` (エントリ供給) /
  `jeh` (picker 構築。`ANTHROPIC_CUSTOM_MODEL_OPTION` は単数のみ、
  `availableModels` 由来エントリ追加経路もあり)

cli.md 収載時はこの gateway discovery を主経路として書くのが良さそう
(`ANTHROPIC_CUSTOM_MODEL_OPTION*` 系は単数枠の副経路として位置づけ)。

## 受け入れ条件

- [ ] 各 env var / settings フィールドの実機挙動を検証 (TUI でのピッカー表示確認)
- [ ] 検証結果をもとに `cli.md` への収載要否・書き方を判断
- [ ] 収載する場合は [未検証] マーカーで開始し、検証が進んだら確度を上げる
