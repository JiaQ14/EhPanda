//
//  HistoryView.swift
//  EhPanda
//

import SwiftUI
import ComposableArchitecture

struct HistoryView: View {
    @Bindable private var store: StoreOf<HistoryReducer>
    @FocusState private var isSearchFocused: Bool
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator
    private let embedsInNavigationStack: Bool

    init(
        store: StoreOf<HistoryReducer>,
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
        .navigationTitle(L10n.Localizable.HistoryView.Title.history)

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
            Button {
                store.send(.setNavigation(.clearHistory))
            } label: {
                Image(systemSymbol: .trashCircle)
            }
            .disabled(store.loadingState != .idle || store.galleries.isEmpty)
            .confirmationDialog(
                message: L10n.Localizable.ConfirmationDialog.Title.clear,
                unwrapping: $store.route,
                case: \.clearHistory
            ) {
                Button(L10n.Localizable.ConfirmationDialog.Button.clear, role: .destructive) {
                    store.send(.clearHistoryGalleries)
                }
            }
        }
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            HistoryView(
                store: .init(initialState: .init(), reducer: HistoryReducer.init),
                user: .init(),
                setting: .constant(.init()),
                blurRadius: 0,
                tagTranslator: .init()
            )
        }
    }
}
