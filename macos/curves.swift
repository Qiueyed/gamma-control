import Cocoa
import CoreGraphics
import ScreenCaptureKit

// MARK: - Presets (edit freely — add, remove, or modify)
//
// Simple presets (same curve for all channels):
//   CurvePreset(name: "S-Curve", pts: [...], contrast: 0.5)
//
// Per-channel presets (different R/G/B curves):
//   CurvePreset(name: "Warm", redPts: [...], greenPts: [...], bluePts: [...], contrast: 0)

struct CurvePreset {
    let name: String
    let redPts: [(Float, Float)]
    let greenPts: [(Float, Float)]
    let bluePts: [(Float, Float)]
    let contrast: Float

    init(name: String, pts: [(Float, Float)], contrast: Float) {
        self.name = name
        self.redPts = pts
        self.greenPts = pts
        self.bluePts = pts
        self.contrast = contrast
    }

    init(name: String, redPts: [(Float, Float)], greenPts: [(Float, Float)], bluePts: [(Float, Float)], contrast: Float) {
        self.name = name
        self.redPts = redPts
        self.greenPts = greenPts
        self.bluePts = bluePts
        self.contrast = contrast
    }
}

let presets: [CurvePreset] = [
    CurvePreset(name: "Default", pts: [(0,0),(1,1)], contrast: 0),
    CurvePreset(name: "S-Curve", pts: [(0,0),(0.2,0.35),(0.5,0.5),(0.8,0.65),(1,1)], contrast: 0),
    CurvePreset(name: "Shadow Lift", pts: [(0,0),(0.2,0.4),(0.5,0.55),(0.8,0.7),(1,1)], contrast: 0),
    CurvePreset(name: "Night Vision", pts: [(0,0),(0.15,0.35),(0.4,0.6),(0.7,0.8),(1,1)], contrast: 0.15),
    CurvePreset(name: "High Contrast", pts: [(0,0),(0.2,0.25),(0.5,0.5),(0.8,0.75),(1,1)], contrast: 0.5),
    CurvePreset(name: "Crisp", pts: [(0,0),(0.2,0.28),(0.5,0.5),(0.8,0.72),(1,1)], contrast: 0.1),
    CurvePreset(name: "Soft", pts: [(0,0),(0.2,0.18),(0.5,0.5),(0.8,0.82),(1,1)], contrast: 0),
    CurvePreset(name: "See Dark lite", pts: [(0,0),(0.01,0.2),(0.03,0.03),(0.5,0.5),(1,1)], contrast: 0),
    CurvePreset(name: "See Dark", pts: [(0,0),(0.01,0.3),(0.04,0.04),(0.5,0.5),(1,1)], contrast: 0),
    CurvePreset(name: "Cave Games2", pts: [(0,0),(0.01,0.99),(0.05,0.15),(0.1,0.55),(0.15,0.25),(0.2,0.6),(0.25,0.3),(0.3,0.65),(0.35,0.35),(0.4,0.7),(0.45,0.4),(0.5,0.75),(0.55,0.45),(0.6,0.8),(0.65,0.5),(0.7,0.85),(0.75,0.55),(0.8,0.9),(0.85,0.6),(0.9,0.95),(0.95,0.65),(1,1)], contrast: 0),
]

// MARK: - Display Target

var targetDisplay: CGDirectDisplayID = CGMainDisplayID()
var displayChoices: [(id: CGDirectDisplayID, name: String)] = []

func enumerateDisplays() -> [(id: CGDirectDisplayID, name: String)] {
    var out: [(CGDirectDisplayID, String)] = []
    for screen in NSScreen.screens {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
        out.append((id, screen.localizedName))
    }
    return out
}

// MARK: - Gamma Table Application

func applyCurves(_ red: [Float], _ green: [Float], _ blue: [Float]) {
    let display = targetDisplay
    var r = red, g = green, b = blue
    for i in 0..<256 {
        if !r[i].isFinite { r[i] = Float(i) / 255.0 }
        if !g[i].isFinite { g[i] = Float(i) / 255.0 }
        if !b[i].isFinite { b[i] = Float(i) / 255.0 }
    }
    CGSetDisplayTransferByTable(display, 256, &r, &g, &b)
}

func restoreGamma() {
    CGDisplayRestoreColorSyncSettings()
}

func identityCurve() -> [Float] {
    (0..<256).map { Float($0) / 255.0 }
}

func curveFromPoints(_ pts: [(Float, Float)]) -> [Float] {
    guard pts.count >= 2 else { return identityCurve() }
    let sorted = pts.sorted { $0.0 < $1.0 }
    var table = [Float](repeating: 0, count: 256)
    for i in 0..<256 {
        let x = Float(i) / 255.0
        if x <= sorted[0].0 { table[i] = sorted[0].1; continue }
        if x >= sorted.last!.0 { table[i] = sorted.last!.1; continue }
        for j in 0..<sorted.count-1 {
            let x1 = sorted[j].0, y1 = sorted[j].1
            let x2 = sorted[j+1].0, y2 = sorted[j+1].1
            if x >= x1 && x <= x2 {
                let dx = x2 - x1
                if dx == 0 { table[i] = (y1 + y2) / 2; break }
                let t = (x - x1) / dx
                table[i] = y1 + t * (y2 - y1)
                break
            }
        }
    }
    return table
}

// MARK: - Curve Editor View

class CurveEditorView: NSView {
    var redPts: [(Float, Float)] = [(0,0), (1,1)]
    var greenPts: [(Float, Float)] = [(0,0), (1,1)]
    var bluePts: [(Float, Float)] = [(0,0), (1,1)]
    var activeChannel: Int = 0
    var contrast: Float = 0.0
    var brightness: Float = 0.0
    var enabled: Bool = true

    var dragged: Int? = nil
    var dragChannel: Int = 0
    var draggedOrigX: Float? = nil

    var trackingArea: NSTrackingArea?
    var mouseGridPos: (Float, Float)?

    var animTimer: Timer?
    var originalR = identityCurve()
    var originalG = identityCurve()
    var originalB = identityCurve()
    var capturedOriginal = false

    var autoOffset: Float = 0.0
    var autoTimer: Timer?

    func captureOriginalTable() {
        guard !capturedOriginal else { return }
        var r = [Float](repeating: 0, count: 256)
        var g = [Float](repeating: 0, count: 256)
        var b = [Float](repeating: 0, count: 256)
        var count: UInt32 = 0
        CGGetDisplayTransferByTable(targetDisplay, 256, &r, &g, &b, &count)
        originalR = r
        originalG = g
        originalB = b
        capturedOriginal = true
    }

    func sampleLuminance() async -> Float? {
        guard let content = try? await ScreenCaptureKit.SCShareableContent.current,
              let display = content.displays.first else { return nil }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 64
        config.height = 36
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return luminance(of: image)
    }

    func luminance(of image: CGImage) -> Float {
        let sw = image.width, sh = image.height
        guard let ctx = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8,
                                  bytesPerRow: sw * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0.5 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        guard let data = ctx.data else { return 0.5 }
        let ptr = data.bindMemory(to: UInt8.self, capacity: sw * sh * 4)

        let rowMin = Int(Double(sh) * 0.2), rowMax = Int(Double(sh) * 0.8)
        let colMin = Int(Double(sw) * 0.2), colMax = Int(Double(sw) * 0.8)
        var sum: Double = 0
        var count = 0
        for y in rowMin..<rowMax {
            for x in colMin..<colMax {
                let i = (y * sw + x) * 4
                let r = Double(ptr[i]), g = Double(ptr[i+1]), b = Double(ptr[i+2])
                sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
            }
        }
        guard count > 0 else { return 0.5 }
        return Float(sum / Double(count) / 255.0)
    }

    func startAutoAdjust() {
        autoTimer?.invalidate()
        autoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.autoTick()
        }
        autoTick()
    }

    func autoTick() {
        Task { [weak self] in
            guard let self = self else { return }
            guard let lum = await self.sampleLuminance() else { return }
            let desired = max(-0.35, min(0.35, 0.5 - lum))
            self.autoOffset += (desired - self.autoOffset) * 0.3
            self.applyToDisplay()
        }
    }

    func stopAuto() {
        autoTimer?.invalidate()
        autoTimer = nil
        autoOffset = 0.0
        applyToDisplay()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(rightClicked(_:)))
        rightClick.buttonMask = 1 << 1
        addGestureRecognizer(rightClick)
        captureOriginalTable()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { updateMousePos(event) }
    override func mouseExited(with event: NSEvent) {
        mouseGridPos = nil
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { updateMousePos(event) }

    func updateMousePos(_ event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let w = bounds.width, h = bounds.height
        let margin: CGFloat = 30
        let gw = w - margin * 2, gh = h - margin * 2
        let x = Float((loc.x - margin) / gw)
        let y = Float(1.0 - (loc.y - margin) / gh)
        if x >= -0.05 && x <= 1.05 && y >= -0.05 && y <= 1.05 {
            mouseGridPos = (max(0, min(1, x)), max(0, min(1, y)))
        } else {
            mouseGridPos = nil
        }
        needsDisplay = true
    }

    @objc func rightClicked(_ gesture: NSClickGestureRecognizer) {
        removePoint(at: gesture.location(in: self))
    }

    func averageTable() -> [Float] {
        let r = curveFromPoints(redPts)
        let g = curveFromPoints(greenPts)
        let b = curveFromPoints(bluePts)
        return zip(zip(r, g), b).map { ($0.0 + $0.1 + $1) / 3 }
    }

    var ptsForActiveChannel: [(Float, Float)] {
        get {
            switch activeChannel {
            case 1: return redPts
            case 2: return greenPts
            case 3: return bluePts
            default: return redPts
            }
        }
        set {
            switch activeChannel {
            case 1: redPts = newValue
            case 2: greenPts = newValue
            case 3: bluePts = newValue
            default:
                redPts = newValue
                greenPts = newValue
                bluePts = newValue
            }
        }
    }

    func generateTables() -> (r: [Float], g: [Float], b: [Float]) {
        var r = curveFromPoints(redPts)
        var g = curveFromPoints(greenPts)
        var b = curveFromPoints(bluePts)

        if contrast > 0 {
            let p = max(0.15, 1.0 - contrast * 0.85)
            for i in 0..<256 {
                func sCurve(_ v: Float) -> Float {
                    let t = 2.0 * v - 1.0
                    let tp = copysign(pow(abs(t), p), t)
                    return (tp + 1.0) / 2.0
                }
                r[i] = sCurve(r[i])
                g[i] = sCurve(g[i])
                b[i] = sCurve(b[i])
            }
        }

        let totalBrightness = brightness + autoOffset
        if totalBrightness != 0 {
            for i in 0..<256 {
                r[i] = max(0, min(1, r[i] + totalBrightness))
                g[i] = max(0, min(1, g[i] + totalBrightness))
                b[i] = max(0, min(1, b[i] + totalBrightness))
            }
        }

        return (r, g, b)
    }

    func applyToDisplay(animated: Bool = false) {
        animTimer?.invalidate()
        animTimer = nil

        if !enabled {
            captureOriginalTable()
            if animated {
                animateTransition(to: originalR, originalG, originalB, duration: 0.4)
            } else {
                restoreGamma()
            }
            return
        }

        let (r, g, b) = generateTables()
        if animated {
            animateTransition(to: r, g, b, duration: 0.3)
        } else {
            applyCurves(r, g, b)
        }
    }

    func animateTransition(to rTarget: [Float], _ gTarget: [Float], _ bTarget: [Float], duration: TimeInterval) {
        let steps = Int(duration * 60)
        guard steps > 0 else { applyCurves(rTarget, gTarget, bTarget); return }

        var curR = [Float](repeating: 0, count: 256)
        var curG = [Float](repeating: 0, count: 256)
        var curB = [Float](repeating: 0, count: 256)
        var count: UInt32 = 0
        CGGetDisplayTransferByTable(targetDisplay, 256, &curR, &curG, &curB, &count)

        var frame = 0
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            frame += 1
            let t = min(Float(frame) / Float(steps), 1.0)
            let nr = zip(curR, rTarget).map { $0 + ($1 - $0) * t }
            let ng = zip(curG, gTarget).map { $0 + ($1 - $0) * t }
            let nb = zip(curB, bTarget).map { $0 + ($1 - $0) * t }
            applyCurves(nr, ng, nb)
            if frame >= steps {
                timer.invalidate()
                self?.animTimer = nil
            }
        }
    }

    func restoreGammaIfActive() {
        restoreGamma()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height
        let pad: CGFloat = 30
        let gw = w - pad * 2, gh = h - pad * 2
        let margin: CGFloat = pad

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(bounds)

        // Grid
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(0.5)
        for i in 0...5 {
            let x = margin + gw * CGFloat(i) / 5
            let y = margin + gh * CGFloat(i) / 5
            ctx.move(to: CGPoint(x: x, y: margin))
            ctx.addLine(to: CGPoint(x: x, y: margin + gh))
            ctx.move(to: CGPoint(x: margin, y: y))
            ctx.addLine(to: CGPoint(x: margin + gw, y: y))
        }
        ctx.strokePath()

        // Sub-grid
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(0.2)
        for i in 0...10 {
            if i % 2 == 0 { continue }
            let x = margin + gw * CGFloat(i) / 10
            let y = margin + gh * CGFloat(i) / 10
            ctx.move(to: CGPoint(x: x, y: margin))
            ctx.addLine(to: CGPoint(x: x, y: margin + gh))
            ctx.move(to: CGPoint(x: margin, y: y))
            ctx.addLine(to: CGPoint(x: margin + gw, y: y))
        }
        ctx.strokePath()

        // Border
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: margin, y: margin, width: gw, height: gh))

        // Diagonal reference line
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 4, lengths: [4.0])
        ctx.move(to: CGPoint(x: margin, y: margin))
        ctx.addLine(to: CGPoint(x: margin + gw, y: margin + gh))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [CGFloat]())

        if activeChannel == 0 {
            let dims: [(CGColor, [(Float, Float)])] = [
                (CGColor(red: 1, green: 0, blue: 0, alpha: 1), redPts),
                (CGColor(red: 0, green: 1, blue: 0, alpha: 1), greenPts),
                (CGColor(red: 0, green: 0, blue: 1, alpha: 1), bluePts),
            ]
            for (color, pts) in dims {
                drawCurve(ctx: ctx, pts: pts, color: color,
                          margin: margin, gw: gw, gh: gh, points: false)
            }
            let avg = averageTable()
            drawTable(ctx: ctx, table: avg, color: NSColor.white.cgColor,
                      margin: margin, gw: gw, gh: gh)
            for (xp, yp) in redPts {
                let cx = margin + gw * CGFloat(xp)
                let cy = margin + gh * CGFloat(1 - yp)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1)
                ctx.fillEllipse(in: CGRect(x: cx-5, y: cy-5, width: 10, height: 10))
                ctx.strokeEllipse(in: CGRect(x: cx-5, y: cy-5, width: 10, height: 10))
                let ptLabel = String(format: "(%.2f,%.2f)", xp, yp)
                let ptAttr: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: NSColor.white
                ]
                (ptLabel as NSString).draw(at: CGPoint(x: cx + 8, y: cy - 6), withAttributes: ptAttr)
            }
        } else {
            let allCh: [(Int, CGColor, [(Float, Float)])] = [
                (1, CGColor(red: 1, green: 0, blue: 0, alpha: 1), redPts),
                (2, CGColor(red: 0, green: 1, blue: 0, alpha: 1), greenPts),
                (3, CGColor(red: 0, green: 0, blue: 1, alpha: 1), bluePts),
            ]
            for (ch, color, pts) in allCh {
                if ch == activeChannel { continue }
                drawCurve(ctx: ctx, pts: pts, color: color,
                          margin: margin, gw: gw, gh: gh, points: false)
            }
            let chInfo: [(Int, [(Float, Float)], CGColor)] = [
                (0, redPts, .white), (1, redPts, CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
                (2, greenPts, CGColor(red: 0, green: 1, blue: 0, alpha: 1)), (3, bluePts, CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            ]
            let (_, activePts, activeColor) = chInfo[activeChannel]
            drawCurve(ctx: ctx, pts: activePts, color: activeColor,
                      margin: margin, gw: gw, gh: gh, points: true)
        }

        // Labels
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        let labels = (0...5).map { String(format: "%.1f", Float($0) / 5.0) }
        for (i, lab) in labels.enumerated() {
            let x = margin + gw * CGFloat(i) / 5 - 10
            let y = margin - 18
            (lab as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: labelAttr)
            let yp = margin + gh * CGFloat(i) / 5 - 7
            (lab as NSString).draw(at: CGPoint(x: 2, y: yp), withAttributes: labelAttr)
        }

        // Cursor readout
        if let (mx, my) = mouseGridPos {
            let coordStr = String(format: "(% .2f, %.2f)", mx, my)
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.white
            ]
            let size = (coordStr as NSString).size(withAttributes: attr)
            (coordStr as NSString).draw(at: CGPoint(x: margin + gw - size.width - 4, y: margin + gh + 4), withAttributes: attr)
        }
    }

    func drawCurve(ctx: CGContext, pts: [(Float, Float)], color: CGColor,
                   margin: CGFloat, gw: CGFloat, gh: CGFloat, points: Bool) {
        guard pts.count >= 2 else { return }
        let sorted = pts.sorted { $0.0 < $1.0 }

        ctx.setStrokeColor(color)
        ctx.setLineWidth(2)
        ctx.beginPath()
        var first = true
        for i in 0..<256 {
            let x = Float(i) / 255.0
            var y: Float = 0
            if x <= sorted[0].0 { y = sorted[0].1 }
            else if x >= sorted.last!.0 { y = sorted.last!.1 }
            else {
                for j in 0..<sorted.count-1 {
                    let x1 = sorted[j].0, y1 = sorted[j].1
                    let x2 = sorted[j+1].0, y2 = sorted[j+1].1
                    if x >= x1 && x <= x2 {
                        let t = (x - x1) / (x2 - x1)
                        y = y1 + t * (y2 - y1)
                        break
                    }
                }
            }
            let px = margin + gw * CGFloat(x)
            let py = margin + gh * CGFloat(1 - y)
            if first { ctx.move(to: CGPoint(x: px, y: py)); first = false }
            else { ctx.addLine(to: CGPoint(x: px, y: py)) }
        }
        ctx.strokePath()

        if points {
            let ptAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.white
            ]
            for (xp, yp) in sorted {
                let cx = margin + gw * CGFloat(xp)
                let cy = margin + gh * CGFloat(1 - yp)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1.5)
                ctx.fillEllipse(in: CGRect(x: cx-6, y: cy-6, width: 12, height: 12))
                ctx.strokeEllipse(in: CGRect(x: cx-6, y: cy-6, width: 12, height: 12))
                let ptLabel = String(format: "(%.2f,%.2f)", xp, yp)
                (ptLabel as NSString).draw(at: CGPoint(x: cx + 8, y: cy - 6), withAttributes: ptAttr)
            }
        }
    }

    func removePoint(at location: CGPoint) {
        let w = bounds.width, h = bounds.height
        let margin: CGFloat = 30
        let gw = w - margin * 2, gh = h - margin * 2

        var pts = ptsForActiveChannel
        guard pts.count > 2 else { return }
        for (i, (xp, yp)) in pts.enumerated() {
            if xp == 0 || xp == 1 { continue }
            let px = margin + gw * CGFloat(xp)
            let py = margin + gh * CGFloat(1 - yp)
            if hypot(location.x - px, location.y - py) < 12 {
                pts.remove(at: i)
                ptsForActiveChannel = pts
                applyToDisplay()
                needsDisplay = true
                return
            }
        }
    }

    func drawTable(ctx: CGContext, table: [Float], color: CGColor,
                   margin: CGFloat, gw: CGFloat, gh: CGFloat) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 2, lengths: [4.0])
        ctx.beginPath()
        var first = true
        for i in 0..<256 {
            let x = Float(i) / 255.0
            let y = table[i]
            let px = margin + gw * CGFloat(x)
            let py = margin + gh * CGFloat(1 - y)
            if first { ctx.move(to: CGPoint(x: px, y: py)); first = false }
            else { ctx.addLine(to: CGPoint(x: px, y: py)) }
        }
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [CGFloat]())
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            removePoint(at: convert(event.locationInWindow, from: nil))
            return
        }

        let loc = convert(event.locationInWindow, from: nil)
        let w = bounds.width, h = bounds.height
        let margin: CGFloat = 30
        let gw = w - margin * 2, gh = h - margin * 2

        var pts = ptsForActiveChannel
        for (i, (xp, yp)) in pts.enumerated() {
            let px = margin + gw * CGFloat(xp)
            let py = margin + gh * CGFloat(1 - yp)
            let dist = hypot(loc.x - px, loc.y - py)
            if dist < 12 {
                dragged = i
                dragChannel = activeChannel
                draggedOrigX = pts[i].0
                return
            }
        }

        let x = Float((loc.x - margin) / gw)
        let y = Float(1.0 - (loc.y - margin) / gh)
        let clampedX = max(0.001, min(0.999, x))
        let clampedY = max(0, min(1, y))
        pts.append((clampedX, clampedY))
        ptsForActiveChannel = pts
        dragged = pts.count - 1
        dragChannel = activeChannel
        draggedOrigX = nil
        applyToDisplay()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let idx = dragged, dragChannel == activeChannel else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let w = bounds.width, h = bounds.height
        let margin: CGFloat = 30
        let gw = w - margin * 2, gh = h - margin * 2

        var pts = ptsForActiveChannel
        let x = Float((loc.x - margin) / gw)
        let y = Float(1.0 - (loc.y - margin) / gh)
        let clampedY = max(0, min(1, y))
        if let ox = draggedOrigX {
            if ox == 0 { pts[idx] = (0, clampedY) }
            else if ox == 1 { pts[idx] = (1, clampedY) }
            else { pts[idx] = (max(0.001, min(0.999, x)), clampedY) }
        } else {
            pts[idx] = (max(0.001, min(0.999, x)), clampedY)
        }
        ptsForActiveChannel = pts
        applyToDisplay()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragged = nil
        draggedOrigX = nil
    }

    override var isFlipped: Bool { true }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var editor: CurveEditorView!
    var channelSeg: NSSegmentedControl!
    var resetBtn: NSButton!
    var presetPopup: NSPopUpButton!
    var contrastSlider: NSSlider!
    var contrastLabel: NSTextField!
    var brightnessSlider: NSSlider!
    var brightnessLabel: NSTextField!
    var enableBtn: NSButton!
    var autoBtn: NSButton!
    var displayPopup: NSPopUpButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let winRect = NSRect(x: screenFrame.midX - 300, y: screenFrame.midY - 280, width: 600, height: 560)
        window = NSWindow(contentRect: winRect, styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Gamma Curves"
        window.delegate = self

        let root = NSView(frame: winRect.insetBy(dx: 0, dy: 0).offsetBy(dx: 0, dy: 0))
        window.contentView = root

        let curveFrame = NSRect(x: 110, y: 140, width: 380, height: 380)
        editor = CurveEditorView(frame: curveFrame)
        root.addSubview(editor)

        // Contrast
        let contrastT = NSTextField(labelWithString: "Contrast")
        contrastT.frame = NSRect(x: 20, y: 110, width: 70, height: 18)
        contrastT.font = .systemFont(ofSize: 11)
        contrastT.textColor = .white
        root.addSubview(contrastT)

        contrastSlider = NSSlider(frame: NSRect(x: 90, y: 110, width: 360, height: 20))
        contrastSlider.minValue = 0.0
        contrastSlider.maxValue = 1.0
        contrastSlider.doubleValue = 0.0
        contrastSlider.isContinuous = true
        contrastSlider.target = self
        contrastSlider.action = #selector(contrastChanged)
        root.addSubview(contrastSlider)

        contrastLabel = NSTextField(labelWithString: "0.00")
        contrastLabel.frame = NSRect(x: 410, y: 110, width: 45, height: 18)
        contrastLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        contrastLabel.textColor = .white
        root.addSubview(contrastLabel)

        enableBtn = NSButton(title: "On", target: self, action: #selector(toggleEnabled))
        enableBtn.frame = NSRect(x: 462, y: 108, width: 50, height: 22)
        enableBtn.setButtonType(.toggle)
        enableBtn.state = .on
        root.addSubview(enableBtn)

        // Brightness
        let brightT = NSTextField(labelWithString: "Brightness")
        brightT.frame = NSRect(x: 20, y: 80, width: 70, height: 18)
        brightT.font = .systemFont(ofSize: 11)
        brightT.textColor = .white
        root.addSubview(brightT)

        brightnessSlider = NSSlider(frame: NSRect(x: 90, y: 80, width: 360, height: 20))
        brightnessSlider.minValue = -0.5
        brightnessSlider.maxValue = 0.5
        brightnessSlider.doubleValue = 0.0
        brightnessSlider.isContinuous = true
        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        root.addSubview(brightnessSlider)

        brightnessLabel = NSTextField(labelWithString: "+0.00")
        brightnessLabel.frame = NSRect(x: 410, y: 80, width: 45, height: 18)
        brightnessLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        brightnessLabel.textColor = .white
        root.addSubview(brightnessLabel)

        autoBtn = NSButton(title: "Auto", target: self, action: #selector(toggleAuto))
        autoBtn.frame = NSRect(x: 462, y: 80, width: 50, height: 22)
        autoBtn.setButtonType(.toggle)
        autoBtn.state = .off
        root.addSubview(autoBtn)

        // Channel selector
        channelSeg = NSSegmentedControl(labels: ["RGB", "R", "G", "B"], trackingMode: .selectOne, target: self, action: #selector(channelChanged))
        channelSeg.frame = NSRect(x: 20, y: 50, width: 170, height: 24)
        channelSeg.selectedSegment = 0
        root.addSubview(channelSeg)

        // Presets dropdown
        presetPopup = NSPopUpButton(frame: NSRect(x: 200, y: 50, width: 140, height: 24), pullsDown: false)
        presetPopup.target = self
        presetPopup.action = #selector(presetSelected)
        root.addSubview(presetPopup)

        // Reset button
        resetBtn = NSButton(title: "Reset", target: self, action: #selector(resetCurves))
        resetBtn.frame = NSRect(x: 350, y: 50, width: 80, height: 24)
        root.addSubview(resetBtn)

        // Display target picker
        displayPopup = NSPopUpButton(frame: NSRect(x: 440, y: 50, width: 140, height: 24), pullsDown: false)
        displayPopup.target = self
        displayPopup.action = #selector(displaySelected)
        root.addSubview(displayPopup)
        displayChoices = enumerateDisplays()
        let defaultIdx = displayChoices.firstIndex(where: { $0.id == CGMainDisplayID() }) ?? 0
        for c in displayChoices {
            displayPopup.addItem(withTitle: c.name)
        }
        targetDisplay = displayChoices[defaultIdx].id
        displayPopup.selectItem(at: defaultIdx)

        // Info text
        let info = NSTextField(labelWithString: "Click to add point · Drag to move · Right-click to remove")
        info.frame = NSRect(x: 20, y: 10, width: 500, height: 18)
        info.font = .systemFont(ofSize: 11)
        info.textColor = .white
        root.addSubview(info)

        for p in presets {
            presetPopup.addItem(withTitle: p.name)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func channelChanged(_ sender: NSSegmentedControl) {
        editor.activeChannel = sender.selectedSegment
        editor.needsDisplay = true
    }

    @objc func contrastChanged(_ sender: NSSlider) {
        let val = Float(sender.doubleValue)
        editor.contrast = val
        contrastLabel.stringValue = String(format: "%.2f", val)
        editor.applyToDisplay()
    }

    @objc func brightnessChanged(_ sender: NSSlider) {
        let val = Float(sender.doubleValue)
        editor.brightness = val
        brightnessLabel.stringValue = String(format: "%+.2f", val)
        editor.applyToDisplay()
    }

    @objc func toggleEnabled() {
        editor.enabled = enableBtn.state == .on
        enableBtn.title = editor.enabled ? "On" : "Off"
        editor.applyToDisplay(animated: true)
    }

    @objc func toggleAuto() {
        if autoBtn.state == .on {
            editor.startAutoAdjust()
        } else {
            editor.stopAuto()
        }
    }

    @objc func presetSelected() {
        let idx = presetPopup.indexOfSelectedItem
        guard idx >= 0, idx < presets.count else { return }
        let p = presets[idx]
        editor.redPts = p.redPts
        editor.greenPts = p.greenPts
        editor.bluePts = p.bluePts
        editor.contrast = p.contrast
        editor.brightness = 0.0
        editor.activeChannel = 0
        channelSeg.selectedSegment = 0
        contrastSlider.doubleValue = Double(p.contrast)
        contrastLabel.stringValue = String(format: "%.2f", p.contrast)
        brightnessSlider.doubleValue = 0.0
        brightnessLabel.stringValue = "+0.00"
        enableBtn.state = .on
        editor.enabled = true
        enableBtn.title = "On"
        editor.applyToDisplay(animated: true)
        editor.needsDisplay = true
    }

    @objc func resetCurves() {
        presetPopup.selectItem(at: 0)
        presetSelected()
    }

    @objc func displaySelected() {
        let idx = displayPopup.indexOfSelectedItem
        guard idx >= 0, idx < displayChoices.count else { return }
        let newId = displayChoices[idx].id
        guard newId != targetDisplay else { return }
        let identity = (0..<256).map { Float($0) / 255.0 }
        CGSetDisplayTransferByTable(targetDisplay, 256, identity, identity, identity)
        targetDisplay = newId
        editor.capturedOriginal = false
        editor.applyToDisplay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        restoreGamma()
    }

    func windowWillClose(_ notification: Notification) {
        editor.stopAuto()
        restoreGamma()
        NSApp.terminate(nil)
    }
}

// MARK: - Main

@main
struct App {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
