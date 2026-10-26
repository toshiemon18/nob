---
title: nob show の揃えを表示幅で行う
slug: display-width
status: reviewing
created: 2026-10-26
updated: 2026-10-26
---

## 目的・背景

`nob show` の frontmatter 節とリンク節は、`ljust` で文字数を基準に揃えている。全角文字（日本語の key やリンク）は端末で 2 桁を占めるので、`:` と `→` の位置がずれる（links の recap で後続の候補にしていた）。

## 設計

- 文字列の表示幅は `unicode-display_width`（`Unicode::DisplayWidth.of`）で数える。East Asian Width と絵文字を扱える
- CLI に `pad(text, width)`（表示幅が width になるまで右に空白を足す）を置き、frontmatter 節とリンク節の両方で使う
- 曖昧幅の文字（`→` など）は 1 桁として数える（ライブラリの既定）

### テストする seam

| seam | 捕まえるもの |
|------|-------------|
| S1: `Nob::Cli.start(["show", ...])` | 全角を含む key とリンクで `:` と `→` が揃う |

## TODO

- [x] **T1**: `Align nob show columns by display width`（S1）
    - gemspec に `unicode-display_width` を追加する
- [x] **T2**: `Mark finished plans as done`
    - config-unknown-keys、links、resolve の status を `done` にする

## レビューフィードバック

## 実装と計画の差分（recap）

- frontmatter の key の幅の下限 8 は今までどおり（表示幅で比べる）
- 曖昧幅の文字はライブラリの既定どおり 1 桁で数える。端末の設定で曖昧幅を 2 桁にしている場合はずれる
