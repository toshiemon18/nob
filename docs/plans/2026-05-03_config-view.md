---
title: nob config に --path / --show を追加して閲覧経路を作る
slug: config-view
status: done
created: 2026-05-03
updated: 2026-05-03
---

## 目的・背景

現状 `nob config` は `-e` がない場合 Usage を出して exit 1 するだけで、config ファイルの場所や内容を確認する経路がない。スクリプト連携や eyeball 確認のため2種の閲覧経路を追加する。

スコープは「閲覧」のみ。schema 検証・編集・初期化リセット等は別 plan。

## 設計

### 公開 CLI

```
nob config            # Usage 表示 + exit 1（現状維持）
nob config -e         # エディタで開く（既存）
nob config --path     # config ファイルのパスを 1 行で stdout
nob config --show     # config ファイルの内容を stdout に流す
```

短縮: `--path` → `-p`、`--show` → `-s`。`-e` はエディタ専用なので衝突なし。

### 振る舞い詳細

- 共通: `Config.ensure_exists` を最初に呼んで未生成なら作る（`-e` と同じ）。`--path` だけのつもりでもファイル生成という副作用を伴うが、`cat $(nob config --path)` のようにパイプで繋ぐ用途では未生成 → 生成 → パス取得が自然なので採用
- `--path`: `Nob::Config.default_path` を `puts` する（末尾改行あり）。`cat $(nob config --path)` で繋ぎやすい
- `--show`: `File.read(path)` の結果を stdout に書き出す（末尾改行は変えない）。`cat` と同じ感覚
- 複数フラグ同時指定（例: `--path --show`）: Thor は両方 true で受け付ける。本実装では「最初に評価したフラグ優先」ではなく **排他にして警告 exit 1**（意図不明な組み合わせを早期に弾く）
- `-e` と `--path`/`--show` の同時指定も同じく排他
- 排他違反時の文言は他コマンドと揃えて `Error: specify only one of -e/--path/--show` 形式にする（`Error:` プレフィクスで grep 一貫性を保つ）

### モジュール構成

CLI 層のみで完結する想定。`Nob::Cli#config` を分岐するだけで `Editor` のような新クラスは作らない（読み出しは1〜2行で済むため）。

### エッジケース

- `Config.ensure_exists` の権限失敗 → 既存の rescue 経路で `warn + exit 1`
- `--show` で読み出し時の I/O 例外 → 同じく rescue で扱う
- `-e --path` のようなフラグ重複 → `warn "Specify only one of -e/--path/--show"` + `exit 1`

### 設計判断

- フラグ排他: 「黙って一方を採る」より「明示的に拒否」の方が後から誤用に気づきやすい
- 専用クラス不導入: 1 行の `puts`/`File.read` をクラスに包むのは過剰

## TODO（TDDタスク分解）

- [x] **T1**: `Add nob config --path to print config file path`
    - Red: cli_spec で `nob config --path` が `Nob::Config.default_path` を 1 行で stdout に出すことを assert（`ensure_exists` も呼ばれる）
    - Green: Cli#config に `--path` 分岐を追加

- [x] **T2**: `Add nob config --show to print config file contents`
    - Red: 一時 config を作り `nob config --show` がその内容を stdout に流すことを assert
    - Green: Cli#config に `--show` 分岐を追加（`File.read` を `puts` ではなく `print` で出す = 末尾改行を変えない）

- [x] **T3**: `Reject conflicting config flags (-e/--path/--show)`
    - Red: cli_spec で `nob config -e --path` が stderr に `Error: specify only one of` を出して exit 1 することを assert（複数組み合わせを 1〜2 ケース）
    - Green: Cli#config の冒頭でフラグ数をチェックして排他にする

## レビューフィードバック

### 2026-05-03 code レビュー (peer-review)

Critical: なし / Important: なし / Nice-to-have: 5

#### Critical / Important
- なし

#### Nice-to-have（すべて見送り）
- `EXCLUSIVE_FLAGS = %i[edit path show]` 定数化 → 見送り（3 フラグでは過剰、追加が出てから抽出）
- `config` メソッド肥大化の閾値メモ → 見送り（plan で「専用クラス不導入」判断済み）
- `IO.copy_stream` 化 → 見送り（config が MB 級になる現実的シナリオなし）
- 排他テストで stdout 空の assert → 見送り（stderr 一致で十分、過剰防衛）
- 排他テストで `ensure_exists` 未呼の assert → 見送り（実装上自明、過剰防衛）

#### Out of scope
- `--path` 副作用、schema 検証、編集系は plan で別スコープに切り出し済

### 2026-05-03 plan レビュー (peer-review)

Critical: なし / Important: 2 / Nice-to-have: 3

反映済み (Important):
- `--path` の `ensure_exists` 副作用を意図として明文化
- 排他エラーの文言を `Error:` プレフィクス揃えに変更

未反映 (Nice-to-have、判断保留):
- 空ファイル時の `--show` 無出力挙動: `print` の自然な振る舞いとして自明なので明記せず
- T1/T2 の `ensure_exists` 副作用テスト: T1 の Red で「ensure_exists も呼ばれる」と既に書いているため追加なし
- `-p` / `-s` の Thor 既存衝突確認: Thor のサブコマンドオプションはコマンドスコープなので衝突なし、明記せず

## 実装と計画の差分（recap）

### 計画通りに実装できた点
- T1〜T3 が 1 task = 1 commit で進行（途中 T1 で T2 分も巻き込んで実装してしまい、revert→再構築で軌道修正したが結果は plan 通り）
- 排他ロジックの早期 return で副作用前にエラーを返す方針通り

### 計画から逸脱した点
- なし

### Implement 中の事故
- T3 の Red を実行した際、排他チェック未実装の状態で `-e --path` が `Editor.open` まで到達し、デフォルト `Kernel.system` で実 `vi` を起動して rspec がハング → pkill で復旧、Green 先行で対処
  - 教訓: CLI で副作用呼び出しを伴う Red を書くときは、Green の先行実装か Editor 系の事前 stub をセットすべき

### 学び・後続 plan への送り
- `EXCLUSIVE_FLAGS` 定数化やメソッド分割は、`--init` などサブ操作が増えた段階で再検討
- `Config::Editor` を sibling に置くなら `Config::Viewer` のような cat 担当クラスも将来選択肢になりうる（現在は CLI に直書きで十分）
