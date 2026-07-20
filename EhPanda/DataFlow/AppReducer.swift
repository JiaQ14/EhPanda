//
//  AppReducer.swift
//  EhPanda
//

import SwiftUI
import ComposableArchitecture

@Reducer
struct AppReducer {
    private enum CancelID {
        case systemSearchIndex
    }

    @ObservableState
    struct State: Equatable {
        var appDelegateState = AppDelegateReducer.State()
        var appRouteState = AppRouteReducer.State()
        var appLockState = AppLockReducer.State()
        var tabBarState = TabBarReducer.State()
        var moreState = MoreReducer.State()
        var homeState = HomeReducer.State()
        var favoritesState = FavoritesReducer.State()
        var cacheState = CacheReducer.State()
        var searchRootState = SearchRootReducer.State()
        var settingState = SettingReducer.State()

        mutating func prepareLoginNavigation(isLoggedIn: Bool) {
            settingState.route = .account
            settingState.accountSettingState.route = isLoggedIn ? nil : .login()
        }

        mutating func navigateToSection(_ item: AppNavigationItem) {
            moreState.route = nil
            if item == .home || settingState.setting.tabBarItems.contains(item) {
                tabBarState.tabBarItemType = item
            } else {
                moreState.route = item
                tabBarState.tabBarItemType = .more
            }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onScenePhaseChange(ScenePhase)
        case consumePendingIntentRoute
        case handleIntentRoute(AppIntentRoute)
        case syncSystemSearchIndex

        case appDelegate(AppDelegateReducer.Action)
        case appRoute(AppRouteReducer.Action)
        case appLock(AppLockReducer.Action)

        case tabBar(TabBarReducer.Action)
        case more(MoreReducer.Action)
        case setNavigationItems([AppNavigationItem], [AppNavigationItem])

        case home(HomeReducer.Action)
        case favorites(FavoritesReducer.Action)
        case cache(CacheReducer.Action)
        case searchRoot(SearchRootReducer.Action)
        case setting(SettingReducer.Action)
    }

    @Dependency(\.hapticsClient) private var hapticsClient
    @Dependency(\.cookieClient) private var cookieClient
    @Dependency(\.deviceClient) private var deviceClient

    var body: some Reducer<State, Action> {
        LoggingReducer {
            BindingReducer()
                .onChange(of: \.appRouteState.route) { _, newValue in
                    Reduce({ _, _ in newValue == nil ? .send(.appRoute(.clearSubStates)) : .none })
                }
                .onChange(of: \.settingState.setting) { oldValue, newValue in
                    Reduce { _, _ in
                        var effects: [Effect<Action>] = [
                            .send(.setting(.syncSetting)),
                            .run { _ in AppIntentPreferences.update(using: newValue) }
                        ]
                        if oldValue.enablesSystemContentSearch
                            != newValue.enablesSystemContentSearch
                            || oldValue.displaysCoversInSystemSearch
                            != newValue.displaysCoversInSystemSearch {
                            effects.append(.send(.syncSystemSearchIndex))
                        }
                        return .merge(effects)
                    }
                }

            Reduce { state, action in
                switch action {
                case .binding:
                    return .none

                case .onScenePhaseChange(let scenePhase):
                    guard state.settingState.hasLoadedInitialSetting else { return .none }

                    switch scenePhase {
                    case .active:
                        let threshold = state.settingState.setting.autoLockPolicy.rawValue
                        let blurRadius = state.settingState.setting.backgroundBlurRadius
                        return .merge(
                            .send(.appLock(.onBecomeActive(threshold, blurRadius))),
                            .send(.consumePendingIntentRoute),
                            .send(.syncSystemSearchIndex)
                        )

                    case .inactive:
                        let blurRadius = state.settingState.setting.backgroundBlurRadius
                        return .send(.appLock(.onBecomeInactive(blurRadius)))

                    default:
                        return .none
                    }

                case .consumePendingIntentRoute:
                    guard state.settingState.hasLoadedInitialSetting else { return .none }
                    return .run { send in
                        if let route = AppIntentNavigationStore.shared.consume() {
                            await send(.handleIntentRoute(route))
                        }
                    }

                case .handleIntentRoute(let route):
                    switch route {
                    case .section(let section):
                        state.navigateToSection(section.navigationItem)
                        return .none

                    case .search(let query):
                        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !query.isEmpty else { return .none }
                        state.navigateToSection(.search)
                        state.searchRootState.keyword = query
                        state.searchRootState.route = .search
                        return .send(.searchRoot(.search(.fetchGalleries(query))))

                    case .gallery(let gid, let readingProgress):
                        return .send(.appRoute(.openGallery(gid, readingProgress)))
                    }

                case .syncSystemSearchIndex:
                    let setting = state.settingState.setting
                    return .run { _ in
                        try await Task.sleep(for: .milliseconds(500))
                        await SystemSearchIndexService.shared.synchronize(using: setting)
                    }
                    .cancellable(id: CancelID.systemSearchIndex, cancelInFlight: true)

                case .appDelegate(.migration(.onDatabasePreparationSuccess)):
                    return .merge(
                        .send(.appDelegate(.removeExpiredImageURLs)),
                        .send(.setting(.loadUserSettings))
                    )

                case .appDelegate:
                    return .none

                case .appRoute(.clearSubStates):
                    var effects = [Effect<Action>]()
                    if deviceClient.isPad() {
                        state.settingState.route = nil
                        effects.append(.send(.setting(.clearSubStates)))
                    }
                    return effects.isEmpty ? .none : .merge(effects)

                case .appRoute(.detail(.saveGalleryHistory)):
                    return .send(.syncSystemSearchIndex)

                case .appRoute:
                    return .none

                case .appLock(.unlockApp):
                    var effects: [Effect<Action>] = [
                        .send(.setting(.fetchGreeting))
                    ]
                    if state.settingState.setting.detectsLinksFromClipboard {
                        effects.append(.send(.appRoute(.detectClipboardURL)))
                    }
                    return .merge(effects)

                case .appLock:
                    return .none

                case .setNavigationItems(let tabBarItems, let moreItems):
                    state.settingState.setting.tabBarItems = tabBarItems
                    state.settingState.setting.moreItems = moreItems
                    state.settingState.setting.normalizeNavigationItems()
                    if !state.settingState.setting.tabBarItems.contains(
                        state.tabBarState.tabBarItemType
                    ), ![.home, .more].contains(state.tabBarState.tabBarItemType) {
                        state.tabBarState.tabBarItemType = .more
                    }
                    return .merge(
                        .send(.setting(.syncSetting)),
                        .run { _ in hapticsClient.generateFeedback(.soft) }
                    )

                case .tabBar(.setTabBarItemType(let type)):
                    var effects = [Effect<Action>]()
                    let hapticEffect: Effect<Action> = .run(operation: { _ in hapticsClient.generateFeedback(.soft) })
                    if type == state.tabBarState.tabBarItemType {
                        switch type {
                        case .home:
                            if state.homeState.route != nil {
                                effects.append(.send(.home(.setNavigation(nil))))
                            } else {
                                effects.append(.send(.home(.fetchAllGalleries)))
                            }
                        case .popular:
                            if state.homeState.popularState.route != nil {
                                effects.append(.send(.home(.popular(.setNavigation(nil)))))
                            } else {
                                effects.append(.send(.home(.popular(.fetchGalleries))))
                            }
                        case .watched:
                            if state.homeState.watchedState.route != nil {
                                effects.append(.send(.home(.watched(.setNavigation(nil)))))
                            } else if cookieClient.didLogin {
                                effects.append(.send(.home(.watched(.fetchGalleries()))))
                            }
                        case .history:
                            if state.homeState.historyState.route != nil {
                                effects.append(.send(.home(.history(.setNavigation(nil)))))
                            } else {
                                effects.append(.send(.home(.history(.fetchGalleries))))
                            }
                        case .favorites:
                            if state.favoritesState.route != nil {
                                effects.append(.send(.favorites(.setNavigation(nil))))
                            } else if cookieClient.didLogin {
                                effects.append(.send(.favorites(.fetchGalleries())))
                            }
                        case .cache:
                            if state.cacheState.route != nil {
                                effects.append(.send(.cache(.setNavigation(nil))))
                            }
                        case .search:
                            if state.searchRootState.route != nil {
                                effects.append(.send(.searchRoot(.setNavigation(nil))))
                            } else {
                                effects.append(.send(.searchRoot(.fetchDatabaseInfos)))
                            }
                        case .setting:
                            if state.settingState.route != nil {
                                effects.append(.send(.setting(.setNavigation(nil))))
                            }
                        case .more:
                            if state.moreState.route != nil {
                                effects.append(.send(.more(.setNavigation(nil))))
                            }
                        }
                        effects.append(hapticEffect)
                    }
                    return effects.isEmpty ? .none : .merge(effects)

                case .tabBar:
                    return .none

                case .more:
                    return .none

                case .home(.watched(.onNotLoginViewButtonTapped)), .favorites(.onNotLoginViewButtonTapped):
                    let isLoggedIn = cookieClient.didLogin
                    state.prepareLoginNavigation(isLoggedIn: isLoggedIn)
                    state.moreState.route = .setting
                    state.tabBarState.tabBarItemType = .more
                    return .run(operation: { _ in hapticsClient.generateFeedback(.soft) })

                case .home:
                    return .none

                case .favorites:
                    return .none

                case .cache(.itemsUpdated):
                    return .send(.syncSystemSearchIndex)

                case .cache:
                    return .none

                case .searchRoot:
                    return .none

                case .setting(.loadUserSettingsDone):
                    var effects = [Effect<Action>]()
                    let threshold = state.settingState.setting.autoLockPolicy.rawValue
                    let blurRadius = state.settingState.setting.backgroundBlurRadius
                    if threshold >= 0 {
                        state.appLockState.becameInactiveDate = .distantPast
                        effects.append(.send(.appLock(.onBecomeActive(threshold, blurRadius))))
                    }
                    if state.settingState.setting.detectsLinksFromClipboard {
                        effects.append(.send(.appRoute(.detectClipboardURL)))
                    }
                    effects.append(.send(.cache(.onAppear(
                        .init(setting: state.settingState.setting),
                        resumesAutomatically: state.settingState.setting.cacheResumesAutomatically
                    ))))
                    effects.append(.send(.consumePendingIntentRoute))
                    effects.append(.send(.syncSystemSearchIndex))
                    effects.append(
                        .run { [setting = state.settingState.setting] _ in
                            AppIntentPreferences.update(using: setting)
                        }
                    )
                    return effects.isEmpty ? .none : .merge(effects)

                case .setting(.fetchGreetingDone(let result)):
                    return .send(.appRoute(.fetchGreetingDone(result)))

                case .setting:
                    return .none
                }
            }

            Scope(state: \.appRouteState, action: \.appRoute, child: AppRouteReducer.init)
            Scope(state: \.appLockState, action: \.appLock, child: AppLockReducer.init)
            Scope(state: \.appDelegateState, action: \.appDelegate, child: AppDelegateReducer.init)
            Scope(state: \.tabBarState, action: \.tabBar, child: TabBarReducer.init)
            Scope(state: \.moreState, action: \.more, child: MoreReducer.init)
            Scope(state: \.homeState, action: \.home, child: HomeReducer.init)
            Scope(state: \.favoritesState, action: \.favorites, child: FavoritesReducer.init)
            Scope(state: \.cacheState, action: \.cache, child: CacheReducer.init)
            Scope(state: \.searchRootState, action: \.searchRoot, child: SearchRootReducer.init)
            Scope(state: \.settingState, action: \.setting, child: SettingReducer.init)
        }
    }
}
