# nob Design Document

## 概要

ObsidianライクなノートをCLIおよびNeovimから操作できるノート管理ツールチェイン。
既存のObsidian vaultをそのまま管理対象にすることを想定する。

## ゴール

- Markdownファイルを実ファイルとして管理する
- CLIおよびNeovimから操作できる
- シンプルな機能セットに絞り、自分が最低限必要とする機能のみを実装する

## スコープ

### 対象

- `lib/nob/` : コアロジック（Vault / Config / Templates）
- `lib/nob/cli.rb` : CLIコマンド定義
- `exe/nob` : エントリーポイント
- Neovimプラグイン : CLIをサブプロセスで呼び出す

### 対象外

- HTTP API
- Web UI

---

## 技術スタック

| 項目 | 選定 |
|------|------|
| 言語 | Ruby |
| Runtime | MRI Ruby |
| 出力 | 実行可能gem（`gem install` または `bundle exec`） |
| パッケージ構成 | 単一gem |
| CLIフレームワーク | Thor |
| TUIライブラリ | tty-prompt（TUIフェーズ着手時に導入予定。現時点ではgem依存に含めていない） |
| TOMLパーサ | toml-rb |
| フロントマターパーサ | front_matter_parser |

---

## プロジェクト構成

単一gemとして管理する。ロードは zeitwerk に任せ、`lib/nob/` 配下のファイルパスと定数名を一致させる。

```
nob/
  lib/
    nob.rb              # エントリ（zeitwerk の setup、Nob::Error）
    nob/
      cli.rb            # CLIコマンド定義（Thor）
      config.rb         # config.toml の読み込みと検証
      config/
        editor.rb       # nob config -e のエディタ起動
        key.rb          # 設定キー（section / name / default）
        keys.rb         # nob が読む設定キーの一覧
      vault.rb          # vault 内のファイル操作（パス組み立て、列挙、frontmatter、バックアップ）
      templates.rb      # テンプレートの facade（Templates.render / Templates.locate）
      templates/
        parser.rb       # 字句解析
        renderer.rb     # 評価
        operators.rb    # 変数名 → オペレータのファクトリ
        operators/      # title / date / time / id
      version.rb
  exe/
    nob                 # 実行可能ファイル
  sig/                  # RBS（typeprof で生成）
  spec/                 # テスト
  nob.gemspec
```

---

## CLI仕様

### ルートコマンド

`nob`単体で実行するとTUIを起動する。

**TUI操作体系**
```
/  → ファイル名の曖昧検索モード
// → ファイル内容の曖昧検索モード
Enter → $EDITOR をサブプロセスで起動
q  → 終了
```

**検索スコープ**
- デフォルト: vaultルート以下全体
- `nob --prefix <path>`: 指定パス以下に絞る

**TUIライブラリ**: `tty-prompt` をベースとし、必要に応じて他のライブラリを移植・追加する。TUIフェーズ着手時に gem 依存として再追加する（現時点では未導入）

### サブコマンド一覧

```
nob create <title>           # ノート作成
nob list [--prefix <path>]   # ノート一覧（prefixで絞り込み）
nob show <title>             # メタデータ・リンク情報表示
nob daily                    # デイリーノート作成
nob daily --force            # 強制再作成（既存はバックアップ）
nob links --unresolved       # 未解決・曖昧なリンクをvault全体で一覧表示
nob resolve <link> [--from <path>]  # リンク 1 つを解決先の絶対パスに変換
nob config -e                # configをエディタで編集
```

### 出力チャンネルの慣習

サブコマンドが書き出す先と prefix を以下に統一する。後続コマンド追加時もこの規約に従う。

| チャンネル | prefix | 終了コード | 例 |
|-----------|--------|----------|----|
| stdout | （prefix なし） | 0 | `Created: ...` / `Recreated: ... (backup: ...)` / `Already exists: ...` |
| stderr | `Error: ` | 1 | `Error: vault directory does not exist: ...` |
| stderr | `Warning: ` | 0 | `Warning: no daily-note template configured ([dailyNote].template); creating an empty file.` / `Warning: unknown config key ...` |

- **`Error: `**: 致命的エラー。コマンドの主目的を達成できず、ユーザー側の対処（config 修正・引数見直し）が必要。`exit 1` で終了。`Nob::Error` ラップ方針の詳細は `docs/adr/0002_error-policy.md`
- **`Warning: `**: 継続可能な注意。コマンドは目的を達成しているが、ユーザーが意図しているか確認したい状況（テンプレ未指定で空ファイル生成、等）。`exit 0` のまま
- **prefix なし**: 通常の情報出力。stdout に書き、機械可読 / パイプ可能な形を保つ

---

## マイルストーン1（最初のゴール）

以下のコマンドが動くこと：

```
nob create <title>           # ノート作成
nob list                     # ノート一覧
nob show <title>             # ノート情報参照
```

---

## 機能仕様

### Config

- 形式: TOML
- 場所: `$XDG_CONFIG_HOME/nob/config.toml`（未設定の場合は`~/.config/nob/config.toml`）
- 初回起動時にファイルが存在しなければデフォルト値で自動生成する
- `nob config -e` でエディタを開いて編集できる（`$EDITOR`を参照、未設定の場合は`vi`）
- `$EDITOR` は `code -w` のような引数付きを許容するため shell 形式で起動する。ユーザ自身の環境変数を信頼する前提で、信頼できない `$EDITOR`（例: `evil; rm -rf ~`）の保護は行わない
- nob が知らないキーがあれば、キーごとに `Warning: unknown config key [note].tempalte in <config のパス> (did you mean [note].template?)` を stderr に出し、そのまま続行する。候補は似たキーがあるときだけ付ける
  - 検査するのは config を読むコマンド（create / show / daily / list）だけ。`nob config` は検査しないので、vault が未設定でも編集できる
  - 値の型は検査しない

---

### ノート管理

- ノートはMarkdownファイルとして実ファイルで管理する
- メタデータはfrontmatter（YAMLヘッダ）で管理する
- 管理対象ディレクトリ（vault）はconfigで指定する
- 書き込み先は vault 内に限る。`create` の title・`--dir`、`daily` の basePath・fileNameFormat に絶対パスや vault の外を指す `..` が含まれる場合は `Error: ` で終了する
  - 判定はパスの字句的な正規化（`File.expand_path`）で行い、symlink の追跡はしない

---

### テンプレート

#### テンプレートファイル

- テンプレートは vault 内の通常の Markdown ファイルとして管理し、エディタで直接編集する
- 機能ごとの config キーで指定する（`[note].template`、`[dailyNote].template`）。共通のテンプレートフォルダは持たない（ADR 0001）
- `nob create` は `--template PATH`（`-t`）で、その回だけテンプレートを指定できる
- パスはすべて vault 相対で解決する（`--template` も cwd ではなく vault 基準）。絶対パスと vault の外を指すパスは `Error: ` で終了する。メッセージには指定元（`--template` / `[note].template` / `[dailyNote].template`）を付ける

#### 展開と書き込み

- 展開結果はそのまま書き込む。nob は frontmatter を足さず、YAML として正しいかも検証しない
- テンプレートがない、構文エラーがある、未定義の変数がある場合は `Error: ` で終了し、ノートを作らない
- テンプレートの展開に成功してから、`--force` のバックアップと書き込みを行う。失敗したときは既存ファイルにも vault にも手を付けない
- 変数はエスケープしない。frontmatter の中で使うときは `title: "{{title}}"` のようにクォートする。タイトルに `"` が含まれる場合は、クォートしても YAML として壊れる

#### 変数展開

テンプレート内で以下の変数を使用できる：

| 変数 | 出力例 | 説明 |
|------|--------|------|
| `{{title}}` | `My Note` | ノートのタイトル |
| `{{date}}` | `2024-03-27` | 今日の日付（YYYY-MM-DD） |
| `{{date:%Y/%m/%d}}` | `2024/03/27` | フォーマット指定（strftime 形式） |
| `{{date:timestamp}}` | `1711497600` | unixtime |
| `{{time}}` | `09:00` | 現在時刻（HH:mm） |
| `{{time:%H:%M:%S}}` | `09:00:00` | フォーマット指定（strftime 形式） |
| `{{time:timestamp}}` | `1711497600` | unixtime |
| `{{id}}` | `20240327090000` | ZettelkastenのID |

- 変数展開は固定変数＋フォーマット指定のみ対応する
- 任意のコード実行は行わない（セキュリティ上の理由）

---

### ノート作成（`nob create`）

```toml
[note]
template = "templates/note.md"   # vault 相対。省略時は title / date の frontmatter を書く
```

- 使うテンプレートの優先順位は `--template` > `[note].template` > 既定の出力
- 既定の出力は `YAML.dump` で作るので、`:` などを含むタイトルも正しくクォートされる

---

### デイリーノート

#### 設定

```toml
[dailyNote]
basePath = "daily/"            # vault 相対。省略時は "daily/"
fileNameFormat = "%Y-%m-%d"    # strftime 形式。省略時は "%Y-%m-%d"
template = "templates/daily.md" # vault 相対。省略時は空ファイルを作成し Warning を出す
```

#### 通常作成 `nob daily`

```
1. {basePath}/{fileNameFormat}.md のパスを決定
2. ファイルが存在しない → テンプレートから作成
3. ファイルが存在 かつ 1byte以上 → スキップ（何もしない）
4. ファイルが存在 かつ 0byte → テンプレートから作成
```

#### 強制作成 `nob daily --force`

```
1. {basePath}/{fileNameFormat}.md のパスを決定
2. ファイルが存在しない → テンプレートから作成
3. ファイルが存在 →
     {basePath}/{fileNameFormat}.backup-YYYYMMDD-HHmmss.md に移動
     → テンプレートから新規作成
     → バックアップパスを通知する
```

バックアップファイル名の例：
```
daily/2024-03-27.backup-20240327-153045.md
```

---

### リンク（`[[]]`記法）

#### 記法と取り出し

- `[[name]]`、`[[name|別名]]`、`[[name#見出し]]`、`[[name#^block]]`、`![[name]]`（埋め込み）をリンクとして扱う
- リンク先は `|` と `#` より前の部分。見出しとブロックが実在するかは検証しない
- 名前が空のリンク（`[[#見出し]]`）は対象外
- frontmatter、フェンスで囲んだコードブロック（```` ``` ```` / `~~~`）、インラインコードの中は無視する。frontmatter は YAML として解釈せず、先頭行の `---` から次の `---` までを飛ばす（閉じがなければファイル全体を本文とみなす）

#### リンク先解決ルール

```
[[note-name]] の解決:
  1. NFC に正規化し、大文字と小文字を区別せずに照合する（[[note-name.md]] も同じ）
     - "/" を含まなければファイル名と、含めば vault 相対パスの末尾と照合する
     - .md 以外の拡張子が付いていれば、添付ファイルも対象にする
  2. 1件見つかった → そのファイルへのリンク
  3. 0件（未存在） → 未解決リンクとして扱う
  4. 複数件見つかった → リンクを書いたノートに最も近いものを選ぶ
     （距離 = 共通の祖先まで上がる段数 + そこから下る段数）
     最も近いものが複数あれば曖昧として扱い、候補を示す
```

未解決リンクや曖昧なリンクがあってもシステムはエラーにならず動作を継続する。最も近いものを選ぶ規則の経緯は `docs/adr/0003_link-resolution.md`。

`nob show TITLE` のタイトルも、NFC と大文字小文字の規則は同じ。距離の起点がないので、複数件見つかればエラーにする。

#### nob show でのリンク表示

`nob show`はそのノートのリンク一覧を出力する。本文に書いたとおりの文字列で、同じものは 1 回だけ、初めて出た順に並べる。リンクがなければ節を出さない。

ノートは既定の外部エンコーディング（`LANG`）によらず UTF-8 として読む。UTF-8 として読めなければ `Error: invalid UTF-8 in <path>` / exit 1。

```
Path     : daily/2024-03-27.md
Size     : 1.2KB
Chars    : 1024
---frontmatter---
title    : 2024-03-27
date     : 2024-03-27
---links---
[[existing-note]]  → daily/existing-note.md
[[missing-note]]   → (unresolved)
[[Note]]           → (ambiguous: a/Note.md, b/Note.md)
```

#### 未解決リンクの一覧

```
nob links --unresolved    # vault全体の未解決リンクと曖昧なリンクを一覧表示
```

```
daily/2024-03-27.md:12: [[missing-note]]
daily/2024-03-27.md:15: [[Note]] (ambiguous: a/Note.md, b/Note.md)
```

- `<ノートの vault 相対パス>:<行番号>: <リンク>` の形で 1 行に 1 件。行番号はファイル先頭から数える（Neovim の quickfix にそのまま読み込める）
- 並びはパス順、同じノートの中では行順。重複は除かない
- 見つかっても終了コードは 0
- UTF-8 として読めないノートは `Warning: skipped <path>: invalid UTF-8` を出して飛ばす

#### リンク 1 つの解決 `nob resolve`

```
nob resolve '[[Plan|計画]]' --from daily/2024-03-27.md
```

Neovim からリンク先へジャンプするための入口。解決の規則は上の「リンク先解決ルール」と同じ。

- `<link>` は `[[...]]` か `![[...]]` がちょうど 1 つの文字列（前後の空白は除く）。括弧なし、前後に文字がある、2 件以上、名前が空（`[[#見出し]]`）は `Error: expected a single [[link]]: <link>` / exit 1
- 見出しとブロック参照（`#` 以降）は捨てる。ファイルを開くところまでが対象
- `--from` はリンクを書いたノートのパス。距離の起点になる
  - 絶対パスでも相対パスでもよい。相対パスは vault を基準にする
  - 存在しなくてよい（保存前のバッファ）
  - 字句的に vault の外なら、vault と `--from` の両方を realpath にしてもう一度判定する（symlink 経由の vault）。`--from` は存在しないことがあるので、実在する一番深い親ディレクトリまでを realpath にする
  - 相対パスの先頭の `~` はホームディレクトリに展開しない（ファイル名の一部として扱う）
  - vault の外なら `Error: --from is outside the vault: <path>`、ディレクトリなら `Error: --from is not a file: <path>` / exit 1
  - 省いたら vault 直下のノートから書いたものとして測る
  - vault のルート（`.`）はディレクトリなので `--from is not a file` になる
- 判定できれば結果によらず exit 0。結果は stdout の行数で区別する

| 結果 | stdout |
|---|---|
| 解決 | 絶対パスを 1 行 |
| 曖昧 | 最も近い候補の絶対パスを 1 行に 1 件（パス順。必ず 2 行以上） |
| 未解決 | 空 |

- 出力する絶対パスは、config の `vault`（`~` は展開する）に vault 相対パスを足したもの。symlink は追わないので、`--from` に実体側のパスを渡しても、出力は config に書いた側のパスになる

#### 新規ノート作成時の配置

リンクを記述したファイルと同じディレクトリ（兄弟）に配置する。

```
# 例
/daily/2024-03-27.md に [[new-note]] を記述
→ /daily/new-note.md として作成
```

リンクからの新規ノート作成のトリガーはNeovim連携側で定義する（フェーズ2以降）。

---

### Zettelkasten

現時点ではおまけ機能として位置づける。詳細仕様は後回し。

---

## Neovim連携

### 方針

- CLIバイナリをサブプロセスとして呼び出す
- DLL的な統合は行わない
- サブプロセス方式の利点：
  - Neovimがクラッシュしても影響を受けない
  - nobのバージョン管理がNeovimと独立する
  - CLIとして単体でデバッグできる

### 実装フェーズ

```
フェーズ1: vim.fn.system('nob create xxx') で叩くだけ。リンク先へのジャンプは nob resolve の出力を :edit に渡す
フェーズ2: Telescopeと組み合わせてノート一覧をファジー検索
フェーズ3: ちゃんとしたNeovimプラグインとしてパッケージ化
```
