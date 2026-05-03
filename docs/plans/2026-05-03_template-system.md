---
title: テンプレートシステム — Parser + Renderer + Operators
slug: template-system
status: done
created: 2026-05-03
updated: 2026-05-03
---

## 目的・背景

ノート作成系コマンド（`create`, `daily`, 将来の zettel 等）が共通で使えるテンプレートエンジンを作る。本 plan では **テンプレート文字列 → 展開済み文字列** の変換を担う `Nob::Templates` モジュール一式を実装する。

設計方針は `docs/adr/0001_template-system.md` で確定済み（accepted）。本 plan はその実装計画。

スコープ:

- Parser（StringScanner ベース）
- Renderer（トークン列の評価）
- Operators ファクトリ + 4 オペレータクラス（Title / Date / Time / Id）
- 例外クラス 2 つ（`UndefinedVariable`, `ParseError`）

スコープ外（明示）:

- `create` コマンドの template 対応 → 別 plan
- `daily` コマンド → 別 plan
- config への `[create] template` のような機能別 config キーの追加 → 各 caller plan で扱う
- design.md の `YYYY/MM/DD` 表記の更新 → 本 plan 完了後に別タスク

## 設計

ADR を正とする。本セクションでは ADR で未確定だった「実装上の取り決め」だけを補足する。

### モジュール構成

```
lib/nob/templates/
  parser.rb               # Nob::Templates::Parser
  renderer.rb             # Nob::Templates::Renderer
  operators.rb            # Nob::Templates::Operators (ファクトリ関数 + dispatch)
  operators/
    title.rb              # Nob::Templates::Operators::Title
    date.rb
    time.rb
    id.rb
lib/nob/templates.rb      # 例外 (UndefinedVariable, ParseError) + Token / Literal / Variable

spec/nob/templates/
  parser_spec.rb
  renderer_spec.rb
  operators_spec.rb
  operators/
    title_spec.rb
    date_spec.rb
    time_spec.rb
    id_spec.rb
```

注:

- `lib/nob/templates.rb` に例外と Token 定義を置く理由: いずれも特定クラスに属さない概念で、Parser/Renderer/Operators 全部から参照される。Zeitwerk が `Nob::Templates` 名前空間を解決する経路になるので自然
- `Token` は `Module.new` した空モジュール、`Literal` / `Variable` は Struct で作ってこの module を `include`。型タグとして機能させる

### Operators.build の dispatch 実装

ADR では「内部実装は本 ADR で決めない」と書いた。本 plan では **case/when** で実装する:

```ruby
module Nob::Templates::Operators
  def self.build(name:, fmt:)
    klass = case name
            when "title" then Title
            when "date"  then Date
            when "time"  then Time
            when "id"    then Id
            else raise UndefinedVariable, "unknown variable: #{name}"
            end
    klass.new(fmt)
  end
end
```

理由:

- Hash + lambda よりも 1 ブランチが見やすい
- Operator クラス追加時の編集ポイントは「ファクトリの case/when に 1 行 + Operator クラス追加」だけ
- Renderer / Parser から見えるのは `Operators.build` の signature のみ。dispatch を後で Hash に変えても外には影響しない

### `}}` 単独リテラルの扱い

`}}` が `{{` を伴わずに単独で出現した場合は **そのままリテラル文字列**として扱う。閉じる対象がないので構文エラーにはしない。

```
"hello }} world"
  → [Literal("hello }} world")]
```

実装上は Parser の literal 蓄積ループが `{{` 以外を全部リテラルに流すだけで自然に成立する。Parser 最小実装 (T6) の段階でこの規則を固定する。

### Parser のメッセージ書式

例外メッセージは ADR の例に揃える:

```
UndefinedVariable: unknown variable: {{ foo }} (line 3)
UndefinedVariable: title does not accept format: {{ title : %Y }} (line 1)
ParseError      : unexpected '{{' inside variable (line 5)
ParseError      : unterminated variable (line 1)
ParseError      : empty variable (line 1)
```

- トークン全体（`{{ ... }}` 形式）を含める
- 行番号は **変数開始 `{{` の行**を採用（unterminated は開始行を出すのが探しやすい）
- 行番号は 1-origin

### Operator のエラーメッセージ書式

Operator は **トークン位置や本文を知らない** ので、自身が原因のメッセージだけを返す:

```ruby
# Operators::Title#initialize
raise UndefinedVariable, "title does not accept format: #{fmt}" unless fmt.nil?
```

Parser 側がこれを catch して、**Operator のメッセージ + トークン全体 + 行番号** を組み合わせた新しい例外を作り直す:

```ruby
rescue UndefinedVariable => e
  raise UndefinedVariable, "#{e.message}: #{token_text} (line #{start_line})"
```

- `e.message` は Operator が組み立てた診断（例: `title does not accept format: %Y`）
- `token_text` は Parser が走査中に保持する **元の `{{...}}` 全体**（空白そのまま）
- 元の例外は cause として保持しない（メッセージだけ使い、Ruby の例外連鎖機能には依存しない）

これにより T10 で書く spec は次の形が確定する:

```ruby
expect { Parser.parse("a\nb {{ title : %Y }}") }.to raise_error(
  UndefinedVariable,
  "title does not accept format: %Y: {{ title : %Y }} (line 2)"
)
```

未知 name の場合も同じ rewrap 経路を通る:

```ruby
# Operators.build が "unknown variable: foo" を投げ、
# Parser が catch して以下に作り直す:
"unknown variable: foo: {{ foo }} (line 1)"
```

### Token の中身

ADR §B 通り Struct で実装する:

```ruby
module Nob::Templates
  Token = Module.new

  Literal  = Struct.new(:text)     { include Token }
  Variable = Struct.new(:operator) { include Token }
end
```

- Struct の `==` は値比較で、`Variable#operator` 同士の比較は Operator 側の `==`（`Operators::Base` で実装）に委譲される。Base の `==` がクラス + fmt で判定するので spec の `expect(tokens).to eq(...)` は安定する
- T1 で Struct 実装の `==` 挙動を spec で固定する。万が一実装中に問題が出たら明示クラスに切り替える（後出しの判断）

### Operator の `==` と `Operators::Base`

各オペレータインスタンスを spec で `eq` 比較できるようにするため、`==` / `hash` / `attr_reader :fmt` を共通化する基底クラス `Operators::Base` を導入する:

```ruby
module Nob::Templates
  module Operators
    class Base
      attr_reader :fmt
      def initialize(fmt) = @fmt = fmt
      def ==(o) = o.is_a?(self.class) && o.fmt == fmt
      def hash = [self.class, fmt].hash
    end
  end
end
```

各 Operator は `Base` を継承し、必要なら `initialize` を override して fmt の検証を行う。

**ADR §C/§D との整合**: ADR で「Operator は Renderer/Parser のクラスを参照しない」と定めた依存方向は維持される。`Base` は Operators 名前空間内に閉じており、Renderer/Parser を参照しない。本 plan で導入する補助クラスであり、ADR の変更は不要。

### `now:` の型は実行時チェックしない

ADR §G の方針通り、Renderer / Parser / Operator は **`now:` が `Time` であることを前提とし、明示的な型チェックを行わない**。`Date` を渡された場合は `strftime("%H:%M")` が `"00:00"` を返す等の挙動になるが、ラップしない。

本 plan では「Date を渡したらどうなるか」を spec で固定**しない**（「期待外の入力をユーザがしないこと」を信頼する）。caller 側（CLI コマンド層）が `Time.now` を渡す前提で書かれている限り問題は起こらない。

### 公開 API（再掲、ADR と同じ）

```ruby
Nob::Templates::Renderer.render(template, title:, now:)  # -> String
Nob::Templates::Parser.parse(template)                    # -> Array<Token>
Nob::Templates::Operators.build(name:, fmt:)              # -> Operator instance
```

## TODO（TDDタスク分解）

T1〜T4 で Operator を完成させ、T5 でファクトリ、T6〜T10 で Parser、T11 で Renderer、T12 で結合を組む順番。Operator → ファクトリ → Parser → Renderer の依存方向に合わせる。

- [x] **T1**: `lib/nob/templates.rb` に `UndefinedVariable`, `ParseError`, `Token`, `Literal`, `Variable` を定義（Struct ベース）。`spec/nob/templates_spec.rb` 1 ファイルにまとめ、`Literal.new("x") == Literal.new("x")` と `Variable.new(op) == Variable.new(op)` を検証（Operator の `==` 実装を待つので T2 完了後に Variable 側を追記する）
- [x] **T2**: `Operators::Base` を導入し、`==` / `hash` / `attr_reader :fmt` を共通化。`Operators::Title` を実装（`fmt` が nil 以外なら `UndefinedVariable`、`call(title:, now:)` は `title` を返す）。`spec/nob/templates/operators/title_spec.rb`
- [x] **T3**: `Operators::Date` を実装（fmt なし → `%Y-%m-%d`、`"timestamp"` → `to_i.to_s`、その他 → strftime 委譲）。境界 spec
- [x] **T4**: `Operators::Time` を実装（既定 `%H:%M`、timestamp 対応）。`Operators::Id` を実装（fmt 不可、`%Y%m%d%H%M%S`）
- [x] **T5**: `Operators.build(name:, fmt:)` を実装。case/when で 4 オペレータに dispatch、未知 name で `UndefinedVariable`。`spec/nob/templates/operators_spec.rb` で全分岐
- [x] **T6**: `Parser.parse` の最小実装。`{{title}}` のみのテンプレート、リテラルのみのテンプレート、混在、**`}}` 単独リテラル** を OK にする（Parser の literal 蓄積ループの挙動として早期に固定）
- [x] **T7**: 変数本体の split + strip。`{{ date : %Y-%m-%d }}` を扱える
- [x] **T8**: 行番号トラッキング。複数行テンプレートでエラーが出た時に開始行が正しく出ること
- [x] **T9**: 異常系 — unterminated `{{` で `ParseError`、ネスト `{{ {{ }} }}` で `ParseError`、空変数 `{{}}` `{{   }}` で `ParseError`
- [x] **T10**: ファクトリ経由の `UndefinedVariable` を Parser が catch して `"#{operator_message}: #{token_text} (line #{N})"` 形式に rewrap する。spec で出力メッセージを文字列リテラルとして固定
- [x] **T11**: `Renderer.render(template, title:, now:)` を実装（Parser を呼んでトークン列を評価、`Literal#text` と `Variable#operator.call(title:, now:)` を順に concat）。`spec/nob/templates/renderer_spec.rb`
- [x] **T12**: 結合シナリオ spec — design.md の例に近い template（frontmatter + 本文 + `{{title}}` / `{{date}}` / `{{time}}` / `{{id}}` 全部入り）を Renderer.render 経由で展開して検証する。本 plan のスコープは Templates モジュールのみで、実 caller（`create`, `daily`）との結合はそれぞれの plan で扱う
- [x] **T13**: `bundle exec rspec` 全 green を確認

## レビューフィードバック

### Plan レビュー（実施日: 2026-05-03、refine 済み）

#### Critical

- なし

#### Important

- **`}}` 単独リテラルの規則が T11 に分離**: Parser 最小実装 (T6) の段階で `}}` 単独の挙動が未定義のまま中盤を進めると事故る。T6/T7 の段階で固めるべき
- **Operator の rewrap 仕様が「実装時に詰める」のまま**: T10 の spec を書く前に「Parser がどう作り直すか」が決まっていないと TDD が組めない
- **`Operators::Base` 導入が ADR で言及されていない**: ADR §C/§D の「Operator は Renderer/Parser を参照しない」依存方向と Base 導入が干渉しないことを明記すべき
- **`now:` に Date を渡したケースの扱いが TODO に無い**: ADR §G で「実行時チェックしない」と決めたが、それを spec で固定するか放置宣言するかを plan で明示する

#### Nice-to-have

- T13 の結合シナリオは Parser/Renderer のみで実 caller を含まないことを 1 行補足
- Token を Struct で実装し、`==` 問題が出たら明示クラスに変える（ADR §B 通り）
- T1 の spec ファイル名（`templates_spec.rb` vs 個別）を plan 段階で確定する

### Code レビュー（実施日: 2026-05-03）

#### Critical

- なし

#### Important

- **Parser の `{` 単独 / `}` 単独混入に対する spec が無い** (`spec/nob/templates/parser_spec.rb`): リグレッション検出網が薄い。明示的なテストを追加すべき
- **`Operators::Base#==` の `is_a?(self.class)` 比較が将来非対称化リスク** (`lib/nob/templates/operators/base.rb:11`): 現状実害ゼロだが、サブクラスを継承したときに `parent == child` と `child == parent` が一致しなくなる。`self.class == other.class` のフラット比較に変えるべき
- **Renderer が毎回新規 parse する実装で固定** (`lib/nob/templates/renderer.rb:4-10`): ADR §H の「Parser を直接公開して caller がキャッシュできる」意図に対し、本実装はキャッシュ経路を持たない。T11 範囲とは整合するので致命ではないが、将来 API 拡張が必要

#### Nice-to-have

- `{{` 内に改行を含むケースで `start_line` 採用ルールを spec で固定（ADR §F 規約の回帰検出）
- Date / Time の不正な strftime 文字列（例: `%Q`）でのエラー伝播挙動を 1 ケース固定（ADR §E 規約）
- `templates_spec.rb` で `Variable.new(op) == Variable.new(op)` の固定が抜けている（plan T1 の達成条件）

#### Out of scope

- `now:` に Date を渡したケースの spec 化（ADR §G の方針通り固定しない）
- caller（`create`/`daily`）との結合は別 plan
- design.md の `YYYY/MM/DD` 表記更新は plan スコープ外

## 実装と計画の差分（recap）

最終結果: 97 examples / 0 failures（全 spec green）。

### Plan 通り実装できたこと

- ADR の依存方向（Operator → Renderer/Parser 参照禁止）と rewrap 仕様（`"#{operator_message}: #{token_text} (line #{N})"`）を実装で正しく実現
- T1〜T13 全 TODO を順番通り消化（Operator → Factory → Parser → Renderer の順）
- `}}` 単独リテラル規則を T6 段階で固定（Important 指摘通り）
- Operator のエラーメッセージ書式を spec で文字列リテラル固定

### 計画から差し引いた / 追加したこと

- **`Operators::Base#==` を `is_a?(self.class)` から `self.class == other.class` に変更**: code review で「サブクラスを継承したときの非対称化リスク」を指摘されたため refine で修正。フラット比較の方が安全
- **Variable equality の spec を refine で追加** (`spec/nob/templates_spec.rb`): plan T1 では Variable の `==` を「Operator 完成後に追記」と書いたが、最初の実装では追加されておらず、code review で抜けが指摘されて refine で補った
- **Parser robustness spec を refine で追加** (`spec/nob/templates/parser_spec.rb`): `{` 単独 / `}` 単独 / `{{` 内に改行を含むテンプレで `start_line` を保持、の 3 ケース。plan には無かったが回帰検出網として有益

### 設計通りで問題が出なかったこと

- StringScanner ベースの parser は line tracking 含めて 1 ファイル / ~80 行で収まり、ADR の見積もり通り
- Operator ごとのクラス分割（Hash + lambda 案を却下した経緯）は spec のテスタビリティで効いた。各 operator の `==` / fmt エッジケース / strftime 委譲をクラス単位で独立に書けた
- Token を Struct で実装し `include Token` で型タグ付けする案（ADR §B）は `==` 動作で問題が出ず、明示クラス化は不要だった

### Renderer のキャッシュ経路（明示的に保留）

- code review で「Renderer が毎回新規 parse する」点を Important 指摘として受けた
- ADR §H では Parser を直接公開しているので、caller がキャッシュする経路は既に open。本 plan のスコープでは Renderer 側 API 拡張は不要と判断し、保留
- 将来 caller（`create`/`daily`）からの呼び出しで再パースコストが顕在化したら別 plan で扱う

### 後続の関連タスク

- caller の template 対応: `create` 別 plan、`daily` 別 plan
- design.md の `YYYY/MM/DD` 表記を `%Y-%m-%d` に揃える: 別タスク
- 不正な strftime 文字列のエラー伝播挙動 spec（Nice-to-have）: 必要になったら追加
