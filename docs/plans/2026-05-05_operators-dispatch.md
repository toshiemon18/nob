---
title: Operators ファクトリの dispatch 整理
slug: operators-dispatch
status: done
created: 2026-05-05
updated: 2026-05-05
---

## 目的・背景

`/peer-review` のアーキテクチャ指摘の本筋議論 4/4（最終）。前 3 サイクル (`config-boundaries`, `notes-unification`, `cli-aggregation`) で層境界・Result 統一・CLI 集約・エラー方針を片付けたので、最後に Templates の `Operators.build` の dispatch 表記を整理する。

### 解きたい問題

`lib/nob/templates/operators.rb` のファクトリは `case/when` で 4 つの Operator クラスを 1 行ずつ列挙していた:

```ruby
def self.build(name:, fmt:)
  operator = case name
  when "title" then Title
  when "date" then Date
  when "time" then Time
  when "id" then Id
  else raise UndefinedVariable, "unknown variable: #{name}"
  end
  operator.new(fmt)
end
```

dispatch 表が `case/when` の文法に埋まっていて、name → Class の対応が読み手に届くまでに 1 段挟まる。Operator が増えるほど読みにくさが効いてくる。「対応表」と「対応表を引く処理」を分離して、name → Class の写像をデータとして見せたい。

スコープ外: なし（本サイクルが最後）。完了後 `done` で recap して全 5 サイクルが揃う。

## 設計

### `Operators.build` を Hash registry 経由に置き換える

```ruby
module Operators
  REGISTRY = {
    "title" => Title,
    "date" => Date,
    "time" => Time,
    "id" => Id
  }.freeze

  def self.build(name:, fmt:)
    operator_class = REGISTRY.fetch(name) {
      raise UndefinedVariable, "unknown variable: #{name}"
    }
    operator_class.new(fmt)
  end
end
```

要点:

- **`REGISTRY` をモジュール直下の定数に切り出す**: 「name → Class の対応表」がコードを読まずデータとして一目で分かる
- **`fetch` のブロック形式で UndefinedVariable**: 既存の `case/when` の `else` 節と同じ振る舞い（unknown name で `UndefinedVariable`）を 1 行で表現
- **明示的 dispatch を選ぶ**: `const_get` 等の動的解決は採らない（メモリ `feedback_metaprogramming_caution.md` 「Factory / dispatch は明示的な Hash や case/when を第一候補に」に基づく判断）。Operator 追加時に `REGISTRY` に 1 行足す手間は、対応表が明示的に並ぶ可読性の対価として受け入れる

ADR 0001 §C は現行の文言（「ファクトリ内部の dispatch は本 ADR で詳細を決めない（case/when でも内部 Hash でも実装次第）」「変数追加は Operator クラスを足す + ファクトリにエントリを 1 つ足す」）が Hash registry 実装と既に整合しているため、補追は行わない。

## TODO（TDDタスク分解）

- [x] **T1**: `Replace Operators dispatch with Hash-registry lookup`
    - Red: `spec/nob/templates/operators_spec.rb` に「name が大文字混じり (`"Title"`) → `UndefinedVariable`」example を追加（既存実装でも green な追加保証 example）
    - Green: `lib/nob/templates/operators.rb` を Hash `REGISTRY` 経由の `fetch` 式に書き換える（設計通り）
    - 完了基準: `bundle exec rake` が green、既存 6 example + 新 1 example pass、`grep "case " lib/nob/templates/operators.rb` で 0 件

## レビューフィードバック

### peer-review 1 回目（2026-05-05, plan モード）

const_get 動的解決を前提とした初版 plan に対するレビュー（Critical 0 / Important 2 / Nice-to-have 3）を受け、いったんすべての指摘に「対応済」を書き入れた。その後 Refine フェーズで「明示的な dispatch を優先する」方針（メモリ `feedback_metaprogramming_caution.md`）に切り替えて Hash registry 実装に差し替えたため、レビュー指摘の前提となる const_get 設計そのものが消えた。autoload 例外の扱い・`Class` 型ガード・動的 `Foo` 定義 spec のクリーンアップなど、const_get 固有の論点はいずれも Hash registry 実装では発生しないため、本サイクルでは追加対応は行わない。

## 実装と計画の差分（recap）

### 実装ハイライト

- 8c2d4fa `Replace Operators dispatch with const_get-based lookup`: 初版 plan 通り `const_get` ベースの動的解決で実装。`CLASS_NAME_PATTERN` / `Class` 型ガード / `Base` サブクラスガードを乗せた lookup を private で実装し、動的 `Foo < Base` 定義 spec で「`operators.rb` を編集せず Operator を追加できる」契約を spec から固定
- 362398e `Refine: switch Operators dispatch to explicit Hash registry`: メモリ `feedback_metaprogramming_caution.md` に基づき、明示的な Hash `REGISTRY` + `fetch` 式に差し替え。動的 `Foo` 定義 spec は「実装そのものを再記述する spec を書かない」（メモリ `feedback_no_implementation_mirror_specs.md`）にも抵触するため削除

### 計画との差分

- **dispatch 実装方針の転換**: 当初は const_get 動的解決を採用し「Operator 追加が 1 ファイルで済む契約」を成果物に掲げていたが、メモリで明示された「メタプロチックな dispatch を避ける」原則と照らして Refine で Hash registry に切り替えた。結果として「1 ファイル契約」は獲得せず、Operator 追加時は依然として `REGISTRY` に entry を追加する必要がある（操作するファイルは従来と同じ 2 つ）。本サイクルの実成果は「`case/when` で散らばっていた dispatch 表を `REGISTRY` 定数に集約し、name → Class の対応をデータとして可視化した」可読性 refactor に縮小した
- **ADR 0001 §C 補追タスクの取り下げ**: 当初 plan の T2 で予定していた ADR §C 補追は、Hash registry 実装が ADR §C の現行文言（「dispatch 詳細は決めない」「entry 1 つ追加」）と既に整合するため不要と判断し、タスクごと削除した
- **plan 設計セクションの整合性**: const_get 前提の設計記述（autoload 発火 / 例外の扱い / 文字種パターン / `Class` 型 + `Base` サブクラスガード 等）は Hash registry 実装では出番が無いため、本 recap と同時に Hash registry 版へ書き換えた

### サイクル全体の総括

`/peer-review` のアーキテクチャ指摘 4 件に対応する 5 サイクル（`config-boundaries` / `notes-unification` / `cli-aggregation` / `cleanup-misc` / `operators-dispatch`）が完了。最後の本サイクルは当初の野心（dispatch 動的化 + 1 ファイル契約）を Refine で縮小し、地味な可読性 refactor に着地した。peer-review 由来の宿題はこれで解消。
