//
//  TabBarView.swift
//  EhPanda
//

import SwiftUI
import SFSafeSymbols
import ComposableArchitecture

struct TabBarView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var store: StoreOf<AppReducer>

    init(store: StoreOf<AppReducer>) {
        self.store = store
    }

    var body: some View {
        ZStack {
            TabView(
                selection: .init(
                    get: { store.tabBarState.tabBarItemType },
                    set: { store.send(.tabBar(.setTabBarItemType($0))) }
                )
            ) {
                ForEach(visibleTabItems) { type in
                    Tab(value: type) {
                        AppNavigationContent(
                            store: store,
                            item: type,
                            embedsInNavigationStack: true
                        )
                    } label: {
                        type.label()
                    }
                }
            }
            .accentColor(store.settingState.setting.accentColor)
            .autoBlur(radius: store.appLockState.blurRadius)
            Button {
                store.send(.appLock(.authorize))
            } label: {
                Image(systemSymbol: .lockFill)
            }
            .font(.system(size: 80)).opacity(store.appLockState.isAppLocked ? 1 : 0)
        }
        .sheet(item: $store.appRouteState.route.sending(\.appRoute.setNavigation).newDawn) { greeting in
            NewDawnView(greeting: greeting)
                .autoBlur(radius: store.appLockState.blurRadius)
        }
        .sheet(item: $store.appRouteState.route.sending(\.appRoute.setNavigation).setting) { _ in
            SettingView(
                store: store.scope(state: \.settingState, action: \.setting),
                blurRadius: store.appLockState.blurRadius
            )
            .accentColor(store.settingState.setting.accentColor)
            .autoBlur(radius: store.appLockState.blurRadius)
        }
        .sheet(item: $store.appRouteState.route.sending(\.appRoute.setNavigation).detail, id: \.self) { route in
            NavigationStack {
                DetailView(
                    store: store.scope(
                        state: \.appRouteState.detailState.wrappedValue!,
                        action: \.appRoute.detail
                    ),
                    gid: route.wrappedValue, user: store.settingState.user,
                    setting: $store.settingState.setting,
                    blurRadius: store.appLockState.blurRadius,
                    tagTranslator: store.settingState.tagTranslator
                )
            }
            .accentColor(store.settingState.setting.accentColor)
            .autoBlur(radius: store.appLockState.blurRadius)
            .environment(\.inSheet, true)
        }
        .progressHUD(
            config: store.appRouteState.hudConfig,
            unwrapping: $store.appRouteState.route,
            case: \.hud
        )
        .onChange(of: scenePhase) { _, newValue in store.send(.onScenePhaseChange(newValue)) }
        .onOpenURL { store.send(.appRoute(.handleDeepLink($0))) }
    }

    private var visibleTabItems: [AppNavigationItem] {
        [.home] + store.settingState.setting.tabBarItems + [.more]
    }
}

private struct AppNavigationContent: View {
    @Bindable private var store: StoreOf<AppReducer>
    private let item: AppNavigationItem
    private let embedsInNavigationStack: Bool

    init(
        store: StoreOf<AppReducer>,
        item: AppNavigationItem,
        embedsInNavigationStack: Bool
    ) {
        self.store = store
        self.item = item
        self.embedsInNavigationStack = embedsInNavigationStack
    }

    @ViewBuilder var body: some View {
        switch item {
        case .home:
            HomeView(
                store: store.scope(state: \.homeState, action: \.home),
                user: store.settingState.user,
                setting: $store.settingState.setting,
                blurRadius: store.appLockState.blurRadius,
                tagTranslator: store.settingState.tagTranslator
            )
        case .popular:
            navigationContainer {
                PopularView(
                    store: store.scope(state: \.homeState.popularState, action: \.home.popular),
                    user: store.settingState.user,
                    setting: $store.settingState.setting,
                    blurRadius: store.appLockState.blurRadius,
                    tagTranslator: store.settingState.tagTranslator
                )
            }
        case .watched:
            navigationContainer {
                WatchedView(
                    store: store.scope(state: \.homeState.watchedState, action: \.home.watched),
                    user: store.settingState.user,
                    setting: $store.settingState.setting,
                    blurRadius: store.appLockState.blurRadius,
                    tagTranslator: store.settingState.tagTranslator
                )
            }
        case .history:
            navigationContainer {
                HistoryView(
                    store: store.scope(state: \.homeState.historyState, action: \.home.history),
                    user: store.settingState.user,
                    setting: $store.settingState.setting,
                    blurRadius: store.appLockState.blurRadius,
                    tagTranslator: store.settingState.tagTranslator
                )
            }
        case .favorites:
            FavoritesView(
                store: store.scope(state: \.favoritesState, action: \.favorites),
                user: store.settingState.user,
                setting: $store.settingState.setting,
                blurRadius: store.appLockState.blurRadius,
                tagTranslator: store.settingState.tagTranslator,
                embedsInNavigationStack: embedsInNavigationStack
            )
        case .cache:
            CacheView(
                store: store.scope(state: \.cacheState, action: \.cache),
                user: store.settingState.user,
                setting: $store.settingState.setting,
                blurRadius: store.appLockState.blurRadius,
                tagTranslator: store.settingState.tagTranslator,
                embedsInNavigationStack: embedsInNavigationStack
            )
        case .search:
            SearchRootView(
                store: store.scope(state: \.searchRootState, action: \.searchRoot),
                user: store.settingState.user,
                setting: $store.settingState.setting,
                blurRadius: store.appLockState.blurRadius,
                tagTranslator: store.settingState.tagTranslator,
                embedsInNavigationStack: embedsInNavigationStack
            )
        case .setting:
            SettingView(
                store: store.scope(state: \.settingState, action: \.setting),
                blurRadius: store.appLockState.blurRadius,
                embedsInNavigationStack: embedsInNavigationStack
            )
        case .more:
            MoreView(store: store)
        }
    }

    @ViewBuilder
    private func navigationContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if embedsInNavigationStack {
            NavigationStack {
                content()
            }
        } else {
            content()
        }
    }
}

private struct MoreView: View {
    @Bindable private var store: StoreOf<AppReducer>
    @State private var editMode: EditMode = .inactive

    init(store: StoreOf<AppReducer>) {
        self.store = store
    }

    private var tabBarItems: [AppNavigationItem] {
        store.settingState.setting.tabBarItems
    }

    private var moreItems: [AppNavigationItem] {
        store.settingState.setting.moreItems
    }

    var body: some View {
        NavigationStack {
            List {
                if editMode.isEditing {
                    editorSections
                } else {
                    destinationRows
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(AppNavigationItem.more.title)
            .navigationDestination(
                item: moreRoute,
                destination: destination
            )
            .toolbar {
                EditButton()
            }
        }
        .environment(\.editMode, $editMode)
    }

    private var moreRoute: Binding<AppNavigationItem?> {
        .init(
            get: { store.moreState.route },
            set: { store.send(.more(.setNavigation($0))) }
        )
    }

    private var destinationRows: some View {
        ForEach(moreItems) { item in
            Button {
                store.send(.more(.setNavigation(item)))
            } label: {
                NavigationItemRow(item: item, showsDisclosureIndicator: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var editorSections: some View {
        Section(L10n.Localizable.MoreView.Section.Title.tabBar) {
            fixedEditorRow(.home)
                .dropDestination(for: String.self) { values, _ in
                    return move(values, to: .tabBar, at: 0)
                }

            ForEach(Array(tabBarItems.enumerated()), id: \.element) { index, item in
                draggableEditorRow(
                    item,
                    group: .tabBar,
                    index: index
                )
            }
            .onMove {
                store.send(.moveNavigationItems(.tabBar, $0, $1))
            }

            fixedEditorRow(.more)
                .dropDestination(for: String.self) { values, _ in
                    return move(values, to: .tabBar, at: tabBarItems.count)
                }
        }

        Section(L10n.Localizable.MoreView.Section.Title.more) {
            ForEach(Array(moreItems.enumerated()), id: \.element) { index, item in
                draggableEditorRow(
                    item,
                    group: .more,
                    index: index
                )
            }
            .onMove {
                store.send(.moveNavigationItems(.more, $0, $1))
            }
        }
    }

    private func fixedEditorRow(_ item: AppNavigationItem) -> some View {
        NavigationItemRow(item: item, isFixed: true)
            .moveDisabled(true)
    }

    private func draggableEditorRow(
        _ item: AppNavigationItem,
        group: NavigationItemGroup,
        index: Int
    ) -> some View {
        NavigationItemRow(item: item)
            .draggable(item.rawValue)
            .dropDestination(for: String.self) { values, location in
                let insertsAfterRow = location.y > 22
                return move(
                    values,
                    to: group,
                    at: index + (insertsAfterRow ? 1 : 0)
                )
            }
    }

    private func move(
        _ values: [String],
        to group: NavigationItemGroup,
        at index: Int
    ) -> Bool {
        guard let rawValue = values.first,
              let item = AppNavigationItem(rawValue: rawValue)
        else { return false }
        store.send(.moveNavigationItem(item, group, index))
        return true
    }

    @ViewBuilder
    private func destination(_ item: AppNavigationItem) -> some View {
        AppNavigationContent(
            store: store,
            item: item,
            embedsInNavigationStack: false
        )
    }
}

private struct NavigationItemRow: View {
    private let item: AppNavigationItem
    private let isFixed: Bool
    private let showsDisclosureIndicator: Bool

    init(
        item: AppNavigationItem,
        isFixed: Bool = false,
        showsDisclosureIndicator: Bool = false
    ) {
        self.item = item
        self.isFixed = isFixed
        self.showsDisclosureIndicator = showsDisclosureIndicator
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemSymbol: item.symbol)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.tintColor)
                .frame(width: 28)

            Text(item.title)
                .foregroundStyle(.primary)

            Spacer()

            if isFixed {
                Image(systemSymbol: .lockFill)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if showsDisclosureIndicator {
                Image(systemSymbol: .chevronForward)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
    }
}

extension AppNavigationItem {
    var title: String {
        switch self {
        case .home:
            return L10n.Localizable.TabItem.Title.home
        case .popular:
            return L10n.Localizable.Enum.HomeMiscGridType.Title.popular
        case .watched:
            return L10n.Localizable.Enum.HomeMiscGridType.Title.watched
        case .history:
            return L10n.Localizable.Enum.HomeMiscGridType.Title.history
        case .favorites:
            return L10n.Localizable.TabItem.Title.favorites
        case .cache:
            return L10n.Localizable.TabItem.Title.cache
        case .search:
            return L10n.Localizable.TabItem.Title.search
        case .setting:
            return L10n.Localizable.TabItem.Title.setting
        case .more:
            return L10n.Localizable.TabItem.Title.more
        }
    }
    var symbol: SFSymbol {
        switch self {
        case .home:
            return .house
        case .popular:
            return .flame
        case .watched:
            return .tagCircle
        case .history:
            return .clockArrowCirclepath
        case .favorites:
            return .heart
        case .cache:
            return .squareAndArrowDown
        case .search:
            return .magnifyingglass
        case .setting:
            return .gearshape
        case .more:
            return .ellipsisCircle
        }
    }

    var tintColor: Color {
        switch self {
        case .home, .search, .more:
            return .accentColor
        case .popular:
            return .orange
        case .watched:
            return .blue
        case .history:
            return .teal
        case .favorites:
            return .pink
        case .cache:
            return .cyan
        case .setting:
            return .gray
        }
    }

    func label() -> Label<Text, Image> {
        Label(title, systemSymbol: symbol)
    }
}

struct TabBarView_Previews: PreviewProvider {
    static var previews: some View {
        TabBarView(store: .init(initialState: .init(), reducer: AppReducer.init))
    }
}
