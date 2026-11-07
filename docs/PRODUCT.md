# Product

## One-liner

Instead of managing a to-do list, the user connects their calendar. Impact finds the events that need preparation, prepares what it can, and gets the user to the outcome in one or two taps.

## Problem

Calendars say *when* something happens, not *what has to be done before it*. People find out at 09:58 that the meeting link is buried in the invite, or at 13:50 that the appointment is 30 minutes away. To-do apps don't help: they require the user to plan, type, and maintain lists every day.

## Target user (Proposed)

iPhone users with several calendar events a day, mostly online meetings and in-person appointments, who want to arrive prepared without planning their day by hand.

## Principles

| Principle | What it means in practice |
|-----------|---------------------------|
| Zero friction | No daily planning, no chat, no confirmation dialogs. Read-only by default. |
| Outcome first | Measure completed outcomes (joined on time, left on time), not task counts. |
| Apple native | SwiftUI and system frameworks. System surfaces (widgets, Live Activities, Siri) over in-app chrome. |
| Local first | No backend, no cloud DB. |
| Privacy first | Calendar data is processed on device and never leaves it. |
| Simple but powerful | Useful on first launch, with zero configuration. |

## Core flow

1. User grants calendar access.
2. The engine scans upcoming events.
3. Rules select only events that need preparation.
4. Foundation Models (when available) adds suggestions, chosen from the action catalog.
5. Home shows today's Impact Cards, most urgent first.
6. Tapping a card shows verified facts and one-tap actions.
7. Executing an action updates the card; the next relevant action surfaces.

## Impact Pack

An Impact Pack turns one event into an executable package: **facts** (each with provenance) plus **actions** (from the catalog). It is not a checklist.

| Event type | Example pack | MVP |
|------------|--------------|-----|
| Online meeting | Join link, start time, organizer, agenda from notes | Yes |
| In-person appointment | Address, travel time, leave-by time, directions | Yes |
| Project deadline | Deliverable, remaining work | Later: the calendar holds too little information, so most content would be inferred |
| Trip | Departure prep, bookings | Later: same reason |

## Action catalog (MVP)

Actions are a closed set. The engine and the model can only pick from it. Each action must be executable on iOS without a server.

| Action | Mechanism | Needs |
|--------|-----------|-------|
| Join meeting | Open meeting URL (Zoom, Meet, Teams, Webex, ...) | URL in event |
| Get directions | Open Apple Maps (`MKMapItem`) to the event location | Geocodable location |
| Call / message | `tel:` / `sms:` | Phone number in event |
| Email organizer | Mail compose | Organizer email |
| Remind me | Local notification at a chosen time | Notification permission |

Not actions: anything the app cannot execute, such as "prepare slides". Those may appear as *suggestions* (clearly labeled as inferred), never as completable actions.

## Completion semantics (Proposed)

- Executing an action marks it done. No confirmation step.
- A card is **done** when its primary action is done.
- A card **expires** silently when its event ends. No "did you do it?" prompts.
- Outcome metric: cards whose primary action was executed before the event started.

## Event selection rules (Proposed, MVP)

Create a card only if at least one rule fires:

| Rule | Card type |
|------|-----------|
| Event has a meeting URL (in URL, location, or notes) from a known provider | Online meeting |
| Event has a physical location (not a URL, not a bare room name) | In-person appointment |

Skip: all-day events, declined or canceled events, events that already ended, and recurring events with no link and no location.

Horizon: the next 24 hours on Home.

## Success metrics (local only, never uploaded)

- Share of cards whose primary action was executed (usefulness).
- Share of cards dismissed as "not needed" (over-generation signal; should be low).
- Time from opening the app to the first action (target: under 5 seconds).

## Non-goals (MVP)

- Task/to-do management, manual planning, AI chat.
- Own backend, accounts, sync.
- Writing to the user's calendar.
- Direct Google Calendar API integration (see open decisions).

## Open decisions

| # | Decision | Proposed default | Status |
|---|----------|------------------|--------|
| D1 | Event selection rules | Table above | Proposed |
| D2 | Action catalog | Table above | Proposed |
| D3 | Completion semantics | Tap = done, auto-expire at event end | Proposed |
| D4 | MVP scenarios | Online meetings + in-person appointments only | Proposed |
| D5 | Empty-state behavior | Calm "nothing needs you" plus the next event that will (see UX.md) | Proposed |
| D6 | Dismiss feedback | "Not needed" plus optional "don't suggest for events like this" as a local rule | Proposed |
| D7 | Google Calendar API | Defer. Google accounts added in iOS Settings are readable through EventKit. Revisit only if EventKit misses critical data (e.g. Meet links); verify with a real account first | Proposed |
| D8 | Minimum iOS version | iOS 26.0 (Foundation Models, scheduled Live Activities) | Proposed |
| D9 | License | Not chosen yet | Open |
