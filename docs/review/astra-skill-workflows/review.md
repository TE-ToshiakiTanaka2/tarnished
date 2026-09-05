# Claude Fable 5.1 Review: Astra skill workflows

- Repository: TE-ToshiakiTanaka2/tarnished
- Branch: refactor/astra-skill-workflows
- review_status: report-only
- reviewed_head: 7fc1aa8360c21acb8f548576d81f5eccbf2f52aa
- verified_head: e9c3d7154ead1e1e1571daaa9ea18d924c98f68f
- base_ref: develop (fetched as origin/develop)
- base_commit: fea0d0f5fbe6870900678ea236e53a3a92919565
- Issue / issue_body_sha256: not applicable; ad-hoc user request, no GitHub Issue
- Design: no issue-specific design; repository shared design and invariants supplied
- Requirements: migrate existing skills/agents to Astra, use high as default effort, improve workflows, create a branch and commit the changes
- Scope: committed diff only; 50 files, 399 insertions, 240 deletions; untracked runtime lock excluded
- Reviewed at: 2026-09-05 UTC
- Reviewer: Claude Code 2.1.261, explicit model claude-fable-5-1, fresh session, read tools only
- Model evidence: CLI modelUsage reports claude-fable-5-1 (20690 output tokens); CLI also reports auxiliary claude-haiku-4-5-20251001 usage (15 output tokens), not a replacement reviewer
- Effort: CLI default; not explicitly overridden or reported in result metadata
- Review duration: 292064 ms
- Result: success; 32 turns; no permission denials; no spawned subagents

This ad-hoc review is retained as report-only under the lifecycle completion contract because it has no Issue. Findings and fix verification below are usable independently; this status does not assert completion of an Issue lifecycle.

## Original reviewer output (verbatim)

## Review Summary

**Overall**: REQUEST_CHANGES

対象は `7fc1aa8`（base `fea0d0f`）の全コミット差分です。Issue および設計書は存在しないため、設計適合性はリポジトリの `docs/design/shared/*`、`AGENTS.md` の不変条件、`_shared/delegation` の契約に対して評価しました。

検証範囲: 差分中の全ミラー対（`.claude/*` ≡ `templates/claude/.claude/*`、`.agents` ≡ `templates/codex/.agents`、`.codex/config.toml` ≡ テンプレート、`.tarnished/workflows/*.md` ≡ `templates/agent-workflows/...`）は diff 上の blob ハッシュが両側で一致しており、`scripts/verify-mirrors.sh` は `diff -r` で新規 `references/` サブディレクトリも再帰的に比較するため、パリティ不変条件は保たれています。新規パス追加なし（`refresh.json` 変更不要、`.claude/skills` 配下の `references/completion.md` は既存の rsync 管理パスに含まれる）。

## Critical Issues

該当なし。

## Major Issues

- [docs/design/shared/api-spec.md:499, 511-512], [docs/design/shared/data-model.md:307-308, 344] `.codex/config.toml` の出荷値として `gpt-5.6-sol` / `ultra` が依然「現在値」として記述されており、本差分の `gpt-6-astra` / `high` と矛盾します。`executor.md` / `designer.md` は `docs/design/shared/*` を "cumulative project truth" として読む契約なので、下流の executor が古い値を真とみなします。加えて同ファイルは本差分で変更した契約も旧状態のままです: api-spec.md:442（`Fixes Applied` 見出しとコミット件名による `/flow` 入口判定）、:473-475（executor が `gh pr create` を実行）、:481-490（「導出不能なら必ず blocked-result」）、data-model.md:331（`roles.<role>.model` は Claude frontmatter へのフォールスルー専用）。ユーザー要件 2「ほかに変更が必要なものは」への直接の回答がこの層であり、未反映です。修正案: 最低限モデル/effort の行を `#312` 以降の履歴書式（"bumped from ... in #N"）で更新し、PR 作成者・blocked-result トリガ・`/flow` 入口判定・`roles.<role>.model` の Codex 解釈を新契約に合わせて書き換えてください。

## Minor Issues

- [.claude/skills/review/SKILL.md:74-75, 87] Phase 1 の bash スニペット削除により `${MERGE_BASE}` と `$TARGET_BRANCH` の定義元が消え、Phase 3A/3B が未定義変数を参照しています。Phase 1 手順 1 に「解決した値を `TARGET_BRANCH` / `MERGE_BASE` として記録する」と明示するか、3A/3B の参照を平文に置き換えてください。
- [.claude/agents/code-reviewer.md:31, 54] vs [.claude/skills/review/SKILL.md:189] 同じ subagent に対し、agent 定義は「空カテゴリも明示」、渡される Review Prompt Template は「空カテゴリは省略」と指示しており矛盾します（`.github/workflows/claude-code-review.yml:99` もテンプレート側に一致）。どちらかに揃えてください。
- [.claude/skills/_shared/branch/SKILL.md:107 vs 116-121] 散文では「分岐した base は暗黙にマージ/リセットせず、フェッチ済みリモート base から作成してローカル base を保全」と述べる一方、直後のコードブロックは `git checkout {base}` + `git pull --ff-only` のままで、分岐時は失敗し、かつ冒頭（:52）の「ユーザーのチェックアウトを動かさない」方針とも整合しません。`git fetch origin {base}` → `git checkout -b <name> origin/{base}`（または `git worktree add`）に置き換えると散文と一致します。
- [.claude/skills/flow/SKILL.md:67] Stage 2 手順 2 が「`_shared/branch/SKILL.md` を用いてブランチを解決」としていますが、その Issue モードは Step 6 でブランチが無ければ作成まで行います。入口判定に副作用が生じ、直下の表の行「Open issue, no issue branch → design」が手順 2 の後では観測不能になります。「Step 1〜5（検出）のみ、作成は `/design` に委ねる」と限定してください。
- [.claude/skills/flow/SKILL.md:69] vs [同 :169], [.agents/skills/flow/SKILL.md:21] Claude 側は「`--from` は同じ前提条件で評価し、未完了の検証を迂回しない」とだけ述べ、Error Handling 表と Codex 側は「前提不足なら報告して停止」と述べています。「早い段階に巻き戻す」のか「停止」なのかが読み手依存です。手順 4 に「前提不足時は報告して停止（`issue` を除く）」を再掲してください。
- [.codex/config.toml:8-9] `gpt-6-astra` / `high` の妥当性は本レビューでは検証できません。リポジトリ規約（api-spec.md:516、config.toml:6-7 のコメント、本差分で追加した review SKILL:82 の「最小ランタイムチェック」）に従い、`codex exec --strict-config` と実行確認の結果をコミット/PR 説明に記録してください。現状その証跡がありません。

## Suggestions

- [.claude/skills/_shared/delegation/SKILL.md:45], [.tarnished/agent-profile.json:8-9] `roles.<role>.model` が Claude 実行時は Claude モデル ID、Codex 実行時は Codex モデル ID と二重の意味を持つようになりました。`dual` プロファイルでは単一値がどちらか一方で必ず「未サポート」扱いになります。ベンダー別キー（例 `model_codex`）を設けるか、「値は primary agent のベンダー固有」と data-model.md に明記することを推奨します。
- [.claude/skills/review/references/completion.md:27] 再利用判定が `HEAD` を固定参照しています。`/flow` Stage 2 は「無関係な `HEAD` ではなく issue ブランチから証拠を読む」方針で、別 worktree にチェックアウト済みのケースを許容しているため、`HEAD` ではなく解決済みの issue ブランチ head を変数で受ける形にすると整合します。
- [.claude/skills/review/SKILL.md:101] メタデータヘッダに追加した evidence フィールドの具体的なキー並びの例が無く、`docs/review/#*/review.md` 既存 15 件はすべてレガシー形式です。ヘッダ例を 1 つ載せると新旧の判別が機械的にできます。

### 良い点

- 全ミラー対が同一コミットで一致しており、パリティ不変条件（AGENTS.md §7）を満たしています。
- `gh pr merge --match-head-commit`、`gh pr view --json headRefOid`、`git pull --ff-only`、`gh pr create --body-file`、`git check-ref-format --branch`、`git for-each-ref` はいずれも実在する正しい CLI 表面で、レース・シェル展開・誤マッチの実害を塞いでいます。
- `/review --codex` が `--codex` をターゲットブランチと誤解釈する既存バグを修正し、9 基準を小規模変更でも適用する変更は要件 3 に適切です。
- 状態ファイルを追加せず、レビュー成果物内の `verified_head` / `issue_body_sha256` で鮮度を判定する設計は、`/flow` の「証拠はリポジトリから導出」方針と整合しています。

### 検証上の制約

- シェル実行不可のため `scripts/verify-mirrors.sh` と `bats` は未実行です（ミラー一致は diff の blob ハッシュで確認）。
- Codex CLI へのアクセスが無く、`gpt-6-astra` / `high` の受理可否は未確認です。
- スキルは自然言語仕様のため、動作評価は記述の整合性と参照先の実在確認に限られます。自動テストが無いのは `execution.md` の「文言テストを追加しない」方針と一致しており、欠落とは扱っていません。

### 要件適合（ユーザー要件 1〜4）

1. astra 向け再構築: `.codex/config.toml`、Codex 実行リファレンス、モデルバインディングの Codex 解釈が追加されており対応済み。
2. 他に必要な変更: `docs/design/shared/*` の未更新が残っています（Major）。
3. ワークフロー改善: PR 再利用、head 固定マージ、worktree 保全、レビュー完了契約などが実装されており対応済み。
4. ブランチ作成とコミット: `refactor/astra-skill-workflows` に `7fc1aa8` として存在。Issue 無しのため `{label}/{assignee}/#N/{title}` 規約外ですが、ad-hoc 作業として妥当です。

## Orchestrator triage and fix verification

- Fix commit / verified_head: e9c3d7154ead1e1e1571daaa9ea18d924c98f68f
- Fix authoring: delegated to the executor; reviewed and committed by the orchestrator.
- Verification outcome: all accepted findings addressed. No Critical or Major finding deferred.
- Review return rounds: one authoring pass with targeted follow-up corrections before acceptance.
- The original Fable verdict above remains REQUEST_CHANGES for 7fc1aa8. The fixes were verified by the orchestrator; no second Fable review was run.
- Model identification reference: [Claude Fable 5.1 model specification](https://platform.claude.com/docs/en/models/fable-5-1/overview).

| Finding | Disposition | Change or evidence |
| --- | --- | --- |
| Major: stale shared design | Fixed | Updated current architecture, API, and data-model snapshots for Astra/high, review freshness, PR ownership, escalation, and dispatcher-specific inheritance. The explicitly historical #308 row retains its old values. |
| Minor: undefined review variables | Fixed | Bound target, fetched base, reviewed head, and merge base; aligned config reads, diff collection, and reviewer execution with the resolved issue worktree. |
| Minor: empty-category conflict | Fixed | Canonical prompt and CI now explicitly state empty categories, matching the agent and root contract. |
| Minor: diverged local base snippet | Fixed | Create from the freshly fetched remote base commit; use a separate worktree when preserving the caller requires it. |
| Minor: entry detection creates branches | Fixed | Flow detection only uses existing-branch discovery; selected authoring stages own creation. |
| Minor: explicit --from ambiguity | Fixed | Missing prerequisites stop the explicit entry without auto-repairing earlier stages; issue entry remains exempt. |
| Minor: runtime validation evidence | Verified | Strict-config Codex run resolved gpt-6-astra/high and returned OK, command and limitations below. |
| Suggestion: vendor-specific model override | Adopted | Documented actual-dispatcher model IDs and null inheritance for a shared dual profile; no schema expansion. |
| Suggestion: unrelated HEAD in reuse | Adopted | Compare resolved ISSUE_HEAD using git -C ISSUE_WORKTREE and inspect that worktree's state. |
| Suggestion: evidence-header example | Adopted | Added compact YAML example and explicit ad-hoc null/report-only representation. |

### Validation

- `bash scripts/verify-mirrors.sh`: all 21 mirror comparisons passed.
- `git diff --check` and staged diff check: passed.
- Codex flow/review `quick_validate.py`: passed via python3.
- Modified CI workflow YAML: parsed successfully.
- Temporary Git fixture with diverged local develop, independently advanced local-test origin, and uncommitted user work: the new issue worktree starts at the fetched remote commit while the local base SHA, checkout, and dirty status remain unchanged.
- Review comparison from an unrelated checkout: the issue-worktree comparison passes, while the old caller-HEAD comparison detects the unrelated tree difference, reproducing the reported risk.
- Original reviewer output preserved verbatim.
- No live GitHub PR creation or merge was performed; no full lifecycle integration run was performed.

Runtime smoke test (Codex CLI 0.153.4):

```text
codex exec --strict-config --ephemeral --sandbox read-only -c 'mcp_servers={}' 'Configuration smoke test only. Do not call tools, read files, or change anything. Reply exactly OK.'
model: gpt-6-astra
reasoning effort: high
response: OK
exit code: 0
```

The model and effort were taken from the active project configuration, without model/effort overrides. MCP servers were disabled for this isolated smoke test, so it does not validate MCP connectivity. The CLI reported using its bundled bubblewrap because bubblewrap was absent from PATH. The runtime lock file was not included in either commit.
