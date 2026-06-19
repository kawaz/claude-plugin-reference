---
title: user invocable skill の配置・命名・frontmatter audience の整理 (フラグ起票)
status: resolved
category: idea
created: 2026-06-19T17:09:32+09:00
last_read:
open_entered:
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-06-19T17:58:44+09:00
discard_reason:
pending_reason:
close_reason: ["reference v0.2.18 で 3 観点 (補完表示 / commands+一般語 / audience 区別) を反映 + 他 plugin 言及鮮度更新 + permission ガード対策"]
blocked_by:
origin: claude-local-issue plugin 開発時の dogfood (= 部外者からのフラグ起票)
---

# user invocable skill の配置・命名・frontmatter audience の整理 (フラグ起票)

claude-local-issue plugin を開発する過程で、reference 記述に従って判断したら kawaz の実機観察と齟齬が出た箇所が複数あった。reference 本体への取り込み判断は当事者 (= reference リポ管理側) に委ねる。フラグ止まりの起票。

## 概要

reference の現状記述に対して、実機で観察された補完挙動・audience 区別の実態が一致しない箇所が複数ある。断定せず、reference 側で検証・判断してほしい。

## 背景

### 観察した実機挙動 (一次資料、v2.1.183)

1. **`commands/<name>.md` 配置 (一般語名)**: 補完表示が `/local-issue:list (local-issue) <description>` で **full namespace**
2. **`skills/<name>/SKILL.md` 配置 (一般語名)**: 補完表示が `/write (local-issue) <description>` で **短縮形**
3. **fuzzy match**: ユーザが `/list` のような短縮形を打っても `/local-issue:list` `/cmux-msg:list` 等が候補に出る (= 短縮形を直打ちしても自前 skill に到達できる)
4. **`argument-hint` のグレー hint**: `/codex:setup ` の末尾スペース後にグレーで `[--enable-review-gate|--disable-review-gate]` が表示、もう 1 文字打つと消える

検証元環境: claude-local-issue v0.1.1 (kawaz が /reload-plugins した直後の状態)

## 受け入れ条件

- [x] (1) § 1 補完表示ルールの判定軸について、実機差分が確認され spec or 実装どちらが正か判断済み
- [x] (2) § 2 役割マッピング / § 4 命名規約に「commands + 一般語」選択肢の追加要否を判断済み
- [x] (3) § 3 frontmatter 表の audience 区別明文化の要否を判断済み

## reference 側で再考の余地があるかもしれない箇所 (= 断定しない、当事者判断)

### (1) §1 補完表示ルールの判定軸

reference §1 補完表示ルールは「name が plugin を prefix に持つときだけ短縮表示」とあるが、実機では `skills/<name>/SKILL.md` 配置の skill が **prefix なしでも短縮表示**される観察があった (= write / update が `/write` `/update` で出る)。表示判定が配置 (commands vs skills) で分岐している可能性があり、検証 / spec の再確認の余地。

### (2) §2 役割マッピング / §4 命名規約推奨に「commands + 一般語」選択肢の追加

現状の §2 / §4 は「短縮形を狙うなら plugin 名 prefix で揃える (cmux-msg-list 方式)」を推奨形に書いているが、kawaz の観察と提案:

- **ユーザ invocable な skill は全部 `commands/` に一般語 (= 短縮形) で置く** が実用解
- namespace 衝突は補完 fuzzy match で吸収される (= 実害なし)
- 実行時の解決は `/<plugin>:<name>` full namespace で明確
- = この選択肢が現状の reference 推奨形に欠落している

「もう 1 つの実用形」として §2 役割マッピングか §4 含意に追記する余地があるかもしれない。

### (3) §3 frontmatter 表に audience 区別を明文化する余地

`description` と `argument-hint` は **別 audience を持つことが実機補完挙動で確認できる**:

| field | audience | 用途 |
|---|---|---|
| `description` | **AI** | skill 発見 / 自動 invoke trigger / listing 常時 context |
| `argument-hint` | **ユーザ** | 補完中スペース後にグレーで `[...]` 表示、もう 1 文字打つと消える |

この区別が §3 frontmatter 表では「listing に表示」「autocomplete hint」程度の機械的記述に留まっており、**audience が違うことを明示**する余地。

実用含意 (= plugin 設計者の混同を防ぐ):

- description は短く保つ (長文は listing context を圧迫しつつユーザにも刺さらない)
- ユーザ向け使い方は **argument-hint + 本文 + plugin root SKILL.md** に分離する設計が正解
- description で「AI 向け説明 + ユーザ向け説明」を混在させない

## 起票元の経緯 (補足、自分の読み違い記録)

claude-local-issue plugin を作る過程で:

1. 私 (起票元 session = local-issue 開発側) が当初「skills/ に統一して短縮形 (`/list` `/write` 等) で打てる方が UX 良い」と提案
2. 私自身が同セッション内で「短縮形は他 plugin と namespace 衝突する」と却下 (= reference §4 含意「短縮形を狙うなら plugin 名 prefix」依拠)
3. kawaz が「fuzzy match で短縮形でも自前 skill が候補に出る、衝突は補完ノイズだけで実害なし」を実機で示す
4. kawaz が「ユーザ invocable は全部 commands に短縮形 (一般語) で置くべき、reference の prac は間違ってる」と指摘
5. = reference の現状 prac (= 短縮形を狙うなら plugin 名 prefix) に従うと skills 配置 + plugin prefix 命名に寄りすぎる、「commands + 一般語」も対等な選択肢

私の reference 読解依拠が偏っていた可能性 + reference 本体の prac 記述が片方に振れている可能性、両方ありうる。reference 側で判断してほしい。

## 当事者判断に委ねる点

- (1) は実機差分の確認、spec or 実装どちらが正かは reference 側の検証で
- (2) は「もう 1 つの実用形」として併記するか、現状推奨形を維持するかは reference 側の方針判断
- (3) は audience 区別の明文化が plugin 設計者に効くかの判断
- 採用しない判断も含めて、reference リポの方針を尊重

## 関連

- 起票元 plugin: claude-local-issue v0.1.1 (= 開発過程の dogfood)
- 起票元 commit (= 補完観察の一次資料): claude-local-issue acfd514 直後
- 関連 reference 章: skills.md §1 §3、commands.md §1 §2 §4
