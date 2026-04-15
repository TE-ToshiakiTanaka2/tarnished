# Workflow: #242 Add _shared/branch and _shared/issue Skills

## Implementation Steps

### Step 1: Create _shared/branch skill
- `.claude/skills/_shared/branch/SKILL.md` を作成
- elsur の _shared/branch から Issue モード部分を抽出・適応

### Step 2: Create _shared/issue skill
- `.claude/skills/_shared/issue/SKILL.md` を作成
- elsur の _shared/issue から Sub-Issue リンク以外の部分を抽出
- project.yml 読み込みを組み込み

### Step 3: Update /design skill
- Phase 1 のブランチ作成セクションを `_shared/branch` 参照に置き換え

### Step 4: Update /implement skill
- Phase 1 のブランチ検出・作成セクションを `_shared/branch` 参照に置き換え

### Step 5: Update /issue skill
- Phase 3 の Issue 作成・メタデータ設定を `_shared/issue` 参照に置き換え

### Step 6: Update templates
- `templates/claude/.claude/skills/_shared/` に branch と issue を追加
- テンプレートの design, implement, issue スキルも更新

## Task Dependencies

- Step 1-2: 並列実行可能
- Step 3-5: Step 1-2 完了後に並列実行可能
- Step 6: Step 3-5 完了後

## Test Strategy

- _shared/branch の手順が /design, /implement から正しく参照されること
- _shared/issue の手順が /issue から正しく参照されること
- 既存のワークフローが破壊されないこと
