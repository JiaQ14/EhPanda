//
//  IntentGalleryService.swift
//  EhPanda
//

import Foundation

final class IntentGalleryService: @unchecked Sendable {
    static let shared = IntentGalleryService()

    private let databaseClient: DatabaseClient
    private let cacheClient: CacheClient

    init(
        databaseClient: DatabaseClient = .live,
        cacheClient: CacheClient = .live
    ) {
        self.databaseClient = databaseClient
        self.cacheClient = cacheClient
    }

    func entity(gid: String) async -> GalleryEntity? {
        let gallery = databaseClient.fetchGallery(gid: gid)
        let cachedItem = await cacheClient.item(gid)
        guard let source = gallery ?? cachedItem?.gallery else { return nil }

        var entity = GalleryEntity(gallery: source)
        if let coverFileURL = cachedItem?.coverFileURL {
            entity.coverURL = coverFileURL
        }
        return entity
    }

    func recentEntities(limit: Int = 10) async -> [GalleryEntity] {
        let galleries = await MainActor.run {
            databaseClient.fetchHistoryGalleries(fetchLimit: limit)
        }
        return galleries.map(GalleryEntity.init)
    }

    func cachedEntities() async -> [GalleryEntity] {
        await cacheClient.items().map { item in
            var entity = GalleryEntity(gallery: item.gallery)
            if let coverFileURL = item.coverFileURL {
                entity.coverURL = coverFileURL
            }
            return entity
        }
    }

    func visualCandidates(limit: Int = 100) async -> [GalleryEntity] {
        let recent = await recentEntities(limit: limit)
        let cached = await cachedEntities()
        return Self.merging(primary: recent, cached: cached)
            .prefix(limit)
            .map { $0 }
    }

    func systemSearchEntities(recentLimit: Int = 100) async -> [GalleryEntity] {
        let recent = await recentEntities(limit: recentLimit)
        let cached = await cachedEntities()
        return Self.merging(primary: recent, cached: cached)
    }

    func localEntities(matching query: String, limit: Int = 20) async -> [GalleryEntity] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return await recentEntities(limit: limit) }

        let recent = await recentEntities(limit: 0)
        let cached = await cachedEntities()
        return Self.merging(primary: recent, cached: cached)
            .filter { $0.matches(normalizedQuery) }
            .prefix(limit)
            .map { $0 }
    }

    func readingProgress(gid: String) async -> Int? {
        await databaseClient.fetchGalleryState(gid: gid)?.readingProgress
    }

    func refreshCacheLibrary() async -> Int {
        await cacheClient.refresh()
        return await cacheClient.items().count
    }

    static func merging(
        primary: [GalleryEntity],
        cached: [GalleryEntity]
    ) -> [GalleryEntity] {
        var cachedByID = [String: GalleryEntity]()
        cached.forEach { cachedByID[$0.id] = $0 }

        var seen = Set<String>()
        var entities = primary.compactMap { entity -> GalleryEntity? in
            guard seen.insert(entity.id).inserted else { return nil }
            guard let cachedEntity = cachedByID[entity.id],
                  cachedEntity.coverURL?.isFileURL == true
            else { return entity }
            var merged = entity
            merged.coverURL = cachedEntity.coverURL
            return merged
        }
        entities.append(contentsOf: cached.filter { seen.insert($0.id).inserted })
        return entities
    }
}
