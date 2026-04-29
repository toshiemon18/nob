---
title: nob list — ノート一覧コマンド
slug: note-list
status: done
created: 2026-04-30
updated: 2026-04-30
---

## 目的・背景

design.md マイルストーン1 の 1 機能。vault 配下の Markdown ノートを CLI から列挙できるようにする。

- ユースケース: シェルや Neovim から `nob list` を叩いて、vault 内のノートをパイプで他コマンドに流す（fzf, grep など）
- スコープ: 再帰的に `.md` を拾い、vault 相対パスを 1 行 1 件で stdout へ出す
- `--prefix <path>` で部分木を絞り込む（design.md の表記準拠）

## 設計

### モジュール構成

- `Nob::NoteList`（新規 / `lib/nob/note_list.rb`）
  - vault 配下の `.md` を列挙する純粋ロジック。I/O は読み取りのみ。
- `Nob::CLI#list`
  - `Nob::Config.load` で vault を解決し、`NoteList.list` の結果を stdout へ整形出力。
- 既存の `Nob::Config` / `Nob::Error` をそのまま再利用。

### 公開 API（signature 案）

```ruby
Nob::NoteList::Entry = Struct.new(:absolute_path, :relative_path, keyword_init: true)

Nob::NoteList.list(vault:, prefix: nil)
  # => [Entry, Entry, ...]   # relative_path 昇順
```

例外:

- `Nob::NoteList::PrefixNotFound < Nob::Error` — prefix で指定されたディレクトリが存在しない
- `Nob::NoteList::InvalidPrefix < Nob::Error` — prefix が絶対パス、もしくは `..` を経由して vault 外を指す

### 列挙ルール

- 拾うのは `.md` 拡張子のみ（大文字小文字は区別しない方針 → MVP では `.md` のみで OK、`.MD` は対象外として後日検討）
- ディレクトリ・ファイル名が `.`（ドット）で始まるものはスキップ（`.git`, `.obsidian` など）
- バックアップファイル（`*.backup-*.md`）は **除外しない**。ノイズ除外は別オプションで後日対応
- 並び順: vault 相対パスの ASCII 昇順（`String#<=>`）。再現性のため明示的にソート
- 結果は `Entry` の配列。`relative_path` は `File::SEPARATOR` 区切り（POSIX のみ想定で `/`）

### prefix の解釈

- vault からの **相対パス** のみ受け付ける
- 末尾スラッシュは無視（`daily` と `daily/` は同義）
- 絶対パス（`/...` で始まる）→ `InvalidPrefix`
- 正規化後に vault の外を指す（`..` 経由）→ `InvalidPrefix`
- 存在しないディレクトリ → `PrefixNotFound`
- prefix がファイルを指している場合 → `InvalidPrefix`（ディレクトリ専用）

### CLI 出力フォーマット

1 行 1 ファイル、vault 相対パスのみ（パイプ前提）。フッターなし。

```
$ nob list
README.md
daily/2026-04-27.md
projects/Plan.md

$ nob list --prefix daily
daily/2026-04-27.md
```

該当 0 件 → 何も出さず exit 0。

### エラー時の振る舞い

- `Nob::Error` 系は既存 `create` と同じパターン: `warn "Error: ..."` → `exit 1`
- vault 未設定／不在は `Config#vault` がすでに `Nob::Error` を投げるので追加対応不要

### 設計判断メモ

- `Dir.glob("**/*.md", base: dir)` を採用 → シンボリックリンク追跡は OS デフォルト挙動に任せる（Obsidian vault は通常リンクを使わないため割り切り）
- ソートは Ruby 側で行う。glob の順序は OS 依存
- `Entry` 構造体に絶対パスも持たせるのは、後続の `nob show` がこれを再利用するため（先回り）

## TODO（TDDタスク分解）

`spec/nob/note_list_spec.rb` を新規作成し、t-wada 流に Red→Green→Refactor を回す。

- [x] **T1**: vault 直下の `.md` 1 件を列挙する最小ケース（Entry 1 件、relative_path / absolute_path が正しい）
- [x] **T2**: ネストしたディレクトリの `.md` を再帰的に拾う
- [x] **T3**: `.md` 以外（`.txt` など）は無視する
- [x] **T4**: `.` で始まるディレクトリ／ファイルはスキップする（`.obsidian/foo.md` を作って検証）
- [x] **T5**: 結果は relative_path 昇順でソートされている
- [x] **T6**: `prefix:` を渡すと指定サブディレクトリ配下のみ返る
- [x] **T7**: `prefix:` 配下のさらにネストした `.md` も再帰的に拾う
- [x] **T8**: `prefix:` の末尾スラッシュは無視される（`daily` と `daily/` が同等）
- [x] **T9**: 存在しない `prefix:` で `PrefixNotFound` を raise
- [x] **T10**: 絶対パス `prefix:` で `InvalidPrefix` を raise
- [x] **T11**: `..` で vault 外に出る `prefix:` で `InvalidPrefix` を raise
- [x] **T12**: ファイルを指す `prefix:` で `InvalidPrefix` を raise
- [x] **T13**: CLI 統合 — `Nob::CLI#list` を実装し、`spec/nob/cli_spec.rb`（必要なら新設）で stdout 出力と `--prefix` フラグ動作を確認
- [x] **T14**: CLI のエラーパス（`Nob::Error` を `warn` + `exit 1`）の動作確認
- [x] **T15**: `spec/fixtures/vault/` を作成（`README.md` / `daily/2026-04-30.md` / `projects/Plan.md` / `.nob/cache.md`（将来の vault ごとキャッシュ想定） / `ignore-me.txt`）
- [x] **T16**: `spec/support/fixture_vault.rb` ヘルパ（fixture vault パス・tmpdir に config.toml 生成）と `spec_helper.rb` への auto-require 追加
- [x] **T17**: `spec/nob/cli_spec.rb` を fixture ベースに書き換え（tmpdir vault 撤去、config.toml は tmpdir に動的生成）
- ~~**T18**: `spec/integration/exe_nob_spec.rb` 新設（Open3）~~ — 削除。`cli_spec.rb` が `Nob::CLI.start` を直接呼んでいるため追加価値なし。「いつ落ちてほしいか」が答えられないテストは書かない
- [x] **T19**: `bundle exec rspec` 全体グリーンを確認（23 examples, 0 failures）

最後に `bundle exec rspec` がオールグリーンであること、`exe/nob list` を手で叩いて動作することを確認。

## レビューフィードバック

レビュー実施日: 2026-04-30

### Critical

- `Dir.glob("**/*.md", base: base)` がドット始まりのディレクトリをスキップしない可能性 (`note_list.rb`) — `**` は FNM_DOTMATCH なしでも `.` 始まりのサブディレクトリを再帰対象にするとの指摘。ただし T4 のテスト（`.obsidian/config.md`, `nested/.cache/x.md` がスキップされる）は Green。→ **却下**: `ruby -e` で実機確認済み。Ruby の `Dir.glob("**/*.md")` は FNM_DOTMATCH なしではドット始まりディレクトリを再帰しない。テストの Green は正当。

### Important

- `normalize_prefix` 内の `File.realpath(vault)` が vault 不在時に `Errno::ENOENT` を素通しする (`note_list.rb`) — `Config#vault` が存在チェック済みのため直接ルートでは問題ないが、`NoteList.list` を Config なしで呼ぶケースで意図しない例外になりうる。→ **見送り**: `Config#vault` が呼び出し前に vault 存在を保証している。`NoteList.list` は vault が有効なディレクトリであることを前提とする旨を将来 YARD doc で明記する
- `cli_spec.rb` のテスト名「prints nothing when the prefix contains no notes」と本文が矛盾（`projects/` は `Plan.md` を返す）。0 件の CLI 結合テストが存在しない。→ **対応済**: テスト名を "filters by --prefix to projects/" に修正、空 vault コンテキストで 0 件ケースを追加

### Nice-to-have

- `FixtureVault` が全 example に `include` されており、`setup_fixture_config!` が全 context に混入する (`fixture_vault.rb`) — `shared_context` + `include_context` で opt-in にする方が明示的。→ **対応済**: `RSpec.shared_context "fixture vault"` に変更、`cli_spec.rb` で `include_context` を明示
- `normalize_prefix` / `validate_base!` が `private_class_method` になっていない — 公開 API として設計されていない内部メソッドは隠蔽すべき。→ **対応済**: `private_class_method :normalize_prefix, :validate_base!` を追加

### Out of scope

- `File.realpath` の I/O コスト（vault 固定なら呼び出し元キャッシュ検討）— 現時点では問題なし。将来の最適化候補。

## 実装と計画の差分（recap）

### 意図的な変更

- **T18（Open3 integration spec）を削除**: 「いつ落ちてほしいか答えられないテストは書かない」という判断。`cli_spec.rb` の `Nob::CLI.start` 直接呼び出しが実質的に同等の保証を与えており、subprocess テストの追加価値が薄かった
- **`FixtureVault` の設計変更**: 当初グローバル `include` としていたが、全 example への混入を避けるため `RSpec.shared_context` + `include_context` の opt-in 方式に変更（Refine で対応）

### 想定外の追加

- **fixture vault の導入（T15〜T17）**: 当初計画に無かったが、手動 smoke test を廃止しつつ CLI の結合テストを自動化するために追加。`spec/fixtures/vault/` に読み取り専用 fixture を置き、設定ファイルのみ tmpdir に動的生成するパターンを確立した
- **`.nob/` の dot-dir スキップ検証**: fixture に `.nob/cache.md` を置くことで、将来の vault ごとキャッシュ機能を見据えたスキップ保証を同時に得た
- **`private_class_method`**: plan の設計に記載なかったが Refine で追加。内部メソッドの隠蔽は小さいが将来の誤用防止に効く

### 削除・スキップ

- **Important: `File.realpath` の `Errno::ENOENT` 対応**: `Config#vault` が vault 存在を保証しているため見送り。将来 `NoteList` を単体で使うユースケースが生まれた際に対応（後続: `note-list-hardening` 等）
- **T1〜T12 のチェックボックスが plan 上 `[ ]` のまま**: 実装は完了しているが plan の TODO 更新を Implement フェーズ中に漏らした。Recap 時点で確認済み → 実装は全て Green
