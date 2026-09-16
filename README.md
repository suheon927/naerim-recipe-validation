# Naerim Recipe Validation

[![Swift tests](https://github.com/suheon927/naerim-recipe-validation/actions/workflows/swift.yml/badge.svg)](https://github.com/suheon927/naerim-recipe-validation/actions/workflows/swift.yml)

A small Swift package extracted from the recipe editor in **Naerim**, a coffee journal I independently developed and released.
It demonstrates how I validate quantities, rescale pours, and preserve an unfinished draft when an edit fails.

[Naerim on the App Store](https://apps.apple.com/kr/app/id6808134502) · [Technical case study](https://github.com/suheon927/suheon927/blob/main/docs/naerim.md)

## Run the tests

Use an installed **Swift 6.0 or newer** toolchain. From this directory:

```sh
swift test
```

There are no third-party package dependencies. No Simulator, Apple account, app signing, database, or network service is required.
The test fixtures are small, synthetic values declared in the test file.

To inspect one failure boundary:

```sh
swift test --filter RecipeValidationTests.testDurationOverflowReturnsNilInsteadOfTrapping
```

## The problem

Changing the target water for a recipe is a small UI action with several data constraints:

- A large duration total must not overflow while the editor displays it.
- A non-finite or out-of-range number must not trap during conversion to `Int`.
- Each pour must remain positive after proportional rounding.
- Rounded pours must add up to the requested target at 0.1 g precision.
- Failed validation must preserve the original draft, including its IDs, notes, dose, and timing.
- Editing water should still work before the user fills in a dose or completes the timing.

This package contains that calculation and its boundaries, with the surrounding app removed.

## Example

```swift
import RecipeValidation

let draft = RecipeDraft(
    name: "Example recipe",
    steps: [
        RecipeStep(kind: .pour, durationSeconds: 0, waterGrams: 40),
        RecipeStep(kind: .pour, durationSeconds: 45, waterGrams: 110),
        RecipeStep(kind: .pour, durationSeconds: 30, waterGrams: 150)
    ]
)

let adjusted = try draft.adjustingWater(to: 250)
// adjusted.steps water: [33.3, 91.7, 125.0]
// draft.steps water:    [40.0, 110.0, 150.0]
// Dose remains nil and step durations remain unchanged.
```

The caller explicitly adopts `adjusted` after success. A thrown error leaves `draft` available for correction.

## Implementation choices and costs

| Decision | Why | Cost or boundary |
| --- | --- | --- |
| Checked duration addition | `addingReportingOverflow` handles invalid totals without trapping during display | `nil` means the total is invalid; it does not explain which step needs correction |
| Integer tenths for quantities | Compare and conserve the accepted 0.1 g quantity independently of binary floating-point noise | Finer input precision is rejected; this is a coffee-editor rule, not an arbitrary-precision unit library |
| `Int(exactly:)` at the conversion boundary | `Double(Int.max)` can round beyond the valid integer range | Extremely large values can be rejected even when their rounded display looks valid |
| Decimal proportional calculation | Avoid overflowing an intermediate integer multiplication during scaling | Uses Foundation `Decimal`; the supported input range is still bounded by `Int` and conversion checks |
| Last-pour residual | The final pour receives the remaining tenths so accepted outputs conserve the target | The last pour can differ slightly from its independently rounded proportion; some tiny targets are rejected |
| Return a replacement value | Validate all quantities before the caller replaces its draft | Requires an explicit commit in the UI; it is not a database transaction or concurrency policy |

Only `.pour` steps are scaled. Other step kinds and their metadata remain unchanged.
This calculation runs in O(n) time and uses O(n) temporary storage for the selected pours.

## Tests

The tests exercise observable behavior at the calculation boundary:

- Duration overflow, negative duration, zero-duration drafts, and valid totals.
- NaN, infinities, unsupported precision, integer boundaries, and ordinary floating-point noise.
- Successful scaling without changes to the original draft or unrelated fields.
- Residual distribution: three equal pours scaled to 1 g become **0.3 / 0.3 / 0.4 g**.
- Targets too small to keep each pour positive, invalid source pours, and source-total overflow.
- Conservation, positivity, and stable IDs across **324 deterministic ratio/target combinations**.

The Swift package tests concern this extracted calculation. They do not establish the behavior of a shipped app binary.

**Recorded run, September 17, 2026:** 14 XCTest tests passed with 0 failures using Apple Swift 6.4 on macOS.
The build directory was placed outside a file-synced workspace with:

```sh
swift test --scratch-path /tmp/naerim-recipe-validation-build
```

This avoids a local macOS file-provider issue that added Finder metadata to the generated test bundle and prevented ad-hoc signing.
The package itself does not require a signing identity or any configuration change.

## Source and extraction scope

Adapted from my Naerim application at source revision:

```text
d91e3e7f66691fc65293c173691bc74f8248f0a8
```

Original implementation locations:

- `Naerim/Domain/Recipes/RecipeModels.swift`: `RecipeStep.totalDuration(in:)`.
- `Naerim/Domain/Recipes/RecipeDraft.swift`: `adjustingWater(to:)`, `waterTenths(_:)`, and decimal rounding.
- `NaerimTests/RecipeDraftQuantityTests.swift`: the original quantity-boundary regression cases.

The numeric checks and scaling policy retain the source implementation's behavior.
This extraction adds public initializers, a Swift Package Manager target, independent tests, and documentation.
The models retain only the identity, descriptive fields, dose, and step values needed to demonstrate edit isolation.

The full app also handles recipe revisions, equipment, temperatures, valve guidance, execution timelines, persistence, recovery, localization, and UI state.
Those systems are omitted here, along with all app configuration, assets, credentials, and stored user data.
In particular, a draft that can be rescaled is **not necessarily a valid executable brew plan**: this sample intentionally does not implement the app's `canRun` or timeline validation.
Input parsing and user-facing error presentation are the caller's responsibility.

## Layout

```text
Package.swift
Sources/RecipeValidation/RecipeDraft.swift
Tests/RecipeValidationTests/RecipeValidationTests.swift
```
