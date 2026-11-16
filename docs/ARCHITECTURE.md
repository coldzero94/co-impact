# Architecture

The project structure, engine selection model, Home snapshot, the action log, the EventKit source, stored Impacts, and the onboarding, Home, and card detail screens as far as [UX.md → Screens](UX.md#screens) says (their "Not built yet" notes list the rest) are implemented (roadmap steps 3–7). The remaining pipeline, enrichment, storage, and system surfaces are **Proposed** (how they settle: AGENTS.md).

## Project structure

Follows Apple's local-package guidance and the thin-app-target pattern used by IceCubesApp and isowords. Evidence: [research/xcode-structure.md](research/xcode-structure.md).

```
Impact.xcodeproj               Thin app shell, Xcode 16+ synchronized folders
Impact/                        App target: @main entry point, Assets.xcassets, Info.plist (URL scheme, Live Activities),
                               and entitlements (App Group)
ImpactWidgets/                 Widget extension: its @main WidgetBundle, Info.plist, and entitlements only
ImpactKit/                     Local Swift package: all logic and UI features
├── Package.swift              Umbrella product `ImpactKit` for the app; `LiveSurfaces` for the extension
├── Sources/ImpactEngine/      Pure Swift: model, rules, ranking (no UI, no EventKit)
├── Sources/CalendarSources/   EventKit: calendar access, fetching, and mapping events to CalendarEvent
├── Sources/LiveSurfaces/      System surfaces: the Live Activity (`LiveCard`, layouts, run link, scheduling), the
│                              Lock Screen widget, the state widgets share with the app, and the card facts every
│                              surface shows (ActivityKit and WidgetKit code iOS-only)
├── Sources/HomeFeature/       SwiftUI onboarding, Home, card detail, actions, Impact ring and moment, live
│                              refresh, stored Impacts, Live Activity sync and run links, synthetic fixtures
├── Tests/ImpactEngineTests/   Swift Testing
├── Tests/CalendarSourcesTests/ Swift Testing
└── Tests/HomeFeatureTests/    Swift Testing
```

Decisions:

- **New code goes into `ImpactKit`**; the app target stays an entry point plus wiring. Working rules for the package (adding modules, platforms, tests): [ImpactKit/AGENTS.md](../ImpactKit/AGENTS.md).
- **Modules are added one per area as their roadmap step starts.** `HomeFeature` (step 5), `CalendarSources` (step 7), and `LiveSurfaces` (step 9) exist; `HomeFeature` uses `CalendarSources` for its live root view and `LiveSurfaces` for Live Activities. Planned (Proposed): `DesignSystem` once a second feature shares components, `ImpactIntelligence` (step 8).
- **The package also builds for macOS**, so `swift test` runs without a simulator.
- **Files need no project edits.** The app and extension folders are synchronized folders (their `Info.plist` excluded from resources), package targets pick up files by directory, and the app links one umbrella product.
- **The `.xcodeproj` is committed.** XcodeGen was used once to scaffold it and is not a dependency. Project-level changes (the widget extension in step 9, capabilities, signing) are made in Xcode or in `project.pbxproj`; revisit a generator (XcodeGen, Tuist) if they become frequent.
- **Build settings** follow Xcode 27's app template (Approachable Concurrency, `MainActor` default isolation in the app target, member import visibility, user script sandboxing, String Catalogs, gnu17/gnu++20, upgrade check 2700), except Swift 6 language mode. The package enables the same upcoming features without default `MainActor` isolation.
- **App identity:** bundle ID `io.github.coldzero94.impact` (placeholder until App Store registration), the widget extension `io.github.coldzero94.impact.widgets`, the App Group `group.io.github.coldzero94.impact` (both targets' entitlements), iPhone only, no development team set; set `DEVELOPMENT_TEAM` on both targets locally for device builds, which registers the App Group (step 10).

Minimum deployment target: iOS 26.0 (PRODUCT.md D8).

## Pipeline

```
CalendarSource ──▶ [CalendarEvent] ──▶ Rules ──▶ [ImpactCard] ──▶ Enrichment (optional) ──▶ Store
  (EventKit/Mock)     normalized        select      facts+actions     Foundation Models          │
                                                                                              ▼
                                                     Surfaces: Home, widgets, notifications, Live Activity
```

1. **Fetch**: events from the start of today through the six days after it, from a `CalendarSource`. Home lists today and tomorrow morning (PRODUCT.md → Horizon); the empty state names the first card not done that Home does not list (UX.md → Empty state).
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
| `CalendarEvent` | Source-independent occurrence, calendar ID/type, dates, cancellation, participation, user membership, optional series ID, raw URL/location/notes, the organizer's and other invitees' display names, and resolved places |
| `Place` | Title, optional address, and a required coordinate pair; invalid coordinates are rejected during selection |
| `SuppressionRule` | Same recurring series on one calendar, exact title on one calendar, or one occurrence |
| `Dismissals` | Occurrences marked Not needed (until the later of the event's end and two days after the dismissal) and muted series or titles (an untitled one-off is only dismissed); its `rules` go to `home(suppressionRules:)` |
| `Provenance`, `Fact` | Calendar field, computation, or inference attached to each displayed fact |
| `ActionKind`, `ImpactAction` | Closed catalog from PRODUCT.md, with provenance; action identity is its kind and payload within a card |
| `ImpactCard` | Event occurrence ID, title ("Untitled" when the calendar's is empty; the Title fact keeps it empty, and title rules match the event's title, never the displayed "Untitled"), dates, kind, facts, and ordered actions; the first calendar or computed one is the primary action (`primaryAction`), and inferred ones are never shown as buttons (`confirmedActions`) |
| `ActionLog` | Which actions ran, by card, and when each card's Impact was recorded (its primary action, once, from the card's Soon phase on; in person from 2 hours before the start until leave-by exists). Feeds `home(…)`'s completions and today's Impact count |
| `HomeSnapshot` | What Home shows: Next up, later today, tomorrow morning, the summary count, the Impact ring, which listed cards are done, and the empty state's next card. Built by `home(events:now:calendar:completedCardIDs:impactsToday:…)` |

`CalendarSources` maps each EventKit occurrence: the ID is `calendarItemIdentifier`, plus the original occurrence date for recurring and detached (moved or otherwise edited on their own) occurrences; the series ID is `calendarItemIdentifier` when the event recurs. On a local calendar a moved occurrence gets an item ID of its own (Platform facts), so it becomes a new card outside its series. Participation and membership come from the attendee marked as the current user and the organizer. Card detail gets the organizer's display name (name, else email address) unless it is the user, and the other attendees' display names, without rooms, equipment, or the organizer listed again (same address in any letter case); a participant with neither a name nor an email address gets an empty name, which card detail shows as an unnamed guest (UX.md → Card detail). Subscription calendars (including CalDAV calendars marked subscribed, e.g. on iCloud) and Birthdays keep their kind, so selection skips them. A structured location becomes a `Place` only with coordinates: its title's first line is the name (or, with no title, the location text's first line) and the rest, or else the location text after that name, the address. No geocoding happens yet, so a location without coordinates gives no in-person card: Apple's geocoder returned wrong or no places in a simulator check (Platform facts), so it waits for a device check (step 10). Home fetches from the start of today to the end of the sixth day after it (`ImpactEngine.horizon`), when the built triggers under Refresh and platform constraints fire. Without full access, or with no regular calendar, the fetch returns nothing at all rather than an empty list, and Home says so instead of showing an empty day.

`CalendarEvent.id` must identify an occurrence, not just a recurring series. `CalendarSources` (above) supplies this ID and the self-organizer/self-attendee flags; unknown membership on an event with attendees is excluded. `seriesID` is separate and supports muting all occurrences (except moved ones; see `Dismissals.mute`). Re-enabling a subscription or Birthdays calendar through `includedCalendarIDs` removes only the calendar-type exclusion, not declined/foreign-event or other exclusions.

`try ImpactEngine()` constructs Foundation's link/phone detector and propagates initialization errors. `card(for:now:suppressionRules:includedCalendarIDs:)` returns one card or `nil`. It implements [PRODUCT.md → Event selection rules v1](PRODUCT.md#event-selection-rules-v1), including all 13 examples. Selection uses an explicit clock; events ending exactly at `now` and invalid date intervals are excluded, and in-person cards leave 15 minutes after their start (PRODUCT.md → Card timeline). The caller fetches the horizon; this single-event selector does not rank or limit tomorrow's cards.

Meeting URLs are checked against one host/path allowlist. Text detection uses the original matched substring and requires explicit HTTP(S) URLs without credentials; it does not turn a detector-supplied scheme into a calendar fact. If several meeting links exist, the first wins in `url`, then `location`, then `notes` order. Non-meeting HTTP(S) links from notes become document actions, deduplicated by URL. Phone matches become Call actions for in-person cards only, deduplicated by the `tel:` URL they dial (`telURL`), with location taking precedence over notes; a number `telURL` cannot dial (letters, no digits) gets none, and an extension or pause after `;` or `,` is not dialed.

Physical selection first uses valid `structuredPlace` coordinates (calendar provenance). Otherwise `canGeocode(_:)` rejects empty, URL, room, and floor labels before the caller requests a lookup. `geocodedPlace` must be the successful address/POI result for that event's location; the engine checks the candidate again and marks its result computed. Failed or missing lookups produce no physical signal. No place or travel time is invented: the Dentist example currently produces Directions without a leave-by time, as PRODUCT.md specifies when no route is available.

`home(…)` runs selection on today's events in the fetch, sorts cards by start, then ID, and applies [UX.md → Home](UX.md#2-home) (Next up, summary, ring) and [PRODUCT.md → Horizon](PRODUCT.md#horizon) in the given calendar. Soon and Now come from PRODUCT.md → Card timeline; until leave-by exists, in-person Soon and Now are measured from the event start. Completions are passed for any day, so a card done before midnight (a 00:05 meeting joined at 23:55) or restored from storage stays done; the caller also passes today's Impact count, which the ring adds to the cards still to do. Events after today are selected only while Tomorrow morning shows or, for the empty state's next card, while no listed card is left to do. Occurrence IDs must be unique (debug builds assert it on the listed cards).

The model deliberately omits the earlier draft's unused answer string, anchor, phase, and suggestions. `ActionLog` keeps which actions ran in memory, and Home stores its Impacts and `Dismissals` (Storage); routing/ETA, geocoding, and AI grounding belong to later work. Presentation lives in `HomeFeature`: `HomeModel` rebuilds the snapshot after each recorded action or dismissal, and views run actions through SwiftUI's `openURL` (Join, Open link, Call) and MapKit (Directions). Product proposals are not approved by this implementation.

## Refresh and platform constraints

iOS does not let an app run whenever it wants. The engine runs when:

| Trigger | Reliability |
|---------|-------------|
| App launch / foreground | Always (built, step 7) |
| Every minute while Home is open | Always; countdowns move on the minute (built, step 7) |
| `EKEventStoreChanged` notification | Only while the app is running (built, step 7) |
| `BGAppRefreshTask` | Best effort; the system decides when, possibly not at all |
| Widget timeline reload | Budgeted by the system. Built (step 9): the Lock Screen widget lays out entries up to each change of phase ahead, and Impact asks for a reload when the done or dismissed cards, the next cards, or calendar access change |

Consequence: results must be **scheduled ahead** at analysis time (notifications, widget timeline entries, scheduled Live Activities). If the user does not open the app for days, newly added events may not be analyzed. This is accepted for the MVP.

Live Activities are started **without a server** by scheduling them at analysis time with `Activity.request(..., pushType: nil, ..., start: Date)` (iOS 26+). Built (step 9): the cards that want one are `HomeSnapshot.liveActivityCards`, the next two cards still to do whose Now phase has not ended, among events starting before tomorrow noon whether Home lists them yet or not. Whenever they change, live Home ends the activities no longer wanted, in front or in the background (so a card done by its Join or Directions loses its activity at once). Whenever Impact is in front, it also requests the missing ones: scheduled to start with their Now phase (with its alert) and go stale at its end, or at once without an alert when already in their Now phase. When Impact can no longer read the calendar, all end. A run link refreshes Home before running the card's action, so the action counts at the time it runs. The content never changes after it is requested (timer text moves on its own); a changed card gets a new activity. ActivityKit push-to-start and push updates need APNs from a server and are out of scope. The `activitykit` skill's examples pass `.token` or `.channel` and its review checklist expects push tokens sent to a server; neither applies here (hard rule 1).

## Foundation Models

- Check `SystemLanguageModel.default.availability` every time; handle `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady` by silently skipping enrichment.
- Check `supportedLanguages` against the event's language before prompting.
- Output only through `@Generable` types whose fields map to the catalog; never render free text as an action.
- Never send calendar data anywhere else (no Private Cloud Compute, no third-party APIs).

## Storage

- Built (step 7): recorded Impacts, as card IDs and times, in one JSON file in the app's Application Support folder. Which secondary actions ran is not stored. A file that does not decode is renamed aside; one that cannot be read at the moment is left alone, each save first tries reading it again and skips until it can, and each refresh tries too and adds what it reads to Home. Merges keep each card's earlier stamp. Without a usable file, Impacts count until the app quits.
- Built (step 9): what widgets need from Impact (`SurfaceState`): the card IDs done in the last two days and the dismissals' rules (so muted titles too), as JSON in the App Group's defaults, rewritten whenever it changes. The widgets read events from the calendar themselves, so no other calendar content is stored; Impacts and dismissals stay where they are, Impact being the only writer.
- Proposed: card and action state in SwiftData in an App Group container (shared with widgets), once background refresh (step 10) or the daily log (step 13) needs more than `SurfaceState`.
- Proposed: goals, Impact records, daily-log lines, and the identifiers of events Impact created, in SwiftData in the same container.
- Built (step 7): dismissals, as JSON in standard `UserDefaults`: occurrence IDs with when they lapse (the later of the event's end and two days after the dismissal) and the calendar IDs with the series IDs or titles the user muted (muted titles are the only calendar text stored). Data that does not decode is kept under another key. When widgets or background refresh read them (steps 9–10), they move to the App Group; since they are loaded once and saved whole, saves must then never overwrite dismissals that could not be read, as Impact saves already do.
- Proposed: settings in `UserDefaults` in the App Group.
- No calendar content is persisted beyond what card state needs; re-read from EventKit instead.

## Privacy

- Run links (`impact://run?card=<id>&token=<secret>`, Live Activity buttons) run a listed card's primary action only with the per-install secret that Impact keeps in standard `UserDefaults` and puts in its own activities' links (owner, 2026-11-16). Card IDs alone are not enough, since any app with full calendar access can read them; a link without the right secret only opens Impact.
- Calendar access: full access is required to read events. It also allows writing; the only write is Block time (PRODUCT.md → Goals). The usage string (`INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription` in the app target) states on-device processing; the clause that Impact adds events only when the user taps Block time joins it with Block time (step 11).
- No analytics SDKs, no network calls with calendar content. The owner has approved sending a location without coordinates to Apple's geocoder (MapKit) once its quality is checked on a device (step 10); until then no location is sent to it. Shipping it means rewording the usage string, PRODUCT.md → Principles ("never leaves it"), and UX.md → Onboarding.
- Google Calendar API (if ever added, D7): official OAuth via `ASWebAuthenticationSession`, tokens in Keychain, read-only scope.

## Testing

- `ImpactKit` engine: Swift Testing with synthetic `CalendarEvent` fixtures (one test per selection rule, plus skip cases).
- `CalendarSources`: mapping tests on unsaved `EKEvent`s, which need no calendar access, so tests never read the machine's calendar.
- UI: SwiftUI previews, and debug builds launched with `-fixtureHour` (ImpactKit/AGENTS.md → UI), use `HomeFixtures` (synthetic events run through the real engine, debug only); otherwise every build runs `LiveHome` (UX.md → Onboarding). A UI change is checked by simulator screenshots (ImpactKit/AGENTS.md → UI).
- Device testing is required for Foundation Models and Live Activities.

## Platform facts

Verified facts only. Add the date and how each was verified.

| Fact | Verified | How |
|------|----------|-----|
| Xcode 27.0 (27A266a), iOS 27.0 SDK installed | 2026-11-07 | `xcodebuild -version` |
| SDK includes FoundationModels, ActivityKit, AlarmKit, EventKit, AppIntents | 2026-11-07 | SDK `Frameworks/` listing |
| `SystemLanguageModel` unavailability reasons: `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`; `contextSize` and `supportedLanguages` exist | 2026-11-07 | FoundationModels `.swiftinterface` |
| `Activity.request(attributes:content:pushType:style:alertConfiguration:start:)` exists, iOS 26.0+; `pushType` is `PushType? = nil` | 2026-11-07, 2026-11-15 | ActivityKit `.swiftinterface` |
| In the iOS 27 simulator, a scheduled request returns an activity in state `pending` that turns `active` at its start date while the app is in the background; `end(_:dismissalPolicy:)` removed an active one. Activities appear on the Lock Screen and in the Dynamic Island (also in `simctl` screenshots) only after the Lock Screen's first "Allow Live Activities from Impact?" is answered. A Live Activity `Link` to `impact://run?card=…` opens Impact with the URL. After Impact is relaunched, `Activity.activities` lists its active and pending activities with the same IDs, so a sync does not request them again; installing a new build ends them all. Ending an activity while Impact was leaving the front for Safari worked | 2026-11-15 | Simulator run (iPhone 18 Pro, iOS 27) |
| In the iOS 27 simulator, the widget extension reads EventKit with the app's full access (`authorizationStatus` `.fullAccess`; events fetched) and opens the App Group container when both targets are signed (ad hoc) with its entitlement | 2026-11-16 | Simulator run (iPhone 18 Pro, iOS 27) |
| `request(…start:)` must be called with the app in the foreground; `update(_:)` and `end(_:dismissalPolicy:)` work in the foreground or background ("You can update or end a Live Activity while your app is in the background, but you can only start a Live Activity while the app is in the foreground, unless you adopt AppIntents") | 2026-11-16 | ActivityKit `.swiftdoc` in the iOS 27 SDK (the `.swiftinterface` has no doc comments); [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) |
| Xcode MCP bridge available at `xcrun mcpbridge` (not configured) | 2026-11-07 | `xcrun --find mcpbridge` |
| `NSDataDetector` finds links and phone numbers in natural-language text; results expose `url` and `phoneNumber` | 2026-11-08 | [Apple documentation](https://developer.apple.com/documentation/foundation/nsdatadetector), iOS 27 Foundation headers, and engine tests on macOS; URLs are validated separately |
| Full calendar access lets an app create, view, edit, and delete events; there is no read-only access. Writes use `saveEvent:span:commit:error:`; `EKCalendar.allowsContentModifications` says whether a calendar accepts them | 2026-11-09 | [Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), iOS 27 EventKit headers |
| `calendarItemIdentifier` is not sync-proof: a full sync can lose it, so a fallback match is needed; `calendarItemExternalIdentifier` is the server-provided one | 2026-11-09 | iOS 27 EventKit `EKCalendarItem.h` |
| No public API turns on an iOS Focus. Apps can only read Focus status (`INFocusStatusCenter`) and adapt to it (`SetFocusFilterIntent`) | 2026-11-09 | iOS 27 SDK: AppIntents `.swiftinterface` and Intents headers list no other Focus API |
| SDK includes JournalingSuggestions | 2026-11-09 | SDK `Frameworks/` listing |
| `Color.mix(with:by:in:)` exists from iOS 18.0 and macOS 15.0 | 2026-11-09 | iOS 27 SDK `SwiftUICore.framework` `arm64e-apple-ios.swiftinterface` |
| `MKMapItem(location:address:)` exists from iOS 26.0 and macOS 26.0 (`init(placemark:)` is deprecated there), with `MKAddress(fullAddress:shortAddress:)` (failable); `openInMaps(launchOptions:)` returns whether Maps opened, on iOS and macOS | 2026-11-09 | iOS 27 SDK MapKit `MKMapItem.h` and `MKAddress.h` |
| `OpenURLAction` calls back with whether the URL was accepted; `ButtonRole.close` exists from iOS 26.0 | 2026-11-09 | iOS 27 SDK `SwiftUICore` and `SwiftUI` `.swiftinterface` |
| `requestFullAccessToEvents()` (iOS 17+) prompts once; `authorizationStatus(for: .event)` reports `.fullAccess`, `.writeOnly`, `.denied`, `.restricted`, or `.notDetermined`, and only full access reads events. The usage key is `NSCalendarsFullAccessUsageDescription` | 2026-11-15 | iOS 27 SDK EventKit `EKEventStore.h`, `EKTypes.h`; simulator run |
| `events(matching:)` expands recurring events into occurrences; `occurrenceDate` is the original date of a recurring occurrence, even after it is moved, and unset otherwise; `EKParticipant.isCurrentUser`, `name` (optional), `url`, and `participantType` (`.room`, `.resource`), `EKEvent.organizer`, `EKEvent.status` (`.canceled`), `EKCalendar.type` (`.subscription`, `.birthday`), and `EKStructuredLocation.geoLocation` exist. A CalDAV subscribed calendar has type `.calDAV` with `isSubscribed` true. `EKCalendar` has no property marking a calendar shared into the user's account; calendars of an account delegated by another user can be told apart with `EKSource.isDelegate` (iOS 16+), not used (D12: delegated calendars count as the user's own) | 2026-11-15 | iOS 27 SDK EventKit `EKEvent.h`, `EKParticipant.h`, `EKTypes.h`, `EKCalendar.h`, `EKSource.h`, `EKStructuredLocation.h`; occurrence expansion seen in a simulator run |
| An `.ics` added through Safari ("Add All") keeps an event's location text as a structured location title but drops `X-APPLE-STRUCTURED-LOCATION` coordinates; opening an `.ics` URL with `simctl openurl` offers a subscription instead | 2026-11-15 | iOS 27 simulator run |
| Moving one occurrence of a recurring event gives it a new `calendarItemIdentifier`, `hasRecurrenceRules` false, `isDetached` true, and `occurrenceDate` still the original date; its `calendarItemExternalIdentifier` became the series UID plus `/RID=<time>` on a local calendar (the format depends on the server) | 2026-11-15 | iOS 27 simulator run: one occurrence of a synthetic daily series moved with `save(_:span: .thisEvent)` |
| In the simulator (US region, no `region` set on the request), `MKGeocodingRequest(addressString:)` (iOS 26.0+, addresses) found nothing for "서울 중구 세종대로 110", "Apple Park", or multi-line "Name\nAddress" locations, matched "110 Sejong-daero" to an address in Daegu and "Seoul City Hall" to Hill City, SD; `MKLocalSearch` (natural-language) found nothing for "서울 중구 세종대로 110", "서울시청", or "Café Onion Seongsu", and matched "City Hall, 110 Sejong-daero" to Jeonju City Hall. ("Apple Park" is a place name; whether the address API covers names is unverified) | 2026-11-15 | iOS 27 simulator run |

To verify before relying on it:

- Whether Google Meet links from Google accounts synced via iOS Settings appear in EventKit (`url`, `location`, or `notes`). Check with a real account.
- Current Live Activity duration limits and scheduled-start behavior on device.
- Foundation Models availability in the Simulator on this Mac.
- MapKit routing and ETA in South Korea (driving and transit). Leave-by times depend on it; see PRODUCT.md D15.
- Whether the `alertConfiguration` of a scheduled Live Activity alerts the user when it starts, including under a Focus or the silent switch (PRODUCT.md → Interruptions relies on it), and whether `end` cancels a pending one on a device; whether installing an update ends stored activities on a device, as in the simulator (`LiveCard`'s stored form changes between builds until release).
- Geocoding quality for Korean addresses and place names on a device in Korea, including whether results outside the user's area can be told apart (selection rule for physical places; the simulator check above found wrong or no places), with the request's `region` set and a non-Korean control address, and MapKit's geocoding rate limits.
- How Impact recognizes the focus blocks it created after a sync changes `calendarItemIdentifier` (PRODUCT.md → Block time), on Google and Exchange accounts.
- Journaling Suggestions: required entitlement, availability, and what the picker returns (PRODUCT.md → Daily log).
- The format of `calendarItemExternalIdentifier` per server (iCloud, Google, Exchange) and whether it survives moving one occurrence, before series mutes key on it (`Dismissals.mute`).
- Whether `OpenURLAction` reports a `tel:` URL as accepted before the user confirms the call prompt; if so, a cancelled call still shows "Call opened" (UX.md → Card detail). Check on a device (step 10).
