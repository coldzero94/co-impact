# Architecture

Everything here is **Proposed** until the Xcode project exists and the choice has been exercised in code. Update this file when that happens.

## Targets (Proposed)

```
Impact.xcodeproj
├── Impact            iOS app (SwiftUI)
├── ImpactWidgets     Widget extension: widgets + Live Activity UI      (step 9)
└── ImpactKit         Local Swift package, shared by app and extensions
    ├── Model         CalendarEvent, ImpactCard, ImpactAction, Provenance
    ├── Engine        Rules, ranking, card lifecycle (pure Swift, no UI, no EventKit)
    ├── Sources       CalendarSource protocol; EventKitSource, MockSource
    └── Intelligence  Foundation Models enrichment, optional         (step 8)
```

Why a package: the engine must be unit-testable without a simulator, and widgets and Live Activities need the same model types.

Minimum deployment target: iOS 26.0 (PRODUCT.md D8).

## Pipeline

```
CalendarSource ──▶ [CalendarEvent] ──▶ Rules ──▶ [ImpactCard] ──▶ Enrichment (optional) ──▶ Store
  (EventKit/Mock)     normalized        select      facts+actions     Foundation Models          │
                                                                                              ▼
                                                     Surfaces: Home, widgets, notifications, Live Activity
```

1. **Fetch**: events in the horizon (next 24 h) from a `CalendarSource`.
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

enum Provenance: Sendable, Hashable {
    case calendar(field: String)     // read directly from the event
    case computed(by: String)        // e.g. "MapKit ETA"
    case inferred(by: Inferrer)      // .rules or .foundationModel
}

struct Fact: Sendable, Hashable { let label: String; let value: String; let provenance: Provenance }

enum ActionKind: Sendable, Hashable {   // the closed catalog, see PRODUCT.md
    case joinMeeting(URL)
    case directions(to: String)
    case call(String), message(String)
    case emailOrganizer(String)
    case remind(at: Date)
}

struct ImpactAction: Sendable, Hashable, Identifiable {
    let id: String
    let kind: ActionKind
    let provenance: Provenance
    var state: ActionState              // pending, done
}

enum CardKind: Sendable { case onlineMeeting, inPerson }

struct ImpactCard: Sendable, Identifiable {
    let id: String                      // derived from event id
    let eventID: String
    let kind: CardKind
    let reason: String                  // one line, from confirmed data
    let relevantAt: Date                // when the primary action matters (start, or leave-by)
    var facts: [Fact]
    var actions: [ImpactAction]         // first = primary
    var suggestions: [Fact]             // always .inferred
    var state: CardState                // upcoming, done, dismissed, expired
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
