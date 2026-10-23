---
title: create のテンプレート対応とテンプレートパスの vault 内制限
slug: create-template
status: reviewing
created: 2026-10-23
updated: 2026-10-23
---

## 目的・背景

`nob create` は `render_create_content` で frontmatter（title / date）を直接書いており、テンプレートを使えない。daily は `[dailyNote].template` を `Templates.render` で展開している。create も同じようにテンプレートからノートを作れるようにする。

あわせて次の 2 点を直す。

- テンプレートのパスに vault の外や絶対パスを書けてしまう。ADR 0001 の前提は「テンプレートは vault 相対パスで指定する」だが、daily の実装はこれから外れている
- `nob daily --force` は既存ファイルをバックアップしてからテンプレートを展開する。そのため展開に失敗すると、元のファイルはバックアップに移ったまま新しいノートが作られない

設計の論点は 2026-10-23 に grilling で合意した（Q1〜Q15）。

## 設計

### config と CLI

```toml
[note]
template = "templates/note.md"   # vault 相対。省略時は従来の frontmatter（title / date）
```

```
nob create TITLE [--dir DIR] [--force] [--template PATH | -t PATH]
```

- 使うテンプレートの優先順位: `--template` > `[note].template` > 組み込みの既定出力（`YAML.dump` で作る title / date の frontmatter。Warning なし）
- `--template` の相対パスも vault 基準で解決する（cwd 基準ではない）
- ディレクトリごとのテンプレート切り替えと、daily への `--template` 追加はスコープ外

### テンプレートパスの解決（Config）

```ruby
Nob::Config::NoteSettings = Struct.new(:template_path, keyword_init: true)

# (String?, source: String) -> String?
config.resolve_template(raw, source:)   # 空や nil なら nil。それ以外は Vault.path_for(vault, raw)
config.note_settings   # -> NoteSettings（[note].template を source "[note].template" で解決）
config.daily_settings  # -> DailySettings（template_path を source "[dailyNote].template" で解決）
```

- 解決には `Vault.path_for` を使う。vault の外を指すパスと絶対パスは拒否する（symlink は検査しない）
- `Vault::InvalidPath` を捕まえて、指定元を付けた `Config::InvalidTemplatePath < Nob::Error` として投げ直す
  - 例: `template path escapes the vault: ../tpl.md ([note].template)`
  - 例: `template path must be relative to the vault: /etc/tpl.md (--template)`
- `--template` は CLI から `config.resolve_template(options[:template], source: "--template")` で解決する。解決処理は 1 か所にまとめる
- **破壊的変更**: `[dailyNote].template` に絶対パスを書いていた設定はエラーになる

### 展開と書き込みの順序（CLI）

- 書き込み先の決定 → テンプレートの解決と展開 → 既存ファイルの判定（`--force` ならバックアップ） → 書き込み、の順にする。展開に失敗したら vault には何も触れない
  - create: 既存ファイルがあり `--force` もない場合のエラーは、今と同じく書き込みより前に出す。展開とどちらを先にするかは問わない（どちらも副作用がない）
  - daily: 「既存ファイルが 1 byte 以上ならスキップ」の判定は展開より前でよい（スキップ時はテンプレートを読まない）。直す順序は「展開 → バックアップ」の部分だけ
- テンプレートの展開結果は、そのまま書き込む。frontmatter を足さず、YAML として正しいかも検証しない
- テンプレートがない、構文エラーがある、未定義の変数がある、といった場合は `Error:` / exit 1 にし、ノートを作らない（`Templates.render` の既存の例外を使う）
- 変数はエスケープしない。frontmatter の中では `"{{title}}"` とクォートすること、`"` を含むタイトルではそれでも壊れること、をドキュメントに書く

### テストする seam

| seam | 捕まえるもの | 捕まえないもの |
|------|-------------|---------------|
| S1: `Nob::Cli.start([...])`（一時 vault + config） | 書き込まれた内容、stdout / stderr、exit code、失敗時に何も書かずバックアップもしないこと、テンプレートの優先順位 | パス解決の細かい分岐（S2 で見る） |
| S2: `Nob::Config#resolve_template` / `#note_settings` / `#daily_settings` | vault 相対の解決、vault の外と絶対パスの拒否、指定元付きのメッセージ | CLI からの結線 |

`Templates` と `Vault` は変更しないので、新しいテストは足さない。

## TODO（TDDタスク分解）

各 TODO は 1 本の縦スライス（テスト 1 つ → 最小の実装）を積み重ね、green になったら 1 コミットにする。

- [x] **T1**: `Confine template paths to the vault in Config`（S2）
    - `resolve_template(raw, source:)` と `InvalidTemplatePath` を追加し、`daily_settings` から使う
    - 既存の spec「leaves an absolute template path as-is」は、絶対パスを拒否する spec に置き換える（破壊的変更）
- [x] **T2**: `Add Config#note_settings for [note].template`（S2）
    - 未設定なら `template_path` は nil。設定されていれば vault 相対で解決する。vault の外を指せば source が `[note].template` のエラーにする
- [x] **T3**: `Render create from [note].template`（S1）
    - テンプレートを設定すると、展開結果がそのまま書かれる
    - 未設定なら従来の frontmatter になる（既存の spec は出力行だけを見ていて中身を検証していなかったため、`:` を含むタイトルのクォートも含めて spec を追加）
    - テンプレートがない / 構文エラーなら exit 1 にし、ファイルを作らない
    - `--force` のとき、展開に失敗したら既存ファイルをバックアップせず元のまま残す
- [x] **T4**: `Add --template option to create`（S1）
    - `--template` が `[note].template` より優先される
    - vault 基準で解決し、vault の外を指せば `(--template)` 付きのエラーで exit 1 にする
- [x] **T5**: `Render daily template before backing up on --force`（S1）
    - テンプレートがない状態で `daily --force` を実行したとき、既存ファイルが元のまま残り、バックアップも作られないこと
- [x] **T6**: `Document note templates and vault-relative template paths`
    - `design.md`（config 例、`--template`、クォートの注意、順序）、README、ADR 0001 の改訂注記、ADR 0002 の例外表、`DEFAULT_CONTENT` の `[note]` 例（コメントアウト）
    - `generate:typesig` で `sig/` を作り直す

## レビューフィードバック

## 実装と計画の差分（recap）

### 実装中に分かったこと（Review 前のメモ）
- T3: plan では「未設定時の frontmatter は既存の spec で担保」としていたが、既存の spec は出力行しか見ていなかった。`:` を含むタイトルのクォートも含めて spec を追加した
- T3 / T4 / T1 の一部の spec は、先行するスライスの実装で最初から通った。展開の順序の spec は、順序を逆にした実装で失敗することを確認した
- 後続の候補: Thor が未定義オプションで `exit` すると、RSpec は途中で止まったまま「0 failures」/ exit 0 で終わる（T4 の Red で発覚）。CLI の spec が黙って打ち切られるテスト基盤の穴
- 後続の候補: typeprof の推論が不正確（`resolve_template -> nil`、`recreated: false`）。生成物なので手では直していない
