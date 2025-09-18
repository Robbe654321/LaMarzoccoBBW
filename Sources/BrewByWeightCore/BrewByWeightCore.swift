import Foundation

/// Represents the configurable parameters for a brew-by-weight espresso shot.
public struct BrewConfiguration: Equatable, Codable {
    public var targetBeverageWeight: Double
    public var coffeeDose: Double
    public var preinfusionTime: TimeInterval
    public var targetFlowRate: Double
    public var autoStopMargin: Double
    public var minimumShotTime: TimeInterval

    /// Creates a new configuration with sensible defaults.
    public init(
        targetBeverageWeight: Double = 36,
        coffeeDose: Double = 18,
        preinfusionTime: TimeInterval = 7,
        targetFlowRate: Double = 2.5,
        autoStopMargin: Double = 1.5,
        minimumShotTime: TimeInterval = 20
    ) {
        self.targetBeverageWeight = targetBeverageWeight
        self.coffeeDose = coffeeDose
        self.preinfusionTime = preinfusionTime
        self.targetFlowRate = targetFlowRate
        self.autoStopMargin = autoStopMargin
        self.minimumShotTime = minimumShotTime
    }

    /// Returns the brew ratio expressed as beverage weight divided by coffee dose.
    public var brewRatio: Double {
        guard coffeeDose > 0 else { return 0 }
        return targetBeverageWeight / coffeeDose
    }

    /// Validates the configuration.
    public func isValid() -> Bool {
        guard targetBeverageWeight > 0, coffeeDose > 0 else { return false }
        guard preinfusionTime >= 0, targetFlowRate > 0 else { return false }
        guard autoStopMargin >= 0, minimumShotTime >= 0 else { return false }
        return true
    }
}

/// Represents a telemetry sample collected during the brew.
public struct BrewSample: Equatable {
    public var elapsedTime: TimeInterval
    public var beverageWeight: Double
    public var flowRate: Double

    public init(elapsedTime: TimeInterval, beverageWeight: Double, flowRate: Double) {
        self.elapsedTime = elapsedTime
        self.beverageWeight = beverageWeight
        self.flowRate = flowRate
    }
}

/// High level phases for a brew.
public enum BrewPhase: String, Codable {
    case idle
    case preinfusion
    case extraction
    case finishing
    case completed
}

/// Contextual warnings the UI can surface to the barista.
public enum BrewWarning: Equatable {
    case flowTooLow(current: Double)
    case flowTooHigh(current: Double)
    case ratioOffTarget(actual: Double)
    case shotRunningLong
}

/// Aggregates derived metrics about the current brew state.
public struct BrewState: Equatable {
    public let configuration: BrewConfiguration
    public let sample: BrewSample
    public let phase: BrewPhase
    public let progress: Double
    public let isAutoStopRecommended: Bool
    public let averageFlowRate: Double
    public let brewRatio: Double
    public let warnings: [BrewWarning]
}

/// Evaluates incoming samples and produces a user facing state model.
public struct BrewStateMachine {
    private let configuration: BrewConfiguration
    private let smoothingWindow: Int
    private var samples: [BrewSample] = []

    public init(configuration: BrewConfiguration, smoothingWindow: Int = 5) {
        precondition(configuration.isValid(), "Invalid brew configuration supplied")
        precondition(smoothingWindow > 0, "Smoothing window must be positive")
        self.configuration = configuration
        self.smoothingWindow = smoothingWindow
    }

    /// Consumes a sample and produces the latest brew state snapshot.
    public mutating func evaluate(with sample: BrewSample) -> BrewState {
        append(sample)

        let averageFlow = averageFlowRate()
        let ratio = currentBrewRatio()
        let phase = currentPhase(for: sample)
        let progress = min(max(sample.beverageWeight / max(configuration.targetBeverageWeight, 0.1), 0), 1)
        let shouldStop = shouldAutoStop(for: sample)
        let warnings = evaluateWarnings(
            sample: sample,
            averageFlow: averageFlow,
            ratio: ratio,
            phase: phase
        )

        return BrewState(
            configuration: configuration,
            sample: sample,
            phase: phase,
            progress: progress,
            isAutoStopRecommended: shouldStop,
            averageFlowRate: averageFlow,
            brewRatio: ratio,
            warnings: warnings
        )
    }

    // MARK: - Private helpers

    private mutating func append(_ sample: BrewSample) {
        samples.append(sample)
        if samples.count > smoothingWindow {
            samples.removeFirst(samples.count - smoothingWindow)
        }
    }

    private func averageFlowRate() -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0) { $0 + max(0, $1.flowRate) }
        return sum / Double(samples.count)
    }

    private func currentBrewRatio() -> Double {
        guard let latest = samples.last else { return 0 }
        guard configuration.coffeeDose > 0 else { return 0 }
        return latest.beverageWeight / configuration.coffeeDose
    }

    private func currentPhase(for sample: BrewSample) -> BrewPhase {
        if sample.elapsedTime <= 0.1 {
            return .idle
        }

        if sample.elapsedTime < configuration.preinfusionTime {
            return .preinfusion
        }

        if sample.beverageWeight < configuration.targetBeverageWeight - configuration.autoStopMargin {
            return .extraction
        }

        if sample.beverageWeight < configuration.targetBeverageWeight {
            return .finishing
        }

        return .completed
    }

    private func shouldAutoStop(for sample: BrewSample) -> Bool {
        guard sample.elapsedTime >= configuration.minimumShotTime else { return false }
        return sample.beverageWeight >= configuration.targetBeverageWeight - configuration.autoStopMargin
    }

    private func evaluateWarnings(
        sample: BrewSample,
        averageFlow: Double,
        ratio: Double,
        phase: BrewPhase
    ) -> [BrewWarning] {
        var warnings: [BrewWarning] = []

        if phase == .extraction {
            let lowerBound = configuration.targetFlowRate * 0.7
            let upperBound = configuration.targetFlowRate * 1.3
            if averageFlow > 0, averageFlow < lowerBound {
                warnings.append(.flowTooLow(current: averageFlow))
            } else if averageFlow > upperBound {
                warnings.append(.flowTooHigh(current: averageFlow))
            }
        }

        let ratioLowerBound = configuration.brewRatio * 0.9
        let ratioUpperBound = configuration.brewRatio * 1.1
        if ratio > 0, (ratio < ratioLowerBound || ratio > ratioUpperBound) {
            warnings.append(.ratioOffTarget(actual: ratio))
        }

        let expectedCompletionTime = max(
            configuration.minimumShotTime,
            configuration.preinfusionTime + (configuration.targetBeverageWeight / max(configuration.targetFlowRate, 0.1))
        )
        if phase != .completed, sample.elapsedTime > expectedCompletionTime * 1.2 {
            warnings.append(.shotRunningLong)
        }

        return warnings
    }
}
