# Design: #242 Add _shared/branch and _shared/issue Skills

## Architecture Overview

elsur リポジトリの `_shared` スキルパターンを tarnished に導入する。ブランチ作成と Issue 作成の共通ロジックを `_shared/branch` と `_shared/issue` に集約し、`/design`, `/implement`, `/issue` スキルからはこれらを参照する形にリファクタリングする。

## Module Structure

```
.claude/skills/
├── _shared/                     # NEW: 内部共通スキル（ユーザー直接呼び出し不可）
│   ├── branch/SKILL.md          # NEW: ブランチ作成・管理（Issueモード）
│   └── issue/SKILL.md           # NEW: Issue作成・メタデータ設定
├── design/SKILL.md              # UPDATE: ブランチ作成を _shared/branch 参照に
├── implement/SKILL.md           # UPDATE: ブランチ検出・作成を _shared/branch 参照に
├── issue/SKILL.md               # UPDATE: Issue作成を _shared/issue 参照に
├── pr/SKILL.md                  # NO CHANGE
└── review/SKILL.md              # NO CHANGE
```

## _shared/branch 設計

### スコープ

Issueモードのみ（Docs/Releaseモードは将来追加可能）。

### パラメータ

| Parameter | Required | Source |
| --- | --- | --- |
| issue_number | Yes | 呼び出し元スキルから提供 |

### 手順

1. `gh issue view` で title, labels を取得
2. ラベル優先順位（`feature > bugfix > refactor > docs`）でブランチラベル決定
3. `gh api user` で assignee 取得
4. タイトルを kebab-case に正規化（50文字上限）
5. `git branch -a | grep "#{issue_number}"` で既存ブランチ検出
6. 既存あり → checkout、なし → develop ベースで新規作成

### 出力

呼び出し元スキルに以下を返す:
- ブランチ名
- 新規作成 or 既存再利用のステータス

## _shared/issue 設計

### パラメータ

| Parameter | Required | Description |
| --- | --- | --- |
| title | Yes | Issue タイトル（英語） |
| body | Yes | Issue 本文（Markdown） |
| labels | Yes | カンマ区切りラベル名 |
| assignee | No | デフォルト: 認証ユーザー |
| milestone | No | Milestone 名 |
| size | No | XS/S/M/L/XL |
| priority | No | P0/P1/P2 |

### 手順

1. assignee 未指定時は `gh api user --jq '.login'` で取得
2. `gh issue create` で Issue 作成（**唯一のブロッキング操作**）
3. Milestone 設定（ノンブロッキング）
4. プロジェクト追加（`project.yml` から project_owner, project_number を読み込み）
5. Size/Priority フィールド設定（GraphQL）

### エラーハンドリング原則

Issue 作成のみブロッキング。メタデータ設定は全てノンブロッキング（失敗時は警告して続行）。

## 既存スキル更新方針

### /design

Phase 1 のブランチ作成手順を `_shared/branch` への参照に置き換え。インラインの命名規則・既存ブランチ検出ロジックを削除し、`_shared/branch` の手順に従う旨を記述。

### /implement

Phase 1 のブランチ検出・作成手順を `_shared/branch` への参照に置き換え。同上。

### /issue

Phase 3 の Issue 作成・メタデータ設定を `_shared/issue` への参照に置き換え。Issue 本文テンプレートとサイズ・優先度基準表はそのまま残す。

## Implementation Notes

- `_shared` スキルは `disable-model-invocation: true` ではなく、frontmatter で内部スキルであることを明示する（elsur パターンに準拠）
- `project.yml` の読み込みは `_shared/issue` の手順内で行う（`.github/project.yml` から `default_project.owner` と `default_project.number` を参照）
- テンプレートへの追加も同一コミットで行う
