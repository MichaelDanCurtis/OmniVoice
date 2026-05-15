import SwiftUI

struct CaptionOverlayView: View {
    let text: String
    let styleName: String
    let level: Float

    var body: some View {
        VStack(spacing: 6) {
            Text(styleName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(text.isEmpty ? "Listening..." : text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.center)

            HStack(spacing: 3) {
                ForEach(0..<14, id: \.self) { index in
                    Capsule()
                        .fill(index < activeBars ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: 5, height: CGFloat(6 + (index % 5) * 3))
                }
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minWidth: 320, maxWidth: 760)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(radius: 18)
    }

    private var activeBars: Int {
        let normalized = min(max(Double(level) * 45, 0), 1)
        return Int((normalized * 14).rounded(.up))
    }
}
