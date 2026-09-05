# Review completion and reuse

Use this contract when saving a review, selecting a `/flow` entry stage, or checking `/pr` readiness. Keep the evidence in the existing review artifact; do not add a separate workflow state file.

## Evidence to record

Alongside reviewer identity, findings, and their dispositions, record:

| Field | Meaning |
| --- | --- |
| `review_status` | `pending`, `report-only`, or `complete` |
| `reviewed_head` | Full commit SHA whose diff the independent reviewer received |
| `verified_head` | Full commit SHA after the orchestrator verified any fixes; same as `reviewed_head` when no fixes were needed |
| `base_ref` / `base_commit` | Target branch and its freshly fetched full commit SHA |
| `issue_body_sha256` | SHA-256 of the issue body supplied to the reviewer, encoded as UTF-8 without an added newline |

Compute the issue digest from the decoded `body` field of a successful `gh issue view <n> --json body` response. Hash the same representation when checking reuse. Record the issue number and repository so another issue's artifact cannot satisfy the contract. If issue retrieval fails, report the missing requirement check; do not hash an error or claim completion. An ad-hoc review without an issue may report findings, but is not lifecycle completion evidence.

`review_status: complete` means every applicable review criterion was assessed, Critical findings are fixed, Major findings are fixed or explicitly deferred with rationale, and any fixes were verified. A review with no required fixes can complete without editing source or inventing a fix commit. Keep a `Fixes Applied` section for compatibility, writing `None required` when appropriate. Report-only requests with unresolved required fixes or missing review inputs remain `report-only`; do not apply fixes without authorization.

A compact metadata header can use the following shape (replace placeholders with full SHAs and the actual digest):

```yaml
repository: owner/repo
issue_number: <number>
review_status: complete
reviewed_head: <full-review-input-sha>
verified_head: <full-verified-sha>
base_ref: develop
base_commit: <full-fetched-target-sha>
issue_body_sha256: <sha256-of-decoded-body>
```

Add the reviewer, timestamp, scope, and merge base required by the review skill. For an ad-hoc review, use `issue_number: null`, `issue_body_sha256: null`, and `review_status: report-only`; these do not establish lifecycle readiness.

Save the original reviewer output verbatim. Record the orchestrator's verification separately; never rewrite the original verdict as if the reviewer issued a new one. An explicit built-in review that omits issue/design checks cannot by itself establish completion; supplement those checks or report the limitation.

## Reuse decision

Before trusting a completed artifact, resolve `ISSUE_WORKTREE` to the issue's worktree (using the shared branch safeguards) and `ISSUE_HEAD` to that issue branch's full commit SHA. Run the following Git checks there; an unrelated current checkout is not evidence for the issue:

1. Confirm repository, issue number, target branch, and the fetched target commit match. Re-fetch the issue and compare its body digest.
2. Confirm `verified_head` exists and is an ancestor of `ISSUE_HEAD` with `git -C "$ISSUE_WORKTREE" merge-base --is-ancestor "$VERIFIED_HEAD" "$ISSUE_HEAD"`. Compare trees with `git -C "$ISSUE_WORKTREE" diff --quiet "$VERIFIED_HEAD" "$ISSUE_HEAD" -- . ':(exclude)docs/review/**'`. Any difference requires review of the changed scope; a commit of only the review artifact does not invalidate its own evidence.
3. Inspect the index and working tree at `ISSUE_WORKTREE` using `git -C "$ISSUE_WORKTREE" status --short`. Uncommitted changes to the work being reviewed are not covered by a committed-head review. Finish and verify authorized changes first, or report their exclusion without claiming readiness. Preserve unrelated user changes.
4. Check the recorded status and finding dispositions. The presence of a filename, heading, or old approval alone is insufficient. Missing fields in legacy artifacts mean freshness is unknown; refresh the review once and record the evidence.

If only fixes for existing findings changed, verify those fixes and rerun affected checks, then advance `verified_head`. Other implementation or design changes require a review of the changed scope before updating completion evidence. A changed target or issue body requires reassessing the diff or requirements as applicable. Reuse unaffected findings; a full unrelated review is unnecessary.

An unavailable ref, failed command, or unreadable input means reuse could not be established. Do not treat it as an empty diff or a completed stage.
