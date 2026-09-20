//
//  AppUtil.swift
//  EhPanda
//

import Foundation

struct AppUtil {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "null"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "null"
    }

    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static var galleryHost: GalleryHost {
        let rawValue: String? = UserDefaultsUtil.value(forKey: .galleryHost)
        return GalleryHost(rawValue: rawValue ?? "") ?? .ehentai
    }

    static func dispatchMainSync(execute work: () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}
