# Workflow: #240 Internalize SuperClaude Front-Half Skills as erd: Commands

## Implementation Steps

### Step 1: Create erd commands directory

- `.claude/commands/erd/` ディレクトリを作成

### Step 2: Create brainstorm.md

- SuperClaude `sc:brainstorm` の本質を抽出
- ソクラテス式対話パターンと要件探索チェックリストを定義
- sequential-thinking MCP 連携を記述
- CRITICAL BOUNDARIES（要件発見のみ）を定義

### Step 3: Create estimate.md

- SuperClaude `sc:estimate` の本質を抽出
- Size/Priority 判定基準表を組み込み
- コードベース分析手法を記述
- CRITICAL BOUNDARIES（見積もりのみ）を定義

### Step 4: Create research.md

- SuperClaude `sc:research` の本質を抽出
- WebSearch + context7 による調査フローを定義
- エビデンス管理と出力フォーマットを記述
- CRITICAL BOUNDARIES（調査レポートのみ）を定義

### Step 5: Create design.md

- SuperClaude `sc:design` の本質を抽出
- serena MCP を活用した既存構造分析を記述
- 設計ドキュメントの出力テンプレートを定義
- CRITICAL BOUNDARIES（設計のみ）を定義

### Step 6: Create workflow.md

- SuperClaude `sc:workflow` の本質を抽出
- sequential-thinking によるタスク分解フローを定義
- 実装ステップ/依存関係/テスト戦略のテンプレートを記述
- CRITICAL BOUNDARIES（計画のみ）を定義

### Step 7: Update /issue skill

- `.claude/skills/issue/SKILL.md` の `sc:` 参照を `erd:` に差し替え
- セクション名の更新（SuperClaude Skills Used → erd Skills Used）
- description の更新

### Step 8: Update /design skill

- `.claude/skills/design/SKILL.md` の `sc:` 参照を `erd:` に差し替え
- セクション名の更新
- description の更新

### Step 9: Verification

- `/erd:brainstorm` が単独で呼び出せることを確認
- 各コマンドのフォーマットが Claude Code の仕様に準拠していることを確認

## Task Dependencies

```
Step 1 (create dir)
  └── Step 2-6 (create commands, parallel)
        └── Step 7-8 (update skills, parallel)
              └── Step 9 (verification)
```

- Step 2-6 は相互依存なし、並列実行可能
- Step 7-8 は Step 2-6 の完了後に実行（参照先が存在する必要があるため）
- Step 9 は全ステップ完了後に実行

## Test Strategy

- **呼び出し確認**: `/erd:brainstorm` がコマンドとして認識されること
- **フォーマット確認**: 各コマンドの markdown が正しくパースされること
- **スキル互換性**: `/issue` と `/design` が `erd:` コマンドを正しく参照すること
- **並行利用**: `/sc:*` と `/erd:*` が同時に利用可能であること
