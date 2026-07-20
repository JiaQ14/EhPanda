//
//  HomeReducer.swift
//  EhPanda
//

import ComposableArchitecture

@Reducer
struct HomeReducer {
    @CasePathable
    enum Route: Equatable, Hashable {
        case detail(String)
        case section(HomeSectionType)
    }

    @ObservableState
    struct State: Equatable {
        var route: Route?

        var popularGalleries = [Gallery]()
        var popularLoadingState: LoadingState = .idle
        var frontpageGalleries = [Gallery]()
        var frontpageLoadingState: LoadingState = .idle
        var toplistsGalleries = [Int: [Gallery]]()
        var toplistsLoadingState = [Int: LoadingState]()

        var frontpageState = FrontpageReducer.State()
        var toplistsState = ToplistsReducer.State()
        var popularState = PopularReducer.State()
        var watchedState = WatchedReducer.State()
        var historyState = HistoryReducer.State()

        mutating func setPopularGalleries(_ galleries: [Gallery]) {
            let sortedGalleries = galleries.sorted { lhs, rhs in
                lhs.title.count > rhs.title.count
            }
            var trimmedGalleries = Array(sortedGalleries.prefix(min(sortedGalleries.count, 10)))
                .removeDuplicates(by: \.trimmedTitle)
            if trimmedGalleries.count >= 6 {
                trimmedGalleries = Array(trimmedGalleries.prefix(6))
            }
            trimmedGalleries.shuffle()
            popularGalleries = trimmedGalleries
        }

        mutating func setFrontpageGalleries(_ galleries: [Gallery]) {
            frontpageGalleries = Array(galleries.prefix(min(galleries.count, 25)))
                .removeDuplicates(by: \.trimmedTitle)
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case setNavigation(Route?)
        case clearSubStates

        case fetchAllGalleries
        case fetchAllToplistsGalleries
        case fetchPopularGalleries
        case fetchPopularGalleriesDone(Result<[Gallery], AppError>)
        case fetchFrontpageGalleries
        case fetchFrontpageGalleriesDone(Result<(PageNumber, [Gallery]), AppError>)
        case fetchToplistsGalleries(Int, Int? = nil)
        case fetchToplistsGalleriesDone(Int, Result<(PageNumber, [Gallery]), AppError>)

        case frontpage(FrontpageReducer.Action)
        case toplists(ToplistsReducer.Action)
        case popular(PopularReducer.Action)
        case watched(WatchedReducer.Action)
        case history(HistoryReducer.Action)
    }

    @Dependency(\.databaseClient) private var databaseClient

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
                state.frontpageState = .init()
                state.toplistsState = .init()
                state.popularState = .init()
                state.watchedState = .init()
                state.historyState = .init()
                return .merge(
                    .send(.frontpage(.teardown)),
                    .send(.toplists(.teardown)),
                    .send(.popular(.teardown)),
                    .send(.watched(.teardown))
                )

            case .fetchAllGalleries:
                return .merge(
                    .send(.fetchPopularGalleries),
                    .send(.fetchFrontpageGalleries),
                    .send(.fetchAllToplistsGalleries)
                )

            case .fetchAllToplistsGalleries:
                return .merge(
                    ToplistsType.allCases
                        .map { Action.fetchToplistsGalleries($0.categoryIndex) }
                        .map(Effect<Action>.send)
                )

            case .fetchPopularGalleries:
                guard state.popularLoadingState != .loading else { return .none }
                state.popularLoadingState = .loading
                let filter = databaseClient.fetchFilterSynchronously(range: .global)
                return .run { send in
                    let response = await PopularGalleriesRequest(filter: filter).response()
                    await send(.fetchPopularGalleriesDone(response))
                }

            case .fetchPopularGalleriesDone(let result):
                state.popularLoadingState = .idle
                switch result {
                case .success(let galleries):
                    guard !galleries.isEmpty else {
                        state.popularLoadingState = .failed(.notFound)
                        return .none
                    }
                    state.setPopularGalleries(galleries)
                    return .run(operation: { _ in await databaseClient.cacheGalleries(galleries) })
                case .failure(let error):
                    state.popularLoadingState = .failed(error)
                }
                return .none

            case .fetchFrontpageGalleries:
                guard state.frontpageLoadingState != .loading else { return .none }
                state.frontpageLoadingState = .loading
                let filter = databaseClient.fetchFilterSynchronously(range: .global)
                return .run { send in
                    let response = await FrontpageGalleriesRequest(filter: filter).response()
                    await send(.fetchFrontpageGalleriesDone(response))
                }

            case .fetchFrontpageGalleriesDone(let result):
                state.frontpageLoadingState = .idle
                switch result {
                case .success(let (_, galleries)):
                    guard !galleries.isEmpty else {
                        state.frontpageLoadingState = .failed(.notFound)
                        return .none
                    }
                    state.setFrontpageGalleries(galleries)
                    return .run(operation: { _ in await databaseClient.cacheGalleries(galleries) })
                case .failure(let error):
                    state.frontpageLoadingState = .failed(error)
                }
                return .none

            case .fetchToplistsGalleries(let index, let pageNum):
                guard state.toplistsLoadingState[index] != .loading else { return .none }
                state.toplistsLoadingState[index] = .loading
                return .run { send in
                    let response = await ToplistsGalleriesRequest(catIndex: index, pageNum: pageNum).response()
                    await send(.fetchToplistsGalleriesDone(index, response))
                }

            case .fetchToplistsGalleriesDone(let index, let result):
                state.toplistsLoadingState[index] = .idle
                switch result {
                case .success(let (_, galleries)):
                    guard !galleries.isEmpty else {
                        state.toplistsLoadingState[index] = .failed(.notFound)
                        return .none
                    }
                    state.toplistsGalleries[index] = galleries
                    return .run(operation: { _ in await databaseClient.cacheGalleries(galleries) })
                case .failure(let error):
                    state.toplistsLoadingState[index] = .failed(error)
                }
                return .none

            case .frontpage:
                return .none

            case .toplists:
                return .none

            case .popular:
                return .none

            case .watched:
                return .none

            case .history:
                return .none

            }
        }

        Scope(state: \.frontpageState, action: \.frontpage, child: FrontpageReducer.init)
        Scope(state: \.toplistsState, action: \.toplists, child: ToplistsReducer.init)
        Scope(state: \.popularState, action: \.popular, child: PopularReducer.init)
        Scope(state: \.watchedState, action: \.watched, child: WatchedReducer.init)
        Scope(state: \.historyState, action: \.history, child: HistoryReducer.init)
    }
}
