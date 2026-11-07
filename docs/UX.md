# UX

Goal: within 5 seconds of opening the app, the user knows what to do next, and can do it in one or two taps.

Follows Apple Human Interface Guidelines. Supports light and dark mode, Dynamic Type, and VoiceOver from the first screen.

## Screens

### 1. Onboarding (first launch only)

- One screen: what Impact does, in one sentence, plus a **Connect Calendar** button.
- Request full calendar access (iOS 17+ `requestFullAccessToEvents`). The usage string explains that events are analyzed on device only.
- If denied: explain what the app needs and link to Settings. No fake or demo data in release builds (mock data is for previews and debug only).
- Notification permission is **not** asked here. Ask in context, the first time a card has a time-bound action (e.g. "Remind me to leave").

### 2. Home (Today)

```
┌───────────────────────────────┐
│ Saturday, Nov 7               │
│ 2 things need you today       │  ← one-line summary
│                               │
│ ┌───────────────────────────┐ │
│ │ IN 25 MIN · 10:00         │ │  ← Next up: large card
│ │ Design review             │ │
│ │ Zoom link ready           │ │  ← why this card exists
│ │ [ Join meeting ]          │ │  ← primary action, one tap
│ └───────────────────────────┘ │
│                               │
│ LATER TODAY                   │
│ 14:30 Dentist · Leave 14:05 ›│  ← compact rows
└───────────────────────────────┘
```

- **Next up** is the most urgent card, shown large with its primary action button.
- **Later today** shows remaining cards as compact rows. At most 3 cards on Home in total; the rest are under "More".
- No tabs, no settings in the main view (settings behind a toolbar button).
- Events that need no preparation are not shown. Home is not a calendar view.

### 3. Empty state

The most frequent state on many days. It must feel like a result, not an error.

- "Nothing needs you right now."
- Below it, the next event that will need preparation, if any: "Next: Mon 10:00 · Design review".

### 4. Card detail

Opened by tapping a card.

| Section | Content | Provenance |
|---------|---------|------------|
| Header | Title, time, relative time ("in 25 min") | Calendar |
| Actions | Catalog actions, primary first, each one tap | Calendar or computed |
| Facts | Location, link, organizer, attendees, notes excerpt | Calendar |
| Computed | Travel time, leave-by time | Computed (MapKit) |
| Suggestions | e.g. "Review last week's notes" | Inferred, visually distinct |

Executing an action marks it done in place (checkmark, subdued). No confirmation dialogs.

## Card anatomy

- Time chip: relative time when under 1 hour, otherwise clock time.
- Title: event title, unchanged.
- Reason line: why this card exists, from confirmed data ("Zoom link ready", "18 min drive").
- Primary action button.

## Confirmed vs. inferred

- Calendar facts and computed values: plain text.
- Inferred content (rules or AI): marked with the `sparkles` SF Symbol and the label "Suggested", grouped in its own section, never mixed into the facts list.
- Do not rely on color alone; the icon and label carry the meaning for VoiceOver and color-blind users.

## Dismissing

- Swipe a card → **Not needed**. The card disappears with no confirmation.
- Optional follow-up in the same gesture menu: **Don't suggest for events like this**, stored as a local rule.

## System surfaces

| Surface | Use | Not for |
|---------|-----|---------|
| Live Activity / Dynamic Island | One active, time-bound activity: "Design review starts in 10 min → Join", "Leave by 14:05 → Directions" | Lists, summaries, anything not time-bound |
| Home Screen widget (small) | Next action with its button | |
| Home Screen widget (medium) | Next two cards | |
| Lock Screen widget | Next time-bound item ("Leave 14:05") | |
| Siri / Shortcuts | "What's next in Impact", "Join my next meeting" | Open-ended chat |
| Local notifications | Leave-by and meeting-start nudges, only for cards with time-bound actions | Daily digests |

## Copy tone

Short, calm, specific. Say what is true ("Zoom link ready"), not how the app feels ("Great news!"). Never claim certainty for inferred content.
