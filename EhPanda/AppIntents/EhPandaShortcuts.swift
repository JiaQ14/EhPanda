//
//  EhPandaShortcuts.swift
//  EhPanda
//

import AppIntents

struct EhPandaShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueReadingIntent(),
            phrases: [
                "Continue reading in \(.applicationName)",
                "在\(.applicationName)中继续阅读"
            ],
            shortTitle: "Continue Reading",
            systemImageName: "book.pages"
        )
        AppShortcut(
            intent: SearchGalleriesIntent(),
            phrases: [
                "Search \(.applicationName)",
                "用\(.applicationName)搜索漫画"
            ],
            shortTitle: "Search Galleries",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenSectionIntent(section: .cache),
            phrases: [
                "Open \(.applicationName) cache",
                "打开\(.applicationName)缓存"
            ],
            shortTitle: "Open Cache",
            systemImageName: "arrow.down.circle"
        )
        AppShortcut(
            intent: RefreshCacheLibraryIntent(),
            phrases: [
                "Refresh \(.applicationName) cache",
                "刷新\(.applicationName)缓存列表"
            ],
            shortTitle: "Refresh Cache",
            systemImageName: "arrow.clockwise"
        )
    }
}

enum AppIntentDependencies {
    static func register() {
        AppDependencyManager.shared.add(dependency: IntentGalleryService.shared)
        AppDependencyManager.shared.add(dependency: GalleryVisualSearchService.shared)
    }
}
