//
//  WaterfallLayoutTests.swift
//  EhPandaTests
//

import UIKit
import XCTest
@testable import EhPanda

private let waterfallTestWidth: CGFloat = 390

final class WaterfallLayoutTests: XCTestCase {
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
