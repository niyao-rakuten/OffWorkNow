import AppKit
import ScreenCaptureKit

/// Owns a single capture session; screenshots and annotations stay in memory.
@MainActor final class ScreenshotController {
    static let shared = ScreenshotController()
    private var panels: [NSPanel] = []
    private weak var selectedPanel: NSPanel?
    private var capturing = false
    private let captureScreens: @MainActor () async throws -> [(NSScreen, CGImage)]
    private let failureHandler: (@MainActor (Error) -> Void)?

    init(captureScreens: @escaping @MainActor () async throws -> [(NSScreen, CGImage)] = {
        try await ScreenshotController.captureScreens()
    }, failureHandler: (@MainActor (Error) -> Void)? = nil) {
        self.captureScreens = captureScreens
        self.failureHandler = failureHandler
    }

    func start() {
        guard !capturing else { return }
        if !panels.isEmpty {
            // A hidden panel still owns the selection and annotations. Resume it
            // instead of leaving the camera inert or capturing our own overlay.
            showPanels()
            return
        }
        capturing = true
        Task { [self] in
            defer { capturing = false }
            do {
                // ScreenCaptureKit is authoritative and performs the system consent flow.
                // A CoreGraphics preflight can be stale after granting permission or updating.
                let captures = try await captureScreens()
                guard !captures.isEmpty else { throw CaptureError.unavailable }
                for (screen, image) in captures {
                    let panel = CapturePanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    panel.level = .screenSaver
                    panel.hidesOnDeactivate = false
                    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    let canvas = ScreenshotCanvas(frame: CGRect(origin: .zero, size: screen.frame.size), image: image)
                    canvas.finish = { [weak self] in self?.close() }
                    canvas.activate = { [weak self, weak panel] in
                        self?.selectedPanel = panel
                        self?.panels.filter { $0 !== panel }.forEach { $0.orderOut(nil) }
                    }
                    panel.contentView = canvas
                    panels.append(panel)
                    panel.makeFirstResponder(canvas)
                }
                showPanels()
            } catch {
                close()
                if let failureHandler { failureHandler(error) }
                else { presentFailure(error) }
            }
        }
    }
    private static func captureScreens() async throws -> [(NSScreen, CGImage)] {
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
        return captures
    }

    static func isPermissionDenied(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }

    private func presentFailure(_ error: Error) {
        let alert = NSAlert()
        if Self.isPermissionDenied(error) {
            alert.messageText = "系统尚未允许当前版本截图"
            alert.informativeText = "请在系统设置中允许“下班啦”录制屏幕。若开关已经开启，请先完全退出应用，再从“应用程序”重新打开。更新后仍无效时，可在权限列表移除旧的“下班啦”，重新添加下方路径的应用并授权。\n\n当前应用：\(Bundle.main.bundlePath)"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        } else {
            let detail = error as NSError
            alert.messageText = "截图失败"
            alert.informativeText = "\(error.localizedDescription)\n\n错误：\(detail.domain) (\(detail.code))"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    private func showPanels() {
        NSApp.activate(ignoringOtherApps: true)
        for panel in panels where selectedPanel == nil || panel === selectedPanel {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.contentView)
        }
    }

    private func close() {
        panels.forEach { ($0.contentView as? ScreenshotCanvas)?.dismissColorPanel(); $0.orderOut(nil) }
        panels.removeAll()
        selectedPanel = nil
    }
    private enum CaptureError: LocalizedError {
        case unavailable
        var errorDescription: String? { "没有可截图的屏幕，请检查显示器连接后重试。" }
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
    private var colorButton: ScreenshotColorButton?
    private var previousColorPanelLevel: NSWindow.Level?
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
        let icons = ["ScreenshotSelect", "ScreenshotPencil", "ScreenshotRectangle", "ScreenshotEllipse", "ScreenshotMosaic"]
        let tips = ["移动选区 / 拖动边缘调整大小", "铅笔画线", "矩形边框", "椭圆边框", "涂抹马赛克"]
        for index in icons.indices {
            let button = iconButton(icons[index], tip: tips[index], action: #selector(changeTool(_:)))
            button.tag = index
            button.setButtonType(.pushOnPushOff)
            toolbar.addArrangedSubview(button); toolButtons.append(button)
        }
        let palette = ScreenshotColorButton(image: ScreenshotIcons.image("ScreenshotColor"), target: self, action: #selector(chooseColor))
        configure(palette, tip: "画笔与边框颜色")
        palette.selectedColor = color
        colorButton = palette
        toolbar.addArrangedSubview(palette)
        let actions: [(String, String, Selector)] = [
            ("ScreenshotUndo", "撤销标注 (⌘Z)", #selector(undoMark)),
            ("ScreenshotCancel", "丢弃截图 (Esc)", #selector(cancel)),
            ("ScreenshotConfirm", "复制到剪贴板 (Return)", #selector(copyCapture))
        ]
        for (icon, tip, action) in actions {
            toolbar.addArrangedSubview(iconButton(icon, tip: tip, action: action))
        }
        addSubview(toolbar); toolbar.isHidden = true
        updateButtons()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func changeTool(_ sender: NSButton) { tool = Tool(rawValue: sender.tag) ?? .select; updateButtons() }
    private func updateButtons() { for button in toolButtons { button.state = button.tag == tool.rawValue ? .on : .off } }
    private func iconButton(_ name: String, tip: String, action: Selector) -> NSButton {
        let button = ScreenshotToolButton(image: ScreenshotIcons.image(name), target: self, action: action)
        configure(button, tip: tip)
        return button
    }
    private func configure(_ button: NSButton, tip: String) {
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.toolTip = tip
        button.setAccessibilityLabel(tip)
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }
    @objc private func chooseColor() {
        let panel = NSColorPanel.shared
        if previousColorPanelLevel == nil { previousColorPanelLevel = panel.level }
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.color = color
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(changeColor(_:)))
        panel.orderFront(nil)
    }
    @objc private func changeColor(_ sender: NSColorPanel) {
        color = sender.color
        colorButton?.selectedColor = color
    }
    @objc private func undoMark() { if !marks.isEmpty { marks.removeLast(); needsDisplay = true } }
    @objc private func cancel() {
        dismissColorPanel()
        finish?()
    }
    func dismissColorPanel() {
        if let level = previousColorPanelLevel {
            let panel = NSColorPanel.shared
            panel.close()
            panel.level = level
            panel.setTarget(nil)
            previousColorPanelLevel = nil
        }
    }
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


/// Trim source padding and preserve aspect ratio at native toolbar sizes.
@MainActor enum ScreenshotIcons {
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage {
        if let cached = cache[name] { return cached }
        guard let source = NSImage(named: name),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return NSImage(size: NSSize(width: 26, height: 26)) }
        let trimmed = PetArtwork.trimTransparentMargin(cg)
        let ratio = CGFloat(trimmed.width) / CGFloat(trimmed.height)
        let size = ratio >= 1 ? NSSize(width: 26, height: 26 / ratio) : NSSize(width: 26 * ratio, height: 26)
        let image = NSImage(cgImage: trimmed, size: size)
        cache[name] = image
        return image
    }
}

private final class ScreenshotColorButton: NSButton {
    var selectedColor: NSColor = .systemRed { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let dot = NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 10, y: 1, width: 8, height: 8))
        selectedColor.setFill(); dot.fill()
        NSColor.white.setStroke(); dot.lineWidth = 1; dot.stroke()
    }
}

private final class ScreenshotToolButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        if state == .on {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}
