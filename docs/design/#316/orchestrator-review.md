# Orchestrator design review: #316

- Repository: TE-ToshiakiTanaka2/tarnished
- Base: develop (c78bb7a)
- Author: delegated Codex-native designer, inherited session model/settings
- Reviewer: primary orchestrator, against the GitHub issue Requirements and accepted user clarification
- Verdict: APPROVE

FR-1–8 are represented in the design and behavioral matrix. The personas/ontology separate developer software and settings from centrally maintained AI assets. Runtime and manifest inventories are disjoint, first adoption is conservative, and conflicts retain installed rather than desired baselines. No vendor model changes are assumed.

One draft-feedback round clarified two material migration details before commit:

1. Full source-directory disappearance may remove only proven unchanged upstream-origin files when the resolved valid upstream tree proves removal for an unchanged mapping. An unavailable source or changed mapping provides no deletion authority.
2. A safe one-shot refresh must also migrate a known unedited legacy container-start updater using shipped-content evidence. Unknown or edited installed updaters are preserved with explicit migration instructions; a legacy manifest hash alone is not evidence.

Both clarifications were re-read in the returned design. No Critical or Major findings remain. There were no user escalations after the requirements dialogue. Shared snapshots were updated without editing historical issue documents. External research and shared-layer bootstrap were unnecessary.

Validation of artifacts: git diff --check passed. Pre-change verification: affected Bats baseline 100/102 passed (existing refresh change/removal failures), ShellCheck error-level checks passed, and all workspace/template mirrors matched. Implementation must satisfy the new behavioral matrix rather than retain unsafe legacy test expectations.
