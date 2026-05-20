import CoreGraphics
import XCTest
@testable import OmniVoiceCore

final class CaptionOverlayPlacementTests: XCTestCase {
    func testDefaultOriginCentersOverlayNearBottomOfVisibleScreen() {
        let origin = CaptionOverlayPlacement.defaultOrigin(
            screenFrame: CGRect(x: 0, y: 40, width: 1440, height: 860),
            overlaySize: CGSize(width: 420, height: 80)
        )

        XCTAssertEqual(origin, CGPoint(x: 510, y: 112))
    }

    func testSavedOriginIsClampedInsideVisibleScreen() {
        let origin = CaptionOverlayPlacement.resolvedOrigin(
            savedOrigin: CGPoint(x: 1800, y: -120),
            screenFrame: CGRect(x: 0, y: 40, width: 1440, height: 860),
            overlaySize: CGSize(width: 420, height: 80)
        )

        XCTAssertEqual(origin, CGPoint(x: 1020, y: 40))
    }

    func testSavedCenterKeepsOverlayCenteredWhenSizeChanges() {
        let screenFrame = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let center = CGPoint(x: 720, y: 160)

        let narrowOrigin = CaptionOverlayPlacement.resolvedOrigin(
            savedCenter: center,
            savedOrigin: nil,
            screenFrame: screenFrame,
            overlaySize: CGSize(width: 320, height: 80)
        )
        let wideOrigin = CaptionOverlayPlacement.resolvedOrigin(
            savedCenter: center,
            savedOrigin: nil,
            screenFrame: screenFrame,
            overlaySize: CGSize(width: 760, height: 80)
        )

        XCTAssertEqual(narrowOrigin, CGPoint(x: 560, y: 120))
        XCTAssertEqual(wideOrigin, CGPoint(x: 340, y: 120))
    }

    func testSavedCenterIsClampedInsideVisibleScreen() {
        let origin = CaptionOverlayPlacement.resolvedOrigin(
            savedCenter: CGPoint(x: 1800, y: -120),
            savedOrigin: nil,
            screenFrame: CGRect(x: 0, y: 40, width: 1440, height: 860),
            overlaySize: CGSize(width: 420, height: 80)
        )

        XCTAssertEqual(origin, CGPoint(x: 1020, y: 40))
    }

    func testCaretAnchoredOriginPlacesOverlayAboveCaretWhenSpaceAllows() {
        let origin = CaptionOverlayPlacement.caretAnchoredOrigin(
            caretFrame: CGRect(x: 640, y: 420, width: 2, height: 20),
            screenFrame: CGRect(x: 0, y: 40, width: 1440, height: 860),
            overlaySize: CGSize(width: 420, height: 96)
        )

        XCTAssertEqual(origin, CGPoint(x: 431, y: 460))
    }

    func testCaretAnchoredOriginPlacesOverlayBelowCaretNearTopOfScreen() {
        let origin = CaptionOverlayPlacement.caretAnchoredOrigin(
            caretFrame: CGRect(x: 640, y: 792, width: 2, height: 20),
            screenFrame: CGRect(x: 0, y: 40, width: 1440, height: 860),
            overlaySize: CGSize(width: 420, height: 96)
        )

        XCTAssertEqual(origin, CGPoint(x: 431, y: 676))
    }
}
