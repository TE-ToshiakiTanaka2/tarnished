# Codex lifecycle execution

Read this reference for any Tarnished lifecycle skill. It adapts the shared procedures to Codex; artifact destinations, review criteria, and stage ownership remain defined by the shared workflows.

## Scope and continuity

Apply system and developer instructions first, then the user's request and existing authorization, then repository and skill guidance. A procedural example does not create an approval gate. Complete authorized preparation before asking about a remaining action. Merge requires `--merge` or an explicit merge request; an end-to-end flow does not imply deployment or unrelated messages.

Use conversation and repository evidence before asking for inputs. Make routine reversible implementation choices within the accepted requirements and record consequential assumptions. Ask for decisions that change scope, public behavior, or authority; continue independent work while an answer is pending. A status question or correction steers the active task. On resumption, inspect existing artifacts and preserve completed stages.

If an instruction leaves work blocked, link and quote its exact source and state what decision or capability is missing. Missing optional MCP tools use built-in search and file reads. Missing required inputs follow the stage's prerequisite contract.

## Tools and roles

Translate Claude tool names to available Codex capabilities: Read/Glob/Grep to file reads and `rg`, Edit/Write to patch tools, Bash to shell execution, and Agent to collaboration tools. For erd instructions, read `.tarnished/workflows/erd.local/<command>.md` when present, otherwise `.tarnished/workflows/erd/<command>.md`, instead of trying to execute Claude slash commands. Load references for the active stage only.

Resolve role overrides from `.tarnished/agent-profile.json` using the shared delegation contract. For Codex-native `designer` and `executor` tasks, inherit the active Codex model and reasoning effort unless a supported explicit override is configured. Claude frontmatter model IDs apply only to Claude dispatch. Never silently substitute an unsupported configured model. The external reviewer uses its own CLI configuration; record actual runtime settings when available, and label unverified settings as configured rather than resolved.

When delegation is available and permitted, give the stage author its issue requirements, relevant artifacts, accepted user decisions, base branch, owned paths, allowed writes/commits, and completion criteria. Use the role responsibilities in `.claude/agents/{designer,executor,code-reviewer}.md` when present, translating their tools as above. Keep one author per stage; parallel work needs disjoint ownership. The orchestrator can inspect requirements and prepare validation while the author works, then review the returned changes before advancing. A subagent receives only the authority already granted to its parent.

Independent review uses a fresh context with raw requirements, design, and diff, without the author's reasoning or preferred verdict. If no independent reviewer can run, label inline review as self-review and disclose the missing independence. If delegation is unavailable or prohibited, perform the stage inline and report the limitation; do not infer capability from the agent family.

## Verification and handoff

Choose checks from the changed behavior and repository requirements. Reuse successful checks for unchanged code, and rerun affected checks after fixes. Do not add tests that only assert prompt wording or repeat broad suites without a new failure, change, or unresolved risk. Template edits require mirror verification; executable changes need relevant behavioral checks. Report skipped or unavailable required checks explicitly.

Keep the user's language and lead with the outcome. Report artifacts, actual verification, and material limitations. Retain mandated review output and saved metadata without repeating the entire workflow in chat.
