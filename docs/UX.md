# UX

Goal: within 5 seconds of opening the app, the user knows what to do next, and can do it in one or two taps.

Follows Apple Human Interface Guidelines and the design principles P1–P8 in [PRODUCT.md](PRODUCT.md#design-principles-from-award-winning-apps). Supports light and dark mode, Dynamic Type, and VoiceOver from the first screen.

## Screens

### 1. Onboarding (first launch only)

- One screen (P5): what Impact does, in one sentence, plus a **Connect Calendar** button.
- Request full calendar access. The usage string says events are analyzed on device only.
- If denied: explain what the app needs and link to Settings. No demo data in release builds (mock data is for previews and debug only).
- No other permission here. Notifications and location are asked in context (PRODUCT.md → Permissions).

### 2. Home

```
┌─────────────────────────────────┐
│ Saturday, Nov 7                 │
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
│ TOMORROW MORNING                │  ← from 18:00 only
│ 08:30  Client visit Leave 07:40 │
└─────────────────────────────────┘
```

- **Summary line** counts all of today's events and how many need the user. It tells the user the app looked at everything, so a short list feels trustworthy rather than incomplete.
- **Next up** is the earliest card in its Soon or Now phase, shown large with its primary action. If no card is Soon yet, the first row is promoted with its time.
- **Later today** uses one line per card, like a departure board: time, title, and the one key fact (leave-by time or meeting provider). Tapping a row opens the card.
- **Tomorrow morning** appears from 18:00, or once today has no cards left (PRODUCT.md → Horizon).
- No tabs. Settings behind a toolbar button. Events that need nothing are counted but not listed; Home is not a calendar.

### 3. Empty state

Often the most common state. It must feel like a result, not an error (P7).

- "Nothing needs you today." with the summary line still showing ("0 of 4 events need you").
- Below it, the next event that will need the user, if any: "Next: Mon 10:00 · Design review".

### 4. Card detail

| Section | Content | Provenance |
|---------|---------|------------|
| Header | Title, time, relative time ("in 12 min") | Calendar |
| Answer | The card's question answered: "Leave by 14:05 · 18 min by car" or "Starts 10:00 · Zoom" | Calendar or computed |
| Actions | Catalog actions, primary first, each one tap | Calendar or computed |
| Details | Place, organizer, attendees, notes excerpt | Calendar |
| Suggested | Up to two AI next steps, each with its source quote from the notes | Inferred |

Executing an action marks it done in place (checkmark, subdued). No confirmation dialogs.

## Card anatomy

- **Time chip:** relative time under 1 hour ("in 12 min"), otherwise clock time.
- **Title:** event title, unchanged.
- **Answer line:** the answer to the card's question, from confirmed or computed data only.
- **Primary action button.**
- Done state: checkmark, secondary text color, primary button replaced by "Joined" / "Directions opened".

## Confirmed vs. inferred

- Calendar facts and computed values: plain text.
- AI next steps: `sparkles` symbol and the label "Suggested", in their own section, never mixed into facts. Each shows the quoted line from the notes it came from, so the user can see why.
- Color is never the only signal; the symbol and label carry the meaning for VoiceOver and Differentiate Without Color.

## Dismissing

- Swipe a card or row → **Not needed**. It disappears with no confirmation.
- Same menu: **Don't suggest for events like this** (mutes the recurring series, or the same title on the same calendar).

## System surfaces

Each surface shows the card's current phase (PRODUCT.md → Card timeline).

| Surface | Shows | Not for |
|---------|-------|---------|
| Live Activity / Dynamic Island | Now phase only. Compact: countdown + symbol (video / car). Expanded: title, answer line, primary action button | Lists, summaries, anything not in its Now phase |
| Home Screen widget, small | Next up: time chip, title, primary action | |
| Home Screen widget, medium | Next up plus the next row | |
| Lock Screen widget | Next time-bound fact ("Leave 14:05", "Zoom 10:00") | |
| Siri / Shortcuts | "What's next in Impact", "Join my next meeting" | Open-ended chat |
| Notifications | One alert per card at its Now phase, plus "Changed" (PRODUCT.md → Interruptions) | Digests, reminders to open the app |

## Accessibility (MVP requirements, P8)

- All text uses Dynamic Type text styles; layouts reflow at accessibility sizes (rows wrap, Next up stacks vertically).
- Every action has a VoiceOver label that includes the event ("Join Design review").
- Reduce Motion: no animated countdowns; values update without motion.
- Differentiate Without Color: status uses symbols and text, not color alone.
- Minimum tap target 44×44 pt.

## Copy tone

Short, calm, specific. State what is true ("Zoom link ready", "Leave by 14:05"), not how the app feels ("Great news!"). Never claim certainty for suggestions. Never scold (P7): no "You missed", "Overdue", or streak language.
