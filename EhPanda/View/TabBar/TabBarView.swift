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
                .tabViewCustomization(sidebarCustomization)
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
                    .tabPlacement(type == .setting ? .sidebarOnly : .automatic)
                    .customizationBehavior(.disabled, for: .sidebar)
                    .customizationBehavior(type == .setting ? .disabled : .automatic, for: .tabBar)
                    .defaultVisibility(.visible, for: .sidebar)
                    .defaultVisibility(type.defaultTabBarVisibility, for: .tabBar)
            }
        }
    }

    private func navigationTab(_ type: AppNavigationItem) -> some TabContent<AppNavigationItem> {
        // Search is an ordinary destination and follows the user's tab order.
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

    private var tabSelection: Binding<AppNavigationItem> {
        .init(
            get: { store.tabBarState.tabBarItemType },
            set: { store.send(.tabBar(.setTabBarItemType($0))) }
        )
    }

    private var phoneTabItems: [AppNavigationItem] {
        store.settingState.setting.phoneTabItems
    }

    private var sidebarCustomization: Binding<TabViewCustomization> {
        .init(
            get: { tabViewCustomization.preservingFullNavigationSidebar() },
            set: { tabViewCustomization = $0.preservingFullNavigationSidebar() }
        )
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
                tagTranslator: store.settingState.tagTranslator,
                embedsInNavigationStack: embedsInNavigationStack
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
    @State private var showsEditor = false

    init(store: StoreOf<AppReducer>) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AppNavigationItem.configurableItems) { item in
                        destinationButton(item)
                    }
                }
                Section {
                    destinationButton(.setting)
                }
            }
            .navigationTitle(AppNavigationItem.more.title)
            .navigationDestination(
                item: $store.moreState.route.sending(\.more.setNavigation)
            ) { item in
                AppNavigationContent(store: store, item: item, embedsInNavigationStack: false)
            }
            .toolbar {
                Button {
                    showsEditor = true
                } label: {
                    Label(L10n.Localizable.MoreView.Section.Title.tabBar, systemSymbol: .sliderHorizontal3)
                }
                .accessibilityIdentifier("navigation.edit")
            }
        }
        .sheet(isPresented: $showsEditor) {
            NavigationItemsEditor(tabBarItems: store.settingState.setting.tabBarItems) {
                store.send(.setNavigationItems($0))
            }
            .accentColor(store.settingState.setting.accentColor)
            .autoBlur(radius: store.appLockState.blurRadius)
        }
    }

    private func destinationButton(_ item: AppNavigationItem) -> some View {
        Button {
            store.send(.navigateToSection(item))
        } label: {
            HStack {
                item.label()
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemSymbol: .chevronRight)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityIdentifier("navigation.destination.\(item.rawValue)")
    }
}

struct NavigationItemsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Setting
    @State private var pendingItem: AppNavigationItem?
    private let onSave: ([AppNavigationItem]) -> Void

    init(tabBarItems: [AppNavigationItem], onSave: @escaping ([AppNavigationItem]) -> Void) {
        var draft = Setting()
        draft.tabBarItems = tabBarItems
        draft.normalizeNavigationItems()
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            NavigationItemsEditorList(draft: $draft, pendingItem: $pendingItem)
                .navigationTitle(L10n.Localizable.MoreView.Section.Title.tabBar)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Localizable.NavigationEditor.Button.cancel) { dismiss() }
                            .accessibilityIdentifier("navigation.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.Localizable.EhSettingView.ToolbarItem.Button.done) {
                            onSave(draft.tabBarItems)
                            dismiss()
                        }
                        .accessibilityIdentifier("navigation.save")
                    }
                }
                .confirmationDialog(
                    L10n.Localizable.NavigationEditor.Replace.title(pendingItem?.title ?? ""),
                    isPresented: .init(
                        get: { pendingItem != nil },
                        set: { if !$0 { pendingItem = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: pendingItem
                ) { item in
                    ForEach(draft.tabBarItems) { replacedItem in
                        Button(replacedItem.title) {
                            draft.addNavigationItem(item, replacing: replacedItem)
                            pendingItem = nil
                        }
                    }
                }
        }
    }
}

struct NavigationItemsEditorList: View {
    @Binding var draft: Setting
    @Binding var pendingItem: AppNavigationItem?

    var body: some View {
        List {
            Section(L10n.Localizable.NavigationEditor.Section.favorites) {
                ForEach($draft.tabBarItems, editActions: [.delete, .move]) { $item in
                    item.label()
                        .accessibilityIdentifier("navigation.pinned.\(item.rawValue)")
                }
            }
            Section {
                HStack {
                    AppNavigationItem.more.label()
                    Spacer()
                    Image(systemSymbol: .lockFill)
                        .foregroundStyle(.secondary)
                }
            }
            Section(L10n.Localizable.NavigationEditor.Section.available) {
                ForEach(draft.availableTabItems) { item in
                    Button {
                        if !draft.addNavigationItem(item) {
                            pendingItem = item
                        }
                    } label: {
                        HStack {
                            Image(systemSymbol: .plusCircleFill)
                                .foregroundStyle(.green)
                            item.label()
                                .foregroundStyle(.primary)
                        }
                    }
                    .accessibilityIdentifier("navigation.add.\(item.rawValue)")
                }
            }
            Section {
                Button {
                    draft.tabBarItems = AppNavigationItem.defaultTabItems
                } label: {
                    Label(L10n.Localizable.NavigationEditor.Button.reset, systemSymbol: .arrowCounterclockwise)
                }
                .accessibilityIdentifier("navigation.reset")
            }
        }
        .environment(\.editMode, .constant(.active))
        // Inserted native cells can miss edit mode. Refresh on membership changes,
        // but keep the list identity stable throughout a reorder gesture.
        .id(Set(draft.tabBarItems))
    }
}

extension TabViewCustomization {
    func preservingFullNavigationSidebar() -> Self {
        var customization = self
        // Older versions allowed hiding destinations from the sidebar as well.
        for item in AppNavigationItem.iPadItems {
            customization[tab: item.customizationID].sidebarVisibility = .visible
        }
        return customization
    }
}

extension AppNavigationItem {
    static let iPadItems: [Self] = [
        .home, .search, .popular, .watched, .history, .favorites, .cache, .setting
    ]

    var customizationID: String {
        "app.ehpanda.tab.\(rawValue)"
    }

    var defaultTabBarVisibility: Visibility {
        Self.defaultTabItems.contains(self) ? .visible : .hidden
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
            return .squareGrid2x2
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
