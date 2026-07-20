//
//  GalleryEntity.swift
//  EhPanda
//

import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

struct GalleryEntity: AppEntity, IndexedEntity {
    static let spotlightDomainIdentifier = "app.ehpanda.gallery"
    private static let spotlightIdentifierPrefix = "gallery:"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Gallery",
        numericFormat: "\(placeholder: .int) galleries"
    )
    static let defaultQuery = GalleryEntityQuery()

    let id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Uploader")
    var uploader: String

    @Property(title: "Page count")
    var pageCount: Int

    var coverURL: URL?

    init(gallery: Gallery) {
        id = gallery.id
        title = gallery.title
        uploader = gallery.uploader ?? ""
        pageCount = gallery.pageCount
        coverURL = gallery.coverURL
    }

    var displayRepresentation: DisplayRepresentation {
        let pageDescription = L10n.Localizable.Common.Value.pages(pageCount)
        let subtitle = uploader.isEmpty
            ? pageDescription
            : "\(uploader) · \(pageDescription)"
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)",
            image: coverURL.map { DisplayRepresentation.Image(url: $0) }
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        searchableAttributeSet(includesCover: true)
    }

    func searchableItem(includesCover: Bool) -> CSSearchableItem {
        let item = CSSearchableItem(
            uniqueIdentifier: Self.spotlightIdentifier(for: id),
            domainIdentifier: Self.spotlightDomainIdentifier,
            attributeSet: searchableAttributeSet(includesCover: includesCover)
        )
        item.expirationDate = .distantFuture
        return item
    }

    static func spotlightIdentifier(for galleryID: String) -> String {
        spotlightIdentifierPrefix + galleryID
    }

    static func galleryID(fromSpotlightIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(spotlightIdentifierPrefix) else { return nil }
        let galleryID = String(identifier.dropFirst(spotlightIdentifierPrefix.count))
        return galleryID.isValidGID ? galleryID : nil
    }

    private func searchableAttributeSet(includesCover: Bool) -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        let pageDescription = L10n.Localizable.Common.Value.pages(pageCount)
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = uploader.isEmpty
            ? pageDescription
            : "\(uploader), \(pageDescription)"
        attributes.textContent = [title, uploader, id]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        attributes.keywords = [title, uploader, id].filter { !$0.isEmpty }
        if includesCover, let coverURL, coverURL.isFileURL {
            attributes.thumbnailURL = coverURL
        }
        attributes.associateAppEntity(self)
        return attributes
    }

    func matches(_ query: String) -> Bool {
        id.localizedCaseInsensitiveContains(query)
            || title.localizedCaseInsensitiveContains(query)
            || uploader.localizedCaseInsensitiveContains(query)
    }

}

struct GalleryEntityQuery: EntityStringQuery {
    @Dependency(default: IntentGalleryService.shared)
    private var service: IntentGalleryService

    func entities(for identifiers: [GalleryEntity.ID]) async throws -> [GalleryEntity] {
        var entities = [GalleryEntity]()
        for identifier in identifiers {
            if let entity = await service.entity(gid: identifier) {
                entities.append(entity)
            }
        }
        return entities
    }

    func suggestedEntities() async throws -> [GalleryEntity] {
        await service.recentEntities()
    }

    func entities(matching string: String) async throws -> [GalleryEntity] {
        await service.localEntities(matching: string)
    }
}
