# Pumped

A personal iOS workout app built around a swipeable card stack. See the product spec and
implementation plan in the project's `spec/` folder.

## Layout

| Path | What it is |
|---|---|
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated from it and not checked in. |
| `App/` | The iOS app target (SwiftUI + SwiftData). |
| `App/Persistence/` | Versioned SwiftData schema, migration plan and the seed importer. |
| `App/Resources/seed.json` | The bundled exercise library. |
| `PumpedCore/` | Swift package with the app's pure logic. No UIKit/SwiftUI, so it builds and tests on Linux. |
| `PumpedTests/`, `PumpedUITests/` | App-level unit tests and UI tests (run on a Mac). |

## Building the app (Mac)

Requires Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Pumped.xcodeproj
```

Pick the **Pumped** scheme and an iPhone simulator, then Run (⌘R). To run on your phone,
choose your team under *Signing & Capabilities* (or set `DEVELOPMENT_TEAM` in `project.yml`).

Re-run `xcodegen generate` whenever files are added or removed or `project.yml` changes.

Run all app tests from Xcode with ⌘U, or from the command line:

```sh
xcodebuild test -project Pumped.xcodeproj -scheme Pumped \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Core logic tests (Mac or Linux)

```sh
swift test --package-path PumpedCore
```

These also validate `App/Resources/seed.json`: every exercise must reference a known movement
type, equipment and muscle groups, and every movement type needs primary muscles and at least
one exercise.

## Exercise library

`seed.json` is imported into SwiftData on first launch. Every record has a stable string `id`.
To change the library, edit the file and bump its `version`; on next launch the app updates
existing rows by `id` (keeping likes, hidden flags and history) and adds new ones.

## CI

GitHub Actions runs the `PumpedCore` tests on Linux and builds the app and runs its unit and
UI tests on an iOS simulator (macOS runner) for every pull request and push to `main`.
