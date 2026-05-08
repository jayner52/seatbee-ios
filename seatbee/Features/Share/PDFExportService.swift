import SwiftUI
import PDFKit

// MARK: - PDF export options (web parity)
//
// Web's exportPDF / exportPlannerPDF accept an opts object with the
// three printable toggles: include meal selections, include dietary
// restrictions, include high chair flags. iOS surfaces these as toggles
// in the Share view and threads them through to both Seating Chart
// and Planner View PDFs so the column set / annotations match exactly.

struct PDFExportOpts: Sendable {
    var includeMeals: Bool = true
    var includeDietary: Bool = true
    var includeHighChairs: Bool = true

    static let `default` = PDFExportOpts()
}

@MainActor
final class PDFExportService {

    // MARK: - Seating Chart PDF (web parity: exportPDF ~13854)
    //
    // Page 1: title + floor plan + stats row.
    // Page 2+: "Seating Assignments" header + 2-column table card grid
    //          (table name + guest list, simpler than Planner View).
    // Free-tier watermark on every page.

    static func generateSeatingChartPDF(plan: SeatingPlan, opts: PDFExportOpts, isPaid: Bool) -> Data? {
        let pageWidth: CGFloat = 612   // Letter portrait
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 40

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return renderer.pdfData { context in
            // ── PAGE 1: Floor plan overview ──
            context.beginPage()
            var ctx = context.cgContext
            drawHeader(ctx: ctx, plan: plan, pageWidth: pageWidth, top: margin)

            let floorTop: CGFloat = margin + 90
            let floorRect = CGRect(x: margin, y: floorTop,
                                   width: pageWidth - margin * 2,
                                   height: pageHeight * 0.55)
            let cardPath = UIBezierPath(roundedRect: floorRect, cornerRadius: 8)
            ctx.setFillColor(UIColor(white: 0.99, alpha: 1).cgColor)
            ctx.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
            ctx.setLineWidth(0.7)
            ctx.addPath(cardPath.cgPath)
            ctx.drawPath(using: .fillStroke)
            CanvasPDFRenderer.drawFloorPlan(in: ctx, rect: floorRect, plan: plan)

            drawStatsRow(ctx: ctx, plan: plan, pageWidth: pageWidth, y: floorRect.maxY + 24)
            drawFooter(ctx: ctx, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
            if !isPaid { drawWatermark(ctx: ctx, pageWidth: pageWidth, pageHeight: pageHeight) }

            // ── PAGE 2+: Seating Assignments — 2-col card grid ──
            let cardWidth = (pageWidth - margin * 3) / 2
            let topYAfterTitle: CGFloat = margin + 28
            let pageBottomY = pageHeight - margin - 24
            let sortedTables = sortTablesForCards(plan.tables)

            var idx = 0
            var pageNum = 1
            while idx < sortedTables.count {
                context.beginPage()
                pageNum += 1
                ctx = context.cgContext

                // Section title centred at top
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: charcoalColor,
                ]
                let title = NSString(string: "Seating Assignments")
                let tSize = title.size(withAttributes: titleAttrs)
                title.draw(at: CGPoint(x: (pageWidth - tSize.width) / 2, y: margin),
                           withAttributes: titleAttrs)

                if !isPaid { drawWatermark(ctx: ctx, pageWidth: pageWidth, pageHeight: pageHeight) }

                var col = 0
                var leftY = topYAfterTitle
                var rightY = topYAfterTitle
                while idx < sortedTables.count {
                    let table = sortedTables[idx]
                    let cardH = seatingCardHeight(table: table, opts: opts)
                    let curY = (col == 0) ? leftY : rightY
                    if curY + cardH > pageBottomY { break }

                    let x = margin + CGFloat(col) * (cardWidth + margin)
                    drawSeatingChartCard(ctx: ctx, table: table, plan: plan, opts: opts,
                                         rect: CGRect(x: x, y: curY, width: cardWidth, height: cardH))
                    if col == 0 { leftY += cardH + 10 } else { rightY += cardH + 10 }
                    col = (col + 1) % 2
                    idx += 1
                }
                drawFooter(ctx: ctx, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)

                // Legend on the last page so caterers know what HC / GF /
                // VG / etc. mean (only includes badges actually used).
                if idx >= sortedTables.count {
                    drawLegend(ctx: ctx, plan: plan, opts: opts,
                               pageWidth: pageWidth, y: pageHeight - margin - 18)
                }
            }
        }
    }

    // MARK: - Planner View PDF (web parity: exportPlannerPDF ~14135)
    //
    // Page 1: title + floor plan only.
    // Page 2+: "Planner View" + 2-col card grid where each card has a
    //          left diagram panel (table shape with numbered seat dots)
    //          and a right list panel with seat-numbered guest rows,
    //          dietary/HC badges, meal column, dietary sub-line.
    // Last page: legend explaining badge codes used in the plan.

    static func generatePlannerViewPDF(plan: SeatingPlan, opts: PDFExportOpts, isPaid: Bool) -> Data? {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 40

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return renderer.pdfData { context in
            // ── PAGE 1: Floor plan overview ──
            context.beginPage()
            var ctx = context.cgContext
            drawHeader(ctx: ctx, plan: plan, pageWidth: pageWidth, top: margin)
            let floorRect = CGRect(x: margin, y: margin + 90,
                                   width: pageWidth - margin * 2,
                                   height: pageHeight - margin * 2 - 130)
            let cardPath = UIBezierPath(roundedRect: floorRect, cornerRadius: 8)
            ctx.setFillColor(UIColor(white: 0.99, alpha: 1).cgColor)
            ctx.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
            ctx.setLineWidth(0.7)
            ctx.addPath(cardPath.cgPath)
            ctx.drawPath(using: .fillStroke)
            CanvasPDFRenderer.drawFloorPlan(in: ctx, rect: floorRect, plan: plan)

            // Footnote about seat numbering — matches web's planner PDF
            let noteAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 8),
                .foregroundColor: warmColor,
            ]
            let note = NSString(string: "Seat 1 is always the top-most position (12 o'clock) on each round table. Table detail on following pages.")
            note.draw(at: CGPoint(x: margin, y: floorRect.maxY + 8),
                      withAttributes: noteAttrs)

            drawFooter(ctx: ctx, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
            if !isPaid { drawWatermark(ctx: ctx, pageWidth: pageWidth, pageHeight: pageHeight) }

            // ── PAGE 2+: Planner cards ──
            let cardWidth = (pageWidth - margin * 3) / 2
            let topYAfterTitle: CGFloat = margin + 28
            let pageBottomY = pageHeight - margin - 36   // leave room for legend strip
            let sortedTables = sortTablesForCards(plan.tables)

            var idx = 0
            while idx < sortedTables.count {
                context.beginPage()
                ctx = context.cgContext

                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: charcoalColor,
                ]
                let title = NSString(string: "Planner View")
                let tSize = title.size(withAttributes: titleAttrs)
                title.draw(at: CGPoint(x: (pageWidth - tSize.width) / 2, y: margin),
                           withAttributes: titleAttrs)

                if !isPaid { drawWatermark(ctx: ctx, pageWidth: pageWidth, pageHeight: pageHeight) }

                var col = 0
                var leftY = topYAfterTitle
                var rightY = topYAfterTitle
                while idx < sortedTables.count {
                    let table = sortedTables[idx]
                    let cardH = plannerCardHeight(table: table, opts: opts)
                    let curY = (col == 0) ? leftY : rightY
                    if curY + cardH > pageBottomY { break }

                    let x = margin + CGFloat(col) * (cardWidth + margin)
                    drawPlannerCard(ctx: ctx, table: table, plan: plan, opts: opts,
                                    rect: CGRect(x: x, y: curY, width: cardWidth, height: cardH))
                    if col == 0 { leftY += cardH + 10 } else { rightY += cardH + 10 }
                    col = (col + 1) % 2
                    idx += 1
                }
                drawFooter(ctx: ctx, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)

                // Legend on the LAST page only.
                if idx >= sortedTables.count {
                    drawLegend(ctx: ctx, plan: plan, opts: opts, pageWidth: pageWidth, y: pageHeight - margin - 18)
                }
            }
        }
    }

    /// Web parity: head tables first, then sweetheart, then natural-sort
    /// by name so Table 2 sorts before Table 10.
    private static func sortTablesForCards(_ tables: [SeatTable]) -> [SeatTable] {
        tables.sorted { a, b in
            let aHead = a.type == .head, bHead = b.type == .head
            if aHead != bHead { return aHead }
            let aSweet = a.type == .sweetheart, bSweet = b.type == .sweetheart
            if aSweet != bSweet { return aSweet }
            return a.name.compare(b.name, options: [.numeric, .caseInsensitive]) == .orderedAscending
        }
    }


    // MARK: - Shared PDF chrome (header / stats / footer / watermark)

    private static let goldColor = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 1)
    private static let charcoalColor = UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 1)
    private static let warmColor = UIColor(red: 139/255, green: 134/255, blue: 128/255, alpha: 1)
    private static let ivoryColor = UIColor(red: 250/255, green: 246/255, blue: 236/255, alpha: 1)

    /// Title block at the top of a PDF page: plan name, decorative line,
    /// optional date + venue subtitle. Returns nothing — caller knows the
    /// header consumes ~90pt vertical space below `top`.
    private static func drawHeader(ctx: CGContext, plan: SeatingPlan, pageWidth: CGFloat, top: CGFloat) {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: charcoalColor,
        ]
        let title = NSString(string: plan.name)
        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(at: CGPoint(x: (pageWidth - titleSize.width) / 2, y: top),
                   withAttributes: titleAttrs)

        // Decorative gold line under the title
        let lineY = top + titleSize.height + 6
        let lineWidth: CGFloat = 60
        ctx.setStrokeColor(goldColor.cgColor)
        ctx.setLineWidth(1.2)
        ctx.move(to: CGPoint(x: (pageWidth - lineWidth) / 2, y: lineY))
        ctx.addLine(to: CGPoint(x: (pageWidth + lineWidth) / 2, y: lineY))
        ctx.strokePath()

        // Date + venue subtitle (single line, em-dash separated)
        var subtitleParts: [String] = []
        if let date = plan.eventDate {
            let f = DateFormatter()
            f.dateStyle = .long
            subtitleParts.append(f.string(from: date))
        }
        if let venue = plan.venue, !venue.isEmpty { subtitleParts.append(venue) }
        if !subtitleParts.isEmpty {
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: warmColor,
            ]
            let sub = NSString(string: subtitleParts.joined(separator: " — "))
            let subSize = sub.size(withAttributes: subAttrs)
            sub.draw(at: CGPoint(x: (pageWidth - subSize.width) / 2, y: lineY + 10),
                     withAttributes: subAttrs)
        }
    }

    /// Three-up stats row: Total Guests / Tables / Seated %.
    private static func drawStatsRow(ctx: CGContext, plan: SeatingPlan, pageWidth: CGFloat, y: CGFloat) {
        let totalGuests = plan.guests.filter { $0.rsvp != .no }.count
        let totalTables = plan.tables.count
        let totalSeats = plan.tables.reduce(0) { $0 + $1.seats }
        let seatedCount = plan.tables.reduce(0) { $0 + $1.assignments.count }
        let seatedPct = totalSeats > 0 ? Int(round(Double(seatedCount) / Double(totalSeats) * 100)) : 0

        let stats: [(String, String)] = [
            ("\(totalGuests)", "TOTAL GUESTS"),
            ("\(totalTables)", "TABLES"),
            ("\(seatedPct)%", "SEATED"),
        ]
        let statsAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: goldColor,
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: warmColor,
        ]
        let spacing = pageWidth / CGFloat(stats.count + 1)
        for (i, stat) in stats.enumerated() {
            let cx = spacing * CGFloat(i + 1)
            let num = NSString(string: stat.0)
            let nSize = num.size(withAttributes: statsAttrs)
            num.draw(at: CGPoint(x: cx - nSize.width / 2, y: y), withAttributes: statsAttrs)
            let lab = NSString(string: stat.1)
            let lSize = lab.size(withAttributes: labelAttrs)
            lab.draw(at: CGPoint(x: cx - lSize.width / 2, y: y + nSize.height + 2),
                     withAttributes: labelAttrs)
        }
    }

    // MARK: - Card-grid rendering (shared by Seating Chart + Planner View)
    //
    // Both PDFs use a 2-column card grid on pages 2+. Card height varies by
    // seat count + selected opts. The Seating Chart draws a simpler card
    // (just guest list with optional meal/dietary text); the Planner View
    // draws a richer card with a left-side table diagram and right-side
    // structured columns + dietary badges.

    /// Web parity: badge { label, fillColor }. Drawn as small filled
    /// circles with white letters on top — readable on both screen and
    /// print, doesn't depend on emoji font support.
    private struct DietaryBadge {
        let label: String
        let color: UIColor
    }

    /// Maps a guest's dietaryTags + flags to badges. `opts` controls
    /// whether dietary / HC categories show. Mirrors the web mapping
    /// (App.jsx ~14349) so a printed iOS PDF keeps the same legend.
    private static func badges(for guest: Guest, opts: PDFExportOpts) -> [DietaryBadge] {
        var out: [DietaryBadge] = []
        if opts.includeHighChairs, guest.highChair == true {
            out.append(DietaryBadge(label: "HC", color: UIColor(red: 0.89, green: 0.42, blue: 0.34, alpha: 1)))
        }
        if guest.isChild == true {
            out.append(DietaryBadge(label: "KID", color: UIColor(red: 0.63, green: 0.43, blue: 0.82, alpha: 1)))
        }
        if opts.includeDietary {
            for tag in (guest.dietaryTags ?? []) {
                if let badge = dietaryBadge(forTag: tag) { out.append(badge) }
            }
            // Free-text dietary (no tag) → generic "D" badge so the row
            // still flags that catering needs to see the sub-line.
            let hasTags = !(guest.dietaryTags ?? []).isEmpty
            if let d = guest.dietary, !d.isEmpty, !hasTags {
                out.append(DietaryBadge(label: "D", color: UIColor(red: 0.39, green: 0.55, blue: 0.78, alpha: 1)))
            }
        }
        return out
    }

    private static func dietaryBadge(forTag tag: String) -> DietaryBadge? {
        switch tag {
        case "vegetarian":        return DietaryBadge(label: "VG", color: UIColor(red: 0.31, green: 0.62, blue: 0.35, alpha: 1))
        case "vegan":             return DietaryBadge(label: "VE", color: UIColor(red: 0.16, green: 0.51, blue: 0.25, alpha: 1))
        case "halal":             return DietaryBadge(label: "HL", color: UIColor(red: 0.12, green: 0.55, blue: 0.55, alpha: 1))
        case "gluten-free":       return DietaryBadge(label: "GF", color: UIColor(red: 0.78, green: 0.58, blue: 0.16, alpha: 1))
        case "dairy-free":        return DietaryBadge(label: "DF", color: UIColor(red: 0.39, green: 0.58, blue: 0.78, alpha: 1))
        case "nut-allergy":       return DietaryBadge(label: "NA", color: UIColor(red: 0.80, green: 0.24, blue: 0.22, alpha: 1))
        case "shellfish-allergy": return DietaryBadge(label: "SH", color: UIColor(red: 0.82, green: 0.39, blue: 0.22, alpha: 1))
        case "kosher":            return DietaryBadge(label: "KS", color: UIColor(red: 0.35, green: 0.43, blue: 0.69, alpha: 1))
        default:                  return nil
        }
    }

    private static func drawDietaryBadge(_ badge: DietaryBadge, center: CGPoint, ctx: CGContext) {
        let r: CGFloat = 5.5
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.setFillColor(badge.color.cgColor)
        ctx.fillEllipse(in: rect)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 5.5, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let s = NSString(string: badge.label)
        let sz = s.size(withAttributes: attrs)
        s.draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2 + 0.3),
               withAttributes: attrs)
    }

    // MARK: - Seating Chart card (web parity: exportPDF table cards)

    private static func seatingCardHeight(table: SeatTable, opts: PDFExportOpts) -> CGFloat {
        let header: CGFloat = 24
        let perRow: CGFloat = 14
        let assigned = max(table.assignments.count, 1)
        let detailHeight: CGFloat = (opts.includeMeals || opts.includeDietary) ? 4 : 0
        return header + CGFloat(assigned) * (perRow + detailHeight) + 10
    }

    private static func drawSeatingChartCard(ctx: CGContext, table: SeatTable, plan: SeatingPlan,
                                             opts: PDFExportOpts, rect: CGRect) {
        // Card chrome
        drawCardChrome(ctx: ctx, table: table, rect: rect)

        let guestById = Dictionary(uniqueKeysWithValues: plan.guests.map { ($0.id, $0) })
        let assigned = table.assignments
            .sorted { $0.value < $1.value }
            .compactMap { guestById[$0.key] }

        let headerHeight: CGFloat = 24
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: charcoalColor,
        ]
        let mutedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.5, weight: .regular),
            .foregroundColor: warmColor,
        ]

        var y = rect.minY + headerHeight + 6
        if assigned.isEmpty {
            NSString(string: "No guests assigned").draw(
                at: CGPoint(x: rect.minX + 8, y: y),
                withAttributes: mutedAttrs)
            return
        }
        for (i, g) in assigned.enumerated() {
            if y + 14 > rect.maxY - 4 { break }

            let displayName = g.displayName.isEmpty ? g.name : g.displayName
            let prefix = "\(i + 1). "
            let nameRow = "\(prefix)\(displayName)"

            // Right-aligned dietary + HC badges (same set as Planner View
            // so the two PDFs read consistently when both toggles are on).
            let guestBadges = badges(for: g, opts: opts)
            let badgeStride: CGFloat = 13
            let badgesWidth = CGFloat(guestBadges.count) * badgeStride
            let nameMaxW = rect.width - 16 - badgesWidth

            let truncated = truncate(nameRow, attrs: nameAttrs, maxWidth: nameMaxW)
            NSString(string: truncated).draw(at: CGPoint(x: rect.minX + 8, y: y),
                                              withAttributes: nameAttrs)
            // Badges drawn at row mid-height, right-aligned to card edge
            let rowMidY = y + 5
            for (bi, b) in guestBadges.enumerated() {
                let bx = rect.maxX - 8 - CGFloat(guestBadges.count - bi - 1) * badgeStride - 5.5
                drawDietaryBadge(b, center: CGPoint(x: bx, y: rowMidY), ctx: ctx)
            }

            // Sub-line: meal · free-text dietary (always text — the badge
            // tells the high-level story, the sub-line gives caterers
            // the exact words).
            if opts.includeMeals || opts.includeDietary {
                var parts: [String] = []
                if opts.includeMeals, let m = g.meal, !m.isEmpty { parts.append(m) }
                if opts.includeDietary, let d = g.dietary, !d.isEmpty { parts.append(d) }
                if !parts.isEmpty {
                    let detail = parts.joined(separator: " · ")
                    let truncatedDetail = truncate(detail, attrs: mutedAttrs, maxWidth: rect.width - 16)
                    NSString(string: truncatedDetail).draw(
                        at: CGPoint(x: rect.minX + 12, y: y + 11),
                        withAttributes: mutedAttrs)
                    y += 18
                    continue
                }
            }
            y += 14
        }
    }

    // MARK: - Planner View card (web parity: exportPlannerPDF table cards)

    /// Card layout: left diagram panel (lpW) + right list panel (rpW).
    /// Height grows with seat count. Same visual mapping as web — round
    /// tables get a circular diagram with seat dots numbered 1..N around
    /// the perimeter; rect/head/sweetheart get a rectangular diagram with
    /// seats above + below.
    private static func plannerCardHeight(table: SeatTable, opts: PDFExportOpts) -> CGFloat {
        let header: CGFloat = 24
        let perSeat: CGFloat = (opts.includeMeals || opts.includeDietary) ? 16 : 14
        let listPad: CGFloat = (opts.includeMeals || opts.includeDietary) ? 16 : 6
        return header + listPad + CGFloat(table.seats) * perSeat + 6
    }

    private static func drawPlannerCard(ctx: CGContext, table: SeatTable, plan: SeatingPlan,
                                        opts: PDFExportOpts, rect: CGRect) {
        drawCardChrome(ctx: ctx, table: table, rect: rect)

        let headerHeight: CGFloat = 24
        let lpW: CGFloat = min(90, rect.width * 0.32)   // left diagram panel
        let rpX = rect.minX + lpW + 6
        let rpW = rect.width - lpW - 12
        let bodyTop = rect.minY + headerHeight
        let bodyHeight = rect.maxY - bodyTop

        // Vertical divider between diagram and list
        ctx.setStrokeColor(UIColor(white: 0.92, alpha: 1).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: rect.minX + lpW, y: bodyTop + 4))
        ctx.addLine(to: CGPoint(x: rect.minX + lpW, y: rect.maxY - 4))
        ctx.strokePath()

        // Left: table diagram with numbered seats
        drawMiniTableDiagram(table: table, panelRect: CGRect(x: rect.minX, y: bodyTop,
                                                              width: lpW, height: bodyHeight),
                             ctx: ctx)

        // Right: column headers
        let showDetail = opts.includeMeals || opts.includeDietary
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 6.5, weight: .bold),
            .foregroundColor: UIColor(white: 0.55, alpha: 1),
        ]
        let nameColW: CGFloat = opts.includeMeals ? rpW * 0.55 : rpW - 14
        var listY = bodyTop + (showDetail ? 14 : 4)
        if showDetail {
            NSString(string: "GUEST").draw(at: CGPoint(x: rpX + 12, y: bodyTop + 4),
                                            withAttributes: headerAttrs)
            if opts.includeMeals {
                NSString(string: "MEAL").draw(at: CGPoint(x: rpX + 14 + nameColW, y: bodyTop + 4),
                                               withAttributes: headerAttrs)
            }
            ctx.setStrokeColor(UIColor(white: 0.88, alpha: 1).cgColor)
            ctx.setLineWidth(0.4)
            ctx.move(to: CGPoint(x: rpX + 1, y: bodyTop + 11))
            ctx.addLine(to: CGPoint(x: rect.maxX - 4, y: bodyTop + 11))
            ctx.strokePath()
        }

        // Seat rows
        let guestById = Dictionary(uniqueKeysWithValues: plan.guests.map { ($0.id, $0) })
        let seatOrder = plannerSeatOrder(table: table, guestById: guestById)
        let perSeat: CGFloat = showDetail ? 16 : 14
        let isHeadOrSweet = table.type == .head || table.type == .sweetheart
        let badgeColor = isHeadOrSweet
            ? UIColor(red: 0.79, green: 0.66, blue: 0.38, alpha: 1)
            : UIColor(red: 0.61, green: 0.69, blue: 0.53, alpha: 1)

        let seatBadgeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 6, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5, weight: .regular),
            .foregroundColor: charcoalColor,
        ]
        let dietSubAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 6.5, weight: .regular),
            .foregroundColor: UIColor(white: 0.6, alpha: 1),
        ]
        let mealAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7, weight: .regular),
            .foregroundColor: UIColor(white: 0.4, alpha: 1),
        ]
        let emptyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7, weight: .regular),
            .foregroundColor: UIColor(white: 0.78, alpha: 1),
        ]

        for i in 0..<table.seats {
            let rowMidY = listY + perSeat * 0.42
            // Seat-number circle
            let circleR: CGFloat = 4.5
            let circleRect = CGRect(x: rpX + 2, y: rowMidY - circleR,
                                    width: circleR * 2, height: circleR * 2)
            ctx.setFillColor(badgeColor.cgColor)
            ctx.fillEllipse(in: circleRect)
            let n = NSString(string: "\(i + 1)")
            let nSize = n.size(withAttributes: seatBadgeAttrs)
            n.draw(at: CGPoint(x: rpX + 2 + circleR - nSize.width / 2,
                               y: rowMidY - nSize.height / 2 + 0.3),
                   withAttributes: seatBadgeAttrs)

            let g = seatOrder[i]
            if let g = g {
                let guestBadges = badges(for: g, opts: opts)
                let badgeW = CGFloat(guestBadges.count) * 13
                let displayName = g.displayName.isEmpty ? g.name : g.displayName
                let nameMaxW = nameColW - badgeW - 4
                let truncatedName = truncate(displayName, attrs: nameAttrs, maxWidth: nameMaxW)
                NSString(string: truncatedName).draw(
                    at: CGPoint(x: rpX + 12, y: rowMidY - 4),
                    withAttributes: nameAttrs)

                // Right-aligned badges in the name column
                for (bi, b) in guestBadges.enumerated() {
                    let bx = rpX + 12 + nameColW - CGFloat(guestBadges.count - bi) * 13 + 6
                    drawDietaryBadge(b, center: CGPoint(x: bx, y: rowMidY), ctx: ctx)
                }

                // Meal text in MEAL column
                if opts.includeMeals, let m = g.meal, !m.isEmpty {
                    let mealColX = rpX + 14 + nameColW
                    let mealMaxW = rect.maxX - mealColX - 6
                    let truncatedMeal = truncate(m, attrs: mealAttrs, maxWidth: mealMaxW)
                    NSString(string: truncatedMeal).draw(
                        at: CGPoint(x: mealColX, y: rowMidY - 3),
                        withAttributes: mealAttrs)
                }

                // Free-text dietary sub-line under name
                if opts.includeDietary, let d = g.dietary, !d.isEmpty {
                    let truncatedDiet = truncate(d, attrs: dietSubAttrs, maxWidth: nameColW)
                    NSString(string: truncatedDiet).draw(
                        at: CGPoint(x: rpX + 12, y: listY + perSeat * 0.78 - 4),
                        withAttributes: dietSubAttrs)
                }
            } else {
                NSString(string: "— empty —").draw(
                    at: CGPoint(x: rpX + 12, y: rowMidY - 3),
                    withAttributes: emptyAttrs)
            }

            // Row divider
            if i < table.seats - 1 {
                ctx.setStrokeColor(UIColor(white: 0.95, alpha: 1).cgColor)
                ctx.setLineWidth(0.3)
                ctx.move(to: CGPoint(x: rpX + 1, y: listY + perSeat))
                ctx.addLine(to: CGPoint(x: rect.maxX - 4, y: listY + perSeat))
                ctx.strokePath()
            }
            listY += perSeat
        }
    }

    /// Web parity: tries seatOrders[tableId], falls back to assignment
    /// dict order for unordered seats. Returns an array of length
    /// `table.seats` where index i is the guest at seat i (or nil).
    private static func plannerSeatOrder(table: SeatTable, guestById: [String: Guest]) -> [Guest?] {
        var out: [Guest?] = Array(repeating: nil, count: table.seats)
        // Direct assignments first — guestId → seatIndex
        for (gid, idx) in table.assignments {
            if idx >= 0, idx < table.seats {
                out[idx] = guestById[gid]
            }
        }
        // Backfill: any unindexed guests fill remaining nil slots in order
        let placedIds = Set(table.assignments.keys)
        let unordered = table.assignments.keys
            .compactMap { guestById[$0] }
            .filter { placedIds.contains($0.id) && !out.contains(where: { $0?.id == $0?.id ? false : false }) }
        var ui = 0
        for i in 0..<out.count where out[i] == nil {
            if ui < unordered.count { out[i] = unordered[ui]; ui += 1 }
        }
        return out
    }

    /// Shared card chrome: rounded background + colored header strip with
    /// table name + occupancy count.
    private static func drawCardChrome(ctx: CGContext, table: SeatTable, rect: CGRect) {
        let isHeadOrSweet = table.type == .head || table.type == .sweetheart
        let headerColor = isHeadOrSweet
            ? UIColor(red: 0.79, green: 0.66, blue: 0.38, alpha: 1)
            : UIColor(red: 0.61, green: 0.69, blue: 0.53, alpha: 1)

        let cardPath = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
        ctx.setLineWidth(0.6)
        ctx.addPath(cardPath.cgPath)
        ctx.drawPath(using: .fillStroke)

        let headerHeight: CGFloat = 24
        let headerRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerHeight)
        ctx.saveGState()
        let headerPath = UIBezierPath(roundedRect: headerRect, cornerRadius: 6)
        ctx.addPath(headerPath.cgPath)
        ctx.clip()
        ctx.setFillColor(headerColor.cgColor)
        ctx.fill(headerRect)
        ctx.restoreGState()

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        NSString(string: table.name).draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 5),
                                           withAttributes: nameAttrs)
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
        ]
        let typeLabel = "\(table.type.rawValue.capitalized) · \(table.assignments.count)/\(table.seats)"
        let meta = NSString(string: typeLabel)
        let mSize = meta.size(withAttributes: metaAttrs)
        meta.draw(at: CGPoint(x: rect.maxX - mSize.width - 8, y: rect.minY + 8),
                  withAttributes: metaAttrs)
    }

    // MARK: - Mini table diagram (Planner View left panel)

    /// Draws a small representation of the table with seat dots numbered
    /// 1..N around the perimeter. Web parity: round/sweetheart use a
    /// circle; rect/head use a horizontal pill with seats above + below.
    private static func drawMiniTableDiagram(table: SeatTable, panelRect: CGRect, ctx: CGContext) {
        let cx = panelRect.midX
        let cy = panelRect.midY
        let isRound = table.type == .round || table.type == .oval || table.type == .sweetheart

        let bodyFill = UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1)
        let isHeadOrSweet = table.type == .head || table.type == .sweetheart
        let bodyStroke = isHeadOrSweet
            ? UIColor(red: 0.79, green: 0.66, blue: 0.38, alpha: 1)
            : UIColor(red: 0.61, green: 0.69, blue: 0.53, alpha: 1)

        let seatR: CGFloat = 4.5
        let seatLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 5, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let filledIndices = Set(table.assignments.values)
        let n = max(table.seats, 1)

        if isRound {
            let bodyR: CGFloat = 9
            let seatRadius = min(panelRect.width / 2 - 6, panelRect.height / 2 - 6)
            ctx.setFillColor(bodyFill.cgColor)
            ctx.setStrokeColor(bodyStroke.cgColor)
            ctx.setLineWidth(0.7)
            let bodyRect = CGRect(x: cx - bodyR, y: cy - bodyR, width: bodyR * 2, height: bodyR * 2)
            ctx.fillEllipse(in: bodyRect)
            ctx.strokeEllipse(in: bodyRect)

            for i in 0..<n {
                let ang = CGFloat(i) / CGFloat(n) * .pi * 2 - .pi / 2
                let sx = cx + cos(ang) * seatRadius
                let sy = cy + sin(ang) * seatRadius
                let seatRect = CGRect(x: sx - seatR, y: sy - seatR,
                                       width: seatR * 2, height: seatR * 2)
                ctx.setFillColor(filledIndices.contains(i)
                                  ? UIColor(red: 0.79, green: 0.66, blue: 0.38, alpha: 1).cgColor
                                  : UIColor(white: 0.84, alpha: 1).cgColor)
                ctx.fillEllipse(in: seatRect)
                let lbl = NSString(string: "\(i + 1)")
                let sz = lbl.size(withAttributes: seatLabelAttrs)
                lbl.draw(at: CGPoint(x: sx - sz.width / 2, y: sy - sz.height / 2 + 0.2),
                         withAttributes: seatLabelAttrs)
            }
        } else {
            // Rect / head
            let tableW: CGFloat = min(panelRect.width - 10, 50)
            let tableH: CGFloat = 10
            let rect = CGRect(x: cx - tableW / 2, y: cy - tableH / 2,
                              width: tableW, height: tableH)
            ctx.setFillColor(bodyFill.cgColor)
            ctx.setStrokeColor(bodyStroke.cgColor)
            ctx.setLineWidth(0.7)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 2)
            ctx.addPath(path.cgPath)
            ctx.drawPath(using: .fillStroke)

            let oneSide = table.oneSide == true
            let perSide = oneSide ? n : Int((CGFloat(n) / 2).rounded(.up))
            let spacing = tableW / CGFloat(perSide + 1)
            for i in 0..<n {
                let side: Int
                let pos: Int
                if oneSide { side = 0; pos = i }
                else { side = i < perSide ? 0 : 1; pos = side == 0 ? i : i - perSide }
                let sx = rect.minX + spacing * CGFloat(pos + 1)
                let sy = side == 0 ? rect.minY - 7 : rect.maxY + 7
                let seatRect = CGRect(x: sx - seatR, y: sy - seatR,
                                       width: seatR * 2, height: seatR * 2)
                ctx.setFillColor(filledIndices.contains(i)
                                  ? UIColor(red: 0.79, green: 0.66, blue: 0.38, alpha: 1).cgColor
                                  : UIColor(white: 0.84, alpha: 1).cgColor)
                ctx.fillEllipse(in: seatRect)
                let lbl = NSString(string: "\(i + 1)")
                let sz = lbl.size(withAttributes: seatLabelAttrs)
                lbl.draw(at: CGPoint(x: sx - sz.width / 2, y: sy - sz.height / 2 + 0.2),
                         withAttributes: seatLabelAttrs)
            }
        }
    }

    // MARK: - Legend (bottom of last Planner page)

    /// Web parity (App.jsx ~14391): only includes badge categories that
    /// are actually present in the plan, so the legend stays compact.
    private static func drawLegend(ctx: CGContext, plan: SeatingPlan, opts: PDFExportOpts,
                                   pageWidth: CGFloat, y: CGFloat) {
        var items: [(badge: DietaryBadge, text: String)] = []
        if opts.includeHighChairs && plan.guests.contains(where: { $0.highChair == true }) {
            items.append((DietaryBadge(label: "HC", color: UIColor(red: 0.89, green: 0.42, blue: 0.34, alpha: 1)),
                          "High chair"))
        }
        if plan.guests.contains(where: { $0.isChild == true }) {
            items.append((DietaryBadge(label: "KID", color: UIColor(red: 0.63, green: 0.43, blue: 0.82, alpha: 1)),
                          "Child"))
        }
        if opts.includeDietary {
            for tag in ["vegetarian", "vegan", "halal", "gluten-free", "dairy-free", "nut-allergy", "shellfish-allergy", "kosher"] {
                let present = plan.guests.contains { ($0.dietaryTags ?? []).contains(tag) }
                guard present, let badge = dietaryBadge(forTag: tag) else { continue }
                items.append((badge, dietaryLegendText(forTag: tag)))
            }
            let hasFreeText = plan.guests.contains { g in
                (g.dietary?.isEmpty == false) && (g.dietaryTags ?? []).isEmpty
            }
            if hasFreeText {
                items.append((DietaryBadge(label: "D", color: UIColor(red: 0.39, green: 0.55, blue: 0.78, alpha: 1)),
                              "Other dietary (see sub-line)"))
            }
        }
        guard !items.isEmpty else { return }

        ctx.setStrokeColor(UIColor(white: 0.88, alpha: 1).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: 40, y: y - 6))
        ctx.addLine(to: CGPoint(x: pageWidth - 40, y: y - 6))
        ctx.strokePath()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7, weight: .bold),
            .foregroundColor: UIColor(white: 0.55, alpha: 1),
        ]
        NSString(string: "LEGEND").draw(at: CGPoint(x: 40, y: y),
                                         withAttributes: labelAttrs)

        var x: CGFloat = 80
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7, weight: .regular),
            .foregroundColor: UIColor(white: 0.45, alpha: 1),
        ]
        for item in items {
            drawDietaryBadge(item.badge, center: CGPoint(x: x, y: y + 3), ctx: ctx)
            let label = NSString(string: item.text)
            label.draw(at: CGPoint(x: x + 8, y: y),
                       withAttributes: textAttrs)
            let labelW = label.size(withAttributes: textAttrs).width
            x += 10 + labelW + 12
            if x > pageWidth - 80 { break }
        }
    }

    private static func dietaryLegendText(forTag tag: String) -> String {
        switch tag {
        case "vegetarian":        return "Vegetarian"
        case "vegan":             return "Vegan"
        case "halal":             return "Halal"
        case "gluten-free":       return "Gluten-Free"
        case "dairy-free":        return "Dairy-Free"
        case "nut-allergy":       return "Nut Allergy"
        case "shellfish-allergy": return "Shellfish Allergy"
        case "kosher":            return "Kosher"
        default:                  return tag.capitalized
        }
    }

    /// Diagonal "Seatbee.app — Free plan — upgrade for clean prints"
    /// stamp matching web's free-tier watermark. Drawn last so it sits on
    /// top of all content; very low alpha so it's visible but not garish.
    private static func drawWatermark(ctx: CGContext, pageWidth: CGFloat, pageHeight: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: pageWidth / 2, y: pageHeight / 2)
        ctx.rotate(by: -.pi / 6)  // -30°
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 38, weight: .semibold),
            .foregroundColor: UIColor(white: 0.0, alpha: 0.07),
        ]
        let line1 = NSString(string: "SEATBEE.APP")
        let l1Size = line1.size(withAttributes: attrs)
        line1.draw(at: CGPoint(x: -l1Size.width / 2, y: -l1Size.height),
                   withAttributes: attrs)
        let smallAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor(white: 0.0, alpha: 0.07),
        ]
        let line2 = NSString(string: "Free plan — upgrade for clean prints")
        let l2Size = line2.size(withAttributes: smallAttrs)
        line2.draw(at: CGPoint(x: -l2Size.width / 2, y: 4),
                   withAttributes: smallAttrs)
        ctx.restoreGState()
    }

    /// Bottom footer line on every PDF page.
    private static func drawFooter(ctx: CGContext, pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: warmColor,
        ]
        let footer = NSString(string: "Generated by Seatbee · seatbee.app")
        let fSize = footer.size(withAttributes: attrs)
        footer.draw(at: CGPoint(x: (pageWidth - fSize.width) / 2,
                                y: pageHeight - margin - 12),
                    withAttributes: attrs)
    }

    /// Truncate `text` so its rendered width ≤ `maxWidth`, appending an
    /// ellipsis if a cut was made. Used by table-cell + annotation drawing
    /// so long meals/dietary strings don't bleed into adjacent columns.
    private static func truncate(_ text: String, attrs: [NSAttributedString.Key: Any], maxWidth: CGFloat) -> String {
        let ns = NSString(string: text)
        if ns.size(withAttributes: attrs).width <= maxWidth { return text }
        var lo = 0
        var hi = text.count
        while lo < hi {
            let mid = (lo + hi) / 2
            let prefix = String(text.prefix(mid)) + "…"
            let w = NSString(string: prefix).size(withAttributes: attrs).width
            if w <= maxWidth { lo = mid + 1 } else { hi = mid }
        }
        return String(text.prefix(max(0, lo - 1))) + "…"
    }

    // MARK: - Public share entry points

    static func shareSeatingChartPDF(plan: SeatingPlan, opts: PDFExportOpts, isPaid: Bool) {
        guard let data = generateSeatingChartPDF(plan: plan, opts: opts, isPaid: isPaid) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(plan.name) Seating Chart.pdf")
        try? data.write(to: url)
        shareFile(url)
    }

    static func sharePlannerViewPDF(plan: SeatingPlan, opts: PDFExportOpts, isPaid: Bool) {
        guard let data = generatePlannerViewPDF(plan: plan, opts: opts, isPaid: isPaid) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(plan.name) Planner View.pdf")
        try? data.write(to: url)
        shareFile(url)
    }


    // MARK: - Social Image — "Seating Wrapped"
    //
    // 1080×1080 share-card built like a Spotify Wrapped page: compact
    // Seatbee branding strip, big event title, headline guest/table
    // line, a horizontal-bar category breakdown (top 5 by guest count
    // with each category's own colour from rawCategories), and a
    // dynamic Highlights list — most popular meal, must-sit-together
    // people, kept-apart people, dietary diversity, VIPs, kids — only
    // showing the metrics the plan actually has data for.
    //
    // Sections are skipped (not just blanked) when empty, so an early-
    // planning plan still produces a polished card without dead space.
    // Tone: factual + delightful, never specific names or judgmental
    // copy ("kept apart" stays as-is, no jokes about who hates whom).

    @MainActor
    static func generateSocialImage(plan: SeatingPlan) -> UIImage? {
        let size: CGFloat = 1080
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let metrics = computeSocialMetrics(plan: plan)
        return renderer.image { context in
            let ctx = context.cgContext
            drawSocialBackground(ctx: ctx, size: size)

            var y: CGFloat = 70
            y = drawSocialBranding(ctx: ctx, size: size, topY: y)
            y = drawSocialEventBlock(ctx: ctx, plan: plan, size: size, topY: y + 24)
            y = drawSocialHeadlineStats(ctx: ctx, metrics: metrics, size: size, topY: y + 28)

            // Reserve room for the footer + a hair of breathing space
            let footerTopY: CGFloat = size - 130
            let availableHeight = footerTopY - y

            // Category chart only if we have ≥1 categorised guest. If
            // it's missing, the highlights section gets the extra room.
            if !metrics.topCategories.isEmpty {
                let chartHeight = min(360, availableHeight * 0.55)
                let nextY = drawSocialCategoryChart(ctx: ctx, metrics: metrics, size: size,
                                                    topY: y + 18, maxHeight: chartHeight)
                y = nextY
            }

            // Highlights — fills the rest, capped at 4 lines
            drawSocialHighlights(ctx: ctx, metrics: metrics, size: size,
                                 topY: y + 24, bottomY: footerTopY - 6)

            drawSocialFooter(ctx: ctx, size: size)
        }
    }

    // MARK: - Floor Plan Image
    //
    // 1080×1080 share-card built around the actual floor plan as the
    // hero. Same branded chrome as the Social Image (compact bee +
    // wordmark, event title, gold underline + date·venue, footer with
    // URL) so the two surfaces feel like a matched set, but the body
    // is a large render of the plan's tables/objects/seats via
    // CanvasPDFRenderer. Designed for Instagram / Stories-style "look
    // at our gorgeous room layout" sharing — not a print artefact.
    //
    // Lives next to the Social Image (not in CanvasPDFRenderer or its
    // own file) because the two share branding helpers; keeping them
    // co-located means the next time we tweak palette / typography /
    // footer copy, they update in lockstep.

    @MainActor
    static func generateFloorPlanImage(plan: SeatingPlan) -> UIImage? {
        let size: CGFloat = 1080
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let ctx = context.cgContext

            drawSocialBackground(ctx: ctx, size: size)

            var y: CGFloat = 70
            y = drawSocialBranding(ctx: ctx, size: size, topY: y)
            y = drawSocialEventBlock(ctx: ctx, plan: plan, size: size, topY: y + 24)

            // Floor plan card — generous footprint so it reads as the
            // hero. Reserved space for the mini-stats line + footer
            // below so the card has breathing room from the bottom.
            let cardTop = y + 28
            let cardBottom = size - 200
            let cardSide: CGFloat = 70
            let cardRect = CGRect(x: cardSide, y: cardTop,
                                   width: size - cardSide * 2,
                                   height: cardBottom - cardTop)

            // Soft drop-shadow effect via a slightly offset darker
            // rounded rect peeking out below the card. Subtle — adds
            // depth without looking "Web 2.0".
            ctx.saveGState()
            let shadowRect = cardRect.offsetBy(dx: 0, dy: 6)
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.06).cgColor)
            let shadowPath = UIBezierPath(roundedRect: shadowRect, cornerRadius: 18)
            ctx.addPath(shadowPath.cgPath)
            ctx.fillPath()
            ctx.restoreGState()

            // Card body — slightly off-white with a thin gold border
            // matching the outer canvas border for visual consistency.
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            ctx.setStrokeColor(socialGold.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(1.2)
            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 18)
            ctx.addPath(cardPath.cgPath)
            ctx.drawPath(using: .fillStroke)

            // Inset the actual drawing rect a hair so seat dots and
            // labels don't kiss the card border.
            let drawRect = cardRect.insetBy(dx: 16, dy: 16)
            CanvasPDFRenderer.drawFloorPlan(in: ctx, rect: drawRect, plan: plan)

            // Mini-stats line under the card: "110 GUESTS · 19 TABLES".
            // Small + restrained — the floor plan is the hero, this is
            // just context. Skip if the plan is empty.
            let totalGuests = plan.guests.filter { $0.rsvp != .no }.count
            let totalTables = plan.tables.count
            if totalGuests > 0 || totalTables > 0 {
                let statsY = cardBottom + 18
                let statsAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: socialWarm,
                    .kern: 1.5,
                ]
                let statsText = NSString(string: "\(totalGuests) GUESTS · \(totalTables) TABLES")
                let sSize = statsText.size(withAttributes: statsAttrs)
                statsText.draw(at: CGPoint(x: size / 2 - sSize.width / 2, y: statsY),
                               withAttributes: statsAttrs)
            }

            drawSocialFooter(ctx: ctx, size: size)
        }
    }

    static func shareFloorPlanImage(plan: SeatingPlan) {
        guard let image = generateFloorPlanImage(plan: plan),
              let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(plan.name) — Floor Plan.png")
        try? data.write(to: url)
        shareFile(url)
    }

    static func shareSocialImage(plan: SeatingPlan) {
        guard let image = generateSocialImage(plan: plan),
              let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(plan.name) — Seatbee.png")
        try? data.write(to: url)
        shareFile(url)
    }

    // MARK: - Social image — palette + metrics

    private static let socialIvory = UIColor(red: 250/255, green: 246/255, blue: 236/255, alpha: 1)
    private static let socialIvoryDeep = UIColor(red: 244/255, green: 235/255, blue: 215/255, alpha: 1)
    private static let socialChampagne = UIColor(red: 234/255, green: 220/255, blue: 188/255, alpha: 1)
    private static let socialGold = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 1)
    private static let socialGoldDk = UIColor(red: 161/255, green: 132/255, blue: 65/255, alpha: 1)
    private static let socialCharcoal = UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 1)
    private static let socialWarm = UIColor(red: 139/255, green: 134/255, blue: 128/255, alpha: 1)

    /// Pre-computed snapshot of everything the card might want to show.
    /// Each draw section reads from this so we never re-walk plan.guests
    /// per section. Empty arrays / nils mean "skip that section".
    private struct SocialMetrics {
        let totalGuests: Int
        let totalTables: Int
        let totalSeats: Int
        let topCategories: [(name: String, color: UIColor, count: Int)]
        let topMeal: (name: String, count: Int)?
        let mustSitPeople: Int
        let keepApartPeople: Int
        let dietaryGuests: Int
        let vipGuests: Int
        let childGuests: Int
        let highChairGuests: Int
    }

    private static func computeSocialMetrics(plan: SeatingPlan) -> SocialMetrics {
        let confirmed = plan.guests.filter { $0.rsvp != .no }
        let totalGuests = confirmed.count
        let totalTables = plan.tables.count
        let totalSeats = plan.tables.reduce(0) { $0 + $1.seats }

        // Categories — resolve from rawCategories (id → {name, color}),
        // count guests by ID match, take top 5 by count desc.
        var catNameById: [String: String] = [:]
        var catColorById: [String: UIColor] = [:]
        if let raw = plan.rawCategories {
            for entry in raw {
                guard let id = entry["id"]?.value as? String else { continue }
                catNameById[id] = (entry["name"]?.value as? String) ?? id
                if let hex = entry["color"]?.value as? String,
                   let c = parseSocialHex(hex) {
                    catColorById[id] = c
                }
            }
        }
        var categoryCounts: [String: Int] = [:]
        for g in confirmed {
            for cid in g.categories {
                categoryCounts[cid, default: 0] += 1
            }
        }
        let topCategories: [(name: String, color: UIColor, count: Int)] = categoryCounts
            .compactMap { id, count -> (String, UIColor, Int)? in
                guard let name = catNameById[id] else { return nil }
                let color = catColorById[id] ?? socialGold
                return (name, color, count)
            }
            .sorted { $0.2 > $1.2 }
            .prefix(5)
            .map { $0 }

        // Most popular meal — case-insensitive, trim, ignore blank.
        var mealCounts: [String: Int] = [:]
        for g in confirmed {
            guard let raw = g.meal?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            let key = raw.capitalized
            mealCounts[key, default: 0] += 1
        }
        let topMeal: (String, Int)? = mealCounts
            .max(by: { $0.value < $1.value })
            .map { ($0.key, $0.value) }

        // Rule-derived people counts (Set so a guest in multiple rules
        // counts once per category — otherwise it gets weird at 200%+).
        var mustSit = Set<String>()
        var keepApart = Set<String>()
        for rule in plan.rules where rule.enabled {
            switch rule.type {
            case .mustTogether, .preferTogether, .categoryTogether,
                 .sideTogether, .seatAdjacent:
                mustSit.formUnion(rule.guests)
            case .mustNot:
                keepApart.formUnion(rule.guests)
                if let a = rule.sideA { keepApart.formUnion(a) }
                if let b = rule.sideB { keepApart.formUnion(b) }
            default:
                break
            }
        }

        let dietaryGuests = confirmed.filter {
            ($0.dietaryTags?.isEmpty == false) || ($0.dietary?.isEmpty == false)
        }.count
        let vipGuests = confirmed.filter { $0.vip }.count
        let childGuests = confirmed.filter { $0.isChild == true }.count
        let highChairGuests = confirmed.filter { $0.highChair == true }.count

        return SocialMetrics(
            totalGuests: totalGuests,
            totalTables: totalTables,
            totalSeats: totalSeats,
            topCategories: topCategories,
            topMeal: topMeal,
            mustSitPeople: mustSit.count,
            keepApartPeople: keepApart.count,
            dietaryGuests: dietaryGuests,
            vipGuests: vipGuests,
            childGuests: childGuests,
            highChairGuests: highChairGuests
        )
    }

    private static func parseSocialHex(_ hex: String) -> UIColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let val = UInt32(s, radix: 16) else { return nil }
        return UIColor(red: CGFloat((val >> 16) & 0xFF) / 255,
                       green: CGFloat((val >> 8) & 0xFF) / 255,
                       blue: CGFloat(val & 0xFF) / 255,
                       alpha: 1)
    }

    // MARK: - Social image — drawing helpers

    /// Top-to-bottom soft ivory→champagne gradient + thin gold inner
    /// border so the card looks intentional on white feeds.
    private static func drawSocialBackground(ctx: CGContext, size: CGFloat) {
        let colors = [socialIvory.cgColor, socialIvoryDeep.cgColor] as CFArray
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: space, colors: colors,
                                         locations: [0, 1]) else {
            ctx.setFillColor(socialIvory.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            return
        }
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: 0, y: size),
                               options: [])

        let inset: CGFloat = 36
        let borderRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        ctx.setStrokeColor(socialGold.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(1.5)
        let borderPath = UIBezierPath(roundedRect: borderRect, cornerRadius: 24)
        ctx.addPath(borderPath.cgPath)
        ctx.strokePath()
    }

    /// Compact branding strip: bee logo on champagne halo + wordmark
    /// to the right of it (single horizontal line, not stacked) so the
    /// header steals less vertical space than the v1 layout. Returns
    /// the bottom Y of the strip so the next section can stack.
    private static func drawSocialBranding(ctx: CGContext, size: CGFloat, topY: CGFloat) -> CGFloat {
        let cx = size / 2
        let beeSide: CGFloat = 64
        let wordmarkW: CGFloat = 200
        let wordmarkH: CGFloat = wordmarkW / 6        // 720x120 native ratio
        let gap: CGFloat = 16
        let totalW = beeSide + gap + wordmarkW
        let startX = cx - totalW / 2

        // Halo behind bee
        let haloR: CGFloat = beeSide / 2 + 8
        let haloRect = CGRect(x: startX + beeSide / 2 - haloR,
                              y: topY + beeSide / 2 - haloR,
                              width: haloR * 2, height: haloR * 2)
        ctx.setFillColor(socialChampagne.withAlphaComponent(0.55).cgColor)
        ctx.fillEllipse(in: haloRect)

        // Bee logo
        if let bee = UIImage(named: "SeatbeeLogo") {
            bee.draw(in: CGRect(x: startX, y: topY, width: beeSide, height: beeSide))
        }
        // Wordmark — centred vertically against the bee
        if let mark = UIImage(named: "SeatbeeWordmark") {
            mark.draw(in: CGRect(x: startX + beeSide + gap,
                                 y: topY + (beeSide - wordmarkH) / 2,
                                 width: wordmarkW, height: wordmarkH))
        }

        // "Seating Wrapped" tagline
        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: socialGoldDk,
            .kern: 4,
        ]
        let tag = NSString(string: "SEATING WRAPPED")
        let tSize = tag.size(withAttributes: tagAttrs)
        tag.draw(at: CGPoint(x: cx - tSize.width / 2, y: topY + beeSide + 14),
                 withAttributes: tagAttrs)

        return topY + beeSide + 14 + tSize.height
    }

    /// Big event title + decorative gold bar + date · venue subtitle.
    /// Title auto-shrinks to fit the canvas width so long names don't
    /// bleed past the inner border. Returns the bottom Y of the block.
    private static func drawSocialEventBlock(ctx: CGContext, plan: SeatingPlan, size: CGFloat, topY: CGFloat) -> CGFloat {
        let cx = size / 2
        let maxWidth = size - 160
        let title = plan.name.uppercased()

        var fontSize: CGFloat = 56
        var titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: socialCharcoal,
            .kern: 1.5,
        ]
        var measured = NSString(string: title).size(withAttributes: titleAttrs)
        while measured.width > maxWidth && fontSize > 28 {
            fontSize -= 2
            titleAttrs[.font] = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            measured = NSString(string: title).size(withAttributes: titleAttrs)
        }
        NSString(string: title).draw(
            at: CGPoint(x: cx - measured.width / 2, y: topY),
            withAttributes: titleAttrs)

        let barWidth: CGFloat = 70
        let barY = topY + measured.height + 16
        ctx.setStrokeColor(socialGold.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: cx - barWidth / 2, y: barY))
        ctx.addLine(to: CGPoint(x: cx + barWidth / 2, y: barY))
        ctx.strokePath()

        var subParts: [String] = []
        if let date = plan.eventDate {
            let f = DateFormatter()
            f.dateStyle = .long
            subParts.append(f.string(from: date))
        }
        if let venue = plan.venue, !venue.isEmpty { subParts.append(venue) }
        var bottom = barY + 4
        if !subParts.isEmpty {
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 19, weight: .regular),
                .foregroundColor: socialWarm,
            ]
            let sub = NSString(string: subParts.joined(separator: " · "))
            let sSize = sub.size(withAttributes: subAttrs)
            sub.draw(at: CGPoint(x: cx - sSize.width / 2, y: barY + 14),
                     withAttributes: subAttrs)
            bottom = barY + 14 + sSize.height
        }
        return bottom
    }

    /// Single-line headline: "110 GUESTS · 19 TABLES" with the numbers
    /// in big gold and the labels in muted caps. Pure typography, no
    /// boxes — keeps the card from feeling card-heavy.
    private static func drawSocialHeadlineStats(ctx: CGContext, metrics: SocialMetrics, size: CGFloat, topY: CGFloat) -> CGFloat {
        let cx = size / 2

        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 64, weight: .bold),
            .foregroundColor: socialGoldDk,
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: socialWarm,
            .kern: 2,
        ]

        let guestsNum = NSString(string: "\(metrics.totalGuests)")
        let guestsLab = NSString(string: "GUESTS")
        let tablesNum = NSString(string: "\(metrics.totalTables)")
        let tablesLab = NSString(string: "TABLES")
        let dot = NSString(string: "·")
        let dotAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 56, weight: .light),
            .foregroundColor: socialGold.withAlphaComponent(0.5),
        ]

        let gNumSize = guestsNum.size(withAttributes: numAttrs)
        let gLabSize = guestsLab.size(withAttributes: labelAttrs)
        let tNumSize = tablesNum.size(withAttributes: numAttrs)
        let tLabSize = tablesLab.size(withAttributes: labelAttrs)
        let dotSize = dot.size(withAttributes: dotAttrs)

        // Each "stat unit" = number stacked above label. Centre each
        // unit, separator dot between.
        let gUnitW = max(gNumSize.width, gLabSize.width)
        let tUnitW = max(tNumSize.width, tLabSize.width)
        let unitGap: CGFloat = 32
        let totalW = gUnitW + unitGap + dotSize.width + unitGap + tUnitW
        let startX = cx - totalW / 2

        let gCenterX = startX + gUnitW / 2
        let dotX = startX + gUnitW + unitGap + dotSize.width / 2
        let tCenterX = startX + gUnitW + unitGap + dotSize.width + unitGap + tUnitW / 2

        guestsNum.draw(at: CGPoint(x: gCenterX - gNumSize.width / 2, y: topY),
                       withAttributes: numAttrs)
        guestsLab.draw(at: CGPoint(x: gCenterX - gLabSize.width / 2, y: topY + gNumSize.height + 4),
                       withAttributes: labelAttrs)
        dot.draw(at: CGPoint(x: dotX - dotSize.width / 2, y: topY + 6),
                 withAttributes: dotAttrs)
        tablesNum.draw(at: CGPoint(x: tCenterX - tNumSize.width / 2, y: topY),
                       withAttributes: numAttrs)
        tablesLab.draw(at: CGPoint(x: tCenterX - tLabSize.width / 2, y: topY + tNumSize.height + 4),
                       withAttributes: labelAttrs)

        return topY + gNumSize.height + 4 + gLabSize.height
    }

    /// Top-5 categories as horizontal bars. Each row: dot + name on the
    /// left, fill bar in category colour, count on the right. Bars are
    /// proportional to the largest category. Bounded by `maxHeight`.
    /// Returns the bottom Y so the next section can stack.
    private static func drawSocialCategoryChart(ctx: CGContext, metrics: SocialMetrics,
                                                size: CGFloat, topY: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let outerInset: CGFloat = 90
        let chartLeft = outerInset
        let chartRight = size - outerInset
        let chartWidth = chartRight - chartLeft

        // Section title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: socialWarm,
            .kern: 2.5,
        ]
        let title = NSString(string: "BY CATEGORY")
        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(at: CGPoint(x: size / 2 - titleSize.width / 2, y: topY),
                   withAttributes: titleAttrs)

        // Cap rows so we never blow past maxHeight
        let rowH: CGFloat = 36
        let rowGap: CGFloat = 8
        let availableForRows = maxHeight - titleSize.height - 18
        let maxRows = max(1, Int((availableForRows + rowGap) / (rowH + rowGap)))
        let rows = Array(metrics.topCategories.prefix(maxRows))

        let maxCount = max(1, rows.first?.count ?? 1)
        var y = topY + titleSize.height + 18

        // Layout: 30% name column | bar | count
        let nameColW = chartWidth * 0.30
        let countColW: CGFloat = 60
        let barLeft = chartLeft + nameColW + 8
        let barRight = chartRight - countColW - 8
        let barFullW = barRight - barLeft

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: socialCharcoal,
        ]
        let countAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17, weight: .bold),
            .foregroundColor: socialGoldDk,
        ]

        for cat in rows {
            // Category dot
            let dotR: CGFloat = 5
            let dotRect = CGRect(x: chartLeft, y: y + rowH / 2 - dotR,
                                  width: dotR * 2, height: dotR * 2)
            ctx.setFillColor(cat.color.cgColor)
            ctx.fillEllipse(in: dotRect)

            // Name (truncated to nameColW)
            let nameStr = NSString(string: truncate(cat.name, attrs: nameAttrs, maxWidth: nameColW - 16))
            let nameSize = nameStr.size(withAttributes: nameAttrs)
            nameStr.draw(at: CGPoint(x: chartLeft + 16,
                                      y: y + rowH / 2 - nameSize.height / 2),
                         withAttributes: nameAttrs)

            // Bar background
            let barH: CGFloat = 12
            let barY = y + rowH / 2 - barH / 2
            let bgRect = CGRect(x: barLeft, y: barY, width: barFullW, height: barH)
            ctx.setFillColor(socialChampagne.withAlphaComponent(0.5).cgColor)
            let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: barH / 2)
            ctx.addPath(bgPath.cgPath)
            ctx.fillPath()

            // Bar fill
            let fillW = max(barH, barFullW * CGFloat(cat.count) / CGFloat(maxCount))
            let fillRect = CGRect(x: barLeft, y: barY, width: fillW, height: barH)
            ctx.setFillColor(cat.color.withAlphaComponent(0.85).cgColor)
            let fillPath = UIBezierPath(roundedRect: fillRect, cornerRadius: barH / 2)
            ctx.addPath(fillPath.cgPath)
            ctx.fillPath()

            // Count (right-aligned)
            let countStr = NSString(string: "\(cat.count)")
            let cSize = countStr.size(withAttributes: countAttrs)
            countStr.draw(at: CGPoint(x: chartRight - cSize.width,
                                       y: y + rowH / 2 - cSize.height / 2),
                          withAttributes: countAttrs)

            y += rowH + rowGap
        }

        return y
    }

    /// Up-to-4 fun facts shaped like a Wrapped card: small gold bullet,
    /// a bold value + short label, optional secondary text. Each line
    /// only renders if its source data exists. Picked in priority
    /// order so the most interesting stats rise to the top.
    private static func drawSocialHighlights(ctx: CGContext, metrics: SocialMetrics,
                                             size: CGFloat, topY: CGFloat, bottomY: CGFloat) {
        let outerInset: CGFloat = 90
        let leftX = outerInset
        let rightX = size - outerInset

        // Build the full ranked list, pick top 4 that fit.
        var candidates: [(headline: String, detail: String)] = []
        if let meal = metrics.topMeal {
            candidates.append(("\(meal.count) ordered \(meal.name.lowercased())",
                               "Most popular meal"))
        }
        if metrics.mustSitPeople > 0 {
            candidates.append(("\(metrics.mustSitPeople) inseparable",
                               "Guests in must-sit-together rules"))
        }
        if metrics.dietaryGuests > 0 {
            let s = metrics.dietaryGuests == 1 ? "" : "s"
            candidates.append(("\(metrics.dietaryGuests) dietary need\(s)",
                               "Guests catered with care"))
        }
        if metrics.keepApartPeople > 0 {
            candidates.append(("\(metrics.keepApartPeople) carefully spaced",
                               "Guests in keep-apart rules"))
        }
        if metrics.vipGuests > 0 {
            let s = metrics.vipGuests == 1 ? "" : "s"
            candidates.append(("\(metrics.vipGuests) VIP\(s)",
                               "On the priority list"))
        }
        if metrics.childGuests > 0 {
            let s = metrics.childGuests == 1 ? "" : "s"
            candidates.append(("\(metrics.childGuests) little one\(s)",
                               "Kids in the room"))
        }
        if metrics.topCategories.isEmpty && candidates.isEmpty {
            // Nothing to highlight (very early-planning) — show a soft
            // closing note instead of empty space.
            let line = NSString(string: "Planning in progress")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 17),
                .foregroundColor: socialWarm,
            ]
            let s = line.size(withAttributes: attrs)
            line.draw(at: CGPoint(x: size / 2 - s.width / 2, y: topY),
                      withAttributes: attrs)
            return
        }

        // Section title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: socialWarm,
            .kern: 2.5,
        ]
        let title = NSString(string: "HIGHLIGHTS")
        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(at: CGPoint(x: size / 2 - titleSize.width / 2, y: topY),
                   withAttributes: titleAttrs)

        let headlineAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: socialCharcoal,
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: socialWarm,
        ]

        let rowH: CGFloat = 56
        let availableHeight = bottomY - (topY + titleSize.height + 16)
        let maxRows = max(1, Int(availableHeight / rowH))
        let chosen = Array(candidates.prefix(min(4, maxRows)))

        var y = topY + titleSize.height + 16
        for item in chosen {
            // Bullet — small filled gold circle
            let bulletR: CGFloat = 4
            let bulletRect = CGRect(x: leftX, y: y + 9,
                                     width: bulletR * 2, height: bulletR * 2)
            ctx.setFillColor(socialGold.cgColor)
            ctx.fillEllipse(in: bulletRect)

            let textX = leftX + bulletR * 2 + 14
            let truncatedHead = truncate(item.headline, attrs: headlineAttrs, maxWidth: rightX - textX)
            NSString(string: truncatedHead).draw(at: CGPoint(x: textX, y: y),
                                                  withAttributes: headlineAttrs)
            let truncatedDet = truncate(item.detail, attrs: detailAttrs, maxWidth: rightX - textX)
            NSString(string: truncatedDet).draw(at: CGPoint(x: textX, y: y + 26),
                                                 withAttributes: detailAttrs)
            y += rowH
        }
    }

    private static func drawSocialFooter(ctx: CGContext, size: CGFloat) {
        let cx = size / 2
        let y: CGFloat = size - 110
        let madeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: socialWarm,
        ]
        let made = NSString(string: "Made with Seatbee")
        let mSize = made.size(withAttributes: madeAttrs)
        made.draw(at: CGPoint(x: cx - mSize.width / 2, y: y), withAttributes: madeAttrs)

        let urlAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: socialGoldDk,
            .kern: 1.5,
        ]
        let url = NSString(string: "seatbee.app")
        let uSize = url.size(withAttributes: urlAttrs)
        url.draw(at: CGPoint(x: cx - uSize.width / 2, y: y + 22),
                 withAttributes: urlAttrs)
    }

    // MARK: - CSV exports (web parity)
    //
    // Mirrors web's `expGuestCSV` and `expTableCSV`. Same column order and
    // semantics so a CSV produced on iOS opens cleanly in the same spreadsheet
    // template a web user would use.

    static func shareGuestListCSV(plan: SeatingPlan) {
        let csv = generateGuestCSV(plan: plan)
        // Web parity (App.jsx:14429): replace any non-alphanumeric with
        // _, suffix `_guests.csv`.
        let url = writeTempFile(csv, name: "\(csvSafeName(plan.name))_guests.csv")
        shareFile(url)
    }

    static func shareTablesCSV(plan: SeatingPlan) {
        let csv = generateTablesCSV(plan: plan)
        let url = writeTempFile(csv, name: "\(csvSafeName(plan.name))_tables.csv")
        shareFile(url)
    }

    /// Web parity (`(state.event?.name||'seating').replace(/[^a-z0-9]/gi,'_')`).
    /// Underscore-replaces any character that isn't `[A-Za-z0-9]`.
    private static func csvSafeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let mapped = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(mapped)
        return result.isEmpty ? "seating" : result
    }

    private static func generateGuestCSV(plan: SeatingPlan) -> String {
        // Web parity (App.jsx expCSV ~14406). Column order, header
        // names, value formatting, and even the always-empty Seat
        // column all match exactly so caterers/vendors can't tell
        // which client produced the file.
        var seatByGuest: [String: SeatTable] = [:]
        for table in plan.tables {
            for guestId in table.assignments.keys {
                seatByGuest[guestId] = table
            }
        }

        // Resolve per-guest party member names from rawParties so the
        // Party column matches web's `partyNames` formatting (display
        // or first-name fallback, joined by '; ', excludes self).
        var partyMemberNames: [String: String] = [:]
        if let rawParties = plan.rawParties {
            let guestById = Dictionary(uniqueKeysWithValues: plan.guests.map { ($0.id, $0) })
            for partyDict in rawParties {
                guard let memberIds = partyDict["guestIds"]?.value as? [String] else { continue }
                let names = memberIds.map { id -> (gid: String, name: String) in
                    guard let g = guestById[id] else { return (id, "") }
                    let label = (g.display?.isEmpty == false) ? g.display!
                        : g.name.split(separator: " ").first.map(String.init) ?? ""
                    return (id, label)
                }
                for (gid, _) in names {
                    let others = names.filter { $0.gid != gid && !$0.name.isEmpty }
                                      .map(\.name)
                                      .joined(separator: "; ")
                    if !others.isEmpty { partyMemberNames[gid] = others }
                }
            }
        }

        let header = [
            "Guest Name", "Display Name", "RSVP", "Table", "Seat",
            "Meal", "Dietary", "Category", "Side", "VIP",
            "Child", "High Chair", "Party", "Email", "Phone", "Notes"
        ]
        var rows: [[String]] = [header]
        for g in plan.guests {
            let table = seatByGuest[g.id]
            let categoryNames = g.categories.compactMap { id -> String? in
                guard let raw = plan.rawCategories else { return id }
                let entry = raw.first { ($0["id"]?.value as? String) == id }
                return (entry?["name"]?.value as? String) ?? id
            }.joined(separator: "; ")

            // Web mapping: yes→Yes, no→No, pending→Maybe, else ''
            let rsvpLabel: String
            switch g.rsvp {
            case .yes:     rsvpLabel = "Yes"
            case .no:      rsvpLabel = "No"
            case .pending: rsvpLabel = "Maybe"
            default:       rsvpLabel = ""
            }

            rows.append([
                g.name,                                  // Guest Name (full)
                g.display ?? "",                          // Display Name
                rsvpLabel,                                // RSVP (capitalized)
                table?.name ?? "Unassigned",              // Table
                "",                                       // Seat (web leaves blank — App.jsx:14423)
                g.meal ?? "",                             // Meal
                g.dietary ?? "",                          // Dietary
                categoryNames,                            // Category (joined; matches web's `cats`)
                g.side.rawValue,                          // Side
                g.vip ? "Yes" : "",                       // VIP (capital Y, matches web)
                (g.isChild == true) ? "Yes" : "",         // Child
                (g.highChair == true) ? "Yes" : "",       // High Chair
                partyMemberNames[g.id] ?? "",             // Party (other member names)
                g.email ?? "",                            // Email
                "",                                       // Phone (iOS Guest model has no phone field)
                g.notes ?? "",                            // Notes
            ])
        }
        return csvString(rows)
    }

    /// Web parity (App.jsx getMealShort). Maps a guest's free-text
    /// meal to a normalised short label so meal columns aggregate
    /// cleanly. `Beef`/`Salmon`/`Chicken`/`Vegan` are the canonical
    /// shorts; anything else falls back to the first two words.
    private static func mealShort(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let m = raw.lowercased()
        if m.contains("beef") || m.contains("tenderloin") { return "Beef" }
        if m.contains("salmon") || m.contains("prawn") || m.contains("fish") { return "Salmon" }
        if m.contains("chicken") { return "Chicken" }
        if m.contains("mushroom") || m.contains("quinoa") || m.contains("vegan") || m.contains("vegetarian") {
            return "Vegan"
        }
        return raw.split(separator: " ").prefix(2).joined(separator: " ")
    }

    private static func generateTablesCSV(plan: SeatingPlan) -> String {
        // Web parity (App.jsx expTableCSV ~14433). One column PER meal
        // type (Beef / Chicken / Salmon / Vegan / etc.) instead of a
        // single combined "Meal breakdown" column. Includes an
        // (Unassigned) row for guests with no table and a TOTALS row.
        let guestsById = Dictionary(uniqueKeysWithValues: plan.guests.map { ($0.id, $0) })
        let assignedIds = Set(plan.tables.flatMap { $0.assignments.keys })

        // Collect every meal short across SEATED guests, sorted alpha.
        var mealSet = Set<String>()
        for g in plan.guests where assignedIds.contains(g.id) {
            if let s = mealShort(g.meal) { mealSet.insert(s) }
        }
        let mealTypes = mealSet.sorted()
        let hasMeals = !mealTypes.isEmpty

        var header = ["Table", "Type", "Capacity", "Seated"]
        if hasMeals { header.append(contentsOf: mealTypes) }
        header.append(contentsOf: ["Dietary Needs", "High Chairs", "Guests"])

        var rows: [[String]] = [header]

        var totalSeated = 0
        var totalCapacity = 0
        var totalHighChairs = 0
        var totalMeals: [String: Int] = [:]
        for m in mealTypes { totalMeals[m] = 0 }
        var totalDietary: [String] = []

        for table in plan.tables {
            let tGuests = table.assignments.keys.compactMap { guestsById[$0] }
            let seated = tGuests.count
            totalSeated += seated
            totalCapacity += table.seats

            var mealCounts: [String: Int] = [:]
            for m in mealTypes { mealCounts[m] = 0 }
            for g in tGuests {
                if let s = mealShort(g.meal), mealCounts[s] != nil {
                    mealCounts[s, default: 0] += 1
                    totalMeals[s, default: 0] += 1
                }
            }

            let dietaryList = tGuests.compactMap { g -> String? in
                guard let d = g.dietary, !d.isEmpty else { return nil }
                return d
            }
            let dietarySummary = dietaryList.joined(separator: "; ")
            totalDietary.append(contentsOf: dietaryList)

            let highChairs = tGuests.filter { $0.highChair == true }.count
            totalHighChairs += highChairs

            // Web uses g.name (full) for the table's guest list, not
            // displayName.
            let names = tGuests.map { $0.name }.joined(separator: "; ")

            var row: [String] = [
                table.name,
                table.type.rawValue,
                String(table.seats),
                String(seated),
            ]
            if hasMeals {
                row.append(contentsOf: mealTypes.map { mealCounts[$0]! > 0 ? String(mealCounts[$0]!) : "" })
            }
            row.append(contentsOf: [
                dietarySummary,
                highChairs > 0 ? String(highChairs) : "",
                names,
            ])
            rows.append(row)
        }

        // (Unassigned) row — RSVP=no guests are excluded, matching web.
        let unassigned = plan.guests.filter {
            !assignedIds.contains($0.id) && $0.rsvp != .no
        }
        if !unassigned.isEmpty {
            var mealCounts: [String: Int] = [:]
            for m in mealTypes { mealCounts[m] = 0 }
            for g in unassigned {
                if let s = mealShort(g.meal), mealCounts[s] != nil {
                    mealCounts[s, default: 0] += 1
                    totalMeals[s, default: 0] += 1
                }
            }
            let dietaryList = unassigned.compactMap { g -> String? in
                guard let d = g.dietary, !d.isEmpty else { return nil }
                return d
            }
            let highChairs = unassigned.filter { $0.highChair == true }.count
            totalHighChairs += highChairs

            var row: [String] = ["(Unassigned)", "", "-", String(unassigned.count)]
            if hasMeals {
                row.append(contentsOf: mealTypes.map { mealCounts[$0]! > 0 ? String(mealCounts[$0]!) : "" })
            }
            row.append(contentsOf: [
                dietaryList.joined(separator: "; "),
                highChairs > 0 ? String(highChairs) : "",
                unassigned.map { $0.name }.joined(separator: "; "),
            ])
            rows.append(row)
        }

        // Blank separator + TOTALS row.
        rows.append([])
        var totals: [String] = ["TOTALS", "", String(totalCapacity), String(totalSeated + unassigned.count)]
        if hasMeals {
            totals.append(contentsOf: mealTypes.map { String(totalMeals[$0] ?? 0) })
        }
        totals.append(contentsOf: [
            "\(totalDietary.count) total",
            totalHighChairs > 0 ? String(totalHighChairs) : "",
            "",
        ])
        rows.append(totals)

        return csvString(rows)
    }

    /// Web-parity CSV (App.jsx ~14425): wraps EVERY field in double
    /// quotes (not just ones containing separators), doubles internal
    /// quotes, joins rows with `\n` (not CRLF). Excel + Numbers parse
    /// either format fine, but matching byte-for-byte means a vendor
    /// can't tell which client generated the file.
    private static func csvString(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { cell in
                let escaped = cell.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            .joined(separator: ",")
        }
        .joined(separator: "\n")
    }

    private static func writeTempFile(_ contents: String, name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func safeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: invalid).joined(separator: "-")
    }

    // MARK: - Share Helper

    private static func shareFile(_ url: URL) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}
