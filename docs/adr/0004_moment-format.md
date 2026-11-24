---
title: 日時の書式に moment 形式も受け付ける
number: 0004
status: accepted
date: 2026-10-27
---

## コンテキスト

design.md では、テンプレートの `{{date:fmt}}` / `{{time:fmt}}` と `[dailyNote].fileNameFormat` の書式を strftime 形式と決めていた。

一方、Obsidian のデイリーノート機能は moment.js の書式を使う。実際の vault でも、テンプレートは `{{date:YYYY-MM-DD}}T{{time:HH:mm}}`、ファイル名の書式は `YYYY/MM/YYYY-MM-DD` で書いている。nob がこのテンプレートを strftime として読むと、`YYYY-MM-DD` という文字列がエラーにならずにそのまま書き込まれる。

Neovim プラグインで dotfiles の自作プラグイン（デイリーノートを作る）を置き換えるには、nob が Obsidian と同じテンプレートを読める必要がある（2026-10-26 の grilling、Q9・Q12・Q13）。

検討した案:

- **nob 用のテンプレートを strftime で別に書く**: 実装は要らない。ただ、同じ内容のテンプレートを 2 つ持ち、片方を直したらもう片方も直す必要がある
- **moment 形式も受け付ける**: 「既存の vault をそのまま管理対象にする」という nob の目標に沿う

## 決定

テンプレートの `date` / `time` と `[dailyNote].fileNameFormat` で、moment 形式も受け付ける。

- 書式に `%` を含めば strftime、含まなければ moment として読む。既存の strftime の書式はすべて `%` を含むので、そのまま動く
- moment のトークンは、よく使う `YYYY` `YY` `MM` `M` `DD` `D` `HH` `H` `mm` `ss` と、エスケープの `[...]` だけに対応する
- 英字は同じ文字の連なりごとに区切って照合する。`MMMM`（moment では月名）を `MM` 2 つとは読まない
- 対応しないトークンはエラーにする。黙って文字どおりに出力すると、きっかけになった問題と同じく、壊れたノートができても気づけないため
- moment の書式は生成時に strftime の書式に変換する（`Nob::TimeFormat`）。テンプレートでは Parser の段階で検証が終わるので、ADR 0001 の「構文エラーと未定義変数は Parser で全部検出する」を保てる
- `.obsidian/daily-notes.json` は読まない。Obsidian の内部ファイルに依存せず、設定は config.toml に書く

## 帰結

- Obsidian と nob で、同じテンプレートとファイル名の書式を使える
- `%` を含まない strftime の書式（`{{date:Y}}` のように、文字をそのまま出す書式）は、moment として読まれてエラーになる。今まではその文字がそのまま出力されていた
- `[...]` の中に `%` を書くと、書式全体が strftime として読まれる。`%` を含むかどうかだけで判定するため
- 曜日や月名（`dddd`、`MMMM`）が必要になったら、トークンを足す。ロケールの扱いを決める必要がある
