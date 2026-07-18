//
//  TabBarView.swift
//  EhPanda
//

import SwiftUI
import UIKit
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
            NavigationItemsTable(
                tabBarItems: tableTabBarItems,
                moreItems: tableMoreItems,
                isEditing: isEditing,
                accentColor: store.settingState.setting.accentColor,
                selectionAction: {
                    store.send(.more(.setNavigation($0)))
                }
            )
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(AppNavigationItem.more.title)
            .navigationDestination(
                item: moreRoute,
                destination: destination
            )
            .toolbar {
                Button {
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
                } label: {
                    Label(
                        isEditing ? "Done" : "Edit",
                        systemSymbol: isEditing ? .checkmark : .pencil
                    )
                    .labelStyle(.iconOnly)
                }
            }
        }
        .background(
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
        )
    }

    private var moreRoute: Binding<AppNavigationItem?> {
        .init(
            get: { store.moreState.route },
            set: { store.send(.more(.setNavigation($0))) }
        )
    }

    private var tableTabBarItems: Binding<[AppNavigationItem]> {
        .init(
            get: {
                isEditing ? draftTabItems : tabBarItems
            },
            set: {
                guard isEditing else { return }
                draftTabItems = $0
            }
        )
    }

    private var tableMoreItems: Binding<[AppNavigationItem]> {
        .init(
            get: {
                isEditing ? draftMoreItems : moreItems
            },
            set: {
                guard isEditing else { return }
                draftMoreItems = $0
            }
        )
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

private struct NavigationItemsTable: UIViewRepresentable {
    @Binding var tabBarItems: [AppNavigationItem]
    @Binding var moreItems: [AppNavigationItem]
    let isEditing: Bool
    let accentColor: Color
    let selectionAction: (AppNavigationItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(
            frame: .zero,
            style: .insetGrouped
        )
        tableView.register(
            UITableViewCell.self,
            forCellReuseIdentifier: Coordinator.cellReuseIdentifier
        )
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.isEditing = isEditing
        tableView.allowsSelectionDuringEditing = false
        tableView.keyboardDismissMode = .interactive
        tableView.backgroundColor = .systemGroupedBackground
        let backgroundView = UIView()
        backgroundView.backgroundColor = .systemGroupedBackground
        tableView.backgroundView = backgroundView
        tableView.sectionHeaderTopPadding = 12
        return tableView
    }

    func updateUIView(_ tableView: UITableView, context: Context) {
        let coordinator = context.coordinator
        let itemsChanged =
            coordinator.tabBarItems != tabBarItems
            || coordinator.moreItems != moreItems
        let modeChanged = coordinator.isEditing != isEditing
        let resolvedAccentColor = UIColor(accentColor)
        let accentColorChanged =
            !coordinator.accentColor.isEqual(resolvedAccentColor)
        coordinator.parent = self
        coordinator.tabBarItems = tabBarItems
        coordinator.moreItems = moreItems
        coordinator.isEditing = isEditing
        coordinator.accentColor = resolvedAccentColor
        tableView.allowsSelection = !isEditing
        if modeChanged {
            tableView.setEditing(isEditing, animated: false)
            tableView.reloadData()
        } else if itemsChanged {
            tableView.reloadData()
        } else if accentColorChanged {
            tableView.visibleCells.forEach {
                guard let indexPath = tableView.indexPath(for: $0) else { return }
                coordinator.configure($0, at: indexPath)
            }
        }
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        static let cellReuseIdentifier = "NavigationEditorCell"

        var parent: NavigationItemsTable
        var tabBarItems: [AppNavigationItem]
        var moreItems: [AppNavigationItem]
        var isEditing: Bool
        var accentColor: UIColor

        init(parent: NavigationItemsTable) {
            self.parent = parent
            tabBarItems = parent.tabBarItems
            moreItems = parent.moreItems
            isEditing = parent.isEditing
            accentColor = UIColor(parent.accentColor)
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            2
        }

        func tableView(
            _ tableView: UITableView,
            numberOfRowsInSection section: Int
        ) -> Int {
            if isEditing {
                return section == 0 ? tabBarItems.count + 2 : moreItems.count
            }
            return section == 0 ? moreItems.count : 1
        }

        func tableView(
            _ tableView: UITableView,
            titleForHeaderInSection section: Int
        ) -> String? {
            guard isEditing else {
                return section == 0
                    ? L10n.Localizable.MoreView.Section.Title.more
                    : nil
            }
            return section == 0
                ? L10n.Localizable.MoreView.Section.Title.tabBar
                : L10n.Localizable.MoreView.Section.Title.more
        }

        func tableView(
            _ tableView: UITableView,
            cellForRowAt indexPath: IndexPath
        ) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: Self.cellReuseIdentifier,
                for: indexPath
            )
            configure(cell, at: indexPath)
            return cell
        }

        func configure(_ cell: UITableViewCell, at indexPath: IndexPath) {
            guard let row = row(at: indexPath) else { return }
            var content = cell.defaultContentConfiguration()
            content.text = row.item.title
            content.image = UIImage(
                systemSymbol: row.item.symbol,
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 17,
                    weight: .semibold
                )
            )
            content.imageProperties.tintColor = tintColor(for: row.item)
            content.imageProperties.maximumSize = CGSize(width: 28, height: 28)
            cell.contentConfiguration = content
            cell.backgroundColor = .secondarySystemGroupedBackground
            cell.selectionStyle = isEditing ? .none : .default
            cell.showsReorderControl = isEditing && !row.isFixed
            cell.accessoryView =
                isEditing && row.isFixed ? lockAccessoryView() : nil
            cell.accessoryType =
                isEditing ? .none : .disclosureIndicator
        }

        func tableView(
            _ tableView: UITableView,
            canMoveRowAt indexPath: IndexPath
        ) -> Bool {
            isEditing && row(at: indexPath)?.isFixed == false
        }

        func tableView(
            _ tableView: UITableView,
            editingStyleForRowAt indexPath: IndexPath
        ) -> UITableViewCell.EditingStyle {
            .none
        }

        func tableView(
            _ tableView: UITableView,
            shouldIndentWhileEditingRowAt indexPath: IndexPath
        ) -> Bool {
            false
        }

        func tableView(
            _ tableView: UITableView,
            targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
            toProposedIndexPath proposedDestinationIndexPath: IndexPath
        ) -> IndexPath {
            if proposedDestinationIndexPath.section == 0 {
                return IndexPath(
                    row: min(
                        max(proposedDestinationIndexPath.row, 1),
                        tabBarItems.count + 1
                    ),
                    section: 0
                )
            }
            return IndexPath(
                row: min(
                    max(proposedDestinationIndexPath.row, 0),
                    moreItems.count
                ),
                section: 1
            )
        }

        func tableView(
            _ tableView: UITableView,
            moveRowAt sourceIndexPath: IndexPath,
            to destinationIndexPath: IndexPath
        ) {
            guard let sourceRow = row(at: sourceIndexPath),
                  !sourceRow.isFixed
            else {
                tableView.reloadData()
                return
            }

            let destinationGroup: NavigationItemGroup =
                destinationIndexPath.section == 0 ? .tabBar : .more
            let destinationIndex =
                destinationGroup == .tabBar
                ? max(destinationIndexPath.row - 1, 0)
                : destinationIndexPath.row
            let sourceGroup: NavigationItemGroup =
                sourceIndexPath.section == 0 ? .tabBar : .more
            let sourceIndex =
                sourceGroup == .tabBar
                ? sourceIndexPath.row - 1
                : sourceIndexPath.row

            var draft = Setting()
            draft.tabBarItems = tabBarItems
            draft.moreItems = moreItems
            guard draft.moveNavigationItem(
                from: sourceGroup,
                at: sourceIndex,
                to: destinationGroup,
                at: destinationIndex
            ) else {
                tableView.reloadData()
                return
            }

            if sourceGroup == .more,
               destinationGroup == .tabBar,
               tabBarItems.count >= Setting.maximumConfigurableTabCount,
               let displacedItem = tabBarItems.last
            {
                completeFullTabBarMove(
                    in: tableView,
                    movedItem: sourceRow.item,
                    displacedItem: displacedItem,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    finalTabBarItems: draft.tabBarItems,
                    finalMoreItems: draft.moreItems
                )
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }

            tabBarItems = draft.tabBarItems
            moreItems = draft.moreItems
            parent.tabBarItems = draft.tabBarItems
            parent.moreItems = draft.moreItems
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        func tableView(
            _ tableView: UITableView,
            didSelectRowAt indexPath: IndexPath
        ) {
            guard !isEditing, let row = row(at: indexPath) else { return }
            tableView.deselectRow(at: indexPath, animated: true)
            parent.selectionAction(row.item)
        }

        private func completeFullTabBarMove(
            in tableView: UITableView,
            movedItem: AppNavigationItem,
            displacedItem: AppNavigationItem,
            sourceIndex: Int,
            destinationIndex: Int,
            finalTabBarItems: [AppNavigationItem],
            finalMoreItems: [AppNavigationItem]
        ) {
            var intermediateTabBarItems = tabBarItems
            var intermediateMoreItems = moreItems
            intermediateMoreItems.remove(at: sourceIndex)
            intermediateTabBarItems.insert(
                movedItem,
                at: min(
                    max(destinationIndex, 0),
                    intermediateTabBarItems.count
                )
            )
            tabBarItems = intermediateTabBarItems
            moreItems = intermediateMoreItems
            guard let displacedSourceIndex =
                    intermediateTabBarItems.firstIndex(of: displacedItem),
                  let displacedDestinationIndex =
                    finalMoreItems.firstIndex(of: displacedItem)
            else {
                DispatchQueue.main.async { [weak self, weak tableView] in
                    guard let self, let tableView else { return }
                    self.tabBarItems = finalTabBarItems
                    self.moreItems = finalMoreItems
                    self.parent.tabBarItems = finalTabBarItems
                    self.parent.moreItems = finalMoreItems
                    tableView.reloadData()
                }
                return
            }

            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                self.tabBarItems = finalTabBarItems
                self.moreItems = finalMoreItems
                tableView.performBatchUpdates {
                    tableView.moveRow(
                        at: IndexPath(
                            row: displacedSourceIndex + 1,
                            section: 0
                        ),
                        to: IndexPath(
                            row: displacedDestinationIndex,
                            section: 1
                        )
                    )
                }
                self.parent.tabBarItems = finalTabBarItems
                self.parent.moreItems = finalMoreItems
            }
        }

        private func row(at indexPath: IndexPath) -> NavigationEditorRow? {
            guard isEditing else {
                if indexPath.section == 0,
                   moreItems.indices.contains(indexPath.row)
                {
                    return .init(
                        item: moreItems[indexPath.row],
                        isFixed: false
                    )
                }
                if indexPath.section == 1, indexPath.row == 0 {
                    return .init(item: .setting, isFixed: false)
                }
                return nil
            }
            if indexPath.section == 0 {
                if indexPath.row == 0 {
                    return .init(item: .home, isFixed: true)
                }
                if indexPath.row == tabBarItems.count + 1 {
                    return .init(item: .more, isFixed: true)
                }
                let itemIndex = indexPath.row - 1
                guard tabBarItems.indices.contains(itemIndex) else { return nil }
                return .init(item: tabBarItems[itemIndex], isFixed: false)
            }
            guard indexPath.section == 1,
                  moreItems.indices.contains(indexPath.row)
            else { return nil }
            return .init(item: moreItems[indexPath.row], isFixed: false)
        }

        private func tintColor(for item: AppNavigationItem) -> UIColor {
            switch item {
            case .home, .search, .more:
                return accentColor
            case .popular:
                return .systemOrange
            case .watched:
                return .systemBlue
            case .history:
                return .systemTeal
            case .favorites:
                return .systemPink
            case .cache:
                return .systemCyan
            case .setting:
                return .systemGray
            }
        }

        private func lockAccessoryView() -> UIImageView {
            let imageView = UIImageView(
                image: UIImage(
                    systemSymbol: .lockFill,
                    withConfiguration: UIImage.SymbolConfiguration(
                        pointSize: 11,
                        weight: .semibold
                    )
                )
            )
            imageView.tintColor = .tertiaryLabel
            return imageView
        }
    }
}

private struct NavigationEditorRow {
    let item: AppNavigationItem
    let isFixed: Bool
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
