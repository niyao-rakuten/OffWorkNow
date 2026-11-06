import AppKit
import ScreenCaptureKit

// The controller's icon helper is unrelated to these headless permission-flow tests.
@MainActor enum PetArtwork {
    static func trimTransparentMargin(_ image: CGImage) -> CGImage { image }
}

@main struct PermissionFlowRegression {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--window-lifecycle") {
            await verifyWindowLifecycle()
            return
        }
        let denied = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        precondition(ScreenshotController.isPermissionDenied(denied))
        precondition(!ScreenshotController.isPermissionDenied(NSError(domain: "Other", code: denied.code)))
        precondition(!ScreenshotController.isPermissionDenied(NSError(domain: SCStreamErrorDomain, code: -3805)))

        var attempts = 0
        var received: CheckedContinuation<Error, Never>?
        let controller = ScreenshotController(captureScreens: {
            attempts += 1
            switch attempts {
            case 1: throw denied
            case 2: return []
            default: throw NSError(domain: "CaptureTransport", code: 7)
            }
        }, failureHandler: { error in
            let callback = received
            received = nil
            callback?.resume(returning: error)
        })

        // An explicit click must reach the actual capture provider; repeated clicks
        // during consent/capture must not launch another request or dialog.
        let first = await withCheckedContinuation { callback in
            received = callback
            controller.start()
            controller.start()
        }
        precondition(attempts == 1)
        precondition(ScreenshotController.isPermissionDenied(first))
        for _ in 0..<10 { await Task.yield() }
        precondition(attempts == 1, "A denial must not cause automatic permission retries")

        // After a failed attempt, another explicit click is allowed (for example,
        // after returning from Settings). No-display errors aren't permission errors.
        let second = await withCheckedContinuation { callback in
            received = callback
            controller.start()
        }
        precondition(attempts == 2)
        precondition(!ScreenshotController.isPermissionDenied(second))

        let third = await withCheckedContinuation { callback in
            received = callback
            controller.start()
        }
        precondition(attempts == 3)
        precondition((third as NSError).domain == "CaptureTransport")
        print("PASS: capture attempt, duplicate-click suppression, no automatic retries, explicit retry, error classification")
    }

    @MainActor private static func verifyWindowLifecycle() async {
        let app = NSApplication.shared
        guard let screen = NSScreen.main,
              let bitmap = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                                     bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = bitmap.makeImage() else { preconditionFailure("Desktop session required") }
        var attempts = 0
        let controller = ScreenshotController(captureScreens: {
            attempts += 1
            return [(screen, image)]
        })
        controller.start()
        for _ in 0..<100 where !app.windows.contains(where: { $0.isVisible && $0.level == .screenSaver }) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let panel = app.windows.first { $0.isVisible && $0.level == .screenSaver } as! NSPanel
        precondition(!panel.hidesOnDeactivate)
        let canvas = panel.contentView
        panel.orderOut(nil)
        controller.start()
        precondition(panel.isVisible, "Camera must restore a hidden screenshot session")
        precondition(panel.contentView === canvas, "Keep the existing selection and annotations")
        precondition(attempts == 1, "Resuming must not capture the overlay again")
        panel.contentView?.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        precondition(!panel.isVisible)
        controller.start()
        for _ in 0..<100 where attempts < 2 { try? await Task.sleep(nanoseconds: 10_000_000) }
        precondition(attempts == 2, "Cancel must allow a fresh capture")
        app.windows.filter { $0.level == .screenSaver }.forEach { $0.orderOut(nil) }
        print("PASS: hidden session resumes, canvas preserved, no recapture, cancel allows new session")
    }
}
