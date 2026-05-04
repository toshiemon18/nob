---
title: Nob::Error のラップ方針
number: 0002
status: accepted
date: 2026-05-04
---

## コンテキスト

`nob` のドメイン層 (`Notes::*`, `Templates::*`, `Config`) は実行中にさまざまな例外に遭遇する。出どころを大別すると 3 種類:

1. **ユーザーの設定や入力に起因するエラー**: vault が未設定、frontmatter YAML が壊れている、`--prefix` が vault を抜けている、テンプレートに未定義変数が書かれている、等。多くは `nob config -e` や個別ファイルの修正で直せる
2. **ライブラリ由来の汎用例外**: `Errno::ENOENT` / `Errno::EACCES` / `Psych::SyntaxError` / `ArgumentError` 等。Ruby 標準ライブラリ・依存 gem が投げる
3. **プログラマのミス**: 引数の型違反、`NoMethodError` 等。バグ

CLI 層 (`Nob::Cli`) は現状サブコマンド単位で `rescue Nob::Error => e; warn "Error: #{e.message}"; exit 1` を書いており、ユーザー向けに整形できるのは `Nob::Error` 派生だけ。それ以外はスタックトレースが出る。

「どの例外を `Nob::Error` 派生にラップして CLI に届けるか」のルールが今までコードベースを横断して文書化されておらず、新規コード追加時の指針が無かった。例として `Viewer::InvalidFrontmatter` は `Psych::SyntaxError` をラップしているが、`Errno::ENOENT` は素通しで、両者の判断軸が暗黙だった。

本 ADR でこの判断軸を固定する。

## 用語

- **ラップ**: ライブラリ例外（`Errno::*` 等）を catch して `Nob::Error` 派生例外を新たに raise すること。元例外のメッセージを引用しても構わないが、種類自体は ` Nob::Error` 派生になる
- **素通し**: ライブラリ例外をそのまま伝播させること。CLI 層では catch されず、Ruby 既定のスタックトレースで終了する

## 決定

### A. 判断軸: 「ユーザーが直せるエラーか」

ライブラリ例外を catch するかどうかは、その例外が**ユーザーの設定 / 入力 / 操作で発生しうる**ものかで判定する。

- **ラップする**: ユーザーが `nob config -e` / vault 内のファイル修正 / コマンド引数の見直し等で直せるエラー。CLI 層に届けてユーザー向けメッセージに変換する
- **素通しする**: ユーザーが直接対処できないエラー（運用ミス、レース、ファイルシステム破損、プログラマのバグ）。スタックトレースが出る方が原因究明が早い

### B. ラップ済み・素通しの具体例

| 状況 | 元例外 | 扱い | 派生クラス |
|------|--------|------|-----------|
| `vault` 未設定 / 不在ディレクトリ | （無し、自前検出） | raise | `Nob::Error`（直接） |
| `--prefix` が vault を抜けている | （無し、自前検出） | raise | `Notes::Lister::InvalidPrefix` |
| `--prefix` ディレクトリが存在しない | （無し、自前検出） | raise | `Notes::Lister::PrefixNotFound` |
| `nob show` で title 未マッチ | （無し、自前検出） | raise | `Notes::Viewer::NotFound` |
| `nob show` で title 複数マッチ | （無し、自前検出） | raise | `Notes::Viewer::Ambiguous` |
| frontmatter YAML が壊れている | `Psych::SyntaxError` | **ラップ** | `Notes::Viewer::InvalidFrontmatter` |
| テンプレートに未定義変数 | （無し、自前検出） | raise | `Templates::UndefinedVariable` |
| テンプレート構文エラー | （無し、自前検出） | raise | `Templates::ParseError` |
| `nob create` で既存ファイル（force 無し） | （無し、自前検出） | raise | `Notes::Creator::AlreadyExists` |
| `--force` 同秒バックアップ衝突（create / daily 共通） | （無し、自前検出） | raise | `Nob::Error`（直接） |
| 対象ファイルがレースで消えた | `Errno::ENOENT` | **素通し** | — |
| パーミッション不足 | `Errno::EACCES` | **素通し** | — |
| 引数の型違反 | `ArgumentError` / `TypeError` | **素通し**（バグ） | — |
| `strftime` のフォーマットエラー | `Errno::*` 系 / `ArgumentError` | **素通し** | — |

### C. 命名規約

- `Nob::Error` 派生は `Nob::<モジュール>::<具体エラー名>` の階層に置く
- 具体エラー名は短い名詞句にする（`NotFound`, `Ambiguous`, `InvalidPrefix`, `AlreadyExists`, `InvalidFrontmatter`, `ParseError`, `UndefinedVariable` 等）
- 名前空間が共通の例外でも、別モジュールで同名のクラスを作って構わない（衝突回避のため `Notes::Viewer::NotFound` のように完全修飾で参照）

### D. CLI 層の責務

- CLI 層は `rescue Nob::Error => e` で全派生をまとめて拾う前提。`Notes::Viewer::NotFound` 等の具体クラスを CLI が個別に rescue することは原則しない
- ライブラリ例外が CLI 層に到達した場合は素通しでよい（`exit_on_failure?` が Thor 側で例外を表示してくれる）。CLI は ライブラリ例外を catch しない
- **集約方式**: Thor の `Thor::Invocation#invoke_command(command, *args)` を `Cli` 内で override し、`super` を `rescue Nob::Error => e` で囲む。これで全サブコマンドが共通の rescue 経路を通る（`cli-aggregation` サイクル, 2026-05-05 で採用）

```ruby
class Cli < Thor
  no_commands do
    def invoke_command(command, *args)
      super
    rescue Nob::Error => e
      warn "Error: #{e.message}"
      exit 1
    end
  end
end
```

- 採用理由: Thor 1.x には `rescue_from` のような専用宣言が無く、`invoke_command` が dispatch 経路上唯一の hook。各サブコマンド末尾の rescue 重複を消せる
- 例外: `config` コマンドの引数バリデーション（`-e/--path/--show` の同時指定 / 全省略）は `Nob::Error` ではなく **直接 `warn + exit 1`** する経路で、こちらは集約対象外

### E. ラップする実装パターン

ラップする場合の最小形:

```ruby
parsed = begin
  FrontMatterParser::Parser.parse_file(abs, loader: YAML_LOADER)
rescue Psych::SyntaxError => e
  raise InvalidFrontmatter, "invalid YAML frontmatter in #{rel}: #{e.message}"
end
```

- `rescue` は最小スコープに絞る（メソッド全体ではなく、ライブラリ呼び出し 1 行を `begin/rescue/end` で囲む）
- メッセージは「**ユーザーが該当ファイルを開いて直せる情報**」を含める（相対パス、行番号など）
- 元例外のメッセージは含めてよいが、CLI ユーザーに見せて意味のある内容かは要判断

## 帰結

**利点**

- 新規コードでライブラリ例外に遭遇したとき「ラップするか素通しか」を判断軸 A に当てはめて即決できる
- ユーザーが見るエラーが整形済みのメッセージに揃う（ラップ対象のもの）。素通しは「これは普通のユーザーは遭遇しないはず」という暗黙のシグナルになる
- `Nob::Error` 派生の階層が命名規約 (C) に従って整理される

**受容するトレードオフ**

- ユーザーが対処可能な経路を新たに発見するたびに「素通しからラップに昇格」する作業が発生しうる。例えば「`Errno::EACCES` も実はユーザーが chown で直せるのでラップすべき」のような議論。本 ADR では現状の判断（素通し）を採るが、運用してみて頻発するなら見直す
- ラップは元例外を握りつぶすので、デバッグ時に元の発生地点を辿りにくくなる。最小スコープの `rescue` で副作用を抑える運用で対処
- `--debug` モードのような「ラップ対象も素通しで見せる」機能は本 ADR では決めない（必要になったら別 ADR）
