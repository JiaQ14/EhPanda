//
//  ToplistsView.swift
//  EhPanda
//

import SwiftUI
import ComposableArchitecture

struct ToplistsView: View {
    @Bindable private var store: StoreOf<ToplistsReducer>
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator

    init(
        store: StoreOf<ToplistsReducer>,
        user: User, setting: Binding<Setting>, blurRadius: Double, tagTranslator: TagTranslator
    ) {
        self.store = store
        self.user = user
        _setting = setting
        self.blurRadius = blurRadius
        self.tagTranslator = tagTranslator
    }

    private var navigationTitle: String {
        [L10n.Localizable.ToplistsView.Title.toplists, store.type.value].joined(separator: " - ")
    }

    var body: some View {
        let content =
        GenericList(
            galleries: store.filteredGalleries ?? [],
            setting: setting,
            translationRevision: tagTranslator.renderRevision,
            datasetIdentity: store.type,
            pageNumber: store.pageNumber,
            loadingState: store.loadingState ?? .idle,
            footerLoadingState: store.footerLoadingState ?? .idle,
            fetchAction: { store.send(.fetchGalleries()) },
            fetchMoreAction: { store.send(.fetchMoreGalleries) },
            navigateAction: { store.send(.setNavigation(.detail($0))) },
            translateAction: {
                tagTranslator.lookup(word: $0, returnOriginal: !setting.translatesTags)
            }
        )
        .alert(
            L10n.Localizable.JumpPageView.Title.jumpPage,
            isPresented: $store.jumpPageAlertPresented
        ) {
            TextField("1", text: $store.jumpPageIndex)
                .keyboardType(.numberPad)

            Button(
                L10n.Localizable.JumpPageView.Button.confirm,
                role: .confirm
            ) {
                store.send(.performJumpPage)
            }
            .disabled(!store.isJumpPageIndexValid)

            Button(role: .cancel) {}
        } message: {
            Text("1 - \((store.pageNumber?.maximum ?? 0) + 1)")
        }
        .searchable(text: $store.keyword, prompt: L10n.Localizable.Searchable.Prompt.filter)
        .onAppear {
            if store.galleries?.isEmpty != false {
                DispatchQueue.main.async {
                    store.send(.fetchGalleries())
                }
            }
        }
        .background(navigationLink)
        .toolbar(content: toolbar)
        .navigationTitle(navigationTitle)

        if DeviceUtil.isPad {
            content
                .sheet(item: $store.route.sending(\.setNavigation).detail, id: \.self) { route in
                    NavigationStack {
                        DetailView(
                            store: store.scope(state: \.detailState.wrappedValue!, action: \.detail),
                            gid: route.wrappedValue, user: user, setting: $setting,
                            blurRadius: blurRadius, tagTranslator: tagTranslator
                        )
                    }
                    .autoBlur(radius: blurRadius).environment(\.inSheet, true)
                }
        } else {
            content
        }
    }

    @ViewBuilder private var navigationLink: some View {
        if DeviceUtil.isPhone {
            NavigationLink(unwrapping: $store.route, case: \.detail) { route in
                DetailView(
                    store: store.scope(state: \.detailState.wrappedValue!, action: \.detail),
                    gid: route.wrappedValue, user: user, setting: $setting,
                    blurRadius: blurRadius, tagTranslator: tagTranslator
                )
            }
        }
    }
    private func toolbar() -> some ToolbarContent {
        CustomToolbarItem {
            ToplistsTypeMenu(type: store.type) { type in
                if type != store.type {
                    store.send(.setToplistsType(type))
                }
            }
            if AppUtil.galleryHost == .ehentai {
                JumpPageButton(pageNumber: store.pageNumber ?? .init(), hideText: true) {
                    store.send(.presentJumpPageAlert)
                }
            }
        }
    }
}

// MARK: Definition
enum ToplistsType: Int, Codable, CaseIterable, Identifiable {
    var id: Int { rawValue }

    case yesterday
    case pastMonth
    case pastYear
    case allTime
}

extension ToplistsType {
    var value: String {
        switch self {
        case .yesterday:
            return L10n.Localizable.Enum.ToplistsType.Value.yesterday
        case .pastMonth:
            return L10n.Localizable.Enum.ToplistsType.Value.pastMonth
        case .pastYear:
            return L10n.Localizable.Enum.ToplistsType.Value.pastYear
        case .allTime:
            return L10n.Localizable.Enum.ToplistsType.Value.allTime
        }
    }
    var categoryIndex: Int {
        switch self {
        case .yesterday:
            return 15
        case .pastMonth:
            return 13
        case .pastYear:
            return 12
        case .allTime:
            return 11
        }
    }
}

struct ToplistsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ToplistsView(
                store: .init(initialState: .init(), reducer: ToplistsReducer.init),
                user: .init(),
                setting: .constant(.init()),
                blurRadius: 0,
                tagTranslator: .init()
            )
        }
    }
}
