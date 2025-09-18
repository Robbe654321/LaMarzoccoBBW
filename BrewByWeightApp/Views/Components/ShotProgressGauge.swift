import SwiftUI

struct ShotProgressGauge: View {
    let progress: Double
    let status: String
    let currentWeight: String
    let targetWeight: String

    var body: some View {
        VStack(spacing: 16) {
            Text(status)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Gauge(value: progress, in: 0...1) {
                Text("Shot progress")
            } currentValueLabel: {
                Text(currentWeight)
                    .font(.title3)
                    .bold()
            } minimumValueLabel: {
                Text("0 g")
                    .font(.caption)
            } maximumValueLabel: {
                Text(targetWeight)
                    .font(.caption)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .frame(maxWidth: .infinity)

            Text("Target \(targetWeight)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shot progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

#Preview {
    ShotProgressGauge(progress: 0.65, status: "Extracting", currentWeight: "24 g", targetWeight: "36 g")
        .padding()
        .previewLayout(.sizeThatFits)
}
