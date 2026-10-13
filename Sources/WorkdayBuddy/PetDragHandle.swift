import AppKit
import SwiftUI

struct PetDragHandle: NSViewRepresentable {
    let singleClick: () -> Void
    let doubleClick: () -> Void
    func makeNSView(context: Context) -> NSView {
        let view = DragView(); view.singleClick = singleClick; view.doubleClick = doubleClick; return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragView)?.singleClick = singleClick
        (nsView as? DragView)?.doubleClick = doubleClick
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) { (nsView as? DragView)?.cancelClick() }
    final class DragView: NSView {
        var singleClick: (() -> Void)?
        var doubleClick: (() -> Void)?
        private var downEvent: NSEvent?
        private var pendingClick: DispatchWorkItem?
        func cancelClick() { pendingClick?.cancel(); pendingClick = nil }
        // The resident panel must receive the first click even while another app is active.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) {
            cancelClick()
            if event.clickCount >= 2 { downEvent = nil; if event.clickCount.isMultiple(of: 2) { doubleClick?() } }
            else { downEvent = event }
        }
        override func mouseDragged(with event: NSEvent) {
            guard let downEvent else { return }
            let distance = hypot(event.locationInWindow.x - downEvent.locationInWindow.x,
                                 event.locationInWindow.y - downEvent.locationInWindow.y)
            guard distance >= 3 else { return }
            cancelClick()
            self.downEvent = nil
            window?.performDrag(with: downEvent)
            window?.saveFrame(usingName: "DesktopPet")
        }
        override func mouseUp(with event: NSEvent) {
            guard downEvent != nil else { return }
            downEvent = nil
            let click = DispatchWorkItem { [weak self] in
                self?.pendingClick = nil
                self?.singleClick?()
            }
            pendingClick = click
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: click)
        }
    }
}
