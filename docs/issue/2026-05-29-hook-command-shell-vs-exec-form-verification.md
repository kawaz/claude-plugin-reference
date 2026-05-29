# hook command の shell-form / exec-form での `#` (= bash comment) 扱い実機検証

- Date: 2026-05-29
- Status: 実機検証 TODO (= reference/hooks.md §9.0 の `[未検証]` 解消用)

## 背景

`reference/hooks.md` §9.0 で **plugin 識別子マーカー** ベストプラクティスを記述:

```json
{
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/push-guard.sh #push-guard"
}
```

= claude runtime の hook error 表示で展開前 command string が literal で出る (= どの plugin か identify 不能) 問題への workaround。`#` 以降を bash comment 扱いにして、error 表示にも plugin 名が見えるようにする。

ただし執筆時点で **shell-form vs exec-form** で挙動が違うはず、と仮定で書いた:
- **shell-form** (= `command: "..."` のみ、`args` なし) → shell が parse、`#` 以降は comment 扱い、script 実行に影響なし
- **exec-form** (= `command: "..."` + `args: []` 指定) → shell を介さず直接 exec、`#` が **literal の引数として渡される** 可能性

これは公式 docs では明示されていない (= shell-form / exec-form の区別自体が docs に明確記述あるか怪しい)。実機検証が必要。

## 検証したいこと

### 1. shell-form の `#` 扱い

設定例:
```json
{ "type": "command", "command": "echo hello #marker" }
```

期待: `echo hello` が実行され `#marker` は comment 扱い (= script に影響なし)

### 2. exec-form の `#` 扱い

設定例:
```json
{ "type": "command", "command": "echo", "args": ["hello", "#marker"] }
```

期待: `echo hello #marker` が literal で実行され `#marker` が出力に含まれる (= bash 経由でないので comment にならない)

### 3. claude runtime の error 表示で `#marker` が見えるか

設定例 (= PreToolUse で意図的に block する hook):
```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        { "type": "command", "command": "exit 2 #test-marker" }
      ]
    }
  ]
}
```

期待: Bash tool 実行時に block され、error message に `[exit 2 #test-marker]` literal で `#test-marker` が見える

## 検証手順案

1. テスト用 plugin (= `~/.local/share/repos/github.com/kawaz/test-hook-marker/` 等) を作る
2. `hooks/hooks.json` に上記 3 パターンの hook を定義
3. plugin install して各 hook を発火
4. error message / hook output を確認

## 確認後の reference 更新

検証結果に応じて `reference/hooks.md` §9.0 の以下ラベルを格上げ:

- `bash shell-form では '#' 以降が comment 扱い = script 実行に影響しない [実機検証推奨]`
- → `[実機検証済]` に格上げ + 結果記述

exec-form での挙動が確認できれば、`exec-form では別経路 (= env var inject 等) [未検証]` も格上げ。

## 関連

- `reference/hooks.md` §9.0 (= plugin 識別子マーカーベストプラクティス、本 issue 解消で確証アップ)
- `reference/hooks.md` §4 (= hook command の type 種別、shell-form / exec-form の区別を §4 にも追記する候補)
