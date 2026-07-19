//
//  FileUtil.swift
//  EhPanda
//

import Foundation

struct FileUtil {
    static var documentDirectory: URL? {
        url(for: .documentDirectory)
    }
    static var cachesDirectory: URL? {
        url(for: .cachesDirectory)
    }
    static var logsDirectoryURL: URL? {
        documentDirectory?.appendingPathComponent(Defaults.FilePath.logs)
    }
    static var galleryCachesDirectoryURL: URL? {
        validatedGalleryCachesDirectoryURL(createIfNeeded: false)
    }
    static var galleryCacheLibraryIndexURL: URL? {
        cachesDirectory?.appendingPathComponent("GalleryCacheLibraryIndex-v1.json")
    }
    static var temporaryDirectory: URL {
        .init(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    static func url(for searchPathDirectory: FileManager.SearchPathDirectory) -> URL? {
        try? FileManager.default.url(for: searchPathDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    static func prepareGalleryCachesDirectoryURL() -> URL? {
        validatedGalleryCachesDirectoryURL(createIfNeeded: true)
    }

    private static func validatedGalleryCachesDirectoryURL(createIfNeeded: Bool) -> URL? {
        guard let documentsURL = documentDirectory?.standardizedFileURL else { return nil }
        let rootURL = documentsURL
            .appendingPathComponent("Downloads", isDirectory: true)
            .standardizedFileURL
        guard rootURL.deletingLastPathComponent() == documentsURL else { return nil }

        if createIfNeeded {
            do {
                try FileManager.default.createDirectory(
                    at: rootURL,
                    withIntermediateDirectories: true
                )
            } catch {
                return nil
            }
        }

        guard let resourceValues = try? rootURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ),
              resourceValues.isDirectory == true,
              resourceValues.isSymbolicLink != true
        else { return nil }

        let resolvedDocumentsURL = documentsURL.resolvingSymlinksInPath()
        let resolvedRootURL = rootURL.resolvingSymlinksInPath()
        guard resolvedRootURL.deletingLastPathComponent() == resolvedDocumentsURL else {
            return nil
        }
        return rootURL
    }
}
