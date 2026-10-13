import AppKit
import SwiftUI

@main struct PetClickValidation {
    @MainActor static func main() {
        _ = NSApplication.shared
        let view = PetDragHandle.DragView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        var singles = 0, doubles = 0
        view.singleClick = { singles += 1 }; view.doubleClick = { doubles += 1 }
        func event(_ type: NSEvent.EventType, count: Int = 1, x: CGFloat = 20) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 20), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                              windowNumber: 0, context: nil, eventNumber: 1, clickCount: count, pressure: 1)!
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(NSEvent.doubleClickInterval + 0.1)) }
        precondition(view.acceptsFirstMouse(for: nil))
        view.mouseDown(with: event(.leftMouseDown)); view.mouseUp(with: event(.leftMouseUp))
        precondition(singles == 0); settle(); precondition(singles == 1 && doubles == 0)
        view.mouseDown(with: event(.leftMouseDown)); view.mouseUp(with: event(.leftMouseUp))
        view.mouseDown(with: event(.leftMouseDown, count: 2)); view.mouseUp(with: event(.leftMouseUp, count: 2))
        settle(); precondition(singles == 1 && doubles == 1, "Double click must cancel the pending single click")
        view.mouseDown(with: event(.leftMouseDown)); view.mouseDragged(with: event(.leftMouseDragged, x: 40)); view.mouseUp(with: event(.leftMouseUp, x: 40))
        settle(); precondition(singles == 1 && doubles == 1, "Dragging must not switch an action or character")
        view.mouseDown(with: event(.leftMouseDown)); view.mouseUp(with: event(.leftMouseUp)); view.cancelClick()
        settle(); precondition(singles == 1 && doubles == 1, "Unmounting must cancel pending clicks")
        print("PASS: delayed single, double without single, drag without clicks, unmount cancellation, first mouse acceptance. Native event handlers only; no real window dragging.")
    }
}
