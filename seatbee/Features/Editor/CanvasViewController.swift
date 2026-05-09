import UIKit
import SwiftUI

// MARK: - Canvas Data Protocol

protocol CanvasDelegate: AnyObject {
    func canvasDidSelectTable(_ tableId: String)
    func canvasDidSelectObject(_ objectId: String)
    func canvasDidDeselectAll()
    func canvasDidMoveTable(_ tableId: String, x: Double, y: Double)
    func canvasDidMoveObject(_ objectId: String, x: Double, y: Double)
    func canvasDidRequestDeleteObject(_ objectId: String)
}

// MARK: - Canvas View Controller

class CanvasViewController: UIViewController, UIScrollViewDelegate {
    weak var delegate: CanvasDelegate?

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private var tableViews: [String: CanvasTableView] = [:]
    private var objectViews: [String: CanvasObjectView] = [:]

    private var selectedId: String?
    private var selectedType: String? // "table" or "object"

    // Canvas size grows to fit the active room. Default covers up to a
    // ~110×80ft (1650×1200px) Large preset with comfortable padding; bigger
    // rooms (Ballroom, Grand, Convention) trigger a recompute in updateRoom.
    // Padding on all sides so users can scroll outside the room.
    private let canvasPadding: CGFloat = 400
    private var canvasSize = CGSize(width: 2000, height: 2000)
    private var canvasOrigin = CGPoint(x: 400, y: 400)
    private var didInitialFit = false

    // Viewport persistence — when the user zooms/scrolls then leaves the
    // editor (Guests tab, AI sheet, app background), the next visit should
    // resume at the same place. Stored in UserDefaults keyed by plan ID so
    // each plan remembers its own viewport across app launches too.
    private var planId: String?
    private var didRestoreViewport = false
    private static let viewportDefaultsPrefix = "seatbee.canvasViewport."

    // Room outline + floor plan backdrop layers. Both sit between the
    // dot pattern background (index 0) and the table/object subviews.
    private let floorPlanImageView = UIImageView()
    private let roomOutlineLayer = CAShapeLayer()
    private let zoneShapesLayer = CAShapeLayer()

    // Alignment guides — drawn while the user drags a table/object. Web
    // parity (App.jsx calcGuides at line 8110): two layers so the room/
    // item-center guides render in red and edge alignments in blue, both
    // 1pt dashed strokes spanning the room.
    private let alignmentCenterGuides = CAShapeLayer()
    private let alignmentEdgeGuides   = CAShapeLayer()
    private static let alignSnapThreshold: CGFloat = 8

    // Ruler overlay — gold tick marks + unit labels along the top and
    // left edges of the room rect. Toggled via setRulerVisible(_:unit:).
    // Strokes live in `rulerLayer`; labels are individual CATextLayers
    // rebuilt on every relevant update so we don't have to reposition
    // 50+ tick labels frame-by-frame.
    private let rulerLayer = CAShapeLayer()
    private var rulerLabels: [CATextLayer] = []
    private var rulerVisible = false
    private var rulerUnit: String?

    // Snapshots of the most recent table / object data so the guide
    // calculator can iterate without poking through the visual views.
    private var currentTables: [SeatTable] = []
    /// Per-axis snap latches — flip true the frame an alignment guide
    /// engages, stay true while held, reset on disengage or drag end.
    /// Drag closures fire HapticEngine.selection() only on the false→true
    /// transition so a sustained snap doesn't buzz every frame.
    private var lastSnapX = false
    private var lastSnapY = false
    private var currentObjects: [RoomObject] = []
    private var currentRoomWidth: CGFloat = 0
    private var currentRoomHeight: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        // Scroll view setup
        scrollView.delegate = self
        // minimumZoomScale is recomputed in updateRoom() to guarantee any
        // room size can fit on screen. Starting low so initial layout is safe.
        scrollView.minimumZoomScale = 0.05
        scrollView.maximumZoomScale = 3.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = UIColor(red: 250/255, green: 246/255, blue: 236/255, alpha: 1) // ivory2

        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Content view
        contentView.frame = CGRect(origin: .zero, size: canvasSize)
        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)
        scrollView.contentSize = canvasSize

        // Dot pattern background (layer index 0)
        let dotLayer = DotPatternLayer()
        dotLayer.frame = contentView.bounds
        contentView.layer.insertSublayer(dotLayer, at: 0)

        // Floor plan backdrop (between dots and outline). Hidden until
        // updateRoom(...) is called with a non-nil image.
        floorPlanImageView.contentMode = .scaleAspectFit
        floorPlanImageView.alpha = 0.4
        floorPlanImageView.isUserInteractionEnabled = false
        floorPlanImageView.isHidden = true
        contentView.addSubview(floorPlanImageView)

        // Room outline (above floor plan, below tables/objects).
        roomOutlineLayer.fillColor = UIColor(red: 247/255, green: 231/255, blue: 206/255, alpha: 0.35).cgColor
        roomOutlineLayer.strokeColor = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 0.7).cgColor
        roomOutlineLayer.lineWidth = 2
        contentView.layer.insertSublayer(roomOutlineLayer, above: dotLayer)

        // Zone (labeled area) outlines. Drawn above the room outline so
        // they read as nested regions within the room.
        zoneShapesLayer.fillColor = UIColor.clear.cgColor
        zoneShapesLayer.strokeColor = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 0.4).cgColor
        zoneShapesLayer.lineWidth = 1.5
        zoneShapesLayer.lineDashPattern = [4, 3]
        contentView.layer.insertSublayer(zoneShapesLayer, above: roomOutlineLayer)

        // Alignment guides — sit above the room outline so they read on
        // top of the floor plan and any tables underneath them. Hidden
        // until a drag is in progress.
        for guide in [alignmentCenterGuides, alignmentEdgeGuides] {
            guide.fillColor = UIColor.clear.cgColor
            guide.lineWidth = 1
            guide.lineDashPattern = [4, 4]
            guide.path = nil
            contentView.layer.insertSublayer(guide, above: zoneShapesLayer)
        }
        alignmentCenterGuides.strokeColor = UIColor(red: 232/255, green: 124/255, blue: 124/255, alpha: 1).cgColor // #E87C7C
        alignmentEdgeGuides.strokeColor   = UIColor(red: 124/255, green: 184/255, blue: 232/255, alpha: 1).cgColor // #7CB8E8

        // Ruler overlay layer — added above the alignment guides so
        // ticks remain visible during a drag. Stroke colour is gold
        // at low alpha to match the canvas chrome without competing
        // with table content.
        rulerLayer.fillColor = UIColor.clear.cgColor
        rulerLayer.strokeColor = UIColor(red: 168/255, green: 136/255, blue: 67/255, alpha: 0.7).cgColor // sbGoldDk
        rulerLayer.lineWidth = 1
        rulerLayer.isHidden = true
        contentView.layer.insertSublayer(rulerLayer, above: alignmentEdgeGuides)

        // Tap to deselect
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        contentView.addGestureRecognizer(tap)

        // Initial zoom
        scrollView.zoomScale = 0.8

        // Center content
        DispatchQueue.main.async {
            let offsetX = max(0, (self.canvasSize.width * 0.8 - self.scrollView.bounds.width) / 2)
            let offsetY = max(0, (self.canvasSize.height * 0.8 - self.scrollView.bounds.height) / 2)
            self.scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentView
    }

    // MARK: - Room outline + floor plan
    //
    // Web parity (src/App.jsx:3723-3761 roomPath()): convert customRoomPoints
    // into an SVG-style path with M / L / A / Z segments, optionally flipped
    // H / V. iOS draws the equivalent UIBezierPath as a CAShapeLayer.
    //
    // Coordinate system: room (0,0) lives at canvasOrigin (400, 400). Web
    // points are absolute pixels in [0..roomWidth, 0..roomHeight], which we
    // translate by canvasOrigin so they align with table x/y coordinates
    // (which are also stored in the same room-pixel space).

    func updateRoom(
        roomShape: String?,
        roomWidth: Double?,
        roomHeight: Double?,
        customRoomPoints: [RoomPoint]?,
        roomFlipH: Bool?,
        roomFlipV: Bool?,
        roomZones: [RoomZone]?,
        floorPlanBase64: String?,
        floorPlanOpacity: Double?
    ) {
        let w = CGFloat(roomWidth ?? 0)
        let h = CGFloat(roomHeight ?? 0)
        currentRoomWidth = w
        currentRoomHeight = h

        // Grow the canvas to fit the room with comfortable padding on every
        // side. Big presets like Convention (4500×3000) need ~5300×3800 of
        // canvas; small rooms keep the original 2000×2000 minimum so tables
        // dragged to a corner have room to scroll.
        let needW = max(2000, w + canvasPadding * 2)
        let needH = max(2000, h + canvasPadding * 2)
        if abs(needW - canvasSize.width) > 1 || abs(needH - canvasSize.height) > 1 {
            canvasSize = CGSize(width: needW, height: needH)
            canvasOrigin = CGPoint(x: canvasPadding, y: canvasPadding)
            contentView.frame = CGRect(origin: .zero, size: canvasSize)
            scrollView.contentSize = canvasSize
            // Resize background dot pattern to match.
            if let dotLayer = contentView.layer.sublayers?.first as? DotPatternLayer {
                dotLayer.frame = contentView.bounds
                dotLayer.setNeedsDisplay()
            }
            recomputeMinZoom()
        }

        // Outline path
        if w > 0 && h > 0 {
            let path = roomBezierPath(
                shape: roomShape,
                width: w,
                height: h,
                customPoints: customRoomPoints,
                flipH: roomFlipH ?? false,
                flipV: roomFlipV ?? false
            )
            // Translate to canvasOrigin so the room aligns with table x/y.
            var transform = CGAffineTransform(translationX: canvasOrigin.x, y: canvasOrigin.y)
            roomOutlineLayer.path = path.cgPath.copy(using: &transform)
        } else {
            roomOutlineLayer.path = nil
        }

        // Zones
        if let zones = roomZones, !zones.isEmpty {
            let combined = UIBezierPath()
            for z in zones {
                let r = CGRect(
                    x: canvasOrigin.x + CGFloat(z.x),
                    y: canvasOrigin.y + CGFloat(z.y),
                    width: CGFloat(z.w),
                    height: CGFloat(z.h)
                )
                combined.append(UIBezierPath(roundedRect: r, cornerRadius: 4))
            }
            zoneShapesLayer.path = combined.cgPath
        } else {
            zoneShapesLayer.path = nil
        }

        // Floor plan backdrop. Web stores floorPlanImage as a base64 data URL
        // (string starting with "data:image/..."). iOS decodes it once and
        // positions it at the canvas origin sized to the room dimensions.
        if let base64 = floorPlanBase64, !base64.isEmpty,
           let image = decodeBase64Image(base64), w > 0, h > 0 {
            floorPlanImageView.image = image
            floorPlanImageView.frame = CGRect(
                x: canvasOrigin.x, y: canvasOrigin.y,
                width: w, height: h
            )
            floorPlanImageView.alpha = CGFloat(floorPlanOpacity ?? 0.4)
            floorPlanImageView.isHidden = false
        } else {
            floorPlanImageView.image = nil
            floorPlanImageView.isHidden = true
        }

        // Room dimensions just changed — refresh the ruler if visible
        // so tick extents follow the new room rect.
        rebuildRulerIfNeeded()
    }

    // MARK: - Ruler overlay

    /// Toggle the ruler on/off and remember the unit. Cheap when the
    /// state hasn't changed; rebuilds when it has.
    func setRulerVisible(_ visible: Bool, unit: String?) {
        let visibilityChanged = (visible != rulerVisible)
        let unitChanged = (unit != rulerUnit)
        rulerVisible = visible
        rulerUnit = unit
        if visibilityChanged || unitChanged {
            rebuildRulerIfNeeded()
        }
    }

    private func rebuildRulerIfNeeded() {
        // When hidden, just blank the layer — no need to recompute
        // ticks until the user toggles it back on.
        if !rulerVisible {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rulerLayer.path = nil
            rulerLayer.isHidden = true
            CATransaction.commit()
            for label in rulerLabels { label.removeFromSuperlayer() }
            rulerLabels.removeAll()
            return
        }
        // Room not sized yet — wait for updateRoom to provide
        // dimensions; nothing to draw against.
        guard currentRoomWidth > 0, currentRoomHeight > 0 else { return }

        let factor = CGFloat(RoomScale.factor(for: rulerUnit))
        let unitLabel = RoomScale.unitLabel(for: rulerUnit)
        let isMetric = (rulerUnit == "metric")
        // Tick spacing (in real-world units): major labels every
        // 5 ft / 1 m; minor ticks every 1 ft / 0.25 m.
        let majorStep: CGFloat = isMetric ? 1 : 5
        let minorStep: CGFloat = isMetric ? 0.25 : 1

        let path = UIBezierPath()
        for label in rulerLabels { label.removeFromSuperlayer() }
        rulerLabels.removeAll()

        // Top ruler: ticks hang DOWN from the top edge of the room
        // into the canvas; labels sit just below the tick.
        let topY = canvasOrigin.y
        var u: CGFloat = 0
        let widthInUnits = currentRoomWidth / factor
        while u <= widthInUnits + 0.001 {
            let x = canvasOrigin.x + u * factor
            let isMajor = abs((u / majorStep).rounded() - (u / majorStep)) < 0.001
            let tickLen: CGFloat = isMajor ? 6 : 3
            path.move(to: CGPoint(x: x, y: topY))
            path.addLine(to: CGPoint(x: x, y: topY + tickLen))
            if isMajor && u > 0 {
                addRulerLabel(at: CGPoint(x: x + 2, y: topY + tickLen + 1),
                              text: rulerLabelText(value: u, unit: unitLabel))
            }
            u += minorStep
        }

        // Left ruler: ticks point RIGHT from the left edge; labels
        // sit just to the right of the tick.
        let leftX = canvasOrigin.x
        u = 0
        let heightInUnits = currentRoomHeight / factor
        while u <= heightInUnits + 0.001 {
            let y = canvasOrigin.y + u * factor
            let isMajor = abs((u / majorStep).rounded() - (u / majorStep)) < 0.001
            let tickLen: CGFloat = isMajor ? 6 : 3
            path.move(to: CGPoint(x: leftX, y: y))
            path.addLine(to: CGPoint(x: leftX + tickLen, y: y))
            if isMajor && u > 0 {
                addRulerLabel(at: CGPoint(x: leftX + tickLen + 1, y: y - 5),
                              text: rulerLabelText(value: u, unit: unitLabel))
            }
            u += minorStep
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rulerLayer.path = path.cgPath
        rulerLayer.isHidden = false
        CATransaction.commit()
    }

    private func rulerLabelText(value: CGFloat, unit: String) -> String {
        // Drop trailing .0 ("5 ft" not "5.0 ft", "1 m" not "1.0 m").
        let rounded = value.rounded()
        if abs(value - rounded) < 0.01 {
            return "\(Int(rounded)) \(unit)"
        }
        return String(format: "%.1f %@", Double(value), unit)
    }

    private func addRulerLabel(at origin: CGPoint, text: String) {
        let label = CATextLayer()
        label.contentsScale = UIScreen.main.scale
        label.string = text
        label.font = UIFont.systemFont(ofSize: 9, weight: .regular)
        label.fontSize = 9
        // sbCharcoal at 70% alpha — readable against the ivory
        // canvas without competing with table glyphs.
        label.foregroundColor = UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 0.7).cgColor
        label.frame = CGRect(x: origin.x, y: origin.y, width: 36, height: 11)
        contentView.layer.addSublayer(label)
        rulerLabels.append(label)
    }

    // Direct port of web's roomPath() — builds a UIBezierPath equivalent
    // to the SVG path web emits. Honors arc segments (rx, ry, sweep,
    // largeArc) and the flipH/flipV transforms (which also invert the
    // arc sweep direction when flipping H xor V).
    private func roomBezierPath(
        shape: String?,
        width: CGFloat,
        height: CGFloat,
        customPoints: [RoomPoint]?,
        flipH: Bool,
        flipV: Bool
    ) -> UIBezierPath {
        let basePoints: [RoomPoint] = {
            if let pts = customPoints, pts.count >= 3 { return pts }
            return RoomShapePresets.defaultPoints(shape: shape ?? "rect", width: Double(width), height: Double(height))
        }()

        let flipped: [RoomPoint] = basePoints.map { p in
            var f = p
            if flipH { f.x = Double(width) - p.x }
            if flipV { f.y = Double(height) - p.y }
            if let arc = p.arc, flipH != flipV {
                // Flipping H xor V inverts arc sweep direction.
                f.arc = RoomArc(rx: arc.rx, ry: arc.ry, sweep: arc.sweep == 1 ? 0 : 1, largeArc: arc.largeArc)
            }
            return f
        }

        let path = UIBezierPath()
        guard !flipped.isEmpty else { return path }
        let first = flipped[0]
        path.move(to: CGPoint(x: first.x, y: first.y))
        for i in 1..<flipped.count {
            let p = flipped[i]
            if let arc = p.arc {
                appendArc(to: path, end: CGPoint(x: p.x, y: p.y), arc: arc)
            } else {
                path.addLine(to: CGPoint(x: p.x, y: p.y))
            }
        }
        // Close: if the FIRST point has an arc, the closing segment is an
        // arc from the last point back to the first. Else a straight close.
        if let arc = first.arc {
            appendArc(to: path, end: CGPoint(x: first.x, y: first.y), arc: arc)
        }
        path.close()
        return path
    }

    // SVG elliptical-arc → cubic Bézier conversion. Implements the
    // endpoint→center-parameterisation in W3C SVG 1.1 §F.6.5, then
    // subdivides into ≤90° segments and emits each as a kappa-tuned
    // cubic Bézier. This is the correct rendering for oval / circle /
    // any future curved walls; the previous quadratic approximation
    // produced concave star shapes because it placed the control point
    // toward the chord midpoint instead of outside the ellipse.
    private func appendArc(to path: UIBezierPath, end: CGPoint, arc: RoomArc) {
        let segments = svgArcToCubics(
            start: path.currentPoint,
            end: end,
            rx: CGFloat(arc.rx),
            ry: CGFloat(arc.ry),
            largeArc: arc.largeArc == 1,
            sweep: arc.sweep == 1
        )
        if segments.isEmpty {
            path.addLine(to: end)
            return
        }
        for seg in segments {
            path.addCurve(to: seg.end, controlPoint1: seg.cp1, controlPoint2: seg.cp2)
        }
    }

    private struct CubicSeg { let cp1: CGPoint; let cp2: CGPoint; let end: CGPoint }

    private func svgArcToCubics(
        start: CGPoint, end: CGPoint,
        rx _rx: CGFloat, ry _ry: CGFloat,
        largeArc: Bool, sweep: Bool
    ) -> [CubicSeg] {
        // Degenerate cases — straight line.
        if start == end { return [] }
        var rx = abs(_rx), ry = abs(_ry)
        if rx < 0.0001 || ry < 0.0001 {
            return [CubicSeg(cp1: start, cp2: end, end: end)]
        }

        // Step 1: compute (x1', y1') in the rotated frame (xRot=0 here).
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = dx
        let y1p = dy

        // Ensure radii are large enough to span the chord; scale up if not.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s
        }

        // Step 2: compute (cx', cy') — the center in rotated frame.
        let rxSq = rx * rx, rySq = ry * ry
        let x1pSq = x1p * x1p, y1pSq = y1p * y1p
        let denom = rxSq * y1pSq + rySq * x1pSq
        let radicand = max(0, (rxSq * rySq - rxSq * y1pSq - rySq * x1pSq) / max(denom, 0.0001))
        let factor = sqrt(radicand) * (largeArc == sweep ? -1 : 1)
        let cxp = factor * (rx * y1p / ry)
        let cyp = factor * (-ry * x1p / rx)

        // Step 3: compute (cx, cy) — center in original coordinate space.
        let cx = cxp + (start.x + end.x) / 2
        let cy = cyp + (start.y + end.y) / 2

        // Step 4: compute θ1 and Δθ.
        func vecAngle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            let clamped = max(-1, min(1, dot / max(len, 0.0001)))
            let sign: CGFloat = (ux * vy - uy * vx) >= 0 ? 1 : -1
            return sign * acos(clamped)
        }
        let theta1 = vecAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var deltaTheta = vecAngle(
            (x1p - cxp) / rx, (y1p - cyp) / ry,
            (-x1p - cxp) / rx, (-y1p - cyp) / ry
        )
        if !sweep && deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep && deltaTheta < 0 { deltaTheta += 2 * .pi }

        // Step 5: subdivide into ≤90° pieces and emit kappa-tuned cubics.
        let count = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
        let segDelta = deltaTheta / CGFloat(count)
        let alpha = sin(segDelta) * (sqrt(4 + 3 * tan(segDelta / 2) * tan(segDelta / 2)) - 1) / 3

        var beziers: [CubicSeg] = []
        var t1 = theta1
        for _ in 0..<count {
            let t2 = t1 + segDelta
            let p1 = ellipsePoint(cx: cx, cy: cy, rx: rx, ry: ry, theta: t1)
            let p2 = ellipsePoint(cx: cx, cy: cy, rx: rx, ry: ry, theta: t2)
            let dp1 = ellipseTangent(rx: rx, ry: ry, theta: t1)
            let dp2 = ellipseTangent(rx: rx, ry: ry, theta: t2)
            let cp1 = CGPoint(x: p1.x + alpha * dp1.x, y: p1.y + alpha * dp1.y)
            let cp2 = CGPoint(x: p2.x - alpha * dp2.x, y: p2.y - alpha * dp2.y)
            beziers.append(CubicSeg(cp1: cp1, cp2: cp2, end: p2))
            t1 = t2
        }
        return beziers
    }

    private func ellipsePoint(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, theta: CGFloat) -> CGPoint {
        CGPoint(x: cx + rx * cos(theta), y: cy + ry * sin(theta))
    }

    private func ellipseTangent(rx: CGFloat, ry: CGFloat, theta: CGFloat) -> CGPoint {
        // Derivative of (rx·cosθ, ry·sinθ) = (-rx·sinθ, ry·cosθ)
        CGPoint(x: -rx * sin(theta), y: ry * cos(theta))
    }

    // Pick a minimumZoomScale that guarantees the whole canvas can be
    // shrunk to fit the viewport, with a small floor so we never go to 0.
    // Without this, large rooms (Convention 5300pt canvas vs 400pt screen)
    // need scale ~0.075 to fit — well below the old hardcoded 0.3 floor.
    private func recomputeMinZoom() {
        guard scrollView.bounds.width > 0 && scrollView.bounds.height > 0 else { return }
        let xRatio = scrollView.bounds.width / canvasSize.width
        let yRatio = scrollView.bounds.height / canvasSize.height
        let needed = min(xRatio, yRatio)
        scrollView.minimumZoomScale = max(0.05, min(0.5, needed * 0.9))
        // Don't pin the current zoom below the new minimum — UIKit handles
        // clamping but we re-clamp explicitly so layout doesn't get stuck.
        if scrollView.zoomScale < scrollView.minimumZoomScale {
            scrollView.zoomScale = scrollView.minimumZoomScale
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        recomputeMinZoom()
        // First time we have both a sized scrollView and any content,
        // either restore the user's last viewport for this plan or
        // auto-fit so they see the whole layout. Restore wins so users
        // returning from Guests / AI land where they left off.
        if !didInitialFit && !contentBounds().isNull {
            didInitialFit = true
            DispatchQueue.main.async {
                if !self.restoreViewport() {
                    self.fitToContent(animated: false)
                }
            }
        }
    }

    func setPlanId(_ id: String?) {
        guard planId != id else { return }
        planId = id
        // Force the next viewDidLayoutSubviews to restore for the new plan.
        didInitialFit = false
        didRestoreViewport = false
    }

    @discardableResult
    private func restoreViewport() -> Bool {
        guard let id = planId, !didRestoreViewport else { return false }
        let key = Self.viewportDefaultsPrefix + id
        guard let dict = UserDefaults.standard.dictionary(forKey: key),
              let zoom = dict["zoom"] as? Double,
              let ox = dict["offsetX"] as? Double,
              let oy = dict["offsetY"] as? Double else { return false }
        let clampedZoom = CGFloat(min(Double(scrollView.maximumZoomScale),
                                      max(Double(scrollView.minimumZoomScale), zoom)))
        scrollView.zoomScale = clampedZoom
        scrollView.contentOffset = CGPoint(x: ox, y: oy)
        didRestoreViewport = true
        return true
    }

    private func saveViewport() {
        guard let id = planId else { return }
        let key = Self.viewportDefaultsPrefix + id
        let dict: [String: Any] = [
            "zoom": Double(scrollView.zoomScale),
            "offsetX": Double(scrollView.contentOffset.x),
            "offsetY": Double(scrollView.contentOffset.y),
        ]
        UserDefaults.standard.set(dict, forKey: key)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        saveViewport()
    }

    /// Forward zoom changes to each table view so seats can render
    /// initials past the threshold. setZoom() short-circuits when the
    /// threshold isn't crossed, so this is cheap on every frame.
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let z = scrollView.zoomScale
        for tv in tableViews.values {
            tv.setZoom(z)
        }
    }

    // MARK: - Alignment guides
    //
    // Web parity (App.jsx calcGuides at line 8110). Called from
    // CanvasTableView / CanvasObjectView during drag. Given the proposed
    // *centre* in contentView coords + the dragged item's body size,
    // computes alignment snaps against every other table/object plus the
    // room centre, draws dashed guide lines on the contentView, and
    // returns the snapped centre to the dragging view.
    //
    // The 8pt threshold is in canvas-local (room) coords so the snap
    // zone scales with zoom — easier to land on a guide when zoomed in.
    /// Snap result — `center` is the proposed center clamped to any
    /// engaged guides; `snappedX` / `snappedY` flag which axes
    /// engaged this frame. Drag closures use the bool flags to fire
    /// a haptic exactly on the engage transition (see lastSnapX /
    /// lastSnapY ivars), avoiding a per-frame buzz while a snap is
    /// sustained.
    struct AlignmentSnapResult {
        let center: CGPoint
        let snappedX: Bool
        let snappedY: Bool
    }

    func computeAlignmentSnap(forDragID id: String, isObject: Bool,
                              proposedCenter: CGPoint, size: CGSize) -> AlignmentSnapResult {
        let cx = proposedCenter.x - canvasOrigin.x
        let cy = proposedCenter.y - canvasOrigin.y
        let dw = size.width
        let dh = size.height
        let dLeft   = cx - dw / 2
        let dRight  = cx + dw / 2
        let dTop    = cy - dh / 2
        let dBottom = cy + dh / 2

        let threshold = Self.alignSnapThreshold
        var snapCx: CGFloat? = nil
        var snapCy: CGFloat? = nil
        var centerLines: [(isVertical: Bool, pos: CGFloat)] = []
        var edgeLines:   [(isVertical: Bool, pos: CGFloat)] = []

        // Room centre — checked first so it wins ties over item alignments.
        if currentRoomWidth > 0 {
            let roomCx = currentRoomWidth / 2
            if abs(cx - roomCx) < threshold {
                centerLines.append((true, roomCx))
                snapCx = roomCx
            }
        }
        if currentRoomHeight > 0 {
            let roomCy = currentRoomHeight / 2
            if abs(cy - roomCy) < threshold {
                centerLines.append((false, roomCy))
                snapCy = roomCy
            }
        }

        // Pre-build a flat (centre, w, h) list of all OTHER items so the
        // table/object distinction doesn't matter for snapping purposes.
        struct Anchor { let cx, cy, w, h: CGFloat }
        var anchors: [Anchor] = []
        for t in currentTables where t.id != id || isObject {
            let body = CanvasTableView.bodySize(for: t)
            let w = body.width, h = body.height
            // x,y is top-left; compute centre for snap comparisons.
            anchors.append(Anchor(cx: CGFloat(t.x) + w / 2, cy: CGFloat(t.y) + h / 2, w: w, h: h))
        }
        for o in currentObjects where o.id != id || !isObject {
            let w = CGFloat(o.width), h = CGFloat(o.height)
            // x,y is top-left; compute centre for snap comparisons.
            anchors.append(Anchor(cx: CGFloat(o.x) + w / 2, cy: CGFloat(o.y) + h / 2, w: w, h: h))
        }

        for a in anchors {
            let aLeft = a.cx - a.w / 2, aRight = a.cx + a.w / 2
            let aTop  = a.cy - a.h / 2, aBottom = a.cy + a.h / 2

            // Centre alignments — vertical guide at item centre when our
            // centre is close to it; horizontal likewise.
            if snapCx == nil, abs(cx - a.cx) < threshold {
                centerLines.append((true, a.cx))
                snapCx = a.cx
            }
            if snapCy == nil, abs(cy - a.cy) < threshold {
                centerLines.append((false, a.cy))
                snapCy = a.cy
            }

            // Edge alignments. Match left/right/top/bottom edges, plus
            // edge-to-opposite-edge so dragging up against a neighbour
            // also snaps cleanly.
            if snapCx == nil {
                if abs(dLeft - aLeft) < threshold       { edgeLines.append((true, aLeft));   snapCx = aLeft  + dw/2 }
                else if abs(dLeft - aRight) < threshold { edgeLines.append((true, aRight));  snapCx = aRight + dw/2 }
                else if abs(dRight - aRight) < threshold{ edgeLines.append((true, aRight));  snapCx = aRight - dw/2 }
                else if abs(dRight - aLeft) < threshold { edgeLines.append((true, aLeft));   snapCx = aLeft  - dw/2 }
            }
            if snapCy == nil {
                if abs(dTop - aTop) < threshold         { edgeLines.append((false, aTop));    snapCy = aTop    + dh/2 }
                else if abs(dTop - aBottom) < threshold { edgeLines.append((false, aBottom)); snapCy = aBottom + dh/2 }
                else if abs(dBottom - aBottom) < threshold { edgeLines.append((false, aBottom)); snapCy = aBottom - dh/2 }
                else if abs(dBottom - aTop) < threshold    { edgeLines.append((false, aTop));    snapCy = aTop    - dh/2 }
            }
        }

        // Build the guide paths. Lines span the full room so the user
        // sees the alignment going edge-to-edge, like web.
        let centerPath = UIBezierPath()
        let edgePath = UIBezierPath()
        for line in centerLines {
            appendGuide(line.isVertical, pos: line.pos, into: centerPath)
        }
        for line in edgeLines {
            appendGuide(line.isVertical, pos: line.pos, into: edgePath)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        alignmentCenterGuides.path = centerPath.isEmpty ? nil : centerPath.cgPath
        alignmentEdgeGuides.path   = edgePath.isEmpty   ? nil : edgePath.cgPath
        CATransaction.commit()

        // Convert the snapped canvas-local centre back to contentView
        // coords. Either axis may be unsnapped — fall back to the
        // proposed value on that axis.
        return AlignmentSnapResult(
            center: CGPoint(
                x: canvasOrigin.x + (snapCx ?? cx),
                y: canvasOrigin.y + (snapCy ?? cy)
            ),
            snappedX: snapCx != nil,
            snappedY: snapCy != nil
        )
    }

    /// Builds a vertical or horizontal guide line spanning the full room
    /// (in contentView coords) and appends it to the given path.
    private func appendGuide(_ isVertical: Bool, pos: CGFloat, into path: UIBezierPath) {
        if isVertical {
            let x = canvasOrigin.x + pos
            path.move(to: CGPoint(x: x, y: canvasOrigin.y))
            path.addLine(to: CGPoint(x: x, y: canvasOrigin.y + currentRoomHeight))
        } else {
            let y = canvasOrigin.y + pos
            path.move(to: CGPoint(x: canvasOrigin.x, y: y))
            path.addLine(to: CGPoint(x: canvasOrigin.x + currentRoomWidth, y: y))
        }
    }

    /// Called when a drag ends so the guide lines disappear. No-op when
    /// nothing is currently drawn.
    func clearAlignmentGuides() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        alignmentCenterGuides.path = nil
        alignmentEdgeGuides.path = nil
        CATransaction.commit()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        saveViewport()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { saveViewport() }
    }

    // MARK: - Fit-to-content
    //
    // Compute the bounding rect of all visible content (room outline +
    // tables + objects) in contentView coords, then ask the scrollView to
    // zoom to it with a small padding margin. Falls back to the full
    // canvas if there's nothing to fit.
    func fitToContent(animated: Bool = true) {
        guard scrollView.bounds.width > 0 && scrollView.bounds.height > 0 else { return }
        let bounds = contentBounds()
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }

        let padding: CGFloat = 40
        let padded = bounds.insetBy(dx: -padding, dy: -padding)
        scrollView.zoom(to: padded, animated: animated)
    }

    private func contentBounds() -> CGRect {
        var rect = CGRect.null

        if let roomPath = roomOutlineLayer.path {
            rect = rect.union(roomPath.boundingBox)
        }
        for v in tableViews.values {
            rect = rect.union(v.frame)
        }
        for v in objectViews.values {
            rect = rect.union(v.frame)
        }
        return rect
    }

    private func decodeBase64Image(_ s: String) -> UIImage? {
        // Web stores floorPlanImage as either a "data:image/...;base64,..."
        // URL or a raw base64 string.
        var raw = s
        if let commaIdx = s.firstIndex(of: ","), s.hasPrefix("data:") {
            raw = String(s[s.index(after: commaIdx)...])
        }
        guard let data = Data(base64Encoded: raw) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Update from SwiftUI

    func updateTables(_ tables: [SeatTable], guests: [Guest], selectedId: String?) {
        self.selectedId = selectedId
        self.currentTables = tables

        let currentIds = Set(tableViews.keys)
        let newIds = Set(tables.map(\.id))

        // Remove deleted
        for id in currentIds.subtracting(newIds) {
            tableViews[id]?.removeFromSuperview()
            tableViews.removeValue(forKey: id)
        }

        // Add or update
        // Web parity: x,y is the TOP-LEFT corner of the table bounding box
        // (web startDrag stores ox=p.x-item.x, resize writes nx=cx-w/2).
        // UIView.center must be at x + halfW, y + halfH. Drag write-back
        // subtracts the half-dimensions so Supabase always stores top-left.
        for table in tables {
            let body = CanvasTableView.bodySize(for: table)
            let centerX = canvasOrigin.x + CGFloat(table.x) + body.width  / 2
            let centerY = canvasOrigin.y + CGFloat(table.y) + body.height / 2
            if let existing = tableViews[table.id] {
                existing.update(table: table, guests: guests, isSelected: table.id == selectedId)
                existing.center = CGPoint(x: centerX, y: centerY)
            } else {
                let tv = CanvasTableView(table: table, guests: guests, isSelected: table.id == selectedId, zoom: scrollView.zoomScale)
                tv.center = CGPoint(x: centerX, y: centerY)
                tv.onTap = { [weak self] in
                    self?.selectTable(table.id)
                }
                tv.onDragMove = { [weak self] proposed, body in
                    guard let self else { return proposed }
                    let result = self.computeAlignmentSnap(
                        forDragID: table.id, isObject: false,
                        proposedCenter: proposed, size: body)
                    // Fire on engage transition only — see lastSnapX /
                    // lastSnapY ivar comment for the latch contract.
                    if (result.snappedX && !self.lastSnapX) ||
                       (result.snappedY && !self.lastSnapY) {
                        HapticEngine.selection()
                    }
                    self.lastSnapX = result.snappedX
                    self.lastSnapY = result.snappedY
                    return result.center
                }
                tv.onDragEnd = { [weak self] center in
                    self?.clearAlignmentGuides()
                    self?.lastSnapX = false
                    self?.lastSnapY = false
                    // Store top-left: subtract canvasOrigin and half-body
                    let halfW = Double(body.width)  / 2
                    let halfH = Double(body.height) / 2
                    let x = Double(center.x - (self?.canvasOrigin.x ?? 0)) - halfW
                    let y = Double(center.y - (self?.canvasOrigin.y ?? 0)) - halfH
                    self?.delegate?.canvasDidMoveTable(table.id, x: x, y: y)
                }
                contentView.addSubview(tv)
                tableViews[table.id] = tv
            }
        }
    }

    func updateObjects(_ objects: [RoomObject], selectedId: String?) {
        self.currentObjects = objects
        let currentIds = Set(objectViews.keys)
        let newIds = Set(objects.map(\.id))

        for id in currentIds.subtracting(newIds) {
            objectViews[id]?.removeFromSuperview()
            objectViews.removeValue(forKey: id)
        }

        for obj in objects {
            // Same top-left convention as tables — x,y is the bounding-box
            // top-left on web; UIView.center is at x + halfW, y + halfH.
            let halfW = CGFloat(obj.width)  / 2
            let halfH = CGFloat(obj.height) / 2
            let centerX = canvasOrigin.x + CGFloat(obj.x) + halfW
            let centerY = canvasOrigin.y + CGFloat(obj.y) + halfH
            if let existing = objectViews[obj.id] {
                existing.update(object: obj, isSelected: obj.id == selectedId)
                existing.center = CGPoint(x: centerX, y: centerY)
            } else {
                let ov = CanvasObjectView(object: obj, isSelected: obj.id == selectedId)
                ov.center = CGPoint(x: centerX, y: centerY)
                ov.onTap = { [weak self] in
                    self?.selectObject(obj.id)
                }
                ov.onDragMove = { [weak self] proposed, body in
                    guard let self else { return proposed }
                    let result = self.computeAlignmentSnap(
                        forDragID: obj.id, isObject: true,
                        proposedCenter: proposed, size: body)
                    if (result.snappedX && !self.lastSnapX) ||
                       (result.snappedY && !self.lastSnapY) {
                        HapticEngine.selection()
                    }
                    self.lastSnapX = result.snappedX
                    self.lastSnapY = result.snappedY
                    return result.center
                }
                ov.onDragEnd = { [weak self] center in
                    self?.clearAlignmentGuides()
                    self?.lastSnapX = false
                    self?.lastSnapY = false
                    // Store top-left: subtract canvasOrigin and half-body
                    let x = Double(center.x - (self?.canvasOrigin.x ?? 0)) - Double(halfW)
                    let y = Double(center.y - (self?.canvasOrigin.y ?? 0)) - Double(halfH)
                    self?.delegate?.canvasDidMoveObject(obj.id, x: x, y: y)
                }
                contentView.addSubview(ov)
                objectViews[obj.id] = ov
            }
        }
    }

    // MARK: - Selection

    private func selectTable(_ id: String) {
        selectedId = id
        selectedType = "table"
        updateSelectionVisuals()
        delegate?.canvasDidSelectTable(id)
    }

    private func selectObject(_ id: String) {
        selectedId = id
        selectedType = "object"
        updateSelectionVisuals()
        delegate?.canvasDidSelectObject(id)
    }

    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: contentView)
        // Check if tap hit any item
        for (_, tv) in tableViews {
            if tv.frame.contains(location) { return }
        }
        for (_, ov) in objectViews {
            if ov.frame.contains(location) { return }
        }
        // Tapped empty space
        selectedId = nil
        selectedType = nil
        updateSelectionVisuals()
        delegate?.canvasDidDeselectAll()
    }

    private func updateSelectionVisuals() {
        for (id, tv) in tableViews {
            tv.setSelected(id == selectedId)
        }
        for (id, ov) in objectViews {
            ov.setSelected(id == selectedId)
        }
    }
}

// MARK: - Dot Pattern Layer

class DotPatternLayer: CALayer {
    override func draw(in ctx: CGContext) {
        let spacing: CGFloat = 18
        let dotSize: CGFloat = 2
        let gold = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 0.12)

        ctx.setFillColor(gold.cgColor)
        var x: CGFloat = spacing
        while x < bounds.width {
            var y: CGFloat = spacing
            while y < bounds.height {
                ctx.fillEllipse(in: CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize))
                y += spacing
            }
            x += spacing
        }
    }
}

// MARK: - Draggable Table View

class CanvasTableView: UIView {
    var onTap: (() -> Void)?
    /// Called on each pan tick with the proposed centre + body size.
    /// Receiver can return a snapped centre (alignment guides) which
    /// the view will adopt instead of the raw finger position.
    var onDragMove: ((CGPoint, CGSize) -> CGPoint)?
    var onDragEnd: ((CGPoint) -> Void)?

    private var table: SeatTable
    private var isItemSelected = false

    // Padding around the body for seats (~14pt outside) + selection halo + label slack.
    // Selection glow is the largest at +20pt outside the body, so 28 leaves room.
    private let padding: CGFloat = 28

    // ATM palette (web parity — App.jsx atmospheric redesign commit ad49273).
    private static let atmPaper    = UIColor(red: 251/255, green: 247/255, blue: 236/255, alpha: 1) // #FBF7EC
    private static let atmInk      = UIColor(red:  45/255, green:  45/255, blue:  45/255, alpha: 1) // #2D2D2D
    private static let atmInk2     = UIColor(red: 107/255, green: 101/255, blue:  92/255, alpha: 1) // #6b655c
    private static let atmGold     = UIColor(red: 201/255, green: 169/255, blue:  97/255, alpha: 1) // #C9A961
    private static let atmGoldGlow = UIColor(red: 201/255, green: 169/255, blue:  97/255, alpha: 0.25) // rgba(201,169,97,.25)

    // Layered render — back-to-front:
    //   glow → dashedRing → progress → body → colorRing → name → count
    private let glowLayer       = CAShapeLayer() // soft gold halo when selected
    private let dashedRingLayer = CAShapeLayer() // dashed gold ring outside body when selected
    private let progressLayer   = CAShapeLayer() // gold arc / line showing seated/total
    private let shapeLayer      = CAShapeLayer() // body fill (paper, or ink for head)
    private let colorRingLayer  = CAShapeLayer() // inner ring tinted with table.color
    private let label           = UILabel()      // table name (italic serif)
    private let countLabel      = UILabel()      // seat count (mono) — pill background when full
    private var seatLayers: [CAShapeLayer] = []
    private var seatInitialLayers: [CATextLayer] = [] // initials shown when zoom ≥ threshold
    private let lockBadge = UIImageView()

    /// Zoom-aware seat-label gating. Three tiers, matching what web
    /// shows when zoomed all the way in:
    ///   < 1.3×  → small dots only
    ///   1.3×–2× → larger dots + 2-letter initials
    ///   ≥ 2×   → larger dots + full first name (web parity)
    private static let seatLabelZoomThreshold: CGFloat = 1.3
    private static let seatLabelFullNameZoomThreshold: CGFloat = 2.0
    private var currentZoom: CGFloat = 1.0
    /// Cache of seatIndex → guest so the parent can change the zoom
    /// without re-passing the guest list each time.
    private var seatGuestByIndex: [Int: Guest] = [:]
    private var lastBodyCenter: CGPoint = .zero
    private var lastBody: CGSize = .zero

    init(table: SeatTable, guests: [Guest], isSelected: Bool, zoom: CGFloat = 1.0) {
        self.table = table
        self.isItemSelected = isSelected
        self.currentZoom = zoom
        super.init(frame: .zero)
        setupView()
        update(table: table, guests: guests, isSelected: isSelected)
        setupGestures()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupView() {
        backgroundColor = .clear

        // Selection glow — soft solid halo behind everything.
        glowLayer.fillColor = CanvasTableView.atmGoldGlow.cgColor
        glowLayer.strokeColor = UIColor.clear.cgColor
        glowLayer.isHidden = true
        layer.addSublayer(glowLayer)

        // Dashed gold ring outside body (round / oval / sweetheart only — rect
        // gets just the rounded glow rect).
        dashedRingLayer.strokeColor = CanvasTableView.atmGold.cgColor
        dashedRingLayer.fillColor = UIColor.clear.cgColor
        dashedRingLayer.lineWidth = 1
        dashedRingLayer.lineDashPattern = [2, 4]
        dashedRingLayer.isHidden = true
        layer.addSublayer(dashedRingLayer)

        // Gold progress indicator — strokeStart/strokeEnd on a closed path
        // for round/oval, or a horizontal stroke for rect.
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = CanvasTableView.atmGold.cgColor
        progressLayer.lineWidth = 3.5
        progressLayer.lineCap = .round
        progressLayer.isHidden = true
        layer.addSublayer(progressLayer)

        // Body — paper fill with a soft drop shadow. Filled separately
        // per-update because head tables flip to ink.
        shapeLayer.strokeColor = UIColor.clear.cgColor
        shapeLayer.shadowColor = UIColor.black.cgColor
        shapeLayer.shadowOpacity = 0.16
        shapeLayer.shadowOffset = CGSize(width: 0, height: 2)
        shapeLayer.shadowRadius = 3
        layer.addSublayer(shapeLayer)

        // Inner color ring — at body radius - 5pt, tinted with table.color.
        colorRingLayer.fillColor = UIColor.clear.cgColor
        colorRingLayer.lineWidth = 2.5
        colorRingLayer.opacity = 0.55
        layer.addSublayer(colorRingLayer)

        // Italic serif for the table name (web uses Fraunces; iOS ships
        // Georgia which has the closest cut and is bundled with the OS).
        label.textAlignment = .center
        label.font = UIFont(name: "Georgia-Italic", size: 11)
            ?? UIFont.italicSystemFont(ofSize: 11)
        label.textColor = CanvasTableView.atmInk
        addSubview(label)

        // Mono seat count. Becomes a gold pill ("8/8 ✓") when full;
        // otherwise plain text in ink2.
        countLabel.textAlignment = .center
        countLabel.font = UIFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
        countLabel.textColor = CanvasTableView.atmInk2
        countLabel.layer.cornerRadius = 8
        countLabel.layer.masksToBounds = true
        addSubview(countLabel)

        // Lock badge — shown when the table is marked locked. Sits in
        // the top-right corner of the bounding box. Web shows a lock
        // icon overlay on the table; this is the iOS equivalent.
        lockBadge.image = UIImage(systemName: "lock.fill")
        lockBadge.tintColor = UIColor(red: 168/255, green: 136/255, blue: 67/255, alpha: 1) // sbGoldDk
        lockBadge.contentMode = .scaleAspectFit
        lockBadge.isHidden = true
        // Soft cream chip behind the icon so it reads against any table colour.
        lockBadge.backgroundColor = UIColor(red: 255/255, green: 254/255, blue: 249/255, alpha: 0.95)
        lockBadge.layer.cornerRadius = 8
        lockBadge.layer.borderColor = UIColor(red: 168/255, green: 136/255, blue: 67/255, alpha: 0.35).cgColor
        lockBadge.layer.borderWidth = 0.5
        addSubview(lockBadge)
    }

    func update(table: SeatTable, guests: [Guest], isSelected: Bool) {
        self.table = table
        self.isItemSelected = isSelected

        let body = CanvasTableView.bodySize(for: table)
        let savedCenter = self.center
        frame.size = CGSize(width: body.width + padding * 2, height: body.height + padding * 2)
        if savedCenter != .zero { self.center = savedCenter }

        let bodyCenter = CGPoint(x: padding + body.width/2, y: padding + body.height/2)
        let isHead = table.type == .head
        let total = max(table.seats, 1)
        let filled = max(0, min(table.filledCount, total))
        let frac = Double(filled) / Double(total)
        let isFull = filled == total && total > 0

        // Suppress implicit animations on path/colour churn so dragging
        // a table doesn't smear seat dots across the canvas.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // ── Body ───────────────────────────────────────────────────────
        let bodyPath = CanvasTableView.shapePath(for: table, body: body, center: bodyCenter)
        shapeLayer.path = bodyPath.cgPath
        shapeLayer.shadowPath = bodyPath.cgPath
        shapeLayer.fillColor = isHead
            ? CanvasTableView.atmInk.cgColor
            : CanvasTableView.atmPaper.cgColor

        // ── Inner colour ring (skip for head — ink body absorbs it) ──
        let tableColor = UIColor(hex: table.color ?? "") ?? CanvasTableView.atmGold
        if isHead {
            colorRingLayer.path = nil
        } else {
            colorRingLayer.path = CanvasTableView.colorRingPath(for: table, body: body, center: bodyCenter).cgPath
            colorRingLayer.strokeColor = tableColor.cgColor
        }

        // ── Selection glow + dashed ring ──────────────────────────────
        glowLayer.path = CanvasTableView.glowPath(for: table, body: body, center: bodyCenter).cgPath
        glowLayer.isHidden = !isSelected
        if let dashed = CanvasTableView.dashedRingPath(for: table, body: body, center: bodyCenter) {
            dashedRingLayer.path = dashed.cgPath
            dashedRingLayer.isHidden = !isSelected
        } else {
            dashedRingLayer.path = nil
            dashedRingLayer.isHidden = true
        }

        // ── Progress indicator (arc for round/oval, line for rect) ────
        configureProgressLayer(table: table, body: body, center: bodyCenter, frac: frac, isHead: isHead)

        // ── Name label ────────────────────────────────────────────────
        label.text = table.name
        label.textColor = isHead ? CanvasTableView.atmPaper : CanvasTableView.atmInk
        let nameYOffset: CGFloat = (table.type == .sweetheart) ? -8 : 0
        label.frame = CGRect(x: padding, y: bodyCenter.y + nameYOffset - 7, width: body.width, height: 14)

        // ── Seat count ────────────────────────────────────────────────
        configureCountLabel(table: table, body: body, center: bodyCenter,
                            filled: filled, total: total, isFull: isFull, isHead: isHead)

        // ── Seat dots / initials ──────────────────────────────────────
        // Build the seat-index → guest cache so setZoom() can re-render
        // initials later without re-passing the guest list.
        seatGuestByIndex.removeAll(keepingCapacity: true)
        for (gid, idx) in table.assignments {
            if let g = guests.first(where: { $0.id == gid }) {
                seatGuestByIndex[idx] = g
            }
        }
        lastBodyCenter = bodyCenter
        lastBody = body
        renderSeats(table: table, body: body, center: bodyCenter, filled: filled)

        // Lock badge — centred horizontally on the table, sitting just
        // above the table-name label so it reads as "this table is
        // locked" without overlapping seats or sticking outside the body.
        let badgeSize: CGFloat = 14
        lockBadge.frame = CGRect(
            x: bodyCenter.x - badgeSize / 2,
            y: label.frame.minY - badgeSize - 2,
            width: badgeSize, height: badgeSize
        )
        lockBadge.isHidden = (table.locked != true)

        CATransaction.commit()
        applyTransform(animated: false)
    }

    /// Re-render seat dots (and initials, when zoomed in past the threshold).
    /// Cheap to call repeatedly — wipes its own layers on each invocation.
    private func renderSeats(table: SeatTable, body: CGSize, center bodyCenter: CGPoint, filled: Int) {
        seatLayers.forEach { $0.removeFromSuperlayer() }
        seatLayers = []
        seatInitialLayers.forEach { $0.removeFromSuperlayer() }
        seatInitialLayers = []

        let showInitials = currentZoom >= Self.seatLabelZoomThreshold
        let showFullName = currentZoom >= Self.seatLabelFullNameZoomThreshold
        let dotSize: CGFloat = showInitials ? 18 : 8
        let gold = CanvasTableView.atmGold
        let emptyStroke = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 0.45)

        let seatPositions = CanvasTableView.seatPositions(for: table, body: body, center: bodyCenter)
        for (i, pos) in seatPositions.enumerated() {
            let dot = CAShapeLayer()
            let r = CGRect(x: pos.x - dotSize/2, y: pos.y - dotSize/2, width: dotSize, height: dotSize)
            dot.path = UIBezierPath(ovalIn: r).cgPath
            if i < filled {
                dot.fillColor = gold.cgColor
                dot.strokeColor = gold.cgColor
                dot.lineWidth = 1
            } else {
                dot.fillColor = UIColor.clear.cgColor
                dot.strokeColor = emptyStroke.cgColor
                dot.lineWidth = 1.5
            }
            layer.addSublayer(dot)
            seatLayers.append(dot)

            // Seat label — only when zoomed past at least the initials
            // threshold AND the seat is filled. Two label modes:
            //   - `showFullName` (zoom ≥ 2×): render the guest's first
            //     name BELOW the seat dot (web parity), so the dot
            //     itself stays uncluttered and the name doesn't
            //     fight the seat for the same pixels
            //   - `showInitials` (1.3× ≤ zoom < 2×): two-letter
            //     initials INSIDE the dot, as before
            if showInitials, let guest = seatGuestByIndex[i] {
                let text = CATextLayer()
                text.contentsScale = UIScreen.main.scale
                text.alignmentMode = .center
                if showFullName {
                    text.string = Self.firstName(for: guest.displayName)
                    text.foregroundColor = CanvasTableView.atmInk.cgColor
                    text.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
                    text.fontSize = 10
                    // Sit BELOW the dot so it doesn't overlap the seat
                    // glyph. Width is generous so longer names don't
                    // clip; CATextLayer truncates by default if it
                    // really overflows.
                    let labelWidth: CGFloat = 70
                    let labelHeight: CGFloat = 12
                    text.frame = CGRect(
                        x: pos.x - labelWidth / 2,
                        y: pos.y + dotSize / 2 + 2,
                        width: labelWidth, height: labelHeight
                    )
                } else {
                    text.string = Self.initials(for: guest.displayName)
                    text.foregroundColor = CanvasTableView.atmPaper.cgColor
                    text.font = UIFont.systemFont(ofSize: 9, weight: .semibold)
                    text.fontSize = 9
                    let textHeight: CGFloat = 11
                    text.frame = CGRect(x: pos.x - dotSize/2,
                                        y: pos.y - textHeight/2,
                                        width: dotSize, height: textHeight)
                }
                layer.addSublayer(text)
                seatInitialLayers.append(text)
            }
        }
    }

    /// First-name extractor for canvas labels at high zoom. Mirrors
    /// web's `displayName` first-token convention.
    private static func firstName(for name: String) -> String {
        let parts = name.split(separator: " ")
        return String(parts.first ?? Substring(name))
    }

    /// Two-letter initials matching SBAvatar's logic so canvas + drawer agree.
    private static func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Called by the parent view controller when the canvas zoom changes.
    /// Re-renders seats when EITHER threshold is crossed (initials at
    /// 1.3× or full-name at 2×) so we pick up label-mode changes
    /// without thrashing CATextLayers on every zoom delta.
    func setZoom(_ zoom: CGFloat) {
        let oldTier = labelTier(for: currentZoom)
        let newTier = labelTier(for: zoom)
        currentZoom = zoom
        guard oldTier != newTier, lastBody != .zero else { return }
        let total = max(table.seats, 1)
        let filled = max(0, min(table.filledCount, total))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderSeats(table: table, body: lastBody, center: lastBodyCenter, filled: filled)
        CATransaction.commit()
    }

    private func labelTier(for zoom: CGFloat) -> Int {
        if zoom >= Self.seatLabelFullNameZoomThreshold { return 2 }
        if zoom >= Self.seatLabelZoomThreshold { return 1 }
        return 0
    }

    // MARK: - Progress / count helpers

    private func configureProgressLayer(table: SeatTable, body: CGSize, center c: CGPoint,
                                        frac: Double, isHead: Bool) {
        // Hide for sweetheart (no count visualisation needed) and head
        // tables (the ink fill is its own visual marker).
        guard !isHead, table.type != .sweetheart, frac > 0 else {
            progressLayer.isHidden = true
            progressLayer.path = nil
            return
        }
        progressLayer.isHidden = false

        switch table.type {
        case .round:
            let r = body.width / 2 + 4
            let arc = UIBezierPath(arcCenter: c, radius: r,
                                    startAngle: -.pi / 2,
                                    endAngle: -.pi / 2 + .pi * 2,
                                    clockwise: true)
            progressLayer.path = arc.cgPath
            progressLayer.lineWidth = 3.5
            progressLayer.strokeStart = 0
            progressLayer.strokeEnd = CGFloat(frac)
        case .oval:
            // Approximate the oval by using the body's enclosing rect at +4pt.
            let rect = CGRect(x: c.x - body.width/2 - 4,
                              y: c.y - body.height/2 - 4,
                              width: body.width + 8, height: body.height + 8)
            // Build an ellipse path manually starting at the top so
            // strokeEnd goes clockwise from 12 o'clock — matches web.
            let path = UIBezierPath()
            let steps = 64
            for i in 0...steps {
                let t = Double(i) / Double(steps) * .pi * 2 - .pi / 2
                let p = CGPoint(x: rect.midX + (rect.width / 2) * CGFloat(cos(t)),
                                y: rect.midY + (rect.height / 2) * CGFloat(sin(t)))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.close()
            progressLayer.path = path.cgPath
            progressLayer.lineWidth = 3.5
            progressLayer.strokeStart = 0
            progressLayer.strokeEnd = CGFloat(frac)
        case .rect:
            // Horizontal line under the table label at the bottom edge.
            let inset: CGFloat = 6
            let y = c.y + body.height / 2 - 4
            let startX = c.x - body.width / 2 + inset
            let endX   = startX + (body.width - inset * 2) * CGFloat(frac)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
            progressLayer.path = path.cgPath
            progressLayer.lineWidth = 2.5
            progressLayer.strokeStart = 0
            progressLayer.strokeEnd = 1
        case .head, .sweetheart:
            progressLayer.isHidden = true
            progressLayer.path = nil
        }
    }

    private func configureCountLabel(table: SeatTable, body: CGSize, center c: CGPoint,
                                     filled: Int, total: Int, isFull: Bool, isHead: Bool) {
        // Sweetheart never shows a count.
        guard table.type != .sweetheart else {
            countLabel.isHidden = true
            return
        }
        countLabel.isHidden = false

        let text = isFull ? "\(filled)/\(total) ✓" : "\(filled)/\(total)"
        countLabel.text = text

        if isFull {
            // Gold pill inside the body, just below the centred name.
            countLabel.backgroundColor = isHead ? CanvasTableView.atmGold : CanvasTableView.atmGold
            countLabel.textColor = isHead ? CanvasTableView.atmInk : CanvasTableView.atmPaper
            let pillSize = CGSize(width: 44, height: 16)
            countLabel.frame = CGRect(x: c.x - pillSize.width / 2,
                                       y: c.y + 8,
                                       width: pillSize.width, height: pillSize.height)
        } else {
            countLabel.backgroundColor = .clear
            countLabel.textColor = isHead
                ? CanvasTableView.atmGold
                : CanvasTableView.atmInk2
            // All shapes: count sits just below the centred name inside the body.
            let yOffset: CGFloat
            switch table.type {
            case .round:        yOffset = c.y + 10
            case .oval:         yOffset = c.y + 11
            case .rect, .head:  yOffset = c.y + 10
            case .sweetheart:   yOffset = c.y + 10  // unused
            }
            countLabel.frame = CGRect(x: c.x - 28, y: yOffset, width: 56, height: 12)
        }
    }

    func setSelected(_ selected: Bool) {
        isItemSelected = selected
        glowLayer.isHidden = !selected
        // Dashed ring is only configured for shapes that use it (round /
        // oval / sweetheart); preserve hidden state when path is nil.
        if dashedRingLayer.path != nil {
            dashedRingLayer.isHidden = !selected
        }
        UIView.animate(withDuration: 0.2) {
            self.applyTransform(animated: true)
        }
    }

    private func applyTransform(animated: Bool) {
        let rotation = CGFloat((table.rotation ?? 0) * .pi / 180)
        let scale: CGFloat = isItemSelected ? 1.06 : 1.0
        transform = CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale)
    }

    // MARK: - Shape geometry (mirrors web `Table` component in src/App.jsx)

    static func bodySize(for table: SeatTable) -> CGSize {
        switch table.type {
        case .round:
            let d = CGFloat(table.diameter ?? 90)
            return CGSize(width: d, height: d)
        case .rect:
            return CGSize(width: CGFloat(table.width ?? 100), height: CGFloat(table.height ?? 50))
        case .head:
            return CGSize(width: CGFloat(table.width ?? 280), height: CGFloat(table.height ?? 50))
        case .sweetheart:
            return CGSize(width: CGFloat(table.width ?? 100), height: CGFloat(table.height ?? 60))
        case .oval:
            // Web default: 8ft × 4ft (=120×60 at scale 15) — see App.jsx:8453.
            return CGSize(width: CGFloat(table.width ?? 120), height: CGFloat(table.height ?? 60))
        }
    }

    private static func shapePath(for table: SeatTable, body: CGSize, center c: CGPoint) -> UIBezierPath {
        switch table.type {
        case .round:
            return UIBezierPath(arcCenter: c, radius: body.width / 2,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)
        case .rect, .head:
            let rect = CGRect(x: c.x - body.width/2, y: c.y - body.height/2,
                              width: body.width, height: body.height)
            return UIBezierPath(roundedRect: rect, cornerRadius: 6)
        case .sweetheart:
            return sweetheartPath(shape: table.sweetShape, body: body, center: c)
        case .oval:
            // Web renders <ellipse rx={w/2} ry={h/2}> — App.jsx:7466.
            let rect = CGRect(x: c.x - body.width/2, y: c.y - body.height/2,
                              width: body.width, height: body.height)
            return UIBezierPath(ovalIn: rect)
        }
    }

    /// Soft glow halo behind the table when selected. Web parity:
    /// circle/ellipse at body+20pt, rounded rect at body+20pt for rect/head.
    private static func glowPath(for table: SeatTable, body: CGSize, center c: CGPoint) -> UIBezierPath {
        switch table.type {
        case .round:
            return UIBezierPath(arcCenter: c, radius: body.width / 2 + 20,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)
        case .oval:
            let rect = CGRect(x: c.x - body.width/2 - 20, y: c.y - body.height/2 - 20,
                              width: body.width + 40, height: body.height + 40)
            return UIBezierPath(ovalIn: rect)
        case .rect, .head:
            let rect = CGRect(x: c.x - body.width/2 - 10, y: c.y - body.height/2 - 10,
                              width: body.width + 20, height: body.height + 20)
            return UIBezierPath(roundedRect: rect, cornerRadius: 14)
        case .sweetheart:
            let inflated = CGSize(width: body.width + 20, height: body.height + 20)
            return sweetheartPath(shape: table.sweetShape, body: inflated, center: c)
        }
    }

    /// Dashed gold ring outside the body when selected. Only emitted for
    /// shapes that take it (web only draws it on round / oval / sweetheart;
    /// rect / head get the rounded glow rect alone).
    private static func dashedRingPath(for table: SeatTable, body: CGSize, center c: CGPoint) -> UIBezierPath? {
        switch table.type {
        case .round:
            return UIBezierPath(arcCenter: c, radius: body.width / 2 + 11,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)
        case .oval:
            let rect = CGRect(x: c.x - body.width/2 - 11, y: c.y - body.height/2 - 11,
                              width: body.width + 22, height: body.height + 22)
            return UIBezierPath(ovalIn: rect)
        case .sweetheart:
            let inflated = CGSize(width: body.width + 18, height: body.height + 18)
            return sweetheartPath(shape: table.sweetShape, body: inflated, center: c)
        case .rect, .head:
            return nil
        }
    }

    /// Inner colour ring at body radius - 5pt — replaces the old "fill the
    /// body with table.color" so the colour reads as a thin tint instead.
    private static func colorRingPath(for table: SeatTable, body: CGSize, center c: CGPoint) -> UIBezierPath {
        switch table.type {
        case .round:
            return UIBezierPath(arcCenter: c, radius: max(body.width / 2 - 5, 1),
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)
        case .oval:
            let rect = CGRect(x: c.x - body.width/2 + 5, y: c.y - body.height/2 + 5,
                              width: max(body.width - 10, 1), height: max(body.height - 10, 1))
            return UIBezierPath(ovalIn: rect)
        case .rect:
            // For rect tables web draws a 3px colour line under the body
            // instead of an inner ring — render that as a horizontal path
            // so the colour ring layer's line cap sells it.
            let path = UIBezierPath()
            let y = c.y + body.height / 2 + 5
            path.move(to: CGPoint(x: c.x - body.width / 2 + 6, y: y))
            path.addLine(to: CGPoint(x: c.x + body.width / 2 - 6, y: y))
            return path
        case .head, .sweetheart:
            // Head body is ink (no colour ring); sweetheart uses paper +
            // glow, no ring either.
            return UIBezierPath()
        }
    }

    private static func sweetheartPath(shape: String?, body: CGSize, center c: CGPoint) -> UIBezierPath {
        let w = body.width
        let h = body.height
        switch (shape ?? "heart").lowercased() {
        case "oval":
            return UIBezierPath(ovalIn: CGRect(x: c.x - w/2, y: c.y - h/2, width: w, height: h))
        case "diamond", "rect", "rectangle":
            return UIBezierPath(roundedRect: CGRect(x: c.x - w/2, y: c.y - h/2, width: w, height: h), cornerRadius: 8)
        default: // heart — matches web SweetheartShape quadratic-curve path
            let path = UIBezierPath()
            path.move(to: CGPoint(x: c.x - w/2, y: c.y))
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h/2),
                              controlPoint: CGPoint(x: c.x - w/2, y: c.y - h/2))
            path.addQuadCurve(to: CGPoint(x: c.x + w/2, y: c.y),
                              controlPoint: CGPoint(x: c.x + w/2, y: c.y - h/2))
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h/2),
                              controlPoint: CGPoint(x: c.x + w/2, y: c.y + h/3))
            path.addQuadCurve(to: CGPoint(x: c.x - w/2, y: c.y),
                              controlPoint: CGPoint(x: c.x - w/2, y: c.y + h/3))
            path.close()
            return path
        }
    }

    private static func seatPositions(for table: SeatTable, body: CGSize, center c: CGPoint) -> [CGPoint] {
        let n = max(0, table.seats)
        guard n > 0 else { return [] }
        let offset: CGFloat = 14

        switch table.type {
        case .round:
            let r = body.width / 2
            return (0..<n).map { i in
                let ang = CGFloat(i) / CGFloat(n) * .pi * 2 - .pi / 2
                return CGPoint(x: c.x + cos(ang) * (r + offset),
                               y: c.y + sin(ang) * (r + offset))
            }
        case .oval:
            // Distribute seats evenly by angle around the ellipse, with
            // each seat sitting `offset` outside the perimeter. Same start
            // angle as round (-π/2 = top) for visual consistency.
            let rx = body.width / 2 + offset
            let ry = body.height / 2 + offset
            return (0..<n).map { i in
                let ang = CGFloat(i) / CGFloat(n) * .pi * 2 - .pi / 2
                return CGPoint(x: c.x + cos(ang) * rx,
                               y: c.y + sin(ang) * ry)
            }
        case .sweetheart:
            // Web hardcodes 2 seats at the bottom regardless of seat count.
            let count = min(n, 2)
            let y = c.y + body.height/2 + offset
            if count == 1 { return [CGPoint(x: c.x, y: y)] }
            return [
                CGPoint(x: c.x - body.width/4, y: y),
                CGPoint(x: c.x + body.width/4, y: y),
            ]
        case .rect, .head:
            let w = body.width
            let h = body.height
            if table.oneSide == true {
                let sp = w / CGFloat(n + 1)
                return (0..<n).map { i in
                    CGPoint(x: c.x - w/2 + sp * CGFloat(i + 1), y: c.y - h/2 - offset)
                }
            }
            // Default two-side: top + bottom edges, with top getting the extra when odd.
            let top = (n + 1) / 2
            let bot = n - top
            let sp = w / CGFloat(max(top, bot) + 1)
            var seats: [CGPoint] = []
            for i in 0..<top {
                seats.append(CGPoint(x: c.x - w/2 + sp * CGFloat(i + 1), y: c.y - h/2 - offset))
            }
            for i in 0..<bot {
                seats.append(CGPoint(x: c.x - w/2 + sp * CGFloat(i + 1), y: c.y + h/2 + offset))
            }
            return seats
        }
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        isUserInteractionEnabled = true
    }

    @objc private func handleTap() {
        onTap?()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard table.locked != true else { return }
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)

        switch gesture.state {
        case .changed:
            let proposed = CGPoint(x: center.x + translation.x,
                                   y: center.y + translation.y)
            // Ask the parent for an alignment-snapped centre. When snap
            // engages the view position lags the finger; we feed the
            // unconsumed delta back into the gesture so the snap releases
            // smoothly once the finger moves past the threshold.
            let body = CanvasTableView.bodySize(for: table)
            let snapped = onDragMove?(proposed, body) ?? proposed
            center = snapped
            gesture.setTranslation(CGPoint(x: proposed.x - snapped.x,
                                           y: proposed.y - snapped.y),
                                   in: superview)
        case .ended, .cancelled:
            onDragEnd?(center)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        default: break
        }
    }
}

// MARK: - Draggable Object View

class CanvasObjectView: UIView {
    var onTap: (() -> Void)?
    var onDragMove: ((CGPoint, CGSize) -> CGPoint)?
    var onDragEnd: ((CGPoint) -> Void)?

    private var object: RoomObject
    private var isItemSelected = false

    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let lockBadge = UIImageView()

    init(object: RoomObject, isSelected: Bool) {
        self.object = object
        self.isItemSelected = isSelected
        super.init(frame: CGRect(x: 0, y: 0, width: object.width, height: object.height))
        setupView()
        update(object: object, isSelected: isSelected)
        setupGestures()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupView() {
        layer.cornerRadius = 8
        clipsToBounds = true

        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)

        nameLabel.textAlignment = .center
        // Web parity (App.jsx ce0ed39): venue object labels use italic
        // serif. Georgia is the closest cut iOS ships built-in.
        nameLabel.font = UIFont(name: "Georgia-Italic", size: 9)
            ?? UIFont.italicSystemFont(ofSize: 9)
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7
        addSubview(nameLabel)

        lockBadge.image = UIImage(systemName: "lock.fill")
        lockBadge.tintColor = UIColor(red: 168/255, green: 136/255, blue: 67/255, alpha: 1)
        lockBadge.contentMode = .scaleAspectFit
        lockBadge.backgroundColor = UIColor(red: 255/255, green: 254/255, blue: 249/255, alpha: 0.95)
        lockBadge.layer.cornerRadius = 8
        lockBadge.layer.borderColor = UIColor(red: 168/255, green: 136/255, blue: 67/255, alpha: 0.35).cgColor
        lockBadge.layer.borderWidth = 0.5
        lockBadge.isHidden = true
        addSubview(lockBadge)
    }

    func update(object: RoomObject, isSelected: Bool) {
        self.object = object
        self.isItemSelected = isSelected
        // Reset transform before resizing — UIKit's frame.size setter
        // doesn't behave the way you expect on a rotated view, and we
        // want the underlying bounds to reflect the unrotated body
        // before re-applying the rotation transform below.
        transform = .identity
        frame.size = CGSize(width: object.width, height: object.height)

        let def = venueObjectTypes.first { $0.type == object.type }
        let colorHex = def?.color ?? "#8B8680"
        backgroundColor = UIColor(hex: colorHex)?.withAlphaComponent(0.85)

        let isDark = colorHex == "#2D2D2D"
        let textColor: UIColor = isDark ? .white : UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 0.7)

        // Resolve via VenueIconMap so web-style icon names ("music",
        // "glass", etc.) and any pre-existing SF-symbol-style names both
        // render to a real glyph instead of falling through to a ?.
        let symbolName = VenueIconMap.sfSymbol(for: def?.icon ?? object.icon)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        iconView.image = UIImage(systemName: symbolName, withConfiguration: config)?
            .withRenderingMode(.alwaysTemplate)
        iconView.tintColor = textColor
        let iconSize: CGFloat = 24
        iconView.frame = CGRect(
            x: (bounds.width - iconSize) / 2,
            y: bounds.height/2 - iconSize - 2,
            width: iconSize,
            height: iconSize
        )

        nameLabel.text = object.name
        nameLabel.textColor = isDark ? .white : UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 1)
        nameLabel.frame = CGRect(x: 4, y: bounds.height/2 + 4, width: bounds.width - 8, height: 14)

        layer.borderWidth = isSelected ? 2 : 0
        layer.borderColor = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 1).cgColor

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = isSelected ? 0.2 : 0.1
        layer.shadowRadius = isSelected ? 8 : 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        let badgeSize: CGFloat = 16
        lockBadge.frame = CGRect(x: bounds.width - badgeSize - 4, y: 4, width: badgeSize, height: badgeSize)
        lockBadge.isHidden = (object.locked != true)

        // Apply object.rotation as a CGAffineTransform — same way
        // CanvasTableView handles table rotation. Without this, the
        // VenueObjects sheet's rotation slider wrote to plan state
        // but the canvas never updated visually until the user
        // dragged the object or re-entered the editor.
        let rad = CGFloat((object.rotation ?? 0) * .pi / 180)
        if rad != 0 {
            transform = CGAffineTransform(rotationAngle: rad)
        }
    }

    func setSelected(_ selected: Bool) {
        isItemSelected = selected
        UIView.animate(withDuration: 0.2) {
            self.layer.borderWidth = selected ? 2 : 0
            self.layer.shadowOpacity = selected ? 0.2 : 0.1
        }
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        isUserInteractionEnabled = true
    }

    @objc private func handleTap() {
        onTap?()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard object.locked != true else { return }
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)

        switch gesture.state {
        case .changed:
            let proposed = CGPoint(x: center.x + translation.x,
                                   y: center.y + translation.y)
            let snapped = onDragMove?(proposed, frame.size) ?? proposed
            center = snapped
            gesture.setTranslation(CGPoint(x: proposed.x - snapped.x,
                                           y: proposed.y - snapped.y),
                                   in: superview)
        case .ended, .cancelled:
            onDragEnd?(center)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        default: break
        }
    }
}

// MARK: - UIColor hex helper

extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: return nil
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

// MARK: - SwiftUI Wrapper

struct CanvasViewRepresentable: UIViewControllerRepresentable {
    let tables: [SeatTable]
    let objects: [RoomObject]
    let guests: [Guest]
    let selectedTableId: String?
    let selectedObjectId: String?

    // Venue setup — drives the room outline + floor plan backdrop on the canvas.
    var roomShape: String?
    var roomWidth: Double?
    var roomHeight: Double?
    var customRoomPoints: [RoomPoint]?
    var roomFlipH: Bool?
    var roomFlipV: Bool?
    var roomZones: [RoomZone]?
    var floorPlanBase64: String?
    var floorPlanOpacity: Double?
    // Ruler overlay (top + left edges of the room rect). Off by
    // default; toggled via the editor toolbar. Unit drives label
    // suffix + tick spacing — see RoomScale in Models/SeatingPlan.swift.
    var rulerVisible: Bool = false
    var measurementUnit: String?

    // Increment to trigger a fit-to-content zoom on next updateUIViewController.
    var fitToken: Int = 0

    // Used to key viewport persistence (zoom + scroll offset) per plan.
    var planId: String?

    var onSelectTable: (String) -> Void
    var onSelectObject: (String) -> Void
    var onDeselectAll: () -> Void
    var onMoveTable: (String, Double, Double) -> Void
    var onMoveObject: (String, Double, Double) -> Void

    func makeUIViewController(context: Context) -> CanvasViewController {
        let vc = CanvasViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: CanvasViewController, context: Context) {
        vc.setPlanId(planId)
        vc.updateTables(tables, guests: guests, selectedId: selectedTableId)
        vc.updateObjects(objects, selectedId: selectedObjectId)
        vc.updateRoom(
            roomShape: roomShape,
            roomWidth: roomWidth,
            roomHeight: roomHeight,
            customRoomPoints: customRoomPoints,
            roomFlipH: roomFlipH,
            roomFlipV: roomFlipV,
            roomZones: roomZones,
            floorPlanBase64: floorPlanBase64,
            floorPlanOpacity: floorPlanOpacity
        )
        vc.setRulerVisible(rulerVisible, unit: measurementUnit)
        if context.coordinator.lastFitToken != fitToken {
            context.coordinator.lastFitToken = fitToken
            DispatchQueue.main.async { vc.fitToContent(animated: true) }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CanvasDelegate {
        let parent: CanvasViewRepresentable
        var lastFitToken: Int = 0

        init(_ parent: CanvasViewRepresentable) {
            self.parent = parent
        }

        func canvasDidSelectTable(_ tableId: String) {
            parent.onSelectTable(tableId)
        }

        func canvasDidSelectObject(_ objectId: String) {
            parent.onSelectObject(objectId)
        }

        func canvasDidDeselectAll() {
            parent.onDeselectAll()
        }

        func canvasDidMoveTable(_ tableId: String, x: Double, y: Double) {
            parent.onMoveTable(tableId, x, y)
        }

        func canvasDidMoveObject(_ objectId: String, x: Double, y: Double) {
            parent.onMoveObject(objectId, x, y)
        }

        func canvasDidRequestDeleteObject(_ objectId: String) {}
    }
}
