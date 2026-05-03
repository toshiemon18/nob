---
title: コア構造整理 — Zeitwerk + entities / notes 名前空間
slug: core-structure
status: done
created: 2026-04-30
updated: 2026-05-02
---

## 目的・背景

現状の `lib/nob/` はフラットで、エンティティとオペレーションが混在している。

- `Nob::Note` — 名前はエンティティ的だが中身は作成サービス（クラスメソッドのみ）
- `Nob::NoteList` — 一覧サービス。`Entry` という型を内包しているが、これは本来ノートエンティティ
- `nob show` など今後の機能を追加するたびに `note_xxx.rb` が並び続ける

整理のゴール：

1. **`entities/`** — 純粋なデータオブジェクト置き場。`Nob::Entities::Note` がノートを表す型として確立し、`NoteList::Entry` と `Note::Result` の役割を統合・整理する
2. **`notes/`** — ノート操作のオペレーション置き場。`Nob::Notes::Creator`, `Nob::Notes::Lister` など機能ごとにファイルを分ける
3. **Zeitwerk** — ファイルパス = 定数名を強制することで命名の迷いをなくし、`require_relative` の羅列を排除する

## 設計

### ディレクトリ構成（移行後）

```
lib/nob/
  version.rb          # Nob::VERSION（変更なし）
  config.rb           # Nob::Config（変更なし）
  cli.rb              # Nob::CLI（呼び出し先クラス名のみ更新）
  entities/
    note.rb           # Nob::Entities::Note — vault 上のノートを表す値オブジェクト
  notes/
    creator.rb        # Nob::Notes::Creator — ノート作成ロジック
    lister.rb         # Nob::Notes::Lister  — ノート一覧ロジック
```

### Nob::Entities::Note

```ruby
module Nob
  module Entities
    Note = Struct.new(:absolute_path, :relative_path, keyword_init: true)
  end
end
```

- 現 `Nob::NoteList::Entry` の完全な置き換え
- vault 上に存在するノートファイルを表す。読み取り専用の値オブジェクト
- `Note::Result`（作成結果）とは別物。作成結果は `Creator` の内部型として残す

### Nob::Notes::Creator

```ruby
Nob::Notes::Creator.create(title:, vault:, dir: nil, force: false, today: Date.today)
  # => Nob::Notes::Creator::Result
```

- 現 `Nob::Note.create` / `.move_to_backup` / `.render` をそのまま移動
- `Nob::Note::AlreadyExists` → `Nob::Notes::Creator::AlreadyExists`
- `Nob::Note::Result` → `Nob::Notes::Creator::Result`（`path`, `backup_path`）

### Nob::Notes::Lister

```ruby
Nob::Notes::Lister.list(vault:, prefix: nil)
  # => [Nob::Entities::Note, ...]
```

- 現 `Nob::NoteList.list` をそのまま移動
- 戻り値の型を `Nob::NoteList::Entry` → `Nob::Entities::Note` に変更
- `InvalidPrefix` / `PrefixNotFound` は `Nob::Notes::Lister::` 以下に残す

### Zeitwerk セットアップ

```ruby
# lib/nob.rb
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.setup

module Nob
  class Error < StandardError; end
end
```

- `require_relative` の羅列を完全に廃止
- `Nob::Config`, `Nob::CLI`, `Nob::Entities::Note`, `Nob::Notes::Creator`, `Nob::Notes::Lister` はすべて自動解決
- `Nob::VERSION` も同様（`lib/nob/version.rb` が `Nob::VERSION` を定義している限り OK）

### CLI の変更

```ruby
# create コマンド
Nob::Notes::Creator.create(title: title, vault: config.vault, ...)

# list コマンド
Nob::Notes::Lister.list(vault: config.vault, prefix: options[:prefix])
```

### 設計判断メモ

- **`core/` を採用しない理由**: design.md は `lib/nob/core/` を示しているが、`core` という名前はすべてのロジックを吸収しがちで責務が曖昧になる。`entities/`（何であるか）と `notes/`（何をするか）に分けることで責務が名前から読める。将来 `config/`, `links/` 等が増えても同じ規則で拡張できる。design.md のディレクトリ構成は更新が必要
- Zeitwerk の `for_gem` は `lib/` 以下のファイルをルートとして扱う。`lib/nob.rb` が `loader.setup` を呼ぶ = gem の require 時に自動登録が完了する
- `Nob::Config`, `Nob::CLI` はディレクトリ移動なしで Zeitwerk に自然に乗る（`lib/nob/config.rb` → `Nob::Config`）
- `cli.rb` の `require "thor"` は残す（外部 gem は Zeitwerk の管轄外）
- T2 で Zeitwerk セットアップを追加する際は `require_relative` との二重定義が起きないよう、`Nob::Config` 等の定数が重複ロードされないことを確認する
- `Creator` の内部メソッド（`move_to_backup`, `render`）は `private_class_method` として隠蔽する。現在の spec で直接テストしているケースは削除し、`create` の結果で間接的にカバーする
- 旧ファイル（`note.rb`, `note_list.rb`）と対応する旧 spec は、各新クラスの実装が green になった直後に削除する（T4 後に `note_list_spec.rb`、T5 後に `note_spec.rb`）

### spec の対応

- `spec/nob/note_spec.rb` → `spec/nob/notes/creator_spec.rb`
- `spec/nob/note_list_spec.rb` → `spec/nob/notes/lister_spec.rb`
- `spec/nob/cli_spec.rb` — クラス名参照のみ更新

## TODO（TDDタスク分解）

- [x] **T1**: `zeitwerk`（`~> 2.6`）を `nob.gemspec` の依存に追加し、`bundle install` が通ることを確認
- [x] **T2**: `lib/nob.rb` に Zeitwerk セットアップを追加（既存の `require_relative` は一時的に残す）。`Nob::Config` 等の定数が二重定義されないことを確認し、既存テストが全 green のままであることを確認
- [x] **T3**: `lib/nob/entities/note.rb` に `Nob::Entities::Note` を新設。`spec/nob/entities/note_spec.rb` で `absolute_path` / `relative_path` を持つ値オブジェクトであることをテスト
- [x] **T4**: `lib/nob/notes/lister.rb` に `Nob::Notes::Lister` を新設（NoteList のロジックをコピー、戻り値を `Nob::Entities::Note` に変更）。`spec/nob/notes/lister_spec.rb` を新設して全ケースが green になることを確認。`lib/nob/cli.rb` の `Nob::NoteList.list` 参照を `Nob::Notes::Lister.list` に切り替え（旧クラス削除で CLI が壊れないようにする）。完了後に `lib/nob/note_list.rb` と `spec/nob/note_list_spec.rb` を削除してテスト全 green を確認
- [x] **T5**: `lib/nob/notes/creator.rb` に `Nob::Notes::Creator` を新設（Note のロジックをコピー、`move_to_backup` / `render` は `private_class_method` に）。`spec/nob/notes/creator_spec.rb` を新設して全ケースが green になることを確認。`lib/nob/cli.rb` の `Nob::Note.create` 参照を `Nob::Notes::Creator.create` に切り替え。完了後に `lib/nob/note.rb` と `spec/nob/note_spec.rb` を削除してテスト全 green を確認
- [x] **T6**: `lib/nob/cli.rb` を `Nob::Notes::Creator` / `Nob::Notes::Lister` を使うよう更新。`spec/nob/cli_spec.rb` が green のままであることを確認（実装上 T4/T5 で先行実施）
- [x] **T7**: `lib/nob.rb` から `require_relative` を全て削除し、Zeitwerk のみに移行。テスト全 green を確認
- [x] **T8**: `bundle exec rspec` 全体 green を最終確認

## レビューフィードバック

レビュー実施日: 2026-04-30

### Critical

- **design.md の `core/` と今回の `entities/` + `notes/` 構造が説明なく乖離している** — design.md は `lib/nob/core/` をコアロジック置き場と明示しているが、plan はその判断を覆す独自構造を採用しており根拠が記載されていない。→ **採用**: 設計判断メモに `core/` を採用しない理由を追記する

### Important

- **T2 で Zeitwerk と既存 `require_relative` の二重ロードが起きる恐れがある** — 同一定数の二重定義になりうる。T2 完了時に二重ロードが起きないことを確認するステップが欠けている。→ **採用**: T2 の TODO に確認ステップを追記する
- **`move_to_backup` の公開/非公開設計への言及がない** — `Creator` への移動時の方針を明記すべき。→ **採用**: 設計に「`private_class_method` として隠蔽する」旨を追記する
- **zeitwerk の採用バージョンが plan に未記載** — `required_ruby_version >= 4.0.0` 環境での動作確認が TODO にない。→ **採用**: T1 に zeitwerk バージョン確認を追記する

### Nice-to-have

- **旧 spec の削除を T7 でまとめると赤区間が長くなる** — T4/T5 完了後すぐに旧 spec を落とす方が常に全 green を維持しやすい。→ **採用**: T4/T5 それぞれで旧 spec の対応する部分を削除する方針に変更する
- **`Creator` の `move_to_backup` / `render` の spec 整理方針を明記** — 移行時に公開メソッドのテストをどう扱うか。→ **採用**: T5 の説明に「`private_class_method` 化するため直接テストは削除、間接的にカバーする」と追記する

### Out of scope

- `lib/nob/cli/` への分割（design.md の `cli/` 分割）— 今回スコープ外。後続 plan で追って整合させる。

---

レビュー実施日: 2026-05-02（実装後コードレビュー）

### Critical

- なし

### Important

- **`lib/nob/cli.rb:2` に `require_relative "../nob"` が残っている** — plan T7「require_relative を全て削除し、Zeitwerk のみに移行」と不整合。`exe/nob` 経由でなく `cli.rb` を直接 require した場合のみ意味があり、Zeitwerk セットアップ済みの想定では不要。 → **対応済**: `require_relative "../nob"` を削除（lib/nob/cli.rb）
- **plan の「実装と計画の差分（recap）」セクションが未記入** — 今回の差分（T6 を T4/T5 に前倒し、inflector の `version`/`cli` 上書き、cli.rb の `require_relative` 残存等）を Recap で記録すべき。 → **Recap フェーズで対応**

### Nice-to-have

- **`loader.inflector.inflect("version" => "VERSION")` の理由が未コメント** (lib/nob.rb) — 将来の読み手が必要性を辿れない。1 行コメントが望ましい。 → **対応済（別解決）**: 検証の結果 `Zeitwerk::GemInflector` が `version.rb → VERSION` をデフォルトで内蔵していたため、上書き自体を削除。さらに user 指摘で「`Nob::CLI` を `Nob::Cli` にすれば `cli` 上書きも不要」と判明し、定数をリネーム → inflector 上書き全廃（lib/nob.rb, lib/nob/cli.rb, exe/nob, spec/nob/cli_spec.rb）
- **`Nob::Notes::Creator::Result` と `Nob::Entities::Note` の役割差がソースに無記載** — 「作成結果 vs. 既存ノート値オブジェクト」の区別を short doc コメントで残すと混同事故を防げる。 → **対応済**: 両方のソースに 1〜2 行のコメント追加（lib/nob/entities/note.rb, lib/nob/notes/creator.rb）
- **`Lister.normalize_prefix` で `File.realpath(vault)` を呼ぶため vault 不在時に `Errno::ENOENT` がそのまま漏れる** — 既存挙動の踏襲なのでスコープ外でも可、`Nob::Error` 系で包む余地あり。 → **見送り**: 既存挙動の踏襲、本 plan のスコープ外。後続で扱う場合は別 plan に切り出す
- **`for_gem` のデフォルト `GemInflector` は `version.rb` を `VERSION` に解決するルールを内蔵している可能性** — `"version" => "VERSION"` の上書きが重複指定なら簡素化できる（要 zeitwerk 2.7.5 の挙動確認）。 → **対応済**: 内蔵ルールであることを実機で確認、上書きを削除（lib/nob.rb）

### Out of scope

- `nob.gemspec` の `required_ruby_version = ">= 4.0.0"` — Ruby 4.0 の制約は本 plan の対象外。
- `cli/` ディレクトリ分割 — 既に out-of-scope 宣言済み。

## 実装と計画の差分（recap）

### 意図的な変更

- **CLI 参照の切り替えを T6 から T4/T5 に前倒し**: plan は T4「Lister 新設＋note_list 削除」→ T5「Creator 新設＋note 削除」→ T6「CLI を新クラス名に切り替え」の順だったが、T4 で `note_list.rb` を削除した瞬間に CLI（`Nob::NoteList.list` 参照）が壊れることに着手時点で気づいた。常時 green を保つため、各オペレーション移行ステップ内で CLI 側の参照も同時切替に変更。T6 は cli_spec の green 確認のみ。
- **`inflector.inflect("version" => "VERSION")` を Refine で削除**: 実装時には Zeitwerk のロード失敗回避のため上書きを入れたが、Review で「`for_gem` のデフォルト `GemInflector` が内蔵している可能性」を指摘され、検証で内蔵確認 → 上書きを削除。

### 想定外の追加

- **`Nob::CLI` → `Nob::Cli` へのリネーム**: 当初は `Nob::CLI`（all-caps）のため `inflector.inflect("cli" => "CLI")` を入れたが、Recap 後の user 指摘「`Nob::Cli` で定義すれば inflector 設定自体不要」を採用してリネーム。Zeitwerk のデフォルト規約に乗せるのが最も簡素という判断。`exe/nob`, `spec/nob/cli_spec.rb` も追従。
- **`exe/nob` の require を `nob/cli` から `nob` に変更**: Refine で `cli.rb` の `require_relative "../nob"` を削除した結果、`exe/nob` 経由（`require "nob/cli"` のみ）で実行すると Zeitwerk セットアップを通らず `Nob::Error` 等が未定義になっていた。動作確認時に発覚。`require "nob"` に変えて lib/nob.rb の Zeitwerk セットアップを必ず通す形に修正。
- **`vendor/bundle` の再生成**: T1 着手時に mise の libruby (4.0.0 → 4.0.3) 不整合で `bundle install` が失敗。本 plan の対象外だが T1 完了に必要だったため、ローカル環境の `vendor/bundle` を削除して再インストール。

### 削除・スキップ

- なし。T1〜T8 すべて完了。

### 学び

- **旧実装の削除ステップは「参照側を新へ切り替えてから旧を削除」を 1 ステップ内で行う方が安全**: 「新オペレーション新設」と「CLI の参照切替」を別タスクに分けると、旧クラス削除 → CLI 参照切替の間で必ず壊れる赤区間が生まれる。次回から類似の置き換えでは、置き換え対象の参照箇所を巻き取って 1 ステップにする。
- **Zeitwerk の inflector 設定のような「実装してみないと出てこない補正」は plan で全部は読み切れない**: plan には「Zeitwerk セットアップ」という粒度までで十分。具体の inflector 上書きは実装時の発見として Recap に残せばよい。
- **autoloader 規約に合わせて定数名を選ぶのが最も簡素**: `Nob::CLI`（all-caps）にこだわらず `Nob::Cli` にすれば inflector 上書きが消せた。新規導入時は autoloader のデフォルト推論に乗る命名を最初から選ぶ。
- **`exe/<gem>` は `require "<gem>"` から始める**: 個別の `require "<gem>/cli"` だけだと Zeitwerk セットアップを経由せず autoload が動かない。テストは `spec_helper` 経由で gem 全体を require するため気付きにくい。
