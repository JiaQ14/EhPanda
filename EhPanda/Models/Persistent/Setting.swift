//
//  Setting.swift
//  EhPanda
//

import SwiftUI
import Foundation
import ComposableArchitecture

enum AppNavigationItem: String, Codable, CaseIterable, Hashable, Identifiable {
    var id: String { rawValue }

    case home
    case search
    case popular
    case watched
    case history
    case favorites
    case cache
    case setting
    case more

    static let configurableItems: [Self] = [
        .search, .popular, .watched, .history, .favorites, .cache
    ]
}

enum NavigationItemGroup: Equatable {
    case tabBar
    case more
}

struct Setting: Codable, Equatable {
    // Account
    var galleryHost: GalleryHost = .ehentai
    var showsNewDawnGreeting = false

    // General
    var enablesTagsExtension = false {
        didSet {
            if !enablesTagsExtension {
                translatesTags = false
                showsTagsSearchSuggestion = false
                showsImagesInTags = false
            }
        }
    }
    var translatesTags = false
    var showsTagsSearchSuggestion = false
    var showsImagesInTags = false
    var redirectsLinksToSelectedHost = false
    var detectsLinksFromClipboard = false
    var backgroundBlurRadius: Double = 10
    var autoLockPolicy: AutoLockPolicy = .never

    // Appearance
    var listDisplayMode: ListDisplayMode = DeviceUtil.isPadWidth ? .waterfall : .detail
    var preferredColorScheme = PreferredColorScheme.automatic
    var accentColor: Color = .blue
    var appIconType: AppIconType = .default
    var showsTagsInList = false
    var listTagsNumberMaximum = 0
    var displaysJapaneseTitle = true

    // Navigation
    var tabBarItems: [AppNavigationItem] = [.search]
    var moreItems: [AppNavigationItem] = [
        .popular, .watched, .history, .favorites, .cache
    ]

    // Cache
    var cacheImageQuality: CacheImageQuality = .standard
    var cacheConcurrentDownloads = 3
    var cacheAllowsCellularAccess = false
    var cacheResumesAutomatically = true

    // Reading
    var readingDirection: ReadingDirection = .vertical
    var prefetchLimit = 10
    var enablesLandscape = false
    var enablesDualPageMode = false
    var exceptCover = false
    var avoidsStatusBarInVerticalMode = true
    var contentDividerHeight: Double = 0
    var maximumScaleFactor: Double = 3
    var doubleTapScaleFactor: Double = 2

    // Laboratory
    var bypassesSNIFiltering = false
}

enum GalleryHost: String, Codable, Equatable, CaseIterable, Identifiable {
    case ehentai = "E-Hentai"
    case exhentai = "ExHentai"

    var id: Int { hashValue }
    var url: URL {
        switch self {
        case .ehentai:
            return Defaults.URL.ehentai
        case .exhentai:
            return Defaults.URL.exhentai
        }
    }
    var cookieURLs: [URL] {
        switch self {
        case .ehentai:
            return [Defaults.URL.ehentai]

        case .exhentai:
            return [Defaults.URL.exhentai, Defaults.URL.sexhentai]
        }
    }
    var abbr: String {
        switch self {
        case .ehentai:
            return "eh"
        case .exhentai:
            return "ex"
        }
    }
}

enum AutoLockPolicy: Int, Codable, CaseIterable, Identifiable {
    var id: Int { rawValue }

    case never = -1
    case instantly = 0
    case sec15 = 15
    case min1 = 60
    case min5 = 300
    case min10 = 600
    case min30 = 1800
}

extension AutoLockPolicy {
    var value: String {
        switch self {
        case .never:
            return L10n.Localizable.Enum.AutoLockPolicy.Value.never
        case .instantly:
            return L10n.Localizable.Enum.AutoLockPolicy.Value.instantly
        case .sec15:
            return L10n.Localizable.Common.Value.seconds("\(rawValue)")
        case .min1:
            return L10n.Localizable.Common.Value.minute("\(rawValue / 60)")
        case .min5, .min10, .min30:
            return L10n.Localizable.Common.Value.minutes("\(rawValue / 60)")
        }
    }
}

enum PreferredColorScheme: Int, Codable, CaseIterable, Identifiable {
    var id: Int { rawValue }

    case automatic
    case light
    case dark
}
extension PreferredColorScheme {
    var value: String {
        switch self {
        case .automatic:
            return L10n.Localizable.Enum.PreferredColorScheme.Value.automatic
        case .light:
            return L10n.Localizable.Enum.PreferredColorScheme.Value.light
        case .dark:
            return L10n.Localizable.Enum.PreferredColorScheme.Value.dark
        }
    }
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .automatic:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum ReadingDirection: Int, Codable, CaseIterable, Identifiable {
    var id: Int { rawValue }

    case vertical
    case rightToLeft
    case leftToRight
}
extension ReadingDirection {
    var value: String {
        switch self {
        case .vertical:
            return L10n.Localizable.Enum.ReadingDirection.Value.vertical
        case .rightToLeft:
            return L10n.Localizable.Enum.ReadingDirection.Value.rightToLeft
        case .leftToRight:
            return L10n.Localizable.Enum.ReadingDirection.Value.leftToRight
        }
    }
}

enum ListDisplayMode: Int, Codable, CaseIterable, Identifiable {
    var id: Int { rawValue }

    case detail
    case waterfall
}
extension ListDisplayMode {
    var value: String {
        switch self {
        case .detail:
            return L10n.Localizable.Enum.ListDisplayMode.Value.detail
        case .waterfall:
            return L10n.Localizable.Enum.ListDisplayMode.Value.waterfall
        }
    }
}

extension Setting {
    static let maximumConfigurableTabCount = 3

    mutating func normalizeNavigationItems() {
        let configurableItems = Set(AppNavigationItem.configurableItems)
        var seen = Set<AppNavigationItem>()

        let normalizedTabItems = tabBarItems.filter {
            configurableItems.contains($0)
                && seen.insert($0).inserted
        }
        let overflow = normalizedTabItems.dropFirst(Self.maximumConfigurableTabCount)
        tabBarItems = Array(normalizedTabItems.prefix(Self.maximumConfigurableTabCount))
        seen = Set(tabBarItems)

        moreItems = (Array(overflow) + moreItems).filter {
            configurableItems.contains($0)
                && !tabBarItems.contains($0)
                && seen.insert($0).inserted
        }
        moreItems.append(contentsOf: AppNavigationItem.configurableItems.filter {
            !seen.contains($0)
        })
    }

    @discardableResult
    mutating func moveNavigationItem(
        _ item: AppNavigationItem,
        to destination: NavigationItemGroup,
        at rawDestinationIndex: Int
    ) -> Bool {
        guard AppNavigationItem.configurableItems.contains(item) else { return false }

        let source: NavigationItemGroup = tabBarItems.contains(item) ? .tabBar : .more
        let sourceIndex = source == .tabBar
            ? tabBarItems.firstIndex(of: item)
            : moreItems.firstIndex(of: item)
        let displacedItem =
            destination == .tabBar
            && source != .tabBar
            && tabBarItems.count >= Self.maximumConfigurableTabCount
            ? tabBarItems.last
            : nil
        tabBarItems.removeAll { $0 == item }
        moreItems.removeAll { $0 == item }
        if let displacedItem {
            tabBarItems.removeAll { $0 == displacedItem }
            let replacementIndex = min(
                max(sourceIndex ?? 0, 0),
                moreItems.count
            )
            moreItems.insert(displacedItem, at: replacementIndex)
        }

        var destinationIndex = rawDestinationIndex
        if source == destination,
           let sourceIndex,
           sourceIndex < destinationIndex {
            destinationIndex -= 1
        }

        switch destination {
        case .tabBar:
            destinationIndex = min(max(destinationIndex, 0), tabBarItems.count)
            tabBarItems.insert(item, at: destinationIndex)
        case .more:
            destinationIndex = min(max(destinationIndex, 0), moreItems.count)
            moreItems.insert(item, at: destinationIndex)
        }
        normalizeNavigationItems()
        return true
    }

}

// swiftlint:disable line_length
// MARK: Manually decode
extension Setting {
    init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        // Account
        galleryHost = (try? container?.decodeIfPresent(GalleryHost.self, forKey: .galleryHost)) ?? .ehentai
        showsNewDawnGreeting = (try? container?.decodeIfPresent(Bool.self, forKey: .showsNewDawnGreeting)) ?? false
        // General
        enablesTagsExtension = (try? container?.decodeIfPresent(Bool.self, forKey: .enablesTagsExtension)) ?? false
        translatesTags = (try? container?.decodeIfPresent(Bool.self, forKey: .translatesTags)) ?? false
        showsTagsSearchSuggestion = (try? container?.decodeIfPresent(Bool.self, forKey: .showsTagsSearchSuggestion)) ?? false
        showsImagesInTags = (try? container?.decodeIfPresent(Bool.self, forKey: .showsImagesInTags)) ?? false
        redirectsLinksToSelectedHost = (try? container?.decodeIfPresent(Bool.self, forKey: .redirectsLinksToSelectedHost)) ?? false
        detectsLinksFromClipboard = (try? container?.decodeIfPresent(Bool.self, forKey: .detectsLinksFromClipboard)) ?? false
        backgroundBlurRadius = (try? container?.decodeIfPresent(Double.self, forKey: .backgroundBlurRadius)) ?? 10
        autoLockPolicy = (try? container?.decodeIfPresent(AutoLockPolicy.self, forKey: .autoLockPolicy)) ?? .never
        // Appearance
        listDisplayMode = (try? container?.decodeIfPresent(ListDisplayMode.self, forKey: .listDisplayMode)) ?? (DeviceUtil.isPadWidth ? .waterfall : .detail)
        preferredColorScheme = (try? container?.decodeIfPresent(PreferredColorScheme.self, forKey: .preferredColorScheme)) ?? .automatic
        accentColor = (try? container?.decodeIfPresent(Color.self, forKey: .accentColor)) ?? .blue
        appIconType = (try? container?.decodeIfPresent(AppIconType.self, forKey: .appIconType)) ?? .default
        showsTagsInList = (try? container?.decodeIfPresent(Bool.self, forKey: .showsTagsInList)) ?? false
        listTagsNumberMaximum = (try? container?.decodeIfPresent(Int.self, forKey: .listTagsNumberMaximum)) ?? 0
        displaysJapaneseTitle = (try? container?.decodeIfPresent(Bool.self, forKey: .displaysJapaneseTitle)) ?? true
        // Navigation
        tabBarItems = (try? container?.decodeIfPresent([AppNavigationItem].self, forKey: .tabBarItems)) ?? [.search]
        moreItems = (try? container?.decodeIfPresent([AppNavigationItem].self, forKey: .moreItems))
            ?? [.popular, .watched, .history, .favorites, .cache]
        normalizeNavigationItems()
        // Cache
        cacheImageQuality = (try? container?.decodeIfPresent(CacheImageQuality.self, forKey: .cacheImageQuality)) ?? .standard
        cacheConcurrentDownloads = (try? container?.decodeIfPresent(Int.self, forKey: .cacheConcurrentDownloads)) ?? 3
        cacheAllowsCellularAccess = (try? container?.decodeIfPresent(Bool.self, forKey: .cacheAllowsCellularAccess)) ?? false
        cacheResumesAutomatically = (try? container?.decodeIfPresent(Bool.self, forKey: .cacheResumesAutomatically)) ?? true
        // Reading
        readingDirection = (try? container?.decodeIfPresent(ReadingDirection.self, forKey: .readingDirection)) ?? .vertical
        prefetchLimit = (try? container?.decodeIfPresent(Int.self, forKey: .prefetchLimit)) ?? 10
        enablesLandscape = (try? container?.decodeIfPresent(Bool.self, forKey: .enablesLandscape)) ?? false
        enablesDualPageMode = (try? container?.decodeIfPresent(Bool.self, forKey: .enablesDualPageMode)) ?? false
        exceptCover = (try? container?.decodeIfPresent(Bool.self, forKey: .exceptCover)) ?? false
        avoidsStatusBarInVerticalMode = (try? container?.decodeIfPresent(
            Bool.self, forKey: .avoidsStatusBarInVerticalMode
        )) ?? true
        contentDividerHeight = (try? container?.decodeIfPresent(Double.self, forKey: .contentDividerHeight)) ?? 0
        maximumScaleFactor = (try? container?.decodeIfPresent(Double.self, forKey: .maximumScaleFactor)) ?? 3
        doubleTapScaleFactor = (try? container?.decodeIfPresent(Double.self, forKey: .doubleTapScaleFactor)) ?? 2
        // Laboratory
        bypassesSNIFiltering = (try? container?.decodeIfPresent(Bool.self, forKey: .bypassesSNIFiltering)) ?? false
    }
}
// swiftlint:enable line_length
