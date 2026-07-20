//
//  FrontpageView.swift
//  EhPanda
//

import SwiftUI
import AlertKit
import ComposableArchitecture

struct FrontpageView: View {
    @Bindable private var store: StoreOf<FrontpageReducer>
    @FocusState private var isSearchFocused: Bool
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator

    init(
        store: StoreOf<FrontpageReducer>,
        user: User, setting: Binding<Setting>, blurRadius: Double, tagTranslator: TagTranslator
    ) {
        self.store = store
        self.user = user
        _setting = setting
        self.blurRadius = blurRadius
        self.tagTranslator = tagTranslator
    }

    var body: some View {
        let content =
        GenericList(
            galleries: store.filteredGalleries,
            setting: setting,
            translationRevision: tagTranslator.renderRevision,
            pageNumber: store.pageNumber,
            loadingState: store.loadingState,
            footerLoadingState: store.footerLoadingState,
            fetchAction: { await store.send(.fetchGalleries).finish() },
            fetchMoreAction: { store.send(.fetchMoreGalleries) },
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
        .navigationTitle(L10n.Localizable.FrontpageView.Title.frontpage)

        content.adaptiveGalleryDetail(
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

struct FrontpageView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FrontpageView(
                store: .init(initialState: .init(), reducer: FrontpageReducer.init),
                user: .init(),
                setting: .constant(.init()),
                blurRadius: 0,
                tagTranslator: .init()
            )
        }
    }
}
