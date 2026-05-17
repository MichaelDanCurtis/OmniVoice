import CoreGraphics

public enum CaptionOverlayPlacement {
    public static let bottomOffset: CGFloat = 72
    public static let caretGap: CGFloat = 20

    public static func defaultOrigin(screenFrame: CGRect, overlaySize: CGSize) -> CGPoint {
        origin(
            forCenter: defaultCenter(screenFrame: screenFrame, overlaySize: overlaySize),
            screenFrame: screenFrame,
            overlaySize: overlaySize
        )
    }

    public static func defaultCenter(screenFrame: CGRect, overlaySize: CGSize) -> CGPoint {
        CGPoint(
            x: screenFrame.midX,
            y: screenFrame.minY + bottomOffset + overlaySize.height / 2
        )
    }

    public static func resolvedOrigin(
        savedOrigin: CGPoint?,
        screenFrame: CGRect,
        overlaySize: CGSize
    ) -> CGPoint {
        let origin = savedOrigin ?? defaultOrigin(screenFrame: screenFrame, overlaySize: overlaySize)
        return clamped(origin: origin, screenFrame: screenFrame, overlaySize: overlaySize)
    }

    public static func resolvedOrigin(
        savedCenter: CGPoint?,
        savedOrigin: CGPoint?,
        screenFrame: CGRect,
        overlaySize: CGSize
    ) -> CGPoint {
        let center = savedCenter
            ?? savedOrigin.map { legacyOrigin in
                CGPoint(
                    x: legacyOrigin.x + overlaySize.width / 2,
                    y: legacyOrigin.y + overlaySize.height / 2
                )
            }
            ?? defaultCenter(screenFrame: screenFrame, overlaySize: overlaySize)

        return origin(forCenter: center, screenFrame: screenFrame, overlaySize: overlaySize)
    }

    public static func origin(
        forCenter center: CGPoint,
        screenFrame: CGRect,
        overlaySize: CGSize
    ) -> CGPoint {
        clamped(
            origin: CGPoint(
                x: center.x - overlaySize.width / 2,
                y: center.y - overlaySize.height / 2
            ),
            screenFrame: screenFrame,
            overlaySize: overlaySize
        )
    }

    public static func caretAnchoredOrigin(
        caretFrame: CGRect,
        screenFrame: CGRect,
        overlaySize: CGSize
    ) -> CGPoint {
        let centeredX = caretFrame.midX - overlaySize.width / 2
        let aboveY = caretFrame.maxY + caretGap
        let belowY = caretFrame.minY - caretGap - overlaySize.height
        let originY = aboveY + overlaySize.height <= screenFrame.maxY ? aboveY : belowY

        return clamped(
            origin: CGPoint(x: centeredX, y: originY),
            screenFrame: screenFrame,
            overlaySize: overlaySize
        )
    }

    public static func clamped(
        origin: CGPoint,
        screenFrame: CGRect,
        overlaySize: CGSize
    ) -> CGPoint {
        let maxX = max(screenFrame.minX, screenFrame.maxX - overlaySize.width)
        let maxY = max(screenFrame.minY, screenFrame.maxY - overlaySize.height)
        return CGPoint(
            x: min(max(origin.x, screenFrame.minX), maxX),
            y: min(max(origin.y, screenFrame.minY), maxY)
        )
    }
}
