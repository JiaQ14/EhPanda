//
//  GalleryCache.swift
//  EhPanda
//

import Foundation

enum CacheImageQuality: Int, Codable, CaseIterable, Identifiable {
    var id: Int { rawValue }

    case standard
    case original
}

struct CacheDownloadOptions: Equatable {
    let imageQuality: CacheImageQuality
    let concurrentDownloads: Int
    let allowsCellularAccess: Bool
    let bypassesSNIFiltering: Bool

    init(
        imageQuality: CacheImageQuality,
        concurrentDownloads: Int,
        allowsCellularAccess: Bool,
        bypassesSNIFiltering: Bool = false
    ) {
        self.imageQuality = imageQuality
        self.concurrentDownloads = min(max(concurrentDownloads, 1), 6)
        self.allowsCellularAccess = allowsCellularAccess
        self.bypassesSNIFiltering = bypassesSNIFiltering
    }

    init(setting: Setting) {
        self.init(
            imageQuality: setting.cacheImageQuality,
            concurrentDownloads: setting.cacheConcurrentDownloads,
            allowsCellularAccess: setting.cacheAllowsCellularAccess,
            bypassesSNIFiltering: setting.bypassesSNIFiltering
        )
    }
}

struct GalleryCacheImageSnapshot: Equatable {
    static let empty = Self(
        directoryIdentifier: nil,
        pageIdentifiers: [:],
        urls: [:]
    )

    let directoryIdentifier: UUID?
    let pageIdentifiers: [Int: UUID]
    let urls: [Int: URL]
}

enum GalleryCacheStatus: String, Codable, Equatable {
    case queued
    case resolving
    case downloading
    case paused
    case completed
    case failed

    var isActive: Bool {
        switch self {
        case .queued, .resolving, .downloading:
            return true
        case .paused, .completed, .failed:
            return false
        }
    }

    var value: String {
        switch self {
        case .queued:
            return L10n.Localizable.CacheView.Status.queued
        case .resolving:
            return L10n.Localizable.CacheView.Status.resolving
        case .downloading:
            return L10n.Localizable.CacheView.Status.downloading
        case .paused:
            return L10n.Localizable.CacheView.Status.paused
        case .completed:
            return L10n.Localizable.CacheView.Status.completed
        case .failed:
            return L10n.Localizable.CacheView.Status.failed
        }
    }
}

struct GalleryCacheItem: Codable, Equatable, Identifiable {
    static let manifestFileName = ".ehpanda-cache.json"
    static let maximumPageCount = 10_000

    var id: String { gallery.id }
    var cachedPageCount: Int {
        guard Self.isValidPageCount(pageCount) else { return 0 }
        return pageFiles.keys.lazy.filter { index in
            index >= 1 && index <= pageCount
        }.count
    }
    var progress: Double {
        guard pageCount > 0 else { return 0 }
        return Double(cachedPageCount) / Double(pageCount)
    }
    var hasAllPages: Bool {
        pageCount > 0 && cachedPageCount == pageCount
    }
    var isComplete: Bool {
        status == .completed && hasAllPages
    }
    var displayTitle: String {
        detail.jpnTitle ?? detail.title
    }
    var directoryURL: URL? {
        guard let rootURL = FileUtil.galleryCachesDirectoryURL else { return nil }
        return Self.validatedChildURL(
            named: folderName,
            in: rootURL,
            isDirectory: true,
            allowsMissing: true
        )
    }
    var coverFileURL: URL? {
        guard let directoryURL, let coverFileName else { return nil }
        return Self.validatedChildURL(named: coverFileName, in: directoryURL)
    }
    var localImageURLs: [Int: URL] {
        guard Self.isValidPageCount(pageCount), let directoryURL else { return [:] }
        return Dictionary(uniqueKeysWithValues: pageFiles.compactMap { index, fileName in
            guard index >= 1, index <= pageCount,
                  let url = Self.validatedChildURL(named: fileName, in: directoryURL)
            else { return nil }
            return (index, url)
        })
    }
    var managedLocalImageURLs: [Int: URL] {
        guard Self.isValidPageCount(pageCount), let directoryURL else { return [:] }
        return Dictionary(uniqueKeysWithValues: pageFiles.compactMap { index, fileName in
            guard index >= 1, index <= pageCount,
                  let url = Self.childURL(named: fileName, in: directoryURL)
            else { return nil }
            return (index, url)
        })
    }

    let gallery: Gallery
    let detail: GalleryDetail
    var folderName: String
    let pageCount: Int
    let createdDate: Date
    var directoryIdentifier: UUID?

    var status: GalleryCacheStatus
    var imageQuality: CacheImageQuality
    var updatedDate: Date
    var byteCount: Int64
    var errorDescription: String?
    var coverFileName: String?
    var pageFiles: [Int: String]
    var pageIdentifiers: [Int: UUID]?
    var remoteImageURLs: [Int: URL]
    var originalImageURLs: [Int: URL]

    static func isValidPageCount(_ pageCount: Int) -> Bool {
        (1...maximumPageCount).contains(pageCount)
    }
}

private extension GalleryCacheItem {
    static func validatedChildURL(
        named name: String,
        in parentURL: URL,
        isDirectory: Bool = false,
        allowsMissing: Bool = false
    ) -> URL? {
        guard let childURL = childURL(named: name, in: parentURL, isDirectory: isDirectory) else {
            return nil
        }
        let standardizedParent = parentURL.standardizedFileURL
        let resolvedParent = standardizedParent.resolvingSymlinksInPath()
        let resolvedChild = childURL.resolvingSymlinksInPath()
        guard resolvedChild.deletingLastPathComponent() == resolvedParent else { return nil }
        if let resourceValues = try? childURL.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        ) {
            guard resourceValues.isSymbolicLink != true else { return nil }
            if isDirectory {
                guard resourceValues.isDirectory == true else { return nil }
            } else {
                guard resourceValues.isRegularFile == true else { return nil }
            }
        } else if !allowsMissing {
            return nil
        }
        return childURL
    }

    static func childURL(
        named name: String,
        in parentURL: URL,
        isDirectory: Bool = false
    ) -> URL? {
        guard !name.isEmpty, name != ".", name != "..",
              URL(fileURLWithPath: name).lastPathComponent == name
        else { return nil }

        let standardizedParent = parentURL.standardizedFileURL
        let childURL = standardizedParent
            .appendingPathComponent(name, isDirectory: isDirectory)
            .standardizedFileURL
        guard childURL.deletingLastPathComponent() == standardizedParent else { return nil }
        return childURL
    }
}
