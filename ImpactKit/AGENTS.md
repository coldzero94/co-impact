# ImpactKit

The local Swift package with all app logic and, later, UI features. Why this layout: [docs/ARCHITECTURE.md → Project structure](../docs/ARCHITECTURE.md#project-structure).

## Modules

- Planned modules and when they start: ARCHITECTURE.md → Project structure.
- Add the module to the `ImpactKit` umbrella product's `targets` in `Package.swift`. The app links only that product, so no `project.pbxproj` edit is needed.
- A module depends only on what it uses. `ImpactEngine` imports no UI and no EventKit.
- Every target uses the shared `swiftSettings` in `Package.swift`: the app template's upcoming features, without default `MainActor` isolation.

## Platforms

- `swift test` compiles every target for macOS, so wrap iOS-only API in `#if os(iOS)`.
- ActivityKit code goes in the app or the extension.

## UI

- A UI change is done when its simulator screenshots were looked at (light, dark, largest accessibility size), not when it compiles. Build with `-derivedDataPath <dir>` and install `<dir>/Build/Products/Debug-iphonesimulator/Impact.app` (a stale Release build can sit beside it), launch with `xcrun simctl launch`, capture with `xcrun simctl io booted screenshot`, and switch with `xcrun simctl ui booted appearance dark` and `content_size accessibility-extra-extra-extra-large`.
- `-fixtureHour <hour>` (debug builds) sets the sample day's clock, e.g. 8 for a done row and a clock countdown, 19 for the empty state and Tomorrow morning.

## Tests

- Swift Testing (`@Test`, `#expect`). Engine tests use synthetic fixtures, never real calendar data.
- Every test target must be listed in `../Impact.xcodeproj/xcshareddata/xcschemes/Impact.xcscheme` → Testables (`skipped = "NO"`, `ReferencedContainer = "container:ImpactKit"`, `BlueprintIdentifier` = target name). CI fails until it is. Add, rename, or remove a test target in both `Package.swift` and the scheme.
