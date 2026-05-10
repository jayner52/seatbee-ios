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
        // 1080×1350 — Instagram portrait. Gives the layout enough
        // vertical room for branding + title + headline + category
        // chart + 4 highlights + 4 badges + footer without trimming
        // anything. Square (1080²) was tight; portrait reads natural
        // in the IG feed and stories.
        let size = CGSize(width: 1080, height: 1350)
        let renderer = UIGraphicsImageRenderer(size: size)
        let metrics = computeSocialMetrics(plan: plan)
        let badges = snapshotBadges(for: metrics, plan: plan)
        return renderer.image { context in
            let ctx = context.cgContext
            drawSocialBackground(ctx: ctx, size: size)

            var y: CGFloat = 70
            y = drawSocialBranding(ctx: ctx, size: size, topY: y, tagline: "SEATING SNAPSHOT")
            y = drawSocialEventBlock(ctx: ctx, plan: plan, size: size, topY: y + 24)
            y = drawSocialHeadlineStats(ctx: ctx, metrics: metrics, size: size, topY: y + 28)

            // Reserve space at the bottom for footer + badges.
            let footerTopY: CGFloat = size.height - 130
            let badgesHeight: CGFloat = badges.isEmpty ? 0 : 158  // header + tiles + breathing
            let badgesTopY = footerTopY - badgesHeight - 16
            let highlightsBottomY = badgesTopY - 18

            let availableHeight = badgesTopY - y

            // Adaptive row sizing: when the plan is sparse (few
            // categories, few highlights) we'd otherwise leave a big
            // void between the highlights and the badges row. Compute
            // each section's "natural" height at base row sizes, then
            // distribute any leftover space as taller rows so the card
            // stays balanced top-to-bottom regardless of plan density.
            let chartRows = min(metrics.topCategories.count, 5)
            let highlightItemsCount = countHighlightCandidates(metrics)
            let baseChartRow: CGFloat = 36
            let baseHlRow: CGFloat = 56
            // Section overheads: title + 18 (chart) / title + 16 (hl).
            let chartOverhead: CGFloat = chartRows > 0 ? 30 : 0
            let hlOverhead: CGFloat = highlightItemsCount > 0 ? 28 : 0
            let interGap: CGFloat = (chartRows > 0 && highlightItemsCount > 0) ? 24 : 0
            let chartNat = chartOverhead + CGFloat(chartRows) * baseChartRow + max(0, CGFloat(chartRows - 1)) * 8
            let hlNat = hlOverhead + CGFloat(highlightItemsCount) * baseHlRow
            let naturalTotal = 18 /* lead-in to chart */ + chartNat + interGap + hlNat
            let slack = max(0, availableHeight - naturalTotal)
            let totalRowsForSlack = max(1, chartRows + highlightItemsCount)
            let perRowSlack = slack / CGFloat(totalRowsForSlack)
            let chartRowH: CGFloat = min(56, baseChartRow + perRowSlack)
            let hlRowH: CGFloat = min(80, baseHlRow + perRowSlack)

            // Category chart — only if categorised guests exist.
            if !metrics.topCategories.isEmpty {
                let chartHeight = min(420, availableHeight * 0.6)
                y = drawSocialCategoryChart(ctx: ctx, metrics: metrics, size: size,
                                             topY: y + 18, maxHeight: chartHeight,
                                             rowHeight: chartRowH)
            }

            // Highlights — fills space between chart and badges.
            drawSocialHighlights(ctx: ctx, metrics: metrics, size: size,
                                 topY: y + 24, bottomY: highlightsBottomY,
                                 rowHeight: hlRowH)

            // Badges row — pinned just above the footer.
            _ = drawSocialBadges(ctx: ctx, badges: badges, size: size, topY: badgesTopY)

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
    static func generateFloorPlanImage(plan: SeatingPlan, showGuestNames: Bool = false) -> UIImage? {
        // Floor plan stays square 1080² — the floor plan is the
        // visual hero and the square crop reads cleanly on IG / X
        // / iMessage previews without letterboxing.
        let size = CGSize(width: 1080, height: 1080)
        // Force scale = 4 so the underlying pixel buffer is 4320×4320
        // regardless of which device renders it. Combined with the
        // guest-name font bump (CanvasPDFRenderer 7.5→9pt), names are
        // now ~33 actual pixels tall instead of ~16, so they stay sharp
        // when the user zooms past the native 1080-pt size in Photos.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 4
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let ctx = context.cgContext

            drawSocialBackground(ctx: ctx, size: size)

            var y: CGFloat = 70
            // No tagline — the floor plan diagram IS the content, and
            // the bee + wordmark already establishes brand. Avoids the
            // visual noise of "FLOOR PLAN" labelled twice.
            y = drawSocialBranding(ctx: ctx, size: size, topY: y, tagline: nil)
            y = drawSocialEventBlock(ctx: ctx, plan: plan, size: size, topY: y + 24)

            // Floor plan card — generous footprint so it reads as the
            // hero. Reserved space for the mini-stats line + footer
            // below so the card has breathing room from the bottom.
            let cardTop = y + 28
            let cardBottom = size.height - 200
            let cardSide: CGFloat = 70
            let cardRect = CGRect(x: cardSide, y: cardTop,
                                   width: size.width - cardSide * 2,
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
            CanvasPDFRenderer.drawFloorPlan(in: ctx, rect: drawRect, plan: plan,
                                             showGuestNames: showGuestNames)

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
                statsText.draw(at: CGPoint(x: size.width / 2 - sSize.width / 2, y: statsY),
                               withAttributes: statsAttrs)
            }

            drawSocialFooter(ctx: ctx, size: size)
        }
    }

    static func shareFloorPlanImage(plan: SeatingPlan, showGuestNames: Bool = false) {
        guard let image = generateFloorPlanImage(plan: plan, showGuestNames: showGuestNames),
              let data = image.pngData() else { return }
        // Filename hints at the variant so the user can tell two
        // exports apart in their Photos / Files app.
        let suffix = showGuestNames ? "Seating Chart" : "Floor Plan"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(plan.name) — \(suffix).png")
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
        let distinctMealCount: Int        // # of unique meal options ordered
        let distinctDietaryTagCount: Int  // # of unique dietary tags represented
        let categoriesWithMembers: Int    // # of categories with ≥1 guest
        let mustSitPeople: Int
        let keepApartPeopleCount: Int
        let keepApartRuleCount: Int       // separate from people-count for badge purposes
        let mustSitRuleCount: Int
        let dietaryGuests: Int
        let vipGuests: Int
        let childGuests: Int
        let highChairGuests: Int
        let hasGrandparentsCategoryWithMembers: Bool
        let hasKidsCategoryWithMembers: Bool
        // Table shape mix — used for the TABLES sub-line and (down the
        // road) badges. Counts by SeatTable.TableType.
        let tableTypeCounts: [SeatTable.TableType: Int]
    }

    /// Mirrors the candidate-building order in drawSocialHighlights so
    /// generateSocialImage can size the section before drawing it.
    /// Capped at 4 to match the visible row cap.
    private static func countHighlightCandidates(_ m: SocialMetrics) -> Int {
        var n = 0
        if m.topMeal != nil { n += 1 }
        if m.mustSitPeople > 0 { n += 1 }
        if m.dietaryGuests > 0 { n += 1 }
        if m.keepApartPeopleCount > 0 { n += 1 }
        if m.vipGuests > 0 { n += 1 }
        if m.childGuests > 0 { n += 1 }
        return min(4, n)
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
        // Hide system "seating directive" categories from the chart —
        // head_table / sweetheart_table are flags that drive auto-
        // placement in solve.js, not demographic groupings, and the
        // user already sees them as table types in the room. Showing
        // them here just adds noise (especially on small plans where
        // a 2-guest "Sweetheart Table" row drowns out real groupings).
        let hiddenCategoryIds: Set<String> = ["head_table", "sweetheart_table"]
        var categoryCounts: [String: Int] = [:]
        for g in confirmed {
            for cid in g.categories where !hiddenCategoryIds.contains(cid) {
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

        // Distinct meal options ordered (for the Culinary Spectacle
        // badge). Case-insensitive de-dup so "Beef" and "beef" don't
        // count separately.
        let distinctMealCount = Set(
            confirmed.compactMap {
                $0.meal?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .filter { !$0.isEmpty }
        ).count

        // Distinct dietary tags represented (for The Foodie Wedding
        // badge). Tags are already canonical strings ("vegetarian",
        // "vegan", etc) so direct Set works.
        let distinctDietaryTagCount = Set(
            confirmed.flatMap { $0.dietaryTags ?? [] }
        ).count

        // Categories with at least one assigned guest (for The Mixer
        // badge). Mirrors the topCategories count without slicing to 5.
        let categoriesWithMembers = categoryCounts.values.filter { $0 > 0 }.count

        // Multi-Generational badge — needs both Grandparents AND Kids
        // categories with members. Use the canonical category names
        // resolved from rawCategories. Web's default category seed
        // uses these exact strings (App.jsx ~line 3042).
        let nameById: [String: String] = catNameById
        let counts: [String: Int] = categoryCounts
        func hasCategoryNamed(_ keyword: String) -> Bool {
            counts.contains { id, count in
                guard count > 0 else { return false }
                let name = (nameById[id] ?? id).lowercased()
                return name.contains(keyword)
            }
        }
        let hasGrandparents = hasCategoryNamed("grandparent")
        let hasKids = hasCategoryNamed("kid") || hasCategoryNamed("child")

        // Table-shape mix (for the headline sub-line + future badges).
        var tableTypeCounts: [SeatTable.TableType: Int] = [:]
        for table in plan.tables {
            tableTypeCounts[table.type, default: 0] += 1
        }

        // Rule counts split from people counts so badges can target
        // either dimension (e.g., The Diplomat fires on rule count,
        // not people count).
        let mustSitRuleCount = plan.rules.filter { rule in
            guard rule.enabled else { return false }
            switch rule.type {
            case .mustTogether, .preferTogether, .categoryTogether,
                 .sideTogether, .seatAdjacent: return true
            default: return false
            }
        }.count
        let keepApartRuleCount = plan.rules.filter {
            $0.enabled && $0.type == .mustNot
        }.count

        return SocialMetrics(
            totalGuests: totalGuests,
            totalTables: totalTables,
            totalSeats: totalSeats,
            topCategories: topCategories,
            topMeal: topMeal,
            distinctMealCount: distinctMealCount,
            distinctDietaryTagCount: distinctDietaryTagCount,
            categoriesWithMembers: categoriesWithMembers,
            mustSitPeople: mustSit.count,
            keepApartPeopleCount: keepApart.count,
            keepApartRuleCount: keepApartRuleCount,
            mustSitRuleCount: mustSitRuleCount,
            dietaryGuests: dietaryGuests,
            vipGuests: vipGuests,
            childGuests: childGuests,
            highChairGuests: highChairGuests,
            hasGrandparentsCategoryWithMembers: hasGrandparents,
            hasKidsCategoryWithMembers: hasKids,
            tableTypeCounts: tableTypeCounts
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

    // MARK: - Snapshot badges
    //
    // Up to 4 badges shown in a horizontal row on the Snapshot card.
    // Each badge is an SF-Symbol icon + name + one-line subtitle,
    // tinted with one of the brand palette colours so the row reads
    // as varied. Badges are picked from a priority-ordered list —
    // the most-specific / most-celebratory triggers fire first so a
    // 350-guest multi-generational wedding doesn't always default to
    // "The Banquet".
    //
    // Empty array when no triggers fire — we don't backfill with a
    // generic "Crafted Seating" badge so the absence of badges
    // genuinely communicates "this plan is still simple".

    private struct SnapshotBadge {
        let icon: String        // SF Symbol name
        let title: String       // Bold headline
        let subtitle: String    // One-line detail, dynamic when useful
        let tint: UIColor       // Icon-tile background tint
        let foreground: UIColor // Icon stroke colour
    }

    private static func snapshotBadges(for metrics: SocialMetrics, plan: SeatingPlan) -> [SnapshotBadge] {
        var out: [SnapshotBadge] = []

        // Brand palette aliases for badge tints.
        let goldFill   = socialChampagne.withAlphaComponent(0.7)
        let goldFG     = socialGoldDk
        let sageFill   = UIColor(red: 213/255, green: 222/255, blue: 198/255, alpha: 1)
        let sageFG     = UIColor(red: 91/255,  green: 127/255, blue: 78/255,  alpha: 1)
        let blushFill  = UIColor(red: 240/255, green: 218/255, blue: 215/255, alpha: 1)
        let blushFG    = UIColor(red: 168/255, green: 95/255,  blue: 88/255,  alpha: 1)
        let charcoalFill = UIColor(red: 232/255, green: 226/255, blue: 218/255, alpha: 1)
        let charcoalFG = socialCharcoal

        // 1. Multi-Generational — both Grandparents and Kids categories
        //    populated. Most specific combo, fires first.
        if metrics.hasGrandparentsCategoryWithMembers && metrics.hasKidsCategoryWithMembers {
            out.append(SnapshotBadge(
                icon: "figure.2.and.child.holdinghands",
                title: "Multi-Generational",
                subtitle: "From grandkids to grandparents",
                tint: sageFill, foreground: sageFG
            ))
        }
        // 2. Culinary Spectacle — at least 4 distinct meal options.
        if metrics.distinctMealCount >= 4 {
            out.append(SnapshotBadge(
                icon: "fork.knife",
                title: "Culinary Spectacle",
                subtitle: "\(metrics.distinctMealCount) meals on the menu",
                tint: goldFill, foreground: goldFG
            ))
        }
        // 3. The Foodie Wedding — at least 3 distinct dietary tags.
        if metrics.distinctDietaryTagCount >= 3 {
            out.append(SnapshotBadge(
                icon: "leaf.fill",
                title: "The Foodie Wedding",
                subtitle: "\(metrics.distinctDietaryTagCount) dietary needs accommodated",
                tint: sageFill, foreground: sageFG
            ))
        }
        // 4. The Diplomat — keep-apart rules. Rare, surfaces high.
        if metrics.keepApartRuleCount >= 3 {
            out.append(SnapshotBadge(
                icon: "scale.3d",
                title: "The Diplomat",
                subtitle: "Carefully spaced",
                tint: charcoalFill, foreground: charcoalFG
            ))
        }
        // 5. Inseparable Bunch — ≥30% of guests in must-sit-together.
        if metrics.totalGuests > 0,
           Double(metrics.mustSitPeople) / Double(metrics.totalGuests) >= 0.30 {
            out.append(SnapshotBadge(
                icon: "link",
                title: "Inseparable Bunch",
                subtitle: "\(metrics.mustSitPeople) people who must sit together",
                tint: goldFill, foreground: goldFG
            ))
        }
        // 6. Kid-Friendly — ≥10% kids OR ≥5 high chairs.
        let kidPct = metrics.totalGuests > 0
            ? Double(metrics.childGuests) / Double(metrics.totalGuests)
            : 0
        if kidPct >= 0.10 || metrics.highChairGuests >= 5 {
            let count = max(metrics.childGuests, metrics.highChairGuests)
            out.append(SnapshotBadge(
                icon: "teddybear.fill",
                title: "Kid-Friendly",
                subtitle: "\(count) little one\(count == 1 ? "" : "s") on the list",
                tint: blushFill, foreground: blushFG
            ))
        }
        // 7. VIP Night — ≥10 VIPs OR ≥5% VIP.
        let vipPct = metrics.totalGuests > 0
            ? Double(metrics.vipGuests) / Double(metrics.totalGuests)
            : 0
        if metrics.vipGuests >= 10 || vipPct >= 0.05 {
            out.append(SnapshotBadge(
                icon: "crown.fill",
                title: "VIP Night",
                subtitle: "\(metrics.vipGuests) on the priority list",
                tint: goldFill, foreground: goldFG
            ))
        }
        // 8. The Banquet — large guest count.
        if metrics.totalGuests >= 300 {
            out.append(SnapshotBadge(
                icon: "wineglass.fill",
                title: "The Banquet",
                subtitle: "A grand affair",
                tint: charcoalFill, foreground: charcoalFG
            ))
        }
        // 9. Tiny But Mighty — small guest count.
        if metrics.totalGuests > 0 && metrics.totalGuests <= 30 {
            out.append(SnapshotBadge(
                icon: "sparkle",
                title: "Tiny But Mighty",
                subtitle: "Intimate gathering",
                tint: blushFill, foreground: blushFG
            ))
        }
        // 10. The Mixer — ≥7 categories with members (catch-all variety).
        if metrics.categoriesWithMembers >= 7 {
            out.append(SnapshotBadge(
                icon: "person.3.fill",
                title: "The Mixer",
                subtitle: "\(metrics.categoriesWithMembers) different guest crews",
                tint: goldFill, foreground: goldFG
            ))
        }

        // Cap at 4 — top of the list wins. Order above is the priority
        // (most-specific badges first so they always win the ranking).
        return Array(out.prefix(4))
    }

    /// Horizontal row of up to 4 badge tiles. Auto-balances width so
    /// 1 badge fills a centred third, 2 fill halves, 3 fill thirds,
    /// 4 fill quarters. Each tile = icon-on-tinted-square + bold name
    /// + one-line subtitle. Returns the bottom Y of the row (or
    /// topY unchanged when no badges fired).
    private static func drawSocialBadges(ctx: CGContext, badges: [SnapshotBadge],
                                          size: CGSize, topY: CGFloat) -> CGFloat {
        guard !badges.isEmpty else { return topY }

        let outerInset: CGFloat = 60
        let usableWidth = size.width - outerInset * 2
        let tileGap: CGFloat = 10
        let count = badges.count
        let tileWidth = (usableWidth - tileGap * CGFloat(count - 1)) / CGFloat(count)
        let tileHeight: CGFloat = 110

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: socialWarm,
            .kern: 2.5,
        ]
        let header = NSString(string: "BADGES")
        let hSize = header.size(withAttributes: titleAttrs)
        header.draw(at: CGPoint(x: size.width / 2 - hSize.width / 2, y: topY),
                    withAttributes: titleAttrs)

        let rowY = topY + hSize.height + 14
        for (i, badge) in badges.enumerated() {
            let x = outerInset + CGFloat(i) * (tileWidth + tileGap)
            drawSingleBadge(badge,
                            rect: CGRect(x: x, y: rowY,
                                          width: tileWidth, height: tileHeight),
                            ctx: ctx)
        }
        return rowY + tileHeight
    }

    private static func drawSingleBadge(_ badge: SnapshotBadge, rect: CGRect, ctx: CGContext) {
        // Tile background — soft white card with a thin gold border so
        // each badge feels like a stamp without competing with the
        // category-bar palette above.
        let tilePath = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setStrokeColor(socialGold.withAlphaComponent(0.30).cgColor)
        ctx.setLineWidth(0.8)
        ctx.addPath(tilePath.cgPath)
        ctx.drawPath(using: .fillStroke)

        // Icon tile — coloured square at the top-centre.
        let iconSide: CGFloat = 38
        let iconRect = CGRect(x: rect.midX - iconSide / 2,
                               y: rect.minY + 10,
                               width: iconSide, height: iconSide)
        let iconBg = UIBezierPath(roundedRect: iconRect, cornerRadius: 9)
        ctx.setFillColor(badge.tint.cgColor)
        ctx.addPath(iconBg.cgPath)
        ctx.fillPath()

        // SF Symbol — render via UIImage configured with the badge's
        // foreground colour. Falls back gracefully if the symbol name
        // isn't available on the running iOS version.
        if let symbol = sfSymbolImage(name: badge.icon, pointSize: 20, weight: .semibold,
                                       tint: badge.foreground) {
            let renderSide: CGFloat = 22
            let symbolRect = CGRect(x: iconRect.midX - renderSide / 2,
                                     y: iconRect.midY - renderSide / 2,
                                     width: renderSide, height: renderSide)
            symbol.draw(in: symbolRect)
        }

        // Title — bold, charcoal, single line.
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: socialCharcoal,
        ]
        let title = NSString(string: badge.title)
        let titleSize = title.size(withAttributes: titleAttrs)
        let titleY = iconRect.maxY + 8
        title.draw(at: CGPoint(x: rect.midX - titleSize.width / 2, y: titleY),
                   withAttributes: titleAttrs)

        // Subtitle — muted, 1-2 lines, truncated to fit.
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: socialWarm,
        ]
        let truncated = truncate(badge.subtitle,
                                  attrs: subtitleAttrs,
                                  maxWidth: rect.width - 12)
        let subtitle = NSString(string: truncated)
        let subSize = subtitle.size(withAttributes: subtitleAttrs)
        subtitle.draw(at: CGPoint(x: rect.midX - subSize.width / 2,
                                   y: titleY + titleSize.height + 2),
                      withAttributes: subtitleAttrs)
    }

    /// Render an SF Symbol as a UIImage at the given point size,
    /// weight, and tint. Used by the badge tiles. Falls back to nil
    /// if the symbol isn't available — the badge tile renders without
    /// an icon but still shows title + subtitle, so we never crash on
    /// a missing symbol.
    private static func sfSymbolImage(name: String, pointSize: CGFloat,
                                       weight: UIImage.SymbolWeight,
                                       tint: UIColor) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let raw = UIImage(systemName: name, withConfiguration: config) else {
            return nil
        }
        // Convert template to a tinted bitmap so the colour bakes in
        // (UIImage.draw doesn't honour tint colour for symbols on its
        // own).
        let renderer = UIGraphicsImageRenderer(size: raw.size)
        return renderer.image { _ in
            tint.set()
            raw.withRenderingMode(.alwaysTemplate).draw(at: .zero)
        }
    }

    // MARK: - Social image — drawing helpers

    /// Top-to-bottom soft ivory→champagne gradient + thin gold inner
    /// border so the card looks intentional on white feeds. Takes
    /// CGSize so the same chrome works for both the square (1080²)
    /// Floor Plan image and the taller (1080×1350) Snapshot image.
    private static func drawSocialBackground(ctx: CGContext, size: CGSize) {
        let colors = [socialIvory.cgColor, socialIvoryDeep.cgColor] as CFArray
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: space, colors: colors,
                                         locations: [0, 1]) else {
            ctx.setFillColor(socialIvory.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            return
        }
        ctx.drawLinearGradient(gradient,
                               start: .zero,
                               end: CGPoint(x: 0, y: size.height),
                               options: [])

        let inset: CGFloat = 36
        let borderRect = CGRect(x: inset, y: inset,
                                width: size.width - inset * 2,
                                height: size.height - inset * 2)
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
    private static func drawSocialBranding(ctx: CGContext, size: CGSize, topY: CGFloat,
                                           tagline: String? = nil) -> CGFloat {
        // Stacked layout: bee at top (centered), wordmark beneath it,
        // optional tagline beneath that. Reads more like a poster /
        // stamp than a horizontal lockup, and gives the bee enough
        // weight to feel like the hero of the card.
        let cx = size.width / 2
        let beeSide: CGFloat = 96
        let wordmarkW: CGFloat = 240
        let wordmarkH: CGFloat = wordmarkW / 6        // 720x120 native ratio
        let beeToWordmarkGap: CGFloat = 14

        // Halo behind bee
        let haloR: CGFloat = beeSide / 2 + 10
        let haloRect = CGRect(x: cx - haloR,
                              y: topY + beeSide / 2 - haloR,
                              width: haloR * 2, height: haloR * 2)
        ctx.setFillColor(socialChampagne.withAlphaComponent(0.55).cgColor)
        ctx.fillEllipse(in: haloRect)

        // Bee logo — centered horizontally
        if let bee = UIImage(named: "SeatbeeLogo") {
            bee.draw(in: CGRect(x: cx - beeSide / 2, y: topY,
                                width: beeSide, height: beeSide))
        }
        // Wordmark — centered horizontally, directly below bee
        let wordmarkY = topY + beeSide + beeToWordmarkGap
        if let mark = UIImage(named: "SeatbeeWordmark") {
            mark.draw(in: CGRect(x: cx - wordmarkW / 2, y: wordmarkY,
                                 width: wordmarkW, height: wordmarkH))
        }

        let wordmarkBottom = wordmarkY + wordmarkH

        // Optional tagline. The Snapshot passes "SEATING SNAPSHOT";
        // the Floor Plan image leaves it nil because the floor plan
        // diagram already labels itself.
        guard let tagline, !tagline.isEmpty else {
            return wordmarkBottom
        }
        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: socialGoldDk,
            .kern: 4,
        ]
        let tag = NSString(string: tagline)
        let tSize = tag.size(withAttributes: tagAttrs)
        tag.draw(at: CGPoint(x: cx - tSize.width / 2, y: wordmarkBottom + 14),
                 withAttributes: tagAttrs)

        return wordmarkBottom + 14 + tSize.height
    }

    /// Big event title + decorative gold bar + date · venue subtitle.
    /// Title auto-shrinks to fit the canvas width so long names don't
    /// bleed past the inner border. Returns the bottom Y of the block.
    private static func drawSocialEventBlock(ctx: CGContext, plan: SeatingPlan, size: CGSize, topY: CGFloat) -> CGFloat {
        let cx = size.width / 2
        let maxWidth = size.width - 160
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
    /// in big gold and the labels in muted caps. Adds a small muted
    /// sub-line under TABLES when the plan has a mixed table-shape
    /// layout ("8 round · 6 rect"). Pure typography, no boxes —
    /// keeps the card from feeling card-heavy.
    private static func drawSocialHeadlineStats(ctx: CGContext, metrics: SocialMetrics, size: CGSize, topY: CGFloat) -> CGFloat {
        let cx = size.width / 2

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

        // Table-shape mix sub-line — only when the plan actually has
        // multiple table shapes. Stays muted so it doesn't compete
        // with the headline numbers.
        var bottom = topY + gNumSize.height + 4 + gLabSize.height
        if let mix = formattedTableShapeMix(from: metrics.tableTypeCounts) {
            let mixAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: socialWarm,
                .kern: 0.5,
            ]
            let mixStr = NSString(string: mix)
            let mixSize = mixStr.size(withAttributes: mixAttrs)
            mixStr.draw(at: CGPoint(x: tCenterX - mixSize.width / 2,
                                     y: bottom + 4),
                        withAttributes: mixAttrs)
            bottom += 4 + mixSize.height
        }
        return bottom
    }

    /// Returns "8 round · 6 rect" style copy when the plan has more
    /// than one shape; nil for uniform layouts so we don't clutter
    /// the headline. Sweetheart + head are paired with rect because
    /// they share the rectangular silhouette.
    private static func formattedTableShapeMix(from counts: [SeatTable.TableType: Int]) -> String? {
        guard !counts.isEmpty else { return nil }
        // Group sweetheart + head under "rect" for the social card —
        // visually they're all rectangular silhouettes; splitting
        // hairs in a 1-line subtitle isn't worth the noise.
        let round = counts[.round] ?? 0
        let oval = counts[.oval] ?? 0
        let rect = (counts[.rect] ?? 0) + (counts[.head] ?? 0) + (counts[.sweetheart] ?? 0)
        let parts: [(String, Int)] = [
            ("round", round),
            ("oval", oval),
            ("rect", rect),
        ].filter { $0.1 > 0 }
        // Single shape — uniform layout, no sub-line needed.
        guard parts.count > 1 else { return nil }
        return parts
            .map { "\($0.1) \($0.0)" }
            .joined(separator: " · ")
    }

    /// Top-5 categories as horizontal bars. Each row: dot + name on the
    /// left, fill bar in category colour, count on the right. Bars are
    /// proportional to the largest category. Bounded by `maxHeight`.
    /// Returns the bottom Y so the next section can stack.
    private static func drawSocialCategoryChart(ctx: CGContext, metrics: SocialMetrics,
                                                size: CGSize, topY: CGFloat,
                                                maxHeight: CGFloat,
                                                rowHeight: CGFloat = 36) -> CGFloat {
        let outerInset: CGFloat = 90
        let chartLeft = outerInset
        let chartRight = size.width - outerInset
        let chartWidth = chartRight - chartLeft

        // Section title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: socialWarm,
            .kern: 2.5,
        ]
        let title = NSString(string: "BY CATEGORY")
        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(at: CGPoint(x: size.width / 2 - titleSize.width / 2, y: topY),
                   withAttributes: titleAttrs)

        // Cap rows so we never blow past maxHeight. rowH adapts upward
        // when the surrounding layout has slack — caller computes it.
        let rowH: CGFloat = rowHeight
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

        // Bar height grows gently with row height so the chart still
        // looks like a chart at larger row sizes.
        let barH: CGFloat = min(20, max(12, rowH * 0.28))

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
                                             size: CGSize, topY: CGFloat, bottomY: CGFloat,
                                             rowHeight: CGFloat = 56) {
        let outerInset: CGFloat = 90
        let leftX = outerInset
        let rightX = size.width - outerInset

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
        if metrics.keepApartPeopleCount > 0 {
            candidates.append(("\(metrics.keepApartPeopleCount) carefully spaced",
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
            line.draw(at: CGPoint(x: size.width / 2 - s.width / 2, y: topY),
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
        title.draw(at: CGPoint(x: size.width / 2 - titleSize.width / 2, y: topY),
                   withAttributes: titleAttrs)

        let headlineAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: socialCharcoal,
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: socialWarm,
        ]

        let rowH: CGFloat = rowHeight
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

    private static func drawSocialFooter(ctx: CGContext, size: CGSize) {
        let cx = size.width / 2
        let y: CGFloat = size.height - 110
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
