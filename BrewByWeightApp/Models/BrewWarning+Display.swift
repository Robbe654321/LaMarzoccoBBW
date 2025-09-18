import Foundation
import BrewByWeightCore

extension BrewWarning {
    var message: String {
        switch self {
        case .flowTooLow:
            return "Increase flow"
        case .flowTooHigh:
            return "Reduce flow"
        case .ratioOffTarget:
            return "Check brew ratio"
        case .shotRunningLong:
            return "Shot running long"
        }
    }

    var detail: String? {
        switch self {
        case let .flowTooLow(current):
            return String(format: "Average flow %.1f g/s", current)
        case let .flowTooHigh(current):
            return String(format: "Average flow %.1f g/s", current)
        case let .ratioOffTarget(actual):
            return String(format: "Current ratio %.2f", actual)
        case .shotRunningLong:
            return "Consider stopping the shot to avoid over-extraction."
        }
    }

    var iconName: String {
        switch self {
        case .flowTooLow:
            return "arrow.down"
        case .flowTooHigh:
            return "arrow.up"
        case .ratioOffTarget:
            return "scale.3d"
        case .shotRunningLong:
            return "timer"
        }
    }
}
