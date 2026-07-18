//
//  AppReducer.swift
//  EhPanda
//

import SwiftUI
import ComposableArchitecture

@Reducer
struct AppReducer {
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
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onScenePhaseChange(ScenePhase)

        case appDelegate(AppDelegateReducer.Action)
        case appRoute(AppRouteReducer.Action)
        case appLock(AppLockReducer.Action)

        case tabBar(TabBarReducer.Action)
        case more(MoreReducer.Action)
        case moveNavigationItem(AppNavigationItem, NavigationItemGroup, Int)
        case moveNavigationItems(NavigationItemGroup, IndexSet, Int)

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
                .onChange(of: \.settingState.setting) { _, _ in
                    Reduce({ _, _ in .send(.setting(.syncSetting)) })
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
                        return .send(.appLock(.onBecomeActive(threshold, blurRadius)))

                    case .inactive:
                        let blurRadius = state.settingState.setting.backgroundBlurRadius
                        return .send(.appLock(.onBecomeInactive(blurRadius)))

                    default:
                        return .none
                    }

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

                case .moveNavigationItem(let item, let destination, let index):
                    let didMove = state.settingState.setting.moveNavigationItem(
                        item, to: destination, at: index
                    )
                    guard didMove else {
                        return .run { _ in
                            hapticsClient.generateNotificationFeedback(.warning)
                        }
                    }
                    if destination == .more,
                       state.tabBarState.tabBarItemType == item {
                        state.tabBarState.tabBarItemType = .more
                    }
                    return .merge(
                        .send(.setting(.syncSetting)),
                        .run { _ in hapticsClient.generateFeedback(.soft) }
                    )

                case .moveNavigationItems(let group, let source, let destination):
                    state.settingState.setting.moveNavigationItems(
                        in: group, from: source, to: destination
                    )
                    return .send(.setting(.syncSetting))

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
                    if state.settingState.setting.tabBarItems.contains(.setting) {
                        state.tabBarState.tabBarItemType = .setting
                    } else {
                        state.moreState.route = .setting
                        state.tabBarState.tabBarItemType = .more
                    }
                    return .run(operation: { _ in hapticsClient.generateFeedback(.soft) })

                case .home:
                    return .none

                case .favorites:
                    return .none

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
