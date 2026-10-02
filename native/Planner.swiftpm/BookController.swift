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
            .sink { [weak self] in self?.handle($0) }
            .store(in: &bag)
        model.$themeID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyTheme() }
            .store(in: &bag)
        model.$showTools
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in self?.pages.forEach { $0.setToolsVisible(visible) } }
            .store(in: &bag)
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

    private func makePage(_ week: Date) -> WeekPageController {
        let p = WeekPageController(week: week, theme: model.theme, toolPicker: toolPicker, showTools: model.showTools)
        p.onZoomChanged = { [weak self] zoomed in self?.setPageTurnsEnabled(!zoomed) }
        return p
    }

    private func controllers(for week: Date) -> [UIViewController] {
        spread ? [makePage(week), makePage(Week.adding(1, to: week))] : [makePage(week)]
    }

    private func build(spread newSpread: Bool) {
        pages.forEach { $0.saveNow() }
        if let old = pageVC {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        spread = newSpread
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
        configurePageGestures()
        let shown = newSpread ? 2 : 1
        DispatchQueue.main.async { [weak self] in self?.model.pagesShown = shown }
    }

    /// Page-curl responds to fingers only (never the Pencil), and the tap-in-the-margin flip is off.
    private func configurePageGestures() {
        for g in pageVC?.gestureRecognizers ?? [] {
            if g is UITapGestureRecognizer {
                g.isEnabled = false
            } else {
                g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            }
        }
    }

    private func setPageTurnsEnabled(_ enabled: Bool) {
        for g in pageVC?.gestureRecognizers ?? [] where !(g is UITapGestureRecognizer) {
            g.isEnabled = enabled
        }
    }

    private func applyTheme() {
        view.backgroundColor = .clear
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
            p.setViewControllers(controllers(for: w), direction: forward ? .forward : .reverse, animated: true)
            model.weekStart = w
        case .undo:
            view.window?.undoManager?.undo()
        case .redo:
            view.window?.undoManager?.redo()
        }
        configurePageGestures()
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
