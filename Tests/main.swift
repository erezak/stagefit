import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
}

func expectFrame(_ actual: CGRect?, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    guard let actual else {
        expect(false, "Expected a fitted rectangle, got nil")
        return
    }
    expect(actual == CGRect(x: x, y: y, width: width, height: height),
           "Unexpected fitted rectangle: \(actual)")
}

// Primary display: AX origin starts at the top-left of the primary screen.
let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
expectFrame(WindowLayout.fittedFrame(
    visibleScreenFrame: visible, primaryScreenTop: 900,
    reservedStripWidth: 190, dockOnLeft: false
), x: 198, y: 8, width: 1234, height: 884)

// Dock on the left => Stage Manager thumbnails on the right.
expectFrame(WindowLayout.fittedFrame(
    visibleScreenFrame: visible, primaryScreenTop: 900,
    reservedStripWidth: 190, dockOnLeft: true
), x: 8, y: 8, width: 1234, height: 884)

// Dock reduces the visible frame; non-primary screens have offset origins.
let secondary = CGRect(x: -1280, y: 30, width: 1280, height: 760)
expectFrame(WindowLayout.fittedFrame(
    visibleScreenFrame: secondary, primaryScreenTop: 900,
    reservedStripWidth: 210, dockOnLeft: false
), x: -1062, y: 118, width: 1054, height: 744)

// Too little space is rejected instead of emitting an unusable rectangle.
expect(WindowLayout.fittedFrame(
    visibleScreenFrame: CGRect(x: 0, y: 0, width: 400, height: 300),
    primaryScreenTop: 300, reservedStripWidth: 190, dockOnLeft: false
) == nil, "Should reject a target narrower than 250 points")
expect(WindowLayout.fittedFrame(
    visibleScreenFrame: CGRect(x: 0, y: 0, width: 1000, height: 180),
    primaryScreenTop: 180, reservedStripWidth: 190, dockOnLeft: false
) == nil, "Should reject a target shorter than 200 points")

expect(WindowLayout.overlapArea(
    CGRect(x: 0, y: 0, width: 100, height: 100),
    CGRect(x: 50, y: 50, width: 100, height: 100)
) == 2500, "Overlap area calculation")
expect(WindowLayout.overlapArea(
    CGRect(x: 0, y: 0, width: 100, height: 100),
    CGRect(x: 101, y: 101, width: 100, height: 100)
) == 0, "Disjoint frames have zero overlap")
// A second activation restores only while the fitted geometry is untouched.
let original = CGRect(x: 55, y: 75, width: 850, height: 615)
let fitted = CGRect(x: 198, y: 8, width: 1234, height: 884)
let snapshot = WindowToggleSnapshot(originalFrame: original, fittedFrame: fitted)
expect(snapshot.restoreFrame(for: fitted) == original,
       "Unchanged fitted window must restore to its original geometry")
expect(snapshot.restoreFrame(for: CGRect(x: 198.3, y: 8, width: 1234, height: 884)) == original,
       "Sub-point Accessibility coordinate jitter is ignored")
expect(snapshot.restoreFrame(for: CGRect(x: 198, y: 8, width: 1190, height: 884)) == nil,
       "Manual width changes must invalidate pending restore")
expect(snapshot.restoreFrame(for: CGRect(x: 198, y: 8, width: 1234, height: 839)) == nil,
       "Manual height changes must invalidate pending restore")
expect(snapshot.restoreFrame(for: CGRect(x: 210, y: 8, width: 1234, height: 884)) == nil,
       "Manual moves must invalidate pending restore")
expect(snapshot.restoreFrame(for: CGRect(x: 198, y: 9, width: 1234, height: 884)) == nil,
       "Even a one-point move must invalidate pending restore")
let newOriginal = CGRect(x: 198, y: 8, width: 1190, height: 884)
let nextSnapshot = WindowToggleSnapshot(originalFrame: newOriginal, fittedFrame: fitted)
expect(nextSnapshot.restoreFrame(for: fitted) == newOriginal,
       "New fit cycle restores the manually adjusted geometry")
let anotherOriginal = CGRect(x: -1000, y: 50, width: 700, height: 510)
let anotherFitted = CGRect(x: -1062, y: 118, width: 1054, height: 744)
let anotherSnapshot = WindowToggleSnapshot(originalFrame: anotherOriginal,
                                            fittedFrame: anotherFitted)
expect(anotherSnapshot.restoreFrame(for: anotherFitted) == anotherOriginal,
       "Another window retains independent restore geometry")
print("All StageFit layout and toggle tests passed")
