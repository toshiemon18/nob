---
title: テンプレートシステムの設計方針
number: 0001
status: accepted
date: 2026-05-03
---

## コンテキスト

`nob` には `create`, `daily`, 将来の zettel など複数のノート作成シーンがあり、決まったテンプレートからノートを生成したい。design.md で対応すべき変数（`{{title}}`, `{{date}}`, `{{date:fmt}}`, `{{time}}`, `{{time:fmt}}`, `{{id}}`）と「任意コード実行を許さない」方針が定義されている。

regex + Hash dispatch の素朴な実装も検討したが、

- 空白の扱い・エスケープ・ネストなど **テンプレートの書きぶりへの依存** が implementation detail に漏れる
- エラーメッセージに位置情報を含めにくい
- Operator → Renderer の依存方向が歪む（Operator が Renderer のクラスを raise する）

といった問題が見えたため、**字句解析 → 評価の 2 段構成**を採用する。本 ADR でその構成を固定する。

## 前提（要求由来でこれは判断ではない）

- テンプレートは vault 相対パスで指定し、機能ごとの config キーで持つ（global な templates_dir は導入しない）
- テンプレート未指定時のフォールバックは各機能の責務（テンプレートシステムは関知しない）
- 既存の `Creator` は本 ADR で書き換えない（別 plan）
- 任意コード実行は許さない（design.md 既決）

## 用語

ADR 全体で使う固有概念をここで定義する。

- **トークン**: テンプレートを字句解析した結果の最小単位。型は 2 つだけ（リテラル / 変数）
- **オペレータ**: 1 つの変数（`{{title}}` 等）に対応する評価器クラス。`Nob::Templates::Operators::*` に置く。インスタンス化時に `fmt` を pre-bind し、`.call(title:, now:)` で展開後文字列を返す
- **ファクトリ関数**: `(name, fmt)` を受け取って対応するオペレータインスタンスを返す関数。`Nob::Templates::Operators.build(name:, fmt:)`。未知の `name` や許されない `fmt` の場合は `UndefinedVariable` を raise する
- **パーサ**: テンプレート文字列をトークン列に変換する。`{{...}}` の内側を `name` / `fmt` に分解し、ファクトリ関数を呼んで変数トークンを構築する
- **レンダラ**: トークン列と (title, now) を受け取って最終文字列を返す

## 決定

### A. 二段構成: Parser → Renderer

```
String
  │
  ├─ Parser ──▶ [Token]      （字句解析。書きぶりの正規化・エラー検出）
  │
  └─ Renderer ──▶ String     （評価。トークンを順に展開して連結）
```

- **構文エラーや未定義変数は Parser 段階で全部検出する**。Renderer は構造的に正しいトークン列を受け取る前提で動くので、評価ループはエラーを投げない（オペレータが投げる Ruby の `strftime` 例外などは別）
- 早期失敗。テンプレートを 1 度 parse すれば、後段でいくら `render` しても構文の心配はない

### B. トークンの表現

```ruby
module Nob::Templates
  Token = Module.new
  Literal  = Struct.new(:text)         { include Token }
  Variable = Struct.new(:operator)     { include Token }
end
```

- `Literal#text` は素のテキスト断片
- `Variable#operator` は **既に pre-bind 済みのオペレータインスタンス**（fmt は instance に閉じ込められている）
- トークン列は単なる Array。AST と呼ぶほどの構造は持たない（ネスト無し）
- Parser がエラーを投げた場合、Variable トークンは構築されない。つまり Variable トークンが手元にある時点で「name は既知、fmt は妥当」が保証される

### C. ファクトリ関数で Operator インスタンスを生成する

```ruby
Nob::Templates::Operators.build(name:, fmt:)
  # name → 該当 Operator クラスを引き当て、fmt を pre-bind して new する
  # 未知 name / 不正 fmt は UndefinedVariable を raise
```

- Parser は `{{ name : fmt }}` をパースした後、このファクトリに `name` と `fmt` を渡してインスタンスを得る
- ファクトリ内部の dispatch は **本 ADR で詳細を決めない**（case/when でも内部 Hash でも実装次第）。重要なのは「Renderer / Parser はファクトリ関数しか知らない」境界
- 変数追加は「Operator クラスを足す + ファクトリにエントリを 1 つ足す」の局所変更で済む

### D. Operator は fmt を pre-bind した evaluator

```ruby
class Nob::Templates::Operators::Date
  def initialize(fmt)
    @fmt = fmt   # nil / "timestamp" / strftime 文字列
  end

  def call(title:, now:)
    case @fmt
    when nil         then now.strftime("%Y-%m-%d")
    when "timestamp" then now.to_i.to_s
    else                  now.strftime(@fmt)
    end
  end
end
```

- 各 Operator はインスタンス化時に `fmt` のバリデーション + 保持を行う。例えば `Operators::Title.new("foo")` は構築段階で `UndefinedVariable` を raise する（`title` は fmt 不可）
- 評価メソッドは `.call(title:, now:)`（fmt は self に閉じ込め済み）
- 各 Operator は **Renderer や Parser のクラスを参照しない**（依存方向: Renderer/Parser → Operator のみ）。raise する例外は `Nob::Templates::UndefinedVariable`

### E. UndefinedVariable は Templates 直下に置く

```ruby
class Nob::Templates::UndefinedVariable < Nob::Error; end
```

- Renderer / Parser / Operators 全部から参照可能で、特定クラスへの依存を作らない
- `strftime` の format エラー等、Ruby ライブラリ由来の例外はラップせずそのまま伝播

### F. パーサの仕様

字句解析の規則：

1. 入力文字列を先頭から走査する
2. `{{` を見たら **変数開始**。続く文字を `}}` まで読む
3. 変数本体の中で再び `{{` が出現した場合は **構文エラー**（ネスト禁止、`UndefinedVariable` ではなく `Nob::Templates::ParseError`）
4. EOF まで `}}` が見つからなければ **構文エラー**（unterminated）
5. `}}` 単独の出現はリテラル文字として扱う（閉じる対象が無いので普通のテキスト）
6. それ以外の文字はリテラルとして蓄積し、`{{` か EOF に当たった時点で `Literal` トークンとして flush

変数本体の解釈：

- `name : fmt` の形式。**最初の `:` のみ**で `name` と `fmt` に分割（fmt 内に `:` を含む `%H:%M:%S` を許すため）
- `name` と `fmt` の **前後の空白を strip**。`{{ date : %Y-%m-%d }}` のような書き方を許容
- `:` が無ければ `fmt = nil`
- `name` が空文字列なら `ParseError`
- 解析した `name`, `fmt` を `Operators.build` に渡してインスタンスを得る。ここで `UndefinedVariable` が発生する可能性あり
- 例外メッセージには **`{{...}}` トークン全体** と **テンプレート上の行番号** を含める

エスケープと literal `{{`:

- エスケープ構文は本 ADR では **導入しない**。テンプレートに `{{` を素のままで残したい場合の手段は無い（必要になったら別 ADR）

### G. now の型

- caller は `now:` に `Time` インスタンスを渡す
- `Date` は受け付けない（`{{time}}` / `{{id}}` が成立しないため）
- 公開 API のドキュメントに明記。実行時に型チェックはせず、`strftime` 経由で暗黙に失敗させる

### H. Renderer の責務

- Renderer は **トークン列の評価**だけを行う
- 入口は `Renderer.render(template_string, title:, now:)`。内部で Parser を呼んでトークン列を作り、評価する
- Parser を直接公開する（`Parser.parse(template_string) -> [Token]`）ので、「同じテンプレートを複数回 render したい」シーンが将来出てきたら parse 結果を caller がキャッシュできる
- 副作用なし。stdout/stderr に出力しない

### I. ファイル I/O は Renderer の外

- Renderer / Parser は文字列入力。`File.read` を呼ばない
- 「config からテンプレパスを取り、vault 相対を絶対に解決し、読み込む」処理は **caller（CLI コマンド側）の責務**
- 専用の loader クラスは導入しない。読み込み処理が複数 caller で重複し始めた時点で切り出す

## 公開 API（決定の集約）

```ruby
module Nob
  module Templates
    class UndefinedVariable < Nob::Error; end
    class ParseError       < Nob::Error; end

    Token    = Module.new
    Literal  = Struct.new(:text)     { include Token }
    Variable = Struct.new(:operator) { include Token }

    class Parser
      def self.parse(template) # -> Array<Token>
      end
    end

    class Renderer
      def self.render(template, title:, now:) # -> String
      end
    end

    module Operators
      def self.build(name:, fmt:) # -> Operator instance
      end

      class Title;  def initialize(fmt); end; def call(title:, now:); end; end
      class Date;   def initialize(fmt); end; def call(title:, now:); end; end
      class Time;   def initialize(fmt); end; def call(title:, now:); end; end
      class Id;     def initialize(fmt); end; def call(title:, now:); end; end
    end
  end
end
```

## 各シーンのトレース

### 通常ケース

```
template = "title: {{title}}\ndate: {{date}}\n# {{ title }}"
Parser.parse(template)
  → [Literal("title: "),
     Variable(Operators::Title.new(nil)),
     Literal("\ndate: "),
     Variable(Operators::Date.new(nil)),
     Literal("\n# "),
     Variable(Operators::Title.new(nil))]

Renderer.render(template, title: "X", now: Time.new(2026, 5, 3, 9, 0))
  → "title: X\ndate: 2026-05-03\n# X"
```

### フォーマット指定（コロン含む）

```
"{{time:%H:%M:%S}}"
  → split(":", 2) で ["time", "%H:%M:%S"]
  → Operators::Time.new("%H:%M:%S")
  → "09:00:00"
```

### 不正なテンプレート（parse 時に失敗）

```
"{{ unknown }}"        → UndefinedVariable: unknown variable: {{ unknown }} (line 1)
"{{ title : foo }}"    → UndefinedVariable: title does not accept format: {{ title : foo }} (line 1)
"{{ {{ a }} }}"        → ParseError: unexpected '{{' inside variable (line 1)
"{{ unterminated"      → ParseError: unterminated variable (line 1)
```

## 帰結

**利点**:

- テンプレートの書きぶり（空白、コロン、ネスト）は Parser に閉じ、Renderer / Operators には漏れない
- エラーは parse 時に位置情報付きで全部捕まる。Renderer 実行時の例外は「Ruby ライブラリ由来」だけ
- Variable トークンを得た時点で「name 既知 / fmt 妥当」が型レベルに近い保証として効く
- 各層が独立にテストできる:
  - Parser spec: 文字列 → トークン列の各種パターン
  - Operator spec: `.new(fmt).call(title:, now:)` の入出力
  - Renderer spec: トークン列の評価（Parser をモックしてもよい）
- 変数追加は Operators クラス + ファクトリエントリの局所変更
- ファクトリ関数によって Renderer / Parser から Operators の dispatch 詳細が隠蔽される

**受容するトレードオフ**:

- 4 変数に対する機構としては重め（Parser, Renderer, Operators ファクトリ, 4 オペレータクラス）。個人プロジェクトの学習・拡張性投資として許容
- design.md の `YYYY/MM/DD` 表記との不一致。Ruby strftime 表記に統一し design.md を後追い更新
- エスケープ `\{\{` を当面サポートしない
- 未定義変数を全件集めない（最初の 1 個で止まる）
- caller が `now:` に Date を渡すケースを実行時にチェックしない（強い型運用ではないが許容）
