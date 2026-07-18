//
//  CacheView.swift
//  EhPanda
//

import SwiftUI
import ComposableArchitecture

struct CacheView: View {
    @Bindable private var store: StoreOf<CacheReducer>
    @FocusState private var isSearchFocused: Bool
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator
    private let embedsInNavigationStack: Bool
    @State private var showsDeleteAllConfirmation = false

    init(
        store: StoreOf<CacheReducer>,
        user: User,
        setting: Binding<Setting>,
        blurRadius: Double,
        tagTranslator: TagTranslator,
        embedsInNavigationStack: Bool = true
    ) {
        self.store = store
        self.user = user
        _setting = setting
        self.blurRadius = blurRadius
        self.tagTranslator = tagTranslator
        self.embedsInNavigationStack = embedsInNavigationStack
    }

    private var options: CacheDownloadOptions {
        .init(setting: setting)
    }

    private var filteredItems: [GalleryCacheItem] {
        guard !store.searchText.isEmpty else { return store.items }
        return store.items.filter {
            GalleryLocalSearchMatcher.matches(
                gallery: $0.gallery,
                query: store.searchText,
                additionalText: [
                    $0.detail.title,
                    $0.detail.jpnTitle,
                    $0.id
                ].compactMap { $0 }
            )
        }
    }

    private var orderedItems: [GalleryCacheItem] {
        filteredItems.sorted { $0.createdDate > $1.createdDate }
    }

    private var displayGalleries: [Gallery] {
        orderedItems.map { item in
            var gallery = item.gallery
            gallery.title = displayTitle(for: item)
            gallery.pageCount = item.pageCount
            return gallery
        }
    }

    private var listPresentations: [String: GalleryListPresentation] {
        Dictionary(uniqueKeysWithValues: orderedItems.map { item in
            (
                item.id,
                GalleryListPresentation(
                    coverURL: item.coverFileURL
                        ?? item.detail.coverURL
                        ?? item.gallery.coverURL,
                    status: listStatus(for: item),
                    actionRevision: cacheActionRevision
                )
            )
        })
    }

    @ViewBuilder var body: some View {
        if embedsInNavigationStack {
            NavigationStack {
                navigationContent
            }
        } else {
            navigationContent
        }
    }

    private var navigationContent: some View {
        Group {
            if store.items.isEmpty {
                ContentUnavailableView(
                    L10n.Localizable.CacheView.Empty.Title.cache,
                    systemImage: "square.and.arrow.down",
                    description: Text(L10n.Localizable.CacheView.Empty.Description.cache)
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            } else {
                cacheList
            }
        }
        .navigationTitle(L10n.Localizable.CacheView.Title.cache)
        .navigationDestination(item: $store.route.sending(\.setNavigation).detail) { gid in
            DetailView(
                store: store.scope(state: \.detailState.wrappedValue!, action: \.detail),
                gid: gid,
                user: user,
                setting: $setting,
                blurRadius: blurRadius,
                tagTranslator: tagTranslator
            )
        }
        .searchable(
            text: $store.searchText,
            prompt: L10n.Localizable.CacheView.Search.Prompt.cache
        )
        .searchFocused($isSearchFocused)
        .overlay {
            TagSuggestionOverlay(
                keyword: $store.searchText,
                translations: tagTranslator.translations,
                showsImages: setting.showsImagesInTags,
                isEnabled: setting.showsTagsSearchSuggestion,
                isPresented: isSearchFocused,
                maximumCount: 5
            )
        }
        .toolbar { toolbarContent }
        .confirmationDialog(
            L10n.Localizable.CacheView.Confirmation.DeleteAll.title,
            isPresented: $showsDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                L10n.Localizable.CacheView.Button.deleteAll,
                role: .destructive
            ) {
                store.send(.deleteAll)
            }
        } message: {
            Text(L10n.Localizable.CacheView.Confirmation.DeleteAll.message)
        }
        .onAppear {
            store.send(.onAppear(
                options,
                resumesAutomatically: setting.cacheResumesAutomatically
            ))
        }
    }

    private var cacheList: some View {
        GenericList(
            galleries: displayGalleries,
            setting: setting,
            translationRevision: tagTranslator.renderRevision,
            datasetIdentity: "cache-library",
            presentations: listPresentations,
            actionsProvider: listActions,
            pageNumber: nil,
            loadingState: .idle,
            footerLoadingState: .idle,
            navigateAction: { store.send(.openDetail($0)) },
            translateAction: {
                tagTranslator.lookup(
                    word: $0,
                    returnOriginal: !setting.translatesTags
                )
            }
        )
        .environment(
            \.galleryContextMenuConfiguration,
            .downloadsOnly(
                user: user,
                setting: setting,
                blurRadius: blurRadius,
                tagTranslator: tagTranslator
            )
        )
    }

    private func displayTitle(for item: GalleryCacheItem) -> String {
        if setting.displaysJapaneseTitle,
           let title = item.detail.jpnTitle,
           !title.isEmpty
        {
            return title
        }
        return item.detail.title.isEmpty ? item.gallery.title : item.detail.title
    }

    private func listStatus(for item: GalleryCacheItem) -> GalleryListStatus {
        let pages = L10n.Localizable.CacheView.Value.pages(
            "\(item.cachedPageCount)",
            "\(item.pageCount)"
        )
        let detailText = item.byteCount > 0
            ? [
                pages,
                ByteCountFormatter.string(
                    fromByteCount: item.byteCount,
                    countStyle: .file
                )
            ].joined(separator: "  ")
            : pages

        return GalleryListStatus(
            text: item.status.value,
            detailText: detailText,
            message: item.status == .failed ? item.errorDescription : nil,
            systemImage: statusSymbol(for: item.status),
            tone: statusTone(for: item.status),
            progress: item.isComplete ? nil : item.progress
        )
    }

    private var cacheActionRevision: AnyHashable {
        AnyHashable([
            setting.cacheImageQuality.rawValue,
            setting.cacheConcurrentDownloads,
            setting.cacheAllowsCellularAccess ? 1 : 0,
            setting.bypassesSNIFiltering ? 1 : 0
        ])
    }

    private func listActions(for gid: String) -> [GalleryListAction] {
        guard let item = store.items.first(where: { $0.id == gid }) else {
            return []
        }

        var actions = [GalleryListAction]()
        if item.status.isActive {
            actions.append(
                GalleryListAction(
                    title: L10n.Localizable.CacheView.Button.pause,
                    systemImage: "pause.fill",
                    role: .normal,
                    edge: .leading,
                    tint: .orange,
                    action: { store.send(.pause(gid)) }
                )
            )
        } else if !item.isComplete {
            actions.append(
                GalleryListAction(
                    title: item.status == .failed
                        ? L10n.Localizable.CacheView.Button.retry
                        : L10n.Localizable.CacheView.Button.resume,
                    systemImage: item.status == .failed
                        ? "arrow.clockwise"
                        : "play.fill",
                    role: .normal,
                    edge: .leading,
                    tint: .green,
                    action: { store.send(.resume(gid, options)) }
                )
            )
        }

        actions.append(
            GalleryListAction(
                title: L10n.Localizable.CacheView.Button.delete,
                systemImage: "trash",
                role: .destructive,
                edge: .trailing,
                tint: .red,
                action: { store.send(.delete(gid)) }
            )
        )
        return actions
    }

    private func statusSymbol(for status: GalleryCacheStatus) -> String {
        switch status {
        case .queued:
            return "clock"
        case .resolving:
            return "link"
        case .downloading:
            return "arrow.down.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private func statusTone(
        for status: GalleryCacheStatus
    ) -> GalleryListStatusTone {
        switch status {
        case .completed:
            return .success
        case .failed:
            return .failure
        case .paused:
            return .warning
        case .queued, .resolving, .downloading:
            return .accent
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    store.send(.resumeAll(options))
                } label: {
                    Label(L10n.Localizable.CacheView.Button.resumeAll, systemImage: "play.fill")
                }
                .disabled(!store.items.contains(where: { !$0.isComplete && !$0.status.isActive }))

                Button {
                    store.send(.pauseAll)
                } label: {
                    Label(L10n.Localizable.CacheView.Button.pauseAll, systemImage: "pause.fill")
                }
                .disabled(!store.items.contains(where: \.status.isActive))

                Divider()

                Button(role: .destructive) {
                    showsDeleteAllConfirmation = true
                } label: {
                    Label(L10n.Localizable.CacheView.Button.deleteAll, systemImage: "trash")
                }
                .disabled(store.items.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(L10n.Localizable.CacheView.Button.more)
        }
    }
}

enum GalleryLocalSearchMatcher {
    static func matches(
        gallery: Gallery,
        query: String,
        additionalText: [String]
    ) -> Bool {
        let normalizedQuery = TagSuggestionEngine.normalizedText(query)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }

        let textValues = additionalText
            + [gallery.title, gallery.uploader].compactMap { $0 }
        let tagKeywords = tagSearchKeywords(for: gallery)
        return tokens(in: normalizedQuery).allSatisfy { token in
            if isCompletedTag(token) {
                return tagKeywords.contains(token.lowercased())
            }

            let text = token.trimmingCharacters(
                in: CharacterSet(charactersIn: "\"")
            )
            return textValues.contains {
                $0.localizedCaseInsensitiveContains(text)
            }
        }
    }

    static func tokens(in query: String) -> [String] {
        guard let regex = Defaults.Regex.tagSuggestion else { return [] }
        let range = NSRange(query.startIndex..<query.endIndex, in: query)
        return regex.matches(in: query, range: range).compactMap {
            Range($0.range, in: query).map { String(query[$0]) }
        }
    }

    private static func isCompletedTag(_ token: String) -> Bool {
        token.hasSuffix("$") || token.hasSuffix("$\"")
    }

    private static func tagSearchKeywords(for gallery: Gallery) -> Set<String> {
        Set(gallery.tags.flatMap { tag in
            tag.contents.flatMap { content -> [String] in
                let value = content.text.contains(" ")
                    ? "\"\(content.text)$\""
                    : "\(content.text)$"
                var namespaces = [tag.rawNamespace]
                if let abbreviation = tag.namespace?.abbreviation {
                    namespaces.append(abbreviation)
                }
                var keywords = namespaces.map { "\($0):\(value)" }
                if tag.namespace == .temp {
                    keywords.append(value)
                }
                return keywords.map { $0.lowercased() }
            }
        })
    }
}

struct CacheView_Previews: PreviewProvider {
    static var previews: some View {
        CacheView(
            store: .init(initialState: .init(), reducer: CacheReducer.init),
            user: .init(),
            setting: .constant(.init()),
            blurRadius: 0,
            tagTranslator: .init()
        )
    }
}
