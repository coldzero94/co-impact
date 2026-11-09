# Roadmap

The one place for status. Update the row when a step starts or finishes, in the PR that does it.

| # | Step | Status |
|---|------|--------|
| 1 | Check Xcode / iOS SDK / Foundation Models availability | Done (2026-11-07) |
| 2 | Product and UX docs | Done; goals, daily log, and motion added 2026-11-09; open decisions pending |
| 3 | Create the SwiftUI project (app + `ImpactKit` package) and make CI `ios` green | Done (2026-11-08, PR #4) |
| 4 | Impact Engine data model + selection rules, with tests; add `swift test` to CI | Done (2026-11-08) |
| 5 | Home screen with mock calendar data and the Impact ring: two or three SwiftUI preview drafts, then pick one | Done (2026-11-09, PR #10) |
| 6 | Impact Card detail, actions, and the Impact moment | |
| 7 | EventKit integration | |
| 8 | Foundation Models enrichment | |
| 9 | Live Activities, widgets, Siri / Shortcuts | |
| 10 | Background refresh, simulator and device testing | |
| 11 | Goals: goal setup, goal-time rules in the engine (with tests), Block time | |
| 12 | Focus blocks: Start focus and its Live Activity | |
| 13 | Daily log and daily review | |
| 14 | Weekly summary with Foundation Models; Journaling Suggestions | |

The data model (step 4) comes before the UI (steps 5–6) because mock data and cards both depend on it.

Goals (11–13) follow the event-card MVP (5–10) so the core loop is tested on device first. The goal-time rules are pure engine logic and may start earlier, as tests. Step numbers stay fixed because AGENTS.md ties skill installs to them.

No release date: quality first, and the new year is a marketing moment only (PRODUCT.md D22).
