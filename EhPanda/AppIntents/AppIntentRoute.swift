//
//  AppIntentRoute.swift
//  EhPanda
//

import Foundation

enum AppIntentRoute: Codable, Equatable, Sendable {
    case section(AppIntentSection)
    case search(String)
    case gallery(gid: String, readingProgress: Int?)
}

enum AppIntentPreferences {
    private static let visualSearchKey = "appIntent.enablesVisualSearch"

    static var enablesVisualSearch: Bool {
        UserDefaults.standard.bool(forKey: visualSearchKey)
    }

    static func update(using setting: Setting) {
        UserDefaults.standard.set(setting.enablesVisualSearch, forKey: visualSearchKey)
    }
}

final class AppIntentNavigationStore: @unchecked Sendable {
    static let shared = AppIntentNavigationStore()
    static let didEnqueueNotification = Notification.Name(
        "app.ehpanda.app-intent-navigation-requested"
    )

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let key = "appIntent.pendingNavigationRoute"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func enqueue(_ route: AppIntentRoute) {
        guard let data = try? JSONEncoder().encode(route) else { return }
        lock.withLock {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: Self.didEnqueueNotification, object: nil)
    }

    func consume() -> AppIntentRoute? {
        lock.withLock {
            guard let data = defaults.data(forKey: key) else { return nil }
            defaults.removeObject(forKey: key)
            return try? JSONDecoder().decode(AppIntentRoute.self, from: data)
        }
    }
}
