# ImpactKit

The local Swift package with all app logic and, later, UI features. Why this layout: [docs/ARCHITECTURE.md → Project structure](../docs/ARCHITECTURE.md#project-structure).

## Modules

- Planned modules and when they start: ARCHITECTURE.md → Project structure.
- Add the module to the `ImpactKit` umbrella product's `targets` in `Package.swift`. The app links only that product, so no `project.pbxproj` edit is needed.
- A module depends only on what it uses. `ImpactEngine` imports no UI and no EventKit.
- Every target uses the shared `swiftSettings` in `Package.swift`: approachable-concurrency features, no default `MainActor` isolation.

## Platforms

- The package builds for iOS and macOS so `swift test` runs without a simulator. It compiles every target for macOS, so wrap iOS-only API in `#if os(iOS)`.
- ActivityKit types shared by the app and its extensions go in a package module, inside `#if os(iOS)`.

## Tests

- Swift Testing (`@Test`, `#expect`). Engine tests use synthetic fixtures, never real calendar data.
- Every test target must be listed in `Impact.xcodeproj/xcshareddata/xcschemes/Impact.xcscheme` → Testables, with `BlueprintIdentifier` set to the target name. CI fails until it is. Add, rename, or remove a test target in both `Package.swift` and the scheme.
