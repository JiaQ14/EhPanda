//
//  WaterfallLayoutTests.swift
//  EhPandaTests
//

import UIKit
import XCTest
@testable import EhPanda

private let waterfallTestWidth: CGFloat = 390

final class WaterfallLayoutTests: XCTestCase {
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

final class NavigationLayoutSettingTests: XCTestCase {
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
