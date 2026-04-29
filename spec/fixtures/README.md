# spec/fixtures

テスト用の固定フィクスチャを置くディレクトリ。

## vault/

`spec/fixtures/vault/` は **読み取り専用の fixture vault** として、CLI / integration テストで使用する。

- **ファイルの内容を変えない** — テストの期待値（`FixtureVault::EXPECTED_NOTES` 等）と 1:1 で対応しているため、ファイルを追加・削除・リネームした場合は `spec/support/fixture_vault.rb` の `EXPECTED_NOTES` も合わせて更新すること
- **書き込みを行うテストには使わない** — `nob create` のような書き込みを伴う操作は `Dir.mktmpdir` で独立した tmpdir を使うこと

### 配置物の意図

| パス | 意図 |
|------|------|
| `vault/README.md` | vault ルート直下のノート（ルート一覧に出る代表例） |
| `vault/daily/2026-04-30.md` | サブディレクトリ配下のノート（`--prefix daily` の絞り込みテスト） |
| `vault/projects/Plan.md` | 別サブディレクトリのノート（複数 prefix の区別テスト） |
| `vault/.nob/cache.md` | `.nob/` は nob が将来 vault ごとのキャッシュ・設定を置く想定のディレクトリ。dot-dir としてスキップされることを確認するためのファイル |
| `vault/ignore-me.txt` | `.md` 以外はフィルタされることを確認するためのファイル |
