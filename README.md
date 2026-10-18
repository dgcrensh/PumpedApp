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

## Workout engine (`PumpedCore`)

| Path | What it is |
|---|---|
| `Selection/` | `VariationSelector` picks an exercise per movement slot (spec §7): filters hidden, gym-unavailable and already-stacked exercises, weights by like/familiarity/repeat damping (all constants in `SelectionTuning`), and falls back to same-muscle substitutes. Takes an injected `RandomNumberGenerator`; `SeededGenerator` makes it deterministic. |
| `Stack/` | `WorkoutStack`, the workout state machine: phases, enforced card order, the four swipes, swap, hide and added slots. A `Codable` value so the app can persist it after every change. |
| `Gyms/` | `EquipmentAvailability` (7-day unavailable-equipment window, reset on re-swipe) and `GymMatcher` (nearest known gym within 150 m). |

## Core logic tests (Mac or Linux)

```sh
swift test --package-path PumpedCore
```

These also validate `App/Resources/seed.json`: every exercise must reference a known movement
type, equipment and muscle groups, and every movement type needs primary muscles and at least
one exercise. `BundledLibraryContentTests` adds coverage checks on the shipped content: 3–6
variations per movement type spread over more than one equipment setup, variations that hit their
movement type's primary muscles, and the Upper/Lower/Full Body stretch sequences.

## Exercise library

`seed.json` is imported into SwiftData on first launch. Every record has a stable string `id`.
To change the library, edit the file and bump its `version`; on next launch the app updates
existing rows by `id` (keeping likes, hidden flags and history) and adds new ones.

Browse the imported library in the app under **Settings → Exercise library** (exercises grouped
by movement type, cardio, stretches and stretch sequences).

## Splits

The **Splits** tab holds the split editor: create, rename, delete and activate splits; add,
remove and reorder days; and, per day, the ordered movement slots (duplicates allowed), the
cool-down stretch sequence and an optional default warmup cardio. Each split shows where its cycle
stands ("Next up: Pull, day 2 of 3") with a picker to skip or repeat a day. Stretch sequences live
there too: the seeded defaults are read-only and can be duplicated into editable copies.

The cycle math (keeping the same day "next up" across edits) and list reordering live in
`PumpedCore/Sources/PumpedCore/Splits` and are tested on Linux.

## CI

GitHub Actions runs the `PumpedCore` tests on Linux and builds the app and runs its unit and
UI tests on an iOS simulator (macOS runner) for every pull request and push to `main`.
