# Sequence Diagram: #255 fresh devcontainer での plugin install

新規 devcontainer (clean state) で post-create が走り、`setup_plugins.sh` がマーケットプレイスを登録した上で context7 / serena を install するまでの相互作用。

```mermaid
sequenceDiagram
    participant Post as post.sh<br/>(set -e)
    participant SP as setup_plugins.sh
    participant CLI as claude CLI
    participant FS as ~/.claude/plugins/<br/>known_marketplaces.json
    participant GH as github.com/<br/>anthropics/claude-plugins-official

    Post->>SP: source + setup_plugins
    SP->>CLI: command -v claude
    CLI-->>SP: present

    SP->>CLI: plugins marketplace list
    CLI->>FS: read known_marketplaces.json
    FS-->>CLI: (empty / not found)
    CLI-->>SP: no claude-plugins-official

    SP->>CLI: plugins marketplace add anthropics/claude-plugins-official
    CLI->>GH: fetch marketplace metadata
    GH-->>CLI: marketplace.json
    CLI->>FS: write known_marketplaces.json
    FS-->>CLI: ok
    CLI-->>SP: added

    SP->>CLI: plugins list
    CLI-->>SP: (empty)

    SP->>CLI: plugins install context7@claude-plugins-official -s project
    CLI->>FS: resolve marketplace -> install context7
    FS-->>CLI: ok
    CLI-->>SP: installed

    SP->>CLI: plugins install serena@claude-plugins-official -s project
    CLI->>FS: resolve marketplace -> install serena
    FS-->>CLI: ok
    CLI-->>SP: installed

    Note over SP: playwright: 非対話環境ではスキップ

    SP-->>Post: return 0
    Post->>Post: continue with setup_codex 他
```

## 失敗時のシーケンス (network 不通で marketplace add が失敗)

```mermaid
sequenceDiagram
    participant Post as post.sh<br/>(set -e)
    participant SP as setup_plugins.sh
    participant CLI as claude CLI
    participant GH as github.com

    Post->>SP: source + setup_plugins
    SP->>CLI: plugins marketplace list
    CLI-->>SP: no claude-plugins-official

    SP->>CLI: plugins marketplace add anthropics/claude-plugins-official
    CLI->>GH: fetch (timeout / 503)
    GH-->>CLI: error
    CLI-->>SP: non-zero exit

    SP->>SP: warning to stderr
    SP-->>Post: return 0 (NOT non-zero)
    Post->>Post: continue with setup_codex 他<br/>(post.sh は止まらない)
```

`set -e` 配下では関数の非 0 戻り値もスクリプト全体を止める。`setup_plugins` は marketplace add の失敗を warning で報告した上で **必ず 0 を返す** ことで、post.sh 全体の継続性を保証する。
