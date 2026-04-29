---
name: dev-workflow
description: 機能単位の開発フローを Plan → Implement → Review → Refine → Recap で段階的に進めるためのオーケストレーション skill。実装は t-wada 流の TDD に従う。状態は docs/plans/YYYY-MM-DD_{slug}.md のフロントマターで管理する。
---

# dev-workflow

機能単位の開発を 5 フェーズに分けて進める。各 feature の真実の源（source of truth）は `docs/plans/<slug>.md`。SKILL.md は薄いオーケストレータとして振る舞い、実フェーズの手順は各フェーズ MD に委譲する。

## 起動

```
/dev-workflow [phase] [slug]
```

- `phase`: `plan` | `implement` | `review` | `refine` | `recap`
- `slug`: kebab-case の機能識別子（例: `daily-note`, `link-resolver`）

引数が不足している場合は user に最大 1 問だけ確認してから進める。

## フェーズ判定とディスパッチ

1. **引数を解釈**
   - 第1引数 → `phase`
   - 第2引数 → `slug`
2. **`slug` が未指定**:
   - `docs/plans/????-??-??_*.md` を Glob し、frontmatter `status` が `done` 以外のものを抽出
   - 1 件 → それを使う
   - 0 件もしくは 2 件以上 → user に確認
3. **`phase` が未指定**:
   - 当該 plan の `status` から推測（例: `implementing` → 続きとして `implement`）
   - 推測できなければ user に確認
4. **対応する MD を Read して、その手順に従う**:
   - `plan` → `PLAN.md`
   - `implement` → `IMPLEMENT.md`
   - `review` → `REVIEW.md`
   - `refine` → `REFINE.md`
   - `recap` → `RECAP.md`

## plan ファイルのスキーマ

ファイル名: `docs/plans/YYYY-MM-DD_{slug}.md`
- `YYYY-MM-DD` は plan 作成日（created と同じ日付）
- 日付 prefix により `ls` で時系列順に並ぶ。類似スコープの plan が複数生まれても衝突しない

```markdown
---
title: <人間可読タイトル>
slug: <slug>
status: planning | implementing | reviewing | refining | done
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

## 目的・背景

## 設計

## TODO（TDDタスク分解）

- [ ] ...

## レビューフィードバック

## 実装と計画の差分（recap）
```

各フェーズの完了時、対応する skill が `status` と `updated` を更新する。

## 横断的なルール

- どのフェーズに入っても、まず `docs/plans/<slug>.md` を **Read** して現状を把握すること
- 各フェーズの末尾で plan ファイルの該当セクションと frontmatter を更新すること
- フェーズの境界を user に明示する（「Plan が完了したので Implement に進みます」のように 1 文）
- 不足しているセクションや使われないセクションが見つかった場合は、SKILL.md / 各フェーズ MD と一緒に整理する提案を user に出す
