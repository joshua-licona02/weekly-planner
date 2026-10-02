import UIKit
import PencilKit

/// One planner page: printed paper underneath, Apple's PencilKit canvas on top, and an
/// events layer that takes over touches in Events mode.
final class WeekPageController: UIViewController, PKCanvasViewDelegate {
    let week: Date
    private weak var model: PlannerModel?
    private let toolPicker: PKToolPicker

    private let paper = PaperView(frame: CGRect(x: 0, y: 0, width: Page.width, height: Page.height))
    private let overlay = UIView(frame: CGRect(x: 0, y: 0, width: Page.width, height: Page.height))
    let canvas = PKCanvasView()
    private var saveWork: DispatchWorkItem?
    private var fitScale: CGFloat = 0
    private var toolsVisible = false
    private var dirty = false          // only ever write pages you actually changed

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
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true

        paper.week = week
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

        toolPicker.addObserver(canvas)
        if let m = model {
            applyTheme(m.theme)
            refreshEvents()
            setMode(m.mode)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(saveNow),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(saveNow),
                                               name: .plannerSaveAll, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds.size
        guard b.width > 0, b.height > 0 else { return }
        let fit = min(b.width / Page.width, b.height / Page.height)
        if abs(fit - fitScale) > 0.0001 {
            fitScale = fit
            canvas.minimumZoomScale = fit
            canvas.maximumZoomScale = fit * 4
            canvas.zoomScale = fit
            canvas.contentSize = CGSize(width: Page.width * fit, height: Page.height * fit)
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

    // MARK: zoom + keeping paper/events layer under the ink

    private func centerContent() {
        let z = canvas.zoomScale
        let w = Page.width * z, h = Page.height * z
        let ix = max(0, (canvas.bounds.width - w) / 2)
        let iy = max(0, (canvas.bounds.height - h) / 2)
        canvas.contentInset = UIEdgeInsets(top: iy, left: ix, bottom: iy, right: ix)
        syncLayers()
    }

    private func syncLayers() {
        let z = canvas.zoomScale
        let center = CGPoint(x: -canvas.contentOffset.x + Page.width * z / 2,
                             y: -canvas.contentOffset.y + Page.height * z / 2)
        for v in [paper, overlay] {
            v.transform = CGAffineTransform(scaleX: z, y: z)
            v.center = center
        }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        canvas.contentSize = CGSize(width: Page.width * canvas.zoomScale, height: Page.height * canvas.zoomScale)
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
        var row = Int(floor((p.y - Page.gy) / Page.dayH))
        if !clamp && (row < 0 || row > 6) { return nil }
        row = min(max(row, 0), 6)
        let line = min(max(Int(floor((p.y - Page.rowY(row)) / Page.lineH)), 0), Page.lines - 1)
        return Slot(row: row, line: line)
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard let m = model else { return }
        let p = g.location(in: overlay)
        if let hit = EventLayout.hit(p, in: EventLayout.geometry(week: week, events: m.events)) {
            m.beginEdit(hit.geo.event)
            return
        }
        guard p.x >= EventLayout.writeX, let s = slot(p, clamp: false) else { return }
        m.beginNew(date: Week.day(s.row, of: week), line: s.line)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let m = model else { return }
        let p = g.location(in: overlay)
        switch g.state {
        case .began:
            if let hit = EventLayout.hit(p, in: EventLayout.geometry(week: week, events: m.events)) {
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
                n.line = min(max(s.line - grabLine, 0), Page.lines - n.lines)
                paper.preview = n
            case .resize(let e):
                var n = e
                n.days = min(max(Week.days(from: e.start, to: Week.day(s.row, of: week)) + 1, 1), 60)
                paper.preview = n
            case .create(let row, let line0):
                let l1 = min(max(Int(floor((p.y - Page.rowY(row)) / Page.lineH)), 0), Page.lines - 1)
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
                    if n != e { m.upsert(n) }
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

    @objc func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard dirty else { return }
        dirty = false
        InkStore.shared.save(canvas.drawing, week: week)
    }
}
