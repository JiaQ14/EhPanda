//
//  CacheClient.swift
//  EhPanda
//

import Foundation
import ImageIO
import BackgroundTasks
import Kanna
import ComposableArchitecture

struct CacheClient {
    let items: () async -> [GalleryCacheItem]
    let updates: () async -> AsyncStream<[GalleryCacheItem]>
    let refresh: () async -> Void
    let item: (String) async -> GalleryCacheItem?
    let enqueue: (Gallery, GalleryDetail, CacheDownloadOptions) async -> Void
    let pause: (String) async -> Void
    let pauseAll: () async -> Void
    let resume: (String, CacheDownloadOptions) async -> Void
    let resumeAll: (CacheDownloadOptions) async -> Void
    let restoreInterrupted: (CacheDownloadOptions) async -> Void
    let delete: (String) async -> Void
    let deleteAll: () async -> Void
    let invalidatePage: (String, Int, UUID, UUID) async -> Void
    let localImageSnapshot: (String) async -> GalleryCacheImageSnapshot
}

extension CacheClient {
    static let live: Self = .init(
        items: { await GalleryCacheManager.shared.allItems() },
        updates: { await GalleryCacheManager.shared.updates() },
        refresh: { await GalleryCacheManager.shared.refresh() },
        item: { await GalleryCacheManager.shared.item(gid: $0) },
        enqueue: {
            let operation = await GalleryCacheManager.shared.enqueue(
                gallery: $0,
                detail: $1,
                options: $2
            )
            await startUserInitiatedCacheOperation(operation)
        },
        pause: {
            let operationID = await GalleryCacheManager.shared.pause(gid: $0)
            if let operationID {
                await GalleryCacheBackgroundTaskCoordinator.shared.cancel(
                    operationID: operationID
                )
            }
        },
        pauseAll: {
            let operationIDs = await GalleryCacheManager.shared.pauseAll()
            await GalleryCacheBackgroundTaskCoordinator.shared.cancel(
                operationIDs: operationIDs
            )
        },
        resume: {
            let operation = await GalleryCacheManager.shared.resume(gid: $0, options: $1)
            await startUserInitiatedCacheOperation(operation)
        },
        resumeAll: {
            let operations = await GalleryCacheManager.shared.resumeAll(options: $0)
            await startUserInitiatedCacheOperations(operations)
        },
        restoreInterrupted: { await GalleryCacheManager.shared.restoreInterrupted(options: $0) },
        delete: {
            let operationID = await GalleryCacheManager.shared.delete(gid: $0)
            if let operationID {
                await GalleryCacheBackgroundTaskCoordinator.shared.cancel(
                    operationID: operationID
                )
            }
        },
        deleteAll: {
            let operationIDs = await GalleryCacheManager.shared.deleteAll()
            await GalleryCacheBackgroundTaskCoordinator.shared.cancel(
                operationIDs: operationIDs
            )
        },
        invalidatePage: {
            await GalleryCacheManager.shared.invalidatePage(
                gid: $0,
                index: $1,
                directoryIdentifier: $2,
                pageIdentifier: $3
            )
        },
        localImageSnapshot: {
            await GalleryCacheManager.shared.localImageSnapshot(gid: $0)
        }
    )

    static let noop: Self = .init(
        items: { [] },
        updates: { AsyncStream { $0.finish() } },
        refresh: {},
        item: { _ in nil },
        enqueue: { _, _, _ in },
        pause: { _ in },
        pauseAll: {},
        resume: { _, _ in },
        resumeAll: { _ in },
        restoreInterrupted: { _ in },
        delete: { _ in },
        deleteAll: {},
        invalidatePage: { _, _, _, _ in },
        localImageSnapshot: { _ in .empty }
    )
}

enum CacheClientKey: DependencyKey {
    static let liveValue = CacheClient.live
    static let previewValue = CacheClient.noop
    static let testValue = CacheClient.noop
}

extension DependencyValues {
    var cacheClient: CacheClient {
        get { self[CacheClientKey.self] }
        set { self[CacheClientKey.self] = newValue }
    }
}

private struct GalleryCacheOperation {
    let gid: String
    let id: UUID
    let options: CacheDownloadOptions
}

private enum GalleryCacheOperationEvent {
    case progress(GalleryCacheItem)
    case finished(success: Bool)
}

private func startUserInitiatedCacheOperation(
    _ operation: GalleryCacheOperation?
) async {
    guard let operation else { return }
    await startUserInitiatedCacheOperations([operation])
}

private func startUserInitiatedCacheOperations(
    _ operations: [GalleryCacheOperation]
) async {
    guard !operations.isEmpty else { return }
    let fallbackOperations = await GalleryCacheBackgroundTaskCoordinator.shared.submit(
        operations
    )
    for operation in fallbackOperations {
        await GalleryCacheManager.shared.activate(operation)
    }
}

private enum GalleryCacheManagerError: Error {
    case invalidMetadata
    case page(index: Int, underlying: Error)
}

struct JHenTaiCacheImporter {
    private static let metadataFileName = "metadata"
    private static let imageExtensions = Set([
        "jpg", "jpeg", "png", "gif", "webp", "avif"
    ])

    static func importItem(
        from directoryURL: URL,
        maximumMetadataByteCount: Int
    ) -> GalleryCacheItem? {
        let metadataURL = directoryURL.appendingPathComponent(metadataFileName)
        guard let metadataValues = try? metadataURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        ),
              metadataValues.isRegularFile == true,
              metadataValues.isSymbolicLink != true,
              let metadataSize = metadataValues.fileSize,
              metadataSize > 0,
              metadataSize <= maximumMetadataByteCount,
              let data = try? Data(contentsOf: metadataURL, options: .mappedIfSafe),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: data),
              metadata.gallery.gid > 0,
              GalleryCacheItem.isValidPageCount(metadata.gallery.pageCount)
        else { return nil }

        let gid = String(metadata.gallery.gid)
        let category = category(from: metadata.gallery.category)
        let postedDate = date(from: metadata.gallery.publishTime) ?? .now
        let createdDate =
            date(from: metadata.gallery.insertTime)
            ?? (try? directoryURL.resourceValues(forKeys: [.creationDateKey]).creationDate)
            ?? postedDate
        let updatedDate =
            (try? directoryURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate)
            ?? createdDate
        let galleryURL =
            metadata.gallery.galleryURL.flatMap(URL.init(string:))
            ?? URL(
                string: "https://e-hentai.org/g/\(gid)/\(metadata.gallery.token)/"
            )
        let uploader = metadata.gallery.uploader ?? ""
        let pageFiles = pageFiles(
            in: directoryURL,
            pageCount: metadata.gallery.pageCount
        )
        let remoteURLs = remoteImageURLs(
            metadata.images,
            pageCount: metadata.gallery.pageCount,
            excluding: Set(pageFiles.keys),
            original: false
        )
        let originalURLs = remoteImageURLs(
            metadata.images,
            pageCount: metadata.gallery.pageCount,
            excluding: Set(pageFiles.keys),
            original: true
        )
        let gallery = Gallery(
            gid: gid,
            token: metadata.gallery.token,
            title: metadata.gallery.title,
            rating: 0,
            tags: [],
            category: category,
            uploader: uploader,
            pageCount: metadata.gallery.pageCount,
            postedDate: postedDate,
            coverURL: nil,
            galleryURL: galleryURL
        )
        let detail = GalleryDetail(
            gid: gid,
            title: metadata.gallery.title,
            isFavorited: false,
            visibility: .yes,
            rating: 0,
            userRating: 0,
            ratingCount: 0,
            category: category,
            language: .japanese,
            uploader: uploader,
            postedDate: postedDate,
            coverURL: nil,
            favoritedCount: 0,
            pageCount: metadata.gallery.pageCount,
            sizeCount: 0,
            sizeType: "",
            torrentCount: 0
        )
        let hasAllPages = pageFiles.count == metadata.gallery.pageCount
        return GalleryCacheItem(
            gallery: gallery,
            detail: detail,
            folderName: directoryURL.lastPathComponent,
            pageCount: metadata.gallery.pageCount,
            createdDate: createdDate,
            directoryIdentifier: UUID(),
            status: hasAllPages ? .completed : .paused,
            imageQuality: metadata.gallery.downloadOriginalImage == true
                ? .original
                : .standard,
            updatedDate: updatedDate,
            byteCount: byteCount(of: pageFiles, in: directoryURL),
            errorDescription: nil,
            coverFileName: pageFiles.sorted(by: { $0.key < $1.key }).first?.value,
            pageFiles: pageFiles,
            pageIdentifiers: Dictionary(
                uniqueKeysWithValues: pageFiles.keys.map { ($0, UUID()) }
            ),
            remoteImageURLs: remoteURLs,
            originalImageURLs: originalURLs
        )
    }
}

private extension JHenTaiCacheImporter {
    struct Metadata: Decodable {
        let gallery: GalleryMetadata
        let images: [ImageMetadata?]

        enum CodingKeys: String, CodingKey {
            case gallery
            case images
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            gallery = try container.decode(GalleryMetadata.self, forKey: .gallery)
            if let encodedImages = try? container.decode(String.self, forKey: .images),
               let data = encodedImages.data(using: .utf8)
            {
                images = (try? JSONDecoder().decode([ImageMetadata?].self, from: data)) ?? []
            } else {
                images = (try? container.decode([ImageMetadata?].self, forKey: .images)) ?? []
            }
        }
    }

    struct GalleryMetadata: Decodable {
        let gid: Int
        let token: String
        let title: String
        let category: String
        let pageCount: Int
        let galleryURL: String?
        let uploader: String?
        let publishTime: String?
        let insertTime: String?
        let downloadOriginalImage: Bool?

        enum CodingKeys: String, CodingKey {
            case gid
            case token
            case title
            case category
            case pageCount
            case galleryURL = "galleryUrl"
            case uploader
            case publishTime
            case insertTime
            case downloadOriginalImage
        }
    }

    struct ImageMetadata: Decodable {
        let url: String?
        let originalImageURL: String?

        enum CodingKeys: String, CodingKey {
            case url
            case originalImageURL = "originalImageUrl"
        }
    }

    static func pageFiles(
        in directoryURL: URL,
        pageCount: Int
    ) -> [Int: String] {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var pageFiles = [Int: String]()
        let sortedFileURLs = fileURLs.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                == .orderedAscending
        }
        for fileURL in sortedFileURLs {
            let fileExtension = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(fileExtension),
                  let serialNumber = Int(
                    fileURL.deletingPathExtension().lastPathComponent
                  ),
                  (0..<pageCount).contains(serialNumber),
                  pageFiles[serialNumber + 1] == nil,
                  let values = try? fileURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                  ),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true
            else { continue }
            pageFiles[serialNumber + 1] = fileURL.lastPathComponent
        }
        return pageFiles
    }

    static func remoteImageURLs(
        _ images: [ImageMetadata?],
        pageCount: Int,
        excluding localIndices: Set<Int>,
        original: Bool
    ) -> [Int: URL] {
        var urls = [Int: URL]()
        for (offset, image) in images.prefix(pageCount).enumerated() {
            let index = offset + 1
            guard !localIndices.contains(index),
                  let string = original ? image?.originalImageURL : image?.url,
                  let url = URL(string: string),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil
            else { continue }
            urls[index] = url
        }
        return urls
    }

    static func category(from value: String) -> Category {
        let normalized = value
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Category.allCases.first {
            $0.rawValue.caseInsensitiveCompare(normalized) == .orderedSame
        } ?? .misc
    }

    static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: value) {
            return date
        }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    static func byteCount(
        of pageFiles: [Int: String],
        in directoryURL: URL
    ) -> Int64 {
        pageFiles.values.reduce(into: 0) { count, fileName in
            let url = directoryURL.appendingPathComponent(fileName)
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            count += Int64(fileSize)
        }
    }
}

private final class DownloadedCachePage: @unchecked Sendable {
    let index: Int
    let sourceURL: URL
    let response: URLResponse
    let temporaryFileURL: URL
    let byteCount: Int64
    let typeIdentifier: String?

    init(
        index: Int,
        sourceURL: URL,
        response: URLResponse,
        temporaryFileURL: URL,
        byteCount: Int64,
        typeIdentifier: String?
    ) {
        self.index = index
        self.sourceURL = sourceURL
        self.response = response
        self.temporaryFileURL = temporaryFileURL
        self.byteCount = byteCount
        self.typeIdentifier = typeIdentifier
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryFileURL)
    }
}

private struct GalleryCacheTask {
    let generation: UUID
    let operationID: UUID
    let options: CacheDownloadOptions
    let task: Task<Void, Never>
}

private struct ManagedCacheDirectory {
    let url: URL
    let directoryIdentifier: UUID
    let fileResourceIdentifier: AnyHashable?
    let createdByCurrentManager: Bool
}

private enum ManagedCacheDirectoryResolution {
    case target(ManagedCacheDirectory)
    case gone
    case conflict
}

private actor GalleryCacheManager {
    static let shared = GalleryCacheManager()
    private static let maximumManifestByteCount = 16 * 1024 * 1024

    private var didLoadItems = false
    private var storedItems = [String: GalleryCacheItem]()
    private var tasks = [String: GalleryCacheTask]()
    private var retiringGIDs = Set<String>()
    private var preemptingGIDs = Set<String>()
    private var prioritizedOperationIDs = Set<UUID>()
    private var pendingGIDs = [String]()
    private var pendingOptions = [String: CacheDownloadOptions]()
    private var operationIDsByGID = [String: UUID]()
    private var operationGIDsByID = [UUID: String]()
    private var operationOutcomes = [UUID: Bool]()
    private var discardedOutcomeOperationIDs = Set<UUID>()
    private var operationContinuations = [
        UUID: [UUID: AsyncStream<GalleryCacheOperationEvent>.Continuation]
    ]()
    private var localImageURLsByGID = [String: [Int: URL]]()
    private var managedDirectoriesByGID = [String: [URL: ManagedCacheDirectory]]()
    private var needsRefresh = false
    private var continuations = [UUID: AsyncStream<[GalleryCacheItem]>.Continuation]()

    func allItems() -> [GalleryCacheItem] {
        loadItemsIfNeeded()
        return sortedItems
    }

    func item(gid: String) -> GalleryCacheItem? {
        loadItemsIfNeeded()
        return storedItems[gid]
    }

    func item(for operation: GalleryCacheOperation) -> GalleryCacheItem? {
        loadItemsIfNeeded()
        guard operationIDsByGID[operation.gid] == operation.id,
              operationGIDsByID[operation.id] == operation.gid,
              operationOutcomes[operation.id] == nil,
              let item = storedItems[operation.gid],
              item.status == .queued
        else { return nil }
        return item
    }

    func items(
        for operations: [GalleryCacheOperation]
    ) -> [(GalleryCacheOperation, GalleryCacheItem)] {
        loadItemsIfNeeded()
        var operationIDs = Set<UUID>()
        return operations.compactMap { operation in
            guard operationIDs.insert(operation.id).inserted,
                  let item = item(for: operation)
            else { return nil }
            return (operation, item)
        }
    }

    func discardOperationOutcomes(operationIDs: Set<UUID>) {
        for operationID in operationIDs {
            if operationOutcomes.removeValue(forKey: operationID) == nil,
               operationGIDsByID[operationID] != nil
            {
                discardedOutcomeOperationIDs.insert(operationID)
            }
        }
    }

    func localImageSnapshot(gid: String) -> GalleryCacheImageSnapshot {
        loadItemsIfNeeded()
        guard let item = storedItems[gid] else { return .empty }
        guard (try? verifiedDirectoryURL(gid: gid)) != nil else {
            if tasks.isEmpty {
                refresh()
            } else {
                needsRefresh = true
            }
            return .empty
        }
        let storedURLs = localImageURLsByGID[gid] ?? [:]
        let storedPageIdentifiers = item.pageIdentifiers ?? [:]
        let indices = Set(storedURLs.keys).intersection(storedPageIdentifiers.keys)
        return .init(
            directoryIdentifier: item.directoryIdentifier,
            pageIdentifiers: storedPageIdentifiers.filter { indices.contains($0.key) },
            urls: storedURLs.filter { indices.contains($0.key) }
        )
    }

    func updates() -> AsyncStream<[GalleryCacheItem]> {
        loadItemsIfNeeded()
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation
            continuation.yield(sortedItems)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    func operationUpdates(
        for operation: GalleryCacheOperation
    ) -> AsyncStream<GalleryCacheOperationEvent> {
        loadItemsIfNeeded()
        let continuationID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            var currentItem: GalleryCacheItem?
            if operationIDsByGID[operation.gid] == operation.id,
               let item = storedItems[operation.gid]
            {
                currentItem = item
                continuation.yield(.progress(item))
            }
            if let success = operationOutcomes.removeValue(forKey: operation.id) {
                continuation.yield(.finished(success: success))
                continuation.finish()
                return
            }
            if currentItem?.isComplete == true {
                continuation.yield(.finished(success: true))
                continuation.finish()
                return
            }
            guard operationGIDsByID[operation.id] == operation.gid else {
                continuation.yield(.finished(success: false))
                continuation.finish()
                return
            }
            operationContinuations[operation.id, default: [:]][continuationID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeOperationContinuation(
                        operationID: operation.id,
                        continuationID: continuationID
                    )
                }
            }
        }
    }

    func refresh() {
        loadItemsIfNeeded()
        guard tasks.isEmpty,
              pendingGIDs.isEmpty,
              operationGIDsByID.isEmpty
        else {
            needsRefresh = true
            return
        }
        storedItems.removeAll()
        localImageURLsByGID.removeAll()
        managedDirectoriesByGID.removeAll()
        didLoadItems = false
        loadItemsIfNeeded()
        publish()
    }

    func enqueue(
        gallery: Gallery,
        detail: GalleryDetail,
        options: CacheDownloadOptions
    ) -> GalleryCacheOperation? {
        loadItemsIfNeeded()
        if var item = storedItems[gallery.id] {
            guard isValidMetadata(item), !item.isComplete else { return nil }
            if item.pageFiles.isEmpty {
                item.imageQuality = options.imageQuality
                storedItems[gallery.id] = item
            }
            return prepareOperation(
                gid: gallery.id,
                options: optionsForExistingItem(item, fallback: options)
            )
        }

        let pageCount = detail.pageCount > 0 ? detail.pageCount : gallery.pageCount
        guard isValidGalleryID(gallery.id),
              detail.gid == gallery.id,
              GalleryCacheItem.isValidPageCount(pageCount)
        else { return nil }
        var cachedGallery = gallery
        cachedGallery.pageCount = pageCount
        let now = Date()
        let item = GalleryCacheItem(
            gallery: cachedGallery,
            detail: detail,
            folderName: availableFolderName(
                gid: cachedGallery.id,
                title: detail.jpnTitle ?? detail.title
            ),
            pageCount: pageCount,
            createdDate: now,
            directoryIdentifier: UUID(),
            status: .queued,
            imageQuality: options.imageQuality,
            updatedDate: now,
            byteCount: 0,
            errorDescription: nil,
            coverFileName: nil,
            pageFiles: [:],
            pageIdentifiers: [:],
            remoteImageURLs: [:],
            originalImageURLs: [:]
        )
        storedItems[gallery.id] = item
        localImageURLsByGID[gallery.id] = [:]
        return prepareOperation(gid: gallery.id, options: options)
    }

    @discardableResult
    func pause(gid: String, expectedOperationID: UUID? = nil) -> UUID? {
        loadItemsIfNeeded()
        if let expectedOperationID,
           operationIDsByGID[gid] != expectedOperationID
        {
            return nil
        }
        guard var item = storedItems[gid], item.status.isActive else { return nil }
        let operationID = operationIDsByGID[gid]
        item.status = .paused
        item.updatedDate = .now
        storedItems[gid] = item
        removePending(gid: gid)
        preemptingGIDs.remove(gid)
        let runningOperationID = tasks[gid]?.operationID
        if let cacheTask = tasks[gid], cacheTask.operationID == operationID {
            retiringGIDs.insert(gid)
            cacheTask.task.cancel()
        }
        if let error = persist(gid: gid) {
            recordPersistenceFailure(error, gid: gid)
        }
        publish()
        if let operationID, runningOperationID != operationID {
            finishOperation(operationID, success: false)
        }
        scheduleNext()
        return operationID
    }

    func resume(gid: String, options: CacheDownloadOptions) -> GalleryCacheOperation? {
        loadItemsIfNeeded()
        guard let item = storedItems[gid], isValidMetadata(item), !item.isComplete else {
            return nil
        }
        return prepareOperation(
            gid: gid,
            options: optionsForExistingItem(item, fallback: options)
        )
    }

    @discardableResult
    func pauseAll() -> [UUID] {
        loadItemsIfNeeded()
        let activeIDs = storedItems.values.filter(\.status.isActive).map(\.id)
        let operationIDs = activeIDs.compactMap { operationIDsByGID[$0] }
        let runningOperationIDs = Set(tasks.values.map(\.operationID))
        pendingGIDs.removeAll()
        pendingOptions.removeAll()
        preemptingGIDs.removeAll()
        for (gid, cacheTask) in tasks {
            retiringGIDs.insert(gid)
            cacheTask.task.cancel()
        }
        for gid in activeIDs {
            guard var item = storedItems[gid] else { continue }
            item.status = .paused
            item.updatedDate = .now
            storedItems[gid] = item
            if let error = persist(gid: gid) {
                recordPersistenceFailure(error, gid: gid)
            }
        }
        publish()
        for operationID in operationIDs where !runningOperationIDs.contains(operationID) {
            finishOperation(operationID, success: false)
        }
        return operationIDs
    }

    func resumeAll(options: CacheDownloadOptions) -> [GalleryCacheOperation] {
        loadItemsIfNeeded()
        let items = storedItems.values.filter {
            isValidMetadata($0) && !$0.isComplete && !$0.status.isActive
        }.sorted { $0.updatedDate < $1.updatedDate }
        return items.compactMap { item in
            prepareOperation(
                gid: item.id,
                options: optionsForExistingItem(item, fallback: options)
            )
        }
    }

    func restoreInterrupted(options: CacheDownloadOptions) {
        loadItemsIfNeeded()
        let items = storedItems.values.filter {
            isValidMetadata($0) && !$0.isComplete && $0.status == .paused
        }.sorted { $0.updatedDate < $1.updatedDate }
        for item in items {
            let options = optionsForExistingItem(item, fallback: options)
            if let operation = prepareOperation(gid: item.id, options: options) {
                activate(operation)
            }
        }
    }

    func invalidatePage(
        gid: String,
        index: Int,
        directoryIdentifier: UUID,
        pageIdentifier: UUID
    ) {
        loadItemsIfNeeded()
        guard var item = storedItems[gid],
              item.directoryIdentifier == directoryIdentifier,
              item.pageIdentifiers?[index] == pageIdentifier,
              (1...item.pageCount).contains(index),
              item.pageFiles[index] != nil
        else { return }

        if let directoryURL = try? verifiedDirectoryURL(gid: gid),
           let fileURL = localImageURLsByGID[gid]?[index],
           fileURL.deletingLastPathComponent() == directoryURL
        {
            try? FileManager.default.removeItem(at: fileURL)
        }
        item.pageFiles.removeValue(forKey: index)
        item.pageIdentifiers?.removeValue(forKey: index)
        localImageURLsByGID[gid]?.removeValue(forKey: index)
        if item.status == .completed {
            item.status = .paused
        }
        item.byteCount = byteCount(of: item)
        item.updatedDate = .now
        storedItems[gid] = item
        if let error = persist(gid: gid) {
            recordPersistenceFailure(error, gid: gid)
        }
        publish()
    }

    @discardableResult
    func delete(gid: String) -> UUID? {
        loadItemsIfNeeded()
        let operationID = operationIDsByGID.removeValue(forKey: gid)
        let runningOperationID = tasks[gid]?.operationID
        removePending(gid: gid)
        preemptingGIDs.remove(gid)
        if let task = tasks[gid]?.task {
            retiringGIDs.insert(gid)
            task.cancel()
        }
        let managedDirectories = managedDirectoriesByGID[gid].map {
            Array($0.values)
        } ?? []
        let didRemoveAll = removeManagedDirectories(managedDirectories, gid: gid)
        if didRemoveAll {
            storedItems.removeValue(forKey: gid)
            localImageURLsByGID.removeValue(forKey: gid)
            managedDirectoriesByGID.removeValue(forKey: gid)
        } else if var item = storedItems[gid] {
            item.status = .failed
            item.errorDescription = CocoaError(.fileWriteNoPermission).localizedDescription
            item.updatedDate = .now
            storedItems[gid] = item
            needsRefresh = true
        }
        publish()
        if let operationID, runningOperationID != operationID {
            finishOperation(operationID, success: false)
        }
        performDeferredRefreshIfPossible()
        scheduleNext()
        return operationID
    }

    @discardableResult
    func deleteAll() -> [UUID] {
        loadItemsIfNeeded()
        let operationIDs = Array(operationIDsByGID.values)
        let runningOperationIDs = Set(tasks.values.map(\.operationID))
        operationIDsByGID.removeAll()
        pendingGIDs.removeAll()
        pendingOptions.removeAll()
        preemptingGIDs.removeAll()
        for (gid, cacheTask) in tasks {
            retiringGIDs.insert(gid)
            cacheTask.task.cancel()
        }
        for gid in Array(storedItems.keys) {
            let managedDirectories = managedDirectoriesByGID[gid].map {
                Array($0.values)
            } ?? []
            let didRemoveAll = removeManagedDirectories(managedDirectories, gid: gid)
            if didRemoveAll {
                storedItems.removeValue(forKey: gid)
                localImageURLsByGID.removeValue(forKey: gid)
                managedDirectoriesByGID.removeValue(forKey: gid)
            } else if var item = storedItems[gid] {
                item.status = .failed
                item.errorDescription = CocoaError(.fileWriteNoPermission).localizedDescription
                item.updatedDate = .now
                storedItems[gid] = item
                needsRefresh = true
            }
        }
        prepareRootDirectory()
        publish()
        for operationID in operationIDs where !runningOperationIDs.contains(operationID) {
            finishOperation(operationID, success: false)
        }
        performDeferredRefreshIfPossible()
        return operationIDs
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func removeOperationContinuation(
        operationID: UUID,
        continuationID: UUID
    ) {
        operationContinuations[operationID]?.removeValue(forKey: continuationID)
        if operationContinuations[operationID]?.isEmpty == true {
            operationContinuations.removeValue(forKey: operationID)
        }
    }

    private var sortedItems: [GalleryCacheItem] {
        storedItems.values.sorted { lhs, rhs in
            let lhsRank = statusRank(lhs.status)
            let rhsRank = statusRank(rhs.status)
            return lhsRank == rhsRank
                ? lhs.updatedDate > rhs.updatedDate
                : lhsRank < rhsRank
        }
    }

    private func statusRank(_ status: GalleryCacheStatus) -> Int {
        switch status {
        case .queued, .resolving, .downloading:
            return 0
        case .paused, .failed:
            return 1
        case .completed:
            return 2
        }
    }

    private func publish() {
        let items = sortedItems
        continuations.values.forEach { $0.yield(items) }
        for (operationID, subscribers) in operationContinuations {
            guard operationOutcomes[operationID] == nil,
                  let gid = operationGIDsByID[operationID],
                  operationIDsByGID[gid] == operationID,
                  let item = storedItems[gid]
            else { continue }
            subscribers.values.forEach { $0.yield(.progress(item)) }
        }
    }

    private func finishOperation(_ operationID: UUID, success: Bool) {
        guard operationGIDsByID[operationID] != nil else { return }
        let wasPrioritized = prioritizedOperationIDs.remove(operationID) != nil
        let shouldDiscardOutcome = discardedOutcomeOperationIDs.remove(operationID) != nil
        if let subscribers = operationContinuations.removeValue(forKey: operationID) {
            subscribers.values.forEach {
                $0.yield(.finished(success: success))
                $0.finish()
            }
        } else if wasPrioritized && !shouldDiscardOutcome {
            operationOutcomes[operationID] = success
        }
        operationGIDsByID.removeValue(forKey: operationID)
        performDeferredRefreshIfPossible()
    }

    private func performDeferredRefreshIfPossible() {
        guard needsRefresh,
              tasks.isEmpty,
              pendingGIDs.isEmpty,
              operationGIDsByID.isEmpty
        else { return }
        needsRefresh = false
        refresh()
    }

    private func loadItemsIfNeeded() {
        guard !didLoadItems else { return }
        didLoadItems = true
        guard let rootURL = prepareRootDirectory(),
              let directories = try? FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileResourceIdentifierKey
                ],
                options: [.skipsHiddenFiles]
              )
        else { return }

        for directoryURL in directories {
            guard let resourceValues = try? directoryURL.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileResourceIdentifierKey
                ]
            ),
                  resourceValues.isDirectory == true,
                  resourceValues.isSymbolicLink != true
            else { continue }

            let decodedItem: GalleryCacheItem
            let importedFromJHenTai: Bool
            if let item = decodedCacheItem(from: directoryURL) {
                decodedItem = item
                importedFromJHenTai = false
            } else if let item = JHenTaiCacheImporter.importItem(
                from: directoryURL,
                maximumMetadataByteCount: Self.maximumManifestByteCount
            ),
                      isValidMetadata(item)
            {
                decodedItem = item
                importedFromJHenTai = true
            } else {
                continue
            }

            var item = decodedItem
            item.folderName = directoryURL.lastPathComponent
            if item.directoryIdentifier == nil {
                item.directoryIdentifier = UUID()
            }
            item.remoteImageURLs = item.remoteImageURLs.filter {
                isValidRemoteURL($0.value) && (1...item.pageCount).contains($0.key)
            }
            item.originalImageURLs = item.originalImageURLs.filter {
                isValidRemoteURL($0.value) && (1...item.pageCount).contains($0.key)
            }
            item.pageFiles = validatedPageFiles(item)
            var pageIdentifiers = item.pageIdentifiers?.filter {
                item.pageFiles[$0.key] != nil
            } ?? [:]
            for index in item.pageFiles.keys where pageIdentifiers[index] == nil {
                pageIdentifiers[index] = UUID()
            }
            item.pageIdentifiers = pageIdentifiers
            item.remoteImageURLs = item.remoteImageURLs.filter {
                item.pageFiles[$0.key] == nil
            }
            item.originalImageURLs = item.originalImageURLs.filter {
                item.pageFiles[$0.key] == nil
            }
            if let coverFileURL = item.coverFileURL {
                if !FileManager.default.fileExists(atPath: coverFileURL.path) {
                    item.coverFileName = nil
                }
            } else {
                item.coverFileName = nil
            }
            item.byteCount = byteCount(of: item)
            if item.status.isActive {
                item.status = .paused
            }
            if item.hasAllPages {
                item.status = .completed
                item.errorDescription = nil
                item.remoteImageURLs.removeAll()
                item.originalImageURLs.removeAll()
            } else if item.status == .completed {
                item.status = .paused
            }

            guard let directoryIdentifier = item.directoryIdentifier else { continue }
            let standardizedDirectoryURL = directoryURL.standardizedFileURL
            managedDirectoriesByGID[item.id, default: [:]][standardizedDirectoryURL] = .init(
                url: standardizedDirectoryURL,
                directoryIdentifier: directoryIdentifier,
                fileResourceIdentifier: resourceValues.fileResourceIdentifier as? AnyHashable,
                createdByCurrentManager: false
            )
            removeStalePartialFiles(in: standardizedDirectoryURL)
            if importedFromJHenTai || item != decodedItem {
                try? writeManifest(item, to: standardizedDirectoryURL)
            }

            let shouldUseItem: Bool
            if let existing = storedItems[item.id] {
                shouldUseItem = item.cachedPageCount > existing.cachedPageCount
                    || (
                        item.cachedPageCount == existing.cachedPageCount
                            && item.updatedDate > existing.updatedDate
                    )
            } else {
                shouldUseItem = true
            }
            if shouldUseItem {
                storedItems[item.id] = item
                localImageURLsByGID[item.id] = item.localImageURLs
            }
        }

    }

    private func decodedCacheItem(from directoryURL: URL) -> GalleryCacheItem? {
        let manifestURL = directoryURL.appendingPathComponent(
            GalleryCacheItem.manifestFileName
        )
        guard let manifestValues = try? manifestURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        ),
              manifestValues.isRegularFile == true,
              manifestValues.isSymbolicLink != true,
              let manifestSize = manifestValues.fileSize,
              manifestSize > 0,
              manifestSize <= Self.maximumManifestByteCount,
              let data = try? Data(contentsOf: manifestURL, options: .mappedIfSafe)
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let item = try? decoder.decode(GalleryCacheItem.self, from: data),
              isValidMetadata(item)
        else { return nil }
        return item
    }

    @discardableResult
    private func prepareRootDirectory() -> URL? {
        guard var rootURL = FileUtil.prepareGalleryCachesDirectoryURL() else { return nil }
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? rootURL.setResourceValues(resourceValues)
        return rootURL
    }

    @discardableResult
    private func persist(gid: String) -> Error? {
        do {
            guard prepareRootDirectory() != nil,
                  let item = storedItems[gid],
                  isValidMetadata(item)
            else { throw GalleryCacheManagerError.invalidMetadata }
            let directoryURL = try writableDirectoryURL(gid: gid, item: item)
            try writeManifest(item, to: directoryURL)
            return nil
        } catch {
            return error
        }
    }

    private func writeManifest(_ item: GalleryCacheItem, to directoryURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(item)
        guard data.count <= Self.maximumManifestByteCount else {
            throw GalleryCacheManagerError.invalidMetadata
        }
        try data.write(
            to: directoryURL.appendingPathComponent(GalleryCacheItem.manifestFileName),
            options: .atomic
        )
    }

    private func recordPersistenceFailure(_ error: Error, gid: String) {
        guard var item = storedItems[gid] else { return }
        item.status = .failed
        item.errorDescription = errorDescription(error)
        item.updatedDate = .now
        storedItems[gid] = item
    }

    private func prepareOperation(
        gid: String,
        options: CacheDownloadOptions
    ) -> GalleryCacheOperation? {
        guard var item = storedItems[gid],
              isValidMetadata(item),
              !item.isComplete
        else { return nil }
        if item.status.isActive,
           let operationID = operationIDsByGID[gid],
           operationGIDsByID[operationID] == gid
        {
            return .init(gid: gid, id: operationID, options: options)
        }

        let operationID = UUID()
        operationIDsByGID[gid] = operationID
        operationGIDsByID[operationID] = gid
        item.status = .queued
        item.errorDescription = nil
        item.updatedDate = .now
        storedItems[gid] = item
        if let error = persist(gid: gid) {
            item.status = .failed
            item.errorDescription = errorDescription(error)
            item.updatedDate = .now
            storedItems[gid] = item
            publish()
            finishOperation(operationID, success: false)
            return nil
        }
        publish()
        return .init(gid: gid, id: operationID, options: options)
    }

    @discardableResult
    func activate(_ operation: GalleryCacheOperation) -> Bool {
        loadItemsIfNeeded()
        guard operationIDsByGID[operation.gid] == operation.id,
              operationGIDsByID[operation.id] == operation.gid,
              let item = storedItems[operation.gid],
              isValidMetadata(item),
              !item.isComplete
        else { return false }
        if let cacheTask = tasks[operation.gid],
           cacheTask.operationID == operation.id,
           !retiringGIDs.contains(operation.gid)
        {
            return true
        }
        if pendingOptions[operation.gid] != nil {
            pendingOptions[operation.gid] = operation.options
            return true
        }
        guard item.status == .queued else { return false }

        pendingGIDs.append(operation.gid)
        pendingOptions[operation.gid] = operation.options
        scheduleNext()
        return true
    }

    func activatePrioritized(
        _ operations: [GalleryCacheOperation],
        appending: Bool
    ) {
        loadItemsIfNeeded()
        var prioritizedGIDs = [String]()
        var seenOperationIDs = Set<UUID>()
        var didAcceptOperation = false

        for operation in operations {
            guard seenOperationIDs.insert(operation.id).inserted,
                  operationIDsByGID[operation.gid] == operation.id,
                  operationGIDsByID[operation.id] == operation.gid,
                  let item = storedItems[operation.gid],
                  isValidMetadata(item),
                  !item.isComplete
            else { continue }

            if let cacheTask = tasks[operation.gid],
               cacheTask.operationID == operation.id,
               !retiringGIDs.contains(operation.gid)
            {
                prioritizedOperationIDs.insert(operation.id)
                didAcceptOperation = true
                continue
            }
            guard item.status == .queued
                    || pendingOptions[operation.gid] != nil
            else { continue }

            prioritizedOperationIDs.insert(operation.id)
            didAcceptOperation = true
            pendingOptions[operation.gid] = operation.options
            prioritizedGIDs.append(operation.gid)
        }
        guard didAcceptOperation else { return }

        let prioritizedGIDSet = Set(prioritizedGIDs)
        let remainingGIDs = pendingGIDs.filter { !prioritizedGIDSet.contains($0) }
        let existingPrioritizedGIDs = remainingGIDs.filter { gid in
            operationIDsByGID[gid].map(prioritizedOperationIDs.contains) == true
        }
        let ordinaryGIDs = remainingGIDs.filter { gid in
            operationIDsByGID[gid].map(prioritizedOperationIDs.contains) != true
        }
        pendingGIDs = appending
            ? existingPrioritizedGIDs + prioritizedGIDs + ordinaryGIDs
            : prioritizedGIDs + existingPrioritizedGIDs + ordinaryGIDs

        if let (gid, cacheTask) = tasks.first,
           !prioritizedOperationIDs.contains(cacheTask.operationID),
           !retiringGIDs.contains(gid),
           !preemptingGIDs.contains(gid),
           operationIDsByGID[gid] == cacheTask.operationID
        {
            preemptingGIDs.insert(gid)
            pendingGIDs.removeAll { $0 == gid }
            let priorityCount = pendingGIDs.prefix { pendingGID in
                operationIDsByGID[pendingGID].map(prioritizedOperationIDs.contains) == true
            }.count
            pendingGIDs.insert(gid, at: priorityCount)
            pendingOptions[gid] = cacheTask.options
            cacheTask.task.cancel()
        }
        scheduleNext()
    }

    private func scheduleNext() {
        guard tasks.isEmpty else { return }
        while !pendingGIDs.isEmpty {
            let gid = pendingGIDs.removeFirst()
            guard let options = pendingOptions.removeValue(forKey: gid) else { continue }
            guard let operationID = operationIDsByGID[gid],
                  let item = storedItems[gid],
                  isValidMetadata(item),
                  !item.isComplete
            else {
                if let operationID = operationIDsByGID[gid] {
                    finishOperation(operationID, success: false)
                }
                continue
            }

            launch(gid: gid, operationID: operationID, options: options)
            return
        }
    }

    private func launch(
        gid: String,
        operationID: UUID,
        options: CacheDownloadOptions
    ) {
        let generation = UUID()
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.runDownload(
                gid: gid,
                operationID: operationID,
                generation: generation,
                options: options
            )
        }
        tasks[gid] = .init(
            generation: generation,
            operationID: operationID,
            options: options,
            task: task
        )
    }

    private func runDownload(
        gid: String,
        operationID: UUID,
        generation: UUID,
        options: CacheDownloadOptions
    ) async {
        do {
            try await performDownload(gid: gid, options: options)
        } catch {
            if tasks[gid]?.generation == generation,
               operationIDsByGID[gid] == operationID,
               !retiringGIDs.contains(gid),
               var item = storedItems[gid]
            {
                if preemptingGIDs.contains(gid) {
                    item.status = .queued
                    item.errorDescription = nil
                } else if Task.isCancelled {
                    if item.status.isActive {
                        item.status = .paused
                    }
                } else {
                    if case GalleryCacheManagerError.page(_, _) = error {
                        item.remoteImageURLs.removeAll()
                        item.originalImageURLs.removeAll()
                    }
                    item.status = .failed
                    item.errorDescription = errorDescription(error)
                }
                item.updatedDate = .now
                storedItems[gid] = item
                persist(gid: gid)
                publish()
            }
        }
        if tasks[gid]?.generation == generation {
            let succeeded = operationIDsByGID[gid] == operationID
                && storedItems[gid]?.isComplete == true
            let wasPreempted = preemptingGIDs.remove(gid) != nil
            tasks.removeValue(forKey: gid)
            retiringGIDs.remove(gid)
            if succeeded || !wasPreempted {
                if succeeded {
                    removePending(gid: gid)
                }
                finishOperation(operationID, success: succeeded)
            }
            scheduleNext()
        }
    }

    private func performDownload(gid: String, options: CacheDownloadOptions) async throws {
        try Task.checkCancellation()
        try setStatus(.resolving, gid: gid)

        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = options.allowsCellularAccess
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if options.bypassesSNIFiltering {
            configuration.protocolClasses = [DFURLProtocol.self]
                + (configuration.protocolClasses ?? [])
        }
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        try await cacheCoverIfNeeded(gid: gid, session: session)
        try Task.checkCancellation()
        try await resolveImageURLs(gid: gid, options: options, session: session)
        try Task.checkCancellation()

        try setStatus(.downloading, gid: gid)
        try await downloadPages(gid: gid, options: options, session: session)
        try Task.checkCancellation()

        guard var item = storedItems[gid], item.hasAllPages else {
            throw AppError.notFound
        }
        item.status = .completed
        item.errorDescription = nil
        item.remoteImageURLs.removeAll()
        item.originalImageURLs.removeAll()
        item.updatedDate = .now
        storedItems[gid] = item
        if let error = persist(gid: gid) {
            throw error
        }
        publish()
    }

    private func setStatus(_ status: GalleryCacheStatus, gid: String) throws {
        guard var item = storedItems[gid] else {
            throw GalleryCacheManagerError.invalidMetadata
        }
        item.status = status
        item.updatedDate = .now
        storedItems[gid] = item
        if let error = persist(gid: gid) {
            throw error
        }
        publish()
    }

    private func cacheCoverIfNeeded(gid: String, session: URLSession) async throws {
        guard let item = storedItems[gid],
              item.coverFileName == nil,
              let coverURL = item.detail.coverURL ?? item.gallery.coverURL
        else { return }

        do {
            let download = try await downloadFile(index: 0, url: coverURL, session: session)
            try Task.checkCancellation()
            guard var updatedItem = storedItems[gid] else {
                throw GalleryCacheManagerError.invalidMetadata
            }
            let directoryURL = try verifiedDirectoryURL(gid: gid)
            let fileName = "cover.\(fileExtension(for: download))"
            try storeDownloadedFile(
                download.temporaryFileURL,
                at: directoryURL.appendingPathComponent(fileName)
            )
            updatedItem.coverFileName = fileName
            updatedItem.byteCount += download.byteCount
            updatedItem.updatedDate = .now
            storedItems[gid] = updatedItem
            if let error = persist(gid: gid) {
                throw error
            }
            publish()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
        }
    }

    private func resolveImageURLs(
        gid: String,
        options: CacheDownloadOptions,
        session: URLSession
    ) async throws {
        guard let initialItem = storedItems[gid],
              let galleryURL = initialItem.gallery.galleryURL
        else { throw GalleryCacheManagerError.invalidMetadata }
        if hasAllRemoteImageURLs(initialItem) {
            return
        }

        var pageNumber = 0
        let maximumPageRequests = max(initialItem.pageCount / 5 + 5, 10)
        while let item = storedItems[gid], !hasAllRemoteImageURLs(item) {
            try Task.checkCancellation()
            guard pageNumber < maximumPageRequests else { throw AppError.notFound }

            let thumbnailURLs = try await fetchThumbnailURLs(
                galleryURL: galleryURL,
                pageNumber: pageNumber,
                session: session
            )
            try Task.checkCancellation()

            if let mpvURL = thumbnailURLs.values.first(where: isMPVURL) {
                try await resolveMPVImageURLs(
                    gid: gid,
                    mpvURL: mpvURL,
                    concurrency: options.concurrentDownloads,
                    session: session
                )
                return
            }

            let unresolvedThumbnailURLs = thumbnailURLs.filter {
                item.pageFiles[$0.key] == nil && item.remoteImageURLs[$0.key] == nil
            }
            if !unresolvedThumbnailURLs.isEmpty {
                let resolved = try await fetchNormalImageURLs(
                    thumbnailURLs: unresolvedThumbnailURLs,
                    concurrency: options.concurrentDownloads,
                    session: session
                )
                try Task.checkCancellation()
                try mergeResolvedURLs(
                    gid: gid,
                    imageURLs: resolved.0,
                    originalImageURLs: resolved.1
                )
            }
            pageNumber += 1
        }
    }

    private func resolveMPVImageURLs(
        gid: String,
        mpvURL: URL,
        concurrency: Int,
        session: URLSession
    ) async throws {
        guard let item = storedItems[gid],
              let gidInteger = Int(gid)
        else { throw GalleryCacheManagerError.invalidMetadata }

        let (mpvKey, imageKeys) = try await fetchMPVKeys(mpvURL: mpvURL, session: session)
        try Task.checkCancellation()
        let indices = Array(1...item.pageCount).filter {
            item.pageFiles[$0] == nil && item.remoteImageURLs[$0] == nil
        }

        for chunk in indices.chunked(into: concurrency) {
            let resolved = try await withThrowingTaskGroup(
                of: (Int, URL, URL?).self,
                returning: [(Int, URL, URL?)].self
            ) { group in
                for index in chunk {
                    guard let imageKey = imageKeys[index] else {
                        throw AppError.notFound
                    }
                    group.addTask {
                        let response = try await self.fetchMPVImageURL(
                            gid: gidInteger,
                            index: index,
                            mpvKey: mpvKey,
                            mpvImageKey: imageKey,
                            session: session
                        )
                        return (index, response.0, response.1)
                    }
                }
                var values = [(Int, URL, URL?)]()
                for try await value in group {
                    values.append(value)
                }
                return values
            }
            try Task.checkCancellation()

            var imageURLs = [Int: URL]()
            var originalImageURLs = [Int: URL]()
            resolved.forEach { index, imageURL, originalImageURL in
                imageURLs[index] = imageURL
                originalImageURLs[index] = originalImageURL
            }
            try mergeResolvedURLs(
                gid: gid,
                imageURLs: imageURLs,
                originalImageURLs: originalImageURLs
            )
        }
    }

    private func mergeResolvedURLs(
        gid: String,
        imageURLs: [Int: URL],
        originalImageURLs: [Int: URL]
    ) throws {
        guard var item = storedItems[gid] else {
            throw GalleryCacheManagerError.invalidMetadata
        }
        let validImageURLs = imageURLs.filter {
            (1...item.pageCount).contains($0.key) && isValidRemoteURL($0.value)
        }
        let validOriginalImageURLs = originalImageURLs.filter {
            (1...item.pageCount).contains($0.key) && isValidRemoteURL($0.value)
        }
        item.remoteImageURLs.merge(validImageURLs, uniquingKeysWith: { _, new in new })
        item.originalImageURLs.merge(
            validOriginalImageURLs,
            uniquingKeysWith: { _, new in new }
        )
        item.updatedDate = .now
        storedItems[gid] = item
        if let error = persist(gid: gid) {
            throw error
        }
        publish()
    }

    private func downloadPages(
        gid: String,
        options: CacheDownloadOptions,
        session: URLSession
    ) async throws {
        guard let item = storedItems[gid] else {
            throw GalleryCacheManagerError.invalidMetadata
        }
        guard item.pageCount > 0 else {
            throw GalleryCacheManagerError.invalidMetadata
        }
        var repairPassesRemaining = 3
        var isInitialPass = true
        while true {
            guard let latestItem = storedItems[gid] else {
                throw GalleryCacheManagerError.invalidMetadata
            }
            let indices = Array(1...latestItem.pageCount).filter {
                latestItem.pageFiles[$0] == nil
            }
            guard !indices.isEmpty else { return }
            if isInitialPass {
                isInitialPass = false
            } else {
                guard repairPassesRemaining > 0 else {
                    throw GalleryCacheManagerError.page(
                        index: indices[0],
                        underlying: URLError(.cannotDecodeContentData)
                    )
                }
                repairPassesRemaining -= 1
            }

            if indices.contains(where: { latestItem.remoteImageURLs[$0] == nil }) {
                try await resolveImageURLs(gid: gid, options: options, session: session)
            }

            for chunk in indices.chunked(into: options.concurrentDownloads) {
                try Task.checkCancellation()
                try await withThrowingTaskGroup(
                    of: DownloadedCachePage.self,
                    returning: Void.self
                ) { group in
                    for index in chunk {
                        guard let latestItem = storedItems[gid],
                              let standardURL = latestItem.remoteImageURLs[index]
                        else {
                            throw GalleryCacheManagerError.page(
                                index: index,
                                underlying: AppError.notFound
                            )
                        }
                        let preferredURL = latestItem.imageQuality == .original
                            ? latestItem.originalImageURLs[index] ?? standardURL
                            : standardURL

                        group.addTask {
                            do {
                                return try await self.downloadFile(
                                    index: index,
                                    url: preferredURL,
                                    session: session
                                )
                            } catch {
                                if preferredURL != standardURL {
                                    do {
                                        return try await self.downloadFile(
                                            index: index,
                                            url: standardURL,
                                            session: session
                                        )
                                    } catch {
                                        throw GalleryCacheManagerError.page(
                                            index: index,
                                            underlying: error
                                        )
                                    }
                                }
                                throw GalleryCacheManagerError.page(
                                    index: index,
                                    underlying: error
                                )
                            }
                        }
                    }
                    for try await download in group {
                        try Task.checkCancellation()
                        try write(download: download, gid: gid)
                    }
                }
            }
        }
    }

    private nonisolated func downloadFile(
        index: Int,
        url: URL,
        session: URLSession
    ) async throws -> DownloadedCachePage {
        let (temporaryFileURL, response) = try await session.download(from: url)
        var transfersTemporaryFileOwnership = false
        defer {
            if !transfersTemporaryFileOwnership {
                try? FileManager.default.removeItem(at: temporaryFileURL)
            }
        }
        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode)
        {
            throw URLError(.badServerResponse)
        }
        guard let resourceValues = try? temporaryFileURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey]
        ),
              resourceValues.isRegularFile == true,
              let fileSize = resourceValues.fileSize,
              fileSize > 0
        else { throw AppError.notFound }
        guard response.mimeType?.lowercased().hasPrefix("image/") != false,
              let source = CGImageSourceCreateWithURL(temporaryFileURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { throw URLError(.cannotDecodeContentData) }
        let download = DownloadedCachePage(
            index: index,
            sourceURL: url,
            response: response,
            temporaryFileURL: temporaryFileURL,
            byteCount: Int64(fileSize),
            typeIdentifier: CGImageSourceGetType(source) as String?
        )
        transfersTemporaryFileOwnership = true
        return download
    }

    private func write(download: DownloadedCachePage, gid: String) throws {
        guard var item = storedItems[gid] else {
            throw GalleryCacheManagerError.invalidMetadata
        }
        let directoryURL = try verifiedDirectoryURL(gid: gid)
        let digits = max(String(item.pageCount).count, 3)
        let pageNumber = String(format: "%0*d", digits, download.index)
        let fileName = "\(pageNumber).\(fileExtension(for: download))"
        let destinationURL = directoryURL.appendingPathComponent(fileName)
        try storeDownloadedFile(
            download.temporaryFileURL,
            at: destinationURL
        )
        item.pageFiles[download.index] = fileName
        var pageIdentifiers = item.pageIdentifiers ?? [:]
        pageIdentifiers[download.index] = UUID()
        item.pageIdentifiers = pageIdentifiers
        item.remoteImageURLs.removeValue(forKey: download.index)
        item.originalImageURLs.removeValue(forKey: download.index)
        item.byteCount += download.byteCount
        item.updatedDate = .now
        storedItems[gid] = item
        localImageURLsByGID[gid, default: [:]][download.index] = destinationURL
        if let error = persist(gid: gid) {
            throw error
        }
        publish()
    }

    private func fileExtension(for download: DownloadedCachePage) -> String {
        if let mimeType = download.response.mimeType?.lowercased() {
            switch mimeType {
            case "image/jpeg":
                return "jpg"
            case "image/png":
                return "png"
            case "image/gif":
                return "gif"
            case "image/webp":
                return "webp"
            case "image/avif":
                return "avif"
            default:
                break
            }
        }

        let pathExtension = download.sourceURL.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "avif"].contains(pathExtension) {
            return pathExtension == "jpeg" ? "jpg" : pathExtension
        }
        switch download.typeIdentifier?.lowercased() {
        case "public.jpeg", "public.jpg":
            return "jpg"
        case "public.png":
            return "png"
        case "com.compuserve.gif":
            return "gif"
        case "org.webmproject.webp":
            return "webp"
        case "public.avif":
            return "avif"
        default:
            break
        }
        return "jpg"
    }

    private func hasAllRemoteImageURLs(_ item: GalleryCacheItem) -> Bool {
        GalleryCacheItem.isValidPageCount(item.pageCount)
            && (1...item.pageCount).allSatisfy {
                item.pageFiles[$0] != nil || item.remoteImageURLs[$0] != nil
            }
    }

    private func isMPVURL(_ url: URL) -> Bool {
        url.pathComponents.count > 1 && url.pathComponents[1] == "mpv"
    }

    private func availableFolderName(gid: String, title: String) -> String {
        let baseName = folderName(gid: gid, title: title)
        guard let rootURL = prepareRootDirectory() else { return baseName }
        var candidate = baseName
        var suffix = 2
        while FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent(candidate, isDirectory: true).path
        ) {
            candidate = "\(baseName) (\(suffix))"
            suffix += 1
            if suffix > 10_000 {
                return "\(gid) - \(UUID().uuidString)"
            }
        }
        return candidate
    }

    private func folderName(gid: String, title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.controlCharacters)
        let sanitized = title
            .components(separatedBy: forbidden)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = sanitized.prefixUTF8Bytes(180)
        let suffix = truncated.isEmpty ? "Gallery" : truncated
        return "\(gid) - \(suffix)"
    }

    private func writableDirectoryURL(
        gid: String,
        item: GalleryCacheItem
    ) throws -> URL {
        guard let directoryURL = item.directoryURL?.standardizedFileURL,
              let directoryIdentifier = item.directoryIdentifier
        else { throw GalleryCacheManagerError.invalidMetadata }

        if let managedDirectory = managedDirectoriesByGID[gid]?[directoryURL] {
            guard isCurrentManagedDirectory(managedDirectory, gid: gid) else {
                throw CocoaError(.fileWriteFileExists)
            }
            return directoryURL
        }

        var isDirectory: ObjCBool = false
        guard !FileManager.default.fileExists(
            atPath: directoryURL.path,
            isDirectory: &isDirectory
        ) else {
            throw CocoaError(.fileWriteFileExists)
        }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        let managedDirectory = try captureManagedDirectory(
            at: directoryURL,
            directoryIdentifier: directoryIdentifier
        )
        managedDirectoriesByGID[gid, default: [:]][directoryURL] = managedDirectory
        return directoryURL
    }

    private func verifiedDirectoryURL(gid: String) throws -> URL {
        guard let item = storedItems[gid],
              let directoryURL = item.directoryURL?.standardizedFileURL,
              let managedDirectory = managedDirectoriesByGID[gid]?[directoryURL],
              isCurrentManagedDirectory(managedDirectory, gid: gid)
        else { throw CocoaError(.fileNoSuchFile) }
        return directoryURL
    }

    private func captureManagedDirectory(
        at directoryURL: URL,
        directoryIdentifier: UUID
    ) throws -> ManagedCacheDirectory {
        let values = try directoryURL.resourceValues(
            forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileResourceIdentifierKey
            ]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw GalleryCacheManagerError.invalidMetadata
        }
        return .init(
            url: directoryURL.standardizedFileURL,
            directoryIdentifier: directoryIdentifier,
            fileResourceIdentifier: values.fileResourceIdentifier as? AnyHashable,
            createdByCurrentManager: true
        )
    }

    private func isCurrentManagedDirectory(
        _ managedDirectory: ManagedCacheDirectory,
        gid: String
    ) -> Bool {
        guard directoryResourceMatches(managedDirectory) else { return false }
        if managedDirectory.fileResourceIdentifier != nil {
            return true
        }
        return manifestMatches(managedDirectory, gid: gid)
    }

    private func directoryResourceMatches(
        _ managedDirectory: ManagedCacheDirectory
    ) -> Bool {
        guard let rootURL = FileUtil.galleryCachesDirectoryURL?.standardizedFileURL,
              managedDirectory.url.deletingLastPathComponent() == rootURL,
              let values = try? managedDirectory.url.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileResourceIdentifierKey
                ]
              ),
              values.isDirectory == true,
              values.isSymbolicLink != true
        else { return false }

        if let expectedIdentifier = managedDirectory.fileResourceIdentifier {
            return values.fileResourceIdentifier as? AnyHashable == expectedIdentifier
        }
        return true
    }

    private func manifestMatches(
        _ managedDirectory: ManagedCacheDirectory,
        gid: String
    ) -> Bool {
        let manifestURL = managedDirectory.url.appendingPathComponent(
            GalleryCacheItem.manifestFileName
        )
        guard let values = try? manifestURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= Self.maximumManifestByteCount,
              let data = try? Data(contentsOf: manifestURL, options: .mappedIfSafe)
        else { return false }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let item = try? decoder.decode(GalleryCacheItem.self, from: data) else {
            return false
        }
        return item.id == gid
            && item.directoryIdentifier == managedDirectory.directoryIdentifier
            && isValidMetadata(item)
    }

    private func removeStalePartialFiles(in directoryURL: URL) {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return }

        for fileURL in fileURLs {
            guard isInternalPartialFile(fileURL) else { continue }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func isInternalPartialFile(_ fileURL: URL) -> Bool {
        let components = fileURL.lastPathComponent.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard components.count >= 4,
              components.last == "partial",
              UUID(uuidString: String(components[components.count - 2])) != nil,
              let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true
        else { return false }
        return true
    }

    private func isValidMetadata(_ item: GalleryCacheItem) -> Bool {
        isValidGalleryID(item.id)
            && item.detail.gid == item.id
            && GalleryCacheItem.isValidPageCount(item.pageCount)
            && item.gallery.pageCount == item.pageCount
            && (item.detail.pageCount == 0 || item.detail.pageCount == item.pageCount)
            && item.pageFiles.count <= GalleryCacheItem.maximumPageCount
            && (item.pageIdentifiers?.count ?? 0) <= GalleryCacheItem.maximumPageCount
            && item.remoteImageURLs.count <= GalleryCacheItem.maximumPageCount
            && item.originalImageURLs.count <= GalleryCacheItem.maximumPageCount
    }

    private func isValidGalleryID(_ gid: String) -> Bool {
        guard gid.isValidGID, let value = Int(gid) else { return false }
        return value > 0
    }

    private func isValidRemoteURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "https" || scheme == "http") && url.host != nil
    }

    private func removePending(gid: String) {
        pendingOptions.removeValue(forKey: gid)
        pendingGIDs.removeAll { $0 == gid }
    }

    private func removeManagedDirectories(
        _ managedDirectories: [ManagedCacheDirectory],
        gid: String
    ) -> Bool {
        var targets = [URL: ManagedCacheDirectory]()
        for managedDirectory in managedDirectories {
            switch resolvedManagedDirectory(managedDirectory, gid: gid) {
            case .target(let target):
                targets[target.url] = target
            case .gone:
                continue
            case .conflict:
                return false
            }
        }
        guard targets.values.allSatisfy({ canRemoveManagedDirectory($0, gid: gid) }) else {
            return false
        }
        for target in targets.values {
            guard removeManagedDirectory(target, gid: gid) else {
                return false
            }
        }
        return true
    }

    private func removeManagedDirectory(
        _ managedDirectory: ManagedCacheDirectory,
        gid: String
    ) -> Bool {
        var coordinationError: NSError?
        var didRemove = false
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(
            writingItemAt: managedDirectory.url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            let coordinatedDirectory = ManagedCacheDirectory(
                url: coordinatedURL.standardizedFileURL,
                directoryIdentifier: managedDirectory.directoryIdentifier,
                fileResourceIdentifier: managedDirectory.fileResourceIdentifier,
                createdByCurrentManager: managedDirectory.createdByCurrentManager
            )
            guard canRemoveManagedDirectory(coordinatedDirectory, gid: gid) else { return }
            do {
                try FileManager.default.removeItem(at: coordinatedDirectory.url)
                didRemove = true
            } catch {
                didRemove = false
            }
        }
        return coordinationError == nil && didRemove
    }

    private func resolvedManagedDirectory(
        _ managedDirectory: ManagedCacheDirectory,
        gid: String
    ) -> ManagedCacheDirectoryResolution {
        if canRemoveManagedDirectory(managedDirectory, gid: gid) {
            return .target(managedDirectory)
        }
        var foundConflict = directoryResourceMatches(managedDirectory)
        guard let rootURL = FileUtil.galleryCachesDirectoryURL,
              let directoryURLs = try? FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileResourceIdentifierKey
                ],
                options: [.skipsHiddenFiles]
              )
        else { return foundConflict ? .conflict : .gone }

        for directoryURL in directoryURLs {
            guard let values = try? directoryURL.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileResourceIdentifierKey
                ]
            ),
                  values.isDirectory == true,
                  values.isSymbolicLink != true
            else { continue }

            let resourceIdentifier = values.fileResourceIdentifier as? AnyHashable
            if let expectedIdentifier = managedDirectory.fileResourceIdentifier,
               resourceIdentifier != expectedIdentifier
            {
                continue
            }
            let candidate = ManagedCacheDirectory(
                url: directoryURL.standardizedFileURL,
                directoryIdentifier: managedDirectory.directoryIdentifier,
                fileResourceIdentifier: resourceIdentifier,
                createdByCurrentManager: managedDirectory.createdByCurrentManager
            )
            if manifestMatches(candidate, gid: gid) {
                return .target(candidate)
            }
            if managedDirectory.fileResourceIdentifier != nil
                || candidate.url == managedDirectory.url
            {
                foundConflict = true
            }
        }
        return foundConflict ? .conflict : .gone
    }

    private func canRemoveManagedDirectory(
        _ managedDirectory: ManagedCacheDirectory,
        gid: String
    ) -> Bool {
        guard directoryResourceMatches(managedDirectory) else { return false }
        if manifestMatches(managedDirectory, gid: gid) {
            return true
        }
        return managedDirectory.createdByCurrentManager
            && managedDirectory.fileResourceIdentifier != nil
            && isDisposableUnmanifestedDirectory(managedDirectory.url)
    }

    private func isDisposableUnmanifestedDirectory(_ directoryURL: URL) -> Bool {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return false }
        return fileURLs.allSatisfy(isInternalPartialFile)
    }

    private func validatedPageFiles(_ item: GalleryCacheItem) -> [Int: String] {
        guard GalleryCacheItem.isValidPageCount(item.pageCount) else { return [:] }
        var validated = [Int: String]()
        var seenFileNames = Set<String>()
        let localImageURLs = item.localImageURLs
        for (index, fileName) in item.pageFiles.sorted(by: { $0.key < $1.key }) {
            guard (1...item.pageCount).contains(index),
                  !seenFileNames.contains(fileName),
                  localImageURLs[index] != nil
            else { continue }
            seenFileNames.insert(fileName)
            validated[index] = fileName
        }
        return validated
    }

    private func byteCount(of item: GalleryCacheItem) -> Int64 {
        let urls = Set(
            Array(item.localImageURLs.values)
                + [item.coverFileURL].compactMap { $0 }
        )
        return urls.reduce(into: 0) { count, url in
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            count += Int64(fileSize)
        }
    }

    private nonisolated func fetchThumbnailURLs(
        galleryURL: URL,
        pageNumber: Int,
        session: URLSession
    ) async throws -> [Int: URL] {
        let url = URLUtil.detailPage(url: galleryURL, pageNum: pageNumber)
        let data = try await fetchData(URLRequest(url: url), session: session)
        let document = try Kanna.HTML(html: data, encoding: .utf8)
        return try Parser.parseThumbnailURLs(doc: document)
    }

    private nonisolated func fetchNormalImageURLs(
        thumbnailURLs: [Int: URL],
        concurrency: Int,
        session: URLSession
    ) async throws -> ([Int: URL], [Int: URL]) {
        var imageURLs = [Int: URL]()
        var originalImageURLs = [Int: URL]()
        let entries = thumbnailURLs.sorted(by: { $0.key < $1.key })

        for chunk in entries.chunked(into: concurrency) {
            let resolved = try await withThrowingTaskGroup(
                of: (Int, URL, URL?).self,
                returning: [(Int, URL, URL?)].self
            ) { group in
                for (index, url) in chunk {
                    group.addTask {
                        let data = try await self.fetchData(URLRequest(url: url), session: session)
                        let document = try Kanna.HTML(html: data, encoding: .utf8)
                        return try Parser.parseGalleryNormalImageURL(doc: document, index: index)
                    }
                }
                var values = [(Int, URL, URL?)]()
                for try await value in group {
                    values.append(value)
                }
                return values
            }
            try Task.checkCancellation()
            for (index, imageURL, originalImageURL) in resolved {
                imageURLs[index] = imageURL
                originalImageURLs[index] = originalImageURL
            }
        }
        return (imageURLs, originalImageURLs)
    }

    private nonisolated func fetchMPVKeys(
        mpvURL: URL,
        session: URLSession
    ) async throws -> (String, [Int: String]) {
        let data = try await fetchData(URLRequest(url: mpvURL), session: session)
        let document = try Kanna.HTML(html: data, encoding: .utf8)
        return try Parser.parseMPVKeys(doc: document)
    }

    private nonisolated func fetchMPVImageURL(
        gid: Int,
        index: Int,
        mpvKey: String,
        mpvImageKey: String,
        session: URLSession
    ) async throws -> (URL, URL?) {
        let params: [String: Any] = [
            "method": "imagedispatch",
            "gid": gid,
            "page": index,
            "imgkey": mpvImageKey,
            "mpvkey": mpvKey
        ]
        var request = URLRequest(url: Defaults.URL.api)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let data = try await fetchData(request, session: session)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let imageURLString = dictionary["i"] as? String,
              let imageURL = URL(string: imageURLString)
        else { throw AppError.parseFailed }

        let originalImageURL = (dictionary["lf"] as? String).map {
            Defaults.URL.host.appendingPathComponent($0)
        }
        return (imageURL, originalImageURL)
    }

    private nonisolated func fetchData(
        _ request: URLRequest,
        session: URLSession
    ) async throws -> Data {
        var lastError: Error = URLError(.unknown)
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)
                if let response = response as? HTTPURLResponse,
                   !(200..<300).contains(response.statusCode)
                {
                    throw URLError(.badServerResponse)
                }
                guard !data.isEmpty else { throw AppError.notFound }
                return data
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(250 * (1 << attempt)))
                }
            }
        }
        throw lastError
    }

    private nonisolated func storeDownloadedFile(
        _ temporaryFileURL: URL,
        at destinationURL: URL
    ) throws {
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: temporaryFileURL) }
        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).partial")
        do {
            try fileManager.moveItem(at: temporaryFileURL, to: stagingURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
            }
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private func optionsForExistingItem(
        _ item: GalleryCacheItem,
        fallback: CacheDownloadOptions
    ) -> CacheDownloadOptions {
        .init(
            imageQuality: item.imageQuality,
            concurrentDownloads: fallback.concurrentDownloads,
            allowsCellularAccess: fallback.allowsCellularAccess,
            bypassesSNIFiltering: fallback.bypassesSNIFiltering
        )
    }

    private func errorDescription(_ error: Error) -> String {
        switch error {
        case let GalleryCacheManagerError.page(_, underlying):
            return errorDescription(underlying)
        case let appError as AppError:
            return appError.localizedDescription
        default:
            return error.localizedDescription
        }
    }
}

struct GalleryCacheActivityUnitProgress: Equatable {
    let completedUnitCount: Int64
    let totalUnitCount: Int64

    init(cachedPageCount: Int, totalPageCount: Int) {
        totalUnitCount = Int64(max(totalPageCount, 0))
        completedUnitCount = min(
            totalUnitCount,
            Int64(max(cachedPageCount, 0))
        )
    }
}

private actor GalleryCacheBackgroundTaskCoordinator {
    static let shared = GalleryCacheBackgroundTaskCoordinator()

    private struct ActivityProgress: Equatable {
        let title: String
        let status: GalleryCacheStatus
        let completedPageCount: Int
        let totalPageCount: Int
        let completedUnitCount: Int64
        let totalUnitCount: Int64

        init(item: GalleryCacheItem) {
            title = item.displayTitle
            status = item.status
            completedPageCount = item.cachedPageCount
            totalPageCount = item.pageCount
            let unitProgress = GalleryCacheActivityUnitProgress(
                cachedPageCount: completedPageCount,
                totalPageCount: totalPageCount
            )
            completedUnitCount = unitProgress.completedUnitCount
            totalUnitCount = unitProgress.totalUnitCount
        }

        var subtitle: String {
            [
                status.value,
                L10n.Localizable.CacheView.Value.pages(
                    completedPageCount,
                    totalPageCount
                )
            ].joined(separator: " - ")
        }
    }

    private struct Ticket {
        let identifier: String
        var pendingOperations: [GalleryCacheOperation]
        var currentOperation: GalleryCacheOperation?
        var itemsByOperationID: [UUID: GalleryCacheItem]
        var isRunning = false
        var isExpired = false
        var hadFailure = false
        var reportedCompletedUnitCount: Int64 = 0
        var lastDisplayedProgress: ActivityProgress?
        var lastReportedTotalUnitCount: Int64 = 0
    }

    private var registeredIdentifiers = Set<String>()
    private var ticketsByIdentifier = [String: Ticket]()
    private var expirationCleanupTasks = [String: Task<Void, Never>]()
    private var cancelledOperationIDs = Set<UUID>()
    private var expirationProtectedOperationIDs = Set<UUID>()
    private var submissionOperationIDsByID = [UUID: Set<UUID>]()
    private var activeIdentifier: String?

    func submit(
        _ operations: [GalleryCacheOperation]
    ) async -> [GalleryCacheOperation] {
        let submissionID = UUID()
        submissionOperationIDsByID[submissionID] = Set(operations.map(\.id))
        defer {
            submissionOperationIDsByID.removeValue(forKey: submissionID)
            pruneCancelledOperations()
        }

        let currentItems = await GalleryCacheManager.shared.items(for: operations)
        let validated = currentItems.filter {
            !cancelledOperationIDs.contains($0.0.id)
        }
        guard !validated.isEmpty else { return [] }

        if let activeIdentifier,
           var ticket = ticketsByIdentifier[activeIdentifier],
           !ticket.isExpired
        {
            var appendedOperations = [GalleryCacheOperation]()
            for (operation, item) in validated
            where ticket.itemsByOperationID[operation.id] == nil {
                ticket.pendingOperations.append(operation)
                ticket.itemsByOperationID[operation.id] = item
                appendedOperations.append(operation)
            }
            let shouldActivate = ticket.isRunning && !appendedOperations.isEmpty
            ticketsByIdentifier[activeIdentifier] = ticket
            if shouldActivate {
                await GalleryCacheManager.shared.activatePrioritized(
                    appendedOperations,
                    appending: true
                )
            }
            return []
        }

        let identifier = taskIdentifier()
        guard registerHandler(identifier: identifier) else {
            return validated.map(\.0)
        }
        let firstProgress = ActivityProgress(item: validated[0].1)
        let ticket = Ticket(
            identifier: identifier,
            pendingOperations: validated.map(\.0),
            currentOperation: nil,
            itemsByOperationID: Dictionary(
                uniqueKeysWithValues: validated.map { ($0.0.id, $0.1) }
            )
        )
        ticketsByIdentifier[identifier] = ticket
        activeIdentifier = identifier

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: firstProgress.title,
            subtitle: firstProgress.subtitle
        )
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
            return []
        } catch {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            ticketsByIdentifier.removeValue(forKey: identifier)
            if activeIdentifier == identifier {
                activeIdentifier = nil
            }
            Logger.error("Unable to submit cache background task: \(error)")
            return validated.map(\.0)
        }
    }

    func cancel(operationID: UUID) async {
        await cancel(operationIDs: [operationID])
    }

    func cancel(operationIDs: [UUID]) async {
        let operationIDs = Set(operationIDs)
        guard !operationIDs.isEmpty else { return }
        recordCancelledOperations(operationIDs)
        await GalleryCacheManager.shared.discardOperationOutcomes(
            operationIDs: operationIDs
        )

        for identifier in Array(ticketsByIdentifier.keys) {
            guard var ticket = ticketsByIdentifier[identifier] else { continue }
            let oldPendingCount = ticket.pendingOperations.count
            if ticket.isRunning {
                if ticket.pendingOperations.contains(where: {
                    operationIDs.contains($0.id)
                }) {
                    ticket.hadFailure = true
                }
            } else {
                ticket.pendingOperations.removeAll { operationIDs.contains($0.id) }
            }
            if !ticket.isRunning,
               ticket.pendingOperations.count != oldPendingCount
            {
                ticket.hadFailure = true
            }
            ticketsByIdentifier[identifier] = ticket

            if !ticket.isRunning,
               ticket.currentOperation == nil,
               ticket.pendingOperations.isEmpty
            {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
                ticketsByIdentifier.removeValue(forKey: identifier)
                if activeIdentifier == identifier {
                    activeIdentifier = nil
                }
            }
        }
    }

    private func registerHandler(identifier: String) -> Bool {
        guard !registeredIdentifiers.contains(identifier) else { return true }
        let didRegister = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            let identifier = task.identifier
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            task.expirationHandler = {
                Task { await Self.shared.expire(identifier: identifier) }
            }
            Task {
                await Self.shared.handle(task, identifier: identifier)
            }
        }
        guard didRegister else {
            Logger.error("Unable to register cache background task: \(identifier)")
            return false
        }
        registeredIdentifiers.insert(identifier)
        return true
    }

    private func recordCancelledOperations(_ operationIDs: Set<UUID>) {
        cancelledOperationIDs.formUnion(operationIDs)
        pruneCancelledOperations()
    }

    private func pruneCancelledOperations() {
        var protectedOperationIDs = expirationProtectedOperationIDs
        for operationIDs in submissionOperationIDsByID.values {
            protectedOperationIDs.formUnion(operationIDs)
        }
        cancelledOperationIDs.formIntersection(protectedOperationIDs)
    }

    private func expire(identifier: String) async {
        guard var ticket = ticketsByIdentifier[identifier],
              !ticket.isExpired
        else { return }
        ticket.isExpired = true
        ticket.hadFailure = true
        let operations = [ticket.currentOperation].compactMap { $0 }
            + ticket.pendingOperations
        let operationIDs = Set(operations.map(\.id))
        expirationProtectedOperationIDs.formUnion(operationIDs)
        recordCancelledOperations(operationIDs)
        ticket.pendingOperations.removeAll()
        ticketsByIdentifier[identifier] = ticket
        if activeIdentifier == identifier {
            activeIdentifier = nil
        }

        let cleanupTask = Task {
            await GalleryCacheManager.shared.discardOperationOutcomes(
                operationIDs: Set(operations.map(\.id))
            )
            for operation in operations {
                await GalleryCacheManager.shared.pause(
                    gid: operation.gid,
                    expectedOperationID: operation.id
                )
            }
            for operation in operations {
                let updates = await GalleryCacheManager.shared.operationUpdates(
                    for: operation
                )
                for await event in updates {
                    if case .finished = event { break }
                }
            }
        }
        expirationCleanupTasks[identifier] = cleanupTask
        await cleanupTask.value
        expirationCleanupTasks.removeValue(forKey: identifier)
        expirationProtectedOperationIDs.subtract(operationIDs)
        pruneCancelledOperations()
    }

    private func handle(
        _ task: BGContinuedProcessingTask,
        identifier: String
    ) async {
        guard beginHandling(identifier: identifier) else {
            if isExpired(identifier: identifier) {
                await waitForExpirationCleanup(identifier: identifier)
                discardExpiredTicket(identifier: identifier)
            }
            task.expirationHandler = nil
            task.setTaskCompleted(success: false)
            return
        }
        update(task, identifier: identifier)
        let queuedOperations = pendingOperations(identifier: identifier)
        await GalleryCacheManager.shared.activatePrioritized(
            queuedOperations,
            appending: false
        )

        while let operation = nextOperation(identifier: identifier) {
            await GalleryCacheManager.shared.activate(operation)
            let stream = await GalleryCacheManager.shared.operationUpdates(for: operation)
            var receivedFinishedEvent = false

            for await event in stream {
                switch event {
                case .progress(let item):
                    recordProgress(
                        item,
                        operationID: operation.id,
                        identifier: identifier
                    )
                    update(task, identifier: identifier)

                case .finished(let didSucceed):
                    finishCurrentOperation(
                        operation,
                        identifier: identifier,
                        success: didSucceed
                    )
                    receivedFinishedEvent = true
                }
                if receivedFinishedEvent { break }
            }

            if !receivedFinishedEvent {
                await GalleryCacheManager.shared.pause(
                    gid: operation.gid,
                    expectedOperationID: operation.id
                )
                finishCurrentOperation(
                    operation,
                    identifier: identifier,
                    success: false
                )
            }
        }

        if isExpired(identifier: identifier) {
            await waitForExpirationCleanup(identifier: identifier)
        }
        let success = finishTicket(identifier: identifier)
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
    }

    private func beginHandling(identifier: String) -> Bool {
        guard var ticket = ticketsByIdentifier[identifier],
              !ticket.isRunning,
              !ticket.isExpired
        else { return false }
        ticket.isRunning = true
        ticketsByIdentifier[identifier] = ticket
        return true
    }

    private func discardExpiredTicket(identifier: String) {
        guard ticketsByIdentifier[identifier]?.isExpired == true else { return }
        ticketsByIdentifier.removeValue(forKey: identifier)
    }

    private func waitForExpirationCleanup(identifier: String) async {
        await expirationCleanupTasks[identifier]?.value
    }

    private func isExpired(identifier: String) -> Bool {
        ticketsByIdentifier[identifier]?.isExpired == true
    }

    private func nextOperation(identifier: String) -> GalleryCacheOperation? {
        guard var ticket = ticketsByIdentifier[identifier],
              !ticket.isExpired,
              ticket.currentOperation == nil,
              !ticket.pendingOperations.isEmpty
        else { return nil }
        let operation = ticket.pendingOperations.removeFirst()
        ticket.currentOperation = operation
        ticketsByIdentifier[identifier] = ticket
        return operation
    }

    private func pendingOperations(
        identifier: String
    ) -> [GalleryCacheOperation] {
        ticketsByIdentifier[identifier]?.pendingOperations ?? []
    }

    private func recordProgress(
        _ item: GalleryCacheItem,
        operationID: UUID,
        identifier: String
    ) {
        guard var ticket = ticketsByIdentifier[identifier],
              ticket.itemsByOperationID[operationID] != nil
        else { return }
        ticket.itemsByOperationID[operationID] = item
        ticketsByIdentifier[identifier] = ticket
    }

    private func finishCurrentOperation(
        _ operation: GalleryCacheOperation,
        identifier: String,
        success: Bool
    ) {
        guard var ticket = ticketsByIdentifier[identifier],
              ticket.currentOperation?.id == operation.id
        else { return }
        ticket.currentOperation = nil
        ticket.hadFailure = ticket.hadFailure || !success
        ticketsByIdentifier[identifier] = ticket
    }

    private func finishTicket(identifier: String) -> Bool {
        guard let ticket = ticketsByIdentifier.removeValue(forKey: identifier) else {
            return false
        }
        if activeIdentifier == identifier {
            activeIdentifier = nil
        }
        return !ticket.isExpired
            && !ticket.hadFailure
            && ticket.currentOperation == nil
            && ticket.pendingOperations.isEmpty
    }

    private func update(
        _ task: BGContinuedProcessingTask,
        identifier: String
    ) {
        guard var ticket = ticketsByIdentifier[identifier] else { return }
        let progressValues = ticket.itemsByOperationID.values.map(ActivityProgress.init)
        guard let displayedProgress = ticket.currentOperation
            .flatMap({ ticket.itemsByOperationID[$0.id] })
            .map(ActivityProgress.init)
            ?? ticket.pendingOperations.first
                .flatMap({ ticket.itemsByOperationID[$0.id] })
                .map(ActivityProgress.init)
            ?? progressValues.first
        else { return }

        let totalUnitCount = progressValues.reduce(Int64(0)) {
            $0 + $1.totalUnitCount
        }
        let measuredCompletedUnitCount = progressValues.reduce(Int64(0)) {
            $0 + $1.completedUnitCount
        }
        let completedUnitCount = min(
            totalUnitCount,
            max(ticket.reportedCompletedUnitCount, measuredCompletedUnitCount)
        )
        let didChange = displayedProgress != ticket.lastDisplayedProgress
            || totalUnitCount != ticket.lastReportedTotalUnitCount
            || completedUnitCount != ticket.reportedCompletedUnitCount
        guard didChange else { return }

        ticket.lastDisplayedProgress = displayedProgress
        ticket.lastReportedTotalUnitCount = totalUnitCount
        ticket.reportedCompletedUnitCount = completedUnitCount
        ticketsByIdentifier[identifier] = ticket
        task.progress.totalUnitCount = totalUnitCount
        task.progress.completedUnitCount = completedUnitCount
        task.updateTitle(
            displayedProgress.title,
            subtitle: displayedProgress.subtitle
        )
    }

    private func taskIdentifier() -> String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.ehpanda"
        let operationIdentifier = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return [
            bundleIdentifier,
            "cache",
            operationIdentifier
        ].joined(separator: ".")
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private extension String {
    func prefixUTF8Bytes(_ maximumByteCount: Int) -> String {
        var result = ""
        var byteCount = 0
        for character in self {
            let value = String(character)
            let valueByteCount = value.utf8.count
            guard byteCount + valueByteCount <= maximumByteCount else { break }
            result.append(character)
            byteCount += valueByteCount
        }
        return result
    }
}
