# Impact

A native iOS app that reads your calendar, finds the events that actually need preparation, and turns each one into an **Impact Card**: verified facts plus one-tap actions such as joining the meeting or getting directions.

No to-do lists, no daily planning, no AI chat. Local-first and private: no backend, and calendar data is processed on device (Apple Foundation Models where available).

**Status:** app shell and `ImpactKit` package in place; the Impact Engine is next.

## Docs

- [Product](docs/PRODUCT.md): vision, MVP scope, action catalog, open decisions
- [UX](docs/UX.md): screens, card anatomy, system surfaces
- [Architecture](docs/ARCHITECTURE.md): modules, data model, platform constraints
- [Roadmap](docs/ROADMAP.md): steps and status
- [AGENTS.md](AGENTS.md): working rules for coding agents

## Requirements

- Xcode 27, iOS 26.0+ deployment target (proposed)
- Apple Intelligence-capable device for on-device AI features (the app works without them)

## Agent setup

```sh
npx skills experimental_install   # restore upstream skills from skills-lock.json
```

Claude Code offers to install the project plugins (ponytail, pr-review-toolkit) when you trust the folder. See [AGENTS.md](AGENTS.md#working-here) for Codex.

## Contributing

`main` accepts changes only through PRs that pass CI and the agent review gate. Docs-only PRs skip the review gate. Details: [.github/AGENTS.md → Merge policy](.github/AGENTS.md#merge-policy).

## License

Not chosen yet. Until a license is added, all rights are reserved.
