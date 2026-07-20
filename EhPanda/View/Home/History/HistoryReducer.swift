//
//  HistoryReducer.swift
//  EhPanda
//

import Foundation
import ComposableArchitecture

@Reducer
struct HistoryReducer {
    @CasePathable
    enum Route: Equatable {
        case detail(String)
        case clearHistory
    }

    @ObservableState
    struct State: Equatable {
        var route: Route?
        var keyword = ""
        var clearDialogPresented = false

        var filteredGalleries: [Gallery] {
            guard !keyword.isEmpty else { return galleries }
            return galleries.filter {
                GalleryLocalSearchMatcher.matches(
                    gallery: $0,
                    query: keyword
                )
            }
        }
        var galleries = [Gallery]()
        var loadingState: LoadingState = .idle
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case setNavigation(Route?)
        case clearSubStates
        case clearHistoryGalleries

        case fetchGalleries
        case fetchGalleriesDone([Gallery])

    }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.hapticsClient) private var hapticsClient

    var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.route) { _, newValue in
                Reduce({ _, _ in newValue == nil ? .send(.clearSubStates) : .none })
            }

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .setNavigation(let route):
                state.route = route
                return route == nil ? .send(.clearSubStates) : .none

            case .clearSubStates:
                return .none

            case .clearHistoryGalleries:
                state.loadingState = .loading
                return .run { send in
                    await databaseClient.clearHistoryGalleries()
                    let historyGalleries = await databaseClient.fetchHistoryGalleries()
                    await send(.fetchGalleriesDone(historyGalleries))
                }

            case .fetchGalleries:
                guard state.loadingState != .loading else { return .none }
                state.loadingState = .loading
                return .run { send in
                    let historyGalleries = await databaseClient.fetchHistoryGalleries()
                    await send(.fetchGalleriesDone(historyGalleries))
                }

            case .fetchGalleriesDone(let galleries):
                state.galleries = galleries
                if galleries.isEmpty {
                    state.loadingState = .failed(.notFound)
                } else {
                    state.loadingState = .idle
                }
                return .none

            }
        }
    }
}
