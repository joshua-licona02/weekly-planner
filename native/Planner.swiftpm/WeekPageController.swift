import UIKit
import PencilKit

/// One planner page: printed paper underneath, Apple's PencilKit canvas on top, and an
/// events layer that takes over touches in Events mode.
final class WeekPageController: UIViewController, PKCanvasViewDelegate, PKToolPickerObserver {
    let week: Date
    private weak var model: PlannerModel?
    private let toolPicker: PKToolPicker

    private var layout: WeekLayout
    private let paper = PaperView(frame: CGRect(x: 0, y: 0, width: Page.width, height: WeekLayout.standard.height))
    private let overlay = UIView(frame: CGRect(x: 0, y: 0, width: Page.width, height: WeekLayout.standard.height))
    let canvas = PKCanvasView()
    private var saveWork: DispatchWorkItem?
    private var fitScale: CGFloat = 0
    private var toolsVisible = false
    private var dirty = false          // only ever write pages you actually changed
    private var obscuredBottom: CGFloat = 0   // height hidden behind Apple's docked tool palette

    /// Called with `true` while the page is zoomed in (so finger page-turns are paused).
    var onZoomChanged: ((Bool) -> Void)?

    private enum Drag {
        case move(PlannerEvent, grabDay: Int, grabLine: Int)
        case resize(PlannerEvent)
        case create(row: Int, line0: Int)
    }
    private var drag: Drag?

    init(week: Date, model: PlannerModel, toolPicker: PKToolPicker) {
        self.week = week
        self.model = model
        self.toolPicker = toolPicker
        self.layout = model.layout(for: week)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true

        paper.week = week
        paper.layout = layout
        paper.frame.size.height = layout.height
        overlay.frame.size.height = layout.height
        view.addSubview(paper)

        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly            // Pencil writes; fingers turn pages / zoom
        canvas.drawing = InkStore.shared.load(week)   // load before the delegate is attached
        canvas.delegate = self
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.bouncesZoom = true
        canvas.isScrollEnabled = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        view.addSubview(canvas)

        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        view.addSubview(overlay)
        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        overlay.addGestureRecognizer(pan)

        // In Write mode: press and hold a line with your finger to type an event there.
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        hold.minimumPressDuration = 0.45
        view.addGestureRecognizer(hold)

        // In Write mode: tap a day's + / − with your finger to add or remove a writing line.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleFingerTap(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addGestureRecognizer(tap)

        toolPicker.addObserver(canvas)
        toolPicker.addObserver(self)
        if let m = model {
            applyTheme(m.theme)
            refreshEvents()
            setMode(m.mode)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(saveNow),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(saveNow),
                                               name: .plannerSaveAll, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(inkChangedElsewhere(_:)),
                                               name: .plannerInkChangedElsewhere, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds.size
        guard b.width > 0, b.height > 0 else { return }
        let fit = min(b.width / Page.width, max(b.height - obscuredBottom, 100) / layout.height)
        if abs(fit - fitScale) > 0.0001 {
            fitScale = fit
            canvas.minimumZoomScale = fit
            canvas.maximumZoomScale = fit * 4
            canvas.zoomScale = fit
            canvas.contentSize = CGSize(width: Page.width * fit, height: layout.height * fit)
        }
        centerContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvas.becomeFirstResponder()
        toolPicker.setVisible(toolsVisible, forFirstResponder: canvas)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveNow()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: theme, events, mode, tools

    func applyTheme(_ t: PaperTheme) {
        paper.theme = t
        // In the dark theme PencilKit flips dark ink to light automatically, like Notes in dark mode.
        canvas.overrideUserInterfaceStyle = t.dark ? .dark : .light
    }

    func refreshEvents() {
        guard let m = model else { return }
        paper.categories = m.categories
        paper.events = m.events
        paper.holidays = (0..<7).map { m.holidays(on: Week.day($0, of: week)) }
    }

    /// A day on this page gained or lost a line: resize the page and fit it to the screen again.
    func refreshLayout() {
        guard let m = model else { return }
        let l = m.layout(for: week)
        guard l != layout else { return }
        layout = l
        paper.layout = l
        for v in [paper, overlay] { v.bounds = CGRect(x: 0, y: 0, width: Page.width, height: l.height) }
        fitScale = 0
        view.setNeedsLayout()
    }

    func setMode(_ mode: InputMode) {
        let events = mode == .events
        overlay.isUserInteractionEnabled = events
        canvas.isUserInteractionEnabled = !events
        paper.showGrips = events
        if events { canvas.setZoomScale(canvas.minimumZoomScale, animated: true) }
    }

    func setToolsVisible(_ visible: Bool) {
        toolsVisible = visible
        toolPicker.setVisible(visible, forFirstResponder: canvas)
        if visible { canvas.becomeFirstResponder() }
    }

    // MARK: Apple's tool palette: keep the whole page visible above it when it's docked

    func toolPickerFramesObscuredDidChange(_ toolPicker: PKToolPicker) {
        let r = toolPicker.frameObscured(in: view)
        let bottom = r.isNull ? 0 : max(0, view.bounds.maxY - r.minY)
        guard abs(bottom - obscuredBottom) > 1 else { return }
        obscuredBottom = bottom
        fitScale = 0                       // re-fit the page to the new space
        view.setNeedsLayout()
    }

    func toolPickerVisibilityDidChange(_ toolPicker: PKToolPicker) {
        toolPickerFramesObscuredDidChange(toolPicker)
    }

    // MARK: zoom + keeping paper/events layer under the ink

    private func centerContent() {
        let z = canvas.zoomScale
        let w = Page.width * z, h = layout.height * z
        let ix = max(0, (canvas.bounds.width - w) / 2)
        let iy = max(0, (canvas.bounds.height - obscuredBottom - h) / 2)
        canvas.contentInset = UIEdgeInsets(top: iy, left: ix, bottom: iy + obscuredBottom, right: ix)
        syncLayers()
    }

    private func syncLayers() {
        let z = canvas.zoomScale
        let center = CGPoint(x: -canvas.contentOffset.x + Page.width * z / 2,
                             y: -canvas.contentOffset.y + layout.height * z / 2)
        for v in [paper, overlay] {
            v.transform = CGAffineTransform(scaleX: z, y: z)
            v.center = center
        }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        canvas.contentSize = CGSize(width: Page.width * canvas.zoomScale, height: layout.height * canvas.zoomScale)
        centerContent()
        let zoomed = canvas.zoomScale > canvas.minimumZoomScale * 1.02
        canvas.isScrollEnabled = zoomed
        onZoomChanged?(zoomed)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        syncLayers()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        paper.contentScaleFactor = max(1, min(UIScreen.main.scale * scale, 4))
        paper.setNeedsDisplay()
    }

    // MARK: events: tap to type, drag to tag / move / stretch

    private struct Slot { let row: Int; let line: Int }

    private func slot(_ p: CGPoint, clamp: Bool) -> Slot? {
        var row = layout.row(at: p.y)
        if !clamp && (row < 0 || row > 6) { return nil }
        row = min(max(row, 0), 6)
        return Slot(row: row, line: line(at: p.y, row: row))
    }

    private func line(at y: CGFloat, row: Int) -> Int {
        min(max(Int(floor((y - layout.rowY(row)) / Page.lineH)), 0), layout.lines[row] - 1)
    }

    private func geometry(_ m: PlannerModel) -> [EventGeo] {
        EventLayout.geometry(week: week, layout: layout, events: m.events)
    }

    /// A finger tap on a day's + or − button.
    private func tapLineButton(at p: CGPoint) -> Bool {
        guard let m = model else { return false }
        for i in 0..<7 {
            let day = Week.day(i, of: week)
            if layout.canAdd(i) && layout.addRect(i).insetBy(dx: -8, dy: -8).contains(p) {
                m.addLine(day)
                return true
            }
            if layout.canRemove(i) && layout.removeRect(i).insetBy(dx: -4, dy: -8).contains(p) {
                m.removeLine(day)
                return true
            }
        }
        return false
    }

    @objc private func handleFingerTap(_ g: UITapGestureRecognizer) {
        guard let m = model, m.mode == .write else { return }     // Events mode: handleTap does it
        _ = tapLineButton(at: g.location(in: overlay))
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard let m = model else { return }
        let p = g.location(in: overlay)
        if tapLineButton(at: p) { return }
        if let hit = EventLayout.hit(p, in: geometry(m)) {
            m.beginEdit(hit.geo.event)
            return
        }
        guard p.x >= EventLayout.writeX, let s = slot(p, clamp: false) else { return }
        m.beginNew(date: Week.day(s.row, of: week), line: s.line)
    }

    @objc private func handleHold(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let m = model, m.mode == .write else { return }
        let p = g.location(in: overlay)
        if let hit = EventLayout.hit(p, in: geometry(m)) {
            m.beginEdit(hit.geo.event)
            return
        }
        guard let s = slot(p, clamp: false) else { return }
        m.beginNew(date: Week.day(s.row, of: week), line: s.line)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let m = model else { return }
        let p = g.location(in: overlay)
        switch g.state {
        case .began:
            if let hit = EventLayout.hit(p, in: geometry(m)) {
                if hit.grip {
                    drag = .resize(hit.geo.event)
                } else if let s = slot(p, clamp: true) {
                    let e = hit.geo.event
                    drag = .move(e, grabDay: Week.days(from: e.start, to: Week.day(s.row, of: week)), grabLine: s.line - e.line)
                }
            } else if p.x >= EventLayout.writeX, let s = slot(p, clamp: false) {
                drag = .create(row: s.row, line0: s.line)
            } else {
                drag = nil
            }
        case .changed:
            guard let d = drag, let s = slot(p, clamp: true) else { return }
            switch d {
            case .move(let e, let grabDay, let grabLine):
                var n = e
                n.date = Week.key(Week.day(s.row - grabDay, of: week))
                n.line = max(0, min(s.line - grabLine, layout.lines[s.row] - n.lines))
                paper.preview = n
            case .resize(let e):
                var n = e
                n.days = min(max(Week.days(from: e.start, to: Week.day(s.row, of: week)) + 1, 1), 60)
                paper.preview = n
            case .create(let row, let line0):
                let l1 = line(at: p.y, row: row)
                let a = min(line0, l1), b = max(line0, l1)
                paper.preview = PlannerEvent(id: "draft", date: Week.key(Week.day(row, of: week)),
                                             line: a, lines: b - a + 1, cat: m.currentCat)
            }
        case .ended:
            if let d = drag, let n = paper.preview {
                switch d {
                case .create:
                    var e = n
                    e.id = UUID().uuidString
                    m.upsert(e)
                case .move(let e, _, _), .resize(let e):
                    if n != e { m.commitDrag(from: e, to: n) }
                }
            }
            paper.preview = nil
            drag = nil
        case .cancelled, .failed:
            paper.preview = nil
            drag = nil
        default:
            break
        }
    }

    // MARK: saving

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        dirty = true
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Month view wrote onto this week: show it.
    @objc private func inkChangedElsewhere(_ n: Notification) {
        guard (n.object as? String) == Week.key(week) else { return }
        saveWork?.cancel()
        canvas.drawing = InkStore.shared.load(week)
        saveWork?.cancel()
        dirty = false
    }

    @objc func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard dirty else { return }
        dirty = false
        InkStore.shared.save(canvas.drawing, week: week)
    }
}
