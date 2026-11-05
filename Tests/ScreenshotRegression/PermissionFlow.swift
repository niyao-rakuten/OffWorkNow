import AppKit
import ScreenCaptureKit

// The controller's icon helper is unrelated to these headless permission-flow tests.
@MainActor enum PetArtwork {
    static func trimTransparentMargin(_ image: CGImage) -> CGImage { image }
}

@main struct PermissionFlowRegression {
    @MainActor static func main() async {
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
}
