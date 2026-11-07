---
name: merge-gate
description: Pre-merge review gate for this repo. Runs /ponytail-review and /pr-review-toolkit:review-pr on a PR, fixes blocking findings, records the results on the PR, and posts the review statuses that the main branch ruleset requires. Use before merging any PR that is not docs-only, or when asked to "merge", "run the gate", or "review before merge".
---

# Merge gate

`main` only accepts a PR when these checks pass (AGENTS.md → Merge policy):

| Check | Set by |
|-------|--------|
| `changes`, `ios` | CI (`.github/workflows/ci.yml`) |
| `review/ponytail` | This skill, after `/ponytail-review` |
| `review/pr-review-toolkit` | This skill, after `/pr-review-toolkit:review-pr` |

Docs-only PRs get both review statuses from CI automatically. Do not run this skill for them.

Run this in Claude Code: pr-review-toolkit is a Claude Code plugin.

## Steps

1. **Find the PR.** `gh pr view --json number,headRefOid,files,url`. No PR: stop and ask to open one. Check out the PR branch and make sure it is pushed and clean.
2. **Run both reviews on the PR's diff against `main`:**
   - `/ponytail-review` on the PR branch.
   - `/pr-review-toolkit:review-pr` (all applicable aspects).
3. **Blocking findings:** ponytail **Must fix**, and pr-review-toolkit **Critical** or **Important**.
   - Fix each one, or decide it is not valid and write down why (a concrete reason, not "minor").
   - Commit and push the fixes. If a fix changed logic, re-run the review that found it on the new head.
   - Non-blocking findings (Should fix, Nice to have, Suggestions) go into the PR comment; fix them only if the user asks.
4. **Record on the PR** with one `gh pr comment`: both verdicts, each blocking finding with its fix commit or the reason it was declined, and the head SHA that was reviewed.
5. **Post statuses on the reviewed head SHA** (`gh pr view --json headRefOid -q .headRefOid`):
   ```sh
   gh api repos/{owner}/{repo}/statuses/$SHA -f state=success -f context=review/ponytail -f description="ponytail-review: Ship"
   gh api repos/{owner}/{repo}/statuses/$SHA -f state=success -f context=review/pr-review-toolkit -f description="No open critical/important issues"
   ```
   If a blocking finding remains, post `state=failure` with a short description instead, and stop.
6. **Merge** when every required check is green: `gh pr merge --squash --delete-branch`. Ask the user before merging unless they already asked for the merge.

## Rules

- Never post `success` for a SHA you did not review in this session. A new push changes the head SHA, so the old statuses no longer count; run the gate again.
- Never merge with `--admin` or otherwise bypass the ruleset.
- Never post statuses for another repository or PR than the one reviewed.
