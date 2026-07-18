//
//  TabBarReducer.swift
//  EhPanda
//

import ComposableArchitecture

@Reducer
struct TabBarReducer {
    @ObservableState
    struct State: Equatable {
        var tabBarItemType: AppNavigationItem = .home
    }

    enum Action: Equatable {
        case setTabBarItemType(AppNavigationItem)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setTabBarItemType(let type):
                state.tabBarItemType = type
                return .none
            }
        }
    }
}

@Reducer
struct MoreReducer {
    @ObservableState
    struct State: Equatable {
        var route: AppNavigationItem?
    }

    enum Action: Equatable {
        case setNavigation(AppNavigationItem?)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setNavigation(let route):
                state.route = route
                return .none
            }
        }
    }
}
