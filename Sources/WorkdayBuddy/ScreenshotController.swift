import AppKit
import ScreenCaptureKit

/// Owns a single capture session; screenshots and annotations stay in memory.
@MainActor final class ScreenshotController {
    static let shared = ScreenshotController()
    private var panels: [NSPanel] = []
    private var capturing = false

    func start() {
        guard !capturing, panels.isEmpty else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            let alert = NSAlert()
            alert.messageText = "需要屏幕录制权限"
            alert.informativeText = "请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许下班啦，然后重新尝试截图。必要时请重启应用。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }
        capturing = true
        Task {
            defer { capturing = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                var captures: [(NSScreen, CGImage)] = []
                for screen in NSScreen.screens {
                    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                          let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
                    let image: CGImage
                    if #available(macOS 14.0, *) {
                        let config = SCStreamConfiguration()
                        config.width = display.width * Int(screen.backingScaleFactor)
                        config.height = display.height * Int(screen.backingScaleFactor)
                        config.showsCursor = false
                        image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
                    } else {
                        guard let captured = CGDisplayCreateImage(display.displayID) else { continue }
                        image = captured
                    }
                    captures.append((screen, image))
                }
                guard !captures.isEmpty else { throw CaptureError.unavailable }
                for (screen, image) in captures {
                    let panel = CapturePanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    panel.level = .screenSaver
                    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    let canvas = ScreenshotCanvas(frame: CGRect(origin: .zero, size: screen.frame.size), image: image)
                    canvas.finish = { [weak self] in self?.close() }
                    canvas.activate = { [weak self, weak panel] in
                        self?.panels.filter { $0 !== panel }.forEach { $0.orderOut(nil) }
                    }
                    panel.contentView = canvas
                    panels.append(panel)
                    panel.makeKeyAndOrderFront(nil)
                    panel.makeFirstResponder(canvas)
                }
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                close()
                let alert = NSAlert()
                alert.messageText = "截图失败"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
    private func close() { panels.forEach { $0.orderOut(nil) }; panels.removeAll() }
    private enum CaptureError: LocalizedError {
        case unavailable
        var errorDescription: String? { "无法读取屏幕，请检查屏幕录制权限。" }
    }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class ScreenshotCanvas: NSView {
    enum Tool: Int { case select, pencil, rectangle, ellipse, mosaic }
    struct Mark { var tool: Tool; var points: [CGPoint]; var color: NSColor }
    let image: NSImage
    private lazy var mosaicImage: NSImage = {
        let small = NSImage(size: NSSize(width: ceil(bounds.width / 10), height: ceil(bounds.height / 10)))
        small.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: small.size))
        small.unlockFocus()
        small.size = bounds.size
        return small
    }()
    var finish: (() -> Void)?
    var activate: (() -> Void)?
    private var selection = CGRect.zero
    private var marks: [Mark] = []
    private var tool = Tool.select
    private var color = NSColor.systemRed
    private var anchor = CGPoint.zero
    private var original = CGRect.zero
    private var handle: Int?
    private var moving = false
    private let toolbar = NSStackView()
    private var toolButtons: [NSButton] = []
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, image: CGImage) {
        self.image = NSImage(cgImage: image, size: frame.size)
        super.init(frame: frame)
        toolbar.orientation = .horizontal
        toolbar.spacing = 5
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        toolbar.layer?.cornerRadius = 9
        toolbar.edgeInsets = NSEdgeInsets(top: 7, left: 8, bottom: 7, right: 8)
        let names = ["选区", "✏️", "▭", "◯", "马赛克"]
        let tips = ["移动选区 / 拖动边缘调整大小", "铅笔画线", "矩形边框", "椭圆边框", "涂抹马赛克"]
        for index in names.indices {
            let button = NSButton(title: names[index], target: self, action: #selector(changeTool(_:)))
            button.tag = index; button.toolTip = tips[index]
            button.setAccessibilityLabel(tips[index])
            button.bezelStyle = .regularSquare
            toolbar.addArrangedSubview(button); toolButtons.append(button)
        }
        let well = NSColorWell(frame: CGRect(x: 0, y: 0, width: 36, height: 26))
        well.color = color; well.target = self; well.action = #selector(changeColor(_:))
        well.toolTip = "画笔与边框颜色"
        toolbar.addArrangedSubview(well)
        for (title, action) in [("撤销", #selector(undoMark)), ("❌", #selector(cancel)), ("✅", #selector(copyCapture))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .regularSquare
            button.toolTip = title == "✅" ? "复制到剪贴板 (Return)" : title == "❌" ? "丢弃截图 (Esc)" : "撤销标注 (⌘Z)"
            toolbar.addArrangedSubview(button)
        }
        addSubview(toolbar); toolbar.isHidden = true
        updateButtons()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func changeTool(_ sender: NSButton) { tool = Tool(rawValue: sender.tag) ?? .select; updateButtons() }
    private func updateButtons() { for button in toolButtons { button.state = button.tag == tool.rawValue ? .on : .off } }
    @objc private func changeColor(_ sender: NSColorWell) { color = sender.color }
    @objc private func undoMark() { if !marks.isEmpty { marks.removeLast(); needsDisplay = true } }
    @objc private func cancel() { NSColorPanel.shared.close(); finish?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel() }
        else if event.keyCode == 36 { copyCapture() }
        else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" { undoMark() }
        else { super.keyDown(with: event) }
    }
    private var handles: [CGPoint] {
        [CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.midX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.minY),
         CGPoint(x: selection.maxX, y: selection.midY), CGPoint(x: selection.maxX, y: selection.maxY), CGPoint(x: selection.midX, y: selection.maxY),
         CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.minX, y: selection.midY)]
    }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        anchor = point(event); original = selection; handle = nil; moving = false
        if tool == .select {
            handle = selection.isEmpty ? nil : handles.firstIndex { hypot($0.x - anchor.x, $0.y - anchor.y) < 10 }
            moving = handle == nil && selection.contains(anchor)
            if !moving && handle == nil { selection = .zero; marks.removeAll() }
            activate?(); toolbar.isHidden = true
        } else if selection.contains(anchor) {
            marks.append(Mark(tool: tool, points: [anchor, anchor], color: color))
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        if tool == .select {
            if let handle {
                var left = original.minX, right = original.maxX, bottom = original.minY, top = original.maxY
                if [0, 6, 7].contains(handle) { left = p.x }
                if [2, 3, 4].contains(handle) { right = p.x }
                if [0, 1, 2].contains(handle) { bottom = p.y }
                if [4, 5, 6].contains(handle) { top = p.y }
                selection = rect(CGPoint(x: left, y: bottom), CGPoint(x: right, y: top))
            } else if moving {
                selection.origin = CGPoint(x: min(max(original.minX + p.x - anchor.x, 0), bounds.width - original.width),
                                           y: min(max(original.minY + p.y - anchor.y, 0), bounds.height - original.height))
            } else { selection = rect(anchor, p) }
        } else if selection.contains(anchor), !marks.isEmpty {
            let clipped = CGPoint(x: min(max(p.x, selection.minX), selection.maxX), y: min(max(p.y, selection.minY), selection.maxY))
            if tool == .pencil || tool == .mosaic {
                let last = marks[marks.count - 1].points.last ?? clipped
                let steps = max(1, Int(ceil(hypot(clipped.x - last.x, clipped.y - last.y) / 4)))
                for step in 1...steps {
                    let fraction = CGFloat(step) / CGFloat(steps)
                    marks[marks.count - 1].points.append(CGPoint(x: last.x + (clipped.x - last.x) * fraction, y: last.y + (clipped.y - last.y) * fraction))
                }
            }
            else { marks[marks.count - 1].points[1] = clipped }
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard selection.width >= 4, selection.height >= 4 else { selection = .zero; needsDisplay = true; return }
        toolbar.isHidden = false
        let size = toolbar.fittingSize
        toolbar.frame = CGRect(x: min(max(selection.maxX - size.width, 8), max(8, bounds.width - size.width - 8)),
                               y: selection.minY >= size.height + 12 ? selection.minY - size.height - 8 : min(bounds.height - size.height - 8, selection.maxY + 8), width: size.width, height: size.height)
        needsDisplay = true
    }
    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect { CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)) }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        if !selection.isEmpty {
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: selection).addClip(); drawMarks(); NSGraphicsContext.restoreGraphicsState()
        }
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: selection)); dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.4).setFill(); dim.fill()
        if !selection.isEmpty {
            NSColor.white.setStroke(); let border = NSBezierPath(rect: selection); border.lineWidth = 1; border.stroke()
            for p in handles { NSColor.white.setFill(); NSBezierPath(ovalIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)).fill() }
        } else {
            let text = "拖动选择截图范围 · Esc 取消"
            text.draw(at: CGPoint(x: 30, y: bounds.height - 55), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 18)])
        }
    }
    private func drawMarks() {
        for mark in marks {
            guard let first = mark.points.first, let last = mark.points.last else { continue }
            mark.color.setStroke()
            let path: NSBezierPath
            switch mark.tool {
            case .rectangle: path = NSBezierPath(rect: rect(first, last))
            case .ellipse: path = NSBezierPath(ovalIn: rect(first, last))
            case .pencil:
                path = NSBezierPath(); path.move(to: first)
                for p in mark.points.dropFirst() { path.line(to: p) }
            case .mosaic:
                // Paint opaque pixelated cells; interpolate pointer movement to avoid gaps.
                var cells = Set<String>()
                for p in mark.points {
                    for dx in -1...1 { for dy in -1...1 {
                        let x = floor(p.x / 10) * 10 + CGFloat(dx * 10), y = floor(p.y / 10) * 10 + CGFloat(dy * 10)
                        guard cells.insert("\(x),\(y)").inserted else { continue }
                        let tile = CGRect(x: x, y: y, width: 10, height: 10).intersection(bounds)
                        guard !tile.isEmpty else { continue }
                        NSGraphicsContext.saveGraphicsState()
                        NSBezierPath(rect: tile).addClip()
                        NSGraphicsContext.current?.imageInterpolation = .none
                        mosaicImage.draw(in: bounds)
                        NSGraphicsContext.restoreGraphicsState()
                    } }
                }
                continue
            case .select: continue
            }
            path.lineWidth = 3; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
        }
    }
    @objc private func copyCapture() {
        guard selection.width >= 4, selection.height >= 4 else { return }
        let scale = window?.backingScaleFactor ?? 2
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(selection.width * scale), pixelsHigh: Int(selection.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let transform = AffineTransform(m11: scale, m12: 0, m21: 0, m22: scale, tX: -selection.minX * scale, tY: -selection.minY * scale)
        (transform as NSAffineTransform).concat()
        image.draw(in: bounds); drawMarks()
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: selection.size); result.addRepresentation(bitmap)
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([result])
        cancel()
    }
}
