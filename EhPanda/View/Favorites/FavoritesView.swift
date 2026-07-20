//
//  FavoritesView.swift
//  EhPanda
//

import SwiftUI
import AlertKit
import ComposableArchitecture

struct FavoritesView: View {
    @Bindable private var store: StoreOf<FavoritesReducer>
    @FocusState private var isSearchFocused: Bool
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator
    private let embedsInNavigationStack: Bool

    init(
        store: StoreOf<FavoritesReducer>,
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

    private var navigationTitle: String {
        let favoriteCategory = user.getFavoriteCategory(index: store.index)
        return (store.index == -1 ? L10n.Localizable.FavoritesView.Title.favorites : favoriteCategory)
    }

    var body: some View {
        content
            .embeddedInNavigationStack(embedsInNavigationStack)
            .adaptiveGalleryDetail(
            selection: $store.route.sending(\.setNavigation).detail,
            blurRadius: blurRadius
        ) { gid in
            GalleryDetailContainer(
                gid: gid, user: user, setting: $setting,
                blurRadius: blurRadius, tagTranslator: tagTranslator
            )
        }
    }

    private var content: some View {
        ZStack {
            if CookieUtil.didLogin {
                GenericList(
                    galleries: store.galleries ?? [],
                    setting: setting,
                    translationRevision: tagTranslator.renderRevision,
                    datasetIdentity: store.index,
                    pageNumber: store.pageNumber,
                    loadingState: store.loadingState ?? .idle,
                    footerLoadingState: store.footerLoadingState ?? .idle,
                    fetchAction: { await store.send(.fetchGalleries()).finish() },
                    fetchMoreAction: { store.send(.fetchMoreGalleries) },
                    navigateAction: { store.send(.setNavigation(.detail($0))) },
                    translateAction: {
                        tagTranslator.lookup(word: $0, returnOriginal: !setting.translatesTags)
                    }
                )
                .environment(
                    \.galleryContextMenuConfiguration,
                    .standard(
                        user: user,
                        setting: setting,
                        blurRadius: blurRadius,
                        tagTranslator: tagTranslator,
                        defaultFavoriteState: true
                    )
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
            if store.galleries?.isEmpty != false && CookieUtil.didLogin {
                DispatchQueue.main.async {
                    store.send(.fetchGalleries())
                }
            }
        }
        .toolbar(content: toolbar)
        .navigationTitle(navigationTitle)
    }

    private func toolbar() -> some ToolbarContent {
        CustomToolbarItem(tint: .primary) {
            FavoritesIndexMenu(user: user, index: store.index) { index in
                if index != store.index {
                    store.send(.setFavoritesIndex(index))
                }
            }
            SortOrderMenu(sortOrder: store.sortOrder) { order in
                if store.sortOrder != order {
                    store.send(.fetchGalleries(nil, order))
                }
            }
            QuickSearchButton(hideText: true) {
                store.send(.setNavigation(.quickSearch()))
            }
        }
    }
}

struct FavoritesView_Previews: PreviewProvider {
    static var previews: some View {
        FavoritesView(
            store: .init(initialState: .init(), reducer: FavoritesReducer.init),
            user: .init(),
            setting: .constant(.init()),
            blurRadius: 0,
            tagTranslator: .init()
        )
    }
}
