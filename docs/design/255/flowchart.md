# Flowchart: #255 setup_plugins 制御フロー

`setup_plugins` 関数の実行フロー。各分岐は最終的に `return 0` で合流し、`set -e` 配下の post.sh を止めない。

```mermaid
graph TD
    A[setup_plugins start] --> B{claude CLI available?}
    B -->|No| Z0[Warning: skip plugin setup]
    Z0 --> Z[return 0]

    B -->|Yes| C[ensure_claude_marketplace<br/>anthropics/claude-plugins-official]
    C --> D{marketplace<br/>already registered?}
    D -->|Yes| F[claude plugins list -> plugins_output]
    D -->|No| E[claude plugins marketplace add]
    E --> E1{add succeeded?}
    E1 -->|No| E2[Warning: marketplace add failed]
    E2 --> Z
    E1 -->|Yes| F

    F --> G[try_install_plugin context7]
    G --> G1{installed?}
    G1 -->|Yes| H
    G1 -->|No| G2[claude plugins install context7]
    G2 --> G3{success?}
    G3 -->|Yes| H[try_install_plugin serena]
    G3 -->|No| G4[Warning: continue]
    G4 --> H

    H --> H1{installed?}
    H1 -->|Yes| I
    H1 -->|No| H2[claude plugins install serena]
    H2 --> H3{success?}
    H3 -->|Yes| I{interactive?}
    H3 -->|No| H4[Warning: continue]
    H4 --> I

    I -->|No| Y[echo skip playwright prompt]
    Y --> Z
    I -->|Yes| J{user yes?}
    J -->|No| Z
    J -->|Yes| K[try_install_plugin playwright]
    K --> Z
```

## 主要分岐の意図

| 分岐 | 失敗時の挙動 | 理由 |
| --- | --- | --- |
| `claude` CLI 検出 | warning + return 0 | Claude Code 未インストール環境でも post.sh は他のセットアップを継続する。 |
| marketplace 登録チェック | スキップ | 冪等性。既登録なら add を呼ばない。 |
| marketplace add 失敗 | warning + setup_plugins 全体を return 0 | ネットワーク不通等で add が失敗しても post.sh の他の処理を巻き込まない。以降のプラグイン install は意味がないので即終了。 |
| 個別プラグイン install 失敗 | warning + 次プラグインへ進む | 1 プラグインの失敗が他のプラグインに波及しない。 |
| 非対話環境での playwright | プロンプトを出さずスキップ | 既存挙動を維持。CI 等で停止させない。 |
