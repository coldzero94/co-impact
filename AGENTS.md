# AGENTS.md

Context for coding agents (Codex, Claude Code, others) working in this repo. Read this first, then the docs it points to.

## What this is

**Impact** is a native iOS app that reads the user's calendar, picks out the events that actually need preparation, and turns each one into an **Impact Card**: a small package of verified facts and one-tap actions (join the meeting, get directions, ...). The user does not write plans or chat with an AI. The app does the triage; the user just acts.

Status: **pre-code**. No Xcode project yet. See [Roadmap](#roadmap).

## Docs map

| File | Owns |
|------|------|
| [docs/PRODUCT.md](docs/PRODUCT.md) | Vision, principles, MVP scope, action catalog, open product decisions |
| [docs/UX.md](docs/UX.md) | Screens, card anatomy, states, system surfaces (widgets, Live Activities, Siri) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, data model, Impact Engine pipeline, platform constraints, verified SDK facts |
| [docs/research/](docs/research/) | Evidence behind decisions (e.g. award-winning app study → design principles P1–P8) |

When a decision changes, update the doc that owns it in the same change. Decisions marked **Proposed** are not final; do not treat them as settled without the owner's confirmation.

## Hard rules

1. **No backend, no cloud DB.** Everything runs and is stored on device. Anything that needs a server (e.g. ActivityKit push-to-start) is out of scope until a doc says otherwise.
2. **Confirmed vs. inferred.** Every fact and action shown to the user carries its provenance: read from the calendar, computed (e.g. travel time), or inferred (rules or Foundation Models). The UI must never present an inference as a calendar fact.
3. **Closed action catalog.** Actions come only from the catalog in PRODUCT.md. Models choose from it; they never invent free-form actions.
4. **Fewer cards beats more cards.** If unsure whether an event needs prep, do not create a card.
5. **Works without Apple Intelligence.** The rule-based engine is the core. Foundation Models only enriches it, behind an availability check.
6. **Don't fake platform capabilities.** Before relying on an API or behavior, verify it against Apple documentation or the SDK itself, e.g.:
   ```sh
   SDK=$(xcrun --sdk iphoneos --show-sdk-path)
   grep -n "func request" "$SDK/System/Library/Frameworks/ActivityKit.framework/Modules/ActivityKit.swiftmodule/arm64e-apple-ios.swiftinterface"
   ```
   Record what you verified in ARCHITECTURE.md → *Platform facts*. If something is not possible, say so and propose an alternative.
7. **Public repo.** Never commit secrets, OAuth client IDs/secrets, tokens, or personal calendar data. Use synthetic fixtures for tests and previews.
8. **Corporate calendars.** Read only what the OS grants. Never work around MDM, Exchange, or account access restrictions.

## Conventions

- Swift 6 language mode, strict concurrency. SwiftUI only (UIKit only where SwiftUI has no API).
- Tests: Swift Testing (`@Test`, `#expect`). The Impact Engine must be testable without UI or EventKit.
- Code, comments, commit messages, and docs in English.
- Minimum change that fully solves the task (see ponytail below). No speculative abstractions.

## Environment

- Xcode 27.0 (27A266a), iOS 27.0 SDK (verified 2026-11-07).
- CI: GitHub Actions `xcode-27` runner label (public preview, announced in actions/runner-images#14404, checked 2026-11-07; not yet exercised because there is no Xcode project). Its Xcode build may differ from the local one; the `ios` job logs `xcodebuild -version`. The GA `macos-26` image tops out at Xcode 26.6.
- Build and test: `xcodebuild test -project Impact.xcodeproj -scheme Impact -destination 'platform=iOS Simulator,name=<iPhone>'`. Step 3 must create exactly this project and scheme, with `ImpactKit` tests in the `Impact` scheme's test plan, so CI runs them. CI hard-codes the project and scheme names in `.github/workflows/ci.yml`; change both together.

## Agent tooling

Plugins (Claude Code, declared in `.claude/settings.json`; Claude Code offers to install them when you trust the project folder):

| Plugin | Use |
|--------|-----|
| `ponytail@ponytail` | Always-on "smallest complete change" mode. `/ponytail lite|full|ultra`, `/ponytail-review`. |
| `pr-review-toolkit@claude-plugins-official` | `/pr-review-toolkit:review-pr` before opening or merging a PR. |

Codex: install ponytail once per machine with `codex plugin marketplace add DietrichGebert/ponytail && codex plugin add ponytail@ponytail`, then trust its hooks in `/hooks`.

Skills (project scope, pinned in `skills-lock.json`, shared by Claude Code via `.claude/skills` and Codex via `.agents/skills`):

| Skill | Source | Use |
|-------|--------|-----|
| `swiftui-pro` | twostraws/swiftui-agent-skill | Writing and reviewing SwiftUI |
| `swift-concurrency` | avdlee/swift-concurrency-agent-skill | Swift 6 concurrency, actors, Sendable |
| `swift-testing` | dpearson2699/swift-ios-skills | Engine tests |
| `apple-hig` | nexu-io/open-design | Design decisions against Apple HIG |

Upstream skill files are git-ignored (some upstream licenses are not open source); project-owned skills such as `merge-gate` (`.claude/skills/merge-gate/`, Claude Code) are committed. Restore upstream skills after cloning:

```sh
npx skills experimental_install
```

Add a skill only when its roadmap step starts, not ahead of time. Planned additions are listed in the roadmap.

## Merge policy

`main` is protected by a GitHub ruleset ("main merge gate", no bypass actors): no direct or force pushes, no deletion, changes land through a PR, and these checks must pass:

| Check | What it means | Set by |
|-------|---------------|--------|
| `changes` | Lists the PR's changed files (old and new paths) and decides whether app code changed | CI workflow (pinned to GitHub Actions) |
| `ios` | Build and tests on the iOS Simulator; skipped when no app code changed | CI workflow, `xcode-27` runner (pinned to GitHub Actions) |
| `review/ponytail` | `/ponytail-review` found no open **Must fix** on this commit | `merge-gate` skill; `Review exemption` workflow for docs-only PRs |
| `review/pr-review-toolkit` | `/pr-review-toolkit:review-pr` found no open **Critical/Important** on this commit | Same as above |

- **Docs-only PRs** change only `docs/**` and `README.md`. The `Review exemption` workflow posts both review statuses for them, so no `merge-gate` run is needed. It runs from `main`'s copy (`pull_request_target`), so a PR cannot widen its own exemption.
- `AGENTS.md` and `CLAUDE.md` are agent rules, not docs: changing them needs the gate.
- **App code** is everything except Markdown files, `.github/`, `.claude/`, `.agents/`, `skills-lock.json`, and `.gitignore`.
- **Every other PR:** run the `merge-gate` skill in Claude Code. Order: `/ponytail-review` first (shape: what should not exist), then `/pr-review-toolkit:review-pr` (detail), then a review of any fix commits, then a `Merge verdict:` comment on the PR, then the statuses.
- Statuses belong to one commit. Pushing again means running the gate again.
- CI and the exemption run only for PRs into `main`. A PR retargeted to `main` gets no `changes`/`ios` run until its next push; close and reopen it to trigger one.
- The review statuses are self-reported: the reviews run in a local Claude Code session, not in CI, and the ruleset accepts the `review/*` contexts from anyone with write access. The verdict comment is the audit trail.
- Never bypass the ruleset (`gh pr merge --admin`, or editing the ruleset to get a PR through).

## Roadmap

| # | Step | Status | Skills to add at start |
|---|------|--------|------------------------|
| 1 | Check Xcode / iOS SDK / Foundation Models availability | Done (2026-11-07) | |
| 2 | Product and UX docs | Done, open decisions pending | |
| 3 | Create SwiftUI project (app + `ImpactKit` package); make CI `ios` green; stop excluding `.github/workflows/ci.yml` from app code in CI's `changes` job | Next | |
| 4 | Impact Engine data model + rules, with tests | | |
| 5 | Home screen with mock calendar data | | |
| 6 | Impact Card detail and actions | | |
| 7 | EventKit integration | | `eventkit` |
| 8 | Foundation Models enrichment | | `apple-on-device-ai` |
| 9 | Live Activities, widgets, Siri / Shortcuts | | `activitykit`, `widgetkit`, `app-intents` |
| 10 | Background refresh, simulator and device testing | | `background-processing` |

The data model (step 4) comes before the UI (steps 5–6) because mock data and cards both depend on it.
