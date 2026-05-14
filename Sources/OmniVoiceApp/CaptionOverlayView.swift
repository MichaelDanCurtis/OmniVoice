import SwiftUI

struct CaptionOverlayView: View {
    let text: String
    let styleName: String

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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minWidth: 320, maxWidth: 760)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(radius: 18)
    }
}
