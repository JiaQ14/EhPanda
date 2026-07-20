//
//  TabBarView.swift
//  EhPanda
//

import SwiftUI
import UIKit
import Combine
import CoreSpotlight
import ImageIO
import SFSafeSymbols
import ComposableArchitecture

struct AppCommandActions {
    let navigate: (AppNavigationItem) -> Void
    let refresh: () -> Void
}

private struct AppCommandActionsKey: FocusedValueKey {
    typealias Value = AppCommandActions
}

extension FocusedValues {
    var ehPandaCommandActions: AppCommandActions? {
        get { self[AppCommandActionsKey.self] }
        set { self[AppCommandActionsKey.self] = newValue }
    }
}

private struct AppDropDestinationModifier: ViewModifier {
    let urlHandler: ([URL]) -> Bool
    let dataHandler: ([Data]) -> Bool

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                return urlHandler(urls)
            }
            .dropDestination(for: Data.self) { items, _ in
                return dataHandler(items)
            }
    }
}

struct TabBarView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appTabViewCustomization")
    private var tabViewCustomization: TabViewCustomization
    @State private var visualSearchTask: Task<Void, Never>?
    @Bindable private var store: StoreOf<AppReducer>

    init(store: StoreOf<AppReducer>) {
        self.store = store
    }

    var body: some View {
        ZStack {
            tabNavigation
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
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            store.send(.appRoute(.setNavigation(nil)))
                        } label: {
                            Image(systemSymbol: .xmark)
                        }
                    }
                }
            }
            .accentColor(store.settingState.setting.accentColor)
            .gallerySheetPresentation(
                gid: route.wrappedValue,
                blurRadius: store.appLockState.blurRadius,
                onDetached: {
                    store.send(.appRoute(.setNavigation(nil)))
                }
            )
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
        .onReceive(
            NotificationCenter.default.publisher(
                for: AppIntentNavigationStore.didEnqueueNotification
            )
            .receive(on: RunLoop.main)
        ) { _ in
            store.send(.consumePendingIntentRoute)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let galleryID = GalleryEntity.galleryID(fromSpotlightIdentifier: identifier)
            else { return }
            store.send(.handleIntentRoute(.gallery(gid: galleryID, readingProgress: nil)))
        }
        .onOpenURL { store.send(.appRoute(.handleDeepLink($0))) }
        .modifier(
            AppDropDestinationModifier(
                urlHandler: handleDroppedURLs,
                dataHandler: handleDroppedImageData
            )
        )
        .focusedSceneValue(
            \.ehPandaCommandActions,
            AppCommandActions(
                navigate: { item in
                    store.send(.navigateToSection(item))
                },
                refresh: {
                    store.send(.tabBar(.setTabBarItemType(store.tabBarState.tabBarItemType)))
                }
            )
        )
        .onDisappear {
            visualSearchTask?.cancel()
            visualSearchTask = nil
        }
    }

    @ViewBuilder
    private var tabNavigation: some View {
        if DeviceUtil.isPad {
            iPadTabView
                .tabViewStyle(.sidebarAdaptable)
                .tabViewCustomization($tabViewCustomization)
                .defaultAdaptableTabBarPlacement(.tabBar)
                .background(TabSidebarLayoutConfigurator())
        } else {
            phoneTabView
        }
    }

    private var phoneTabView: some View {
        TabView(selection: tabSelection) {
            ForEach(phoneTabItems) { type in
                navigationTab(type)
            }
        }
    }

    private var iPadTabView: some View {
        TabView(selection: tabSelection) {
            ForEach(AppNavigationItem.iPadItems) { type in
                navigationTab(type)
                    .customizationID(type.customizationID)
                    .customizationBehavior(
                        type.nativeCustomizationBehavior,
                        for: .sidebar,
                        .tabBar
                    )
                    .defaultVisibility(
                        defaultTabBarVisibility(for: type),
                        for: .tabBar
                    )
            }
        }
    }

    private func navigationTab(_ type: AppNavigationItem) -> some TabContent<AppNavigationItem> {
        Tab(value: type, role: type == .search ? .search : nil) {
            AppNavigationContent(
                store: store,
                item: type,
                embedsInNavigationStack: true
            )
        } label: {
            type.label()
        }
    }

    private var tabSelection: Binding<AppNavigationItem> {
        .init(
            get: { store.tabBarState.tabBarItemType },
            set: { store.send(.tabBar(.setTabBarItemType($0))) }
        )
    }

    private var phoneTabItems: [AppNavigationItem] {
        [.home] + store.settingState.setting.tabBarItems + [.more]
    }

    private func defaultTabBarVisibility(for type: AppNavigationItem) -> Visibility {
        if type == .home || type == .setting
            || store.settingState.setting.tabBarItems.contains(type) {
            return .visible
        }
        return .hidden
    }

    private func handleDroppedURLs(_ urls: [URL]) -> Bool {
        for url in urls {
            let resolvedURL = URLClient.live.resolveAppSchemeURL(url) ?? url
            if URLClient.live.checkIfHandleable(resolvedURL) {
                store.send(.appRoute(.handleDeepLink(resolvedURL)))
                return true
            }
        }

        guard store.settingState.setting.enablesVisualSearch, !urls.isEmpty else {
            return false
        }
        store.send(.appRoute(.setNavigation(.hud)))
        visualSearchTask?.cancel()
        visualSearchTask = Task {
            for url in urls {
                guard !Task.isCancelled else { return }
                guard let data = await GalleryVisualSearchImageLoader.data(
                    from: url,
                    session: .shared
                ), let image = Self.image(from: data) else { continue }
                await completeVisualSearch(image)
                return
            }
            guard !Task.isCancelled else { return }
            store.send(.appRoute(.setNavigation(nil)))
        }
        return true
    }

    private func handleDroppedImageData(_ items: [Data]) -> Bool {
        guard store.settingState.setting.enablesVisualSearch,
              let image = items.lazy.compactMap(Self.image(from:)).first
        else { return false }
        store.send(.appRoute(.setNavigation(.hud)))
        visualSearchTask?.cancel()
        visualSearchTask = Task { await completeVisualSearch(image) }
        return true
    }

    private func completeVisualSearch(_ image: CGImage) async {
        let output = await GalleryVisualSearchService.shared.search(image: image)
        guard !Task.isCancelled else { return }
        store.send(.appRoute(.setNavigation(nil)))
        store.send(.handleIntentRoute(output.navigationRoute))
    }

    private static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

private struct TabSidebarLayoutConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> ResolverView {
        ResolverView()
    }

    func updateUIView(_ uiView: ResolverView, context: Context) {
        uiView.applyPreferredLayout()
    }

    final class ResolverView: UIView {
        private weak var tabBarController: UITabBarController?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyPreferredLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyPreferredLayout()
        }

        func applyPreferredLayout() {
            if let tabBarController {
                configure(tabBarController)
                return
            }

            var responder: UIResponder? = self
            while let nextResponder = responder?.next {
                if let tabBarController = nextResponder as? UITabBarController {
                    configure(tabBarController)
                    return
                }
                responder = nextResponder
            }

            DispatchQueue.main.async { [weak self] in
                guard let rootViewController = self?.window?.rootViewController,
                      let tabBarController = rootViewController.descendantTabBarController
                else {
                    return
                }
                self?.configure(tabBarController)
            }
        }

        private func configure(_ tabBarController: UITabBarController) {
            self.tabBarController = tabBarController
            if tabBarController.sidebar.preferredLayout != .overlap {
                tabBarController.sidebar.preferredLayout = .overlap
                tabBarController.view.setNeedsLayout()
            }
        }
    }
}

private extension UIViewController {
    var descendantTabBarController: UITabBarController? {
        if let tabBarController = self as? UITabBarController {
            return tabBarController
        }
        for child in children {
            if let tabBarController = child.descendantTabBarController {
                return tabBarController
            }
        }
        return presentedViewController?.descendantTabBarController
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
            PopularView(
                store: store.scope(state: \.homeState.popularState, action: \.home.popular),
                user: store.settingState.user,
                setting: $store.settingState.setting,
                blurRadius: store.appLockState.blurRadius,
                tagTranslator: store.settingState.tagTranslator,
                embedsInNavigationStack: embedsInNavigationStack
            )
        case .watched:
            WatchedView(
                store: store.scope(state: \.homeState.watchedState, action: \.home.watched),
                user: store.settingState.user,
                setting: $store.settingState.setting,
                blurRadius: store.appLockState.blurRadius,
                tagTranslator: store.settingState.tagTranslator,
                embedsInNavigationStack: embedsInNavigationStack
            )
        case .history:
            HistoryView(
                store: store.scope(state: \.homeState.historyState, action: \.home.history),
                user: store.settingState.user,
                setting: $store.settingState.setting,
                blurRadius: store.appLockState.blurRadius,
                tagTranslator: store.settingState.tagTranslator,
                embedsInNavigationStack: embedsInNavigationStack
            )
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
                    move: FullTabBarMove(
                        movedItem: sourceRow.item,
                        displacedItem: displacedItem,
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        finalTabBarItems: draft.tabBarItems,
                        finalMoreItems: draft.moreItems
                    )
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
            move: FullTabBarMove
        ) {
            var intermediateTabBarItems = tabBarItems
            var intermediateMoreItems = moreItems
            intermediateMoreItems.remove(at: move.sourceIndex)
            intermediateTabBarItems.insert(
                move.movedItem,
                at: min(
                    max(move.destinationIndex, 0),
                    intermediateTabBarItems.count
                )
            )
            tabBarItems = intermediateTabBarItems
            moreItems = intermediateMoreItems
            guard let displacedSourceIndex =
                    intermediateTabBarItems.firstIndex(of: move.displacedItem),
                  let displacedDestinationIndex =
                    move.finalMoreItems.firstIndex(of: move.displacedItem)
            else {
                DispatchQueue.main.async { [weak self, weak tableView] in
                    guard let self, let tableView else { return }
                    self.tabBarItems = move.finalTabBarItems
                    self.moreItems = move.finalMoreItems
                    self.parent.tabBarItems = move.finalTabBarItems
                    self.parent.moreItems = move.finalMoreItems
                    tableView.reloadData()
                }
                return
            }

            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                self.tabBarItems = move.finalTabBarItems
                self.moreItems = move.finalMoreItems
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
                self.parent.tabBarItems = move.finalTabBarItems
                self.parent.moreItems = move.finalMoreItems
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

private struct FullTabBarMove {
    let movedItem: AppNavigationItem
    let displacedItem: AppNavigationItem
    let sourceIndex: Int
    let destinationIndex: Int
    let finalTabBarItems: [AppNavigationItem]
    let finalMoreItems: [AppNavigationItem]
}

extension AppNavigationItem {
    static let iPadItems: [Self] = [
        .home, .setting, .popular, .watched, .history, .favorites, .cache, .search
    ]

    var customizationID: String {
        "app.ehpanda.tab.\(rawValue)"
    }

    var nativeCustomizationBehavior: TabCustomizationBehavior {
        switch self {
        case .home, .search:
            return .disabled
        default:
            return .automatic
        }
    }

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
