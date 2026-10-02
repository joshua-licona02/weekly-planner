import UIKit
import SwiftUI
import PencilKit
import Combine

/// The planner as a real book: UIKit's page-curl. One week per page in portrait,
/// a two-page spread in landscape. Fingers curl pages; the Pencil only writes.
final class BookController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let model: PlannerModel
    private let toolPicker = PKToolPicker()
    private var pageVC: UIPageViewController?
    private var spread = false
    private var zoomed = false
    private var bag = Set<AnyCancellable>()

    init(model: PlannerModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        model.commands
            .receive(on: DispatchQueue.main)
            .sink { [weak self] command in self?.handle(command) }
            .store(in: &bag)
        model.$themeID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyTheme() }
            .store(in: &bag)
        model.$events
            .combineLatest(model.$categories)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pages.forEach { $0.refreshEvents() } }
            .store(in: &bag)
        model.$mode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let self = self else { return }
                self.pages.forEach { $0.setMode(mode) }
                self.updatePageTurns()
            }
            .store(in: &bag)
        Publishers.CombineLatest3(model.$screen, model.$mode, model.$showTools)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screen, mode, show in
                let visible = screen == .planner && mode == .write && show
                self?.pages.forEach { $0.setToolsVisible(visible) }
            }
            .store(in: &bag)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.undoManager = view.window?.undoManager
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds.size
        guard b.width > 0, b.height > 0 else { return }
        let wantSpread = b.width > b.height * 1.15
        if pageVC == nil || wantSpread != spread { build(spread: wantSpread) }
    }

    private var pages: [WeekPageController] {
        (pageVC?.viewControllers ?? []).compactMap { $0 as? WeekPageController }
    }

    private var toolsShouldShow: Bool {
        model.screen == .planner && model.mode == .write && model.showTools
    }

    private func makePage(_ week: Date) -> WeekPageController {
        let p = WeekPageController(week: week, model: model, toolPicker: toolPicker)
        p.setToolsVisible(toolsShouldShow)
        p.onZoomChanged = { [weak self] z in
            self?.zoomed = z
            self?.updatePageTurns()
        }
        return p
    }

    private func controllers(for week: Date) -> [UIViewController] {
        spread ? [makePage(week), makePage(Week.adding(1, to: week))] : [makePage(week)]
    }

    private func build(spread newSpread: Bool) {
        NotificationCenter.default.post(name: .plannerSaveAll, object: nil)
        if let old = pageVC {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        spread = newSpread
        zoomed = false
        let spine: UIPageViewController.SpineLocation = newSpread ? .mid : .min
        let p = UIPageViewController(transitionStyle: .pageCurl,
                                     navigationOrientation: .horizontal,
                                     options: [.spineLocation: NSNumber(value: spine.rawValue)])
        p.isDoubleSided = newSpread
        p.dataSource = self
        p.delegate = self
        addChild(p)
        p.view.frame = view.bounds
        p.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        p.view.backgroundColor = .clear
        view.addSubview(p.view)
        p.didMove(toParent: self)
        pageVC = p
        p.setViewControllers(controllers(for: model.weekStart), direction: .forward, animated: false)
        updatePageTurns()
        let shown = newSpread ? 2 : 1
        DispatchQueue.main.async { [weak self] in self?.model.pagesShown = shown }
    }

    /// Page-curl responds to fingers only (never the Pencil); off while zoomed or in Events mode.
    private func updatePageTurns() {
        let enabled = !zoomed && model.mode == .write
        for g in pageVC?.gestureRecognizers ?? [] {
            if g is UITapGestureRecognizer {
                g.isEnabled = false             // no accidental flips from tapping the margin
            } else {
                g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                g.isEnabled = enabled
            }
        }
    }

    private func applyTheme() {
        pages.forEach { $0.applyTheme(model.theme) }
    }

    // MARK: commands from the top bar

    private func handle(_ command: BookCommand) {
        guard let p = pageVC else { return }
        let step = spread ? 2 : 1
        switch command {
        case .next:
            let w = Week.adding(step, to: model.weekStart)
            p.setViewControllers(controllers(for: w), direction: .forward, animated: true)
            model.weekStart = w
        case .previous:
            let w = Week.adding(-step, to: model.weekStart)
            p.setViewControllers(controllers(for: w), direction: .reverse, animated: true)
            model.weekStart = w
        case .go(let date):
            let w = Week.start(of: date)
            let forward = w >= model.weekStart
            p.setViewControllers(controllers(for: w), direction: forward ? .forward : .reverse, animated: model.screen == .planner)
            model.weekStart = w
        case .show(let date):                     // jump without a page-turn (e.g. from Month view)
            let w = Week.start(of: date)
            p.setViewControllers(controllers(for: w), direction: .forward, animated: false)
            model.weekStart = w
        case .undo:
            view.window?.undoManager?.undo()
        case .redo:
            view.window?.undoManager?.redo()
        case .reload:
            build(spread: spread)
        }
        updatePageTurns()
    }

    // MARK: data source / delegate

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? WeekPageController else { return nil }
        return makePage(Week.adding(-1, to: page.week))
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? WeekPageController else { return nil }
        return makePage(Week.adding(1, to: page.week))
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed, let first = pageViewController.viewControllers?.first as? WeekPageController else { return }
        model.weekStart = first.week
    }
}

/// SwiftUI wrapper.
struct BookView: UIViewControllerRepresentable {
    @EnvironmentObject var model: PlannerModel

    func makeUIViewController(context: Context) -> BookController {
        BookController(model: model)
    }

    func updateUIViewController(_ controller: BookController, context: Context) {}
}
