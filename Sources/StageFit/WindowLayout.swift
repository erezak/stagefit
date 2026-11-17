import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Pure coordinate and sizing calculations used by WindowFitter.
/// AX coordinates are top-left-based; AppKit screen coordinates are bottom-left-based.
enum WindowLayout {
    static func toAXCoordinates(_ cocoa: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(
            x: cocoa.minX,
            y: primaryScreenTop - cocoa.maxY,
            width: cocoa.width,
            height: cocoa.height
        )
    }

    /// Returns nil when a usable window would not fit beside the reserved strip.
    /// When the Dock is on the left, Stage Manager appears on the right.
    static func fittedFrame(
        visibleScreenFrame: CGRect,
        primaryScreenTop: CGFloat,
        reservedStripWidth: CGFloat,
        dockOnLeft: Bool,
        edgeGap: CGFloat = 8
    ) -> CGRect? {
        var target = toAXCoordinates(visibleScreenFrame, primaryScreenTop: primaryScreenTop)
            .insetBy(dx: edgeGap, dy: edgeGap)

        if dockOnLeft {
            target.size.width -= reservedStripWidth
        } else {
            target.origin.x += reservedStripWidth
            target.size.width -= reservedStripWidth
        }

        return target.width >= 250 && target.height >= 200 ? target : nil
    }

    static func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : max(0, intersection.width) * max(0, intersection.height)
    }
}
