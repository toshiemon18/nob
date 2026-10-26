---
title: レビューで見送った細かい件の対応
slug: review-leftovers
status: implementing
created: 2026-10-26
updated: 2026-10-26
---

## 目的・背景

resolve（PR #13）のレビューで見送った指摘のうち、次の 3 件を片付ける。

1. `nob show` が vault を 2 回走査する。タイトルを探すときの `Vault.list` と、リンクを解決するときの `Vault.files` の 2 回
2. `Plan.md` と拡張子のない `Plan` が同じ場所にあると、`[[Plan]]` が曖昧になる。Obsidian は `[[Plan]]` で `Plan.md` を開く
3. `InvalidPath` のメッセージ（`path ...`）を、呼ぶ側が `sub(/\Apath /, ...)` で書き換えている（`normalize_prefix` と `resolve_from!` の 2 か所）

スコープ外（引き続き見送る）:
- `[[../Plan]]` のような相対パスのリンク
- 引用やリストの中のフェンス
- 先頭の `---` が水平線の場合
- `links` の走査中に読めないノート（ADR 0002 の方針どおり `Errno` はそのまま出す）

## 設計

### 1. 走査を 1 回にする

```ruby
Nob::Vault.find_notes(vault, title, files: Nob::Vault.files(vault))
```

- `files:` を渡せば、それを `.md` で絞ってタイトルと照合する。省けば今どおり自分で走査する
- `show` は `Vault.files` を 1 回だけ呼び、タイトルの照合とリンクの解決の両方に渡す

### 2. ノートを優先する

- リンク先の鍵に当たる候補の中にノート（`.md`）があれば、ノート以外のファイルは候補から外す。そのあとで距離を測る
- `[[diagram.png]]` のように `.md` 以外のファイルにしか当たらないリンクは、今までどおり
- 規則が変わるので、design.md の解決ルールと ADR 0003 に追記する

### 3. メッセージの主語を渡す

```ruby
Nob::Vault.path_for(vault, *segments, label: "path")
Nob::Vault.relative_path(vault, path, label: "path")
```

- メッセージは `#{label} escapes the vault: ...` のように組み立てる。呼ぶ側は `label: "prefix"` や `label: "--from"` を渡し、`sub` での書き換えをやめる
- 文言は今と同じ（spec で固定済み）

### テストする seam

| seam | 捕まえるもの |
|------|-------------|
| S1: `Nob::Cli.start(["show", ...])` | `Vault.files` を 1 回だけ呼ぶ |
| S2: `Nob::Links::Resolver#resolve` | ノートを優先する。ノート以外にしか当たらないリンクは今どおり |
| S3: 既存の spec | メッセージの文言（`prefix ...`、`--from ...`）は変わらない |

## TODO

- [x] **T1**: `Walk the vault once in nob show`（S1）
- [ ] **T2**: `Prefer notes over other files with the same name`（S2）
- [ ] **T3**: `Pass a label to Vault path errors instead of rewriting them`（S3）
- [ ] **T4**: `Document note preference in link resolution`
    - design.md、ADR 0003、`generate:typesig`

## レビューフィードバック

## 実装と計画の差分（recap）
