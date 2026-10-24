---
title: 設定キーを Config::Keys で表し、テンプレートのパス解決を Templates に移す
slug: config-keys
status: done
created: 2026-10-24
updated: 2026-10-24
---

## 目的・背景

PR #8（create-template）のレビューで、`source: "[dailyNote].template"` のような設定キーの直書きを避け、設定キーを表す手段を用意したいと指摘された。直書きは次の箇所にある。

- `lib/nob/config.rb`: `data["dailyNote"]`、`raw["basePath"]`、`"[dailyNote].template"`、`"[note].template"`、`data["vault"]`、`DAILY_DEFAULTS` のキー
- `lib/nob/cli.rb`: daily の Warning にある `([dailyNote].template)`、`--template` の説明にある `[note].template`

検討の中で、`Config#resolve_template` の置き場所もずれていると分かった。Config は設定ファイルを表すクラスだが、CLI の `--template` の値まで受け取っており、そのために `source:` 引数が必要になっている。ADR 0001 の決定 I は、もともと「テンプレートのパスを解決して読み込むのは caller の責務」としていた。

そこで次の 2 点を行う（2026-10-23〜24 に合意）。

1. 設定キーを `Config::Key`（section / name / default を持つ値オブジェクト）と、その定数をまとめた `Config::Keys` で表す。キー名、既定値、表示名を 1 か所で定義する
2. Config は設定ファイルの値を `Keys` で読んで返すだけにする。テンプレートのパス解決は `Templates.locate` に移し、どの値を使うか（`--template` を優先するか）と指定元ラベルは CLI が決める

PR #8 は変更しない。このブランチは `feature/create-template` から分岐し、#8 のマージ後にマージする。

スコープ外:
- 未知のキーの検出（Warning）。テンプレート対応が終わってから別の plan で行う
- `DEFAULT_CONTENT` を `Keys` から自動生成すること（説明コメントが書けなくなるため、手書きのまま残す）
- CLI のオプション名の定数化（Thor の `method_option` と二重管理になるため）

## 設計

### Config::Key / Config::Keys

```ruby
# lib/nob/config/key.rb
Nob::Config::Key = Data.define(:section, :name, :default)
  # to_s       -> "[dailyNote].template"（section が nil なら "vault"）
  # read(data) -> 設定ファイルの値。キー（またはセクション）がなければ default

# lib/nob/config/keys.rb
module Nob::Config::Keys
  VAULT                  = Key.new(section: nil,         name: "vault",          default: nil)
  DAILY_BASE_PATH        = Key.new(section: "dailyNote", name: "basePath",       default: "daily/")
  DAILY_FILE_NAME_FORMAT = Key.new(section: "dailyNote", name: "fileNameFormat", default: "%Y-%m-%d")
  DAILY_TEMPLATE         = Key.new(section: "dailyNote", name: "template",       default: nil)
  NOTE_TEMPLATE          = Key.new(section: "note",      name: "template",       default: nil)
end
```

- `read` は値が `nil` のときだけ `default` を返す。空文字列はそのまま返す（今の `raw["basePath"] || default` と同じ挙動）
- `DAILY_DEFAULTS` は削除する

### Config が返すもの

```ruby
DailySettings = Struct.new(:base_path, :file_name_format, :template, keyword_init: true)
NoteSettings  = Struct.new(:template, keyword_init: true)
```

- `template` は設定ファイルに書かれた生の値（未解決）。`template_path` は削除する
- `Config#resolve_template` と `Config::InvalidTemplatePath` は削除する
- `resolve_vault!` も `Keys::VAULT` で読む

### Templates.locate

```ruby
# (String vault, String? raw, source: #to_s) -> String?
Nob::Templates.locate(vault, raw, source:)
```

- 空や nil なら nil。それ以外は `Vault.path_for(vault, raw)` で解決する
- `Vault::InvalidPath` を `Templates::InvalidPath < Nob::Error` に包み直し、指定元を付ける。メッセージは今と同じ（`template path escapes the vault: ../x.md ([note].template)`）
- `source:` は `to_s` で表示名を返すもの。config のキーなら `Keys::NOTE_TEMPLATE` などを、CLI のオプションなら `"--template"` を渡す
- ファイルの読み込みと展開は、今までどおり `Templates.render(path:)` が担う

### CLI

```ruby
# create
raw, source = if options[:template]
  [options[:template], "--template"]
else
  [config.note_settings.template, Nob::Config::Keys::NOTE_TEMPLATE]
end
template_path = Nob::Templates.locate(config.vault, raw, source: source)

# daily
template_path = Nob::Templates.locate(config.vault, settings.template, source: Nob::Config::Keys::DAILY_TEMPLATE)
warn("Warning: no daily-note template configured (#{Nob::Config::Keys::DAILY_TEMPLATE}); creating an empty file.") if template_path.nil?
```

- 利用者から見た挙動（出力、エラーメッセージ、終了コード、優先順位）は変えない。既存の CLI spec がそのまま回帰テストになる
- `--template` の説明文も `Keys::NOTE_TEMPLATE` から作る

### テストする seam

| seam | 捕まえるもの | 捕まえないもの |
|------|-------------|---------------|
| S1: `Nob::Cli.start([...])` | 利用者から見た挙動が変わらないこと（既存 spec） | 内部の分担 |
| S2: `Nob::Config#daily_settings` / `#note_settings` | 設定ファイルの値と既定値が `Keys` どおりに返ること | パスの解決 |
| S3: `Nob::Templates.locate` | vault 相対の解決、空値、拒否と指定元付きのメッセージ | CLI からの結線 |
| S4: `Nob::Config::Key` | `to_s` の表示名、`read` の既定値とセクションの有無 | 個々のキー定義の妥当性（S2 で見る） |

## TODO（TDDタスク分解）

- [x] **T1**: `Add Config::Key and Config::Keys`（S4）
    - `to_s`（section あり / なし）、`read`（値あり / キーなし / セクションなし / 空文字列）
- [x] **T2**: `Read config values through Config::Keys`（S2）
    - `daily_settings` と `resolve_vault!` を `Keys` 経由にし、`DAILY_DEFAULTS` を削除する
    - `DEFAULT_CONTENT` の spec を `Keys` の既定値との照合に変える
- [x] **T3**: `Add Templates.locate for template path resolution`（S3）
    - `Config#resolve_template` の spec を `Templates.locate` に移し、`Templates::InvalidPath` を追加する（この時点では Config 側も残す）
- [x] **T4**: `Return raw template values from Config and locate them in the CLI`（S1 / S2）
    - Settings の `template_path` を `template`（生の値）に変え、create と daily を `Templates.locate` に切り替える。`Config#resolve_template` と `InvalidTemplatePath` を削除する
    - 既存の CLI spec が変更なしで通ること
- [x] **T5**: `Derive config key labels in CLI messages from Config::Keys`（S1）
    - daily の Warning と `--template` の説明を `Keys` から作る
- [x] **T6**: `Update ADRs and RBS for Config::Keys and Templates.locate`
    - ADR 0001 の改訂注記（解決は `Templates.locate`、ラベルは caller）、ADR 0002 の例外表（`Templates::InvalidPath`）、`generate:typesig`

## レビューフィードバック

## 実装と計画の差分（recap）

### 実装中に分かったこと（Review 前のメモ）
- T3: plan では「`Config#resolve_template` の spec を `Templates.locate` に移す」としていたが、T3 では `Templates.locate` の spec を足すだけにし、Config 側の spec は実装と一緒に T4 で削除した
- T4: Config の spec から拒否のテストを外すと、CLI が正しいキーをラベルに渡しているかを確かめるテストがなくなる。そこで CLI spec に `([note].template)` と `([dailyNote].template)` のエラーを足した（既存の CLI spec は変更していない）
- T5: Warning の文言（ラベル部分）と `--template` の説明は spec で検証していなかった。置き換える前に spec で固定した
- `design.md` のプロジェクト構成に `config/key.rb` と `config/keys.rb`、`Templates.locate` を追記した（plan の T6 には書いていなかった）
- 後続の候補: typeprof は `Data.define` のブロック内のメソッド（`Key#to_s` / `#read`）を `Nob::Config` のメソッドとして出力し、`Templates.locate` を `-> nil` と推論する。生成物なので手では直していない
