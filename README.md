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
| `Workout/` | `SwipeClassifier` (turns a drag into one of the four swipes by distance or flick speed), `SetPrefill` (what the card's reps and weight steppers start at), `RestTimer` (absolute end date, skip, +30s), `CooldownPlayer` (stretch countdown with auto-advance that catches up after the background, pause, skip, back) and `WorkoutSummary`. |
| `PRs/` | `PersonalRecords`: heaviest weight, best Epley e1RM and most reps at a weight, measured against earlier sets, plus the per-set check behind the card's PR badge and the PR timeline. `RecordBook` holds an exercise's current bests, and `ExerciseProgress` turns workouts into chart points (top set and e1RM). |
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

## Workouts

The **Workout** tab shows the active split's next day with **Start workout**, or **Resume** for an
unfinished one (the app also reopens it on launch). A workout runs warmup → lifting → cool-down:

- **Warmup:** pick the cardio (defaults to the day's choice, then the last one used), log the
  duration and an optional distance, or skip.
- **Lifting:** one card per movement slot, in slot order. Drag the top card: → done, ← later,
  ↑ like (the card stays), ↓ equipment unavailable (the slot gets another variation, and the
  equipment is marked at the workout's gym for 7 days). There are no direction labels on the card:
  it moves and tilts with your finger, and right, left and up swipes can be undone from the toolbar.
  Each card shows the exercise's image, last session's sets, today's sets, reps and weight steppers
  prefilled from last time (the weight's + adds 5 lb) and **Log set**; its ⋯ menu has swap variation, like/unlike and never show. A card with sets logged keeps its exercise
  (no down-swipe, swap or hide). **Add exercise** and **Finish lifting** sit under the stack.
- **Rest timer:** logging a set starts a countdown on the card, sized by the exercise's type
  (Settings → Rest timers; defaults 3:00 heavy compound, 2:00 compound, 1:00 isolation), with
  **Skip** and **+30s**. A haptic plays at zero, and a local notification is scheduled for the end
  so it still alerts with the app in the background or the phone locked. The end time is saved on
  the workout, so it survives a relaunch. Notification permission is asked when the first workout
  starts.
- **Cool-down:** the day's stretches one at a time, full screen, with a countdown that moves on by
  itself (with a haptic), plus back, pause and skip. Progress is kept per workout, so a relaunch
  picks up where it was. **Finish workout** or **Skip cool-down** ends the workout.
- **Summary:** duration, exercises, sets, volume and any PRs hit. Finishing moves the split to the
  next day if any set was logged.

`App/Features/Workout/WorkoutFlow.swift` holds every workout action. Each one rebuilds the
`WorkoutStack` from the saved `WorkoutSession`, applies the change and saves straight away, so a
force-quit never loses a set. Schema version 2 (`App/Persistence/SchemaV2.swift`) added each card's
slot movement type so the stack rebuilds exactly; version 1 stores migrate automatically.

## Look (Night Shift)

The app is dark only, with one volt-green accent and condensed heavy type for names and numbers.
The colors, the type helper and the shared button styles live in `App/Theme/NightShift.swift`.

**Exercise images:** each workout card has an image slot at the top (landscape, about 3:2,
cropped to fill). Add a PNG or JPEG named after the exercise's id from `App/Resources/seed.json`,
like `back-squat.png`, to a new `App/Resources/ExerciseImages/` folder and run `xcodegen generate`. Exercises
without an image show a striped placeholder.

## History

The **History** tab lists finished workouts, newest first (date, split day, gym, duration); swipe
to delete one. A workout's detail shows the warmup, every set, the cool-down and the PRs it set.
Tap a set to edit its reps or weight, or swipe to delete it. **Exercises** in the toolbar lists
everything trained.

An exercise's detail (from a workout, the exercises list, or the exercise name on a workout card)
charts top-set weight and estimated 1RM per workout with Swift Charts, and a toggle widens the chart
to every variation of the movement type. It also lists the exercise's records (heaviest weight,
best e1RM, most reps at each weight), its PR history and each workout it was in.

PRs are never stored: they're computed from the logged sets each time, so editing or deleting a set
updates them everywhere. While lifting, the card shows a PR badge as soon as a logged set beats the
exercise's history. `App/Features/History/HistoryData.swift` holds the queries and edits.

## Settings

Besides the library browser, rest timers and gyms, **Settings → Your exercises** has:

- **Liked** and **Hidden exercises**, with Unlike and Unhide.
- **Custom exercises**: name, movement type, exercise type (sets the rest timer), equipment (none
  means bodyweight) and muscles (default: the movement's). Workouts pick them like any library
  exercise. A custom exercise that's in your history can't be deleted; hide it instead.
- **Custom stretches**: a name and default hold, for your own stretch sequences. Deleting one also
  takes it out of those sequences.

`App/Features/Settings/Library/LibraryEditing.swift` holds these edits.

## Accessibility

Every swipe has a VoiceOver action on the card's exercise name (Done, Later, Like, Equipment
unavailable). At the accessibility text sizes the card scrolls, the swipes become buttons under it,
and the weight controls stack. Colors are system colors throughout, so dark mode follows the phone.

## Debug menu

Debug builds (which includes running from Xcode onto a phone) have **Settings → Debug**:
**Generate 6 months of history** adds about four workouts a week over the active split's days (or
push/pull/legs without one), filled by the real selection weighting and with weights creeping up,
to try out charts and selection. Generated workouts have ids starting with `debug-`, and **Remove
generated history** deletes only those. The generator is `PumpedCore`'s `FakeHistory` (tested on
Linux); `App/Features/Settings/Debug` writes it to SwiftData.

## Running on your iPhone

1. In `project.yml` set `DEVELOPMENT_TEAM` to your team id (or pick your team under *Signing &
   Capabilities* after `xcodegen generate`). A free Apple ID works.
2. Plug in the phone, choose it as the run destination and Run. The first time, trust the
   developer on the phone under *Settings → General → VPN & Device Management*, and turn on
   *Developer Mode* if iOS asks.
3. Free provisioning expires after 7 days: re-run from Xcode to re-sign. Your data stays, because
   the store lives on the phone and the bundle id doesn't change. A paid developer account (one
   year) or TestFlight avoids the weekly re-sign.

## CI

GitHub Actions runs the `PumpedCore` tests on Linux and builds the app and runs its unit and
UI tests on an iOS simulator (macOS runner) for every pull request and push to `main`.
