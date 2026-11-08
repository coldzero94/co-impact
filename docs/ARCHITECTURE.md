# Architecture

The project structure below is implemented (roadmap step 3). Everything else is **Proposed** until it has been exercised in code; update this file when that happens.

## Project structure

Follows Apple's local-package guidance and the thin-app-target pattern used by IceCubesApp and isowords. Evidence: [research/xcode-structure.md](research/xcode-structure.md).

```
Impact.xcodeproj               Thin app shell, Xcode 16+ synchronized folders
Impact/                        App target: @main entry point and Assets.xcassets only
ImpactKit/                     Local Swift package: all logic and, later, UI features
├── Package.swift
├── Sources/ImpactEngine/      Pure Swift: model, rules, ranking (no UI, no EventKit)
└── Tests/ImpactEngineTests/   Swift Testing
```

Rules:

- **New code goes into `ImpactKit`**, not the app target. The app target stays an entry point plus wiring.
- **One module per area, added when its roadmap step starts.** Planned (Proposed): `ImpactEngine` (step 4), `DesignSystem` and `HomeFeature` (steps 5–6), `CalendarSources` (step 7), `ImpactIntelligence` (step 8). Each module depends only on what it uses; `ImpactEngine` imports no UI or EventKit.
- **The package also builds for macOS**, so pure modules are tested with `swift test` without a simulator. Code that needs iOS-only frameworks (ActivityKit, WidgetKit) goes in iOS-only targets or the app/extension.
- **Files need no project edits.** The app folder is a synchronized folder, and package targets pick up files by directory.
- **The `.xcodeproj` is committed.** XcodeGen was used once to scaffold it and is not a dependency. Project-level changes (the widget extension in step 9, capabilities, signing) are made in Xcode or in `project.pbxproj`; revisit a generator (XcodeGen, Tuist) if they become frequent.
- **Build settings** follow Xcode 27's app template (Approachable Concurrency, `MainActor` default isolation in the app target, member import visibility, user script sandboxing), except Swift 6 language mode (AGENTS.md conventions). The package enables the same upcoming features without default `MainActor` isolation.
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

## Data model (draft)

```swift
struct CalendarEvent: Sendable, Hashable {
    let id: String              // EventKit identifier + occurrence start date (recurrences share an identifier)
    let title: String
    let start: Date, end: Date
    let isAllDay: Bool
    let location: String?
    let url: URL?
    let notes: String?
    let organizer: Person?
    let attendees: [Person]
    let isRecurring: Bool
    let participation: Participation   // accepted, declined, tentative, unknown
}

struct Place: Sendable, Hashable {
    let title: String
    let address: String?
    let latitude: Double?, longitude: Double?   // from structuredLocation or geocoding
}

enum Provenance: Sendable, Hashable {
    case calendar(field: String)     // read directly from the event
    case computed(by: String)        // e.g. "MapKit ETA"
    case inferred(by: Inferrer)      // .rules or .foundationModel
}

struct Fact: Sendable, Hashable { let label: String; let value: String; let provenance: Provenance }

enum ActionKind: Sendable, Hashable {   // the closed catalog, see PRODUCT.md
    case joinMeeting(URL)
    case directions(to: Place)
    case openLink(URL)                  // non-meeting URL from notes, e.g. a Figma or Docs link
    case call(String)
}

struct ImpactAction: Sendable, Hashable, Identifiable {
    let id: String
    let kind: ActionKind
    let provenance: Provenance
    var state: ActionState              // pending, done
}

enum CardKind: Sendable { case onlineMeeting, inPerson, hybrid }

enum CardPhase: Sendable { case upcoming, soon, now, done, expired }   // PRODUCT.md → Card timeline

struct NextStep: Sendable, Hashable {  // AI output, PRODUCT.md → AI scope
    let text: String
    let quote: String                   // must be a verbatim substring of the event notes
}

struct ImpactCard: Sendable, Identifiable {
    let id: String                      // derived from event id
    let eventID: String
    let kind: CardKind
    let answer: String                  // answers the card type's question, confirmed or computed data only
    let anchor: Date                    // event start, or leave-by time for in-person cards
    var facts: [Fact]
    var actions: [ImpactAction]         // first = primary
    var nextSteps: [NextStep]           // AI, at most 2
    var phase: CardPhase
    var isDismissed: Bool
}
```

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
- Settings and local rules (e.g. "don't suggest for events like this"): `UserDefaults` in the App Group.
- No calendar content is persisted beyond what card state needs; re-read from EventKit instead.

## Privacy

- Calendar access: full access is required to read events. Usage string states on-device processing.
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

To verify before relying on it:

- Whether Google Meet links from Google accounts synced via iOS Settings appear in EventKit (`url`, `location`, or `notes`). Check with a real account.
- Current Live Activity duration limits and scheduled-start behavior on device.
- Foundation Models availability in the Simulator on this Mac.
- MapKit routing and ETA in South Korea (driving and transit). Leave-by times depend on it; see PRODUCT.md D15.
- Whether the `alertConfiguration` of a scheduled Live Activity alerts the user when it starts (PRODUCT.md → Interruptions relies on it).
- Geocoding quality for Korean addresses and place names (selection rule for physical places).
