import CoreGraphics

public enum CaptionOverlayLayout {
    public enum LiveElement: Equatable, Sendable {
        case translationStatus
        case captionText
        case waveformMeter
        case styleLabel
    }

    public static let windowMinWidth: CGFloat = 320
    public static let windowMaxWidth: CGFloat = 840
    public static let captionWidth: CGFloat = 620
    public static let captionLineLimit = 5
    public static let haloBleedPaddingHorizontal: CGFloat = 44
    public static let haloBleedPaddingVertical: CGFloat = 28

    public static let liveStackOrder: [LiveElement] = [
        .translationStatus,
        .captionText,
        .waveformMeter,
        .styleLabel,
    ]
}
