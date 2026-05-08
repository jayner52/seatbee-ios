import UIKit

// MARK: - Floor plan renderer for PDF exports
//
// Web parity: the web Seating Chart PDF (App.jsx exportPDF ~13800)
// captures the editor SVG via html2canvas → image → embeds in jsPDF.
// iOS draws a printable equivalent in pure Core Graphics — same data
// (tables, objects, room outline, seat dots) rendered cleanly for print.
// Visual style intentionally diverges from the live editor: no glow,
// no atmospheric fills, no progress rings — just shapes + labels +
// seat dots that read well on white paper.
//
// Coordinate system mirrors the editor: a table's `(x, y)` is the
// CENTRE of its body, dimensions are in pixels at SCALE = 15 px/ft
// (web's RoomScale.imperial). The renderer scales-to-fit a target
// CGRect on the PDF page, preserving aspect ratio.

enum CanvasPDFRenderer {

    /// Draw the entire floor plan (room outline + objects + tables + seats)
    /// scaled to fit `rect` on the given context. No-op if the plan has no
    /// tables and no objects.
    static func drawFloorPlan(in ctx: CGContext, rect: CGRect, plan: SeatingPlan) {
        let bounds = computeWorldBounds(plan)
        guard bounds.width > 0, bounds.height > 0 else {
            drawEmptyMessage(in: ctx, rect: rect)
            return
        }

        // Fit-to-rect with a small inner padding so seats/labels don't
        // touch the edge.
        let pad: CGFloat = 12
        let target = rect.insetBy(dx: pad, dy: pad)
        let scale = min(target.width / bounds.width, target.height / bounds.height)
        let scaledW = bounds.width * scale
        let scaledH = bounds.height * scale
        let offsetX = target.midX - scaledW / 2 - bounds.minX * scale
        let offsetY = target.midY - scaledH / 2 - bounds.minY * scale

        ctx.saveGState()
        ctx.translateBy(x: offsetX, y: offsetY)
        ctx.scaleBy(x: scale, y: scale)

        drawRoomOutline(plan: plan, ctx: ctx)
        for obj in plan.objects { drawRoomObject(obj, ctx: ctx) }
        for table in plan.tables { drawTable(table, ctx: ctx) }

        ctx.restoreGState()
    }

    // MARK: - Bounds

    private static func computeWorldBounds(_ plan: SeatingPlan) -> CGRect {
        var minX: CGFloat = .infinity
        var minY: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var maxY: CGFloat = -.infinity

        // Seat-dot perimeter padding so we leave room for seats around
        // each table and labels under objects.
        let seatPad: CGFloat = 22

        for t in plan.tables {
            let body = bodySize(for: t)
            let cx = CGFloat(t.x), cy = CGFloat(t.y)
            // Use diagonal-half so rotated tables still fit.
            let half = max(body.width, body.height) / 2 + seatPad
            minX = min(minX, cx - half)
            minY = min(minY, cy - half)
            maxX = max(maxX, cx + half)
            maxY = max(maxY, cy + half)
        }
        for o in plan.objects {
            let cx = CGFloat(o.x), cy = CGFloat(o.y)
            let halfW = CGFloat(o.width) / 2
            let halfH = CGFloat(o.height) / 2
            minX = min(minX, cx - halfW)
            minY = min(minY, cy - halfH)
            maxX = max(maxX, cx + halfW)
            maxY = max(maxY, cy + halfH)
        }
        if let pts = plan.customRoomPoints {
            for p in pts {
                minX = min(minX, CGFloat(p.x))
                minY = min(minY, CGFloat(p.y))
                maxX = max(maxX, CGFloat(p.x))
                maxY = max(maxY, CGFloat(p.y))
            }
        } else if let w = plan.roomWidth, let h = plan.roomHeight {
            minX = min(minX, 0); minY = min(minY, 0)
            maxX = max(maxX, CGFloat(w)); maxY = max(maxY, CGFloat(h))
        }

        guard minX.isFinite else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func drawEmptyMessage(in ctx: CGContext, rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor(white: 0.55, alpha: 1),
        ]
        let str = NSString(string: "No tables placed yet — add tables in the Editor to populate the floor plan.")
        let size = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                 withAttributes: attrs)
    }

    // MARK: - Room outline

    private static func drawRoomOutline(plan: SeatingPlan, ctx: CGContext) {
        let lineColor = UIColor(white: 0.72, alpha: 1)
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(1.5)

        if let pts = plan.customRoomPoints, pts.count >= 2 {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
            for i in 1..<pts.count {
                let p = pts[i]
                if let arc = p.arc {
                    appendArc(to: path, end: CGPoint(x: p.x, y: p.y), arc: arc)
                } else {
                    path.addLine(to: CGPoint(x: p.x, y: p.y))
                }
            }
            // Close back to start (with arc if first point declared one)
            if let firstArc = pts[0].arc {
                appendArc(to: path, end: CGPoint(x: pts[0].x, y: pts[0].y), arc: firstArc)
            } else {
                path.close()
            }
            ctx.addPath(path.cgPath)
            ctx.strokePath()
        } else if let w = plan.roomWidth, let h = plan.roomHeight {
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            ctx.stroke(rect)
        }
    }

    private static func appendArc(to path: UIBezierPath, end: CGPoint, arc: RoomArc) {
        // Direct port of the SVG-arc → quadratic approximation used by the
        // editor (simplified for printable rendering — a single-curve arc
        // is acceptable for PDF, full SVG-arc decomposition isn't needed).
        let start = path.currentPoint
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        // Bow direction: perpendicular to the chord, magnitude proportional
        // to rx so straight chords stay straight and curved walls bow out.
        let bow = CGFloat(arc.rx) / 4 * (arc.sweep == 1 ? 1 : -1)
        let nx = -dy / dist * bow
        let ny = dx / dist * bow
        let control = CGPoint(x: mid.x + nx, y: mid.y + ny)
        path.addQuadCurve(to: end, controlPoint: control)
    }

    // MARK: - Room objects

    private static func drawRoomObject(_ o: RoomObject, ctx: CGContext) {
        let cx = CGFloat(o.x), cy = CGFloat(o.y)
        let w = CGFloat(o.width), h = CGFloat(o.height)
        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)

        let fill = parseColor(o.color) ?? UIColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1)
        let stroke = UIColor(white: 0.55, alpha: 1)

        ctx.saveGState()
        if let rot = o.rotation, rot != 0 {
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: CGFloat(rot * .pi / 180))
            ctx.translateBy(x: -cx, y: -cy)
        }

        let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
        ctx.setFillColor(fill.withAlphaComponent(0.45).cgColor)
        ctx.setStrokeColor(stroke.cgColor)
        ctx.setLineWidth(0.8)
        ctx.addPath(path.cgPath)
        ctx.drawPath(using: .fillStroke)

        // Label centred inside the object.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor(white: 0.25, alpha: 1),
        ]
        let label = NSString(string: o.name)
        let size = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: cx - size.width / 2, y: cy - size.height / 2),
                   withAttributes: attrs)

        ctx.restoreGState()
    }

    // MARK: - Tables

    private static func drawTable(_ t: SeatTable, ctx: CGContext) {
        let body = bodySize(for: t)
        let center = CGPoint(x: t.x, y: t.y)

        ctx.saveGState()
        if let rot = t.rotation, rot != 0 {
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: CGFloat(rot * .pi / 180))
            ctx.translateBy(x: -center.x, y: -center.y)
        }

        // Seats first (under the table body so the body's edge clips the dots).
        drawSeats(table: t, body: body, center: center, ctx: ctx)

        // Table body
        let path = shapePath(for: t, body: body, center: center)
        let fill = isHeadOrSweetheart(t)
            ? UIColor(red: 0.79, green: 0.66, blue: 0.38, alpha: 1)   // gold for head/sweetheart
            : UIColor(white: 0.97, alpha: 1)                           // ivory for others
        let stroke = UIColor(red: 0.45, green: 0.40, blue: 0.32, alpha: 1)
        ctx.setFillColor(fill.cgColor)
        ctx.setStrokeColor(stroke.cgColor)
        ctx.setLineWidth(1.1)
        ctx.addPath(path.cgPath)
        ctx.drawPath(using: .fillStroke)

        // Table name centred inside the body
        let nameColor = isHeadOrSweetheart(t)
            ? UIColor.white
            : UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: nameColor,
        ]
        let name = NSString(string: t.name)
        let nSize = name.size(withAttributes: nameAttrs)
        name.draw(at: CGPoint(x: center.x - nSize.width / 2, y: center.y - nSize.height / 2 - 5),
                  withAttributes: nameAttrs)

        // Seat count under the name (e.g. "8/10")
        if t.type != .sweetheart {
            let countAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: nameColor.withAlphaComponent(0.85),
            ]
            let countText = "\(t.assignments.count)/\(t.seats)"
            let count = NSString(string: countText)
            let cSize = count.size(withAttributes: countAttrs)
            count.draw(at: CGPoint(x: center.x - cSize.width / 2, y: center.y + 3),
                       withAttributes: countAttrs)
        }

        ctx.restoreGState()
    }

    private static func drawSeats(table: SeatTable, body: CGSize, center: CGPoint, ctx: CGContext) {
        let positions = seatPositions(for: table, body: body, center: center)
        let dotR: CGFloat = 4
        let filledColor = UIColor(red: 0.79, green: 0.66, blue: 0.38, alpha: 1)
        let emptyColor = UIColor(white: 0.85, alpha: 1)
        let strokeColor = UIColor(white: 0.55, alpha: 1)

        let filledIndices = Set(table.assignments.values)
        for (i, p) in positions.enumerated() {
            let isFilled = filledIndices.contains(i)
            let rect = CGRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2)
            ctx.setFillColor((isFilled ? filledColor : emptyColor).cgColor)
            ctx.setStrokeColor(strokeColor.cgColor)
            ctx.setLineWidth(0.5)
            ctx.fillEllipse(in: rect)
            ctx.strokeEllipse(in: rect)
        }
    }

    // MARK: - Shape geometry (mirrors CanvasViewController)

    static func bodySize(for t: SeatTable) -> CGSize {
        switch t.type {
        case .round:
            let d = CGFloat(t.diameter ?? 90)
            return CGSize(width: d, height: d)
        case .rect:
            return CGSize(width: CGFloat(t.width ?? 100), height: CGFloat(t.height ?? 50))
        case .head:
            return CGSize(width: CGFloat(t.width ?? 280), height: CGFloat(t.height ?? 50))
        case .sweetheart:
            return CGSize(width: CGFloat(t.width ?? 100), height: CGFloat(t.height ?? 60))
        case .oval:
            return CGSize(width: CGFloat(t.width ?? 120), height: CGFloat(t.height ?? 60))
        }
    }

    private static func shapePath(for t: SeatTable, body: CGSize, center c: CGPoint) -> UIBezierPath {
        switch t.type {
        case .round:
            return UIBezierPath(arcCenter: c, radius: body.width / 2,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)
        case .rect, .head:
            let rect = CGRect(x: c.x - body.width / 2, y: c.y - body.height / 2,
                              width: body.width, height: body.height)
            return UIBezierPath(roundedRect: rect, cornerRadius: 6)
        case .sweetheart:
            return sweetheartPath(shape: t.sweetShape, body: body, center: c)
        case .oval:
            let rect = CGRect(x: c.x - body.width / 2, y: c.y - body.height / 2,
                              width: body.width, height: body.height)
            return UIBezierPath(ovalIn: rect)
        }
    }

    private static func sweetheartPath(shape: String?, body: CGSize, center c: CGPoint) -> UIBezierPath {
        let w = body.width, h = body.height
        switch (shape ?? "heart").lowercased() {
        case "oval":
            return UIBezierPath(ovalIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
        case "diamond", "rect", "rectangle":
            return UIBezierPath(roundedRect: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h),
                                cornerRadius: 8)
        default:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: c.x - w / 2, y: c.y))
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h / 2),
                              controlPoint: CGPoint(x: c.x - w / 2, y: c.y - h / 2))
            path.addQuadCurve(to: CGPoint(x: c.x + w / 2, y: c.y),
                              controlPoint: CGPoint(x: c.x + w / 2, y: c.y - h / 2))
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h / 2),
                              controlPoint: CGPoint(x: c.x + w / 2, y: c.y + h / 3))
            path.addQuadCurve(to: CGPoint(x: c.x - w / 2, y: c.y),
                              controlPoint: CGPoint(x: c.x - w / 2, y: c.y + h / 3))
            path.close()
            return path
        }
    }

    private static func seatPositions(for table: SeatTable, body: CGSize, center c: CGPoint) -> [CGPoint] {
        let n = max(0, table.seats)
        guard n > 0 else { return [] }
        let offset: CGFloat = 10

        switch table.type {
        case .round:
            let r = body.width / 2
            return (0..<n).map { i in
                let ang = CGFloat(i) / CGFloat(n) * .pi * 2 - .pi / 2
                return CGPoint(x: c.x + cos(ang) * (r + offset),
                               y: c.y + sin(ang) * (r + offset))
            }
        case .oval:
            let rx = body.width / 2 + offset
            let ry = body.height / 2 + offset
            return (0..<n).map { i in
                let ang = CGFloat(i) / CGFloat(n) * .pi * 2 - .pi / 2
                return CGPoint(x: c.x + cos(ang) * rx,
                               y: c.y + sin(ang) * ry)
            }
        case .sweetheart:
            let count = min(n, 2)
            let y = c.y + body.height / 2 + offset
            if count == 1 { return [CGPoint(x: c.x, y: y)] }
            return [
                CGPoint(x: c.x - body.width / 4, y: y),
                CGPoint(x: c.x + body.width / 4, y: y),
            ]
        case .rect, .head:
            let w = body.width
            let h = body.height
            if table.oneSide == true {
                let sp = w / CGFloat(n + 1)
                return (0..<n).map { i in
                    CGPoint(x: c.x - w / 2 + sp * CGFloat(i + 1), y: c.y - h / 2 - offset)
                }
            }
            let top = (n + 1) / 2
            let bot = n - top
            let sp = w / CGFloat(max(top, bot) + 1)
            var seats: [CGPoint] = []
            for i in 0..<top {
                seats.append(CGPoint(x: c.x - w / 2 + sp * CGFloat(i + 1), y: c.y - h / 2 - offset))
            }
            for i in 0..<bot {
                seats.append(CGPoint(x: c.x - w / 2 + sp * CGFloat(i + 1), y: c.y + h / 2 + offset))
            }
            return seats
        }
    }

    // MARK: - Helpers

    private static func isHeadOrSweetheart(_ t: SeatTable) -> Bool {
        t.type == .head || t.type == .sweetheart
    }

    private static func parseColor(_ hex: String?) -> UIColor? {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let val = UInt32(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 6 {
            r = CGFloat((val >> 16) & 0xFF) / 255
            g = CGFloat((val >> 8) & 0xFF) / 255
            b = CGFloat(val & 0xFF) / 255
            a = 1
        } else {
            r = CGFloat((val >> 24) & 0xFF) / 255
            g = CGFloat((val >> 16) & 0xFF) / 255
            b = CGFloat((val >> 8) & 0xFF) / 255
            a = CGFloat(val & 0xFF) / 255
        }
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
