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
    ///
    /// `showGuestNames` controls whether each filled seat dot is labelled
    /// with the guest's first name (radially placed for round/oval/sweet
    /// tables, stacked above/below for rect/head). Used by the Floor Plan
    /// share image — turning it on gives caterers / venues an actual
    /// "who sits where" reference; off keeps the plan readable as a
    /// pure room layout.
    static func drawFloorPlan(in ctx: CGContext, rect: CGRect, plan: SeatingPlan,
                              showGuestNames: Bool = false) {
        let bounds = computeWorldBounds(plan)
        guard bounds.width > 0, bounds.height > 0 else {
            drawEmptyMessage(in: ctx, rect: rect)
            return
        }

        // When labels are on, the world bounds need extra perimeter room
        // so names don't get clipped at the edges of the target rect.
        // 60pt buys margin for the worst-case label: a 9-char name in
        // a 7.5pt semibold font with the ivory pill backdrop's 3pt
        // horizontal padding (~50pt total label width) sitting on the
        // outermost seat at body_radius + seat_offset (10) + label
        // offset (16). 36pt was clipping "Sterling" / "Alexander" on
        // tables at the far left/right of the floor plan.
        let labelPad: CGFloat = showGuestNames ? 60 : 0
        let inflatedBounds = bounds.insetBy(dx: -labelPad, dy: -labelPad)

        // Fit-to-rect with a small inner padding so seats/labels don't
        // touch the edge.
        let pad: CGFloat = 12
        let target = rect.insetBy(dx: pad, dy: pad)
        let scale = min(target.width / inflatedBounds.width, target.height / inflatedBounds.height)
        let scaledW = inflatedBounds.width * scale
        let scaledH = inflatedBounds.height * scale
        let offsetX = target.midX - scaledW / 2 - inflatedBounds.minX * scale
        let offsetY = target.midY - scaledH / 2 - inflatedBounds.minY * scale

        ctx.saveGState()
        ctx.translateBy(x: offsetX, y: offsetY)
        ctx.scaleBy(x: scale, y: scale)

        drawRoomOutline(plan: plan, ctx: ctx)
        for obj in plan.objects { drawRoomObject(obj, ctx: ctx) }
        for table in plan.tables {
            drawTable(table, plan: plan, showGuestNames: showGuestNames, ctx: ctx)
        }

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

        // Resolve the actual polygon to draw. Priority:
        //   1. customRoomPoints (user-traced or AI-generated outline)
        //   2. roomShape preset ("t", "l", "u", "circle", "oval") — convert
        //      to the same polygon the canvas + web renderer use, so the
        //      printable export matches what the user sees in the editor
        //      (was previously falling through to a plain rectangle, which
        //      was the user-reported "why did the shape change?" bug)
        //   3. plain roomWidth × roomHeight rectangle as final fallback
        let pts: [RoomPoint]? = {
            if let custom = plan.customRoomPoints, custom.count >= 2 { return custom }
            if let shape = plan.roomShape?.lowercased(),
               shape != "rect", shape != "rectangle",
               let w = plan.roomWidth, let h = plan.roomHeight {
                let preset = RoomShapePresets.defaultPoints(shape: shape, width: w, height: h)
                return preset.count >= 2 ? preset : nil
            }
            return nil
        }()

        if let pts {
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

        // Mirror the canvas's CanvasViewController styling: object colour
        // at 0.85 alpha, contrast-aware text colour (white on dark bg,
        // dark on light bg), SF Symbol icon stacked above the label.
        let fill = parseColor(o.color) ?? UIColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1)
        let isDark = (o.color ?? "").lowercased() == "#2d2d2d"
        let textColor = isDark
            ? UIColor.white
            : UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
        let stroke = isDark ? fill : UIColor(white: 0.55, alpha: 1)

        ctx.saveGState()
        if let rot = o.rotation, rot != 0 {
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: CGFloat(rot * .pi / 180))
            ctx.translateBy(x: -cx, y: -cy)
        }

        let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
        ctx.setFillColor(fill.withAlphaComponent(0.85).cgColor)
        ctx.setStrokeColor(stroke.cgColor)
        ctx.setLineWidth(0.8)
        ctx.addPath(path.cgPath)
        ctx.drawPath(using: .fillStroke)

        // Icon — SF Symbol centred above the name. Same VenueIconMap
        // resolution the canvas uses, so an object's web-style icon name
        // (e.g. "music", "utensils") renders the same glyph everywhere.
        let iconName = VenueIconMap.sfSymbol(for: o.icon)
        let iconPt: CGFloat = min(w, h) * 0.32
        let iconCfg = UIImage.SymbolConfiguration(pointSize: iconPt, weight: .regular)
        if let icon = UIImage(systemName: iconName, withConfiguration: iconCfg)?
                .withTintColor(textColor.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
            let iSize = icon.size
            let iconRect = CGRect(x: cx - iSize.width / 2,
                                   y: cy - iSize.height / 2 - 6,
                                   width: iSize.width, height: iSize.height)
            icon.draw(in: iconRect)
        }

        // Label centred under the icon. Clipped to the object bounds and
        // truncated with an ellipsis when it doesn't fit — small accent
        // objects (40×60 entrance, 30×30 speaker) were rendering "Welcome
        // Sign" / "Main Entrance" at full width and bleeding into their
        // neighbours. Matches the canvas's UILabel-truncation behaviour.
        let labelPara = NSMutableParagraphStyle()
        labelPara.lineBreakMode = .byTruncatingTail
        labelPara.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: textColor,
            .paragraphStyle: labelPara,
        ]
        // Tiny objects (< 28pt either dimension) — icon already conveys
        // identity; the label would just be noise. Skip it entirely.
        if min(w, h) >= 28 {
            let labelW = w - 4
            let labelRect = CGRect(x: cx - labelW / 2,
                                    y: cy + iconPt / 2 - 2,
                                    width: labelW,
                                    height: 12)
            (o.name as NSString).draw(in: labelRect, withAttributes: attrs)
        }

        ctx.restoreGState()
    }

    // MARK: - Tables

    private static func drawTable(_ t: SeatTable, plan: SeatingPlan, showGuestNames: Bool, ctx: CGContext) {
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

        // Table body — match the canvas styling (CanvasViewController):
        //   • Head Table   → charcoal fill, white text (dark hero strip)
        //   • Sweetheart   → ivory fill, charcoal text (cream cloud)
        //   • All others   → ivory fill, charcoal text, gold-ish rim
        let path = shapePath(for: t, body: body, center: center)
        let goldRim   = UIColor(red: 0.79, green: 0.66, blue: 0.38, alpha: 1)
        let charcoal  = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
        let ivoryFill = UIColor(white: 0.97, alpha: 1)
        let fill: UIColor
        let stroke: UIColor
        let nameColor: UIColor
        switch t.type {
        case .head:
            fill = charcoal
            stroke = charcoal
            nameColor = .white
        case .sweetheart:
            fill = ivoryFill
            stroke = goldRim
            nameColor = charcoal
        default:
            fill = ivoryFill
            stroke = goldRim
            nameColor = charcoal
        }
        ctx.setFillColor(fill.cgColor)
        ctx.setStrokeColor(stroke.cgColor)
        ctx.setLineWidth(1.4)
        ctx.addPath(path.cgPath)
        ctx.drawPath(using: .fillStroke)
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

        // First-name labels at each filled seat — turned on by the
        // "Include guest names" toggle on the Share Via row. Drawn last
        // so they sit on top of everything else.
        if showGuestNames {
            drawSeatGuestNames(table: t, plan: plan, body: body, center: center, ctx: ctx)
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

    /// Per-seat first-name labels, positioned outward from the seat dot
    /// so the table name + count inside the body remain readable.
    /// Truncated to 9 chars + ellipsis to keep things tidy at typical
    /// floor-plan render sizes. Only labels FILLED seats — empty seats
    /// stay as bare dots so the eye finds them as gaps.
    private static func drawSeatGuestNames(table: SeatTable, plan: SeatingPlan,
                                           body: CGSize, center: CGPoint, ctx: CGContext) {
        let positions = seatPositions(for: table, body: body, center: center)
        guard !positions.isEmpty else { return }

        // Reverse map: seatIndex -> guestId. plan.tables.assignments is
        // guestId -> seatIndex; flip it so we can look up by index.
        var guestBySeat: [Int: Guest] = [:]
        let byId = Dictionary(uniqueKeysWithValues: plan.guests.map { ($0.id, $0) })
        for (gid, idx) in table.assignments {
            if let g = byId[gid] { guestBySeat[idx] = g }
        }

        // Guest names render INSIDE the canvas's scaleBy() transform
        // (typically ~0.62×) and then again through the export's pixel
        // scale. With the export now at scale 8 and source font 10pt,
        // effective output ≈ 10 × 0.62 × 8 = ~50 actual pixels per
        // name. Names are ~6 chars after truncation; the +1 offset bump
        // (12pt) keeps them clear of seat dots given the slightly larger
        // glyph height.
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1),
        ]
        let labelOffset: CGFloat = 12  // distance from seat dot to label centre

        for (i, p) in positions.enumerated() {
            guard let g = guestBySeat[i] else { continue }
            let label = firstNameTruncated(for: g)
            guard !label.isEmpty else { continue }
            let s = NSString(string: label)
            let size = s.size(withAttributes: labelAttrs)

            // Position the label OUTWARD from the table centre — radial
            // for round/oval/sweet, vertical for rect/head. Centred on
            // the offset point.
            let target = labelPosition(for: table, seatPoint: p, tableCenter: center,
                                       offset: labelOffset, labelSize: size)

            // Draw a soft ivory pill behind the text so it stays
            // legible when it overlaps another table's perimeter or a
            // room object.
            let padX: CGFloat = 3, padY: CGFloat = 1.5
            let pill = CGRect(x: target.x - size.width / 2 - padX,
                              y: target.y - size.height / 2 - padY,
                              width: size.width + padX * 2,
                              height: size.height + padY * 2)
            ctx.setFillColor(UIColor(white: 0.99, alpha: 0.88).cgColor)
            let pillPath = UIBezierPath(roundedRect: pill, cornerRadius: 3)
            ctx.addPath(pillPath.cgPath)
            ctx.fillPath()

            s.draw(at: CGPoint(x: target.x - size.width / 2,
                               y: target.y - size.height / 2),
                   withAttributes: labelAttrs)
        }
    }

    /// First name (or full display name if there's no space) truncated
    /// to 9 chars + ellipsis. 9 is a sweet spot for typical wedding
    /// names ("Alexander" → "Alexande…") that fits without crowding
    /// neighbouring seats.
    private static func firstNameTruncated(for g: Guest) -> String {
        let raw = g.displayName.isEmpty ? g.name : g.displayName
        let first = raw.split(separator: " ").first.map(String.init) ?? raw
        if first.count <= 9 { return first }
        return String(first.prefix(8)) + "…"
    }

    /// Compute where a seat label should sit. Round / oval / sweet
    /// tables get radial placement (label flies outward along the
    /// vector from table centre to seat). Rect / head tables get
    /// vertical placement (above for top-row seats, below for bottom).
    private static func labelPosition(for table: SeatTable, seatPoint p: CGPoint,
                                       tableCenter c: CGPoint, offset: CGFloat,
                                       labelSize: CGSize) -> CGPoint {
        switch table.type {
        case .round, .oval, .sweetheart:
            let dx = p.x - c.x
            let dy = p.y - c.y
            let dist = sqrt(dx * dx + dy * dy)
            guard dist > 0 else {
                return CGPoint(x: p.x, y: p.y + offset + labelSize.height / 2)
            }
            let nx = dx / dist
            let ny = dy / dist
            return CGPoint(x: p.x + nx * (offset + labelSize.height / 2),
                           y: p.y + ny * (offset + labelSize.height / 2))
        case .rect, .head:
            // Head / rect seats sit in a single horizontal row above the
            // body. With 10 seats on a 400pt table the centres are only
            // ~40pt apart — labels at 9pt font easily run together into
            // a smear. Stagger by alternating two height tiers so
            // adjacent labels never share a line.
            let above = p.y < c.y
            let direction: CGFloat = above ? -1 : 1
            // Use the seat's x relative to the body to determine a stable
            // odd/even index — robust to seat ordering changes.
            let body = bodySize(for: table)
            let leftEdge = c.x - body.width / 2
            let seatSpacing = max(1, body.width / CGFloat(max(1, table.seats)))
            let approxIdx = Int(((p.x - leftEdge) / seatSpacing).rounded())
            let tier: CGFloat = (approxIdx & 1 == 0) ? 0 : (labelSize.height + 4)
            return CGPoint(x: p.x,
                           y: p.y + direction * (offset + tier))
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
