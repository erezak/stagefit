import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The original frame and the actual frame StageFit applied to one window.
/// A pending restore is valid only while the current frame remains unchanged.
struct WindowToggleSnapshot {
    let originalFrame: CGRect
    let fittedFrame: CGRect

    func restoreFrame(for currentFrame: CGRect) -> CGRect? {
        // Fractional point conversion may have sub-point differences; a user
        // move/resize of at least one point invalidates the saved frame.
        let tolerance: CGFloat = 0.5
        let unchanged = abs(currentFrame.minX - fittedFrame.minX) <= tolerance
            && abs(currentFrame.minY - fittedFrame.minY) <= tolerance
            && abs(currentFrame.width - fittedFrame.width) <= tolerance
            && abs(currentFrame.height - fittedFrame.height) <= tolerance
        return unchanged ? originalFrame : nil
    }
}
