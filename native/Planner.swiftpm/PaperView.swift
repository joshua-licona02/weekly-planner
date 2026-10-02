import UIKit

/// Draws the printed planner page (header, day rows, light writing lines, dark borders) in
/// logical 1000 x 1400 page coordinates. The PencilKit canvas sits on top of it.
final class PaperView: UIView {
    var week: Date = Week.start(of: Date()) { didSet { setNeedsDisplay() } }
    var theme: PaperTheme = PaperTheme.all[0] { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func text(_ s: String, _ p: CGPoint, _ font: UIFont, _ color: UIColor, alignRight: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        var origin = p
        if alignRight { origin.x -= (s as NSString).size(withAttributes: attrs).width }
        (s as NSString).draw(at: origin, withAttributes: attrs)
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

            // label column
            (isToday ? t.accent : t.header).setFill()
            ctx.fill(CGRect(x: Page.gx, y: y, width: Page.lab, height: Page.dayH))
            if weekday == 1 || weekday == 7 {
                (t.dark ? UIColor.white : UIColor.black).withAlphaComponent(0.03).setFill()
                ctx.fill(CGRect(x: Page.gx + Page.lab, y: y, width: Page.gw - Page.lab, height: Page.dayH))
            }
            let labelColor = isToday ? onAccent : t.ink
            text(Week.weekday(day).uppercased(), CGPoint(x: Page.gx + 14, y: y + 12), t.font(17, bold: true), labelColor)
            text("\(cal.component(.day, from: day))", CGPoint(x: Page.gx + 12, y: y + 34), t.font(52), labelColor)
            if i == 0 || cal.component(.day, from: day) == 1 {
                text(Week.monthShort(day).uppercased(), CGPoint(x: Page.gx + 14, y: y + 104), t.font(15, bold: true), labelColor.withAlphaComponent(0.75))
            }

            // light writing lines
            ctx.setStrokeColor(t.line.cgColor)
            ctx.setLineWidth(1.4)
            for l in 1..<Page.lines {
                let ly = y + CGFloat(l) * Page.lineH
                line(ctx, CGPoint(x: Page.gx + Page.lab, y: ly), CGPoint(x: Page.right, y: ly))
            }
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
}
