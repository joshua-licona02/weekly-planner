import UIKit

/// Draws the printed planner page (header, day rows, light writing lines, dark borders, events)
/// in logical 1000 x 1400 page coordinates. The PencilKit canvas sits on top of it.
final class PaperView: UIView {
    var week: Date = Week.start(of: Date()) { didSet { setNeedsDisplay() } }
    var theme: PaperTheme = PaperTheme.all[0] { didSet { setNeedsDisplay() } }
    var events: [PlannerEvent] = [] { didSet { setNeedsDisplay() } }
    var categories: [EventCategory] = EventCategory.defaults { didSet { setNeedsDisplay() } }
    /// An event being dragged (replaces the saved one with the same id, or is added).
    var preview: PlannerEvent? { didSet { setNeedsDisplay() } }
    var showGrips = false { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var shownEvents: [PlannerEvent] {
        guard let p = preview else { return events }
        var list = events
        if let i = list.firstIndex(where: { $0.id == p.id }) { list[i] = p } else { list.append(p) }
        return list
    }

    private func color(_ cat: String) -> UIColor {
        categories.first { $0.id == cat }?.uiColor ?? UIColor(hex: 0x9ca3af)
    }
    private func catName(_ cat: String) -> String {
        categories.first { $0.id == cat }?.name ?? "Other"
    }

    private func text(_ s: String, _ p: CGPoint, _ font: UIFont, _ color: UIColor, alignRight: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        var origin = p
        if alignRight { origin.x -= (s as NSString).size(withAttributes: attrs).width }
        (s as NSString).draw(at: origin, withAttributes: attrs)
    }

    private func text(_ s: String, in rect: CGRect, _ font: UIFont, _ color: UIColor, alignRight: Bool = false) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        para.alignment = alignRight ? .right : .left
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        (s as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
    }

    private func line(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint) {
        ctx.move(to: a)
        ctx.addLine(to: b)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let t = theme
        let cal = Week.calendar
        let today = cal.startOfDay(for: Date())

        t.paper.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: Page.width, height: Page.height))

        // header
        text(Week.title(week), CGPoint(x: Page.gx, y: 22), t.font(44, bold: true), t.ink)
        text(Week.range(week), CGPoint(x: Page.width - Page.gx, y: 38), t.font(24), t.muted, alignRight: true)

        let onAccent: UIColor = t.dark ? UIColor(hex: 0x0b0c0e) : .white

        for i in 0..<7 {
            let y = Page.rowY(i)
            let day = Week.day(i, of: week)
            let isToday = cal.isDate(day, inSameDayAs: today)
            let weekday = cal.component(.weekday, from: day)

            (isToday ? t.accent : t.header).setFill()
            ctx.fill(CGRect(x: Page.gx, y: y, width: Page.lab, height: Page.dayH))
            if weekday == 1 || weekday == 7 {
                (t.dark ? UIColor.white : UIColor.black).withAlphaComponent(0.03).setFill()
                ctx.fill(CGRect(x: EventLayout.writeX, y: y, width: Page.right - EventLayout.writeX, height: Page.dayH))
            }
            let labelColor = isToday ? onAccent : t.ink
            text(Week.weekday(day).uppercased(), CGPoint(x: Page.gx + 14, y: y + 12), t.font(17, bold: true), labelColor)
            text("\(cal.component(.day, from: day))", CGPoint(x: Page.gx + 12, y: y + 34), t.font(52), labelColor)
            if i == 0 || cal.component(.day, from: day) == 1 {
                text(Week.monthShort(day).uppercased(), CGPoint(x: Page.gx + 14, y: y + 104), t.font(15, bold: true), labelColor.withAlphaComponent(0.75))
            }

            ctx.setStrokeColor(t.line.cgColor)
            ctx.setLineWidth(1.4)
            for l in 1..<Page.lines {
                let ly = y + CGFloat(l) * Page.lineH
                line(ctx, CGPoint(x: Page.gx + Page.lab, y: ly), CGPoint(x: Page.right, y: ly))
            }
            line(ctx, CGPoint(x: EventLayout.writeX - 3, y: y), CGPoint(x: EventLayout.writeX - 3, y: y + Page.dayH))
            ctx.strokePath()
        }

        // notes box
        let ny = Page.rowY(7)
        t.header.setFill()
        ctx.fill(CGRect(x: Page.gx, y: ny, width: Page.gw, height: 30))
        text("NOTES", CGPoint(x: Page.gx + 14, y: ny + 6), t.font(16, bold: true), t.ink)
        ctx.setStrokeColor(t.line.cgColor)
        ctx.setLineWidth(1.4)
        var ly = ny + 30 + Page.lineH
        while ly < ny + Page.notesH {
            line(ctx, CGPoint(x: Page.gx, y: ly), CGPoint(x: Page.right, y: ly))
            ly += Page.lineH
        }
        ctx.strokePath()

        drawEvents(ctx)

        // dark borders
        ctx.setStrokeColor(t.border.cgColor)
        ctx.setLineWidth(2)
        for i in 1...7 { line(ctx, CGPoint(x: Page.gx, y: Page.rowY(i)), CGPoint(x: Page.right, y: Page.rowY(i))) }
        line(ctx, CGPoint(x: Page.gx, y: ny + 30), CGPoint(x: Page.right, y: ny + 30))
        line(ctx, CGPoint(x: Page.gx + Page.lab, y: Page.gy), CGPoint(x: Page.gx + Page.lab, y: ny))
        ctx.strokePath()
        ctx.setLineWidth(4)
        ctx.stroke(CGRect(x: Page.gx, y: Page.gy, width: Page.gw, height: 7 * Page.dayH + Page.notesH))
    }

    private func drawEvents(_ ctx: CGContext) {
        let t = theme
        for g in EventLayout.geometry(week: week, events: shownEvents) {
            let col = color(g.event.cat)
            for (i, b) in g.bands.enumerated() {
                let first = i == 0 && g.startsHere
                col.withAlphaComponent(first ? (t.dark ? 0.32 : 0.22) : (t.dark ? 0.16 : 0.10)).setFill()
                ctx.fill(b)
                guard first else { continue }
                col.setFill()
                ctx.fill(CGRect(x: b.minX, y: b.minY, width: 4, height: b.height))
                if g.event.title.isEmpty {
                    text(catName(g.event.cat), in: CGRect(x: b.minX + 14, y: b.minY + 6, width: b.width - 24, height: 20),
                         UIFont.italicSystemFont(ofSize: 14), t.ink.withAlphaComponent(0.55), alignRight: true)
                } else {
                    text(g.event.title, in: CGRect(x: b.minX + 14, y: b.minY + 6, width: b.width - 28, height: 28),
                         t.font(21, bold: true), t.ink)
                }
            }

            // bar in the lane column (shows how many days it spans)
            col.setFill()
            UIBezierPath(roundedRect: g.lane, cornerRadius: 4).fill()
            if !g.endsHere {          // continues onto the next page
                let p = UIBezierPath()
                p.move(to: CGPoint(x: g.lane.minX - 2, y: g.lane.maxY))
                p.addLine(to: CGPoint(x: g.lane.maxX + 2, y: g.lane.maxY))
                p.addLine(to: CGPoint(x: g.lane.midX, y: g.lane.maxY + 9))
                p.close(); p.fill()
            }
            if !g.startsHere {        // started on an earlier page
                let p = UIBezierPath()
                p.move(to: CGPoint(x: g.lane.minX - 2, y: g.lane.minY))
                p.addLine(to: CGPoint(x: g.lane.maxX + 2, y: g.lane.minY))
                p.addLine(to: CGPoint(x: g.lane.midX, y: g.lane.minY - 9))
                p.close(); p.fill()
            }
            if !g.event.title.isEmpty && g.lane.height >= 80 {
                ctx.saveGState()
                ctx.translateBy(x: g.lane.midX, y: g.lane.minY + 8)
                ctx.rotate(by: .pi / 2)
                text(g.event.title, in: CGRect(x: 0, y: -6, width: g.lane.height - 16, height: 12),
                     UIFont.boldSystemFont(ofSize: 10), .white)
                ctx.restoreGState()
            }
            if showGrips, let grip = g.grip {
                let r = CGRect(x: grip.x - 9, y: grip.y - 9, width: 18, height: 18)
                t.paper.setFill()
                ctx.fillEllipse(in: r)
                ctx.setStrokeColor(col.cgColor)
                ctx.setLineWidth(3)
                ctx.strokeEllipse(in: r)
            }
        }
    }
}
