# 配布編 — plugin.json / marketplace.json / 配布フロー

kawaz/* で 1 plugin 配布する時の 2 manifest 最小テンプレ + 配布手順 + 参考 URL。詳細 spec は出典先参照。

## plugin.json (`.claude-plugin/plugin.json`)

```json
{
  "name": "<plugin-name>",
  "description": "<short description>",
  "version": "<semver>",
  "author": { "name": "kawaz" },
  "license": "MIT",
  "repository": "https://github.com/kawaz/<repo>"
}
```

触るのは `name` / `description` / `version` / `repository` の 4 field。残り固定。[spec 明示]

## marketplace.json (`.claude-plugin/marketplace.json`)

```json
{
  "name": "<plugin-name>",
  "owner": { "name": "kawaz" },
  "metadata": {
    "description": "<short description>",
    "version": "<semver>",
    "license": "MIT"
  },
  "plugins": [
    {
      "name": "<plugin-name>",
      "description": "<plugin description>",
      "source": "./"
    }
  ]
}
```

1 plugin 配布なら `source: "./"` 固定 (= marketplace.json 自身がいる plugin root を指す)。[spec 明示]

`metadata.license` field は `claude plugin validate .` で「Unknown field 'license'」warning が出るが、公式 spec 上は OK な field (= validator の認識ズレ、無視可)。[実機検証済 / 既知 warning]

## ユーザ install 手順 (README に書く 2 コマンド)

```
claude plugin marketplace add kawaz/<repo>
claude plugin install <plugin-name>@<plugin-name>
```

具体例 (cmux-msg):

```
claude plugin marketplace add kawaz/claude-cmux-msg
claude plugin install cmux-msg@cmux-msg
```

## ユーザ update 手順

```
claude plugin marketplace update <plugin-name>
claude plugin update <plugin-name>@<plugin-name>
```

## 開発者の version bump + push (kawaz の運用)

`just push` task に集約:
1. `just bump-version` で 3 ファイル (`plugin.json` + `marketplace.json.metadata.version` + `package.json`) を semver 同期 bump
2. `jj git push --bookmark main` で publish
3. `claude plugin marketplace update <name>` で marketplace 側の cache 更新
4. `claude plugin update <plugin>@<market>` で plugin 本体 cache 更新

push 後の `/reload-plugins` (= ユーザ側 interactive command) で session 内 cache を切り替えるまで、既存 session の Skill / hook 解決先は古い cache を見続ける。[実機検証済]

## version 管理

- `version` field を plugin.json or `marketplace.json.plugins[].version` に設定済 → その文字列に pin、ユーザは version 変更時のみ更新通知 [spec 明示]
- 未設定 → git commit SHA fallback (= 毎 commit が新 version 扱い) [spec 明示]

kawaz は前者 (= 明示 version) で運用。

## 参考 URL (出典)

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins.md)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces.md)
- [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins.md)
