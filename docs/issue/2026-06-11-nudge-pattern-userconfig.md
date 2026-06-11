# nudge パターンの userConfig 外部化 + 最小 CI 検討

- status: idea
- 起票: 2026-06-11

## 背景 / 問題

`hooks/plugin-repo-nudge.sh` の発火判定のうち `claude-rules-` prefix マッチは
**kawaz 個人の rule overlay リポ命名規約の焼き込み**。公開配布物として汎用性に欠ける
(= 他ユーザの環境では `claude-rules-*` リポは存在せず、無関係 prefix での false
positive だけが残る)。

## 提案

### (a) nudge パターンの userConfig 外部化

`claude-rules-` 等の判定パターンを plugin の userConfig (= ユーザが設定で上書きできる値)
として外部化し、個人規約の焼き込みを解く。デフォルトは現状維持 (= kawaz 環境で動く)、
他ユーザはパターンを差し替え / 空にして無効化できる形を検討。

### (b) tests のみ回す最小 GitHub Actions

現在 CI/CD は持たない (STRUCTURE.md 方針)。が、`just test` (= nudge 判定の回帰テスト) を
PR / push で回す **最小 GH Actions** を入れると、nudge ロジック改変時の安全網になる。

## 留意

- STRUCTURE.md は明示的に「(CI/CD で release artifact を作る workflow は持たない。
  push = リリース完了)」と書いている。最小 CI の導入はこの方針の **一部見直し**になるので、
  方針変更の是非ごとこの issue で検討する (= 黙って workflow を足さない)。
- `freshness-auto-drive` issue の GH Actions cron 案と CI 基盤を共有できる可能性あり。
- userConfig 外部化は plugin spec (`plugin.json` / settings) での config 受け渡し方法の
  実機検証が前提 (= reference 自身のドッグフーディング題材にもなる)。

## TODO

- [ ] userConfig での nudge パターン外部化の設計 + 実機検証
- [ ] 最小 GH Actions (tests のみ) 導入の是非 (STRUCTURE.md 方針との整合)
- [ ] freshness-auto-drive との CI 基盤共有検討
