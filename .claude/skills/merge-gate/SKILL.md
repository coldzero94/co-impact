---
name: merge-gate
description: Pre-merge review gate for this repo. Runs /ponytail-review, then /pr-review-toolkit:review-pr on a PR's full diff, judges whether the PR is mergeable, records the verdict on the PR, and posts the review statuses the main branch ruleset requires. Use before merging any PR that changes more than docs/** and README.md, or when asked to "run the gate" or "review before merge".
---

# Merge gate

Required checks and the docs-only exemption: AGENTS.md → Merge policy. Docs-only PRs (`docs/**` and `README.md` only) get both review statuses from the `Review exemption` workflow: skip to step 9.

Run this in Claude Code; both review commands are Claude Code plugins. If a review command is unavailable, errors, or ends without its own verdict (ponytail: a `Verdict:` or `Looks good. Ship.` line; pr-review-toolkit: Critical/Important counts), post nothing and stop. Never substitute your own review for either command.

## Steps

1. **PR and scope.** `gh pr view <number|url> --json number,headRefOid,url,files`, then `gh pr checkout <number>` and `git fetch origin main`. The working tree must be clean and `git rev-parse HEAD` must equal `headRefOid`. The review scope is `origin/main...HEAD`. Pass it explicitly to both commands: they default to uncommitted changes.
2. **ponytail first.** `/ponytail-review` on `origin/main...HEAD`. It settles the shape of the change (what should not exist), so it runs before the detailed review.
3. **Resolve ponytail's Must fix** findings (see below). Commit and push fixes.
4. **pr-review-toolkit second.** `/pr-review-toolkit:review-pr` on `origin/main...HEAD` with the applicable agents: code-reviewer always; comment-analyzer, silent-failure-hunter, pr-test-analyzer, type-design-analyzer when relevant. Skip code-simplifier: ponytail already covers simplification, and the two pull in different directions. Drop findings about code that step 3 deleted.
5. **Resolve Critical and Important** findings. Commit and push fixes.
6. **Re-review the fixes** if step 3 or 5 pushed commits: run both reviews again, ponytail first, scoped to `<last reviewed SHA>..HEAD`. Repeat until a round has no blocking findings and pushes nothing. The reviewed SHA is then `HEAD`.
7. **Verdict.** Mergeable only if no blocking finding is open. Write one `gh pr comment` starting with `Merge verdict: Mergeable` or `Merge verdict: Not mergeable`, then: the reviewed SHA, each review's verdict, each blocking finding with its fix commit or decline evidence, non-blocking findings left open, and ponytail's `Not checked:` line. Keep the comment URL that `gh pr comment` prints.
8. **Statuses** on the reviewed SHA, in one Bash call (shell variables do not persist between calls):
   ```sh
   SHA=<reviewed SHA>; N=<PR number>; URL=<verdict comment URL>
   [ "$(gh pr view "$N" --json headRefOid -q .headRefOid)" = "$SHA" ] || { echo "PR head moved: run the gate again"; exit 1; }
   gh api "repos/{owner}/{repo}/statuses/$SHA" -f state=success -f context=review/ponytail -f description="<ponytail verdict line>" -f target_url="$URL"
   gh api "repos/{owner}/{repo}/statuses/$SHA" -f state=success -f context=review/pr-review-toolkit -f description="Critical/Important open: 0" -f target_url="$URL"
   ```
   Not mergeable: post `state=failure` with the reason instead, and stop.
9. **Merge** when every required check is green: `gh pr merge <N> --squash --delete-branch`. Ask the user first unless they already asked for the merge.

## Resolving findings

- Blocking: ponytail **Must fix**; pr-review-toolkit **Critical** and **Important**.
- Each is fixed, or declined with evidence that it is factually wrong (a command, test, or citation, shown in the verdict comment).
- A disagreement about trade-offs or policy is not a decline: ask the user, and keep the PR at `failure` until they decide.
- Non-blocking findings go into the verdict comment. Fix them when cheap or when the user asks.

## Rules

- `success` only on the SHA the last review round ran on, and only while the PR head still equals it.
- Never merge with `--admin` or otherwise bypass the ruleset. Never post statuses on another PR or repository.
