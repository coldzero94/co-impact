# Research: Xcode project structure

Researched 2026-11-08. Goal: choose a project layout that stays easy for agents and CI to change, and that scales to the app, a widget extension, and several feature modules. Applied in [ARCHITECTURE.md → Project structure](../ARCHITECTURE.md#project-structure).

## Findings

| Source | What it shows | What Impact takes |
|--------|---------------|-------------------|
| Apple, *Organizing your code with local packages* | Move code such as logic and utilities into local packages in the same repository | All code in the local package `ImpactKit`; the app target is a thin shell |
| IceCubesApp (Dimillian) | A shipping SwiftUI app split into several local Swift packages, one per area (UI, network, models) | One module per area, added when needed |
| isowords (Point-Free) | Hyper-modularized client; small modules rebuild alone and power fast preview apps | Small modules so a change rebuilds only its module, and previews build fast (step 5) |
| Xcode 16 buildable (synchronized) folders | The project references a directory and syncs its files, so adding files no longer edits `project.pbxproj`; helps agents and CI | App folder is a synchronized folder |
| Xcode 27 app template (read from the installed Xcode) | `SWIFT_APPROACHABLE_CONCURRENCY`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for app targets, `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`, `ENABLE_USER_SCRIPT_SANDBOXING`; `SWIFT_VERSION = 5.0` | Same settings, but Swift 6 language mode |

## Considered and not adopted

| Option | Why not (for now) |
|--------|-------------------|
| Keep only `project.yml` (XcodeGen) or a Tuist manifest, generate the project | Adds a tool to every machine and CI, and Xcode GUI edits get overwritten on regeneration. With synchronized folders the committed project rarely changes. Revisit when extensions and capabilities make project edits frequent (step 9) |
| One app target holding all code | Every change rebuilds the app, previews get slow, and the engine can only be tested through the simulator |
| Many modules up front | Modules without code are speculative; each is added when its roadmap step starts |

## Sources

- Apple, Organizing your code with local packages: https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages
- IceCubesApp: https://github.com/Dimillian/IceCubesApp
- isowords: https://github.com/pointfreeco/isowords
- Point-Free, Modularization (episode 172): https://www.pointfree.co/episodes/ep172-modularization-part-2
- Tuist changelog, buildable folders (on Xcode 16 synchronized groups): https://tuist.dev/changelog/2025.08.11-buildable-folders
- Xcode 27 project templates: `Xcode.app/Contents/Developer/Library/Xcode/Templates/Project Templates/Base/`
