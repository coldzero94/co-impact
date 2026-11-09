# Architecture

The project structure, engine selection model, and Home snapshot below are implemented (roadmap steps 3–4 and the engine part of step 5). The remaining pipeline, enrichment, storage, and system surfaces are **Proposed** until exercised in code. Product decisions remain tracked in PRODUCT.md.

## Project structure

Follows Apple's local-package guidance and the thin-app-target pattern used by IceCubesApp and isowords. Evidence: [research/xcode-structure.md](research/xcode-structure.md).

```
Impact.xcodeproj               Thin app shell, Xcode 16+ synchronized folders
Impact/                        App target: @main entry point and Assets.xcassets only
ImpactKit/                     Local Swift package: all logic and, later, UI features
├── Package.swift              One umbrella product, `ImpactKit`, linked by the app
├── Sources/ImpactEngine/      Pure Swift: model, rules, ranking (no UI, no EventKit)
└── Tests/ImpactEngineTests/   Swift Testing
```

Decisions:

- **New code goes into `ImpactKit`**; the app target stays an entry point plus wiring. Working rules for the package (adding modules, platforms, tests): [ImpactKit/AGENTS.md](../ImpactKit/AGENTS.md).
- **Modules are added one per area as their roadmap step starts.** Planned (Proposed): `DesignSystem` and `HomeFeature` (steps 5–6), `CalendarSources` (step 7), `ImpactIntelligence` (step 8).
- **The package also builds for macOS**, so `swift test` runs without a simulator.
- **Files need no project edits.** The app folder is a synchronized folder, package targets pick up files by directory, and the app links one umbrella product.
- **The `.xcodeproj` is committed.** XcodeGen was used once to scaffold it and is not a dependency. Project-level changes (the widget extension in step 9, capabilities, signing) are made in Xcode or in `project.pbxproj`; revisit a generator (XcodeGen, Tuist) if they become frequent.
- **Build settings** follow Xcode 27's app template (Approachable Concurrency, `MainActor` default isolation in the app target, member import visibility, user script sandboxing, String Catalogs, gnu17/gnu++20, upgrade check 2700), except Swift 6 language mode. The package enables the same upcoming features without default `MainActor` isolation.
- **App identity:** bundle ID `io.github.coldzero94.impact` (placeholder until App Store registration), iPhone only, no development team set; set `DEVELOPMENT_TEAM` locally for device builds (step 10).

Minimum deployment target: iOS 26.0 (PRODUCT.md D8).

## Pipeline

```
CalendarSource ──▶ [CalendarEvent] ──▶ Rules ──▶ [ImpactCard] ──▶ Enrichment (optional) ──▶ Store
  (EventKit/Mock)     normalized        select      facts+actions     Foundation Models          │
                                                                                              ▼
                                                     Surfaces: Home, widgets, notifications, Live Activity
```

1. **Fetch**: events in the horizon (today, plus tomorrow morning; PRODUCT.md → Horizon) from a `CalendarSource`.
2. **Normalize** into `CalendarEvent` (source-independent).
3. **Select** with deterministic rules (PRODUCT.md, event selection rules). Output: cards with confirmed facts and catalog actions.
4. **Compute**: travel time / leave-by (MapKit) for in-person cards.
5. **Enrich** (only if `SystemLanguageModel` is available): suggestions, using guided generation constrained to catalog types. One event per request to stay within the context size.
6. **Store** card and action state; merge with previous state so completed or dismissed cards stay that way.
7. **Schedule surfaces**: local notifications, widget timeline reload, scheduled Live Activity.

## Engine model and selection

The source of truth for the implemented types is [ImpactKit/Sources/ImpactEngine/](../ImpactKit/Sources/ImpactEngine/). The engine imports Foundation only: no UI, EventKit, MapKit, AI, persistence, or network calls.

| Type | Responsibility |
|------|----------------|
| `CalendarEvent` | Source-independent occurrence, calendar ID/type, dates, cancellation, participation, user membership, optional series ID, raw URL/location/notes, and resolved places |
| `Place` | Title, optional address, and a required coordinate pair; invalid coordinates are rejected during selection |
| `SuppressionRule` | Same recurring series on one calendar, or exact title on one calendar |
| `Provenance`, `Fact` | Calendar field, computation, or inference attached to each displayed fact |
| `ActionKind`, `ImpactAction` | Closed catalog from PRODUCT.md, with provenance; action identity is its kind and payload within a card |
| `ImpactCard` | Event occurrence ID, title, dates, kind, facts, and ordered actions (first is primary) |
| `HomeSnapshot` | What Home shows: Next up, later today, tomorrow morning, the summary count, the Impact ring, and which listed cards are done. Built by `home(events:now:calendar:completedCardIDs:impactsToday:…)` |

`CalendarEvent.id` must identify an occurrence, not just a recurring series. The future calendar adapter supplies this ID and the self-organizer/self-attendee flags; unknown membership on an event with attendees is excluded. `seriesID` is separate and supports muting all occurrences. Re-enabling a subscription or Birthdays calendar through `includedCalendarIDs` removes only the calendar-type exclusion, not declined/foreign-event or other exclusions.

`try ImpactEngine()` constructs Foundation's link/phone detector and propagates initialization errors. `card(for:now:suppressionRules:includedCalendarIDs:)` returns one card or `nil`. It implements [PRODUCT.md → Event selection rules v1](PRODUCT.md#event-selection-rules-v1), including all 13 examples. Selection uses an explicit clock; events ending exactly at `now` and invalid date intervals are excluded, and in-person cards leave 15 minutes after their start (PRODUCT.md → Card timeline). The caller fetches the horizon; this single-event selector does not rank or limit tomorrow's cards.

Meeting URLs are checked against one host/path allowlist. Text detection uses the original matched substring and requires explicit HTTP(S) URLs without credentials; it does not turn a detector-supplied scheme into a calendar fact. If several meeting links exist, the first wins in `url`, then `location`, then `notes` order. Non-meeting HTTP(S) links from notes become document actions, deduplicated by URL. Phone matches become Call actions for in-person cards only, deduplicated by matched text, with location taking precedence over notes.

Physical selection first uses valid `structuredPlace` coordinates (calendar provenance). Otherwise `canGeocode(_:)` rejects empty, URL, room, and floor labels before the caller requests a lookup. `geocodedPlace` must be the successful address/POI result for that event's location; the engine checks the candidate again and marks its result computed. Failed or missing lookups produce no physical signal. No place or travel time is invented: the Dentist example currently produces Directions without a leave-by time, as PRODUCT.md specifies when no route is available.

`home(…)` runs selection on today's events in the fetched horizon, sorts cards by start, then ID, and applies [UX.md → Home](UX.md#2-home) (Next up, summary, ring) and [PRODUCT.md → Horizon](PRODUCT.md#horizon) in the given calendar. Soon and Now come from PRODUCT.md → Card timeline; until leave-by exists, in-person cards count from the event start. Completions are passed for any day, so a card done the evening before stays done; the caller also passes today's Impact count, which the ring adds to the cards still to do. Tomorrow's events are selected only while Tomorrow morning shows. Occurrence IDs must be unique across the listed cards (asserted in debug builds).

The model deliberately omits the earlier draft's unused answer string, anchor, phase, action-completion state, suggestions, and dismissal state. Presentation, routing/ETA, persisting and merging card state, dismissal, and AI grounding belong to their later roadmap steps. Product proposals are not approved by this implementation.

## Refresh and platform constraints

iOS does not let an app run whenever it wants. The engine runs when:

| Trigger | Reliability |
|---------|-------------|
| App launch / foreground | Always |
| `EKEventStoreChanged` notification | Only while the app is running |
| `BGAppRefreshTask` | Best effort; the system decides when, possibly not at all |
| Widget timeline reload | Budgeted by the system |

Consequence: results must be **scheduled ahead** at analysis time (notifications, widget timeline entries, scheduled Live Activities). If the user does not open the app for days, newly added events may not be analyzed. This is accepted for the MVP.

Live Activities are started **without a server** by scheduling them at analysis time with `Activity.request(..., start: Date)` (iOS 26+). ActivityKit push-to-start needs APNs from a server and is out of scope.

## Foundation Models

- Check `SystemLanguageModel.default.availability` every time; handle `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady` by silently skipping enrichment.
- Check `supportedLanguages` against the event's language before prompting.
- Output only through `@Generable` types whose fields map to the catalog; never render free text as an action.
- Never send calendar data anywhere else (no Private Cloud Compute, no third-party APIs).

## Storage (Proposed)

- Card and action state: SwiftData in an App Group container (shared with widgets).
- Goals, Impact records, daily-log lines, and the identifiers of events Impact created: SwiftData in the same container.
- Settings and local rules (e.g. "don't suggest for events like this"): `UserDefaults` in the App Group.
- No calendar content is persisted beyond what card state needs; re-read from EventKit instead.

## Privacy

- Calendar access: full access is required to read events. It also allows writing; the only write is Block time (PRODUCT.md → Goals). Usage string states on-device processing and that Impact adds events only when the user taps Block time.
- No analytics SDKs, no network calls with calendar content.
- Google Calendar API (if ever added, D7): official OAuth via `ASWebAuthenticationSession`, tokens in Keychain, read-only scope.

## Testing

- `ImpactKit` engine: Swift Testing with synthetic `CalendarEvent` fixtures (one test per selection rule, plus skip cases).
- UI: SwiftUI previews backed by `MockSource`.
- Device testing is required for Foundation Models and Live Activities.

## Platform facts

Verified facts only. Add the date and how each was verified.

| Fact | Verified | How |
|------|----------|-----|
| Xcode 27.0 (27A266a), iOS 27.0 SDK installed | 2026-11-07 | `xcodebuild -version` |
| SDK includes FoundationModels, ActivityKit, AlarmKit, EventKit, AppIntents | 2026-11-07 | SDK `Frameworks/` listing |
| `SystemLanguageModel` unavailability reasons: `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`; `contextSize` and `supportedLanguages` exist | 2026-11-07 | FoundationModels `.swiftinterface` |
| `Activity.request(attributes:content:pushType:style:alertConfiguration:start:)` exists, iOS 26.0+ | 2026-11-07 | ActivityKit `.swiftinterface` |
| Xcode MCP bridge available at `xcrun mcpbridge` (not configured) | 2026-11-07 | `xcrun --find mcpbridge` |
| `NSDataDetector` finds links and phone numbers in natural-language text; results expose `url` and `phoneNumber` | 2026-11-08 | [Apple documentation](https://developer.apple.com/documentation/foundation/nsdatadetector), iOS 27 Foundation headers, and engine tests on macOS; URLs are validated separately |
| Full calendar access lets an app create, view, edit, and delete events; there is no read-only access. Writes use `saveEvent:span:commit:error:`; `EKCalendar.allowsContentModifications` says whether a calendar accepts them | 2026-11-09 | [Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), iOS 27 EventKit headers |
| `calendarItemIdentifier` is not sync-proof: a full sync can lose it, so a fallback match is needed; `calendarItemExternalIdentifier` is the server-provided one | 2026-11-09 | iOS 27 EventKit `EKCalendarItem.h` |
| No public API turns on an iOS Focus. Apps can only read Focus status (`INFocusStatusCenter`) and adapt to it (`SetFocusFilterIntent`) | 2026-11-09 | iOS 27 SDK: AppIntents `.swiftinterface` and Intents headers list no other Focus API |
| SDK includes JournalingSuggestions | 2026-11-09 | SDK `Frameworks/` listing |

To verify before relying on it:

- Whether Google Meet links from Google accounts synced via iOS Settings appear in EventKit (`url`, `location`, or `notes`). Check with a real account.
- Current Live Activity duration limits and scheduled-start behavior on device.
- Foundation Models availability in the Simulator on this Mac.
- MapKit routing and ETA in South Korea (driving and transit). Leave-by times depend on it; see PRODUCT.md D15.
- Whether the `alertConfiguration` of a scheduled Live Activity alerts the user when it starts (PRODUCT.md → Interruptions relies on it).
- Geocoding quality for Korean addresses and place names (selection rule for physical places).
- How Impact recognizes the focus blocks it created after a sync changes `calendarItemIdentifier` (PRODUCT.md → Block time), on Google and Exchange accounts.
- Journaling Suggestions: required entitlement, availability, and what the picker returns (PRODUCT.md → Daily log).
