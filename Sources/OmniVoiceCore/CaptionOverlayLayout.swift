import CoreGraphics

public enum CaptionOverlayLayout {
    public enum LiveElement: Equatable, Sendable {
        case captionText
        case waveformMeter
        case styleLabel
    }

    public static let windowMinWidth: CGFloat = 320
    public static let windowMaxWidth: CGFloat = 760
    public static let captionWidth: CGFloat = 620
    public static let captionLineLimit = 5

    public static let liveStackOrder: [LiveElement] = [
        .captionText,
        .waveformMeter,
        .styleLabel,
    ]
}
