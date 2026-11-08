# CI and merge policy

Rules for `.github/` and for how changes reach `main`. The review-and-merge procedure itself: [merge-gate skill](../.claude/skills/merge-gate/SKILL.md).

## CI

- `workflows/ci.yml` runs only for PRs into `main`. `changes` lists the PR's files (old and new paths) and decides whether app code changed; `ios` then runs `swift test` on macOS, checks that every `ImpactKit` test target is in the scheme (ImpactKit/AGENTS.md → Tests), and builds and tests on the iOS Simulator.
- Runner: the `xcode-27` label (public preview, actions/runner-images#14404; first green on PR #4 with Xcode 27.1, 27A9275). The GA `macos-26` image tops out at Xcode 26.6 (as of 2026-11-07).
- The changed-file listing is shared by `ci.yml`, `review-exemption.yml`, and the merge-gate skill; change all three together.
- CI hard-codes the project and scheme names. Renaming either, update every hit in the same PR: project `git grep -n '<old>\.xcodeproj'`; scheme `git grep -n -e '<old>\.xcscheme' -e '-scheme <old>'`. Not a bare `git grep <old>`: the name is also the app target, folder, and brand.

## Merge policy

`main` is protected by a GitHub ruleset ("main merge gate", no bypass actors): no direct or force pushes, no deletion, changes land through a PR, and these checks must pass:

| Check | What it means | Set by |
|-------|---------------|--------|
| `changes` | Lists the PR's changed files and decides whether app code changed | CI workflow |
| `ios` | Build and tests on the iOS Simulator; skipped when no app code changed | CI workflow, `xcode-27` runner |
| `review/ponytail` | `/ponytail:ponytail-review` found no open **Must fix** on this commit | `merge-gate` skill; `Review exemption` workflow for docs-only PRs |
| `review/pr-review-toolkit` | `/pr-review-toolkit:review-pr` found no open blocking finding on this commit (Critical/Important; see `merge-gate` for the mapping) | Same as above |

- **Docs-only PRs** change only `docs/**` and `README.md`, with printable-ASCII file names (no non-ASCII or control characters; newlines are escaped to `\n` first) and no agent instruction file (`AGENTS.md`, `AGENTS.override.md`, `CLAUDE.md`, `CLAUDE.local.md`, and anything named or under `.claude` or `.agents`, whether a directory, symlink, or submodule) at any depth or letter case, because those load as agent rules. The `Review exemption` workflow posts both review statuses for them; no `merge-gate` run is needed. It runs from `main`'s copy (`pull_request_target`), so a PR cannot widen its own exemption.
- **Every other PR** (app code, CI, tooling, agent instruction files, any other Markdown): the `merge-gate` skill reviews it and, when it passes, merges it on its own. **No user approval is needed and the gate never waits for one.** A PR it finds not mergeable, or an untrusted PR with sensitive paths, gets a `failure` status with the reason; a passing PR that could not be merged gets a comment; any other stop posts nothing on GitHub. Every stop is reported in the session.
- **Trusted PRs** are branches in this repo, opened by the owner, with fewer than 100 commits, only the owner's commits, and no `Built on` in the body (the skill checks this with one command). Any session that never checked out or fetched an untrusted PR may gate a trusted PR, including the session that wrote it; no session builds or runs an untrusted PR's code. An untrusted PR needs a new session started on an up-to-date `main`, and if it touches sensitive paths (agent instruction files, `.github/`, `skills-lock.json`, non-ASCII paths, or 300+ files), the gate never merges it: the owner reviews it, posts the statuses (any description except the gate's `Must fix open: 0` / `Blocking open: 0`, e.g. `Owner reviewed`), and merges it, or closes it.
- **App code** (decides whether `ios` runs) is everything except `docs/`, root-level Markdown, `.github/` (but `.github/workflows/ci.yml` counts), `.claude/`, `.agents/`, `skills-lock.json`, and `.gitignore`.
- Statuses belong to one commit; pushing again means running the gate again. A PR retargeted to `main` gets no `changes`/`ios` run until its next push; close and reopen it to trigger one.

## Trust model

`changes` and `ios` are pinned to the GitHub Actions app, but a PR's own copy of `ci.yml` reports them, and a PR's own workflow could report `review/*` as check runs. So `.github/` changes always need the gate and are owner-only for untrusted PRs, a fork PR's own workflow code (`pull_request` runs) runs only after the owner approves it (the exemption's `pull_request_target` run always runs, but it uses main's code), and `merge-gate` confirms before merging that every `review/*` result is a status created by the owner (or by `github-actions[bot]` only on a docs-only PR, since any workflow can post as that bot).

The review statuses are self-reported by the agent, and the gate merges without human approval. The owner acts only on untrusted PRs: approving a fork's workflow run so `changes` and `ios` can report, and reviewing and posting the statuses when it has sensitive paths. Outside content inside an owner's PR is flagged only through the commit-author check and the `Built on` marker (AGENTS.md hard rule 9). Commit authors are matched by email, which any author can set, so that check catches only honest outside commits; the marker is written by the authoring agent and cannot be verified. The verdict comment is the audit trail.
