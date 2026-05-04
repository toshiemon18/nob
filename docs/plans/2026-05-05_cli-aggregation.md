---
title: CLI 層の集約
slug: cli-aggregation
status: implementing
created: 2026-05-05
updated: 2026-05-05
---

## 目的・背景

`/peer-review` のアーキテクチャ指摘の本筋議論 3/4。`notes-unification` で Notes 層内部と ADR 0002 のラップ方針が揃ったので、それに沿って CLI 層の構造を整理する。

### 解きたい問題

1. **`rescue Nob::Error` 5 箇所コピペ** (`lib/nob/cli.rb:24-27, 43-46, 71-74, 90-93, 101-104`)
   - 各サブコマンド (`create` / `show` / `config` / `daily` / `list`) で同じ `rescue Nob::Error => e; warn "Error: #{e.message}"; exit 1` を繰り返している
   - 新コマンド追加時に毎回コピペが必要で、ハンドリング方針を変えるとき 5 箇所の修正が漏れるリスク
   - ADR 0002 で「CLI 層は `rescue Nob::Error` で全派生をまとめて拾う前提」と定めた以上、集約箇所を 1 つにすべき

2. **`read_template` が `Cli` 内に直書き** (`lib/nob/cli.rb:107-113`)
   - `cleanup-misc` peer-review の元 Critical 指摘。`daily` 以外（将来 `create` のテンプレ対応など）で使い回すと CLI 層に分散する
   - ADR 0001 の「ファイル I/O は Renderer の外、caller の責務」原則自体は維持するが、`Templates` 名前空間内に共通の薄い loader を置くと caller 側のコードが揃う

3. **`daily` でテンプレ未指定 → 黙って空ファイル作成** (`lib/nob/notes/daily.rb:36`)
   - `template_text=nil` で `Notes::Daily.create` を呼ぶと空文字を書き込む。ユーザーには成功通知だけが出る
   - 「テンプレートを設定し忘れている」のか「敢えて空にしている」のか区別が付かない UX

スコープ外（次サイクル）:

- `Operators` ファクトリの dispatch 軽量化 → `operators-dispatch`（最後のサイクル）

## 設計

### 0. ADR 0002 §D / ADR 0001 §I の補追を本サイクルで反映

本サイクルの設計判断は既存 ADR の **保留事項を埋める** 性質を持つので、コード変更と同 commit で ADR 側も更新する:

- ADR 0002 §D: 「`rescue Nob::Error` の集約方法は別 ADR / 別サイクルの議論」と保留していた箇所に、本サイクルで採用する **`Cli#invoke_command` override** 方式を追記する（T1 commit に含める）
- ADR 0001 §I: 「専用の loader クラスは導入しない。読み込み処理が複数 caller で重複し始めた時点で切り出す」を、**caller が単数でも CLI 層と core 層の境界をまたぐ薄いヘルパなら早めに切り出してよい** と補追する（T2 commit に含める）。理由: CLI に直書きで放置すると `create` への Templates 適用時に分散リスクが顕在化する、Notes 層に置くと「Notes がテンプレファイル I/O を持つ」責務違反になる、Templates 名前空間内に置くのが層境界として自然

### 1. `Cli#invoke_command` で `Nob::Error` rescue を集約

Thor の `Thor::Invocation#invoke_command(command, *args)` は dispatch 経路上の hook で、override 可能（`Thor::Invocation` に public instance method として定義済みであることを `bundle exec ruby -r thor` で確認した）。

```ruby
class Cli < Thor
  no_commands do
    def invoke_command(command, *args)
      super
    rescue Nob::Error => e
      warn "Error: #{e.message}"
      exit 1
    end
  end
end
```

これで全サブコマンドが `Nob::Error` を一括 rescue する。各 command 内の `rescue Nob::Error => e ... end` ブロック 5 箇所を削除できる。

注意:

- `config` コマンド内の `warn "Error: specify only one of -e/--path/--show"` / `warn "Usage: nob config -e"` は `Nob::Error` ではなく **直接 `warn` + `exit 1`** する経路で、こちらは集約対象外（rescue では拾えないので別途維持）。引数バリデーション系のため、Thor が出すエラーと並列に扱う

### 2. `Templates::Loader.read(path)` を新設し `read_template` を移設

```ruby
# lib/nob/templates/loader.rb
module Nob
  module Templates
    module Loader
      def self.read(path)
        return nil if path.nil?
        unless File.exist?(path)
          raise Nob::Error, "template file not found: #{path}"
        end
        File.read(path)
      end
    end
  end
end
```

- `nil` を渡したら `nil` を返す（テンプレ未指定の意味を caller に伝える）
- 不在パスは ADR 0002 の判断軸 A に沿ってラップ済み `Nob::Error` を raise（ユーザーが config を直せば直る）
- `File.read` の `Errno::ENOENT` 等は素通し（レース時の話、ADR 0002 通り）

ADR 0001 との整合: ADR 0001 「ファイル I/O は Renderer の外、caller の責務」は維持。Loader は **caller が呼び出す薄いヘルパ**であって Renderer 内には組み込まれない。Renderer / Parser は引き続き文字列入力。

CLI 側の追従:

- `lib/nob/cli.rb#daily` の `template_text = read_template(settings.template_path)` → `Nob::Templates::Loader.read(settings.template_path)`
- `cli.rb` の `no_commands` ブロックから `read_template` を削除

### 3. `daily` テンプレ未指定時の警告

`cli.rb#daily` で `settings.template_path` が `nil` の場合に **stderr に警告を出す** だけの最小実装に留める:

```
Warning: no daily-note template configured ([dailyNote].template); creating an empty file.
```

判断:

- デフォルトテンプレを当てる案は「設定ミスを隠蔽する」「テンプレ内容の議論」が膨らむので不採用
- 「黙って空」は UX が悪いと peer-review で指摘済み
- 警告のみ (stderr 1 行) なら既存の挙動を変えず、ユーザーに気付かせる最小限の介入として妥当
- 警告は `warn` で出す。stdout の "Created: ..." は維持
- **`Warning:` prefix の慣習を `docs/design.md` に明文化する**。本サイクルで初登場する prefix。今後のサブコマンドで「`Error:` (致命) / `Warning:` (継続可) / それ以外 (情報)」が揃うように design.md に 1 段追記する

### 依存と順序

- T1 (rescue 集約 + ADR 0002 §D 補追) は独立。先にやると後段で CLI を触る際に rescue 重複を増やさず済む
- T2 (Loader 新設 + ADR 0001 §I 補追) は単体で完結する new module。`Templates::Loader` 単体仕様を spec で固める
- T3 (CLI を Loader に差し替え + `read_template` 撤去) は T2 完了後
- T4 (daily 警告 + design.md の prefix 慣習追記) は独立だが、T1〜T3 後にまとめてやる方が CLI 構造がクリアな状態で触れる

順序: T1 → T2 → T3 → T4

T2 / T3 を分けた理由: 前サイクル peer-review でも同パターン（新規モジュール作成と既存呼び出し側差し替えを 1 task に詰める）の指摘があった。Loader 単体仕様 (Red→Green) と CLI 側の差し替え (リファクタ) は概念的に別。

## TODO（TDDタスク分解）

- [ ] **T1** (リファクタ task + ADR 補追): `Centralize Nob::Error rescue via Cli#invoke_command`
    - 事前確認: 既存 cli_spec の error 経路（`#show error conditions`, `#config Editor.open raises`, `#daily template not found`, `#list prefix not found`）が green。これらが「`SystemExit` exit 1 + stderr に `Error: ...`」を assert しているので、集約後も同じ挙動を保てば回帰検出になる
    - Red 兼セーフティネット: `spec/nob/cli_spec.rb` に `#version` の正常系 example を 1 つ追加。`described_class.start(["version"])` が `Nob::VERSION` を stdout に出すこと。`invoke_command` override が `version` / 将来追加されうる help 系を壊さない確認。現状実装でも green になる（だが追加の保証として価値あり）
    - 変更:
      1. `cli.rb` の `no_commands` ブロックに `def invoke_command(command, *args); super; rescue Nob::Error => e; warn "Error: #{e.message}"; exit 1; end` を追加
      2. 各サブコマンド (`create`, `show`, `config`, `daily`, `list`) 末尾の `rescue Nob::Error => e; warn ...; exit 1` を削除
      3. `docs/adr/0002_error-policy.md` §D に **Cli#invoke_command override 方式** を採用する旨を追記（保留事項を埋める）
    - 完了基準: `bundle exec rake` が green、`grep "rescue Nob::Error" -- lib/nob/cli.rb` で 1 箇所だけ（`invoke_command` 内）、ADR 0002 §D に採用方式が記載されている
- [ ] **T2**: `Add Templates::Loader as a thin file-read helper`
    - Red: `spec/nob/templates/loader_spec.rb` を新規追加し、(a) `path: nil` で `nil` 返却、(b) 存在しないパスで `Nob::Error` raise (メッセージに該当パス含む)、(c) 存在するパスで内容を返却、を assert。実装無いので `NameError` で fail
    - Green:
      1. `lib/nob/templates/loader.rb` を新規作成（`Nob::Templates::Loader.read(path)` を実装）
      2. `docs/adr/0001_template-system.md` §I を補追: 「caller が単数でも、CLI 層と core 層の境界をまたぐ薄いヘルパなら早めに切り出してよい」を 1 段落追記。Loader 導入の論拠を残す
    - この task では CLI 側はまだ触らない（Loader は孤児コードになるが、T3 で接続する）
    - 完了基準: `bundle exec rake` が green、Loader spec の 3 例が pass、ADR 0001 §I に補追あり
- [ ] **T3**: `Switch CLI daily to Templates::Loader and drop Cli#read_template`
    - Red: `spec/nob/cli_spec.rb#daily` の既存 "warns and exits 1 when the configured template path is missing" が gate になる。現状 `read_template` 経由のメッセージと、`Templates::Loader.read` 経由のメッセージを **互換にする**（plan 設計 §2 のメッセージ "template file not found: <path>" は元の `read_template` と同一）。互換性で既存 spec は green を維持する
    - Green:
      1. `cli.rb#daily` を `Nob::Templates::Loader.read(settings.template_path)` 呼び出しに差し替え
      2. `cli.rb` の `no_commands` から `read_template` を撤去
    - 完了基準: `bundle exec rake` が green、`grep "read_template" -- lib/nob` で参照ゼロ、`#daily template not found` spec が引き続き pass
- [ ] **T4**: `Warn when daily template is not configured (and document Warning: prefix)`
    - Red: `spec/nob/cli_spec.rb#daily` に 2 つの example 追加
      - 「テンプレ未指定 (`[dailyNote].template` 無し) で `nob daily` 実行 → stderr に "Warning: ..." 行が出る + stdout に "Created: ..." が出る + exit 0」 — 現状実装は警告無しなので fail
      - 「テンプレ指定済み + 実在パスでは Warning 行が **出ない**」 negative example — 現状実装でも green（追加保証）
    - Green:
      1. `cli.rb#daily` で `settings.template_path` が `nil` の場合に `warn "Warning: no daily-note template configured ([dailyNote].template); creating an empty file."` を発行
      2. `docs/design.md` の CLI 仕様節に「stderr prefix の慣習」を追記: `Error:` (致命的、exit 1) / `Warning:` (継続可、exit 0) / それ以外の情報は stdout
    - 完了基準: `bundle exec rake` が green、両 example pass、design.md に prefix 慣習の記載あり

## レビューフィードバック

### peer-review 1 回目（2026-05-05, plan モード）

Critical: 0 件 / Important: 3 件 / Nice-to-have: 3 件

**Important**

- T2 の `Templates::Loader` 導入が ADR 0001 §I「caller が複数になる前は loader を切り出さない」と緊張する。現状 caller は `daily` 1 箇所のみ。
  - → **対応済**: 設計 §0 を新設し、ADR 0001 §I を「caller が単数でも CLI 層と core 層の境界をまたぐ薄いヘルパなら早めに切り出してよい」に補追する旨を明記。T2 完了基準に ADR 0001 §I 補追を含める。
- T2 が「新規 spec + 新規 lib + cli 差し替え + read_template 撤去」を 1 task に詰めている。前サイクル peer-review でも同型指摘があった。
  - → **対応済**: T2 を T2 (`Templates::Loader` 新設) と T3 (CLI 差し替え + `read_template` 撤去) に分割。T2 では Loader が孤児コードになるが、T3 で接続する形に。daily 警告は T4 に番号繰り下げ。「依存と順序」節に分割理由を明記。
- ADR 0002 §D が「集約方法は別 ADR / 別サイクルの議論」と保留している。本サイクルで決定するなら ADR 0002 §D の補追が必要。
  - → **対応済**: 設計 §0 に明記し、T1 完了基準に ADR 0002 §D 補追（`Cli#invoke_command` override 方式の採用記述）を含める。

**Nice-to-have**

- Thor の `version` / help 系コマンドが `invoke_command` 経路を通って override の影響を受けないかの確認が plan に無い。
  - → **対応済**: T1 の Red セーフティネットとして `spec/nob/cli_spec.rb` に `#version` の正常系 example を 1 つ追加。
- `Warning:` prefix が CLI 内で初登場するので、慣習を ADR / design.md に書き添える流儀。
  - → **対応済**: T4 の Green に `docs/design.md` への prefix 慣習追記（`Error:` / `Warning:` / 情報の使い分け）を含める。
- T4 の spec で「テンプレ指定済みでは警告が出ない」 negative example も入れる。
  - → **対応済**: T4 の Red に negative example を追加し、現状実装でも green になる確認込みで明記。

## 実装と計画の差分（recap）

（recap で記入）
