# UX

Goal: within 5 seconds of opening the app, the user knows what to do next, and can do it in one or two taps. Every completed action should feel like progress.

Follows Apple Human Interface Guidelines and the design principles P1–P8 in [PRODUCT.md](PRODUCT.md#design-principles-from-award-winning-apps). Supports light and dark mode, Dynamic Type, and VoiceOver from the first screen.

## Simplicity rules (Proposed)

1. **One screen.** Home is the app. No tabs; goals appear only as cards; settings sit behind a toolbar button; everything else is a sheet over Home.
2. **One card, one action.** Each card shows one primary action. Secondary actions live in card detail.
3. **Only when needed.** Event cards follow the selection rules; goal-time suggestions appear at most twice a day (PRODUCT.md → Goal-time rules v1).
4. **Five-second rule.** Opening the app answers "what now?" within 5 seconds, without scrolling.
5. **Setup in 30 seconds.** Goal setup and working hours take under 30 seconds, with defaults for everything but the goal's title.

## Screens

### 1. Onboarding (first launch only)

- One screen (P5): what Impact does, in one sentence, plus a **Connect Calendar** button.
- Request full calendar access. The usage string says events are analyzed on device only.
- If denied: explain what the app needs and link to Settings. No demo data in release builds (mock data is for previews and debug only).
- No other permission here. Notifications and location are asked in context (PRODUCT.md → Permissions).
- No goal setup here. After the first Impact, Home offers it once as a quiet row under the cards ("Set up to three goals for this year"); afterwards it is in Settings.

### 2. Home

```
┌─────────────────────────────────┐
│ Saturday, Nov 7            ◔ 2  │  ← Impact ring: today's Impacts
│ 2 of 6 events need you          │  ← summary: shows the app checked everything
│                                 │
│ ┌─────────────────────────────┐ │
│ │ IN 12 MIN · 10:00           │ │  ← Next up: the earliest card in Soon/Now
│ │ Design review               │ │
│ │ Zoom link ready             │ │  ← the answer to the card's question (P1)
│ │ [ Join meeting ]            │ │  ← primary action, one tap
│ └─────────────────────────────┘ │
│                                 │
│ LATER TODAY                     │
│ 14:30  Dentist      Leave 14:05 │  ← departure-board rows (P2)
│ 17:00  Town hall    Teams       │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ WRITE A BOOK                │ │  ← goal-time card, below time-bound cards
│ │ Thu 19:00 is free           │ │
│ │ [ Block time ]              │ │
│ └─────────────────────────────┘ │
│                                 │
│ TOMORROW MORNING                │  ← from 18:00, or once today has no cards left
│ 08:30  Client visit Leave 07:40 │
└─────────────────────────────────┘
```

- **Impact ring** shows today's Impacts. Its segments are the day's chances for one (event cards and focus blocks); each Impact fills one. A dismissed or expired card's segment disappears instead of showing as missed, so the ring has no target to fail (P7). Tapping it opens the daily review.
- **Summary line** counts the user's events left today and how many of them have a card, done or not. It tells the user the app looked at everything, so a short list feels trustworthy rather than incomplete.
- **Next up** is the earliest card not done in its Soon or Now phase, shown large with its primary action. If none is, the card that started most recently and is still running leads (the user may be late); otherwise the next card is promoted with its time. Done cards never lead. A focus block in its Now phase shows here with **Start focus**.
- **Later today** uses one line per card, like a departure board: time, title, and the one key fact (leave-by time or meeting provider). Tapping a row opens the card.
- **Goal-time card** sits below the time-bound cards, one at a time. **Block time** shows "Blocked · Undo" for 5 seconds; swiping offers **Not now**.
- **Tomorrow morning** appears from 18:00, or once today has no cards left (PRODUCT.md → Horizon).
- Events that need nothing are counted but not listed; Home is not a calendar.

### 3. Empty state

Often the most common state. It must feel like a result, not an error (P7).

- "Nothing needs you today." with the summary line still showing ("0 of 4 events need you").
- Below it, the next event that will need the user, if any: "Next: Mon 10:00 · Design review".
- A goal-time card may still appear; an empty day is a good day for a goal.

### 4. Card detail

| Section | Content | Provenance |
|---------|---------|------------|
| Header | Title, time, relative time ("in 12 min") | Calendar |
| Answer | The card's question answered: "Leave by 14:05 · 18 min by car" or "Starts 10:00 · Zoom" | Calendar or computed |
| Actions | Catalog actions, primary first, each one tap | Calendar or computed |
| Details | Place, organizer, attendees, notes excerpt | Calendar |
| Suggested | Up to two AI next steps, each with its source quote from the notes | Inferred |

Executing an action marks it done in place (checkmark, subdued). No confirmation dialogs.

### 5. Goal setup (sheet)

- Up to three rows. Each row: a title field, times per week (stepper, 1–5, default 2), and Workday / Personal time (segmented, default Workday).
- Working hours in one row below (default Mon–Fri 09:00–18:00).
- Done is enabled as soon as one title exists. The first goal-time card can appear right after.

### 6. Daily review (sheet)

- Opens from the Impact ring, or from the "Today" row Home shows from 18:00.
- The day's Impacts as a short list ("Joined Design review · 10:01", "50 min on Write a book") and one optional line ("One line about today").
- Earlier days below, newest first. No charts, no comparisons, no empty-day markers.

## Card anatomy

- **Time chip:** relative time under 1 hour ("in 12 min"), otherwise clock time.
- **Title:** event title, unchanged; for goal-time and focus cards, the goal's title.
- **Answer line:** the answer to the card's question, from confirmed or computed data only.
- **Primary action button.**
- Done state: checkmark, secondary text color, primary button replaced by "Joined" / "Directions opened" / "Blocked".

## Confirmed vs. inferred

- Calendar facts and computed values: plain text.
- AI next steps: `sparkles` symbol and the label "Suggested", in their own section, never mixed into facts. Each shows the quoted line from the notes it came from, so the user can see why.
- Color is never the only signal; the symbol and label carry the meaning for VoiceOver and Differentiate Without Color.

## Dismissing

- Swipe a card or row → **Not needed**. It disappears with no confirmation.
- Same menu: **Don't suggest for events like this** (mutes the recurring series, or the same title on the same calendar).
- Goal-time cards offer **Not now** instead (hidden until tomorrow).

## Motion (Proposed)

Motion exists to make progress felt, never to decorate.

1. **Show cause and effect.** Every animation connects an action to its result: the card the user acted on is the thing that moves.
2. **Delight matches meaning.** Block time gets a checkmark; an Impact gets the Impact moment; a finished focus session gets its larger version. Opening the app, scrolling, and dismissing get none.
3. **Never in the way.** The action fires on tap, before any animation. Springs last 0.3–0.5 s and can be interrupted by the next touch.
4. **For everyone.** Reduce Motion replaces movement with a cross-fade; haptics follow the system setting; VoiceOver announces the result ("Impact recorded. 3 today.").

### The Impact moment

The signature animation, used for every Impact:

1. The card folds into a small token (its symbol: video, car, or the goal's mark).
2. The token travels to the Impact ring, and its segment fills.
3. A success haptic plays as it lands.

If the action left the app (Join opens Zoom, Directions opens Maps), the moment plays when the user comes back, so it is seen rather than missed. A focus session that ends gets the larger version: the ring briefly glows. In the daily review, the day's tokens gather into the ring once, the first time the review opens that evening.

During a focus session, the Live Activity and Dynamic Island show the same ring shape filling with time, so the session and the day read as one thing.

## System surfaces

Each surface shows the card's current phase (PRODUCT.md → Card timeline).

| Surface | Shows | Not for |
|---------|-------|---------|
| Live Activity / Dynamic Island | Now phase only. Compact: countdown + symbol (video / car / focus). Expanded: title, answer line, primary action button. Focus session: goal and time left | Lists, summaries, anything not in its Now phase |
| Home Screen widget, small | Next up: time chip, title, primary action; otherwise the Impact ring | |
| Home Screen widget, medium | Next up plus the next row | |
| Lock Screen widget | Next time-bound fact ("Leave 14:05", "Zoom 10:00") | |
| Siri / Shortcuts | "What's next in Impact", "Join my next meeting" | Open-ended chat |
| Notifications | One alert per card at its Now phase, plus "Changed" (PRODUCT.md → Interruptions) | Digests, reminders to open the app, goal suggestions, the daily log |

## Accessibility (MVP requirements, P8)

- All text uses Dynamic Type text styles; layouts reflow at accessibility sizes (rows wrap, Next up stacks vertically).
- Every action has a VoiceOver label that includes the event or goal ("Join Design review", "Block Thursday 19:00 for Write a book").
- Reduce Motion: no animated countdowns, and the Impact moment becomes a cross-fade; values update without motion.
- Differentiate Without Color: status uses symbols and text, not color alone.
- Minimum tap target 44×44 pt.

## Design checklist for UI changes

A PR that changes UI says in its description how it meets each item, with a preview or screenshot:

- [ ] Five-second rule: a first-time viewer can say what to do next.
- [ ] One tap: the primary action needs one tap, with no confirmation.
- [ ] Reduce Motion: the change works with it on.
- [ ] Dynamic Type: layouts hold at the largest accessibility size.
- [ ] VoiceOver: every element and action has a meaningful label.
- [ ] Light and dark mode.

## Copy tone

Short, calm, specific. State what is true ("Zoom link ready", "Leave by 14:05", "Thu 19:00 is free"), not how the app feels ("Great news!"). Never claim certainty for suggestions. Never scold (P7): no "You missed", "Overdue", "You should", or streak language.
