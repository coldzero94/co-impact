# Research: award-winning iOS apps

Researched 2026-11-07. Goal: find what award-winning iOS apps do to stay simple and reduce user effort, and decide what Impact adopts. Conclusions are applied in [PRODUCT.md](../PRODUCT.md#design-principles-from-award-winning-apps) and [UX.md](../UX.md).

Source quality: **Apple** = Apple newsroom, App Store editorial, or Apple developer articles. **3rd party** = press or independent analysis. Only Apple-sourced statements are treated as facts about why an app won.

## Apps reviewed

| App | Award | Why it matters to Impact |
|-----|-------|--------------------------|
| Flighty | Apple Design Award 2023, Interaction (winner) | Closest analog: turns a schedule (flights) into timed, glanceable, actionable state |
| Things 3 | Apple Design Award 2017 (winner) | Today view that combines calendar and next actions |
| Crouton | Apple Design Award 2024, Interaction (winner) | Interaction that keeps users focused on the task, not the screen |
| Gentler Streak | Apple Design Award 2024, Social Impact (winner) | Tone: supportive, no guilt |
| Tiimo | App Store Awards 2025, iPhone App of the Year | AI that turns goals into next steps |
| Moonlitt | Apple Design Award 2026, Interaction (winner) | Complexity hidden behind a simple surface; Liquid Glass; easy onboarding |
| Structured | Apple Design Award 2026, Inclusivity (finalist) | Daily planner; accessibility included in the free tier |
| Tide Guide | Apple Design Award 2026, Visuals and Graphics (winner) | Considered, mostly not adopted (see below) |

## Findings

### Flighty: answer the question before the user asks it

- Goal, in the founder's words: *"We want Flighty to work so well that it feels almost boringly obvious."* (Apple)
- Key information front and center, with an immediately understandable interface. (Apple)
- Users kept re-checking the same facts ("I have to be at the gate in 32 minutes"); the app shows them before they ask: *"There's something comforting about information always being there."* (Apple)
- Live Activities and Dynamic Island as a *"companion that makes key information available at all times."* (Apple)
- Borrowed a proven real-world convention, the airport departure board: *"one line per flight ... they've had 50 years of figuring out what's important."* (Apple)
- Plans for losing connectivity: before takeoff, the Dynamic Island switches to a minimal progress presentation computed without network. (Apple)
- *"We really have to shine when things go awry."* (Apple)

### Things 3: one tidy Today view, invisible chrome

- The Today screen shows calendar appointments and next actions together in one view. (Apple, App Store listing)
- The company describes simplicity as key; reviewers note the interface recedes so content stands out. (Apple feature; 3rd party reviews)

### Crouton: the screen gets out of the way

- Praised for effortless interactions that let users *"focus on cooking rather than the screen."* (Apple)
- Timers continue on the Lock Screen. (Apple)

### Gentler Streak: support, not pressure

- Reminders are *"just as likely to remind you to take a break as to push yourself a little harder."* (Apple)

### Tiimo: AI produces next steps, not conversation

- *"An impressive visual planner and thoughtfully implemented AI that turns aspirations into actionable next steps."* (Apple)

### Moonlitt: complexity disappears into the experience

- Cited for *"best-in-class Liquid Glass integration"* and *"easy onboarding."* (Apple)
- Developers: *"the goal was never to make people feel the complexity"*; proud of *"how much complexity disappears into the experience."* (Apple)

### Structured: accessibility is not a premium feature

- Finalist in Inclusivity; VoiceOver, Voice Control, Dynamic Type, and a dyslexia-friendly font ship in the free tier. (3rd party review)
- Criticism: the time-proportional timeline becomes an unreadable ribbon when many short tasks stack. (3rd party review)

## What Impact adopts

| # | Principle | From | Applied as |
|---|-----------|------|------------|
| P1 | Each card answers one question before the user asks | Flighty | Card types are defined by their question ("When do I leave?"), see PRODUCT.md |
| P2 | Boringly obvious: proven conventions over novelty | Flighty, Things 3 | Departure-board rows for later items; system components and SF Symbols |
| P3 | Always there at the right moment | Flighty, Crouton | Card timeline with phases; scheduled Live Activity; widgets |
| P4 | Shine when things change | Flighty | Changed time or place is the one case that earns an extra alert |
| P5 | Complexity disappears into the experience | Moonlitt | Engine, rules, and AI are invisible; a card shows only results. One-screen onboarding |
| P6 | AI turns text into next steps, never chat | Tiimo | AI only extracts up to 2 grounded next steps from event notes |
| P7 | Support, not pressure | Gentler Streak | No streaks, no "you missed it", expired cards vanish silently |
| P8 | Accessibility from day one, for everyone | Structured | Dynamic Type, VoiceOver, Reduce Motion in MVP scope, not later |

## Considered and not adopted

| Idea | From | Why not |
|------|------|---------|
| Time-proportional day timeline | Structured | Becomes unreadable when dense; Impact shows only events that need the user, so a list of cards is clearer |
| Full-screen animated charts, decorative palettes | Tide Guide | Impact's content is actions, not data; decoration would compete with the one thing to do |
| Novel input gestures (e.g. hands-free control) | Crouton | No hands-busy moment in Impact's flow; actions are one tap |
| Visual planning of the whole day | Tiimo | Impact deliberately avoids planning by the user |

## Sources

- Apple, *Behind the Design: Flighty* (2023): https://developer.apple.com/news/?id=970ncww4
- Apple Design Awards 2023 winners: https://developer.apple.com/design/awards/2023
- Apple Design Awards 2024 winners: https://www.apple.com/newsroom/2024/06/apple-announces-winners-of-the-2024-apple-design-awards/
- Apple, *Meet this year's Apple Design Award winners* (Crouton, 2024): https://apps.apple.com/ca/story/id1745165692
- Apple newsroom, 2025 App Store Awards (Tiimo): https://apple.com/newsroom/2025/12/apple-unveils-the-winners-of-the-2025-app-store-awards
- Apple newsroom, 2026 Apple Design Awards: https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/
- Apple, *ADA Q&A: What a little Moonlitt can do* (2026): https://developer.apple.com/news/?id=v1nphz91
- Things 3 on the App Store / Apple editorial: https://apps.apple.com/us/story/id1390028519
- Structured review (3rd party): https://coolcuration.com/structured-app-review-uk
