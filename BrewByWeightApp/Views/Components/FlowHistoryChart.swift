import SwiftUI

struct FlowHistoryChart: View {
    let values: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if values.isEmpty {
                Text("Waiting for flow data")
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .foregroundStyle(.secondary)
            } else {
                GeometryReader { geometry in
                    let minValue = values.min() ?? 0
                    let maxValue = values.max() ?? 0
                    let span = max(maxValue - minValue, 0.1)
                    let step = geometry.size.width / CGFloat(max(values.count - 1, 1))

                    Path { path in
                        for index in values.indices {
                            let normalized = (values[index] - minValue) / span
                            let x = CGFloat(index) * step
                            let y = (1 - normalized) * geometry.size.height
                            let point = CGPoint(x: x, y: y)

                            if index == values.startIndex {
                                path.move(to: point)
                            } else {
                                path.addLine(to: point)
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(colors: [.accentColor, .mint], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .animation(.easeInOut(duration: 0.3), value: values)
                }
                .frame(height: 140)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flow trend")
        .accessibilityValue(flowAccessibilityValue)
    }

    private var flowAccessibilityValue: String {
        guard let latest = values.last else { return "No data" }
        return String(format: "Last reading %.1f grams per second", latest)
    }
}

#Preview {
    FlowHistoryChart(values: stride(from: 1.2, through: 3.0, by: 0.2).map { $0 })
        .padding()
        .previewLayout(.sizeThatFits)
}
