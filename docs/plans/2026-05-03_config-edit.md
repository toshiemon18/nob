---
title: nob config -e でエディタから config を編集する
slug: config-edit
status: done
created: 2026-05-03
updated: 2026-05-03
---

## 目的・背景

design.md の Config 仕様で唯一未実装な `nob config -e` を追加する。

- vault パスや今後追加されるテンプレート／デイリーノート設定を user が編集する経路として必要
- `Config.ensure_exists` は実装済みなので、未生成でも `-e` で初回生成 → 編集の流れに乗る

スコープは `-e` のみ。`nob config`（引数なし）でのパス表示やスキーマバリデーションは別 plan に切る。

## 設計

### モジュール構成

新規:
- `Nob::Config::Editor` — エディタコマンドの解決と起動を担うサービスオブジェクト
  - `Editor.resolve(env: ENV)` → エディタコマンド文字列を返す純粋関数
  - `Editor.open(path:, env: ENV, runner: Kernel)` → ensure_exists 済み前提で起動。失敗時は例外

CLI:
- `Nob::Cli#config` Thor サブコマンド + `-e/--edit` オプション
  - `-e` 指定時のみエディタ起動。`-e` なしの場合は `warn "Usage: nob config -e"` + `exit 1`
  - `Config.ensure_exists` を呼んでから `Editor.open` に委譲

### 公開 API

```ruby
Nob::Config::Editor.resolve(env: ENV)     # => "vi" / ENV["EDITOR"]
Nob::Config::Editor.open(path:, env: ENV, runner: Kernel)  # 成功時は単に return / raise Nob::Error
```

`runner` は `system` メソッドを持つオブジェクト。テストで差し替え可能。

### エディタ解決ルール

1. `env["EDITOR"]` が非空文字列ならそれを使う（前後空白は strip）
2. 空 / nil / 空白のみ → デフォルト `"vi"`

`EDITOR` には `code -w` のように引数付きが入りうるため、shell 形式 `runner.system("#{editor} #{Shellwords.escape(path)}")` で呼ぶ。`vi` 等は tty を要求するが、`Kernel.system` は親プロセスの stdin/stdout/stderr (tty) をそのまま継承するので問題ない。

### エッジケース・失敗時の振る舞い

- `system` が `nil`（コマンド起動失敗） → `Nob::Error, "failed to launch editor: <cmd>"`
- `system` が `false`（exit non-zero） → `Nob::Error, "editor exited with non-zero status: <cmd>"`
- `Config.ensure_exists` が失敗（権限など） → そのまま例外を伝播。CLI 層で rescue して `warn + exit 1`

### 設計判断

- `Editor` を Config の名前空間配下に置く: vault 取得などの「設定値の読み出し」と「設定値の編集経路」は別関心だが、寿命と凝集度が近い
- `runner` 注入: Kernel.system のスタブ化はモンキーパッチが必要で test の副作用が残りやすいので、引数で差し込めるようにする
- shell 形式採用: `EDITOR=code -w` のような引数付き設定を受け入れるため。引数なしのバイナリ名なら配列形式と同等

## TODO（TDDタスク分解）

- [x] **T1**: `Add Config::Editor.resolve to pick $EDITOR or fallback to vi`
    - Red: `spec/nob/config/editor_spec.rb` で `resolve(env: {})` が `"vi"`、`resolve(env: {"EDITOR" => "nvim"})` が `"nvim"`、空白のみは `"vi"`、前後空白は strip されることを assert
    - Green: `lib/nob/config/editor.rb` に `Editor.resolve(env:)` を実装

- [x] **T2**: `Add Config::Editor.open to launch editor with injected runner`
    - Red: 同 spec で fake runner（呼ばれた引数を記録）を渡し、`open(path:, env:, runner:)` に渡される command 文字列が editor 名と path 由来の文字列を両方含むこと（部分一致で検証、`Shellwords.escape` 実装に依存しない）、runner が `nil` を返したら `Nob::Error /failed to launch/`、`false` を返したら `Nob::Error /non-zero/` を投げることを assert
    - Green: `Editor.open` を実装

- [x] **T3**: `Wire nob config -e command in CLI`
    - Red: `spec/nob/cli_spec.rb` に `nob config -e` 起動で `Config.ensure_exists` と `Editor.open` がこの順で呼ばれることを assert（両方 stub）
    - Green: `Cli#config` サブコマンドと `-e` オプションを追加。`-e` なしの場合は `warn` + `exit 1` で usage 案内

## レビューフィードバック

### 2026-05-03 code レビュー (peer-review)

Critical: なし / Important: 2 / Nice-to-have: 4

#### Critical
- なし

#### Important
- shell 形式採用により `EDITOR='evil; rm -rf ~'` のような環境変数で任意コマンド実行になりうる旨を README/設計に明示すべき → 対応済 (c91860e: design.md に信頼前提を追記)
- CLI spec で `Editor.open` が例外を投げた場合の rescue 経路がカバーされていない（happy path と `-e` なしのみ） → 対応済 (a105b22: rescue 経路の spec を追加)

#### Nice-to-have
- POSIX 慣習では `VISUAL` を `EDITOR` より優先する（将来拡張余地として TODO コメント） → 見送り（必要になった時点で対応すれば十分、今は YAGNI）
- 例外メッセージで `cmd` をそのまま使うとエスケープ済み path が読みづらい。`editor` と `path` を分けて表示する案 → 対応済 (2c58079: Editor.open のメッセージを editor/path 分離形式に)
- editor_spec の fake runner はクラス定義より `Struct`/`Proc` の方が短い → 見送り（既存の形で十分明快、好みの範疇）
- `nob config -e` の usage 文言を `nob help config` 出力と整合させる → 見送り（既存 `desc` で `nob help config` 出力は十分）

#### Out of scope
- パス表示や schema validation は別 plan として明記済み
- `Config.ensure_exists` の権限失敗ケースは Config 側の責務

### 2026-05-03 plan レビュー (peer-review)

Critical: なし / Important: 3 / Nice-to-have: 3

反映済み (Important):
- shell 形式と配列形式の混在記述 → 配列形式の言及を削除し shell 形式採用に一本化
- T2 のテスト assert 文字列等価 → 部分一致（editor 名と path を include）で検証する方針に変更
- `nob config`（引数なし）の振る舞い → `warn + exit 1` に確定

未反映 (Nice-to-have / 別 plan):
- `EDITOR` キー欠落の `nil` ケース明示: T1 の Red で空文字列ケースに含意される（`env: {}` で nil → fallback）ので追加せず
- `Editor.open` の戻り値仕様: 成功時は単純に return（true 相当）。CLI 側で使わないため戻り値仕様は記述削除済
- tty 引き継ぎの言及: 設計セクションに追記済

## 実装と計画の差分（recap）

### 計画通りに実装できた点
- 3 task = 3 commit の対応関係が崩れずに進行した
- `Editor.resolve` / `Editor.open` の責務分離と runner 注入によりテスト容易性は計画どおり
- shell 形式 vs 配列形式の判断は plan レビュー段階で確定したのでブレなし

### 計画から逸脱した点
- なし（Implement 中の設計変更は発生していない）

### Refine で追加された変更（plan 範囲内）
- design.md に EDITOR 信頼前提を追記（Important 指摘への対応、c91860e）
- CLI rescue 経路のテスト追加（Important 指摘への対応、a105b22）
- 例外メッセージの可読性改善（Nice-to-have 採用、2c58079）

### 学び・後続 plan への送り
- POSIX `VISUAL` 優先は気が向いた時に別 plan 化してもよい（現時点では YAGNI）
- `nob config`（引数なし）でのパス表示や schema validation は別 plan 候補
