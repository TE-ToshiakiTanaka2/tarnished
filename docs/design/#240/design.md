# Design: #240 Internalize SuperClaude Front-Half Skills as erd: Commands

## Architecture Overview

SuperClaude (sc:) のワークフロー前半スキル5つを、Claude Code のコマンドシステムを利用して `.claude/commands/erd/` に内製化する。`/erd:brainstorm` のようにスラッシュコマンドとして呼び出せる独立コマンドとして設計する。

既存の `/issue`, `/design` スキルは `sc:` 参照を `erd:` に差し替えるのみで、ワークフロー構造は維持する。

## Module Structure

```
.claude/
├── commands/
│   └── erd/                     # NEW: 内製コマンド群
│       ├── brainstorm.md        # 要件発見コマンド
│       ├── estimate.md          # 開発見積もりコマンド
│       ├── research.md          # 外部調査コマンド
│       ├── design.md            # アーキテクチャ設計コマンド
│       └── workflow.md          # ワークフロー計画コマンド
└── skills/
    ├── issue/SKILL.md           # UPDATE: sc: → erd: 参照差し替え
    ├── design/SKILL.md          # UPDATE: sc: → erd: 参照差し替え
    ├── implement/SKILL.md       # NO CHANGE (Phase 2 scope)
    ├── pr/SKILL.md              # NO CHANGE (Phase 2 scope)
    └── review/SKILL.md          # NO CHANGE
```

## Command Design

### 共通設計原則

1. **SuperClaude からの本質抽出**: 各スキルの行動パターン・分析フレームワーク・出力形式を抽出
2. **不要な複雑さの除去**: ペルソナ切替、戦略/深度パラメータ、未使用MCPサーバー参照を除去
3. **利用可能MCPのみ参照**: sequential-thinking, context7, serena のみ
4. **明確な境界**: 各コマンドは出力のみ生成し、次フェーズの作業は行わない
5. **チェックリスト化**: ペルソナの多角的観点をチェックリストとして組み込み

### brainstorm.md

| 項目 | 内容 |
| --- | --- |
| **目的** | ソクラテス式対話による要件発見 |
| **入力** | トピック/アイデア（$ARGUMENTS） |
| **MCP** | sequential-thinking |
| **行動** | 構造化された質問で要件を深掘り |
| **出力** | 要件仕様（機能/非機能/受入基準/未解決質問） |
| **境界** | 要件発見のみ。設計・実装・アーキテクチャ決定はしない |

**観点チェックリスト**（ペルソナ代替）:
- 機能要件: 達成目標、受入基準
- 非機能要件: パフォーマンス、セキュリティ、保守性
- アーキテクチャ: 影響レイヤー
- ユーザー体験: UI/UX、アクセシビリティ
- データモデル: エンティティ、リレーション、マイグレーション

### estimate.md

| 項目 | 内容 |
| --- | --- |
| **目的** | 開発見積もり（Size/Priority/リスク） |
| **入力** | タスク/機能の説明（$ARGUMENTS） |
| **MCP** | なし（Read/Grep/Glob で直接分析） |
| **行動** | コードベース分析 + 判定基準に基づく評価 |
| **出力** | 見積もりレポート（Size/Priority/リスク/影響範囲） |
| **境界** | 見積もりのみ。タスク実行・スケジュール確定はしない |

**Size 判定基準**:
- XS: 設定変更のみ、1ファイル内の軽微修正
- S: 1-2ファイル、単一機能追加
- M: 3-5ファイル、複数モジュールにまたがる変更
- L: 複数コンポーネント、新規主要機能
- XL: アーキテクチャ変更、大規模リファクタリング

**Priority 判定基準**:
- High: バグ修正、セキュリティ関連、ブロッカー
- Medium: 通常の機能追加、改善
- Low: ドキュメント、リファクタリング、nice-to-have

### research.md

| 項目 | 内容 |
| --- | --- |
| **目的** | 外部ライブラリ/API/パターンの調査 |
| **入力** | 調査対象（$ARGUMENTS） |
| **MCP** | context7 |
| **ツール** | WebSearch, context7 (resolve-library-id, query-docs) |
| **行動** | エビデンスベースの情報収集と分析 |
| **出力** | 調査レポート（発見/分析/推奨/ソース引用） |
| **境界** | 調査レポートのみ。実装・アーキテクチャ決定はしない |

### design.md

| 項目 | 内容 |
| --- | --- |
| **目的** | アーキテクチャ設計・インターフェース定義 |
| **入力** | 対象システム/コンポーネント（$ARGUMENTS） |
| **MCP** | serena, sequential-thinking |
| **行動** | 既存構造分析 + 設計ドキュメント生成 |
| **出力** | アーキテクチャドキュメント（構造/API/データモデル/エラー処理） |
| **境界** | 設計のみ。実装コード生成はしない |

### workflow.md

| 項目 | 内容 |
| --- | --- |
| **目的** | 要件/設計からの実装ステップ分解 |
| **入力** | PRD/要件/設計ドキュメント（$ARGUMENTS） |
| **MCP** | sequential-thinking |
| **行動** | タスク分解、依存関係マッピング、実行順序定義 |
| **出力** | ワークフロー計画（実装ステップ/依存関係/テスト戦略） |
| **境界** | 計画のみ。コード実行・ファイル生成はしない |

## Data Flow

```
ユーザー入力
    │
    ▼
/erd:brainstorm ──→ 要件仕様
    │                   │
    ▼                   ▼
/erd:estimate ──→ 見積もりレポート
    │
    ▼
/erd:research ──→ 調査レポート（条件付き）
    │
    ▼
/erd:design ──→ アーキテクチャドキュメント
    │
    ▼
/erd:workflow ──→ 実装ステップ計画
```

各コマンドは独立して呼び出し可能だが、`/issue` や `/design` スキルからの呼び出しでは上記の順序で使用される。

## 既存スキル更新方針

`/issue` と `/design` スキルの更新は以下の文字列置換のみ:

| 変更対象 | Before | After |
| --- | --- | --- |
| コマンド参照 | `/sc:brainstorm` | `/erd:brainstorm` |
| コマンド参照 | `/sc:estimate` | `/erd:estimate` |
| コマンド参照 | `/sc:research` | `/erd:research` |
| コマンド参照 | `/sc:design` | `/erd:design` |
| コマンド参照 | `/sc:workflow` | `/erd:workflow` |
| セクション名 | `SuperClaude Skills Used` | `erd Skills Used` |
| セクション名 | `Leveraging sc:*` | `Leveraging erd:*` |
| description | `SuperClaude skills (sc:*)` | `erd commands (erd:*)` |

## Implementation Notes

- Claude Code の commands ディレクトリは、サブディレクトリ名がコマンドのプレフィックスになる仕組み
  - `.claude/commands/erd/brainstorm.md` → `/erd:brainstorm` で呼び出し可能
- 既存の SuperClaude (`/sc:*`) は並行して利用可能。内製スキルへの完全移行は段階的に行える
- 将来の Phase 2（implement, build, test 等）でも同じパターンで内製化可能
