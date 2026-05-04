---
title: Operators ファクトリの dispatch 軽量化
slug: operators-dispatch
status: implementing
created: 2026-05-05
updated: 2026-05-05
---

## 目的・背景

`/peer-review` のアーキテクチャ指摘の本筋議論 4/4（最終）。前 3 サイクル (`config-boundaries`, `notes-unification`, `cli-aggregation`) で層境界・Result 統一・CLI 集約・エラー方針を片付けたので、最後に Templates の Operator 追加コストを下げる。

### 解きたい問題

`lib/nob/templates/operators.rb:4-13` のファクトリ:

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

- 4 つの Operator クラスごとに `case/when` のエントリが 1 行ずつ書かれている
- Operator 追加時に必要な変更: (a) `lib/nob/templates/operators/<name>.rb` の新規追加、(b) `operators.rb` の `case/when` にエントリ追加、の **2 ファイル**
- ADR 0001 §C は「変数追加は『Operator クラスを足す + ファクトリにエントリを 1 つ足す』の局所変更で済む」と書いていたが、peer-review でも「ADR の『局所変更』の謳い文句より一段重い」と指摘済み

`Operators` モジュール直下のクラスと name (小文字) は **1 対 1 対応** （`title` → `Title`, `date` → `Date`, etc）で、これを const_get で動的解決すれば `case/when` テーブルが消え、Operator 追加が 1 ファイルで済む。

スコープ外: なし（本サイクルが最後）。完了後 `done` で recap して全 5 サイクルが揃う。

## 設計

### 1. `Operators.build` を const_get ベースの動的解決に置き換える

```ruby
module Operators
  CLASS_NAME_PATTERN = /\A[a-z]+\z/

  def self.build(name:, fmt:)
    klass = lookup(name) or raise UndefinedVariable, "unknown variable: #{name}"
    klass.new(fmt)
  end

  def self.lookup(name)
    return nil unless name.match?(CLASS_NAME_PATTERN)
    const_name = name.capitalize.to_sym
    klass = begin
      const_get(const_name, false)
    rescue NameError
      return nil
    end
    (klass.is_a?(Class) && klass < Base) ? klass : nil
  end

  private_class_method :lookup
end
```

要点:

- **name のバリデーション**: 小文字英字のみ（`/\A[a-z]+\z/`）。`Date` のような大文字始まりや `my-op` のようなハイフン入りは弾く（現状 case/when では fall through で `UndefinedVariable`、新実装でも同じ結果）
- **直下のみ参照**: `const_get(const_name, false)` で `inherit: false` 指定。`Object` 階層の `Date` / `Time` などの組み込みクラスに到達しない
- **`Class` 型ガード**: `klass.is_a?(Class)` で `Operators::CLASS_NAME_PATTERN` のような non-Class const（`Regexp` など）を弾く
- **`Base` サブクラスガード**: 続く `klass < Base` で `Base` を継承していない Class を弾く。Operator は `Base` を継承する規約に乗せる
- **autoload 発火**: Zeitwerk の autoload は `const_get` で発火するので、`operators/title.rb` 等が遅延ロード経路に乗ったまま動く（事前 require 不要）
- **autoload 例外の扱い**: `Zeitwerk::NameError` は `NameError` のサブクラスなので `rescue NameError` で拾われ `nil` 返却 → `UndefinedVariable`。一方「ファイルは存在するが const を定義し損ねた」規約違反シナリオで `Zeitwerk::Error` 等が発生しうるが、これは規約違反として **意図的に拾わず**素通しする（ライブラリ実装ミスの早期発覚を優先、ADR 0002 §A の「ユーザーが直せないエラーは素通し」とも整合）
- **`Base` 自身の保護**: `Base` は `klass < Base` の判定で `false` を返す（自分自身は自分のサブクラスではない）ので、`build(name: "base", fmt: ...)` は `UndefinedVariable` になる

### 2. ADR 0001 §C の補追

「ファクトリ内部 dispatch は本 ADR で詳細を決めない」は維持しつつ、現在の dispatch 実装が `const_get` 式に変わったことと、それにより Operator 追加が **1 ファイル変更で済む**契約になったことを補追する。

ADR §F (Parser の仕様) との切り分けを明文化:

- **§F は変更しない**: Parser は引き続き「`name` を strip して空でなければ `Operators.build` に渡す」のみ。文字種の制約は §F に書かない
- **§C で文字種を縛る**: 「`Operators.build` が受け付ける `name` は `/\A[a-z]+\z/`（小文字英字のみ）。それ以外は `UndefinedVariable`」を §C に追記
- 責務分担の理由: 文字種は dispatch（`name → Class` 変換）の都合で決まる制約であり、Parser の字句解析の都合ではない。dispatch の実装が将来別形式に変わったら §C だけ更新すれば済む

### 3. 「Operator 追加が 1 ファイルで済む」契約を spec で固定

spec の中で `Operators::Foo < Operators::Base` を **動的に定義** し、`Operators.build(name: "foo", fmt: nil)` がそのクラスのインスタンスを返すことを assert する。これにより:

- 「`operators.rb` を編集せずに Operator を追加できる」が回帰検出可能
- 将来 dispatch を再度 case/when に戻したくなったときも、この spec が gate になる

## TODO（TDDタスク分解）

- [x] **T1**: `Replace Operators dispatch with const_get-based lookup`
    - Red: `spec/nob/templates/operators_spec.rb` に 3 example を追加
      - 「`Operators` 配下に `Foo < Base` を動的定義 → `build(name: "foo", fmt: nil)` が `Foo.new(nil)` を返す」 — 現状 `case/when` では `UndefinedVariable` で fail
      - 「name が大文字混じり (`"Title"`) → `UndefinedVariable`」 — 既存実装でも green（追加保証）
      - 「`build(name: "base", fmt: nil)` は `UndefinedVariable`」 — 新実装で初めて固定される（現実装は `case/when` に `"base"` のエントリ無しで偶然 green）
    - 動的定義 example の片付け: spec の `after` ブロックで `Operators.send(:remove_const, :Foo) if Operators.const_defined?(:Foo, false)` を呼ぶ。`after` は example raise 時も実行されるので（RSpec の hook 仕様、`ensure` 相当）、後続 example への漏れは起きない
    - Green: `lib/nob/templates/operators.rb` を const_get 式に書き換える（設計 §1 通り、`CLASS_NAME_PATTERN` / `lookup` private、`Class` 型 + `Base` サブクラスのガード 2 段）
    - 完了基準: `bundle exec rake` が green、既存 6 example + 新 3 example pass、`grep "case " lib/nob/templates/operators.rb` で 0 件
- [ ] **T2** (docs task): `Loosen ADR 0001 §C to lock the const_get dispatch and 1-file Operator addition`
    - 事前確認: `bundle exec rake` が green（T1 完了状態）
    - 変更: `docs/adr/0001_template-system.md` §C を補追（設計 §2 通り、`const_get` 式の採用 / 1 ファイル追加で済む契約 / `name` 許容文字を §C で縛り §F は変更しない切り分け）
    - 完了基準: `bundle exec rake` が green（コード変更なし）、ADR §C の補追セクションが `Token` 撤去 / `loader` 解禁の前例（cleanup-misc / cli-aggregation）と同じ書きぶり（cycle 名 + 日付 + 補追内容）で並ぶ

## レビューフィードバック

### peer-review 1 回目（2026-05-05, plan モード）

Critical: 0 件 / Important: 2 件 / Nice-to-have: 3 件

**Important**

- `lookup` の `rescue NameError` で拾えない `Zeitwerk::Error` 系（規約違反シナリオ）の扱いが plan に明示されていない。
  - → **対応済**: 設計 §1 の要点に「autoload 例外の扱い」を追加。`Zeitwerk::NameError` は `NameError` のサブクラスなので拾われる、`Zeitwerk::Error`（ファイルあるが const 未定義の規約違反）は意図的に素通し（ADR 0002 §A 「ユーザーが直せないエラーは素通し」とも整合）と明記。
- `name` 文字種の責務切り分け（ADR §C で縛る / §F (Parser) は変えない）が ADR 補追で明示される旨の説明が plan で曖昧。
  - → **対応済**: 設計 §2 を改稿。「§F は変更しない」「§C で文字種を縛る」「責務分担の理由（dispatch の都合で決まる制約）」を明文化。

**Nice-to-have**

- T1 が「実装 + spec + ADR 補追」を 1 task に詰めており、ADR 補追は Red/Green と無関係なので別 task に切ると差分レビューが楽。
  - → **対応済**: T1 を T1（実装 + spec）と T2（ADR 補追、docs task）に分割。T2 は `cleanup-misc` の T4（Token 撤去 + ADR 0001 §B 改訂）や `cli-aggregation` の T1/T2（rescue 集約 + ADR 0002 §D 補追、Loader 新設 + ADR 0001 §I 補追）と同じく「実装後に ADR を別 commit で固定」のスタイルに揃える。
- spec の動的 `Foo` 定義 → `remove_const` クリーンアップが example 失敗時にも漏れない保証を一言。
  - → **対応済**: T1 の Red 説明に「`after` は example raise 時も実行される（RSpec hook 仕様、`ensure` 相当）」を明記。
- `CLASS_NAME_PATTERN` のような non-Class const を `klass.is_a?(Class)` で弾く自衛が要点に並んでいない。
  - → **対応済**: 設計 §1 の要点に「`Class` 型ガード」を独立項目として追加（`Base` サブクラスガードと並列）。

## 実装と計画の差分（recap）

（recap で記入）
