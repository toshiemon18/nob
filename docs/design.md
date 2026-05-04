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

- `lib/nob/core` : コアロジック
- `lib/nob/cli` : CLIコマンド定義
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

単一gemとして管理する。コアロジックとCLIを同一プロジェクト内でディレクトリ分離する。

```
nob/
  lib/
    nob/
      core/   # コアロジック
      cli/    # CLIコマンド定義
  exe/
    nob       # 実行可能ファイル
  spec/       # テスト
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
nob links --unresolved       # 未解決リンクをvault全体で一覧表示
nob config -e                # configをエディタで編集
```

### 出力チャンネルの慣習

サブコマンドが書き出す先と prefix を以下に統一する。後続コマンド追加時もこの規約に従う。

| チャンネル | prefix | 終了コード | 例 |
|-----------|--------|----------|----|
| stdout | （prefix なし） | 0 | `Created: ...` / `Recreated: ... (backup: ...)` / `Already exists: ...` |
| stderr | `Error: ` | 1 | `Error: vault directory does not exist: ...` |
| stderr | `Warning: ` | 0 | `Warning: no daily-note template configured ([dailyNote].template); creating an empty file.` |

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

---

### ノート管理

- ノートはMarkdownファイルとして実ファイルで管理する
- メタデータはfrontmatter（YAMLヘッダ）で管理する
- 管理対象ディレクトリ（vault）はconfigで指定する

---

### テンプレート

#### テンプレートフォルダ

- configでテンプレートフォルダのパスを指定する
- テンプレートは通常のMarkdownファイルとして管理する
- テンプレートの編集はエディタで直接行う
- 特定機能においてテンプレートをファイルパスで任意に指定できる

#### 変数展開

テンプレート内で以下の変数を使用できる：

| 変数 | 出力例 | 説明 |
|------|--------|------|
| `{{title}}` | `My Note` | ノートのタイトル |
| `{{date}}` | `2024-03-27` | 今日の日付（YYYY-MM-DD） |
| `{{date:YYYY/MM/DD}}` | `2024/03/27` | フォーマット指定 |
| `{{date:timestamp}}` | `1711497600` | unixtime |
| `{{time}}` | `09:00` | 現在時刻（HH:mm） |
| `{{time:HH:mm:ss}}` | `09:00:00` | フォーマット指定 |
| `{{id}}` | `20240327090000` | ZettelkastenのID |

- 変数展開は固定変数＋フォーマット指定のみ対応する
- 任意のコード実行は行わない（セキュリティ上の理由）

---

### デイリーノート

#### 設定

```yaml
dailyNote:
  basePath: "daily/"
  fileNameFormat: "YYYY-MM-DD"
```

#### 通常作成 `note daily`

```
1. {basePath}/YYYY-MM-DD.md のパスを決定
2. ファイルが存在しない → テンプレートから作成
3. ファイルが存在 かつ 1byte以上 → スキップ（何もしない）
4. ファイルが存在 かつ 0byte → テンプレートから作成
```

#### 強制作成 `note daily --force`

```
1. {basePath}/YYYY-MM-DD.md のパスを決定
2. ファイルが存在しない → テンプレートから作成
3. ファイルが存在 →
     {basePath}/YYYY-MM-DD.backup-YYYYMMDDHHmmss.md に移動
     → テンプレートから新規作成
     → バックアップパスを通知する
```

バックアップファイル名の例：
```
daily/2024-03-27.backup-20240327-153045.md
```

---

### リンク（`[[]]`記法）

#### リンク先解決ルール

```
[[note-name]] の解決:
  1. vault全体から note-name.md を検索（ファイル名ベース）
  2. 1件見つかった → そのファイルへのリンク
  3. 0件（未存在） → 未解決リンクとして扱う
  4. 複数件見つかった → 曖昧さを通知し、明示するよう促す
```

未解決リンクがあってもシステムはエラーにならず動作を継続する。

#### note show でのリンク表示

`note show`はそのノートのリンク一覧を出力する。未解決の場合はその旨を表示する。

```
Path     : daily/2024-03-27.md
Size     : 1.2KB
Chars    : 1024
---frontmatter---
title    : 2024-03-27
date     : 2024-03-27
---links---
[[existing-note]]  → daily/existing-note.md
[[missing-note]]   → 未解決
```

#### 未解決リンクの一覧

```
note links --unresolved   # vault全体の未解決リンクを一覧表示
```

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
フェーズ1: vim.fn.system('note create xxx') で叩くだけ
フェーズ2: Telescopeと組み合わせてノート一覧をファジー検索
フェーズ3: ちゃんとしたNeovimプラグインとしてパッケージ化
```
