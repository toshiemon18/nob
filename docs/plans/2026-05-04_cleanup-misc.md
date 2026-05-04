---
title: 雑掃除（peer-review 指摘の小粒な不整合まとめ）
slug: cleanup-misc
status: refining
created: 2026-05-04
updated: 2026-05-04
---

## 目的・背景

`/peer-review` で挙がったアーキテクチャ指摘のうち、**設計判断を伴わず単独で完結する小粒な整合化**だけを 1 サイクルにまとめて片付ける。狙いは:

- 後続サイクル（Config 責務分離、Notes 統一、CLI 集約、Operators dispatch）で本筋の議論をするときに、瑣末なノイズで気が散らないようにする
- TUI/Neovim フェーズ着手前に、未参照の依存や役割の薄い型タグを残さない

スコープ外（別サイクル）。slug 候補は次サイクル開始時の参照用:

- `Config#vault` の副作用整理 / `DailySettings` の core 漏れ → `config-boundaries`
- `Creator::Result` への `:action` 統一・`Viewer`/`Lister` の glob 共通化・`Viewer` のエラーラップ方針 → `notes-unification`
- CLI の `rescue` 集約・`read_template` の移設・`daily` テンプレ未指定 UX → `cli-aggregation`
- `Operators` ファクトリの dispatch 軽量化 → `operators-dispatch`

## 設計

各項目は独立しており、相互依存なし。並べ順は影響範囲の小さい順。

### 1. `nob.gemspec` から `tty-prompt` 依存を削除

- 現状コードのどこからも参照されていない（TUI フェーズ未着手）
- TUI 実装着手時に戻せばよい。先取りした依存は不要なノイズ
- 確認手段: `rg tty-prompt -- lib spec exe` で参照ゼロ + `bundle exec rake`（rspec + standardrb）が green

### 2. `lib/nob.rb` の Zeitwerk セットアップを簡素化

- 現状 `loader = Zeitwerk::Loader.for_gem; loader.setup` で `loader` ローカル変数を捕まえているが未使用
- `Zeitwerk::Loader.for_gem.setup` でメソッドチェーンに集約
- 振る舞いは変わらない。standardrb の未使用変数警告を出さない形にするだけ

### 3. `Config::DailySettings` を `keyword_init: true` に

現状 positional 初期化:

```ruby
DailySettings = Struct.new(:base_path, :file_name_format, :template_path)
```

他の Struct（`Entities::Note` / `Entities::NoteDetail` / `Notes::Creator::Result` / `Notes::Daily::Result`）はすべて `keyword_init: true`。`DailySettings` だけが positional で書き手の混乱要因になる。

影響を受ける箇所:

- `lib/nob/config.rb` の `DailySettings.new(...)` 呼び出し（行 68-72）
- `spec/nob/config_spec.rb` で `DailySettings.new` を positional で呼んでいるか確認し、あれば追従
- `Notes::Daily` 内の `daily_settings.base_path` 等の読み取りはアクセサ呼び出しなので影響なし

### 4. `lib/nob/templates.rb` の `Token = Module.new` を撤去

- `Literal` / `Variable` で `include Token` しているが、`Renderer#render` (`renderer.rb:14`) は `case t when Literal / when Variable` と個別クラスを名指ししており、`Token` を型タグとしては使っていない
- 当面この 2 種以外のトークンは想定外（ADR でも明言）。型タグの一般化は YAGNI
- 撤去して `Literal` / `Variable` を裸の `Struct` に戻す
- 既存 spec で `Token` を直接 assert している箇所が無いか確認し、あれば外す
- **ADR 0001 の追従**: `Token = Module.new` は ADR 0001 の B 節および「公開 API」セクションに明文化されている決定事項。撤去にあたっては同 ADR の該当箇所を改訂（B 節と公開 API ブロックから `Token` を削除し、撤去した経緯を「帰結」または注記として追記）して、ADR と実装の乖離を防ぐ。同一コミット内で行う

## TODO（TDDタスク分解）

- [x] **T1** (非 TDD / cleanup task): `Drop unused tty-prompt gem dependency`
    - 事前確認: `rg tty-prompt -- lib spec exe` で参照ゼロ
    - 変更: `nob.gemspec` から `add_dependency "tty-prompt"` 行を削除 + `bundle install` で `Gemfile.lock` 追従
    - 完了基準: `bundle exec rake`（rspec + standardrb）が green
- [x] **T2** (非 TDD / cleanup task): `Inline Zeitwerk loader setup in lib/nob.rb`
    - 事前確認: 既存 spec が green
    - 変更: `lib/nob.rb` を `Zeitwerk::Loader.for_gem.setup` の 1 行に集約
    - 完了基準: `bundle exec rake` が green（autoload 経路の振る舞いが従来通り）
- [x] **T3**: `Switch Config::DailySettings to keyword_init`
    - 事前: `spec/nob/config_spec.rb` で `DailySettings` がどう参照されているか確認（`Config#daily_settings` の戻り値経由か、`DailySettings.new(...)` を直接呼ぶか）
    - Red: spec の期待値・組み立てを keyword 形式に書き換える（既存が positional 直呼びなら fail、`.base_path` 等のアクセサ経由なら期待値書き換えだけでは red にならない可能性があるので、その場合は新規 example を keyword 形式で追加して red を作る）
    - Green: `Struct.new(:base_path, :file_name_format, :template_path, keyword_init: true)` に変更し、`Config#daily_settings` 内の `DailySettings.new(...)` 呼び出しも同一コミット内で keyword 形式に書き換え（Struct 定義と呼び出しは keyword_init 化と同時に変えないとそもそも初期化が通らないため、commit は分割不可）
    - 完了基準: `bundle exec rake` が green
- [x] **T4**: `Drop unused Token tag module from Templates and update ADR 0001`
    - 事前: `rg "Token\b" -- lib spec` で `Token` の参照箇所を洗い出す。spec で直接 assert していれば該当 example を red にしてから外す
    - Green: `lib/nob/templates.rb` から `Token = Module.new` と `Literal`/`Variable` の `include Token` を削除し、`docs/adr/0001_template-system.md` の B 節および「公開 API」セクションを Token 撤去に合わせて改訂（撤去理由を「帰結」or 注記として記載）
    - 完了基準: `bundle exec rake` が green、ADR と実装の表現が一致

## レビューフィードバック

### peer-review 1 回目（2026-05-04, plan モード）

Critical: 0 件 / Important: 2 件 / Nice-to-have: 2 件

**Important**

- T4 と ADR 0001 の整合: ADR は accepted で「公開 API」と B 節に `Token = Module.new` を含む `Literal/Variable` 構造が明記されており、撤去するなら ADR を改訂する TODO が plan に必要。→ **対応済み**: T4 に ADR 0001 B 節および公開 API ブロックの追従更新を含める形に書き換え
- T3 のテスト粒度: Struct 定義変更／呼び出し側書き換え／spec 期待値の関係を Red→Green で素直に書ける構成か事前確認したい。→ **対応済み**: 事前ステップを追加し、`keyword_init: true` 化と `Config#daily_settings` 内の呼び出し書き換えは「同一コミットで同時に変えないと初期化が通らない」前提を T3 に明記

**Nice-to-have**

- T1/T2 が「事前 green 確認」型で TDD の Red→Green 形式から外れる旨を plan に明示。→ **対応済み**: T1/T2 に「(非 TDD / cleanup task)」ラベルを付け、事前確認 / 変更 / 完了基準の 3 段で記述
- スコープ外項目の後続 plan slug 候補を併記。→ **対応済み**: 「目的・背景」のスコープ外節に slug 候補（`config-boundaries` / `notes-unification` / `cli-aggregation` / `operators-dispatch`）を併記

### peer-review 2 回目（2026-05-04, code モード）

range: `16efa73..HEAD`（plan 追加 + T1〜T4 の 5 commit）

Critical: 0 件 / Important: 2 件 / Nice-to-have: 2 件

**Important**

- `docs/design.md:39, 81` に `tty-prompt` 記述が残存。T1 のスコープを `nob.gemspec` / `Gemfile.lock` に絞ったが、design.md にも TUI ライブラリとして明記されており「未参照の依存を残さない」目的（plan 目的・背景）と乖離。撤去か「未導入」の注記かを判断すべき。
  - → **対応済 (R1)**: design.md は「TUI フェーズ着手時の選定候補」を表明しており、tty-prompt 自体を完全削除するのは将来意図を消し過ぎる。技術スタック表 (`docs/design.md:39`) と CLI 仕様 (`docs/design.md:81`) の `tty-prompt` 記述に「TUIフェーズ着手時に導入予定。現時点ではgem依存に含めていない」の注記を加えて整合させた。
- plan status が `reviewing` のままで TODO 全 `[x]` だが「実装と計画の差分（recap）」が空欄。
  - → **却下（フェーズ運用上正常）**: dev-workflow は `reviewing → refining → recap` の順に進む。recap セクションは RECAP フェーズで埋める前提で、現スナップショットでは未記入が正しい状態。

**Nice-to-have**

- ADR 0001 の帰結注記が B 節内のみで、ADR 末尾の「帰結」セクションに撤去履歴が無い。
  - → **却下**: 本 ADR の「帰結」セクションは「採用時点の利点／受容するトレードオフ」を述べたもので、撤去履歴を後付けで足す節ではない。B 節注記で改訂時点と理由が分かるので十分。レビュアー本人も「許容範囲」と述べている。
- `spec/nob/config_spec.rb` の `rejects positional initialization` は `keyword_init` を外しても positional 3 引数は通るため契約固定としては弱い。keyword での正常系 example 追加で回帰検出を強くできる。
  - → **却下**: `daily_spec.rb` の `Nob::Config::DailySettings.new(base_path:, file_name_format:, template_path:)` 呼び出しが事実上 keyword 系の正常系をカバーしており、`keyword_init` を外せば daily_spec 全 8 example が `unknown keywords` で red になる。重複した spec を増やす実益が薄い。

## 実装と計画の差分（recap）

（recap で記入）
