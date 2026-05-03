# Phase: PLAN

実装計画を立てる。設計とテストの分解までをこのフェーズで完成させ、`docs/plans/<slug>.md` を成果物とする。

## ゴール

- 何を作り、なぜ作るかが言語化されている
- 採用する設計（モジュール構成、API、データ構造、エッジケース）が明文化されている
- TDD で進められる粒度の TODO リストに分解されている
- user の合意が取れている

## 手順

1. **slug 確定**
   - 未指定なら 1 問で user に確認（「機能のスラッグを kebab-case で。例: `daily-note`」）
   - 同名 plan がすでに存在する場合は user に上書きの可否を確認

2. **インプットを集める**
   - user に「何を作りたいか／背景・制約」を 1〜3 個の絞った質問で聞く
   - 関連コードを把握する必要があれば `Agent(subagent_type=Explore)` に短く依頼。コードベースの該当部分を要約させる
   - `docs/design.md` がある場合は必ず Read し、整合を取る

3. **設計のたたき台を書く**
   - モジュール／クラスの責務分割
   - 公開 API の signature 案
   - データ形式（ファイル、frontmatter、引数 など）
   - エッジケース・失敗時の振る舞い
   - 設計判断の根拠を 1 行ずつ添える

4. **タスク分解（= コミットプラン）**
   - **1 task = 1 commit** が原則。task は「green になった瞬間にそのまま commit できる粒度」で切る
   - Red→Green→Refactor は 1 task の内部サイクル。別 task に切らない
   - 各 task は次の 2 段で書く:
     - 1 行目: そのままコミットメッセージ subject になる短い英語フレーズ（70 字以内、命令形 / 動詞始まり）
     - 続けて、Red で書くテストの意図と Green で実装する範囲を 1〜2 行で補足
   - 「全テスト green の確認」のように差分を生まない作業は task に書かない（commit にならない task は不要）
   - 並べ順は Red→Green→Refactor の TDD 連続性 + 依存方向（先に作るべきものから）で決める
   - チェックボックス形式で書く

   フォーマット例:

   ```markdown
   - [ ] **T1**: `Add Templates module skeleton with exception classes`
       - Red: `spec/nob/templates_spec.rb` で `UndefinedVariable` / `ParseError` が `Nob::Error` を継承していることを assert
       - Green: `lib/nob/templates.rb` に例外と `Token` / `Literal` / `Variable` を定義
   ```

5. **plan ファイルを書き出す**
   - 出力先: `docs/plans/YYYY-MM-DD_{slug}.md`（YYYY-MM-DD は作成日）
   - frontmatter:
     - `title`, `slug`, `status: planning`, `created`, `updated` を埋める
   - セクション: 目的・背景 / 設計 / TODO / レビューフィードバック（空） / 実装と計画の差分（空）

6. **plan レビュー**
   - `peer-review` skill を `plan=<planファイルパス>` モードで呼ぶ
   - 結果を plan の「レビューフィードバック」セクションに記録する
   - Critical / Important の指摘があれば plan を修正してから次へ進む

7. **user レビュー**
   - plan の要点（目的・設計の核・TODO 件数）と peer-review の Critical 件数を簡潔にまとめて提示
   - 修正があれば反映
   - OK が出たら `status: implementing` に更新し、`Implement に進みますか？` と user に確認して終了

## 出さない情報

- 実装コードそのもの（このフェーズではテストもコードも書かない）
- 詳細な命名議論（モジュール／クラス粒度まででよい）

## 失敗時の振る舞い

- 要件が曖昧で設計に踏み込めない場合は、判断材料が不足していることを user に共有して質問する。憶測で書き進めない
