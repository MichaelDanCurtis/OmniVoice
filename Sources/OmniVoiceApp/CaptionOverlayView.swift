import SwiftUI

struct CaptionOverlayView: View {
    let text: String
    let styleName: String
    let level: Float

    var body: some View {
        VStack(spacing: 7) {
            Text(styleName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.56))

            Text(text.isEmpty ? "Listening..." : text)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.10))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)

            HStack(spacing: 3) {
                ForEach(0..<14, id: \.self) { index in
                    Capsule()
                        .fill(index < activeBars ? Color.accentColor.opacity(0.78) : Color.white.opacity(0.10))
                        .frame(width: 5, height: CGFloat(6 + (index % 5) * 3))
                }
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minWidth: 320, maxWidth: 760)
    }

    private var activeBars: Int {
        let normalized = min(max(Double(level) * 45, 0), 1)
        return Int((normalized * 14).rounded(.up))
    }
}
