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

        let currentIds = Set(tableViews.keys)
        let newIds = Set(tables.map(\.id))

        // Remove deleted
        for id in currentIds.subtracting(newIds) {
            tableViews[id]?.removeFromSuperview()
            tableViews.removeValue(forKey: id)
        }

        // Add or update
        for table in tables {
            if let existing = tableViews[table.id] {
                existing.update(table: table, guests: guests, isSelected: table.id == selectedId)
                existing.center = CGPoint(x: canvasOrigin.x + table.x, y: canvasOrigin.y + table.y)
            } else {
                let tv = CanvasTableView(table: table, guests: guests, isSelected: table.id == selectedId)
                tv.center = CGPoint(x: canvasOrigin.x + table.x, y: canvasOrigin.y + table.y)
                tv.onTap = { [weak self] in
                    self?.selectTable(table.id)
                }
                tv.onDragEnd = { [weak self] center in
                    let x = Double(center.x - (self?.canvasOrigin.x ?? 0))
                    let y = Double(center.y - (self?.canvasOrigin.y ?? 0))
                    self?.delegate?.canvasDidMoveTable(table.id, x: x, y: y)
                }
                contentView.addSubview(tv)
                tableViews[table.id] = tv
            }
        }
    }

    func updateObjects(_ objects: [RoomObject], selectedId: String?) {
        let currentIds = Set(objectViews.keys)
        let newIds = Set(objects.map(\.id))

        for id in currentIds.subtracting(newIds) {
            objectViews[id]?.removeFromSuperview()
            objectViews.removeValue(forKey: id)
        }

        for obj in objects {
            if let existing = objectViews[obj.id] {
                existing.update(object: obj, isSelected: obj.id == selectedId)
                existing.center = CGPoint(x: canvasOrigin.x + obj.x, y: canvasOrigin.y + obj.y)
            } else {
                let ov = CanvasObjectView(object: obj, isSelected: obj.id == selectedId)
                ov.center = CGPoint(x: canvasOrigin.x + obj.x, y: canvasOrigin.y + obj.y)
                ov.onTap = { [weak self] in
                    self?.selectObject(obj.id)
                }
                ov.onDragEnd = { [weak self] center in
                    let x = Double(center.x - (self?.canvasOrigin.x ?? 0))
                    let y = Double(center.y - (self?.canvasOrigin.y ?? 0))
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
    var onDragEnd: ((CGPoint) -> Void)?

    private var table: SeatTable
    private var isItemSelected = false

    // Padding around the body for seats (~14pt outside) + selection ring + label slack.
    private let padding: CGFloat = 28

    private let shapeLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private let label = UILabel()
    private var seatLayers: [CAShapeLayer] = []
    private let lockBadge = UIImageView()

    init(table: SeatTable, guests: [Guest], isSelected: Bool) {
        self.table = table
        self.isItemSelected = isSelected
        super.init(frame: .zero)
        setupView()
        update(table: table, guests: guests, isSelected: isSelected)
        setupGestures()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupView() {
        backgroundColor = .clear

        selectionLayer.strokeColor = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 1).cgColor
        selectionLayer.fillColor = UIColor.clear.cgColor
        selectionLayer.lineWidth = 2
        selectionLayer.lineDashPattern = [4, 3]
        selectionLayer.isHidden = true
        layer.addSublayer(selectionLayer)

        shapeLayer.strokeColor = UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 0.15).cgColor
        shapeLayer.lineWidth = 1
        layer.addSublayer(shapeLayer)

        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 1)
        addSubview(label)

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

        let bodyPath = CanvasTableView.shapePath(for: table, body: body, center: bodyCenter)
        shapeLayer.path = bodyPath.cgPath
        let fallbackFill = UIColor(red: 247/255, green: 231/255, blue: 206/255, alpha: 1)
        shapeLayer.fillColor = (UIColor(hex: table.color ?? "") ?? fallbackFill).cgColor

        let selPath = CanvasTableView.selectionPath(for: table, body: body, center: bodyCenter)
        selectionLayer.path = selPath.cgPath
        selectionLayer.isHidden = !isSelected

        label.text = table.name
        label.frame = CGRect(x: padding, y: bodyCenter.y - 6, width: body.width, height: 12)

        seatLayers.forEach { $0.removeFromSuperlayer() }
        seatLayers = []

        let dotSize: CGFloat = 8
        let gold = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 1)
        let empty = UIColor(red: 255/255, green: 254/255, blue: 249/255, alpha: 1)
        let emptyStroke = UIColor(red: 185/255, green: 179/255, blue: 166/255, alpha: 1)

        let seatPositions = CanvasTableView.seatPositions(for: table, body: body, center: bodyCenter)
        for (i, pos) in seatPositions.enumerated() {
            let dot = CAShapeLayer()
            let r = CGRect(x: pos.x - dotSize/2, y: pos.y - dotSize/2, width: dotSize, height: dotSize)
            dot.path = UIBezierPath(ovalIn: r).cgPath
            if i < table.filledCount {
                dot.fillColor = gold.cgColor
                dot.strokeColor = gold.cgColor
            } else {
                dot.fillColor = empty.cgColor
                dot.strokeColor = emptyStroke.cgColor
            }
            dot.lineWidth = 1
            layer.addSublayer(dot)
            seatLayers.append(dot)
        }

        // Lock badge — centred horizontally on the table, sitting just
        // above the table-name label so it reads as "this table is
        // locked" without overlapping seats or sticking outside the body.
        let badgeSize: CGFloat = 14
        let labelTopY = bodyCenter.y - 6  // matches label.frame.origin.y above
        lockBadge.frame = CGRect(
            x: bodyCenter.x - badgeSize / 2,
            y: labelTopY - badgeSize - 2,
            width: badgeSize, height: badgeSize
        )
        lockBadge.isHidden = (table.locked != true)

        applyTransform(animated: false)
    }

    func setSelected(_ selected: Bool) {
        isItemSelected = selected
        selectionLayer.isHidden = !selected
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

    private static func bodySize(for table: SeatTable) -> CGSize {
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

    private static func selectionPath(for table: SeatTable, body: CGSize, center c: CGPoint) -> UIBezierPath {
        switch table.type {
        case .round:
            return UIBezierPath(arcCenter: c, radius: body.width / 2 + 10,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)
        case .rect, .head:
            let rect = CGRect(x: c.x - body.width/2 - 6, y: c.y - body.height/2 - 6,
                              width: body.width + 12, height: body.height + 12)
            return UIBezierPath(roundedRect: rect, cornerRadius: 10)
        case .sweetheart:
            let inflated = CGSize(width: body.width + 12, height: body.height + 12)
            return sweetheartPath(shape: table.sweetShape, body: inflated, center: c)
        case .oval:
            let inflated = CGRect(x: c.x - body.width/2 - 6, y: c.y - body.height/2 - 6,
                                  width: body.width + 12, height: body.height + 12)
            return UIBezierPath(ovalIn: inflated)
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
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)

        switch gesture.state {
        case .changed:
            center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
            gesture.setTranslation(.zero, in: superview)
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
    var onDragEnd: ((CGPoint) -> Void)?

    private var object: RoomObject
    private var isItemSelected = false

    private let iconView = UIImageView()
    private let nameLabel = UILabel()

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
        nameLabel.font = UIFont.systemFont(ofSize: 9, weight: .medium)
        addSubview(nameLabel)
    }

    func update(object: RoomObject, isSelected: Bool) {
        self.object = object
        self.isItemSelected = isSelected
        frame.size = CGSize(width: object.width, height: object.height)

        let def = venueObjectTypes.first { $0.type == object.type }
        let colorHex = def?.color ?? "#8B8680"
        backgroundColor = UIColor(hex: colorHex)?.withAlphaComponent(0.85)

        let isDark = colorHex == "#2D2D2D"
        let textColor: UIColor = isDark ? .white : UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 0.7)

        let symbolName = def?.icon ?? "questionmark.circle"
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
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)

        switch gesture.state {
        case .changed:
            center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
            gesture.setTranslation(.zero, in: superview)
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
