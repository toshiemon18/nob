---
title: Config 層の責務分離
slug: config-boundaries
status: implementing
created: 2026-05-04
updated: 2026-05-04
---

## 目的・背景

`/peer-review` のアーキテクチャ指摘のうち、**Config 層の責務混在** に手を入れる。本筋議論 4 サイクルの 1 つ目（残: `notes-unification` / `cli-aggregation` / `operators-dispatch`）。

### 解きたい問題

1. **`Config#vault` の副作用が呼び出しごとに発火** (`lib/nob/config.rb:38-48`)
   - 値オブジェクトであるはずの `Config` がアクセサ呼び出しのたびに `File.directory?` を走らせて `Nob::Error` を raise する
   - `Config#daily_settings` が内部で `vault` を再呼び出し (`config.rb:65`) するため、`daily` 系では実質 2 回検証が走る
   - ドメイン的判定（vault 実在性）と値の取り出しが同じメソッドに同居している

2. **`Config::DailySettings` をドメイン層 (`Notes::Daily`) が直接食っている** (`cli.rb:83`, `notes/daily.rb:8`)
   - `Notes::Daily.create(vault:, daily_settings:, template_text:, ...)` で `daily_settings.base_path` / `daily_settings.file_name_format` を読む
   - `design.md` の `core/` ⇔ `cli/` 分離方針に照らすと Config → Notes 方向の依存が強い
   - 実際 `Notes::Daily` が使うのは 2 フィールドだけで、Config の型を抱える理由がない

スコープ外（次サイクル以降）。slug 候補は併記済:

- `Creator::Result` の `:action` 統一・`Viewer`/`Lister` の glob 共通化・`Viewer` のエラーラップ方針 → `notes-unification`
- CLI の `rescue` 集約・`read_template` の移設・`daily` テンプレ未指定 UX → `cli-aggregation`
- `Operators` ファクトリの dispatch 軽量化 → `operators-dispatch`

## 設計

### 1. `Config#vault` を eager validation に切り替える

現状:

```ruby
def vault
  raw = data["vault"].to_s
  raise Nob::Error, "..." if raw.empty?
  expanded = File.expand_path(raw)
  raise Nob::Error, "..." unless File.directory?(expanded)
  expanded
end
```

変更後の方針:

- `Config.load(path:)` の中で 1 度だけ `data["vault"]` を取り出して expand + 存在検証する。検証結果（絶対パス）を `@vault` に保持する
- `Config#vault` は `attr_reader` 相当のアクセサに徹する（副作用なし）
- 検証で raise するのは `Config.load` の中だけ。CLI 各サブコマンドは現状すでに `Config.load → Nob::Error rescue` の形なので外側の挙動は変わらない
- 検証ロジック自体は private なクラスメソッド（例: `Config.validate_vault!(raw)`）に切り出す。コンストラクタを直接呼べるテストヘルパからも同じ検証が走るように

副次効果:

- `Config#daily_settings` 内部の `vault` 呼び出しは `@vault`（既に検証済み絶対パス）を読むだけになり、二重検証が消える
- 「load 後に `#vault` を何度呼んでも `File.directory?` は走らない」という性質が成立する。spec で副作用消失を保証する

エッジケース:

- vault が空文字 / 未設定 → 既存と同じメッセージで raise（タイミングが load 時になるだけ）
- vault がディレクトリでない（ファイルや存在しないパス）→ 同上
- `Config.new(path:, data:)` を直接呼ぶ箇所の調査結果: `rg "Nob::Config\.new\b|Config\.new\b" -- lib spec` でヒットゼロ。`Config.load` の中だけが `new` を呼ぶ。よって理論上は検証を `Config.load` に閉じても外部から見た振る舞いは同じ
- ただし `Config.new` のシグネチャが `new(path:, data:)` のまま raw な `data` ハッシュを受け取り続ける形だと、テストヘルパや将来のリファクタで誤って未検証の Config が生成されるリスクが残る。**コンストラクタ側で検証して `@vault` を埋める**形に揃え、`new` を呼んだ瞬間に raise するか正しい絶対パスが入るかのどちらかしか取れない不変条件にする
- `Config#daily_settings` 内部の `template_path` 計算は `vault` に依存するため、`Config.load` が失敗した場合には `daily_settings` も呼べないという**呼び出し順制約は本サイクル前後で不変**。検証タイミングが「初回 `#vault` 呼び出し時」から「`Config.load` 完了時」に前倒しになるだけ
- シンボリックリンク / 相対パスの扱いは現状維持（`File.expand_path` + `File.directory?` の挙動。`directory?` はリンクを follow するため、リンク切れは「ディレクトリ不在」扱い）

### 2. `Notes::Daily.create` の引数から Config 型を排除する

現状:

```ruby
Notes::Daily.create(vault:, daily_settings:, template_text:, force:, now:)
```

`daily_settings` から読まれているのは `base_path` / `file_name_format` の 2 フィールドだけ（`template_path` は CLI 側で `read_template` 済みで `template_text` として渡される）。

変更後:

```ruby
Notes::Daily.create(vault:, base_path:, file_name_format:, template_text:, force:, now:)
```

判断:

- 引数展開で十分。`Notes::Daily::Settings` のような core 側値オブジェクトを切るのは現状フィールド数が 2 つでオーバーキル。フィールドが増えたら値オブジェクト化を再検討
- 値オブジェクト化の閾値の目安: **3 フィールド以上 / 共起する複数の不変条件 / 複数の caller で同じ束を組み立てる** のいずれか。現状はどれも満たさない
- `Config::DailySettings` 自体は残す（Config 構造の表現として機能している）。CLI 側で `settings.base_path` / `settings.file_name_format` を取り出して `Notes::Daily.create` に渡す
- これで `Notes::Daily` は `Nob::Config` 名前空間を一切参照しなくなる

CLI 側の追従 (`lib/nob/cli.rb:79-93`):

```ruby
def daily
  config = Nob::Config.load
  settings = config.daily_settings
  template_text = read_template(settings.template_path)
  result = Nob::Notes::Daily.create(
    vault: config.vault,
    base_path: settings.base_path,
    file_name_format: settings.file_name_format,
    template_text: template_text,
    force: options[:force]
  )
  ...
end
```

引数の行が 1 行増えるが、ドメイン層が Config を知らなくなる効果と引き換え。

### 依存と順序

- T1（Config 側）と T2（Notes::Daily 側）は独立。T1 → T2 の順で進めると Config の責務が確定した状態で Notes 側の整理に入れる
- 各 task の Red→Green は閉じる。entangled なし

## TODO（TDDタスク分解）

- [ ] **T1**: `Validate vault eagerly in Config.load`
    - Red: `spec/nob/config_spec.rb` に 2 つの spec を追加
      - 「`Config.load` で vault 未設定 / 不在ディレクトリの場合に `Nob::Error` を raise する（load 時に raise）」 — 現状実装は `#vault` を呼ぶまで raise しないので fail
      - 「load 後に vault ディレクトリを削除しても `#vault` は当初の絶対パスを返し続ける（副作用消失の振る舞いベース確認）」 — 現状実装は `#vault` 内で `File.directory?` を走らせるので削除後に raise → fail。**`File.directory?` をモックする方式は採らない**（実装結合度が上がる、振る舞いベース spec で十分）
    - Green: `Config.new(path:, data:)` のコンストラクタで `data["vault"]` を expand + 検証して `@vault` に保持。検証ロジックは `Config.validate_vault!(raw)` 等の private クラスメソッドに切り出し、`new` から呼ぶ。`Config#vault` は `attr_reader :vault` 相当に縮める。`Config#daily_settings` 内部も `@vault`（= 検証済み絶対パス）を読むだけになる
    - 完了基準: `bundle exec rake` が green、新 spec 2 件 + 既存 spec が pass
- [ ] **T2**: `Drop daily_settings: arg from Notes::Daily in favor of explicit fields`
    - Red の最小単位: `spec/nob/notes/daily_spec.rb` の **先頭 1 example だけ** を `daily_settings:` から `base_path:` / `file_name_format:` を渡す形に書き換える。実装変更前なので `ArgumentError: unknown keywords :base_path, :file_name_format` で fail。残りの example は一旦そのまま（全部書き換えると Red が大きくなり、TDD の最小単位を超える）
    - Green:
      1. `lib/nob/notes/daily.rb` の `.create` を `(vault:, base_path:, file_name_format:, template_text:, now:, force:)` 受けに変更し、内部参照を `daily_settings.base_path` → `base_path` 等に
      2. この時点で先頭 example は green に、残りの example は逆に `ArgumentError: unknown keyword: :daily_settings` で red になる。残りの example も `base_path:` / `file_name_format:` 形式に書き換え（**この書き換えは Refactor フェーズの一部**）
      3. `lib/nob/cli.rb#daily` を `Nob::Notes::Daily.create(vault:, base_path: settings.base_path, file_name_format: settings.file_name_format, template_text:, force:)` 形式に追従
    - 完了基準: `bundle exec rake` が green。`Notes::Daily` 側で `Nob::Config::DailySettings` への参照がゼロ（`rg "Config::DailySettings" -- lib/nob/notes` で確認）

## レビューフィードバック

### peer-review 1 回目（2026-05-04, plan モード）

Critical: 0 件 / Important: 3 件 / Nice-to-have: 3 件

**Important**

- `Config.new(path:, data:)` を「検証込み」に揃える判断の影響範囲調査と代替案の論拠が plan に無い。
  - → **対応済**: `rg` で `Nob::Config.new` / `Config.new` の直接呼び出しを調査した結果ゼロ（`Config.load` 経由のみ）。検証を `load` のみに閉じる代替案も挙げた上で、コンストラクタ側で検証する判断の根拠（テストヘルパや将来リファクタで誤って未検証 Config が生成されるリスク回避）を「設計 → 1. → エッジケース」節に追記
- `daily_settings` の `template_path` 計算は `vault` を読むため、`Config.load` 失敗時には呼べないという呼び出し順制約が plan に明記されていない。
  - → **対応済**: 「呼び出し順制約は本サイクル前後で不変」を「設計 → 1. → エッジケース」節に追記
- T2 の Red 戦略「全 example を一括書き換え」が TDD の最小単位として粗い。
  - → **対応済**: T2 の Red を「先頭 1 example だけ書き換える」最小単位に縮め、残りの example の書き換えは Green 後の Refactor フェーズの一部として明記

**Nice-to-have**

- 副作用消失 spec の方針（`File.directory?` をモックするか、ディレクトリを後から削除して振る舞い確認するか）を plan で固定したい。
  - → **対応済**: T1 の Red に「振る舞いベース（ディレクトリ後削除）。`File.directory?` モック方式は採らない」を明記
- `Notes::Daily::Settings` 値オブジェクトを切らない判断の閾値が「フィールド数 2」のみで、再現性が弱い。
  - → **対応済**: 「設計 → 2. → 判断」に値オブジェクト化の閾値（3 フィールド以上 / 共起する複数の不変条件 / 複数 caller で同じ束を組み立てる、のいずれか）を追記
- シンボリックリンク / リンク切れ vault の挙動を spec で 1 行担保しておくと安全。
  - → **却下**: 現状実装の `File.expand_path` + `File.directory?` を維持するため、リンクの follow 挙動は自然と等価。新規 spec で固定するのは過剰。エッジケース節に「現状維持」とだけ明記

## 実装と計画の差分（recap）

（recap で記入）
