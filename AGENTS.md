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
- Build and test commands: TBD when the Xcode project is created (roadmap step 3).

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

Skill files are git-ignored (some upstream licenses are not open source). Restore them after cloning:

```sh
npx skills experimental_install
```

Add a skill only when its roadmap step starts, not ahead of time. Planned additions are listed in the roadmap.

## Roadmap

| # | Step | Status | Skills to add at start |
|---|------|--------|------------------------|
| 1 | Check Xcode / iOS SDK / Foundation Models availability | Done (2026-11-07) | |
| 2 | Product and UX docs | Done, open decisions pending | |
| 3 | Create SwiftUI project (app + `ImpactKit` package) | Next | |
| 4 | Impact Engine data model + rules, with tests | | |
| 5 | Home screen with mock calendar data | | |
| 6 | Impact Card detail and actions | | |
| 7 | EventKit integration | | `eventkit` |
| 8 | Foundation Models enrichment | | `apple-on-device-ai` |
| 9 | Live Activities, widgets, Siri / Shortcuts | | `activitykit`, `widgetkit`, `app-intents` |
| 10 | Background refresh, simulator and device testing | | `background-processing` |

The data model (step 4) comes before the UI (steps 5–6) because mock data and cards both depend on it.
