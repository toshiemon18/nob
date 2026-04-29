# Phase: REVIEW

実装を独立したレビューに掛け、結果を plan に記録する。レビュー実行そのものは別 skill `peer-review` に委譲し、このフェーズはコンテキストの受け渡しと plan への反映だけを担う。

## ゴール

- 第三者視点のレビュー結果が `docs/plans/<slug>.md` の「レビューフィードバック」セクションに記録されている
- フィードバックが優先度別に整理されている（Critical / Important / Nice-to-have / Out of scope）
- 次フェーズ（Refine）が判断材料として使える状態

## 手順

1. **状態確認**
   - `docs/plans/<slug>.md` を Read。`status` が `reviewing` であること

2. **`peer-review` skill を呼ぶ**
   - `Skill` ツールで `peer-review` を起動
   - 渡す情報:
     - 比較対象: 当該 feature の変更（plan 起動以降の作業ツリー＋直近コミット）
     - コンテキスト文書: `docs/plans/<slug>.md`（plan と整合しているかを観点に含めることを明示）
     - 保存先: `docs/plans/<slug>.md` の「レビューフィードバック」セクションに追記する旨を伝える

3. **plan ファイルへの反映**
   - peer-review の出力を「レビューフィードバック」セクションに整形して貼り付け
   - 末尾にレビュー実施日を 1 行で添える
   - 明らかに的外れな指摘や合意済みで再議論不要な点には `→ 却下（理由）` を付けてもよい（後で Refine 判断の根拠になる）

4. **user への提示**
   - Critical 件数と総件数を 1〜2 行で要約
   - 「Refine に進みますか？」と確認

5. **frontmatter 更新**
   - `status: refining`
   - `updated`: 当日

## peer-review 側の責務との分担

- **peer-review が担う**: 別 agent でのレビュー実行、出力の構造化（Critical/Important/...）
- **dev-workflow REVIEW が担う**: plan を真実の源として扱う、結果の plan ファイルへの反映、フェーズ遷移

peer-review の挙動を変えたい場合（観点・出力形式・対象範囲）は、`peer-review/SKILL.md` 側を直す。
