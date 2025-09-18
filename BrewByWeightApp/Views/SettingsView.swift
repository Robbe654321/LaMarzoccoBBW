import SwiftUI
import BrewByWeightCore

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("Recipe") {
                Stepper(value: binding(
                    get: { viewModel.configuration.targetBeverageWeight },
                    set: viewModel.updateTargetWeight
                ), in: viewModel.targetWeightRange, step: 0.5) {
                    settingRow(title: "Target beverage", value: formatted(viewModel.configuration.targetBeverageWeight, suffix: "g"))
                }

                Stepper(value: binding(
                    get: { viewModel.configuration.coffeeDose },
                    set: viewModel.updateCoffeeDose
                ), in: viewModel.coffeeDoseRange, step: 0.5) {
                    settingRow(title: "Coffee dose", value: formatted(viewModel.configuration.coffeeDose, suffix: "g"))
                }

                LabeledContent("Brew ratio", value: viewModel.formattedBrewRatio)
            } footer: {
                Text("Adjust the recipe to match your beans and machine calibration.")
            }

            Section("Flow control") {
                Stepper(value: binding(
                    get: { viewModel.configuration.preinfusionTime },
                    set: viewModel.updatePreinfusionTime
                ), in: 0...15, step: 0.5) {
                    settingRow(title: "Preinfusion", value: formatted(viewModel.configuration.preinfusionTime, suffix: "s"))
                }

                Stepper(value: binding(
                    get: { viewModel.configuration.targetFlowRate },
                    set: viewModel.updateFlowRate
                ), in: viewModel.flowRateRange, step: 0.1) {
                    settingRow(title: "Target flow", value: "\(viewModel.formattedFlowRate) g/s")
                }

                Stepper(value: binding(
                    get: { Double(viewModel.smoothingWindow) },
                    set: { viewModel.smoothingWindow = Int($0.rounded()) }
                ), in: 1...15, step: 1) {
                    settingRow(title: "Smoothing window", value: "\(viewModel.smoothingWindow) samples")
                }
            } footer: {
                Text("Flow smoothing stabilizes the live graph when using noisy scales.")
            }

            Section("Automation") {
                Toggle(isOn: binding(
                    get: { viewModel.isAutoStopEnabled },
                    set: viewModel.updateAutoStop
                )) {
                    Text("Auto-stop near target")
                }

                Stepper(value: binding(
                    get: { viewModel.configuration.autoStopMargin },
                    set: viewModel.updateAutoStopMargin
                ), in: viewModel.autoStopMarginRange, step: 0.1) {
                    settingRow(title: "Stop margin", value: formatted(viewModel.configuration.autoStopMargin, suffix: "g"))
                }
                .disabled(!viewModel.isAutoStopEnabled)

                Stepper(value: binding(
                    get: { viewModel.configuration.minimumShotTime },
                    set: viewModel.updateMinimumShotTime
                ), in: 0...60, step: 1) {
                    settingRow(title: "Minimum shot time", value: formatted(viewModel.configuration.minimumShotTime, suffix: "s"))
                }
            } footer: {
                Text("Auto-stop ensures consistency while respecting a minimum extraction time.")
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Text("Reset to defaults")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset settings?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                viewModel.resetToDefaults()
            }
        } message: {
            Text("All customizations will be replaced with the recommended defaults.")
        }
    }

    private func settingRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private func formatted(_ value: Double, suffix: String) -> String {
        String(format: "%.1f %@", value, suffix)
    }

    private func binding<T>(get: @escaping () -> T, set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: set)
    }
}

#Preview {
    NavigationStack {
        SettingsView(viewModel: SettingsViewModel())
            .navigationTitle("Settings")
    }
}
