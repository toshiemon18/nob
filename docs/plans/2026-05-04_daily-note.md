---
title: nob daily / nob daily --force でデイリーノートを作る
slug: daily-note
status: implementing
created: 2026-05-04
updated: 2026-05-04
---

## 目的・背景

design.md の `nob daily` / `nob daily --force` を実装する。templates 基盤と Config 系は揃っているので、残るは

1. Config に `[dailyNote]` セクション (basePath / fileNameFormat / template) を生やす
2. パス決定 + 既存判定 + テンプレート展開のドメインロジックを `Notes::Daily` に置く
3. CLI に `nob daily [--force]` を配線する

の3層を組み合わせる作業。link 機能は実装スコープ外。

## 設計

### Config 拡張

```toml
[dailyNote]
basePath = "daily/"            # vault からの相対パス（末尾スラッシュは任意）
fileNameFormat = "%Y-%m-%d"    # Ruby strftime 書式
template = "templates/daily.md" # 任意。vault からの相対 or 絶対パス。省略時は空ファイル
```

`Nob::Config#daily_settings` を追加。返り値は値オブジェクト（基本は Struct）で、`base_path` / `file_name_format` / `template_path`（resolve 済み絶対パス or `nil`）を持つ。値が無い時のデフォルト:

| キー | デフォルト |
|------|-----------|
| basePath | `daily/` |
| fileNameFormat | `%Y-%m-%d` |
| template | 未指定 → `nil` |

`template` が相対パスなら `vault` を起点に解決（`Pathname.new(vault) + raw`）。

### Notes::Daily

新規モジュール。公開 API:

```ruby
Nob::Notes::Daily.create(vault:, daily_config:, template_text: nil, now: Time.now, force: false)
# => CreateResult(path:, backup_path:, action: :created | :skipped | :recreated)
```

- `path = vault/{base_path}/{now.strftime(fileNameFormat)}.md`
- `template_text`（呼び出し側で `File.read(template_path)` 済みの文字列）が `nil` なら本文は空文字列
- 通常モード:
  - 存在しない → テンプレート展開して作成、`action: :created`
  - 存在 & size > 0 → 何もしない、`action: :skipped`
  - 存在 & size == 0 → テンプレート展開して上書き、`action: :recreated`（design.md の「0byte なら作成」）
- force モード:
  - 存在しない → 通常と同じ `:created`
  - 存在 → `{base_path}/{date}.backup-YYYYMMDDHHmmss.md` にリネーム、テンプレート展開で新規作成、`backup_path` を返す、`action: :recreated`

テンプレート展開は `Nob::Templates::Renderer.render(template_text, title: date_str, now: now)` を使う。`title` は `now.strftime(fileNameFormat)` の結果。

### CLI

```ruby
desc "daily", "Create today's daily note"
method_option :force, aliases: "-f", type: :boolean, default: false, desc: "Backup existing and recreate"
def daily
  config = Nob::Config.load
  daily_cfg = config.daily_settings
  template_text = daily_cfg.template_path && File.read(daily_cfg.template_path)
  result = Nob::Notes::Daily.create(
    vault: config.vault,
    daily_config: daily_cfg,
    template_text: template_text,
    force: options[:force]
  )
  puts case result.action
       when :created    then "Created: #{result.path}"
       when :recreated  then "Recreated: #{result.path}" + (result.backup_path ? " (backup: #{result.backup_path})" : "")
       when :skipped    then "Already exists: #{result.path}"
       end
rescue Nob::Error => e
  warn "Error: #{e.message}"
  exit 1
end
```

### エッジケース・失敗時の振る舞い

- `daily_cfg.template_path` が存在しないファイル → `Nob::Error` を呼び出し側 (CLI) で投げる。`Notes::Daily` は受け取った文字列を信頼
- `basePath` ディレクトリが無い → 自動 `mkdir_p` する（既存 `Notes::Creator` と挙動を揃える）
- バックアップパスがすでに存在（同一秒で2回叩いた等） → 衝突したら `Nob::Error` で失敗。微小確率なので個別救済はしない
- `now` は外部注入可能にしてテストで時刻を固定する
- テンプレート展開で `Nob::Templates::*` 例外が出たらそのまま伝播（CLI 層で rescue）

### 設計判断

- `Notes::Daily` は副作用（File IO）を持つが、`template_text` を文字列で受け取ることで Templates 層と疎結合に保つ。テストでテンプレート読み込みを stub する必要なし
- `daily_config` を値オブジェクトで渡す: Config 全体を渡すより責務が明確
- `action` を返す: CLI 層で出力を分岐するのに必要、戻り値で表現する方が呼び出し側がスッキリする
- バックアップファイル名のサフィックスは `.backup-YYYYMMDD-HHmmss.md` を採用（design.md の例 `daily/2024-03-27.backup-20240327-153045.md` に揃える）

## TODO（TDDタスク分解）

- [x] **T1**: `Add Config#daily_settings returning a struct with base_path/file_name_format/template_path`
    - Red: `spec/nob/config_spec.rb` で TOML に `[dailyNote]` 有り／空（デフォルト適用）／template 相対パスの絶対化、3 ケースを assert
    - Green: `Nob::Config#daily_settings` を実装、`DailyNote = Struct.new(...)` を内部に置く

- [x] **T2**: `Add Notes::Daily.create for normal mode (skip when non-empty exists)`
    - Red: `spec/nob/notes/daily_spec.rb` でテンポラリ vault に対し: 未生成 → 作成 (:created)、size>0 既存 → スキップ (:skipped)、size==0 既存 → 再生成 (:recreated)、テンプレ無し → 空ファイル、テンプレ有り → 変数展開済み内容、`basePath` ディレクトリが未存在でも `mkdir_p` で自動生成されること
    - Green: `lib/nob/notes/daily.rb` を実装。force=false 経路のみ

- [ ] **T3**: `Handle force mode with timestamped backup in Notes::Daily`
    - Red: 同 spec で force=true: 未生成 → 通常通り (:created, backup_path nil)、既存 → backup へリネーム & 再生成 (:recreated, backup_path 値あり)、バックアップファイル名がフォーマット通り (`.backup-\d{8}-\d{6}\.md$`)、`now` を固定して同一秒で2回呼んでバックアップ衝突 → `Nob::Error` で失敗
    - Green: force 分岐を追加

- [ ] **T4**: `Wire nob daily / nob daily --force in CLI`
    - Red: `spec/nob/cli_spec.rb` に: テンポラリ vault と config を作って `nob daily` 起動 → "Created:" 出力、再実行 → "Already exists:" 出力、`--force` で "Recreated:" + backup 出力、テンプレートファイルが指定されているのに存在しない場合 → "Error:" + exit 1
    - Green: `Cli#daily` を追加

## レビューフィードバック

### 2026-05-04 plan レビュー (peer-review)

Critical: なし / Important: 3 / Nice-to-have: 3

反映済み (Important):
- T2 の Red に `basePath` 未存在 → 自動 `mkdir_p` ケース追加
- T3 の Red にバックアップ衝突 → `Nob::Error` ケース追加
- バックアップファイル名を design.md 例に揃え、`.backup-YYYYMMDD-HHmmss.md` 形式に修正

未反映 (Nice-to-have):
- CLI 経由テストでの時刻固定: T4 で `Time.now` をどう固定するかは Red 段階で決める（必要なら `Daily.create` を直接 stub する方針で十分）。明記せず
- T1 の部分指定ケース／absolute template path: 主要3ケースで充分、余裕があれば実装中に追加

## 実装と計画の差分（recap）

(実装後に追記)
