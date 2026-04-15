# Design: #244 Separate project-label-routing as optional sub-feature with interactive setup

## Architecture Overview

`project-label-routing.yml` を `project-integration` プラグインのサブ機能として分離する。
`plugin_interactive_setup()` の末尾でopt-in確認を行い、有効化された場合のみワークフローのコピーと`label_projects`の対話的セットアップを実行する。

## Module Structure

```
templates/github-actions/project-integration/
├── .github/workflows/
│   ├── project-integration.yml    # (no change) Core workflow
│   ├── pr-project-status.yml      # (no change) PR status workflow
│   └── project-label-routing.yml  # (no change) Label routing workflow template
└── plugin.sh                      # Modified: conditional copy + interactive setup
```

## Changes to plugin.sh

### 1. New Global Variable

```bash
# In init_field_config_vars()
ENABLE_LABEL_ROUTING="false"
```

### 2. New Function: `prompt_label_routing_setup()`

Label routing のopt-in確認と `label_projects` の対話的設定を行う。

**Flow:**
1. "Enable label-based project routing? (y/n)" を確認
2. Yesの場合、ラベル→プロジェクトのマッピングをループで入力
3. 各マッピングで:
   - ラベル名を入力
   - プロジェクトを選択（gh CLI auto-detection or manual）
   - `field_defaults` を設定（既存の `prompt_single_select_field_value` パターンを再利用）
4. 複数エントリ対応（"Add another? (y/n)" ループ）

**Data Structure:**
```bash
# Associative arrays for label routing
declare -gA LABEL_ROUTING_PROJECTS    # label -> "owner:number"
declare -gA LABEL_ROUTING_FIELDS      # "label:field_name" -> "value"
```

### 3. Modify `plugin_interactive_setup()`

末尾（L782付近、`print_success "Project configuration collected"` の前）に `prompt_label_routing_setup` 呼び出しを追加。

### 4. Modify `plugin_copy()`

`project-label-routing.yml` を条件付きコピーに変更:

```bash
# Skip project-label-routing.yml if not enabled
if [[ "$workflow_name" == "project-label-routing.yml" ]] && [[ "$ENABLE_LABEL_ROUTING" != "true" ]]; then
    print_info "Skipping $workflow_name (label routing not enabled)"
    continue
fi
```

### 5. Modify `plugin_post_copy()`

`label_projects` セクションを条件付きで active YAML として書き込む:
- `ENABLE_LABEL_ROUTING == "true"` の場合: コメントアウトなしで `label_projects` を書き込む
- `ENABLE_LABEL_ROUTING != "true"` の場合: 現状通りコメントアウトされた例を書き込む

## Interface Design

### New Functions

| Name | Signature | Description |
| --- | --- | --- |
| `prompt_label_routing_setup` | `()` | Label routing opt-in + interactive setup |
| `prompt_label_routing_project` | `(label_name)` | Single label→project mapping setup |
| `build_label_projects_yaml` | `()` → stdout | LABEL_ROUTING_* からYAMLを生成 |

### Modified Functions

| Name | Change | Description |
| --- | --- | --- |
| `init_field_config_vars` | Add vars | `ENABLE_LABEL_ROUTING`, `LABEL_ROUTING_PROJECTS`, `LABEL_ROUTING_FIELDS` 追加 |
| `plugin_interactive_setup` | Add call | 末尾に `prompt_label_routing_setup` 呼び出し追加 |
| `plugin_copy` | Add condition | `project-label-routing.yml` の条件付きスキップ |
| `plugin_post_copy` | Add condition | `label_projects` の条件付き書き込み |

## Data Flow

```
plugin_interactive_setup()
  └── (existing setup flow)
  └── prompt_label_routing_setup()
        ├── "Enable label routing?" → No → ENABLE_LABEL_ROUTING="false" → return
        └── Yes → ENABLE_LABEL_ROUTING="true"
              └── loop:
                    ├── prompt label name
                    ├── prompt_label_routing_project(label)
                    │     ├── gh CLI: select project from list
                    │     │   └── get_project_fields_detailed() → field setup
                    │     └── manual: enter owner + number + field_defaults
                    └── "Add another?" → y → continue loop
                                        → n → break

plugin_copy()
  └── for each workflow:
        └── if "project-label-routing.yml" && !ENABLE_LABEL_ROUTING → skip

plugin_post_copy()
  └── if ENABLE_LABEL_ROUTING:
        └── build_label_projects_yaml() → write active config
  └── else:
        └── write commented-out example (current behavior)
```

## Error Handling

- gh CLIが利用不可: manual fallback（owner/number/field_defaults手動入力）
- Project取得失敗: 警告表示して manual fallback
- field_defaults取得失敗: Statusのデフォルト値のみ設定

## Implementation Notes

- `LABEL_ROUTING_FIELDS` は `"label:field_name"` をキーとする複合キーで、ラベルごとの `field_defaults` を区別する
- 既存のプロジェクト選択・フィールド設定パターン（`get_owner_projects`, `get_project_fields_detailed`, `prompt_single_select_field_value`）を最大限再利用する
- non-interactive mode では `ENABLE_LABEL_ROUTING="false"` のままにする（従来通り）
