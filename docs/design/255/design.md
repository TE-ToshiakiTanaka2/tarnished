---
issue: 255
title: "setup_plugins.sh: claude plugins install が新規 devcontainer で失敗する"
type: bugfix
---

# Design: #255 setup_plugins.sh — Marketplace 未登録によるインストール失敗の修正

## Architecture Overview

`setup_plugins.sh` は devcontainer 起動時に Claude Code 公式プラグイン (context7 / serena / 任意で playwright) を `claude plugins install <name>@claude-plugins-official` でインストールする。

このコマンドは `claude-plugins-official` マーケットプレイスが事前に `~/.claude/plugins/known_marketplaces.json` に登録済みであることを前提とする。Claude Code はこのマーケットプレイスを組み込みで保持しないため、新規 devcontainer (clean state) では必ず失敗する。

加えて呼び出し元の `post.sh` 冒頭で `set -e` が有効なため、最初の plugin install 失敗で `setup_plugins` 関数自体が `return` され、`post.sh` のスクリプト実行も停止する。

本修正では次の 3 点を行う:

1. `setup_plugins` 内に **マーケットプレイス登録の冪等化処理** を追加する (`claude plugins marketplace add anthropics/claude-plugins-official`)。
2. 各 `claude plugins install` 呼び出しを **個別の if 分岐で囲み**、1 プラグインの失敗が他のプラグインや後続処理を巻き込まないようにする。
3. マーケットプレイス登録自体に失敗した場合は **warning を出力して `return 0`** することで、`post.sh` 全体 (`set -e`) の中断を防ぐ。

`post.sh` 側のスクリプト構造 (`set -e`, `is_interactive`, `setup_plugins.sh` の source) は変更しない。修正は `setup_plugins.sh` 単体で完結する。

## Module Structure

```
.devcontainer/scripts/
├── post.sh              # 既存 (変更なし) — set -e のもと setup_plugins.sh を source
└── setup_plugins.sh     # 修正対象
    ├── ensure_claude_marketplace()  # 新規: marketplace 冪等登録ヘルパ
    ├── try_install_plugin()         # 新規: 単一プラグイン install ヘルパ (失敗を吸収)
    └── setup_plugins()              # 修正: ensure_claude_marketplace と try_install_plugin を呼ぶ
```

新規ファイルは作らない。`setup_plugins.sh` 内部の関数を整理して再構成する。

## Interface Design

### Functions

| 関数 | シグネチャ | 役割 |
| --- | --- | --- |
| `ensure_claude_marketplace` | `(marketplace_repo: string) -> 0\|1` | `claude plugins marketplace list` で `<marketplace_repo>` の登録有無を確認し、未登録なら `claude plugins marketplace add <marketplace_repo>` を実行。失敗時は warning を出力して非 0 を返す。 |
| `try_install_plugin` | `(plugin_name: string, marketplace: string, plugins_output: string) -> 0` | `plugins_output` に `<plugin_name>` が含まれていればスキップ。そうでなければ `claude plugins install <plugin_name>@<marketplace> -s project` を試み、失敗しても warning を出すだけで常に 0 を返す。 |
| `setup_plugins` | `() -> 0` | 既存。Claude CLI 検出 → `ensure_claude_marketplace` → `plugins list` → `try_install_plugin` を 3 プラグインに対して呼ぶ流れに変更。 |

### Marketplace Identifier

| 種類 | 値 |
| --- | --- |
| Marketplace 名 (install 時の suffix) | `claude-plugins-official` |
| Marketplace add 時の引数 (GitHub repo) | `anthropics/claude-plugins-official` |

`marketplace add` の引数は GitHub の `<owner>/<repo>` 形式。一方 `install` は登録済み marketplace の **論理名** (`claude-plugins-official`) を suffix に付ける。両者は同じ marketplace を指すが文字列としては異なる。

### 冪等性ポリシー

- `ensure_claude_marketplace`: `claude plugins marketplace list` の出力に `claude-plugins-official` (または `anthropics/claude-plugins-official`) を grep でマッチ。マッチしたら add をスキップ。
- `try_install_plugin`: `claude plugins list` の事前取得結果に plugin 名がマッチしたらスキップ。
- 結果として fresh state でも 2 回目の実行でも全て "already ..." でスキップされる。

## Data Flow

```
post.sh (set -e)
  └─> source setup_plugins.sh
        └─> setup_plugins()
              ├─ command -v claude  → なければ return 0
              ├─ ensure_claude_marketplace "anthropics/claude-plugins-official"
              │     ├─ claude plugins marketplace list
              │     ├─ already registered? → return 0
              │     ├─ claude plugins marketplace add ...
              │     └─ 失敗 → warning + return 1 (呼び出し側で return 0 する)
              ├─ plugins_output=$(claude plugins list)
              ├─ try_install_plugin "context7"  "claude-plugins-official" "$plugins_output"
              ├─ try_install_plugin "serena"    "claude-plugins-official" "$plugins_output"
              └─ try_install_plugin "playwright" ...  (interactive プロンプト経由)
```

`ensure_claude_marketplace` が失敗したら、`setup_plugins` は warning を出して **`return 0`** する。`set -e` 配下で関数が非 0 を返すと post.sh 全体が止まるため、必ず 0 で抜けることを保証する。

## Error Handling

| 失敗ケース | 挙動 | post.sh への影響 |
| --- | --- | --- |
| `claude` コマンド未インストール | warning 出力 + `return 0` (既存挙動を維持) | 後続処理は継続 |
| `claude plugins marketplace list` がエラー | warning 出力 + `return 0` | 後続処理は継続 |
| `claude plugins marketplace add` がエラー (ネットワーク等) | warning 出力 + `setup_plugins` 全体を `return 0` | 後続処理は継続 |
| 単一プラグインの install 失敗 | warning 出力、他プラグインの試行は継続 | 後続処理は継続 |
| 全プラグインが既にインストール済み | "already installed, skipping" を出力 | 後続処理は継続 |

設計原則: **`setup_plugins` は何があっても `0` を返す**。devcontainer の post-create は他の重要な初期化 (Rust, code quality tools, Codex 等) を行うため、プラグインインストール失敗が全体を止めることを許容しない。

## Implementation Notes

### Key decisions

- **Helper 関数を分離**: `ensure_claude_marketplace` / `try_install_plugin` を導入することで、`setup_plugins` 本体は宣言的に読める。重複した `if echo "$plugins_output" | grep -q ... ; else claude plugins install ... ; fi` パターンを排除。
- **`return 0` の徹底**: shell の `set -e` 環境下で関数を確実に非中断にするため、ヘルパが非 0 を返した場合でも `setup_plugins` 自体は 0 で抜ける。これは "プラグインは best-effort" という意図を明示する。
- **`grep -q` のマッチ条件**: `claude plugins marketplace list` の出力フォーマットは将来変わる可能性があるため、`claude-plugins-official` というマーケットプレイス名と `anthropics/claude-plugins-official` という GitHub 参照のどちらにマッチしてもよいよう、両方に反応する `grep -E "claude-plugins-official"` を使う (短い形式で十分)。
- **shellcheck**: 既存スクリプトと同様に shellcheck をパスする。`local` 変数のクォート、`"$var"` 展開を徹底する。

### Edge cases

- **既存 devcontainer (キャッシュあり)**: `known_marketplaces.json` に既に登録済みの状態。`ensure_claude_marketplace` は list 出力を grep して既登録を検出し、`add` をスキップする。
- **Network 起因の add 失敗**: `claude plugins marketplace add` は GitHub にアクセスする。オフライン環境では失敗するが、warning のみで post.sh は継続する。
- **playwright の対話プロンプト**: 既存実装と同様、`is_interactive` のときだけプロンプトを表示。非対話環境ではスキップ。
- **冪等再実行**: 全 helper が "既存ならスキップ" のロジックを持つため、何回実行しても副作用なく完了する。

### Out of scope

- `post.sh` 側の `set -e` を外す/緩める変更は行わない (他の関数の失敗は引き続き止まるべき)。
- 他の `setup_*` 関数 (Rust, code quality, Codex 等) の修正は行わない。
- 新規プラグインの追加は行わない。

## Verification

Issue の "検証手順" に従う:

1. `rm -f ~/.claude/plugins/known_marketplaces.json ~/.claude/plugins/installed_plugins.json` で fresh state を再現。
2. `bash -c 'set -e; source .devcontainer/scripts/setup_plugins.sh; setup_plugins'` を実行。
3. 期待結果:
   - marketplace が自動登録される
   - `context7@claude-plugins-official` と `serena@claude-plugins-official` が project スコープで install される
   - 終了コード `0`
4. 再実行時、全てが "already ..." 系のメッセージでスキップされ、終了コード `0` (冪等性)。
5. 追加: `claude` コマンドが PATH にない環境でも `setup_plugins` が `0` で抜けること (既存挙動の維持)。
