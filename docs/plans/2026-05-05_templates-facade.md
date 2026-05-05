---
title: Templates ファサード化と Loader 撤去
slug: templates-facade
status: refining
created: 2026-05-05
updated: 2026-05-05
---

## 目的・背景

現状、テンプレート読込は `Nob::Templates::Loader.read(path)` という薄いラッパーが担っている。中身は `path.nil?` ガード + `File.exist?` チェック + `File.read` のみで、Templates 固有のロジックを一つも持っていない。daily 以外にも将来テンプレートを使うコマンドが増える前提で、この構造を整理しておきたい。

### 解きたい問題

1. **責務の置きどころ**: ファイル I/O が Templates 名前空間の `Loader` に置かれており、Templates モジュールの責務（テンプレート文字列 → 出力）からはみ出している。Loader は class（module）化するほどの仕事をしていない
2. **呼び出し方の一貫性**: 現行は CLI 層で「Loader で読む → 文字列を Notes::Daily に渡す → Daily 内部で Renderer に渡す」と 3 段になっている。呼び出し元が増えたとき各コマンドが同じ手順を踏むかは保証されず、ドリフトの余地が大きい
3. **入力経路の単一化**: テスト都合で文字列を直接渡したい場面と、本番コードでパスを渡したい場面がある。両方を 1 エントリで吸収できる形にしたい

判断軸: メモリ `feedback_structure_over_yagni.md` (構造の整理と呼び出し方の一貫性を YAGNI より優先する) と、本会話で確認した「Templates の責務は文字列 → 出力で、ファイル I/O は外」を両立する形を採る。

スコープ外: Renderer/Parser のシグネチャ変更、Operators の変更。

## 設計

### `Nob::Templates.render` ファサードを新設する

`lib/nob/templates.rb` のモジュール直下に以下の class method を追加する:

```ruby
module Nob
  module Templates
    # 既存: UndefinedVariable / ParseError / Literal / Variable

    def self.render(path: nil, text: nil, title:, now:)
      text ||= read_template(path)
      return "" if text.nil?
      Renderer.render(text, title: title, now: now)
    end

    def self.read_template(path)
      return nil if path.nil?
      unless File.exist?(path)
        raise Nob::Error, "template file not found: #{path}"
      end
      File.read(path)
    end
    private_class_method :read_template
  end
end
```

要点:

- **入口は 1 つだけ**: 呼び出し側は `path:` か `text:` のどちらかを渡す。本番コードはパスを渡し、テストは文字列を直接渡す、という使い分けを想定する。両方同時に渡されたケースの挙動は spec で固定しない（実装上は `text` が勝つが契約には含めない）
- **nil → "" フォールバックをファサードに集約**: 現状 `Notes::Daily.render` が持っている `return "" if template_text.nil?` をファサード側に寄せる。これにより daily 以外の呼び出し元でも同じ「テンプレ未設定なら空文字」挙動が無料で得られる
- **`read_template` は private**: ファイル I/O は実装詳細として隠す。外から呼ぶ手段としては `Templates.render(path: ...)` のみ
- **エラー文言は現行 Loader と同一**: `Nob::Error, "template file not found: #{path}"` を維持し、CLI 層の表示挙動を変えない
- **Renderer/Parser は無変更**: 文字列を取って AST → 出力を返す純粋ユニットのまま据え置く

#### 警告と fallback の責務分担

`cli.rb#daily` の `Warning: no daily-note template configured (...)` の `warn` 出力は CLI 層に残す。これは「ユーザーへの通知」という UI 責務であり、ファサードの「データ非存在時の戻り値」とは別レイヤ。具体的には CLI が `settings.template_path.nil?` を見て warn を出し、その後 `Templates.render(path: nil, ...)` を呼んで `""` を受け取る、という分業にする。ファサードは warn を出さない。

### `Notes::Daily` の signature 整理

`Notes::Daily.create` のキーワードを `template_text:` → `template_path:` に変更し、内部で `Templates.render(path: template_path, ...)` を呼ぶ。private `Notes::Daily.render` は不要になるので削除する。

```ruby
def self.create(vault:, base_path:, file_name_format:, template_path: nil, now: Time.now, force: false)
  # ...
  File.write(target_path, Nob::Templates.render(path: template_path, title: date_str, now: now))
  # ...
end
```

要点:

- **CLI から Daily への入力もパスに統一**: `cli.rb#daily` も `template_path: settings.template_path` を渡すだけになり、`File.read` を経由しない
- **Daily が Templates の内部表現に依存しない**: Daily は「path をもらって render を依頼する」だけ。文字列加工は Templates の中で完結する

### `Loader` の撤去

`lib/nob/templates/loader.rb` と `spec/nob/templates/loader_spec.rb` を削除する。役割は `Templates.render` + private `read_template` に移管済み。

### エッジケースの確認

| 入力 | 振る舞い |
|---|---|
| `path: nil, text: nil` | `""` を返す（テンプレ未設定の daily 相当） |
| `path: "...", text: nil`（ファイル存在） | ファイル内容を読んで render |
| `path: "...", text: nil`（ファイル不在） | `Nob::Error, "template file not found: <path>"` |
| `path: nil, text: "..."` | text をそのまま render |

## TODO（TDDタスク分解）

- [x] **T1**: `Add Templates.render facade with path/text inputs`
    - Red: `spec/nob/templates_spec.rb` を新設し、`Nob::Templates.render` の振る舞いを behavior レベルで固定する。example: text 渡しで render 結果が返る / path 渡しでファイル内容が render される / 両方 nil で `""` / path 指定でファイル不在で `Nob::Error`
    - Green: `lib/nob/templates.rb` に `self.render` と private `self.read_template` を追加。Renderer/Parser は触らない

- [x] **T2**: `Switch Notes::Daily and CLI to Templates.render facade`
    - Red: `spec/nob/notes/daily_spec.rb` の `template_text:` キーワードを `template_path:` に書き換え、必要に応じてテンプレ fixture を tmpdir に書いて path を渡す形に修正（既存の振る舞い assertion は維持）。現状の private `Daily.render` を直接 assert している spec は無いので影響範囲は `template_text:` 引数だけ
    - Green: `lib/nob/notes/daily.rb` の `create` 引数を `template_path:` に変更し、`Nob::Templates.render(path: template_path, title: date_str, now: now)` を直接呼ぶ。private `self.render` を削除。`lib/nob/cli.rb#daily` を `template_path: settings.template_path` を渡す形に変更し、`Nob::Templates::Loader.read(...)` 呼び出しを除去（Loader 自体はこの commit ではまだ残す）
    - 注: CLI の差分は spec を持たないが、`Notes::Daily.create` の signature 変更に伴う build-fix のため同 commit に含める。Daily 単独 commit では `bundle exec rake` が通らない

- [x] **T3**: `Remove Templates::Loader and its spec`
    - Red: 削除専用 task のため新規 Red は無い。本 task の green 条件は「`bundle exec rake` 全 green かつ `grep -r 'Templates::Loader' lib spec` が 0 件」
    - Green: `lib/nob/templates/loader.rb` と `spec/nob/templates/loader_spec.rb` を削除

## レビューフィードバック

### peer-review 1 回目（2026-05-05, plan モード）

Critical 0 / Important 3 / Nice-to-have 2。Important の各指摘について 1 段検討した結果:

- **警告と fallback の責務分担（Imp#1）**: 妥当な指摘として反映。設計セクションに「警告は CLI、fallback はファサード」の分業を明記した
- **`text` + `path` 両方指定で text 優先（Imp#2）**: 妥当な指摘として反映。テスト都合のために本番 API に分岐を持ち込むのは余計と判断し、edge case 表から該当行を削除し、T1 の spec example からも除いた。実装上は `||=` で `text` が勝つが、契約として固定しない
- **T2 の Red/Green 境界（Imp#3）**: 軟着地。CLI の差分は Daily signature 変更に追従する build-fix で、独立 task に分けても新規 spec が増えるわけではないため bundle のままとし、T2 末尾にその旨を 1 行追記した
- **Nice-to-have 2 件（ファサード化便益の補強 / T1 example の整合）**: Imp#2 の反映で T1 example 側は自動的に解消。便益の補強は「目的・背景」内の "解きたい問題" 3 点で既に表現できているため追加修正は行わない

### peer-review 2 回目（2026-05-05, code モード）

実装 3 commit (T1/T2/T3) に対するコードレビュー。Critical 0 / Important 1 / Nice-to-have 2。

- **Important: `Templates.render` のキーワード並びが plan サンプルと差異**: plan の設計サンプルは `path: nil, text: nil, title:, now:` 順だが実装は `title:, now:, path: nil, text: nil` 順。standard linter の `Style/KeywordParametersOrder`（オプション kw を末尾に）に従って実装側で並び替えた。挙動は等価。recap セクションで明記する形で対応済み（このセクション + 「実装と計画の差分」）
- **Nice-to-have: skip ケースの回帰検出力低下**: `spec/nob/notes/daily_spec.rb:55` の "skips when the file exists with size > 0" example は移行前 `template_text: "new"` で「テンプレがあっても既存ファイルは上書きされない」意図を表現していた。新コードでは `template_path: nil` にしたため意図が読み取りにくい。Refine で `write_template("new")` を渡す形に戻して回帰検出力を回復する → 反映
- **Nice-to-have: `.render` spec の describe/context 構造化**: edge case 表との対応を読みやすくする任意の改善 → 採用しない（example のラベル（"returns an empty string when..." 等）で挙動の対応は読み取れる、追加 nesting は overkill と判断）

## 実装と計画の差分（recap）
