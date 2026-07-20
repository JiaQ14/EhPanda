//
//  CoreAppIntents.swift
//  EhPanda
//

import AppIntents

enum AppIntentSection: String, AppEnum, Codable, Sendable {
    case home
    case popular
    case history
    case favorites
    case cache
    case search
    case settings

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Section")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .home: "Home",
        .popular: "Popular",
        .history: "History",
        .favorites: "Favorites",
        .cache: "Cache",
        .search: "Search",
        .settings: "Settings"
    ]

    var navigationItem: AppNavigationItem {
        switch self {
        case .home: .home
        case .popular: .popular
        case .history: .history
        case .favorites: .favorites
        case .cache: .cache
        case .search: .search
        case .settings: .setting
        }
    }
}

struct OpenSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Section"
    static let description = IntentDescription("Open a section in EhPanda.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Section")
    var section: AppIntentSection

    init() {}

    init(section: AppIntentSection) {
        self.section = section
    }

    func perform() async throws -> some IntentResult {
        AppIntentNavigationStore.shared.enqueue(.section(section))
        return .result()
    }
}

struct SearchGalleriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Galleries"
    static let description = IntentDescription("Search for galleries in EhPanda.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Search text")
    var query: String

    init() {}

    init(query: String) {
        self.query = query
    }

    func perform() async throws -> some IntentResult {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .result() }
        AppIntentNavigationStore.shared.enqueue(.search(query))
        return .result()
    }
}

struct OpenGalleryIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Gallery"
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Gallery")
    var target: GalleryEntity

    init() {}

    init(target: GalleryEntity) {
        self.target = target
    }

    func perform() async throws -> some IntentResult {
        AppIntentNavigationStore.shared.enqueue(
            .gallery(gid: target.id, readingProgress: nil)
        )
        return .result()
    }
}

struct ContinueReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Reading"
    static let description = IntentDescription("Continue reading a recent gallery in EhPanda.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Gallery")
    var gallery: GalleryEntity?

    @Dependency(default: IntentGalleryService.shared)
    private var service: IntentGalleryService

    init() {}

    init(gallery: GalleryEntity?) {
        self.gallery = gallery
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = if let gallery {
            gallery
        } else {
            await service.recentEntities(limit: 1).first
        }
        guard let target else {
            return .result(dialog: "There is no recent gallery to continue.")
        }
        let progress = await service.readingProgress(gid: target.id) ?? 0
        AppIntentNavigationStore.shared.enqueue(
            .gallery(gid: target.id, readingProgress: progress)
        )
        return .result(dialog: "Continuing \(target.title).")
    }
}

struct RefreshCacheLibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Cache Library"
    static let description = IntentDescription("Synchronize the EhPanda cache library with files on disk.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Dependency(default: IntentGalleryService.shared)
    private var service: IntentGalleryService

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = await service.refreshCacheLibrary()
        return .result(dialog: "The cache library now contains \(count) galleries.")
    }
}
