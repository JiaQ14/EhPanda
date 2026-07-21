//
//  WatchedView.swift
//  EhPanda
//

import SwiftUI
import ComposableArchitecture

struct WatchedView: View {
    @Bindable private var store: StoreOf<WatchedReducer>
    @FocusState private var isSearchFocused: Bool
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator
    private let embedsInNavigationStack: Bool

    init(
        store: StoreOf<WatchedReducer>,
        user: User, setting: Binding<Setting>, blurRadius: Double, tagTranslator: TagTranslator,
        embedsInNavigationStack: Bool = true
    ) {
        self.store = store
        self.user = user
        _setting = setting
        self.blurRadius = blurRadius
        self.tagTranslator = tagTranslator
        self.embedsInNavigationStack = embedsInNavigationStack
    }

    var body: some View {
        let content =
        ZStack {
            if CookieUtil.didLogin {
                GenericList(
                    galleries: store.galleries,
                    setting: setting,
                    translationRevision: tagTranslator.renderRevision,
                    pageNumber: store.pageNumber,
                    loadingState: store.loadingState,
                    footerLoadingState: store.footerLoadingState,
                    fetchAction: { await store.send(.fetchGalleries()).finish() },
                    fetchMoreAction: { store.send(.fetchMoreGalleries) },
                    navigateAction: { store.send(.setNavigation(.detail($0))) },
                    translateAction: {
                        tagTranslator.lookup(word: $0, returnOriginal: !setting.translatesTags)
                    }
                )
            } else {
                NotLoginView(action: { store.send(.onNotLoginViewButtonTapped) })
            }
        }
        .sheet(item: $store.route.sending(\.setNavigation).quickSearch) { _ in
            QuickSearchView(
                store: store.scope(state: \.quickSearchState, action: \.quickSearch)
            ) { keyword in
                store.send(.setNavigation(nil))
                store.send(.fetchGalleries(keyword))
            }
            .accentColor(setting.accentColor)
            .autoBlur(radius: blurRadius)
        }
        .sheet(item: $store.route.sending(\.setNavigation).filters) { _ in
            FiltersView(store: store.scope(state: \.filtersState, action: \.filters))
                .autoBlur(radius: blurRadius).environment(\.inSheet, true)
        }
        .searchable(text: $store.keyword)
        .searchFocused($isSearchFocused)
        .tagSuggestionOverlay(
            keyword: $store.keyword,
            tagTranslator: tagTranslator,
            setting: setting,
            isPresented: isSearchFocused
        )
        .onSubmit(of: .search) {
            store.send(.fetchGalleries())
        }
        .onAppear {
            if store.galleries.isEmpty && CookieUtil.didLogin {
                DispatchQueue.main.async {
                    store.send(.fetchGalleries())
                }
            }
        }
        .toolbar(content: toolbar)
        .navigationTitle(L10n.Localizable.WatchedView.Title.watched)

        content
            .adaptiveGalleryDetail(
                selection: $store.route.sending(\.setNavigation).detail,
                blurRadius: blurRadius
            ) { gid in
                GalleryDetailContainer(
                    gid: gid, user: user, setting: $setting,
                    blurRadius: blurRadius, tagTranslator: tagTranslator
                )
            }
            .embeddedInNavigationStack(embedsInNavigationStack)
    }
    private func toolbar() -> some ToolbarContent {
        CustomToolbarItem {
            ToolbarFeaturesMenu {
                FiltersButton {
                    store.send(.setNavigation(.filters()))
                }
                QuickSearchButton {
                    store.send(.setNavigation(.quickSearch()))
                }
            }
        }
    }
}

struct WatchedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            WatchedView(
                store: .init(initialState: .init(), reducer: WatchedReducer.init),
                user: .init(),
                setting: .constant(.init()),
                blurRadius: 0,
                tagTranslator: .init()
            )
        }
    }
}
