# nob

Obsidian の vault をそのまま管理対象にして、CLI（と、今後は Neovim）からノートを操作するためのツールです。ノートは素の Markdown ファイルで、メタデータは YAML frontmatter で持ちます。

設計の詳細は [docs/design.md](docs/design.md) を参照してください。

## 必要なもの

- Ruby 4.0 以上（バージョンは `.ruby-version` を参照）
- Bundler

## インストール

```sh
git clone https://github.com/toshiemon18/nob.git
cd nob
bundle install
bundle exec exe/nob version
```

## 設定

設定ファイルは `$XDG_CONFIG_HOME/nob/config.toml` です（`XDG_CONFIG_HOME` が未設定なら `~/.config/nob/config.toml`）。初回実行時に雛形が作られるので、`nob config -e` で開いて `vault` を設定してください。

```toml
# vault のルート（必須）
vault = "~/Documents/MyVault"

[dailyNote]
basePath = "daily/"              # vault 相対。省略時は "daily/"
fileNameFormat = "%Y-%m-%d"      # strftime 形式。省略時は "%Y-%m-%d"
template = "templates/daily.md"  # vault 相対。省略時は空ファイルを作る

[note]
template = "templates/note.md"   # nob create 用。vault 相対。省略時は title / date の frontmatter を書く
```

テンプレートのパスは vault 相対で書きます（`--template` も同じ）。絶対パスや vault の外を指すパスはエラーになります。テンプレートの変数はエスケープされないので、frontmatter の中では `title: "{{title}}"` のようにクォートしてください。

テンプレートでは `{{title}}` `{{date}}` `{{date:%Y/%m/%d}}` `{{time}}` `{{id}}` などの変数を使えます。一覧は [docs/design.md](docs/design.md) の「テンプレート」を参照してください。

## コマンド

| コマンド | 説明 |
|----------|------|
| `nob create TITLE [--dir DIR] [--force] [--template PATH]` | ノートを作る。`--force` は既存ファイルをバックアップしてから作り直す。`--template`（`-t`）はその回だけ使うテンプレート |
| `nob list [--prefix PATH]` | vault 内のノートを vault 相対パスで 1 行ずつ出力する |
| `nob show TITLE` | ノートのパス、サイズ、文字数、frontmatter、リンクとその解決先を表示する。TITLE は大文字と小文字を区別しない |
| `nob links --unresolved` | vault 全体で、解決できないリンクと曖昧なリンクを `path:line: [[link]]` の形で出力する |
| `nob resolve LINK [--from PATH]` | リンク 1 つを解決先の絶対パスにして出力する。曖昧なら候補を 1 行に 1 件、未解決なら何も出さない（いずれも exit 0） |
| `nob daily [--force]` | 今日のデイリーノートを作る |
| `nob config -e \| --path \| --show` | 設定ファイルを編集・パス表示・内容表示する |
| `nob version` | バージョンを表示する |

書き込み先は vault 内に限られます。vault の外を指すパスや絶対パスを渡すと、`Error:` を出して終了コード 1 で終わります。

## 開発

タスクは [mise](https://mise.jdx.dev/) で定義しています。初回は `mise trust` でこのリポジトリの `mise.toml` を信頼してください。

```sh
mise run test              # RSpec
mise run lint              # rubyfmt --check
mise run fix               # rubyfmt で整形
mise run generate:typesig  # typeprof で sig/ を再生成
```

- フォーマッタは rubyfmt です。CI でも `rubyfmt --check` を実行します。
- `sig/` の RBS は typeprof の生成物です。手で編集せず、`generate:typesig` で作り直してください。型検査（steep など）はまだ導入していません。
- 機能単位の開発記録は `docs/plans/`、設計判断は `docs/adr/` にあります。

## ライセンス

[MIT License](LICENSE.txt)
