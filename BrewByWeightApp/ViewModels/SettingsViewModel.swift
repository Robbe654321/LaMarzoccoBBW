import Foundation
import SwiftUI
import BrewByWeightCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var configuration: BrewConfiguration
    @Published var isAutoStopEnabled: Bool
    @Published var smoothingWindow: Int

    let targetWeightRange: ClosedRange<Double> = 10...70
    let coffeeDoseRange: ClosedRange<Double> = 10...25
    let flowRateRange: ClosedRange<Double> = 0.5...5
    let autoStopMarginRange: ClosedRange<Double> = 0...5

    private let ratioFormatter: NumberFormatter
    private let decimalFormatter: NumberFormatter

    init(configuration: BrewConfiguration = BrewConfiguration(), smoothingWindow: Int = 5) {
        self.configuration = configuration
        self.isAutoStopEnabled = configuration.autoStopMargin > 0
        self.smoothingWindow = smoothingWindow

        ratioFormatter = NumberFormatter()
        ratioFormatter.maximumFractionDigits = 2
        ratioFormatter.minimumFractionDigits = 0

        decimalFormatter = NumberFormatter()
        decimalFormatter.maximumFractionDigits = 1
        decimalFormatter.minimumFractionDigits = 0
    }

    var formattedBrewRatio: String {
        ratioFormatter.string(from: NSNumber(value: configuration.brewRatio)) ?? "--"
    }

    var formattedFlowRate: String {
        decimalFormatter.string(from: NSNumber(value: configuration.targetFlowRate)) ?? "--"
    }

    var isConfigurationValid: Bool {
        configuration.isValid() && smoothingWindow > 0
    }

    func updateTargetWeight(_ value: Double) {
        configuration.targetBeverageWeight = value
    }

    func updateCoffeeDose(_ value: Double) {
        configuration.coffeeDose = value
    }

    func updatePreinfusionTime(_ value: Double) {
        configuration.preinfusionTime = value
    }

    func updateFlowRate(_ value: Double) {
        configuration.targetFlowRate = value
    }

    func updateAutoStop(enabled: Bool) {
        isAutoStopEnabled = enabled
        if enabled && configuration.autoStopMargin == 0 {
            configuration.autoStopMargin = 1
        } else if !enabled {
            configuration.autoStopMargin = 0
        }
    }

    func updateAutoStopMargin(_ value: Double) {
        configuration.autoStopMargin = value
        isAutoStopEnabled = value > 0
    }

    func updateMinimumShotTime(_ value: Double) {
        configuration.minimumShotTime = value
    }

    func resetToDefaults() {
        configuration = BrewConfiguration()
        isAutoStopEnabled = configuration.autoStopMargin > 0
        smoothingWindow = 5
    }
}
