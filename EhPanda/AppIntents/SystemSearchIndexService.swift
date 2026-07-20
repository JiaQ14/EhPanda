//
//  SystemSearchIndexService.swift
//  EhPanda
//

import CoreSpotlight
import Foundation

struct SystemSearchIndexClient: @unchecked Sendable {
    let isAvailable: () -> Bool
    let deleteGalleryItems: () async throws -> Void
    let indexItems: ([CSSearchableItem]) async throws -> Void

    static func live(index: CSSearchableIndex) -> Self {
        .init(
            isAvailable: CSSearchableIndex.isIndexingAvailable,
            deleteGalleryItems: {
                try await index.deleteSearchableItems(
                    withDomainIdentifiers: [GalleryEntity.spotlightDomainIdentifier]
                )
            },
            indexItems: { try await index.indexSearchableItems($0) }
        )
    }
}

actor SystemSearchIndexService {
    static let shared = SystemSearchIndexService()

    private struct GallerySnapshot: Equatable {
        let id: String
        let title: String
        let uploader: String
        let pageCount: Int
        let coverURL: URL?

        init(entity: GalleryEntity, includesCover: Bool) {
            id = entity.id
            title = entity.title
            uploader = entity.uploader
            pageCount = entity.pageCount
            coverURL = includesCover && entity.coverURL?.isFileURL == true
                ? entity.coverURL
                : nil
        }
    }

    private enum Snapshot: Equatable {
        case disabled
        case enabled(includesCover: Bool, galleries: [GallerySnapshot])
    }

    private let entityProvider: @Sendable () async -> [GalleryEntity]
    private let indexClient: SystemSearchIndexClient

    private var pendingSetting: Setting?
    private var workerTask: Task<Void, Never>?
    private var lastSnapshot: Snapshot?

    init(
        galleryService: IntentGalleryService = .shared,
        index: CSSearchableIndex = .default()
    ) {
        entityProvider = {
            await galleryService.systemSearchEntities(recentLimit: 100)
        }
        indexClient = .live(index: index)
    }

    init(
        entityProvider: @escaping @Sendable () async -> [GalleryEntity],
        indexClient: SystemSearchIndexClient
    ) {
        self.entityProvider = entityProvider
        self.indexClient = indexClient
    }

    func synchronize(using setting: Setting) async {
        pendingSetting = setting

        if let workerTask {
            await workerTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.processPendingSettings()
        }
        workerTask = task
        await task.value
    }

    private func processPendingSettings() async {
        while let setting = pendingSetting {
            pendingSetting = nil
            await synchronizeLatest(using: setting)
        }
        workerTask = nil
    }

    private func synchronizeLatest(using setting: Setting) async {
        guard indexClient.isAvailable() else {
            Logger.error("Spotlight indexing is unavailable on this device.")
            return
        }

        guard setting.enablesSystemContentSearch else {
            await applyDisabledSnapshot()
            return
        }

        let entities = await entityProvider()
        guard pendingSetting == nil else { return }

        var seen = Set<String>()
        let uniqueEntities = entities
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.id < $1.id }
        let includesCover = setting.displaysCoversInSystemSearch
        let snapshot = Snapshot.enabled(
            includesCover: includesCover,
            galleries: uniqueEntities.map {
                GallerySnapshot(entity: $0, includesCover: includesCover)
            }
        )
        guard snapshot != lastSnapshot else { return }

        do {
            try await indexClient.deleteGalleryItems()
            guard pendingSetting == nil else { return }
            if !uniqueEntities.isEmpty {
                try await indexClient.indexItems(uniqueEntities.map {
                    $0.searchableItem(includesCover: includesCover)
                })
            }
            lastSnapshot = snapshot
            Logger.info("Spotlight indexed \(uniqueEntities.count) galleries.")
        } catch {
            Logger.error("Unable to synchronize Spotlight index: \(error)")
        }
    }

    private func applyDisabledSnapshot() async {
        guard lastSnapshot != .disabled else { return }
        do {
            try await indexClient.deleteGalleryItems()
            lastSnapshot = .disabled
        } catch {
            Logger.error("Unable to remove Spotlight gallery items: \(error)")
        }
    }
}
