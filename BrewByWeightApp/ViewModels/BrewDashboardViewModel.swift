import Combine
import Foundation
import BrewByWeightCore

@MainActor
final class BrewDashboardViewModel: ObservableObject {
    @Published private(set) var brewState: BrewState?
    @Published private(set) var flowHistory: [Double] = []

    private var stateMachine: BrewStateMachine?
    private var cancellables: Set<AnyCancellable> = []

    private let weightFormatter: MeasurementFormatter
    private let ratioFormatter: NumberFormatter

    init() {
        weightFormatter = MeasurementFormatter()
        weightFormatter.unitOptions = .providedUnit
        weightFormatter.unitStyle = .medium

        ratioFormatter = NumberFormatter()
        ratioFormatter.maximumFractionDigits = 2
        ratioFormatter.minimumFractionDigits = 0
    }

    func bind(to settings: SettingsViewModel) {
        cancellables.removeAll()

        Publishers.CombineLatest(settings.$configuration, settings.$smoothingWindow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] configuration, smoothingWindow in
                guard let self else { return }
                self.stateMachine = BrewStateMachine(
                    configuration: configuration,
                    smoothingWindow: max(1, smoothingWindow)
                )
                self.brewState = nil
                self.flowHistory.removeAll()
            }
            .store(in: &cancellables)

    }

    func resetState() {
        brewState = nil
        flowHistory.removeAll()
    }

    func update(with sample: BrewSample) {
        guard var machine = stateMachine else { return }
        let state = machine.evaluate(with: sample)
        stateMachine = machine
        brewState = state

        flowHistory.append(state.averageFlowRate)
        if flowHistory.count > 30 {
            flowHistory.removeFirst(flowHistory.count - 30)
        }
    }

    var statusText: String {
        guard let state = brewState else { return "Ready" }
        switch state.phase {
        case .idle: return "Ready"
        case .preinfusion: return "Preinfusion"
        case .extraction: return "Extracting"
        case .finishing: return state.isAutoStopRecommended ? "Auto stop" : "Finishing"
        case .completed: return "Completed"
        }
    }

    var beverageWeightText: String {
        guard let weight = brewState?.sample.beverageWeight else { return "--" }
        let measurement = Measurement(value: weight, unit: UnitMass.grams)
        return weightFormatter.string(from: measurement)
    }

    var targetWeightText: String {
        guard let target = brewState?.configuration.targetBeverageWeight else { return "--" }
        let measurement = Measurement(value: target, unit: UnitMass.grams)
        return weightFormatter.string(from: measurement)
    }

    var flowRateText: String {
        guard let flow = brewState?.averageFlowRate else { return "--" }
        return String(format: "%.1f g/s", flow)
    }

    var ratioText: String {
        guard let ratio = brewState?.brewRatio else { return "--" }
        return ratioFormatter.string(from: NSNumber(value: ratio)) ?? "--"
    }

    var progress: Double {
        brewState?.progress ?? 0
    }

    var warnings: [BrewWarning] {
        brewState?.warnings ?? []
    }
}

#if DEBUG
extension BrewDashboardViewModel {
    static let preview: BrewDashboardViewModel = {
        let viewModel = BrewDashboardViewModel()
        let configuration = BrewConfiguration(
            targetBeverageWeight: 38,
            coffeeDose: 19,
            preinfusionTime: 7,
            targetFlowRate: 2.4,
            autoStopMargin: 1.5,
            minimumShotTime: 20
        )
        let settings = SettingsViewModel(configuration: configuration)
        viewModel.bind(to: settings)

        let samples: [BrewSample] = stride(from: 0.0, through: 27.0, by: 3).enumerated().map { index, time in
            let weight = min(Double(index) * 4.5, configuration.targetBeverageWeight - 0.5)
            let flow = Double.random(in: 1.8...2.9)
            return BrewSample(elapsedTime: time, beverageWeight: weight, flowRate: flow)
        }

        samples.forEach { viewModel.update(with: $0) }
        return viewModel
    }()
}
#endif
