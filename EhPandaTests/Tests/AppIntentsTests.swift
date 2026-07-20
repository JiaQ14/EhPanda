//
//  AppIntentsTests.swift
//  EhPandaTests
//

import XCTest
import CoreSpotlight
@testable import EhPanda

final class AppIntentsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = "AppIntentsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        _ = AppIntentNavigationStore.shared.consume()
        defaults = nil
        super.tearDown()
    }

    func testNavigationRoutePersistsAcrossStoreInstancesAndIsConsumedOnce() {
        let writer = AppIntentNavigationStore(defaults: defaults)
        let reader = AppIntentNavigationStore(defaults: defaults)
        let route = AppIntentRoute.gallery(gid: "12345", readingProgress: 17)

        writer.enqueue(route)

        XCTAssertEqual(reader.consume(), route)
        XCTAssertNil(reader.consume())
    }

    func testNewestNavigationRouteReplacesAnUnconsumedRoute() {
        let store = AppIntentNavigationStore(defaults: defaults)

        store.enqueue(.section(.cache))
        store.enqueue(.search("artist:example"))

        XCTAssertEqual(store.consume(), .search("artist:example"))
    }

    func testMalformedNavigationRouteIsDiscarded() {
        let store = AppIntentNavigationStore(defaults: defaults)
        let key = "appIntent.pendingNavigationRoute"
        defaults.set(Data("not-json".utf8), forKey: key)

        XCTAssertNil(store.consume())
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testSearchIntentTrimsTextAndQueuesSearchRoute() async throws {
        _ = AppIntentNavigationStore.shared.consume()

        _ = try await SearchGalleriesIntent(query: "  artist:example  ").perform()

        XCTAssertEqual(
            AppIntentNavigationStore.shared.consume(),
            .search("artist:example")
        )
    }

    func testBlankSearchIntentDoesNotQueueNavigation() async throws {
        _ = AppIntentNavigationStore.shared.consume()

        _ = try await SearchGalleriesIntent(query: "  \n ").perform()

        XCTAssertNil(AppIntentNavigationStore.shared.consume())
    }

    func testOpenSectionIntentQueuesRequestedSection() async throws {
        _ = AppIntentNavigationStore.shared.consume()

        _ = try await OpenSectionIntent(section: .cache).perform()

        XCTAssertEqual(
            AppIntentNavigationStore.shared.consume(),
            .section(.cache)
        )
    }

    @MainActor
    func testLegacySettingsKeepSystemIntegrationsDisabled() throws {
        var setting = Setting()
        setting.enablesSystemContentSearch = true
        setting.displaysCoversInSystemSearch = true
        setting.enablesVisualSearch = true
        let encoded = try JSONEncoder().encode(setting)
        var legacyJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyJSON.removeValue(forKey: "enablesSystemContentSearch")
        legacyJSON.removeValue(forKey: "displaysCoversInSystemSearch")
        legacyJSON.removeValue(forKey: "enablesVisualSearch")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        let decoded = try JSONDecoder().decode(Setting.self, from: legacyData)

        XCTAssertFalse(decoded.enablesSystemContentSearch)
        XCTAssertFalse(decoded.displaysCoversInSystemSearch)
        XCTAssertFalse(decoded.enablesVisualSearch)
    }

    func testSearchTextExtractorPrefersTitlesAndFiltersInterfaceText() {
        let queries = GallerySearchTextExtractor.queries(from: [
            .init(text: "Read", confidence: 0.99, isTitle: true),
            .init(text: " A Manga Title! ", confidence: 0.81, isTitle: true),
            .init(text: "A Manga Title", confidence: 0.78, isTitle: false),
            .init(text: "作者 名称", confidence: 0.92, isTitle: false),
            .init(text: "x", confidence: 0.99, isTitle: true),
            .init(text: "Low confidence", confidence: 0.1, isTitle: true)
        ])

        XCTAssertEqual(queries, ["A Manga Title", "作者 名称"])
    }

    func testVisualSearchRankerRewardsRelatedTitlesAndExactImages() {
        let related = GalleryVisualSearchRanker.textScore(
            title: "A Manga Title Vol. 2",
            queries: ["A Manga Title"]
        )
        let unrelated = GalleryVisualSearchRanker.textScore(
            title: "Completely Different",
            queries: ["A Manga Title"]
        )

        XCTAssertEqual(
            GalleryVisualSearchRanker.textScore(
                title: "Exact Title",
                queries: ["Exact Title"]
            ),
            1
        )
        XCTAssertGreaterThan(related, unrelated)
        XCTAssertGreaterThan(
            GalleryVisualSearchRanker.combinedScore(text: related, imageDistance: 0),
            GalleryVisualSearchRanker.combinedScore(text: related, imageDistance: 10)
        )
    }

    func testVisualSearchOutputOpensBestMatchBeforeFallingBackToText() {
        let entity = GalleryEntity(gallery: makeGallery())

        XCTAssertEqual(
            VisualGallerySearchOutput(
                query: "recognized title",
                entities: [entity]
            ).navigationRoute,
            .gallery(gid: entity.id, readingProgress: nil)
        )
        XCTAssertEqual(
            VisualGallerySearchOutput(
                query: "recognized title",
                entities: []
            ).navigationRoute,
            .search("recognized title")
        )
        XCTAssertEqual(
            VisualGallerySearchOutput(query: "", entities: []).navigationRoute,
            .section(.search)
        )
    }

    func testVisualSearchImageLoaderReadsLocalCoverFiles() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EhPandaVisualSearch-\(UUID().uuidString).data")
        let expected = Data("local-cover".utf8)
        try expected.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let data = await GalleryVisualSearchImageLoader.data(
            from: fileURL,
            session: .shared
        )

        XCTAssertEqual(data, expected)
    }

    func testEntityMergeKeepsRecentOrderAndUsesCachedLocalCover() {
        var recent = GalleryEntity(gallery: makeGallery())
        recent.coverURL = URL(string: "https://example.com/remote.webp")
        var cached = recent
        let localCover = FileManager.default.temporaryDirectory
            .appendingPathComponent("cached-cover.webp")
        cached.coverURL = localCover

        let entities = IntentGalleryService.merging(
            primary: [recent],
            cached: [cached]
        )

        XCTAssertEqual(entities.map(\.id), [recent.id])
        XCTAssertEqual(entities.first?.coverURL, localCover)
    }

    func testSpotlightItemHasStableIdentifierAndSearchableMetadata() {
        let entity = GalleryEntity(gallery: makeGallery())

        let item = entity.searchableItem(includesCover: false)

        XCTAssertEqual(
            GalleryEntity.galleryID(fromSpotlightIdentifier: item.uniqueIdentifier),
            entity.id
        )
        XCTAssertEqual(item.domainIdentifier, GalleryEntity.spotlightDomainIdentifier)
        XCTAssertEqual(item.attributeSet.title, entity.title)
        XCTAssertEqual(item.attributeSet.displayName, entity.title)
        XCTAssertTrue(item.attributeSet.keywords?.contains(entity.id) == true)
        XCTAssertNil(item.attributeSet.thumbnailURL)
        XCTAssertEqual(item.expirationDate, .distantFuture)
    }

    func testSpotlightIdentifierRejectsUnrelatedAndEmptyValues() {
        XCTAssertNil(GalleryEntity.galleryID(fromSpotlightIdentifier: "unrelated:123"))
        XCTAssertNil(GalleryEntity.galleryID(fromSpotlightIdentifier: "gallery:"))
        XCTAssertNil(GalleryEntity.galleryID(fromSpotlightIdentifier: "gallery:not-a-number"))
        XCTAssertEqual(
            GalleryEntity.galleryID(fromSpotlightIdentifier: "gallery:12345"),
            "12345"
        )
    }

    @MainActor
    func testSpotlightSynchronizationSkipsUnchangedSnapshots() async {
        let recorder = SystemSearchIndexRecorder()
        let entity = GalleryEntity(gallery: makeGallery())
        let service = makeSystemSearchService(recorder: recorder) { [entity] in
            [entity]
        }
        var setting = Setting()
        setting.enablesSystemContentSearch = true

        await service.synchronize(using: setting)
        await service.synchronize(using: setting)

        let operations = await recorder.recordedOperations()
        XCTAssertEqual(operations, [
            .delete,
            .index([GalleryEntity.spotlightIdentifier(for: entity.id)])
        ])
    }

    @MainActor
    func testDisablingSpotlightWinsOverInFlightEnableSynchronization() async throws {
        let recorder = SystemSearchIndexRecorder()
        let gate = AsyncGate()
        let entity = GalleryEntity(gallery: makeGallery())
        let service = makeSystemSearchService(recorder: recorder) {
            await gate.wait()
            return [entity]
        }
        var enabledSetting = Setting()
        enabledSetting.enablesSystemContentSearch = true
        var disabledSetting = enabledSetting
        disabledSetting.enablesSystemContentSearch = false

        let enabling = Task { await service.synchronize(using: enabledSetting) }
        await gate.waitUntilBlocked()
        let disabling = Task { await service.synchronize(using: disabledSetting) }
        try await Task.sleep(for: .milliseconds(30))
        await gate.open()
        await enabling.value
        await disabling.value

        let operations = await recorder.recordedOperations()
        XCTAssertEqual(operations.last, .delete)
    }

    @MainActor
    func testDisablingSpotlightDuringDeletionSkipsStaleIndexWrite() async throws {
        let deleteGate = AsyncGate()
        let recorder = SystemSearchIndexRecorder(firstDeleteGate: deleteGate)
        let entity = GalleryEntity(gallery: makeGallery())
        let service = makeSystemSearchService(recorder: recorder) { [entity] in
            [entity]
        }
        var enabledSetting = Setting()
        enabledSetting.enablesSystemContentSearch = true
        var disabledSetting = enabledSetting
        disabledSetting.enablesSystemContentSearch = false

        let enabling = Task { await service.synchronize(using: enabledSetting) }
        await deleteGate.waitUntilBlocked()
        let disabling = Task { await service.synchronize(using: disabledSetting) }
        try await Task.sleep(for: .milliseconds(30))
        await deleteGate.open()
        await enabling.value
        await disabling.value

        let operations = await recorder.recordedOperations()
        XCTAssertEqual(operations, [.delete, .delete])
    }

    func testSpotlightIndexStoresAndReturnsSearchableItem() async throws {
        guard CSSearchableIndex.isIndexingAvailable() else {
            throw XCTSkip("Spotlight indexing is unavailable.")
        }

        let token = "EhPandaSpotlight\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let gallery = Gallery(
            gid: token,
            token: "",
            title: token,
            rating: 0,
            tags: [],
            category: .manga,
            uploader: "Spotlight Test",
            pageCount: 1,
            postedDate: .now,
            coverURL: nil,
            galleryURL: nil
        )
        let item = GalleryEntity(gallery: gallery).searchableItem(includesCover: false)
        let index = CSSearchableIndex.default()

        try await index.indexSearchableItems([item])
        do {
            let results = try await spotlightItems(
                matching: "title == \"\(token)\"c"
            )
            XCTAssertTrue(results.contains { $0.uniqueIdentifier == item.uniqueIdentifier })
        } catch {
            try? await index.deleteSearchableItems(withIdentifiers: [item.uniqueIdentifier])
            throw error
        }
        try await index.deleteSearchableItems(withIdentifiers: [item.uniqueIdentifier])
    }

    private func spotlightItems(matching queryString: String) async throws -> [CSSearchableItem] {
        try await withCheckedThrowingContinuation { continuation in
            let query = CSSearchQuery(queryString: queryString, queryContext: nil)
            var items = [CSSearchableItem]()
            query.foundItemsHandler = { items.append(contentsOf: $0) }
            query.completionHandler = { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: items)
                }
            }
            query.start()
        }
    }

    private func makeSystemSearchService(
        recorder: SystemSearchIndexRecorder,
        entityProvider: @escaping @Sendable () async -> [GalleryEntity]
    ) -> SystemSearchIndexService {
        SystemSearchIndexService(
            entityProvider: entityProvider,
            indexClient: .init(
                isAvailable: { true },
                deleteGalleryItems: { await recorder.recordDelete() },
                indexItems: { await recorder.recordIndex($0) }
            )
        )
    }

    private func makeGallery(
        gid: String = "12345",
        title: String = "App Intents Test Gallery"
    ) -> Gallery {
        Gallery(
            gid: gid,
            token: "",
            title: title,
            rating: 0,
            tags: [],
            category: .manga,
            uploader: "Test Uploader",
            pageCount: 10,
            postedDate: .now,
            coverURL: nil,
            galleryURL: nil
        )
    }
}

private actor SystemSearchIndexRecorder {
    enum Operation: Equatable {
        case delete
        case index([String])
    }

    private var operations = [Operation]()
    private let firstDeleteGate: AsyncGate?
    private var hasBlockedDelete = false

    init(firstDeleteGate: AsyncGate? = nil) {
        self.firstDeleteGate = firstDeleteGate
    }

    func recordDelete() async {
        operations.append(.delete)
        if !hasBlockedDelete, let firstDeleteGate {
            hasBlockedDelete = true
            await firstDeleteGate.wait()
        }
    }

    func recordIndex(_ items: [CSSearchableItem]) {
        operations.append(.index(items.map(\.uniqueIdentifier)))
    }

    func recordedOperations() -> [Operation] {
        operations
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilBlocked() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
