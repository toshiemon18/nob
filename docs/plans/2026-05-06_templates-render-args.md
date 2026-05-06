---
title: Templates.render の引数規約を厳格化する
slug: templates-render-args
status: planning
created: 2026-05-06
updated: 2026-05-06
---

## 目的・背景

2026-05-06 の peer-review (Templates 周りの実装レビュー) で `Nob::Templates.render` facade の引数規約に関して 2 件の Important 指摘が挙がった。

1. `path:` と `text:` 同時指定時に `text` が暗黙に勝ち、`path` を黙殺する (`lib/nob/templates.rb:10`)
2. `path: nil`, `text: nil` でも `title:` / `now:` 必須なのは facade の使い勝手として歪。「描画対象なし → 空文字」の分岐が早すぎ、引数規約と実体がミスマッチ (`lib/nob/templates.rb:9`)

facade を導入した直後 (2026-05-05 `templates-facade` サイクル) のうちに引数規約を確立しておく方が、後続 caller (将来的な `Notes::Creator` のテンプレ対応など) を巻き込んだ修正コストが小さい。

立脚する判断軸:

- **公開 API 一貫性**: facade は薄いが入口なので、引数規約の歪みは下流の caller にしわ寄せが来る
- **構造の一貫性 > YAGNI**: caller が単数 (`Notes::Daily`) でも、facade に空文字フォールバックを置くより caller 側に責務を寄せる方が「テンプレ未指定時のフォールバックは各機能の責務」(ADR 0001 の前提) と整合する

なお ADR 0001 §I 補追と現行 facade の責務定義に齟齬がある件は別 plan で扱う。本 plan は **実装の引数規約だけ** を対象とする。

## 設計

### 公開 API の改定

現状:

```ruby
Nob::Templates.render(title:, now:, path: nil, text: nil)
  # path 優先、text fallback、両 nil なら "" を返す
```

改定後:

```ruby
Nob::Templates.render(title:, now:, path: nil, text: nil)
  # path と text 両方指定 → ArgumentError
  # path も text も nil → ArgumentError
  # それ以外 → 従来通り String を返す
```

#### 例外メッセージ

- 両指定: `Nob::Templates.render: specify only one of path: or text:`
- 両 nil: `Nob::Templates.render: specify path: or text:`

`ArgumentError` を選ぶ理由: caller のプログラマエラーであり、エンドユーザが直せる種類のエラーではない。ADR 0002 の判断軸 (素通し) に沿う。`Nob::Error` 派生にはしない。

### caller 側の追従

`Nob::Notes::Daily.create` で `template_path: nil` を facade に渡している経路を、Daily 側で分岐する形に変更する:

```ruby
# Before
File.write(target_path, Nob::Templates.render(path: template_path, title: date_str, now: now))

# After
content = template_path.nil? ? "" : Nob::Templates.render(path: template_path, title: date_str, now: now)
File.write(target_path, content)
```

これにより「テンプレ未指定 → 空ファイル」のフォールバック責務が Daily 側に戻る。CLI 側の `warn "Warning: no daily-note template configured ..."` 出力は既に Daily の外 (`Cli#daily`) にあり、Daily が空文字フォールバックを持つことと整合する。

### 影響範囲

| ファイル | 変更内容 |
|---------|---------|
| `lib/nob/templates.rb` | `render` 引数バリデーション追加。`read_template` の nil 早期 return を削除（呼び出し時点で path nil は来なくなる） |
| `lib/nob/notes/daily.rb` | `template_path.nil?` 分岐を追加 |
| `spec/nob/templates_spec.rb` | 「両 nil で空文字」テストを削除し、「両 nil で ArgumentError」「両指定で ArgumentError」を追加 |
| `spec/nob/notes/daily_spec.rb` | template_path nil 時に空ファイルが生成される振る舞いは維持。実装が変わっても spec の期待は変わらない |

### エッジケース

- **`path: ""` (空文字)**: 現行 `read_template("")` は `File.exist?("")` が false で `Nob::Error` (template file not found) を raise する。改定後も同じ。空文字パスは「指定された」扱いに含める判断。Config が `template_path` を nil か absolute path どちらかに正規化しているので、facade に空文字が来るシナリオは現状無いが、API としての挙動は保つ
- **`text: ""` (空文字)**: 「render する対象として空文字テキストが指定された」扱い。`""` を返す。これは正常系
- **`title:` / `now:`**: 引き続き必須。caller が「描画対象なし」を facade に判断させる経路は塞がれるので、これらの kwargs が無意味になるケースは発生しない

### 戻り値

- 常に `String`。`nil` を返すパスは消える

### 何を変えないか

- `Renderer.render(template, title:, now:)` の signature (positional + kwargs) は本 plan のスコープ外
- `Templates::Loader` 撤去 / facade のファイル I/O 内包の是非は ADR 整合の話なので別 plan
- `Operators::Date` / `Operators::Time` の空 fmt 不整合は別 plan (Plan B 相当)

## TODO（TDDタスク分解）

- [ ] **T1**: `Move empty-template fallback into Notes::Daily`
    - Red: 既存の `daily_spec.rb` で「template 未設定なら空ファイルを書く」振る舞いを引き続き green に保つ。実装ミラーの新規 spec は書かない（memory: 実装そのものを再記述する spec を書かない）
    - Green: `Notes::Daily.create` で `template_path.nil? ? "" : Nob::Templates.render(...)` に分岐を追加。`Templates.render(path: nil)` の経路をこの caller から消す
    - Refactor: なし

- [ ] **T2**: `Reject path: and text: double-spec in Templates.render`
    - Red: `spec/nob/templates_spec.rb` で `Templates.render(path: ..., text: ..., title:, now:)` が `ArgumentError` を raise することを assert
    - Green: `lib/nob/templates.rb` の `render` 先頭で両指定を `ArgumentError` で弾く分岐を追加
    - Refactor: なし

- [ ] **T3**: `Reject path: and text: both-nil in Templates.render`
    - Red: 既存「両 nil で空文字を返す」テストを削除し、「両 nil で `ArgumentError` を raise する」テストに置き換え
    - Green: `Templates.render` の早期 return (`return "" if text.nil?`) を削除し、両 nil で `ArgumentError` を raise する分岐に置き換え。`read_template` 内の `return nil if path.nil?` も削除
    - Refactor: なし

T1 → T2 → T3 の順で進める理由: T1 を先に行わないと T3 で `Daily` 経由の既存テストが `ArgumentError` で落ちる。T1 はリファクタ (振る舞い不変) で commit を切り、T2 / T3 は仕様追加で各々独立した Red を持てる。

## レビューフィードバック

(plan 完了時に peer-review 結果を追記)

## 実装と計画の差分（recap）

(recap フェーズで追記)
