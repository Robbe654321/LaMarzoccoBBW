# Brew by Weight iOS App

This repository now contains:

- `BrewByWeightCore`: a Swift Package with platform-agnostic brew logic and unit tests.
- `BrewByWeightApp`: SwiftUI views, view models, and assets for the iOS application.
- `arduinoSketchLaMaControl`: the original Arduino sketch.

## Architecture overview

The iOS app is split into a pure Swift core module and a SwiftUI client:

- `BrewByWeightCore` encapsulates brew configuration, telemetry samples, and a state machine that produces user-facing metrics. The library is fully covered by Swift tests that run on Linux, keeping the telemetry logic verifiable in CI.
- `BrewByWeightApp` consumes the core module. `BrewDashboardViewModel` bridges the state machine to the SwiftUI `BrewDashboardView`, while `SettingsViewModel` manages recipe and automation preferences exposed via a `Form` that follows the Apple Human Interface Guidelines.

The dashboard presents live metrics (weight, flow, ratio), a progress gauge, a smoothed flow trend graph, and contextual warnings. The settings screen lets baristas tune brew parameters, flow smoothing, and auto-stop automation while remaining accessible and adaptable to Dynamic Type.

## Running tests

To validate the telemetry logic run:

```bash
swift test
```

The command executes the `BrewByWeightCoreTests` suite which verifies the state machine, warnings, and configuration helpers.

## Next steps

- Integrate hardware telemetry by feeding `BrewSample` instances into `BrewDashboardViewModel.update(with:)`.
- Wire `BrewByWeightApp` into an Xcode project and add app assets such as color sets and icons.
- Extend the settings view with connectivity options once the target hardware is defined.
