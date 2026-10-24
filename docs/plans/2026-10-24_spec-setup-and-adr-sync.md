---
title: cli_spec の準備の共通化、テストの穴埋め、ADR の更新
slug: spec-setup-and-adr-sync
status: done
created: 2026-10-24
updated: 2026-10-24
---

## 目的・背景

2026-10-24 にサブエージェントがコード全体を評価した。その指摘のうち、小さくてすぐ直せる次の 3 点を片付ける。

1. cli_spec で「一時 vault を作る → config.toml を書く → `Config.default_path` をスタブする → 後で削除する」準備が 6 か所で重複している
2. 次の挙動にテストがない
   - daily で既存ファイルが 0 バイトなら作り直す（design.md「デイリーノート」）
   - `create --dir` の正常系
3. ADR がコードに追いついていない
   - ADR 0001 に、削除済みの `Templates::Loader` の補追が残っている
   - ADR 0001 の公開 API の記述に `Templates.render` / `Templates.locate` がない
   - ADR 0001 に載っているエラーメッセージの例が、実際の出力と違う
   - ADR 0002 の例外表に「テンプレートファイルがない」の行がない

`refactor/config-keys`（#9）から分岐する。マージ順は #8 → #9 → このブランチ。

スコープ外（評価で「後でよい」とされたもの、または別 plan で扱うもの）:
- `resolve_title!` の検索部分を Vault に移す（links の plan の最初の作業にする）
- ノート作成の流れの切り出しと `now` の注入（zettel に着手するとき）
- `Vault.list` のパス判定を `path_for` に揃える
- 「template file not found」を派生クラスにする（今回は ADR に現状を書くだけにする）
- `config` コマンドの spec の準備（vault を持たないので別の形になる）

## 設計

`spec/support/tmp_vault.rb` に shared context を追加する。

```ruby
RSpec.shared_context("tmp vault") do
  # @vault        一時 vault の絶対パス
  # @config_path  一時 config.toml のパス（Config.default_path がこれを返す）
  # write_config(toml)  config.toml を書き換える
end
```

- 既定の config.toml は `vault = "<@vault>"` だけ
- 後片付けは shared context が行う

## TODO

- [x] **T1**: `Share tmp vault setup across CLI specs`
    - shared context を追加し、cli_spec の 6 か所を置き換える。example 数は変わらないこと
- [x] **T2**: `Cover daily recreation of an empty note and create --dir`
- [x] **T3**: `Sync ADRs 0001 and 0002 with the current template code`

## レビューフィードバック

## 実装と計画の差分（recap）

- T1: 置き換えたのは `show`（2 か所）、`create`、`daily`、`list`（2 か所）の 6 か所。`config` コマンドの 4 か所は vault を持たないため対象外のまま。example 数は 176 で変わらない
- T2: どちらも既存の挙動なので、追加した時点で green だった。daily の判定を `>= 0` に、create の `--dir` を無視するように実装を一時的に壊し、追加した spec が落ちることを確かめた
- T3: ADR 0001 の Loader の補追は、消さずに取り消し線を引き、削除した経緯を補追として足した。エラーメッセージの例は実際に `Templates.render` を呼んで確かめた値にした

