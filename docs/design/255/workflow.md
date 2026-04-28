---
issue: 255
title: "setup_plugins.sh: claude plugins install が新規 devcontainer で失敗する"
type: bugfix
---

# Workflow: #255 setup_plugins.sh — Marketplace 登録と失敗の隔離

## Implementation Steps

### Step 1: ヘルパ関数 `ensure_claude_marketplace` の追加

- **Action**:
  - `setup_plugins.sh` に新しい関数 `ensure_claude_marketplace` を追加する。
  - 引数: marketplace の GitHub repo (`anthropics/claude-plugins-official`)。
  - `claude plugins marketplace list 2>/dev/null` の出力を `grep -q "claude-plugins-official"` で確認。マッチしたら `return 0` (登録済み)。
  - 未登録なら `claude plugins marketplace add "$1"` を試行。成功で `return 0`、失敗で warning を `>&2` に出力して `return 1`。
- **Files**: `.devcontainer/scripts/setup_plugins.sh`
- **Depends on**: なし
- **Done when**:
  - 関数が定義され、`shellcheck .devcontainer/scripts/setup_plugins.sh` がパスする。
  - 単体で関数を呼び出して、登録済み/未登録の両ケースで適切な戻り値を返すことを確認できる。

### Step 2: ヘルパ関数 `try_install_plugin` の追加

- **Action**:
  - `setup_plugins.sh` に新しい関数 `try_install_plugin` を追加する。
  - 引数: `plugin_name` (例 `context7`), `marketplace` (例 `claude-plugins-official`), `plugins_output` (`claude plugins list` の事前取得結果)。
  - `plugins_output` に plugin 名が含まれていれば "already installed, skipping" を出力して `return 0`。
  - そうでなければ `claude plugins install "${plugin_name}@${marketplace}" -s project` を実行。失敗してもメッセージを出すだけで `return 0`。
- **Files**: `.devcontainer/scripts/setup_plugins.sh`
- **Depends on**: なし (Step 1 と並行可能)
- **Done when**:
  - 関数が定義され、shellcheck をパスする。
  - install 失敗時にも 0 を返すことが確認できる (`if try_install_plugin ...` が常に true)。

### Step 3: `setup_plugins` 本体のリファクタリング

- **Action**:
  - 既存の context7 / serena / playwright のインライン install ブロックを削除する。
  - `claude` 検出直後に `ensure_claude_marketplace "anthropics/claude-plugins-official"` を呼び、失敗したら warning + `return 0`。
  - その後 `plugins_output=$(claude plugins list 2>/dev/null)` で一括取得 (既存ロジックを維持)。
  - context7, serena, playwright の install 呼び出しを `try_install_plugin` ベースに置き換える。
  - playwright は既存の対話プロンプト (`is_interactive`) でラップし、ユーザが yes と答えた場合のみ `try_install_plugin` を呼ぶ。
- **Files**: `.devcontainer/scripts/setup_plugins.sh`
- **Depends on**: Step 1, Step 2
- **Done when**:
  - `setup_plugins` の本体が宣言的に読める (重複した if 分岐がない)。
  - shellcheck がパスする。
  - 既存の出力フォーマット ("Installing ... plugin", "already installed, skipping" 等) と互換である。

### Step 4: Fresh state 再現での動作検証

- **Action**:
  - 以下のコマンドで fresh state を再現:
    ```bash
    rm -f ~/.claude/plugins/known_marketplaces.json ~/.claude/plugins/installed_plugins.json
    ```
  - 修正後のスクリプトを `set -e` 配下で source して実行:
    ```bash
    bash -c 'set -e; source .devcontainer/scripts/setup_plugins.sh; setup_plugins'
    ```
  - 終了コード `0` であること、`echo $?` で確認。
  - context7 / serena が project スコープで install されたことを `claude plugins list` で確認。
- **Files**: なし (検証のみ)
- **Depends on**: Step 3
- **Done when**:
  - 終了コード 0
  - `claude plugins list` に `context7` および `serena` が表示される
  - `claude plugins marketplace list` に `claude-plugins-official` が表示される

### Step 5: 冪等再実行検証

- **Action**:
  - Step 4 の直後に同じコマンドを再度実行する。
  - "already ..." 系のスキップメッセージのみが出力されることを確認。
  - 終了コード `0` であることを確認。
- **Files**: なし
- **Depends on**: Step 4
- **Done when**:
  - 全プラグインが "already installed, skipping" としてスキップされる
  - marketplace も "already registered" 相当のスキップになる
  - 終了コード 0

### Step 6: 失敗ケースの隔離検証

- **Action**:
  - 一時的に存在しない marketplace 名で install を試みるなど、人為的に失敗を発生させる (例: `try_install_plugin "nonexistent" "claude-plugins-official" ""` をテストハーネスから呼び出す)。
  - `setup_plugins` 全体が `set -e` 配下でも止まらず `return 0` で抜けることを確認する。
  - 別の方法として、`ensure_claude_marketplace` を一時的に `return 1` するパッチを当てて post.sh の後続処理 (`setup_codex` 等) が実行されることを確認する。
- **Files**: なし (検証のみ)
- **Depends on**: Step 3
- **Done when**:
  - 単一プラグインの install 失敗が他プラグインの試行を止めない
  - marketplace 登録の失敗が `setup_plugins` 全体および post.sh を止めない
  - post.sh 末尾の "Post-creation setup complete!" が出力される

### Step 7: 静的解析と最終確認

- **Action**:
  - `shellcheck .devcontainer/scripts/setup_plugins.sh` をパスすること。
  - 既存の `.claude/rules/shell.md` のルール (4-space indent, lowercased local vars, quoted expansions, `[[ ]]` 等) に従っていること。
  - `set -euo pipefail` を新規追加するかは既存ファイルと整合させる (現状 `setup_plugins.sh` 単体ではこれを設定していないため、source される側のスクリプトとして post.sh の `set -e` を尊重する。新規追加はしない)。
- **Files**: `.devcontainer/scripts/setup_plugins.sh`
- **Depends on**: Step 3
- **Done when**:
  - shellcheck エラー 0
  - rules/shell.md のチェック項目を満たす

## Task Dependencies

- Step 1 と Step 2 は **並行可能** (互いに独立した関数追加)。
- Step 3 は Step 1 と Step 2 に依存。
- Step 4, Step 5, Step 6, Step 7 は Step 3 完了後に実施。Step 4 → Step 5 は順序依存 (前者の状態を後者が利用)。Step 6 と Step 7 は Step 3 完了後ならいつでも可能。

```
Step 1 ─┐
        ├─> Step 3 ─┬─> Step 4 ─> Step 5
Step 2 ─┘           ├─> Step 6
                    └─> Step 7
```

## Test Strategy

### Unit-level (function isolation)

- `ensure_claude_marketplace`:
  - 既登録の場合 → 0、`add` を呼ばない
  - 未登録の場合 → `add` を呼んで成功 → 0
  - `add` が失敗 → 1 を返し warning を出す
- `try_install_plugin`:
  - plugin 名が `plugins_output` にあれば "already installed" を出力して 0
  - install 成功時 → 0
  - install 失敗時 → warning を出すが 0

### Integration (script-level)

- Issue の検証手順 (fresh state → 全 install 成功 → 再実行で全スキップ) を再現。
- post.sh から source した状態で `set -e` 配下でも `setup_plugins` が常に 0 で抜けること。
- `claude` コマンド未検出環境でも 0 で抜けること (既存挙動の回帰確認)。

### Edge cases

- `claude plugins marketplace list` が空出力 (新規 install 直後)。
- `claude plugins marketplace list` が non-zero 終了 (CLI バージョン差異)。
- ネットワーク不通による `marketplace add` の失敗。
- playwright プラグインの対話プロンプトが非対話環境でスキップされること。
- 同一 plugin が複数の marketplace から候補化されるケース (現状は `claude-plugins-official` のみで非該当だが、将来の拡張を妨げない grep を使う)。

### 静的解析

- `shellcheck .devcontainer/scripts/setup_plugins.sh`
- `.claude/rules/shell.md` の遵守 (indent, quote, `[[ ]]`, `local` の使用)
