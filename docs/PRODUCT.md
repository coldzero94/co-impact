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

## Design principles from award-winning apps

Derived from Apple Design Award and App Store Award winners. Evidence and sources: [research/award-winning-apps.md](research/award-winning-apps.md).

| # | Principle | Learned from | Rule for Impact |
|---|-----------|--------------|-----------------|
| P1 | Answer the question before the user asks | Flighty | Every card type exists to answer one question (see Card types). If a card can't answer its question with confirmed data, it is not created. |
| P2 | Boringly obvious | Flighty, Things 3 | Use proven conventions: departure-board rows, system components, SF Symbols. No novel gestures or custom controls without a reason. |
| P3 | There at the right moment | Flighty, Crouton | Cards move through timed phases; the right surface (Home, widget, Live Activity) shows the right thing at each phase. |
| P4 | Shine when things change | Flighty | A changed time or place is the only reason for an extra alert. |
| P5 | Complexity disappears | Moonlitt | Rules, scoring, and AI are never shown. A card shows results only. Onboarding is one screen. |
| P6 | AI produces next steps, not conversation | Tiimo | AI extracts at most two next steps from event notes, each grounded in the notes. No chat. |
| P7 | Support, not pressure | Gentler Streak | No streaks, badges, or "you missed it". Expired cards vanish silently. |
| P8 | Accessibility from day one | Structured | Dynamic Type, VoiceOver, Reduce Motion, and Differentiate Without Color are MVP requirements. |

## Core flow

1. User grants calendar access (the only permission asked at onboarding).
2. The engine scans today's events (see Horizon).
3. Rules select only events that need preparation.
4. Foundation Models (when available) adds up to two grounded next steps from event notes.
5. Home shows today's Impact Cards, most urgent first.
6. Tapping a card shows confirmed facts and one-tap actions.
7. Executing an action updates the card; the card moves through its phases and leaves when it is no longer relevant.

## Card types

Each card type answers exactly one question (P1).

| Card type | The question it answers | Primary action | Secondary actions |
|-----------|------------------------|----------------|-------------------|
| Online meeting | "Where do I click, and when?" | Join meeting | Open linked documents |
| In-person appointment | "When do I have to leave?" | Directions | Open linked documents, Call |
| Hybrid (link + physical address) | "Where do I click, and when?" | Join meeting | Directions, Open linked documents |

Later (not MVP): project deadline, trip. The calendar holds too little information for these, so most content would be inferred.

## Action catalog (MVP)

Actions are a closed set. The engine and the model can only pick from it. Each action is executable on iOS without a server, and each comes from confirmed data.

| Action | Mechanism | Source of data |
|--------|-----------|----------------|
| Join meeting | Open the meeting URL | Meeting URL detected in the event |
| Directions | Open Apple Maps to the place (`MKMapItem`) | Event's structured location or geocoded address |
| Open linked document | Open a non-meeting URL found in notes, labeled by host (e.g. "Open Figma") | URL in notes |
| Call | `tel:` | Phone number in location or notes |

Not actions: anything the app cannot execute, such as "prepare slides". Those may appear as AI next steps (labeled as suggestions), never as completable actions.

Removed from the earlier draft: *Remind me* (timing is automatic through the card timeline) and *Email organizer* (no clear moment of use).

## Event selection rules v1

A card is created only if a signal is found **and** no exclusion applies. These rules are deterministic and run on every device; AI never decides whether a card exists.

### Signals

**Meeting URL.** Any URL in the event's `url`, `location`, or `notes` whose host matches:

| Provider | Host / path |
|----------|-------------|
| Zoom | `zoom.us` and `*.zoom.us`, paths `/j/`, `/my/`, `/w/` |
| Google Meet | `meet.google.com/<code>` |
| Microsoft Teams | `teams.microsoft.com/l/meetup-join`, `teams.live.com/meet` |
| Webex | `*.webex.com`, paths `/meet/`, `/join/`, `/<site>/j.php` |
| FaceTime | `facetime.apple.com/join` |

The list lives in one place in code and grows only with a test case.

**Physical place.** In order:

1. `structuredLocation` has coordinates → physical place (confirmed).
2. Otherwise, a non-empty location that is not a URL and does not look like a room name (e.g. contains "회의실", "Room", "Conf", "F" floor patterns) is geocoded. If it resolves to an address or point of interest → physical place (computed).
3. Otherwise → no physical place (treated as a room inside a building the user is already in).

### Exclusions

| Exclusion | Why |
|-----------|-----|
| All-day events | Not time-bound |
| Canceled events, events the user declined | Not happening for the user |
| Events that already ended | Too late |
| Events with attendees where the user is neither organizer nor attendee | Shared or subscribed team calendars would otherwise flood Home |
| Calendars of type subscription, and the Birthdays calendar (default; user can re-enable) | Mostly other people's events |
| Events matching a "Don't suggest for events like this" rule | User feedback (same recurring series, or same title on the same calendar) |

### Examples (each row becomes a test)

| Event | Result |
|-------|--------|
| "Design review" 10:00, notes contain `https://zoom.us/j/123` | Online meeting card, primary Join |
| "1:1" with location `https://meet.google.com/abc-defg-hij` | Online meeting card |
| "Daily standup", recurring, Teams link in notes | Online meeting card (user can mute the series) |
| "Daily standup", recurring, no link, no location | No card (no signal) |
| "Dentist", structured location with coordinates | In-person card with leave-by time |
| "Lunch" at "Café Onion Seongsu" (geocodes to a place) | In-person card |
| "Team sync" at "회의실 3A", no link | No card (room name) |
| "Town hall" at "서울 중구 세종대로 110" plus Teams link | Hybrid card: Join primary, Directions secondary |
| "Holiday", all-day | No card (all-day) |
| Meeting with Zoom link, user declined | No card (declined) |
| Event on a subscribed team calendar, user not an attendee | No card (not the user's event) |
| "Focus time", no attendees, no link, no location | No card (no signal) |
| Zoom meeting that ended 5 minutes ago | No card (ended) |

## Card timeline

Cards move through phases (P3). Times are relative to the event start, or to the leave-by time for in-person cards.

**Leave-by time** = start − travel time − 5 min buffer. Travel time comes from MapKit using the current location at analysis time. Without location permission, or if no route is available, there is no leave-by time: the card shows the address and the Directions action only.

| Phase | Online meeting | In-person appointment | What changes |
|-------|----------------|----------------------|--------------|
| Upcoming | From the start of the horizon | Same | Listed as a row under "Later today" |
| Soon | T − 15 min | Leave-by − 30 min | Becomes "Next up" if it is the earliest |
| Now | T − 10 min until T + 10 min | Leave-by − 10 min until event start | Live Activity shown (scheduled ahead); one alert |
| Done | Join tapped | Directions tapped | Card subdued with a checkmark, moves out of "Next up" |
| Expired | Event end | Event start + 15 min | Removed silently (P7) |

## Horizon

- Home shows **Today**: from now until the end of the local day.
- From 18:00, or once today has no remaining cards, Home also shows **Tomorrow morning**: cards for events before 12:00 tomorrow, at most two. Preparing the evening before (e.g. an early appointment far away) is high value.

## AI scope (MVP)

AI is optional enrichment (P5, P6). Without Apple Intelligence the product is complete.

- **Input:** one event's title and notes. Nothing else, and nothing from outside the event.
- **Output:** at most two next steps, each `{ text, quote }`, where `quote` is a verbatim substring of the notes that justifies it. A step whose quote is not found in the notes is discarded.
- **When:** only for events that already have a card and whose notes contain enough text to act on.
- **Never:** decide whether a card exists, invent actions outside the catalog, generate the card's answer line, or chat.
- **Language:** generate in the notes' language if it is in `supportedLanguages`; otherwise skip.
- **Presentation:** a separate "Suggested" section with the `sparkles` symbol (see UX.md).

## Interruptions

- At most **one alert per card**, at the start of the Now phase. Preferred carrier: the scheduled Live Activity's start alert; fallback: a local notification at the same time.
- **Exception (P4):** if a carded event's time or place changes after the alert was scheduled, one "Changed" alert. Limitation: the change is only detected when the app gets to run (foreground, background refresh).
- No daily digest, no morning summary push, no streaks, no "you missed it" (P7).
- Interruption level `timeSensitive` only for meeting start and leave-by; everything else is passive (Home, widgets).

## Permissions

| Permission | When it is asked | Without it |
|------------|------------------|-----------|
| Calendar (full access) | Onboarding, the only permission there | App explains why and links to Settings |
| Notifications | The first time a card reaches its Now phase while the app is open, or from the first card's detail | Live Activities and widgets still work |
| Location (when in use) | The first time an in-person card appears: "To tell you when to leave" | In-person cards show Directions without a leave-by time |

## Completion semantics

- Executing an action marks it done. No confirmation step.
- A card is **done** when its primary action is done.
- A card **expires** silently (see Card timeline). No "did you do it?" prompts.
- Outcome metric: cards whose primary action was executed before the event started.

## Success metrics (local only, never uploaded)

- Share of cards whose primary action was executed (usefulness).
- Share of cards dismissed as "not needed" (over-generation signal; should be low).
- Time from opening the app to the first action (target: under 5 seconds).

## Non-goals (MVP)

- Task/to-do management, manual planning, AI chat.
- Own backend, accounts, sync.
- Writing to the user's calendar.
- Time-proportional day timelines, streaks, gamification.
- Direct Google Calendar API integration (see D7).

## Open decisions

| # | Decision | Proposed default | Status |
|---|----------|------------------|--------|
| D1 | Event selection rules | Selection rules v1 above | Proposed |
| D2 | Action catalog | Join, Directions, Open linked document, Call | Proposed |
| D3 | Completion semantics | Tap = done; silent expiry per Card timeline | Proposed |
| D4 | MVP scenarios | Online, in-person, hybrid only | Proposed |
| D5 | Empty-state behavior | Calm "nothing needs you" plus the next event that will (see UX.md) | Proposed |
| D6 | Dismiss feedback | "Not needed" plus optional "Don't suggest for events like this" | Proposed |
| D7 | Google Calendar API | Defer; verify Meet links via EventKit with a real account first | Proposed |
| D8 | Minimum iOS version | iOS 26.0 | Proposed |
| D9 | License | Not chosen yet | Open |
| D10 | Home horizon | Today, plus Tomorrow morning from 18:00 | Proposed |
| D11 | Location permission | Ask in context on the first in-person card; work without it | Proposed |
| D12 | Subscribed and shared calendars | Excluded by default; user's own events only | Proposed |
| D13 | Interruptions | One alert per card, plus one "Changed" alert | Proposed |
| D14 | AI grounding | Max two next steps, each with a verbatim quote from notes | Proposed |
| D15 | Directions app | Apple Maps. Korean users may prefer Naver Map or Kakao Map; decide after verifying MapKit routing in Korea | Open |
