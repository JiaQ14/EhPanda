//
//  PopularView.swift
//  EhPanda
//

import SwiftUI
import ComposableArchitecture

struct PopularView: View {
    @Bindable private var store: StoreOf<PopularReducer>
    @FocusState private var isSearchFocused: Bool
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator
    private let embedsInNavigationStack: Bool

    init(
        store: StoreOf<PopularReducer>,
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
        GenericList(
            galleries: store.filteredGalleries,
            setting: setting,
            translationRevision: tagTranslator.renderRevision,
            pageNumber: nil,
            loadingState: store.loadingState,
            footerLoadingState: .idle,
            fetchAction: { await store.send(.fetchGalleries).finish() },
            navigateAction: { store.send(.setNavigation(.detail($0))) },
            translateAction: {
                tagTranslator.lookup(word: $0, returnOriginal: !setting.translatesTags)
            }
        )
        .sheet(item: $store.route.sending(\.setNavigation).filters) { _ in
            FiltersView(store: store.scope(state: \.filtersState, action: \.filters))
                .autoBlur(radius: blurRadius).environment(\.inSheet, true)
        }
        .searchable(text: $store.keyword, prompt: L10n.Localizable.Searchable.Prompt.filter)
        .searchFocused($isSearchFocused)
        .tagSuggestionOverlay(
            keyword: $store.keyword,
            tagTranslator: tagTranslator,
            setting: setting,
            isPresented: isSearchFocused
        )
        .onAppear {
            if store.galleries.isEmpty {
                DispatchQueue.main.async {
                    store.send(.fetchGalleries)
                }
            }
        }
        .toolbar(content: toolbar)
        .navigationTitle(L10n.Localizable.PopularView.Title.popular)

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
    private func toolbar() -> some ToolbarContent {
        CustomToolbarItem {
            FiltersButton(hideText: true) {
                store.send(.setNavigation(.filters()))
            }
        }
    }
}

struct PopularView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PopularView(
                store: .init(initialState: .init(), reducer: PopularReducer.init),
                user: .init(),
                setting: .constant(.init()),
                blurRadius: 0,
                tagTranslator: .init()
            )
        }
    }
}
