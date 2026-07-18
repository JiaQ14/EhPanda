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
        .environment(
            \.galleryContextMenuConfiguration,
            .standard(
                user: store.settingState.user,
                setting: store.settingState.setting,
                blurRadius: store.appLockState.blurRadius,
                tagTranslator: store.settingState.tagTranslator
            )
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
    @State private var isEditing = false
    @State private var draftTabItems = [AppNavigationItem]()
    @State private var draftMoreItems = [AppNavigationItem]()

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
                if isEditing {
                    editorSections
                } else {
                    destinationRows
                    settingRow
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(AppNavigationItem.more.title)
            .navigationDestination(
                item: moreRoute,
                destination: destination
            )
            .toolbar {
                Button {
                    withAnimation {
                        if isEditing {
                            store.send(
                                .setNavigationItems(
                                    draftTabItems,
                                    draftMoreItems
                                )
                            )
                        } else {
                            draftTabItems = tabBarItems
                            draftMoreItems = moreItems
                        }
                        isEditing.toggle()
                    }
                } label: {
                    Label(
                        isEditing ? "Done" : "Edit",
                        systemSymbol: isEditing ? .checkmark : .pencil
                    )
                    .labelStyle(.iconOnly)
                }
            }
        }
        .environment(
            \.editMode,
            .constant(isEditing ? .active : .inactive)
        )
    }

    private var moreRoute: Binding<AppNavigationItem?> {
        .init(
            get: { store.moreState.route },
            set: { store.send(.more(.setNavigation($0))) }
        )
    }

    @ViewBuilder private var destinationRows: some View {
        Section(L10n.Localizable.MoreView.Section.Title.more) {
            ForEach(moreItems) { item in
                destinationRow(item)
            }
        }
    }

    private var settingRow: some View {
        Section {
            destinationRow(.setting)
        }
    }

    @ViewBuilder private var editorSections: some View {
        Section {
            ForEach(editorEntries) { entry in
                switch entry {
                case .header(let group):
                    editorHeader(group)
                        .moveDisabled(true)
                case .fixed(let item):
                    fixedEditorRow(item)
                        .moveDisabled(true)
                case .item(let item):
                    NavigationItemRow(item: item)
                        .moveDisabled(false)
                }
            }
            .onMove(perform: moveEditorRows)
        }
    }

    private func destinationRow(_ item: AppNavigationItem) -> some View {
        Button {
            store.send(.more(.setNavigation(item)))
        } label: {
            NavigationItemRow(item: item, showsDisclosureIndicator: true)
        }
        .buttonStyle(.plain)
    }

    private func fixedEditorRow(_ item: AppNavigationItem) -> some View {
        NavigationItemRow(item: item, isFixed: true)
    }

    private func editorHeader(_ group: NavigationItemGroup) -> some View {
        Text(
            group == .tabBar
                ? L10n.Localizable.MoreView.Section.Title.tabBar
                : L10n.Localizable.MoreView.Section.Title.more
        )
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var editorEntries: [NavigationEditorEntry] {
        [.header(.tabBar), .fixed(.home)]
            + draftTabItems.map(NavigationEditorEntry.item)
            + [.fixed(.more), .header(.more)]
            + draftMoreItems.map(NavigationEditorEntry.item)
    }

    private func moveEditorRows(
        from source: IndexSet,
        to destination: Int
    ) {
        guard source.count == 1,
              let sourceIndex = source.first,
              editorEntries.indices.contains(sourceIndex),
              case .item(let item) = editorEntries[sourceIndex]
        else { return }

        var reorderedEntries = editorEntries
        reorderedEntries.move(fromOffsets: source, toOffset: destination)
        guard let itemIndex = reorderedEntries.firstIndex(of: .item(item)),
              let boundaryIndex = reorderedEntries.firstIndex(of: .fixed(.more))
        else { return }

        let destinationGroup: NavigationItemGroup =
            itemIndex < boundaryIndex ? .tabBar : .more
        let destinationRange =
            destinationGroup == .tabBar
            ? reorderedEntries[..<itemIndex]
            : reorderedEntries[(boundaryIndex + 1)..<itemIndex]
        let finalDestinationIndex = destinationRange.reduce(into: 0) { count, entry in
            if case .item = entry {
                count += 1
            }
        }

        var draft = Setting()
        draft.tabBarItems = draftTabItems
        draft.moreItems = draftMoreItems
        let sourceGroup: NavigationItemGroup =
            draftTabItems.contains(item) ? .tabBar : .more
        let sourceItems =
            sourceGroup == .tabBar ? draftTabItems : draftMoreItems
        let sourceIndexInGroup = sourceItems.firstIndex(of: item)
        let rawDestinationIndex =
            sourceGroup == destinationGroup
            && (sourceIndexInGroup ?? .max) < finalDestinationIndex
            ? finalDestinationIndex + 1
            : finalDestinationIndex
        guard draft.moveNavigationItem(
            item,
            to: destinationGroup,
            at: rawDestinationIndex
        ) else { return }

        withAnimation(.snappy(duration: 0.2)) {
            draftTabItems = draft.tabBarItems
            draftMoreItems = draft.moreItems
        }
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

private enum NavigationEditorEntry: Hashable, Identifiable {
    case header(NavigationItemGroup)
    case fixed(AppNavigationItem)
    case item(AppNavigationItem)

    var id: String {
        switch self {
        case .header(let group):
            return "header-\(group)"
        case .fixed(let item):
            return "fixed-\(item.rawValue)"
        case .item(let item):
            return "item-\(item.rawValue)"
        }
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
