import SwiftUI

struct BrewStatusIndicator: View {
    let status: String

    var body: some View {
        Label(status, systemImage: "waveform.path.ecg")
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
    }
}

#Preview {
    BrewStatusIndicator(status: "Extracting")
        .padding()
        .previewLayout(.sizeThatFits)
}
