import Testing
@testable import BrewByWeightCore

@Test("Brew ratio is derived from configuration")
func brewRatioCalculation() async throws {
    let configuration = BrewConfiguration(
        targetBeverageWeight: 42,
        coffeeDose: 18,
        preinfusionTime: 8,
        targetFlowRate: 2.6,
        autoStopMargin: 1.2,
        minimumShotTime: 22
    )

    #expect(configuration.isValid())
    #expect(configuration.brewRatio == 42.0 / 18.0)
}

@Test("Auto-stop is recommended near the target weight once minimum time elapsed")
func autoStopRecommendation() async throws {
    let configuration = BrewConfiguration(
        targetBeverageWeight: 36,
        coffeeDose: 18,
        preinfusionTime: 7,
        targetFlowRate: 2.4,
        autoStopMargin: 1.5,
        minimumShotTime: 20
    )

    var machine = BrewStateMachine(configuration: configuration)
    _ = machine.evaluate(with: BrewSample(elapsedTime: 10, beverageWeight: 15, flowRate: 2.6))
    let state = machine.evaluate(with: BrewSample(elapsedTime: 24, beverageWeight: 35, flowRate: 2.2))

    #expect(state.phase == .finishing)
    #expect(state.isAutoStopRecommended)
}

@Test("Flow warnings are produced when the shot drifts off target")
func flowWarnings() async throws {
    let configuration = BrewConfiguration(
        targetBeverageWeight: 40,
        coffeeDose: 18,
        preinfusionTime: 6,
        targetFlowRate: 2.8,
        autoStopMargin: 1,
        minimumShotTime: 18
    )

    var machine = BrewStateMachine(configuration: configuration)
    _ = machine.evaluate(with: BrewSample(elapsedTime: 8, beverageWeight: 10, flowRate: 1.2))
    _ = machine.evaluate(with: BrewSample(elapsedTime: 12, beverageWeight: 16, flowRate: 1.3))
    let state = machine.evaluate(with: BrewSample(elapsedTime: 16, beverageWeight: 22, flowRate: 1.1))

    let hasFlowWarning = state.warnings.contains { warning in
        if case .flowTooLow = warning { return true }
        return false
    }

    #expect(hasFlowWarning)
}

@Test("Long running shots trigger a warning before completion")
func longRunningShotWarning() async throws {
    let configuration = BrewConfiguration(
        targetBeverageWeight: 38,
        coffeeDose: 19,
        preinfusionTime: 5,
        targetFlowRate: 2.8,
        autoStopMargin: 1.5,
        minimumShotTime: 20
    )

    var machine = BrewStateMachine(configuration: configuration)
    _ = machine.evaluate(with: BrewSample(elapsedTime: 4, beverageWeight: 2, flowRate: 0.5))
    _ = machine.evaluate(with: BrewSample(elapsedTime: 10, beverageWeight: 12, flowRate: 2.3))
    let state = machine.evaluate(with: BrewSample(elapsedTime: 28, beverageWeight: 32, flowRate: 2.0))

    let hasLongShotWarning = state.warnings.contains { warning in
        if case .shotRunningLong = warning { return true }
        return false
    }

    #expect(hasLongShotWarning)
}
