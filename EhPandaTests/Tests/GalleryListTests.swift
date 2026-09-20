//
//  GalleryListTests.swift
//  EhPandaTests
//

import UIKit
import SwiftUI
import XCTest
import ComposableArchitecture
@testable import EhPanda

@MainActor
final class GalleryListLayoutTests: XCTestCase {
    func testWaterfallGeometryHasNoOverlapAndAppendKeepsExistingFrames() {
        let heights = (0..<1200).map { CGFloat(160 + ($0 * 37) % 240) }
        for width: CGFloat in [320, 390, 744, 1024, 1366] {
            let first = GalleryListGeometry.waterfall(viewport: width, heights: Array(heights.prefix(40)))
            let full = GalleryListGeometry.waterfall(viewport: width, heights: heights, footerHeight: 56)
            XCTAssertEqual(first.frames, Array(full.frames.prefix(40)))
            for (index, frame) in full.frames.enumerated() {
                XCTAssertGreaterThan(frame.width, 0)
                XCTAssertGreaterThan(frame.height, 0)
                XCTAssertGreaterThanOrEqual(frame.minX, 16)
                XCTAssertLessThanOrEqual(frame.maxX, width - 16 + 0.01)
                for other in full.frames.dropFirst(index + 1).prefix(12) {
                    XCTAssertFalse(frame.intersects(other))
                }
            }
            XCTAssertEqual(full.frames.last?.width, width - 32)
            XCTAssertGreaterThan(full.contentHeight, full.frames.last?.maxY ?? 0)
        }
    }

    func testWaterfallMirrorsColumnsForRightToLeft() {
        let left = GalleryListGeometry.waterfall(viewport: 744, heights: [120, 200, 160, 90])
        let right = GalleryListGeometry.waterfall(viewport: 744, heights: [120, 200, 160, 90], rightToLeft: true)
        for (a, b) in zip(left.frames, right.frames) {
            XCTAssertEqual(a.minY, b.minY)
            XCTAssertEqual(a.width, b.width)
            XCTAssertEqual(a.minX, 744 - b.maxX, accuracy: 0.01)
        }
    }

    func testSpatialQueriesAndHeightOnlyResizeDoNotReflow() {
        let layout = GalleryMasonryLayout()
        let geometry = GalleryListGeometry.waterfall(
            viewport: 390, heights: (0..<500).map { CGFloat(100 + $0 % 180) }, footerHeight: 56
        )
        layout.setGeometry(geometry)
        for y in stride(from: CGFloat(-200), through: geometry.contentHeight, by: 211) {
            let rect = CGRect(x: 0, y: y, width: 390, height: 850)
            let expected = geometry.frames.enumerated().compactMap { $0.element.intersects(rect) ? $0.offset : nil }
            XCTAssertEqual(layout.layoutAttributesForElements(in: rect)?.map { $0.indexPath.item }, expected)
        }
        XCTAssertFalse(layout.shouldInvalidateLayout(forBoundsChange: CGRect(x: 0, y: 800, width: 390, height: 350)))
        XCTAssertEqual(layout.geometry, geometry)
    }

    func testCardMetricsUseTextAndDynamicTypeWithoutAsyncMeasurement() {
        var gallery = Gallery.preview
        gallery.title = String(repeating: "A long localized gallery title ", count: 10)
        for mode in [ListDisplayMode.detail, .waterfall] {
            var setting = Setting()
            setting.listDisplayMode = mode
            let normal = GalleryCardLayout(gallery: gallery, setting: setting, presentation: nil,
                                           width: 320, contentSize: .large, translate: nil)
            let large = GalleryCardLayout(gallery: gallery, setting: setting, presentation: nil,
                                          width: 320, contentSize: .accessibilityExtraExtraExtraLarge, translate: nil)
            XCTAssertGreaterThan(large.height, normal.height)
            XCTAssertGreaterThan(large.title.height, normal.title.height)
            for frame in [large.cover, large.title, large.metadata, large.rating] {
                XCTAssertLessThanOrEqual(frame.maxY, large.height)
                XCTAssertLessThanOrEqual(frame.maxX, large.width)
            }
        }
    }

    func testProgressValuesDoNotChangeCardHeight() {
        let status: (Double, String?) -> GalleryListStatus = { value, message in
            .init(text: "Downloading", detailText: "10 / 30", message: message,
                  systemImage: "arrow.down.circle", tone: .accent, progress: value)
        }
        for mode in [ListDisplayMode.detail, .waterfall] {
            var setting = Setting()
            setting.listDisplayMode = mode
            let before = GalleryCardLayout(
                gallery: .preview, setting: setting,
                presentation: .init(coverURL: nil, status: status(0, nil)),
                width: 260, contentSize: .large, translate: nil
            )
            let after = GalleryCardLayout(
                gallery: .preview, setting: setting,
                presentation: .init(coverURL: nil, status: status(0.8, "Retrying a page")),
                width: 260, contentSize: .large, translate: nil
            )
            XCTAssertEqual(before.height, after.height)
        }
    }

    func testToplistsWaterfallSearchAtTop() async throws { try await checkSearch(.waterfall, route: .toplists, offset: 0) }
    func testToplistsWaterfallSearchScrolled() async throws { try await checkSearch(.waterfall, route: .toplists, offset: 1700) }
    func testToplistsDetailSearchAtTop() async throws { try await checkSearch(.detail, route: .toplists, offset: 0) }
    func testToplistsDetailSearchScrolled() async throws { try await checkSearch(.detail, route: .toplists, offset: 1700) }
    func testShowAllWaterfallSearch() async throws { try await checkSearch(.waterfall, route: .frontpage, offset: 900) }
    func testShowAllDetailSearch() async throws { try await checkSearch(.detail, route: .frontpage, offset: 900) }
    func testPopularWaterfallSearch() async throws { try await checkSearch(.waterfall, route: .popular, offset: 0) }
    func testPopularDetailSearch() async throws { try await checkSearch(.detail, route: .popular, offset: 0) }

    private enum Route { case toplists, frontpage, popular }

    private func checkSearch(_ mode: ListDisplayMode, route: Route, offset: CGFloat) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene)
        let window = try XCTUnwrap(scene.keyWindow)
        let previous = window.rootViewController
        var setting = Setting()
        setting.listDisplayMode = mode
        setting.tabBarItems = [.popular, .search]
        let galleries = try makeListTestGalleries(count: 100)
        var state = AppReducer.State()
        state.settingState.setting = setting
        state.homeState.popularGalleries = Array(galleries.prefix(10))
        state.homeState.frontpageGalleries = Array(galleries.prefix(20))
        state.homeState.toplistsGalleries = [11: Array(galleries.prefix(20))]
        state.homeState.toplistsState.rawGalleries[.yesterday] = galleries
        state.homeState.frontpageState.galleries = galleries
        state.homeState.popularState.galleries = galleries
        let store = StoreOf<AppReducer>(initialState: state) {
            Scope(state: \AppReducer.State.homeState, action: \Case<AppReducer.Action>.home) {
                Scope(state: \HomeReducer.State.toplistsState, action: \Case<HomeReducer.Action>.toplists) {
                    BindingReducer<ToplistsReducer.State, ToplistsReducer.Action, ToplistsReducer.Action>()
                }
                Scope(state: \HomeReducer.State.frontpageState, action: \Case<HomeReducer.Action>.frontpage) {
                    BindingReducer<FrontpageReducer.State, FrontpageReducer.Action, FrontpageReducer.Action>()
                }
                Scope(state: \HomeReducer.State.popularState, action: \Case<HomeReducer.Action>.popular) {
                    BindingReducer<PopularReducer.State, PopularReducer.Action, PopularReducer.Action>()
                }
            }
            Reduce<AppReducer.State, AppReducer.Action> { state, action in
                if case .home(.setNavigation(let route)) = action { state.homeState.route = route }
                if case .tabBar(.setTabBarItemType(let tab)) = action { state.tabBarState.tabBarItemType = tab }
                return .none
            }
        }
        let migration = Store(initialState: MigrationReducer.State()) {
            Reduce<MigrationReducer.State, MigrationReducer.Action> { _, _ in .none }
        }
        let host = UIHostingController(rootView: GeometryReader { proxy in
            ZStack {
                TabBarView(store: store)
                MigrationView(store: migration).opacity(0)
            }
            .environment(\.windowSize, proxy.size)
            .navigationViewStyle(.stack)
        })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.endEditing(true)
            window.rootViewController = previous
        }
        try await Task.sleep(for: .milliseconds(700))
        switch route {
        case .toplists: store.send(.home(.setNavigation(.section(.toplists))), animation: .default)
        case .frontpage: store.send(.home(.setNavigation(.section(.frontpage))), animation: .default)
        case .popular: store.send(.tabBar(.setTabBarItemType(.popular)))
        }
        try await Task.sleep(for: .milliseconds(700))
        let controller = try XCTUnwrap(findController(GalleryListController.self, in: host))
        let scroll = try XCTUnwrap(controller.scrollView)
        XCTAssertEqual(scroll.contentInsetAdjustmentBehavior, .never)
        XCTAssertEqual(scroll.adjustedContentInset, .zero)
        if mode == .detail {
            XCTAssertTrue(scroll is UITableView)
            XCTAssertEqual((scroll as? UITableView)?.estimatedRowHeight, 0)
        } else {
            XCTAssertTrue(scroll is UICollectionView)
        }
        XCTAssertNil(findSearchController(in: host), "The gallery must not use navigation-owned search")
        scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        try await Task.sleep(for: .milliseconds(300))
        let field = try XCTUnwrap(findView(UITextField.self, in: host.view))
        let anchor = try XCTUnwrap(controller.captureAnchor())
        let initialOffset = scroll.contentOffset.y
        let initialSearchY = field.convert(.zero, to: window).y
        let initialFrame = scroll.convert(scroll.bounds, to: window)
        let cell = try XCTUnwrap(anchorCell(in: scroll))
        let initialCellY = cell.convert(.zero, to: window).y
        let initialCellSize = cell.bounds.size
        snapshot(window, name: "before-\(mode)-\(route)-\(offset)")

        func observe(_ phase: String) async throws {
            var maximumMovement: CGFloat = 0
            for _ in 0..<40 {
                try await Task.sleep(for: .milliseconds(16))
                let currentY = cell.layer.presentation()?.convert(
                    .zero, to: window.layer.presentation() ?? window.layer
                ).y ?? cell.convert(.zero, to: window).y
                maximumMovement = max(maximumMovement, abs(currentY - initialCellY))
                XCTAssertEqual(field.convert(.zero, to: window).y, initialSearchY, accuracy: 1)
                XCTAssertEqual(scroll.contentOffset.y, initialOffset, accuracy: 1)
                XCTAssertEqual(scroll.adjustedContentInset, .zero)
            }
            XCTAssertLessThanOrEqual(maximumMovement, 1, "\(phase) moved visible content")
            XCTAssertEqual(controller.captureAnchor()?.id, anchor.id)
            XCTAssertEqual(cell.bounds.size, initialCellSize)
        }
        for cycle in 0..<5 {
            XCTAssertTrue(field.becomeFirstResponder())
            try await observe("focus-\(cycle)")
            XCTAssertLessThan(window.keyboardLayoutGuide.layoutFrame.minY, window.bounds.maxY - 100)
            snapshot(window, name: "focused-\(mode)-\(cycle)")
            let cancel = try XCTUnwrap(findView(UIButton.self, in: host.view) {
                $0.accessibilityIdentifier == "gallery-search-cancel"
            })
            cancel.sendActions(for: .touchUpInside)
            try await observe("cancel-\(cycle)")
            XCTAssertFalse(field.isFirstResponder)
            XCTAssertEqual(scroll.convert(scroll.bounds, to: window).minY, initialFrame.minY, accuracy: 1)
        }
        snapshot(window, name: "cancelled-\(mode)-\(route)-\(offset)")
    }

    private func anchorCell(in scroll: UIScrollView) -> UIView? {
        if let table = scroll as? UITableView {
            return table.visibleCells.filter { $0.frame.maxY > scroll.contentOffset.y }
                .min { $0.frame.minY < $1.frame.minY }
        }
        if let collection = scroll as? UICollectionView {
            return collection.visibleCells.filter { $0.frame.maxY > scroll.contentOffset.y }
                .min { $0.frame.minY < $1.frame.minY }
        }
        return nil
    }

    private func snapshot(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func findController<T: UIViewController>(_ type: T.Type, in controller: UIViewController) -> T? {
        if let match = controller as? T { return match }
        return controller.children.reversed().lazy.compactMap { self.findController(type, in: $0) }.first
    }

    private func findSearchController(in controller: UIViewController) -> UISearchController? {
        if let search = controller.navigationItem.searchController { return search }
        return controller.children.lazy.compactMap { self.findSearchController(in: $0) }.first
    }

    private func findView<T: UIView>(_ type: T.Type, in view: UIView, matching: (T) -> Bool = { _ in true }) -> T? {
        if let match = view as? T, matching(match) { return match }
        for child in view.subviews {
            if let match = findView(type, in: child, matching: matching) { return match }
        }
        return nil
    }
}


@MainActor
private func makeListTestGalleries(count: Int) throws -> [Gallery] {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gallery-list-test-covers")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let colors: [UIColor] = [.systemTeal, .systemPink, .systemGreen, .systemIndigo]
    var covers = [URL]()
    for (index, color) in colors.enumerated() {
        let url = directory.appendingPathComponent("\(index).png")
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 260)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 180, height: 260))
            UIColor.white.setFill()
            context.fill(CGRect(x: 16, y: 30, width: 148, height: 6))
            context.fill(CGRect(x: 16, y: 220, width: 148, height: 6))
            ("\(index + 1)" as NSString).draw(
                at: CGPoint(x: 60, y: 80),
                withAttributes: [.font: UIFont.systemFont(ofSize: 72, weight: .bold), .foregroundColor: UIColor.white]
            )
        }
        try XCTUnwrap(picture.pngData()).write(to: url)
        covers.append(url)
    }
    return (0..<count).map { index in
        Gallery(
            gid: "list-test-\(index)", token: "token",
            title: "Gallery \(index) " + String(repeating: "title ", count: index % 9),
            rating: 4, tags: [GalleryTag(rawNamespace: "language", contents: [
                .init(rawNamespace: "language", text: "chinese", isVotedUp: false, isVotedDown: false,
                      textColor: nil, backgroundColor: nil)
            ])],
            category: .manga, uploader: "Tester", pageCount: 20,
            postedDate: Date(timeIntervalSince1970: 0), coverURL: covers[index % covers.count], galleryURL: nil
        )
    }
}

@MainActor
private final class GalleryListFixture: ObservableObject {
    @Published var galleries: [Gallery]
    @Published var setting = Setting()
    @Published var width: CGFloat = 390
    @Published var height: CGFloat = 720
    @Published var dataset = 0
    @Published var presentation = [String: GalleryListPresentation]()
    @Published var footer: LoadingState = .idle
    @Published var page: PageNumber?
    @Published var query = ""
    @Published var searching = false
    var selection: String?
    var actionCount = 0
    var fetchCount = 0
    var refreshCount = 0
    var submitCount = 0

    init(mode: ListDisplayMode) throws {
        galleries = try makeListTestGalleries(count: 60)
        setting.listDisplayMode = mode
    }
}

private struct GalleryListFixtureView: View {
    @ObservedObject var fixture: GalleryListFixture

    var body: some View {
        GenericList(
            galleries: fixture.galleries, setting: fixture.setting, datasetIdentity: fixture.dataset,
            presentations: fixture.presentation,
            actionsProvider: { _ in [
                .init(title: "Resume", systemImage: "play", role: .normal, edge: .leading, tint: .green,
                      action: { fixture.actionCount += 1 }),
                .init(title: "Remove", systemImage: "trash", role: .destructive, edge: .trailing, tint: .red,
                      action: { fixture.actionCount += 1 })
            ] },
            pageNumber: fixture.page, loadingState: .idle, footerLoadingState: fixture.footer,
            fetchAction: { fixture.refreshCount += 1 },
            fetchMoreAction: { fixture.fetchCount += 1 },
            navigateAction: { fixture.selection = $0 }
        )
        .environment(\.galleryContextMenuConfiguration, .downloadsOnly(
            user: .empty, setting: fixture.setting, blurRadius: 0, tagTranslator: TagTranslator()
        ))
        .gallerySearch(text: $fixture.query, isPresented: $fixture.searching,
                       tagTranslator: TagTranslator(), setting: fixture.setting,
                       onSubmit: { fixture.submitCount += 1 })
        .frame(width: fixture.width, height: fixture.height)
    }
}

@MainActor
final class GalleryListLifecycleTests: XCTestCase {
    func testSearchSubmitReachesPageAndCancelClearsQuery() async throws {
        let fixture = try GalleryListFixture(mode: .detail)
        let host = try await mount(fixture)
        defer { unmount(host) }
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextField }.first)
        XCTAssertTrue(field.becomeFirstResponder())
        try await settle()
        fixture.query = "Gallery"
        try await settle()
        // UIKit asks the delegate first, then sends the control's return-key event.
        // Calling only the delegate omits SwiftUI's installed submit target.
        if field.delegate?.textFieldShouldReturn?(field) != false {
            field.sendActions(for: .editingDidEndOnExit)
        }
        try await settle()
        XCTAssertEqual(fixture.submitCount, 1)
        XCTAssertEqual(fixture.query, "Gallery")
        XCTAssertFalse(field.isFirstResponder)
        let cancel = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "gallery-search-cancel"
        })
        cancel.sendActions(for: .touchUpInside)
        try await settle()
        XCTAssertEqual(fixture.query, "")
        XCTAssertFalse(fixture.searching)
    }

    func testBothStylesInstallNativeContextMenuInteractions() async throws {
        for mode in [ListDisplayMode.waterfall, .detail] {
            let fixture = try GalleryListFixture(mode: mode)
            let host = try await mount(fixture)
            defer { unmount(host) }
            let list = try XCTUnwrap(findList(in: host))
            let cell = try XCTUnwrap(firstCell(list.scrollView))
            let interactions = descendants(cell).flatMap(\.interactions)
            XCTAssertTrue(interactions.contains { $0 is UIContextMenuInteraction })
            if DeviceUtil.isPad { XCTAssertTrue(interactions.contains { $0 is UIDragInteraction }) }
        }
    }

    func testRefreshingDataDoesNotForceNegativeOffsetToZero() async throws {
        for mode in [ListDisplayMode.waterfall, .detail] {
            let fixture = try GalleryListFixture(mode: mode)
            let host = try await mount(fixture)
            defer { unmount(host) }
            let list = try XCTUnwrap(findList(in: host))
            let control = try XCTUnwrap(list.scrollView.refreshControl)
            control.beginRefreshing()
            list.scrollView.setContentOffset(CGPoint(x: 0, y: -70), animated: false)
            fixture.galleries = try makeListTestGalleries(count: 65)
            try await settle()
            XCTAssertLessThan(list.scrollView.contentOffset.y, 0)
            control.endRefreshing()
        }
    }

    func testAppendRemovalResizeAndDatasetResetInBothModes() async throws {
        for mode in [ListDisplayMode.waterfall, .detail] {
            let fixture = try GalleryListFixture(mode: mode)
            let host = try await mount(fixture)
            defer { unmount(host) }
            let list = try XCTUnwrap(findList(in: host))
            let scroll = try XCTUnwrap(list.scrollView)
            scroll.setContentOffset(CGPoint(x: 0, y: 1400), animated: false)
            try await settle()
            let anchor = try XCTUnwrap(list.captureAnchor())
            let oldFrames = frames(of: scroll)
            fixture.galleries = try makeListTestGalleries(count: 90)
            try await settle()
            XCTAssertEqual(Array(frames(of: scroll).prefix(60)), oldFrames)
            XCTAssertEqual(list.captureAnchor()?.id, anchor.id)
            XCTAssertEqual(list.captureAnchor()?.distance ?? 0, anchor.distance, accuracy: 1)

            fixture.galleries.removeFirst(2)
            try await settle()
            let anchoredIndex = try XCTUnwrap(fixture.galleries.firstIndex { $0.id == anchor.id })
            XCTAssertEqual(frames(of: scroll)[anchoredIndex].minY - scroll.contentOffset.y, anchor.distance, accuracy: 1)
            let framesBeforeKeyboard = frames(of: scroll)
            let offsetBeforeKeyboard = scroll.contentOffset.y
            fixture.height = 350
            try await settle()
            XCTAssertEqual(frames(of: scroll), framesBeforeKeyboard)
            XCTAssertEqual(scroll.contentOffset.y, offsetBeforeKeyboard, accuracy: 1)
            fixture.height = 720
            fixture.width = 320
            try await settle()
            XCTAssertEqual(list.scrollView.bounds.width, 320, accuracy: 1)
            XCTAssertGreaterThan(list.scrollView.contentOffset.y, 0)
            XCTAssertTrue(frames(of: scroll).allSatisfy { $0.maxX <= 320.01 })

            fixture.dataset += 1
            try await settle()
            XCTAssertEqual(scroll.contentOffset.y, 0, accuracy: 1)
        }
    }

    func testChangingDisplayStyleRetainsVisibleGallery() async throws {
        let fixture = try GalleryListFixture(mode: .waterfall)
        let host = try await mount(fixture)
        defer { unmount(host) }
        let list = try XCTUnwrap(findList(in: host))
        list.scrollView.setContentOffset(CGPoint(x: 0, y: 1800), animated: false)
        try await settle()
        let anchor = try XCTUnwrap(list.captureAnchor())
        fixture.setting.listDisplayMode = .detail
        try await settle()
        XCTAssertTrue(list.scrollView is UITableView)
        XCTAssertEqual(list.captureAnchor()?.id, anchor.id)
        XCTAssertEqual(list.captureAnchor()?.fraction ?? 0, anchor.fraction, accuracy: 0.01)
    }

    func testProgressUpdateDoesNotReplaceVisibleCells() async throws {
        for mode in [ListDisplayMode.waterfall, .detail] {
            let fixture = try GalleryListFixture(mode: mode)
            let id = try XCTUnwrap(fixture.galleries.first?.id)
            let status: (Double) -> GalleryListStatus = {
                .init(text: "Downloading", detailText: "10 / 30", message: nil,
                      systemImage: "arrow.down", tone: .accent, progress: $0)
            }
            fixture.presentation[id] = .init(coverURL: nil, status: status(0))
            let host = try await mount(fixture)
            defer { unmount(host) }
            let list = try XCTUnwrap(findList(in: host))
            let cell = try XCTUnwrap(firstCell(list.scrollView))
            let originalFrames = frames(of: list.scrollView)
            fixture.presentation[id] = .init(coverURL: nil, status: status(0.9))
            try await settle()
            XCTAssertTrue(cell === firstCell(list.scrollView))
            XCTAssertEqual(frames(of: list.scrollView), originalFrames)
        }
    }

    func testShrinkingVisibleCardKeepsItsRelativePosition() async throws {
        for mode in [ListDisplayMode.waterfall, .detail] {
            let fixture = try GalleryListFixture(mode: mode)
            for index in fixture.galleries.indices {
                fixture.galleries[index].title = String(repeating: "Long title ", count: 30)
            }
            let host = try await mount(fixture)
            defer { unmount(host) }
            let list = try XCTUnwrap(findList(in: host))
            list.scrollView.setContentOffset(CGPoint(x: 0, y: 1390), animated: false)
            try await settle()
            let anchor = try XCTUnwrap(list.captureAnchor())
            let index = try XCTUnwrap(fixture.galleries.firstIndex { $0.id == anchor.id })
            fixture.galleries[index].title = "Short"
            try await settle()
            let frame = frames(of: list.scrollView)[index]
            let fraction = (frame.minY - list.scrollView.contentOffset.y) / frame.height
            XCTAssertEqual(fraction, anchor.fraction, accuracy: 0.01)
        }
    }

    func testSelectionAndNativeDetailSwipeActions() async throws {
        for mode in [ListDisplayMode.waterfall, .detail] {
            let fixture = try GalleryListFixture(mode: mode)
            let host = try await mount(fixture)
            defer { unmount(host) }
            let list = try XCTUnwrap(findList(in: host))
            let index = IndexPath(item: 1, section: 0)
            if let table = list.scrollView as? UITableView {
                table.delegate?.tableView?(table, didSelectRowAt: index)
                let leading = try XCTUnwrap(table.delegate?.tableView?(
                    table, leadingSwipeActionsConfigurationForRowAt: index
                ))
                let trailing = try XCTUnwrap(table.delegate?.tableView?(
                    table, trailingSwipeActionsConfigurationForRowAt: index
                ))
                XCTAssertTrue(leading.performsFirstActionWithFullSwipe)
                XCTAssertFalse(trailing.performsFirstActionWithFullSwipe)
                XCTAssertEqual(trailing.actions.first?.style, .destructive)
                let action = try XCTUnwrap(leading.actions.first)
                action.handler(action, table) { XCTAssertTrue($0) }
                XCTAssertEqual(fixture.actionCount, 1)
            } else if let collection = list.scrollView as? UICollectionView {
                collection.delegate?.collectionView?(collection, didSelectItemAt: index)
            }
            XCTAssertEqual(fixture.selection, fixture.galleries[1].id)
        }
    }

    func testRefreshCanCompleteAndRunAgainInBothModes() async throws {
        for mode in [ListDisplayMode.waterfall, .detail] {
            let fixture = try GalleryListFixture(mode: mode)
            let host = try await mount(fixture)
            defer { unmount(host) }
            let list = try XCTUnwrap(findList(in: host))
            let control = try XCTUnwrap(list.scrollView.refreshControl)
            for count in 1...3 {
                control.beginRefreshing()
                control.sendActions(for: .valueChanged)
                try await settle()
                XCTAssertFalse(control.isRefreshing)
                XCTAssertEqual(fixture.refreshCount, count)
            }
        }
    }

    func testPaginationIsDeduplicatedAndFailureDoesNotAutoRetry() async throws {
        for mode in [ListDisplayMode.waterfall, .detail] {
            let fixture = try GalleryListFixture(mode: mode)
            fixture.page = PageNumber(current: 0, maximum: 4, isNextButtonEnabled: true)
            let host = try await mount(fixture)
            defer { unmount(host) }
            let list = try XCTUnwrap(findList(in: host))
            let scroll = try XCTUnwrap(list.scrollView)
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
            try await settle()
            for _ in 0..<10 { list.scrollViewDidScroll(scroll) }
            XCTAssertEqual(fixture.fetchCount, 1)
            fixture.footer = .failed(.networkingFailed)
            try await settle()
            for _ in 0..<10 { list.scrollViewDidScroll(scroll) }
            XCTAssertEqual(fixture.fetchCount, 1)
            fixture.galleries = try makeListTestGalleries(count: 90)
            fixture.page = PageNumber(current: 1, maximum: 4, isNextButtonEnabled: true)
            fixture.footer = .idle
            try await settle()
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
            try await settle()
            XCTAssertEqual(fixture.fetchCount, 2)
        }
    }

    private var previousController: UIViewController?
    private var window: UIWindow?

    private func mount(_ fixture: GalleryListFixture) async throws -> UIViewController {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene)
        let window = try XCTUnwrap(scene.keyWindow)
        self.window = window
        previousController = window.rootViewController
        let host = UIHostingController(rootView: GalleryListFixtureView(fixture: fixture))
        window.rootViewController = host
        window.makeKeyAndVisible()
        try await settle()
        return host
    }

    private func unmount(_ host: UIViewController) {
        if window?.rootViewController === host { window?.rootViewController = previousController }
        previousController = nil
        window = nil
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(250)) }

    private func findList(in controller: UIViewController) -> GalleryListController? {
        if let list = controller as? GalleryListController { return list }
        return controller.children.lazy.compactMap { self.findList(in: $0) }.first
    }

    private func frames(of scroll: UIScrollView) -> [CGRect] {
        if let table = scroll as? UITableView {
            return (0..<table.numberOfRows(inSection: 0)).map { table.rectForRow(at: IndexPath(row: $0, section: 0)) }
        }
        if let collection = scroll as? UICollectionView {
            return (0..<collection.numberOfItems(inSection: 0)).compactMap {
                collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame
            }
        }
        return []
    }

    private func firstCell(_ scroll: UIScrollView) -> UIView? {
        (scroll as? UITableView)?.cellForRow(at: IndexPath(row: 0, section: 0))
            ?? (scroll as? UICollectionView)?.cellForItem(at: IndexPath(item: 0, section: 0))
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}

final class JHenTaiCacheImporterTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("123456 - Imported Gallery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(
                at: directoryURL.deletingLastPathComponent()
            )
        }
    }

    func testImportsJHenTaiMetadataAndZeroBasedPageFiles() throws {
        try writeMetadata(pageCount: 3, downloadsOriginalImages: true)
        try Data([0x01]).write(to: directoryURL.appendingPathComponent("0.jpg"))
        try Data([0x02, 0x03]).write(to: directoryURL.appendingPathComponent("2.png"))

        let item = try XCTUnwrap(
            JHenTaiCacheImporter.importItem(
                from: directoryURL,
                maximumMetadataByteCount: 1_000_000
            )
        )

        XCTAssertEqual(item.id, "123456")
        XCTAssertEqual(item.displayTitle, "Imported Gallery")
        XCTAssertEqual(item.gallery.category, .manga)
        XCTAssertEqual(item.pageCount, 3)
        XCTAssertEqual(item.pageFiles, [1: "0.jpg", 3: "2.png"])
        XCTAssertEqual(item.coverFileName, "0.jpg")
        XCTAssertEqual(item.remoteImageURLs[2]?.absoluteString, "https://example.com/1.jpg")
        XCTAssertEqual(
            item.originalImageURLs[2]?.absoluteString,
            "https://example.com/original-1.jpg"
        )
        XCTAssertEqual(item.imageQuality, .original)
        XCTAssertEqual(item.status, .paused)
        XCTAssertEqual(item.byteCount, 3)
    }

    func testMarksFullyImportedJHenTaiGalleryCompleted() throws {
        try writeMetadata(pageCount: 2, downloadsOriginalImages: false)
        try Data([0x01]).write(to: directoryURL.appendingPathComponent("0.webp"))
        try Data([0x02]).write(to: directoryURL.appendingPathComponent("1.jpeg"))

        let item = try XCTUnwrap(
            JHenTaiCacheImporter.importItem(
                from: directoryURL,
                maximumMetadataByteCount: 1_000_000
            )
        )

        XCTAssertEqual(item.cachedPageCount, 2)
        XCTAssertEqual(item.status, .completed)
        XCTAssertTrue(item.isComplete)
        XCTAssertEqual(item.imageQuality, .standard)
    }

    func testRejectsDirectoryWithoutJHenTaiMetadata() {
        XCTAssertNil(
            JHenTaiCacheImporter.importItem(
                from: directoryURL,
                maximumMetadataByteCount: 1_000_000
            )
        )
    }

    private func writeMetadata(
        pageCount: Int,
        downloadsOriginalImages: Bool
    ) throws {
        let images = (0..<pageCount).map { index in
            [
                "url": "https://example.com/\(index).jpg",
                "originalImageUrl": "https://example.com/original-\(index).jpg",
                "downloadStatus": 4
            ] as [String: Any]
        }
        let imagesData = try JSONSerialization.data(withJSONObject: images)
        let payload: [String: Any] = [
            "gallery": [
                "gid": 123456,
                "token": "token",
                "title": "Imported Gallery",
                "category": "Manga",
                "pageCount": pageCount,
                "galleryUrl": "https://e-hentai.org/g/123456/token/",
                "uploader": "Uploader",
                "publishTime": "2026-07-18 12:30:00",
                "insertTime": "2026-07-18 12:31:00",
                "downloadOriginalImage": downloadsOriginalImages
            ],
            "images": try XCTUnwrap(String(data: imagesData, encoding: .utf8))
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: directoryURL.appendingPathComponent("metadata"))
    }
}

final class GalleryIdentityTests: XCTestCase {
    func testEqualGalleryValuesHaveEqualHashes() {
        let first = makeGallery(title: "First")
        let second = makeGallery(title: "Updated")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
        XCTAssertEqual(Set([first, second]).count, 1)
    }

    private func makeGallery(title: String) -> Gallery {
        .init(
            gid: "1",
            token: "token",
            title: title,
            rating: 4,
            tags: [],
            category: .doujinshi,
            uploader: nil,
            pageCount: 10,
            postedDate: .distantPast,
            coverURL: nil,
            galleryURL: nil
        )
    }
}

final class WebLoginCompletionPolicyTests: XCTestCase {
    func testExistingCredentialsDoNotCompleteBeforeLoginPageIsPresented() {
        var policy = WebLoginCompletionPolicy()

        XCTAssertFalse(
            policy.shouldComplete(
                navigationURL: URL(string: "https://forums.e-hentai.org/index.php"),
                hasCredentials: true
            )
        )
    }

    func testLoginPageDoesNotCompleteWithExistingCredentials() {
        var policy = WebLoginCompletionPolicy()

        XCTAssertFalse(
            policy.shouldComplete(
                navigationURL: Defaults.URL.webLogin,
                hasCredentials: true
            )
        )
        XCTAssertTrue(policy.hasPresentedLoginPage)
    }

    func testAuthenticatedNavigationCompletesAfterPresentingLoginPage() {
        var policy = WebLoginCompletionPolicy()
        _ = policy.shouldComplete(
            navigationURL: Defaults.URL.webLogin,
            hasCredentials: false
        )

        XCTAssertTrue(
            policy.shouldComplete(
                navigationURL: URL(string: "https://forums.e-hentai.org/index.php"),
                hasCredentials: true
            )
        )
    }
}

final class TagSuggestionEngineTests: XCTestCase {
    func testMatchesTranslatedValueAndLimitsSuggestions() {
        let translations = [
            "languagechinese": translation(key: "chinese", value: "中文"),
            "languagechinese simplified": translation(
                key: "chinese simplified",
                value: "中文简体"
            ),
            "languagechinese traditional": translation(
                key: "chinese traditional",
                value: "中文繁体"
            ),
            "languagetranslated": translation(
                key: "translated",
                value: "中文翻译"
            ),
            "languagetranslated rewrite": translation(
                key: "translated rewrite",
                value: "中文改写"
            ),
            "languagechinese text": translation(
                key: "chinese text",
                value: "中文文本"
            )
        ]

        let suggestions = TagSuggestionEngine.suggestions(
            for: "中文",
            translations: translations,
            maximumCount: 5
        )

        XCTAssertEqual(suggestions.count, 5)
        XCTAssertEqual(suggestions.first?.tag.searchKeyword, "l:chinese$")
    }

    func testCompletesOnlyTheUnfinishedSuffix() throws {
        let suggestion = try XCTUnwrap(
            TagSuggestionEngine.suggestions(
                for: "中文",
                translations: [
                    "languagechinese": translation(
                        key: "chinese",
                        value: "中文"
                    )
                ],
                maximumCount: 3
            ).first
        )

        XCTAssertEqual(
            TagSuggestionEngine.completing(
                "a:example$ 中文",
                with: suggestion
            ),
            "a:example$ l:chinese$ "
        )
    }

    func testDoesNotSuggestAfterAnExactTagIsComplete() {
        let suggestions = TagSuggestionEngine.suggestions(
            for: "l:chinese$",
            translations: [
                "languagechinese": translation(
                    key: "chinese",
                    value: "中文"
                )
            ],
            maximumCount: 3
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    private func translation(key: String, value: String) -> TagTranslation {
        .init(
            namespace: .language,
            key: key,
            value: value,
            description: nil,
            linksString: nil
        )
    }
}

final class ReadingImageRetryRouteTests: XCTestCase {
    func testFetchesImageURLWhenThePageHasNoURL() {
        XCTAssertEqual(ReadingImageRetryRoute(imageURL: nil), .fetch)
    }

    func testRefreshesImageURLWhenThePageHasAnExistingURL() {
        XCTAssertEqual(
            ReadingImageRetryRoute(
                imageURL: URL(string: "https://example.com/image.jpg")
            ),
            .refetch
        )
    }
}

final class ReadingPageIndexMapperTests: XCTestCase {
    func testKeepsLogicalOrderForLeftToRightReading() {
        XCTAssertEqual(
            ReadingPageIndexMapper.displayIndex(
                forLogicalIndex: 2,
                itemCount: 5,
                isReversed: false
            ),
            2
        )
        XCTAssertEqual(
            ReadingPageIndexMapper.logicalIndex(
                forDisplayIndex: 2,
                itemCount: 5,
                isReversed: false
            ),
            2
        )
    }

    func testMirrorsLogicalOrderForRightToLeftReading() {
        XCTAssertEqual(
            ReadingPageIndexMapper.displayIndex(
                forLogicalIndex: 0,
                itemCount: 5,
                isReversed: true
            ),
            4
        )
        XCTAssertEqual(
            ReadingPageIndexMapper.logicalIndex(
                forDisplayIndex: 3,
                itemCount: 5,
                isReversed: true
            ),
            1
        )
    }

    func testClampsExternalPageUpdatesToAvailableItems() {
        XCTAssertEqual(ReadingPageIndexMapper.clamped(-1, itemCount: 5), 0)
        XCTAssertEqual(ReadingPageIndexMapper.clamped(8, itemCount: 5), 4)
        XCTAssertEqual(ReadingPageIndexMapper.clamped(1, itemCount: 0), 0)
    }
}

final class ReadingImageLoadRequestGateTests: XCTestCase {
    func testCancelledRequestCannotReportACompletion() {
        var gate = ReadingImageLoadRequestGate()
        let requestID = gate.begin()

        gate.cancel()

        XCTAssertFalse(gate.complete(requestID))
        XCTAssertNil(gate.activeRequestID)
    }

    func testStaleCompletionCannotClearTheCurrentRequest() {
        var gate = ReadingImageLoadRequestGate()
        let staleRequestID = gate.begin()
        let currentRequestID = gate.begin()

        XCTAssertFalse(gate.complete(staleRequestID))
        XCTAssertEqual(gate.activeRequestID, currentRequestID)
        XCTAssertTrue(gate.complete(currentRequestID))
        XCTAssertNil(gate.activeRequestID)
    }
}

final class ReadingReloadStateTests: XCTestCase {
    func testReloadClearsRemoteLoadingStateAndKeepsLocalPages() {
        let localURL = URL(fileURLWithPath: "/tmp/ehpanda-reader-page")
        let remoteURL = URL(string: "https://example.com/page.jpg")!
        var state = ReadingReducer.State()
        state.previewURLs = [1: remoteURL]
        state.thumbnailURLs = [1: remoteURL]
        state.imageURLs = [1: remoteURL, 2: localURL]
        state.networkImageURLs = [1: remoteURL]
        state.originalImageURLs = [1: remoteURL]
        state.imageURLLoadingStates = [1: .loading]
        state.previewLoadingStates = [1: .loading]
        state.webImageLoadSuccessIndices = [1]
        state.prefetchLimitsByIndex = [1: 10]
        state.mpvKey = "key"
        state.mpvImageKeys = [1: "image-key"]
        state.mpvSkipServerIdentifiers = [1: "server"]
        let oldRefreshID = state.forceRefreshID

        state.resetRemoteImageLoadingState()

        XCTAssertEqual(state.imageURLs, [2: localURL])
        XCTAssertTrue(state.previewURLs.isEmpty)
        XCTAssertTrue(state.thumbnailURLs.isEmpty)
        XCTAssertTrue(state.networkImageURLs.isEmpty)
        XCTAssertTrue(state.originalImageURLs.isEmpty)
        XCTAssertTrue(state.imageURLLoadingStates.isEmpty)
        XCTAssertTrue(state.previewLoadingStates.isEmpty)
        XCTAssertTrue(state.webImageLoadSuccessIndices.isEmpty)
        XCTAssertTrue(state.prefetchLimitsByIndex.isEmpty)
        XCTAssertNil(state.mpvKey)
        XCTAssertTrue(state.mpvImageKeys.isEmpty)
        XCTAssertTrue(state.mpvSkipServerIdentifiers.isEmpty)
        XCTAssertNotEqual(state.forceRefreshID, oldRefreshID)
    }
}

final class ListDisplayModeTests: XCTestCase {
    func testPersistedThumbnailModeDecodesAsWaterfall() throws {
        let mode = try JSONDecoder().decode(
            ListDisplayMode.self,
            from: Data("1".utf8)
        )

        XCTAssertEqual(mode, .waterfall)
    }
}

final class AppIconTypeTests: XCTestCase {
    func testExistingPersistedRawValuesRemainStable() {
        XCTAssertEqual(AppIconType.default.rawValue, 0)
        XCTAssertEqual(AppIconType.ukiyoe.rawValue, 1)
        XCTAssertEqual(AppIconType.developer.rawValue, 2)
        XCTAssertEqual(AppIconType.standWithUkraine2022.rawValue, 3)
        XCTAssertEqual(AppIconType.notMyPresident.rawValue, 4)
        XCTAssertEqual(AppIconType.classic.rawValue, 5)
    }

    func testPrimaryAndClassicIconMappings() {
        XCTAssertNil(AppIconType.default.alternateIconName)
        XCTAssertEqual(
            AppIconType.classic.alternateIconName,
            "AppIcon_Default"
        )
        XCTAssertEqual(AppIconType(alternateIconName: nil), .default)
        XCTAssertEqual(
            AppIconType(alternateIconName: "AppIcon_Default"),
            .classic
        )
    }
}

final class LoginNavigationTests: XCTestCase {
    func testLoginNavigationStartsAtWebLoginFromSettingsRoot() {
        var state = AppReducer.State()

        state.prepareLoginNavigation(isLoggedIn: false)

        XCTAssertEqual(state.settingState.route, .account)
        guard case .some(.login) = state.settingState.accountSettingState.route else {
            return XCTFail("Expected the web login destination")
        }
    }

    func testLoginNavigationReplacesAnExistingSettingsDestination() {
        var state = AppReducer.State()
        state.settingState.route = .appearance
        state.settingState.accountSettingState.route = .ehSetting()

        state.prepareLoginNavigation(isLoggedIn: false)

        XCTAssertEqual(state.settingState.route, .account)
        guard case .some(.login) = state.settingState.accountSettingState.route else {
            return XCTFail("Expected the web login destination")
        }
    }
}

final class GalleryLocalSearchMatcherTests: XCTestCase {
    func testMatchesCompletedTagSuggestionsAgainstCachedGalleryTags() {
        var gallery = Gallery.preview
        gallery.tags = [
            GalleryTag(
                rawNamespace: TagNamespace.language.rawValue,
                contents: [
                    .init(
                        rawNamespace: TagNamespace.language.rawValue,
                        text: "chinese",
                        isVotedUp: false,
                        isVotedDown: false,
                        textColor: nil,
                        backgroundColor: nil
                    )
                ]
            )
        ]

        XCTAssertTrue(
            GalleryLocalSearchMatcher.matches(
                gallery: gallery,
                query: "l:chinese$",
                additionalText: []
            )
        )
        XCTAssertFalse(
            GalleryLocalSearchMatcher.matches(
                gallery: gallery,
                query: "l:english$",
                additionalText: []
            )
        )
    }

    func testCombinesTagAndMetadataTokens() {
        var gallery = Gallery.preview
        gallery.tags = [
            GalleryTag(
                rawNamespace: TagNamespace.language.rawValue,
                contents: [
                    .init(
                        rawNamespace: TagNamespace.language.rawValue,
                        text: "chinese",
                        isVotedUp: false,
                        isVotedDown: false,
                        textColor: nil,
                        backgroundColor: nil
                    )
                ]
            )
        ]

        XCTAssertTrue(
            GalleryLocalSearchMatcher.matches(
                gallery: gallery,
                query: "l:chinese$ panda",
                additionalText: ["Panda collection"]
            )
        )
        XCTAssertFalse(
            GalleryLocalSearchMatcher.matches(
                gallery: gallery,
                query: "l:chinese$ missing",
                additionalText: ["Panda collection"]
            )
        )
    }
}

final class GalleryCacheActivityUnitProgressTests: XCTestCase {
    func testResolvedURLsDoNotAdvanceDownloadProgress() {
        let progress = GalleryCacheActivityUnitProgress(
            cachedPageCount: 0,
            totalPageCount: 100
        )

        XCTAssertEqual(progress.completedUnitCount, 0)
        XCTAssertEqual(progress.totalUnitCount, 100)
    }

    func testProgressTracksDownloadedPagesAndClampsToTotal() {
        let partialProgress = GalleryCacheActivityUnitProgress(
            cachedPageCount: 42,
            totalPageCount: 100
        )
        let completedProgress = GalleryCacheActivityUnitProgress(
            cachedPageCount: 101,
            totalPageCount: 100
        )

        XCTAssertEqual(partialProgress.completedUnitCount, 42)
        XCTAssertEqual(completedProgress.completedUnitCount, 100)
    }
}

final class NavigationLayoutSettingTests: XCTestCase {
    @MainActor
    func testPhoneSearchTabRespectsCustomOrder() async throws {
        guard !DeviceUtil.isPad else { throw XCTSkip("Phone-specific tab ordering") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        var state = AppReducer.State()
        state.settingState.setting.tabBarItems = [.search, .popular, .favorites]
        state.tabBarState.tabBarItemType = .more
        let store = Store(initialState: state) {
            Reduce<AppReducer.State, AppReducer.Action> { state, action in
                if case let .setNavigationItems(tabs, more) = action {
                    state.settingState.setting.tabBarItems = tabs
                    state.settingState.setting.moreItems = more
                }
                return .none
            }
        }
        let host = UIHostingController(rootView: TabBarView(store: store))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(600))
        let controller = try XCTUnwrap(findTabController(in: host))
        XCTAssertFalse(controller.tabs.contains { $0 is UISearchTab })
        XCTAssertEqual(
            controller.tabBar.items?.map(\.title),
            [AppNavigationItem.home, .search, .popular, .favorites, .more].map(\.title)
        )

        store.send(.setNavigationItems([.popular, .search, .favorites], state.settingState.setting.moreItems))
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(
            controller.tabBar.items?.map(\.title),
            [AppNavigationItem.home, .popular, .search, .favorites, .more].map(\.title)
        )
    }

    @MainActor
    private func findTabController(in controller: UIViewController) -> UITabBarController? {
        if let tabController = controller as? UITabBarController { return tabController }
        return controller.children.lazy.compactMap { self.findTabController(in: $0) }.first
    }

    func testDefaultLayoutKeepsHomeAndMoreAroundSearch() {
        let setting = Setting()

        XCTAssertEqual(setting.tabBarItems, [.search])
        XCTAssertEqual(
            setting.moreItems,
            [.popular, .watched, .history, .favorites, .cache]
        )
    }

    func testMovesItemsBetweenTabBarAndMoreInRequestedOrder() {
        var setting = Setting()

        XCTAssertTrue(setting.moveNavigationItem(.favorites, to: .tabBar, at: 0))
        XCTAssertEqual(setting.tabBarItems, [.favorites, .search])
        XCTAssertFalse(setting.moreItems.contains(.favorites))

        XCTAssertTrue(setting.moveNavigationItem(.favorites, to: .more, at: 1))
        XCTAssertEqual(setting.tabBarItems, [.search])
        XCTAssertEqual(
            setting.moreItems,
            [.popular, .favorites, .watched, .history, .cache]
        )
    }

    func testRejectsFixedItemsAndReplacesTheLastItemInAFullTabBar() {
        var setting = Setting()
        setting.tabBarItems = [.search, .popular, .history]
        setting.moreItems = [.watched, .favorites, .cache]

        XCTAssertFalse(setting.moveNavigationItem(.home, to: .more, at: 0))
        XCTAssertFalse(setting.moveNavigationItem(.more, to: .tabBar, at: 0))
        XCTAssertFalse(setting.moveNavigationItem(.setting, to: .tabBar, at: 0))
        XCTAssertTrue(setting.moveNavigationItem(.watched, to: .tabBar, at: 0))
        XCTAssertEqual(setting.tabBarItems, [.watched, .search, .popular])
        XCTAssertEqual(setting.moreItems, [.history, .favorites, .cache])
    }

    func testEditorMovesAnItemFromMoreIntoAnEmptyTabBar() {
        var setting = Setting()
        setting.tabBarItems = []
        setting.moreItems = [.popular, .search, .history]

        XCTAssertTrue(
            setting.moveNavigationItem(
                from: .more,
                at: 1,
                to: .tabBar,
                at: 0
            )
        )
        XCTAssertEqual(setting.tabBarItems, [.search])
        XCTAssertEqual(
            setting.moreItems,
            [.popular, .history, .watched, .favorites, .cache]
        )
    }

    func testEditorMovesAnItemFromTabBarBackToMore() {
        var setting = Setting()
        setting.tabBarItems = [.search, .popular]
        setting.moreItems = [.history, .watched, .favorites, .cache]

        XCTAssertTrue(
            setting.moveNavigationItem(
                from: .tabBar,
                at: 0,
                to: .more,
                at: 2
            )
        )
        XCTAssertEqual(setting.tabBarItems, [.popular])
        XCTAssertEqual(
            setting.moreItems,
            [.history, .watched, .search, .favorites, .cache]
        )
    }

    func testEditorMovesAnItemDownWithinTheSameGroup() {
        var setting = Setting()
        setting.tabBarItems = [.search]
        setting.moreItems = [.popular, .watched, .history, .favorites, .cache]

        XCTAssertTrue(
            setting.moveNavigationItem(
                from: .more,
                at: 0,
                to: .more,
                at: 2
            )
        )
        XCTAssertEqual(
            setting.moreItems,
            [.watched, .history, .popular, .favorites, .cache]
        )
    }

    func testNormalizationRepairsDuplicatesInvalidItemsAndOverflow() {
        var setting = Setting()
        setting.tabBarItems = [
            .home, .setting, .search, .search, .popular, .watched, .history, .more
        ]
        setting.moreItems = [.favorites, .setting, .favorites, .home]

        setting.normalizeNavigationItems()

        XCTAssertEqual(setting.tabBarItems, [.search, .popular, .watched])
        XCTAssertEqual(setting.moreItems, [.history, .favorites, .cache])
    }
}

final class GalleryCacheLibraryIndexTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }

    func testLibraryIndexRoundTripsCacheItems() throws {
        let fingerprint = GalleryCacheDirectoryFingerprint(
            creationDate: Date(timeIntervalSince1970: 100.123_456),
            modificationDate: Date(timeIntervalSince1970: 200.654_321),
            manifest: .init(
                modificationDate: Date(timeIntervalSince1970: 300.456_789),
                byteCount: 512
            ),
            jHenTaiMetadata: nil
        )
        let entry = GalleryCacheLibraryIndex.DirectoryEntry(
            fingerprint: fingerprint,
            item: makeCacheItem()
        )
        let index = GalleryCacheLibraryIndex(
            directories: [entry.item.folderName: entry]
        )
        let store = GalleryCacheLibraryIndexStore(
            fileURL: temporaryDirectoryURL.appendingPathComponent("index.json"),
            maximumByteCount: 1_000_000
        )

        try store.save(index)

        XCTAssertEqual(store.load(), index)
    }

    func testLibraryIndexRejectsCorruptData() throws {
        let fileURL = temporaryDirectoryURL.appendingPathComponent("index.json")
        try Data("not-json".utf8).write(to: fileURL)
        let store = GalleryCacheLibraryIndexStore(
            fileURL: fileURL,
            maximumByteCount: 1_000_000
        )

        XCTAssertNil(store.load())
    }

    func testDirectoryFingerprintChangesAfterManualPageAddition() throws {
        let directoryURL = temporaryDirectoryURL.appendingPathComponent(
            "123456 - Gallery",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: directoryURL.path
        )
        let before = try XCTUnwrap(
            GalleryCacheDirectoryFingerprint.capture(at: directoryURL)
        )

        try Data([0x01]).write(to: directoryURL.appendingPathComponent("001.jpg"))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000)],
            ofItemAtPath: directoryURL.path
        )
        let after = try XCTUnwrap(
            GalleryCacheDirectoryFingerprint.capture(at: directoryURL)
        )

        XCTAssertNotEqual(after, before)
    }

    func testDirectoryFingerprintTracksManifestReplacement() throws {
        let directoryURL = temporaryDirectoryURL.appendingPathComponent(
            "123456 - Gallery",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        let manifestURL = directoryURL.appendingPathComponent(
            GalleryCacheItem.manifestFileName
        )
        try Data([0x01]).write(to: manifestURL)
        let before = try XCTUnwrap(
            GalleryCacheDirectoryFingerprint.capture(at: directoryURL)
        )

        try Data([0x01, 0x02]).write(to: manifestURL, options: .atomic)
        let after = try XCTUnwrap(
            GalleryCacheDirectoryFingerprint.capture(at: directoryURL)
        )

        XCTAssertNotEqual(after.manifest, before.manifest)
    }

    func testRefreshReconcilesManuallyAddedAndDeletedPages() async throws {
        let rootURL = try XCTUnwrap(FileUtil.prepareGalleryCachesDirectoryURL())
        let gid = String(Int.random(in: 900_000_000...999_999_999))
        let folderName = "\(gid) - Integration Test \(UUID().uuidString)"
        let directoryURL = rootURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try Data([0x01]).write(to: directoryURL.appendingPathComponent("001.jpg"))
        let item = makeCacheItem(gid: gid, folderName: folderName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(item).write(
            to: directoryURL.appendingPathComponent(GalleryCacheItem.manifestFileName),
            options: .atomic
        )

        await CacheClient.live.refresh()
        let initialItem = await CacheClient.live.item(gid)
        var refreshedItem = try XCTUnwrap(initialItem)
        XCTAssertEqual(refreshedItem.cachedPageCount, 1)
        XCTAssertEqual(refreshedItem.status, .paused)

        try Data([0x02]).write(to: directoryURL.appendingPathComponent("002.jpg"))
        await CacheClient.live.refresh()
        let addedPageItem = await CacheClient.live.item(gid)
        refreshedItem = try XCTUnwrap(addedPageItem)
        XCTAssertEqual(refreshedItem.cachedPageCount, 2)
        XCTAssertEqual(refreshedItem.status, .completed)

        try FileManager.default.removeItem(
            at: directoryURL.appendingPathComponent("001.jpg")
        )
        await CacheClient.live.refresh()
        let deletedPageItem = await CacheClient.live.item(gid)
        refreshedItem = try XCTUnwrap(deletedPageItem)
        XCTAssertEqual(refreshedItem.pageFiles, [2: "002.jpg"])
        XCTAssertEqual(refreshedItem.status, .paused)

        try FileManager.default.removeItem(at: directoryURL)
        await CacheClient.live.refresh()
        let removedItem = await CacheClient.live.item(gid)
        XCTAssertNil(removedItem)
    }

    func testDeleteLogRejectsParentDirectoryTraversal() async {
        let result = await FileClient.live.deleteLog("../unrelated.log")

        XCTAssertEqual(result, .failure(.notFound))
    }

    func testDeleteLogTreatsAnAlreadyMissingFileAsDeleted() async {
        let fileName = "missing-\(UUID().uuidString).log"

        let result = await FileClient.live.deleteLog(fileName)

        XCTAssertEqual(result, .success(fileName))
    }

    private func makeCacheItem(
        gid: String = "123456",
        folderName: String = "123456 - Gallery"
    ) -> GalleryCacheItem {
        let date = Date(timeIntervalSince1970: 100)
        let gallery = Gallery(
            gid: gid,
            token: "token",
            title: "Gallery",
            rating: 4,
            tags: [],
            category: .manga,
            uploader: "Uploader",
            pageCount: 2,
            postedDate: date,
            coverURL: nil,
            galleryURL: URL(string: "https://e-hentai.org/g/\(gid)/token/")
        )
        let detail = GalleryDetail(
            gid: gid,
            title: "Gallery",
            isFavorited: false,
            visibility: .yes,
            rating: 4,
            userRating: 0,
            ratingCount: 1,
            category: .manga,
            language: .english,
            uploader: "Uploader",
            postedDate: date,
            coverURL: nil,
            favoritedCount: 0,
            pageCount: 2,
            sizeCount: 2,
            sizeType: "MB",
            torrentCount: 0
        )
        return GalleryCacheItem(
            gallery: gallery,
            detail: detail,
            folderName: folderName,
            pageCount: 2,
            createdDate: date,
            directoryIdentifier: UUID(
                uuidString: "00000000-0000-0000-0000-000000000001"
            ),
            status: .paused,
            imageQuality: .standard,
            updatedDate: date,
            byteCount: 1,
            errorDescription: nil,
            coverFileName: "001.jpg",
            pageFiles: [1: "001.jpg"],
            pageIdentifiers: [
                1: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            ],
            remoteImageURLs: [2: URL(string: "https://example.com/002.jpg")!],
            originalImageURLs: [:]
        )
    }
}
