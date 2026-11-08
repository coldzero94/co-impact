# Roadmap

The one place for status. Update the row when a step starts or finishes, in the PR that does it.

| # | Step | Status | Skills to add at start |
|---|------|--------|------------------------|
| 1 | Check Xcode / iOS SDK / Foundation Models availability | Done (2026-11-07) | |
| 2 | Product and UX docs | Done, open decisions pending | |
| 3 | Create the SwiftUI project (app + `ImpactKit` package) and make CI `ios` green | Done (2026-11-08, PR #4) | |
| 4 | Impact Engine data model + selection rules, with tests; add `swift test` to CI | Next | |
| 5 | Home screen with mock calendar data | | |
| 6 | Impact Card detail and actions | | |
| 7 | EventKit integration | | `eventkit` |
| 8 | Foundation Models enrichment | | `apple-on-device-ai` |
| 9 | Live Activities, widgets, Siri / Shortcuts | | `activitykit`, `widgetkit`, `app-intents` |
| 10 | Background refresh, simulator and device testing | | `background-processing` |

The data model (step 4) comes before the UI (steps 5–6) because mock data and cards both depend on it.
