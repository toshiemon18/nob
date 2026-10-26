---
title: Neovim プラグインから呼ぶための CLI の出力（--porcelain と config --vault）
slug: cli-for-nvim
status: in-progress
created: 2026-10-27
updated: 2026-10-27
---

## 目的・背景

Neovim プラグイン（2026-10-26 の grilling）は nob をサブプロセスで呼び、結果を stdout から読む。今の `create` と `daily` は `Created: <path>` のような人間向けの文を出すので、プラグインが文言に依存してしまう。また、プラグインは vault のルートを知る必要があるが、設定を二重に持たない方針なので（Q6）、nob に問い合わせる口が要る。

- Q4・Q10: `daily` と `create` に `--porcelain` を足し、stdout には絶対パスだけを 1 行出力する
- Q15: `nob config --vault` を足し、展開・検証済みの vault の絶対パスを 1 行出力する

PR #17（feature/moment）の上に積む。

## 仕様

### `--porcelain`（`nob create` / `nob daily`）

stdout には、操作の対象になったノートの絶対パスだけを 1 行出力する。

| 場合 | 通常の出力 | `--porcelain` |
|---|---|---|
| 作成した | `Created: <path>` | `<path>` |
| 作り直した（`--force`、`daily` の 0 バイトのファイル） | `Recreated: <path> (backup: <backup>)` | `<path>` |
| すでにある（`daily`） | `Already exists: <path>` | `<path>` |

- バックアップのパスは出さない
- `Warning:` と `Error:` は今までどおり stderr に出す。終了コードも変わらない
- 名前は git にならった。将来ほかのコマンドにもスクリプト向けの出力を足すときに、同じ名前を使う

### `nob config --vault`

- config の `vault` を展開・検証した絶対パスを 1 行出力する（`~` は展開する）。`create` などの出力に使う vault と同じ
- vault が未設定、または存在しなければ、ほかのコマンドと同じ `Error:` / exit 1
- config を読むコマンドなので、未知のキーの Warning も出す
- `-e` / `--path` / `--show` / `--vault` は 1 つだけ指定できる。エラーの文言も `-e/--path/--show/--vault` にする

## 設計

- CLI だけの変更。`format_write_result` の前で `options[:porcelain]` を見て、パスだけを出す
- `daily` の `Already exists:` も同じ分岐を通す
- `config --vault` は `load_config.vault` を出力する

### テストする seam

| seam | 捕まえるもの |
|------|-------------|
| S1: `Nob::Cli.start(["create", ..., "--porcelain"])` | 作成・作り直しで絶対パスだけが出ること |
| S2: `Nob::Cli.start(["daily", "--porcelain"])` | 作成・作り直し・既存で絶対パスだけが出ること、Warning は stderr のまま |
| S3: `Nob::Cli.start(["config", "--vault"])` | `~` の展開、未設定のエラー、ほかのフラグとの排他 |

## TODO（TDDタスク分解）

- [ ] **T1**: `Add --porcelain to nob create`（S1）
- [ ] **T2**: `Add --porcelain to nob daily`（S2）
- [ ] **T3**: `Add nob config --vault`（S3）
- [ ] **T4**: `Document the output for scripts`
    - design.md（サブコマンド一覧、出力チャンネルの慣習、Neovim 連携）、README、`generate:typesig`
