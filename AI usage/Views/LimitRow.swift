import SwiftUI

struct LimitRow: View {
    let limit: UsageLimit
    let isSelected: Bool

    private var displayedFraction: Double {
        guard limit.usedFraction.isFinite else { return 0 }
        return min(max(limit.usedFraction, 0), 1)
    }

    private var percentageText: String {
        "\(Int((displayedFraction * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(limit.name)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(percentageText)
                    .monospacedDigit()

                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(!isSelected)
            }

            ProgressView(value: displayedFraction)
                .progressViewStyle(.linear)

            if let resetsAt = limit.resetsAt {
                Text("Resets \(resetsAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}
