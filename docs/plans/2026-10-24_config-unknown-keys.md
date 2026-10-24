---
title: 未知の設定キーの警告、spec の打ち切り対策、prefix 判定の統一
slug: config-unknown-keys
status: reviewing
created: 2026-10-24
updated: 2026-10-25
---

## 目的・背景

links に着手する前に、残っている細かい課題を 3 つ片付ける。

1. 設定ファイルのキーを打ち間違えても（例: `[note] tempalte = ...`）、黙って既定値が使われる。テンプレート対応が終わったら検出する、と決めていた。`Config::Keys` に一覧ができたので、それと照合できる
2. CLI の spec で Thor が `exit` すると、`SystemExit` が example の外に抜ける。RSpec はそこで止まり、残りの example を実行しないまま「0 failures」と表示する（create-template の T4 で発覚。2026-10-24 に再現を確認）
3. `Vault.list` の prefix の判定（`normalize_prefix`）が、`path_for` とは別に書かれている。`realpath` を使う点も違う
   - 判定はどちらも字句的なので、今の挙動に差はない。ただ、同じ規則を 2 か所で持っている

1 の仕様は 2026-10-24 に合意した。
- 未知のキーは `Warning:` を出して続行する（exit 0）
- 標準ライブラリの `DidYouMean::SpellChecker` で、似たキーがあれば候補を添える
- `Config.load` を通るコマンド（create / show / daily / list）で毎回検査する。`nob config` は `Config.load` を通らないので、vault が未設定でも今どおり編集できる

PR は 1 本にまとめ、TODO ごとに 1 コミットにする。

スコープ外:
- 値の型の検査（例: `basePath = 1`）
- `[dailyNote]` に `template` を入れる以外の、セクションの構造の検査

## 設計

### 未知のキー

```ruby
Nob::Config::Keys.all            # -> Array<Key>（Keys の定数から集める）
Nob::Config#unknown_keys         # -> Array<String>  例: ["[note].tempalte", "editor"]
```

- 設定ファイルの最上位がテーブルなら、その中のキーごとに `[section].name` として照合する。テーブルでなければ `name` として照合する
- セクションごと未知の場合（`[notes]`）も、キー単位で `[notes].template` と報告する
- Config は出力しない（副作用を持たせない）。警告は CLI が出す

CLI では `Config.load` の 4 か所を `load_config` ヘルパにまとめ、未知のキーごとに 1 行の警告を出す。

```
Warning: unknown config key [note].tempalte in /home/me/.config/nob/config.toml (did you mean [note].template?)
Warning: unknown config key editor in /home/me/.config/nob/config.toml
```

### spec の打ち切り対策

`spec_helper.rb` に `around` フックを足す。example から `SystemExit` が抜けたら、その example を失敗にする。

```ruby
config.around do |example|
  example.run
rescue SystemExit => e
  raise "unexpected exit(#{e.status}); wrap the call in expect { ... }.to(raise_error(SystemExit))"
end
```

`expect { ... }.to(raise_error(SystemExit))` で捕まえている spec には影響しない。

### prefix 判定の統一

`normalize_prefix` は `path_for(vault, prefix)` で判定し、`Vault::InvalidPath` を `Vault::InvalidPrefix` に包み直す。メッセージは今と同じ（`prefix escapes the vault: ../outside`、`prefix must be relative to the vault: /etc`）。

### テストする seam

| seam | 捕まえるもの | 捕まえないもの |
|------|-------------|---------------|
| S1: `Nob::Config#unknown_keys` | 照合の規則（最上位のキー、セクション内のキー、未知のセクション、既知のキーは出さない） | 警告の文言 |
| S2: `Nob::Cli.start([...])` | 警告の文言と候補、stderr に出て exit 0 のまま、未知のキーがなければ何も出ない | 照合の細かい分岐 |
| S3: `Nob::Vault.list` | 既存の prefix の spec（変更なし）を回帰テストにする | — |
| S4: 打ち切り対策 | 一時的な probe spec で、`exit` した example が失敗になり、後続の example も実行されることを確かめる（コミットしない） | — |

## TODO（TDDタスク分解）

- [x] **T1**: `Fail specs that exit without expecting SystemExit`（S4）
- [x] **T2**: `Add Config#unknown_keys`（S1）
    - `Keys.all` を追加する
- [x] **T3**: `Warn about unknown config keys`（S2）
    - `load_config` ヘルパ、`DidYouMean::SpellChecker` による候補
- [x] **T4**: `Check list prefixes with Vault.path_for`（S3）
- [x] **T5**: `Document unknown config key warnings`
    - design.md（Config の節、Warning の例）、`generate:typesig`
    - 2026-10-23_create-template、2026-10-24_config-keys、2026-10-24_spec-setup-and-adr-sync の status を `done` にする

## レビューフィードバック

## 実装と計画の差分（recap）

- T2: 最初の実装で最上位のキーと未知のセクションの分岐まで書いたため、後から足した spec は最初から green だった。最上位のキーの分岐を壊すと spec が落ちることを確かめた
- T4: prefix のエラーメッセージは spec で固定されていなかった。置き換える前に固定した。末尾に `/` が付いた prefix もメッセージにそのまま出す（今までどおり）
- 手動確認: `[dailyNote] basepath` と `[notes] template` で候補付きの警告が出て exit 0、`list --prefix ../x` は従来どおり `Error: prefix escapes the vault: ../x`、`nob config --path` は警告を出さない

