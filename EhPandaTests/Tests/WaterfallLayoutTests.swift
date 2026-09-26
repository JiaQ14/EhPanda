//
//  WaterfallLayoutTests.swift
//  EhPandaTests
//

import UIKit
import SwiftUI
import XCTest
import ComposableArchitecture
import Kanna
@testable import EhPanda

private let waterfallTestWidth: CGFloat = 390

final class WaterfallLayoutTests: XCTestCase {
    @MainActor
    func testSearchActivationDoesNotJumpWaterfallToTop() async throws {
        try await checkSearchTransition(startingAtTop: false)
    }

    @MainActor
    func testSearchTransitionKeepsFirstRowBelowNavigationBar() async throws {
        try await checkSearchTransition(startingAtTop: true)
    }

    @MainActor
    func testDetailListSearchPreservesItemGeometry() async throws {
        try await checkSearchTransition(startingAtTop: true, displayMode: .detail)
    }

    @MainActor
    func testScrolledDetailListSearchPreservesVisibleGallery() async throws {
        try await checkSearchTransition(startingAtTop: false, displayMode: .detail)
    }

    @MainActor
    func testShowAllWaterfallSearchPreservesNavigationGeometry() async throws {
        try await checkSearchTransition(startingAtTop: true, route: .frontpage)
    }

    @MainActor
    func testShowAllDetailSearchPreservesNavigationGeometry() async throws {
        try await checkSearchTransition(startingAtTop: true, displayMode: .detail, route: .frontpage)
    }

    @MainActor
    func testPopularTabSearchPreservesVisibleGallery() async throws {
        try await checkSearchTransition(startingAtTop: false, route: .popular)
    }

    private enum SearchTestRoute { case toplists, frontpage, popular }

    @MainActor
    private func checkSearchTransition(
        startingAtTop: Bool, displayMode: ListDisplayMode = .waterfall,
        route: SearchTestRoute = .toplists
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene)
        let window = try XCTUnwrap(scene.keyWindow)
        let previousController = window.rootViewController
        var setting = Setting()
        setting.listDisplayMode = displayMode
        setting.tabBarItems = [.home, .popular, .search]
        let galleries = (0..<80).map { index in
            Gallery(
                gid: "search-test-\(index)", token: "token", title: "Gallery \(index)",
                rating: 4, tags: [], category: .manga, uploader: "Tester", pageCount: 20,
                postedDate: Date(timeIntervalSince1970: 0), coverURL: nil, galleryURL: nil
            )
        }
        var appState = AppReducer.State()
        appState.settingState.setting = setting
        appState.homeState.popularGalleries = Array(galleries.prefix(10))
        appState.homeState.frontpageGalleries = Array(galleries.prefix(20))
        appState.homeState.toplistsGalleries = [11: Array(galleries.prefix(20))]
        appState.homeState.toplistsState.rawGalleries[.yesterday] = galleries
        appState.homeState.frontpageState.galleries = galleries
        appState.homeState.popularState.galleries = galleries
        let store = StoreOf<AppReducer>(initialState: appState) {
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
                if case .home(.setNavigation(let route)) = action {
                    state.homeState.route = route
                }
                if case .tabBar(.setTabBarItemType(let tab)) = action {
                    state.tabBarState.tabBarItemType = tab
                }
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
            window.rootViewController = previousController
        }
        try await Task.sleep(for: .milliseconds(800))
        switch route {
        case .toplists:
            store.send(.home(.setNavigation(.section(.toplists))), animation: .default)
        case .frontpage:
            store.send(.home(.setNavigation(.section(.frontpage))), animation: .default)
        case .popular:
            store.send(.tabBar(.setTabBarItemType(.popular)))
        }
        try await Task.sleep(for: .milliseconds(800))
        let collection = try XCTUnwrap(findSubview(UICollectionView.self, in: host.view))
        let initialOffset: CGFloat = startingAtTop ? -collection.adjustedContentInset.top : 1600
        collection.setContentOffset(CGPoint(x: 0, y: initialOffset), animated: false)
        try await Task.sleep(for: .milliseconds(400))
        let initialVisibleTop = collection.contentOffset.y + collection.adjustedContentInset.top
        let initialFrame = collection.convert(collection.bounds, to: window)
        let firstIndex = IndexPath(item: 0, section: 0)
        let anchorIndex = try XCTUnwrap(collection.indexPathsForVisibleItems.sorted().first)
        let anchorCell = try XCTUnwrap(collection.cellForItem(at: anchorIndex))
        let initialAnchorY = anchorCell.convert(.zero, to: window).y
        let initialCellWidth = collection.collectionViewLayout.layoutAttributesForItem(at: firstIndex)?.size.width
        let initialCellFrames = Dictionary(
            uniqueKeysWithValues: collection.indexPathsForVisibleItems.compactMap { index in
                collection.collectionViewLayout.layoutAttributesForItem(at: index).map { (index, $0.frame) }
            }
        )
        func snapshot(_ name: String) {
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let picture = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
            let attachment = XCTAttachment(image: picture)
            attachment.name = name
            attachment.lifetime = .deleteOnSuccess
            self.add(attachment)
        }
        snapshot("before")
        var visibleTops = [initialVisibleTop]
        let observation = collection.observe(\.contentOffset, options: [.new]) { view, _ in
            visibleTops.append(view.contentOffset.y + view.adjustedContentInset.top)
        }
        defer { observation.invalidate() }
        let search = try XCTUnwrap(findSearchController(in: host))
        XCTAssertTrue(search.hidesNavigationBarDuringPresentation)
        let initialSearchY = search.searchBar.convert(.zero, to: window).y
        let navigationBar = try XCTUnwrap(findSubview(UINavigationBar.self, in: host.view))
        let initialNavigationBottom = navigationBar.convert(navigationBar.bounds, to: window).maxY
        var maximumNavigationTransition: CGFloat = 0
        func renderedFrame(of view: UIView) -> CGRect {
            let layer = view.layer.presentation() ?? view.layer
            return layer.convert(layer.bounds, to: window.layer.presentation() ?? window.layer)
        }
        func recordTransition(_ name: String) async throws {
            var metrics = [String]()
            var maximumSearchMovement: CGFloat = 0
            var maximumGalleryMovement: CGFloat = 0
            var maximumNavigationMovement: CGFloat = 0
            var minimumRenderedBottom = initialFrame.maxY
            var lostVisibleGallery = false
            for frame in 0..<40 {
                try await Task.sleep(for: .milliseconds(16))
                let frameInWindow = collection.convert(collection.bounds, to: window)
                let renderedCollectionFrame = renderedFrame(of: collection)
                minimumRenderedBottom = min(minimumRenderedBottom, renderedCollectionFrame.maxY)
                let searchFrame = renderedFrame(of: search.searchBar)
                maximumSearchMovement = max(maximumSearchMovement, abs(searchFrame.minY - initialSearchY))
                let navigationBottom = renderedFrame(of: navigationBar).maxY
                maximumNavigationMovement = max(
                    maximumNavigationMovement, abs(navigationBottom - initialNavigationBottom)
                )
                if let cell = collection.cellForItem(at: anchorIndex) {
                    // End-state offsets miss jumps that only exist in the navigation animation.
                    let renderedY = cell.layer.presentation()?.convert(
                        .zero, to: window.layer.presentation() ?? window.layer
                    ).y ?? cell.convert(.zero, to: window).y
                    maximumGalleryMovement = max(maximumGalleryMovement, abs(renderedY - initialAnchorY))
                } else {
                    lostVisibleGallery = true
                }
                metrics.append(
                    "\(frame): frame=\(frameInWindow) offset=\(collection.contentOffset.y) "
                    + "inset=\(collection.adjustedContentInset) search=\(searchFrame) rendered=\(renderedCollectionFrame)"
                )
                if frame == 0 || frame == 5 { snapshot("\(name)-frame-\(frame)") }
            }
            let attachment = XCTAttachment(string: metrics.joined(separator: "\n"))
            attachment.name = name
            attachment.lifetime = .deleteOnSuccess
            self.add(attachment)
            // Collapsing the native title/search toolbar may move the viewport,
            // but must not jump to another gallery or uncover the host background.
            maximumNavigationTransition = max(
                maximumNavigationTransition, max(maximumSearchMovement, maximumNavigationMovement)
            )
            XCTAssertLessThanOrEqual(
                maximumGalleryMovement, maximumNavigationTransition + 1,
                "Visible gallery jumped beyond the navigation transition during \(name)"
            )
            XCTAssertGreaterThanOrEqual(
                minimumRenderedBottom, initialFrame.maxY - 1,
                "List uncovered the keyboard background during \(name)"
            )
            XCTAssertFalse(lostVisibleGallery, "Visible gallery disappeared during \(name)")
        }
        for cycle in 0..<3 {
            XCTAssertTrue(search.searchBar.searchTextField.becomeFirstResponder())
            XCTAssertTrue(search.searchBar.searchTextField.isFirstResponder)
            try await recordTransition("activate-\(cycle)")
            XCTAssertTrue(search.isActive)
            XCTAssertLessThan(window.keyboardLayoutGuide.layoutFrame.minY, window.bounds.maxY - 100)
            if !DeviceUtil.isPad {
                XCTAssertLessThan(search.searchBar.convert(.zero, to: window).y, initialSearchY - 1)
            }
            snapshot("focused-\(cycle)")
            XCTAssertTrue(collection === findSubview(UICollectionView.self, in: host.view))
            if DeviceUtil.isPad {
                // The native iPad search presentation doesn't expose a cancel button.
                search.searchBar.searchTextField.resignFirstResponder()
                search.searchBar.delegate?.searchBarCancelButtonClicked?(search.searchBar)
            } else {
                let cancelButton = try XCTUnwrap(findSearchCancelButton(in: search.searchBar))
                cancelButton.sendActions(for: .touchUpInside)
            }
            try await recordTransition("cancel-\(cycle)")
            snapshot("cancelled-\(cycle)")
            XCTAssertFalse(search.isActive)
            XCTAssertFalse(search.searchBar.searchTextField.isFirstResponder)
            XCTAssertTrue(collection === findSubview(UICollectionView.self, in: host.view))
            let finalFrame = collection.convert(collection.bounds, to: window)
            XCTAssertEqual(finalFrame.width, initialFrame.width, accuracy: 0.5)
            XCTAssertEqual(finalFrame.minX, initialFrame.minX, accuracy: 0.5)
            XCTAssertEqual(finalFrame.minY, initialFrame.minY, accuracy: 0.5)
            XCTAssertEqual(
                collection.collectionViewLayout.layoutAttributesForItem(at: firstIndex)?.size.width,
                initialCellWidth
            )
            for (index, initial) in initialCellFrames {
                let final = try XCTUnwrap(collection.collectionViewLayout.layoutAttributesForItem(at: index)?.frame)
                XCTAssertEqual(final.minY, initial.minY, accuracy: 0.5, "Item \(index) moved within the list")
                XCTAssertEqual(final.height, initial.height, accuracy: 0.5, "Item \(index) changed height")
            }
        }
        if startingAtTop {
            XCTAssertLessThanOrEqual(visibleTops.map(abs).max() ?? 0, 1, "Visible tops: \(visibleTops)")
        } else {
            XCTAssertGreaterThan(visibleTops.min() ?? 0, initialVisibleTop - 100, "Visible tops: \(visibleTops)")
            XCTAssertEqual(
                collection.contentOffset.y + collection.adjustedContentInset.top,
                initialVisibleTop, accuracy: 1
            )
        }
    }

    @MainActor
    private func findSearchCancelButton(in view: UIView) -> UIButton? {
        // Exclude the text field's clear button; exercise the system search cancellation action.
        guard !(view is UITextField), !view.isHidden, view.alpha > 0.01 else { return nil }
        if let button = view as? UIButton, button.isEnabled,
           button.allControlEvents.contains(.touchUpInside) {
            return button
        }
        return view.subviews.lazy.compactMap { self.findSearchCancelButton(in: $0) }.first
    }

    @MainActor
    private func findSearchController(in controller: UIViewController) -> UISearchController? {
        if let search = controller.navigationItem.searchController { return search }
        for child in controller.children.reversed() {
            if let search = findSearchController(in: child) { return search }
        }
        return nil
    }

    @MainActor
    private func findSubview<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = findSubview(type, in: child) { return match }
        }
        return nil
    }

    func testThumbnailInformationHeightIsStableAndContentDependent() {
        var shortTitleGallery = Gallery.preview
        shortTitleGallery.title = "Short"
        var longTitleGallery = Gallery.preview
        longTitleGallery.title = String(repeating: "Long title ", count: 12)
        var setting = Setting()
        setting.showsTagsInList = false

        let shortHeight = GalleryThumbnailCell.informationHeight(
            gallery: shortTitleGallery,
            setting: setting,
            availableWidth: 180
        )
        let longHeight = GalleryThumbnailCell.informationHeight(
            gallery: longTitleGallery,
            setting: setting,
            availableWidth: 180
        )

        XCTAssertEqual(
            shortHeight,
            GalleryThumbnailCell.informationHeight(
                gallery: shortTitleGallery,
                setting: setting,
                availableWidth: 180
            )
        )
        XCTAssertGreaterThan(longHeight, shortHeight)
    }

    func testCacheStatusUsesAStableWaterfallHeight() {
        var setting = Setting()
        setting.showsTagsInList = false
        let presentation = GalleryListPresentation(
            coverURL: nil,
            status: GalleryListStatus(
                text: "Downloading",
                detailText: "12 / 30",
                message: nil,
                systemImage: "arrow.down.circle.fill",
                tone: .accent,
                progress: 0.4
            )
        )
        let normalHeight = GalleryThumbnailCell.informationHeight(
            gallery: .preview,
            setting: setting,
            availableWidth: 180
        )
        let cacheHeight = GalleryThumbnailCell.informationHeight(
            gallery: .preview,
            setting: setting,
            availableWidth: 180,
            presentation: presentation
        )

        XCTAssertEqual(
            cacheHeight - normalHeight,
            GalleryThumbnailCell.statusInformationHeight
        )
    }

    func testPlacesItemsInShortestColumnAndBreaksTiesToLeadingColumn() {
        let result = WaterfallLayoutCalculator.calculate(
            containerWidth: 220,
            columnCount: 2,
            spacing: 10,
            sectionInsets: .init(top: 10, left: 10, bottom: 10, right: 10),
            items: [
                .init(height: 100, spansAllColumns: false),
                .init(height: 60, spansAllColumns: false),
                .init(height: 50, spansAllColumns: false),
                .init(height: 30, spansAllColumns: false)
            ]
        )

        XCTAssertEqual(result.frames[0], .init(x: 10, y: 10, width: 95, height: 100))
        XCTAssertEqual(result.frames[1], .init(x: 115, y: 10, width: 95, height: 60))
        XCTAssertEqual(result.frames[2], .init(x: 115, y: 80, width: 95, height: 50))
        XCTAssertEqual(result.frames[3], .init(x: 10, y: 120, width: 95, height: 30))
        XCTAssertEqual(result.contentHeight, 160)
    }

    func testFullWidthItemStartsBelowEveryColumn() {
        let result = WaterfallLayoutCalculator.calculate(
            containerWidth: 220,
            columnCount: 2,
            spacing: 10,
            sectionInsets: .init(top: 10, left: 10, bottom: 10, right: 10),
            items: [
                .init(height: 100, spansAllColumns: false),
                .init(height: 60, spansAllColumns: false),
                .init(height: 50, spansAllColumns: true)
            ]
        )

        XCTAssertEqual(result.frames[2], .init(x: 10, y: 120, width: 200, height: 50))
        XCTAssertEqual(result.contentHeight, 180)
    }

    func testLargeLayoutStaysInsideBoundsWithoutOverlaps() {
        let insets = UIEdgeInsets(top: 8, left: 16, bottom: 16, right: 16)
        let items = (0..<10_000).map { index in
            WaterfallLayoutItem(
                height: CGFloat(80 + (index * 47) % 240),
                spansAllColumns: false
            )
        }
        let result = WaterfallLayoutCalculator.calculate(
            containerWidth: 1024,
            columnCount: 5,
            spacing: 12,
            sectionInsets: insets,
            items: items
        )

        XCTAssertEqual(result.frames.count, items.count)
        for frame in result.frames {
            XCTAssertGreaterThanOrEqual(frame.minX, insets.left)
            XCTAssertLessThanOrEqual(frame.maxX, 1024 - insets.right + 0.001)
        }

        var activeFrames = [CGRect]()
        for frame in result.frames.sorted(by: { $0.minY < $1.minY }) {
            activeFrames.removeAll { $0.maxY <= frame.minY }
            XCTAssertFalse(activeFrames.contains(where: { $0.intersects(frame) }))
            activeFrames.append(frame)
        }
    }

    func testEmptyLayoutHasNoContentHeight() {
        let result = WaterfallLayoutCalculator.calculate(
            containerWidth: 390,
            columnCount: 2,
            spacing: 12,
            sectionInsets: .init(top: 8, left: 12, bottom: 16, right: 12),
            items: []
        )

        XCTAssertTrue(result.frames.isEmpty)
        XCTAssertEqual(result.contentHeight, 0)
    }

    func testInvalidGeometryReturnsEmptyLayout() {
        let item = WaterfallLayoutItem(height: 100, spansAllColumns: false)

        let zeroWidth = WaterfallLayoutCalculator.calculate(
            containerWidth: 0,
            columnCount: 2,
            spacing: 12,
            sectionInsets: .zero,
            items: [item]
        )
        let zeroColumns = WaterfallLayoutCalculator.calculate(
            containerWidth: 390,
            columnCount: 0,
            spacing: 12,
            sectionInsets: .zero,
            items: [item]
        )

        XCTAssertTrue(zeroWidth.frames.isEmpty)
        XCTAssertEqual(zeroWidth.contentHeight, 0)
        XCTAssertTrue(zeroColumns.frames.isEmpty)
        XCTAssertEqual(zeroColumns.contentHeight, 0)
    }

    @MainActor
    func testIncrementalMeasuredHeightRelayoutMatchesFullCalculation() {
        let identifiers = galleryIdentifiers(count: 18) + [.footer]
        var heights = measuredHeights(for: identifiers)
        let harness = WaterfallLayoutHarness(
            identifiers: identifiers,
            measuredHeights: heights
        )
        let stableColumns = columnAssignments(
            identifiers: identifiers,
            layout: harness.layout
        )

        assertLayout(
            harness.layout,
            matches: expectedLayout(
                identifiers: identifiers,
                heights: heights,
                columnAssignments: stableColumns
            )
        )

        heights[.gallery("gallery-1")] = 242
        heights[.gallery("gallery-7")] = 48
        harness.updateMeasuredHeights([
            .gallery("gallery-1"): 242,
            .gallery("gallery-7"): 48
        ])

        assertLayout(
            harness.layout,
            matches: expectedLayout(
                identifiers: identifiers,
                heights: heights,
                columnAssignments: stableColumns
            )
        )
    }

    @MainActor
    func testMeasuredHeightUpdatesKeepGalleryColumnsStable() {
        let identifiers = galleryIdentifiers(count: 12) + [.footer]
        let harness = WaterfallLayoutHarness(
            identifiers: identifiers,
            measuredHeights: [:]
        )
        let originalColumns = Dictionary(
            uniqueKeysWithValues: identifiers.compactMap { identifier in
                harness.layout.indexPath(for: identifier).flatMap {
                    harness.layout.layoutAttributesForItem(at: $0).map {
                        (identifier, $0.frame.minX)
                    }
                }
            }
        )

        var updatedHeights = Dictionary(
            uniqueKeysWithValues: identifiers.enumerated().map { index, identifier in
                (identifier, identifier == .footer ? 50 : CGFloat(40 + index * 17))
            }
        )
        updatedHeights[.gallery("gallery-0")] = 1_200
        harness.updateMeasuredHeights(updatedHeights)

        for identifier in identifiers {
            guard let indexPath = harness.layout.indexPath(for: identifier),
                  let attributes = harness.layout.layoutAttributesForItem(at: indexPath),
                  let originalX = originalColumns[identifier]
            else {
                XCTFail("Missing layout attributes for \(identifier)")
                continue
            }
            XCTAssertEqual(attributes.frame.minX, originalX, accuracy: 0.001)
        }
    }

    @MainActor
    func testSpatialQueryMatchesBruteForceAfterHeightChangesAndAppend() {
        var identifiers = galleryIdentifiers(count: 18) + [.footer]
        var heights = measuredHeights(for: identifiers)
        let harness = WaterfallLayoutHarness(
            identifiers: identifiers,
            measuredHeights: heights
        )
        var stableColumns = columnAssignments(
            identifiers: identifiers,
            layout: harness.layout
        )

        heights[.gallery("gallery-2")] = 260
        heights[.gallery("gallery-9")] = 54
        harness.updateMeasuredHeights([
            .gallery("gallery-2"): 260,
            .gallery("gallery-9"): 54
        ])
        var expected = expectedLayout(
            identifiers: identifiers,
            heights: heights,
            columnAssignments: stableColumns
        )
        assertSpatialQueries(harness.layout, expected: expected)

        identifiers.removeLast()
        let appendedIdentifiers = galleryIdentifiers(in: 18..<24)
        identifiers.append(contentsOf: appendedIdentifiers)
        identifiers.append(.footer)
        heights.merge(measuredHeights(for: appendedIdentifiers)) { _, new in new }
        harness.replaceItems(
            identifiers,
            measuredHeights: Dictionary(
                uniqueKeysWithValues: appendedIdentifiers.map { ($0, heights[$0]!) }
            )
        )
        stableColumns = columnAssignments(
            identifiers: identifiers,
            layout: harness.layout
        )

        expected = expectedLayout(
            identifiers: identifiers,
            heights: heights,
            columnAssignments: stableColumns
        )
        assertLayout(harness.layout, matches: expected)
        assertSpatialQueries(harness.layout, expected: expected)
    }

    @MainActor
    func testDiffableAppendSnapshotAfterLayoutItemsMatchesFullCalculation() {
        var identifiers = galleryIdentifiers(count: 18) + [.footer]
        var heights = measuredHeights(for: identifiers)
        let harness = WaterfallDiffableLayoutHarness(
            identifiers: identifiers,
            measuredHeights: heights
        )

        let appendedIdentifiers = galleryIdentifiers(in: 18..<30)
        identifiers.removeLast()
        identifiers.append(contentsOf: appendedIdentifiers)
        identifiers.append(.footer)
        let appendedHeights = measuredHeights(for: appendedIdentifiers)
        heights.merge(appendedHeights) { _, new in new }

        harness.applyAppendSnapshot(
            identifiers,
            measuredHeights: appendedHeights
        )

        let expected = expectedLayout(
            identifiers: identifiers,
            heights: heights,
            columnAssignments: columnAssignments(
                identifiers: identifiers,
                layout: harness.layout
            )
        )
        assertLayout(harness.layout, matches: expected)
        assertSpatialQueries(harness.layout, expected: expected)
        XCTAssertEqual(harness.itemIdentifiers, identifiers)
    }

    @MainActor
    func testDiffableReplacementSnapshotAfterLayoutItemsMatchesFullCalculation() {
        let initialIdentifiers = galleryIdentifiers(count: 18) + [.footer]
        let replacementIdentifiers =
            (30..<47).map { WaterfallItemID.gallery("replacement-\($0)") }
            + [.footer]
        let replacementHeights = measuredHeights(for: replacementIdentifiers)
        let harness = WaterfallDiffableLayoutHarness(
            identifiers: initialIdentifiers,
            measuredHeights: measuredHeights(for: initialIdentifiers)
        )

        harness.applyReplacementSnapshot(
            replacementIdentifiers,
            measuredHeights: replacementHeights
        )

        let expected = expectedLayout(
            identifiers: replacementIdentifiers,
            heights: replacementHeights,
            columnAssignments: columnAssignments(
                identifiers: replacementIdentifiers,
                layout: harness.layout
            )
        )
        assertLayout(harness.layout, matches: expected)
        assertSpatialQueries(harness.layout, expected: expected)
        XCTAssertEqual(harness.itemIdentifiers, replacementIdentifiers)
    }

    func testDatasetClassifierRecognizesAppendWithinSameDataset() {
        let oldIdentifiers = galleryIdentifiers(count: 3) + [.footer]
        let newIdentifiers = galleryIdentifiers(count: 6) + [.footer]

        XCTAssertEqual(
            WaterfallDatasetUpdateKind.classify(
                oldIdentifiers: oldIdentifiers,
                newIdentifiers: newIdentifiers,
                hasExistingSnapshot: true,
                datasetChanged: false
            ),
            .append
        )
    }

    func testDatasetClassifierRejectsSharedPrefixAcrossDatasets() {
        let oldIdentifiers = galleryIdentifiers(count: 3) + [.footer]
        let newIdentifiers = galleryIdentifiers(count: 6) + [.footer]

        XCTAssertEqual(
            WaterfallDatasetUpdateKind.classify(
                oldIdentifiers: oldIdentifiers,
                newIdentifiers: newIdentifiers,
                hasExistingSnapshot: true,
                datasetChanged: true
            ),
            .replace
        )
    }

    func testDatasetClassifierReplacesIdenticalItemsAfterFullReload() {
        let identifiers = galleryIdentifiers(count: 3) + [.footer]

        XCTAssertEqual(
            WaterfallDatasetUpdateKind.classify(
                oldIdentifiers: identifiers,
                newIdentifiers: identifiers,
                hasExistingSnapshot: true,
                datasetChanged: true
            ),
            .replace
        )
    }

    func testContentCommitGateDefersChangesUntilScrollingAndPendingCommitsFinish() {
        let cases: [(
            contentChanged: Bool,
            isActivelyScrolling: Bool,
            hasPendingCommit: Bool,
            expected: Bool
        )] = [
            (false, false, false, false),
            (false, false, true, true),
            (false, true, false, false),
            (false, true, true, true),
            (true, false, false, false),
            (true, false, true, true),
            (true, true, false, true),
            (true, true, true, true)
        ]

        for testCase in cases {
            XCTAssertEqual(
                WaterfallContentCommitGate.shouldDefer(
                    contentChanged: testCase.contentChanged,
                    isActivelyScrolling: testCase.isActivelyScrolling,
                    hasPendingCommit: testCase.hasPendingCommit
                ),
                testCase.expected
            )
        }

        XCTAssertTrue(
            WaterfallContentCommitGate.shouldDefer(
                contentChanged: false,
                loadingStateChanged: true,
                isActivelyScrolling: true,
                hasPendingCommit: false
            )
        )
    }

    func testRefreshStateMachineWaitsForCommittedContentAfterOperationCompletes() {
        var stateMachine = GalleryRefreshStateMachine()

        XCTAssertTrue(stateMachine.begin())
        XCTAssertEqual(stateMachine.phase, .refreshing)
        XCTAssertFalse(stateMachine.contentDidCommit(isLoading: true, isScrolling: false))
        XCTAssertFalse(stateMachine.operationCompleted(isScrolling: false))
        XCTAssertEqual(stateMachine.phase, .waitingForContent)
        XCTAssertTrue(stateMachine.contentDidCommit(isLoading: false, isScrolling: false))
        XCTAssertEqual(stateMachine.phase, .idle)
    }

    func testRefreshStateMachineWaitsForFastOperationGestureToEnd() {
        var stateMachine = GalleryRefreshStateMachine()

        XCTAssertTrue(stateMachine.begin())
        XCTAssertFalse(stateMachine.operationCompleted(isScrolling: true))
        XCTAssertEqual(stateMachine.phase, .waitingForContent)
        XCTAssertFalse(stateMachine.contentDidCommit(isLoading: false, isScrolling: true))
        XCTAssertEqual(stateMachine.phase, .waitingForScrollEnd)
        XCTAssertTrue(stateMachine.scrollingDidEnd())
        XCTAssertEqual(stateMachine.phase, .idle)
    }

    func testRefreshStateMachineAcceptsContentBeforeOperationCompletes() {
        var stateMachine = GalleryRefreshStateMachine()

        XCTAssertTrue(stateMachine.begin())
        XCTAssertFalse(stateMachine.contentDidCommit(isLoading: true, isScrolling: false))
        XCTAssertFalse(stateMachine.contentDidCommit(isLoading: false, isScrolling: false))
        XCTAssertTrue(stateMachine.operationCompleted(isScrolling: false))
        XCTAssertEqual(stateMachine.phase, .idle)
    }

    func testRefreshStateMachineAcceptsCoalescedTerminalContentUpdate() {
        var stateMachine = GalleryRefreshStateMachine()

        XCTAssertTrue(stateMachine.begin())
        XCTAssertFalse(stateMachine.contentDidCommit(isLoading: false, isScrolling: false))
        XCTAssertTrue(stateMachine.operationCompleted(isScrolling: false))
        XCTAssertEqual(stateMachine.phase, .idle)
    }

    func testRefreshStateMachineAcceptsCoalescedTerminalContentAfterOperationCompletes() {
        var stateMachine = GalleryRefreshStateMachine()

        XCTAssertTrue(stateMachine.begin())
        XCTAssertFalse(stateMachine.operationCompleted(isScrolling: false))
        XCTAssertEqual(stateMachine.phase, .waitingForContent)
        XCTAssertTrue(stateMachine.contentDidCommit(isLoading: false, isScrolling: false))
        XCTAssertEqual(stateMachine.phase, .idle)
    }

    func testRefreshWaitsWhenScrollEndsBeforeDeferredTerminalRevisionCommits() {
        var stateMachine = GalleryRefreshStateMachine()

        XCTAssertTrue(stateMachine.begin())
        XCTAssertFalse(stateMachine.contentDidCommit(isLoading: true, isScrolling: true))
        XCTAssertFalse(stateMachine.operationCompleted(isScrolling: true))
        XCTAssertEqual(stateMachine.phase, .waitingForContent)
        XCTAssertFalse(stateMachine.scrollingDidEnd())
        XCTAssertEqual(stateMachine.phase, .waitingForContent)
        XCTAssertTrue(stateMachine.contentDidCommit(isLoading: false, isScrolling: false))
        XCTAssertEqual(stateMachine.phase, .idle)
    }

    func testRefreshStateMachineRejectsDuplicateRefreshesAndCompletions() {
        var stateMachine = GalleryRefreshStateMachine()

        XCTAssertTrue(stateMachine.begin())
        XCTAssertFalse(stateMachine.begin())
        XCTAssertFalse(stateMachine.operationCompleted(isScrolling: false))
        XCTAssertFalse(stateMachine.operationCompleted(isScrolling: false))
        XCTAssertTrue(stateMachine.contentDidCommit(isLoading: false, isScrolling: false))
        XCTAssertFalse(stateMachine.contentDidCommit(isLoading: false, isScrolling: false))
        XCTAssertFalse(stateMachine.scrollingDidEnd())
    }

    private func galleryIdentifiers(count: Int) -> [WaterfallItemID] {
        galleryIdentifiers(in: 0..<count)
    }

    private func galleryIdentifiers(in range: Range<Int>) -> [WaterfallItemID] {
        range.map { .gallery("gallery-\($0)") }
    }

    private func measuredHeights(
        for identifiers: [WaterfallItemID]
    ) -> [WaterfallItemID: CGFloat] {
        Dictionary(uniqueKeysWithValues: identifiers.enumerated().map { index, identifier in
            let height: CGFloat = identifier == .footer
                ? 50
                : CGFloat(90 + (index * 43) % 170)
            return (identifier, height)
        })
    }

    private func expectedLayout(
        identifiers: [WaterfallItemID],
        heights: [WaterfallItemID: CGFloat],
        columnAssignments: [Int?]? = nil
    ) -> WaterfallLayoutResult {
        WaterfallLayoutCalculator.calculate(
            containerWidth: waterfallTestWidth,
            columnCount: 2,
            spacing: 12,
            sectionInsets: .init(top: 8, left: 12, bottom: 16, right: 12),
            items: identifiers.map {
                WaterfallLayoutItem(
                    height: heights[$0]!,
                    spansAllColumns: $0 == .footer
                )
            },
            columnAssignments: columnAssignments
        )
    }

    private func columnAssignments(
        identifiers: [WaterfallItemID],
        layout: WaterfallCollectionLayout
    ) -> [Int?] {
        identifiers.map { identifier in
            guard identifier != .footer,
                  let indexPath = layout.indexPath(for: identifier),
                  let attributes = layout.layoutAttributesForItem(at: indexPath)
            else { return nil }
            return attributes.frame.midX < waterfallTestWidth / 2 ? 0 : 1
        }
    }

    private func assertLayout(
        _ layout: WaterfallCollectionLayout,
        matches expected: WaterfallLayoutResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let attributes = (0..<expected.frames.count).compactMap {
            layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))
        }
        XCTAssertEqual(attributes.count, expected.frames.count, file: file, line: line)
        for (attribute, expectedFrame) in zip(attributes, expected.frames) {
            assertEqual(attribute.frame, expectedFrame, file: file, line: line)
        }
        XCTAssertEqual(
            layout.collectionViewContentSize.height,
            expected.contentHeight,
            accuracy: 0.001,
            file: file,
            line: line
        )
    }

    private func assertSpatialQueries(
        _ layout: WaterfallCollectionLayout,
        expected: WaterfallLayoutResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var rects = stride(
            from: CGFloat(-256),
            through: expected.contentHeight + 256,
            by: CGFloat(137)
        ).map {
            CGRect(x: 0, y: $0, width: waterfallTestWidth, height: 233)
        }
        rects.append(contentsOf: [
            .init(x: 0, y: 511.75, width: waterfallTestWidth, height: 1),
            .init(x: 0, y: 500, width: waterfallTestWidth, height: 600),
            .init(
                x: 0,
                y: expected.contentHeight / 2,
                width: waterfallTestWidth / 2,
                height: 1_100
            ),
            .init(
                x: waterfallTestWidth / 2,
                y: expected.contentHeight / 3,
                width: waterfallTestWidth / 2,
                height: 900
            ),
            .init(
                x: 0,
                y: -500,
                width: waterfallTestWidth,
                height: expected.contentHeight + 1_000
            ),
            .init(x: 0, y: 0, width: waterfallTestWidth, height: 0)
        ])

        for rect in rects {
            let expectedIndexPaths = Set(expected.frames.enumerated().compactMap { index, frame in
                frame.intersects(rect) ? IndexPath(item: index, section: 0) : nil
            })
            let actualIndexPaths = Set(
                (layout.layoutAttributesForElements(in: rect) ?? []).map(\.indexPath)
            )
            XCTAssertEqual(
                actualIndexPaths,
                expectedIndexPaths,
                "Query rect: \(rect)",
                file: file,
                line: line
            )
        }
    }

    private func assertEqual(
        _ actual: CGRect,
        _ expected: CGRect,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}

@MainActor
private final class WaterfallLayoutHarness {
    let layout = WaterfallCollectionLayout()
    let collectionView: UICollectionView
    private let dataSource: WaterfallLayoutDataSource

    init(
        identifiers: [WaterfallItemID],
        measuredHeights: [WaterfallItemID: CGFloat]
    ) {
        dataSource = .init(itemCount: identifiers.count)
        collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: waterfallTestWidth, height: 844),
            collectionViewLayout: layout
        )
        collectionView.register(
            WaterfallLayoutTestCell.self,
            forCellWithReuseIdentifier: WaterfallLayoutDataSource.reuseIdentifier
        )
        collectionView.dataSource = dataSource

        layout.setItems(
            identifiers,
            estimatedGalleryExtraHeight: 125,
            estimatedFooterHeight: 50
        )
        reloadLayout()
        _ = layout.updateMeasuredHeights(measuredHeights)
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
    }

    func updateMeasuredHeights(_ heights: [WaterfallItemID: CGFloat]) {
        XCTAssertTrue(layout.updateMeasuredHeights(heights))
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
    }

    func replaceItems(
        _ identifiers: [WaterfallItemID],
        measuredHeights: [WaterfallItemID: CGFloat]
    ) {
        dataSource.itemCount = identifiers.count
        layout.setItems(
            identifiers,
            estimatedGalleryExtraHeight: 125,
            estimatedFooterHeight: 50
        )
        _ = layout.updateMeasuredHeights(measuredHeights)
        reloadLayout()
    }

    private func reloadLayout() {
        collectionView.reloadData()
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
    }
}

@MainActor
private final class WaterfallLayoutDataSource: NSObject, UICollectionViewDataSource {
    static let reuseIdentifier = "WaterfallLayoutTestCell"

    var itemCount: Int

    init(itemCount: Int) {
        self.itemCount = itemCount
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        itemCount
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(
            withReuseIdentifier: Self.reuseIdentifier,
            for: indexPath
        )
    }
}

@MainActor
private final class WaterfallDiffableLayoutHarness {
    let layout = WaterfallCollectionLayout()
    let collectionView: UICollectionView
    private var dataSource:
        UICollectionViewDiffableDataSource<Int, WaterfallItemID>!

    var itemIdentifiers: [WaterfallItemID] {
        dataSource.snapshot().itemIdentifiers
    }

    init(
        identifiers: [WaterfallItemID],
        measuredHeights: [WaterfallItemID: CGFloat]
    ) {
        collectionView = UICollectionView(
            frame: .init(
                x: 0,
                y: 0,
                width: waterfallTestWidth,
                height: 844
            ),
            collectionViewLayout: layout
        )
        collectionView.register(
            WaterfallLayoutTestCell.self,
            forCellWithReuseIdentifier: WaterfallLayoutDataSource.reuseIdentifier
        )
        dataSource = UICollectionViewDiffableDataSource<Int, WaterfallItemID>(
            collectionView: collectionView
        ) { collectionView, indexPath, _ in
            collectionView.dequeueReusableCell(
                withReuseIdentifier: WaterfallLayoutDataSource.reuseIdentifier,
                for: indexPath
            )
        }

        layout.setItems(
            identifiers,
            estimatedGalleryExtraHeight: 125,
            estimatedFooterHeight: 50
        )
        var snapshot = NSDiffableDataSourceSnapshot<Int, WaterfallItemID>()
        snapshot.appendSections([0])
        snapshot.appendItems(identifiers)
        dataSource.applySnapshotUsingReloadData(snapshot)
        prepare()
        _ = layout.updateMeasuredHeights(measuredHeights)
        prepare()
    }

    func applyAppendSnapshot(
        _ identifiers: [WaterfallItemID],
        measuredHeights: [WaterfallItemID: CGFloat]
    ) {
        layout.setItems(
            identifiers,
            estimatedGalleryExtraHeight: 125,
            estimatedFooterHeight: 50
        )
        _ = layout.updateMeasuredHeights(measuredHeights)

        var snapshot = NSDiffableDataSourceSnapshot<Int, WaterfallItemID>()
        snapshot.appendSections([0])
        snapshot.appendItems(identifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
        prepare()
    }

    func applyReplacementSnapshot(
        _ identifiers: [WaterfallItemID],
        measuredHeights: [WaterfallItemID: CGFloat]
    ) {
        layout.resetColumnAssignments()
        layout.setItems(
            identifiers,
            estimatedGalleryExtraHeight: 125,
            estimatedFooterHeight: 50
        )
        _ = layout.updateMeasuredHeights(measuredHeights)

        var snapshot = NSDiffableDataSourceSnapshot<Int, WaterfallItemID>()
        snapshot.appendSections([0])
        snapshot.appendItems(identifiers)
        dataSource.applySnapshotUsingReloadData(snapshot)
        prepare()
    }

    private func prepare() {
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
    }
}

private final class WaterfallLayoutTestCell: UICollectionViewCell {
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        layoutAttributes
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

final class FavoritesSearchTests: XCTestCase {
    private func gallery(_ id: String = "favorites-search-test") -> Gallery {
        Gallery(
            gid: id, token: "test", title: "Chinese gallery", rating: 4, tags: [],
            category: .manga, pageCount: 1, postedDate: Date(timeIntervalSince1970: 0),
            coverURL: nil, galleryURL: nil
        )
    }

    @MainActor
    func testEmptySearchResponseReplacesExistingResults() async {
        var state = FavoritesReducer.State()
        state.keyword = "language:japanese"
        state.submittedKeyword = state.keyword
        state.rawGalleries[-1] = [gallery()]
        let revision = state.beginSearch(keyword: nil, sortOrder: nil)
        let store = TestStore(initialState: state) { FavoritesReducer() }
        await store.send(.fetchGalleriesDone(-1, revision, .success((PageNumber(), nil, [])))) {
            $0.activeRequests[-1] = nil
            $0.rawGalleries[-1] = []
            $0.rawLoadingState[-1] = .failed(.notFound)
        }
    }

    func testNewSearchInvalidatesEveryCachedCategoryAndPendingRequest() {
        var state = FavoritesReducer.State()
        state.rawGalleries = [-1: [gallery()], 0: [gallery()], 2: [gallery()]]
        state.rawPageNumber[0] = PageNumber(isNextButtonEnabled: true)
        state.rawFooterLoadingState[0] = .loading
        let oldRevision = state.beginRequest(index: 0)
        let revision = state.beginSearch(keyword: "  language:japanese  ", sortOrder: nil)
        XCTAssertEqual(state.keyword, "language:japanese")
        XCTAssertEqual(state.submittedKeyword, "language:japanese")
        XCTAssertTrue(state.rawGalleries.isEmpty)
        XCTAssertNil(state.rawPageNumber[0])
        XCTAssertNil(state.rawFooterLoadingState[0])
        XCTAssertEqual(state.activeRequests, [-1: revision])
        XCTAssertGreaterThan(revision, oldRevision)
    }

    @MainActor
    func testOldSearchAndPaginationResponsesCannotRestorePreviousResults() async {
        var state = FavoritesReducer.State()
        let oldRevision = state.beginSearch(keyword: "language:chinese", sortOrder: nil)
        _ = state.beginSearch(keyword: "language:japanese", sortOrder: nil)
        let store = TestStore(initialState: state) { FavoritesReducer() }
        await store.send(.fetchGalleriesDone(-1, oldRevision, .success((PageNumber(), nil, [gallery()]))))
        await store.send(.fetchMoreGalleriesDone(-1, oldRevision, .success((PageNumber(), nil, [gallery()]))))
        await store.send(.fetchGalleriesDone(-1, oldRevision, .failure(.parseFailed)))
    }

    func testReplacementRequestHasNewIdentityEvenWithTheSameQuery() {
        var state = FavoritesReducer.State()
        let first = state.beginSearch(keyword: "l:japanese", sortOrder: nil)
        let second = state.beginSearch(keyword: "l:japanese", sortOrder: nil)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(state.activeRequests[-1], second)
    }

    func testClearingSearchInvalidatesFilteredCategories() {
        var state = FavoritesReducer.State()
        _ = state.beginSearch(keyword: "l:chinese", sortOrder: nil)
        state.rawGalleries[1] = [gallery()]
        _ = state.beginSearch(keyword: "", sortOrder: nil)
        XCTAssertTrue(state.rawGalleries.isEmpty)
        XCTAssertEqual(state.submittedKeyword, "")
    }

    func testSortChangeInvalidatesCachedCategories() {
        var state = FavoritesReducer.State()
        state.sortOrder = .favoritedTime
        state.rawGalleries[0] = [gallery()]
        _ = state.beginSearch(keyword: nil, sortOrder: .lastUpdateTime)
        XCTAssertTrue(state.rawGalleries.isEmpty)
        XCTAssertEqual(state.sortOrder, .lastUpdateTime)
    }

    func testPaginationUsesSubmittedQueryAndServerCursorNotTheDraftOrOldGallery() throws {
        var state = FavoritesReducer.State()
        state.submittedKeyword = "language:chinese"
        state.keyword = "language:japanese"
        state.rawGalleries[2] = [gallery("old-gallery")]
        state.rawPageNumber[2] = PageNumber(
            lastItemTimestamp: "1234", nextGalleryID: "5678", isNextButtonEnabled: true
        )
        let request = try XCTUnwrap(state.paginationRequest(index: 2))
        XCTAssertEqual(request.favIndex, 2)
        XCTAssertEqual(request.keyword, "language:chinese")
        XCTAssertEqual(request.lastID, "5678")
        XCTAssertEqual(request.lastTimestamp, "1234")
        state.rawLoadingState[2] = .loading
        XCTAssertNil(state.paginationRequest(index: 2))
    }

    func testEmptyFilteredPageRetainsServerPaginationCursor() throws {
        let document = try Kanna.HTML(html: """
        <html><body><div class="searchnav">
        <a href="https://example.com/favorites.php?next=5678-1234">Next &gt;</a>
        </div></body></html>
        """, encoding: .utf8)
        let page = Parser.parsePageNum(doc: document)
        XCTAssertTrue(try Parser.parseGalleries(doc: document).isEmpty)
        XCTAssertEqual(page.nextGalleryID, "5678")
        XCTAssertEqual(page.lastItemTimestamp, "1234")
        var state = FavoritesReducer.State()
        state.rawGalleries[-1] = []
        state.rawPageNumber[-1] = page
        XCTAssertNotNil(state.paginationRequest(index: -1))
    }

    func testFavoritesURLsPreserveLanguageSearchOnFirstAndFollowingPages() throws {
        let keyword = "l:japanese$"
        let urls = [
            URLUtil.favoritesList(favIndex: 2, keyword: keyword),
            URLUtil.moreFavoritesList(favIndex: 2, lastID: "5678", lastTimestamp: "1234", keyword: keyword)
        ]
        for url in urls {
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(items.first { $0.name == "f_search" }?.value, keyword)
            XCTAssertEqual(items.first { $0.name == "favcat" }?.value, "2")
            XCTAssertEqual(items.first { $0.name == "st" }?.value, "on")
        }
        XCTAssertEqual(TagNamespace.language.abbreviation, "l")
    }
}

final class NavigationLayoutSettingTests: XCTestCase {
    @Observable
    final class EditorDraft {
        var setting = Setting()
    }

    @MainActor
    func testPhoneSearchTabRespectsCustomOrder() async throws {
        guard !DeviceUtil.isPad else { throw XCTSkip("Phone-specific tab ordering") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        var state = AppReducer.State()
        state.settingState.setting.tabBarItems = [.home, .search, .popular, .favorites]
        state.tabBarState.tabBarItemType = .more
        let store = Store(initialState: state) {
            Reduce<AppReducer.State, AppReducer.Action> { state, action in
                if case let .setNavigationItems(tabs) = action {
                    state.settingState.setting.tabBarItems = tabs
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

        store.send(.setNavigationItems([.popular, .search, .favorites]))
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(
            controller.tabBar.items?.map(\.title),
            [AppNavigationItem.popular, .search, .favorites, .more].map(\.title)
        )
    }

    @MainActor
    private func findTabController(in controller: UIViewController) -> UITabBarController? {
        if let tabController = controller as? UITabBarController { return tabController }
        return controller.children.lazy.compactMap { self.findTabController(in: $0) }.first
    }

    func testDefaultLayoutHasFourShortcutsAndAll() {
        XCTAssertEqual(Setting().phoneTabItems, [.home, .search, .favorites, .cache, .more])
        XCTAssertEqual(Setting().availableTabItems, [.popular, .watched, .history])
    }

    func testLegacyDefaultsAdoptNewDefaults() throws {
        for json in ["{}", #"{"tabBarItems":["search"]}"#] {
            let setting = try JSONDecoder().decode(Setting.self, from: Data(json.utf8))
            XCTAssertEqual(setting.tabBarItems, AppNavigationItem.defaultTabItems)
        }
    }

    func testLegacyCustomOrderPreservesImplicitHomeAndAllChoices() throws {
        let json = #"{"tabBarItems":["popular","search","history"],"moreItems":["cache","favorites","watched"]}"#
        let setting = try JSONDecoder().decode(Setting.self, from: Data(json.utf8))
        XCTAssertEqual(setting.tabBarItems, [.home, .popular, .search, .history])
        XCTAssertEqual(setting.availableTabItems, [.watched, .favorites, .cache])
    }

    func testLegacyEmptyLayoutRetainsOnlyHome() throws {
        let setting = try JSONDecoder().decode(Setting.self, from: Data(#"{"tabBarItems":[]}"#.utf8))
        XCTAssertEqual(setting.phoneTabItems, [.home, .more])
    }

    func testCurrentLayoutsRoundTripWithoutAddingHomeOrResettingSearch() throws {
        for items: [AppNavigationItem] in [[], [.search], [.cache, .search, .history]] {
            var setting = Setting()
            setting.tabBarItems = items
            let decoded = try JSONDecoder().decode(Setting.self, from: JSONEncoder().encode(setting))
            XCTAssertEqual(decoded.tabBarItems, items)
        }
    }

    func testFullBarRequiresExplicitReplacement() {
        var setting = Setting()
        XCTAssertFalse(setting.addNavigationItem(.popular))
        XCTAssertEqual(setting.tabBarItems, AppNavigationItem.defaultTabItems)
        XCTAssertTrue(setting.addNavigationItem(.popular, replacing: .search))
        XCTAssertEqual(setting.tabBarItems, [.home, .popular, .favorites, .cache])
    }

    func testInvalidReplacementAndDuplicateLeaveLayoutUnchanged() {
        var setting = Setting()
        XCTAssertFalse(setting.addNavigationItem(.cache, replacing: .home))
        XCTAssertFalse(setting.addNavigationItem(.popular, replacing: .history))
        XCTAssertFalse(setting.addNavigationItem(.more, replacing: .home))
        XCTAssertFalse(setting.addNavigationItem(.setting, replacing: .home))
        XCTAssertEqual(setting.tabBarItems, AppNavigationItem.defaultTabItems)
    }

    func testHomeAndSearchAreOrdinaryRemovableAndReorderableItems() {
        var setting = Setting()
        setting.tabBarItems = []
        XCTAssertTrue(setting.addNavigationItem(.search))
        XCTAssertTrue(setting.addNavigationItem(.home))
        setting.tabBarItems.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(setting.phoneTabItems, [.home, .search, .more])
        setting.tabBarItems.remove(atOffsets: IndexSet(integer: 0))
        XCTAssertEqual(setting.phoneTabItems, [.search, .more])
    }

    func testNormalizationRepairsDuplicatesInvalidItemsAndOverflow() {
        var setting = Setting()
        setting.tabBarItems = [.home, .setting, .search, .search, .popular, .watched, .history, .more]
        setting.normalizeNavigationItems()
        XCTAssertEqual(setting.tabBarItems, [.home, .search, .popular, .watched])
        XCTAssertEqual(setting.availableTabItems, [.history, .favorites, .cache])
    }

    @MainActor
    func testAllCatalogDestinationsRemainReachableWithEveryPinConfiguration() {
        for pins: [AppNavigationItem] in [[], [.search], AppNavigationItem.defaultTabItems] {
            var state = AppReducer.State()
            state.settingState.setting.tabBarItems = pins
            for item in AppNavigationItem.allCases {
                state.navigateToSection(item)
                if pins.contains(item) || item == .more {
                    XCTAssertEqual(state.tabBarState.tabBarItemType, item)
                    XCTAssertNil(state.moreState.route)
                } else {
                    XCTAssertEqual(state.tabBarState.tabBarItemType, .more)
                    XCTAssertEqual(state.moreState.route, item)
                }
            }
        }
    }

    @MainActor
    func testRemovingSelectedTabPreservesItsDestinationInAll() {
        var state = AppReducer.State()
        state.settingState.setting.tabBarItems = [.search]
        state.reconcileNavigationSelection(usesNativeTabs: false)
        XCTAssertEqual(state.tabBarState.tabBarItemType, .more)
        XCTAssertEqual(state.moreState.route, .home)
        state.navigateToSection(.search)
        state.reconcileNavigationSelection(usesNativeTabs: false)
        XCTAssertEqual(state.tabBarState.tabBarItemType, .search)
        XCTAssertNil(state.moreState.route)
    }

    @MainActor
    func testPhoneCustomizationDoesNotAffectIPadSelectionOrDefaults() {
        var state = AppReducer.State()
        state.settingState.setting.tabBarItems = []
        state.navigateToSection(.setting, usesNativeTabs: true)
        state.reconcileNavigationSelection(usesNativeTabs: true)
        XCTAssertEqual(state.tabBarState.tabBarItemType, .setting)
        XCTAssertNil(state.moreState.route)
        XCTAssertEqual(AppNavigationItem.home.defaultTabBarVisibility, .visible)
        XCTAssertEqual(AppNavigationItem.search.defaultTabBarVisibility, .visible)
        XCTAssertEqual(AppNavigationItem.cache.defaultTabBarVisibility, .visible)
        XCTAssertEqual(AppNavigationItem.setting.defaultTabBarVisibility, .hidden)
    }

    @MainActor
    func testStartupUsesFirstPinnedTabWithoutOverwritingPendingNavigation() {
        var state = AppReducer.State()
        state.settingState.setting.tabBarItems = [.cache, .search]
        state.restoreInitialNavigationSelection(usesNativeTabs: false)
        XCTAssertEqual(state.tabBarState.tabBarItemType, .cache)
        state.navigateToSection(.search)
        state.restoreInitialNavigationSelection(usesNativeTabs: false)
        XCTAssertEqual(state.tabBarState.tabBarItemType, .search)
        state.navigateToSection(.home)
        state.restoreInitialNavigationSelection(usesNativeTabs: false)
        XCTAssertEqual(state.moreState.route, .home)
        state.navigateToSection(.more)
        state.settingState.setting.tabBarItems = []
        state.restoreInitialNavigationSelection(usesNativeTabs: false)
        XCTAssertEqual(state.tabBarState.tabBarItemType, .more)
        XCTAssertNil(state.moreState.route)
    }

    func testPreviouslyHiddenIPadSidebarItemsBecomeReachableAgain() {
        var customization = TabViewCustomization()
        for item in AppNavigationItem.iPadItems {
            customization[tab: item.customizationID].sidebarVisibility = .hidden
        }
        let normalized = customization.preservingFullNavigationSidebar()
        for item in AppNavigationItem.iPadItems {
            XCTAssertEqual(normalized[tab: item.customizationID].sidebarVisibility, .visible)
        }
    }

    @MainActor
    func testUnpinnedHomeReusesAllNavigationStack() async throws {
        guard !DeviceUtil.isPad else { throw XCTSkip("Phone All catalog") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        var state = AppReducer.State()
        state.settingState.setting.tabBarItems = [.search]
        state.tabBarState.tabBarItemType = .more
        let store = Store(initialState: state) {
            Reduce<AppReducer.State, AppReducer.Action> { state, action in
                if case let .navigateToSection(item) = action { state.navigateToSection(item) }
                if case let .home(.setNavigation(route)) = action { state.homeState.route = route }
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
        try await Task.sleep(for: .milliseconds(500))
        store.send(.navigateToSection(.home))
        try await Task.sleep(for: .milliseconds(600))
        let tabs = try XCTUnwrap(findTabController(in: host))
        let selected = try XCTUnwrap(tabs.selectedViewController)
        func navigationControllers(in controller: UIViewController) -> [UINavigationController] {
            (controller as? UINavigationController).map { [$0] } ?? controller.children.flatMap {
                navigationControllers(in: $0)
            }
        }
        let navigation = try XCTUnwrap(navigationControllers(in: selected).first)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertTrue(navigationControllers(in: try XCTUnwrap(navigation.topViewController)).isEmpty)
        store.send(.home(.setNavigation(.section(.frontpage))))
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(navigation.viewControllers.count, 3)
    }

    @MainActor
    func testEditorUpdatesEditingControlsWithoutReopening() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let draft = EditorDraft()
        draft.setting.tabBarItems = [.home, .search, .favorites]
        let host = UIHostingController(rootView: NavigationStack {
            NavigationItemsEditorList(
                draft: Binding(get: { draft.setting }, set: { draft.setting = $0 }),
                pendingItem: .constant(nil)
            )
        })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        func descendants(of view: UIView) -> [UIView] {
            [view] + view.subviews.flatMap { descendants(of: $0) }
        }
        @discardableResult
        func checkControls(_ name: String, capture: Bool = false) async throws -> UICollectionView {
            try await Task.sleep(for: .milliseconds(300))
            let list = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? UICollectionView }.first)
            XCTAssertEqual(list.numberOfItems(inSection: 0), draft.setting.tabBarItems.count, name)
            XCTAssertEqual(list.numberOfItems(inSection: 2), draft.setting.availableTabItems.count, name)
            for section in 0..<list.numberOfSections {
                for item in 0..<list.numberOfItems(inSection: section) {
                    let indexPath = IndexPath(item: item, section: section)
                    list.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
                    list.layoutIfNeeded()
                    let cell = try XCTUnwrap(list.cellForItem(at: indexPath) as? UICollectionViewListCell)
                    XCTAssertEqual(cell.accessories.count, section == 0 ? 2 : 0, "\(name): \(indexPath)")
                    if section == 0 {
                        XCTAssertTrue(cell.configurationState.isEditing,
                                      "\(name): pinned item \(item) must enter edit mode immediately")
                    }
                }
            }
            if capture {
                list.setContentOffset(CGPoint(x: 0, y: -list.adjustedContentInset.top), animated: false)
                let screenshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                })
                screenshot.name = name
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            return list
        }
        try await checkControls("Before adding")
        XCTAssertTrue(draft.setting.addNavigationItem(.popular))
        try await checkControls("After adding", capture: true)
        XCTAssertTrue(draft.setting.addNavigationItem(.history, replacing: .search))
        try await checkControls("After replacement")
        draft.setting.tabBarItems.remove(at: 3)
        try await checkControls("After removal")
        XCTAssertTrue(draft.setting.addNavigationItem(.popular))
        let listBeforeReordering = try await checkControls("After re-adding")
        draft.setting.tabBarItems.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        let listAfterReordering = try await checkControls("After reordering")
        XCTAssertTrue(listBeforeReordering === listAfterReordering, "Reordering must not rebuild the list")
        draft.setting.tabBarItems = []
        try await checkControls("After removing all")
        XCTAssertTrue(draft.setting.addNavigationItem(.cache))
        try await checkControls("After first addition to empty list")
        draft.setting.tabBarItems = AppNavigationItem.defaultTabItems
        try await checkControls("After restoring defaults", capture: true)
    }

    @MainActor
    func testEditorRendersAtCompactWidthAndAccessibilityTextSize() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: NavigationItemsEditor(
            tabBarItems: AppNavigationItem.defaultTabItems,
            onSave: { _ in XCTFail("Rendering must not save changes") }
        ).environment(\.dynamicTypeSize, .xxxLarge))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(500))
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        attachment.name = "Navigation editor large text"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testIPadNativeTabPlacementAndSidebarCatalog() async throws {
        guard DeviceUtil.isPad else { throw XCTSkip("iPad native customization") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        var state = AppReducer.State()
        state.settingState.setting.tabBarItems = []
        state.tabBarState.tabBarItemType = .search
        let store = Store(initialState: state) {
            Reduce<AppReducer.State, AppReducer.Action> { _, _ in .none }
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
        let initialScreenshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        initialScreenshot.name = "iPad initial tabs"
        initialScreenshot.lifetime = .keepAlways
        add(initialScreenshot)
        // SwiftUI 26 uses legacy viewControllers; SwiftUI 27 exposes UITab objects.
        if controller.tabs.isEmpty {
            XCTAssertEqual(
                Set(controller.viewControllers?.compactMap { $0.tabBarItem.title } ?? []),
                Set(AppNavigationItem.iPadItems.map(\.title))
            )
        } else {
            XCTAssertEqual(Set(controller.tabs.map(\.title)), Set(AppNavigationItem.iPadItems.map(\.title)))
            XCTAssertFalse(controller.tabs.contains { $0 is UISearchTab })
            for item in AppNavigationItem.iPadItems {
                let tab = try XCTUnwrap(controller.tabs.first { $0.title == item.title })
                XCTAssertFalse(tab.isHidden, "\(item) must remain in the sidebar")
                XCTAssertFalse(tab.allowsHiding)
                if item == .setting {
                    XCTAssertEqual(tab.preferredPlacement, .sidebarOnly)
                } else {
                    XCTAssertTrue(
                        [UITab.Placement.automatic, .default, .optional].contains(tab.preferredPlacement),
                        "\(item) has unexpected placement \(tab.preferredPlacement.rawValue)"
                    )
                }
            }
        }
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        attachment.name = "iPad native tabs"
        attachment.lifetime = .keepAlways
        add(attachment)

        host.traitOverrides.horizontalSizeClass = .compact
        try await Task.sleep(for: .milliseconds(600))
        let compactController = try XCTUnwrap(findTabController(in: host))
        let compactScreenshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        compactScreenshot.name = "iPad compact tabs"
        compactScreenshot.lifetime = .keepAlways
        add(compactScreenshot)
        XCTAssertFalse(compactController.tabBar.items?.isEmpty ?? true)
        XCTAssertEqual(compactController.tabBar.items?.last?.title, compactController.moreNavigationController.tabBarItem.title)
        let compactTitles = compactController.tabs.isEmpty
            ? compactController.viewControllers?.compactMap { $0.tabBarItem.title } ?? []
            : compactController.tabs.map(\.title)
        XCTAssertEqual(Set(compactTitles), Set(AppNavigationItem.iPadItems.map(\.title)))
        XCTAssertTrue(compactTitles.contains(AppNavigationItem.setting.title),
                      "Settings must remain reachable through native overflow in compact windows")
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
