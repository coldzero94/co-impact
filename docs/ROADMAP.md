# Roadmap

The one place for status. Update the row when a step starts or finishes, in the PR that does it.

| # | Step | Status |
|---|------|--------|
| 1 | Check Xcode / iOS SDK / Foundation Models availability | Done (2026-11-07) |
| 2 | Product and UX docs | Done; goals, daily log, and motion added 2026-11-09; open decisions pending |
| 3 | Create the SwiftUI project (app + `ImpactKit` package) and make CI `ios` green | Done (2026-11-08, PR #4) |
| 4 | Impact Engine data model + selection rules, with tests; add `swift test` to CI | Done (2026-11-08) |
| 5 | Home screen with mock calendar data and the Impact ring: two or three SwiftUI preview drafts, then pick one | Done (2026-11-09, PR #10) |
| 6 | Impact Card detail, actions, and the Impact moment | Done (2026-11-09, PR #11) |
| 7 | EventKit integration, with stored card state (done actions, Impacts, dismissals) | Done (2026-11-15, PRs #12–#16): calendar access, live Home, stored Impacts (a done card's primary action is restored from its Impact, other done actions are not stored), dismissals, the empty state's "Next:" line, and organizer, attendees, and notes in card detail |
| 8 | Foundation Models enrichment | Done (2026-11-18, PR #30): Suggested next steps in card detail; generation not yet seen, the model was not ready on this Mac, so checking it moves to step 10 (owner decision, 2026-11-18); D14 still Proposed |
| 9 | Live Activities, widgets, Siri / Shortcuts | Done (2026-11-17, PRs #20–#29; the owner moved it before step 8, 2026-11-15): skills installed (PR #20); Live Activity for the Now phase (PR #21); run links closed with a token (PR #22); Lock Screen widget (PR #23); Home Screen small and medium widgets (PR #24); Live Activity views for limited width, the Watch, and CarPlay (PR #25); App Shortcuts in English and Korean (PR #26); Next up control (PR #27); a card of tomorrow runs from its Now phase on every surface (PR #28); the fallback Now alert (PR #29); device checks are in ARCHITECTURE.md → To verify (step 10); design inputs: [research/system-surfaces.md](research/system-surfaces.md) |
| 10 | Background refresh, simulator and device testing | In progress (2026-11-18): background refresh (PR #33; the simulator runs no background tasks, so it is checked on a device). Background refresh and simulator checks first; the device checks run before release, after steps 11–14 (owner decision, 2026-11-18). Includes: the checks in ARCHITECTURE.md → To verify, among them Suggested steps generated from English and Korean notes; check whether synced notes carry HTML (card detail shows them as plain text); check Apple's geocoding with Korean addresses on a device, then geocode locations without coordinates (owner decision, 2026-11-15) and reword what promises the calendar never leaves the device (ARCHITECTURE.md → Privacy) |
| 11 | Goals: goal setup, goal-time rules in the engine (with tests), Block time | Done (2026-11-19, PRs #34–#36): goal-time rules in the engine (PR #34); goal setup (PR #35); the goal-time card with Block time, Undo, and Not now (PR #36). Not built, waiting for Settings (no step yet): pausing a goal, and picking a writable calendar when the default is not one. Built on the Proposed defaults of D17 (Goals) and D18 (Calendar writes), which stay Proposed until the owner settles them |
| 12 | Focus blocks: Start focus and its Live Activity | |
| 13 | Daily log and daily review | |
| 14 | Weekly summary with Foundation Models; Journaling Suggestions | |

The data model (step 4) comes before the UI (steps 5–6) because mock data and cards both depend on it.

Goals (11–13) follow the event-card MVP (5–10). Step 10's device checks wait until just before release and cover everything built by then (owner decision, 2026-11-18). The goal-time rules are pure engine logic and may start earlier, as tests. Step numbers stay fixed because AGENTS.md ties skill installs to them.

No release date: quality first, and the new year is a marketing moment only (PRODUCT.md D22).
