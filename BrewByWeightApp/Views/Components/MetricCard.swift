import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title)
                .bold()
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MetricCard(title: "Beverage", value: "36 g", subtitle: "Current weight", systemImage: "scalemass")
        .padding()
        .previewLayout(.sizeThatFits)
}
