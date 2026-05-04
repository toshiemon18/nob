---
title: Notes 層の統一
slug: notes-unification
status: implementing
created: 2026-05-04
updated: 2026-05-04
---

## 目的・背景

`/peer-review` のアーキテクチャ指摘の本筋議論 2/4。`config-boundaries` で Config 境界が固まったので、Notes 層内部の不整合を片付ける。

### 解きたい問題

1. **`Creator::Result` と `Daily::Result` の非対称** (`lib/nob/notes/creator.rb:11`, `lib/nob/notes/daily.rb:6`)
   - `Daily::Result` は `:action`（`:created` / `:recreated` / `:skipped`）を持ち、CLI 側 `format_daily_result` で動作別に出力分岐できる
   - `Creator::Result` は `:action` を持たず、CLI 側は `result.backup_path` の有無だけで分岐し「Created: ..." / "Backup : ..." の素朴な 2 行出力」をしている
   - 結果、CLI の出力フォーマットが `nob create` と `nob daily` で揃わない（Recreated の表記が daily だけ）

2. **`Viewer.show` と `Lister.list` で `Dir.glob("**/*.md", base: vault)` が重複** (`lib/nob/notes/viewer.rb:17`, `lib/nob/notes/lister.rb:13`)
   - vault 全体の Markdown 走査という同じ責務が 2 箇所に散らばっている
   - 将来 `.obsidian/` や `.nob/` の除外ルールを足す際の修正点が 2 箇所になる

3. **`Nob::Error` ラップ方針が未文書化** (`lib/nob/notes/viewer.rb:32-36` ほか)
   - `Viewer` は `Psych::SyntaxError` のみ `InvalidFrontmatter` にラップし、`Errno::ENOENT` 等は素通し
   - 「何をラップして何を素通しするか」の判断軸が design.md / ADR にない。新規コード追加時の指針が無い

スコープ外（次サイクル以降）:

- CLI の `rescue` 集約・`read_template` の移設・`daily` テンプレ未指定 UX → `cli-aggregation`
- `Operators` ファクトリの dispatch 軽量化 → `operators-dispatch`

## 設計

### 1. `Creator::Result` に `:action` を追加

`Daily::Result` と同じ shape にする:

```ruby
Result = Struct.new(:path, :backup_path, :action, keyword_init: true)
```

`Creator.create` の挙動 → `:action` 値の対応:

| ケース | 現状の振る舞い | `:action` |
|--------|--------------|-----------|
| ファイル無し → 作成 | 作成して Result 返す | `:created` |
| ファイル有り + `force=false` | `AlreadyExists` raise | （Result を返さない、変更なし） |
| ファイル有り + `force=true` | backup → 作成 | `:recreated` |

`:skipped` は Creator では現状発生しない（force=false の既存ファイルは raise する設計）。本サイクルではこの設計判断は維持する（`:skipped` 化は CLI UX 全体の議論なので別サイクル候補）。

**`:skipped` の到達範囲についての注記**: T2 で導入する共通 formatter は `:created` / `:recreated` / `:skipped` の 3 分岐を持つが、`:skipped` には現状 `Daily` 経由でしか到達しない（Creator は `AlreadyExists` raise するため）。これは仕様。将来 Creator が `force=false` で `:skipped` を返すよう変更しても formatter 側は変更不要、という形で前向き互換を担保する。

### 2. CLI の出力フォーマッタを `nob create` / `nob daily` で統一

現状:

- `cli.rb#create:23-24`: `puts "Created: ..."` + `puts "Backup : ..."` if backup_path
- `cli.rb#daily` → `format_daily_result(result)`: `:created` / `:recreated` / `:skipped` で分岐

変更後:

- 共通 formatter `format_note_action(result)` を `no_commands` ブロック内に置く
- `:created` → "Created: {path}"
- `:recreated` → "Recreated: {path} (backup: {backup_path})"
- `:skipped` → "Already exists: {path}"
- `cli.rb#create` と `cli.rb#daily` の両方が `puts format_note_action(result)` を呼ぶ
- 既存の `format_daily_result` は撤去（共通 formatter に統合）

### 3. `Notes::Scanner.markdown_files(base)` で glob を共通化

```ruby
# lib/nob/notes/scanner.rb
module Nob
  module Notes
    module Scanner
      def self.markdown_files(base)
        Dir.glob("**/*.md", base: base).sort
      end
    end
  end
end
```

- 入力: glob のベースディレクトリ（絶対 / 相対どちらでも）
- 出力: ベース相対の `.md` パス Array、ソート済み
- 「ベース」を引数に取ることで Lister 側 (vault + prefix) も Viewer 側 (vault) も同じ呼び出しに乗る
- Dir.glob のデフォルト挙動でドットファイル / ドットディレクトリは除外される（既存の挙動を維持）
- 将来 `.obsidian/` / `.nob/` の明示的除外ルールを足すなら Scanner だけ修正すれば済む

呼び出し側の変更:

- `Lister.list`: `Dir.glob("**/*.md", base: base).sort` → `Scanner.markdown_files(base)`
- `Viewer.show`: `Dir.glob("**/*.md", base: vault)` → `Scanner.markdown_files(vault)`

責務分担と挙動の補足:

- **prefix 検証は Scanner の責務外**: Lister の `normalize_prefix!` / `validate_base!` は本サイクルで触らない。Scanner は「base から `.md` を集めて返す」だけの薄いヘルパに留める
- **Viewer の挙動微変化（sort 済みになる）**: 既存 Viewer は `.sort` なしで `Dir.glob` していた。Scanner 経由にすると Viewer 側でも sort 済み Array が返るようになる。`Viewer.show` の title マッチは `File.basename(rel, ".md") == title` の filename 一致のみで sort 順に依存しない（候補が複数ある場合の `Ambiguous` メッセージは既に `sorted = matches.sort_by` で別途並べ替えている）。**機能差分なし**。一応 spec で既存挙動の維持を確認する

### 4. ADR 0002 で `Nob::Error` ラップ方針を文書化

新規 ADR `docs/adr/0002_error-policy.md` を起こし、以下の方針を明文化する:

- `Nob::Error` 派生は **CLI に伝えてユーザー向けメッセージに変換するもの**
- ライブラリ例外（`Errno::*`, `Psych::*`, etc）は基本的に素通し。**ユーザー操作で発生しうる入力エラー** はラップしてユーザー向けメッセージに変換する
- 具体例:
  - `Viewer::InvalidFrontmatter` (= `Psych::SyntaxError` ラップ): ユーザーが書いた frontmatter YAML が壊れているケース → ラップする
  - `Errno::ENOENT` (= ファイル消失): Viewer 中に他プロセスが触ったレースは想定外、素通し
  - `Errno::EACCES`: パーミッションエラーも素通し（運用ミス、発生時にスタックトレースで原因が分かる方がよい）
- 各 `Nob::Error` 派生クラスの命名規約: `Nob::<モジュール>::<具体エラー>` (e.g. `Notes::Viewer::NotFound`, `Templates::ParseError`)
- CLI 層 (`Cli`) は `rescue Nob::Error` で全派生をまとめて拾う前提（次サイクル `cli-aggregation` で `rescue_from` に集約予定）

これはコード変更を伴わない非 TDD task。ADR 単独で完結する。

**`cli-aggregation` と一緒にやらず本サイクルに含める判断**: ADR 0002 が決めるのは「**どの例外を `Nob::Error` 派生にラップして CLI に届けるか**」というラップ方針で、これは Notes 層内部（`Viewer::InvalidFrontmatter`, `Lister::InvalidPrefix`, etc）の責務に直結する。一方 `cli-aggregation` で扱う `rescue` 集約 (`rescue_from`) は CLI 層の rescue 構造の話で層が違う。本サイクル（Notes 層整理）でラップ方針を確定させ、それに沿って次サイクルで CLI rescue を集約する、という順序の方が依存方向が素直（ラップされる側 → ラップを受ける側）。同サイクルで束ねる選択肢は「rescue 集約の議論にラップ方針が引きずられる」リスクがあり、退ける。

### 依存と順序

- T1 (Creator::Result の :action) → T2 (`format_note_action` 導入 + daily を載せ替え, 出力互換) → T3 (create を formatter 経由に切り替え, 出力フォーマット変更) は順序依存
- T4 (Scanner) は独立
- T5 (ADR 0002) は独立

順序: T1 → T2 → T3 → T4 → T5

T2 と T3 を分けた理由: T2 は出力互換のリファクタ（`format_daily_result` を `format_note_action` にリネーム＋拡張、daily の挙動は変えない）、T3 は出力契約の変更（create の "Backup : ..." 表記が "Recreated: ... (backup: ...)" に変わる）。Red→Green の単位として、出力フォーマットの変化は独立 task に分けた方が回帰検出が明確になる。

## TODO（TDDタスク分解）

- [ ] **T1**: `Add :action to Creator::Result`
    - Red: `spec/nob/notes/creator_spec.rb` の既存 example を拡張し、`result.action == :created` (新規作成ケース) と `result.action == :recreated` (force backup ケース) を assert。`AlreadyExists` raise ケースには触らない。実装変更前なので `NoMethodError: undefined method 'action'` で fail
    - Green: `lib/nob/notes/creator.rb` の `Result` に `:action` を追加し、`create` 内で `:created` / `:recreated` をセットして返す
    - 完了基準: `bundle exec rake` が green、`Creator::Result` の shape が `Daily::Result` と一致
- [ ] **T2**: `Rename format_daily_result to format_note_action (output unchanged)`
    - Red: `spec/nob/cli_spec.rb` の既存 `#daily` example が `format_note_action` 経由で動くこと自体は assert しないが、リネームに伴い既存 `format_daily_result` が無くなるので、`grep "format_daily_result" -- lib spec` が空になることを完了基準とする。Red としては「`format_note_action` を呼ぶ統合テストを書いてから、まだ未定義なので `NoMethodError` で fail」 — ただし既存 `#daily` spec の振る舞い (created / recreated / skipped 出力) はそのまま green を維持する形で、出力の互換性は担保される
    - Green: `lib/nob/cli.rb` の `format_daily_result` を `format_note_action` にリネーム + 中身は同じ（`:created` / `:recreated` / `:skipped` の 3 分岐）。`cli.rb#daily` の呼び出しを `format_note_action(result)` に差し替え。`#create` はまだ触らない（T3 で扱う）
    - 完了基準: `bundle exec rake` が green、既存 `#daily` spec の出力期待が変わらないこと、`grep "format_daily_result" -- lib spec` で参照ゼロ
- [ ] **T3**: `Switch nob create CLI output to format_note_action`
    - Red: `spec/nob/cli_spec.rb` に `#create` の describe を新設し、新規作成時の "Created: ..." と `--force` 時の "Recreated: ... (backup: ...)" 形式を assert。現状 `cli.rb#create` は "Created: ..." と "Backup : ..." の 2 行出力なので、force ケース spec が "Recreated: ..." 期待で fail
    - Green: `cli.rb#create` を `puts format_note_action(result)` に書き換え、現状の `puts "Created: ..."` + `puts "Backup : ..."` 2 行出力を撤去
    - 完了基準: `bundle exec rake` が green、新 `#create` spec が両ケース pass。CLI 出力フォーマットが `nob create` / `nob daily` で揃う（Recreated 表記の統一）
- [ ] **T4**: `Extract Notes::Scanner.markdown_files for vault traversal`
    - Red: `spec/nob/notes/scanner_spec.rb` を新規追加し、「`.md` のみ列挙」「sort 済み」「ドットファイル / ドットディレクトリ除外」を assert。`Notes::Scanner` 未定義なので `NameError` で fail
    - Green: `lib/nob/notes/scanner.rb` を新規作成して `Scanner.markdown_files(base)` を実装。`Lister.list` と `Viewer.show` の glob 呼び出しを Scanner 経由に差し替え
    - 完了基準: `bundle exec rake` が green。`rg "Dir.glob" -- lib/nob/notes` で `Scanner` 内の 1 箇所だけがヒット
- [ ] **T5** (非 TDD / docs task): `Document Nob::Error wrapping policy in ADR 0002`
    - 事前確認: 既存 ADR (`docs/adr/0001_*`) のスタイル（frontmatter, セクション構成）を踏襲
    - 変更: `docs/adr/0002_error-policy.md` を新規追加。設計節 4 の方針を ADR 形式に整形（コンテキスト / 決定 / 帰結）
    - 完了基準: `bundle exec rake` が green（コード変更なしなので素通し）、ADR 0001 と同様の体裁で 0002 が存在する

## レビューフィードバック

### peer-review 1 回目（2026-05-04, plan モード）

Critical: 0 件 / Important: 3 件 / Nice-to-have: 4 件

**Important**

- T2 の粒度が太すぎる（formatter 新設 + format_daily_result 撤去 + create/daily 両方の差し替え + 新規 cli_spec#create を 1 task に同梱）。Red→Green の単位として「daily 載せ替え（出力互換）」と「create 切替（出力契約変更）」は分離可能。
  - → **対応済**: T2 を 2 task に分割。T2 = `Rename format_daily_result to format_note_action (output unchanged)`、T3 = `Switch nob create CLI output to format_note_action`。これに伴い旧 T3/T4 を T4/T5 に番号繰り下げ。「依存と順序」節に分割理由を明記
- 共通 formatter なのに `:skipped` には Daily 経由でしか到達しない問題を plan で半端に扱っている。
  - → **対応済**: 設計 1 に「`:skipped` の到達範囲についての注記」を追加。formatter の 3 分岐は将来 Creator が `:skipped` を返すよう変更しても formatter 側は変更不要、という前向き互換を明記
- ADR 0002 と `cli-aggregation` の rescue 集約を分離する根拠が plan に無い。
  - → **対応済**: 設計 4 に「`cli-aggregation` と一緒にやらず本サイクルに含める判断」節を追加。ラップ方針（Notes 層内部の責務）と rescue 構造（CLI 層の責務）が層違いであり、ラップされる側 → ラップを受ける側の順序が依存方向として素直、と明記

**Nice-to-have**

- Scanner で `.sort` を加えると Viewer の挙動が「sort 済みになる」変化が起きる。`File.basename(rel) == title` のセマンティクスは変わらないが plan で一言触れた方がよい。
  - → **対応済**: 設計 3 の「責務分担と挙動の補足」に明記（機能差分なし、`Ambiguous` メッセージは別途 sort_by 済み）
- Scanner に prefix を渡さない（Lister の `normalize_prefix!` / `validate_base!` 側に残す）責務分担の明示。
  - → **対応済**: 設計 3 の「責務分担と挙動の補足」に明記
- Viewer の title マッチへの影響に一言。
  - → **対応済**: 設計 3 の「責務分担と挙動の補足」に明記
- T1 の Red の想定（`NoMethodError`）。
  - → **対応不要**: レビュアー自身が「正しい」と評価している

## 実装と計画の差分（recap）

（recap で記入）
