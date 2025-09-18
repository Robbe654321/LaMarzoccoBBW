import SwiftUI
import BrewByWeightCore

struct BrewWarningRow: View {
    let warning: BrewWarning

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warning.iconName)
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(warning.message)
                    .font(.subheadline)
                    .bold()
                if let detail = warning.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        BrewWarningRow(warning: .flowTooLow(current: 1.2))
        BrewWarningRow(warning: .ratioOffTarget(actual: 1.8))
    }
    .padding()
    .previewLayout(.sizeThatFits)
}
