import SwiftUI
import BrewByWeightCore

struct BrewDashboardView: View {
    @ObservedObject var viewModel: BrewDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShotProgressGauge(
                    progress: viewModel.progress,
                    status: viewModel.statusText,
                    currentWeight: viewModel.beverageWeightText,
                    targetWeight: viewModel.targetWeightText
                )

                metricsSection
                flowSection
                warningsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live metrics")
                .font(.title3)
                .bold()
                .accessibilityAddTraits(.isHeader)

            AdaptiveGrid {
                MetricCard(
                    title: "Beverage",
                    value: viewModel.beverageWeightText,
                    subtitle: "Current weight",
                    systemImage: "scalemass"
                )
                MetricCard(
                    title: "Flow",
                    value: viewModel.flowRateText,
                    subtitle: "Average g/s",
                    systemImage: "drop"
                )
                MetricCard(
                    title: "Ratio",
                    value: viewModel.ratioText,
                    subtitle: "Target \(viewModel.targetWeightText)",
                    systemImage: "divide"
                )
            }
        }
    }

    private var flowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flow trend")
                .font(.title3)
                .bold()
                .accessibilityAddTraits(.isHeader)

            FlowHistoryChart(values: viewModel.flowHistory)
        }
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Guidance")
                .font(.title3)
                .bold()
                .accessibilityAddTraits(.isHeader)

            if viewModel.warnings.isEmpty {
                Label("Brew is tracking on target", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(viewModel.warnings.enumerated()), id: \..offset) { warning in
                        BrewWarningRow(warning: warning.element)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        BrewDashboardView(viewModel: .preview)
            .navigationTitle("Dashboard")
    }
}
