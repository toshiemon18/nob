---
title: 書き込み系コマンドで vault の外へ出るパスを拒否する
slug: vault-path-escape
status: done
created: 2026-10-22
updated: 2026-10-23
---

## 目的・背景

`nob list --prefix` は vault の外に出る prefix を `Vault::InvalidPrefix` で拒否している。一方、書き込み側の `Vault.path_for` は `File.join` でつなぐだけなので、次の操作で vault の外にファイルが作られる（2026-10-21 に手元で再現）。

| 操作 | 書き込み先 |
|------|-----------|
| `nob create x --dir ../escaped` | `<vault>/../escaped/x.md` |
| `nob create "../../evil"` | `<vault>/../../evil.md` |
| `[dailyNote] basePath = "../out"` で `nob daily` | `<vault>/../out/YYYY-MM-DD.md` |

この先のリンク機能では、ノート本文の `[[...]]` からノートを作る予定がある。そこでは vault 内のテキストがそのままパスになるため、その前にこの穴を塞いでおく。

スコープ外:
- symlink を辿った先が vault の外にある場合の検査。書き込み先はまだ存在しないことが多く、字句的な判定にとどめる。
- タイトルに `/` を含めてサブディレクトリを作る使い方（vault の中に収まるなら現状どおり許可する）。

## 設計

### 公開 API

```ruby
class Nob::Vault::InvalidPath < Nob::Error; end

# (String, *String?) -> String
Nob::Vault.path_for(vault, *segments)
```

- 返り値は従来どおり `File.join(vault, *non_empty_segments)` の結果で、正規化はしない。既存の出力（`Created: /v/x.md`）を変えないため。
- 組み立てたパスを `File.expand_path` で正規化し、`File.expand_path(vault)` と一致するか、その配下にあることを確かめる。外に出ていれば `InvalidPath` を raise する。
  - メッセージは `path escapes the vault: <空でない segments を "/" で join したもの>` とする。
- 先頭が `/` の segment（絶対パス）も `InvalidPath` で拒否する（メッセージは `path must be relative to the vault: ...`）。`--prefix` が絶対パスを `InvalidPrefix` で拒否しているのと揃えるため。`File.join` の結果は vault 配下に収まるが、ユーザーの意図（vault 外の絶対パスを指したつもり）と挙動がずれるので、黙って vault 配下に解釈するより拒否するほうが分かりやすい。
- 実際に脱出しうる経路は create（title / `--dir`）と daily（basePath / fileNameFormat）。show に渡るパスは `Vault.list`（Dir.glob）由来、backup は元ファイルと同じ dirname に作るので、どちらも脱出しえない。それでも書き込み経路はすべて `path_for` を通すので、ここ 1 か所で防げる。

### 包含判定の共通化

- `normalize_prefix` の判定式 `candidate == root || candidate.start_with?("#{root}#{File::SEPARATOR}")` を、private の `within?(root, candidate)` に切り出す。`path_for` と `normalize_prefix` の両方がこれを使う。
- `normalize_prefix` は `File.realpath(vault)` を基準にしたまま変えない（vault は存在が保証されている）。
- `path_for` は vault の存在を前提にしない。既存 spec は `"/v"` のような存在しないパスで呼んでいるので、`File.expand_path` を使う。
- `within?` は root が `/` で終わる場合（vault が `/`）に `"//"` との前方一致にならないよう、区切りを付ける前に root 末尾の separator を除く。

### エッジケース

| 入力 | 結果 |
|------|------|
| `path_for("/v", "../x.md")` | `InvalidPath` |
| `path_for("/v", "a/../../x.md")` | `InvalidPath` |
| `path_for("/v", "a/../b.md")` | `"/v/a/../b.md"`（中に収まるので許可） |
| `path_for("/v", "/etc", "x.md")` | `InvalidPath`（絶対パスの segment は拒否） |
| `path_for("/v", nil, "")` | `"/v"`（vault 自身。従来どおり） |
| `path_for("/vault", "../vault2/x.md")` | `InvalidPath`（前方一致の誤判定を `File::SEPARATOR` で防ぐ） |
| `path_for("/", "a.md")` | `"/a.md"`（vault が `/` でも誤って拒否しない） |
| daily で `fileNameFormat = "../../%Y"`（既定の basePath `daily/` から 2 段上がる） | `InvalidPath`（daily は basePath と日付文字列を両方 `path_for` に渡すので、同じ経路で防げる。`"../%Y"` は `daily/../` で vault 内に収まるので許可） |

### ADR 0002 との整合

- 例外表に「書き込み先パスが vault を抜けている → 自前検出 → `Vault::InvalidPath`」の 1 行を足す。
- ADR 本文に残っている旧クラス名の一括更新は、別 PR（chore/cleanup-docs-lint）で行う。

## TODO（TDDタスク分解）

- [x] **T1**: `Reject vault-escaping segments in Vault.path_for`
    - Red: `spec/nob/vault_spec.rb` の `.path_for` に、上のエッジケース表の各行を追加する（脱出は `InvalidPath`、それ以外は従来の返り値）。`InvalidPath < Nob::Error` も assert する。
    - Green: `InvalidPath` を定義し、`path_for` に包含判定を入れる。Refactor で `within?` を切り出し、`normalize_prefix` にも適用する。
- [x] **T2**: `Add CLI regression specs for vault escape via create and daily`
    - 回帰テスト（T1 で実装済みなので Red は成立しない。CLI 経路の結線確認が目的）。`spec/nob/cli_spec.rb` に次を追加する。
      - `create x --dir ../escaped` と `create ../evil` が `Error: path escapes the vault` で exit 1 になること。ファイルも `../escaped` ディレクトリも作られないこと。
      - basePath が `../out` の `daily` が同様に exit 1 になり、何も作られないこと。
- [x] **T3**: `Document vault-confined write paths in RBS, ADR and design`
    - `mise run generate:typesig` で `sig/nob/vault.rbs` を再生成し、vault.rbs の差分だけをコミットする。他ファイルに無関係な差分が出たら捨てる。
    - `docs/adr/0002_error-policy.md` の例外表に 1 行足す。
    - `docs/design.md` の「ノート管理」に次を明記する。書き込み先（create の title / `--dir`、daily の basePath / fileNameFormat）は vault 内に限り、絶対パスと vault 外を指す `..` は拒否する。symlink は検査しない。
- [x] **T4**: `Point setup-homebrew at main in CI`（Implement 中に追加）
    - Homebrew/actions のデフォルトブランチが `master` から `main` に変わり、check-format ジョブが Set up job の段階で `Unable to resolve action homebrew/actions@master` になっていた。main ブランチでも同様に落ちるため、この PR で直す。

## レビューフィードバック

### Plan peer-review (2026-10-22)

Critical: なし

- Important
  - RBS は TypeProf 生成物なので、手書きせず再生成する → **反映**（T3）
  - 絶対パス segment の扱いが prefix 側と不揃い。表の `"/v//etc/x.md"` は誤りで、実際は `"/v/etc/x.md"` → **反映**（絶対パスは拒否に統一し、表を修正）
  - T2 は Red が成立しない。`../escaped` ディレクトリが作られないことも assert すべき → **反映**（回帰テストと明記し、ディレクトリ不在も assert）
  - design.md の更新 TODO がない → **反映**（T3 に追加）
- Nice-to-have
  - vault が `/` のとき `within?` が全拒否になる → **反映**（設計とエッジケース表）
  - fileNameFormat の `../` ケース → **反映**（エッジケース表）
  - 「show も守られる」の書き方が不正確 → **反映**（脱出しうる経路を明記）
- Out of scope（plan の判断を維持）: symlink の realpath 検査、vault 外の template_path の読み込み、ADR 旧クラス名の一括更新（別 PR）

### Code peer-review (2026-10-23)

Critical: なし / Important: なし（全件 3 件）

- Important: なし
  - 補足: `path_for` の呼び出し 3 箇所（create・daily・show）はすべて検査を通る。例外は `mkdir_p` と backup より前に raise され、`invoke_command` が `Error:` / exit 1 に変換する。148 examples, 0 failures。
- Nice-to-have
  - daily の `fileNameFormat = "../%Y"` を CLI 経路で確かめる spec がない（plan のエッジケース表には載っているが、CLI 経路の spec は basePath だけ）
    → 対応済（Refine コミット `Add CLI regression specs for absolute --dir and fileNameFormat`）。エッジケース表の `"../%Y"` は既定の basePath だと vault 内に収まるため、`"../../%Y"` に訂正した。spec を書く中で、エラーメッセージが `daily//../..` と二重スラッシュになる問題が見つかった。segment の連結を `File.join` に変えて同じコミットで直した
  - `create x --dir /tmp` のような絶対パスを CLI から渡す回帰 spec がない（`path_for` の単体 spec では確認済み）
    → 対応済（同上のコミット）
  - vault 内に収まる `..` を許可した副作用で、`create b --dir a/..` は `mkdir_p("/v/a/..")` により空の `a/` を作る → plan で許可すると決めた範囲内。記録に残すだけにする
    → 見送り（設計どおり。vault 外への副作用ではない）
- Out of scope
  - symlink 先の検査（plan と design.md でスコープ外と明記済み）
  - ADR 0002 の表で旧クラス名と `Vault::InvalidPath` の表記が混在している → PR-B（chore/cleanup-docs-lint）で一括更新
  - CI の `@master` から `@main` への変更は妥当

## 実装と計画の差分（recap）

### 意図的な変更
- 絶対パスの segment（初版 plan では「File.join の結果が vault 配下に収まるので許可」）: `InvalidPath` で拒否する — plan peer-review で `--prefix` の扱いと揃っていないと指摘された。初版の表に書いた `File.join` の結果（`"/v//etc/x.md"`）も誤りだった
- エラーメッセージの segment 連結（初版の設計は `"/"` で join）: `File.join` に変更 — 既定の basePath `daily/` で `daily//../..` と二重スラッシュになることが、Refine の spec で分かった
- エッジケース表の `fileNameFormat = "../%Y"`: `"../../%Y"` に訂正 — 既定の basePath だと `daily/../` で vault 内に収まり、脱出しない。学び: 表に載せたエッジケースは、実際の既定値と組み合わせて確かめる

### 想定外の追加
- T4 `Point setup-homebrew at main in CI`: Homebrew/actions のデフォルトブランチが `master` から `main` に変わり、check-format ジョブが起動前に失敗していた。main ブランチでも同じ原因で落ちるため、この PR で直した
- Refine の追加 spec（CLI 経路で絶対パスの `--dir` と fileNameFormat を確認）: code peer-review の Nice-to-have を採用した

### 削除・スキップ
- `create b --dir a/..` で空の `a/` ができる副作用: 設計どおりなので対応しない
- TODO とコミットの対応: T1〜T4 がそれぞれ 1 コミット、Refine が 1 コミット。plan の TODO と git log が 1 対 1 で対応している
