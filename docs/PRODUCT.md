# Product

## One-liner

Instead of managing a to-do list, the user connects their calendar. Impact finds the moments that matter (an event that needs preparation, a free hour that could move a goal forward), prepares what it can, and gets the user to the outcome in one or two taps. The purpose: make an impact, often.

## Problem

Calendars say *when* something happens, not *what has to be done before it*. People find out at 09:58 that the meeting link is buried in the invite, or at 13:50 that the appointment is 30 minutes away. To-do apps don't help: they require the user to plan, type, and maintain lists every day.

Goals fail the same way. New-year goals and "deep work" live in a note while the calendar fills with other people's meetings; by February there is no time left for them. Diaries fail because they ask the user to write every evening.

## Target user (Proposed)

iPhone users with several calendar events a day (iCloud, Exchange, or a personal Google account added in iOS Settings), mostly online meetings and in-person appointments, who want to arrive prepared without planning their day by hand, and who have one to three goals for the year that keep losing to the week.

## Impact (Proposed)

An **Impact** is one completed action toward something that matters:

- the primary action of an event card (online, in-person, or hybrid), executed: joined the meeting, opened directions;
- a focus session of at least 10 minutes in a block the user set for a goal.

Blocking time is a plan, not an Impact; the session that follows is.

Impacts are recorded automatically; the user never logs anything by hand. They are counted, never ranked or compared, and a day without one shows nothing (P7).

**North-star metric:** Impacts per week. Supporting metrics: the share of goals whose sessions are blocked this week, and focus minutes kept. All stay on device (see Success metrics).

## Core loop (Proposed)

**Detect → Suggest → Act → Record → Look back.**

1. **Detect** moments that matter: events that need preparation (Event selection rules v1) and free time a goal could use (Goal-time rules v1).
2. **Suggest** each one as an Impact Card that answers one question (P1).
3. **Act** in one tap, from the closed action catalog.
4. **Record** the completed action as an Impact.
5. **Look back** at the end of the day, in the daily log.

| Scale | What happens | Where |
|-------|--------------|-------|
| Moment | An event card or a focus block reaches its Now phase: one tap to join, leave, or start focus | Home, Live Activity |
| Day | At most two goal-time suggestions | Home |
| Week | Each goal gets its sessions blocked | Home (goal-time cards) |
| End of day | The day's Impacts become the daily log; the user may add one line | Home, evening |
| Year | One to three goals, set once in under 30 seconds | Goal setup |

## Principles

| Principle | What it means in practice |
|-----------|---------------------------|
| Zero friction | No daily planning, no chat, no confirmation dialogs. Writes to the calendar only when the user taps Block time. |
| Outcome first | Measure Impacts (joined, left on time, focus kept), not task counts. |
| Apple native | SwiftUI and system frameworks. System surfaces (widgets, Live Activities, Siri) over in-app chrome. |
| Local first | No backend, no cloud DB. |
| Privacy first | Calendar data is processed on device and never leaves it. |
| Simple but powerful | Useful on first launch, with zero configuration. Goals are optional. |

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

## Core flow (event cards)

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
| Goal time (Proposed) | "When will I work on this goal this week?" | Block time | None |
| Focus block (Proposed) | "Is it time to start, and on what?" | Start focus | None |

Later (not MVP): project deadline, trip. The calendar holds too little information for these, so most content would be inferred.

## Action catalog (MVP)

Actions are a closed set. The engine and the model can only pick from it. Each action is executable on iOS without a server, and each comes from confirmed or computed data, or from the user's own goals.

| Action | Mechanism | Source of data |
|--------|-----------|----------------|
| Join meeting | Open the meeting URL | Meeting URL detected in the event |
| Directions | Open Apple Maps to the place (`MKMapItem`) | Event's structured location or geocoded address |
| Open linked document | Open a non-meeting URL found in notes, labeled by host (e.g. "Open Figma") | URL in notes |
| Call | `tel:` | Phone number in location or notes |
| Block time (Proposed) | Save a calendar event titled with the goal, in a calendar that allows modifications; Undo for 5 seconds | Free slot computed from the calendar; goal set by the user |
| Start focus (Proposed) | Start an in-app focus session with a Live Activity. It does not turn on an iOS Focus: no public API exists (ARCHITECTURE.md → Platform facts) | A focus block created by Block time |

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

## Goals (Proposed)

Goals are where work focus and new-year goals meet: "Ship the Q1 launch" and "Run three times a week" work the same way. Goals are optional; without them, Impact is the event-card app above.

- **One to three goals.** Each has a title, times per week (1–5, default 2), and a window: **Workday** or **Personal time**. Sessions are 60 minutes in v1.
- **Windows.** Working hours default to Mon–Fri 09:00–18:00, editable in Settings. Personal time is everything outside working hours between 07:00 and 22:00.
- **The only typing in the app.** Goals and working hours are the one exception to "no input"; setup takes under 30 seconds (UX.md → Goal setup).
- **Not projects.** No sub-tasks, due dates, progress percentages, or reminders. A goal can be paused or removed at any time, silently.

### Goal-time rules v1

Deterministic, like event selection; AI never decides.

- **Busy time:** any event Impact can read, except all-day events, canceled events, events the user declined, and events marked free.
- **Free slot:** 60 minutes inside the goal's window, at least 10 minutes from any busy time, starting at least 1 hour from now and ending within the current week (weeks start on the locale's first weekday).
- **Blocked sessions:** events Impact created for the goal this week that are still on the calendar.
- A goal gets a card when it has fewer blocked sessions this week than its times per week **and** a free slot exists. The card proposes the earliest free slot; two sessions of one goal are never on the same day.
- **Limits:** one goal-time card on Home at a time, at most two a day (hard rule 4). **Not now** hides that goal's card until tomorrow.

| Situation | Result |
|-----------|--------|
| "Write a book", Personal time, 2 per week, none blocked; the earliest free slot in Personal time is Thursday 19:00 | Card: "Thu 19:00 is free", Block time |
| Same goal, two sessions already blocked this week | No card (target met) |
| "Ship the Q1 launch", Workday; now 11:00; a meeting 13:00–14:00, nothing else until 15:30 | Card: today 14:10–15:10 (12:00–13:00 is too close to the meeting) |
| Only 50-minute gaps left in the window this week | No card (no slot) |
| User tapped Not now on this goal's card today | No card until tomorrow |

### Block time

- Saves an event titled with the goal to the default calendar for new events, if the OS allows modifying it. Otherwise the user picks a writable calendar once, at the first Block time. Never a calendar the OS does not let Impact write to (hard rule 8).
- No attendees, no alarms from Impact. Impact keeps the identifiers of the events it created, on device, with a fallback match because identifiers can change after a sync (ARCHITECTURE.md → Platform facts). It never edits or deletes any other event.
- Undo for 5 seconds removes the event. Moving the event in Calendar moves the block; deleting it removes the block.

### Focus blocks

- An event Impact created becomes a focus block card: Soon from 15 minutes before, Now from 5 minutes before until it ends, expired at its end.
- **Start focus** starts an in-app session shown as a Live Activity with the goal and the time left in the block. It does not silence notifications; that needs an iOS Focus, which apps cannot turn on.
- The user can end a session at any time; ending early is never scolded, and the minutes still count as focus minutes. A session of 10 minutes or more records an Impact.

## Daily log (Proposed)

The diary, without writing a diary.

- From 18:00, or after the day's last card, the day's Impacts become a log entry: "Joined Design review · 10:01", "50 min on Write a book".
- The user may add **one line**. No prompt, no notification, nothing shown for a day without one.
- Stored on device only. Past entries are browsable (UX.md → Daily review).
- Later, behind availability checks and with no new onboarding step: a weekly summary that Foundation Models writes from the log alone, and Journaling Suggestions to attach a moment to the line (verify first; ARCHITECTURE.md → Platform facts).

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

Goal-time cards have no phases: they leave when the block is created, when the slot starts, or on Not now. Focus blocks: see Goals → Focus blocks.

## Horizon

- Home shows **Today**: from now until the end of the local day.
- From 18:00, or once today has no remaining cards, Home also shows **Tomorrow morning**: cards for events before 12:00 tomorrow, at most two. Preparing the evening before (e.g. an early appointment far away) is high value.
- Goal-time cards are the exception: they may propose a slot later this week, because blocking it is decided now.

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
- Goals add no alert type. Goal-time cards and the daily log never notify; a focus block, like any card, gets at most one alert, at its start, at the default interruption level.

## Permissions

| Permission | When it is asked | Without it |
|------------|------------------|-----------|
| Calendar (full access) | Onboarding, the only permission there. Full access also covers Block time; no second prompt | App explains why and links to Settings |
| Notifications | The first time a card reaches its Now phase while the app is open, or from the first card's detail | Live Activities and widgets still work |
| Location (when in use) | The first time an in-person card appears: "To tell you when to leave" | In-person cards show Directions without a leave-by time |

## Completion semantics

- Executing an action marks it done. No confirmation step.
- A card is **done** when its primary action is done.
- A card **expires** silently (see Card timeline). No "did you do it?" prompts.
- Outcome metric: cards whose primary action was executed before the event started.
- A goal-time card is done when Block time succeeds; Undo brings it back.
- Every executed primary action of an event card and every focus session of 10 minutes or more records one Impact, automatically (see Impact).

## Success metrics (local only, never uploaded)

- **Impacts per week** (north star).
- Share of goals whose sessions are blocked this week; focus minutes kept.
- Share of cards whose primary action was executed (usefulness).
- Share of cards dismissed as "not needed" (over-generation signal; should be low).
- Time from opening the app to the first action (target: under 5 seconds).

## Non-goals (MVP)

- Task/to-do management, manual planning, AI chat.
- Own backend, accounts, sync.
- Writing to the calendar beyond Block time. Impact never edits or deletes an event it did not create.
- Time-proportional day timelines, streaks, badges, points, leaderboards. The Impact ring (UX.md) has no target to fail.
- Habit tracking, goal sub-tasks, journaling prompts.
- Direct Google Calendar API integration (see D7).

## Open decisions

| # | Decision | Proposed default | Status |
|---|----------|------------------|--------|
| D1 | Event selection rules | Selection rules v1 above | Proposed |
| D2 | Action catalog | Join, Directions, Open linked document, Call; Block time and Start focus for goals | Proposed |
| D3 | Completion semantics | Tap = done; silent expiry per Card timeline; Impacts recorded automatically | Proposed |
| D4 | MVP scenarios | Online, in-person, hybrid first; goal time and focus blocks next (ROADMAP.md) | Proposed |
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
| D16 | What counts as an Impact; north star | Executed primary action or a focus session of 10+ minutes; Impacts per week | Proposed |
| D17 | Goals | One to three; title, times per week, Workday or Personal time; 60-minute sessions; default working hours Mon–Fri 09:00–18:00 | Proposed |
| D18 | Calendar writes | Block time only, to a writable calendar, with Undo; never touch events Impact did not create | Proposed |
| D19 | Focus session | In-app session with a Live Activity; no iOS Focus (no API) | Proposed |
| D20 | Daily log | Built from Impacts, optional one line, on device only; Foundation Models summary and Journaling Suggestions later | Proposed |
| D21 | Positioning and accounts | Work and personal goals in one app; personal Google accounts through iOS Settings, no Google sign-in (D7) | Proposed |
| D22 | Launch timing | No deadline, quality first; the new year is a marketing moment, not a release date | Decided (2026-11-09) |
